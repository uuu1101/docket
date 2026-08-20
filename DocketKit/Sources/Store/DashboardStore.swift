//  DashboardStore.swift
//  DocketKit

import Foundation
import Observation
import SwiftData

@MainActor
@Observable
public final class DashboardStore {
    public enum ConnectionState: Equatable, Sendable {
        case notConfigured
        case ok
        case failed(String)

        public var isFailed: Bool {
            if case .failed = self { return true }
            return false
        }
    }

    public private(set) var tickets: [Ticket] = []
    public private(set) var isSyncing = false
    public private(set) var lastSyncedAt: Date?
    public private(set) var jiraState: ConnectionState = .notConfigured
    public private(set) var slackState: ConnectionState = .notConfigured

    private let settings: AppSettings
    /// Owned, not just referenced: `ModelContext` does not keep its container alive, and
    /// using a context whose container has been deallocated traps inside SwiftData.
    private let container: ModelContainer
    private let context: ModelContext
    private var refreshTask: Task<Void, Never>?
    private var autoRefreshTask: Task<Void, Never>?
    private var slackAPI: LiveSlackAPI?
    /// Resolved once per launch rather than persisted, so adding the field in Jira takes
    /// effect on the next start instead of never.
    private var targetEndFieldID: String?

    public init(settings: AppSettings, container: ModelContainer) {
        self.settings = settings
        self.container = container
        context = container.mainContext
        removeThreadsLeftOverFromSearch()
        reloadFromStore()
    }

    // MARK: - Reading

    public func ticket(withKey key: String?) -> Ticket? {
        guard let key else { return nil }
        return tickets.first { $0.key == key }
    }

    public var totalUnreadReplyCount: Int {
        tickets.reduce(0) { $0 + $1.unreadReplyCount }
    }

    /// How many tickets have something the user has not looked at. Drives the menu bar mark.
    public var ticketsNeedingAttention: Int {
        tickets.count(where: \.needsAttention)
    }

    private func reloadFromStore() {
        let descriptor = FetchDescriptor<Ticket>()
        let stored = (try? context.fetch(descriptor)) ?? []
        tickets = stored.sorted(by: Self.isOrderedBefore)
    }

    /// Finished work sinks; everything else races its target end date, and equal dates are
    /// broken by priority. A ticket with no date cannot be imminent, so it sorts after the
    /// ones that have one.
    static func isOrderedBefore(_ lhs: Ticket, _ rhs: Ticket) -> Bool {
        let lhsDone = lhs.statusCategory == .done
        let rhsDone = rhs.statusCategory == .done
        if lhsDone != rhsDone { return rhsDone }

        switch (lhs.targetEndDate, rhs.targetEndDate) {
        case let (left?, right?) where left != right:
            return left < right
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        default:
            break
        }

        if lhs.priorityRank != rhs.priorityRank { return lhs.priorityRank < rhs.priorityRank }
        return lhs.updatedAt > rhs.updatedAt
    }

    // MARK: - Status

    /// Fetched when a ticket is opened rather than on every refresh: the list depends on the
    /// issue and would cost one request per ticket per tick.
    public func availableTransitions(for ticket: Ticket) async -> [JiraTransition] {
        guard let configuration = settings.jiraConfiguration else { return [] }
        let found = try? await LiveJiraAPI(configuration: configuration).transitions(issueKey: ticket.key)
        return found ?? []
    }

    /// Moves the ticket, then reflects the new status without waiting for a refresh.
    public func apply(_ transition: JiraTransition, to ticket: Ticket) async -> JiraError? {
        guard let configuration = settings.jiraConfiguration else { return .notConfigured }

        do {
            try await LiveJiraAPI(configuration: configuration)
                .performTransition(issueKey: ticket.key, transitionID: transition.id)
        } catch {
            Log.jira.error("transition \(transition.id, privacy: .public) on \(ticket.key, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            return error
        }

        ticket.statusName = transition.toStatusName
        ticket.statusCategory = transition.toStatusCategory
        // The user did this; flagging it as something they have not seen would be absurd.
        ticket.seenStatusName = transition.toStatusName
        save()
        reloadFromStore()
        return nil
    }

    /// How many comments a detail view shows. Tickets in a fifteen-issue sample held at most
    /// thirteen comments in total, so this is the whole conversation for almost every ticket.
    public static let commentLimit = 10

    /// Read when a ticket is opened and kept in view state only. Persisting them would add a
    /// column, a staleness problem and unread bookkeeping, for content that is read at the
    /// moment it is fetched.
    public func comments(for ticket: Ticket) async -> JiraComments? {
        guard let configuration = settings.jiraConfiguration else { return nil }
        return try? await LiveJiraAPI(configuration: configuration)
            .comments(issueKey: ticket.key, limit: Self.commentLimit)
    }

    // MARK: - Threads

    /// Attaches the thread a pasted Slack link points at. Without a Slack connection the
    /// link still attaches, as a card that knows nothing beyond the link itself.
    public func addThread(link: String, to ticket: Ticket) async -> SlackError? {
        guard let permalink = SlackPermalink(text: link) else { return .api("invalid_link") }
        guard settings.isSlackConfigured, let slack = slackClient() else {
            attachLinkOnlyThread(permalink, origin: .manual, to: ticket)
            save()
            return nil
        }

        let engine = SyncEngine(
            jira: LiveJiraAPI(configuration: settings.jiraConfiguration ?? .placeholder),
            slack: slack
        )

        do {
            guard let snapshot = try await engine.thread(
                issueKey: ticket.key,
                channelID: permalink.channelID,
                threadTS: permalink.threadTS,
                permalink: permalink.threadURL,
                knownChannelName: nil,
                origin: .manual
            ) else { return .api("thread_not_found") }

            upsert(snapshot, into: ticket)
            save()
            return nil
        } catch {
            return error
        }
    }

    /// A pasted thread is gone for good. One found in the Jira description is only hidden:
    /// the link is still in Jira, so deleting it outright would just invite it back.
    public func removeThread(_ thread: SlackThread) {
        switch thread.origin {
        case .manual:
            context.delete(thread)
        case .jira:
            thread.isHidden = true
        }
        save()
    }

    public func setFigmaURL(_ link: String, for ticket: Ticket) -> Bool {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), DescriptionLinks.isFigma(url) else { return false }
        ticket.chosenFigmaURLString = url.absoluteString
        save()
        return true
    }

    /// Drops the user's link so the one detected in Jira takes over again.
    public func clearChosenFigmaURL(for ticket: Ticket) {
        ticket.chosenFigmaURLString = nil
        save()
    }

    /// Called when a ticket's detail is on screen. Opening the popover is not enough: a
    /// mark that clears itself before the user reads anything is worse than none.
    public func markSeen(_ ticket: Ticket) {
        guard ticket.seenStatusName != ticket.statusName else { return }
        ticket.seenStatusName = ticket.statusName
        save()
    }

    public func markSeen(_ thread: SlackThread) {
        guard thread.seenReplyCount != thread.replyCount else { return }
        thread.seenReplyCount = thread.replyCount
        save()
    }

    // MARK: - Refresh

    public func refresh(force: Bool) {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            await self?.performRefresh(force: force)
        }
    }

    public func startAutoRefresh() {
        autoRefreshTask?.cancel()
        let minutes = settings.refreshMinutes
        autoRefreshTask = Task { [weak self] in
            while Task.isCancelled.not {
                await self?.performRefresh(force: false)
                try? await Task.sleep(for: .seconds(Double(minutes) * 60))
            }
        }
    }

    public func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
        refreshTask?.cancel()
        refreshTask = nil
    }

    private func performRefresh(force _: Bool) async {
        guard isSyncing.not else { return }
        guard let configuration = settings.jiraConfiguration else {
            jiraState = .notConfigured
            return
        }

        isSyncing = true
        defer { isSyncing = false }

        let engine = SyncEngine(jira: LiveJiraAPI(configuration: configuration), slack: slackClient())

        // Jira and Slack fail independently: a broken Slack token must not blank the
        // ticket list, and vice versa. Neither failure clears the cache.
        if targetEndFieldID == nil {
            targetEndFieldID = await engine.resolveTargetEndFieldID()
        }

        do {
            let issues = try await engine.issues(jql: settings.jql, targetEndFieldID: targetEndFieldID)
            apply(issues)
            jiraState = .ok
        } catch {
            jiraState = .failed(settings.strings.jiraErrorMessage(error))
        }

        guard Task.isCancelled.not else { return }

        await refreshPullRequests()

        guard Task.isCancelled.not else { return }

        if settings.isSlackConfigured {
            await attachThreadsFoundInJira(using: engine)
            await refreshThreads(using: engine)
        } else {
            attachLinkOnlyThreadsFoundInJira()
            slackState = .notConfigured
        }

        lastSyncedAt = Date()
        save()
    }

    /// Lists each repository's recent pull requests once, then matches every ticket against
    /// that one list. Optional information: a failure leaves the previous links in place
    /// rather than surfacing an error over the ticket list.
    private func refreshPullRequests() async {
        guard let configuration = settings.githubConfiguration else { return }
        let github = LiveGitHubAPI(configuration: configuration)

        var pullRequests: [GitHubPullRequest] = []
        for repository in configuration.repositories {
            guard Task.isCancelled.not else { return }
            do {
                pullRequests += try await github.recentPullRequests(repository: repository)
            } catch {
                Log.github.error("listing \(repository, privacy: .public) failed: \(String(describing: error), privacy: .public)")
                if error == .rateLimited || error == .unauthorized { return }
            }
        }

        guard pullRequests.isEmpty.not else { return }
        for ticket in tickets {
            ticket.pullRequests = PullRequestMatcher.links(for: ticket.key, in: pullRequests)
        }
        save()
    }

    /// Attaches Slack links written into the Jira description. A thread already attached —
    /// or hidden by the user — is left alone.
    private func attachThreadsFoundInJira(using engine: SyncEngine) async {
        for ticket in tickets {
            for permalink in ticket.pendingJiraThreadLinks {
                guard Task.isCancelled.not else { return }
                let id = SyncEngine.snapshotID(
                    issueKey: ticket.key,
                    channelID: permalink.channelID,
                    threadTS: permalink.threadTS
                )
                guard ticket.threads.contains(where: { $0.id == id }).not else { continue }

                guard let snapshot = try? await engine.thread(
                    issueKey: ticket.key,
                    channelID: permalink.channelID,
                    threadTS: permalink.threadTS,
                    permalink: permalink.threadURL,
                    knownChannelName: nil,
                    origin: .jira
                ) else { continue }
                upsert(snapshot, into: ticket)
            }
        }
        save()
    }

    /// The same links, attached without a token: each card keeps the link and nothing
    /// else. Connecting Slack later needs no migration — the next refresh finds these by
    /// id and fills them in through `upsert`.
    private func attachLinkOnlyThreadsFoundInJira() {
        for ticket in tickets {
            for permalink in ticket.pendingJiraThreadLinks {
                attachLinkOnlyThread(permalink, origin: .jira, to: ticket)
            }
        }
        save()
    }

    private func attachLinkOnlyThread(_ permalink: SlackPermalink, origin: ThreadOrigin, to ticket: Ticket) {
        let id = SyncEngine.snapshotID(
            issueKey: ticket.key,
            channelID: permalink.channelID,
            threadTS: permalink.threadTS
        )
        guard ticket.threads.contains(where: { $0.id == id }).not else { return }

        let thread = SlackThread(
            id: id,
            channelID: permalink.channelID,
            // The id doubles as the unresolved-name marker, the same convention the fetch
            // path uses, so hydration knows to look the real name up.
            channelName: permalink.channelID,
            threadTS: permalink.threadTS,
            permalinkString: permalink.threadURL.absoluteString,
            rootAuthorName: "",
            rootText: "",
            replyCount: 0,
            participantNames: [],
            // The permalink carries the root message's timestamp, which sorts truthfully
            // where "now" would not.
            lastActivityAt: Double(permalink.threadTS).map { Date(timeIntervalSince1970: $0) } ?? Date(),
            lastReplyAuthorName: nil,
            origin: origin
        )
        context.insert(thread)
        thread.ticket = ticket
    }

    /// Attached threads are never discovered on their own, so each is refreshed by id to
    /// keep its reply count and last activity current.
    private func refreshThreads(using engine: SyncEngine) async {
        var didRefreshAny = false
        var lastFailure: SlackError?

        for ticket in tickets {
            for thread in ticket.threads {
                guard Task.isCancelled.not else { return }
                guard let permalink = thread.permalink else { continue }
                do {
                    guard let snapshot = try await engine.thread(
                        issueKey: ticket.key,
                        channelID: thread.channelID,
                        threadTS: thread.threadTS,
                        permalink: permalink,
                        knownChannelName: thread.channelName,
                        origin: thread.origin
                    ) else { continue }
                    upsert(snapshot, into: ticket)
                    didRefreshAny = true
                } catch {
                    lastFailure = error
                    // About the client rather than this thread: stop before burning quota.
                    if case .rateLimited = error { return }
                    if case .invalidAuth = error { return }
                    if case .refreshFailed = error { return }
                }
            }
            ticket.slackSyncedAt = Date()
        }

        if let lastFailure, didRefreshAny.not {
            slackState = .failed(settings.strings.slackErrorMessage(lastFailure))
        } else {
            slackState = .ok
        }
    }

    private func slackClient() -> LiveSlackAPI? {
        guard settings.isSlackConfigured else {
            slackAPI = nil
            return nil
        }
        // Reused across refreshes so the rate limiter and the name cache survive. The token
        // itself is fetched per call, so a renewal needs no new client.
        if let slackAPI { return slackAPI }
        let client = LiveSlackAPI(tokenStore: SlackTokenStore(settings: settings))
        slackAPI = client
        return client
    }

    // MARK: - Persistence

    func apply(_ issues: [JiraIssue]) {
        var existing = Dictionary(tickets.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })

        for issue in issues {
            if let ticket = existing.removeValue(forKey: issue.key) {
                ticket.summary = issue.summary
                ticket.statusName = issue.statusName
                ticket.statusCategory = issue.statusCategory
                ticket.priorityName = issue.priorityName
                ticket.priorityRank = PriorityRank.value(for: issue.priorityName)
                ticket.issueType = issue.issueType
                ticket.updatedAt = issue.updatedAt
                ticket.browseURLString = issue.browseURL.absoluteString
                ticket.targetEndDate = issue.targetEndDate
                ticket.numericID = issue.numericID
                applyDescription(issue.description, to: ticket)
                apply(issue.descriptionLinks, to: ticket)
            } else {
                context.insert(
                    Ticket(
                        key: issue.key,
                        summary: issue.summary,
                        statusName: issue.statusName,
                        statusCategory: issue.statusCategory,
                        priorityName: issue.priorityName,
                        issueType: issue.issueType,
                        updatedAt: issue.updatedAt,
                        browseURLString: issue.browseURL.absoluteString,
                        targetEndDate: issue.targetEndDate
                    )
                )
                if let inserted = tickets.first(where: { $0.key == issue.key }) {
                    inserted.numericID = issue.numericID
                    applyDescription(issue.description, to: inserted)
                    apply(issue.descriptionLinks, to: inserted)
                }
            }
        }

        // Whatever the query no longer returns is no longer mine. Its threads go with it,
        // by the cascade rule on the relationship.
        for orphan in existing.values {
            context.delete(orphan)
        }

        save()
        reloadFromStore()
    }

    private func applyDescription(_ description: JSONValue?, to ticket: Ticket) {
        ticket.descriptionData = description.flatMap { try? JSONEncoder().encode($0) }
    }

    private func apply(_ links: DescriptionLinks, to ticket: Ticket) {
        ticket.detectedFigmaURLString = links.figmaURL?.absoluteString
        ticket.jiraThreadLinkStrings = links.slackPermalinks.map(\.url.absoluteString)
    }

    func upsert(_ snapshot: ThreadSnapshot, into ticket: Ticket) {
        if let thread = ticket.threads.first(where: { $0.id == snapshot.id }) {
            thread.channelName = snapshot.channelName
            thread.permalinkString = snapshot.permalinkString
            thread.rootAuthorName = snapshot.rootAuthorName
            thread.rootText = snapshot.rootText
            thread.replyCount = snapshot.replyCount
            thread.participantNames = snapshot.participantNames
            thread.lastActivityAt = snapshot.lastActivityAt
            thread.lastReplyAuthorName = snapshot.lastReplyAuthorName
            thread.lastFetchedAt = Date()
            // seenReplyCount belongs to the user, never to the server.
            return
        }

        let thread = SlackThread(
            id: snapshot.id,
            channelID: snapshot.channelID,
            channelName: snapshot.channelName,
            threadTS: snapshot.threadTS,
            permalinkString: snapshot.permalinkString,
            rootAuthorName: snapshot.rootAuthorName,
            rootText: snapshot.rootText,
            replyCount: snapshot.replyCount,
            participantNames: snapshot.participantNames,
            lastActivityAt: snapshot.lastActivityAt,
            lastReplyAuthorName: snapshot.lastReplyAuthorName,
            origin: snapshot.origin,
            lastFetchedAt: Date()
        )
        context.insert(thread)
        thread.ticket = ticket
    }

    /// Clears rows written while threads were still discovered by searching. Nothing
    /// refreshes them any more, so they would sit there going stale forever.
    private func removeThreadsLeftOverFromSearch() {
        let known = Set(ThreadOrigin.allCases.map(\.rawValue))
        let leftovers = ((try? context.fetch(FetchDescriptor<SlackThread>())) ?? [])
            .filter { known.contains($0.matchKindRaw).not }
        guard leftovers.isEmpty.not else { return }

        for thread in leftovers {
            context.delete(thread)
        }
        save()
    }

    private func save() {
        do {
            try context.save()
        } catch {
            // A failed write must not take the UI down; the next refresh retries.
            Log.store.error("save failed: \(String(describing: error), privacy: .public)")
        }
    }
}

//  Strings.swift
//  DocketKit

import Foundation

/// Every user-facing string, resolved against the language picked in Settings.
///
/// Deliberately not a `.strings`/`.xcstrings` bundle: the app has to switch language
/// live, without a relaunch, and bundle lookup is fixed at launch.
public struct Strings: Sendable, Equatable {
    public let language: ResolvedLanguage

    public init(language: ResolvedLanguage) {
        self.language = language
    }

    private func t(_ ko: String, _ en: String) -> String {
        language == .korean ? ko : en
    }

    // MARK: - Shell

    /// The product name is not translated.
    public var appName: String { "Docket" }
    public var refresh: String { t("새로고침", "Refresh") }
    public var settings: String { t("설정", "Settings") }
    public var openInWindow: String { t("창으로 열기", "Open in Window") }
    public var quit: String { t("종료", "Quit") }
    public var close: String { t("닫기", "Close") }
    public var done: String { t("완료", "Done") }
    public var cancel: String { t("취소", "Cancel") }

    // MARK: - Sync status

    public var syncing: String { t("갱신 중…", "Syncing…") }
    public var neverSynced: String { t("아직 갱신되지 않음", "Not synced yet") }

    public func lastUpdated(_ relative: String) -> String {
        t("\(relative) 갱신", "Updated \(relative)")
    }

    // MARK: - Filters

    public var filterStatus: String { t("상태", "Status") }
    public var filterPriority: String { t("우선순위", "Priority") }
    public var filterAll: String { t("전체", "All") }
    public var searchPlaceholder: String { t("티켓 검색", "Search tickets") }

    // MARK: - Empty and setup states

    public var emptyTitle: String { t("할당된 티켓이 없습니다", "No tickets assigned to you") }
    public var emptySubtitle: String { t("여유로운 날이네요.", "Enjoy the quiet.") }
    public var emptyFilteredTitle: String { t("조건에 맞는 티켓이 없습니다", "No tickets match your filters") }
    public var emptyFilteredSubtitle: String { t("필터나 검색어를 바꿔보세요.", "Try changing the filter or search text.") }
    public var setupTitle: String { t("Jira를 연결해 주세요", "Connect Jira to get started") }
    public var setupSubtitle: String {
        t(
            "사이트 주소, 이메일, API 토큰을 입력하면 할당된 티켓을 불러옵니다.",
            "Enter your site address, email and API token to load your assigned tickets."
        )
    }
    public var openSettings: String { t("설정 열기", "Open Settings") }

    // MARK: - Connection banners

    public var jiraDisconnected: String { t("Jira에 연결할 수 없습니다", "Cannot reach Jira") }
    public var slackDisconnected: String { t("Slack에 연결할 수 없습니다", "Cannot reach Slack") }
    public var slackNotConfigured: String { t("Slack이 연결되지 않았습니다", "Slack is not connected") }
    public var retry: String { t("다시 시도", "Retry") }
    // MARK: - Ticket

    public var openInJira: String { t("Jira에서 열기", "Open in Jira") }
    /// The number carries the meaning, so it goes inside the button rather than beside it.
    public func openPullRequest(_ number: String) -> String {
        t("PR \(number) 열기", "Open PR \(number)")
    }
    public var openInFigma: String { t("Figma에서 열기", "Open in Figma") }
    public var addFigmaLink: String { t("Figma 링크 추가", "Add Figma link") }
    public var changeFigmaLink: String { t("Figma 링크 변경", "Change Figma link") }
    public var clearFigmaLink: String { t("직접 넣은 링크 지우기", "Clear the link you set") }
    public var figmaLinkPlaceholder: String { t("Figma 링크 붙여넣기", "Paste a Figma link") }
    public var figmaLinkFromJira: String {
        t("Jira 설명에서 찾은 링크입니다.", "Found in the Jira description.")
    }
    public var invalidFigmaLink: String {
        t("figma.com 주소가 아닙니다.", "That is not a figma.com address.")
    }
    public var copyKey: String { t("티켓 키 복사", "Copy Issue Key") }
    /// Compact enough for a list row: how long is left before the target end date.
    public func targetEnd(daysRemaining days: Int) -> String {
        switch days {
        case 0: t("D-DAY", "due today")
        case ..<0: t("D+\(-days)", "\(-days)d late")
        default: t("D-\(days)", "\(days)d left")
        }
    }

    public var targetEndLabel: String { t("목표 종료", "Target end") }

    public var noPriority: String { t("우선순위 없음", "No priority") }
    public var selectTicketPrompt: String { t("왼쪽에서 티켓을 선택하세요", "Select a ticket on the left") }

    // MARK: - Slack

    public func slackThreadCount(_ count: Int) -> String {
        t("Slack · 스레드 \(count)개", count == 1 ? "Slack · 1 thread" : "Slack · \(count) threads")
    }

    public var slackSectionEmpty: String { t("연결된 Slack 스레드가 없습니다", "No Slack threads linked") }
    public var slackSectionEmptyHint: String {
        t(
            "스레드 추가를 눌러 Slack 메시지 링크를 붙여 넣으세요.",
            "Use Add thread and paste a Slack message link."
        )
    }

    public var openInSlack: String { t("Slack에서 열기", "Open in Slack") }

    /// Stands in for the channel name on a card attached without a Slack connection.
    public var linkOnlyThreadTitle: String { t("Slack 스레드", "Slack thread") }
    public var linkOnlyThreadHint: String {
        t(
            "Slack을 연결하면 내용과 답글 수가 표시됩니다.",
            "Connect Slack to see the message and reply count."
        )
    }
    public var slackNotConfiguredThreadsHint: String {
        t(
            "링크는 연결 없이도 붙일 수 있습니다 — 스레드 추가에 Slack 링크를 붙여 넣으세요.",
            "Links attach without a connection — use Add thread and paste a Slack link."
        )
    }

    public func replyCount(_ count: Int) -> String {
        t("답글 \(count)", count == 1 ? "1 reply" : "\(count) replies")
    }

    public func participantCount(_ count: Int) -> String {
        t("\(count)명", count == 1 ? "1 person" : "\(count) people")
    }

    public func newReplyCount(_ count: Int) -> String {
        t("새 답글 \(count)", count == 1 ? "1 new reply" : "\(count) new replies")
    }

    public func lastActivity(_ author: String, _ relative: String) -> String {
        t("마지막 \(author) · \(relative)", "Last by \(author) · \(relative)")
    }

    public var addThread: String { t("스레드 추가", "Add thread") }
    public var addThreadPlaceholder: String {
        t("Slack 메시지 링크 붙여넣기", "Paste a Slack message link")
    }
    public var addThreadHelp: String {
        t(
            "Slack에서 메시지 우클릭 → Copy link. 답글 링크를 넣어도 스레드 전체가 붙습니다.",
            "In Slack, right-click a message and choose Copy link. A reply's link attaches the whole thread."
        )
    }
    public var add: String { t("추가", "Add") }
    public var adding: String { t("추가 중…", "Adding…") }
    public var removeThread: String { t("이 스레드 삭제", "Remove this thread") }
    public var hideJiraThread: String { t("이 스레드 숨기기", "Hide this thread") }
    public var threadFromJira: String {
        t("Jira 설명의 링크로 연결되었습니다.", "Attached from a link in the Jira description.")
    }
    public var invalidSlackLink: String {
        t(
            "Slack 메시지 링크가 아닙니다. Copy link로 얻은 주소를 넣어주세요.",
            "That is not a Slack message link. Paste the address from Copy link."
        )
    }
    public var threadNotFound: String {
        t(
            "스레드를 찾을 수 없습니다. 접근 권한이 있는 대화인지 확인해 주세요.",
            "The thread could not be read. Check that you have access to that conversation."
        )
    }

    // MARK: - Settings

    public var settingsGeneral: String { t("일반", "General") }
    public var settingsJira: String { t("Jira", "Jira") }
    public var settingsSlack: String { t("Slack", "Slack") }
    public var settingsGitHub: String { t("GitHub", "GitHub") }

    public var githubToken: String { t("Personal access token", "Personal access token") }
    public var githubTokenHelp: String {
        t(
            "fine-grained 토큰이면 해당 저장소에 Pull requests: Read-only 만 주면 됩니다. classic 토큰이면 repo 권한이 필요합니다.",
            "A fine-grained token needs only Pull requests: Read-only on those repositories. A classic token needs the repo scope."
        )
    }
    public var githubRepositories: String { t("저장소", "Repositories") }
    public var githubRepositoriesHelp: String {
        t(
            "owner/repo 형식으로, 쉼표나 줄바꿈으로 구분합니다. 티켓 키가 PR 제목이나 브랜치명에 있으면 찾습니다.",
            "As owner/repo, separated by commas or newlines. A pull request matches when the ticket key is in its title or its branch name."
        )
    }

    public var languageLabel: String { t("언어", "Language") }
    public var languageSystem: String { t("시스템 설정", "System") }
    public var languageKorean: String { t("한국어", "Korean") }
    public var languageEnglish: String { t("영어", "English") }

    public var refreshInterval: String { t("갱신 주기", "Refresh interval") }

    public func minutes(_ value: Int) -> String {
        t("\(value)분", value == 1 ? "1 minute" : "\(value) minutes")
    }

    /// "로그인 시" would be ambiguous here: this app logs in to Jira, Slack and GitHub.
    public var launchAtLogin: String { t("맥 시작 시 실행", "Launch at login") }
    public var launchAtLoginHelp: String {
        t(
            "맥에 로그인하면 자동으로 실행되어 메뉴바에 상주합니다.",
            "Starts with your Mac and sits in the menu bar."
        )
    }
    public var launchAtLoginNeedsApproval: String {
        t(
            "시스템 설정 → 일반 → 로그인 항목에서 허용해야 실제로 실행됩니다.",
            "It will not actually run until you allow it in System Settings › General › Login Items."
        )
    }
    public var launchAtLoginNotInApplications: String {
        t(
            "응용 프로그램 폴더에 두세요. 등록 시점의 위치가 기록되므로 나중에 옮기면 깨집니다.",
            "Keep the app in your Applications folder. Registration records where it is now, so moving it later breaks this."
        )
    }
    public var openSystemSettings: String { t("시스템 설정 열기", "Open System Settings") }

    public func launchAtLoginFailed(_ detail: String) -> String {
        t("등록하지 못했습니다: \(detail)", "Could not register: \(detail)")
    }

    public var ticketQueryLabel: String { t("표시할 티켓", "Tickets to show") }

    public func ticketQueryName(_ query: TicketQuery) -> String {
        switch query {
        case .assignedOpen:
            t("내게 할당된 미완료", "Assigned to me, open")
        case .assignedOpenOrRecentlyDone:
            t("내게 할당 · 최근 완료 7일 포함", "Assigned to me, plus done in the last 7 days")
        case .reportedOpen:
            t("내가 보고한 미완료", "Reported by me, open")
        case .watching:
            t("워치 중", "Watched by me")
        case .custom:
            t("직접 입력", "Custom JQL")
        }
    }

    public var jqlLabel: String { t("JQL", "JQL") }
    public var jqlHelp: String {
        t(
            "고를 항목이 없으면 직접 입력을 선택해 JQL을 쓰세요.",
            "Pick Custom JQL to write the query yourself."
        )
    }
    public var validateQuery: String { t("질의 확인", "Check query") }
    public var queryValid: String { t("유효한 질의입니다", "The query is valid") }

    public var jiraSiteURL: String { t("사이트 주소", "Site address") }
    public var jiraSiteURLHelp: String { t("예: https://your-team.atlassian.net", "e.g. https://your-team.atlassian.net") }
    public var jiraEmail: String { t("이메일", "Email") }
    public var jiraAPIToken: String { t("API 토큰", "API token") }
    public var jiraTokenHelp: String {
        t(
            "id.atlassian.com/manage-profile → Security → API tokens 에서 발급합니다.",
            "Create one at id.atlassian.com/manage-profile → Security → API tokens."
        )
    }

    public var slackUserToken: String { t("User 토큰", "User token") }
    public var slackTokenHelp: String {
        t(
            "앱의 User Token Scopes에 search:read, channels:history, groups:history, users:read 가 필요합니다. 토큰 회전은 꺼두세요.",
            "The app needs the user token scopes search:read, channels:history, groups:history and users:read. Leave token rotation off."
        )
    }
    public var slackConnect: String { t("Slack 연결", "Connect Slack") }
    public var slackReconnect: String { t("다시 연결", "Reconnect") }
    public var slackDisconnect: String { t("연결 해제", "Disconnect") }
    public var slackWaitingForBrowser: String { t("브라우저에서 승인해 주세요…", "Approve access in your browser…") }
    public var slackExchanging: String { t("연결을 마무리하는 중…", "Finishing the connection…") }
    public var slackNotConnected: String { t("연결되지 않음", "Not connected") }
    public var slackClientIDMissing: String { t("Slack Client ID가 설정되지 않았습니다", "No Slack client ID is configured") }
    public var slackClientIDHelp: String {
        t(
            "api.slack.com에서 앱을 만들고 PKCE를 켠 뒤, Client ID를 Project.swift의 SlackClientID 값에 넣고 tuist generate를 다시 실행하세요.",
            "Create an app at api.slack.com, turn on PKCE, then put its client ID in the SlackClientID value in Project.swift and run tuist generate again."
        )
    }
    public var slackRedirectHelp: String {
        t(
            "앱의 Redirect URLs에 아래 주소를 모두 등록해야 합니다.",
            "Register all of these addresses as Redirect URLs on your app."
        )
    }
    public var slackAdvanced: String { t("고급", "Advanced") }
    public var slackClientSecret: String { t("Client Secret", "Client secret") }
    public var slackClientSecretHelp: String {
        t(
            "PKCE 앱은 보통 secret 없이 토큰을 갱신할 수 있습니다. Slack이 secret을 요구하는 경우에만 입력하세요 — Keychain에만 저장되고 앱에 포함되지 않습니다.",
            "A PKCE app can usually renew its token without one. Fill this in only if Slack demands it — it is kept in the keychain and never ships inside the app."
        )
    }
    public var slackManualTokenHelp: String {
        t(
            "OAuth를 쓸 수 없을 때만 토큰을 직접 넣으세요.",
            "Paste a token directly only when OAuth is not available to you."
        )
    }

    public func githubErrorMessage(_ error: GitHubError) -> String {
        switch error {
        case .notConfigured:
            t("GitHub이 설정되지 않았습니다.", "GitHub is not configured.")
        case .unauthorized:
            t("토큰이 올바르지 않거나 권한이 부족합니다.", "The token is not valid, or lacks access.")
        case let .notFound(path):
            t(
                "저장소를 찾을 수 없거나 접근 권한이 없습니다: \(path)",
                "That repository could not be found, or the token cannot reach it: \(path)"
            )
        case .rateLimited:
            t("GitHub 요청이 제한되었습니다. 잠시 후 다시 시도하세요.", "GitHub rate limited the request. Try again shortly.")
        case let .http(status):
            t("GitHub 오류 (\(status))", "GitHub error (\(status))")
        case let .network(detail):
            t("네트워크 오류: \(detail)", "Network error: \(detail)")
        case let .decoding(detail):
            t("응답을 해석하지 못했습니다: \(detail)", "Could not read the response: \(detail)")
        }
    }

    public func slackOAuthErrorMessage(_ error: SlackOAuthError) -> String {
        switch error {
        case .missingClientID:
            slackClientIDMissing
        case .noAvailablePort:
            t(
                "리다이렉트 포트가 모두 사용 중입니다. 해당 포트를 쓰는 프로그램을 종료해 주세요.",
                "Every redirect port is busy. Quit whatever is using them and try again."
            )
        case let .listenerFailed(detail):
            t("리다이렉트를 받을 수 없습니다: \(detail)", "Could not listen for the redirect: \(detail)")
        case .cancelled:
            t("연결이 취소되었습니다.", "The connection was cancelled.")
        case .timedOut:
            t("승인 대기 시간이 지났습니다.", "Timed out waiting for approval.")
        case .stateMismatch:
            t(
                "응답이 이 요청과 일치하지 않아 중단했습니다. 다시 시도해 주세요.",
                "The response did not match this request, so it was rejected. Try again."
            )
        case let .denied(reason):
            t("승인이 거부되었습니다: \(reason)", "Access was denied: \(reason)")
        case .missingUserToken:
            t(
                "User 토큰이 발급되지 않았습니다. User Token Scopes 설정을 확인해 주세요.",
                "No user token came back. Check the app's user token scopes."
            )
        case .missingRefreshToken:
            t(
                "만료된 토큰을 갱신할 수 없습니다. Slack을 다시 연결해 주세요.",
                "There is no refresh token to renew with. Connect Slack again."
            )
        case let .network(detail):
            t("네트워크 오류: \(detail)", "Network error: \(detail)")
        case let .api(code):
            t("Slack 오류: \(code)", "Slack error: \(code)")
        case let .decoding(detail):
            t("응답을 해석하지 못했습니다: \(detail)", "Could not read the response: \(detail)")
        }
    }

    public var testConnection: String { t("연결 테스트", "Test connection") }
    public var testing: String { t("확인 중…", "Testing…") }

    public func connectedAs(_ name: String) -> String {
        t("연결됨 · \(name)", "Connected · \(name)")
    }

    public var notConfigured: String { t("설정되지 않음", "Not configured") }

    // MARK: - Errors

    public func jiraErrorMessage(_ error: JiraError) -> String {
        switch error {
        case .notConfigured:
            t("Jira 설정이 완료되지 않았습니다.", "Jira is not configured yet.")
        case .invalidSite:
            t("사이트 주소를 확인해 주세요.", "Check the site address.")
        case .unauthorized:
            t("이메일 또는 API 토큰이 올바르지 않습니다.", "The email or API token is not valid.")
        case let .http(status, message):
            message.isEmpty ? t("Jira 오류 (\(status))", "Jira error (\(status))") : message
        case let .network(detail):
            t("네트워크 오류: \(detail)", "Network error: \(detail)")
        case let .decoding(detail):
            t("응답을 해석하지 못했습니다: \(detail)", "Could not read the response: \(detail)")
        }
    }

    public func slackErrorMessage(_ error: SlackError) -> String {
        switch error {
        case .notConfigured:
            t("Slack 토큰이 없습니다.", "No Slack token set.")
        case .invalidAuth:
            t("Slack 토큰이 만료되었거나 올바르지 않습니다.", "The Slack token is expired or not valid.")
        case .tokenExpired:
            t("Slack 토큰이 만료되었습니다. 갱신을 시도합니다.", "The Slack token expired; renewing it.")
        case let .refreshFailed(detail):
            t("토큰 갱신에 실패했습니다: \(detail)", "Could not renew the token: \(detail)")
        case let .missingScope(scope):
            t("Slack 권한이 부족합니다: \(scope)", "The Slack token is missing a scope: \(scope)")
        case let .rateLimited(seconds):
            t("Slack 요청이 제한되었습니다. \(Int(seconds))초 후 재시도합니다.", "Slack rate limited. Retrying in \(Int(seconds))s.")
        case .api("invalid_link"):
            invalidSlackLink
        case .api("thread_not_found"):
            threadNotFound
        case let .api(code):
            t("Slack 오류: \(code)", "Slack error: \(code)")
        case let .http(status):
            t("Slack 오류 (\(status))", "Slack error (\(status))")
        case let .network(detail):
            t("네트워크 오류: \(detail)", "Network error: \(detail)")
        case let .decoding(detail):
            t("응답을 해석하지 못했습니다: \(detail)", "Could not read the response: \(detail)")
        }
    }
}

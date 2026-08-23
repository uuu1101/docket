//  SettingsView.swift
//  Docket

import SwiftUI

import DocketKit

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label(settings.strings.settingsGeneral, systemImage: "gearshape") }
            JiraSettingsView()
                .tabItem { Label(settings.strings.settingsJira, systemImage: "checklist") }
            SlackSettingsView()
                .tabItem { Label(settings.strings.settingsSlack, systemImage: "bubble.left.and.bubble.right") }
            GitHubSettingsView()
                .tabItem { Label(settings.strings.settingsGitHub, systemImage: "chevron.left.forwardslash.chevron.right") }
        }
        .frame(width: 520)
        .accessibilityIdentifier("setting_container_tabs")
    }
}

// MARK: - General

private struct GeneralSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(DashboardStore.self) private var store
    @Environment(LoginItem.self) private var loginItem

    @State private var queryResult: ConnectionTestResult = .idle

    var body: some View {
        @Bindable var settings = settings

        Form {
            Picker(settings.strings.languageLabel, selection: $settings.language) {
                Text(settings.strings.languageSystem).tag(AppLanguage.system)
                Text(settings.strings.languageKorean).tag(AppLanguage.korean)
                Text(settings.strings.languageEnglish).tag(AppLanguage.english)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("setting_dropdown_language")

            Section {
                Toggle(settings.strings.launchAtLogin, isOn: Binding(
                    get: { loginItem.isEnabled },
                    set: { loginItem.set($0) }
                ))
                .accessibilityIdentifier("setting_toggle_launch_at_login")

                if let failure = loginItem.failure {
                    Label(settings.strings.launchAtLoginFailed(failure), systemImage: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("setting_status_launch_at_login_failure")
                } else if loginItem.needsApproval {
                    HStack(spacing: 8) {
                        Label(settings.strings.launchAtLoginNeedsApproval, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Button(settings.strings.openSystemSettings) { openLoginItemsSettings() }
                            .buttonStyle(.borderless)
                            .font(.caption)
                    }
                    .accessibilityIdentifier("setting_status_launch_at_login_approval")
                } else {
                    Text(settings.strings.launchAtLoginHelp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if loginItem.isInApplicationsFolder == false {
                    Label(settings.strings.launchAtLoginNotInApplications, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("setting_status_launch_at_login_location")
                }
            }

            Picker(settings.strings.refreshInterval, selection: $settings.refreshMinutes) {
                ForEach([5, 10, 15, 30, 60], id: \.self) { minutes in
                    Text(settings.strings.minutes(minutes)).tag(minutes)
                }
            }
            .onChange(of: settings.refreshMinutes) { store.startAutoRefresh() }
            .accessibilityIdentifier("setting_dropdown_refresh_interval")

            Section {
                Picker(settings.strings.ticketQueryLabel, selection: $settings.query) {
                    ForEach(TicketQuery.allCases) { query in
                        Text(settings.strings.ticketQueryName(query)).tag(query)
                    }
                }
                .accessibilityIdentifier("setting_dropdown_ticket_query")
                .onChange(of: settings.query) { previous, current in
                    // Switching into custom starts from the query that was showing, so the
                    // user edits something that already works instead of an empty box.
                    if current == .custom, settings.customJQL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        settings.customJQL = previous.jql ?? TicketQuery.fallbackJQL
                    }
                    queryResult = .idle
                    store.refresh(force: true)
                }

                if settings.query == .custom {
                    TextField(settings.strings.jqlLabel, text: $settings.customJQL, axis: .vertical)
                        .lineLimit(2 ... 4)
                        .font(.callout.monospaced())
                        .accessibilityIdentifier("setting_input_jql")

                    ConnectionTestRow(title: settings.strings.validateQuery, result: queryResult) {
                        await validateQuery()
                    }
                } else if let jql = settings.query.jql {
                    Text(jql)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("setting_text_resolved_jql")
                }

                Text(settings.strings.jqlHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
        // The user can change this in System Settings, so read it back on every visit.
        .onAppear { loginItem.refresh() }
    }

    private func openLoginItemsSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// Runs the query for a single issue: enough to tell a valid JQL from a typo without
    /// pulling the whole result set.
    private func validateQuery() async {
        guard let configuration = settings.jiraConfiguration else {
            queryResult = .failure(settings.strings.notConfigured)
            return
        }
        queryResult = .testing
        do {
            _ = try await LiveJiraAPI(configuration: configuration).issues(jql: settings.jql, maxResults: 1, extraFieldID: nil)
            queryResult = .success(settings.strings.queryValid)
            store.refresh(force: true)
        } catch {
            queryResult = .failure(settings.strings.jiraErrorMessage(error))
        }
    }
}

// MARK: - Jira

private struct JiraSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(DashboardStore.self) private var store

    @State private var result: ConnectionTestResult = .idle

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                TextField(settings.strings.jiraSiteURL, text: $settings.jiraSiteURL)
                    .accessibilityIdentifier("setting_input_jira_site")
                Text(settings.strings.jiraSiteURLHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField(settings.strings.jiraEmail, text: $settings.jiraEmail)
                    .accessibilityIdentifier("setting_input_jira_email")

                SecureField(settings.strings.jiraAPIToken, text: $settings.jiraAPIToken)
                    .accessibilityIdentifier("setting_input_jira_token")
                Text(settings.strings.jiraTokenHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField(settings.strings.jiraBotAccountIDs, text: $settings.jiraBotAccountIDs)
                    .accessibilityIdentifier("setting_input_jira_bot_ids")
                Text(settings.strings.jiraBotAccountIDsHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ConnectionTestRow(title: settings.strings.testConnection, result: result) {
                await testConnection()
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }

    private func testConnection() async {
        guard let configuration = settings.jiraConfiguration else {
            result = .failure(settings.strings.notConfigured)
            return
        }
        result = .testing
        do {
            let account = try await LiveJiraAPI(configuration: configuration).account()
            result = .success(settings.strings.connectedAs(account.displayName))
            store.refresh(force: true)
        } catch {
            result = .failure(settings.strings.jiraErrorMessage(error))
        }
    }
}

// MARK: - Slack

private struct SlackSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(DashboardStore.self) private var store
    @Environment(SlackAuthCoordinator.self) private var auth

    @State private var result: ConnectionTestResult = .idle
    @State private var showsAdvanced = false

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                connection

                if case let .failed(message) = auth.phase {
                    Label(message, systemImage: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("setting_status_slack_auth_failure")
                }

                if settings.slackClientID.isEmpty {
                    Text(settings.strings.slackClientIDHelp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(settings.strings.slackRedirectHelp)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(auth.redirectURIs, id: \.self) { uri in
                            Text(uri)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    .accessibilityIdentifier("setting_container_redirect_uris")
                }

                Text(settings.strings.slackTokenHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if settings.isSlackConfigured {
                ConnectionTestRow(title: settings.strings.testConnection, result: result) {
                    await testConnection()
                }
            }

            Section(isExpanded: $showsAdvanced) {
                // Through the manual-token path, not the raw property: pasting over an
                // OAuth connection must also drop its rotation state, or the store tries
                // to renew a token that has no refresh token of its own.
                SecureField(
                    settings.strings.slackUserToken,
                    text: Binding(
                        get: { settings.slackUserToken },
                        set: { settings.applyManualSlackToken($0) }
                    )
                )
                .accessibilityIdentifier("setting_input_slack_token")
                Text(settings.strings.slackManualTokenHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                SecureField(settings.strings.slackClientSecret, text: $settings.slackClientSecret)
                    .accessibilityIdentifier("setting_input_slack_client_secret")
                Text(settings.strings.slackClientSecretHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(settings.strings.slackAdvanced)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
        .onChange(of: settings.isSlackConfigured) { _, isConfigured in
            result = .idle
            if isConfigured { store.refresh(force: true) }
        }
    }

    @ViewBuilder private var connection: some View {
        if settings.isSlackConfigured {
            HStack(spacing: 8) {
                Label(
                    settings.strings.connectedAs(settings.slackAccountLabel.isEmpty ? "Slack" : settings.slackAccountLabel),
                    systemImage: "checkmark.circle.fill"
                )
                .font(.callout)
                .foregroundStyle(.green)
                .accessibilityIdentifier("setting_status_slack_connected")

                Spacer(minLength: 0)

                Button(settings.strings.slackDisconnect) { auth.disconnect() }
                    .accessibilityIdentifier("setting_button_slack_disconnect")
            }
        } else if auth.phase.isRunning {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(auth.phase == .exchanging ? settings.strings.slackExchanging : settings.strings.slackWaitingForBrowser)
                    .font(.callout)
                Spacer(minLength: 0)
                Button(settings.strings.cancel) { auth.cancel() }
                    .accessibilityIdentifier("setting_button_slack_cancel")
            }
        } else {
            Button(settings.strings.slackConnect) { auth.connect() }
                .disabled(settings.slackClientID.isEmpty)
                .accessibilityIdentifier("setting_button_slack_connect")
        }
    }

    private func testConnection() async {
        guard settings.isSlackConfigured else {
            result = .failure(settings.strings.notConfigured)
            return
        }
        result = .testing
        do {
            let identity = try await LiveSlackAPI(token: settings.slackUserToken).identity()
            // Workspaces connected before the id was stored learn it here, without reconnecting.
            settings.applySlackIdentity(identity)
            let label = identity.teamName.isEmpty ? identity.userName : "\(identity.userName) · \(identity.teamName)"
            result = .success(settings.strings.connectedAs(label))
            store.refresh(force: true)
        } catch {
            result = .failure(settings.strings.slackErrorMessage(error))
        }
    }
}

// MARK: - GitHub

private struct GitHubSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(DashboardStore.self) private var store

    @State private var result: ConnectionTestResult = .idle

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                SecureField(settings.strings.githubToken, text: $settings.githubToken)
                    .accessibilityIdentifier("setting_input_github_token")
                Text(settings.strings.githubTokenHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField(settings.strings.githubRepositories, text: $settings.githubRepositories, axis: .vertical)
                    .lineLimit(1 ... 4)
                    .font(.callout.monospaced())
                    .accessibilityIdentifier("setting_input_github_repositories")
                Text(settings.strings.githubRepositoriesHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ConnectionTestRow(title: settings.strings.testConnection, result: result) {
                await testConnection()
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }

    private func testConnection() async {
        guard let configuration = settings.githubConfiguration else {
            result = .failure(settings.strings.notConfigured)
            return
        }
        result = .testing
        do {
            let login = try await LiveGitHubAPI(configuration: configuration).login()
            result = .success(settings.strings.connectedAs(login))
            store.refresh(force: true)
        } catch {
            result = .failure(settings.strings.githubErrorMessage(error))
        }
    }
}

// MARK: - Shared

enum ConnectionTestResult: Equatable {
    case idle
    case testing
    case success(String)
    case failure(String)
}

private struct ConnectionTestRow: View {
    @Environment(AppSettings.self) private var settings

    let title: String
    let result: ConnectionTestResult
    let action: () async -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(result == .testing ? settings.strings.testing : title) {
                Task { await action() }
            }
            .disabled(result == .testing)
            .accessibilityIdentifier("setting_button_test_connection")

            switch result {
            case .idle, .testing:
                EmptyView()
            case let .success(message):
                Label(message, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .accessibilityIdentifier("setting_status_connection_success")
            case let .failure(message):
                Label(message, systemImage: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .accessibilityIdentifier("setting_status_connection_failure")
            }

            Spacer(minLength: 0)
        }
    }
}

//  ConnectionBanner.swift
//  Docket

import SwiftUI

import DocketKit

/// Thin strip that reports a broken connection without hiding the cached data underneath.
struct ConnectionBanner: View {
    @Environment(AppSettings.self) private var settings
    @Environment(DashboardStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            if case let .failed(message) = store.jiraState {
                banner(title: settings.strings.jiraDisconnected, detail: message, tint: .red)
            }
            if case let .failed(message) = store.slackState {
                banner(title: settings.strings.slackDisconnected, detail: message, tint: .orange)
            }
        }
    }

    private func banner(title: String, detail: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Button(settings.strings.retry) { store.refresh(force: false) }
                .buttonStyle(.borderless)
                .font(.caption)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tint.opacity(0.1))
        .accessibilityIdentifier("dashboard_alert_connection")
    }
}

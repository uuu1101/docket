//  KeychainStore.swift
//  DocketKit

import Foundation
import Security

/// Generic-password storage for the two API tokens.
///
/// Items use `kSecAttrAccessibleAfterFirstUnlock` so a background refresh right after
/// login does not fail on a locked keychain.
public struct KeychainStore: Sendable {
    public enum Key: String, Sendable, CaseIterable {
        case jiraAPIToken = "jira-api-token"
        case slackUserToken = "slack-user-token"
        case slackRefreshToken = "slack-refresh-token"
        case slackClientSecret = "slack-client-secret"
        case githubToken = "github-token"
    }

    private let service: String

    public init(service: String = "dev.taetae.docket") {
        self.service = service
    }

    public func value(for key: Key) -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let string = String(data: data, encoding: .utf8),
              string.isEmpty.not
        else { return nil }
        return string
    }

    @discardableResult
    public func set(_ value: String?, for key: Key) -> Bool {
        guard let value, value.isEmpty.not else { return delete(key) }

        let data = Data(value.utf8)
        let query = baseQuery(for: key)
        let attributes: [String: Any] = [kSecValueData as String: data]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        guard updateStatus == errSecItemNotFound else { return false }

        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    public func delete(_ key: Key) -> Bool {
        let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private func baseQuery(for key: Key) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
    }
}


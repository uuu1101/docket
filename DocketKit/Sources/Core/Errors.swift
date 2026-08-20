//  Errors.swift
//  DocketKit

import Foundation

public enum JiraError: Error, Sendable, Equatable {
    case notConfigured
    case invalidSite
    case unauthorized
    case http(status: Int, message: String)
    case network(String)
    case decoding(String)
}

public enum SlackError: Error, Sendable, Equatable {
    case notConfigured
    case invalidAuth
    case tokenExpired
    case refreshFailed(String)
    case missingScope(String)
    case rateLimited(retryAfter: TimeInterval)
    case api(String)
    case http(status: Int)
    case network(String)
    case decoding(String)
}

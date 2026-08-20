//  AppLanguage.swift
//  DocketKit

import Foundation

/// UI language chosen in Settings.
public enum AppLanguage: String, CaseIterable, Sendable, Codable {
    case system
    case korean
    case english

    public var resolved: ResolvedLanguage {
        switch self {
        case .korean: .korean
        case .english: .english
        case .system: Locale.preferredLanguages.first?.hasPrefix("ko") == true ? .korean : .english
        }
    }
}

public enum ResolvedLanguage: String, Sendable {
    case korean
    case english

    public var locale: Locale {
        switch self {
        case .korean: Locale(identifier: "ko_KR")
        case .english: Locale(identifier: "en_US")
        }
    }
}

//  BoolNegation.swift
//  DocketKit

extension Bool {
    /// Reads better than a leading `!` in a long condition.
    var not: Bool { self == false }
}

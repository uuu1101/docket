//  TicketFilter.swift
//  Docket

import Foundation

import DocketKit

/// Filter state for one list. The popover and the window each keep their own.
struct TicketFilter: Equatable {
    var statusCategory: StatusCategory?
    var priorityName: String?
    var searchText: String = ""

    var isActive: Bool {
        statusCategory != nil || priorityName != nil || searchText.isEmpty == false
    }

    func apply(to tickets: [Ticket]) -> [Ticket] {
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return tickets.filter { ticket in
            if let statusCategory, ticket.statusCategory != statusCategory { return false }
            if let priorityName, ticket.priorityName != priorityName { return false }
            guard needle.isEmpty == false else { return true }
            return ticket.key.lowercased().contains(needle)
                || ticket.summary.lowercased().contains(needle)
                || ticket.statusName.lowercased().contains(needle)
        }
    }
}

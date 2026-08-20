//  TransitionTests.swift
//  DocketKitTests

import Foundation
import Testing

@testable import DocketKit

@Suite("Reading the moves a workflow allows")
struct TransitionDecodingTests {
    private func transitions(_ json: String) throws -> [JiraTransition] {
        try JSONDecoder().decode(JiraTransitionsResponse.self, from: Data(json.utf8))
            .transitions?.compactMap(\.asEntity) ?? []
    }

    @Test("A move keeps its id and the status it lands on")
    func decodes() throws {
        let found = try transitions("""
        {"transitions":[{"id":"31","name":"Start Review",
          "to":{"name":"검토 중","statusCategory":{"key":"indeterminate"}}}]}
        """)
        #expect(found.count == 1)
        #expect(found.first?.id == "31")
        #expect(found.first?.name == "Start Review")
        #expect(found.first?.toStatusName == "검토 중")
        #expect(found.first?.toStatusCategory == .inProgress)
    }

    @Test("The status override applies to the destination too")
    func appliesStatusOverride() throws {
        let found = try transitions("""
        {"transitions":[{"id":"41","name":"Ready","to":{"name":"READY FOR QA","statusCategory":{"key":"done"}}}]}
        """)
        // Jira calls it done; the dashboard treats it as work still in flight.
        #expect(found.first?.toStatusCategory == .inProgress)
    }

    @Test("Required fields are reported so the move can be refused up front")
    func requiredFields() throws {
        let found = try transitions("""
        {"transitions":[{"id":"51","name":"Done","to":{"name":"완료","statusCategory":{"key":"done"}},
          "fields":{"resolution":{"required":true},"comment":{"required":false}}}]}
        """)
        #expect(found.first?.requiredFields == ["resolution"])
    }

    @Test("A move with no fields needs nothing")
    func noRequiredFields() throws {
        let found = try transitions("""
        {"transitions":[{"id":"11","name":"TO DO","to":{"name":"해야 할 일","statusCategory":{"key":"new"}}}]}
        """)
        #expect(found.first?.requiredFields.isEmpty == true)
    }

    @Test("An entry without a destination is dropped rather than shown as a blank option")
    func dropsIncomplete() throws {
        #expect(try transitions(#"{"transitions":[{"id":"1","name":"Nowhere"}]}"#).isEmpty)
    }

    @Test("No permission means no moves, not an error", arguments: [
        #"{"transitions":[]}"#, "{}",
    ])
    func emptyList(json: String) throws {
        #expect(try transitions(json).isEmpty)
    }

    @Test("An unknown category falls back to to-do rather than failing")
    func unknownCategory() throws {
        let found = try transitions("""
        {"transitions":[{"id":"61","name":"Odd","to":{"name":"뭔가","statusCategory":{"key":"whatever"}}}]}
        """)
        #expect(found.first?.toStatusCategory == .todo)
    }
}

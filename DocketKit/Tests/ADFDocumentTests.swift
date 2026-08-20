//  ADFDocumentTests.swift
//  DocketKitTests

import Foundation
import Testing

@testable import DocketKit

@Suite("Rendering a Jira description")
struct ADFDocumentTests {
    private func blocks(_ json: String) throws -> [ADFBlock] {
        let document = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        return ADFDocument.blocks(from: document)
    }

    private func plainText(_ block: ADFBlock?) -> String {
        switch block {
        case let .paragraph(spans), let .heading(_, spans), let .listItem(_, _, spans):
            spans.map(\.text).joined()
        case let .codeBlock(code):
            code
        default:
            ""
        }
    }

    @Test("A paragraph becomes one line")
    func paragraph() throws {
        let found = try blocks("""
        {"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"결제 화면에서 앱이 죽습니다"}]}]}
        """)
        #expect(found.count == 1)
        #expect(plainText(found.first) == "결제 화면에서 앱이 죽습니다")
    }

    @Test("Marks survive on their span")
    func marks() throws {
        let found = try blocks("""
        {"type":"doc","content":[{"type":"paragraph","content":[
          {"type":"text","text":"필수","marks":[{"type":"strong"}]},
          {"type":"text","text":" 항목"},
          {"type":"text","text":"코드","marks":[{"type":"code"}]}]}]}
        """)
        guard case let .paragraph(spans) = try #require(found.first) else {
            Issue.record("expected a paragraph")
            return
        }
        #expect(spans[0].isBold)
        #expect(spans[1].isBold == false)
        #expect(spans[2].isCode)
    }

    @Test("A link mark keeps its destination")
    func link() throws {
        let found = try blocks("""
        {"type":"doc","content":[{"type":"paragraph","content":[
          {"type":"text","text":"디자인","marks":[{"type":"link","attrs":{"href":"https://www.figma.com/design/abc"}}]}]}]}
        """)
        guard case let .paragraph(spans) = try #require(found.first) else {
            Issue.record("expected a paragraph")
            return
        }
        #expect(spans.first?.link?.absoluteString == "https://www.figma.com/design/abc")
    }

    @Test("Headings keep their level, clamped to what a renderer can use")
    func headings() throws {
        let found = try blocks("""
        {"type":"doc","content":[
          {"type":"heading","attrs":{"level":2},"content":[{"type":"text","text":"재현 절차"}]},
          {"type":"heading","content":[{"type":"text","text":"레벨 없음"}]}]}
        """)
        guard case let .heading(level, _) = found[0] else {
            Issue.record("expected a heading")
            return
        }
        #expect(level == 2)
        guard case let .heading(fallback, _) = found[1] else {
            Issue.record("expected a heading")
            return
        }
        #expect((1 ... 6).contains(fallback))
    }

    @Test("A bullet list yields one line per item")
    func bulletList() throws {
        let found = try blocks("""
        {"type":"doc","content":[{"type":"bulletList","content":[
          {"type":"listItem","content":[{"type":"paragraph","content":[{"type":"text","text":"첫째"}]}]},
          {"type":"listItem","content":[{"type":"paragraph","content":[{"type":"text","text":"둘째"}]}]}]}]}
        """)
        #expect(found.count == 2)
        #expect(plainText(found[0]) == "첫째")
        guard case let .listItem(marker, depth, _) = found[0] else {
            Issue.record("expected a list item")
            return
        }
        #expect(marker == "•")
        #expect(depth == 0)
    }

    @Test("An ordered list numbers its items")
    func orderedList() throws {
        let found = try blocks("""
        {"type":"doc","content":[{"type":"orderedList","content":[
          {"type":"listItem","content":[{"type":"paragraph","content":[{"type":"text","text":"켠다"}]}]},
          {"type":"listItem","content":[{"type":"paragraph","content":[{"type":"text","text":"누른다"}]}]}]}]}
        """)
        let markers = found.compactMap { block -> String? in
            guard case let .listItem(marker, _, _) = block else { return nil }
            return marker
        }
        #expect(markers == ["1.", "2."])
    }

    @Test("A nested list is indented rather than flattened away")
    func nestedList() throws {
        let found = try blocks("""
        {"type":"doc","content":[{"type":"bulletList","content":[
          {"type":"listItem","content":[
            {"type":"paragraph","content":[{"type":"text","text":"바깥"}]},
            {"type":"bulletList","content":[
              {"type":"listItem","content":[{"type":"paragraph","content":[{"type":"text","text":"안쪽"}]}]}]}]}]}]}
        """)
        let depths = found.compactMap { block -> Int? in
            guard case let .listItem(_, depth, _) = block else { return nil }
            return depth
        }
        #expect(depths == [0, 1])
        #expect(plainText(found.last) == "안쪽")
    }

    @Test("A code block keeps its text as one string")
    func codeBlock() throws {
        let found = try blocks("""
        {"type":"doc","content":[{"type":"codeBlock","content":[{"type":"text","text":"let x = 1"}]}]}
        """)
        #expect(plainText(found.first) == "let x = 1")
    }

    @Test("A hard break stays inside the line")
    func hardBreak() throws {
        let found = try blocks("""
        {"type":"doc","content":[{"type":"paragraph","content":[
          {"type":"text","text":"위"},{"type":"hardBreak"},{"type":"text","text":"아래"}]}]}
        """)
        #expect(found.count == 1)
        #expect(plainText(found.first) == "위\n아래")
    }

    @Test("An inline card shows its address, since no title is sent")
    func inlineCard() throws {
        let found = try blocks("""
        {"type":"doc","content":[{"type":"paragraph","content":[
          {"type":"inlineCard","attrs":{"url":"https://example.atlassian.net/browse/APP-1"}}]}]}
        """)
        guard case let .paragraph(spans) = try #require(found.first) else {
            Issue.record("expected a paragraph")
            return
        }
        #expect(spans.first?.link != nil)
    }

    @Test("Tables and media are named, not silently dropped", arguments: [
        (#"{"type":"doc","content":[{"type":"table","content":[]}]}"#, "table"),
        (#"{"type":"doc","content":[{"type":"mediaSingle","content":[]}]}"#, "media"),
    ])
    func unsupported(json: String, kind: String) throws {
        #expect(try blocks(json) == [.unsupported(kind: kind)])
    }

    @Test("A panel's children are read through, not lost with the wrapper")
    func panel() throws {
        let found = try blocks("""
        {"type":"doc","content":[{"type":"panel","attrs":{"panelType":"info"},"content":[
          {"type":"paragraph","content":[{"type":"text","text":"주의"}]}]}]}
        """)
        #expect(plainText(found.first) == "주의")
    }

    @Test("A node type this renderer has never seen still yields its text")
    func unknownNodeType() throws {
        let found = try blocks("""
        {"type":"doc","content":[{"type":"somethingNew","content":[
          {"type":"paragraph","content":[{"type":"text","text":"내용"}]}]}]}
        """)
        #expect(plainText(found.first) == "내용")
    }

    @Test("No description yields no blocks", arguments: [#"{"type":"doc","content":[]}"#, "null"])
    func empty(json: String) throws {
        #expect(try blocks(json).isEmpty)
    }

    @Test("A description survives being stored and read back")
    func roundTrip() throws {
        let json = #"{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"본문"}]}]}"#
        let document = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        let encoded = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: encoded)
        #expect(plainText(ADFDocument.blocks(from: decoded).first) == "본문")
    }
}

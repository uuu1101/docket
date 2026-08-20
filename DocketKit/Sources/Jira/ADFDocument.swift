//  ADFDocument.swift
//  DocketKit

import Foundation

/// A run of text carrying the marks Jira actually uses.
public struct ADFSpan: Sendable, Equatable {
    public var text: String
    public var isBold = false
    public var isItalic = false
    public var isCode = false
    public var isUnderlined = false
    public var link: URL?

    public init(
        text: String,
        isBold: Bool = false,
        isItalic: Bool = false,
        isCode: Bool = false,
        isUnderlined: Bool = false,
        link: URL? = nil
    ) {
        self.text = text
        self.isBold = isBold
        self.isItalic = isItalic
        self.isCode = isCode
        self.isUnderlined = isUnderlined
        self.link = link
    }
}

/// One line of a rendered description.
public enum ADFBlock: Sendable, Equatable {
    case paragraph([ADFSpan])
    case heading(level: Int, [ADFSpan])
    /// `marker` is the bullet or number already resolved for its depth.
    case listItem(marker: String, depth: Int, [ADFSpan])
    case codeBlock(String)
    case rule
    /// A node this renderer does not draw. Named so the reader is told what is missing
    /// rather than left with a gap that looks like a bug.
    case unsupported(kind: String)
}

/// Flattens an Atlassian Document Format description into lines.
///
/// The node types are the ones real tickets use — a sample of fifteen was over 95%
/// paragraphs, list items, headings, code and links. Tables and media appeared twice each
/// and are deliberately left to Jira: a table in a 400pt panel is unreadable, and media
/// needs an authenticated fetch.
public enum ADFDocument {
    public static func blocks(from document: JSONValue?) -> [ADFBlock] {
        guard let document, case let .object(root) = document else { return [] }
        var blocks: [ADFBlock] = []
        append(contentOf: root["content"], into: &blocks, depth: 0)
        return blocks
    }

    private static func append(contentOf value: JSONValue?, into blocks: inout [ADFBlock], depth: Int) {
        guard case let .array(nodes)? = value else { return }
        for node in nodes {
            append(node: node, into: &blocks, depth: depth)
        }
    }

    private static func append(node: JSONValue, into blocks: inout [ADFBlock], depth: Int) {
        guard case let .object(fields) = node, case let .string(kind)? = fields["type"] else { return }

        switch kind {
        case "paragraph":
            let spans = self.spans(in: fields["content"])
            // A paragraph inside a list item is the item's text, already emitted by the list.
            if spans.isEmpty.not { blocks.append(.paragraph(spans)) }

        case "heading":
            blocks.append(.heading(level: level(of: fields), spans(in: fields["content"])))

        case "bulletList", "orderedList":
            appendList(fields: fields, ordered: kind == "orderedList", into: &blocks, depth: depth)

        case "codeBlock":
            blocks.append(.codeBlock(plainText(in: fields["content"])))

        case "rule":
            blocks.append(.rule)

        case "blockquote", "panel":
            // Container types: their children are ordinary blocks.
            append(contentOf: fields["content"], into: &blocks, depth: depth)

        case "table":
            blocks.append(.unsupported(kind: "table"))

        case "mediaSingle", "mediaGroup", "media", "file":
            blocks.append(.unsupported(kind: "media"))

        default:
            // Unknown block with children still yields its text rather than vanishing.
            append(contentOf: fields["content"], into: &blocks, depth: depth)
        }
    }

    private static func appendList(
        fields: [String: JSONValue],
        ordered: Bool,
        into blocks: inout [ADFBlock],
        depth: Int
    ) {
        guard case let .array(items)? = fields["content"] else { return }

        for (offset, item) in items.enumerated() {
            guard case let .object(itemFields) = item, case let .array(children)? = itemFields["content"] else {
                continue
            }

            var text: [ADFSpan] = []
            var nested: [ADFBlock] = []
            for child in children {
                guard case let .object(childFields) = child,
                      case let .string(childKind)? = childFields["type"]
                else { continue }

                if childKind == "paragraph" {
                    text += spans(in: childFields["content"])
                } else {
                    append(node: child, into: &nested, depth: depth + 1)
                }
            }

            let marker = ordered ? "\(offset + 1)." : "•"
            blocks.append(.listItem(marker: marker, depth: depth, text))
            blocks += nested
        }
    }

    private static func level(of fields: [String: JSONValue]) -> Int {
        guard case let .object(attributes)? = fields["attrs"],
              case let .number(level)? = attributes["level"]
        else { return 3 }
        return min(max(Int(level), 1), 6)
    }

    // MARK: - Inline content

    private static func spans(in value: JSONValue?) -> [ADFSpan] {
        guard case let .array(nodes)? = value else { return [] }

        var spans: [ADFSpan] = []
        for node in nodes {
            guard case let .object(fields) = node, case let .string(kind)? = fields["type"] else { continue }

            switch kind {
            case "text":
                guard case let .string(text)? = fields["text"], text.isEmpty.not else { continue }
                spans.append(span(text: text, marks: fields["marks"]))

            case "hardBreak":
                spans.append(ADFSpan(text: "\n"))

            case "inlineCard":
                // A bare link card: show the address, since the title is not in the payload.
                // Only a web URL may become clickable; anything else stays plain text.
                if case let .object(attributes)? = fields["attrs"],
                   case let .string(url)? = attributes["url"] {
                    spans.append(ADFSpan(text: url, link: URL(string: url).flatMap { $0.isWebURL ? $0 : nil }))
                }

            case "emoji":
                if case let .object(attributes)? = fields["attrs"],
                   case let .string(text)? = attributes["text"] {
                    spans.append(ADFSpan(text: text))
                }

            case "mention":
                if case let .object(attributes)? = fields["attrs"],
                   case let .string(name)? = attributes["text"] {
                    spans.append(ADFSpan(text: name, isBold: true))
                }

            default:
                spans += self.spans(in: fields["content"])
            }
        }
        return spans
    }

    private static func span(text: String, marks: JSONValue?) -> ADFSpan {
        var span = ADFSpan(text: text)
        guard case let .array(marks)? = marks else { return span }

        for mark in marks {
            guard case let .object(markFields) = mark,
                  case let .string(kind)? = markFields["type"]
            else { continue }

            switch kind {
            case "strong": span.isBold = true
            case "em": span.isItalic = true
            case "code": span.isCode = true
            case "underline": span.isUnderlined = true
            case "link":
                // A `javascript:` or `file:` href planted in a description must not
                // become clickable; the text still renders.
                if case let .object(attributes)? = markFields["attrs"],
                   case let .string(href)? = attributes["href"],
                   let url = URL(string: href), url.isWebURL {
                    span.link = url
                }
            default: break
            }
        }
        return span
    }

    private static func plainText(in value: JSONValue?) -> String {
        spans(in: value).map(\.text).joined()
    }
}

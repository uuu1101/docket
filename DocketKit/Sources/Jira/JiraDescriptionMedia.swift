//  JiraDescriptionMedia.swift
//  DocketKit

import Foundation

/// An image or a video the description embeds.
///
/// An ADF `media` node identifies its file by a media-services UUID, which no Jira REST
/// endpoint accepts. Jira's own rendering of the same description does name the attachment —
/// `/rest/api/3/attachment/content/70664` — so the ids come from there, in document order.
public struct JiraDescriptionMedia: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable {
        case image
        case video
        /// A file this app does not draw, named so the reader is told what it is.
        case other
    }

    public let attachmentID: String
    public let kind: Kind
    public let width: Int?
    public let height: Int?

    public var id: String { attachmentID }

    public init(attachmentID: String, kind: Kind, width: Int? = nil, height: Int? = nil) {
        self.attachmentID = attachmentID
        self.kind = kind
        self.width = width
        self.height = height
    }
}

/// Reads the media references out of Jira's rendered description.
enum JiraRenderedDescription {
    /// Jira wraps an image in `<img src="…/attachment/thumbnail/54451">` and a video in
    /// `<object type="video/quicktime" data="…/attachment/content/70664?stream=true">`, whose
    /// nested `param` and `embed` repeat the same address — only the outer tag is read.
    private static let mediaTag = try? NSRegularExpression(
        pattern: "<(img|object)\\b[^>]*>",
        options: [.caseInsensitive]
    )

    private static func attribute(_ name: String, in tag: String) -> String? {
        guard let expression = try? NSRegularExpression(
            pattern: "\\b\(name)\\s*=\\s*\"([^\"]*)\"",
            options: [.caseInsensitive]
        ) else { return nil }
        let range = NSRange(tag.startIndex ..< tag.endIndex, in: tag)
        guard let match = expression.firstMatch(in: tag, range: range),
              let captured = Range(match.range(at: 1), in: tag)
        else { return nil }
        return String(tag[captured])
    }

    private static func attachmentID(in tag: String) -> String? {
        guard let expression = try? NSRegularExpression(
            pattern: "/attachment/(?:thumbnail|content)/(\\d+)"
        ) else { return nil }
        let range = NSRange(tag.startIndex ..< tag.endIndex, in: tag)
        guard let match = expression.firstMatch(in: tag, range: range),
              let captured = Range(match.range(at: 1), in: tag)
        else { return nil }
        return String(tag[captured])
    }

    static func media(in html: String) -> [JiraDescriptionMedia] {
        guard let mediaTag else { return [] }

        let range = NSRange(html.startIndex ..< html.endIndex, in: html)
        var found: [JiraDescriptionMedia] = []
        var seen: Set<String> = []

        for match in mediaTag.matches(in: html, range: range) {
            guard let tagRange = Range(match.range, in: html) else { continue }
            let tag = String(html[tagRange])
            guard let id = attachmentID(in: tag), seen.contains(id) == false else { continue }
            seen.insert(id)

            let type = attribute("type", in: tag)?.lowercased() ?? ""
            let kind: JiraDescriptionMedia.Kind = if tag.lowercased().hasPrefix("<img") {
                .image
            } else if type.hasPrefix("video/") {
                .video
            } else if type.hasPrefix("image/") {
                .image
            } else {
                .other
            }

            found.append(
                JiraDescriptionMedia(
                    attachmentID: id,
                    kind: kind,
                    width: attribute("width", in: tag).flatMap(Int.init),
                    height: attribute("height", in: tag).flatMap(Int.init)
                )
            )
        }
        return found
    }
}

struct JiraRenderedFieldsResponse: Decodable {
    let renderedFields: RenderedFields?

    struct RenderedFields: Decodable {
        let description: String?
    }

    var descriptionMedia: [JiraDescriptionMedia] {
        JiraRenderedDescription.media(in: renderedFields?.description ?? "")
    }
}

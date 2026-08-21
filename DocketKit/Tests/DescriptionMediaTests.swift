//  DescriptionMediaTests.swift
//  DocketKitTests

import Foundation
import Testing

@testable import DocketKit

@Suite("Finding the media a description embeds")
struct DescriptionMediaTests {
    @Test("An image names the attachment behind it")
    func readsImage() {
        let html = """
        <p>Actual Result</p>
        <p><span class="image-wrap"><img src="/rest/api/3/attachment/thumbnail/54451?default=false" \
        width="266" height="218" /></span></p>
        """

        let media = JiraRenderedDescription.media(in: html)

        #expect(media.count == 1)
        #expect(media.first?.attachmentID == "54451")
        #expect(media.first?.kind == .image)
        #expect(media.first?.width == 266)
        #expect(media.first?.height == 218)
    }

    /// The shape Jira actually returned for APP-27098, whose description holds a screen
    /// recording: the nested param and embed repeat the same address.
    @Test("A video is read once, from the outer tag")
    func readsVideoOnce() {
        let html = """
        <p><div class="embeddedObject"><object classid="clsid:02BF25D5" \
        data="/rest/api/3/attachment/content/70664?stream=true" height="380" \
        type="video/quicktime" width="454" ><param name="data" \
        value="/rest/api/3/attachment/content/70664?stream=true"/><param name="src" \
        value="/rest/api/3/attachment/content/70664?stream=true"/><embed height="380" \
        src="/rest/api/3/attachment/content/70664?stream=true" type="video/quicktime" \
        width="454" /></object></div></p>
        """

        let media = JiraRenderedDescription.media(in: html)

        #expect(media.map(\.attachmentID) == ["70664"])
        #expect(media.first?.kind == .video)
    }

    @Test("Several files keep the order they appear in")
    func keepsDocumentOrder() {
        let html = """
        <img src="/rest/api/3/attachment/thumbnail/1" />
        <object data="/rest/api/3/attachment/content/2?stream=true" type="video/mp4"></object>
        <img src="/rest/api/3/attachment/thumbnail/3" />
        """

        let media = JiraRenderedDescription.media(in: html)

        #expect(media.map(\.attachmentID) == ["1", "2", "3"])
        #expect(media.map(\.kind) == [.image, .video, .image])
    }

    @Test("Text with no attachments yields nothing", arguments: [
        "<p>Just a sentence.</p>",
        "",
        "<p><a href=\"https://example.atlassian.net/browse/APP-1\">APP-1</a></p>",
        "<img src=\"https://secure.gravatar.com/avatar/33abf1\" />",
    ])
    func ignoresEverythingElse(html: String) {
        #expect(JiraRenderedDescription.media(in: html).isEmpty)
    }
}

@Suite("Numbering media in a description")
struct ADFMediaBlockTests {
    private func blocks(_ json: String) -> [ADFBlock] {
        let value = try? JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        return ADFDocument.blocks(from: value)
    }

    @Test("Each file is a numbered place, wrappers are not")
    func numbersEachFile() {
        let found = blocks("""
        {"type":"doc","content":[
          {"type":"paragraph","content":[{"type":"text","text":"Before"}]},
          {"type":"mediaSingle","content":[{"type":"media","attrs":{"id":"aaa","type":"file"}}]},
          {"type":"mediaGroup","content":[
            {"type":"media","attrs":{"id":"bbb","type":"file"}},
            {"type":"media","attrs":{"id":"ccc","type":"file"}}
          ]}
        ]}
        """)

        #expect(found == [
            .paragraph([ADFSpan(text: "Before")]),
            .media(index: 0),
            .media(index: 1),
            .media(index: 2),
        ])
    }

    @Test("A table still stands aside, so its images are not numbered")
    func tableStaysUnsupported() {
        let found = blocks("""
        {"type":"doc","content":[
          {"type":"table","content":[{"type":"tableRow","content":[
            {"type":"tableCell","content":[{"type":"mediaSingle","content":[
              {"type":"media","attrs":{"id":"aaa","type":"file"}}]}]}]}]}
        ]}
        """)

        // The count no longer matches what Jira rendered, which is what makes the view fall
        // back to showing the images below the text instead of inside it.
        #expect(found == [.unsupported(kind: "table")])
    }
}

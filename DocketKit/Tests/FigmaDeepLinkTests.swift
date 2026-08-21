//  FigmaDeepLinkTests.swift
//  DocketKitTests

import Foundation
import Testing

@testable import DocketKit

@Suite("Opening a Figma link in the app")
struct FigmaDeepLinkTests {
    private func appURL(_ address: String) -> URL? {
        FigmaDeepLink.appURL(for: URL(string: address)!)
    }

    @Test("A design link keeps its file, name and frame")
    func keepsFrame() throws {
        let url = try #require(appURL(
            "https://www.figma.com/design/2rKx6XGOJDlEXRO7SqFoJn/Driver-App_Master?node-id=133114-2&m=dev"
        ))

        #expect(url.absoluteString == "figma://design/2rKx6XGOJDlEXRO7SqFoJn/Driver-App_Master?node-id=133114-2&m=dev")
    }

    @Test("The older /file/ form is left as it is, since the app claims both")
    func keepsFileKind() throws {
        let url = try #require(appURL("https://www.figma.com/file/ABC123abc456DEF789ghi0/Rider-App?node-id=1-2"))

        #expect(url.absoluteString == "figma://file/ABC123abc456DEF789ghi0/Rider-App?node-id=1-2")
    }

    @Test("A file without a name still opens")
    func nameIsOptional() throws {
        let url = try #require(appURL("https://www.figma.com/design/2rKx6XGOJDlEXRO7SqFoJn"))

        #expect(url.absoluteString == "figma://design/2rKx6XGOJDlEXRO7SqFoJn")
    }

    @Test("Pages the app has no view for stay in the browser", arguments: [
        "https://www.figma.com/files/recent",
        "https://www.figma.com/",
        "https://www.figma.com/board/XYZ/FigJam-Board",
        "https://www.figma.com/proto/XYZ/Prototype",
        "https://notfigma.com/design/2rKx6XGOJDlEXRO7SqFoJn/Driver-App_Master",
        "https://example.atlassian.net/browse/APP-22628",
    ])
    func staysInBrowser(address: String) {
        #expect(appURL(address) == nil, "\(address) should stay in the browser")
    }
}

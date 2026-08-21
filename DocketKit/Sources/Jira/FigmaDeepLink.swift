//  FigmaDeepLink.swift
//  DocketKit

import Foundation

/// Turns a Figma web address into the one that opens the desktop app.
///
/// Figma registers only the `figma://` scheme and claims no associated domain, so a
/// `figma.com` link always goes to the browser unless the scheme is swapped. Path and query
/// carry over unchanged, which is what keeps `node-id` pointing at the same frame.
public enum FigmaDeepLink {
    /// Document paths only. `/files/recent`, settings and the rest of the site are pages the
    /// app has no view for.
    private static let documentKinds: Set<String> = ["design", "file"]

    /// `nil` when the address is not a Figma document, in which case the caller keeps it.
    public static func appURL(for webURL: URL) -> URL? {
        guard var components = URLComponents(url: webURL, resolvingAgainstBaseURL: false),
              isFigmaHost(components.host)
        else { return nil }

        let path = components.path.split(separator: "/").map(String.init)
        // A document is /<kind>/<key>/<name>; the name is optional.
        guard path.count >= 2, documentKinds.contains(path[0]) else { return nil }

        components.scheme = "figma"
        components.host = path[0]
        components.path = "/" + path.dropFirst().joined(separator: "/")
        return components.url
    }

    /// A suffix match alone would accept `notfigma.com`, so the boundary has to be a dot.
    private static func isFigmaHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "figma.com" || host.hasSuffix(".figma.com")
    }
}

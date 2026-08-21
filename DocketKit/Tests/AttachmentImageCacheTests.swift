//  AttachmentImageCacheTests.swift
//  DocketKitTests

import AppKit
import Foundation
import Testing

@testable import DocketKit

@MainActor
@Suite("Caching attachment images")
struct AttachmentImageCacheTests {
    /// A real PNG, so the cache measures a real decoded size.
    private func pngData(side: Int) -> Data {
        let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: side,
            pixelsHigh: side,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        return representation.representation(using: .png, properties: [:])!
    }

    /// Counts what the cache actually asked for.
    @MainActor
    private final class Loader {
        var calls = 0
        var data: Data
        var delay: Duration?

        init(data: Data, delay: Duration? = nil) {
            self.data = data
            self.delay = delay
        }

        func load() async -> Data? {
            calls += 1
            if let delay {
                try? await Task.sleep(for: delay)
            }
            return data
        }
    }

    @Test("A second read comes from memory")
    func servesFromMemory() async {
        let cache = AttachmentImageCache()
        let loader = Loader(data: pngData(side: 8))

        let first = await cache.image(site: "example.atlassian.net", attachmentID: "1", thumbnail: true) {
            await loader.load()
        }
        let second = await cache.image(site: "example.atlassian.net", attachmentID: "1", thumbnail: true) {
            await loader.load()
        }

        #expect(first != nil)
        #expect(second != nil)
        #expect(loader.calls == 1)
    }

    @Test("The same id on another site is another file, and is fetched again")
    func siteScopesTheKey() async {
        let cache = AttachmentImageCache()
        let loader = Loader(data: pngData(side: 8))

        _ = await cache.image(site: "example.atlassian.net", attachmentID: "54451", thumbnail: true) {
            await loader.load()
        }
        _ = await cache.image(site: "other.atlassian.net", attachmentID: "54451", thumbnail: true) {
            await loader.load()
        }

        #expect(loader.calls == 2)
    }

    @Test("A thumbnail and its full-size copy are separate entries")
    func sizeScopesTheKey() async {
        let cache = AttachmentImageCache()
        let loader = Loader(data: pngData(side: 8))

        _ = await cache.image(site: "s", attachmentID: "1", thumbnail: true) { await loader.load() }
        _ = await cache.image(site: "s", attachmentID: "1", thumbnail: false) { await loader.load() }

        #expect(loader.calls == 2)
    }

    @Test("Two readers wanting the same image download it once")
    func coalescesConcurrentReads() async {
        let cache = AttachmentImageCache()
        let loader = Loader(data: pngData(side: 8), delay: .milliseconds(100))

        // Tasks rather than `async let`: both start on this actor, and the first suspends in
        // its sleep, which is when the second must find it and join instead of fetching.
        // The tasks carry a Bool because NSImage cannot cross a Task boundary.
        let first = Task { await cache.image(site: "s", attachmentID: "1", thumbnail: true) { await loader.load() } != nil }
        let second = Task { await cache.image(site: "s", attachmentID: "1", thumbnail: true) { await loader.load() } != nil }
        let loaded = await [first.value, second.value]

        #expect(loaded.allSatisfy { $0 })
        #expect(loader.calls == 1)
    }

    @Test("What is kept is bounded by decoded size, not by count")
    func evictsByCost() async {
        // Two 100x100 images fit; the third pushes the first out.
        let oneImage = 100 * 100 * 4
        let cache = AttachmentImageCache(costLimit: oneImage * 2)
        let loader = Loader(data: pngData(side: 100))

        for id in ["1", "2", "3"] {
            _ = await cache.image(site: "s", attachmentID: id, thumbnail: false) { await loader.load() }
        }
        // Reading the oldest again has to fetch, the newest does not.
        _ = await cache.image(site: "s", attachmentID: "1", thumbnail: false) { await loader.load() }
        _ = await cache.image(site: "s", attachmentID: "3", thumbnail: false) { await loader.load() }

        #expect(loader.calls == 4)
    }

    @Test("Reading an image keeps it from being the next one dropped")
    func readingRefreshesOrder() async {
        let oneImage = 100 * 100 * 4
        let cache = AttachmentImageCache(costLimit: oneImage * 2)
        let loader = Loader(data: pngData(side: 100))

        _ = await cache.image(site: "s", attachmentID: "1", thumbnail: false) { await loader.load() }
        _ = await cache.image(site: "s", attachmentID: "2", thumbnail: false) { await loader.load() }
        _ = await cache.image(site: "s", attachmentID: "1", thumbnail: false) { await loader.load() }
        // 1 was just read, so 2 is the one to go.
        _ = await cache.image(site: "s", attachmentID: "3", thumbnail: false) { await loader.load() }

        #expect(loader.calls == 3)
        _ = await cache.image(site: "s", attachmentID: "1", thumbnail: false) { await loader.load() }
        #expect(loader.calls == 3, "1 should still be resident")
    }

    @Test("A failed fetch is not remembered as an image")
    func failureIsNotCached() async {
        let cache = AttachmentImageCache()
        var calls = 0

        for _ in 0 ..< 2 {
            let image = await cache.image(site: "s", attachmentID: "1", thumbnail: true) {
                calls += 1
                return nil
            }
            #expect(image == nil)
        }
        #expect(calls == 2)
    }

    @Test("Nothing survives a clear")
    func clearDropsEverything() async {
        let cache = AttachmentImageCache()
        let loader = Loader(data: pngData(side: 8))

        _ = await cache.image(site: "s", attachmentID: "1", thumbnail: true) { await loader.load() }
        cache.removeAll()
        _ = await cache.image(site: "s", attachmentID: "1", thumbnail: true) { await loader.load() }

        #expect(loader.calls == 2)
    }

    @Test("Cost is the pixels, not the bytes that arrived")
    func costIsDecodedSize() throws {
        let image = try #require(NSImage(data: pngData(side: 100)))

        #expect(AttachmentImageCache.cost(of: image) == 100 * 100 * 4)
    }
}

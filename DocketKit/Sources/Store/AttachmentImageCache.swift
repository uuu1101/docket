//  AttachmentImageCache.swift
//  DocketKit

import AppKit
import Foundation

/// Jira attachment images, held in memory only.
///
/// A ticket's screenshots are as sensitive as the ticket, so nothing is written to disk. What
/// is kept is bounded by decoded size rather than by count: a thumbnail costs kilobytes and a
/// full-size screenshot tens of megabytes, and counting them the same lets a handful of
/// originals hold hundreds of megabytes.
@MainActor
public final class AttachmentImageCache {
    /// Attachment ids are per-site numbers — id 54451 names a different file on another Jira
    /// site — so the site belongs in the key or a site change serves the wrong picture.
    private struct Key: Hashable {
        let site: String
        let attachmentID: String
        let thumbnail: Bool
    }

    private var images: [Key: NSImage] = [:]
    /// Least recently used first.
    private var order: [Key] = []
    /// The tasks carry bytes rather than images: `NSImage` is not Sendable, so it cannot
    /// be a `Task`'s success type under strict concurrency. Decoding happens back on this
    /// actor once the bytes arrive.
    private var inflight: [Key: Task<Data?, Never>] = [:]
    private var cost = 0

    private let costLimit: Int

    public init(costLimit: Int = 96 << 20) {
        self.costLimit = costLimit
    }

    /// Returns the cached image, joins a fetch already running for it, or starts one.
    public func image(
        site: String,
        attachmentID: String,
        thumbnail: Bool,
        load: @escaping @MainActor () async -> Data?
    ) async -> NSImage? {
        let key = Key(site: site, attachmentID: attachmentID, thumbnail: thumbnail)

        if let cached = images[key] {
            touch(key)
            return cached
        }
        // Two views can want the same image at once — a thumbnail and the sheet opened over
        // it — and downloading it twice serves neither faster. The first completer stores
        // the decoded image, so joiners usually find it in the cache.
        if let running = inflight[key] {
            guard let data = await running.value else { return nil }
            if let cached = images[key] {
                touch(key)
                return cached
            }
            return NSImage(data: data)
        }

        // The task inherits this actor, which is what lets the caller's loader stay
        // main-actor bound instead of having to be Sendable.
        let task = Task { @MainActor () -> Data? in
            await load()
        }
        inflight[key] = task
        let data = await task.value
        inflight[key] = nil

        guard let data, let image = NSImage(data: data) else { return nil }
        store(image, for: key)
        return image
    }

    /// Called when the site changes: what was cached belongs to a different Jira.
    public func removeAll() {
        images.removeAll()
        order.removeAll()
        inflight.values.forEach { $0.cancel() }
        inflight.removeAll()
        cost = 0
    }

    private func store(_ image: NSImage, for key: Key) {
        images[key] = image
        order.append(key)
        cost += Self.cost(of: image)

        while cost > costLimit, let oldest = order.first {
            order.removeFirst()
            if let dropped = images.removeValue(forKey: oldest) {
                cost -= Self.cost(of: dropped)
            }
        }
    }

    private func touch(_ key: Key) {
        guard let index = order.firstIndex(of: key) else { return }
        order.remove(at: index)
        order.append(key)
    }

    /// What the image costs once decoded, which is the pixels rather than the bytes that
    /// arrived: a 200KB screenshot occupies tens of megabytes as a bitmap.
    static func cost(of image: NSImage) -> Int {
        let pixels = image.representations.reduce(0) { largest, representation in
            max(largest, representation.pixelsWide * representation.pixelsHigh)
        }
        return max(pixels, 1) * 4
    }
}

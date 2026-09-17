import AppKit
import QuickLookThumbnailing
import UniformTypeIdentifiers

/// Bounded in-memory cache of Finder-style previews (QuickLook thumbnails with icon decoration).
///
/// Generation runs in the system's QuickLook thumbnail agent, a separate process that does NOT
/// inherit the dataless-file I/O policy set in main.swift. So before anything is handed to
/// QuickLook, the file is checked (off the main thread) to be fully local (`isFullyLocal`) and of
/// a kind Finder would preview (`isEligible`). Files that fail either check, or whose generation
/// fails, are remembered as negative results until `invalidate`/`removeAll`.
///
/// Threading: the public methods are main-thread only; checks and bitmap copies happen on
/// background queues; state is mutated on the main queue only; `onReady` fires on the main queue.
/// No timers, no polling: work happens only in response to `thumbnail(for:)` calls and to
/// QuickLook completions.
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    /// Called on the main queue when a thumbnail that was previously reported nil becomes available.
    var onReady: ((URL) -> Void)?

    // MARK: - Tunables

    /// Maximum number of QuickLook requests outstanding at once (including the local pre-checks).
    private let maxInFlight = 6
    /// Cache bounds: whichever is hit first evicts the oldest entries.
    private let maxEntries = 500
    private let maxBytes = 32 << 20
    /// Negative results are cheap (a key each) but still bounded.
    private let maxNegative = 2000

    // MARK: - State (main queue only)

    /// Cache key: path | size (points) | scale (backing scale, 1 or 2).
    private struct Key: Hashable {
        let path: String
        let size: Int
        let scale: Int

        init(url: URL, size: CGFloat, scale: CGFloat) {
            path = url.path
            // Clamped so a bogus size/scale can neither trap Int() (NaN/inf) nor request a huge bitmap.
            self.size = Int(min(max(size.isFinite ? size.rounded() : 0, 0), 1024))
            self.scale = Int(min(max(scale.isFinite ? scale.rounded() : 1, 1), 4))
        }
    }

    private struct Entry {
        let image: NSImage
        let bytes: Int
    }

    /// One outstanding generation. Identity is used to discard completions of cancelled jobs.
    private final class Job {
        let key: Key
        let url: URL
        let size: CGFloat
        let scale: CGFloat
        var request: QLThumbnailGenerator.Request?

        init(key: Key, url: URL, size: CGFloat, scale: CGFloat) {
            self.key = key
            self.url = url
            self.size = size
            self.scale = scale
        }
    }

    private var entries: [Key: Entry] = [:]
    private var order: [Key] = []       // insertion order for eviction (oldest at `orderHead`)
    private var orderHead = 0
    private var totalBytes = 0
    private var negative: Set<Key> = []
    private var inFlight: [Key: Job] = [:]
    private var pending: [Job] = []     // FIFO of jobs waiting for an in-flight slot
    private var pendingHead = 0
    private var pendingKeys: Set<Key> = []

    /// Serial background queue for the local pre-checks (metadata reads only).
    private let checkQueue = DispatchQueue(label: "dev.quietdesk.ThumbnailCache.check", qos: .utility)
    private let generator = QLThumbnailGenerator.shared

    private init() {}

    // MARK: - Public API (main thread)

    /// Returns the cached preview at `size` points for the given backing `scale` (1 or 2), or nil.
    /// When nil and the file is eligible, generation is started (bounded concurrency) and onReady fires later.
    /// Never blocks; never reads file contents on the calling thread.
    func thumbnail(for url: URL, size: CGFloat, scale: CGFloat) -> NSImage? {
        assert(Thread.isMainThread)
        let key = Key(url: url, size: size, scale: scale)
        if let entry = entries[key] { return entry.image }
        if negative.contains(key) { return nil }
        if inFlight[key] != nil || pendingKeys.contains(key) { return nil }

        // The request uses the key's normalised size/scale (whole points, scale >= 1) so the
        // cached entry and the QuickLook request always agree and scale can never be 0.
        let job = Job(key: key, url: url, size: CGFloat(key.size), scale: CGFloat(key.scale))
        pending.append(job)
        pendingKeys.insert(key)
        pump()
        return nil
    }

    /// Forget one file (e.g. after it changed) or everything.
    func invalidate(_ url: URL) {
        assert(Thread.isMainThread)
        let path = url.path
        for key in entries.keys where key.path == path { remove(key) }
        dropFromOrder { $0.path == path }
        negative = negative.filter { $0.path != path }
        for (key, job) in inFlight where key.path == path {
            inFlight[key] = nil
            if let request = job.request { generator.cancel(request) }
        }
        if pendingKeys.contains(where: { $0.path == path }) {
            dropFromPending { $0.key.path == path }
            pendingKeys = pendingKeys.filter { $0.path != path }
        }
        pump()
    }

    func removeAll() {
        assert(Thread.isMainThread)
        cancelAll()
        entries.removeAll()
        order.removeAll()
        orderHead = 0
        totalBytes = 0
        negative.removeAll()
    }

    /// Cancels pending generation (e.g. when the overlay is disabled). Cached results are kept.
    func cancelAll() {
        assert(Thread.isMainThread)
        for job in inFlight.values {
            if let request = job.request { generator.cancel(request) }
        }
        inFlight.removeAll()
        pending.removeAll()
        pendingHead = 0
        pendingKeys.removeAll()
    }

    /// Diagnostics only (e.g. for --dump output): current sizes of the internal tables.
    var statistics: (cached: Int, bytes: Int, negative: Int, inFlight: Int, pending: Int) {
        (entries.count, totalBytes, negative.count, inFlight.count, pendingKeys.count)
    }

    // MARK: - Local checks (metadata only; safe to call from any thread)

    /// True when reading the file cannot trigger a cloud download: not a dataless file (SF_DATALESS in st_flags via stat, see Apple TN3150) and,
    /// if it is an iCloud item, its ubiquitousItemDownloadingStatus is .current or .downloaded.
    static func isFullyLocal(_ url: URL) -> Bool {
        // lstat() reads metadata only and does not materialize the file itself (TN3150). stat()
        // and getattrlist() DO materialize dataless *intermediate* folders in the path they
        // resolve, so a symlink is never followed here: its target has not been checked, and a
        // symlink is rejected by isEligible anyway (reviewer hardening; the app's process-wide
        // dataless-file policy in main.swift would already turn such a stat into EDEADLK).
        var st = stat()
        guard lstat(url.path, &st) == 0 else { return false }
        if (st.st_mode & S_IFMT) == S_IFLNK { return false }
        if st.st_flags & UInt32(SF_DATALESS) != 0 { return false }

        let keys: Set<URLResourceKey> = [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return false }
        if values.isUbiquitousItem == true {
            guard let status = values.ubiquitousItemDownloadingStatus else { return false }
            return status == .current || status == .downloaded
        }
        return true
    }

    /// Root types QuickLook can thumbnail and Finder shows previews for. Anything else keeps its
    /// plain type icon (archives, disk images, executables, unknown data...).
    private static let previewableTypes: [UTType] = [
        .image, .pdf, .audiovisualContent, .text, .rtf, .rtfd,
        .compositeContent, .presentation, .spreadsheet, .font, .epub,
    ]

    /// 3D content is admitted only as a self-contained .usdz archive. The QuickLook agent thumbnails
    /// other 3D formats (.obj + .mtl, .usd/.usda, .dae) by opening the material and texture files
    /// they name by relative path; those siblings were never checked by `isFullyLocal`, and the
    /// agent does not carry this process's dataless-file policy, so a cloud-evicted texture next to
    /// an .obj would be downloaded. (Reviewer check, macOS 26.6: an .obj and a .usda referencing a
    /// sibling PNG made the agent read that PNG; .html, .svg, .md, .rtf and .csv referencing a sibling
    /// did not.)
    private static let selfContained3DTypes: [UTType] = [.usdz]

    /// Pure type test behind `isEligible`: whether QuickLook previews of this content type are wanted.
    /// Callers that already hold the item's content type (and know it is a regular, non-package,
    /// non-alias file) can use this without any file-system access.
    static func isPreviewable(_ type: UTType) -> Bool {
        if type.conforms(to: .threeDContent) { return selfContained3DTypes.contains { type.conforms(to: $0) } }
        return previewableTypes.contains { type.conforms(to: $0) }
    }

    /// True for files Finder would show a preview for: regular files (not folders, not packages/apps) whose type QuickLook can thumbnail
    /// (images, PDF, movies, audio, text/documents...). Folders, packages and apps return false.
    static func isEligible(_ url: URL) -> Bool {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .isPackageKey, .isAliasFileKey, .contentTypeKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return false }
        if values.isDirectory == true || values.isPackage == true || values.isAliasFile == true { return false }
        guard values.isRegularFile == true, let type = values.contentType else { return false }
        return isPreviewable(type)
    }

    // MARK: - Pipeline (main queue)

    /// Moves jobs from the FIFO into in-flight slots.
    private func pump() {
        while inFlight.count < maxInFlight, pendingHead < pending.count {
            let job = pending[pendingHead]
            pendingHead += 1
            if pendingHead > 64 || pendingHead == pending.count {
                pending.removeFirst(pendingHead)
                pendingHead = 0
            }
            pendingKeys.remove(job.key)
            inFlight[job.key] = job
            start(job)
        }
    }

    private func start(_ job: Job) {
        // Step 1: local pre-checks on a background queue (metadata reads only).
        checkQueue.async { [weak self] in
            let allowed = ThumbnailCache.isFullyLocal(job.url) && ThumbnailCache.isEligible(job.url)
            DispatchQueue.main.async {
                guard let self, self.inFlight[job.key] === job else { return }   // cancelled meanwhile
                if allowed {
                    self.generate(job)
                } else {
                    self.finish(job, image: nil, bytes: 0)
                }
            }
        }
    }

    /// Step 2: hand the file to QuickLook. Only reached for fully local, previewable files.
    private func generate(_ job: Job) {
        let request = QLThumbnailGenerator.Request(
            fileAt: job.url,
            size: CGSize(width: job.size, height: job.size),
            scale: job.scale,
            representationTypes: .thumbnail)
        request.iconMode = true   // Finder-style decoration (frame, page curl, shadow as appropriate)
        job.request = request
        generator.generateBestRepresentation(for: request) { [weak self] representation, error in
            // Arbitrary queue. Copy the pixels into a small bitmap we own before hopping to main.
            var image: NSImage?
            var bytes = 0
            if let cg = representation?.cgImage {
                (image, bytes) = ThumbnailCache.ownedBitmap(from: cg, scale: job.scale)
            }
            let cancelled = (error as? QLThumbnailError)?.code == .requestCancelled
            DispatchQueue.main.async {
                guard let self, self.inFlight[job.key] === job else { return }
                if cancelled && image == nil {
                    // Cancelled by the system rather than by us (we drop cancelled jobs from
                    // inFlight first): do not remember as a failure; a later call can retry.
                    self.inFlight[job.key] = nil
                    self.pump()
                    return
                }
                self.finish(job, image: image, bytes: bytes)
            }
        }
    }

    private func finish(_ job: Job, image: NSImage?, bytes: Int) {
        inFlight[job.key] = nil
        if let image {
            insert(Entry(image: image, bytes: bytes), for: job.key)
            onReady?(job.url)
        } else {
            if negative.count >= maxNegative { negative.removeAll() }
            negative.insert(job.key)
        }
        pump()
    }

    // MARK: - Storage

    private func insert(_ entry: Entry, for key: Key) {
        if entries[key] != nil {
            remove(key)
            dropFromOrder { $0 == key }
        }
        entries[key] = entry
        order.append(key)
        totalBytes += entry.bytes
        // Never evict the entry just inserted (order.last): if a single result exceeded maxBytes,
        // evicting it would make the caller's next thumbnail(for:) miss and regenerate forever.
        while (entries.count > maxEntries || totalBytes > maxBytes), orderHead < order.count - 1 {
            let oldest = order[orderHead]
            orderHead += 1
            remove(oldest)
        }
        if orderHead > 256 {
            order.removeFirst(orderHead)
            orderHead = 0
        }
    }

    private func remove(_ key: Key) {
        guard let entry = entries.removeValue(forKey: key) else { return }
        totalBytes -= entry.bytes
    }

    /// Removes matching keys from the eviction order. The consumed prefix [0, orderHead) is
    /// dropped first so the head index stays valid after a removal from the middle.
    private func dropFromOrder(where predicate: (Key) -> Bool) {
        if orderHead > 0 { order.removeFirst(orderHead); orderHead = 0 }
        order.removeAll(where: predicate)
    }

    /// Same for the pending FIFO and its consumed prefix [0, pendingHead).
    private func dropFromPending(where predicate: (Job) -> Bool) {
        if pendingHead > 0 { pending.removeFirst(pendingHead); pendingHead = 0 }
        pending.removeAll(where: predicate)
    }

    /// Copies a QuickLook result into a bitmap this process owns, at the result's pixel size,
    /// wrapped in an NSImage whose point size matches `scale`.
    private static func ownedBitmap(from source: CGImage, scale: CGFloat) -> (NSImage?, Int) {
        let width = source.width, height = source.height
        guard width > 0, height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return (nil, 0) }
        context.interpolationQuality = .none
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let copy = context.makeImage() else { return (nil, 0) }
        let points = NSSize(width: CGFloat(width) / scale, height: CGFloat(height) / scale)
        return (NSImage(cgImage: copy, size: points), context.bytesPerRow * height)
    }
}

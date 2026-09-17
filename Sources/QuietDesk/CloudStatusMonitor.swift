import Foundation
import CoreServices   // FSEvents (public CoreServices API; imported explicitly so the dependency is visible)

/// iCloud sync state of one desktop item, as Finder would badge it.
enum CloudStatus: Equatable {
    case notInCloud            // local item, no glyph
    case current               // in iCloud and fully downloaded/up to date (Finder shows a small cloud glyph or nothing; report what Apple's keys say)
    case notDownloaded         // cloud-only, evicted (cloud with down arrow)
    case downloading(Double)   // 0...1
    case uploading(Double)     // 0...1
    case notUploaded           // waiting to upload
    case error
}

/// Event-driven iCloud status for the items directly inside `directory` (the user's Desktop).
///
/// Why this is not built on NSMetadataQuery (measured on macOS 26.6.2, Command Line Tools build,
/// process without an iCloud entitlement; probe in the scratch package next to the harness):
/// - A directory-URL search scope is accepted (and `searchItems` limits it to the top level), but
///   the results come from the Spotlight index, which carries no ubiquity attributes here: every
///   `NSMetadataUbiquitousItem*` key and `NSMetadataItemIsUbiquitousKey` is nil for every item, as
///   are the attributes of `NSMetadataItem(url:)`. The recursive directory scope also returned
///   196,764 items for this Desktop (about 90 MB resident), since `kMDItemPath` cannot be used in
///   a predicate to limit the depth. (`%K LIKE '*'` matched nothing; `%K != ''` matched everything.)
/// - `NSMetadataQueryUbiquitousDocumentsScope`, `...DataScope` and
///   `...AccessibleUbiquitousExternalDocumentsScope` return zero results: they cover the app's
///   own iCloud container, which needs an entitlement, and never the user's iCloud Drive.
///
/// What is used instead (public, documented, in-process; nothing runs at idle):
/// - Truth: URL resource values (`isUbiquitousItemKey`, `ubiquitousItemDownloadingStatusKey`,
///   `...IsDownloading` / `...IsUploading` / `...IsUploaded`, `...DownloadingError` /
///   `...UploadingError`). Reading them touches metadata only; with the process I/O policy set in
///   main.swift nothing in this process can materialize a dataless file anyway.
/// - Push channels, all delivered to the main queue:
///   1. An FSEvents file-level stream on the directory (kernel-fed). Downloads fill a file in
///      place and evictions change its attributes; events at any depth are mapped to the
///      top-level item they belong to, and only that item's resource values are re-read.
///   2. An NSFilePresenter for the directory: coordinated changes made by other processes
///      (sub-item changed, appeared, moved), which is how the system daemons and Finder write.
///   3. An NSFilePresenter for each item that is in transit (waiting to upload, uploading,
///      downloading, or in error), because `presentedItemDidChangeUbiquityAttributes(_:)` is the
///      documented way to hear that a file's iCloud attributes changed; it is removed again once
///      the item is stable, so the number of presenters stays bounded by items in flight.
///   4. A `Progress` file-URL subscription for the directory: the system invokes it for progress
///      published for the directory's direct children (the mechanism Finder uses for its download
///      pies). Percentages come only from there; resource values have no percent keys.
///   Every notification-only presenter method is implemented and nothing with a completion
///   handler, so no coordinated reader or writer ever waits on this process.
/// - Not verifiable without triggering a download (which this project never does): whether the
///   iCloud daemon publishes `Progress` for Desktop items and whether it coordinates its writes.
///   If it does neither, a transfer in progress is still reported as .downloading(0) /
///   .uploading(0) from the resource keys, and the item is re-read when FSEvents sees it change.
///
/// Threading: call `start`, `stop` and `status(for:)` on the main thread; `onChange` is invoked on
/// the main queue. Resource values are read on a private utility queue and applied on main.
final class CloudStatusMonitor {

    // MARK: Public interface

    init(directory: URL) {
        let standardized = directory.standardizedFileURL
        self.directory = standardized
        self.directoryPath = standardized.path
        var aliases: Set<String> = [standardized.path, standardized.resolvingSymlinksInPath().path]
        if let real = realpath(standardized.path, nil) {
            aliases.insert(String(cString: real))
            free(real)
        }
        self.directoryAliases = aliases
        let queue = OperationQueue()
        queue.name = "dev.quietdesk.CloudStatusMonitor.presenters"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .utility
        self.presenterQueue = queue
    }

    deinit {
        tearDownEventSources()
    }

    /// Main-queue callback fired when any status changed (coalesced).
    var onChange: (() -> Void)?

    /// Diagnostics only (nil in the app): a terse line per event, on the main queue.
    var diagnostics: ((String) -> Void)?

    func start() {
        guard !isRunning else { return }
        isRunning = true
        generation &+= 1
        startFSEvents()
        let presenter = DirectoryPresenter(url: directory, queue: presenterQueue, monitor: self)
        NSFileCoordinator.addFilePresenter(presenter)
        directoryPresenter = presenter
        for url in progressSubscriptionURLs() {
            progressSubscriptions.append(Progress.addSubscriber(forFileURL: url) { [weak self] progress in
                guard let self, self.isRunning else { return nil }
                return self.handlePublished(progress)
            })
        }
        // Initial snapshot, off the main thread; onChange fires when it has been applied.
        pendingFull = true
        performRefresh()
    }

    /// Stops every event source and forgets all state. Safe to call twice.
    func stop() {
        guard isRunning else { return }
        isRunning = false
        generation &+= 1
        tearDownEventSources()
        statuses.removeAll()
        transfers.removeAll()
        pendingNames.removeAll()
        pendingFull = false
        refreshInFlight = false
        // A debounce armed before stop() belongs to the old generation; its closure exits on the
        // generation check without touching this flag, so clear it here or no refresh could ever be
        // armed again after a restart.
        refreshArmed = false
    }

    /// Last known status; .notInCloud when unknown/not ubiquitous.
    func status(for url: URL) -> CloudStatus {
        guard isRunning, let name = itemName(for: url) else { return .notInCloud }
        let base = statuses[name] ?? .notInCloud
        guard let transfer = transfers[name] else { return base }
        if case .error = base { return base }
        let fraction = transfer.fraction
        switch transfer.kind {
        case .uploading: return .uploading(fraction)
        case .downloading: return .downloading(fraction)
        case nil:
            // Kind unknown: trust it only while the resource keys already report a transfer.
            switch base {
            case .uploading, .notUploaded: return .uploading(fraction)
            case .downloading: return .downloading(fraction)
            default: return base
            }
        default: return base   // copying, receiving, decompressing: not a sync transfer
        }
    }

    /// One-shot, synchronous status from URL resource values (fallback when the query has not gathered yet).
    /// Resource values carry no percentage, so a transfer in progress reports 0.
    static func resourceStatus(for url: URL) -> CloudStatus {
        let fresh = URL(fileURLWithPath: url.path)   // a new URL instance: no cached resource values
        guard let values = try? fresh.resourceValues(forKeys: resourceKeys) else { return .notInCloud }
        return status(from: values)
    }

    // MARK: State (main thread unless noted)

    private let directory: URL
    private let directoryPath: String
    private let directoryAliases: Set<String>
    private let presenterQueue: OperationQueue
    private let workQueue = DispatchQueue(label: "dev.quietdesk.CloudStatusMonitor", qos: .utility)
    private let debounce: TimeInterval = 0.25

    private var isRunning = false
    private var generation = 0
    private var statuses: [String: CloudStatus] = [:]        // item name -> resource-value status
    private var transfers: [String: TransferProgress] = [:]  // item name -> live published progress

    private var stream: FSEventStreamRef?
    private var directoryPresenter: DirectoryPresenter?
    private var itemPresenters: [String: ItemPresenter] = [:]
    private var progressSubscriptions: [Any] = []

    private var pendingNames = Set<String>()
    private var pendingFull = false
    private var refreshArmed = false
    private var refreshInFlight = false
    private var changeNotificationScheduled = false

    fileprivate static let resourceKeys: Set<URLResourceKey> = [
        .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey,
        .ubiquitousItemIsDownloadingKey, .ubiquitousItemIsUploadingKey, .ubiquitousItemIsUploadedKey,
        .ubiquitousItemDownloadingErrorKey, .ubiquitousItemUploadingErrorKey,
    ]

    private final class CallbackBox {
        weak var monitor: CloudStatusMonitor?
        init(monitor: CloudStatusMonitor) { self.monitor = monitor }
    }

    private final class TransferProgress {
        let progress: Progress
        let kind: Progress.FileOperationKind?
        var observation: NSKeyValueObservation?
        var fraction: Double {
            progress.isIndeterminate ? 0 : min(max(progress.fractionCompleted, 0), 1)
        }
        init(progress: Progress) {
            self.progress = progress
            self.kind = progress.fileOperationKind
        }
    }

    // MARK: Event sources

    private func startFSEvents() {
        let box = CallbackBox(monitor: self)
        let info = Unmanaged.passRetained(box).toOpaque()
        var context = FSEventStreamContext(
            version: 0, info: info, retain: nil,
            release: { info in
                if let info { Unmanaged<CallbackBox>.fromOpaque(info).release() }
            },
            copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, flags, _ in
            guard let info else { return }
            let box = Unmanaged<CallbackBox>.fromOpaque(info).takeUnretainedValue()
            guard let monitor = box.monitor else { return }
            let pathArray = (Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as NSArray)
                .compactMap { $0 as? String }
            let flagArray = Array(UnsafeBufferPointer(start: flags, count: count))
            monitor.handleFSEvents(paths: pathArray, flags: flagArray)
        }
        // File-level events; the 0.5 s latency only coalesces bursts (NoDefer delivers the first
        // event of a burst at once). No timer runs while nothing changes.
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)
        guard let stream = FSEventStreamCreate(kCFAllocatorDefault, callback, &context, [directoryPath] as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.5, flags) else {
            Unmanaged<CallbackBox>.fromOpaque(info).release()
            diagnostics?("fsevents: stream creation failed")
            return
        }
        FSEventStreamSetDispatchQueue(stream, .main)
        if FSEventStreamStart(stream) {
            self.stream = stream
        } else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            diagnostics?("fsevents: stream start failed")
        }
    }

    private func tearDownEventSources() {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
        // Presenters keep only a weak reference to the monitor and are never written after init
        // (their queue may be reading it right now); late messages are discarded on main by the
        // isRunning check.
        if let directoryPresenter {
            NSFileCoordinator.removeFilePresenter(directoryPresenter)
            self.directoryPresenter = nil
        }
        for presenter in itemPresenters.values {
            NSFileCoordinator.removeFilePresenter(presenter)
        }
        itemPresenters.removeAll()
        for subscription in progressSubscriptions { Progress.removeSubscriber(subscription) }
        progressSubscriptions.removeAll()
        for transfer in transfers.values { transfer.observation?.invalidate() }
    }

    private func handleFSEvents(paths: [String], flags: [FSEventStreamEventFlags]) {
        guard isRunning else { return }
        let rescanMask = FSEventStreamEventFlags(
            kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped |
            kFSEventStreamEventFlagKernelDropped | kFSEventStreamEventFlagRootChanged |
            kFSEventStreamEventFlagMount | kFSEventStreamEventFlagUnmount)
        var names = Set<String>()
        var full = false
        for (index, path) in paths.enumerated() {
            if index < flags.count, flags[index] & rescanMask != 0 { full = true; continue }
            switch topLevelName(forPath: path) {
            case .directoryItself: full = true
            case .item(let name): names.insert(name)
            case .outside: break
            }
        }
        diagnostics?("fsevents: \(paths.count) path(s) -> \(full ? "full rescan" : "\(names.sorted())")")
        if full { requestRefresh(full: true) } else if !names.isEmpty { requestRefresh(names: names) }
    }

    /// Called on a presenter's queue; hops to main. `url == nil` means the directory itself.
    fileprivate func presenterDidChange(subitem url: URL?, reason: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isRunning else { return }
            guard let url else {
                self.diagnostics?("presenter: \(reason) (directory) -> full rescan")
                self.requestRefresh(full: true)
                return
            }
            switch self.topLevelName(forPath: url.standardizedFileURL.path) {
            case .directoryItself:
                self.diagnostics?("presenter: \(reason) (directory) -> full rescan")
                self.requestRefresh(full: true)
            case .item(let name):
                self.diagnostics?("presenter: \(reason) -> \(name)")
                self.requestRefresh(names: [name])
            case .outside:
                self.diagnostics?("presenter: \(reason) outside directory: \(url.path)")
            }
        }
    }

    /// Called on a presenter's queue by an in-transit item's presenter; hops to main.
    fileprivate func itemPresenterDidChange(name: String, reason: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isRunning else { return }
            self.diagnostics?("item presenter: \(reason) -> \(name)")
            self.requestRefresh(names: [name])
        }
    }

    /// The directory itself plus its `~/Library/Mobile Documents/com~apple~CloudDocs/<name>` alias
    /// when that alias is a symlink to the directory. The iCloud Drive container location is
    /// community knowledge, not a documented API; the check is defensive and read-only, and
    /// subscribing to a second URL only widens what we listen to.
    private func progressSubscriptionURLs() -> [URL] {
        var urls = [directory]
        let alias = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
            .appendingPathComponent(directory.lastPathComponent, isDirectory: true)
        if alias.standardizedFileURL.path != directoryPath,
           let real = realpath(alias.path, nil) {
            if directoryAliases.contains(String(cString: real)) { urls.append(alias) }
            free(real)
        }
        return urls
    }

    private func handlePublished(_ progress: Progress) -> (@Sendable () -> Void)? {
        // Main thread (documented for Progress subscribers). On the proxy the `fileURL` accessor
        // is nil (observed on macOS 26.6.2) but the documented `fileURLKey` user-info entry is set.
        let publishedURL = (progress.userInfo[.fileURLKey] as? URL)
            ?? (progress.userInfo[.fileURLKey] as? String).map { URL(fileURLWithPath: $0) }
            ?? progress.fileURL
        guard let fileURL = publishedURL, let name = itemName(for: fileURL) else {
            diagnostics?("progress: published without a usable fileURL (\(publishedURL?.path ?? "nil"))")
            return nil
        }
        // Finder publishes progress for its own copies and receives too; only sync transfers
        // (or an unknown kind, judged against the resource keys in status(for:)) are tracked.
        switch progress.fileOperationKind {
        case nil, .uploading?, .downloading?: break
        default:
            diagnostics?("progress: ignored \(progress.fileOperationKind?.rawValue ?? "?") for \(name)")
            return nil
        }
        let transfer = TransferProgress(progress: progress)
        transfer.observation = progress.observe(\.fractionCompleted, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.notifyChange() }
        }
        transfers[name]?.observation?.invalidate()
        transfers[name] = transfer
        diagnostics?("progress: published for \(name) kind=\(progress.fileOperationKind?.rawValue ?? "?") fraction=\(transfer.fraction)")
        requestRefresh(names: [name])
        notifyChange()
        let token = UnpublishToken(monitor: self, transfer: transfer, name: name)
        return { @Sendable in DispatchQueue.main.async { token.fire() } }
    }

    /// Carries the unpublish callback to the main queue without capturing non-Sendable state in
    /// the `@Sendable` handler; everything it touches is touched on main.
    private final class UnpublishToken: @unchecked Sendable {
        weak var monitor: CloudStatusMonitor?
        let transfer: TransferProgress
        let name: String
        init(monitor: CloudStatusMonitor, transfer: TransferProgress, name: String) {
            self.monitor = monitor; self.transfer = transfer; self.name = name
        }
        func fire() { monitor?.transferUnpublished(name: name, transfer: transfer) }
    }

    private func transferUnpublished(name: String, transfer: TransferProgress) {
        if let current = transfers[name], current === transfer {
            current.observation?.invalidate()
            transfers.removeValue(forKey: name)
        }
        diagnostics?("progress: unpublished for \(name)")
        guard isRunning else { return }
        requestRefresh(names: [name])
        notifyChange()
    }

    // MARK: Refresh pipeline (main thread)

    private func requestRefresh(full: Bool = false, names: Set<String> = []) {
        guard isRunning else { return }
        if full { pendingFull = true } else { pendingNames.formUnion(names) }
        armRefresh(after: debounce)
    }

    private func armRefresh(after delay: TimeInterval) {
        guard !refreshArmed, !refreshInFlight else { return }
        refreshArmed = true
        let gen = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, gen == self.generation else { return }
            self.refreshArmed = false
            self.performRefresh()
        }
    }

    private func performRefresh() {
        guard isRunning, !refreshInFlight, pendingFull || !pendingNames.isEmpty else { return }
        let full = pendingFull
        let names = pendingNames
        pendingFull = false
        pendingNames.removeAll()
        refreshInFlight = true
        let gen = generation
        let dir = directory
        workQueue.async {
            var result: [String: CloudStatus?] = [:]   // nil value = item no longer exists
            if full {
                for (name, status) in Self.scan(directory: dir) { result[name] = status }
            } else {
                for name in names { result[name] = Self.statusIfPresent(dir.appendingPathComponent(name)) }
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, gen == self.generation else { return }
                self.refreshInFlight = false
                self.apply(result, full: full)
                if self.pendingFull || !self.pendingNames.isEmpty { self.armRefresh(after: self.debounce) }
            }
        }
    }

    private func apply(_ result: [String: CloudStatus?], full: Bool) {
        var changed = false
        if full {
            let fresh = result.compactMapValues { $0 }
            changed = fresh != statuses
            statuses = fresh
        } else {
            for (name, status) in result {
                if let status {
                    if statuses[name] != status { statuses[name] = status; changed = true }
                } else if statuses.removeValue(forKey: name) != nil {
                    changed = true
                }
            }
        }
        reconcileItemPresenters()
        diagnostics?("refresh: \(full ? "full (\(result.count) items)" : "\(result.count) item(s)") changed=\(changed) inTransit=\(itemPresenters.count)")
        if changed { notifyChange() }
    }

    /// Keeps exactly one presenter per item that is in transit, so that ubiquity-attribute
    /// changes (upload finished, download finished, error cleared) reach us even when nothing
    /// on disk changes.
    private func reconcileItemPresenters() {
        var wanted = Set<String>()
        for (name, status) in statuses where Self.isInTransit(status) { wanted.insert(name) }
        for name in Array(itemPresenters.keys) where !wanted.contains(name) {
            if let presenter = itemPresenters.removeValue(forKey: name) {
                NSFileCoordinator.removeFilePresenter(presenter)
            }
        }
        for name in wanted where itemPresenters[name] == nil {
            let presenter = ItemPresenter(url: directory.appendingPathComponent(name), name: name,
                                          queue: presenterQueue, monitor: self)
            NSFileCoordinator.addFilePresenter(presenter)
            itemPresenters[name] = presenter
        }
    }

    private static func isInTransit(_ status: CloudStatus) -> Bool {
        switch status {
        case .notUploaded, .uploading, .downloading, .error: return true
        case .notInCloud, .current, .notDownloaded: return false
        }
    }

    private func notifyChange() {
        guard !changeNotificationScheduled else { return }
        changeNotificationScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.changeNotificationScheduled = false
            guard self.isRunning else { return }
            self.onChange?()
        }
    }

    // MARK: Resource values (work queue or any thread)

    /// Top-level, non-hidden items and their statuses. Values are prefetched in one enumeration.
    private static func scan(directory: URL) -> [String: CloudStatus] {
        let keys = Array(resourceKeys)
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys, options: []) else { return [:] }
        var out: [String: CloudStatus] = [:]
        for url in urls {
            let name = url.lastPathComponent
            if name.hasPrefix(".") { continue }
            out[name] = (try? url.resourceValues(forKeys: resourceKeys)).map(status(from:)) ?? .notInCloud
        }
        return out
    }

    private static func statusIfPresent(_ url: URL) -> CloudStatus? {
        let fresh = URL(fileURLWithPath: url.path)
        guard let values = try? fresh.resourceValues(forKeys: resourceKeys) else { return nil }
        return status(from: values)
    }

    private static func status(from v: URLResourceValues) -> CloudStatus {
        guard v.isUbiquitousItem == true else { return .notInCloud }
        if v.ubiquitousItemDownloadingError != nil || v.ubiquitousItemUploadingError != nil { return .error }
        if v.ubiquitousItemIsDownloading == true { return .downloading(0) }
        if v.ubiquitousItemIsUploading == true { return .uploading(0) }
        if v.ubiquitousItemDownloadingStatus == .notDownloaded { return .notDownloaded }
        if v.ubiquitousItemIsUploaded == false { return .notUploaded }
        // .current, or .downloaded (a local copy exists but a newer version is known; Apple says it
        // is fetched "as soon as possible", which then shows up here as .downloading).
        return .current
    }

    // MARK: Path mapping

    private enum PathClass { case directoryItself, item(String), outside }

    /// Maps any path inside the directory (at any depth) to the top-level item it belongs to.
    private func topLevelName(forPath path: String) -> PathClass {
        for alias in directoryAliases {
            if path == alias { return .directoryItself }
            let prefix = alias.hasSuffix("/") ? alias : alias + "/"
            if path.hasPrefix(prefix) {
                let rest = path.dropFirst(prefix.count)
                let name = rest.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? ""
                if name.isEmpty { return .directoryItself }
                if name.hasPrefix(".") { return .outside }   // hidden items are never shown
                return .item(name)
            }
        }
        return .outside
    }

    private func itemName(for url: URL) -> String? {
        let standardized = url.standardizedFileURL
        if directoryAliases.contains(standardized.deletingLastPathComponent().path) {
            return standardized.lastPathComponent
        }
        let resolved = url.resolvingSymlinksInPath()
        if directoryAliases.contains(resolved.deletingLastPathComponent().path) {
            return resolved.lastPathComponent
        }
        return nil
    }
}

/// NSFilePresenter for the directory. Implements notification methods only (nothing with a
/// completion handler or relinquish semantics), so no coordinated reader or writer ever waits on us.
private final class DirectoryPresenter: NSObject, NSFilePresenter {
    let presentedItemURL: URL?
    let presentedItemOperationQueue: OperationQueue
    weak var monitor: CloudStatusMonitor?

    init(url: URL, queue: OperationQueue, monitor: CloudStatusMonitor) {
        presentedItemURL = url
        presentedItemOperationQueue = queue
        self.monitor = monitor
    }

    func presentedItemDidChange() {
        monitor?.presenterDidChange(subitem: nil, reason: "itemDidChange")
    }
    func presentedSubitemDidChange(at url: URL) {
        monitor?.presenterDidChange(subitem: url, reason: "subitemDidChange")
    }
    func presentedSubitemDidAppear(at url: URL) {
        monitor?.presenterDidChange(subitem: url, reason: "subitemDidAppear")
    }
    func presentedSubitem(at oldURL: URL, didMoveTo newURL: URL) {
        monitor?.presenterDidChange(subitem: oldURL, reason: "subitemDidMove(from)")
        monitor?.presenterDidChange(subitem: newURL, reason: "subitemDidMove(to)")
    }
}

/// NSFilePresenter for one item in transit. Notification-only, like the directory presenter.
/// `presentedItemDidChangeUbiquityAttributes(_:)` is the documented channel for iCloud attribute
/// changes of a file (macOS 10.13+); it is sent only for files and file packages, which is fine:
/// a folder in transit is refreshed through the events its contents generate.
private final class ItemPresenter: NSObject, NSFilePresenter {
    let presentedItemURL: URL?
    let presentedItemOperationQueue: OperationQueue
    let name: String
    weak var monitor: CloudStatusMonitor?

    init(url: URL, name: String, queue: OperationQueue, monitor: CloudStatusMonitor) {
        presentedItemURL = url
        presentedItemOperationQueue = queue
        self.name = name
        self.monitor = monitor
    }

    var observedPresentedItemUbiquityAttributes: Set<URLResourceKey> { CloudStatusMonitor.resourceKeys }

    func presentedItemDidChange() {
        monitor?.itemPresenterDidChange(name: name, reason: "itemDidChange")
    }
    func presentedItemDidChangeUbiquityAttributes(_ attributes: Set<URLResourceKey>) {
        monitor?.itemPresenterDidChange(name: name, reason: "ubiquityAttributes \(attributes.map(\.rawValue).sorted())")
    }
}

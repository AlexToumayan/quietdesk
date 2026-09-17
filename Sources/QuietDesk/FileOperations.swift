import AppKit
import UniformTypeIdentifiers

/// File operations the overlay performs itself, each undoable through `undoManager`.
/// Every operation here is an explicit user action that Finder would also perform; nothing
/// runs on its own, and nothing rewrites file contents. Long copies run off the main thread.
final class FileOperations {
    static let shared = FileOperations()
    let undoManager = UndoManager()
    init() {}
    private let fm = FileManager.default
    private let queue = DispatchQueue(label: "dev.quietdesk.fileops", qos: .userInitiated)

    enum OperationError: Error, CustomStringConvertible {
        case invalidName, nameExists, leadingDot
        var description: String {
            switch self {
            case .invalidName: return "The name can't be empty."
            case .nameExists: return "An item with that name already exists."
            case .leadingDot: return "Names that begin with a period are reserved for the system."
            }
        }
    }

    typealias Pair = (from: URL, to: URL)

    /// True when `destination` is `source` itself or lies inside it (copying or moving a folder
    /// into its own descendant would recurse or destroy it).
    static func isSameOrDescendant(_ destination: URL, of source: URL) -> Bool {
        let s = source.standardizedFileURL.resolvingSymlinksInPath().path
        let d = destination.standardizedFileURL.resolvingSymlinksInPath().path
        return d == s || d.hasPrefix(s.hasSuffix("/") ? s : s + "/")
    }

    /// Wraps results that arrive after the background work finishes; the undo action is
    /// registered immediately so the undo stack stays in the order of the user's actions.
    private final class Deferred { var pairs: [Pair]? }

    // MARK: - Naming

    static func isPlainDirectory(_ url: URL) -> Bool {
        let rv = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        return (rv?.isDirectory ?? false) && !(rv?.isPackage ?? false)
    }

    /// Finder-style unique names: "Name", "Name 2" … or with a word: "Name copy", "Name copy 2",
    /// keeping the extension of files. Plain folders are treated as having no extension.
    static func uniqueURL(in dir: URL, name: String, word: String?, isDirectory: Bool) -> URL {
        let ext = isDirectory ? "" : (name as NSString).pathExtension
        var stem = ext.isEmpty ? name : (name as NSString).deletingPathExtension
        if let word { stem += " " + word }
        func url(_ s: String) -> URL { dir.appendingPathComponent(ext.isEmpty ? s : s + "." + ext) }
        var candidate = stem
        var n = 2
        while FileManager.default.fileExists(atPath: url(candidate).path) {
            candidate = "\(stem) \(n)"
            n += 1
        }
        return url(candidate)
    }

    // MARK: - Undo plumbing

    private func registerUndo(_ name: String, _ block: @escaping () -> Void) {
        undoManager.registerUndo(withTarget: self) { _ in block() }
        undoManager.setActionName(name)
    }

    /// Registers the undo action now, runs `work` on the background queue, and hands the
    /// resulting (from, to) pairs to `undo` when the user undoes. Undo before completion is a
    /// silent no-op; nothing-done results make the undo entry a no-op as well.
    private func perform(_ name: String, work: @escaping () -> [Pair], undo: @escaping ([Pair]) -> Void, completion: (([URL]) -> Void)? = nil) {
        let box = Deferred()
        registerUndo(name) { if let pairs = box.pairs, !pairs.isEmpty { undo(pairs) } }
        queue.async {
            let results = work()
            DispatchQueue.main.async {
                box.pairs = results
                completion?(results.map { $0.to })
            }
        }
    }

    /// Copy one item; on failure remove the partial copy (a destination that did not exist
    /// before) and beep so the failure is not silent. Cloud-only files fail here on purpose:
    /// the process never downloads them (see main.swift).
    private func copyItemCleanly(_ src: URL, to dest: URL) -> Bool {
        do { try fm.copyItem(at: src, to: dest); return true }
        catch {
            try? fm.removeItem(at: dest)
            DispatchQueue.main.async { NSSound.beep() }
            return false
        }
    }

    /// Moves each pair (from → to) off the main thread; undo moves them back the same way.
    private func moveItems(_ pairs: [Pair], actionName: String, completion: (([URL]) -> Void)? = nil) {
        let fm = fm
        perform(actionName, work: {
            pairs.compactMap { p in
                if fm.fileExists(atPath: p.to.path) { return nil }
                return (try? fm.moveItem(at: p.from, to: p.to)) != nil ? p : nil
            }
        }, undo: { [weak self] done in self?.moveItems(done.map { ($0.to, $0.from) }, actionName: actionName) }, completion: completion)
    }

    // MARK: - Operations

    /// Rename in place. "/" is stored as ":" the way Finder does. Throws on empty or clashing names.
    @discardableResult
    func rename(_ url: URL, to newName: String) throws -> URL {
        let cleaned = newName.replacingOccurrences(of: "/", with: ":").trimmingCharacters(in: .newlines)
        guard !cleaned.isEmpty, cleaned != ".", cleaned != ".." else { throw OperationError.invalidName }
        guard !cleaned.hasPrefix(".") else { throw OperationError.leadingDot }
        let dest = url.deletingLastPathComponent().appendingPathComponent(cleaned)
        if dest.path == url.path { return url }
        let caseOnly = dest.lastPathComponent.lowercased() == url.lastPathComponent.lowercased()
        if !caseOnly, fm.fileExists(atPath: dest.path) { throw OperationError.nameExists }
        try fm.moveItem(at: url, to: dest)
        let oldName = url.lastPathComponent
        registerUndo("Rename") { [weak self] in _ = try? self?.rename(dest, to: oldName) }
        return dest
    }

    func duplicate(_ urls: [URL], completion: (([URL]) -> Void)? = nil) {
        perform("Duplicate", work: { [self] in
            urls.compactMap { url in
                let dest = Self.uniqueURL(in: url.deletingLastPathComponent(), name: url.lastPathComponent, word: "copy", isDirectory: Self.isPlainDirectory(url))
                return copyItemCleanly(url, to: dest) ? (url, dest) : nil
            }
        }, undo: { [weak self] made in self?.trash(made.map { $0.to }) }, completion: completion)
    }

    /// Creates Finder alias files ("Name alias") next to the originals.
    func makeAliases(_ urls: [URL]) {
        var made: [URL] = []
        for url in urls {
            let dest = Self.uniqueURL(in: url.deletingLastPathComponent(), name: url.lastPathComponent + " alias", word: nil, isDirectory: true)
            do {
                let data = try url.bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil)
                try URL.writeBookmarkData(data, to: dest)
                made.append(dest)
            } catch { NSSound.beep() }
        }
        if !made.isEmpty { registerUndo("Make Alias") { [weak self] in self?.trash(made) } }
    }

    /// Finder's "Compress": hands the items to Archive Utility, which writes "Name.zip" beside them.
    func compress(_ urls: [URL]) {
        let archiveUtility = URL(fileURLWithPath: "/System/Library/CoreServices/Applications/Archive Utility.app")
        guard fm.fileExists(atPath: archiveUtility.path) else { NSSound.beep(); return }
        NSWorkspace.shared.open(urls, withApplicationAt: archiveUtility, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Move to Trash (Finder's Put Back keeps working). Undo moves the items back.
    func trash(_ urls: [URL]) {
        var pairs: [(trashed: URL, original: URL)] = []
        for url in urls {
            var trashed: NSURL?
            if (try? fm.trashItem(at: url, resultingItemURL: &trashed)) != nil, let t = trashed as URL? { pairs.append((t, url)) }
            else { NSSound.beep() }
        }
        if !pairs.isEmpty {
            registerUndo("Move to Trash") { [weak self] in
                guard let self else { return }
                var restored: [URL] = []
                for p in pairs where (try? self.fm.moveItem(at: p.trashed, to: p.original)) != nil { restored.append(p.original) }
                if !restored.isEmpty { self.registerUndo("Move to Trash") { self.trash(restored) } }
            }
        }
    }

    @discardableResult
    func newFolder(in dir: URL) -> URL? {
        let url = Self.uniqueURL(in: dir, name: "untitled folder", word: nil, isDirectory: true)
        do { try fm.createDirectory(at: url, withIntermediateDirectories: false) } catch { NSSound.beep(); return nil }
        registerUndo("New Folder") { [weak self] in self?.trash([url]) }
        return url
    }

    /// Move items into `dir` (skips items already there, items that contain `dir`, and never overwrites).
    func move(_ urls: [URL], into dir: URL, completion: (([URL]) -> Void)? = nil) {
        var pairs: [Pair] = []
        var refused = false
        for url in urls {
            if url.deletingLastPathComponent().standardizedFileURL == dir.standardizedFileURL { continue }
            if Self.isSameOrDescendant(dir, of: url) { refused = true; continue }
            pairs.append((url, dir.appendingPathComponent(url.lastPathComponent)))
        }
        if refused { NSSound.beep() }
        guard !pairs.isEmpty else { completion?([]); return }
        moveItems(pairs, actionName: "Move", completion: completion)
    }

    /// Copy items into `dir` (never overwrites, never into an item's own descendant). Undo trashes the copies.
    func copy(_ urls: [URL], into dir: URL, completion: (([URL]) -> Void)? = nil) {
        let sources = urls.filter { !Self.isSameOrDescendant(dir, of: $0) }
        if sources.count != urls.count { NSSound.beep() }
        guard !sources.isEmpty else { completion?([]); return }
        let fm = fm
        perform("Copy", work: { [self] in
            sources.compactMap { url in
                if url.deletingLastPathComponent().standardizedFileURL == dir.standardizedFileURL {
                    // Copy into the same folder: Finder makes "Name copy".
                    let dest = Self.uniqueURL(in: dir, name: url.lastPathComponent, word: "copy", isDirectory: Self.isPlainDirectory(url))
                    return copyItemCleanly(url, to: dest) ? (url, dest) : nil
                }
                let dest = dir.appendingPathComponent(url.lastPathComponent)
                if fm.fileExists(atPath: dest.path) { return nil }
                return copyItemCleanly(url, to: dest) ? (url, dest) : nil
            }
        }, undo: { [weak self] made in self?.trash(made.map { $0.to }) }, completion: completion)
    }

    // MARK: - Clipboard (Finder reads and writes file URLs on the general pasteboard)

    func copyToPasteboard(_ urls: [URL]) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(urls.map { $0 as NSURL })
    }

    static func pasteboardFileURLs() -> [URL] {
        (NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }

    // MARK: - Volumes, tags, apps, aliases

    func eject(_ volume: URL) {
        do { try NSWorkspace.shared.unmountAndEjectDevice(at: volume) } catch { NSSound.beep() }
    }

    static func tags(for url: URL) -> [String] {
        (try? url.resourceValues(forKeys: [.tagNamesKey]).tagNames) ?? []
    }

    func setTags(_ tags: [String], for url: URL) {
        let old = Self.tags(for: url)
        do { try (url as NSURL).setResourceValue(tags, forKey: .tagNamesKey) } catch { NSSound.beep(); return }
        registerUndo("Tags") { [weak self] in self?.setTags(old, for: url) }
    }

    /// Finder's seven standard tag colours; custom tags get a grey dot.
    static let standardTagColors: [(name: String, color: NSColor)] = [
        ("Red", .systemRed), ("Orange", .systemOrange), ("Yellow", .systemYellow), ("Green", .systemGreen),
        ("Blue", .systemBlue), ("Purple", .systemPurple), ("Gray", .systemGray),
    ]

    static func color(forTag name: String) -> NSColor {
        standardTagColors.first { $0.name == name }?.color ?? .systemGray
    }

    static func applications(toOpen url: URL) -> [URL] { NSWorkspace.shared.urlsForApplications(toOpen: url) }
    static func defaultApplication(toOpen url: URL) -> URL? { NSWorkspace.shared.urlForApplication(toOpen: url) }

    func open(_ urls: [URL], with app: URL) {
        NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    static func resolveAlias(_ url: URL) -> URL? {
        try? URL(resolvingAliasFileAt: url, options: [.withoutUI, .withoutMounting])
    }
}

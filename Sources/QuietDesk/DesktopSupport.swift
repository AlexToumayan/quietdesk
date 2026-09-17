import AppKit

final class RenameField: NSTextField {}

/// Drop handling shared by the icon view and the shield.
enum DesktopDrop {
    /// Files (URLs) and file promises (browsers, Mail, Photos) dropped into `destination`.
    static func perform(_ sender: NSDraggingInfo, into destination: URL, fileOps: FileOperations) -> Bool {
        let pb = sender.draggingPasteboard
        var handled = false
        if let receivers = pb.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver], !receivers.isEmpty {
            let queue = OperationQueue()
            for r in receivers {
                r.receivePromisedFiles(atDestination: destination, options: [:], operationQueue: queue) { _, error in
                    if error != nil { DispatchQueue.main.async { NSSound.beep() } }
                }
            }
            handled = true
        }
        let urls = (pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        if !urls.isEmpty {
            let destVolume = try? destination.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier
            let sameVolume = urls.allSatisfy { ((try? $0.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier)?.isEqual(destVolume)) ?? false }
            if sameVolume && sender.draggingSourceOperationMask.contains(.move) { fileOps.move(urls, into: destination) }
            else { fileOps.copy(urls, into: destination) }
            handled = true
        }
        return handled
    }

    /// Manual layouts: an overlay-internal drag dropped on empty desktop moves the icons.
    static func reposition(from source: DesktopView, dropScreenPoint: NSPoint, targetView: NSView, delegate: DesktopSurfaceDelegate?) -> Bool {
        guard let delegate, delegate.isManualLayout, let screen = targetView.window?.screen, let win = targetView.window else { return false }
        let delta = NSPoint(x: dropScreenPoint.x - source.dragStartScreenPoint.x, y: dropScreenPoint.y - source.dragStartScreenPoint.y)
        var centres: [URL: NSPoint] = [:]
        for (url, c) in source.draggedCentres {
            // Source centre (flipped, source-screen-local) -> screen -> target-screen-local (flipped).
            let s = source.screenPoint(c)
            let moved = NSPoint(x: s.x + delta.x, y: s.y + delta.y)
            let local = NSPoint(x: moved.x - screen.frame.minX, y: screen.frame.maxY - moved.y)
            _ = win
            centres[url] = local
        }
        delegate.surface(reposition: centres, on: screen)
        return true
    }
}

/// "Show item info" values, computed once per item. Folder counts need a directory listing
/// (top level only, never recursive), done off the main thread and cached until the folder changes.
final class ItemInfoCache {
    static let shared = ItemInfoCache()
    var onReady: ((URL) -> Void)?
    private var cache: [String: String] = [:]
    private var pending = Set<String>()
    private let queue = DispatchQueue(label: "dev.quietdesk.iteminfo", qos: .utility)
    private static let bytes: ByteCountFormatter = { let f = ByteCountFormatter(); f.countStyle = .file; return f }()

    func info(for item: DesktopItem) -> String? {
        if item.isVolume {
            let free = (try? item.url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage ?? 0
            return free > 0 ? Self.bytes.string(fromByteCount: free) + " available" : nil
        }
        if !item.isFolder { return Self.bytes.string(fromByteCount: item.size) }
        let key = item.url.path
        if let cached = cache[key] { return cached }
        if pending.insert(key).inserted {
            queue.async {
                let names = (try? FileManager.default.contentsOfDirectory(atPath: key)) ?? []
                let count = names.filter { !$0.hasPrefix(".") }.count
                DispatchQueue.main.async {
                    self.cache[key] = count == 1 ? "1 item" : "\(count) items"
                    self.pending.remove(key)
                    self.onReady?(item.url)
                }
            }
        }
        return nil
    }

    func invalidate(_ url: URL) { cache[url.path] = nil }
    func removeAll() { cache.removeAll(); pending.removeAll() }
}

enum DesktopMenus {
    /// Mirrors Finder's own desktop menu: New Folder, then the items the app delegate supplies
    /// (Get Info, Change Wallpaper, Use Stacks, Group Stacks By, Sort By, labels, View Options),
    /// then Paste and a shortcut to the Desktop folder.
    static func emptyDesktopMenu(target: AnyObject, extras: [NSMenuItem]) -> NSMenu {
        let menu = NSMenu()
        let newFolder = NSMenuItem(title: "New Folder", action: Selector(("menuNewFolder")), keyEquivalent: "n")
        newFolder.keyEquivalentModifierMask = [.command, .shift]; newFolder.target = target
        menu.addItem(newFolder)
        if !extras.isEmpty {
            menu.addItem(.separator())
            extras.forEach { menu.addItem($0) }
        }
        menu.addItem(.separator())
        let paste = NSMenuItem(title: "Paste", action: Selector(("menuPaste")), keyEquivalent: "v")
        paste.target = target
        paste.isEnabled = !FileOperations.pasteboardFileURLs().isEmpty
        menu.addItem(paste)
        menu.addItem(withTitle: "Show Desktop Folder in Finder", action: Selector(("menuShowDesktop")), keyEquivalent: "").target = target
        menu.autoenablesItems = false
        return menu
    }

    static func openWallpaperSettings() { openSystemSettings(pane: "com.apple.Wallpaper-Settings.extension") }

    /// UNDOCUMENTED: the `x-apple.systempreferences:` scheme with pane identifiers is community
    /// knowledge, not an Apple API. If a pane identifier stops working, fall back to opening
    /// System Settings itself.
    static func openSystemSettings(pane: String) {
        if let url = URL(string: "x-apple.systempreferences:" + pane), NSWorkspace.shared.open(url) { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }

    static func showError(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

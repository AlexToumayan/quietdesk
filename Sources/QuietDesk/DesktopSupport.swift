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

enum DesktopMenus {
    static func emptyDesktopMenu(target: AnyObject, extras: [NSMenuItem]) -> NSMenu {
        let menu = NSMenu()
        let newFolder = NSMenuItem(title: "New Folder", action: Selector(("menuNewFolder")), keyEquivalent: "n")
        newFolder.keyEquivalentModifierMask = [.command, .shift]; newFolder.target = target
        menu.addItem(newFolder)
        let paste = NSMenuItem(title: "Paste", action: Selector(("menuPaste")), keyEquivalent: "v")
        paste.target = target
        paste.isEnabled = !FileOperations.pasteboardFileURLs().isEmpty
        menu.addItem(paste)
        if !extras.isEmpty {
            menu.addItem(.separator())
            extras.forEach { menu.addItem($0) }
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Show Desktop Folder in Finder", action: Selector(("menuShowDesktop")), keyEquivalent: "").target = target
        menu.addItem(withTitle: "Change Wallpaper…", action: Selector(("menuChangeWallpaper")), keyEquivalent: "").target = target
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

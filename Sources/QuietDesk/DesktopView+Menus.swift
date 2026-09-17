import AppKit
import UniformTypeIdentifiers

// Context menus for items and for the empty desktop.
extension DesktopView {

    override func menu(for event: NSEvent) -> NSMenu? {
        let p = convert(event.locationInWindow, from: nil)
        if renameField != nil { commitRename() }
        if bandStart != nil { bandStart = nil; bandHost?.showRubberBand(screenRect: nil) }
        window?.makeKey()
        window?.makeFirstResponder(self)
        delegate?.surfaceDidReceiveClick()
        guard let i = cellIndex(at: p) else {
            select([]); setFocus(nil)
            return DesktopMenus.emptyDesktopMenu(target: self, extras: delegate?.surfaceMenuExtras() ?? [])
        }
        if !selection.contains(i) { select([i]); setFocus(i) }
        return itemMenu()
    }

    func itemMenu() -> NSMenu {
        let menu = NSMenu()
        let items = selectedItems
        let single = items.count == 1 ? items[0] : nil
        if let stack = selection.count == 1 ? cells[selection.first!].entry.stack : nil {
            menu.addItem(withTitle: isExpanded(stack) ? "Collapse Stack" : "Expand Stack", action: #selector(menuToggleStack), keyEquivalent: "").target = self
            menu.addItem(withTitle: "Show Stack Items in Finder", action: #selector(menuOpen), keyEquivalent: "").target = self
            return menu
        }
        guard !items.isEmpty else { return menu }
        func add(_ title: String, _ sel: Selector, _ key: String = "", _ mods: NSEvent.ModifierFlags = .command) {
            let mi = NSMenuItem(title: title, action: sel, keyEquivalent: key)
            mi.keyEquivalentModifierMask = key.isEmpty ? [] : mods
            mi.target = self
            menu.addItem(mi)
        }
        add("Open", #selector(menuOpen), "o")
        if let single, !single.isFolder, !single.isVolume {
            let openWith = NSMenuItem(title: "Open With", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            let apps = FileOperations.applications(toOpen: single.url)
            let def = FileOperations.defaultApplication(toOpen: single.url)
            for app in apps.sorted(by: { ($0 == def ? 0 : 1, $0.lastPathComponent) < ($1 == def ? 0 : 1, $1.lastPathComponent) }) {
                let name = (app.deletingPathExtension().lastPathComponent) + (app == def ? " (default)" : "")
                let mi = NSMenuItem(title: name, action: #selector(menuOpenWith(_:)), keyEquivalent: "")
                mi.target = self; mi.representedObject = app
                let icon = NSWorkspace.shared.icon(forFile: app.path); icon.size = NSSize(width: 16, height: 16); mi.image = icon
                sub.addItem(mi)
                if app == def, apps.count > 1 { sub.addItem(.separator()) }
            }
            if apps.isEmpty { sub.addItem(withTitle: "No applications found", action: nil, keyEquivalent: "") }
            openWith.submenu = sub
            menu.addItem(openWith)
        }
        menu.addItem(.separator())
        add("Show in Finder", #selector(menuReveal))
        if let single, single.isAlias { add("Show Original", #selector(menuShowOriginal), "r") }
        add("Get Info", #selector(menuGetInfo), "i")
        if single != nil, !(single?.isVolume ?? false) { add("Rename", #selector(menuRename)) }
        if !items.contains(where: { $0.isVolume }) {
            add("Duplicate", #selector(menuDuplicate), "d")
            add("Make Alias", #selector(menuMakeAlias), "l")
        }
        add(single.map { "Quick Look \"\($0.name)\"" } ?? "Quick Look \(items.count) Items", #selector(menuQuickLook), "y")
        if !items.contains(where: { $0.isVolume }) { add(single.map { "Compress \"\($0.name)\"" } ?? "Compress \(items.count) Items", #selector(menuCompress)) }
        menu.addItem(.separator())
        add(single.map { "Copy \"\($0.name)\"" } ?? "Copy \(items.count) Items", #selector(menuCopy), "c")
        add("Share…", #selector(menuShare(_:)))
        if !items.contains(where: { $0.isVolume }) {
            let tags = NSMenuItem(title: "Tags", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            let common = items.dropFirst().reduce(Set(items[0].tags)) { $0.intersection($1.tags) }
            var names = FileOperations.standardTagColors.map { $0.name }
            for t in items.flatMap({ $0.tags }) where !names.contains(t) { names.append(t) }
            for name in names {
                let mi = NSMenuItem(title: name, action: #selector(menuToggleTag(_:)), keyEquivalent: "")
                mi.target = self; mi.representedObject = name
                mi.state = common.contains(name) ? .on : .off
                mi.image = Self.dot(FileOperations.color(forTag: name))
                sub.addItem(mi)
            }
            tags.submenu = sub
            menu.addItem(tags)
        }
        menu.addItem(.separator())
        if items.contains(where: { $0.isVolume }) { add("Eject", #selector(menuEject), "e") }
        else { add("Move to Trash", #selector(menuTrash), "\u{8}") }
        return menu
    }

    static func dot(_ color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            color.setFill(); NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill(); return true
        }
    }

    @objc func menuOpen() { open(selection.sorted()) }
    @objc func menuOpenWith(_ sender: NSMenuItem) { if let app = sender.representedObject as? URL { fileOps.open(selectedURLs, with: app) } }
    @objc func menuReveal() { NSWorkspace.shared.activateFileViewerSelecting(selectedURLs) }
    @objc func menuShowOriginal() {
        let originals = selectedURLs.compactMap { FileOperations.resolveAlias($0) }
        if !originals.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(originals) } else { NSSound.beep() }
    }
    @objc func menuGetInfo() { getInfo() }
    @objc func menuRename() { if let i = selection.first, selection.count == 1 { beginRename(i) } }
    @objc func menuDuplicate() { fileOps.duplicate(selectedURLs) }
    @objc func menuMakeAlias() { fileOps.makeAliases(selectedURLs) }
    @objc func menuQuickLook() { toggleQuickLook() }
    @objc func menuCompress() { fileOps.compress(selectedURLs) }
    @objc func menuCopy() { fileOps.copyToPasteboard(selectedURLs) }
    @objc func menuShare(_ sender: NSMenuItem) {
        guard let i = selection.first else { return }
        NSApp.activate(ignoringOtherApps: true)
        let picker = NSSharingServicePicker(items: selectedURLs)
        picker.show(relativeTo: cells[i].iconRect, of: self, preferredEdge: .minY)
    }
    @objc func menuToggleTag(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        let items = selectedItems
        let allHave = items.allSatisfy { $0.tags.contains(name) }
        for item in items {
            var tags = FileOperations.tags(for: item.url)
            if allHave { tags.removeAll { $0 == name } } else if !tags.contains(name) { tags.append(name) }
            fileOps.setTags(tags, for: item.url)
        }
        delegate?.surfaceRequestsReload()
    }
    @objc func menuEject() { for item in selectedItems where item.isVolume { fileOps.eject(item.url) } }
    @objc func menuTrash() { fileOps.trash(selectedURLs) }
    @objc func menuToggleStack() { if let i = selection.first, let s = cells[i].entry.stack { delegate?.surface(toggleStack: s) } }

    // Empty-desktop actions (shared with the shield)
    @objc func menuNewFolder() { fileOps.newFolder(in: DesktopModel.desktopURL) }
    @objc func menuPaste() { paste() }
    @objc func menuShowDesktop() { NSWorkspace.shared.open(DesktopModel.desktopURL) }
    @objc func menuChangeWallpaper() { DesktopMenus.openWallpaperSettings() }

    func getInfo() {
        let urls = selectedURLs
        guard !urls.isEmpty else { return }
        FinderAutomation.openInfoWindows(for: urls) { error in
            if let error { DesktopMenus.showError("Get Info needs Finder", error.description) }
        }
    }

    func paste() {
        let urls = FileOperations.pasteboardFileURLs()
        guard !urls.isEmpty else { NSSound.beep(); return }
        fileOps.copy(urls, into: DesktopModel.desktopURL)
    }
}

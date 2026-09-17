import AppKit
import os

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let log = Logger(subsystem: "dev.quietdesk.QuietDesk", category: "app")
    private let settings = Settings.shared
    private var statusItem: NSStatusItem?
    private var controller: OverlayController?
    private var weSetHideKey = false
    private let args = CommandLine.arguments
    private var noHide: Bool { args.contains("--no-hide") || scenarioTest }
    private var scenarioTest: Bool { args.contains("--scenario-test") }
    private var sigterm: DispatchSourceSignal?
    private let menu = NSMenu()

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        if args.contains("--self-test") { exit(SelfTest.run()) }
        if args.contains("--dump-layout") {
            let c = OverlayController(labelMode: settings.labelMode)
            c.prepare()
            print(c.layoutDescription())
            exit(0)
        }
        if let i = args.firstIndex(of: "--render"), i + 1 < args.count {
            let c = OverlayController(labelMode: settings.labelMode)
            c.prepare()
            if let e = args.firstIndex(of: "--expand"), e + 1 < args.count { c.expandStackForTesting(args[e + 1]) }
            let hover = args.firstIndex(of: "--hover").flatMap { $0 + 1 < args.count ? Int(args[$0 + 1]) : nil }
            // Let the iCloud status query and thumbnails settle so the render shows them.
            c.startWatching()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                do {
                    try c.renderPNG(screenIndex: 0, to: URL(fileURLWithPath: self.args[i + 1]), hover: hover)
                    print("rendered \(self.args[i + 1])")
                } catch { print("render failed: \(error)") }
                c.stop()
                exit(0)
            }
            return
        }

        recoverFromPreviousRun()
        installSignalHandler()
        ViewOptionsWindowController.shared.onChange = { [weak self] in
            DebugLog.log("view options changed")
            self?.controller?.applyViewOptions()
            self?.controller?.reloadAndRelayout()   // sort/stacks changes need the model
            self?.rebuildMenu()
        }
        buildStatusItem()
        if let i = args.firstIndex(of: "--render-status-item"), i + 1 < args.count {
            // Give AppKit a moment to place the item in the menu bar before inspecting it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [self] in
                Diagnostics.renderStatusItem(statusItem, to: self.args[i + 1])
                exit(0)
            }
            return
        }
        if args.contains("--icon-candidates") { Diagnostics.renderIconCandidates(); exit(0) }
        showWelcomeOnce()
        if DebugLog.enabled { DebugLog.log("launch pid=\(ProcessInfo.processInfo.processIdentifier) enabled=\(settings.enabled) version=\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")") }
        if settings.enabled || scenarioTest { enable() }
        if scenarioTest {
            guard let c = controller else { print("scenario test: overlay could not be prepared (Desktop access?)"); exit(2) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { ScenarioTest(controller: c).start() }
        }

        if let i = args.firstIndex(of: "--test-seconds"), i + 1 < args.count, let s = Double(args[i + 1]) {
            DispatchQueue.main.asyncAfter(deadline: .now() + s) { NSApp.terminate(nil) }
        }
        if args.contains("--hit-test") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.runHitTests() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        disable()
    }

    /// Cmd-H while the overlay is key would hide our windows with the app; the desktop
    /// must never disappear that way, so undo it immediately.
    func applicationDidHide(_ notification: Notification) {
        NSApp.unhide(nil)
    }

    /// `kill`, `killall QuietDesk` and logout send SIGTERM, which skips applicationWillTerminate.
    /// Turn it into a normal quit so the desktop is restored.
    private func installSignalHandler() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { NSApp.terminate(nil) }
        source.resume()
        sigterm = source
    }

    /// One-time note so nobody is surprised by their icons changing hands.
    private func showWelcomeOnce() {
        guard !args.contains("--test-seconds"), !scenarioTest, !Settings.defaults.bool(forKey: "welcomeShown") else { return }
        Settings.defaults.set(true, forKey: "welcomeShown")
        let alert = NSAlert()
        alert.messageText = "QuietDesk is in your menu bar"
        alert.informativeText = "Look for the eye icon at the top right: slashed while QuietDesk is quieting your desktop, open when it is off. While QuietDesk is enabled it asks macOS to hide Finder's desktop icons and draws them itself, with names on hover.\n\nmacOS will ask once for access to your Desktop folder. To go back to the normal desktop at any time, choose Quit and Restore Desktop from the menu."
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // MARK: - Enable / disable (the only state changes the app makes)

    private func enable() {
        guard controller == nil else { return }
        DebugLog.log("enable")
        let c = OverlayController(labelMode: settings.labelMode)
        c.menuExtrasProvider = { [weak self] in self?.contextMenuExtras() ?? [] }
        c.prepare()                                       // replacement is ready before anything is hidden
        if c.listingFailed {
            // Without Desktop access there is nothing to draw; never hide the native icons then.
            c.stop()
            settings.enabled = false
            rebuildMenu()
            DesktopMenus.showError("QuietDesk can't read your Desktop folder",
                                   "Allow access in System Settings › Privacy & Security › Files and Folders › QuietDesk › Desktop Folder, then enable QuietDesk again. Your desktop was left untouched.")
            return
        }
        controller = c
        if !noHide {
            let previous = DesktopIconsPreference.read()
            if previous != true {
                RestoreRecord.save(previous: previous)
                DesktopIconsPreference.write(true)
                weSetHideKey = true
                log.notice("hid native desktop items (previous value: \(String(describing: previous)))")
            }
        }
        if settings.itemsVisible { c.show() }
        c.startWatching()
        rebuildMenu()
    }

    private func disable() {
        guard let c = controller else { return }
        DebugLog.log("disable")
        c.stop()
        controller = nil
        restoreNativeDesktop()
        rebuildMenu()
    }

    private func restoreNativeDesktop() {
        guard weSetHideKey, let previous = RestoreRecord.pending() else { return }
        if DesktopIconsPreference.read() == true {
            switch previous {
            case .absent: DesktopIconsPreference.write(nil)
            case .value(let b): DesktopIconsPreference.write(b)
            }
            log.notice("restored native desktop items setting to \(String(describing: previous))")
        } else {
            log.notice("desktop items setting was changed outside the app; leaving it alone")
        }
        RestoreRecord.clear()
        weSetHideKey = false
    }

    /// After a crash or force-quit the normal cleanup never ran; undo our change now.
    private func recoverFromPreviousRun() {
        guard let previous = RestoreRecord.pending() else { return }
        log.notice("previous run did not clean up; restoring desktop items setting")
        if DesktopIconsPreference.read() == true {
            switch previous {
            case .absent: DesktopIconsPreference.write(nil)
            case .value(let b): DesktopIconsPreference.write(b)
            }
        }
        RestoreRecord.clear()
    }

    // MARK: - Menu bar

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        updateStatusIcon()
        item.menu = menu
        menu.delegate = self
        statusItem = item
        rebuildMenu()
    }

    /// Open eye: the desktop is untouched (QuietDesk off). Slashed eye: QuietDesk is enabled and
    /// quieting the desktop. Template images follow the menu bar's light/dark appearance.
    private func updateStatusIcon() {
        guard let button = statusItem?.button else { return }
        let name = settings.enabled ? "eye.slash" : "eye"
        if let image = NSImage(systemSymbolName: name, accessibilityDescription: settings.enabled ? "QuietDesk, enabled" : "QuietDesk, off") {
            image.isTemplate = true
            button.image = image
        } else {
            button.title = "QD"
        }
    }

    /// Rebuilt every time it opens, so states that change outside the app (Launch at Login,
    /// Finder's own Sort By / Stacks settings) are always current.
    func menuNeedsUpdate(_ menu: NSMenu) { if menu === self.menu { rebuildMenu() } }

    private func radioMenu<T: Equatable>(_ cases: [(title: String, value: T)], current: T, action: Selector, enabled: Bool) -> NSMenu {
        let menu = NSMenu()
        for c in cases {
            let mi = NSMenuItem(title: c.title, action: action, keyEquivalent: "")
            mi.target = self
            mi.representedObject = c.value as AnyObject
            mi.state = c.value == current ? .on : .off
            mi.isEnabled = enabled
            menu.addItem(mi)
        }
        menu.autoenablesItems = false
        return menu
    }

    private func sortMenu(enabled: Bool) -> NSMenu {
        let finderTitle = "Finder's Setting (\(SortKey.allCases.first { $0.arrangeBy == FinderDesktopPrefs.load().arrangeBy }?.title ?? "None"))"
        var cases = SortKey.allCases.map { (title: $0.title, value: $0.rawValue) }
        cases[0].title = finderTitle
        return radioMenu(cases, current: settings.sortKey.rawValue, action: #selector(setSortKey(_:)), enabled: enabled)
    }

    private func stacksMenu(enabled: Bool) -> NSMenu {
        let g = FinderDesktopPrefs.load().groupBy
        var cases = StacksMode.allCases.map { (title: $0.title, value: $0.rawValue) }
        cases[0].title = "Finder's Setting (\(g == "None" || g.isEmpty ? "Off" : g))"
        return radioMenu(cases, current: settings.stacksMode.rawValue, action: #selector(setStacksMode(_:)), enabled: enabled)
    }

    private func labelsMenu(enabled: Bool) -> NSMenu {
        radioMenu(LabelMode.allCases.map { (title: $0.title, value: $0.rawValue) }, current: settings.labelMode.rawValue, action: #selector(setLabelMode(_:)), enabled: enabled)
    }

    private var stacksEnabledNow: Bool {
        let g = settings.stacksMode.groupBy ?? FinderDesktopPrefs.load().groupBy
        return !g.isEmpty && g != "None"
    }

    private func groupStacksMenu() -> NSMenu {
        let modes: [StacksMode] = [.kind, .dateAdded, .dateModified, .dateCreated, .dateLastOpened, .tags]
        let prefs = FinderDesktopPrefs.load()
        let effective: StacksMode = settings.stacksMode == .finder ? (StacksMode.allCases.first { $0.groupBy == prefs.groupBy } ?? .off) : settings.stacksMode
        return radioMenu(modes.map { (title: String($0.title.dropFirst("Group by ".count)), value: $0.rawValue) }, current: effective.rawValue, action: #selector(setStacksMode(_:)), enabled: true)
    }

    /// The middle of the desktop's own right-click menu, mirroring Finder's: Get Info, Change
    /// Wallpaper, Use Stacks, Group Stacks By, Sort By, Item Labels, Show View Options.
    private func contextMenuExtras() -> [NSMenuItem] {
        let info = NSMenuItem(title: "Get Info", action: #selector(getInfoDesktop), keyEquivalent: ""); info.target = self
        let wallpaper = NSMenuItem(title: "Change Wallpaper…", action: #selector(changeWallpaper), keyEquivalent: ""); wallpaper.target = self
        let useStacks = NSMenuItem(title: "Use Stacks", action: #selector(toggleUseStacks), keyEquivalent: ""); useStacks.target = self
        useStacks.state = stacksEnabledNow ? .on : .off
        let group = NSMenuItem(title: "Group Stacks By", action: nil, keyEquivalent: ""); group.submenu = groupStacksMenu(); group.isEnabled = stacksEnabledNow
        let sort = NSMenuItem(title: "Sort By", action: nil, keyEquivalent: ""); sort.submenu = sortMenu(enabled: true)
        let labels = NSMenuItem(title: "Item Labels", action: nil, keyEquivalent: ""); labels.submenu = labelsMenu(enabled: true)
        let options = NSMenuItem(title: "Show View Options", action: #selector(showViewOptions), keyEquivalent: "j"); options.target = self
        return [info, wallpaper, .separator(), useStacks, group, sort, labels, options]
    }

    private func rebuildMenu() {
        updateStatusIcon()
        menu.removeAllItems()
        menu.autoenablesItems = false
        let title = NSMenuItem(title: "QuietDesk", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())

        let power = NSMenuItem(title: settings.enabled ? "Turn QuietDesk Off" : "Turn QuietDesk On", action: #selector(toggleEnabled), keyEquivalent: "")
        power.target = self
        power.attributedTitle = NSAttributedString(string: power.title, attributes: [.font: NSFont.menuFont(ofSize: 0).withWeight(.semibold)])
        power.toolTip = settings.enabled ? "Restores the native desktop; the menu-bar icon stays." : "Hides Finder's desktop icons and draws them with names on hover."
        menu.addItem(power)
        menu.addItem(.separator())

        let items = NSMenuItem(title: "Desktop Items", action: nil, keyEquivalent: "")
        items.submenu = radioMenu([(title: "Visible", value: true), (title: "Hidden", value: false)], current: settings.itemsVisible, action: #selector(setItemsVisible(_:)), enabled: settings.enabled)
        items.isEnabled = settings.enabled
        menu.addItem(items)

        let labelsEnabled = settings.enabled && settings.itemsVisible
        let labels = NSMenuItem(title: labelsEnabled || !settings.enabled ? "Item Labels" : "Item Labels (items hidden)", action: nil, keyEquivalent: "")
        labels.submenu = labelsMenu(enabled: labelsEnabled)
        labels.isEnabled = labelsEnabled
        menu.addItem(labels)

        let sort = NSMenuItem(title: "Sort By", action: nil, keyEquivalent: "")
        sort.submenu = sortMenu(enabled: settings.enabled); sort.isEnabled = settings.enabled
        menu.addItem(sort)
        let stacks = NSMenuItem(title: "Stacks", action: nil, keyEquivalent: "")
        stacks.submenu = stacksMenu(enabled: settings.enabled); stacks.isEnabled = settings.enabled
        menu.addItem(stacks)
        let options = NSMenuItem(title: "Show View Options…", action: #selector(showViewOptions), keyEquivalent: "")
        options.target = self
        options.toolTip = "Icon size, grid spacing, text size, label position, item info, previews."
        menu.addItem(options)

        menu.addItem(.separator())
        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = LoginItem.isEnabled ? .on : .off
        login.isEnabled = LoginItem.isAvailable
        login.toolTip = LoginItem.isAvailable ? nil : "Available when running from QuietDesk.app"
        menu.addItem(login)
        let finderClick = NSMenuItem(title: "Bring Finder Forward on Desktop Click", action: #selector(toggleFinderClick), keyEquivalent: "")
        finderClick.target = self
        finderClick.state = settings.activateFinderOnDesktopClick ? .on : .off
        finderClick.toolTip = "On: the menu bar shows Finder when you click the desktop, as it does natively. Off: QuietDesk becomes the active app."
        menu.addItem(finderClick)
        let settingsItem = NSMenuItem(title: "Open Desktop & Dock Settings…", action: #selector(openDesktopSettings), keyEquivalent: "")
        settingsItem.target = self
        settingsItem.toolTip = "Fallback: the \"Show Items > On Desktop\" switch lives here if macOS ignores the automatic change."
        menu.addItem(settingsItem)
        let reload = NSMenuItem(title: "Reload Desktop", action: #selector(reloadDesktop), keyEquivalent: "")
        reload.target = self
        reload.isEnabled = settings.enabled
        menu.addItem(reload)
        menu.addItem(.separator())
        let about = NSMenuItem(title: "About QuietDesk", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        let quit = NSMenuItem(title: "Quit QuietDesk", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        quit.toolTip = "Quits and restores the native desktop. To keep the menu-bar icon, use Turn QuietDesk Off instead."
        menu.addItem(quit)
    }

    @objc private func showViewOptions() { ViewOptionsWindowController.shared.show() }

    @objc private func getInfoDesktop() {
        FinderAutomation.openInfoWindows(for: [DesktopModel.desktopURL]) { error in
            if let error { DesktopMenus.showError("Get Info needs Finder", error.description) }
        }
    }

    @objc private func changeWallpaper() { DesktopMenus.openWallpaperSettings() }

    @objc private func toggleUseStacks() {
        settings.stacksMode = stacksEnabledNow ? .off : settings.lastStacksGroup
        controller?.reloadAndRelayout()
        ViewOptionsWindowController.shared.refresh()
        rebuildMenu()
    }

    @objc private func toggleEnabled() {
        settings.enabled.toggle()
        if settings.enabled { enable() } else { disable() }
    }

    @objc private func setItemsVisible(_ sender: NSMenuItem) {
        guard let visible = sender.representedObject as? Bool else { return }
        settings.itemsVisible = visible
        if visible { controller?.show() } else { controller?.hide() }
        rebuildMenu()
    }

    @objc private func setLabelMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = LabelMode(rawValue: raw) else { return }
        settings.labelMode = mode
        controller?.labelMode = mode
        rebuildMenu()
    }

    @objc private func setSortKey(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let key = SortKey(rawValue: raw) else { return }
        settings.sortKey = key
        controller?.reloadAndRelayout()
        ViewOptionsWindowController.shared.refresh()
        rebuildMenu()
    }

    @objc private func setStacksMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = StacksMode(rawValue: raw) else { return }
        settings.stacksMode = mode
        controller?.reloadAndRelayout()
        ViewOptionsWindowController.shared.refresh()
        rebuildMenu()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            try LoginItem.setEnabled(!LoginItem.isEnabled)
            if LoginItem.requiresApproval {
                DesktopMenus.showError("Launch at Login needs your approval",
                                       "macOS wants you to confirm this in System Settings › General › Login Items & Extensions.")
                LoginItem.openSettings()
            }
        } catch { DesktopMenus.showError("Launch at Login could not be changed", error.localizedDescription) }
        rebuildMenu()
    }

    @objc private func toggleFinderClick() {
        settings.activateFinderOnDesktopClick.toggle()
        rebuildMenu()
    }

    @objc private func reloadDesktop() { controller?.reloadAndRelayout() }

    @objc private func openDesktopSettings() { DesktopMenus.openSystemSettings(pane: "com.apple.Desktop-Settings.extension") }

    @objc private func showAbout() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        let alert = NSAlert()
        alert.messageText = "QuietDesk \(version)"
        alert.informativeText = "Desktop icons where they are; names only when you need them.\nOpen source. No network, no analytics.\n\nWhile enabled, QuietDesk draws your desktop items itself and asks macOS to hide Finder's copies (System Settings › Desktop & Dock › Show Items). Quit to restore."
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: - Diagnostics

    /// Server-side hit tests: which window would receive a click at a few points?
    private func runHitTests() {
        guard let c = controller, let w = c.windows.first, let v = c.views.first, let cell = v.cells.first else { return }
        func test(_ label: String, _ viewPoint: NSPoint) {
            let screenPoint = w.convertPoint(toScreen: v.convert(viewPoint, to: nil))
            let n = NSWindow.windowNumber(at: screenPoint, belowWindowWithWindowNumber: 0)
            print("hit-test \(label) view=(\(Int(viewPoint.x)),\(Int(viewPoint.y))) -> window \(n) \(n == w.windowNumber ? "(QuietDesk)" : (c.shields.contains { $0.windowNumber == n } ? "(QuietDesk shield)" : "(other)"))")
        }
        test("icon centre", NSPoint(x: cell.iconRect.midX, y: cell.iconRect.midY))
        test("label area", NSPoint(x: cell.labelRect.midX, y: cell.labelRect.midY))
        test("between icon and label", NSPoint(x: cell.iconRect.midX, y: cell.iconRect.maxY + 1))
        test("gutter beside the cell", NSPoint(x: cell.cellRect.minX + 1, y: cell.iconRect.midY))
        for d in [8, 16, 24, 32, 48, 64] { test("\(d) px left of the window's first fill", NSPoint(x: cell.iconRect.minX - 4 - CGFloat(d), y: cell.iconRect.midY)) }
        test("window corner", NSPoint(x: 2, y: 2))
        print("QuietDesk window number \(w.windowNumber); level \(w.level.rawValue); shield level \(c.shields.first?.level.rawValue ?? 0)")
        // Z-order of our own windows (front to back), independent of whatever app windows cover the desktop.
        func order(_ label: String) {
            let list = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
            let mine = list.compactMap { e -> String? in
                guard let n = e[kCGWindowNumber as String] as? Int else { return nil }
                if c.windows.contains(where: { $0.windowNumber == n }) { return "icons#\(n)" }
                if c.shields.contains(where: { $0.windowNumber == n }) { return "shield#\(n)" }
                return nil
            }
            print("z-order \(label): " + mine.joined(separator: " > "))
        }
        order("at start")
        // Reproduce: activating the app (as opening View Options does) must not change who gets the click.
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            order("after app activation")
            ViewOptionsWindowController.shared.show()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                order("after View Options opened")
                ViewOptionsWindowController.shared.close()
                c.applyViewOptions(); c.reloadAndRelayout()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { order("after view-option relayout") }
            }
        }
    }
}

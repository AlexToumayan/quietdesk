import AppKit
import os

/// Owns one shield window and one icon window per screen, plus the model, layout, expanded
/// Stacks, Finder positions (manual layouts), thumbnail and iCloud-status hookups and the
/// change observers. Everything here is torn down completely when the utility is disabled.
final class OverlayController: DesktopSurfaceDelegate {
    private let log = Logger(subsystem: "dev.quietdesk.QuietDesk", category: "overlay")
    private(set) var windows: [OverlayWindow] = []     // icon windows (one per screen)
    private(set) var shields: [OverlayWindow] = []     // full-screen shield windows (one per screen)
    private(set) var views: [DesktopView] = []
    private var shieldViews: [ShieldView] = []
    private var watcher: DesktopWatcher?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var defaultObservers: [NSObjectProtocol] = []
    private(set) var prefs = FinderDesktopPrefs.load()
    private(set) var options = Settings.shared.effectiveViewOptions(finder: FinderDesktopPrefs.load())
    private(set) var model: DesktopModel?
    private var visible = false
    private var expandedStacks = Set<String>()
    private var finderPositions: [URL: CGPoint] = [:]
    private var positionsRequested = false
    private var positionsGeneration = 0
    private var localOverrides: [URL: (point: CGPoint, generation: Int)] = [:]
    private var pendingWrites = 0
    private var positionsUnavailable = false
    private var lastCloudStatus: [URL: CloudStatus] = [:]
    private var cloudMonitor: CloudStatusMonitor?
    private var knownModificationDates: [URL: Date] = [:]
    private let settings = Settings.shared
    /// Provided by the app delegate: Sort By / Stacks / Labels submenus for the desktop context menu.
    var menuExtrasProvider: (() -> [NSMenuItem])?

    var labelMode: LabelMode {
        didSet {
            views.forEach { $0.labelMode = labelMode }
            applyViewOptions()   // the compact grid depends on whether names are always shown
        }
    }

    /// `--no-hide` is an alignment check against Finder's own icons, so it always uses Finder's grid.
    var forceFinderGrid = false

    /// The compact grid applies only while names are hidden, and never to manual layouts
    /// (those positions are Finder's and live on Finder's grid).
    private func currentMetrics() -> GridMetrics {
        GridMetrics.from(options: options, compact: options.compactGrid && labelMode != .always && !forceFinderGrid && !(model?.isManual ?? false))
    }
    var usesCompactGrid: Bool { currentMetrics().compact }

    init(labelMode: LabelMode) {
        self.labelMode = labelMode
    }

    /// Builds the model and the windows without showing anything.
    func prepare() {
        reloadModel()
        makeWindows()
        ThumbnailCache.shared.onReady = { [weak self] url in self?.views.forEach { $0.invalidate(url: url) } }
        ItemInfoCache.shared.onReady = { [weak self] url in self?.views.forEach { $0.invalidate(url: url) } }
    }

    /// View Options changed (icon size, spacing, text size, label position, info, previews):
    /// recompute the grid from the current model without rescanning the folder.
    func applyViewOptions() {
        options = settings.effectiveViewOptions(finder: prefs)
        DebugLog.log("applyViewOptions icon=\(Int(options.iconSize)) spacing=\(Int(options.gridSpacing)) text=\(Int(options.textSize)) bottom=\(options.labelOnBottom) info=\(options.showItemInfo) previews=\(options.showIconPreview) cloud=\(options.showCloudStatus) hover=\(options.hoverReveal)")
        guard let model else { return }
        let metrics = currentMetrics()
        let layouts = layout(model, metrics: metrics)
        guard layouts.count == views.count else { rebuildWindows(); return }
        for ((window, view), layout) in zip(zip(windows, views), layouts) {
            let region = Layout.windowRegion(for: layout, metrics: metrics)
            window.setFrame(Layout.cocoaFrame(region, on: layout.screen), display: false)
            view.setFrameSize(region.size)
            view.metrics = metrics
            view.cells = layout.cells.map { $0.shifted(by: region.origin) }
        }
    }

    func show() {
        visible = true
        guard !steppedAside else { return }      // the desktop is revealed: stay out of the way
        shields.forEach { $0.orderFrontRegardless() }
        windows.forEach { $0.orderFrontRegardless() }   // icon windows above their shields
        traceWindows("show")
    }

    /// "Desktop Items › Hidden": the icons go away but the shields stay, so wallpaper clicks
    /// still never reach the system's click-catcher (which would re-show Finder's icons).
    func hide() {
        visible = false
        windows.forEach { $0.orderOut(nil) }
        if !steppedAside { shields.forEach { $0.orderFrontRegardless() } }
        traceWindows("hide")
    }

    func startWatching() {
        watcher = DesktopWatcher(url: DesktopModel.desktopURL) { [weak self] in self?.reloadAndRelayout() }
        let wc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            workspaceObservers.append(wc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.reloadAndRelayout() })
        }
        defaultObservers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.rebuildWindows() })
        // A window opening on top of the desktop (e.g. the file just double-clicked) does not
        // move the pointer, so no mouse-exited event arrives; end the hover when another app
        // comes forward or our panel loses keyboard focus.
        workspaceObservers.append(wc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if app?.processIdentifier != ProcessInfo.processInfo.processIdentifier { self?.views.forEach { $0.clearHover() } }
        })
        defaultObservers.append(NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, let w = note.object as? NSWindow, self.windows.contains(where: { $0 === w }) else { return }
            self.views.forEach { $0.clearHover() }
        })
        scheduleRevealCheck(every: 1.0)
        checkReveal()                               // enabled in the middle of a reveal: start out of the way
        // No reveal can start while the displays sleep or the session is switched out: no checks then.
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            workspaceObservers.append(wc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.revealTimer?.invalidate(); self?.revealTimer = nil
            })
        }
        for name in [NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            workspaceObservers.append(wc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let self, self.revealTimer == nil else { return }
                self.scheduleRevealCheck(every: self.steppedAside ? 0.25 : 1.0)
                self.checkReveal()
            })
        }
        let monitor = CloudStatusMonitor(directory: DesktopModel.desktopURL)
        monitor.onChange = { [weak self] in self?.cloudStatusChanged() }
        monitor.start()
        cloudMonitor = monitor
    }

    func stop() {
        revealTimer?.invalidate(); revealTimer = nil
        hide()
        watcher = nil
        cloudMonitor?.stop(); cloudMonitor = nil
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        defaultObservers.forEach { NotificationCenter.default.removeObserver($0) }
        workspaceObservers = []; defaultObservers = []
        windows.forEach { $0.close() }
        shields.forEach { $0.close() }
        windows = []; shields = []; views = []; shieldViews = []; model = nil
        ThumbnailCache.shared.cancelAll()
        ThumbnailCache.shared.removeAll()
        IconCache.shared.removeAll()
        ItemInfoCache.shared.removeAll()
    }

    func reloadAndRelayout() {
        reloadModel()
        guard let model else { return }
        let metrics = currentMetrics()
        let layouts = layout(model, metrics: metrics)
        guard layouts.count == views.count else { rebuildWindows(); return }
        for ((window, view), layout) in zip(zip(windows, views), layouts) {
            let region = Layout.windowRegion(for: layout, metrics: metrics)
            window.setFrame(Layout.cocoaFrame(region, on: layout.screen), display: false)
            view.setFrameSize(region.size)
            view.metrics = metrics
            view.cells = layout.cells.map { $0.shifted(by: region.origin) }
        }
        log.notice("relayout after desktop change: \(model.entries.count) entries")
        DebugLog.log("relayout: \(model.entries.count) entries, expanded=\(expandedStacks)")
        traceWindows("after relayout")
    }

    func rebuildWindows() {
        windows.forEach { $0.close() }
        shields.forEach { $0.close() }
        makeWindows()
        if visible { show() } else if !steppedAside { shields.forEach { $0.orderFrontRegardless() } }
    }

    var listingFailed: Bool { model?.listingFailed ?? false }
    var expandedStackTitles: Set<String> { expandedStacks }

    /// The window server's on-screen list lags a window ordering by a moment, so read it after the
    /// current turn of the run loop; otherwise the trace shows the previous generation of windows.
    private func traceWindows(_ what: String) {
        guard DebugLog.enabled else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else { return }
            DebugLog.log("\(what): \(DebugLog.windowOrder(icons: self.windows, shields: self.shields))")
        }
    }

    private func reloadModel() {
        prefs = FinderDesktopPrefs.load()
        options = settings.effectiveViewOptions(finder: prefs)
        model = DesktopModel.scan(prefs: prefs, settings: settings, expandedStacks: expandedStacks)
        invalidateChangedItems()
        if model?.isManual == true {
            if finderSyncsPositions { requestFinderPositionsIfNeeded() } else { seedLocalPositionsIfNeeded() }
        }
    }

    /// Only redraw the items whose iCloud status actually changed, and forget a "no thumbnail"
    /// verdict when a cloud-only file has finished downloading.
    private func cloudStatusChanged() {
        guard let model, let monitor = cloudMonitor else { return }
        var current: [URL: CloudStatus] = [:]
        var changed: [URL] = []
        func visit(_ item: DesktopItem) {
            let s = monitor.status(for: item.url)
            current[item.url] = s
            if lastCloudStatus[item.url] != s { changed.append(item.url) }
        }
        for entry in model.entries {
            switch entry {
            case .item(let i): visit(i)
            case .stack(let s): s.items.prefix(3).forEach(visit)
            }
        }
        lastCloudStatus = current
        for url in changed {
            if current[url] == .current { ThumbnailCache.shared.invalidate(url) }
            views.forEach { $0.forgetEligibility(of: url); $0.invalidate(url: url) }
        }
    }

    /// Drops cached thumbnails/icons for items whose modification date changed or that disappeared,
    /// so a replaced file (atomic save) gets a fresh preview. Everything else stays cached.
    private func invalidateChangedItems() {
        guard let model else { return }
        var current: [URL: Date] = [:]
        func visit(_ item: DesktopItem) { current[item.url] = item.dateModified }
        for entry in model.entries {
            switch entry {
            case .item(let i): visit(i)
            case .stack(let s): s.items.forEach(visit)
            }
        }
        for (url, date) in knownModificationDates where current[url] != date {
            ThumbnailCache.shared.invalidate(url)
            IconCache.shared.invalidate(url)
            ItemInfoCache.shared.invalidate(url)
            views.forEach { $0.forgetEligibility(of: url) }
        }
        knownModificationDates = current
    }

    /// Finder is the source and sink of icon positions only while Finder's OWN desktop is
    /// manually arranged; otherwise its stored positions are stale (FEASIBILITY E2) and writing
    /// them would be meaningless. When QuietDesk is set to "None (Finder Positions)" on a sorted
    /// Finder desktop, positions live in QuietDesk's own preferences instead.
    private var finderSyncsPositions: Bool { prefs.arrangeBy == .none || prefs.arrangeBy == .grid }

    private var localPositions: [URL: CGPoint] {
        get {
            let raw = Settings.defaults.dictionary(forKey: "localPositions") as? [String: [Double]] ?? [:]
            return raw.reduce(into: [:]) { out, kv in
                if kv.value.count == 2 { out[URL(fileURLWithPath: kv.key).standardizedFileURL] = CGPoint(x: kv.value[0], y: kv.value[1]) }
            }
        }
        set {
            let raw = newValue.reduce(into: [String: [Double]]()) { out, kv in out[kv.key.path] = [kv.value.x, kv.value.y] }
            Settings.defaults.set(raw, forKey: "localPositions")
        }
    }

    /// First switch to app-local manual mode: start from where the icons are right now (Finder's
    /// sorted grid), like Finder does when Sort By is turned off.
    private func seedLocalPositionsIfNeeded() {
        guard let model, localPositions.isEmpty else { return }
        var seeded: [URL: CGPoint] = [:]
        let sortedModel = DesktopModel.scan(prefs: prefs, settings: Settings.shared, expandedStacks: [], now: Date(), forceArrangeBy: prefs.arrangeBy)
        let metrics = GridMetrics.from(options: options)   // Finder's own grid: these become Finder-style positions
        for layout in Layout.compute(entries: sortedModel.entries, screens: NSScreen.screens, metrics: metrics) {
            for cell in layout.cells {
                guard let url = cell.entry.url?.standardizedFileURL else { continue }
                seeded[url] = Layout.finderPoint(localIconCentre: NSPoint(x: cell.iconRect.midX, y: cell.iconRect.midY), on: layout.screen, screens: NSScreen.screens)
            }
        }
        _ = model
        localPositions = seeded
    }

    private func layout(_ model: DesktopModel, metrics: GridMetrics) -> [ScreenLayout] {
        if model.isManual {
            let positions = finderSyncsPositions ? finderPositions : localPositions
            return Layout.computeManual(entries: model.entries, positions: positions, screens: NSScreen.screens, metrics: metrics, snapToGrid: model.arrangeBy == .grid)
        }
        return Layout.compute(entries: model.entries, screens: NSScreen.screens, metrics: metrics)
    }

    private func makeWindows() {
        guard let model else { return }
        let metrics = currentMetrics()
        let layouts = layout(model, metrics: metrics)
        windows = []; shields = []; views = []; shieldViews = []
        for layout in layouts {
            let shield = OverlayWindow(frame: layout.screen.frame, canBecomeKey: false, levelOffset: 1)
            let shieldView = ShieldView(frame: NSRect(origin: .zero, size: layout.screen.frame.size))
            shieldView.delegate = self
            shield.contentView = shieldView

            let region = Layout.windowRegion(for: layout, metrics: metrics)
            let window = OverlayWindow(frame: Layout.cocoaFrame(region, on: layout.screen), levelOffset: 2)
            let view = DesktopView(frame: NSRect(origin: .zero, size: region.size), metrics: metrics)
            view.labelMode = labelMode
            view.delegate = self
            view.cells = layout.cells.map { $0.shifted(by: region.origin) }
            view.bandHost = shieldView
            shieldView.iconView = view
            window.contentView = view

            shields.append(shield); shieldViews.append(shieldView)
            windows.append(window); views.append(view)
        }
    }

    // MARK: - Manual layouts: positions from Finder

    private func requestFinderPositionsIfNeeded() {
        guard finderSyncsPositions, !positionsUnavailable, !positionsRequested else { return }
        positionsRequested = true
        let issued = positionsGeneration
        FinderAutomation.readDesktopPositions { [weak self] result in
            guard let self else { return }
            self.positionsRequested = false
            switch result {
            case .success(var positions):
                // Drags that happened while this read was in flight win over what Finder held then.
                for (url, o) in self.localOverrides where o.generation >= issued { positions[url] = o.point }
                self.localOverrides = self.localOverrides.filter { $0.value.generation >= issued }
                self.finderPositions = positions
                self.relayoutOnly()
            case .failure(let error):
                self.log.notice("Finder positions unavailable: \(String(describing: error))")
                if case .notPermitted = error {
                    self.positionsUnavailable = true
                    DesktopMenus.showError("Icon positions need Finder", error.description + "\n\nUntil then QuietDesk arranges the desktop in a grid.")
                }
            }
        }
    }

    private func relayoutOnly() {
        guard let model else { return }
        let metrics = currentMetrics()
        let layouts = layout(model, metrics: metrics)
        guard layouts.count == views.count else { rebuildWindows(); return }
        for ((window, view), layout) in zip(zip(windows, views), layouts) {
            let region = Layout.windowRegion(for: layout, metrics: metrics)
            window.setFrame(Layout.cocoaFrame(region, on: layout.screen), display: false)
            view.setFrameSize(region.size)
            view.cells = layout.cells.map { $0.shifted(by: region.origin) }
        }
    }

    // MARK: - DesktopSurfaceDelegate

    var showsPreviews: Bool { options.showIconPreview }
    var showsItemInfo: Bool { options.showItemInfo }
    var showsCloudStatus: Bool { options.showCloudStatus }
    var hoverRevealRadius: Int { options.hoverReveal }

    // MARK: - Reveal desktop (Show Desktop): step aside while it lasts

    private var revealTimer: Timer?
    /// True while the desktop is revealed and QuietDesk's windows are out of the way.
    private(set) var steppedAside = false
    /// Off in tests that click the wallpaper but must not fling the person's windows about.
    var revealOnWallpaperClick = true
    private(set) var wallpaperClicks = 0

    /// The system gives no event for a reveal starting or ending (FEASIBILITY E14), so the state
    /// is read from the window list: once a second with generous tolerance at rest (about 1 ms
    /// each), four times a second while revealed so the desktop comes back promptly.
    private func scheduleRevealCheck(every interval: TimeInterval) {
        revealTimer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.checkReveal() }
        timer.tolerance = interval / 2
        RunLoop.main.add(timer, forMode: .common)
        revealTimer = timer
    }

    func checkReveal() {
        let revealed = DesktopReveal.isRevealed
        guard revealed != steppedAside else { return }
        steppedAside = revealed
        DebugLog.log(revealed ? "desktop revealed: stepping aside" : "reveal ended: coming back")
        if revealed {
            // macOS is showing Finder's own items now; ours on top would be doubles. A rename in
            // progress ends quietly first: no alert from inside a timer, and no second commit when
            // ordering the key window out makes it resign key.
            views.forEach { $0.finishRenameQuietly(); $0.clearHover() }
            windows.forEach { $0.orderOut(nil) }
            shields.forEach { $0.orderOut(nil) }
            scheduleRevealCheck(every: 0.25)
        } else {
            if visible { show() } else { shields.forEach { $0.orderFrontRegardless() } }
            scheduleRevealCheck(every: 1.0)
        }
    }

    /// Set when a reveal we asked for never showed up in the window list: either the Dock ignored
    /// the request or the detection no longer matches this macOS. Revealing without being able to
    /// step aside would leave doubled icons, so wallpaper clicks stop asking for the session.
    private var revealUnseen = false

    func surfaceWallpaperClicked() {
        wallpaperClicks += 1
        guard revealOnWallpaperClick, settings.revealDesktopOnWallpaperClick, !revealUnseen, DesktopReveal.clickRevealsDesktop else { return }
        let sent = DesktopReveal.toggle()
        DebugLog.log("wallpaper click -> show desktop (\(sent ? "sent" : "entry point unavailable"))")
        guard sent else { revealUnseen = true; return }
        // The Dock needs a moment; look again shortly rather than waiting for the slow tick.
        for delay in [0.15, 0.35, 0.7] { DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.checkReveal() } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self, self.revealTimer != nil || self.steppedAside else { return }
            self.checkReveal()
            if !self.steppedAside {
                self.revealUnseen = true
                self.log.notice("a requested reveal was never observed; wallpaper clicks will only deselect until QuietDesk is turned off and on")
                DebugLog.log("reveal requested but never observed: wallpaper-click reveal off for this session")
            }
        }
    }

    func surfaceCollapseStacks() {
        guard !expandedStacks.isEmpty else { return }
        expandedStacks.removeAll()
        reloadAndRelayout()
    }
    var isManualLayout: Bool { model?.isManual ?? false }

    private var keyReassertObserver: NSObjectProtocol?

    func surfaceDidReceiveClick() {
        DebugLog.log("surfaceDidReceiveClick bringFinderForward=\(settings.activateFinderOnDesktopClick) active=\(NSApp.isActive) front=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?") key=\(windows.first(where: { $0.isKeyWindow })?.windowNumber ?? 0)")
        guard settings.activateFinderOnDesktopClick else { NSApp.activate(ignoringOtherApps: true); return }
        guard let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first, !finder.isActive,
              let keyWindow = windows.first(where: { $0.isKeyWindow }) else { return }
        // Bring Finder forward so the menu bar reads "Finder" as on the native desktop. Its
        // activation completes asynchronously and may take key status away from our
        // non-activating panel; if that happens within the next moment, take it back once.
        if let o = keyReassertObserver { NotificationCenter.default.removeObserver(o) }
        keyReassertObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: keyWindow, queue: .main) { [weak self, weak keyWindow] _ in
            if let o = self?.keyReassertObserver { NotificationCenter.default.removeObserver(o); self?.keyReassertObserver = nil }
            keyWindow?.makeKey()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            if let o = self?.keyReassertObserver { NotificationCenter.default.removeObserver(o); self?.keyReassertObserver = nil }
        }
        // macOS 14 cooperative activation: while QuietDesk is the active app (View Options, Quick
        // Look, a menu) it must PASS activation with activate(from:); otherwise the click the person
        // just made on our panel entitles a plain activate(). NSApp.isActive can read true while
        // Finder is frontmost (accessory app with a key panel), so try the hand-off first and fall back.
        var ok = NSApp.isActive && finder.activate(from: .current, options: [])
        if !ok { ok = finder.activate() }
        DebugLog.log("finder.activate -> \(ok)")
    }

    func surface(toggleStack stack: StackGroup) {
        // One Stack open at a time, like Finder.
        if expandedStacks.contains(stack.title) { expandedStacks.removeAll() } else { expandedStacks = [stack.title] }
        DebugLog.log("toggleStack '\(stack.title)' -> expanded=\(expandedStacks)")
        reloadAndRelayout()
    }

    func surface(reposition centres: [URL: NSPoint], on screen: NSScreen) {
        var local = localPositions
        for (url, centre) in centres {
            let point = Layout.finderPoint(localIconCentre: centre, on: screen, screens: NSScreen.screens)
            let key = url.standardizedFileURL
            if finderSyncsPositions {
                positionsGeneration += 1
                localOverrides[key] = (point, positionsGeneration)
                finderPositions[key] = point
                pendingWrites += 1
                FinderAutomation.writeDesktopPosition(point, for: url) { [weak self] error in
                    guard let self else { return }
                    self.pendingWrites -= 1
                    if let error { self.log.notice("could not store position in Finder: \(String(describing: error))") }
                    if self.pendingWrites == 0 { self.requestFinderPositionsIfNeeded() }   // re-sync once per batch of drags
                }
            } else {
                local[key] = point
            }
        }
        if !finderSyncsPositions { localPositions = local }
        relayoutOnly()
    }

    func surfaceMenuExtras() -> [NSMenuItem] { menuExtrasProvider?() ?? [] }

    func surface(cloudStatusFor url: URL) -> CloudStatus { cloudMonitor?.status(for: url) ?? .notInCloud }

    func surfaceRequestsReload() { reloadAndRelayout() }

    // MARK: - Diagnostics used by the command-line test flags

    func layoutDescription() -> String {
        guard let model else { return "no model" }
        var out = "view options: icon=\(Int(options.iconSize)) text=\(Int(options.textSize)) spacing=\(Int(options.gridSpacing)) labelOnBottom=\(options.labelOnBottom) info=\(options.showItemInfo) previews=\(options.showIconPreview) (Finder: spacing=\(Int(prefs.gridSpacing))) arrangeBy=\(model.arrangeBy) groupBy=\(model.groupBy) stacks=\(model.stacksEnabled) manual=\(model.isManual)\n"
        out += "entries: \(model.entries.count) (items scanned: \(model.itemCount))\n"
        let metrics = currentMetrics()
        for (si, layout) in self.layout(model, metrics: metrics).enumerated() {
            let region = Layout.windowRegion(for: layout, metrics: metrics)
            out += "screen \(si) \(layout.screen.localizedName) \(Int(layout.screen.frame.width))x\(Int(layout.screen.frame.height)) grid \(layout.columns)x\(layout.rows) cell \(Int(metrics.cellWidth))x\(Int(metrics.cellHeight)) used \(layout.cells.count) window region \(Int(region.minX)),\(Int(region.minY)) \(Int(region.width))x\(Int(region.height))\n"
            for c in layout.cells {
                let kind: String
                switch c.entry {
                case .stack(let s): kind = "STACK(\(s.items.count))"
                case .item(let i): kind = i.isVolume ? "VOLUME" : (i.isFolder ? "folder" : (i.stackTitle != nil ? "in-stack" : "file"))
                }
                out += String(format: "  c%02d r%02d  icon@(%4d,%4d)  %@  %@\n", c.col, c.row, Int(c.iconRect.midX), Int(c.iconRect.midY), kind, c.entry.displayName)
            }
        }
        return out
    }

    /// Renders one screen's overlay over a flat background into a PNG (for offline checks).
    func renderPNG(screenIndex: Int, to url: URL, hover: Int?) throws {
        guard screenIndex < views.count else { return }
        let view = views[screenIndex]
        let size = view.bounds.size
        let scale: CGFloat = 2
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        rep.size = size
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        NSColor(calibratedRed: 0.38, green: 0.55, blue: 0.68, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()
        if let hover { view.simulateHover(hover) }
        view.displayIgnoringOpacity(view.bounds, in: ctx)
        NSGraphicsContext.restoreGraphicsState()
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try data.write(to: url)
    }

    /// Expands a stack by title (used by --render for offline checks).
    func expandStackForTesting(_ title: String) {
        expandedStacks.insert(title)
        reloadAndRelayout()
    }
}

import AppKit

/// `--scenario-test`: drives the real overlay windows with synthesized mouse events sent through
/// NSApp.sendEvent, so window routing, key-window handling and Finder activation all take part.
/// It replays what a person does (expand a Stack, click a member, double-click to open, click
/// the wallpaper) before and after every View Options change, with Finder brought forward
/// between clicks as on the real desktop. Clicks stay at one screen point like a real pointer,
/// so a relayout that moves the icon window away routes the next click to the shield.
///
/// Run with a private preferences suite and, in CI, a fixture folder:
///   QuietDesk --scenario-test --defaults-suite dev.quietdesk.scenario [--desktop-dir PATH]
/// The native desktop is never touched (no hide key). Exit status 0 = every check passed.
final class ScenarioTest {
    private let controller: OverlayController
    private var failures: [String] = []
    private var checks = 0
    private var opened: [URL] = []
    private var steps: [(name: String, body: () -> Void)] = []
    private var eventNumber = 1000
    private var round = ""
    private var frontWasOurs = true

    private let withReveal = CommandLine.arguments.contains("--with-reveal")

    /// The simulated reveal: what the probe reports, how many reveals were asked for, a clock the
    /// round moves by hand, and the controller's delayed follow-up checks with the time each is due,
    /// captured so the rounds below can run them in order.
    private var revealed = false
    private var revealToggles = 0
    private var revealClock: TimeInterval = 1000
    private var pendingReveal: [(due: TimeInterval, body: () -> Void)] = []
    /// How much time passed that the round's clock did not see, the way a sleep does: the delayed
    /// blocks wait on a clock that stops, so they run at wake with the world much older than they
    /// think. Rounds add to this to sleep the Mac without sleeping the Mac.
    private var revealSleepOffset: TimeInterval = 0

    init(controller: OverlayController) {
        self.controller = controller
        controller.revealOnWallpaperClick = false   // never fling the person's windows about by surprise
        DesktopView.openHandler = { [weak self] urls in self?.opened += urls }
    }

    // MARK: - Driving

    /// The icon view with the most cells (the main display's).
    private var view: DesktopView? { controller.views.max { $0.cells.count < $1.cells.count } }

    private func send(_ type: NSEvent.EventType, window: NSWindow, at windowPoint: NSPoint, clickCount: Int) {
        eventNumber += 1
        guard let e = NSEvent.mouseEvent(with: type, location: windowPoint, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                         windowNumber: window.windowNumber, context: nil, eventNumber: eventNumber, clickCount: clickCount,
                                         pressure: type == .leftMouseUp ? 0 : 1) else { return }
        NSApp.sendEvent(e)
    }

    /// Each event goes to whichever of our windows is under the screen point at that moment.
    private func click(_ cell: LayoutCell, count: Int = 1) {
        guard let view, let w = view.window else { return }
        let screenPoint = w.convertPoint(toScreen: view.convert(NSPoint(x: cell.iconRect.midX, y: cell.iconRect.midY), to: nil))
        for c in 1...count {
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let icons = controller.windows.first { $0.isVisible && $0.frame.contains(screenPoint) }
                let target: NSWindow = icons ?? controller.shields.first { $0.frame.contains(screenPoint) } ?? w
                send(type, window: target, at: target.convertPoint(fromScreen: screenPoint), clickCount: c)
            }
        }
    }

    /// `gap` is how long since the previous click, on the simulated clock.
    private func clickWallpaper(after gap: TimeInterval = 2.0) {
        revealClock += gap
        guard let shield = controller.shields.first, let sv = shield.contentView else { return }
        let p = sv.convert(NSPoint(x: 40, y: 200), to: nil)   // far from the icon column
        send(.leftMouseDown, window: shield, at: p, clickCount: 1)
        send(.leftMouseUp, window: shield, at: p, clickCount: 1)
    }

    /// Moves the clock on by `gap`, running every captured follow-up check that falls due on the
    /// way, and then clicks. That is how a steady rhythm of clicks really arrives: the re-checks and
    /// the verdict a click schedules run in the gaps between clicks, not in a batch at the end.
    private func clickWallpaperInRhythm(after gap: TimeInterval) {
        let target = revealClock + gap
        while let i = pendingReveal.indices
            .filter({ pendingReveal[$0].due <= target })
            .min(by: { pendingReveal[$0].due < pendingReveal[$1].due }) {
            let item = pendingReveal.remove(at: i)
            revealClock = max(revealClock, item.due)
            item.body()
        }
        revealClock = target
        clickWallpaper(after: 0)
    }

    /// Runs the next captured follow-up check, earliest first, moving the clock to when it is due.
    private func runNextPendingReveal() {
        guard let i = pendingReveal.indices.min(by: { pendingReveal[$0].due < pendingReveal[$1].due }) else { return }
        let item = pendingReveal.remove(at: i)
        revealClock = max(revealClock, item.due)
        item.body()
    }

    /// Runs the next few captured follow-up checks.
    private func runPendingReveal(_ count: Int) {
        for _ in 0..<count where !pendingReveal.isEmpty { runNextPendingReveal() }
    }

    /// Runs every captured follow-up check, including the ones those checks schedule.
    private func drainReveal() {
        var safety = 40
        while !pendingReveal.isEmpty, safety > 0 { safety -= 1; runNextPendingReveal() }
    }

    /// One read of the window list, as a timer tick makes it: the clock moves on first.
    private func readReveal(after gap: TimeInterval = 0.25) {
        revealClock += gap
        controller.checkReveal()
    }

    /// One read plus everything it schedules (the end of a reveal takes a later read to confirm).
    private func tickReveal() {
        readReveal()
        drainReveal()
    }

    /// Puts the simulated reveal in place of the real one: nothing asks the Dock, no window on
    /// this screen moves, and the delays are the round's own clock. The clock carries on from the
    /// round before. The person's own wallpaper-click preference is put back afterwards.
    private var revealSettingWas = false
    private func installRevealSeams() {
        revealSettingWas = Settings.shared.revealDesktopOnWallpaperClick
        Settings.shared.revealDesktopOnWallpaperClick = true
        revealed = false; pendingReveal = []; revealSleepOffset = 0
        controller.revealProbe = { [self] in revealed }
        controller.revealToggle = { [self] in revealToggles += 1; return true }
        controller.revealGestureEnabled = { true }
        controller.revealAfter = { [self] delay, body in pendingReveal.append((revealClock + delay, body)) }
        controller.revealNow = { [self] in revealClock }
        controller.revealSleepProofNow = { [self] in revealClock + revealSleepOffset }
        controller.revealOnWallpaperClick = true
    }

    private func removeRevealSeams() {
        controller.revealOnWallpaperClick = false
        controller.revealProbe = { DesktopReveal.isRevealed }
        controller.revealToggle = { DesktopReveal.toggle() }
        controller.revealGestureEnabled = { DesktopReveal.clickRevealsDesktop }
        controller.revealAfter = { delay, body in DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: body) }
        controller.revealNow = { ProcessInfo.processInfo.systemUptime }
        controller.revealSleepProofNow = { TimeInterval(clock_gettime_nsec_np(CLOCK_MONOTONIC)) / 1_000_000_000 }
        Settings.shared.revealDesktopOnWallpaperClick = revealSettingWas
        pendingReveal = []; revealSleepOffset = 0
    }

    private func expect(_ condition: Bool, _ message: @autoclosure () -> String) {
        checks += 1
        if !condition {
            let m = "[\(round)] \(message())"
            failures.append(m)
            print("FAIL \(m)")
        }
    }

    private var stackCell: LayoutCell? { view?.cells.first { $0.entry.isStack } }
    private var folderCell: LayoutCell? {
        view?.cells.first { ($0.entry.item?.isFolder ?? false) && !($0.entry.item?.isVolume ?? true) && $0.entry.item?.stackTitle == nil }
    }
    private func member(of title: String) -> LayoutCell? { view?.cells.first { $0.entry.item?.stackTitle == title } }
    private var expanded: Set<String> { controller.expandedStackTitles }

    private func orderIsRight() -> Bool {
        let order = DebugLog.windowOrder(icons: controller.windows, shields: controller.shields)
        // Front to back: every icon window must come before every shield.
        let parts = order.split(separator: ">").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let lastIcon = parts.lastIndex(where: { $0.hasPrefix("icons#") }), let firstShield = parts.firstIndex(where: { $0.hasPrefix("shield#") }) else { return false }
        return lastIcon < firstShield
    }

    // MARK: - One round of the click paths people use

    private func addRound(_ name: String, stacks: Bool = true, setup: @escaping () -> Void) {
        steps.append((name, { [self] in round = name; setup(); controller.surfaceCollapseStacks() }))
        steps.append(("overlay present", { [self] in
            expect(view != nil && !(view?.cells.isEmpty ?? true), "the overlay should have an icon view with cells")
            expect(orderIsRight(), "icon windows must be in front of the shields: \(DebugLog.windowOrder(icons: controller.windows, shields: controller.shields))")
            expect((stackCell != nil) == stacks, stacks ? "expected a Stack on the desktop" : "expected no Stacks while Stacks are off")
        }))
        steps.append(("double-click on a folder opens it", { [self] in
            guard let f = folderCell, let url = f.entry.url else { expect(false, "no folder on the desktop to test with"); return }
            opened = []
            click(f, count: 2)
            expect(opened == [url], "double-click on a folder should open it (opened: \(opened.count))")
        }))
        guard stacks else { return }
        steps.append(("Finder comes forward after a desktop click", { [self] in
            guard Settings.shared.activateFinderOnDesktopClick, let f = folderCell else { return }
            let front = NSWorkspace.shared.frontmostApplication
            frontWasOurs = front?.bundleIdentifier == "com.apple.finder" || front?.processIdentifier == ProcessInfo.processInfo.processIdentifier
            click(f)   // one click; the activation completes asynchronously before the next step
        }))
        steps.append(("Finder is the active app", { [self] in
            guard Settings.shared.activateFinderOnDesktopClick else { return }
            let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first
            let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"
            // Locked screen or a headless CI session: nothing can be frontmost, so nothing to check.
            if front == "com.apple.loginwindow" || front == "?" { print("skip: no frontmost app to hand off to (\(front))"); return }
            // Someone is working in another app: a synthesized click is not user input, so macOS
            // rightly refuses to take the foreground away from them. A real click is allowed to.
            if !frontWasOurs { print("skip: another app was frontmost before the click (\(front))"); return }
            // NSApp.isActive is not the criterion: an accessory app with a key panel can report
            // itself active while Finder owns the menu bar. What people see is the frontmost app.
            expect(front == "com.apple.finder" && finder?.isActive == true, "with Bring Finder Forward on, Finder should be frontmost after a desktop click (front: \(front))")
        }))
        steps.append(("stack expands on a single click", { [self] in
            guard let s = stackCell, let title = s.entry.stack?.title, let before = view?.cells.count else { return }
            click(s)
            expect(expanded == [title], "click on Stack '\(title)' should expand it (expanded: \(expanded))")
            expect((view?.cells.count ?? 0) > before, "expanding should add the Stack's members to the layout (\(before) -> \(view?.cells.count ?? 0))")
            expect(member(of: title) != nil, "members of '\(title)' should be laid out")
        }))
        steps.append(("member click keeps the Stack open", { [self] in
            guard let title = expanded.first, let m = member(of: title), let view else { return }
            click(m)
            expect(expanded == [title], "clicking a member must not collapse the Stack")
            expect(view.selection.contains(where: { view.cells[$0].entry.url == m.entry.url }), "the clicked member should be selected")
        }))
        steps.append(("double-click on a member opens it", { [self] in
            guard let title = expanded.first, let m = member(of: title), let url = m.entry.url else { return }
            opened = []
            click(m, count: 2)
            expect(opened == [url], "double-click on a member should open exactly it (opened: \(opened.count))")
        }))
        steps.append(("second click on the Stack collapses it", { [self] in
            guard let s = stackCell else { return }
            click(s)
            expect(expanded.isEmpty, "second click on the Stack should collapse it")
        }))
        steps.append(("double-click on a Stack toggles it once and opens nothing", { [self] in
            guard let s = stackCell, let title = s.entry.stack?.title else { return }
            opened = []
            click(s, count: 2)
            expect(expanded == [title], "a double-click on a closed Stack should leave it open")
            expect(opened.isEmpty, "a double-click on a Stack must not open a Finder window")
            controller.surfaceCollapseStacks()
        }))
        steps.append(("double-click on a folder while a Stack is open", { [self] in
            guard let s = stackCell, let title = s.entry.stack?.title else { return }
            click(s)
            expect(expanded == [title], "Stack should be open before the folder click")
            guard let f = folderCell, let url = f.entry.url else { return }
            opened = []
            click(f, count: 2)
            expect(expanded.isEmpty, "clicking a folder should collapse the open Stack")
            expect(opened == [url], "the folder should still open after the collapse relayout (opened: \(opened.count))")
        }))
        steps.append(("wallpaper click collapses a Stack", { [self] in
            guard let s = stackCell else { return }
            click(s)
            let before = controller.wallpaperClicks
            clickWallpaper()
            expect(expanded.isEmpty, "a click on the wallpaper should collapse the Stack")
            expect(view?.selection.isEmpty ?? false, "a click on the wallpaper should clear the selection")
            expect(controller.wallpaperClicks == before + 1, "a plain click on the wallpaper should be reported as one")
        }))
        steps.append(("hover then click", { [self] in
            guard let s = stackCell, let view, let i = view.cells.firstIndex(where: { $0.entry.isStack }) else { return }
            view.setHover(i)
            click(s)
            expect(expanded.count == 1, "a click on a hovered Stack should expand it")
            view.clearHover()
            controller.surfaceCollapseStacks()
        }))
    }

    /// The live view must actually be on the grid the round asked for.
    private func expectGrid(compact: Bool) {
        steps.append(("grid is \(compact ? "compact" : "Finder's")", { [self] in
            guard let view else { return }
            let o = Settings.shared.effectiveViewOptions(finder: controller.prefs)
            let expected = GridMetrics.from(options: o, compact: compact)
            expect(view.metrics.compact == compact, "metrics.compact should be \(compact)")
            expect(view.metrics.cellHeight == expected.cellHeight, "cell height \(view.metrics.cellHeight) should be \(expected.cellHeight)")
            expect(view.cells.allSatisfy { compact ? $0.labelRect.height == 0 : $0.labelRect.height > 0 }, "label boxes should be \(compact ? "empty" : "present")")
        }))
    }

    private func change(_ mutate: @escaping (inout ViewOptions) -> Void) -> () -> Void {
        { [self] in
            var o = Settings.shared.effectiveViewOptions(finder: controller.prefs)
            mutate(&o)
            Settings.shared.viewOptions = o
            ViewOptionsWindowController.shared.onChange?()   // exactly what the panel's controls do
        }
    }

    func start() {
        let vo = ViewOptionsWindowController.shared
        let s = Settings.shared
        // Deterministic starting point in the private suite: Stacks and Sort By Date Added.
        s.stacksMode = .dateAdded; s.sortKey = .dateAdded
        s.viewOptions = ViewOptions(iconSize: 36, gridSpacing: 26, textSize: 12, labelOnBottom: true, showItemInfo: false, showIconPreview: true)
        s.activateFinderOnDesktopClick = true
        vo.onChange?()

        addRound("baseline, Finder active") { NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first?.activate() }
        addRound("QuietDesk active") { NSApp.activate(ignoringOtherApps: true) }
        addRound("View Options open") { vo.show() }
        addRound("iCloud status off", setup: change { $0.showCloudStatus = false })
        addRound("names on hover: wider area", setup: change { $0.hoverReveal = 2 })
        addRound("icon size 48", setup: change { $0.iconSize = 48 })
        addRound("grid spacing 1", setup: change { $0.gridSpacing = 1 })
        addRound("text size 14", setup: change { $0.textSize = 14 })
        addRound("labels on the right", setup: change { $0.labelOnBottom = false })
        addRound("item info on, previews off", setup: change { $0.showItemInfo = true; $0.showIconPreview = false })
        addRound("compact grid off (Finder's grid)", setup: change { $0.compactGrid = false })
        expectGrid(compact: false)
        addRound("compact grid on again", setup: change { $0.compactGrid = true })
        expectGrid(compact: true)
        addRound("names always visible") { [self] in s.labelMode = .always; controller.labelMode = .always }
        expectGrid(compact: false)
        addRound("names on hover again") { [self] in s.labelMode = .hover; controller.labelMode = .hover }
        expectGrid(compact: true)
        addRound("Finder's icon size, spacing and text") { s.viewOptions = nil; vo.onChange?() }
        addRound("Stacks off", stacks: false) { s.stacksMode = .off; vo.onChange?() }
        addRound("Stacks by Kind") { s.stacksMode = .kind; vo.onChange?() }
        addRound("Stacks by Date Added, Sort By Name") { s.stacksMode = .dateAdded; s.sortKey = .name; vo.onChange?() }
        // Sort By > None on a Finder-sorted desktop: QuietDesk's own positions, Finder's grid. Only
        // where Finder itself is sorted; otherwise positions come from Finder over Apple Events,
        // which needs an Automation consent nobody can give in a test run.
        if controller.prefs.arrangeBy != .none && controller.prefs.arrangeBy != .grid {
            addRound("Sort By None (manual layout, own positions)") { s.sortKey = SortKey.none; vo.onChange?() }
            steps.append(("layout is manual", { [self] in expect(controller.isManualLayout, "Sort By None should give a manual layout") }))
            expectGrid(compact: false)
            addRound("Sort By Date Added again") { s.sortKey = .dateAdded; vo.onChange?() }
            steps.append(("layout is sorted again", { [self] in expect(!controller.isManualLayout, "Sort By Date Added should leave manual mode") }))
            expectGrid(compact: true)
        } else {
            print("skip: manual-layout round (Finder is not sorted here, positions would need Finder automation)")
        }
        addRound("View Options closed") { vo.close() }
        addRound("items hidden then shown again") { [self] in controller.hide(); controller.show() }
        addRound("Bring Finder Forward off") { s.activateFinderOnDesktopClick = false }
        addRound("Bring Finder Forward on again") { s.activateFinderOnDesktopClick = true }
        addRound("reload desktop") { [self] in controller.reloadAndRelayout() }
        // A simulated reveal through the test seam: the whole step-aside state machine, no real reveal.
        steps.append(("simulated reveal: step aside", { [self] in
            round = "simulated reveal"
            controller.revealProbe = { true }
            controller.checkReveal()
            expect(controller.steppedAside, "QuietDesk should step aside when the desktop is revealed")
            expect(controller.windows.allSatisfy { !$0.isVisible } && controller.shields.allSatisfy { !$0.isVisible }, "no QuietDesk window should be on screen during a reveal")
            controller.reloadAndRelayout(); controller.applyViewOptions(); controller.show()
            expect(controller.windows.allSatisfy { !$0.isVisible } && controller.shields.allSatisfy { !$0.isVisible }, "a relayout, a view-option change or show() during a reveal must not bring the windows back")
        }))
        steps.append(("simulated reveal: come back", { [self] in
            controller.revealProbe = { false }
            controller.checkReveal()
            expect(controller.steppedAside, "one read saying the reveal ended is not enough to come back")
            controller.checkReveal()
            expect(controller.steppedAside, "a second read straight afterwards is not enough either")
        }))
        steps.append(("simulated reveal: back on screen", { [self] in
            expect(!controller.steppedAside, "QuietDesk should come back a moment after the reveal ends")
            expect(controller.windows.contains { $0.isVisible } && controller.shields.allSatisfy { $0.isVisible }, "QuietDesk's windows should be back on screen")
            controller.revealProbe = { DesktopReveal.isRevealed }
        }))
        steps.append(("a click in a gap between icons is a wallpaper click", { [self] in
            guard let view, let w = view.window, let cell = view.cells.first(where: { !$0.entry.isStack }) else { return }
            // The cell's bottom-left corner: inside the icon window, outside every icon and name.
            let p = NSPoint(x: cell.cellRect.minX + 1, y: cell.cellRect.maxY - 1)
            guard view.cellIndex(at: p) == nil else { print("skip: no gap at the probe point on this grid"); return }
            let before = controller.wallpaperClicks
            let wp = view.convert(p, to: nil)
            send(.leftMouseDown, window: w, at: wp, clickCount: 1)
            send(.leftMouseUp, window: w, at: wp, clickCount: 1)
            expect(controller.wallpaperClicks == before + 1, "a plain click between icons should count as a wallpaper click")
        }))
        // Repeated wallpaper-click reveals, all through the test seams: nothing asks the real Dock
        // and no window on this screen moves. The first cycle ends the reveal before the delayed
        // check that judges whether the reveal happened, which used to turn the feature off.
        steps.append(("repeated wallpaper-click reveals", { [self] in
            round = "repeated reveals"
            let settingWas = Settings.shared.revealDesktopOnWallpaperClick
            Settings.shared.revealDesktopOnWallpaperClick = true
            revealed = false; revealToggles = 0; pendingReveal = []; revealClock = 1000
            controller.revealProbe = { [self] in revealed }
            controller.revealToggle = { [self] in revealToggles += 1; return true }
            controller.revealGestureEnabled = { true }
            controller.revealAfter = { [self] delay, body in pendingReveal.append((revealClock + delay, body)) }
            controller.revealNow = { [self] in revealClock }
            controller.revealOnWallpaperClick = true

            clickWallpaper()
            expect(revealToggles == 1, "a plain wallpaper click should ask for a reveal")
            revealed = true
            runPendingReveal(1)                         // the first quick re-check after the request
            expect(controller.steppedAside, "QuietDesk should step aside for the first reveal")
            expect(controller.windows.allSatisfy { !$0.isVisible }, "no icon window should be on screen during a reveal")
            revealed = false                            // the person ends it straight away
            readReveal(); drainReveal()                 // the delayed judgement runs in here too
            expect(!controller.steppedAside, "QuietDesk should come back when the first reveal ends")
            expect(!controller.revealUnseen, "a reveal that was seen and ended quickly must leave the feature on")

            clickWallpaper()
            expect(revealToggles == 2, "a second wallpaper click should ask for a reveal too")
            revealed = true
            drainReveal()
            expect(controller.steppedAside, "QuietDesk should step aside for the second reveal")
            revealed = false
            readReveal(after: 0.05)
            expect(controller.steppedAside, "one read saying the reveal ended must not bring the icons back")
            readReveal(after: 0.05)
            expect(controller.steppedAside, "two reads a moment apart must not bring the icons back either")
            revealed = true                             // the window list flickered mid-reveal
            drainReveal()
            expect(controller.steppedAside, "a flickering read must leave QuietDesk stepped aside")
            revealed = false
            tickReveal()
            expect(!controller.steppedAside, "QuietDesk should come back when the second reveal ends")
            expect(controller.windows.contains { $0.isVisible } && controller.shields.allSatisfy { $0.isVisible }, "QuietDesk's windows should be back after repeated reveals")

            // Two clicks a quarter second apart. The reveal the first one asked for is on screen but
            // nothing has read the window list yet, and the second click cancels it. Neither click
            // can say reveals do not work, and the next one must still ask for one.
            let beforePair = revealToggles
            clickWallpaper()
            revealed = true
            clickWallpaper(after: 0.25)
            revealed = false
            expect(revealToggles == beforePair + 2, "both of two quick wallpaper clicks should ask for a reveal")
            drainReveal()
            expect(!controller.revealUnseen, "two wallpaper clicks a moment apart must not turn the feature off")
            clickWallpaper()
            expect(revealToggles == beforePair + 3, "a wallpaper click after those two should still ask for a reveal")
            revealed = true; tickReveal(); revealed = false; tickReveal()
            expect(!controller.steppedAside, "QuietDesk should be back after that reveal")

            // Reveals that never appear: the fail safe. One miss is weak evidence, so it takes
            // three in a row (with no reveal seen in between) to switch wallpaper clicks off.
            drainReveal()
            let beforeFailSafe = revealToggles
            for strike in 1...3 {
                clickWallpaper()                        // a reveal that never appears
                expect(revealToggles == beforeFailSafe + strike, "wallpaper click \(strike) should still ask for a reveal")
                drainReveal()
                expect(controller.revealMisses == strike, "an unobserved reveal should count as strike \(strike)")
                expect(controller.revealUnseen == (strike == 3), strike == 3
                       ? "three unobserved reveals in a row should stop wallpaper clicks asking"
                       : "\(strike) unobserved reveal(s) must not stop wallpaper clicks asking")
            }
            clickWallpaper()
            expect(revealToggles == beforeFailSafe + 3, "after that, a wallpaper click should only deselect")
            revealed = true                             // a reveal seen later (F11) shows it does work
            tickReveal()
            expect(!controller.revealUnseen, "seeing a reveal should let wallpaper clicks ask again")
            expect(controller.revealMisses == 0, "seeing a reveal should put the strike count back to 0")
            revealed = false
            tickReveal()
            expect(!controller.steppedAside, "QuietDesk should come back at the end of that reveal")
            clickWallpaper()
            expect(revealToggles == beforeFailSafe + 4, "a wallpaper click should ask for a reveal again")
            revealed = true; tickReveal(); revealed = false; tickReveal()
            expect(!controller.steppedAside && controller.windows.contains { $0.isVisible }, "QuietDesk should be back on screen at the end of the round")

            controller.revealOnWallpaperClick = false
            controller.revealProbe = { DesktopReveal.isRevealed }
            controller.revealToggle = { DesktopReveal.toggle() }
            controller.revealGestureEnabled = { DesktopReveal.clickRevealsDesktop }
            controller.revealAfter = { delay, body in DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: body) }
            controller.revealNow = { ProcessInfo.processInfo.systemUptime }
            Settings.shared.revealDesktopOnWallpaperClick = settingWas
            pendingReveal = []
        }))
        // A request the Dock simply does not act on. It happens after a burst of clicks, when the
        // Dock is probably still finishing the previous un-reveal: nothing is revealed, so nothing
        // is doubled, and the next click must just ask again. Three misses in a row with no reveal
        // in between is the only pattern worth switching the feature off for.
        steps.append(("the Dock ignores a request", { [self] in
            round = "ignored requests"
            installRevealSeams()
            var dockAnswers = true                      // a fake Dock that really toggles the reveal
            controller.revealToggle = { [self] in
                revealToggles += 1
                if dockAnswers { revealed.toggle() }
                return true
            }

            // A burst: a reveal, ended by one of the clicks that reach the system while QuietDesk
            // is stepped aside, then a request the Dock ignores, then a plain click that must still
            // ask for a reveal and get one.
            clickWallpaper()
            runPendingReveal(1)
            expect(controller.steppedAside, "the first click's reveal should be noticed")
            revealed = false                            // a click that reached the system ended it
            readReveal(); drainReveal()
            expect(!controller.steppedAside, "QuietDesk should come back when that reveal ends")
            expect(controller.revealMisses == 0, "a reveal that was seen should leave no strikes behind")

            dockAnswers = false
            var before = revealToggles
            clickWallpaper()
            expect(revealToggles == before + 1, "the click after a burst should ask for a reveal")
            drainReveal()
            expect(controller.revealMisses == 1, "a request the Dock ignored should be strike 1")
            expect(!controller.revealUnseen, "one ignored request must not switch wallpaper-click reveal off")

            dockAnswers = true
            before = revealToggles
            clickWallpaper()
            expect(revealToggles == before + 1, "the click after an ignored request should ask again")
            drainReveal()
            expect(controller.steppedAside, "and that reveal should be noticed")
            expect(controller.revealMisses == 0, "seeing it should clear the strike")
            revealed = false
            tickReveal()
            expect(!controller.steppedAside, "QuietDesk should come back after it")

            // Two ignored, a reveal that works, two more ignored: never three in a row, so the
            // feature stays on the whole way through.
            dockAnswers = false
            clickWallpaper(); drainReveal()
            clickWallpaper(); drainReveal()
            expect(controller.revealMisses == 2, "two ignored requests should be two strikes")
            expect(!controller.revealUnseen, "two ignored requests must not switch the feature off")
            dockAnswers = true
            clickWallpaper(); drainReveal()
            expect(controller.revealMisses == 0, "a reveal in between should put the strikes back to 0")
            revealed = false; tickReveal()
            dockAnswers = false
            clickWallpaper(); drainReveal()
            clickWallpaper(); drainReveal()
            expect(controller.revealMisses == 2, "the two after that reveal should count from 0 again")
            expect(!controller.revealUnseen, "two misses, a reveal, then two more must leave the feature on")

            // No entry point at all is a certain failure, not a miss: it switches off on the spot.
            controller.revealToggle = { [self] in revealToggles += 1; return false }
            before = revealToggles
            clickWallpaper()
            expect(revealToggles == before + 1, "a wallpaper click should still try the entry point")
            expect(controller.revealUnseen, "an unavailable entry point should switch wallpaper-click reveal off at once")
            clickWallpaper()
            expect(revealToggles == before + 1, "after that, a wallpaper click should only deselect")

            // Leave the feature on and QuietDesk on screen for the rounds that follow.
            revealed = true; tickReveal()
            expect(!controller.revealUnseen, "a reveal seen later should switch it back on")
            revealed = false; tickReveal()
            expect(!controller.steppedAside && controller.windows.contains { $0.isVisible }, "QuietDesk should be back on screen at the end of the round")
            removeRevealSeams()
        }))
        // Clicks in a steady rhythm: slower than a double click, so every one of them is a plain
        // click that asks for a reveal, but close enough that each request has another one within
        // the verdict delay of it. No single request in such a run can be judged, so the strikes
        // never move. Nothing reveals here, which is what a reveal that no read can see looks like
        // from inside QuietDesk: the run has to end by itself, after a bounded number of requests.
        steps.append(("wallpaper clicks in a steady rhythm", { [self] in
            round = "steady rhythm"
            installRevealSeams()
            controller.revealToggle = { [self] in revealToggles += 1; return true }

            let before = revealToggles
            var asked = 0
            var clicks = 0
            while !controller.revealUnseen, clicks < 24 {
                clicks += 1
                clickWallpaperInRhythm(after: 0.8)
                if controller.revealUnseen { break }   // the run ended as this click arrived
                asked += 1
                expect(revealToggles == before + asked, "click \(asked) of a steady rhythm should ask for a reveal")
                expect(controller.revealMisses == 0, "a request with another one close to it must not score a strike")
                expect(controller.revealUnjudged == asked - 2 || asked < 3, "each cancelled request should join the unjudged run")
            }
            drainReveal()
            expect(controller.revealUnseen, "a rhythm of requests with no reveal seen for any of them should switch the wallpaper click off")
            expect(asked <= 10, "it should do that after a small, bounded number of requests (asked \(asked))")
            expect(controller.revealMisses == 0, "and without a single strike, since no request in the run could be judged")
            let afterOff = revealToggles
            clickWallpaperInRhythm(after: 0.8)
            expect(revealToggles == afterOff, "once it is off, a wallpaper click should only deselect")

            // Any reveal at all, however it started, switches it back on and empties both counts.
            revealed = true
            tickReveal()
            expect(!controller.revealUnseen, "a reveal seen later should switch the wallpaper click back on")
            expect(controller.revealUnjudged == 0, "and put the run of unjudged requests back to 0")
            revealed = false
            tickReveal()
            expect(!controller.steppedAside, "QuietDesk should come back at the end of that reveal")

            // A judged request ends the run: two cancelled requests, then one on its own that is a
            // plain strike, and the unjudged count starts again from nothing.
            clickWallpaper(after: 2.0)
            clickWallpaperInRhythm(after: 0.6)
            drainReveal()
            expect(controller.revealUnjudged == 2, "two requests that cancel each other should leave a run of 2")
            expect(controller.revealMisses == 0, "neither of them should be a strike")
            clickWallpaper(after: 3.0)
            drainReveal()
            expect(controller.revealMisses == 1, "a request with nothing near it should be judged, and missing it is a strike")
            expect(controller.revealUnjudged == 0, "and a judged request should end the unjudged run")
            expect(!controller.revealUnseen, "one strike must not switch the wallpaper click off")

            revealed = true; tickReveal(); revealed = false; tickReveal()
            expect(!controller.revealUnseen && controller.revealMisses == 0, "a reveal at the end should leave the feature on with no strikes")
            expect(!controller.steppedAside && controller.windows.contains { $0.isVisible }, "QuietDesk should be back on screen at the end of the round")
            removeRevealSeams()
        }))
        // Detection must survive a sleep whose wake notification never arrives, which is how it was
        // lost for a whole session once. Sleep is only posted here, never asked for: nothing
        // in this round puts the Mac or its displays to sleep.
        steps.append(("reveal checks survive a sleep with no wake", { [self] in
            round = "sleep with no wake"
            installRevealSeams()
            let wc = NSWorkspace.shared.notificationCenter

            // A sleep, no wake afterwards, then a wallpaper click. The reveal must still be noticed.
            wc.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
            let before = revealToggles
            clickWallpaper()
            expect(revealToggles == before + 1, "a wallpaper click after a sleep should still ask for a reveal")
            revealed = true
            runPendingReveal(1)
            expect(controller.steppedAside, "after a sleep with no wake, the reveal a wallpaper click asks for must still be noticed")
            expect(controller.revealTimerIsLive, "a wallpaper click should leave the reveal check running")
            revealed = false
            readReveal(); drainReveal()
            expect(!controller.steppedAside, "QuietDesk should come back when that reveal ends")

            // The checks a click queues answer to nothing but a QuietDesk that has been turned off.
            clickWallpaper()
            controller.killRevealTimerForTesting(forget: true)
            revealed = true
            runPendingReveal(1)
            expect(controller.steppedAside, "the checks a wallpaper click queues must work with no timer at all")
            revealed = false
            readReveal(); drainReveal()
            expect(!controller.steppedAside, "QuietDesk should come back after that one too")

            // A check killed behind the controller's back: a click starts it again.
            controller.revealOnWallpaperClick = false        // this click only has to heal the timer
            controller.killRevealTimerForTesting(forget: false)
            expect(!controller.revealTimerIsLive, "the test hook should leave the reveal check dead")
            clickWallpaper()
            expect(controller.revealTimerIsLive, "a click on the desktop should start a dead reveal check again")

            // Waking starts it again too, and looks at once: a reveal may have begun meanwhile.
            controller.killRevealTimerForTesting(forget: true)
            revealed = true
            wc.post(name: NSWorkspace.didWakeNotification, object: nil)
            expect(controller.revealTimerIsLive, "waking the Mac should start the reveal check again")
            expect(controller.steppedAside, "a reveal already on screen at wake should be noticed at once")
            revealed = false
            readReveal(); drainReveal()
            expect(!controller.steppedAside, "QuietDesk should come back when that reveal ends")
            controller.killRevealTimerForTesting(forget: true)
            wc.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
            expect(controller.revealTimerIsLive, "waking the displays should start the reveal check again")

            // Switching to another account, or the lock screen, leaves this session with nothing
            // drawn: what the check reads there says nothing about what the person will see. The
            // moment this session is in front again, the desktop is read afresh.
            controller.killRevealTimerForTesting(forget: true)
            revealed = true
            wc.post(name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
            expect(controller.revealTimerIsLive, "coming back to this session should start the reveal check again")
            expect(controller.steppedAside, "a reveal on screen when this session comes back should be noticed at once")
            revealed = false
            readReveal(); drainReveal()
            expect(!controller.steppedAside, "QuietDesk should come back when that reveal ends")
            controller.revealOnWallpaperClick = true
        }))
        // The one delayed check that decides something: the verdict on whether the reveal a click
        // asked for ever appeared. A sleep in between holds it until the Mac wakes, and it then
        // looks at a desktop an hour older than the click. It must not judge the click on that.
        steps.append(("a wallpaper click the Mac slept through", { [self] in
            round = "slept through a click"
            let before = revealToggles
            clickWallpaper()
            expect(revealToggles == before + 1, "a wallpaper click should ask for a reveal")
            revealSleepOffset += 3600            // an hour asleep before any of the checks can run
            revealed = false                     // and no reveal on screen by the time they do
            drainReveal()
            expect(!controller.revealUnseen, "a verdict that only ran after a long sleep must not switch wallpaper-click reveal off")
            clickWallpaper()
            expect(revealToggles == before + 2, "wallpaper clicks should still ask for a reveal after that")
            revealed = true; tickReveal()
            expect(controller.steppedAside, "and that reveal should still be noticed")
            revealed = false; tickReveal(); drainReveal()
            expect(!controller.steppedAside && !controller.revealUnseen, "QuietDesk should come back with the feature still on")
        }))
        // A reveal started by F11 or the gesture after that same sleep: nothing asks for it and no
        // click follows, so only the repeating check can find it. This one waits on the real timer.
        steps.append(("a reveal starting on its own after a sleep", { [self] in
            round = "sleep with no wake"
            NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
            revealed = true
        }))
        for _ in 0..<12 { steps.append(("waiting for the check to notice", {})) }
        steps.append(("the check noticed it", { [self] in
            expect(controller.steppedAside, "the repeating check should notice a reveal that starts on its own after a sleep")
            expect(controller.windows.allSatisfy { !$0.isVisible }, "no icon window should be on screen during that reveal")
            revealed = false
            tickReveal()
            expect(!controller.steppedAside && controller.windows.contains { $0.isVisible }, "QuietDesk should be back on screen after it")
            removeRevealSeams()
        }))
        if withReveal {
            // The real thing (opt-in: it slides every window aside for about three seconds).
            // Two cycles, and the second one is ended quickly, which is how the bug first showed up.
            for cycle in 1...2 {
                steps.append(("reveal \(cycle): wallpaper click", { [self] in
                    round = "reveal desktop \(cycle)"
                    controller.revealOnWallpaperClick = true
                    expect(DesktopReveal.clickRevealsDesktop, "System Settings should have Click wallpaper to reveal desktop on for this round")
                    let before = controller.revealRequests
                    clickWallpaper()
                    expect(controller.revealRequests == before + 1, "a wallpaper click should ask the Dock for a reveal")
                }))
                for _ in 0..<(cycle == 1 ? 5 : 3) { steps.append(("reveal \(cycle): waiting", {})) }
                steps.append(("reveal \(cycle): stepped aside", { [self] in
                    expect(DesktopReveal.isRevealed, "the desktop should be revealed after a wallpaper click")
                    expect(controller.steppedAside, "QuietDesk should step aside while the desktop is revealed")
                    expect(controller.windows.allSatisfy { !$0.isVisible } && controller.shields.allSatisfy { !$0.isVisible }, "no QuietDesk window should be on screen during a reveal")
                    if DesktopReveal.isRevealed { DesktopReveal.toggle() }   // end it the way F11 would (it is a toggle: only when revealed)
                }))
                for _ in 0..<7 { steps.append(("reveal \(cycle): waiting", {})) }
                steps.append(("reveal \(cycle): back", { [self] in
                    expect(!DesktopReveal.isRevealed, "the reveal should have ended")
                    expect(!controller.steppedAside, "QuietDesk should come back when the reveal ends")
                    expect(controller.windows.contains { $0.isVisible } && controller.shields.allSatisfy { $0.isVisible }, "QuietDesk's windows should be back on screen")
                    expect(!controller.revealUnseen, "a reveal that worked must leave wallpaper-click reveals on")
                    controller.revealOnWallpaperClick = false
                }))
            }
        }
        steps.append(("finish", { [self] in
            if withReveal, DesktopReveal.isRevealed { DesktopReveal.toggle() }   // never leave the windows slid aside
            // Turned off: a wake or a click must leave a stopped QuietDesk alone.
            round = "after Turn Off"
            controller.revealOnWallpaperClick = false        // nothing here may ask the real Dock
            controller.stop()
            expect(!controller.revealTimerIsLive, "stop() should end the reveal check")
            let wc = NSWorkspace.shared.notificationCenter
            wc.post(name: NSWorkspace.didWakeNotification, object: nil)
            wc.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
            wc.post(name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
            controller.surfaceWallpaperClicked()
            controller.surfaceDidReceiveClick()
            expect(!controller.revealTimerIsLive, "a wake or a click must not start the reveal check on a QuietDesk that is off")
            print("scenario test: \(checks) checks, \(failures.count) failed")
            for f in failures { print("  - \(f)") }
            print(failures.isEmpty ? "ALL PASSED" : "FAILED")
            Settings.removeScenarioSuite()   // pass or fail, leave no plist behind
            exit(failures.isEmpty ? 0 : 1)
        }))
        run(0)
    }

    private func run(_ i: Int) {
        guard i < steps.count else { return }
        steps[i].body()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [self] in run(i + 1) }
    }
}

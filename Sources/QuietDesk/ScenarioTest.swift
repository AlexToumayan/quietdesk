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

    init(controller: OverlayController) {
        self.controller = controller
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

    private func clickWallpaper() {
        guard let shield = controller.shields.first, let sv = shield.contentView else { return }
        let p = sv.convert(NSPoint(x: 40, y: 200), to: nil)   // far from the icon column
        send(.leftMouseDown, window: shield, at: p, clickCount: 1)
        send(.leftMouseUp, window: shield, at: p, clickCount: 1)
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
            click(f)   // one click; the activation completes asynchronously before the next step
        }))
        steps.append(("Finder is the active app", { [self] in
            guard Settings.shared.activateFinderOnDesktopClick else { return }
            let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first
            let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"
            // Locked screen or a headless CI session: nothing can be frontmost, so nothing to check.
            if front == "com.apple.loginwindow" || front == "?" { print("skip: no frontmost app to hand off to (\(front))"); return }
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
            clickWallpaper()
            expect(expanded.isEmpty, "a click on the wallpaper should collapse the Stack")
            expect(view?.selection.isEmpty ?? false, "a click on the wallpaper should clear the selection")
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
        addRound("Finder's icon size, spacing and text") { s.viewOptions = nil; vo.onChange?() }
        addRound("Stacks off", stacks: false) { s.stacksMode = .off; vo.onChange?() }
        addRound("Stacks by Kind") { s.stacksMode = .kind; vo.onChange?() }
        addRound("Stacks by Date Added, Sort By Name") { s.stacksMode = .dateAdded; s.sortKey = .name; vo.onChange?() }
        addRound("View Options closed") { vo.close() }
        addRound("items hidden then shown again") { [self] in controller.hide(); controller.show() }
        addRound("Bring Finder Forward off") { s.activateFinderOnDesktopClick = false }
        addRound("Bring Finder Forward on again") { s.activateFinderOnDesktopClick = true }
        addRound("reload desktop") { [self] in controller.reloadAndRelayout() }
        steps.append(("finish", { [self] in
            print("scenario test: \(checks) checks, \(failures.count) failed")
            for f in failures { print("  - \(f)") }
            print(failures.isEmpty ? "ALL PASSED" : "FAILED")
            controller.stop()
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

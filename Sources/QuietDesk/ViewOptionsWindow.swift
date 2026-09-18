import AppKit

/// QuietDesk's equivalent of Finder's "Show View Options" panel for the desktop. Changes apply
/// to QuietDesk's own drawing immediately and never modify Finder's settings; "Use Finder's
/// Settings" re-imports Finder's current values.
final class ViewOptionsWindowController: NSWindowController {
    static let shared = ViewOptionsWindowController()
    /// Called after any change; the app delegate relayouts the desktop and refreshes its menus.
    var onChange: (() -> Void)?

    private let settings = Settings.shared
    private let stackBy = NSPopUpButton(frame: .zero, pullsDown: false)
    private let sortBy = NSPopUpButton(frame: .zero, pullsDown: false)
    private let iconSizeLabel = NSTextField(labelWithString: "")
    private let iconSize = SteppedSlider(value: 2, minValue: 0, maxValue: Double(ViewOptions.iconSizes.count - 1), target: nil, action: nil)
    private let gridSpacing = NSSlider(value: 26, minValue: 1, maxValue: 100, target: nil, action: nil)
    private let textSize = NSPopUpButton(frame: .zero, pullsDown: false)
    private let labelBottom = NSButton(radioButtonWithTitle: "Bottom", target: nil, action: nil)
    private let labelRight = NSButton(radioButtonWithTitle: "Right", target: nil, action: nil)
    private let itemInfo = NSButton(checkboxWithTitle: "Show item info", target: nil, action: nil)
    private let iconPreview = NSButton(checkboxWithTitle: "Show icon preview", target: nil, action: nil)
    private let cloudStatus = NSButton(checkboxWithTitle: "Show iCloud status", target: nil, action: nil)
    private let compactGrid = NSButton(checkboxWithTitle: "Compact grid while names are hidden", target: nil, action: nil)
    private let hoverReveal = NSPopUpButton(frame: .zero, pullsDown: false)
    private let stackModes: [StacksMode] = [.off, .kind, .dateAdded, .dateModified, .dateCreated, .dateLastOpened, .tags]
    private let sortKeys: [SortKey] = [.none, .name, .kind, .dateAdded, .dateModified, .dateCreated, .dateLastOpened, .size, .tags]

    private init() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 292, height: 560),
                            styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        panel.title = "Desktop"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        super.init(window: panel)   // the controls are laid out on first use, not at launch
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    private var isBuilt = false
    private func buildIfNeeded() { if !isBuilt { isBuilt = true; build() } }

    func show() {
        refresh()
        if let w = window, !w.isVisible, let screen = NSScreen.main {
            let f = screen.visibleFrame
            w.setFrameTopLeftPoint(NSPoint(x: f.maxX - w.frame.width - 24, y: f.maxY - 24))
        }
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Layout (follows Finder's desktop View Options: left-aligned sections, full-width rules,
    // small and large glyphs at the ends of the two sliders)

    private static let sideInset: CGFloat = 20
    private static let contentWidth: CGFloat = 252

    private func label(_ text: String) -> NSTextField { NSTextField(labelWithString: text) }

    /// A decorative SF Symbol (the sliders carry the accessibility labels).
    private func glyph(_ name: String, pointSize: CGFloat, slot: CGFloat) -> NSImageView {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)) ?? NSImage()
        let view = NSImageView(image: image)
        view.contentTintColor = .labelColor
        view.imageScaling = .scaleNone
        view.setAccessibilityElement(false)
        view.widthAnchor.constraint(equalToConstant: slot).isActive = true   // same slots, so both sliders line up
        return view
    }

    /// [small glyph] slider-over-dots [large glyph], like Finder's icon-size and grid-spacing rows.
    private func sliderRow(_ slider: NSSlider, ticks: Int, small: NSImageView, large: NSImageView) -> NSStackView {
        let dots = TickDots(count: ticks, slider: slider)
        let column = NSStackView(views: [slider, dots])
        column.orientation = .vertical; column.alignment = .leading; column.spacing = 1
        dots.widthAnchor.constraint(equalTo: slider.widthAnchor).isActive = true
        slider.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        let row = NSStackView(views: [small, column, large])
        row.orientation = .horizontal; row.alignment = .centerY; row.spacing = 8
        return row
    }

    private func rule() -> NSBox { let box = NSBox(); box.boxType = .separator; return box }

    /// One group between two rules; `fill` views stretch to the section's width.
    private func section(_ views: [NSView], fill: [NSView] = []) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 0, left: Self.sideInset, bottom: 0, right: Self.sideInset)
        for view in fill { view.widthAnchor.constraint(equalToConstant: Self.contentWidth).isActive = true }
        return stack
    }

    private func build() {
        for mode in stackModes { stackBy.addItem(withTitle: mode == .off ? "None" : String(mode.title.dropFirst("Group by ".count))) }
        for key in sortKeys { sortBy.addItem(withTitle: key == .none ? "None" : key.title) }
        for size in ViewOptions.textSizes { textSize.addItem(withTitle: String(Int(size))) }
        for title in ["Only the item", "The item and its neighbours", "A wider area"] { hoverReveal.addItem(withTitle: title) }
        // No system tick marks (they are bars through the track for this SDK): Finder-style dots
        // are drawn underneath, and the icon-size slider snaps to its stops in changed(_:).
        iconSize.isContinuous = true
        iconSize.setAccessibilityLabel("Icon size")
        gridSpacing.isContinuous = true
        gridSpacing.setAccessibilityLabel("Grid spacing")
        for control in [stackBy, sortBy, textSize, hoverReveal, iconSize, gridSpacing, labelBottom, labelRight, itemInfo, iconPreview, cloudStatus, compactGrid] as [NSControl] {
            control.target = self; control.action = #selector(changed)
        }
        compactGrid.toolTip = "With Item Labels set to On Hover or Hidden, pack the icons as if there were no names; a name appears over its neighbours when you point at its item. Off: keep Finder's grid, with room under every icon. Manually arranged desktops (Sort By: None) always keep Finder's grid."
        hoverReveal.toolTip = "How far around the pointed-at item names are revealed. Needs room under the icons, so it is off while the compact grid is in use."
        itemInfo.toolTip = "Item counts, sizes and free space under the names. Needs room under the icons, so it is off while the compact grid is in use."

        // Stack By / Sort By: labels in one column, pop-ups filling the rest of the row.
        let sortGrid = NSGridView(views: [[label("Stack By:"), stackBy], [label("Sort By:"), sortBy]])
        sortGrid.rowSpacing = 8; sortGrid.columnSpacing = 8
        sortGrid.rowAlignment = .firstBaseline
        sortGrid.column(at: 0).xPlacement = .leading
        sortGrid.column(at: 1).xPlacement = .fill

        let iconTitle = NSStackView(views: [label("Icon size:"), iconSizeLabel]); iconTitle.spacing = 6
        let iconRow = sliderRow(iconSize, ticks: ViewOptions.iconSizes.count, small: glyph("doc.fill", pointSize: 11, slot: 22), large: glyph("doc.fill", pointSize: 26, slot: 34))
        let gridRow = sliderRow(gridSpacing, ticks: 8, small: glyph("square.grid.2x2", pointSize: 12, slot: 22), large: glyph("square.grid.3x3", pointSize: 25, slot: 34))

        let textRow = NSStackView(views: [label("Text size:"), textSize]); textRow.spacing = 8
        let labelRow = NSStackView(views: [labelBottom, labelRight]); labelRow.spacing = 14

        let extras = label("QuietDesk")
        extras.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        extras.textColor = .secondaryLabelColor
        let useFinder = NSButton(title: "Use Finder's Settings", target: self, action: #selector(useFinderSettings))
        let note = NSTextField(wrappingLabelWithString: "Applies to QuietDesk's desktop only. Finder's own View Options are never changed.")
        note.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize); note.textColor = .secondaryLabelColor
        note.preferredMaxLayoutWidth = Self.contentWidth

        let groups: [NSView] = [
            section([sortGrid], fill: [sortGrid]),
            rule(),
            section([iconTitle, iconRow, label("Grid spacing:"), gridRow], fill: [iconRow, gridRow]),
            rule(),
            section([textRow, label("Label position:"), labelRow]),
            rule(),
            section([itemInfo, iconPreview]),
            rule(),
            section([extras, cloudStatus, compactGrid, label("Names on hover:"), hoverReveal], fill: [hoverReveal]),
            rule(),
            section([useFinder, note], fill: [note]),
        ]
        let stack = NSStackView(views: groups)
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 0, bottom: 16, right: 0)
        stack.translatesAutoresizingMaskIntoConstraints = false
        guard let content = window?.contentView else { return }
        content.addSubview(stack)
        var constraints = [
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            stack.widthAnchor.constraint(equalToConstant: Self.contentWidth + 2 * Self.sideInset),
        ]
        // Sections and rules run edge to edge, as in Finder's panel.
        for view in groups { constraints.append(view.widthAnchor.constraint(equalTo: stack.widthAnchor)) }
        NSLayoutConstraint.activate(constraints)
        content.layoutSubtreeIfNeeded()
        window?.setContentSize(stack.fittingSize)
        // Finder's panel has a close button only.
        window?.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window?.standardWindowButton(.zoomButton)?.isHidden = true
    }

    // MARK: - State

    private var current: ViewOptions { settings.effectiveViewOptions(finder: FinderDesktopPrefs.load()) }

    func refresh() {
        buildIfNeeded()
        let o = current
        let prefs = FinderDesktopPrefs.load()
        let effectiveStacks = settings.stacksMode == .finder ? (StacksMode.allCases.first { $0.groupBy == prefs.groupBy } ?? .off) : settings.stacksMode
        stackBy.selectItem(at: stackModes.firstIndex(of: effectiveStacks) ?? 0)
        let effectiveSort = settings.sortKey == .finder ? (SortKey.allCases.first { $0.arrangeBy == prefs.arrangeBy } ?? .none) : settings.sortKey
        sortBy.selectItem(at: sortKeys.firstIndex(of: effectiveSort) ?? 0)
        iconSize.doubleValue = Double(ViewOptions.iconSizes.firstIndex(of: o.iconSize) ?? 2)
        iconSizeLabel.stringValue = "\(Int(o.iconSize))×\(Int(o.iconSize))"
        gridSpacing.doubleValue = Double(o.gridSpacing)
        textSize.selectItem(at: ViewOptions.textSizes.firstIndex(of: o.textSize) ?? 2)
        labelBottom.state = o.labelOnBottom ? .on : .off
        labelRight.state = o.labelOnBottom ? .off : .on
        itemInfo.state = o.showItemInfo ? .on : .off
        iconPreview.state = o.showIconPreview ? .on : .off
        cloudStatus.state = o.showCloudStatus ? .on : .off
        compactGrid.state = o.compactGrid ? .on : .off
        hoverReveal.selectItem(at: o.hoverReveal)
        updateEnabledStates(o)
    }

    @objc private func changed(_ sender: Any?) {
        iconSize.doubleValue = iconSize.doubleValue.rounded()   // snap to the eight icon sizes
        var o = current
        o.iconSize = ViewOptions.iconSizes[max(0, min(ViewOptions.iconSizes.count - 1, Int(iconSize.doubleValue.rounded())))]
        o.gridSpacing = gridSpacing.doubleValue.rounded()
        o.textSize = ViewOptions.textSizes[max(0, textSize.indexOfSelectedItem)]
        o.labelOnBottom = labelBottom.state == .on
        o.showItemInfo = itemInfo.state == .on
        o.showIconPreview = iconPreview.state == .on
        o.showCloudStatus = cloudStatus.state == .on
        o.hoverReveal = max(0, hoverReveal.indexOfSelectedItem)
        o.compactGrid = compactGrid.state == .on
        settings.viewOptions = o
        // Only the popup that was used changes Sort By / Stacks; any other control must leave
        // "follow Finder's setting" alone.
        if let s = sender as AnyObject?, s === stackBy { settings.stacksMode = stackModes[max(0, stackBy.indexOfSelectedItem)] }
        if let s = sender as AnyObject?, s === sortBy { settings.sortKey = sortKeys[max(0, sortBy.indexOfSelectedItem)] }
        iconSizeLabel.stringValue = "\(Int(o.iconSize))×\(Int(o.iconSize))"
        updateEnabledStates(o)
        onChange?()
    }

    /// Manual layouts keep Finder's grid, exactly as OverlayController.currentMetrics() decides.
    private var manualLayout: Bool {
        let arrange = settings.sortKey.arrangeBy ?? FinderDesktopPrefs.load().arrangeBy
        return arrange == .none || arrange == .grid
    }

    /// Controls that have no effect in the current mode are disabled rather than silently ignored.
    private func updateEnabledStates(_ o: ViewOptions) {
        let namesHidden = settings.labelMode != .always
        let compactApplies = o.compactGrid && namesHidden && !manualLayout
        compactGrid.isEnabled = namesHidden && !manualLayout
        for control in [hoverReveal, itemInfo, labelBottom, labelRight] as [NSControl] { control.isEnabled = !compactApplies }
    }

    @objc private func useFinderSettings() {
        settings.viewOptions = nil
        settings.stacksMode = .finder
        settings.sortKey = .finder
        refresh()
        onChange?()
    }
}

/// A slider whose stops are whole numbers: the arrow keys and VoiceOver's increment/decrement
/// move one stop at a time (the mouse snaps in ViewOptionsWindowController.changed).
final class SteppedSlider: NSSlider {
    private func step(_ delta: Double) {
        doubleValue = max(minValue, min(maxValue, doubleValue.rounded() + delta))
        sendAction(action, to: target)
    }
    override func keyDown(with event: NSEvent) {
        switch event.specialKey {
        case .leftArrow?, .downArrow?: step(-1)
        case .rightArrow?, .upArrow?: step(1)
        default: super.keyDown(with: event)
        }
    }
    override func accessibilityPerformIncrement() -> Bool { step(1); return true }
    override func accessibilityPerformDecrement() -> Bool { step(-1); return true }
}

/// Finder-style tick dots under a slider. Decorative only.
final class TickDots: NSView {
    private let count: Int
    private weak var slider: NSSlider?

    init(count: Int, slider: NSSlider) {
        self.count = count; self.slider = slider
        super.init(frame: .zero)
        setAccessibilityElement(false)
    }

    /// Where the knob's centre sits at the slider's minimum: the dots span the same travel.
    /// Asked of a copy of the cell, so the real slider's value is never touched.
    private var inset: CGFloat {
        guard let slider, let cell = (slider.cell as? NSSliderCell)?.copy() as? NSSliderCell else { return 10 }
        cell.doubleValue = cell.minValue
        let x = cell.knobRect(flipped: slider.isFlipped).midX
        return (x > 0 && x < bounds.width / 2) ? x : 10
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 4) }

    override func draw(_ dirtyRect: NSRect) {
        guard count > 1 else { return }
        NSColor.tertiaryLabelColor.setFill()
        let span = bounds.width - 2 * inset
        for i in 0..<count {
            let x = inset + span * CGFloat(i) / CGFloat(count - 1)
            NSBezierPath(ovalIn: NSRect(x: x - 1.25, y: bounds.midY - 1.25, width: 2.5, height: 2.5)).fill()
        }
    }
}

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
    private let iconSize = NSSlider(value: 2, minValue: 0, maxValue: Double(ViewOptions.iconSizes.count - 1), target: nil, action: nil)
    private let gridSpacing = NSSlider(value: 26, minValue: 1, maxValue: 100, target: nil, action: nil)
    private let textSize = NSPopUpButton(frame: .zero, pullsDown: false)
    private let labelBottom = NSButton(radioButtonWithTitle: "Bottom", target: nil, action: nil)
    private let labelRight = NSButton(radioButtonWithTitle: "Right", target: nil, action: nil)
    private let itemInfo = NSButton(checkboxWithTitle: "Show item info", target: nil, action: nil)
    private let iconPreview = NSButton(checkboxWithTitle: "Show icon preview", target: nil, action: nil)
    private let stackModes: [StacksMode] = [.off, .kind, .dateAdded, .dateModified, .dateCreated, .dateLastOpened, .tags]
    private let sortKeys: [SortKey] = [.none, .name, .kind, .dateAdded, .dateModified, .dateCreated, .dateLastOpened, .size, .tags]

    private init() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 430),
                            styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        panel.title = "Desktop"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        super.init(window: panel)
        build()
    }
    required init?(coder: NSCoder) { fatalError("not used") }

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

    // MARK: - Layout

    private func build() {
        for mode in stackModes { stackBy.addItem(withTitle: mode == .off ? "None" : String(mode.title.dropFirst("Group by ".count))) }
        for key in sortKeys { sortBy.addItem(withTitle: key == .none ? "None" : key.title) }
        for size in ViewOptions.textSizes { textSize.addItem(withTitle: String(Int(size))) }
        iconSize.numberOfTickMarks = ViewOptions.iconSizes.count
        iconSize.allowsTickMarkValuesOnly = true
        iconSize.isContinuous = true
        gridSpacing.numberOfTickMarks = 8
        gridSpacing.isContinuous = true
        for (control, sel) in [(stackBy, #selector(changed)), (sortBy, #selector(changed)), (textSize, #selector(changed))] as [(NSControl, Selector)] { control.target = self; control.action = sel }
        for control in [iconSize, gridSpacing] { control.target = self; control.action = #selector(changed) }
        for control in [labelBottom, labelRight, itemInfo, iconPreview] { control.target = self; control.action = #selector(changed) }
        iconSizeLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)

        func row(_ title: String, _ view: NSView) -> [NSView] { [NSTextField(labelWithString: title), view] }
        let labelRow = NSStackView(views: [labelBottom, labelRight]); labelRow.spacing = 12
        let sizeRow = NSStackView(views: [iconSizeLabel, iconSize]); sizeRow.orientation = .vertical; sizeRow.alignment = .leading
        let useFinder = NSButton(title: "Use Finder's Settings", target: self, action: #selector(useFinderSettings))
        let note = NSTextField(wrappingLabelWithString: "Applies to QuietDesk's desktop only. Finder's own View Options are never changed.")
        note.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize); note.textColor = .secondaryLabelColor
        note.preferredMaxLayoutWidth = 250

        let grid = NSGridView(views: [
            row("Stack By:", stackBy),
            row("Sort By:", sortBy),
            row("Icon size:", sizeRow),
            row("Grid spacing:", gridSpacing),
            row("Text size:", textSize),
            row("Label position:", labelRow),
            [NSGridCell.emptyContentView, itemInfo],
            [NSGridCell.emptyContentView, iconPreview],
            [NSGridCell.emptyContentView, useFinder],
            [NSGridCell.emptyContentView, note],
        ])
        grid.rowSpacing = 10; grid.columnSpacing = 10
        grid.column(at: 0).xPlacement = .trailing
        grid.translatesAutoresizingMaskIntoConstraints = false
        iconSize.widthAnchor.constraint(equalToConstant: 150).isActive = true
        gridSpacing.widthAnchor.constraint(equalToConstant: 150).isActive = true
        guard let content = window?.contentView else { return }
        content.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -16),
            grid.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -16),
        ])
    }

    // MARK: - State

    private var current: ViewOptions { settings.effectiveViewOptions(finder: FinderDesktopPrefs.load()) }

    func refresh() {
        let o = current
        let prefs = FinderDesktopPrefs.load()
        let effectiveStacks = settings.stacksMode == .finder ? (StacksMode.allCases.first { $0.groupBy == prefs.groupBy } ?? .off) : settings.stacksMode
        stackBy.selectItem(at: stackModes.firstIndex(of: effectiveStacks) ?? 0)
        let effectiveSort = settings.sortKey == .finder ? (SortKey.allCases.first { $0.arrangeBy == prefs.arrangeBy } ?? .none) : settings.sortKey
        sortBy.selectItem(at: sortKeys.firstIndex(of: effectiveSort) ?? 0)
        iconSize.doubleValue = Double(ViewOptions.iconSizes.firstIndex(of: o.iconSize) ?? 2)
        iconSizeLabel.stringValue = "\(Int(o.iconSize)) × \(Int(o.iconSize))"
        gridSpacing.doubleValue = Double(o.gridSpacing)
        textSize.selectItem(at: ViewOptions.textSizes.firstIndex(of: o.textSize) ?? 2)
        labelBottom.state = o.labelOnBottom ? .on : .off
        labelRight.state = o.labelOnBottom ? .off : .on
        itemInfo.state = o.showItemInfo ? .on : .off
        iconPreview.state = o.showIconPreview ? .on : .off
    }

    @objc private func changed(_ sender: Any?) {
        var o = current
        o.iconSize = ViewOptions.iconSizes[max(0, min(ViewOptions.iconSizes.count - 1, Int(iconSize.doubleValue.rounded())))]
        o.gridSpacing = gridSpacing.doubleValue.rounded()
        o.textSize = ViewOptions.textSizes[max(0, textSize.indexOfSelectedItem)]
        o.labelOnBottom = labelBottom.state == .on
        o.showItemInfo = itemInfo.state == .on
        o.showIconPreview = iconPreview.state == .on
        settings.viewOptions = o
        settings.stacksMode = stackModes[max(0, stackBy.indexOfSelectedItem)]
        settings.sortKey = sortKeys[max(0, sortBy.indexOfSelectedItem)]
        iconSizeLabel.stringValue = "\(Int(o.iconSize)) × \(Int(o.iconSize))"
        onChange?()
    }

    @objc private func useFinderSettings() {
        settings.viewOptions = nil
        settings.stacksMode = .finder
        settings.sortKey = .finder
        refresh()
        onChange?()
    }
}

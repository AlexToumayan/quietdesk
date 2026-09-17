import AppKit
import Quartz
import UniformTypeIdentifiers

/// What the desktop surfaces (icon view and shield) need from their owner.
protocol DesktopSurfaceDelegate: AnyObject {
    var showsPreviews: Bool { get }
    var showsItemInfo: Bool { get }
    var isManualLayout: Bool { get }
    /// Called on any click on the desktop, before the click is handled (activation policy).
    func surfaceDidReceiveClick()
    func surface(toggleStack stack: StackGroup)
    /// Manual layouts: the user dropped items at new icon centres (flipped, screen-local).
    func surface(reposition centres: [URL: NSPoint], on screen: NSScreen)
    /// Submenus appended to the empty-desktop context menu (Sort By, Stacks, Labels).
    func surfaceMenuExtras() -> [NSMenuItem]
    func surface(cloudStatusFor url: URL) -> CloudStatus
    func surfaceRequestsReload()
}

/// Draws the desktop items for one screen and handles hover, selection (click, modifier
/// clicks, rubber band, keyboard, type-to-select), opening, rename, Quick Look, drag-out,
/// drops (files and file promises) onto folders or the desktop, spring-loaded folders,
/// context menus and accessibility. Coordinates are flipped (origin top-left).
///
/// Redraw policy: only the cells whose state changed are invalidated. There are no timers
/// at idle; the only timers live during a drag (spring-loading), while typing (type-to-select)
/// and after a click on a selected name (rename).
final class DesktopView: NSView, NSDraggingSource, NSTextFieldDelegate, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    var cells: [LayoutCell] = [] {
        willSet { keptSelection = Set(selectedURLs) }   // read against the OLD cells
        didSet {
            selection.removeAll(); hoverIndex = nil; focusIndex = nil
            setDropTarget(nil)                              // also stops a spring-loading timer
            pendingRenameClick?.cancel(); pendingRenameClick = nil
            bandStart = nil
            cancelRename()
            // Keep the selection across relayouts when the same items are still present.
            for (i, c) in cells.enumerated() where c.entry.url.map({ keptSelection.contains($0) }) ?? false { selection.insert(i) }
            rebuildAccessibility()
            updateTrackingAreas()
            needsDisplay = true
            if let panel = QLPreviewPanel.sharedPreviewPanelExists() ? QLPreviewPanel.shared() : nil, panel.isVisible { panel.reloadData() }
        }
    }
    var metrics: GridMetrics
    var labelMode: LabelMode = .hover { didSet { needsDisplay = true } }
    weak var delegate: DesktopSurfaceDelegate?
    weak var bandHost: RubberBandHost?
    let fileOps = FileOperations.shared

    var keptSelection = Set<URL>()
    var committingRename = false
    var dragCarriesPromise = false
    var hoverIndex: Int?
    var selection = Set<Int>()
    var focusIndex: Int?
    var dropTargetIndex: Int?
    var mouseDownCell: Int?
    var mouseDownPoint = NSPoint.zero
    var didDrag = false
    var bandStart: NSPoint?
    var truncationCache: [String: NSAttributedString] = [:]
    var eligibility: [String: Bool] = [:]
    var axElements: [NSAccessibilityElement] = []

    // rename
    var renameField: RenameField?
    var renamingIndex: Int?
    var pendingRenameClick: DispatchWorkItem?
    var keyObserver: NSObjectProtocol?
    // type-to-select
    var typeBuffer = ""
    var typeTimer: Timer?
    // spring-loaded folders during drags
    var springTimer: Timer?
    var springTarget: Int?
    // manual-layout drags
    var dragStartScreenPoint = NSPoint.zero
    var draggedCentres: [URL: NSPoint] = [:]


    init(frame: NSRect, metrics: GridMetrics) {
        self.metrics = metrics
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL] + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) })
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    deinit {
        if QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared(), panel.dataSource === self {
            panel.dataSource = nil
            panel.delegate = nil
        }
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var selectedURLs: [URL] { selection.sorted().compactMap { cells[$0].entry.url } }
    /// Selected files and folders, never mounted volumes (trash/duplicate/alias make no sense for them).
    var selectedFileURLs: [URL] { selection.sorted().compactMap { cells[$0].entry.item }.filter { !$0.isVolume }.map { $0.url } }
    var selectedItems: [DesktopItem] { selection.sorted().compactMap { cells[$0].entry.item } }

    // MARK: - Hover (window-server tracking rects; no polling)

    override func updateTrackingAreas() {
        for area in trackingAreas { removeTrackingArea(area) }
        for (i, cell) in cells.enumerated() {
            addTrackingArea(NSTrackingArea(rect: cell.iconRect.union(cell.labelRect),
                                           options: [.mouseEnteredAndExited, .activeAlways],
                                           owner: self, userInfo: ["i": i]))
        }
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        guard let i = event.trackingArea?.userInfo?["i"] as? Int else { return }
        setHover(i)
    }

    override func mouseExited(with event: NSEvent) {
        guard let i = event.trackingArea?.userInfo?["i"] as? Int, hoverIndex == i else { return }
        setHover(nil)
    }

    /// Test hook used by the --render flag.
    func simulateHover(_ i: Int) { setHover(i) }

    func setHover(_ i: Int?) {
        guard i != hoverIndex else { return }
        let old = hoverIndex
        hoverIndex = i
        if let o = old { invalidate(o) }
        if let n = i { invalidate(n) }
    }

    func invalidate(_ i: Int) {
        guard i < cells.count else { return }
        setNeedsDisplay(cells[i].cellRect.union(expandedLabelRect(for: cells[i])))
    }

    func invalidate(url: URL) {
        for (i, c) in cells.enumerated() where c.entry.url == url || (c.entry.stack?.items.prefix(3).contains { $0.url == url } ?? false) { invalidate(i) }
    }

    /// The eligibility memo (a small metadata read per file) persists across relayouts; it is
    /// dropped per file when that file changes, and wholesale when iCloud status changes.
    func forgetEligibility(of url: URL) { eligibility[url.path] = nil }

    func cloudStatusDidChange() {
        eligibility.removeAll()
        needsDisplay = true
    }
    // (Per-item updates come through forgetEligibility(of:) and invalidate(url:).)

    // MARK: - Selection

    func select(_ new: Set<Int>) {
        let changed = selection.symmetricDifference(new)
        selection = new
        changed.forEach(invalidate)
        if let panel = QLPreviewPanel.sharedPreviewPanelExists() ? QLPreviewPanel.shared() : nil, panel.isVisible { panel.reloadData() }
    }

    func toggle(_ i: Int) {
        var s = selection
        if s.contains(i) { s.remove(i) } else { s.insert(i) }
        select(s)
    }

    func setFocus(_ i: Int?) {
        let old = focusIndex
        focusIndex = i
        if let o = old { invalidate(o) }
        if let n = i { invalidate(n) }
    }

    func open(_ indices: [Int]) {
        for i in indices where i < cells.count {
            switch cells[i].entry {
            case .item(let item): NSWorkspace.shared.open(item.url)
            case .stack(let stack): NSWorkspace.shared.activateFileViewerSelecting(stack.items.map { $0.url })
            }
        }
    }
}

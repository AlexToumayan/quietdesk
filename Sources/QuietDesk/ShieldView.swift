import AppKit

/// Full-screen, bitmap-free layer that sits under the drawn icon window. Its only pixels are a
/// server-composited solid colour at alpha 1/255, so it costs no backing-store memory, yet it
/// makes the overlay own every click on the wallpaper while enabled (clicks, rubber-band
/// selection, drops onto the desktop, the empty-desktop context menu).
final class ShieldView: NSView, RubberBandHost {
    weak var iconView: DesktopView?
    weak var delegate: DesktopSurfaceDelegate?
    private var bandLayer: CALayer?
    private var downPoint: NSPoint?
    private var dragged = false
    /// Decided at mouse-down: a mouse-up's click count drops to 0 after a slow press, and the
    /// modifiers that matter are the ones held when the button went down.
    private var plainDown = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        layer?.backgroundColor = CGColor(gray: 0, alpha: 1.0 / 255.0)
        registerForDraggedTypes([.fileURL] + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) })
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: - Clicks on the wallpaper

    private func focusIconView() {
        if let v = iconView { v.commitRename(); v.window?.makeKey(); v.window?.makeFirstResponder(v) }
        delegate?.surfaceDidReceiveClick()
    }

    override func mouseDown(with event: NSEvent) {
        DebugLog.log("shield mouseDown \(DebugLog.describe(event))")
        plainDown = false
        // The first click of a double-click collapsed a Stack and the icon window shrank away
        // from under the pointer: the second click still means "open what I clicked".
        if let v = iconView, let target = v.firstClickTarget(for: event) {
            focusIconView()
            v.open([target])
            return
        }
        focusIconView()
        if !event.modifierFlags.contains(.command) && !event.modifierFlags.contains(.shift) {
            iconView?.clearSelection()
            delegate?.surfaceCollapseStacks()
        }
        downPoint = convert(event.locationInWindow, from: nil)
        dragged = false
        plainDown = event.clickCount == 1 && event.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty
    }

    override func mouseDragged(with event: NSEvent) {
        guard let d = downPoint else { return }
        let p = convert(event.locationInWindow, from: nil)
        if hypot(p.x - d.x, p.y - d.y) > 4 { dragged = true }
        let band = NSRect(x: min(p.x, d.x), y: min(p.y, d.y), width: abs(p.x - d.x), height: abs(p.y - d.y))
        showRubberBand(localRect: band)
        iconView?.selectCells(intersectingScreenRect: screenRect(band))
    }

    override func mouseUp(with event: NSEvent) {
        let wasPlainClick = downPoint != nil && !dragged && plainDown
        plainDown = false
        downPoint = nil
        showRubberBand(localRect: nil)
        if wasPlainClick { delegate?.surfaceWallpaperClicked() }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        focusIconView()
        iconView?.clearSelection()
        return DesktopMenus.emptyDesktopMenu(target: self, extras: delegate?.surfaceMenuExtras() ?? [])
    }

    @objc func menuNewFolder() { iconView?.menuNewFolder() }
    @objc func menuPaste() { iconView?.menuPaste() }
    @objc func menuShowDesktop() { iconView?.menuShowDesktop() }
    @objc func menuChangeWallpaper() { DesktopMenus.openWallpaperSettings() }

    // MARK: - Rubber band (a plain CALayer: no bitmap, server-side compositing)

    func showRubberBand(screenRect: NSRect?) { showRubberBand(localRect: screenRect.map(localRect)) }

    private func showRubberBand(localRect: NSRect?) {
        guard let rect = localRect else { bandLayer?.removeFromSuperlayer(); bandLayer = nil; return }
        if bandLayer == nil {
            let l = CALayer()
            l.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
            l.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.6).cgColor
            l.borderWidth = 1
            l.actions = ["bounds": NSNull(), "position": NSNull(), "frame": NSNull()]   // no implicit animation
            layer?.addSublayer(l)
            bandLayer = l
        }
        bandLayer?.frame = rect
    }

    private func screenRect(_ r: NSRect) -> NSRect {
        guard let w = window else { return r }
        return w.convertToScreen(convert(r, to: nil))
    }

    private func localRect(_ r: NSRect) -> NSRect {
        guard let w = window else { return r }
        return convert(w.convertFromScreen(r), from: nil)
    }

    // MARK: - Drops onto the desktop

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if sender.draggingSource is DesktopView { return (delegate?.isManualLayout ?? false) ? .move : [] }
        if sender.draggingPasteboard.canReadObject(forClasses: [NSFilePromiseReceiver.self], options: nil) { return .copy }
        return sender.draggingSourceOperationMask.contains(.move) ? .move : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if let source = sender.draggingSource as? DesktopView {
            return DesktopDrop.reposition(from: source, dropScreenPoint: window?.convertPoint(toScreen: sender.draggingLocation) ?? .zero, targetView: self, delegate: delegate)
        }
        return DesktopDrop.perform(sender, into: DesktopModel.desktopURL, fileOps: FileOperations.shared)
    }
}

protocol RubberBandHost: AnyObject {
    func showRubberBand(screenRect: NSRect?)
}

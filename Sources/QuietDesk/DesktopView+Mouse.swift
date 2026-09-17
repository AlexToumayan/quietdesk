import AppKit

// Clicks, rubber band, drag-out, and the hooks the shield window uses.
extension DesktopView {

    func cellIndex(at point: NSPoint) -> Int? {
        cells.firstIndex { $0.iconRect.insetBy(dx: -4, dy: -4).contains(point) || $0.labelRect.contains(point) }
    }

    /// For the second click of a double-click: the cell of the item the first click landed on,
    /// wherever the layout has moved it since (nil when there was no such item or too long ago).
    func firstClickTarget(for event: NSEvent) -> Int? {
        guard event.clickCount >= 2, let url = lastClickURL, event.timestamp - lastClickTime < NSEvent.doubleClickInterval * 2 else { return nil }
        return cells.firstIndex { $0.entry.url == url }
    }

    override func mouseDown(with event: NSEvent) {
        if renameField != nil { commitRename() }
        pendingRenameClick?.cancel(); pendingRenameClick = nil
        let p = convert(event.locationInWindow, from: nil)
        DebugLog.log("icons mouseDown at \(Int(p.x)),\(Int(p.y)) \(DebugLog.describe(event)) cell=\(cellIndex(at: p).map { "\($0) \(cells[$0].entry.isStack ? "stack" : "item") \(cells[$0].entry.displayName)" } ?? "none") key=\(window?.isKeyWindow ?? false) active=\(NSApp.isActive)")
        mouseDownPoint = p
        didDrag = false
        bandStart = nil
        window?.makeKey()
        window?.makeFirstResponder(self)
        delegate?.surfaceDidReceiveClick()
        let cmd = event.modifierFlags.contains(.command), shift = event.modifierFlags.contains(.shift)
        // The second click of a double-click belongs to the item the first click hit, even if a
        // collapse relayout has since moved that item (or the whole window) from under the pointer.
        guard var i = firstClickTarget(for: event) ?? cellIndex(at: p) else {
            mouseDownCell = nil; lastClickURL = nil
            if !cmd && !shift { select([]); setFocus(nil); delegate?.surfaceCollapseStacks() }
            bandStart = p
            return
        }
        // Clicking anything that is not a Stack or one of an open Stack's members collapses Stacks.
        // Collapsing relayouts synchronously, so find the clicked item again in the new cells.
        if !cells[i].entry.isStack, cells[i].entry.item?.stackTitle == nil, let url = cells[i].entry.url {
            delegate?.surfaceCollapseStacks()
            guard let again = cells.firstIndex(where: { $0.entry.url == url }) else { mouseDownCell = nil; return }
            i = again
        }
        if event.clickCount == 1 { lastClickURL = cells[i].entry.url; lastClickTime = event.timestamp }
        let wasSoleSelection = selection == [i]
        mouseDownCell = i
        if cmd {
            toggle(i)
        } else if shift, let f = focusIndex {
            select(Set(min(f, i)...max(f, i)))
        } else if !selection.contains(i) {
            select([i])
        }
        setFocus(i)
        if event.clickCount == 2 {
            // A Stack toggles on the first click (mouse up); the second click of a double-click
            // must not open a Finder window on top of that.
            if !cells[i].entry.isStack { open([i]) }
        } else if event.clickCount == 1, wasSoleSelection, !cmd, !shift, cells[i].labelRect.contains(p), cells[i].entry.url != nil {
            // Finder: a second, slow click on a selected name starts renaming.
            let work = DispatchWorkItem { [weak self] in self?.beginRename(i) }
            pendingRenameClick = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let d = bandStart {
            let band = NSRect(x: min(p.x, d.x), y: min(p.y, d.y), width: abs(p.x - d.x), height: abs(p.y - d.y))
            bandHost?.showRubberBand(screenRect: screenRect(band))
            select(Set(cells.indices.filter { cells[$0].iconRect.union(cells[$0].labelRect).intersects(band) }))
            return
        }
        guard let i = mouseDownCell else { return }
        guard hypot(p.x - mouseDownPoint.x, p.y - mouseDownPoint.y) > 4 else { return }
        pendingRenameClick?.cancel(); pendingRenameClick = nil
        didDrag = true
        let indices = selection.contains(i) ? selection.sorted() : [i]
        var items: [NSDraggingItem] = []
        draggedCentres.removeAll()
        for j in indices {
            guard let url = cells[j].entry.url else { continue }
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            item.setDraggingFrame(cells[j].iconRect, contents: image(for: cells[j].entry.item!, size: metrics.iconSize))
            items.append(item)
            draggedCentres[url.standardizedFileURL] = NSPoint(x: cells[j].iconRect.midX, y: cells[j].iconRect.midY)
        }
        mouseDownCell = nil
        guard !items.isEmpty else { return }
        dragStartScreenPoint = window?.convertPoint(toScreen: event.locationInWindow) ?? .zero
        beginDraggingSession(with: items, event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        DebugLog.log("icons mouseUp \(DebugLog.describe(event)) downCell=\(mouseDownCell.map(String.init) ?? "none") dragged=\(didDrag) band=\(bandStart != nil)")
        defer { mouseDownCell = nil }
        if bandStart != nil { bandStart = nil; bandHost?.showRubberBand(screenRect: nil); return }
        // Single click on a Stack toggles it, like Finder.
        if let i = mouseDownCell, !didDrag, event.clickCount == 1, let stack = cells[i].entry.stack,
           !event.modifierFlags.contains(.command), !event.modifierFlags.contains(.shift) {
            delegate?.surface(toggleStack: stack)
        }
    }

    // Drag source: other apps decide copy/move/link; inside the overlay: move into a folder or reposition.
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.copy, .move, .link] : [.move]
    }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        session.draggingFormation = .stack      // AppKit shows the item-count badge for multi-item drags
    }

    // MARK: - Hooks used by the shield window

    func clearSelection() { select([]); setFocus(nil) }

    func selectCells(intersectingScreenRect r: NSRect) {
        guard let w = window else { return }
        let local = convert(w.convertFromScreen(r), from: nil)
        select(Set(cells.indices.filter { cells[$0].iconRect.union(cells[$0].labelRect).intersects(local) }))
    }

    func screenRect(_ r: NSRect) -> NSRect {
        guard let w = window else { return r }
        return w.convertToScreen(convert(r, to: nil))
    }

    func screenPoint(_ p: NSPoint) -> NSPoint {
        guard let w = window else { return p }
        return w.convertPoint(toScreen: convert(p, to: nil))
    }
}

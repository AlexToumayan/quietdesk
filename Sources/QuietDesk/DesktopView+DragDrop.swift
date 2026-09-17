import AppKit

// Drop destination: files and file promises onto folders or the desktop; spring-loaded folders.
extension DesktopView {

    func folderCell(at point: NSPoint) -> Int? {
        guard let i = cellIndex(at: point), let item = cells[i].entry.item, item.isFolder || item.isVolume else { return nil }
        return i
    }

    func setDropTarget(_ i: Int?) {
        guard i != dropTargetIndex else { return }
        let old = dropTargetIndex
        dropTargetIndex = i
        if let o = old { invalidate(o) }
        if let n = i { invalidate(n) }
        // Spring-loaded folders: hovering over a folder while dragging opens it after a moment.
        springTimer?.invalidate(); springTimer = nil
        if let n = i, let url = cells[n].entry.url {
            let timer = Timer(timeInterval: 1.0, repeats: false) { [weak self] _ in
                self?.springTimer = nil
                NSWorkspace.shared.open(url)
            }
            RunLoop.main.add(timer, forMode: .common)   // fires during drag tracking too
            springTimer = timer
        }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        // One pasteboard round trip per drag, not per mouse move.
        dragCarriesPromise = sender.draggingPasteboard.canReadObject(forClasses: [NSFilePromiseReceiver.self], options: nil)
        return draggingUpdated(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let p = convert(sender.draggingLocation, from: nil)
        let target = folderCell(at: p)
        setDropTarget(target)
        let fromOverlay = sender.draggingSource is DesktopView
        if fromOverlay && target == nil { return (delegate?.isManualLayout ?? false) ? .move : [] }
        if dragCarriesPromise { return .copy }
        return sender.draggingSourceOperationMask.contains(.move) ? .move : .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { setDropTarget(nil); dragCarriesPromise = false }
    override func draggingEnded(_ sender: NSDraggingInfo) { setDropTarget(nil); dragCarriesPromise = false }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let p = convert(sender.draggingLocation, from: nil)
        setDropTarget(nil)
        if let source = sender.draggingSource as? DesktopView, folderCell(at: p) == nil {
            return DesktopDrop.reposition(from: source, dropScreenPoint: window?.convertPoint(toScreen: sender.draggingLocation) ?? .zero, targetView: self, delegate: delegate)
        }
        let destination: URL
        if let t = folderCell(at: p), let url = cells[t].entry.url { destination = url } else { destination = DesktopModel.desktopURL }
        return DesktopDrop.perform(sender, into: destination, fileOps: fileOps)
    }
}

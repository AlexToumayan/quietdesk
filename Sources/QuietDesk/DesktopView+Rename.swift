import AppKit

// Inline rename with Finder semantics.
extension DesktopView {

    func beginRename(_ i: Int) {
        guard i < cells.count, let item = cells[i].entry.item, !item.isVolume, renameField == nil else { return }
        if !(window?.isKeyWindow ?? false) { window?.makeKey() }
        let cell = cells[i]
        // Wide enough to edit in even on the compact grid, centred on the cell, kept on screen.
        let width = max(cell.cellRect.width + 12, 120)
        let x = max(0, min(cell.cellRect.midX - width / 2, bounds.width - width))
        let field = RenameField(frame: NSRect(x: x, y: cell.labelRect.minY - 2, width: width, height: metrics.labelLineHeight * 2 + 8))
        field.font = NSFont.systemFont(ofSize: metrics.textSize)
        field.alignment = .center
        field.isBezeled = true; field.bezelStyle = .squareBezel
        field.backgroundColor = .white; field.textColor = .black
        field.stringValue = item.url.lastPathComponent
        field.delegate = self
        field.cell?.wraps = true; field.cell?.isScrollable = false
        addSubview(field)
        renamingIndex = i
        renameField = field
        invalidate(i)
        window?.makeFirstResponder(field)
        let stem = FileOperations.isPlainDirectory(item.url) ? item.url.lastPathComponent : (item.url.lastPathComponent as NSString).deletingPathExtension
        field.currentEditor()?.selectedRange = NSRange(location: 0, length: (stem as NSString).length)
        keyObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in self?.commitRename() }
    }

    func endRename() {
        renameField?.removeFromSuperview()
        renameField = nil
        if let o = keyObserver { NotificationCenter.default.removeObserver(o); keyObserver = nil }
        if let i = renamingIndex { renamingIndex = nil; invalidate(i) }
        window?.makeFirstResponder(self)
    }

    func commitRename() {
        guard !committingRename else { return }          // the error alert resigns key; ignore that re-entry
        committingRename = true
        defer { committingRename = false }
        guard let field = renameField, let i = renamingIndex, i < cells.count, let url = cells[i].entry.url else { endRename(); return }
        let newName = field.stringValue
        if newName == url.lastPathComponent || newName.isEmpty { endRename(); return }
        do {
            try fileOps.rename(url, to: newName)
            endRename()
        } catch {
            NSSound.beep()
            DesktopMenus.showError("The name \"\(newName)\" can't be used.", (error as? FileOperations.OperationError)?.description ?? error.localizedDescription)
            // Keep editing.
            window?.makeKey()
            window?.makeFirstResponder(field)
        }
    }

    func cancelRename() { if renameField != nil { endRename() } }

    /// Ends a rename without ever putting up an alert: keeps the new name when it is usable and
    /// drops it otherwise. For moments when the desktop is being taken away (a reveal).
    func finishRenameQuietly() {
        guard let field = renameField, let i = renamingIndex, i < cells.count, let url = cells[i].entry.url else { cancelRename(); return }
        let newName = field.stringValue
        if newName != url.lastPathComponent, !newName.isEmpty { try? fileOps.rename(url, to: newName) }
        endRename()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) { commitRename(); return true }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) { cancelRename(); return true }
        return false
    }
}

import AppKit

// Keyboard: Finder shortcuts, arrows, type-to-select.
extension DesktopView {

    override func keyDown(with event: NSEvent) {
        pendingRenameClick?.cancel(); pendingRenameClick = nil
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let cmd = flags.contains(.command), option = flags.contains(.option), shift = flags.contains(.shift)
        switch event.keyCode {
        case 123: moveFocus(dCol: 1, dRow: 0); return                  // left (columns count from the right)
        case 124: moveFocus(dCol: -1, dRow: 0); return                 // right
        case 125: if cmd { open(selection.sorted()) } else { moveFocus(dCol: 0, dRow: 1) }; return
        case 126: moveFocus(dCol: 0, dRow: -1); return
        case 53:  select([]); setFocus(nil); return                    // escape
        case 36 where !cmd, 76 where !cmd:                             // return / enter: rename
            if selection.count == 1, let i = selection.first { beginRename(i) } else { NSSound.beep() }
            return
        case 49 where !cmd: toggleQuickLook(); return                  // space
        case 51 where cmd: fileOps.trash(selectedFileURLs); return     // cmd-delete (never a volume)
        default: break
        }
        if cmd, let chars = event.charactersIgnoringModifiers?.lowercased() {
            switch chars {
            case "o": open(selection.sorted()); return
            case "a": select(Set(cells.indices)); return
            case "i": getInfo(); return
            case "d": fileOps.duplicate(selectedFileURLs); return
            case "l": fileOps.makeAliases(selectedFileURLs); return
            case "y": toggleQuickLook(); return
            case "c": fileOps.copyToPasteboard(selectedURLs); return
            case "v":
                if option { let urls = FileOperations.pasteboardFileURLs(); if urls.isEmpty { NSSound.beep() } else { fileOps.move(urls, into: DesktopModel.desktopURL) } }
                else { paste() }
                return
            case "z": if shift { fileOps.undoManager.redo() } else { fileOps.undoManager.undo() }; return
            case "e": for item in selectedItems where item.isVolume { fileOps.eject(item.url) }; return
            case "r": menuShowOriginal(); return
            case "n":
                if shift { fileOps.newFolder(in: DesktopModel.desktopURL) }
                else {
                    FinderAutomation.openNewWindow(at: FileManager.default.homeDirectoryForCurrentUser) { error in
                        if let error { DesktopMenus.showError("New Finder Window needs Finder", error.description) }
                    }
                }
                return
            default: break
            }
        }
        if !cmd, !flags.contains(.control), let chars = event.characters, !chars.isEmpty,
           chars.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) {
            typeToSelect(chars)
            return
        }
        super.keyDown(with: event)
    }

    func typeToSelect(_ chars: String) {
        typeTimer?.invalidate()
        typeBuffer += chars
        let timer = Timer(timeInterval: 1.0, repeats: false) { [weak self] _ in self?.typeBuffer = ""; self?.typeTimer = nil }
        RunLoop.main.add(timer, forMode: .common)
        typeTimer = timer
        let needle = typeBuffer.lowercased()
        if let i = cells.firstIndex(where: { $0.entry.displayName.lowercased().hasPrefix(needle) })
            ?? cells.firstIndex(where: { $0.entry.displayName.lowercased().contains(needle) }) {
            select([i]); setFocus(i)
        }
    }

    func moveFocus(dCol: Int, dRow: Int) {
        let current = focusIndex ?? selection.min() ?? 0
        guard current < cells.count else { return }
        let c = cells[current]
        guard let target = cells.firstIndex(where: { $0.col == c.col + dCol && $0.row == c.row + dRow }) else { return }
        select([target]); setFocus(target)
        window?.makeFirstResponder(self)
    }
}

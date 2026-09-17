import AppKit

// Icons, badges, labels and the redraw policy.
extension DesktopView {

    /// Cheap bound that contains a cell and any expanded label it could show.
    func reach(of cell: LayoutCell) -> NSRect {
        cell.cellRect.insetBy(dx: -metrics.cellWidth * 0.75, dy: 0).union(NSRect(x: cell.cellRect.minX, y: cell.cellRect.minY, width: cell.cellRect.width, height: cell.cellRect.height + metrics.labelLineHeight * 5))
    }

    override func draw(_ dirtyRect: NSRect) {
        for (i, cell) in cells.enumerated() where reach(of: cell).intersects(dirtyRect) {
            drawIcon(cell, index: i)
            if i != hoverIndex, i != renamingIndex, labelVisible(i) {
                drawLabel(cell, style: selection.contains(i) ? .selected : (focusIndex == i ? .focused : .plain))
            }
        }
        // The hovered label is drawn last so it sits above its neighbours.
        if let h = hoverIndex, h < cells.count, h != renamingIndex, labelMode != .hidden {
            drawLabel(cells[h], style: selection.contains(h) ? .selected : .hovered)
        }
    }

    func labelVisible(_ i: Int) -> Bool {
        switch labelMode {
        case .always: return true
        case .hover: return selection.contains(i) || focusIndex == i
        case .hidden: return false
        }
    }

    func image(for item: DesktopItem, size: CGFloat) -> NSImage {
        if delegate?.showsPreviews ?? false, !item.isFolder, !item.isVolume, !item.isPackage {
            let key = item.url.path
            let eligible: Bool
            if let cached = eligibility[key] { eligible = cached } else { eligible = ThumbnailCache.isEligible(item.url); eligibility[key] = eligible }
            if eligible, let thumb = ThumbnailCache.shared.thumbnail(for: item.url, size: size, scale: window?.backingScaleFactor ?? 2) {
                return thumb
            }
        }
        return IconCache.shared.icon(for: item.url, size: size)
    }

    func drawIcon(_ cell: LayoutCell, index i: Int) {
        let selected = selection.contains(i), dropTarget = dropTargetIndex == i
        if selected || dropTarget {
            NSColor(calibratedWhite: 0.5, alpha: dropTarget ? 0.5 : 0.35).setFill()
            NSBezierPath(roundedRect: cell.iconRect.insetBy(dx: -4, dy: -4), xRadius: 5, yRadius: 5).fill()
        }
        let hints: [NSImageRep.HintKey: Any] = [.interpolation: NSImageInterpolation.high]
        switch cell.entry {
        case .item(let item):
            image(for: item, size: metrics.iconSize).draw(in: cell.iconRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: hints)
            drawBadges(for: item, cell: cell)
        case .stack(let stack):
            // A pile: the newest item's icon on top of two offset copies of the next ones.
            let expanded = stack.items.first?.stackTitle != nil || isExpanded(stack)
            let spread: CGFloat = expanded ? 5 : 3
            let top = Array(stack.items.prefix(3))
            for (k, item) in top.enumerated().reversed() {
                let off = CGFloat(k) * spread
                let r = cell.iconRect.offsetBy(dx: off, dy: -off).insetBy(dx: CGFloat(k) * 1.5, dy: CGFloat(k) * 1.5)
                image(for: item, size: metrics.iconSize).draw(in: r, from: .zero, operation: .sourceOver, fraction: k == 0 ? 1 : 0.8, respectFlipped: true, hints: hints)
            }
            if expanded, let chevron = Self.symbol("chevron.down.circle.fill", pointSize: 10, color: .white) {
                chevron.draw(in: NSRect(x: cell.iconRect.maxX - 8, y: cell.iconRect.maxY - 8, width: 12, height: 12), from: .zero, operation: .sourceOver, fraction: 0.95, respectFlipped: true, hints: hints)
            }
        }
    }

    func isExpanded(_ stack: StackGroup) -> Bool {
        cells.contains { $0.entry.item?.stackTitle == stack.title }
    }

    /// Cloud-status glyph after the label and tag colour dots before it (Finder's desktop style).
    func drawBadges(for item: DesktopItem, cell: LayoutCell) {
        // Cloud status
        if item.isUbiquitous, let d = delegate {
            let status = d.surface(cloudStatusFor: item.url)
            let name: String?
            switch status {
            case .notInCloud: name = nil
            case .current: name = "checkmark.icloud"
            case .notDownloaded: name = "icloud.and.arrow.down"
            case .downloading: name = "icloud.and.arrow.down"
            case .uploading, .notUploaded: name = "icloud.and.arrow.up"
            case .error: name = "exclamationmark.icloud"
            }
            if let name, let glyph = Self.symbol(name, pointSize: 9, color: NSColor.white.withAlphaComponent(0.9)) {
                // A small badge on the icon's bottom-right corner (works for both label positions).
                let r = NSRect(x: cell.iconRect.maxX - 9, y: cell.iconRect.maxY - 7, width: 13, height: 11)
                glyph.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
            }
        }
        // Tag dots (up to three, overlapping) under the icon's left edge.
        if !item.tags.isEmpty {
            let dots = item.tags.prefix(3).reversed()
            var x = cell.iconRect.minX - 6
            for tag in dots {
                let r = NSRect(x: x, y: cell.iconRect.maxY - 4, width: 8, height: 8)
                NSColor.white.setFill(); NSBezierPath(ovalIn: r.insetBy(dx: -0.75, dy: -0.75)).fill()
                FileOperations.color(forTag: tag).setFill(); NSBezierPath(ovalIn: r).fill()
                x += 5
            }
        }
    }

    static var symbolCache: [String: NSImage] = [:]
    static func symbol(_ name: String, pointSize: CGFloat, color: NSColor) -> NSImage? {
        let key = "\(name)|\(pointSize)|\(color)"
        if let cached = symbolCache[key] { return cached }
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)) else { return nil }
        let tinted = NSImage(size: base.size, flipped: false) { rect in
            base.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        symbolCache[key] = tinted
        return tinted
    }

    enum LabelStyle { case plain, hovered, selected, focused }

    func labelAttributes() -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = metrics.labelOnBottom ? .center : .left
        paragraph.lineBreakMode = .byWordWrapping
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.85)
        shadow.shadowBlurRadius = 2
        shadow.shadowOffset = NSSize(width: 0, height: 1)   // flipped view: +y is down
        return [.font: NSFont.systemFont(ofSize: metrics.textSize),
                .foregroundColor: NSColor.white,
                .paragraphStyle: paragraph,
                .shadow: shadow]
    }

    /// Full-name label box (up to 6 lines, up to ~2.4 cells wide), centred on the cell and
    /// clamped to the view so it never runs off a screen edge.
    func expandedLabelRect(for cell: LayoutCell) -> NSRect {
        let text = cell.entry.displayName as NSString
        let maxWidth = min(metrics.cellWidth * 2.4, bounds.width - 16)
        var attrs = labelAttributes()
        attrs[.shadow] = nil
        let bounding = text.boundingRect(with: NSSize(width: maxWidth - 12, height: metrics.labelLineHeight * 6),
                                         options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs)
        let w = ceil(bounding.width) + 12, h = ceil(bounding.height) + 4
        var x = metrics.labelOnBottom ? cell.cellRect.midX - w / 2 : cell.labelRect.minX - 6
        x = max(4, min(x, bounds.width - w - 4))
        return NSRect(x: x, y: cell.labelRect.minY - 1, width: w, height: h)
    }

    func drawLabel(_ cell: LayoutCell, style: LabelStyle) {
        let name = cell.entry.displayName
        switch style {
        case .plain:
            truncatedLabel(name, width: cell.labelRect.width).draw(with: cell.labelRect, options: [.usesLineFragmentOrigin])
            if metrics.infoLines > 0, let info = itemInfo(for: cell) {
                var attrs = labelAttributes()
                attrs[.foregroundColor] = NSColor.white.withAlphaComponent(0.78)
                attrs[.font] = NSFont.systemFont(ofSize: max(9, metrics.textSize - 1))
                let r = NSRect(x: cell.labelRect.minX, y: cell.labelRect.minY + 2 * metrics.labelLineHeight, width: cell.labelRect.width, height: metrics.labelLineHeight + 2)
                (info as NSString).draw(with: r, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs)
            }
        case .hovered, .selected, .focused:
            let box = expandedLabelRect(for: cell)
            switch style {
            case .selected: NSColor.controlAccentColor.setFill()
            case .hovered: NSColor.black.withAlphaComponent(0.55).setFill()
            default: NSColor.black.withAlphaComponent(0.35).setFill()
            }
            NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4).fill()
            var attrs = labelAttributes()
            attrs[.shadow] = nil
            (name as NSString).draw(with: box.insetBy(dx: 6, dy: 2), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs)
        }
    }

    /// Finder's "Show item info" line: item counts for folders and stacks, sizes for files,
    /// free space for volumes. Folder counts are computed lazily off the main thread.
    private func itemInfo(for cell: LayoutCell) -> String? {
        switch cell.entry {
        case .stack(let s): return s.items.count == 1 ? "1 item" : "\(s.items.count) items"
        case .item(let item): return ItemInfoCache.shared.info(for: item)
        }
    }

    /// Two-line, middle-truncated label like Finder's. Results are cached per name and width.
    func truncatedLabel(_ name: String, width: CGFloat) -> NSAttributedString {
        let key = "\(Int(width))|\(name)"
        if let cached = truncationCache[key] { return cached }
        let attrs = labelAttributes()
        let maxHeight = 2 * metrics.labelLineHeight + 1
        func fits(_ s: String) -> Bool {
            (s as NSString).boundingRect(with: NSSize(width: width, height: 1000), options: [.usesLineFragmentOrigin], attributes: attrs).height <= maxHeight
        }
        var text = name
        if !fits(name) {
            let chars = Array(name)
            var lo = 0, hi = chars.count - 1
            while lo < hi {
                let mid = (lo + hi + 1) / 2
                if fits(middleTruncate(chars, keep: mid)) { lo = mid } else { hi = mid - 1 }
            }
            text = middleTruncate(chars, keep: lo)
        }
        let result = NSAttributedString(string: text, attributes: attrs)
        if truncationCache.count > 1000 { truncationCache.removeAll() }
        truncationCache[key] = result
        return result
    }

    func middleTruncate(_ chars: [Character], keep: Int) -> String {
        guard keep < chars.count else { return String(chars) }
        let head = (keep + 1) / 2, tail = keep - head
        return String(chars[0..<head]) + "…" + String(chars[(chars.count - tail)...])
    }
}

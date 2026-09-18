import AppKit

/// Grid geometry. Finder's exact formula is internal; this one is CALIBRATED against Finder on
/// macOS 26.6 at text size 12: icon 36 / spacing 26 gives 84 x 82 pt cells, icon 36 / spacing 1
/// (the slider's minimum) gives 50 x 66, icon 32 / spacing 1 gives 48 x 60. Between and beyond
/// those points the mapping is assumed linear in the spacing value; other icon sizes extrapolate.
struct GridMetrics {
    let iconSize: CGFloat
    let textSize: CGFloat
    let cellWidth: CGFloat
    let cellHeight: CGFloat
    let topInset: CGFloat
    let rightInset: CGFloat
    let labelLineHeight: CGFloat
    let labelOnBottom: Bool
    let infoLines: Int          // 1 when "Show item info" adds a line under the name
    /// No room reserved for names: the grid is as dense as the icons allow, and a name appears
    /// over its neighbours only while its item is pointed at, selected or focused.
    let compact: Bool
    /// Name lines that fit under the icon: 2 normally, 1 at the tightest spacings (Finder shows
    /// one line there too), 0 on the compact grid.
    let nameLines: Int

    var labelLines: Int { compact ? 0 : nameLines + infoLines }

    static func from(options o: ViewOptions, compact: Bool = false) -> GridMetrics {
        let font = NSFont.systemFont(ofSize: o.textSize)
        let raw = font.ascender - font.descender + font.leading
        // Finder's label pitch (14 pt at 12 pt text); the labels are drawn at exactly this pitch
        // so the box in the cell formula and the box on screen are the same box.
        let lineHeight = raw.rounded()
        let infoOption = (!compact && o.showItemInfo) ? 1 : 0
        // Finder's cell holds the label lines (plus one for item info) and 2 pt around icons of
        // 36 pt and up: 32 -> 60 and 36 -> 66 at the tightest spacing, 36 / 26 -> 82.
        let labelBlock = compact ? 0 : CGFloat(2 + infoOption) * lineHeight + (o.iconSize >= 36 ? 2 : 0)
        let vGap = 0.64 * (o.gridSpacing - 1)
        let cw: CGFloat, ch: CGFloat
        if o.labelOnBottom || compact {
            // Finder never lets a cell get narrower than a short name needs (48 pt at 12 pt text).
            cw = max(o.iconSize + 13 + 1.36 * o.gridSpacing, 4 * o.textSize + 1.36 * (o.gridSpacing - 1)).rounded()
            ch = (o.iconSize + (compact ? 13 : labelBlock) + vGap).rounded()
        } else {
            // Label beside the icon: a wide, short cell.
            let textWidth = (max(96, o.textSize * 9) + 1.36 * o.gridSpacing).rounded()
            cw = o.iconSize + 6 + textWidth
            ch = (max(o.iconSize, labelBlock) + 6 + vGap).rounded()
        }
        // What actually fits under the icon: at the tightest spacing only one name line does.
        var nameLines = 0, info = 0
        if !compact && o.labelOnBottom {
            let avail = max(1, Int(floor((ch - o.iconSize - 2) / lineHeight)))
            info = (infoOption == 1 && avail >= 2) ? 1 : 0
            nameLines = min(2, avail - info)
        } else if !compact {
            nameLines = 2; info = infoOption
        }
        return GridMetrics(iconSize: o.iconSize, textSize: o.textSize, cellWidth: cw, cellHeight: ch,
                           topInset: 9, rightInset: 9, labelLineHeight: lineHeight,
                           labelOnBottom: o.labelOnBottom || compact, infoLines: info, compact: compact, nameLines: nameLines)
    }

    static func from(prefs: FinderDesktopPrefs) -> GridMetrics { from(options: .from(finder: prefs)) }
}

struct LayoutCell {
    let index: Int            // index into the model's entries
    let entry: LayoutEntry
    let col: Int              // 0 = rightmost column (sorted layouts); grid slot otherwise
    let row: Int              // 0 = top row
    let cellRect: NSRect      // flipped coordinates (origin top-left of the window)
    let iconRect: NSRect
    let labelRect: NSRect     // two-line label box under the icon

    /// The same cell expressed relative to a window whose top-left (flipped) origin is `origin`.
    func shifted(by origin: NSPoint) -> LayoutCell {
        LayoutCell(index: index, entry: entry, col: col, row: row,
                   cellRect: cellRect.offsetBy(dx: -origin.x, dy: -origin.y),
                   iconRect: iconRect.offsetBy(dx: -origin.x, dy: -origin.y),
                   labelRect: labelRect.offsetBy(dx: -origin.x, dy: -origin.y))
    }
}

struct ScreenLayout {
    let screen: NSScreen
    let cells: [LayoutCell]
    let columns: Int
    let rows: Int
}

enum Layout {
    /// Flipped, screen-local geometry of one screen's usable grid area.
    private struct Area {
        let topBar: CGFloat, leftEdge: CGFloat, rightEdge: CGFloat, rows: Int, cols: Int
        init(screen: NSScreen, metrics m: GridMetrics) {
            let f = screen.frame, v = screen.visibleFrame
            topBar = f.maxY - v.maxY
            let bottomBar = v.minY - f.minY
            leftEdge = v.minX - f.minX
            rightEdge = v.maxX - f.minX
            let usableHeight = f.height - topBar - bottomBar - m.topInset
            rows = max(1, Int(floor(usableHeight / m.cellHeight)))
            cols = max(1, Int(floor((rightEdge - leftEdge - m.rightInset) / m.cellWidth)))
        }
        func cellOrigin(col: Int, row: Int, metrics m: GridMetrics) -> NSPoint {
            NSPoint(x: rightEdge - m.rightInset - CGFloat(col + 1) * m.cellWidth, y: topBar + m.topInset + CGFloat(row) * m.cellHeight)
        }
        /// Nearest grid slot for a flipped screen-local point (icon centre).
        /// Nearest grid slot for an icon centre (the point may be off by a few points from the
        /// exact centre, so both axes round to the nearest slot rather than truncating).
        func slot(for p: NSPoint, metrics m: GridMetrics) -> (col: Int, row: Int) {
            let col = Int(((rightEdge - m.rightInset - p.x) / m.cellWidth - 0.5).rounded())
            let row = Int(((p.y - topBar - m.topInset - m.iconSize / 2) / m.cellHeight).rounded())
            return (max(0, min(cols - 1, col)), max(0, min(rows - 1, row)))
        }
    }

    static func makeCell(index: Int, entry: LayoutEntry, col: Int, row: Int, origin: NSPoint, metrics m: GridMetrics) -> LayoutCell {
        let cell = NSRect(x: origin.x, y: origin.y, width: m.cellWidth, height: m.cellHeight)
        let labelHeight = m.labelLines == 0 ? 0 : CGFloat(m.labelLines) * m.labelLineHeight + 1
        if m.labelOnBottom {
            let icon = NSRect(x: (cell.midX - m.iconSize / 2).rounded(), y: origin.y, width: m.iconSize, height: m.iconSize)
            let label = NSRect(x: origin.x + 5, y: icon.maxY + 2, width: m.cellWidth - 10, height: labelHeight)
            return LayoutCell(index: index, entry: entry, col: col, row: row, cellRect: cell, iconRect: icon, labelRect: label)
        }
        let icon = NSRect(x: origin.x + 3, y: (cell.midY - m.iconSize / 2).rounded(), width: m.iconSize, height: m.iconSize)
        let label = NSRect(x: icon.maxX + 4, y: (cell.midY - labelHeight / 2).rounded(), width: cell.maxX - icon.maxX - 8, height: labelHeight)
        return LayoutCell(index: index, entry: entry, col: col, row: row, cellRect: cell, iconRect: icon, labelRect: label)
    }

    /// Sorted desktop: fills columns from the top-right of the main display downward, then
    /// leftward, then continues on the next display, the way Finder's sorted desktop does.
    static func compute(entries: [LayoutEntry], screens: [NSScreen], metrics m: GridMetrics) -> [ScreenLayout] {
        var result: [ScreenLayout] = []
        var next = 0
        for screen in screens {
            let area = Area(screen: screen, metrics: m)
            var cells: [LayoutCell] = []
            outer: for col in 0..<area.cols {
                for row in 0..<area.rows {
                    guard next < entries.count else { break outer }
                    cells.append(makeCell(index: next, entry: entries[next], col: col, row: row, origin: area.cellOrigin(col: col, row: row, metrics: m), metrics: m))
                    next += 1
                }
            }
            result.append(ScreenLayout(screen: screen, cells: cells, columns: area.cols, rows: area.rows))
        }
        // Overflow: more entries than every display can hold. Finder overlaps them; so do we,
        // wrapping onto the main display again with a growing offset so every item stays visible
        // and clickable rather than silently dropped.
        if next < entries.count, let main = screens.first, !result.isEmpty {
            let area = Area(screen: main, metrics: m)
            var cells = result[0].cells
            var wrap = 1
            while next < entries.count {
                let shift = CGFloat(wrap) * 14
                outer: for col in 0..<area.cols {
                    for row in 0..<area.rows {
                        guard next < entries.count else { break outer }
                        var origin = area.cellOrigin(col: col, row: row, metrics: m)
                        origin.x = max(area.leftEdge, origin.x - shift)
                        origin.y = min(main.frame.height - m.cellHeight, origin.y + shift)
                        cells.append(makeCell(index: next, entry: entries[next], col: col, row: row, origin: origin, metrics: m))
                        next += 1
                    }
                }
                wrap += 1
            }
            result[0] = ScreenLayout(screen: main, cells: cells, columns: area.cols, rows: area.rows)
        }
        return result
    }

    /// Manually arranged desktop: entries with a known Finder position are placed there
    /// (position = icon centre, Finder's coordinate space: origin at the top-left of the main
    /// display, y down, points). Entries without a position take the first free grid slots.
    static func computeManual(entries: [LayoutEntry], positions: [URL: CGPoint], screens: [NSScreen], metrics m: GridMetrics, snapToGrid: Bool) -> [ScreenLayout] {
        guard let main = screens.first else { return [] }
        struct Placed { var cells: [LayoutCell] = []; var occupied = Set<Int>() }
        var placed = Array(repeating: Placed(), count: screens.count)
        let areas = screens.map { Area(screen: $0, metrics: m) }
        // Flipped rects of every screen in Finder's global space.
        let rects = screens.map { s in NSRect(x: s.frame.minX - main.frame.minX, y: main.frame.maxY - s.frame.maxY, width: s.frame.width, height: s.frame.height) }

        var unplaced: [Int] = []
        for (index, entry) in entries.enumerated() {
            // A position outside every display (a display that was unplugged) counts as unplaced.
            guard let url = entry.url?.standardizedFileURL, let p = positions[url], let si = rects.firstIndex(where: { $0.contains(p) }) else { unplaced.append(index); continue }
            var local = NSPoint(x: p.x - rects[si].minX, y: p.y - rects[si].minY)
            let area = areas[si]
            let slot = area.slot(for: local, metrics: m)
            if snapToGrid {
                let o = area.cellOrigin(col: slot.col, row: slot.row, metrics: m)
                local = NSPoint(x: o.x + m.cellWidth / 2, y: o.y + m.iconSize / 2)
            }
            let origin = NSPoint(x: local.x - m.cellWidth / 2, y: local.y - m.iconSize / 2)
            placed[si].cells.append(makeCell(index: index, entry: entry, col: slot.col, row: slot.row, origin: origin, metrics: m))
            placed[si].occupied.insert(slot.row * 10_000 + slot.col)
        }
        // Free slots, main display first, same enumeration as the sorted layout.
        var next = 0
        for si in screens.indices where next < unplaced.count {
            let area = areas[si]
            outer: for col in 0..<area.cols {
                for row in 0..<area.rows {
                    guard next < unplaced.count else { break outer }
                    let key = row * 10_000 + col
                    if placed[si].occupied.contains(key) { continue }
                    let index = unplaced[next]
                    placed[si].cells.append(makeCell(index: index, entry: entries[index], col: col, row: row, origin: area.cellOrigin(col: col, row: row, metrics: m), metrics: m))
                    placed[si].occupied.insert(key)
                    next += 1
                }
            }
        }
        return screens.indices.map { ScreenLayout(screen: screens[$0], cells: placed[$0].cells, columns: areas[$0].cols, rows: areas[$0].rows) }
    }

    /// Converts a flipped screen-local icon centre into Finder's global coordinate space.
    static func finderPoint(localIconCentre p: NSPoint, on screen: NSScreen, screens: [NSScreen]) -> CGPoint {
        guard let main = screens.first else { return p }
        return CGPoint(x: p.x + screen.frame.minX - main.frame.minX, y: p.y + main.frame.maxY - screen.frame.maxY)
    }

    /// The smallest screen region (flipped, screen-local) that contains every cell plus room
    /// for expanded hover labels. The drawn overlay window is kept this small so its backing
    /// store (memory) is proportional to the icon area; a separate bitmap-free shield window
    /// covers the rest of the screen.
    static func windowRegion(for layout: ScreenLayout, metrics m: GridMetrics) -> NSRect {
        guard var region = layout.cells.first?.cellRect else { return NSRect(x: 0, y: 0, width: 2, height: 2) }
        for cell in layout.cells { region = region.union(cell.cellRect) }
        let marginX = ceil(m.cellWidth * 0.8)
        // Room for the tallest name pill (6 lines) below the last row, plus its 3 pt hover rise.
        let marginBottom = ceil(max(m.labelLineHeight * 5, m.iconSize + 6 * m.labelLineHeight + 9 - m.cellHeight))
        region = NSRect(x: region.minX - marginX, y: region.minY, width: region.width + 2 * marginX, height: region.height + marginBottom)
        return region.intersection(NSRect(origin: .zero, size: layout.screen.frame.size)).integral
    }

    /// Converts a flipped screen-local rect into Cocoa screen coordinates for NSWindow.
    static func cocoaFrame(_ local: NSRect, on screen: NSScreen) -> NSRect {
        NSRect(x: screen.frame.minX + local.minX, y: screen.frame.maxY - local.maxY, width: local.width, height: local.height)
    }
}

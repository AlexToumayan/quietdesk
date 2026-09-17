import AppKit

/// Offline rendering helpers used by the developer flags (never at runtime otherwise).
enum Diagnostics {
    private static func writePNG(_ image: NSImage, to path: String) {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }

    /// Both status-item states (off: eye, enabled: eye.slash) on light and dark menu-bar strips, 4x.
    static func renderStatusItem(_ item: NSStatusItem?, to path: String) {
        guard let button = item?.button else { return }
        func snapshot(_ symbol: String) -> NSImage {
            let saved = button.image
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil).map { $0.isTemplate = true; return $0 }
            defer { button.image = saved }
            guard let rep = button.bitmapImageRepForCachingDisplay(in: button.bounds) else { return NSImage() }
            button.cacheDisplay(in: button.bounds, to: rep)
            let image = NSImage(size: button.bounds.size); image.addRepresentation(rep); return image
        }
        let states = [("off", snapshot("eye")), ("enabled", snapshot("eye.slash"))]
        let glyph = states[1].1
        let scale: CGFloat = 4
        let out = NSImage(size: NSSize(width: 200 * scale, height: 60 * scale), flipped: false) { rect in
            NSColor(white: 0.93, alpha: 1).setFill(); NSRect(x: 0, y: rect.height / 2, width: rect.width, height: rect.height / 2).fill()
            NSColor(white: 0.12, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: rect.width, height: rect.height / 2).fill()
            for (row, tint) in [(1, NSColor.black), (0, NSColor.white)] {
                let y = CGFloat(row) * rect.height / 2 + (rect.height / 2 - 22 * scale) / 2
                var x: CGFloat = 12 * scale
                for (label, image) in states {
                    let tinted = NSImage(size: image.size, flipped: false) { r in image.draw(in: r); tint.set(); r.fill(using: .sourceAtop); return true }
                    tinted.draw(in: NSRect(x: x, y: y, width: image.size.width * scale, height: 22 * scale))
                    (label as NSString).draw(at: NSPoint(x: x, y: y - 14 * scale), withAttributes: [.font: NSFont.systemFont(ofSize: 9 * scale), .foregroundColor: tint])
                    x += (image.size.width + 12) * scale
                }
                ("QuietDesk" as NSString).draw(at: NSPoint(x: x + 4 * scale, y: y + 4 * scale), withAttributes: [.font: NSFont.systemFont(ofSize: 13 * scale), .foregroundColor: tint])
            }
            return true
        }
        writePNG(out, to: path)
        print("rendered status item to \(path) (button size \(button.bounds.size))")
        if let w = button.window {
            print("status item window #\(w.windowNumber) visible=\(w.isVisible) level=\(w.level.rawValue) frame=\(w.frame) screen=\(w.screen?.localizedName ?? "none")")
            let onscreen = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]])?.contains { ($0[kCGWindowNumber as String] as? Int) == w.windowNumber } ?? false
            print("window server lists it on screen: \(onscreen)")
        } else { print("status item has NO window") }
    }

    /// Candidate SF Symbols for the menu-bar icon, on light and dark strips.
    static func renderIconCandidates() {
        let names = ["square.grid.3x3", "square.grid.3x3.square", "rectangle.dashed", "macwindow", "eye.slash", "square.dashed.inset.filled", "text.below.photo", "circle.grid.3x3"]
        let scale: CGFloat = 3
        let cell: CGFloat = 92
        let out = NSImage(size: NSSize(width: CGFloat(names.count) * cell * scale, height: 96 * scale), flipped: false) { rect in
            NSColor(white: 0.93, alpha: 1).setFill(); NSRect(x: 0, y: rect.height / 2, width: rect.width, height: rect.height / 2).fill()
            NSColor(white: 0.12, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: rect.width, height: rect.height / 2).fill()
            for (k, name) in names.enumerated() {
                guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 16, weight: .regular)) else { continue }
                for (row, tint) in [(1, NSColor.black), (0, NSColor.white)] {
                    let tinted = NSImage(size: base.size, flipped: false) { r in base.draw(in: r); tint.set(); r.fill(using: .sourceAtop); return true }
                    let x = (CGFloat(k) * cell + 10) * scale
                    let y = CGFloat(row) * rect.height / 2 + 24 * scale
                    tinted.draw(in: NSRect(x: x, y: y, width: base.size.width * scale, height: base.size.height * scale))
                    ((k + 1).description as NSString).draw(at: NSPoint(x: x, y: y - 18 * scale), withAttributes: [.font: NSFont.systemFont(ofSize: 11 * scale), .foregroundColor: tint])
                }
            }
            return true
        }
        let path = NSTemporaryDirectory() + "quietdesk-icon-candidates.png"
        writePNG(out, to: path)
        print("candidates: " + names.enumerated().map { "\($0.offset + 1)=\($0.element)" }.joined(separator: "  "))
        print("rendered \(path)")
    }
}

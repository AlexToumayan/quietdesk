import AppKit

// Three app-icon directions for QuietDesk, drawn with Core Graphics only.
// Usage: icons <variant A|B|C> <pixels> <out.png>   or   icons sheet <out.png>

func squircle(_ r: NSRect) -> NSBezierPath {
    // macOS icon silhouette: rounded rect with ~22.4% corner radius (close to Apple's continuous corners).
    NSBezierPath(roundedRect: r, xRadius: r.width * 0.224, yRadius: r.height * 0.224)
}

func background(_ s: CGFloat, top: NSColor, bottom: NSColor) {
    let body = NSRect(x: s * 0.05, y: s * 0.05, width: s * 0.9, height: s * 0.9)
    let path = squircle(body)
    // soft drop shadow
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.28); shadow.shadowBlurRadius = s * 0.04; shadow.shadowOffset = NSSize(width: 0, height: -s * 0.02)
    shadow.set()
    NSColor.black.setFill(); path.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: top, ending: bottom)!.draw(in: path, angle: -90)
    // glass highlight: a smooth fade over the whole body, strongest at the top, no seam
    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    let hl = NSGradient(colorsAndLocations: (NSColor.white.withAlphaComponent(0.0), 0), (NSColor.white.withAlphaComponent(0.0), 0.45), (NSColor.white.withAlphaComponent(0.20), 1))!
    hl.draw(in: body, angle: 90)
    NSGraphicsContext.restoreGraphicsState()
    // hairline inner edge
    NSColor.white.withAlphaComponent(0.18).setStroke(); path.lineWidth = s * 0.006; path.stroke()
}

func glyphShadow(_ s: CGFloat) -> NSShadow {
    let sh = NSShadow(); sh.shadowColor = NSColor.black.withAlphaComponent(0.25); sh.shadowBlurRadius = s * 0.02; sh.shadowOffset = NSSize(width: 0, height: -s * 0.012); return sh
}

// A: slashed eye, the same story as the menu-bar icon.
func drawA(_ s: CGFloat) {
    background(s, top: NSColor(calibratedRed: 0.30, green: 0.36, blue: 0.52, alpha: 1), bottom: NSColor(calibratedRed: 0.12, green: 0.15, blue: 0.27, alpha: 1))
    let cx = s * 0.5, cy = s * 0.5
    let w = s * 0.60, h = s * 0.19
    let stroke = s * 0.05
    NSGraphicsContext.saveGraphicsState(); glyphShadow(s).set()
    // almond with round lids
    let eye = NSBezierPath()
    eye.move(to: NSPoint(x: cx - w / 2, y: cy))
    eye.curve(to: NSPoint(x: cx + w / 2, y: cy), controlPoint1: NSPoint(x: cx - w * 0.27, y: cy + h * 1.3), controlPoint2: NSPoint(x: cx + w * 0.27, y: cy + h * 1.3))
    eye.curve(to: NSPoint(x: cx - w / 2, y: cy), controlPoint1: NSPoint(x: cx + w * 0.27, y: cy - h * 1.3), controlPoint2: NSPoint(x: cx - w * 0.27, y: cy - h * 1.3))
    eye.close()
    eye.lineWidth = stroke; eye.lineJoinStyle = .round
    NSColor.white.setStroke(); eye.stroke()
    // pupil
    let iris = NSBezierPath(ovalIn: NSRect(x: cx - s * 0.075, y: cy - s * 0.075, width: s * 0.15, height: s * 0.15))
    NSColor.white.setFill(); iris.fill()
    NSGraphicsContext.restoreGraphicsState()
    // slash from top-left to bottom-right (same direction as the menu-bar glyph): a gap, then the stroke
    let slash = NSBezierPath()
    slash.move(to: NSPoint(x: cx - s * 0.29, y: cy + s * 0.29)); slash.line(to: NSPoint(x: cx + s * 0.29, y: cy - s * 0.29))
    slash.lineCapStyle = .round
    slash.lineWidth = stroke * 2.4; NSColor(calibratedRed: 0.19, green: 0.24, blue: 0.38, alpha: 1).setStroke(); slash.stroke()
    NSGraphicsContext.saveGraphicsState(); glyphShadow(s).set()
    slash.lineWidth = stroke; NSColor.white.setStroke(); slash.stroke()
    NSGraphicsContext.restoreGraphicsState()
}

// B: a quiet grid of tiles, one with its name showing.
func drawB(_ s: CGFloat) {
    background(s, top: NSColor(calibratedRed: 0.30, green: 0.36, blue: 0.52, alpha: 1), bottom: NSColor(calibratedRed: 0.12, green: 0.15, blue: 0.27, alpha: 1))
    let tile = s * 0.17, gap = s * 0.075
    let gridW = 3 * tile + 2 * gap
    let x0 = (s - gridW) / 2, y0 = s * 0.5 + (gridW / 2) - tile   // top row y (unflipped: y grows upward)
    for row in 0..<3 {
        for col in 0..<3 {
            let x = x0 + CGFloat(col) * (tile + gap)
            let y = y0 - CGFloat(row) * (tile + gap) - (row == 2 ? 0 : 0)
            let hot = row == 1 && col == 1
            let r = NSRect(x: x, y: y, width: tile, height: tile)
            NSGraphicsContext.saveGraphicsState(); glyphShadow(s).set()
            let p = NSBezierPath(roundedRect: r, xRadius: tile * 0.26, yRadius: tile * 0.26)
            if hot {
                NSGradient(starting: .white, ending: NSColor(calibratedWhite: 0.9, alpha: 1))!.draw(in: p, angle: -90)
            } else {
                NSColor.white.withAlphaComponent(0.55).setFill(); p.fill()
            }
            NSGraphicsContext.restoreGraphicsState()
            // name: a pill under the hot tile; a faint short line under the others
            let pillH = tile * 0.24
            if hot {
                let pill = NSRect(x: x - tile * 0.28, y: y - pillH - tile * 0.16, width: tile * 1.56, height: pillH)
                NSGraphicsContext.saveGraphicsState(); glyphShadow(s).set()
                NSColor(calibratedRed: 1.0, green: 0.80, blue: 0.30, alpha: 1).setFill()
                NSBezierPath(roundedRect: pill, xRadius: pillH / 2, yRadius: pillH / 2).fill()
                NSGraphicsContext.restoreGraphicsState()
            } else {
                let line = NSRect(x: x + tile * 0.15, y: y - pillH * 0.7 - tile * 0.16, width: tile * 0.7, height: pillH * 0.45)
                NSColor.white.withAlphaComponent(0.16).setFill()
                NSBezierPath(roundedRect: line, xRadius: line.height / 2, yRadius: line.height / 2).fill()
            }
        }
    }
}

// C: one tile, its name fading away.
func drawC(_ s: CGFloat) {
    background(s, top: NSColor(calibratedRed: 0.20, green: 0.66, blue: 0.86, alpha: 1), bottom: NSColor(calibratedRed: 0.08, green: 0.30, blue: 0.55, alpha: 1))
    let tile = s * 0.40
    let r = NSRect(x: (s - tile) / 2, y: s * 0.40, width: tile, height: tile)
    NSGraphicsContext.saveGraphicsState(); glyphShadow(s).set()
    let p = NSBezierPath(roundedRect: r, xRadius: tile * 0.24, yRadius: tile * 0.24)
    NSGradient(starting: .white, ending: NSColor(calibratedWhite: 0.88, alpha: 1))!.draw(in: p, angle: -90)
    NSGraphicsContext.restoreGraphicsState()
    // folder tab hint on the tile
    let tab = NSRect(x: r.minX + tile * 0.16, y: r.maxY - tile * 0.30, width: tile * 0.38, height: tile * 0.10)
    NSColor(calibratedRed: 0.20, green: 0.66, blue: 0.86, alpha: 0.35).setFill()
    NSBezierPath(roundedRect: tab, xRadius: tab.height / 2, yRadius: tab.height / 2).fill()
    // name line fading out to the right
    let line = NSRect(x: s * 0.31, y: s * 0.24, width: s * 0.46, height: s * 0.075)
    let lp = NSBezierPath(roundedRect: line, xRadius: line.height / 2, yRadius: line.height / 2)
    NSGraphicsContext.saveGraphicsState(); glyphShadow(s).set()
    NSGradient(colorsAndLocations: (NSColor.white, 0), (NSColor.white, 0.35), (NSColor.white.withAlphaComponent(0.0), 1))!.draw(in: lp, angle: 0)
    NSGraphicsContext.restoreGraphicsState()
}

func render(_ variant: String, _ px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    switch variant { case "A": drawA(CGFloat(px)); case "B": drawB(CGFloat(px)); default: drawC(CGFloat(px)) }
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func png(_ rep: NSBitmapImageRep, _ path: String) { try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path)) }

let args = CommandLine.arguments
if args[1] == "sheet" {
    // three variants at 256 px on a light strip and at 64 px on a dark "Dock" strip
    let W = 3 * 300 + 60, H = 256 + 60 + 120
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor(calibratedWhite: 0.94, alpha: 1).setFill(); NSRect(x: 0, y: 120, width: W, height: H - 120).fill()
    NSColor(calibratedWhite: 0.16, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: W, height: 120).fill()
    for (i, v) in ["A", "B", "C"].enumerated() {
        let big = render(v, 512); let img = NSImage(size: NSSize(width: 256, height: 256)); img.addRepresentation(big)
        img.draw(in: NSRect(x: 30 + i * 300 + 22, y: 150, width: 256, height: 256))
        (v as NSString).draw(at: NSPoint(x: 30 + i * 300 + 22, y: 410), withAttributes: [.font: NSFont.boldSystemFont(ofSize: 22), .foregroundColor: NSColor.black])
        let small = render(v, 128); let simg = NSImage(size: NSSize(width: 64, height: 64)); simg.addRepresentation(small)
        simg.draw(in: NSRect(x: 30 + i * 300 + 118, y: 28, width: 64, height: 64))
        let tiny = render(v, 64); let timg = NSImage(size: NSSize(width: 32, height: 32)); timg.addRepresentation(tiny)
        timg.draw(in: NSRect(x: 30 + i * 300 + 200, y: 44, width: 32, height: 32))
    }
    NSGraphicsContext.restoreGraphicsState()
    png(rep, args[2])
} else {
    png(render(args[1], Int(args[2])!), args[3])
}

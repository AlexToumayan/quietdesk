import AppKit
// Two windows of our own at the desktop-icon level: B (opaque everywhere) below A (opaque square + alpha patches, transparent elsewhere).
// For each test point, walk the hit-test chain from the top of the screen down and see whether A is skipped (pass-through) or hit.
let screen = NSScreen.screens[0]
let level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)))
final class A: NSView {
    let alphas: [CGFloat] = [1, 4, 16, 64, 128, 200, 250, 255]
    override var isFlipped: Bool { true }
    func rect(_ k: Int) -> NSRect { NSRect(x: 100 + k * 90, y: 300, width: 60, height: 60) }
    let opaqueRect = NSRect(x: 100, y: 450, width: 80, height: 80)
    let clearPt = NSPoint(x: 340, y: 490)
    override func draw(_ d: NSRect) {
        for (k, a) in alphas.enumerated() { NSColor(calibratedWhite: 0, alpha: a / 255.0).setFill(); rect(k).fill() }
        NSColor.systemRed.withAlphaComponent(0.9).setFill(); opaqueRect.fill()
    }
}
final class B: NSView {
    override func draw(_ d: NSRect) { NSColor(calibratedWhite: 0.2, alpha: 1).setFill(); bounds.fill() }
}
let app = NSApplication.shared; app.setActivationPolicy(.accessory)
func makeWindow(_ v: NSView) -> NSWindow {
    let w = NSWindow(contentRect: NSRect(x: screen.frame.minX, y: screen.frame.minY, width: 1000, height: 700), styleMask: .borderless, backing: .buffered, defer: false)
    w.level = level; w.isOpaque = false; w.backgroundColor = .clear; w.hasShadow = false
    w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    v.frame = NSRect(x: 0, y: 0, width: 1000, height: 700); w.contentView = v
    return w
}
let bv = B(frame: .zero), av = A(frame: .zero)
let wb = makeWindow(bv), wa = makeWindow(av)
wb.orderFrontRegardless(); wa.orderFrontRegardless()   // A above B
func chain(_ p: NSPoint) -> [Int] {
    var out: [Int] = []; var below = 0
    for _ in 0..<40 {
        let n = NSWindow.windowNumber(at: p, belowWindowWithWindowNumber: below)
        if n == 0 || out.contains(n) { break }
        out.append(n); below = n
        if n == wb.windowNumber { break }
    }
    return out
}
func describe(_ c: [Int]) -> String {
    c.map { $0 == wa.windowNumber ? "A" : ($0 == wb.windowNumber ? "B" : "other#\($0)") }.joined(separator: " > ")
}
DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
    func sp(_ p: NSPoint) -> NSPoint { wa.convertPoint(toScreen: av.convert(p, to: nil)) }
    print("A=\(wa.windowNumber) B=\(wb.windowNumber)")
    print("opaque red square : \(describe(chain(sp(NSPoint(x: av.opaqueRect.midX, y: av.opaqueRect.midY)))))")
    print("fully transparent : \(describe(chain(sp(av.clearPt))))")
    for (k, a) in av.alphas.enumerated() {
        let r = av.rect(k)
        print("alpha \(Int(a))/255      : \(describe(chain(sp(NSPoint(x: r.midX, y: r.midY)))))")
    }
    app.terminate(nil)
}
app.run()

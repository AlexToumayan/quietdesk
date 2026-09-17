import AppKit
import CoreGraphics

var globalMoved = 0
final class TestView: NSView {
    var entered = 0, exited = 0, moved = 0, downs = 0
    override var isFlipped: Bool { true }
    let square = NSRect(x: 200, y: 500, width: 120, height: 120)
    override func draw(_ dirtyRect: NSRect) {
        NSColor.systemRed.withAlphaComponent(0.9).setFill(); square.fill()
        NSColor.white.set()
        ("QuietDesk test" as NSString).draw(at: NSPoint(x: 205, y: 505), withAttributes: [.foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 12)])
    }
    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways], owner: self))
        addTrackingArea(NSTrackingArea(rect: square, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
        super.updateTrackingAreas()
    }
    override func mouseEntered(with e: NSEvent) { entered += 1 }
    override func mouseExited(with e: NSEvent) { exited += 1 }
    override func mouseMoved(with e: NSEvent) { moved += 1 }
    override func mouseDown(with e: NSEvent) { downs += 1 }
    func snapshot(_ tag: String) { print("[\(tag)] entered=\(entered) exited=\(exited) moved=\(moved) downs=\(downs) globalMoved=\(globalMoved)"); entered=0; exited=0; moved=0; downs=0; globalMoved=0 }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let screen = NSScreen.screens[0]
let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)))
w.isOpaque = false; w.backgroundColor = .clear; w.hasShadow = false
w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
let v = TestView(frame: NSRect(origin: .zero, size: screen.frame.size))
w.contentView = v
w.orderFrontRegardless()
print("our window number:", w.windowNumber, "level:", w.level.rawValue)

func ordering() {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    var seq: [String] = []
    for e in list {
        let layer = e[kCGWindowLayer as String] as? Int ?? 0
        if layer == Int(CGWindowLevelForKey(.desktopIconWindow)) {
            seq.append("\(e[kCGWindowOwnerName as String] ?? "?")#\(e[kCGWindowNumber as String] ?? 0)")
        }
    }
    print("front-to-back at desktopIcon level:", seq.joined(separator: " > "))
}
let insidePt = NSPoint(x: 260, y: screen.frame.height - 560)   // screen coords (bottom-left origin) inside red square
let clearPt  = NSPoint(x: 600, y: screen.frame.height - 560)   // transparent region, no icon there
func hit(_ tag: String) {
    let a = NSWindow.windowNumber(at: insidePt, belowWindowWithWindowNumber: 0)
    let b = NSWindow.windowNumber(at: clearPt, belowWindowWithWindowNumber: 0)
    print("[\(tag)] hit-test inside-square -> window \(a) (ours=\(w.windowNumber)); transparent-region -> window \(b)")
}
let origLoc = CGEvent(source: nil)?.location ?? CGPoint(x: 800, y: 600)
func warp(_ p: CGPoint) { CGWarpMouseCursorPosition(p) }
let sqCG = CGPoint(x: 260, y: 560), clearCG = CGPoint(x: 600, y: 560)

_ = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { _ in globalMoved += 1 }

func after(_ s: Double, _ f: @escaping () -> Void) { DispatchQueue.main.asyncAfter(deadline: .now() + s, execute: f) }
after(0.3) { ordering(); hit("phase1 normal") }
after(1.0) { warp(sqCG) }; after(1.5) { warp(clearCG) }; after(2.0) { warp(sqCG) }; after(2.5) { warp(origLoc) }
after(3.0) { v.snapshot("phase1 warp-only"); print("now move the mouse over the red square for 5s...") }
after(8.0) { v.snapshot("phase1 user-mouse"); w.ignoresMouseEvents = true; hit("phase2 ignoresMouseEvents"); }
after(8.5) { warp(sqCG) }; after(9.0) { warp(clearCG) }; after(9.5) { warp(sqCG) }; after(10.0) { warp(origLoc) }
after(10.5) { v.snapshot("phase2 warp-only"); print("keep moving the mouse over the red square for 5s...") }
after(15.5) { v.snapshot("phase2 user-mouse"); w.ignoresMouseEvents = false; w.order(.above, relativeTo: 61); }
after(16.0) { ordering(); hit("phase3 after order(.above, relativeTo: Finder#61)"); app.terminate(nil) }
app.run()

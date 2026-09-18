import Cocoa
// Experiment: which notifications and window changes accompany Show Desktop starting and ending?
typealias Fn = @convention(c) (CFString, UnsafeMutableRawPointer?) -> Void
let handle = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_LAZY)
let send = unsafeBitCast(dlsym(handle, "CoreDockSendNotification")!, to: Fn.self)
let t0 = Date()
func stamp() -> String { String(format: "%5.2f", Date().timeIntervalSince(t0)) }
DistributedNotificationCenter.default().addObserver(forName: nil, object: nil, queue: .main) { n in
    let name = n.name.rawValue
    if name.contains("MenuBar") || name.contains("AppleInterface") { return }
    print("\(stamp()) DIST \(name) obj=\(n.object ?? "-")")
}
NSWorkspace.shared.notificationCenter.addObserver(forName: nil, object: nil, queue: .main) { n in
    print("\(stamp()) WS   \(n.name.rawValue)")
}
func windows(_ label: String) {
    let desktopIcon = Int(CGWindowLevelForKey(.desktopIconWindow)), desktop = Int(CGWindowLevelForKey(.desktopWindow))
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
    print("\(stamp()) WINDOWS \(label)")
    for w in list {
        let owner = w[kCGWindowOwnerName as String] as? String ?? "?"
        let layer = w[kCGWindowLayer as String] as? Int ?? 0
        guard ["Dock", "WindowManager", "Finder", "Window Server"].contains(owner), layer < 25 else { continue }
        let b = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
        let rel = layer - desktopIcon
        print("        \(owner) #\(w[kCGWindowNumber as String] ?? 0) layer=\(layer) (icon\(rel >= 0 ? "+" : "")\(rel), desktop=\(desktop)) \(b["X"] ?? 0),\(b["Y"] ?? 0) \(b["Width"] ?? 0)x\(b["Height"] ?? 0) alpha=\(w[kCGWindowAlpha as String] ?? 1)")
    }
}
func revealed() -> Bool {
    let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
    return list.contains { w in
        guard (w[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == dock, let layer = w[kCGWindowLayer as String] as? Int else { return false }
        return layer > 0 && layer < Int(CGWindowLevelForKey(.dockWindow))
    }
}
// The entry point is a TOGGLE, so the script reads the state first and always sends an even
// number of toggles from a normal desktop: it leaves the desktop as it found it.
var steps: [(Double, () -> Void)] = []
var t = 0.5
if revealed() {
    steps.append((t, { print("\(stamp()) >>> toggle (the desktop was already revealed: ending that first)"); send("com.apple.showdesktop.awake" as CFString, nil) })); t += 2.5
}
steps.append((t, { windows("normal") })); t += 0.5
steps.append((t, { print("\(stamp()) >>> toggle (starts a reveal)"); send("com.apple.showdesktop.awake" as CFString, nil) })); t += 2.0
steps.append((t, { windows("revealed") })); t += 0.5
steps.append((t, { print("\(stamp()) >>> toggle (ends the reveal)"); send("com.apple.showdesktop.awake" as CFString, nil) })); t += 2.0
steps.append((t, { windows("normal again"); exit(0) }))
for (delay, body) in steps { DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: body) }
RunLoop.main.run()

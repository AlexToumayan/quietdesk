import Cocoa
import notify
// Experiment: does a desktop-level panel (like QuietDesk's shield) get any event when Show Desktop starts or ends?
typealias Fn = @convention(c) (CFString, UnsafeMutableRawPointer?) -> Void
let send = unsafeBitCast(dlsym(dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_LAZY), "CoreDockSendNotification")!, to: Fn.self)
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let t0 = Date()
func stamp() -> String { String(format: "%5.2f", Date().timeIntervalSince(t0)) }
let screen = NSScreen.screens[0]
let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
panel.isFloatingPanel = false
panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
panel.orderFrontRegardless()
let nc = NotificationCenter.default
for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didChangeScreenNotification, NSWindow.didExposeNotification,
             NSWindow.didMoveNotification, NSWindow.didResizeNotification, NSWindow.didChangeBackingPropertiesNotification,
             NSApplication.didChangeOcclusionStateNotification, NSApplication.didChangeScreenParametersNotification] {
    nc.addObserver(forName: name, object: nil, queue: .main) { n in
        print("\(stamp()) \(n.name.rawValue) visible=\(panel.occlusionState.contains(.visible)) frame=\(Int(panel.frame.minX)),\(Int(panel.frame.minY))")
    }
}
var darwinTokens: [Int32] = []
for name in ["com.apple.showdesktop.awake", "com.apple.expose.awake", "com.apple.expose.front.awake", "com.apple.dock.showdesktop", "com.apple.WindowManager.showDesktop", "com.apple.WindowManager.revealDesktop", "com.apple.dock.exposestate"] {
    var token: Int32 = 0
    notify_register_dispatch(name, &token, DispatchQueue.main) { _ in print("\(stamp()) DARWIN \(name)") }
    darwinTokens.append(token)
}
func dockOverlay() -> Bool {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
    return list.contains { ($0[kCGWindowOwnerName as String] as? String) == "Dock" && ($0[kCGWindowLayer as String] as? Int) == 18 }
}
func onScreen() -> Bool {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
    return list.contains { ($0[kCGWindowNumber as String] as? Int) == panel.windowNumber }
}
print("\(stamp()) start: dockOverlay=\(dockOverlay()) panelOnScreen=\(onScreen())")
DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { print("\(stamp()) >>> reveal"); send("com.apple.showdesktop.awake" as CFString, nil) }
DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { print("\(stamp()) revealed: dockOverlay=\(dockOverlay()) panelOnScreen=\(onScreen()) visible=\(panel.occlusionState.contains(.visible))") }
DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { print("\(stamp()) >>> end reveal"); send("com.apple.showdesktop.awake" as CFString, nil) }
DispatchQueue.main.asyncAfter(deadline: .now() + 5.5) { print("\(stamp()) normal: dockOverlay=\(dockOverlay()) panelOnScreen=\(onScreen())"); exit(0) }
app.run()

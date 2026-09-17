import AppKit
import ApplicationServices
import CoreGraphics

// 1. Permissions we can preflight WITHOUT prompting
print("AXIsProcessTrusted:", AXIsProcessTrusted())
print("CGPreflightScreenCaptureAccess:", CGPreflightScreenCaptureAccess())

// Apple Events automation permission for Finder (no prompt: askUserIfNeeded=false)
if let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first {
    var pid = finder.processIdentifier
    let target = NSAppleEventDescriptor(descriptorType: typeKernelProcessID, bytes: &pid, length: MemoryLayout<pid_t>.size)!
    let status = AEDeterminePermissionToAutomateTarget(target.aeDesc!, typeWildCard, typeWildCard, false)
    print("AEDeterminePermissionToAutomateTarget(Finder) status:", status, "(0=allowed, -1743=denied, -1744=would prompt, -600=procNotFound)")
} else {
    print("Finder not running?")
}

// 2. Displays
for (i, s) in NSScreen.screens.enumerated() {
    print("Screen \(i): frame=\(s.frame) visible=\(s.visibleFrame) scale=\(s.backingScaleFactor) name=\(s.localizedName)")
}

// 3. Window levels
print("kCGDesktopWindowLevel:", CGWindowLevelForKey(.desktopWindow))
print("kCGDesktopIconWindowLevel:", CGWindowLevelForKey(.desktopIconWindow))
print("kCGNormalWindowLevel:", CGWindowLevelForKey(.normalWindow))

// 4. Window list: what lives at/below desktop icon level right now (no screen recording needed for bounds/level/owner)
let opts: CGWindowListOption = [.optionOnScreenOnly]
if let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] {
    let iconLevel = Int(CGWindowLevelForKey(.desktopIconWindow))
    for w in list {
        let layer = w[kCGWindowLayer as String] as? Int ?? 0
        if layer <= iconLevel + 5 {
            print("LOW WINDOW owner=\(w[kCGWindowOwnerName as String] ?? "?") layer=\(layer) bounds=\(w[kCGWindowBounds as String] ?? "?") alpha=\(w[kCGWindowAlpha as String] ?? "?") name=\(w[kCGWindowName as String] ?? "<no name (needs screen recording)>") num=\(w[kCGWindowNumber as String] ?? "?")")
        }
    }
}

import AppKit

/// macOS's "reveal desktop": click the wallpaper, F11, the spread gesture or a hot corner, and
/// every window slides aside. Three things measured on macOS 26.6 (FEASIBILITY E14) shape this:
///
/// 1. For as long as the desktop is revealed, the system re-shows Finder's hidden desktop
///    items, however the reveal was started. QuietDesk therefore steps aside for its duration,
///    which is also what macOS does for anyone who hides desktop items.
/// 2. Nothing announces the start or the end of a reveal: no AppKit, workspace, distributed or
///    Darwin notification, and no occlusion change on a desktop-level window. The only
///    observable is the Dock's full-screen window above the normal window levels, so the state
///    is read from the window list (about 1 ms).
/// 3. The old "Mission Control 1" command line no longer does anything; the Dock's own
///    notification entry point does.
enum DesktopReveal {
    private static let windowManager = "com.apple.WindowManager" as CFString

    /// System Settings › Desktop & Dock › "Click wallpaper to reveal desktop": Always (the
    /// default when the key is absent), or Only in Stage Manager.
    static var clickRevealsDesktop: Bool {
        CFPreferencesAppSynchronize(windowManager)
        func flag(_ key: String) -> Bool? {
            guard let v = CFPreferencesCopyAppValue(key as CFString, windowManager) else { return nil }
            return (v as? Bool) ?? (v as? NSNumber)?.boolValue
        }
        return (flag("EnableStandardClickToShowDesktop") ?? true) || (flag("GloballyEnabled") ?? false)
    }

    /// Asks the Dock to toggle Show Desktop through the entry point its own hot key uses.
    /// NOT PUBLIC API: the symbol is looked up at run time, and if a future macOS drops it this
    /// returns false and a wallpaper click just deselects, as it did before.
    @discardableResult
    static func toggle() -> Bool {
        typealias Send = @convention(c) (CFString, UnsafeMutableRawPointer?) -> Void
        guard let handle = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_LAZY),
              let symbol = dlsym(handle, "CoreDockSendNotification") else { return false }
        unsafeBitCast(symbol, to: Send.self)("com.apple.showdesktop.awake" as CFString, nil)
        return true
    }

    /// The Dock's process id. The window list's owner NAME is localised ("程序坞" in Chinese), so
    /// the Dock is recognised by process; looked up again whenever that process has gone (a Dock restart).
    private static var dockPID: pid_t?
    private static func resolveDock() -> pid_t? {
        dockPID = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier
        return dockPID
    }

    /// True while the desktop is revealed: the Dock then owns a screen-sized window between the
    /// normal and the Dock's own level (its bar and the wallpaper windows are outside that range).
    static var isRevealed: Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return false }
        func owner(_ w: [String: Any]) -> pid_t? { (w[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value }
        var dock = dockPID ?? resolveDock()
        // The Dock always owns on-screen windows (the wallpaper); none with this pid means it restarted.
        if let d = dock, !list.contains(where: { owner($0) == d }) { dock = resolveDock() }
        guard let dock else { return false }
        let dockLevel = Int(CGWindowLevelForKey(.dockWindow))
        let screens = NSScreen.screens.map { $0.frame.size }
        return list.contains { w in
            guard owner(w) == dock,
                  let layer = w[kCGWindowLayer as String] as? Int, layer > 0, layer < dockLevel,
                  let b = w[kCGWindowBounds as String] as? [String: Any],
                  let width = (b["Width"] as? NSNumber)?.doubleValue, let height = (b["Height"] as? NSNumber)?.doubleValue else { return false }
            return screens.contains { abs($0.width - width) < 2 && abs($0.height - height) < 2 }
        }
    }
}

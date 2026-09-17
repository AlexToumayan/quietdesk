import AppKit

/// Opt-in event trace for bug reports. Off by default and then costs nothing: every call site
/// checks one Bool. Enabled with `--debug-log` or `defaults write dev.quietdesk.QuietDesk
/// debugLog -bool YES`; lines go to ~/Library/Logs/QuietDesk/debug.log (never anywhere else).
enum DebugLog {
    static let enabled: Bool = CommandLine.arguments.contains("--debug-log") || Settings.defaults.bool(forKey: "debugLog")
    static let url: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/QuietDesk/debug.log")
    private static let queue = DispatchQueue(label: "dev.quietdesk.debuglog")
    private static let stamp: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"; return f
    }()

    static func log(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        let line = "\(stamp.string(from: Date())) \(message())\n"
        queue.async {
            let fm = FileManager.default
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
            if let h = try? FileHandle(forWritingTo: url) {
                h.seekToEndOfFile()
                h.write(line.data(using: .utf8) ?? Data())
                try? h.close()
            }
        }
    }

    /// Front-to-back order of the overlay windows plus whatever else sits at the desktop-icon
    /// levels (WindowManager's click-catcher, Finder's desktop), so a bug report shows who was
    /// on top when a click went astray.
    static func windowOrder(icons: [NSWindow], shields: [NSWindow]) -> String {
        let desktopIcon = Int(CGWindowLevelForKey(.desktopIconWindow))
        let list = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
        var out: [String] = []
        for e in list {
            guard let n = e[kCGWindowNumber as String] as? Int, let layer = e[kCGWindowLayer as String] as? Int else { continue }
            if icons.contains(where: { $0.windowNumber == n }) { out.append("icons#\(n)@\(layer - desktopIcon)") }
            else if shields.contains(where: { $0.windowNumber == n }) { out.append("shield#\(n)@\(layer - desktopIcon)") }
            else if layer >= desktopIcon - 1 && layer <= desktopIcon + 4 {
                out.append("\(e[kCGWindowOwnerName as String] as? String ?? "?")#\(n)@\(layer - desktopIcon)")
            }
        }
        return out.joined(separator: " > ")
    }

    static func describe(_ event: NSEvent) -> String {
        var mods: [String] = []
        if event.modifierFlags.contains(.command) { mods.append("cmd") }
        if event.modifierFlags.contains(.shift) { mods.append("shift") }
        if event.modifierFlags.contains(.option) { mods.append("opt") }
        if event.modifierFlags.contains(.control) { mods.append("ctrl") }
        return "clicks=\(event.clickCount) mods=[\(mods.joined(separator: ","))] window=\(event.windowNumber)"
    }
}

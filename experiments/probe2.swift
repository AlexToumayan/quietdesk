import AppKit
import CoreGraphics
// All windows (on and off screen) owned by Finder, plus anything below normal level
let opts: CGWindowListOption = [.optionAll]
if let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] {
    for w in list {
        let owner = w[kCGWindowOwnerName as String] as? String ?? "?"
        let layer = w[kCGWindowLayer as String] as? Int ?? 0
        let onscreen = w[kCGWindowIsOnscreen as String] as? Bool ?? false
        if owner == "Finder" || layer < 0 {
            print("owner=\(owner) layer=\(layer) onscreen=\(onscreen) bounds=\((w[kCGWindowBounds as String] as? [String: Any]).map { "\($0["X"]!),\($0["Y"]!) \($0["Width"]!)x\($0["Height"]!)" } ?? "?") alpha=\(w[kCGWindowAlpha as String] ?? "?") pid=\(w[kCGWindowOwnerPID as String] ?? "?") num=\(w[kCGWindowNumber as String] ?? "?")")
        }
    }
}

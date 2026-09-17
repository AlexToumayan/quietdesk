import AppKit
let iconLevel = Int(CGWindowLevelForKey(.desktopIconWindow))
for e in (CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]]) ?? [] {
    let layer = e[kCGWindowLayer as String] as? Int ?? 0
    let owner = e[kCGWindowOwnerName as String] as? String ?? "?"
    guard layer < 0 || owner == "Finder" || owner == "WindowManager" || owner == "Dock" else { continue }
    let b = e[kCGWindowBounds as String] as? [String: Any] ?? [:]
    print("owner=\(owner) layer=\(layer) onscreen=\(e[kCGWindowIsOnscreen as String] as? Bool ?? false) bounds=\(b["X"] ?? 0),\(b["Y"] ?? 0) \(b["Width"] ?? 0)x\(b["Height"] ?? 0) alpha=\(e[kCGWindowAlpha as String] ?? 0) num=\(e[kCGWindowNumber as String] ?? 0)")
}

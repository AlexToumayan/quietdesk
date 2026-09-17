import Foundation

/// Finder's desktop view options, read (never written) from the `com.apple.finder`
/// preference domain, key `DesktopViewSettings`. These keys are UNDOCUMENTED; they are the
/// same values Finder shows in View > Show View Options for the desktop.
struct FinderDesktopPrefs {
    enum ArrangeBy: String {
        case none, name, kind, dateModified, dateCreated, dateAdded, dateLastOpened, size, tags
        case grid   // "Snap to Grid": manual positions, snapped
    }

    var iconSize: CGFloat = 64
    var textSize: CGFloat = 12
    var gridSpacing: CGFloat = 54
    var labelOnBottom = true
    var showIconPreview = true
    var arrangeBy: ArrangeBy = .none
    /// "None" or e.g. "Date Added". Anything other than "None" means Desktop Stacks are on.
    var groupBy: String = "None"

    var showInternalDisks = false
    var showExternalDisks = true
    var showRemovableMedia = true
    var showServers = false

    var stacksEnabled: Bool { !groupBy.isEmpty && groupBy != "None" }

    static func load() -> FinderDesktopPrefs {
        var p = FinderDesktopPrefs()
        let domain = "com.apple.finder" as CFString
        if let dvs = CFPreferencesCopyAppValue("DesktopViewSettings" as CFString, domain) as? [String: Any] {
            if let g = dvs["GroupBy"] as? String { p.groupBy = g }
            if let ivs = dvs["IconViewSettings"] as? [String: Any] {
                if let v = ivs["iconSize"] as? NSNumber { p.iconSize = CGFloat(v.doubleValue) }
                if let v = ivs["textSize"] as? NSNumber { p.textSize = CGFloat(v.doubleValue) }
                if let v = ivs["gridSpacing"] as? NSNumber { p.gridSpacing = CGFloat(v.doubleValue) }
                if let v = ivs["labelOnBottom"] as? NSNumber { p.labelOnBottom = v.boolValue }
                if let v = ivs["showIconPreview"] as? NSNumber { p.showIconPreview = v.boolValue }
                if let a = ivs["arrangeBy"] as? String, let e = ArrangeBy(rawValue: a) { p.arrangeBy = e }
            }
        }
        func flag(_ key: String, _ fallback: Bool) -> Bool {
            (CFPreferencesCopyAppValue(key as CFString, domain) as? NSNumber)?.boolValue ?? fallback
        }
        p.showInternalDisks = flag("ShowHardDrivesOnDesktop", false)
        p.showExternalDisks = flag("ShowExternalHardDrivesOnDesktop", true)
        p.showRemovableMedia = flag("ShowRemovableMediaOnDesktop", true)
        p.showServers = flag("ShowMountedServersOnDesktop", false)
        return p
    }
}

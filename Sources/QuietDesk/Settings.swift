import Foundation

enum LabelMode: String, CaseIterable {
    case always, hover, hidden

    var title: String {
        switch self {
        case .always: return "Always Visible"
        case .hover: return "On Hover"
        case .hidden: return "Hidden"
        }
    }
}

/// How the desktop is ordered. `.finder` follows Finder's own desktop setting.
enum SortKey: String, CaseIterable {
    case finder, none, name, kind, dateAdded, dateModified, dateCreated, dateLastOpened, size, tags

    var title: String {
        switch self {
        case .finder: return "Finder's Setting"
        case .none: return "None (Finder Positions)"
        case .name: return "Name"
        case .kind: return "Kind"
        case .dateAdded: return "Date Added"
        case .dateModified: return "Date Modified"
        case .dateCreated: return "Date Created"
        case .dateLastOpened: return "Date Last Opened"
        case .size: return "Size"
        case .tags: return "Tags"
        }
    }

    var arrangeBy: FinderDesktopPrefs.ArrangeBy? {
        switch self {
        case .finder: return nil
        case .none: return .none
        case .name: return .name
        case .kind: return .kind
        case .dateAdded: return .dateAdded
        case .dateModified: return .dateModified
        case .dateCreated: return .dateCreated
        case .dateLastOpened: return .dateLastOpened
        case .size: return .size
        case .tags: return .tags
        }
    }
}

/// Desktop Stacks grouping. `.finder` follows Finder's setting; `.off` disables Stacks.
enum StacksMode: String, CaseIterable {
    case finder, off, kind, dateAdded, dateModified, dateCreated, dateLastOpened, tags

    var title: String {
        switch self {
        case .finder: return "Finder's Setting"
        case .off: return "Off"
        case .kind: return "Group by Kind"
        case .dateAdded: return "Group by Date Added"
        case .dateModified: return "Group by Date Modified"
        case .dateCreated: return "Group by Date Created"
        case .dateLastOpened: return "Group by Date Last Opened"
        case .tags: return "Group by Tags"
        }
    }

    /// Finder's GroupBy string, or nil to follow Finder.
    var groupBy: String? {
        switch self {
        case .finder: return nil
        case .off: return "None"
        case .kind: return "Kind"
        case .dateAdded: return "Date Added"
        case .dateModified: return "Date Modified"
        case .dateCreated: return "Date Created"
        case .dateLastOpened: return "Date Last Opened"
        case .tags: return "Tags"
        }
    }
}

/// The desktop's View Options (Finder's vocabulary). QuietDesk keeps its own copy so the grid
/// can be adjusted live without touching Finder's settings; the defaults are imported from Finder.
struct ViewOptions: Equatable {
    var iconSize: CGFloat
    var gridSpacing: CGFloat      // Finder's scale, 1...100
    var textSize: CGFloat
    var labelOnBottom: Bool
    var showItemInfo: Bool
    var showIconPreview: Bool
    /// Cloud glyph on iCloud items (Finder shows one; at tight spacings some people prefer none).
    var showCloudStatus: Bool = true
    /// On Hover: how far around the pointed-at item names are revealed (0 = just that item,
    /// 1 = its neighbours too, 2 = a wider area).
    var hoverReveal: Int = 0

    static let iconSizes: [CGFloat] = [16, 32, 36, 48, 64, 72, 96, 128]
    static let textSizes: [CGFloat] = [10, 11, 12, 13, 14, 15, 16]

    static func from(finder p: FinderDesktopPrefs) -> ViewOptions {
        ViewOptions(iconSize: p.iconSize, gridSpacing: p.gridSpacing, textSize: p.textSize,
                    labelOnBottom: p.labelOnBottom, showItemInfo: p.showItemInfo, showIconPreview: p.showIconPreview)
    }

    var dictionary: [String: Any] {
        ["iconSize": iconSize, "gridSpacing": gridSpacing, "textSize": textSize,
         "labelOnBottom": labelOnBottom, "showItemInfo": showItemInfo, "showIconPreview": showIconPreview,
         "showCloudStatus": showCloudStatus, "hoverReveal": hoverReveal]
    }

    init(iconSize: CGFloat, gridSpacing: CGFloat, textSize: CGFloat, labelOnBottom: Bool, showItemInfo: Bool, showIconPreview: Bool) {
        self.iconSize = iconSize; self.gridSpacing = gridSpacing; self.textSize = textSize
        self.labelOnBottom = labelOnBottom; self.showItemInfo = showItemInfo; self.showIconPreview = showIconPreview
    }

    init?(dictionary d: [String: Any]) {
        guard let i = d["iconSize"] as? Double, let g = d["gridSpacing"] as? Double, let t = d["textSize"] as? Double else { return nil }
        self.init(iconSize: i, gridSpacing: g, textSize: t,
                  labelOnBottom: d["labelOnBottom"] as? Bool ?? true, showItemInfo: d["showItemInfo"] as? Bool ?? false,
                  showIconPreview: d["showIconPreview"] as? Bool ?? true)
        showCloudStatus = d["showCloudStatus"] as? Bool ?? true
        hoverReveal = max(0, min(2, d["hoverReveal"] as? Int ?? 0))
    }
}

/// Plain UserDefaults persistence for the user-facing controls.
final class Settings {
    static let shared = Settings()
    /// One preferences domain for the bundle and the bare developer executable.
    static let defaults = UserDefaults(suiteName: "dev.quietdesk.QuietDesk") ?? .standard
    private let defaults = Settings.defaults
    private init() {}

    var enabled: Bool {
        get { defaults.object(forKey: "enabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "enabled") }
    }
    var itemsVisible: Bool {
        get { defaults.object(forKey: "itemsVisible") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "itemsVisible") }
    }
    var labelMode: LabelMode {
        get { LabelMode(rawValue: defaults.string(forKey: "labelMode") ?? "") ?? .hover }
        set { defaults.set(newValue.rawValue, forKey: "labelMode") }
    }
    var sortKey: SortKey {
        get { SortKey(rawValue: defaults.string(forKey: "sortKey") ?? "") ?? .finder }
        set { defaults.set(newValue.rawValue, forKey: "sortKey") }
    }
    var stacksMode: StacksMode {
        get { StacksMode(rawValue: defaults.string(forKey: "stacksMode") ?? "") ?? .finder }
        set {
            defaults.set(newValue.rawValue, forKey: "stacksMode")
            if newValue.groupBy != nil, newValue != .off { defaults.set(newValue.rawValue, forKey: "lastStacksGroup") }
        }
    }
    /// The grouping to return to when "Use Stacks" is switched back on.
    var lastStacksGroup: StacksMode {
        StacksMode(rawValue: defaults.string(forKey: "lastStacksGroup") ?? "") ?? .dateAdded
    }
    /// nil means "follow Finder's current View Options".
    var viewOptions: ViewOptions? {
        get { (defaults.dictionary(forKey: "viewOptions")).flatMap(ViewOptions.init(dictionary:)) }
        set { if let v = newValue { defaults.set(v.dictionary, forKey: "viewOptions") } else { defaults.removeObject(forKey: "viewOptions") } }
    }
    func effectiveViewOptions(finder: FinderDesktopPrefs) -> ViewOptions { viewOptions ?? .from(finder: finder) }
    /// Clicking the desktop brings Finder forward (menu bar shows Finder, like the native desktop)
    /// while QuietDesk's panel keeps keyboard focus. Off: QuietDesk itself becomes the active app.
    var activateFinderOnDesktopClick: Bool {
        get { defaults.object(forKey: "activateFinderOnDesktopClick") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "activateFinderOnDesktopClick") }
    }
}

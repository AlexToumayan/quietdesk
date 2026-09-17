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
        set { defaults.set(newValue.rawValue, forKey: "stacksMode") }
    }
    /// Clicking the desktop brings Finder forward (menu bar shows Finder, like the native desktop)
    /// while QuietDesk's panel keeps keyboard focus. Off: QuietDesk itself becomes the active app.
    var activateFinderOnDesktopClick: Bool {
        get { defaults.object(forKey: "activateFinderOnDesktopClick") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "activateFinderOnDesktopClick") }
    }
}

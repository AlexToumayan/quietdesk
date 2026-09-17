import Foundation
import UniformTypeIdentifiers

struct DesktopItem {
    let url: URL
    let name: String          // user-visible name (localizedName)
    let isFolder: Bool        // directory that is not a package
    let isVolume: Bool
    let isPackage: Bool
    let isAlias: Bool
    let dateAdded: Date
    let dateModified: Date
    let dateCreated: Date
    let dateLastOpened: Date
    let size: Int64
    let kind: String
    let contentType: UTType?
    let tags: [String]
    let isUbiquitous: Bool
    /// Set when this item is shown because its Stack is expanded.
    var stackTitle: String? = nil
}

struct StackGroup {
    let title: String
    let items: [DesktopItem]  // sorted like the desktop
    let order: Int            // lower sorts first
}

enum LayoutEntry {
    case item(DesktopItem)
    case stack(StackGroup)

    var displayName: String {
        switch self {
        case .item(let i): return i.name
        case .stack(let s): return s.title
        }
    }
    var url: URL? {
        if case .item(let i) = self { return i.url }
        return nil
    }
    var item: DesktopItem? {
        if case .item(let i) = self { return i }
        return nil
    }
    var stack: StackGroup? {
        if case .stack(let s) = self { return s }
        return nil
    }
    var isStack: Bool { stack != nil }
}

/// A non-recursive snapshot of what Finder would show on the desktop: the top level of
/// ~/Desktop plus mounted volumes that Finder's preferences say to show, ordered the way
/// Finder fills its sorted grid (first entry = top-right cell of the main display).
struct DesktopModel {
    let arrangeBy: FinderDesktopPrefs.ArrangeBy
    let groupBy: String
    let entries: [LayoutEntry]
    let itemCount: Int
    /// True when ~/Desktop could not be listed (typically: Desktop folder access denied).
    let listingFailed: Bool

    var stacksEnabled: Bool { !groupBy.isEmpty && groupBy != "None" }
    /// Manual arrangement: positions come from Finder, not from a sort order.
    var isManual: Bool { arrangeBy == .none || arrangeBy == .grid }

    /// ~/Desktop, or the folder given with `--desktop-dir` (tests run against a fixture folder).
    static let desktopURL: URL = {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--desktop-dir"), i + 1 < args.count {
            return URL(fileURLWithPath: args[i + 1], isDirectory: true).standardizedFileURL
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
    }()

    static func scan(prefs: FinderDesktopPrefs, settings: Settings, expandedStacks: Set<String>, now: Date = Date(), forceArrangeBy: FinderDesktopPrefs.ArrangeBy? = nil) -> DesktopModel {
        let arrangeBy = forceArrangeBy ?? settings.sortKey.arrangeBy ?? prefs.arrangeBy
        let groupBy = settings.stacksMode.groupBy ?? prefs.groupBy
        let (scanned, failed) = scanDesktopFolder()
        var items = scanned
        let volumes = scanVolumes(prefs: prefs)
        items.sort(by: comparator(for: arrangeBy))

        var entries: [LayoutEntry] = volumes.map { .item($0) }
        let stacksOn = !groupBy.isEmpty && groupBy != "None"
        if stacksOn {
            let files = items.filter { !$0.isFolder }
            let folders = items.filter { $0.isFolder }
            for stack in buildStacks(files: files, groupBy: groupBy, now: now) {
                entries.append(.stack(stack))
                if expandedStacks.contains(stack.title) {
                    for var member in stack.items {
                        member.stackTitle = stack.title
                        entries.append(.item(member))
                    }
                }
            }
            entries += folders.map { .item($0) }
        } else {
            entries += items.map { .item($0) }
        }
        return DesktopModel(arrangeBy: arrangeBy, groupBy: groupBy, entries: entries, itemCount: items.count + volumes.count, listingFailed: failed)
    }

    // MARK: - Scanning (reads directory metadata only; never file contents)

    private static let itemKeys: Set<URLResourceKey> = [
        .isDirectoryKey, .isPackageKey, .isHiddenKey, .isAliasFileKey, .localizedNameKey, .addedToDirectoryDateKey,
        .contentModificationDateKey, .creationDateKey, .contentAccessDateKey, .fileSizeKey,
        .localizedTypeDescriptionKey, .contentTypeKey, .tagNamesKey, .isUbiquitousItemKey,
    ]

    private static func scanDesktopFolder() -> ([DesktopItem], failed: Bool) {
        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(at: desktopURL, includingPropertiesForKeys: Array(itemKeys), options: [.skipsHiddenFiles])
        } catch {
            return ([], true)
        }
        var out: [DesktopItem] = []
        for url in urls {
            guard let rv = try? url.resourceValues(forKeys: itemKeys) else { continue }
            if rv.isHidden == true { continue }
            let isPackage = rv.isPackage ?? false
            let isFolder = (rv.isDirectory ?? false) && !isPackage
            let created = rv.creationDate ?? .distantPast
            out.append(DesktopItem(
                url: url,
                name: rv.localizedName ?? url.lastPathComponent,
                isFolder: isFolder, isVolume: false, isPackage: isPackage,
                isAlias: rv.isAliasFile ?? false,
                dateAdded: rv.addedToDirectoryDate ?? created,
                dateModified: rv.contentModificationDate ?? .distantPast,
                dateCreated: created,
                dateLastOpened: rv.contentAccessDate ?? .distantPast,
                size: Int64(rv.fileSize ?? 0),
                kind: rv.localizedTypeDescription ?? "",
                contentType: rv.contentType,
                tags: rv.tagNames ?? [],
                isUbiquitous: rv.isUbiquitousItem ?? false))
        }
        return (out, false)
    }

    private static let volumeKeys: Set<URLResourceKey> = [
        .volumeIsRootFileSystemKey, .volumeIsInternalKey, .volumeIsRemovableKey, .volumeIsEjectableKey,
        .volumeIsLocalKey, .volumeLocalizedNameKey, .volumeIsBrowsableKey, .creationDateKey,
    ]

    private static func scanVolumes(prefs: FinderDesktopPrefs) -> [DesktopItem] {
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Array(volumeKeys), options: [.skipHiddenVolumes]) ?? []
        var out: [DesktopItem] = []
        for url in urls {
            guard let rv = try? url.resourceValues(forKeys: volumeKeys) else { continue }
            if rv.volumeIsBrowsable == false { continue }
            let show: Bool
            if rv.volumeIsRootFileSystem == true {
                show = prefs.showInternalDisks
            } else if rv.volumeIsLocal == false {
                show = prefs.showServers
            } else if (rv.volumeIsRemovable ?? false) || (rv.volumeIsEjectable ?? false) {
                show = prefs.showRemovableMedia
            } else if rv.volumeIsInternal ?? false {
                show = prefs.showInternalDisks
            } else {
                show = prefs.showExternalDisks
            }
            guard show else { continue }
            let date = rv.creationDate ?? .distantPast
            out.append(DesktopItem(url: url, name: rv.volumeLocalizedName ?? url.lastPathComponent,
                                   isFolder: false, isVolume: true, isPackage: false, isAlias: false,
                                   dateAdded: date, dateModified: date, dateCreated: date, dateLastOpened: date,
                                   size: 0, kind: "Volume", contentType: .volume, tags: [], isUbiquitous: false))
        }
        return out.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: - Ordering

    static func comparator(for arrange: FinderDesktopPrefs.ArrangeBy) -> (DesktopItem, DesktopItem) -> Bool {
        let byName: (DesktopItem, DesktopItem) -> Bool = { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        switch arrange {
        case .dateAdded:      return { $0.dateAdded != $1.dateAdded ? $0.dateAdded > $1.dateAdded : byName($0, $1) }
        case .dateModified:   return { $0.dateModified != $1.dateModified ? $0.dateModified > $1.dateModified : byName($0, $1) }
        case .dateCreated:    return { $0.dateCreated != $1.dateCreated ? $0.dateCreated > $1.dateCreated : byName($0, $1) }
        case .dateLastOpened: return { $0.dateLastOpened != $1.dateLastOpened ? $0.dateLastOpened > $1.dateLastOpened : byName($0, $1) }
        case .size:           return { $0.size != $1.size ? $0.size > $1.size : byName($0, $1) }
        case .kind:
            // Finder sorts by the item's Kind string ("Folder", "PDF document", …), then by name.
            return { a, b in
                let ka = a.isFolder ? "Folder" : a.kind, kb = b.isFolder ? "Folder" : b.kind
                return ka != kb ? ka.localizedStandardCompare(kb) == .orderedAscending : byName(a, b)
            }
        case .tags:
            return { a, b in
                let ta = a.tags.first ?? "\u{FFFF}", tb = b.tags.first ?? "\u{FFFF}"
                return ta != tb ? ta.localizedStandardCompare(tb) == .orderedAscending : byName(a, b)
            }
        case .name, .none, .grid: return byName
        }
    }

    /// Finder-like kind categories used by "Sort By Kind" and "Group Stacks by Kind".
    static func kindCategory(_ item: DesktopItem) -> String {
        if item.isVolume { return "Volumes" }
        if item.isFolder { return "Folders" }
        guard let t = item.contentType else { return "Other" }
        if t.conforms(to: .image) { return item.name.hasPrefix("Screenshot") ? "Screenshots" : "Images" }
        if t.conforms(to: .pdf) { return "PDF Documents" }
        if t.conforms(to: .movie) || t.conforms(to: .video) { return "Movies" }
        if t.conforms(to: .audio) { return "Music" }
        if t.conforms(to: .archive) { return "Archives" }
        if t.conforms(to: .application) { return "Applications" }
        if t.conforms(to: .presentation) { return "Presentations" }
        if t.conforms(to: .spreadsheet) { return "Spreadsheets" }
        if t.conforms(to: .text) || t.conforms(to: .compositeContent) || t.conforms(to: .sourceCode) { return "Documents" }
        return "Other"
    }

    // MARK: - Stacks (approximation of Finder's Desktop Stacks grouping)

    static func buildStacks(files: [DesktopItem], groupBy: String, now: Date) -> [StackGroup] {
        var buckets: [String: (order: Int, items: [DesktopItem])] = [:]
        for f in files {
            let (title, order): (String, Int)
            switch groupBy {
            case "Date Added":        (title, order) = dateBucket(f.dateAdded, now: now)
            case "Date Modified":     (title, order) = dateBucket(f.dateModified, now: now)
            case "Date Created":      (title, order) = dateBucket(f.dateCreated, now: now)
            case "Date Last Opened":  (title, order) = dateBucket(f.dateLastOpened, now: now)
            case "Kind":              (title, order) = (kindCategory(f), 0)
            case "Tags":              (title, order) = (f.tags.first ?? "No Tags", f.tags.isEmpty ? 1 : 0)
            default:                  (title, order) = ("Files", 0)
            }
            buckets[title, default: (order, [])].items.append(f)
        }
        return buckets.map { StackGroup(title: $0.key, items: $0.value.items, order: $0.value.order) }
            .sorted { $0.order != $1.order ? $0.order < $1.order : $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// Finder-like date buckets: Today, Yesterday, Previous 7 Days, Previous 30 Days,
    /// months of the current year, the previous year, then "Earlier". (Approximation.)
    static func dateBucket(_ date: Date, now: Date, calendar: Calendar = .current) -> (String, Int) {
        let today = calendar.startOfDay(for: now)
        if date >= today { return ("Today", 0) }
        if let d = calendar.date(byAdding: .day, value: -1, to: today), date >= d { return ("Yesterday", 1) }
        if let d = calendar.date(byAdding: .day, value: -7, to: today), date >= d { return ("Previous 7 Days", 2) }
        if let d = calendar.date(byAdding: .day, value: -30, to: today), date >= d { return ("Previous 30 Days", 3) }
        let y = calendar.component(.year, from: date), m = calendar.component(.month, from: date)
        let thisYear = calendar.component(.year, from: now)
        if y == thisYear { return (calendar.monthSymbols[m - 1], 100 + (12 - m)) }
        if y == thisYear - 1 { return (String(y), 200) }
        return ("Earlier", 300)
    }
}

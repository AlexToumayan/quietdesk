import Foundation

/// The macOS setting  System Settings > Desktop & Dock > Desktop & Stage Manager > Show Items: "On Desktop".
///
/// UNDOCUMENTED MECHANISM. The user-facing switch is backed by the boolean
/// `StandardHideDesktopIcons` in the `com.apple.WindowManager` preference domain (macOS 14+).
/// `true` hides Finder's desktop items. Absent key means "shown". Writing it is what
/// System Settings does; there is no public API. If a future macOS stops honouring it,
/// the user can still flip the switch manually in System Settings.
enum DesktopIconsPreference {
    private static let domain = "com.apple.WindowManager" as CFString
    private static let key = "StandardHideDesktopIcons" as CFString

    /// nil means the key is absent (macOS default: items shown).
    static func read() -> Bool? {
        guard let value = CFPreferencesCopyAppValue(key, domain) else { return nil }
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber { return n.boolValue }
        return nil
    }

    static var itemsHidden: Bool { read() ?? false }

    /// Writes the key; nil removes it. Equivalent to `defaults write` / `defaults delete`.
    static func write(_ value: Bool?) {
        let cf: CFPropertyList? = value.map { ($0 ? kCFBooleanTrue : kCFBooleanFalse) as CFPropertyList }
        CFPreferencesSetAppValue(key, cf, domain)
        CFPreferencesAppSynchronize(domain)
    }
}

/// What the key looked like before QuietDesk touched it.
enum PreviousValue: Equatable {
    case absent
    case value(Bool)
}

/// Durable record of the one system change QuietDesk makes, so it can be undone
/// on the next launch after a crash or force-quit (normal cleanup is not guaranteed to run).
enum RestoreRecord {
    private static let pendingKey = "restore.pending"
    private static let previousKey = "restore.previousValue" // -1 absent, 0 false, 1 true

    static func save(previous: Bool?) {
        let d = Settings.defaults
        d.set(true, forKey: pendingKey)
        d.set(previous == nil ? -1 : (previous! ? 1 : 0), forKey: previousKey)
        d.synchronize()   // flushed to disk BEFORE the system setting is changed
    }

    static func clear() {
        let d = Settings.defaults
        d.removeObject(forKey: pendingKey)
        d.removeObject(forKey: previousKey)
        d.synchronize()
    }

    static func pending() -> PreviousValue? {
        let d = Settings.defaults
        guard d.bool(forKey: pendingKey) else { return nil }
        let v = d.integer(forKey: previousKey)
        return v == -1 ? .absent : .value(v == 1)
    }
}

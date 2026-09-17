import AppKit

// FinderAutomation: in-process Apple events to Finder.
//
// Everything here goes through NSAppleScript inside this process, so macOS attributes the
// request to this app (System Settings > Privacy & Security > Automation > QuietDesk > Finder)
// and no subprocess (osascript, Process) is involved. Completions are delivered on the main
// queue.
//
// Threading. Apple's AppleScript 10.6 release notes state: "OSA and AppleScript are now
// thread-safe: they may be safely called on a non-main thread or from multiple threads without
// any locking in the client code. This also applies to NSAppleScript. [...] AppleScript uses
// locking to ensure that any single connection (a ComponentInstance) will only run on one
// thread at a time. [...] trying to manipulate the same script from multiple threads at once
// may still be subject to race conditions, and is not recommended."
// (developer.apple.com/library/archive/releasenotes/AppleScript/RN-AppleScript/RN-10_6/).
// The older, archived Threading Programming Guide still lists NSAppleScript as main-thread
// only; the release notes are the later statement. This module runs every script on ONE
// serial background queue, one script at a time, never concurrently and never on the main
// thread, because a Finder round trip for ~150 items takes about a second and the first send
// can block on the Automation consent prompt; neither may stall the UI.
//
// Public, documented APIs only: NSAppleScript, NSAppleEventDescriptor, NSRunningApplication,
// AEDeterminePermissionToAutomateTarget (AppleEvents.h, macOS 10.14+), NSApplication
// .yieldActivation(to:) (macOS 14+), and Finder's own scripting dictionary (Finder.sdef:
// item.URL, item.desktop position, item.information window, make new Finder window to).
//
// Nothing here renames, moves or modifies files. Reading `URL` and `desktop position` asks
// Finder for metadata it already holds; it does not touch file contents, so it cannot start an
// iCloud download of a dataless file. No timers, no polling: every Apple event is sent only
// when one of the functions below is called.

/// Outcome of the consent preflight for sending Apple events to Finder.
enum FinderAutomationStatus {
    /// The user has allowed this app to control Finder (or has not been asked and the system
    /// does not require consent for the event class checked).
    case allowed
    /// The user denied the Automation prompt, or the grant was switched off in System Settings.
    case denied
    /// No decision yet: the first script sent to Finder will show the system consent prompt.
    case needsConsent
    /// Finder is not running (the preflight cannot address a non-running application).
    case finderNotRunning
}

enum FinderAutomationError: Error, CustomStringConvertible {
    /// errAEEventNotPermitted (-1743): the user denied the Automation prompt or switched the
    /// grant off. `description` tells the user where to allow it.
    case notPermitted
    /// procNotFound (-600) or Finder not found among running applications.
    case finderNotRunning
    /// Any other AppleScript or Finder error; the payload is Finder's message plus the number.
    case scriptError(String)

    var description: String {
        switch self {
        case .notPermitted:
            let app = FinderAutomation.appName
            return "\(app) is not allowed to control Finder. Allow it in System Settings > "
                + "Privacy & Security > Automation (\(app) > Finder), then try again."
        case .finderNotRunning:
            return "Finder is not running."
        case .scriptError(let message):
            return "Finder reported an error: \(message)"
        }
    }
}

enum FinderAutomation {

    // MARK: Public interface

    /// Preflight with AEDeterminePermissionToAutomateTarget(askUserIfNeeded: false); never
    /// shows the consent prompt. Apple's header says not to call that function on the main
    /// thread (it may block while the user is prompted), so when this is called from the main
    /// thread the check is hopped synchronously onto a private queue; with askUserIfNeeded
    /// false it returns in a few milliseconds (measured). Prefer calling it from a background
    /// thread anyway.
    static func status() -> FinderAutomationStatus {
        if Thread.isMainThread {
            return preflightQueue.sync { determineStatus() }
        }
        return determineStatus()
    }

    /// Reads Finder's desktop icon positions off the main thread; completion on the main
    /// queue.
    ///
    /// One script, three `get` events: `{URL, desktop position, URL} of every item of
    /// desktop`. AppleScript evaluates a property list as one `get` per property, so the URL
    /// list and the position list come from two separate `every item` queries and are paired
    /// by index. Finder does not promise the same order for two queries (observed: the first
    /// two queries on a folder Finder had not listed before came back in different orders),
    /// so the URL list is fetched again after the positions; if the two URL lists differ (or
    /// their lengths differ), the module re-reads with a per-item script whose `{URL,
    /// position}` pairs are built inside Finder, one item at a time (2N events, about four
    /// times slower). Either way the result is never a misaligned pairing.
    ///
    /// Result keys are file URLs (`standardizedFileURL` of the `file:///…` string Finder
    /// returns). Finder gives folders and packages (.app) a trailing slash (`…/Folder/`), plain
    /// files none; that is the same form `FileManager.contentsOfDirectory(at:)` produces, but
    /// compare by `path` if your URLs may differ in that respect. Names are percent-encoded
    /// (`#`, `?`, `%`, `[`, `]`, `;`, spaces and non-ASCII verified) and use the on-disk name
    /// (a name Finder shows with "/" comes back with ":"), so `path` is the real path. Mounted
    /// volumes shown on the desktop are included (`file:///Volumes/Name/`).
    /// Measured: 148 items take about 1.2 s per call on the fast path (the first call also
    /// compiles the script; compiled scripts are cached), about 3 s on the fallback, so call
    /// this on events (a layout change, an enable), never on a timer.
    ///
    /// Values are Finder's points: origin at the top-left of the main display, y down, in
    /// points (not pixels); a display above the main one has negative y. On a sorted desktop
    /// (Sort By other than None) the values are stale, see docs/FEASIBILITY.md E2. Which anchor
    /// the point describes is recorded in the comment on `positionsScriptSource` below.
    static func readDesktopPositions(completion: @escaping (Result<[URL: CGPoint], FinderAutomationError>) -> Void) {
        queue.async {
            let result = readDesktopPositionsSync()
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// Sets one item's desktop position, in the coordinate system `readDesktopPositions`
    /// reports. Only meaningful when Sort By is None; what Finder does with a stored position
    /// on a sorted desktop has not been exercised (this function was compiled and its script
    /// checked, but never run, while the module was written). Coordinates are rounded to whole
    /// points and limited to the 16-bit range of a QuickDraw point (Finder's `point` type); a
    /// non-finite coordinate fails with `.scriptError` before anything is sent.
    static func writeDesktopPosition(_ point: CGPoint, for url: URL, completion: @escaping (FinderAutomationError?) -> Void) {
        guard point.x.isFinite, point.y.isFinite else {
            DispatchQueue.main.async { completion(.scriptError("desktop position (\(point.x), \(point.y)) is not a finite point")) }
            return
        }
        let source = writePositionScriptSource(point, for: url)
        queue.async {
            let error = runScript(source).failure
            DispatchQueue.main.async { completion(error) }
        }
    }

    /// Opens Finder's Get Info window(s) for the given items and brings Finder to the front
    /// (as choosing Get Info on the native desktop would). An empty list completes immediately
    /// with nil.
    static func openInfoWindows(for urls: [URL], completion: @escaping (FinderAutomationError?) -> Void) {
        guard !urls.isEmpty else {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        yieldActivationToFinder()
        let source = infoWindowsScriptSource(for: urls)
        queue.async {
            let error = runScript(source).failure
            DispatchQueue.main.async { completion(error) }
        }
    }

    /// Opens a new Finder window showing the given folder (equivalent of File > New Finder
    /// Window / Cmd-N on the desktop) and brings Finder to the front.
    static func openNewWindow(at folder: URL, completion: @escaping (FinderAutomationError?) -> Void) {
        yieldActivationToFinder()
        let source = newWindowScriptSource(at: folder)
        queue.async {
            let error = runScript(source).failure
            DispatchQueue.main.async { completion(error) }
        }
    }

    // MARK: Script sources (internal so a self-test can check the quoting without sending anything)

    /// Fast path: three `get` events in one script (see `readDesktopPositions`). Finder
    /// answers with a list of three lists, `{URLs, positions, URLs}`; by the time NSAppleScript
    /// hands the result back, each position is a list of two 'long' integers `{x, y}` (the
    /// AppleScript component coerces Finder's typeQDPoint). See `parsePositionsReply`.
    ///
    /// Anchor of the point. Apple does not document which point of the icon `desktop position`
    /// describes. Observed with the harness on macOS 26.6.2 / Finder 26.4 (icon size 36, grid
    /// spacing 26, text size 12; two displays: main 1728x1117 pt with a 33 pt menu bar, and an
    /// external 1920x1080 pt display above it whose top-left corner is (-103, -1080) in Finder's
    /// space). The desktop was sorted (Sort By Date Added), so the values are stale
    /// (docs/FEASIBILITY.md E2): they are wherever Finder last stored each icon, and several
    /// old grids overlap (column pitches of 78 and 122 pt, so items were placed under different
    /// View Options over time). Observed, 148 items:
    ///   main display   125 items, x 15…1685, y 15…1073; the most common column pitch is 78 pt
    ///                  ending at x = 1685; rows at y = 65, 162, 254, 401, 513, 621, 713, 806,
    ///                  898, 990, 1073 (plus rows from the other stale grids)
    ///   display above   23 items, x 35…1264, y -1015…-271 (its top edge is y = -1080, so its
    ///                  first row is 65 pt below the top, like the main display's first row)
    ///   (15, 15) on two items that look never placed (Finder's default for a fresh item?).
    /// The live sorted layout (E7) has its first icon centre at (1677, 60) with an 84x82 pt
    /// pitch, which none of the stale grids match, so a same-anchor comparison with what is on
    /// screen is not possible on this machine. The values are consistent with the icon CENTRE
    /// (the rightmost x = 1685 leaves 43 pt, about half a cell, to the display edge; the lowest
    /// y = 1073 leaves 44 pt to the bottom edge; with a top-left anchor those icons' labels would
    /// run past both edges) but that is inference, not proof. QuietDesk's Layout treats the point
    /// as the icon centre; confirm on a manually arranged desktop (Sort By: None) by dragging one
    /// icon in Finder and reading its position back.
    static let positionsScriptSource =
        "tell application \"Finder\" to get {URL, desktop position, URL} of every item of desktop"

    /// Fallback: one `{URL, desktop position}` pair per item, built inside Finder from the same
    /// item reference, so the pairing cannot be wrong; 2N events (measured 3.1 s for 148
    /// items). Used only when the fast path's two URL lists disagree.
    static let positionsLoopScriptSource = """
        tell application "Finder"
        \tset out to {}
        \trepeat with i in (get every item of desktop)
        \t\tset end of out to {URL of i, desktop position of i}
        \tend repeat
        \treturn out
        end tell
        """

    static func writePositionScriptSource(_ point: CGPoint, for url: URL) -> String {
        let x = quickDrawCoordinate(point.x)
        let y = quickDrawCoordinate(point.y)
        return "tell application \"Finder\" to set desktop position of \(itemReference(url)) to {\(x), \(y)}"
    }

    /// Rounds to a whole point and clamps to the range of a QuickDraw `Point` coordinate
    /// (SInt16), which is what Finder's `point` type carries. A non-finite value (NaN, ±inf)
    /// becomes 0 rather than trapping in `Int(_:)`; `writeDesktopPosition` rejects non-finite
    /// input with an error before calling this.
    static func quickDrawCoordinate(_ value: CGFloat) -> Int {
        guard value.isFinite else { return 0 }
        return Int(min(max(value.rounded(), CGFloat(Int16.min)), CGFloat(Int16.max)))
    }

    static func infoWindowsScriptSource(for urls: [URL]) -> String {
        var lines = ["tell application \"Finder\""]
        for url in urls {
            lines.append("\topen information window of \(itemReference(url))")
        }
        lines.append("\tactivate")
        lines.append("end tell")
        return lines.joined(separator: "\n")
    }

    static func newWindowScriptSource(at folder: URL) -> String {
        return """
        tell application "Finder"
        \tmake new Finder window to \(itemReference(folder))
        \tactivate
        end tell
        """
    }

    /// `(POSIX file "…" as alias)`: AppleScript resolves the path to an alias record inside
    /// this process (metadata only; creating an alias does not read file contents) and Finder
    /// accepts the alias as an item reference. Resolution fails with AppleScript error -1700
    /// ("Can't make … into type alias") if the item does not exist, which `runScript` reports
    /// as `.scriptError`.
    static func itemReference(_ url: URL) -> String {
        return "(POSIX file \(appleScriptStringLiteral(url.path)) as alias)"
    }

    /// AppleScript string literal: backslash and double quote are escaped; CR/LF/TAB use the
    /// escapes AppleScript defines so a file name containing them cannot break the source.
    static func appleScriptStringLiteral(_ string: String) -> String {
        var out = "\""
        out.reserveCapacity(string.utf8.count + 2)
        for scalar in string.unicodeScalars {
            switch scalar {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default: out.unicodeScalars.append(scalar)
            }
        }
        out += "\""
        return out
    }

    // MARK: Internals

    static let finderBundleIdentifier = "com.apple.finder"

    /// Used in the `notPermitted` message; the process name is "QuietDesk" for both the bundle
    /// and the bare executable.
    static var appName: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? ProcessInfo.processInfo.processName
    }

    /// All scripts run here, one at a time, never on the main thread.
    private static let queue = DispatchQueue(label: "dev.quietdesk.FinderAutomation.scripts", qos: .userInitiated)
    /// The preflight has its own queue so a `status()` call from the main thread never waits
    /// behind a running script.
    private static let preflightQueue = DispatchQueue(label: "dev.quietdesk.FinderAutomation.preflight", qos: .userInitiated)

    /// Compiled scripts reused across reads, keyed by source; only the two position scripts
    /// are cached, so this holds at most two entries. Touched only on `queue`, which is what
    /// makes the unsynchronised storage safe. (A box rather than a `static var` so the file
    /// compiles with a Swift 5.9 toolchain, the project's stated minimum, and is a `let` of a
    /// Sendable type under Swift 6 rules.)
    private final class ScriptCache: @unchecked Sendable {
        var scripts: [String: NSAppleScript] = [:]
    }
    private static let scriptCache = ScriptCache()

    private static func fourCharCode(_ s: String) -> FourCharCode {
        var code: FourCharCode = 0
        for byte in s.utf8 { code = (code << 8) | FourCharCode(byte) }
        return code
    }

    private static let typeWildCardCode = fourCharCode("****")   // typeWildCard
    private static let typeAEListCode = fourCharCode("list")     // typeAEList
    private static let typeQDPointCode = fourCharCode("QDpt")    // typeQDPoint
    private static let typeDoubleCode = fourCharCode("doub")     // typeIEEE64BitFloatingPoint

    private static let errAEEventNotPermittedCode = -1743          // errAEEventNotPermitted
    private static let errAEEventWouldRequireUserConsentCode = -1744 // errAEEventWouldRequireUserConsent
    private static let procNotFoundCode = -600                     // procNotFound

    private static func finderRunningApplication() -> NSRunningApplication? {
        // Thread safe per NSRunningApplication.h ("properties are returned atomically").
        NSRunningApplication.runningApplications(withBundleIdentifier: finderBundleIdentifier).first
    }

    private static func determineStatus() -> FinderAutomationStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier: finderBundleIdentifier)
        let status: OSStatus = withExtendedLifetime(target) {
            guard let address = target.aeDesc else { return OSStatus(-50) } // paramErr
            return AEDeterminePermissionToAutomateTarget(address, typeWildCardCode, typeWildCardCode, false)
        }
        switch Int(status) {
        case 0: return .allowed
        case errAEEventNotPermittedCode: return .denied
        case errAEEventWouldRequireUserConsentCode: return .needsConsent
        case procNotFoundCode: return .finderNotRunning
        default:
            // Unexpected code (e.g. paramErr). Report it as denied rather than trigger a send
            // that would prompt; the send functions still map the real error if attempted.
            return .denied
        }
    }

    /// Cooperative activation (macOS 14+): allow Finder to come to the front when the script
    /// says `activate`. Only meaningful when this app is the active one (the overlay is active
    /// after a desktop click) and only from the main thread; otherwise it is a harmless no-op
    /// (NSApp is nil in a bare command-line harness).
    private static func yieldActivationToFinder() {
        let yield = {
            // Runs on the main thread only (checked at runtime by assumeIsolated).
            MainActor.assumeIsolated {
                guard let app = NSApp, let finder = finderRunningApplication() else { return }
                app.yieldActivation(to: finder)
            }
        }
        if Thread.isMainThread { yield() } else { DispatchQueue.main.async(execute: yield) }
    }

    /// Runs a script on the calling (background) thread and maps the error dictionary.
    private static func runScript(_ source: String, cached: Bool = false) -> Result<NSAppleEventDescriptor, FinderAutomationError> {
        dispatchPrecondition(condition: .onQueue(queue))
        // `tell application "Finder"` would launch Finder if it were not running; refuse instead.
        guard finderRunningApplication() != nil else { return .failure(.finderNotRunning) }

        let script: NSAppleScript
        if cached, let compiled = scriptCache.scripts[source] {
            script = compiled
        } else {
            guard let fresh = NSAppleScript(source: source) else {
                return .failure(.scriptError("could not create the script"))
            }
            var compileError: NSDictionary?
            guard fresh.compileAndReturnError(&compileError) else {
                return .failure(mapError(compileError))
            }
            if cached { scriptCache.scripts[source] = fresh }
            script = fresh
        }

        var executeError: NSDictionary?
        // Declared non-null but documented to return nil on failure (verified: nil only
        // together with an error dictionary; a script without a result gives a 'null'
        // descriptor). Bind it as optional so a nil is never carried around as a reference.
        let result: NSAppleEventDescriptor? = script.executeAndReturnError(&executeError)
        if let executeError { return .failure(mapError(executeError)) }
        return .success(result ?? NSAppleEventDescriptor.null())
    }

    private static func mapError(_ info: NSDictionary?) -> FinderAutomationError {
        let number = (info?[NSAppleScript.errorNumber] as? NSNumber)?.intValue
        let message = (info?[NSAppleScript.errorMessage] as? String)
            ?? (info?[NSAppleScript.errorBriefMessage] as? String)
            ?? "unknown error"
        switch number {
        case errAEEventNotPermittedCode?: return .notPermitted
        case procNotFoundCode?: return .finderNotRunning
        case let code?: return .scriptError("\(message) (\(code))")
        case nil: return .scriptError(message)
        }
    }

    private static func readDesktopPositionsSync() -> Result<[URL: CGPoint], FinderAutomationError> {
        switch runScript(positionsScriptSource, cached: true) {
        case .failure(let error):
            return .failure(error)
        case .success(let descriptor):
            switch parsePositionsReply(descriptor) {
            case .positions(let positions):
                return .success(positions)
            case .unexpectedShape:
                return .failure(.scriptError("unexpected reply shape (\(describe(descriptor)))"))
            case .orderChanged:
                // Finder's item order (or item set) changed between the get events; pair inside
                // Finder instead.
                switch runScript(positionsLoopScriptSource, cached: true) {
                case .failure(let error):
                    return .failure(error)
                case .success(let loopDescriptor):
                    if case .positions(let positions) = parsePositionsReply(loopDescriptor) {
                        return .success(positions)
                    }
                    return .failure(.scriptError("unexpected reply shape (\(describe(loopDescriptor)))"))
                }
            }
        }
    }

    /// Result of decoding a positions reply.
    enum PositionsReply: Equatable {
        case positions([URL: CGPoint])
        /// The fast path's two URL lists differ (or a list length differs): Finder's item order
        /// or item set changed between the get events, so pairing by index would be wrong.
        case orderChanged
        /// Not a list, or lists of a shape this module does not know.
        case unexpectedShape
    }

    /// Decodes the reply shapes the two scripts produce, plus two defensive ones:
    ///   1. `{ {url…}, {point…}, {url…} }`  fast path (bracketed; the two URL lists must be
    ///      identical, otherwise `.orderChanged`); `{ {}, {}, {} }` for an empty desktop;
    ///   2. `{ {url, point}, … }`           fallback script, one pair per item (`{}` when empty);
    ///   3. `{ {url…}, {point…} }`          two parallel lists without the check (only the
    ///      lengths can be verified);
    ///   4. `{ url, point }`                a single flat pair.
    /// Entries whose URL is not a file URL or whose point cannot be decoded (`missing value`)
    /// are skipped.
    static func parsePositionsReply(_ descriptor: NSAppleEventDescriptor) -> PositionsReply {
        guard descriptor.descriptorType == typeAEListCode else { return .unexpectedShape }
        let count = descriptor.numberOfItems
        if count == 0 { return .positions([:]) }
        let elements = (1...count).compactMap { descriptor.atIndex($0) }
        guard elements.count == count else { return .unexpectedShape }

        // Shape 2: every element is a `{url, point}` pair (checked first: with two or three
        // items this shape also has two or three list elements).
        if elements.allSatisfy(isURLPointPair) {
            var result: [URL: CGPoint] = [:]
            result.reserveCapacity(count)
            for pair in elements {
                guard let urlDesc = pair.atIndex(1), let pointDesc = pair.atIndex(2),
                      let url = fileURL(from: urlDesc), let point = point(from: pointDesc) else { continue }
                result[url] = point
            }
            return .positions(result)
        }

        // Shape 4: one flat pair.
        if count == 2, let url = fileURL(from: elements[0]) {
            guard let point = point(from: elements[1]) else { return .unexpectedShape }
            return .positions([url: point])
        }

        guard elements.allSatisfy({ $0.descriptorType == typeAEListCode }) else { return .unexpectedShape }

        // Shape 1: bracketed parallel lists.
        if count == 3 {
            guard let before = stringList(elements[0]), let after = stringList(elements[2]) else { return .unexpectedShape }
            guard before == after, elements[1].numberOfItems == before.count else { return .orderChanged }
            return .positions(pairLists(urls: elements[0], points: elements[1]))
        }

        // Shape 3: unbracketed parallel lists.
        if count == 2 {
            guard stringList(elements[0]) != nil else { return .unexpectedShape }
            guard elements[0].numberOfItems == elements[1].numberOfItems else { return .orderChanged }
            return .positions(pairLists(urls: elements[0], points: elements[1]))
        }
        return .unexpectedShape
    }

    /// `parsePositionsReply` reduced to the dictionary; nil for `.orderChanged` and
    /// `.unexpectedShape`.
    static func parsePositions(_ descriptor: NSAppleEventDescriptor) -> [URL: CGPoint]? {
        if case .positions(let positions) = parsePositionsReply(descriptor) { return positions }
        return nil
    }

    private static func isURLPointPair(_ descriptor: NSAppleEventDescriptor) -> Bool {
        guard descriptor.descriptorType == typeAEListCode, descriptor.numberOfItems == 2,
              let first = descriptor.atIndex(1), let second = descriptor.atIndex(2) else { return false }
        return fileURL(from: first) != nil && fileURL(from: second) == nil
    }

    /// The strings of a list whose elements are all non-list descriptors; nil otherwise.
    private static func stringList(_ descriptor: NSAppleEventDescriptor) -> [String]? {
        guard descriptor.descriptorType == typeAEListCode else { return nil }
        var strings: [String] = []
        let count = descriptor.numberOfItems
        strings.reserveCapacity(count)
        for index in stride(from: 1, through: count, by: 1) {
            guard let element = descriptor.atIndex(index), element.descriptorType != typeAEListCode,
                  let string = element.stringValue else { return nil }
            strings.append(string)
        }
        return strings
    }

    private static func pairLists(urls: NSAppleEventDescriptor, points: NSAppleEventDescriptor) -> [URL: CGPoint] {
        var result: [URL: CGPoint] = [:]
        let n = urls.numberOfItems
        result.reserveCapacity(n)
        for index in stride(from: 1, through: n, by: 1) {
            guard let urlDesc = urls.atIndex(index), let pointDesc = points.atIndex(index),
                  let url = fileURL(from: urlDesc), let point = point(from: pointDesc) else { continue }
            result[url] = point
        }
        return result
    }

    private static func fileURL(from descriptor: NSAppleEventDescriptor) -> URL? {
        guard descriptor.descriptorType != typeAEListCode,
              let string = descriptor.stringValue, let url = URL(string: string), url.isFileURL else { return nil }
        return url.standardizedFileURL
    }

    /// What NSAppleScript actually returns for a Finder point (observed) is a list of two
    /// 'long' integers `{x, y}`. A raw typeQDPoint ('QDpt') is decoded too, as the QuickDraw
    /// `Point` struct `{ SInt16 v; SInt16 h; }` (vertical first) in host byte order, but that
    /// branch was NOT exercised against Finder: AppleScript coerced every point to a list. (The
    /// harness only checks that the decoder does what this comment says.)
    static func point(from descriptor: NSAppleEventDescriptor) -> CGPoint? {
        if descriptor.descriptorType == typeQDPointCode {
            let data = descriptor.data
            if data.count == 4 {
                let v = Int16(littleEndian: data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: Int16.self) })
                let h = Int16(littleEndian: data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 2, as: Int16.self) })
                return CGPoint(x: CGFloat(h), y: CGFloat(v))
            }
            if data.count == 8 {
                let v = Int32(littleEndian: data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: Int32.self) })
                let h = Int32(littleEndian: data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: Int32.self) })
                return CGPoint(x: CGFloat(h), y: CGFloat(v))
            }
            return nil
        }
        if descriptor.descriptorType == typeAEListCode, descriptor.numberOfItems == 2,
           let xDesc = descriptor.atIndex(1), let yDesc = descriptor.atIndex(2),
           let x = number(from: xDesc), let y = number(from: yDesc) {
            return CGPoint(x: x, y: y)
        }
        // Anything else: let the Apple Event Manager try to coerce it to a list.
        if descriptor.descriptorType != typeAEListCode,
           let list = descriptor.coerce(toDescriptorType: typeAEListCode), list.numberOfItems == 2,
           let xDesc = list.atIndex(1), let yDesc = list.atIndex(2),
           let x = number(from: xDesc), let y = number(from: yDesc) {
            return CGPoint(x: x, y: y)
        }
        return nil
    }

    /// A numeric descriptor ('long', 'shor', 'doub', …) as a CGFloat; nil for text or lists so
    /// a `{url, point}` pair is never mistaken for a point.
    private static func number(from descriptor: NSAppleEventDescriptor) -> CGFloat? {
        let type = descriptor.descriptorType
        if type == typeAEListCode { return nil }
        if type == typeDoubleCode { return CGFloat(descriptor.doubleValue) }
        // int32Value returns 0 for anything it cannot coerce (e.g. text); make sure the
        // descriptor really is a number by round-tripping through the AE Manager's coercion.
        guard descriptor.coerce(toDescriptorType: typeDoubleCode) != nil else { return nil }
        return CGFloat(descriptor.int32Value)
    }

    /// Short human-readable summary of a descriptor (for error messages and the harness).
    static func describe(_ descriptor: NSAppleEventDescriptor, depth: Int = 0) -> String {
        let type = descriptor.descriptorType
        // 0 is what a nil reference answers (messages to nil return 0); typeNull itself is
        // 'null', which the generic branch below prints as 'null' 0B.
        if type == 0 { return "null" }
        let bytes = [UInt8(type >> 24 & 0xff), UInt8(type >> 16 & 0xff), UInt8(type >> 8 & 0xff), UInt8(type & 0xff)]
        let code = bytes.allSatisfy({ $0 >= 0x20 && $0 < 0x7f }) ? String(decoding: bytes, as: UTF8.self) : String(format: "0x%08x", type)
        if type == typeAEListCode {
            let count = descriptor.numberOfItems
            if depth >= 2 || count == 0 { return "list[\(count)]" }
            let sample = (1...min(count, 3)).compactMap { descriptor.atIndex($0) }.map { describe($0, depth: depth + 1) }
            return "list[\(count)]{\(sample.joined(separator: ", "))\(count > 3 ? ", …" : "")}"
        }
        if type == typeQDPointCode {
            let bytes = descriptor.data.map { String(format: "%02x", $0) }.joined()
            return "QDpt(\(bytes))"
        }
        if let string = descriptor.stringValue, type != typeDoubleCode {
            return "'\(code)' \"\(string.prefix(60))\""
        }
        return "'\(code)' \(descriptor.data.count)B"
    }
}

private extension Result {
    var failure: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}

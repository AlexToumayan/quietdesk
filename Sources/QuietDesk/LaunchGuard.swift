import AppKit
import Darwin

/// The two checks that run before anything else, at the top of `main.swift`.
///
/// A command line QuietDesk does not understand must not start the app, and a second copy must
/// never start while one is already running. Both matter because of the one system setting
/// QuietDesk changes: while it is enabled it holds a restore record so that the next launch can
/// put the setting back if this run is killed. A second copy shares those preferences. It reads
/// the first copy's record, concludes that the previous run crashed, undoes the hiding and clears
/// the record. Finder's icons come back underneath the first copy's drawn ones, and the first copy
/// no longer has anything to restore. An unrecognised flag used to reach the same place the long
/// way round, by starting the app instead of being refused.
enum LaunchGuard {
    /// The bundle identifier of QuietDesk.app, and the name of the preferences domain that both
    /// the bundle and the bare developer executable keep their settings in.
    static let bundleIdentifier = "dev.quietdesk.QuietDesk"
    /// The name of the executable file, inside the bundle and in `.build` alike.
    static let executableName = "QuietDesk"

    private struct Flag {
        let name: String
        /// The name of the value that follows the flag, or nil when it stands alone.
        let value: String?
        let help: String
        var spelled: String { value.map { "\(name) \($0)" } ?? name }
    }

    /// Every flag QuietDesk understands. Keep in step with AppDelegate, Settings, DebugLog,
    /// DesktopModel and ScenarioTest, which are the files that read the command line.
    private static let flags: [Flag] = [
        Flag(name: "--help", value: nil, help: "Print this text, then exit. Also -h."),
        Flag(name: "--self-test", value: nil, help: "Run the built-in logic checks, then exit."),
        Flag(name: "--dump-layout", value: nil, help: "Print the computed icon grid, then exit."),
        Flag(name: "--render", value: "FILE", help: "Render the overlay on the main display to a PNG, then exit."),
        Flag(name: "--hover", value: "N", help: "With --render: draw item number N as if the pointer were on it."),
        Flag(name: "--expand", value: "TITLE", help: "With --render: open the Stack with this title first."),
        Flag(name: "--render-view-options", value: "FILE", help: "Render the View Options panel to a PNG, then exit."),
        Flag(name: "--dark", value: nil, help: "With --render-view-options: use the dark appearance."),
        Flag(name: "--render-status-item", value: "FILE", help: "Render the menu bar icon to a PNG, then exit."),
        Flag(name: "--icon-candidates", value: nil, help: "Render the app icon candidates, then exit."),
        Flag(name: "--scenario-test", value: nil, help: "Replay click sequences through the real windows, then exit."),
        Flag(name: "--with-reveal", value: nil, help: "With --scenario-test: add the rounds that reveal the desktop."),
        Flag(name: "--desktop-dir", value: "PATH", help: "Read this folder instead of the Desktop folder."),
        Flag(name: "--defaults-suite", value: "NAME", help: "Keep settings in this preferences domain instead of the usual one."),
        Flag(name: "--test-seconds", value: "N", help: "Quit after N seconds, restoring the desktop."),
        Flag(name: "--no-hide", value: nil, help: "Draw the overlay without hiding Finder's own icons."),
        Flag(name: "--hit-test", value: nil, help: "Print which window a click would reach at a few points."),
        Flag(name: "--debug-log", value: nil, help: "Write an event trace to the QuietDesk log file."),
    ]

    /// The flags that do their work and exit without ever enabling the overlay.
    private static let selfExitingFlags = ["--self-test", "--dump-layout", "--render",
                                           "--render-view-options", "--render-status-item", "--icon-candidates"]

    static var usage: String {
        let width = flags.map(\.spelled.count).max() ?? 0
        var lines = [
            "QuietDesk draws your desktop items itself and asks macOS to hide Finder's copies.",
            "With no flags it starts in the menu bar. The rest are for development.",
            "",
            "Usage: QuietDesk [flags]",
            "",
        ]
        lines += flags.map { "  \($0.spelled.padding(toLength: width, withPad: " ", startingAt: 0))  \($0.help)" }
        lines += ["", "A setting can also be given the Cocoa way, for example: -labelMode hover"]
        return lines.joined(separator: "\n")
    }

    enum ArgumentCheck: Equatable {
        case ok
        case help
        case unknown(String)
    }

    /// Reads the command line left to right. Only arguments that start with two dashes are judged:
    /// a single dash is how Cocoa takes a setting (`-labelMode hover`, which the README documents)
    /// and how macOS passes its own arguments (`-psn_...`, `-NSDocumentRevisionsDebugMode`). The
    /// value that follows a known flag is skipped, so a path, a number or a Stack title is never
    /// mistaken for a flag of its own.
    static func check(_ args: [String]) -> ArgumentCheck {
        var i = 1
        while i < args.count {
            let argument = args[i]
            if argument == "--help" || argument == "-h" { return .help }
            if argument.hasPrefix("--") {
                guard let flag = flags.first(where: { $0.name == argument }) else { return .unknown(argument) }
                if flag.value != nil { i += 1 }
            }
            i += 1
        }
        return .ok
    }

    /// Prints and exits when the command line is not one QuietDesk can run. Nothing here touches
    /// preferences, so a typo can never disturb a copy that is running.
    static func checkArguments(_ args: [String] = CommandLine.arguments) {
        switch check(args) {
        case .ok:
            return
        case .help:
            print(usage)
            exit(0)
        case .unknown(let flag):
            fputs("QuietDesk: \(flag) is not a flag QuietDesk knows.\n\n\(usage)\n", stderr)
            exit(64)   // EX_USAGE
        }
    }

    /// True for a run that would hide the desktop using the person's own preferences: a plain
    /// launch, and the flags that still enable the overlay (--test-seconds, --hit-test, --no-hide,
    /// --debug-log). A run that exits on its own, a scenario test (always its own per-process
    /// domain) and any run given another preferences domain are not: those are meant to work while
    /// the real app is running.
    static func isNormalMode(_ args: [String] = CommandLine.arguments) -> Bool {
        if args.contains(where: selfExitingFlags.contains) { return false }
        if args.contains("--scenario-test") { return false }
        if let i = args.firstIndex(of: "--defaults-suite"), i + 1 < args.count, args[i + 1] != bundleIdentifier { return false }
        return true
    }

    /// The process id of another QuietDesk, or nil.
    static func otherInstance() -> pid_t? {
        let me = ProcessInfo.processInfo.processIdentifier
        for app in NSWorkspace.shared.runningApplications
        where app.processIdentifier != me && app.bundleIdentifier == bundleIdentifier {
            return app.processIdentifier
        }
        // Measured: NSWorkspace lists bundled apps only. A bare executable, which is how the
        // developer flags are run, never appears there even though it is a real accessory app,
        // so the process table is read as well. That is also the copy with no bundle identifier,
        // so it is recognised by the name of its executable file.
        return otherProcessByExecutableName(me: me)
    }

    private static func otherProcessByExecutableName(me: pid_t) -> pid_t? {
        let known = proc_listallpids(nil, 0)
        guard known > 0 else { return nil }
        var pids = [pid_t](repeating: 0, count: Int(known) + 64)   // room for processes started since
        let bytes = proc_listallpids(&pids, Int32(MemoryLayout<pid_t>.size * pids.count))
        guard bytes > 0 else { return nil }
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        for pid in pids.prefix(Int(bytes) / MemoryLayout<pid_t>.size) where pid > 0 && pid != me {
            // Another user's process answers with an error, and is none of our business anyway.
            guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { continue }
            if isQuietDeskExecutable(String(cString: path)) { return pid }
        }
        return nil
    }

    /// True for the executable inside QuietDesk.app and for the bare one in `.build`.
    static func isQuietDeskExecutable(_ path: String) -> Bool {
        (path as NSString).lastPathComponent == executableName
    }

    /// Refuses to start a second copy, before anything has read or written a preference. Silent
    /// apart from one line on stderr: a login item and a launch by hand can race, and nobody needs
    /// an alert for that.
    static func enforceSingleInstance(_ args: [String] = CommandLine.arguments) {
        guard isNormalMode(args), let pid = otherInstance() else { return }
        fputs("QuietDesk is already running (pid \(pid)); not starting a second copy.\n", stderr)
        exit(0)
    }
}

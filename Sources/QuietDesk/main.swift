import AppKit
import Darwin

// Never materialize (download) cloud-only files, no matter what code path touches them.
// Documented in Apple TN3150 "Working with dataless files": with this policy a read of a
// dataless file fails with EDEADLK instead of triggering a download.
_ = setiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_PROCESS, IOPOL_MATERIALIZE_DATALESS_FILES_OFF)

// First of all, before a preference or a restore record is read or written: a command line
// QuietDesk cannot run must not start the app, and a second copy must not start at all.
LaunchGuard.checkArguments()
LaunchGuard.enforceSingleInstance()

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // menu-bar only: no Dock icon, no main window
app.run()

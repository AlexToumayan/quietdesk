import AppKit
import Darwin

// Never materialize (download) cloud-only files, no matter what code path touches them.
// Documented in Apple TN3150 "Working with dataless files": with this policy a read of a
// dataless file fails with EDEADLK instead of triggering a download.
_ = setiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_PROCESS, IOPOL_MATERIALIZE_DATALESS_FILES_OFF)

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // menu-bar only: no Dock icon, no main window
app.run()

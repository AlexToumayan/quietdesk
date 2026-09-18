import Foundation
// Experiment only: the Dock's private notification entry point for Show Desktop.
typealias Fn = @convention(c) (CFString, UnsafeMutableRawPointer?) -> Void
guard let handle = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_LAZY),
      let sym = dlsym(handle, "CoreDockSendNotification") else { print("symbol not found"); exit(1) }
let send = unsafeBitCast(sym, to: Fn.self)
send("com.apple.showdesktop.awake" as CFString, nil)
print("sent com.apple.showdesktop.awake")

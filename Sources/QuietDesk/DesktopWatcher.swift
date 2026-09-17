import Foundation

/// Event-driven, non-recursive watch on the Desktop folder: fires when an entry is added,
/// removed or renamed at the top level. Rewrites of existing files (including Finder's
/// .DS_Store) do not change the directory entry list and do not wake us.
final class DesktopWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?

    init?(url: URL, debounce: TimeInterval = 0.4, onChange: @escaping () -> Void) {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        src.setEventHandler { [weak self] in
            guard let self else { return }
            self.pending?.cancel()
            let work = DispatchWorkItem(block: onChange)
            self.pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + debounce, execute: work)
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    deinit {
        pending?.cancel()
        source?.cancel()
    }
}

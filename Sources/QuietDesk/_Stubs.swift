// TEMPORARY stand-ins for modules being implemented separately (ThumbnailCache.swift,
// CloudStatusMonitor.swift, FinderAutomation.swift). Delete this file once those land.
import AppKit

final class ThumbnailCache {
    static let shared = ThumbnailCache()
    var onReady: ((URL) -> Void)?
    func thumbnail(for url: URL, size: CGFloat, scale: CGFloat) -> NSImage? { nil }
    func invalidate(_ url: URL) {}
    func removeAll() {}
    func cancelAll() {}
    static func isFullyLocal(_ url: URL) -> Bool { false }
    static func isEligible(_ url: URL) -> Bool { false }
}

enum CloudStatus: Equatable { case notInCloud, current, notDownloaded, downloading(Double), uploading(Double), notUploaded, error }

final class CloudStatusMonitor {
    init(directory: URL) {}
    var onChange: (() -> Void)?
    func start() {}
    func stop() {}
    func status(for url: URL) -> CloudStatus { .notInCloud }
    static func resourceStatus(for url: URL) -> CloudStatus { .notInCloud }
}

enum FinderAutomationStatus { case allowed, denied, needsConsent, finderNotRunning }
enum FinderAutomationError: Error, CustomStringConvertible {
    case notPermitted, finderNotRunning, scriptError(String)
    var description: String { "Finder automation unavailable (stub)" }
}
enum FinderAutomation {
    static func status() -> FinderAutomationStatus { .needsConsent }
    static func readDesktopPositions(completion: @escaping (Result<[URL: CGPoint], FinderAutomationError>) -> Void) { completion(.failure(.notPermitted)) }
    static func writeDesktopPosition(_ point: CGPoint, for url: URL, completion: @escaping (FinderAutomationError?) -> Void) { completion(nil) }
    static func openInfoWindows(for urls: [URL], completion: @escaping (FinderAutomationError?) -> Void) { completion(nil) }
    static func openNewWindow(at folder: URL, completion: @escaping (FinderAutomationError?) -> Void) { completion(nil) }
}

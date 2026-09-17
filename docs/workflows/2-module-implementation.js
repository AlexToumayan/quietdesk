export const meta = {
  name: 'quietdesk-modules',
  description: 'Implement three self-contained Swift modules for QuietDesk (thumbnails, iCloud status, Finder automation) and verify each',
  phases: [
    { title: 'Implement', detail: 'one agent per module, developed in a scratch package, then copied into the project' },
    { title: 'Verify', detail: 'skeptic checks API usage, safety constraints and compile' },
  ],
}

const COMMON = `
CONTEXT: QuietDesk is a small open-source macOS menu-bar utility (Swift, AppKit, SwiftPM, NO Xcode on this machine: only Command Line Tools with Swift 6.1 and the macOS 15.4 SDK; swift-tools-version 5.9, Swift 5 language mode, platforms macOS 14+). Project: <repo> (read README.md and docs/FEASIBILITY.md first for constraints). The main developer is editing the core files concurrently, so the project may not build at any given moment — DO NOT run 'swift build' in the project, do not edit any existing project file, and do not touch git.

HARD CONSTRAINTS (from the product brief): never rename/move/modify user files; never trigger iCloud/cloud downloads of dataless files; no polling or timers at idle (event-driven only); no subprocesses (no Process/osascript) — use in-process APIs; no Accessibility or Screen Recording permissions; keep memory bounded; only public, documented APIs (if you must rely on undocumented behaviour, say so in a comment). Do not run anything that changes the user's desktop, Finder state or system preferences. Reading ~/Desktop is allowed (this session already has Desktop access).

WORKFLOW: (1) Create a scratch SwiftPM package under <scratch>/modules/<module>/ with an executable target containing your module file plus a small harness main.swift that exercises it against real files in ~/Desktop (read-only) and prints results; build it with 'swift build -c release' and run it. (2) When it works, copy ONLY your module file to <repo>/Sources/QuietDesk/<ModuleName>.swift (create; do not modify other files). The module must have NO dependencies on other project types — only Foundation/AppKit/QuickLookThumbnailing/UniformTypeIdentifiers/ServiceManagement as needed. (3) Return: the exact public interface you implemented, what you verified by running, API caveats, and anything you could not verify. Use ToolSearch "select:WebFetch,WebSearch" to check Apple documentation when unsure (developer.apple.com pages are JS-rendered; fetch https://developer.apple.com/tutorials/data/documentation/<path>.json).
`

const MODULES = [
  {
    key: 'ThumbnailCache',
    prompt: `${COMMON}
MODULE: ThumbnailCache.swift — Finder-style "icon preview" thumbnails for desktop items, never triggering cloud downloads.

Implement exactly this interface (add private helpers freely):

import AppKit
import QuickLookThumbnailing
import UniformTypeIdentifiers

/// Bounded in-memory cache of Finder-style previews (QuickLook thumbnails with icon decoration).
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    /// Called on the main queue when a thumbnail that was previously reported nil becomes available.
    var onReady: ((URL) -> Void)?
    /// Returns the cached preview at \`size\` points for the given backing \`scale\` (1 or 2), or nil.
    /// When nil and the file is eligible, generation is started (bounded concurrency) and onReady fires later.
    /// Never blocks; never reads file contents on the calling thread.
    func thumbnail(for url: URL, size: CGFloat, scale: CGFloat) -> NSImage?
    /// Forget one file (e.g. after it changed) or everything.
    func invalidate(_ url: URL)
    func removeAll()
    /// Cancels pending generation (e.g. when the overlay is disabled).
    func cancelAll()
    /// True when reading the file cannot trigger a cloud download: not a dataless file (SF_DATALESS in st_flags via stat, see Apple TN3150) and,
    /// if it is an iCloud item, its ubiquitousItemDownloadingStatus is .current or .downloaded.
    static func isFullyLocal(_ url: URL) -> Bool
    /// True for files Finder would show a preview for: regular files (not folders, not packages/apps) whose type QuickLook can thumbnail
    /// (images, PDF, movies, audio, text/documents...). Folders, packages and apps return false.
    static func isEligible(_ url: URL) -> Bool
}

Requirements: use QLThumbnailGenerator with a QLThumbnailGenerator.Request (size in points, scale, representationTypes .thumbnail; set iconMode = true so the result looks like Finder's decorated icon; verify iconMode exists in the SDK). Limit in-flight requests (e.g. 6) with a FIFO of pending URLs; never request for files that are not fully local (check BEFORE requesting, because the generation happens in another process which does not inherit our I/O policy). Cache key = path|size|scale; bound the cache (e.g. 500 entries, evict oldest). Store only small bitmaps (the result at the requested pixel size). Remember negative results (generation failed) so we do not retry endlessly; invalidate() clears that. Thread-safety: public methods called on the main thread; completion handlers hop to main. Harness: print isFullyLocal/isEligible for 10 desktop files, request thumbnails for a few PDFs/images on the Desktop, wait for onReady, and write one thumbnail PNG to the scratch dir to prove it rendered (do not write into ~/Desktop). Report timing per thumbnail.`,
  },
  {
    key: 'CloudStatusMonitor',
    prompt: `${COMMON}
MODULE: CloudStatusMonitor.swift — event-driven iCloud sync status for the top-level items of ~/Desktop (the user's Desktop is synced with iCloud Desktop & Documents).

Implement exactly this interface:

import Foundation

enum CloudStatus: Equatable {
    case notInCloud            // local item, no glyph
    case current               // in iCloud and fully downloaded/up to date (Finder shows a small cloud glyph or nothing; report what Apple's keys say)
    case notDownloaded         // cloud-only, evicted (cloud with down arrow)
    case downloading(Double)   // 0...1
    case uploading(Double)     // 0...1
    case notUploaded           // waiting to upload
    case error
}

/// Watches iCloud status of items directly inside \`directory\` using NSMetadataQuery (no polling: Spotlight pushes updates).
final class CloudStatusMonitor {
    init(directory: URL)
    /// Main-queue callback fired when any status changed (coalesced).
    var onChange: (() -> Void)?
    func start()
    func stop()
    /// Last known status; .notInCloud when unknown/not ubiquitous.
    func status(for url: URL) -> CloudStatus
    /// One-shot, synchronous status from URL resource values (fallback when the query has not gathered yet).
    static func resourceStatus(for url: URL) -> CloudStatus
}

Requirements: NSMetadataQuery with searchScopes = [directory] (verify that a directory URL scope is supported; otherwise use NSMetadataQueryUbiquitousDocumentsScope plus filtering by parent directory), predicate matching all items, notifications NSMetadataQueryDidFinishGathering and NSMetadataQueryDidUpdate; call disableUpdates/enableUpdates around result reads; only keep items whose parent directory is \`directory\` (top level). Map NSMetadataUbiquitousItemDownloadingStatusKey (.current/.downloaded/.notDownloaded), NSMetadataUbiquitousItemIsDownloadingKey, ...PercentDownloadedKey, ...IsUploadingKey, ...PercentUploadedKey, ...IsUploadedKey, ...DownloadingErrorKey/UploadingErrorKey. Make sure start() does not read file contents and cannot trigger downloads. stop() must fully stop the query and remove observers (used when the utility is disabled). Harness: run the query on ~/Desktop for ~5 seconds, print a histogram of statuses and 10 example items, then stop; also print resourceStatus for a few items and compare.`,
  },
  {
    key: 'FinderAutomation',
    prompt: `${COMMON}
MODULE: FinderAutomation.swift — in-process Apple Events to Finder for (a) reading/writing desktop icon positions on manually arranged desktops and (b) opening Finder's Get Info window. This session ALREADY has Automation consent for Finder, so your harness can run these (read-only calls only: do not write positions, do not open Info windows during the harness unless you immediately close them — prefer not to).

Implement exactly this interface:

import AppKit

enum FinderAutomationStatus { case allowed, denied, needsConsent, finderNotRunning }

enum FinderAutomation {
    /// Preflight with AEDeterminePermissionToAutomateTarget(askUserIfNeeded: false). Must be called off the main thread (Apple's header says so); wrap accordingly.
    static func status() -> FinderAutomationStatus
    /// Reads Finder's desktop icon positions in ONE Apple event ({URL, desktop position} of every item of desktop), off the main thread; completion on main.
    /// Result keys are file URLs (standardized); values are Finder's points: origin at the top-left of the main display, y down, in points.
    static func readDesktopPositions(completion: @escaping (Result<[URL: CGPoint], FinderAutomationError>) -> Void)
    /// Sets one item's desktop position (only meaningful when Sort By is None).
    static func writeDesktopPosition(_ point: CGPoint, for url: URL, completion: @escaping (FinderAutomationError?) -> Void)
    /// Opens Finder's Get Info window(s) for the given items.
    static func openInfoWindows(for urls: [URL], completion: @escaping (FinderAutomationError?) -> Void)
    /// Opens a new Finder window showing the given folder (equivalent of File > New Finder Window / Cmd-N on the desktop).
    static func openNewWindow(at folder: URL, completion: @escaping (FinderAutomationError?) -> Void)
}

enum FinderAutomationError: Error, CustomStringConvertible {
    case notPermitted          // -1743 / user denied: description must tell the user where to allow it (System Settings > Privacy & Security > Automation)
    case finderNotRunning
    case scriptError(String)
    var description: String { get }
}

Requirements: use NSAppleScript in-process (so TCC attributes the request to this app), run on a dedicated serial background queue, never on main; build scripts with proper quoting of paths (use POSIX file "..." and escape quotes/backslashes). Parse NSAppleEventDescriptor results (list of {URL text, {x, y}}); 'URL' property returns "file:///..." strings. Detect error -1743 (errAEEventNotPermitted) and -600 (procNotFound). Also document (in a comment, with what your harness observed) whether the returned position is the icon centre or another anchor: compare a couple of returned points with the known layout facts from docs/FEASIBILITY.md (this desktop is sorted, so positions are stale; just record the observed values and the coordinate ranges for both displays). Harness: print status(), then readDesktopPositions and show 10 entries plus min/max x/y; do NOT call write/openInfoWindows/openNewWindow in the harness (just make sure they compile) — actually you may call openNewWindow once and then close that window with a follow-up 'close front window' script so nothing is left behind; say what you did.`,
  },
]

const RESULT = {
  type: 'object',
  properties: {
    module: { type: 'string' },
    file_written: { type: 'string' },
    interface: { type: 'string' },
    verified_by_running: { type: 'array', items: { type: 'string' } },
    caveats: { type: 'array', items: { type: 'string' } },
    not_verified: { type: 'array', items: { type: 'string' } },
  },
  required: ['module', 'file_written', 'interface', 'verified_by_running'],
}

const VERDICT = {
  type: 'object',
  properties: {
    module: { type: 'string' },
    compiles_standalone: { type: 'boolean' },
    problems: { type: 'array', items: { type: 'object', properties: { severity: { type: 'string', enum: ['blocker', 'major', 'minor'] }, description: { type: 'string' }, fix_applied: { type: 'boolean' } }, required: ['severity', 'description', 'fix_applied'] } },
    summary: { type: 'string' },
  },
  required: ['module', 'compiles_standalone', 'problems', 'summary'],
}

phase('Implement')
const results = await pipeline(
  MODULES,
  m => agent(m.prompt, { label: `impl:${m.key}`, phase: 'Implement', schema: RESULT }),
  (impl, m) => {
    if (!impl) return null
    return agent(`${COMMON}
You are a SKEPTICAL REVIEWER for the module ${m.key} written to ${impl.file_written}. Read the file. Check against the HARD CONSTRAINTS above and against Apple's documentation: (1) can any code path read file contents or trigger a cloud download of a dataless file? (2) any timers, polling, or work at idle? (3) any subprocess? (4) thread-safety of the public API and completion-handler queues; (5) bounded memory; (6) correct use of the APIs (verify signatures against the macOS 15.4 SDK headers under /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk or the docs); (7) does it compile standalone: copy it into a fresh scratch package under <scratch>/review/${m.key}/ with an empty main.swift and run 'swift build'. Fix blockers/majors directly in the project file (only that file) and re-verify compile; report what you changed.

Implementer's report:
${JSON.stringify(impl, null, 1)}`, { label: `review:${m.key}`, phase: 'Verify', schema: VERDICT })
      .then(v => ({ key: m.key, impl, review: v }))
  },
)
return results.filter(Boolean)
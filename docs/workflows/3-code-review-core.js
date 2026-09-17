export const meta = {
  name: 'quietdesk-code-review-core',
  description: 'Adversarial review of the QuietDesk codebase across five dimensions, each finding verified by an independent skeptic',
  phases: [
    { title: 'Review', detail: 'five reviewers, one dimension each' },
    { title: 'Verify', detail: 'each finding independently checked against the code' },
  ],
}

const COMMON = `
CONTEXT: QuietDesk, <repo> — a Swift/AppKit/SwiftPM macOS menu-bar utility (no Xcode on this machine; Command Line Tools, Swift 6.1, macOS 15.4 SDK, Swift 5 language mode). Read README.md and docs/FEASIBILITY.md first, then the sources in Sources/QuietDesk/. HARD PRODUCT CONSTRAINTS: never rename/move/modify user files except as an explicit user action that Finder would perform the same way; never trigger cloud downloads of dataless files; near-zero idle work (no timers/polling at idle; timers allowed only during a drag, while typing, or after a click for rename); no subprocesses; only Desktop-folder and Finder-Automation permissions; restore the desktop setting on disable/quit and after crashes; bounded memory; public APIs (document any reliance on undocumented behaviour). You may build with 'swift build -c release' and run './.build/release/QuietDesk --self-test', '--dump-layout' and '--render out.png' (write PNGs only under <scratch>/). Do NOT run the app in live mode (no --test-seconds without --no-hide, no 'open build/QuietDesk.app'), do not change system preferences, do not modify ~/Desktop, do not touch git. Report only real defects with a concrete failure scenario; skip style nits.
`

const DIMENSIONS = [
  { key: 'file-safety', prompt: `${COMMON}
DIMENSION: File-operation safety and undo correctness. Files: FileOperations.swift, the DesktopDrop enum and rename code in DesktopView.swift, ShieldView.swift drops, DesktopModel.swift scanning. Hunt for: data loss (overwrites, wrong destination, moving the wrong item, renaming to an invalid name, case-only renames on APFS), undo that restores the wrong thing or re-registers incorrectly (redo loops, undo after the file was moved again), operations on the main thread that block (large copies), race conditions between the background queue and the Desktop watcher relayout, dataless-file materialization (copyItem/moveItem of a cloud-only file — is that acceptable? it is an explicit user action, but confirm nothing implicit reads contents), symlink/alias handling, volumes (trash/duplicate on a volume root), file promises (NSFilePromiseReceiver misuse), pasteboard misuse.` },
  { key: 'events-focus', prompt: `${COMMON}
DIMENSION: Event handling, focus and window behaviour. Files: OverlayWindow.swift, DesktopView.swift, ShieldView.swift, OverlayController.swift. Hunt for: mouse state machines that get stuck (mouseDownCell/bandStart/didDrag after drags, right-click during drag), rubber band coordinate conversions across two windows and screens (flipped coordinates, multi-display, external display above the main one), tracking areas not rebuilt on relayout, hover label stuck after cells change, keyboard handling (keyCode switch fallthrough, Cmd shortcuts colliding, type-to-select swallowing shortcuts), rename field lifecycle (commit on resign key, cells change while renaming, first responder), Quick Look panel data source lifetime, non-activating NSPanel becoming key vs Finder activation ordering, level resets, spring-loading timer leaks, drop target highlight stuck, the --render and simulateHover hooks, and anything that could leave a window at the wrong level or on the wrong Space.` },
  { key: 'idle-resources', prompt: `${COMMON}
DIMENSION: Idle behaviour, resources and leaks. All files. Hunt for: any timer, polling, run-loop source or observer that stays alive while enabled-and-idle or after disable; observers not removed in stop(); notification observers capturing self strongly; DispatchSource/file-descriptor leaks in DesktopWatcher on rebuild; NSMetadataQuery lifecycle (CloudStatusMonitor.swift if present); ThumbnailCache in-flight jobs after stop(); IconCache and truncation caches growing without bound; per-draw allocations that could matter (expandedLabelRect boundingRect per cell per draw, symbol rendering), full-view redraws where a cell invalidation would do; retain cycles (closures in OverlayController/DesktopView/ShieldView, delegate strong refs); memory of the full-screen shield (must stay bitmap-free); anything that runs on every mouse move.` },
  { key: 'restore-safety', prompt: `${COMMON}
DIMENSION: Restoration, crash safety and settings. Files: AppDelegate.swift, DesktopIconsPreference.swift, Settings.swift, OverlayController.swift, main.swift, LoginItem.swift. Hunt for: paths where the hide key is written but the restore record is not saved (or vice versa), enable() failing after the key is written, disable() not restoring when the user changed the key externally (expected behaviour: leave it), applicationWillTerminate not running for SIGTERM/kill (document), --test-seconds and diagnostic flags interfering, recovery on next launch when the previous value was 'true', double enable/disable, menu state drift (rebuildMenu), Launch at Login via SMAppService with an ad-hoc bundle, the 'Bring Finder Forward' setting semantics, and the 'Desktop Items: Hidden' mode leaving observers running (acceptable?) or the shield still catching clicks.` },
  { key: 'layout-model', prompt: `${COMMON}
DIMENSION: Layout and model correctness. Files: Layout.swift, DesktopModel.swift, FinderDesktopPrefs.swift, SelfTest.swift. Hunt for: off-by-one in rows/columns, cells placed under the menu bar or Dock, multi-display continuation order, manual layout (computeManual) coordinate conversions with a display above the main one (negative y), slot collisions when two items share a grid slot, unpositioned items overlapping positioned ones, snapToGrid rounding, expanded stack members and selection index invalidation after relayout, kindCategory misclassification, dateBucket edge cases (DST, year boundary, dates in the future), comparator inconsistency (non-strict weak ordering crashes in sort), sorting stability for equal dates, volume filtering rules vs Finder prefs, hidden/dot files, packages vs folders, localizedName vs lastPathComponent mismatches (extension hidden), and the self-test's own assumptions.` },
]

const FINDINGS = { type: 'object', properties: { dimension: { type: 'string' }, findings: { type: 'array', items: { type: 'object', properties: { file: { type: 'string' }, line: { type: 'integer' }, severity: { type: 'string', enum: ['blocker', 'major', 'minor'] }, summary: { type: 'string' }, failure_scenario: { type: 'string' }, suggested_fix: { type: 'string' } }, required: ['file', 'severity', 'summary', 'failure_scenario'] } } }, required: ['dimension', 'findings'] }
const VERDICT = { type: 'object', properties: { real: { type: 'boolean' }, severity: { type: 'string', enum: ['blocker', 'major', 'minor', 'not-a-bug'] }, note: { type: 'string' }, fix: { type: 'string' } }, required: ['real', 'severity', 'note'] }

phase('Review')
const results = await pipeline(
  DIMENSIONS,
  d => agent(d.prompt, { label: `review:${d.key}`, phase: 'Review', schema: FINDINGS }),
  (found, d) => {
    if (!found) return null
    const items = found.findings.filter(f => f.severity !== 'minor').slice(0, 12)
    log(`${d.key}: ${found.findings.length} findings, verifying ${items.length} non-minor`)
    return parallel(items.map(f => () =>
      agent(`${COMMON}
You are a SKEPTICAL VERIFIER. A reviewer claims the following defect. Read the actual code and decide whether it is real, with a concrete reproduction argument; default to real=false if you cannot show the failure from the code. Do not fix anything.

CLAIM (${d.key}): ${JSON.stringify(f)}`, { label: `verify:${d.key}`, phase: 'Verify', schema: VERDICT })
        .then(v => ({ ...f, verdict: v }))))
      .then(vs => ({ key: d.key, minors: found.findings.filter(f => f.severity === 'minor'), verified: vs.filter(Boolean) }))
  },
)
const out = results.filter(Boolean)
const confirmed = out.flatMap(r => r.verified.filter(v => v.verdict && v.verdict.real).map(v => ({ dimension: r.key, ...v })))
log(`confirmed ${confirmed.length} findings`)
return { confirmed, minors: out.flatMap(r => r.minors.map(m => ({ dimension: r.key, ...m }))), rejected: out.flatMap(r => r.verified.filter(v => !(v.verdict && v.verdict.real)).map(v => ({ dimension: r.key, summary: v.summary, note: v.verdict && v.verdict.note }))) }

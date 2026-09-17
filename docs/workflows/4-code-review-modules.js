export const meta = {
  name: 'quietdesk-code-review-modules',
  description: 'Adversarial review of the QuietDesk codebase across the module-integration dimension, each finding verified by an independent skeptic',
  phases: [
    { title: 'Review', detail: 'one reviewer' },
    { title: 'Verify', detail: 'each finding independently checked against the code' },
  ],
}

const COMMON = `
CONTEXT: QuietDesk, <repo> — a Swift/AppKit/SwiftPM macOS menu-bar utility (no Xcode on this machine; Command Line Tools, Swift 6.1, macOS 15.4 SDK, Swift 5 language mode). Read README.md and docs/FEASIBILITY.md first, then the sources in Sources/QuietDesk/. HARD PRODUCT CONSTRAINTS: never rename/move/modify user files except as an explicit user action that Finder would perform the same way; never trigger cloud downloads of dataless files; near-zero idle work (no timers/polling at idle; timers allowed only during a drag, while typing, or after a click for rename); no subprocesses; only Desktop-folder and Finder-Automation permissions; restore the desktop setting on disable/quit and after crashes; bounded memory; public APIs (document any reliance on undocumented behaviour). You may build with 'swift build -c release' and run './.build/release/QuietDesk --self-test', '--dump-layout' and '--render out.png' (write PNGs only under <scratch>/). Do NOT run the app in live mode (no --test-seconds without --no-hide, no 'open build/QuietDesk.app'), do not change system preferences, do not modify ~/Desktop, do not touch git. Report only real defects with a concrete failure scenario; skip style nits.
`

const DIMENSIONS = [
  { key: 'modules-integration', prompt: `${COMMON}
DIMENSION: Integration of the three modules. Files: ThumbnailCache.swift, FinderAutomation.swift, CloudStatusMonitor.swift (if present), and their call sites in DesktopView.swift, OverlayController.swift. Hunt for: thumbnails requested for dataless files through any path, thumbnail size/scale mismatches between displays (1x external vs 2x built-in), onReady invalidation on the wrong view, FinderAutomation calls on the main thread or without permission handling (denied → what does the user see?), Get Info/New Window scripts with unusual file names (quotes, backslashes, unicode, trailing slashes for folders), positions read on sorted desktops (should not happen), write-back of positions racing with relayout, CloudStatusMonitor scope/predicate correctness for top-level items only and start/stop balance, and any use of undocumented APIs not flagged in comments.` },
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

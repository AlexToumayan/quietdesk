export const meta = {
  name: 'review-reveal-desktop',
  description: 'Adversarially review QuietDesk\'s reveal-desktop support (3 lenses, 2 skeptics per finding, completeness critic)',
  phases: [{ title: 'Review' }, { title: 'Verify' }, { title: 'Critic' }],
}

const CONTEXT = `
You are reviewing an UNCOMMITTED change in the SwiftPM package at <repo> (a macOS AppKit
menu-bar utility "QuietDesk": it asks macOS to hide Finder's desktop icons (com.apple.WindowManager
StandardHideDesktopIcons) and draws them itself in borderless non-activating panels at the desktop-icon window
levels: a full-screen "shield" at +1 and an icon window at +2; names appear on hover). Run \`git diff\` and
\`git status\` there to see the change (new file Sources/QuietDesk/DesktopReveal.swift is untracked: read it), and
read any file you need with cat/sed. Do NOT modify files. Do NOT run the app or any QuietDesk binary, do NOT run
anything that triggers Show Desktop. \`swift build -c release\` is fine.

Measured facts on macOS 26.6 that the change is built on (treat as true):
- While the desktop is "revealed" (wallpaper click, F11, spread gesture, hot corner), macOS re-shows Finder's hidden
  desktop items for the duration, however the reveal was started.
- No AppKit, NSWorkspace, distributed or Darwin notification fires when a reveal starts or ends, and a desktop-level
  panel gets no occlusion change. The only observable: while revealed the Dock owns a screen-sized window at layer 18
  (one per display); WindowManager's click-catcher windows disappear for the duration. One window-list check costs ~1 ms.
- CoreDockSendNotification("com.apple.showdesktop.awake") (private symbol in ApplicationServices, found with dlsym)
  toggles Show Desktop without any permission. The old "Mission Control 1" command does nothing any more.
- QuietDesk's desktop-level panels stay on screen during a reveal unless ordered out.

What the change does:
1. DesktopReveal.swift: clickRevealsDesktop (reads EnableStandardClickToShowDesktop, default true, or Stage Manager
   GloballyEnabled), toggle() (dlsym + call), isRevealed (Dock-owned on-screen window, 0 < layer < dock level,
   size equal to some screen's).
2. OverlayController: a repeating Timer checks isRevealed every 1.0 s (tolerance 0.5) at rest and every 0.25 s while
   revealed; on reveal it commits a rename, clears hover, orders out all icon windows and shields (steppedAside =
   true); when the reveal ends it shows them again. show()/hide()/rebuildWindows() respect steppedAside.
   surfaceWallpaperClicked() counts the click, and if revealOnWallpaperClick && clickRevealsDesktop calls toggle()
   and schedules three quick checkReveal() calls.
3. ShieldView.mouseUp and DesktopView.mouseUp (a click in a gap between icons) report a plain click (no drag > 4 pt,
   clickCount 1, no modifiers) via surfaceWallpaperClicked(). DesktopSurfaceDelegate gained that method.
4. ScenarioTest: reveal is disabled in tests (revealOnWallpaperClick = false) except with --with-reveal, which runs
   one real reveal round.

Product invariants: never leave the person with NO desktop icons or with doubled icons for long; restore correctly on
Turn Off / Quit / SIGTERM even in the middle of a reveal; no crashes; idle work must stay tiny (the README promises
measured near-zero idle cost); the private entry point must fail safe; QuietDesk must not fight the user (e.g. a
wallpaper click that both deselects and reveals is what Finder does; a click that reveals twice is a bug).
`

const FINDINGS = {
  type: 'object',
  properties: {
    findings: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          file: { type: 'string' }, line: { type: 'integer' },
          title: { type: 'string' }, description: { type: 'string' },
          failure_scenario: { type: 'string', description: 'Concrete inputs/state -> wrong output, crash, or bad UX' },
          severity: { type: 'string', enum: ['blocker', 'major', 'minor', 'nit'] },
        },
        required: ['file', 'line', 'title', 'description', 'failure_scenario', 'severity'],
      },
    },
  },
  required: ['findings'],
}
const VERDICT = {
  type: 'object',
  properties: { refuted: { type: 'boolean' }, reason: { type: 'string' }, fix_hint: { type: 'string' } },
  required: ['refuted', 'reason'],
}

const LENSES = [
  { key: 'state-machine', prompt: `Lens: STATE MACHINE, TIMERS AND RACES. Walk every path through steppedAside / visible / show() / hide() /
     rebuildWindows() / stop() / startWatching() / checkReveal() / the three delayed checks / screen-parameter changes /
     Desktop Items Hidden-Visible / Turn Off and On / Quit while revealed / labelMode or View Options changes while revealed /
     reloadAndRelayout while revealed (does it order windows front?) / applyViewOptions. Look for: windows ordered front
     during a reveal, windows never coming back, a timer that survives stop() or is scheduled twice, retain cycles,
     the delayed checks firing after stop(), double toggles (click then double-click on the wallpaper, a click in an icon-window gap
     followed by the shield), a reveal toggled OFF by our own click when the user only wanted to deselect during a reveal
     (can our windows even receive clicks then?), and the rename commit/hover clear ordering.` },
  { key: 'detection', prompt: `Lens: DETECTION ROBUSTNESS AND SYSTEM SEMANTICS. Scrutinise DesktopReveal.isRevealed: false positives (Launchpad,
     Mission Control, app Expose, the Dock's own bar or magnification, Notification Centre, screen savers, fullscreen Spaces,
     Stage Manager strips, multiple displays of different sizes, scaled/HiDPI modes where CG bounds vs NSScreen frame
     might differ, mirrored displays) and false negatives (layer values other than 18, Dock level constant, window owner
     name localisation: is kCGWindowOwnerName "Dock" in every language?). Scrutinise clickRevealsDesktop: key names and
     defaults, CFPreferences caching, reading another app's domain. Scrutinise toggle(): dlopen handle leak per call,
     calling convention, thread, what happens if the symbol exists but the Dock is restarting. Consider what a wrong
     answer costs in each direction and whether the code degrades safely.` },
  { key: 'interaction-cost', prompt: `Lens: CLICK SEMANTICS, COST AND CLAIMS. Check the plain-click detection in ShieldView and DesktopView+Mouse against
     Finder's behaviour: right-click, control-click, double-click, a click that ends a rename, a click that collapses a Stack,
     a click while a context menu or Quick Look is open, drag threshold, the double-click forwarding path in ShieldView
     (downPoint stays nil), clicks on the second display. Check the idle-cost story: a 1 Hz timer with tolerance on the main
     run loop in .common mode, ~1 ms per check, plus 4 Hz while revealed; is anything heavier than claimed (e.g. NSScreen
     enumeration, CFPreferencesAppSynchronize on every click)? Compare with what README.md / docs/CONCEPTS.md /
     docs/FEASIBILITY.md currently promise ("no timers at rest", "Not offered: click the wallpaper to reveal desktop") and
     list every statement that the change makes false.` },
]

phase('Review')
const results = await pipeline(
  LENSES,
  l => agent(`${CONTEXT}\n\n${l.prompt}\n\nReport only defects you can point to at a file:line with a concrete failure scenario.
     At most 5 findings, most severe first. Return an empty list if you find nothing real.`, { label: `review:${l.key}`, phase: 'Review', schema: FINDINGS }),
  (r, l) => parallel((r?.findings ?? []).slice(0, 5).map(f => () =>
    parallel([0, 1].map(k => () => agent(`${CONTEXT}\n\nA reviewer (${l.key} lens) claims this defect:\n${JSON.stringify(f, null, 2)}\n\n
       Try hard to REFUTE it by reading the actual code. Default to refuted=true if you cannot confirm the exact failure
       scenario from the code and the measured facts above. If it stands, give a one-line fix_hint.`,
       { label: `verify:${l.key}:${k}`, phase: 'Verify', schema: VERDICT })))
      .then(vs => { const ok = vs.filter(Boolean); const stands = ok.filter(v => !v.refuted).length; return { ...f, lens: l.key, votes: ok, confirmed: stands >= 1 && stands >= Math.ceil(ok.length / 2) } })))
)

phase('Critic')
const flat = results.flat().filter(Boolean)
const confirmed = flat.filter(f => f.confirmed)
const critic = await agent(`${CONTEXT}\n\nThree reviewers covered: ${LENSES.map(l => l.key).join(', ')}.
   Confirmed so far:\n${JSON.stringify(confirmed.map(f => ({ file: f.file, line: f.line, title: f.title })), null, 2)}\n
   What is MISSING? Name at most 3 concrete, verifiable defects or gaps nobody covered (read the code; point to file:line).
   Return an empty list if the review looks complete.`, { label: 'critic', phase: 'Critic', schema: FINDINGS })
log(`${flat.length} raw findings, ${confirmed.length} confirmed, critic added ${(critic?.findings ?? []).length}`)
return { confirmed, rejected: flat.filter(f => !f.confirmed).map(f => ({ title: f.title, file: f.file, line: f.line, reasons: f.votes.map(v => v.reason) })), critic: critic?.findings ?? [] }
export const meta = {
  name: 'review-compact-grid',
  description: 'Adversarially review the compact-grid / calibration change in QuietDesk (4 lenses, 2 skeptics per finding, completeness critic)',
  phases: [{ title: 'Review' }, { title: 'Verify' }, { title: 'Critic' }],
}

const CONTEXT = `
You are reviewing an UNCOMMITTED change in the SwiftPM package at <repo> (a macOS AppKit
menu-bar utility "QuietDesk": it hides Finder's desktop icons and draws them itself in borderless panels; names
appear on hover). Run \`git diff\` in that directory to see the change, and read any file you need with cat/sed
(Sources/QuietDesk/*.swift, Tests/QuietDeskTests/LayoutTests.swift). Do NOT modify files. Do NOT run the app
(no \`open\`, no launching QuietDesk binaries); \`swift build\` is fine if you need it.

What the change does:
1. Grid calibration (Layout.swift, GridMetrics.from): a third measured Finder data point at text size 12:
   icon 32 / spacing 1 -> 48 x 60 pt cells (previously the formula gave 46 x 62). Existing points must still hold:
   icon 36 / spacing 26 -> 84 x 82; icon 36 / spacing 1 -> 50 x 66. New formula: width = max(icon+13+1.36*spacing,
   4*textSize+1.36*(spacing-1)) rounded; height = icon + (2+info)*round(rawLineHeight) + (icon>=36 ? 2 : 0) + 0.64*(spacing-1).
2. "Compact grid" (ViewOptions.compactGrid, default true, View Options checkbox): while Item Labels are On Hover or
   Hidden and the layout is sorted (not manual/Finder positions), GridMetrics.from(options:compact:true) reserves no
   label rows: cellHeight = icon + 13 + 0.64*(spacing-1), labelLines = 0, labelRect height 0, labelOnBottom forced
   true. The hovered/selected/focused name is drawn as a pill (expandedLabelRect) over the neighbours, drawn last.
   Neighbour reveal (hoverReveal radius) is disabled in compact mode (neighbours(of:) returns []).
   OverlayController.currentMetrics() decides compactness from options.compactGrid, labelMode != .always and
   model.isManual; labelMode didSet now calls applyViewOptions(); seedLocalPositionsIfNeeded keeps the non-compact grid.
3. Hover animation (DesktopView.animateHoverIn): a 120 ms Timer at 60 Hz sets hoverProgress 0->1 and invalidates
   the hovered cell; drawLabel(.hovered) offsets the pill by 3*(1-p) pt and scales alpha by p. Timer must never
   outlive the hover or run at idle.
4. Rename field is now max(cellWidth+12, 120) wide, centred and clamped to the view.
5. ViewOptionsWindow: "Compact grid while names are hidden" checkbox; hoverReveal popup disabled when compact
   applies; AppDelegate.setLabelMode refreshes the panel if visible.
6. Tests: SelfTest.swift, LayoutTests.swift, ScenarioTest.swift rounds ("compact grid off/on", "names always visible").

Invariants that matter to the product: icons must be clickable exactly where they are drawn (cellIndex(at:) uses
iconRect inset -4 or labelRect); tracking areas (updateTrackingAreas) drive hover; cells didSet resets hover/selection
by URL; redraw uses reach(of:) and invalidate(i) = cellRect ∪ expandedLabelRect; manual layouts use Finder's icon
centres and write positions back to Finder via surface(reposition:); overflow wrap; label-right layout;
accessibility frames use cellRect; Quick Look, drag images and drops use iconRect; no timers at idle; the app must
never crash on relayout (index out of range) and must restore the native desktop.
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
  { key: 'geometry', prompt: `Lens: GEOMETRY AND HIT-TESTING. Check every consumer of labelRect/cellRect/iconRect/labelLines/labelLineHeight
     in compact mode: cellIndex(at:), rubber band selection, tracking areas, expandedLabelRect placement (does the pill
     cover the next row's icon and is that acceptable / does it clip at the view bottom or edges), reach(of:) and
     invalidate(i) (is every pixel the pill can touch invalidated, including the 3 pt animation rise), rename field
     placement, drag image frames, drop targets (folderCell(at:)), Quick Look zoom rect, accessibility frames,
     keyboard navigation by col/row, label-right layout combined with compact, item info line. Also verify the
     calibration arithmetic for all three data points by hand and look for rounding traps at other icon/text sizes.` },
  { key: 'layout-modes', prompt: `Lens: LAYOUT MODES AND STATE. Check currentMetrics() decisions across: sorted vs manual (Finder positions,
     local positions, snapToGrid), overflow wrap, seedLocalPositionsIfNeeded (must produce Finder-grid positions),
     Layout.windowRegion / window frames when the grid changes size, labelMode didSet ordering (views may not exist,
     model may be nil, called during init?), applyViewOptions vs reloadAndRelayout paths, the ViewOptions dictionary
     migration (old settings without compactGrid), "Use Finder's Settings" resetting, the panel's enable states,
     and whether turning Item Labels to Always/Hover from the menu relayouts correctly and keeps selection/hover sane.` },
  { key: 'animation', prompt: `Lens: ANIMATION, TIMERS, REDRAW. Check animateHoverIn: timer lifecycle on rapid hover changes, on cells didSet
     (hoverIndex reset to nil while a timer runs -> invalidate(h) with a stale/valid index?), on window close/stop
     (retain cycles, weak self), on --render (simulateHover then renderPNG after 3 s), on hover clearing paths
     (clearHover, mouseExited, app activation). Does hoverProgress ever stay < 1 for a non-hover draw path? Are
     .selected/.focused pills unaffected? Is CACurrentMediaTime available (import QuartzCore/AppKit)? Is the timer
     added to .common mode a problem during menu tracking or drags (needless CPU)? Idle CPU must stay at zero.` },
  { key: 'tests-docs', prompt: `Lens: TESTS AND CONSISTENCY. Check the new SelfTest/XCTest checks compute the expected numbers with the real
     NSFont metrics (system font 12 pt: ascender 11.45, descender -2.86, leading 0 -> raw 14.31), that ScenarioTest's new
     rounds are meaningful (compact off/on, names always/hover) and cannot fail spuriously on the CI fixture desktop
     (macos-15 runner, fixture folder with 3 folders and 4 files, Stacks by Date Added), that nothing in the diff
     contradicts README.md / docs (e.g. claims of "no timers", Finder-identical grid), and that the View Options
     panel text and tooltips are accurate. Also look for Swift 6.1 / macOS 14 SDK compile hazards (CI uses Xcode's SDK).` },
]

phase('Review')
const results = await pipeline(
  LENSES,
  l => agent(`${CONTEXT}\n\n${l.prompt}\n\nReport only defects you can point to at a file:line, with a concrete failure scenario.
     Cosmetic style is not a finding. Return an empty list if you find nothing real.`, { label: `review:${l.key}`, phase: 'Review', schema: FINDINGS }),
  (r, l) => parallel((r?.findings ?? []).slice(0, 6).map(f => () =>
    parallel([0, 1].map(k => () => agent(`${CONTEXT}\n\nA reviewer (${l.key} lens) claims this defect:\n${JSON.stringify(f, null, 2)}\n\n
       Try hard to REFUTE it by reading the actual code (git diff, and the files). Default to refuted=true if you cannot
       confirm the exact failure scenario from the code. If it stands, give a one-line fix_hint.`,
       { label: `verify:${l.key}:${k}`, phase: 'Verify', schema: VERDICT })))
      .then(vs => ({ ...f, lens: l.key, votes: vs.filter(Boolean), confirmed: vs.filter(Boolean).filter(v => !v.refuted).length >= 1 && vs.filter(Boolean).filter(v => !v.refuted).length >= Math.ceil(vs.filter(Boolean).length / 2) }))))
)

phase('Critic')
const flat = results.flat().filter(Boolean)
const confirmed = flat.filter(f => f.confirmed)
const critic = await agent(`${CONTEXT}\n\nFour reviewers looked at this change through these lenses: ${LENSES.map(l => l.key).join(', ')}.
   Confirmed findings so far:\n${JSON.stringify(confirmed.map(f => ({file: f.file, line: f.line, title: f.title})), null, 2)}\n
   What is MISSING? Name at most 3 concrete, verifiable defects or gaps nobody covered (read the code; point to file:line).
   Return an empty list if the review looks complete.`, { label: 'critic', phase: 'Critic', schema: FINDINGS })
log(`${flat.length} raw findings, ${confirmed.length} confirmed, critic added ${(critic?.findings ?? []).length}`)
return { confirmed, rejected: flat.filter(f => !f.confirmed).map(f => ({ title: f.title, file: f.file, line: f.line, reasons: f.votes.map(v => v.reason) })), critic: critic?.findings ?? [] }
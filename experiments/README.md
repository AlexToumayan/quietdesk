# Experiments

**In plain words.** These are the small programs we ran on the real Mac to settle questions that documentation could not answer: does this setting really hide the icons, which window gets a click on a transparent pixel, will Finder accept tiny label text, where does Finder think the icons are. Each one is reversible and touches the live desktop for a few seconds at most; each section says what question it answers, how to run it, what it changes, and what happened on macOS 26.6.2. The ideas behind them are explained in [../docs/CONCEPTS.md](../docs/CONCEPTS.md).

The scripts in this directory are the throwaway probes that produced the measurements in
[docs/FEASIBILITY.md](../docs/FEASIBILITY.md), sections 3 and 4 (experiments E1–E12). They were written
during the QuietDesk build session, one per question, and are kept so that every claim in the feasibility
document can be re-run. None of them is part of the app. Each one is reversible; the ones that touch the
live desktop do so for a few seconds and put it back. Results below are what was observed on the session
machine: macOS 26.6.2 (build 25G83), Finder 26.4, Apple Silicon, Command Line Tools with Swift 6.1 and the
macOS 15.4 SDK, two displays (built-in 1728x1117 pt @2x with a 33 pt menu bar; external 1920x1080 @1x
placed above it), desktop sorted by Date Added with Stacks on, icon size 36, text size 12, grid spacing 26,
148 items, iCloud Desktop sync on.

## Index

| Script | Experiment | Question it answers | Touches the live desktop |
|---|---|---|---|
| [probe.swift](probe.swift) | groundwork for E1, E4 | Which permissions are already granted, what the displays are, what the desktop window levels are and which windows sit there | No (read-only) |
| [probe2.swift](probe2.swift) | E1 | Every window Finder owns, plus every window below the normal level, on or off screen | No (read-only) |
| [lowwin.swift](lowwin.swift) | E1, E8 | Compact, diff-friendly list of Finder, WindowManager, Dock and sub-zero-level windows | No (read-only) |
| [hide-toggle.sh](hide-toggle.sh) | E1, E8 | Does `StandardHideDesktopIcons` apply live, does Finder relaunch, and what appears in the window list while it is set | Yes, about 2 s hidden |
| [hovertest.swift](hovertest.swift) | E4 | Does a transparent window at the desktop-icon level order above Finder's, what hit tests return, and does tracking fire with `ignoresMouseEvents` on | Yes, 16 s, red square on the main display, cursor warps |
| [alphatest4.swift](alphatest4.swift) | E6 | Is there an alpha threshold below which a point is treated as transparent for hit testing | Yes, under 1 s |
| [alphatest5.swift](alphatest5.swift) | E11 (E10 ordering) | Same, with a non-activating `NSPanel` as the upper window | Yes, under 1 s |
| [positions.applescript](positions.applescript) | E2 | What Finder's scripting dictionary reports for the desktop's view options and every item's position | No (read-only; Automation consent) |
| [textsize.applescript](textsize.applescript) | E3 | Does Finder accept a label text size of 4 | Attempts a change; Finder rejects it |
| [textsize10.applescript](textsize10.applescript) | E3 | Does Finder accept 10, and apply it live | Yes, 2 s at text size 10 |
| [dsstore_iloc.py](dsstore_iloc.py) | E5 | Are the icon positions stored in `~/Desktop/.DS_Store` usable | No (parses a copy; refuses the live file) |
| [reveal-trigger.swift](reveal-trigger.swift), [reveal-probe.swift](reveal-probe.swift), [reveal-events-probe.swift](reveal-events-probe.swift) | E14 | Can Show Desktop be started without a permission, are hidden items re-shown while the desktop is revealed, and does any event announce a reveal | Yes, windows slide aside for a few seconds |

Experiments E7, E9, E10 and E12 (layout reproduction, resource use, the panel level trap) were measured
with the app itself and its `--self-test` mode; they have no standalone script here.

## Conventions

| Fact | Value | Where it comes from |
|---|---|---|
| `kCGDesktopWindowLevel` | -2147483623 | SDK header `CGWindowLevel.h`; printed by probe.swift |
| `kCGDesktopIconWindowLevel` | -2147483603 | Same; Finder's desktop windows were measured at this level (E1) |
| QuietDesk's overlay level | -2147483602 (icon level + 1) | E8, E10 |
| `CGWindowListCopyWindowInfo` bounds | Global top-left origin, y down; the external display above the built-in one reports `-103,-1080 1920x1080` | probe output |
| `NSScreen` / `NSWindow` points | Bottom-left origin, y up; hovertest converts with `screen.frame.height - y` | AppKit |
| Building a Swift probe | `swiftc -O -o NAME NAME.swift` (no Xcode needed) | all six compile with no warnings on Swift 6.1 |
| Running an AppleScript | `osascript NAME.applescript` | first run prompts for Automation → Finder, attributed to the terminal app |

Binaries built here are ignored by [.gitignore](.gitignore).

## probe.swift

**Question.** Before any experiment: which permissions does the process already have (without prompting),
what are the display frames and scale factors, what numeric values do the desktop window levels have, and
which windows currently sit at or just above the desktop-icon level?

**Build and run.** `swiftc -O -o probe probe.swift && ./probe`

**What it changes.** Nothing. `AXIsProcessTrusted`, `CGPreflightScreenCaptureAccess` and
`AEDeterminePermissionToAutomateTarget(..., askUserIfNeeded: false)` all report without prompting.

**Result on 26.6.2.** Levels: desktop -2147483623, desktop icon -2147483603, normal 0. Two screens: the
built-in Retina display at scale 2 (1728x1117 pt, visible height 1084 pt, so a 33 pt menu bar) and the
external display at scale 1 (1920x1080 pt, frame origin y = 1117, i.e. above the built-in one). The
on-screen list at and just above the desktop-icon level contained only Dock, Wallpaper and Window Server
windows: no Finder window was reported on screen at that moment. That gap is why probe2.swift (all windows,
on or off screen) was written next; Finder's two desktop windows appear there. Window names are absent
without Screen Recording, which the experiments never requested. Permissions, as recorded in the session
log (they are not in the feasibility document): `AXIsProcessTrusted` false, `CGPreflightScreenCaptureAccess`
false, Automation → Finder status -1744 (would prompt). For a bare executable macOS attributes these to the
parent terminal process.

## probe2.swift and lowwin.swift

**Question.** What does the full window list look like below the normal level, including off-screen
windows, so that a change can be diffed?

**Build and run.** `swiftc -O -o probe2 probe2.swift && ./probe2` and
`swiftc -O -o lowwin lowwin.swift && ./lowwin | sort`

**What they change.** Nothing.

**Result on 26.6.2** (from the `before.txt` capture used by E1/E8; window numbers omitted):

| Owner | Level | Windows | Bounds | Note |
|---|---|---|---|---|
| Window Server | -2147483626 | 23 | 2560x1440, 1920x1080, 1728x1117, 1x1 | backstop windows, 2 on screen |
| Wallpaper | -2147483625 | 1 | 1920x1080 | external display |
| loginwindow | -2147483625 | 1 | 0x0 | |
| Dock | -2147483624 | 5 | 1920x1080 / 1728x1117 | wallpaper hosts, one per display on screen |
| Dock | -2147483622 | 3 | 1920x1080 | |
| **Finder** | **-2147483603** | **2** | **1920x1080 at -103,-1080; 1728x1117 at 0,0** | **the desktop icon windows, one per display** |
| Window Server | -2147483602 | 6 | 1920x91, 2056x38, 1728x94 | menu-bar-height strips |
| Finder | 0 | 9 | 1920x30, 1728x33, 64x64 | off screen |
| Dock | 20 | 1 | 1728x1117 | off screen |
| Finder | 103 | 1 | 59x18, alpha 0.1 | off screen |

## hide-toggle.sh

**Question.** Does writing `com.apple.WindowManager StandardHideDesktopIcons = true` (the key behind
System Settings › Desktop & Dock › "Show Items › On Desktop") hide Finder's desktop items live, without a
Finder relaunch, and what changes in the window list while the key is set?

**Build and run.** `swiftc -O -o lowwin lowwin.swift && ./hide-toggle.sh [work-dir]`. The script compiles
`lowwin` itself if it is missing.

**What it changes.** Captures the key's current value (or notes that it is absent), writes `true`, waits
2 s, restores the captured value (or deletes the key), waits 2 s. The desktop items disappear for about
two seconds. The restore is registered as an `EXIT` trap and `INT`/`TERM`/`HUP` are routed through it, so
Ctrl-C or a failing command still restores. Finder's process id is recorded before and after. The three
window lists (`before.txt`, `during.txt`, `after.txt`) are left in the work directory.

**Result on 26.6.2 (E1, E8).**

| Check | Observed |
|---|---|
| Items hidden | Within about 2 s of the write, no Finder restart |
| Finder's desktop windows | Both stayed in the list at level -2147483603, unchanged |
| Finder's pid | Unchanged |
| `before → during` diff | Exactly one added line: `owner=WindowManager layer=-2147483603 onscreen=true bounds=0,0 1728x1117 alpha=1` |
| `before → after` diff | Identical |

The added window is a full-screen WindowManager window on the built-in display at the desktop-icon level.
Hit tests land on it while the key is set, which is why QuietDesk draws at icon level + 1 (E8). Restoring
the key removes it.

## hovertest.swift

**Question.** Three things about a transparent, borderless window placed at exactly the desktop-icon
level: (1) does it order above Finder's desktop window when shown later; (2) what does
`NSWindow.windowNumber(at:belowWindowWithWindowNumber:)` return at an opaque point and at a transparent
point; (3) do `NSTrackingArea` enter/exit events and `mouseMoved` still arrive after
`ignoresMouseEvents = true`?

**Build and run.** `swiftc -O -o hovertest hovertest.swift && ./hovertest`, then move the mouse over the red
square when the script asks (twice, 5 s each). Total run time 16 s; the process quits itself.

**What it changes.** Shows a full-screen transparent window on the main display with a red 120x120 pt
square at (200, 500) pt from the top-left corner, labelled "QuietDesk test", for 16 s. Warps the cursor between the square and a
clear area four times per phase and returns it to its original position. Nothing persists. Two literals are
tied to the session machine: the clear test point `(600, 560)` assumes no icon there (on the session desktop
the grid fills from the top-right), and phase 3 calls `order(.above, relativeTo: 61)`, where 61 was the
window number of Finder's built-in-display desktop window; read the current number from `lowwin` first.

**Result on 26.6.2 (E4).**

| Phase | Observed |
|---|---|
| Ordering | The test window orders in front of Finder's desktop window at the same level once shown |
| Hit test, opaque point | Returns the test window |
| Hit test, fully transparent point | Returns Finder's desktop window (the test window is skipped) |
| Tracking with `ignoresMouseEvents = true` | Enter/exit still fired on the cursor warps (`entered=1 exited=1` in both warp phases) |
| `mouseMoved` and the global monitor | Counted 0 in every phase: the warps produced no mouse-moved events, and no mouse movement was recorded during the two "move the mouse" phases either (`entered=0 exited=0 moved=0`) |
| Phase 3: `ignoresMouseEvents = false`, then `order(.above, relativeTo: 61)` | Recorded as `inside-square -> window 61`, i.e. the hit test at the opaque point returned Finder's desktop window, not the test window. The feasibility document does not use this phase, and the session did not analyse it further; it is listed here because it was observed |

The tracking row is what made "hover on a click-through window" plausible; the transparent-point row is the
documented hit-testing rule for windows with transparency at the point.

## alphatest4.swift

**Question.** Is there an alpha value above zero below which a pixel still counts as transparent for hit
testing? If so, a near-invisible shield could not be used to catch clicks.

**Build and run.** `swiftc -O -o alphatest4 alphatest4.swift && ./alphatest4`

**What it changes.** Shows two 1000x700 pt borderless windows of its own at the desktop-icon level for about
0.7 s: B, opaque grey everywhere, below A, which has an 80x80 red square drawn at alpha 0.9 (the output
labels it "opaque red square"), eight 60x60 patches at alpha 1, 4, 16, 64, 128, 200, 250 and 255 of 255,
and is transparent elsewhere. For each test point it walks the
hit-test chain downward from the top and prints whether A is hit or skipped. Quits itself.

**Result on 26.6.2 (E6).**

| Point | Chain (as recorded: `A > B` or `B`) |
|---|---|
| Red square (alpha 0.9) | A > B |
| Fully transparent | B (A skipped) |
| Alpha 1/255 | A > B |
| Alpha 4, 16, 64, 128, 200, 250, 255 / 255 | A > B, each one |

There is no threshold above zero: one part in 255 is enough to be hit. QuietDesk's shield window is a single
colour layer at alpha 1/255 because of this measurement.

An earlier version of this test (alphatest3, not kept) probed points on Finder's real desktop window and
searched for a 60x60 region not covered by any application window; across 22 attempts it found none, so its
results said nothing about alpha and were discarded. The two-window design above removes the dependency on
what else is on screen.

## alphatest5.swift

**Question.** The same alpha question when the upper window is a non-activating `NSPanel`
(`.nonactivatingPanel`), which QuietDesk needs so that the overlay can take keyboard focus while Finder
stays the active application.

**Build and run.** `swiftc -O -o alphatest5 alphatest5.swift && ./alphatest5`

**What it changes.** Same as alphatest4; the upper window is an `NSPanel`. Note the order in `makePanel`:
`isFloatingPanel = false` is set before `level`, because setting `isFloatingPanel` rewrites `level`. The
app's first panel version set them the other way round and spent a 12 s run above application windows
(E10) before the order was fixed and the `level` setter guarded.

**Result on 26.6.2 (E11).** With `ignoresMouseEvents` left at its default, the panel behaves like the plain
window: the red square and the alpha 1/255 patch hit A, a fully transparent point passes to B. The session
ran this script as `./alphatest5 | head -4`, so only those three points were recorded for the panel; the
patches from 4/255 upward were exercised but their output was not kept. The second half of E11 (setting
`ignoresMouseEvents = false` explicitly makes the panel receive clicks everywhere in its frame, transparent
pixels included) was measured in the app itself, not by this script; it matches the behaviour Apple
described in the AppKit 10.3 release notes, and QuietDesk sets the property to `false` on purpose.

## positions.applescript

**Question.** Can Finder's scripting dictionary supply the desktop layout? It reads the desktop's
`icon view options` (icon size, text size, label position, arrangement, item info, icon preview), the item
count, and `{name, desktop position, class}` of every item in one request.

**Run.** `osascript positions.applescript`. The first run asks for Automation → Finder consent.

**What it changes.** Nothing; it only reads. The output lists the name of every item on the desktop, so it
is not reproduced here.

**Result on 26.6.2 (E2).**

| Check | Observed |
|---|---|
| Round trips | 148 items returned by one Apple event |
| View options | icon size 36, text size 12, label position bottom, arrangement reported as "not arranged" (Finder's `earr` enumeration has no Date Added value), icon preview on |
| Positions | Do not match the visible sorted grid; one folder visible in column 5 of the built-in display reported y = -811 |
| Stacks | Files inside Stacks are listed individually |
| Volumes | A mounted disk image appears with class `disk` |

Verdict: `desktop position` is stale on a desktop that Finder sorts itself. QuietDesk reads and writes it
only while Finder's desktop is set to Sort By None or Snap to Grid.

## textsize.applescript and textsize10.applescript

**Question.** Finder's View Options menu offers text sizes 10–16. Does the scripting property enforce the
same range, or can labels be shrunk below it (a possible way to make them effectively disappear)?

**Run.** `osascript textsize.applescript` then `osascript textsize10.applescript`.

**What they change.** `textsize.applescript` tries to set the desktop label size to 4, waits 4 s and sets it
back. `textsize10.applescript` sets it to 10, waits 2 s and sets it back, returning `{original, readback,
restored, icon size}`. If the first script's `set` fails, nothing was changed, so nothing needs restoring.

**Result on 26.6.2 (E3).**

| Script | Observed |
|---|---|
| textsize (4) | Finder raises error -10000; the value stays at 12 |
| textsize10 (10) | Accepted; labels visibly shrink at once and return after 2 s; returns `{12, 10, 12, 36}` |

Verdict: the range is enforced and applied live; labels cannot be shrunk away.

## dsstore_iloc.py

**Question.** Finder stores icon centres in `~/Desktop/.DS_Store` as `Iloc` records. Are they current and
complete enough to use as a layout source?

**Run.** Copy the file first; the script opens its input read-only and refuses any path inside `~/Desktop`,
so it can never write there.

```
cp ~/Desktop/.DS_Store "$TMPDIR/Desktop.DS_Store"
python3 dsstore_iloc.py --types "$TMPDIR/Desktop.DS_Store"       # add --no-names to hide item names
```

**What it does.** Parses the `Bud1` header, the allocator's block table and table of contents, the `DSDB`
superblock and the B-tree nodes, decoding all eight record types (`long`, `shor`, `bool`, `blob`, `type`,
`ustr`, `comp`, `dutc`), and prints every `Iloc` record as `x y trailing-bytes name`. The format is
undocumented by Apple; the layout follows the reverse-engineered description in
[Mac::Finder::DSStore](https://metacpan.org/dist/Mac-Finder-DSStore/view/DSStoreFormat.pod) and the
[ds_store](https://ds-store.readthedocs.io/en/latest/index.html) package.

**Result on 26.6.2 (E5), re-run on the session copy while writing this README.**

| Check | Observed |
|---|---|
| File | 102404 bytes, 27 allocator blocks, one TOC entry `DSDB`, B-tree of 25 nodes and 2 levels |
| Records | 724 (matches the DSDB count), 148 distinct item names |
| `Iloc` records | 58, for 148 items |
| Other structures | `bwsp` 52, `dilc` 147, `icvp` 10, `lg1S` 87, `lsvC` 23, `lsvp` 23, `moDD` 87, `modD` 87, `ph1S` 87, `vSrn` 63 |
| Coordinates | x on 65 + 110·k (k = 0–5), y on 46 + 126·k up to y = 6850, plus one record at (15, 15) |
| Trailing bytes | 51 records end in `ff ff ff ff ff ff 00 00`; 7 carry non-zero values in the last two bytes |

The coordinates describe a left-to-right arrangement on a 110x126 pt pitch that runs far below the
1117 pt display; the live desktop fills from the top-right on an 84x82 pt pitch (E7). The records are
therefore both incomplete (58 of 148) and stale. The trailing-bytes row also refines the format note:
DSStoreFormat.pod gives the padding as "6 bytes 0xff and 2 bytes 0?" with a question mark, and this file
shows the last two bytes are not always zero.

## reveal-trigger.swift, reveal-probe.swift, reveal-events-probe.swift

**Question (E14):** can an app start macOS's "reveal desktop" without a permission, does the
system re-show Finder's hidden items while the desktop is revealed, and is there any event that
says a reveal started or ended?

**What they do:** `reveal-trigger.swift` asks the Dock to toggle Show Desktop through
`CoreDockSendNotification("com.apple.showdesktop.awake")`, a private symbol looked up with
`dlsym`. `reveal-probe.swift` listens to every distributed and workspace notification while it
toggles a reveal on and off and prints the Dock, WindowManager and Finder windows at the desktop
levels in each state. `reveal-events-probe.swift` puts a transparent panel at the desktop-icon
level + 1 (like QuietDesk's shield), registers for its occlusion, expose, screen and move
notifications and for seven candidate Darwin notifications, and toggles a reveal.

**Run:** `swift experiments/reveal-probe.swift` (each script slides your windows aside for a few
seconds and leaves the desktop as it was). To see finding 1, hide desktop items first
(`hide-toggle.sh`) and look at the screen during the reveal.

**Result:** the trigger works with no permission; the old `Mission Control 1` command line does
nothing on macOS 26. Finder's hidden items are re-shown for the whole reveal, however it was
started. No notification of any kind fires, and the panel sees no occlusion change; the only
observable is one screen-sized Dock window per display at layer 18 while revealed (and
WindowManager's click-catchers gone). One window-list check takes about 1 ms.

## Hypotheses these experiments rejected or corrected

| Hypothesis | Script | Outcome |
|---|---|---|
| Labels can be hidden by shrinking Finder's text size below the menu's range | textsize.applescript | Rejected: error -10000 |
| Finder's `desktop position` can drive an overlay on a sorted desktop | positions.applescript | Rejected: stale values |
| `.DS_Store` `Iloc` records can drive the layout | dsstore_iloc.py | Rejected: 58 of 148, old layout |
| A near-transparent shield might fall under an alpha threshold and be skipped | alphatest4.swift | Rejected: 1/255 is hit |
| Alpha behaviour can be measured against Finder's real window | alphatest3 (discarded) | Invalid: no uncovered test region in 22 attempts; replaced by the two-window design |
| Writing the hide key may report success without changing the visible desktop on Tahoe (Raycast extension pull request, verified by its author on 26.4.1), so a `CreateDesktop` + Finder relaunch would be needed | hide-toggle.sh | Not on 26.6.2: applies in about 2 s, same Finder pid, no relaunch |
| A window at exactly the desktop-icon level is enough to receive clicks | hide-toggle.sh, hovertest.swift | Corrected: WindowManager adds its own window at that level while items are hidden, so the overlay sits at level + 1 |
| `ignoresMouseEvents = true` also stops tracking-area events | hovertest.swift | Not observed: enter/exit fired on warps |
| A non-activating `NSPanel` keeps the level it was given | alphatest5.swift, app (E10) | Corrected: `isFloatingPanel` rewrites `level`; set it first |

## Not included

- `alphatest`, `alphatest2`, `alphatest3`: superseded attempts at E6 (see alphatest4).
- The app-level measurements E7, E9, E10 and E12: reproduce them with the app's `--self-test` mode and
  `ps` sampling as described in the feasibility document.
- Any experiment output that lists desktop item names.

## Sources

- Apple, Change Desktop & Dock settings (macOS 26): https://support.apple.com/guide/mac-help/mchlp1119/26/mac/26
- Apple, desktop view options: https://support.apple.com/guide/mac-help/mchlp2209/mac
- Apple, `CGWindowLevelKey.desktopIconWindow`: https://developer.apple.com/documentation/coregraphics/cgwindowlevelkey/desktopiconwindow
- Apple, `NSWindow.windowNumber(at:belowWindowWithWindowNumber:)`: https://developer.apple.com/documentation/appkit/nswindow/windownumber(at:belowwindowwithwindownumber:)
- Apple, `NSWindow.ignoresMouseEvents` and the archived AppKit release notes: https://developer.apple.com/documentation/appkit/nswindow/ignoresmouseevents , https://developer.apple.com/library/archive/releasenotes/AppKit/RN-AppKitOlderNotes/index.html
- Apple, `NSTrackingArea.Options.activeAlways`: https://developer.apple.com/documentation/appkit/nstrackingarea/options-swift.struct/activealways
- Finder scripting dictionary: `/System/Library/CoreServices/Finder.app/Contents/Resources/Finder.sdef`
- Community, WindowManager defaults keys: https://mynixos.com/nix-darwin/options/system.defaults.WindowManager
- Community, Raycast issue listing the WindowManager keys (in its comments): https://github.com/raycast/extensions/issues/8599
- Community, Raycast pull request that found the key unreliable on 26.4.1 and reverted to `CreateDesktop` (merged 2026-05-28): https://github.com/raycast/extensions/pull/28009
- Community, `.DS_Store` format: https://metacpan.org/dist/Mac-Finder-DSStore/view/DSStoreFormat.pod , https://ds-store.readthedocs.io/en/latest/index.html
- Community, Hammerspoon canvas note on desktopIcon + 1: https://github.com/Hammerspoon/hammerspoon/blob/master/extensions/canvas/libcanvas.m

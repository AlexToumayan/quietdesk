# Changelog

## Unreleased

- Compact grid (View Options, on by default while names are On Hover or Hidden): no room is reserved
  for names, so the desktop packs as densely as the icons allow, and a name materialises over its
  neighbours when you point at its item (120 ms fade and rise). Off keeps Finder's grid, which is
  what "Names on hover: neighbours" and "Show item info" need (both are off while the compact grid
  is in use); manually arranged desktops always keep Finder's grid.
- Grid calibration: a third measured point (icon 32, tightest spacing: 48 × 60) corrected cells that
  were 2 pt too narrow and 2 pt too tall at that size; the two earlier points still match exactly.
  Labels are drawn at Finder's line pitch and show one line where only one fits (the tightest
  spacings), as Finder does, instead of running into the row below.
- View Options: "Show iCloud status" switch (hide the cloud glyphs, useful on tight grids).
- View Options: "Names on hover" (only the item / the item and its neighbours / a wider area).
- Fixed: a hover label could stay on screen after a window opened on top of the desktop without
  the pointer moving (e.g. after double-clicking a file); hover now ends when another app comes
  forward or the desktop loses keyboard focus.
- Stacks: one open at a time; clicking the wallpaper, another item, or Escape collapses it (Finder behaviour).
- Fixed: double-clicking an item while a Stack was open collapsed the Stack on the first click, the
  layout shifted under the pointer, and the second click opened whatever had moved there (or
  nothing, when the icon window itself had shrunk away). The second click now goes to the item the
  first click landed on, wherever it moved. Found by the new scenario test.
- Fixed: any View Options change (for example the iCloud switch) silently replaced "follow Finder's
  setting" for Sort By and Stacks with explicit values; only the Sort By / Stack By popups change them.
- Double-click on a Stack toggles it once and no longer also opens a Finder window.
- Overlay windows: the icon window (desktop icons +2) and the shield (+1) now sit on two distinct
  window levels, so no reordering by AppKit can put the shield above the icons.
- View Options panel sizes itself to its content.
- Fixed: while QuietDesk itself was the active app (after View Options, Quick Look or a menu), a
  desktop click did not hand the menu bar back to Finder; it now passes activation the macOS 14 way.
- Diagnostics: `--scenario-test` replays real click sequences through the overlay windows (346
  checks across 19 View Options and activation states) and runs in CI on a fixture desktop;
  `--debug-log` writes an event trace to `~/Library/Logs/QuietDesk/debug.log` for bug reports.
- Documentation: figures for measurements, review outcomes, research verification, grid
  calibration, workflow sizes and the window-level stack (`scripts/make-charts.py`).

## 0.9.1 — 2026-09-17

- New app icon (slashed eye, matching the menu-bar icon); menu-bar icon shows an open eye while off.
- Menu: "Turn QuietDesk On/Off" at the top; "Quit QuietDesk" kept separate; "Show View Options…".
- View Options window: Stack By, Sort By, icon size, grid spacing, text size, label position
  (bottom/right), item info, icon preview; applied live; "Use Finder's Settings" re-imports.
- Right-click on the wallpaper now mirrors Finder's desktop menu (Get Info, Change Wallpaper,
  Use Stacks, Group Stacks By, Sort By, Show View Options).
- Fixed: Finder's freshly changed View Options were read from a stale cache; the grid formula is now
  calibrated at two spacing settings (tight grids match).
- "Show item info" (item counts, sizes, free space) and label-on-the-right layouts.

## 0.9.0 — 2026-09-17

First public build. Feature-complete desktop layer; hands-on validation still in progress
(see docs/VALIDATION-CHECKLIST.md).

- Menu-bar utility: Enabled, Desktop Items (Visible/Hidden), Item Labels (Always / On Hover / Hidden),
  Sort By, Stacks, Launch at Login, Bring Finder Forward on Desktop Click.
- Desktop layer at desktop-icon level + 1 with a bitmap-free shield; native items hidden through the
  "Show Items › On Desktop" setting, restored on disable, quit, SIGTERM and after crashes.
- Finder-matching sorted grid, manual layouts (Finder positions or app-local), Stacks with in-place
  expansion, previews, iCloud glyphs, tag dots, alias badges.
- Selection (click, modifiers, rubber band, keyboard, type-to-select), open, Open With, spring-loaded
  folders, rename, Quick Look, Get Info, Duplicate, Make Alias, Compress, Copy/Paste/Move, New Folder,
  Trash, Eject, Show Original, Tags, Share, undo/redo, drag-out with count badge, drops of files and
  file promises.
- No downloads of cloud-only files (process I/O policy plus per-file checks before thumbnails).
- Idle cost measured at 0 CPU over 40 s, about 75 MB resident.

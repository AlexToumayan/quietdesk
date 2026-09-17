# Changelog

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

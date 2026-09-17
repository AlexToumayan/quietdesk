# Manual validation checklist

Run with `build/QuietDesk.app` (so permission prompts are attributed to the app), release build.
Tick each line with the result and the macOS version. Items marked (P) were exercised programmatically;
everything else is unverified until ticked.

## Alignment and rendering
- [ ] `.build/release/QuietDesk --no-hide --test-seconds 30`: overlay icons coincide with Finder's icons (no visible doubling). (P: order and cell centres matched a screenshot.)
- [ ] Enable: native icons disappear and QuietDesk's appear with no gap in which neither is visible.
- [ ] Labels: On Hover shows the full name promptly; moving away hides it; no flicker; long names wrap and stay on screen at the right and bottom edges.
- [ ] Always Visible matches Finder's two-line, middle-truncated labels closely.
- [ ] Hidden shows no labels; VoiceOver still reads item names.
- [ ] Light and dark wallpapers: labels readable (white text with shadow; hover pill).
- [ ] External 1x display and Retina display both render crisp icons.
- [ ] Icon previews appear for local images/PDFs/documents when Finder's "Show icon preview" is on; a cloud-only (evicted) file keeps its generic icon and is NOT downloaded (check its cloud glyph stays "download").
- [ ] iCloud glyphs: not-downloaded, uploading and current items show the expected symbols; they update when a download finishes.
- [ ] Tag colour dots appear for tagged items; alias badge on aliases.

## Selection and keyboard
- [ ] Single click selects; Cmd-click toggles; Shift-click extends; click on wallpaper deselects.
- [ ] Rubber-band selection from wallpaper and from between icons.
- [ ] Arrow keys move selection through the grid; Escape clears; Cmd-A selects all.
- [ ] Type-to-select: typing the first letters of a name selects that item.
- [ ] With "Bring Finder Forward on Desktop Click" ON: after clicking an icon, the menu bar shows Finder AND arrow keys still move QuietDesk's selection. If keys go elsewhere, turn the option off and note it.
- [ ] Cmd-N opens a new Finder window; Cmd-Shift-N creates "untitled folder" on the desktop.

## Opening, files, undo
- [ ] Double-click opens files, folders and apps; Cmd-O and Cmd-Down open the selection.
- [ ] Open With ▸ lists the apps with the default first; choosing one opens the file there.
- [ ] Return on a selected item starts renaming with the stem selected; Return commits, Escape cancels, clicking elsewhere commits; renaming to an existing name shows an error and keeps editing; a slow second click on a selected name also starts renaming.
- [ ] Cmd-D duplicates ("X copy"), Cmd-L makes "X alias", Compress creates "X.zip" via Archive Utility.
- [ ] Cmd-C then Cmd-V copies to the desktop; Cmd-Option-V moves; paste from a Finder window works both ways.
- [ ] Cmd-Delete moves to Trash; Finder's Put Back works; Cmd-Z brings it back; Shift-Cmd-Z redoes.
- [ ] Cmd-Z undoes rename, duplicate, alias, new folder, move, copy and tag changes.
- [ ] Cmd-I opens Finder's Get Info window (first use asks for Finder automation permission; denying shows a clear message).
- [ ] Space / Cmd-Y opens Quick Look on the selection; arrow keys move to the next item; Space closes.
- [ ] Share… shows the sharing picker.
- [ ] Tags ▸ toggles a colour; dot appears; Finder shows the same tag.
- [ ] Eject on a mounted disk image ejects it; the icon disappears.
- [ ] Show Original on an alias reveals the original in Finder.

## View Options and menus
- [ ] Menu › Turn QuietDesk Off restores the native desktop and keeps the eye icon (open); Turn On brings the layer back (slashed).
- [ ] Right-click on the wallpaper shows New Folder, Get Info, Change Wallpaper, Use Stacks, Group Stacks By, Sort By, Item Labels, Show View Options, Paste.
- [ ] Show View Options opens the panel; moving Grid spacing re-flows the grid live; the tightest setting matches Finder's tightest grid; icon size and text size apply live.
- [ ] Label position Right: names sit beside icons in wide cells; hover, selection and rename still work.
- [ ] Show item info: folders show item counts, files sizes, the disk image free space.
- [ ] Use Finder's Settings returns everything to Finder's current values (change Finder's View Options while QuietDesk is off, turn it on: the grid matches).

## Stacks and sorting
- [ ] Single click on a stack expands it in place (items appear after it, others shift); click again collapses.
- [ ] Sort By ▸ Name / Kind / Date Modified reorder the grid; "Finder's Setting" returns to Finder's order.
- [ ] Stacks ▸ Off shows files individually; Group by Kind builds Images / PDF Documents / … stacks.
- [ ] Sort By ▸ None (Finder Positions) on a desktop that uses manual positions: icons appear where Finder had them; dragging an icon moves it and Finder shows it there after disabling QuietDesk. (Needs a manually arranged desktop; not tested here.)

## Drag and drop
- [ ] Drag an item to a Finder window (move within volume), to an app (opens/inserts), to the Dock's Trash.
- [ ] Multi-item drag shows an item-count badge.
- [ ] Drop a file from a Finder window onto the desktop (moves into ~/Desktop) and onto a folder icon (moves into the folder); never overwrites an existing name.
- [ ] Drop an image from Safari or a message from Mail onto the desktop (file promise): the file appears.
- [ ] Hover over a folder while dragging for about a second: the folder opens in Finder (spring-loading).
- [ ] Adding, removing or renaming an item in ~/Desktop (via Finder or a save dialog) updates the overlay within a second.
- [ ] Mounting/unmounting a disk image or USB drive adds/removes its icon.

## macOS integration
- [ ] Show Desktop (F11 / trackpad spread): app windows slide away, overlay stays; clicking icons works.
- [ ] Mission Control: overlay is not shown as a window; returns intact.
- [ ] Switching Spaces: overlay present on every Space; nothing duplicated.
- [ ] A full-screen app: overlay is not visible over it; visible again on exit.
- [ ] Stage Manager on: overlay behaviour and the "Show Items in Stage Manager" switch; document what happens.
- [ ] Sleep and wake: overlay intact, still responsive, no duplicate windows.
- [ ] Unplug and replug the external display: overlay rebuilds; nothing left behind on the wrong screen.
- [ ] Desktop widgets (if any): not covered by the overlay; still clickable.
- [ ] Finder relaunched (Force Quit › Finder › Relaunch): native icons stay hidden; overlay unaffected.
- [ ] Cmd-H with QuietDesk active does not hide the overlay.
- [ ] Launch at Login from the .app: enabling succeeds (or shows the signature error); the app starts after a reboot.

## Restoration and safety
- [ ] Enabled off: native icons return immediately, exactly as before.
- [ ] Quit and Restore Desktop: same.
- [ ] `kill -9` the app: native icons stay hidden (expected); launching the app again restores them at startup, before anything else happens.
- [ ] Toggle "Show Items › On Desktop" in System Settings while QuietDesk runs: QuietDesk leaves your change alone on disable.
- [ ] `defaults read com.apple.WindowManager StandardHideDesktopIcons` after quit: key absent (or your previous value).
- [ ] No file on the Desktop changed name, date, flags or iCloud status (`ls -lO@ ~/Desktop` before and after).

## Performance (P, partially)
- [ ] Activity Monitor, 5 minutes idle: 0 % CPU, no wakeups beyond the baseline, memory stable.
- [ ] While hovering across all icons for 30 s: brief CPU, back to 0 % immediately after.
- [ ] Energy tab shows no "Preventing Sleep" and no GPU use at idle.

# My validation checklist

**In plain words.** This is the list I work through by hand before I am willing to call a version done.
Some things a computer can check for itself, and those live in the automated tests. The things below
cannot be checked that way. Whether a name appears promptly when I point at an icon, whether dragging a
file feels the way it feels in Finder, whether my desktop comes back exactly as it was: for those I have
to look at my own screen and decide.

**How I run it.** I use `build/QuietDesk.app`, the packaged app rather than the bare program, so that any
permission prompt macOS shows is attributed to QuietDesk and not to my terminal, and I build it for release
rather than for debugging. Then I go down the list and tick each line with what I saw and which version of
macOS I saw it on.

**What the notes in brackets mean.** Some lines end with a note like `(P: ...)` or `(Automated ...)`. That
means a program has already exercised the behaviour, and the note says what it checked. I still look at
those by hand, because an automated check can only confirm the thing it was told to look for. A line with
no such note is unverified until I have ticked it myself, and so is any part of the Performance section
that its `(P, partially)` mark does not cover.

## Alignment and rendering

Does QuietDesk's desktop look like the one it replaced?
- [ ] `.build/release/QuietDesk --no-hide --test-seconds 30` (this flag always uses Finder's grid, not the compact one): overlay icons coincide with Finder's icons (no visible doubling). (P: order and cell centres matched a screenshot.)
- [ ] Enable: native icons disappear and QuietDesk's appear with no gap in which neither is visible.
- [ ] Labels: On Hover shows the full name promptly; moving away hides it; no flicker; long names wrap and stay on screen at the right and bottom edges.
- [ ] Always Visible matches Finder's two-line, middle-truncated labels closely.
- [ ] Hidden shows no labels; VoiceOver still reads item names.
- [ ] Light and dark wallpapers: labels readable (white text with shadow; hover pill).
- [ ] External 1x display and Retina display both render crisp icons.
- [ ] Icon previews appear for local images/PDFs/documents when Finder's "Show icon preview" is on; a cloud-only (evicted) file keeps its generic icon and is NOT downloaded (check its cloud glyph stays "download").
- [ ] iCloud glyphs: not-downloaded, uploading and current items show the expected symbols; they update when a download finishes.
- [ ] Tag colour dots appear for tagged items; alias badge on aliases.

## Reveal desktop

macOS can slide every window aside to show the bare desktop. While that is happening, Finder puts its own
icons and names back, so QuietDesk has to step out of the way and then return. These lines check that the
handover is clean in both directions, with no moment where two sets of icons are visible at once.

- [ ] Click the wallpaper: every window slides aside (with System Settings › Desktop & Dock › "Click wallpaper to reveal desktop" set to Always); Finder's own icons with names are what you see, with no doubled icons; click the wallpaper or a window edge: the windows return and QuietDesk's quiet desktop is back within about a quarter of a second. (Automated once: `--scenario-test --with-reveal`.)
- [ ] F11 (or fn-F11), the spread gesture and a Desktop hot corner behave the same; doubled icons, if any, last up to about a second and a half (the check runs once a second with half a second of tolerance).
- [ ] With Stage Manager off and the setting on "Only in Stage Manager", a wallpaper click only deselects; the same with QuietDesk's own menu switch (Click Wallpaper to Reveal Desktop) off.
- [ ] With another app in front (say Safari), one click on the wallpaper both brings Finder forward and reveals the desktop, and the windows stay aside until the next click.
- [ ] Start renaming an item, type a name that already exists, press F11: the rename ends quietly (no alert in the middle of the reveal).
- [ ] Dragging a rubber band on the wallpaper, right-clicking it, or Command-clicking it never reveals the desktop.
- [ ] Mission Control and Launchpad: QuietDesk's icons are hidden for their duration and return afterwards.

## Selection and keyboard

Every way of picking an item, with the mouse and without one.

- [ ] Single click selects; Cmd-click toggles; Shift-click extends; click on wallpaper deselects.
- [ ] Rubber-band selection from wallpaper and from between icons.
- [ ] Arrow keys move selection through the grid; Escape clears; Cmd-A selects all.
- [ ] Type-to-select: typing the first letters of a name selects that item.
- [ ] With "Bring Finder Forward on Desktop Click" ON: after clicking an icon, the menu bar shows Finder AND arrow keys still move QuietDesk's selection. If keys go elsewhere, turn the option off and note it.
- [ ] Cmd-N opens a new Finder window; Cmd-Shift-N creates "untitled folder" on the desktop.

## Opening, files, undo

The section that touches real files. Nothing here may lose or damage anything, and anything that changes a
file has to be undoable in the same way Finder would undo it.

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

The controls themselves, and whether changing one of them quietly breaks another.

- [ ] Menu › Turn QuietDesk Off restores the native desktop and keeps the eye icon (open); Turn On brings the layer back (slashed).
- [ ] Right-click on the wallpaper shows New Folder, Get Info, Change Wallpaper, Use Stacks, Group Stacks By, Sort By, Item Labels, Show View Options, Paste.
- [ ] Show View Options opens the panel; moving Grid spacing re-flows the grid live; the tightest setting matches Finder's tightest grid; icon size and text size apply live.
- [ ] Label position Right: names sit beside icons in wide cells; hover, selection and rename still work.
- [ ] Show item info: folders show item counts, files sizes, the disk image free space.
- [ ] Use Finder's Settings returns everything to Finder's current values (change Finder's View Options while QuietDesk is off, turn it on: the grid matches).
- [ ] After each View Options change (iCloud status, names on hover, icon size, spacing, text size, label position, item info, previews, Use Finder's Settings): a single click still expands a Stack and a double-click still opens a folder. (Automated: `--scenario-test`, ALL PASSED on 2026-09-17.)
- [ ] With a Stack open, double-click a folder elsewhere: the Stack collapses and that folder opens, not whatever moved under the pointer. (Automated in `--scenario-test`.)
- [ ] Changing an unrelated View Option (e.g. iCloud status) keeps Sort By / Stacks on "Finder's Setting" if that is what they were.
- [ ] Compact grid on (default): icons pack with no label rows; pointing at an item fades its name in over the row below; clicking, double-clicking, renaming (Return) and rubber-band selection still work on the dense grid; unchecking it returns to Finder's grid with room under every icon.
- [ ] With QuietDesk off, Finder's grid at icon 32 / tightest spacing has 48 pt columns and 60 pt rows; turning QuietDesk on with Compact grid off keeps every icon exactly where it was.

## Stacks and sorting

Finder's own ways of tidying a desktop, now done by QuietDesk. The order on screen has to match what Finder
would have shown.

- [ ] Single click on a stack expands it in place (items appear after it, others shift); click again collapses.
- [ ] Sort By ▸ Name / Kind / Date Modified reorder the grid; "Finder's Setting" returns to Finder's order.
- [ ] Stacks ▸ Off shows files individually; Group by Kind builds Images / PDF Documents / … stacks.
- [ ] Sort By ▸ None (Finder Positions) on a desktop that uses manual positions: icons appear where Finder had them; dragging an icon moves it and Finder shows it there after disabling QuietDesk. (Needs a manually arranged desktop; not tested here.)

## Drag and drop

Moving things by hand, into the desktop and out of it, plus the desktop noticing changes I made somewhere
else.

- [ ] Drag an item to a Finder window (move within volume), to an app (opens/inserts), to the Dock's Trash.
- [ ] Multi-item drag shows an item-count badge.
- [ ] Drop a file from a Finder window onto the desktop (moves into ~/Desktop) and onto a folder icon (moves into the folder); never overwrites an existing name.
- [ ] Drop an image from Safari or a message from Mail onto the desktop (file promise): the file appears.
- [ ] Hover over a folder while dragging for about a second: the folder opens in Finder (spring-loading).
- [ ] Adding, removing or renaming an item in ~/Desktop (via Finder or a save dialog) updates the overlay within a second.
- [ ] Mounting/unmounting a disk image or USB drive adds/removes its icon.

## macOS integration

The places where a layer drawn on top of the desktop usually goes wrong: other Spaces, full-screen apps,
Stage Manager, a display unplugged mid-session, Finder restarted underneath it.

- [ ] Show Desktop (F11 / trackpad spread): see "Reveal desktop" above (QuietDesk steps aside; Finder's own items show).
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

The section that matters most to me. However QuietDesk stops, whether I switch it off, quit it, or it is
killed outright, my real desktop has to come back and my files have to be untouched.

- [ ] Enabled off: native icons return immediately, exactly as before.
- [ ] Quit and Restore Desktop: same.
- [ ] `kill -9` the app: native icons stay hidden (expected); launching the app again restores them at startup, before anything else happens.
- [ ] Toggle "Show Items › On Desktop" in System Settings while QuietDesk runs: QuietDesk leaves your change alone on disable.
- [ ] `defaults read com.apple.WindowManager StandardHideDesktopIcons` after quit: key absent (or your previous value).
- [ ] No file on the Desktop changed name, date, flags or iCloud status (`ls -lO@ ~/Desktop` before and after).

## Performance (P, partially)

I asked for an app I could forget was running, so this is where I check that it costs me nothing while I am
not using it.

- [ ] Activity Monitor, 5 minutes idle: 0 % CPU, memory stable, and no wakeups beyond the reveal
  check, which is one look at the window list a second (about 1 ms) for as long as QuietDesk is on.
- [ ] While hovering across all icons for 30 s: brief CPU, back to 0 % immediately after.
- [ ] Energy tab shows no "Preventing Sleep" and no GPU use at idle.

# The ideas behind QuietDesk, explained simply

This page explains, in plain language, every idea the project depends on. No prior knowledge
of macOS internals is assumed. Each section says what the thing is, why it mattered here, and
what we found out. If you want the citations and the exact experiments, they are in
[FEASIBILITY.md](FEASIBILITY.md) and [experiments/](../experiments/README.md); this page is the
version you can read on a phone.

---

## 1. Your desktop is a window, not a place

When you look at your Mac's desktop you see three things stacked on top of each other: the
wallpaper, the icons, and your open app windows. Each of those is a separate *window* in the
technical sense, even the wallpaper.

- The **wallpaper** is a full-screen window drawn by a system helper (the same program that runs
  the Dock).
- The **icons** are drawn by **Finder**, in a transparent full-screen window that sits just above
  the wallpaper. When you click an icon, you are clicking Finder's window.
- **App windows** sit above both.

Why it matters: QuietDesk does not change Finder. It asks macOS to make Finder's icon window
empty (using an ordinary switch in System Settings), and then draws its own icons in a new
transparent window in the same place. Finder, Finder windows, Spotlight and the menu bar carry
on exactly as before; only the "layer of icons on the wallpaper" changes hands.

## 2. Windows live on numbered sheets of glass

Imagine a stack of glass sheets. Each window is drawn on one sheet, and the sheets have numbers.
Higher numbers are closer to you. macOS reserves a few numbers for special things: the wallpaper
sheet is at the very bottom, the desktop-icons sheet is one step above it, and normal app
windows are far above both.

QuietDesk draws on a sheet **one step above the desktop-icons sheet**. That keeps it below every
app window (it can never cover your work) and above Finder's icon window and, as it turned out,
above an invisible window macOS adds when icons are hidden (see §4).

We found one trap here: the kind of window we use (a "panel") silently moves itself to the
normal-app sheet if two settings are applied in the wrong order. For twelve seconds during a
test, the overlay sat on top of every app. The fix was a one-line ordering change and a guard;
the lesson is recorded as experiment E10.

## 3. How a click finds its window

When you click, macOS walks down the stack of sheets from the top and stops at the first window
that is *there* at that point. "There" is subtle: for windows with transparent parts, a fully
transparent pixel does not count, so the click falls through to whatever is underneath. A pixel
that is even one step away from fully transparent (1 on a 0–255 scale) counts as solid. We
measured this by stacking two windows of our own and asking macOS which one a click would hit.

There is also a switch on each window that can override the rule in both directions: set one
way, the window ignores clicks everywhere; set the other way explicitly, it catches clicks
everywhere, transparent pixels included. Apple described this three-way behaviour in release
notes in 2003 and it still holds on macOS 26. QuietDesk uses the "catch everywhere" setting on
purpose (§4 explains why), and keeps a second, invisible full-screen window underneath as a
safety net.

## 4. The "Show Items" switch and the invisible click-catcher

System Settings › Desktop & Dock has a switch, "Show Items › On Desktop". Turning it off hides
Finder's desktop icons instantly, without restarting Finder. QuietDesk flips the same switch
(it is stored as a preference key that Apple does not document, so the app captures the old
value first and puts it back on quit, and even after a crash on the next launch).

The surprise: while the switch is off, macOS adds an invisible full-screen window at the
desktop-icons level whose only job is to notice a click on the wallpaper and bring the native
icons back. If QuietDesk let wallpaper clicks fall through, every click on empty desktop would
make Finder's icons reappear underneath QuietDesk's. So while QuietDesk is enabled it owns every
click on the desktop, and provides the things a wallpaper click used to do (deselect, rubber-band
select, the right-click menu, drops) itself. The one thing it deliberately does not offer is the
"click the wallpaper to reveal the desktop" gesture.

## 5. Why the names could not simply be hidden

The obvious idea is to keep Finder's icons and just hide the names. We looked hard for a way and
each door was closed:

- There is no setting or programming interface for "hide desktop names". Apple's own user guide
  lists what the desktop view options can do (icon size, spacing, text size, label position) and
  hiding names is not among them.
- Finder can be scripted to change the label text size, but it refuses anything below 10 points
  (we tried 4 and got an error; 10 worked and was put back to 12).
- Finder's extension mechanisms (the ones apps like Dropbox use) can add badges and menu items,
  not change how names are drawn. Apple says so directly.
- Covering the names with wallpaper-coloured patches would need pixel-perfect copies of the
  wallpaper, which is impossible for animated or time-of-day wallpapers without screen recording.

So the only honest route was to draw the icons ourselves, and the rest of the project is about
doing that without breaking what the desktop already did.

## 6. Knowing where every icon belongs

Finder arranges a "Sort By" desktop in columns from the top-right corner downward, then leftward.
QuietDesk recomputes that order from the same information (dates, names, kinds) and the same
grid size, and the result matched the owner's real desktop icon for icon, including the date
Stacks. The cell size was measured from screenshots at three settings (icon 36 at two spacings,
icon 32 at the tightest); the third point turned up a 2-point error at icon 32 that the owner had
noticed by eye, which is a good reminder that "looks right" is a measurement too. Other settings
may be a few points off, which is documented.

**Why the grid can get denser.** Finder leaves two lines of room under every icon for its name.
Once names only appear on hover, that room is empty most of the time, so QuietDesk's "compact
grid" packs the icons as if there were no names at all and lets a name fade in over the row below
when you point at its item. The icons never move while you hover: a name that pushed its
neighbours away would also move the thing you were about to click, which is exactly the kind of
bug the scenario test exists to catch.

For desktops arranged by hand, Finder can be *asked* where each icon is, through its scripting
interface. We found that on a sorted desktop those stored positions are stale leftovers from
years ago (E2), which is why QuietDesk only uses them when Finder itself is in manual mode, and
keeps its own positions otherwise.

## 7. Permissions: the Mac asks before an app may look

macOS protects a few folders (Desktop, Documents, Downloads) and a few abilities (controlling
other apps, recording the screen, reading everything). An app gets a dialog the first time it
needs one, and the answer is remembered per app. QuietDesk needs:

- **Desktop folder access**, to list the names of the items to draw (never their contents).
- **Automation of Finder**, only when you use Get Info, open a new Finder window from the
  desktop, or drag icons around on a manually arranged desktop.

It does not need Accessibility or Screen Recording, the two broad permissions people are right
to be wary of. One quirk worth knowing: the app is signed with a throwaway ("ad-hoc") signature,
so macOS may ask again after you rebuild it, because it cannot prove the new build is the same
app.

## 8. Cloud-only files, and never downloading them by accident

With iCloud Desktop sync and "Optimize Mac Storage", some files on your desktop are only
placeholders: the name and icon are there, the contents are in the cloud and download the moment
anything reads the file. A desktop utility that reads files to draw them could quietly pull
gigabytes down.

QuietDesk closes this in two layers. It tells macOS, for the whole process, "never download a
placeholder for me" (a documented setting; a read of such a file fails instead). And because
preview thumbnails are made by a separate system helper that does not inherit that setting, the
app checks each file's local/placeholder status first and simply never asks for previews of
placeholders. Opening or Quick-Looking such a file does download it, the same as in Finder,
because that is what you asked for.

## 9. Asking Finder politely: Apple Events

Some things only Finder can do well: its Get Info window, a new Finder window, remembering where
you put an icon. macOS has a decades-old way for one app to ask another to do something ("Apple
Events", what AppleScript is built on). QuietDesk sends those requests from inside itself, in the
background, and treats "the user said no" as a normal answer with a clear message, never as a
crash.

## 10. Keyboard focus without stealing the stage

When you click a normal app's window, that app "activates": its name appears in the menu bar
and it takes keyboard input. If QuietDesk did that on every desktop click, the menu bar would
say "QuietDesk" instead of "Finder", which is not how a desktop feels.

The fix uses a special kind of window (a non-activating panel, the same trick Spotlight uses) that
can accept keyboard input without making its app the active one. On a desktop click, QuietDesk
brings Finder forward for the menu bar and keeps the keys for itself. This is the one behaviour
that could only be confirmed by a person at the keyboard, so it is a switch in the menu and the
first item on the validation checklist.

## 11. Doing nothing, measurably

"Efficient" is easy to claim and easy to check. The app has no timers and no loops at rest; it
only wakes up when macOS tells it something happened: the pointer entered an icon, a file
appeared on the Desktop, a disk was mounted, a display was plugged in, an iCloud status changed.
Redraws touch only the icon that changed.

We measured it the plain way: run the release build with the desktop taken over, do nothing for
40 seconds, and sample the process. Its CPU time did not move at all, and it held about 75 MB of
memory. The script to repeat this is `scripts/measure-idle.sh`.

## 12. Undo, and why file operations are careful

Every file action the desktop offers (rename, duplicate, alias, move, copy, trash, new folder,
tags) is recorded so that ⌘Z puts things back, and long copies run in the background so the
desktop never freezes. Two things the code review caught are worth knowing: copying a folder into
its own subfolder would have recursed until the file system gave up (Finder refuses this; now so
does QuietDesk), and a copy that fails halfway now cleans up its partial result and beeps instead
of leaving a folder that looks complete.

## 13. How the AI work was organized, in plain words

The whole thing was built in one session by one person directing an AI, and the AI in turn
delegated to short-lived helpers. Three habits made that work:

- **Research team plus fact-checkers.** Eight helpers each researched one question using Apple's
  own documentation. Eight other helpers then fetched every cited page and checked that it really
  said what was claimed, with instructions to assume "not supported" when in doubt. Several claims
  were corrected or downgraded that way before any code existed.
- **Builders in separate rooms.** Three parts of the app (previews, iCloud status, talking to
  Finder) were built by separate helpers who were each given an exact interface to fill in and a
  private scratch project to build it in, so they could not step on each other or on the main
  code. Each part was then checked by a skeptical reviewer before it was allowed in.
- **Reviewers plus skeptics.** Six reviewers each looked at the finished code through one lens
  (file safety, focus and events, idle cost, restoration, layout maths, module integration).
  Every finding they raised was handed to a separate helper told to assume it was false unless
  it could show the failure from the code. Fifteen real problems survived that filter and were
  fixed; one was rejected with a written reason.

The exact instructions given to each helper are in [PROMPTS.md](PROMPTS.md), and the outputs
they produced are under [evidence/](evidence/). The person stayed in charge of the decisions
that mattered: whether to build a custom desktop layer at all, and which icon to use.

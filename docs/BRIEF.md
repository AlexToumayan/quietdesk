# The brief

This is the product brief the project started from, reproduced verbatim (it was written by the
project owner as the opening prompt of an AI-assisted build session). Everything else in this
repository is an answer to it. See [CASE-STUDY.md](CASE-STUDY.md) for how it was carried out.

---

I want you to help me design and build a small, native, open-source macOS menu-bar utility that makes the desktop visually cleaner without making the computer less efficient or interfering with normal file management.

Please read this as a product brief, not just a request for a few settings. The user experience, performance constraints, and respect for existing macOS behavior are the core of the project.

## 1. The idea and why I want it

My Mac desktop contains many files, folders, and project directories. I like having these items immediately accessible, but having every filename visible all the time makes the desktop visually overwhelming.

I do NOT primarily want an app that organizes my files, moves everything into categories, or hides my entire desktop. The specific experience I originally wanted is:

My desktop icons remain visible in their usual locations, but their names appear only when I hover over them.

That would let me see a clean arrangement of icons against my wallpaper while still immediately identifying an item when I need it. The names should appear without clicking.

I also want simple controls for showing or hiding the desktop items entirely and for choosing whether their labels are always visible, visible on hover, or hidden.

The design philosophy is that a Mac should feel like a clean, powerful workhorse. This utility should quietly remove visual clutter without becoming another resource-hungry application I need to manage.

Think "small native presentation utility," not "desktop customization platform."

## 2. The interface I have in mind

The app should live in the macOS menu bar—the top bar where other small utilities and system controls live.

Use a restrained, native-looking menu-bar icon and a standard macOS menu. No permanent main window, floating dashboard, or Dock icon during normal operation.

A working menu structure could be:

```
[App Name]
────────────────────────────────
Enabled                         ✓

Desktop Items                  ▸
    Visible                    ✓
    Hidden

Item Labels                    ▸
    Always Visible
    On Hover                   ✓
    Hidden

────────────────────────────────
Launch at Login                 □
Quit and Restore Desktop
```

This is an illustrative structure, not a requirement to reproduce the exact wording or spacing.

Use "Desktop Items" to make it clear that the control applies to both files and folders. Do not introduce separate settings for every item type unless a real technical limitation requires it.

The intended behavior is:

Enabled: The utility applies my chosen presentation settings.

Disabled: The utility stops applying its presentation changes and restores the appropriate native desktop state. Its menu-bar control can remain available, but unnecessary observers, rendering, and other background work should stop.

Desktop Items — Visible: Show the desktop items.

Desktop Items — Hidden: Hide their visual presentation without deleting, moving, renaming, or changing the actual files.

Item Labels — Always Visible: Show names normally.

Item Labels — On Hover: Keep icons visible while revealing the relevant name on pointer hover. Also support keyboard selection and accessibility, as described below.

Item Labels — Hidden: Hide visual labels, while preserving actual filenames and accessibility information.

When desktop items are hidden, disable or clearly indicate that label settings are temporarily inapplicable. Remember the chosen label mode so that showing the items again restores that preference.

Keep version one this small. Do not add themes, icon packs, AI features, accounts, widgets, subscriptions, file organization tools, or a complex preferences window.

## 3. The most important constraint: preserve my actual desktop

This is a visual-presentation tool.

Do not rename files to blank or invisible Unicode characters. Do not remove extensions. Do not move files into a managed directory. Do not change hidden-file flags as a cosmetic workaround. Do not replace my files with aliases or reorganize my folders. Do not modify file contents or cloud-sync settings.

The app should affect the desktop presentation, not filename visibility throughout ordinary Finder windows.

I want my desktop to continue behaving like my desktop. Opening files, selecting items, dragging, keyboard navigation, context menus, and normal Finder operations should remain intact wherever possible.

Do not quietly replace all of this with a simplified launcher and describe it as equivalent.

## 4. Prove the difficult part before building the easy part

The small menu-bar interface is not the main uncertainty. The important question is whether the exact label behavior can be implemented safely and reliably.

First investigate the mechanisms actually available on my installed macOS version.

Distinguish clearly between:

- Documented public APIs.
- User-facing macOS settings that may or may not have a supported programmatic interface.
- Undocumented preferences or other version-sensitive behavior.
- A custom desktop surface that would render its own icons and labels.

Do not assume that a setting exists merely because it would be convenient. Do not assume Finder extensions or Finder Sync can arbitrarily change desktop filename rendering. Verify capabilities against current primary documentation and, where appropriate, a small reproducible experiment.

Do not build settings around imaginary functionality such as a presumed "hideDesktopLabels" API.

My preferred outcome is the smallest safe mechanism that preserves native Finder behavior.

If controlling native labels is not feasible within these constraints, explain the limitation specifically. Then evaluate the smallest credible alternative.

A native custom-rendered desktop layer is a possible alternative to investigate, not an automatic architectural decision. Before committing to it, explain which Finder interactions it would preserve, which it would need to recreate, what permissions it would require, and what maintenance or performance costs it introduces.

Do not spend days building a replacement file manager without first discussing that tradeoff.

Likewise, do not implement only an ordinary "hide all desktop icons" switch and present it as completion. The hover-only filename behavior is the distinguishing feature of this idea.

## 5. How hover-only labels should feel

Hovering over an icon should reveal that item's full name clearly and promptly. Moving away should hide it again, unless the item remains selected or keyboard-focused.

The interaction should feel native and predictable, not like a web tooltip with a distracting animation.

Avoid label flicker, overlapping text, and revealing adjacent items unintentionally. Handle long names, screen edges, different display scaling, and light or dark wallpaper backgrounds.

In On Hover mode, selected or keyboard-focused items should also reveal their names so that using the desktop does not require a mouse.

In Hidden mode, hiding visual labels must not remove filenames from accessibility information or interfere with commands that operate on the files.

Do not add continuous animation or a large collection of styling controls. Start with a readable, restrained appearance close to the existing desktop.

If a proposed implementation cannot support these interactions without interfering with normal selection or dragging, identify that in the prototype rather than hiding it until later.

## 6. Architecture preferences

Prefer Swift and native macOS frameworks, using AppKit and/or SwiftUI where they fit the actual requirements.

Choose the simplest architecture that satisfies the behavior. Do not turn this into an elaborate framework exercise.

I do not want Electron, a browser-based desktop widget, a bundled web runtime, a local web server, or a background AI service for this application.

Claude is helping write the software. The finished app should run independently, without requiring Claude or any other AI product.

Keep dependencies minimal and justified. Prefer system frameworks where practical.

Use straightforward local settings persistence. Do not add a database, background helper, launch agent, updater service, or privileged component unless there is a concrete requirement that cannot reasonably be met without it.

The app should run locally and should not require a server, login, account, analytics service, or subscription.

## 7. Performance is a product requirement

"Virtually no bottleneck" means the utility should spend almost all of its idle time doing no work.

I understand that no running application has literally zero overhead. Do not promise that. Design for near-zero idle CPU, stable and modest memory use, minimal disk activity, and no unnecessary GPU work, then measure the result.

Use event-driven behavior wherever practical.

For any app-owned icon views, investigate native pointer-entry and pointer-exit events rather than continuously polling the mouse position.

If the implementation needs to know when desktop contents change, investigate appropriate file-system notifications rather than repeatedly scanning the desktop.

Avoid recursive indexing of folder contents. Showing a folder icon should not require inspecting everything inside it.

Avoid repeated shell commands, subprocess creation, accessibility-tree scans, or file enumeration during hover interactions.

Do not generate thumbnails repeatedly when a cached icon would suffice. Keep caches bounded and invalidate only what changed.

Do not read file contents or request downloads of cloud-only files just to display their icons or names.

Only redraw or update the parts of the interface that actually changed. Do not maintain a constant rendering loop for a mostly static desktop.

When disabled, stop work that is no longer necessary. A menu-bar app that is switched off should not keep its full monitoring and rendering machinery running.

Measure performance using an appropriate release build and available profiling tools. Compare the normal desktop with the utility disabled, enabled and idle, and actively being used.

Report the test conditions and observed CPU, memory, disk, and rendering behavior. Do not invent performance numbers or treat "written in Swift" as proof of efficiency.

## 8. macOS integration and everyday reliability

Evaluate the approach against the ways a real Mac desktop is used.

Important scenarios include multiple displays, Retina scaling, display connection changes, Spaces, Mission Control, full-screen apps, Show Desktop, sleep and wake, Finder relaunch, and relevant desktop features such as stacks and Stage Manager.

Do not assume that a custom overlay will automatically behave correctly in these situations.

If a custom surface is necessary, pay particular attention to window layering. It must not sit above normal application windows, block unrelated desktop clicks, steal keyboard focus unexpectedly, or appear in places where the native desktop would not.

Check ordinary file interactions: double-clicking, keyboard activation, multiple selection, dragging items, context menus, and renaming. Clearly document any behavior that is not preserved.

The desktop may include cloud-synced items. Respect their existing locations and synchronization state.

These are validation requirements, not permission to build a huge feature set before proving the core idea.

## 9. Safety, permissions, and restoration

Use the least privilege necessary.

Do not require disabling System Integrity Protection, injecting code into Finder, patching system components, or installing privileged helpers for version one.

Do not request Accessibility, Screen Recording, Full Disk Access, or other broad permissions speculatively. Determine what the chosen implementation actually requires and explain each permission before introducing it.

Do not use screenshots or screen-reading as a default method of locating icons.

If an undocumented preference is proposed, explain its uncertainty, compatibility risks, and rollback mechanism. Do not silently present it as a supported API.

Do not restart Finder automatically without explaining the reason and obtaining approval when that would disrupt the session. Never restart it as part of ordinary hover behavior.

Before changing any relevant system preference, capture the state needed to undo the app's own change.

Disabling or normally quitting the utility should restore the presentation it is responsible for, rather than forcing a guessed "default." Account for the possibility that the user changes a preference outside the app while it is running.

Design a practical recovery path for crashes and force-quits. Do not claim that normal shutdown cleanup is guaranteed to run after an abrupt termination.

If persistent system settings are changed, record enough information to offer restoration on the next launch and provide a clear manual recovery procedure.

Never hide the native desktop until any necessary replacement is ready to display successfully. If activation fails, leave the user with a usable native desktop.

## 10. Free development and open-source distribution

I want to build this without paid dependencies and eventually publish the source so other people can use and improve it.

Keep the source understandable, the build process reproducible, and the repository easy for another developer to work with.

Separate local development from public app distribution. Explain any signing, notarization, or distribution considerations accurately, but do not make optional distribution infrastructure a prerequisite for proving the concept.

Do not add telemetry or network calls to the shipped app without an explicit requirement and my approval.

Suggest an appropriate open-source license rather than making licensing decisions silently. Licensing and branding should not distract from the first working prototype.

## 11. How I want you to work

Start by inspecting the actual development environment and any project files I give you. Verify the macOS version, available tooling, and repository structure rather than assuming them.

If no project exists, use a clean, dedicated project directory. Do not modify unrelated projects.

Research current official documentation for capabilities that matter to the architecture. Cite the sources supporting your feasibility conclusions and distinguish documentation from your own experimental findings.

Your first milestone is a feasibility assessment and the smallest reversible proof of the hover-label mechanism—not a polished menu with nonfunctional switches.

Explain the proposed approach in plain language, including what it changes, what it preserves, what permissions it needs, and what could break.

Proceed with safe, bounded prototyping when it fits this brief. Ask for a decision before making a material tradeoff, such as replacing native desktop interactions, relying on fragile private behavior, or requiring broad system permissions.

Do not repeatedly ask me about minor implementation details that you can resolve sensibly yourself.

After the mechanism is proven, build the minimal menu-bar application, add restoration behavior, test normal desktop interactions, and profile it.

If a required feature is unsupported, mark it clearly. Do not ship a control that appears to work while doing something different.

## 12. What I expect to receive

I want working source code and a buildable project, not just pseudocode or a conceptual explanation.

Include concise instructions for building and running the app, the supported and tested macOS versions, required permissions, known limitations, and how to disable, quit, recover, and uninstall it.

Include focused tests where practical, plus a manual validation checklist for behaviors that need real desktop interaction.

Report what you actually built and tested. Clearly distinguish working features, unverified assumptions, and incomplete work.

Keep the final implementation narrow:

A small menu-bar utility. A few understandable controls. Icons visible when I choose. Names visible only when useful. Actual files unchanged. Normal desktop behavior preserved as much as the verified approach allows. No unnecessary background work.

The project is successful when my workspace looks cleaner and I can otherwise forget the utility is running.

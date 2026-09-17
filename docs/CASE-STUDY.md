# How QuietDesk was built

**If you only read one paragraph.** One person wanted a Mac desktop where the icons stay but the
names only appear when you point at them. Nobody had built it, and it turned out there is no
switch for it anywhere in macOS. So the work went like this: first find out, with Apple's own
documents and small experiments, what the operating system will and will not allow; then stop and
let the person decide whether the only workable route (drawing the icons ourselves) was worth its
costs; then build it, have it torn apart by reviewers whose findings were fact-checked, fix what
survived, and measure the result. One human directed one AI, which delegated to about fifty
short-lived helpers in five organized rounds, all in a single session on 2026-09-16/17. This page
tells that story; the plain-language explanations of the ideas involved are in
[CONCEPTS.md](CONCEPTS.md).

**Start here:** [concepts](CONCEPTS.md) → [the brief](BRIEF.md) → [feasibility](FEASIBILITY.md) → [prompt library](PROMPTS.md) → evidence ([research](evidence/research.md), [experiments](../experiments/README.md), [modules](evidence/modules.md), [code review](evidence/code-review.md)) → [validation checklist](VALIDATION-CHECKLIST.md).

## 1. What the brief asked for, and why it worked as a prompt

The [brief](BRIEF.md) is a product document, not a feature list, and that is why it worked. It
told the AI what must never happen, what to prove before building, and how to be honest about
the result. Five properties made it a strong opening prompt:

1. **A non-negotiable invariant** ("preserve my actual desktop": no renames, moves, flags, aliases).
   Every later decision could be tested against it.
2. **Required distinctions** (documented API vs user-facing setting vs undocumented preference vs
   custom surface), which forced honest labelling of every mechanism.
3. **Milestone gating** ("prove the difficult part before building the easy part") and an explicit
   instruction to stop for a decision before a material tradeoff.
4. **Performance as a requirement with a measurement obligation**, including "do not invent numbers".
5. **Honesty requirements** ("clearly distinguish working features, unverified assumptions, and
   incomplete work"), which shaped every output schema downstream.

## 2. The shape of the work

In one sentence: survey the machine, research the rules, run experiments, stop for the human's
decision, build, review, fix, measure, hand over. The diagram shows the same thing.

```mermaid
flowchart LR
  B[Brief] --> S[Environment survey]
  S --> R[Research workflow<br/>8 topics x verifier]
  S --> E[Experiments E1-E12<br/>reversible, on the real desktop]
  R --> D{Decision memo<br/>custom layer or not?}
  E --> D
  D -->|owner: build it| P[Parity build<br/>lead agent]
  D -->|owner: build it| M[Module workflow<br/>3 implementers x reviewer]
  P --> C[Code review<br/>6 lenses x verifiers]
  M --> C
  C --> F[Fixes + self-test]
  F --> Q[Measurement + polish]
  Q --> V[Hands-on validation<br/>checklist, owner]
```

| Stage | Who | Output |
|---|---|---|
| Environment survey | lead | macOS 26.6.2, no Xcode, two displays, the owner's desktop settings, which permissions the session had ([FEASIBILITY §1](FEASIBILITY.md)) |
| Research | 8 researchers + 8 verifiers | Cited findings per mechanism, corrections, open questions ([evidence/research.md](evidence/research.md)) |
| Experiments | lead, on the live desktop with capture/restore | E1–E12: what Finder accepts, what the window server does, what WindowManager adds ([experiments/](../experiments/README.md)) |
| Decision | owner | "Build the custom layer to full parity, then test" |
| Parity build | lead + 3 module implementers + 3 module reviewers | 13 feature areas, three modules with harness-verified behaviour ([evidence/modules.md](evidence/modules.md)) |
| Code review | 6 reviewers + 21 verifiers | 15 confirmed defects fixed, 1 rejected, 28 minors triaged ([evidence/code-review.md](evidence/code-review.md)) |
| Measurement | lead | Idle: constant CPU time over 40 s, ~75 MB resident (`scripts/measure-idle.sh`) |
| Validation | owner | [VALIDATION-CHECKLIST.md](VALIDATION-CHECKLIST.md), demo video |

## 3. Five decisions, and the evidence behind each

Each row is a fork in the road, what was chosen, and the specific fact that forced the choice
(E-numbers are the experiments in [FEASIBILITY.md](FEASIBILITY.md)).

| Decision | Evidence that forced it |
|---|---|
| Native Finder cannot do hover-only labels; a custom layer is the only mechanism. | No API in AppKit or Finder's dictionary; Finder Sync cannot touch rendering (Apple docs); Finder rejects a scripted text size below 10 (E3); `desktop position` and `.DS_Store` are stale on a sorted desktop (E2, E5). |
| Hide native items with the same switch System Settings uses, not by relaunching Finder. | The setting applies live (E8 shows WindowManager reacting within two seconds); the `CreateDesktop` route needs Finder relaunches and removes drops and menus (research). |
| Put the overlay one level above the desktop-icon level and let it own every desktop click. | With items hidden, WindowManager inserts a full-screen click-catcher at the icon level that re-shows native icons on any wallpaper click (E8); at the same level it ordered above ours. |
| Use a non-activating panel so the menu bar can stay with Finder. | Documented AppKit behaviour; the keyboard-focus race with Finder's activation was flagged by review and mitigated with a one-shot re-assert, and is on the checklist. |
| Never let anything download a cloud-only file. | Apple TN3150 (process I/O policy); the thumbnail generator runs out of process, so eligibility is checked before any request (module harness proved `st_flags` unchanged). |

## 4. What the process caught

These are the things that would have reached a user if the reviewers and their fact-checkers had
not been part of the process.

- **Two blockers** the tests would not have found: a crash on relayout when the selection had more items than the new grid, and copying a folder into its own subfolder (a verifier reproduced 450 levels of recursion before the path limit).
- **A silent data hazard**: hiding native icons even when Desktop access had been denied, leaving an empty desktop with no explanation.
- **An architecture trap**: `NSPanel` resets its level when `isFloatingPanel` is set after `level`; a 12-second run put the overlay above application windows before the hit test exposed it (E10).
- **An undocumented three-state behaviour** of `ignoresMouseEvents` (E11), matching a sentence in AppKit release notes from 2003 that a verifier dug up.
- **A wrong assumption in a brief**: the iCloud module was asked for Spotlight metadata queries; the implementer measured that they carry no iCloud attributes here and proposed a documented alternative instead of complying.

## 5. What it did not do

Honesty about limits is part of the method, so here is what was deliberately not done or could
not be checked without a person at the keyboard.

- No sub-agent ever ran the app in live mode or changed a system preference; only the lead did, with capture and restore, for seconds at a time.
- Nothing was screenshotted (no Screen Recording permission); visual claims were verified by rendering the overlay offline into PNGs, and the owner's own screenshot was used to check the layout column by column.
- The hands-on checklist has not been run. Show Desktop, Mission Control, Stage Manager, sleep/wake, display changes and the keyboard-focus behaviour after a Finder activation are unverified as of v0.9.0.
- Manual (unsorted) desktops were implemented from Finder's dictionary and the module's calibration; the owner's desktop is sorted, so they were never exercised for real.

## 6. Numbers

| Workflow | Agents | Tokens | Tool calls | Wall clock |
|---|---|---|---|---|
| Feasibility research | 16 | 2.28 M | 1,336 | 26 min |
| Module implementation (two runs; the first hit a usage limit and was resumed with cached results) | 5 + 6 | 1.48 M | 265 | 58 min |
| Code review, five lenses | 18 | 2.13 M | 297 | 30 min |
| Code review, module integration | 4 | 0.60 M | 104 | 15 min |
| Evidence documentation (this repo's evidence pages) | 8 | 1.44 M | 215 | 19 min |

The lead agent's own work (survey, experiments, core implementation, integration, fixes, docs) is not
counted above. Source size at v0.9.0: about 4,700 lines of Swift, no third-party dependencies.

## 7. Reproduce

```bash
./scripts/build-app.sh            # build + bundle with Command Line Tools only
.build/release/QuietDesk --self-test
scripts/measure-idle.sh 40        # idle measurement, restores the desktop afterwards
```

The experiment scripts in [experiments/](../experiments/README.md) are the smallest reproductions of
each finding; each one says what it changes and restores it.

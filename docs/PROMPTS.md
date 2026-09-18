# Prompt library

**What this is.** When one AI delegates work to helper agents, the instructions it writes for
them are the whole job: a vague instruction produces vague work, and a missing rule produces a
helper that does something you did not want (like changing your desktop to test an idea). This
page collects the instructions written for the helpers in the five main rounds, laid out the
same way each time so you can see the pattern, and says what each one was for and what it caught.

Every helper in this project was driven by a prompt built from the same five parts. Each card below uses the same labels: Context, Objective, Guardrails, Output contract, Verification, plus a closing Result line that says what the prompt caught. A part that a whole family of helpers shares is shown once, in that family's first card. Each section starts with its script, its evidence page and what the run cost. The scripts as run are in [workflows/](workflows/), with local paths replaced by placeholders. Scripts 6 to 8 are the later review rounds; their cards are in section 5.

| Part | What it does |
|---|---|
| **Context** | The situation the agent is stepping into: machine, product, constraints already decided. Reused verbatim across a family of agents so they cannot drift. |
| **Objective** | One job, stated as a deliverable. |
| **Guardrails** | What the agent must never do, phrased as hard rules (no live desktop changes, no subprocesses, no git, no file writes outside a named directory). |
| **Output contract** | A fill-in-the-blanks form the helper must return. The program that runs the helpers rejects an answer that does not fit the form. Anything that is counted or filtered later is multiple choice, not free text (source kind, confidence, severity, verdict). In technical terms: a JSON Schema with enums. |
| **Verification** | A second, independent agent that reads the first one's output and tries to knock it down, with a default of "not supported / not real" when unsure. |

**Words used on this page.** *Lead*: the main AI session (the raw prompts call it "the orchestrator"). *Helper*: a short-lived agent given one job. *Lens*: the one kind of problem a reviewer looks for (the schema field is `dimension`). *Reviewer*: finds problems; in section 2 it also fixes them. *Verifier*: a second helper told to disbelieve a claim until it can prove it. The evidence pages also call verifiers "skeptics" or "fact-checkers".

Two rules for running the helpers applied throughout: **pipeline, not barrier** (each finished piece goes straight to its
verifier as soon as it is done), and **the human decides material tradeoffs** (the lead agent
stopped for a decision before replacing native desktop interactions, and again for the icon).

---

## 1. Feasibility research (8 topics, each verified)

Script: [1-feasibility-research.js](workflows/1-feasibility-research.js). Evidence: [evidence/research.md](evidence/research.md). Run: 16 agents, 2.28 M tokens, 1,336 tool calls, 26 minutes.

### 1.1 Shared context block

Every research and verification agent received the same preamble.

- **Context**: the product idea in two sentences; target machine (macOS 26.6.2, Finder 26.4, no Xcode, Swift 6.1); two displays; the test desktop's settings (sorted by date added, Stacks on, icon 36 / text 12 / spacing 26, cloud sync on).
- **Guardrails**: read-only documentation research; prefer primary Apple sources; developer.apple.com is JS-rendered, so fetch the `/tutorials/data/documentation/<path>.json` endpoint; local files may be read but no `defaults write`, no `killall`, no scripting of apps, nothing written outside a scratch directory; "Do not run experiments on the live desktop; the orchestrator does that."
- **Output contract**: every claim carries `source_kind`, a URL and a short paraphrase; confidence is `high` only when a primary Apple source states it directly; unknown means say so (`source_kind: none`), never guess; list open questions for experiments.

*Design note.* The ban on live experiments was deliberate: only one process should touch the real desktop, with capture-and-restore around every change. Research agents were confined to reading.

### 1.2 Topic researcher (×8)

- **Objective**: answer one mechanism question with cited findings.
- **Context**: the shared block from 1.1, plus a topic prompt listing the specific sub-questions and the sources to check first.
- **Output contract**: `{topic, summary, findings[{claim, source_kind ∈ {apple-developer-doc, apple-user-guide, apple-header-or-sdef, apple-wwdc-or-forum-staff, community, none}, url, evidence, confidence ∈ {high, medium, low}}], open_questions[], recommended_experiments[]}`.
- **Verification**: every finding goes to the skeptical verifier in 1.3.

| Topic | Question it had to settle |
|---|---|
| hide-desktop-items | Which supported or unsupported ways hide Finder's desktop items without touching files, and what survives (context menu, drops, click-to-reveal)? |
| finder-scripting-positions | Is Finder's `desktop position` a usable public interface? Coordinate system, behaviour under Sort By, Stacks, consent model, batching. |
| appkit-window-mechanics | Window levels, `ignoresMouseEvents`, transparent-region click-through, collection behaviours, tracking areas for inactive apps, agent apps and key windows. |
| finder-extension-limits | Can Finder Sync, File Provider, Quick Actions or Accessibility change label rendering? (Expected: no; prove it with citations.) |
| permissions-tcc | Which consents the design triggers, when they block, how ad-hoc signatures affect grants, Gatekeeper for local vs downloaded builds. |
| icons-files-cloud | Icon APIs vs file contents, dataless (cloud-only) files, useful URL resource keys, FSEvents vs dispatch sources, Finder's Date Added and Stacks rules. |
| prior-art | Open-source and commercial apps drawing at desktop level; their collection behaviours and reported pitfalls. |
| tahoe-changes | Anything in macOS 26 that changes the design; building a bundle with Command Line Tools only; menu-bar icon guidance. |

### 1.3 Skeptical verifier (×8)

- **Objective**: for every `high` or `medium` finding, fetch the cited URL and decide whether the source actually says that.
- **Guardrails**: "Default to `not-supported-by-cited-source` if the page does not say it." Also list what the researcher missed and what is overstated.
- **Output contract**: `{verdicts[{claim, verdict ∈ {supported, partially-supported, not-supported-by-cited-source, could-not-fetch}, note, better_url}], corrections[], missing[]}`.
- **Result**: a "high" claim about Finder Sync and the Desktop was corrected; a windowing claim was upgraded from community to primary (the verifier found the AppKit release notes the researcher had missed); several URLs were replaced with version-pinned ones. Details in [evidence/research.md](evidence/research.md).

---

## 2. Parallel module implementation (3 modules, each reviewed)

Script: [2-module-implementation.js](workflows/2-module-implementation.js). Evidence: [evidence/modules.md](evidence/modules.md). Run: two runs, because the first hit a usage limit; 5 + 6 agents, 1.48 M tokens, 265 tool calls, 58 minutes.

### 2.1 Shared rules

- **Context**: the project, the toolchain, and the fact that the lead is editing core files concurrently, so "the project may not build at any given moment — do not run `swift build` in the project, do not edit any existing file, do not touch git."
- **Guardrails**: the product's hard constraints restated as a list (never modify user files, never trigger cloud downloads, no polling at idle, no subprocesses, no broad permissions, bounded memory, public APIs only).
- **Guardrails (how to work)**: build the module in an isolated scratch SwiftPM package with a test harness (a small throwaway program that calls the module on real files, read-only, and prints what happened); only then copy the single file into the project; the module must have no dependency on other project types.

*Design note.* Giving each implementer an exact Swift interface to fill in (written by the lead first) made integration mechanical: stubs with the same signatures kept the core compiling until the real files landed.

### 2.2 Module implementer (×3)

| Module | Interface it had to implement | What the harness had to prove |
|---|---|---|
| ThumbnailCache | `thumbnail(for:size:scale:) -> NSImage?`, `onReady`, `invalidate`, `removeAll`, `cancelAll`, `isFullyLocal`, `isEligible` | Cloud-only files are never handed to QuickLook (the generator runs out of process and does not inherit the app's no-download policy); bounded concurrency; a rendered PNG. |
| CloudStatusMonitor | `init(directory:)`, `start`, `stop`, `status(for:)`, `onChange`, `resourceStatus(for:)` | Event-driven status for top-level items only; a 5 s live run with a histogram; nothing that reads contents. |
| FinderAutomation | `status()`, `readDesktopPositions`, `writeDesktopPosition`, `openInfoWindows`, `openNewWindow`, typed errors | Consent preflight off the main thread; one Apple event for all positions; correct quoting of arbitrary file names; observed coordinate ranges to settle the anchor question. |

- **Output contract**: `{module, file_written, interface, verified_by_running[], caveats[], not_verified[]}`.
- **Result**: the CloudStatusMonitor implementer measured that Spotlight metadata queries carry no iCloud attributes for the user's Desktop and deviated from the brief with a documented FSEvents / file-presenter / Progress design, exactly the kind of deviation the "say what you could not verify" rule is for.

### 2.3 Module reviewer (×3)

- **Objective**: re-derive the hard constraints against the finished file; verify API signatures against the SDK headers; compile it standalone in a fresh package; fix blockers and majors in place; report every change.
- **Output contract**: `{module, compiles_standalone, problems[{severity ∈ {blocker, major, minor}, description, fix_applied}], summary}`.
- **Result**: a cloud-download hole through 3D-model sibling files in the thumbnail eligibility list; positions paired by index from two separate Finder queries; a refresh pipeline that could stick after stop/start. All fixed before integration. Details in [evidence/modules.md](evidence/modules.md).

---

## 3. Adversarial code review (6 lenses, every finding verified)

Scripts: [3-code-review-core.js](workflows/3-code-review-core.js) (five lenses) and [4-code-review-modules.js](workflows/4-code-review-modules.js) (the module-integration lens). Evidence: [evidence/code-review.md](evidence/code-review.md). Run: 22 agents, 2.73 M tokens, 401 tool calls. Raised 49, verified 16, confirmed 15, rejected 1, minor 33.

### 3.1 Shared rules

- **Context**: the repository, the README and feasibility document as required reading, the hard constraints.
- **Guardrails**: reviewers may build and run the offline diagnostics (`--self-test`, `--dump-layout`, `--render`) but "Do NOT run the app in live mode", no preference changes, no writes to the Desktop, no git. "Report only real defects with a concrete failure scenario; skip style nits."

### 3.2 Lens reviewer (×6)

| Lens | What it was told to hunt for |
|---|---|
| file-safety | Data loss, wrong destinations, undo that restores the wrong thing, main-thread blocking copies, races with the folder watcher, dataless-file materialization, file-promise misuse. |
| events-focus | Stuck mouse state machines, coordinate conversions across two windows and two displays, tracking areas after relayout, rename lifecycle, Quick Look lifetime, non-activating panel key status vs Finder activation, level resets. |
| idle-resources | Anything alive at idle or after disable; observer leaks; unbounded caches; per-draw allocations; retain cycles; the shield must stay bitmap-free. |
| restore-safety | Hide key written without a restore record, enable failing after the write, external changes to the setting, SIGTERM, diagnostics interfering, login-item edge cases, menu state drift. |
| layout-model | Off-by-one grids, cells under the menu bar, manual-layout coordinate maths with a display above the main one, slot collisions, comparator strictness, date-bucket edges, package vs folder. |
| modules-integration | Thumbnails requested for dataless files through any path, size/scale mismatches across displays, automation calls without permission handling, position write-back racing relayout, scope of the iCloud monitor. |

- **Objective**: review the finished code through one lens and report only real defects.
- **Output contract**: `{dimension, findings[{file, line, severity, summary, failure_scenario, suggested_fix}]}`.
- **Verification**: every blocker and major finding goes to its own verifier (3.3). Minor findings are listed without a second check.

### 3.3 Finding verifier (one per non-minor finding)

- **Objective**: "Read the actual code and decide whether it is real, with a concrete reproduction argument; default to `real=false` if you cannot show the failure from the code. Do not fix anything."
- **Output contract**: `{real, severity ∈ {blocker, major, minor, not-a-bug}, note, fix}`.
- **Result**: 15 findings confirmed (two blockers), 1 rejected with a documented reason (the Quick Look dangling-pointer claim does not hold on the target OS), 33 minors triaged (28 from the five core lenses, 5 from module integration). Every confirmed finding and its resolution is in [evidence/code-review.md](evidence/code-review.md).

*Design note.* Reviewers were separated from verifiers on purpose: a reviewer that must also verify tends to soften its own claims. Several verifiers wrote small scratch programs to reproduce a claim before confirming it.

---

## 4. Evidence writers and privacy checkers (this documentation)

- **Context**: the raw outputs of the earlier rounds, which mention real desktop contents.
- **Objective (writer, ×4)**: turn one raw output into a focused Markdown page with tables and links. The four jobs were the research page, the modules page, the code-review page, and the experiments folder with its README.
- **Guardrails**: a strict privacy rule. No personal file or folder names from the owner's desktop, ever; use generic descriptions instead ("a folder", "a PDF"). Do not run the app, do not touch git, and change nothing outside the pages being written.
- **Output contract**: `{file, lines, notes}` for writers and `{file, personal_names_found[], fixed, accuracy_issues[], verdict}` for checkers.
- **Verification (checker, ×4)**: a second helper searches the finished page for personal names and fixes them in place, spot-checks five facts against the source, and confirms the Markdown renders.
- **Run**: script [5-evidence-docs.js](workflows/5-evidence-docs.js); 8 agents, 1.44 M tokens, 215 tool calls, 19 minutes. The privacy rule's list of examples was made more general after the run.

---

## 5. Feature reviews and the documentation review (scripts 6 to 8)

Scripts: [6-review-compact-grid.js](workflows/6-review-compact-grid.js), [7-review-reveal-desktop.js](workflows/7-review-reveal-desktop.js), [8-docs-readability-and-evidence.js](workflows/8-docs-readability-and-evidence.js). Evidence: [evidence/feature-reviews.md](evidence/feature-reviews.md). Run: 47 + 26 + 7 agents, 4.04 M + 2.20 M + 1.09 M tokens, 22 + 29 + 45 minutes.

### 5.1 Shared context for a single-change review

- **Context**: one uncommitted change, read with `git diff`. The block says what the change does, step by step, which facts were measured and may be treated as true (for example "no notification fires when a reveal starts"), and which product promises must survive (icons clickable exactly where they are drawn, idle work stays tiny, never doubled icons for long, the private entry point must fail safe).
- **Guardrails**: do not modify files, do not run the app, and, for the reveal review, do nothing that triggers Show Desktop. Building the package is allowed.

*Design note.* Telling reviewers which facts were measured stops them from re-arguing the experiments and points them at the code that depends on those facts.

### 5.2 Lens reviewer (×4 for the compact grid, ×3 for reveal desktop)

| Review | Lens | What it was told to hunt for |
|---|---|---|
| Compact grid | geometry | Every user of the name box and icon box once the name box has zero height: clicks, rubber band, hover areas, redraw bounds, rename field, drag images |
| Compact grid | layout-modes | Sorted against manual layouts, settings migration, which code path decides compactness, panel enable states |
| Compact grid | animation | The fade timer's whole life: rapid hover changes, relayout mid-fade, render paths, idle cost |
| Compact grid | tests-docs | Whether the new checks can fail for the right reason, and every sentence in the docs the change makes false |
| Reveal desktop | state-machine | Every path through step aside and come back: timers, races, quitting mid-reveal, double toggles |
| Reveal desktop | detection | False positives and negatives of the window-list rule, localisation, preference keys, the private call |
| Reveal desktop | interaction-cost | Plain-click semantics against Finder's, the idle-cost story, and claims in the docs that are now false |

- **Objective**: report only defects that can be pointed to at a file and line, each with a concrete failure scenario. An empty list is a valid answer.
- **Output contract**: `{findings[{file, line, title, description, failure_scenario, severity ∈ {blocker, major, minor, nit}}]}`.
- **Verification**: every finding goes to two skeptics (5.3).

### 5.3 Skeptic (two per finding) and completeness critic (one per review)

- **Objective (skeptic)**: "Try hard to REFUTE it by reading the actual code. Default to refuted=true if you cannot confirm the exact failure scenario." A finding stands when at least one skeptic, and at least half of those who answered, could not refute it.
- **Objective (critic)**: given only the lens names and the titles of the confirmed findings, name at most three concrete gaps nobody covered.
- **Output contract**: `{refuted, reason, fix_hint}` for skeptics; the reviewer's format for the critic.
- **Result**: 32 findings raised, 30 confirmed, 2 rejected, 6 added by the critics; 26 distinct problems, all resolved before the commit. The most serious one (the Dock recognised by its translated name) could not have been found by testing on an English system. Skeptics wrote their own small probes to settle facts rather than argue from memory.

### 5.4 Reader personas and synthesizer (documentation review)

- **Context**: the owner's standing requests for the docs: written for humans, prompts as cards, nothing personal.
- **Objective (reader, ×4)**: read an assigned set of pages as one person: a friend with no programming background, a hiring manager with five minutes, a macOS developer, a lead prompt engineer. Report at most twelve issues, each with file, line, a short quote, the problem for that reader, and a concrete suggestion.
- **Objective (synthesizer)**: check every claimed stale fact against the files, merge duplicates, and return a fix list where each item carries the exact current text and the exact replacement, so it can be applied by a plain string search.
- **Guardrails**: do not edit files; replacement text must use plain words and must not invent facts or numbers.
- **Output contract**: `{overall, score, issues[{file, line, kind ∈ {stale-or-wrong-fact, confusing, jargon-unexplained, too-long, navigation, inconsistent, typo}, quote, problem, suggestion, priority}]}` for readers; `{verdict, scores[], fixes[{file, line, priority, current_text, replacement_text, why}], rejected[]}` for the synthesizer.
- **Result**: reader scores of 6 to 7 out of 10, and 87 fixes (16 high). The main finding was not wording but drift: numbers and present-tense statements that had stopped agreeing with each other after a day of fast changes. 86 fixes applied by exact match on the first pass; the synthesizer itself rejected parts of eight reader suggestions that could not be checked.

*Design note.* Asking for the exact current text turns a review into a patch. It also makes the reviewer prove the passage exists.

---

## 6. Patterns worth reusing

1. **Constraint preamble, reused verbatim.** One block of context and hard rules per agent family. Drift between agents comes from paraphrased constraints.
2. **Schemas with enums.** Anything you will later filter, count or sort belongs in an enum in the schema, not in free text.
3. **Verification as a separate role with a hostile default.** "Default to not supported" and "default to not real" turned plausible-but-wrong claims into rejected ones.
4. **Pipeline over barrier.** Each research topic went to its verifier the moment it finished; each finding went to its verifier without waiting for the other lenses.
5. **Isolation by contract.** Parallel implementers got an interface to fill and a scratch package to build in; the lead kept stubs so the core always compiled.
6. **Say what you did not verify.** Every output schema had a place for it, and the lead carried those lists into the README and the validation checklist rather than dropping them.
7. **Resume, don't restart.** When a usage limit stopped the first run, the workflow was resumed. One finished implementation was replayed from cache. The two interrupted implementers ran again, found their own earlier drafts and re-checked them instead of trusting them.
8. **Humans own material tradeoffs.** The lead stopped for the custom-surface decision and for the icon; it did not stop for details it could settle itself.

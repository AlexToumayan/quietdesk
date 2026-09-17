# Prompt library

Every sub-agent in this project was driven by a prompt built from the same five parts. This page
presents each prompt as a card in that structure, so the design of the delegation is readable
without wading through code. The exact scripts are in [workflows/](workflows/) as the appendix.

| Part | What it does |
|---|---|
| **Context** | The situation the agent is stepping into: machine, product, constraints already decided. Reused verbatim across a family of agents so they cannot drift. |
| **Objective** | One job, stated as a deliverable. |
| **Guardrails** | What the agent must never do, phrased as hard rules (no live desktop changes, no subprocesses, no git, no file writes outside a named directory). |
| **Output contract** | A JSON Schema the harness enforces, with enums for anything that is later filtered or counted (source kind, confidence, severity, verdict). |
| **Verification** | A second, independent agent that reads the first one's output and tries to knock it down, with a default of "not supported / not real" when unsure. |

Two orchestration rules applied throughout: **pipeline, not barrier** (each item flows into its
verifier as soon as it is done), and **the human decides material tradeoffs** (the lead agent
stopped for a decision before replacing native desktop interactions, and again for the icon).

---

## 1. Feasibility research (8 topics, each verified)

### 1.1 Shared context block

Every research and verification agent received the same preamble.

- **Context**: the product idea in two sentences; target machine (macOS 26.6.2, Finder 26.4, no Xcode, Swift 6.1); two displays; the owner's desktop settings (sorted by date added, Stacks on, icon 36 / text 12 / spacing 26, iCloud sync on).
- **Guardrails**: read-only documentation research; prefer primary Apple sources; developer.apple.com is JS-rendered, so fetch the `/tutorials/data/documentation/<path>.json` endpoint; local files may be read but no `defaults write`, no `killall`, no scripting of apps, nothing written outside a scratch directory; "Do not run experiments on the live desktop; the orchestrator does that."
- **Output rule**: every claim carries `source_kind`, a URL and a short paraphrase; confidence is `high` only when a primary Apple source states it directly; unknown means say so (`source_kind: none`), never guess; list open questions for experiments.

*Design note.* The ban on live experiments was deliberate: only one process should touch the real desktop, with capture-and-restore around every change. Research agents were confined to reading.

### 1.2 Topic researcher (×8)

- **Objective**: answer one mechanism question with cited findings.
- **Inputs**: the shared context, plus a topic prompt listing the specific sub-questions and the sources to check first.
- **Output contract**: `{topic, summary, findings[{claim, source_kind ∈ {apple-developer-doc, apple-user-guide, apple-header-or-sdef, apple-wwdc-or-forum-staff, community, none}, url, evidence, confidence ∈ {high, medium, low}}], open_questions[], recommended_experiments[]}`.

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
- **What it caught**: a "high" claim about Finder Sync and the Desktop was corrected; a windowing claim was upgraded from community to primary (the verifier found the AppKit release notes the researcher had missed); several URLs were replaced with version-pinned ones. Details in [evidence/research.md](evidence/research.md).

---

## 2. Parallel module implementation (3 modules, each reviewed)

### 2.1 Shared rules

- **Context**: the project, the toolchain, and the fact that the lead is editing core files concurrently, so "the project may not build at any given moment — do not run `swift build` in the project, do not edit any existing file, do not touch git."
- **Guardrails**: the product's hard constraints restated as a list (never modify user files, never trigger cloud downloads, no polling at idle, no subprocesses, no broad permissions, bounded memory, public APIs only).
- **Method**: build the module in an isolated scratch SwiftPM package with a harness that exercises it against real files read-only; only then copy the single file into the project; the module must have no dependency on other project types.

*Design note.* Giving each implementer an exact Swift interface to fill in (written by the lead first) made integration mechanical: stubs with the same signatures kept the core compiling until the real files landed.

### 2.2 Module implementer (×3)

| Module | Interface it had to implement | What the harness had to prove |
|---|---|---|
| ThumbnailCache | `thumbnail(for:size:scale:) -> NSImage?`, `onReady`, `invalidate`, `removeAll`, `cancelAll`, `isFullyLocal`, `isEligible` | Cloud-only files are never handed to QuickLook (the generator runs out of process and does not inherit the app's no-download policy); bounded concurrency; a rendered PNG. |
| CloudStatusMonitor | `init(directory:)`, `start`, `stop`, `status(for:)`, `onChange`, `resourceStatus(for:)` | Event-driven status for top-level items only; a 5 s live run with a histogram; nothing that reads contents. |
| FinderAutomation | `status()`, `readDesktopPositions`, `writeDesktopPosition`, `openInfoWindows`, `openNewWindow`, typed errors | Consent preflight off the main thread; one Apple event for all positions; correct quoting of arbitrary file names; observed coordinate ranges to settle the anchor question. |

- **Output contract**: `{module, file_written, interface, verified_by_running[], caveats[], not_verified[]}`.
- **Notable outcome**: the CloudStatusMonitor implementer measured that Spotlight metadata queries carry no iCloud attributes for the user's Desktop and deviated from the brief with a documented FSEvents / file-presenter / Progress design, exactly the kind of deviation the "say what you could not verify" rule is for.

### 2.3 Module reviewer (×3)

- **Objective**: re-derive the hard constraints against the finished file; verify API signatures against the SDK headers; compile it standalone in a fresh package; fix blockers and majors in place; report every change.
- **Output contract**: `{module, compiles_standalone, problems[{severity ∈ {blocker, major, minor}, description, fix_applied}], summary}`.
- **What it caught**: a cloud-download hole through 3D-model sibling files in the thumbnail eligibility list; positions paired by index from two separate Finder queries; a refresh pipeline that could stick after stop/start. All fixed before integration. Details in [evidence/modules.md](evidence/modules.md).

---

## 3. Adversarial code review (6 lenses, every finding verified)

### 3.1 Shared rules

- **Context**: the repository, the README and feasibility document as required reading, the hard constraints.
- **Guardrails**: reviewers may build and run the offline diagnostics (`--self-test`, `--dump-layout`, `--render`) but "Do NOT run the app in live mode", no preference changes, no writes to the Desktop, no git. "Report only real defects with a concrete failure scenario; skip style nits."

### 3.2 Dimension reviewer (×6)

| Lens | What it was told to hunt for |
|---|---|
| file-safety | Data loss, wrong destinations, undo that restores the wrong thing, main-thread blocking copies, races with the folder watcher, dataless-file materialization, file-promise misuse. |
| events-focus | Stuck mouse state machines, coordinate conversions across two windows and two displays, tracking areas after relayout, rename lifecycle, Quick Look lifetime, non-activating panel key status vs Finder activation, level resets. |
| idle-resources | Anything alive at idle or after disable; observer leaks; unbounded caches; per-draw allocations; retain cycles; the shield must stay bitmap-free. |
| restore-safety | Hide key written without a restore record, enable failing after the write, external changes to the setting, SIGTERM, diagnostics interfering, login-item edge cases, menu state drift. |
| layout-model | Off-by-one grids, cells under the menu bar, manual-layout coordinate maths with a display above the main one, slot collisions, comparator strictness, date-bucket edges, package vs folder. |
| modules-integration | Thumbnails requested for dataless files through any path, size/scale mismatches across displays, automation calls without permission handling, position write-back racing relayout, scope of the iCloud monitor. |

- **Output contract**: `{dimension, findings[{file, line, severity, summary, failure_scenario, suggested_fix}]}`.

### 3.3 Finding verifier (one per non-minor finding)

- **Objective**: "Read the actual code and decide whether it is real, with a concrete reproduction argument; default to `real=false` if you cannot show the failure from the code. Do not fix anything."
- **Output contract**: `{real, severity ∈ {blocker, major, minor, not-a-bug}, note, fix}`.
- **Result**: 15 findings confirmed (two blockers), 1 rejected with a documented reason (the Quick Look dangling-pointer claim does not hold on the target OS), 28 minors triaged. Every confirmed finding and its resolution is in [evidence/code-review.md](evidence/code-review.md).

*Design note.* Reviewers were separated from verifiers on purpose: a reviewer that must also verify tends to soften its own claims. Several verifiers wrote small scratch programs to reproduce a claim before confirming it.

---

## 4. Evidence writers and privacy checkers (this documentation)

- **Writer objective**: turn one raw JSON output into a focused Markdown page with tables and links, under a strict privacy rule: no personal file or folder names from the owner's desktop, ever, replaced by generic descriptions.
- **Checker objective**: search the produced page for personal names, fix in place, spot-check five facts against the source, confirm the Markdown renders.
- **Output contracts**: `{file, lines, notes}` and `{file, personal_names_found[], fixed, accuracy_issues[], verdict}`.

---

## 5. Patterns worth reusing

1. **Constraint preamble, reused verbatim.** One block of context and hard rules per agent family. Drift between agents comes from paraphrased constraints.
2. **Schemas with enums.** Anything you will later filter, count or sort belongs in an enum in the schema, not in free text.
3. **Verification as a separate role with a hostile default.** "Default to not supported" and "default to not real" turned plausible-but-wrong claims into rejected ones.
4. **Pipeline over barrier.** Each research topic went to its verifier the moment it finished; each finding went to its verifier without waiting for the other lenses.
5. **Isolation by contract.** Parallel implementers got an interface to fill and a scratch package to build in; the lead kept stubs so the core always compiled.
6. **Say what you did not verify.** Every output schema had a place for it, and the lead carried those lists into the README and the validation checklist rather than dropping them.
7. **Resume, don't restart.** When a usage limit killed three agents mid-run, the workflow was resumed with the two finished modules replayed from cache.
8. **Humans own material tradeoffs.** The lead stopped for the custom-surface decision and for the icon; it did not stop for details it could settle itself.

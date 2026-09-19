# Prompt library

**What this is.** I built QuietDesk by directing an AI, Claude, working in Claude Code. Claude did
the research, ran the experiments and wrote the Swift code, and for the bigger rounds it handed
pieces of the work to short-lived helper agents: separate AI sessions started for one job, given
one set of instructions, and finished. Those instructions are the whole job. A vague instruction
produces vague work, and a missing rule produces a helper that does something I did not want, like
changing my real desktop to test an idea. This page collects the instructions the helpers were
given in the five main rounds, laid out the same way each time so you can see the pattern, and says
what each one was for and what it caught.

Every helper prompt was built from the same five parts, so that no helper could drift from the plan.
Each card below uses the same labels: Context, Objective, Guardrails, Output contract, Verification, plus a closing Result line that says what the prompt caught. A part that a whole family of helpers shares is shown once, in that family's first card.

Each section starts with its script, its evidence page and what the run cost. The scripts as run are in [workflows/](workflows/), with local paths replaced by placeholders. Scripts 6 to 8 are the later review rounds; their cards are in section 5.

| Part | What it does |
|---|---|
| **Context** | The situation the agent is stepping into: machine, product, constraints already decided. Reused word for word across a family of agents so they cannot drift. |
| **Objective** | One job, stated as a deliverable. |
| **Guardrails** | What the agent must never do, phrased as hard rules (no live desktop changes, no subprocesses, no git, no file writes outside a named directory). |
| **Output contract** | A fill-in-the-blanks form the helper must return. The program that runs the helpers rejects an answer that does not fit the form. Anything that is counted or filtered later is multiple choice, not free text (source kind, confidence, severity, verdict). In technical terms: a JSON Schema with enums. |
| **Verification** | A second, independent agent that reads the first one's output and tries to knock it down, with a default of "not supported / not real" when unsure. |

**Words used on this page.** *Claude*, or *the main Claude session*: the one AI session I directed. It wrote these prompts and ran the helpers. The raw prompts and the scripts call it "the lead" or "the orchestrator". *Helper*, or *agent*: a short-lived session started for one job. *Lens*: the one kind of problem a reviewer was told to look for (the field in the schema is `dimension`). *Reviewer*: a helper that finds problems; in section 2 it also fixes them. *Verifier*: a second helper told to disbelieve a claim until it can prove it. The evidence pages also call verifiers "skeptics" or "fact-checkers".

Two rules ran through all of it: **pipeline, not barrier** (each finished piece goes straight to its
verifier as soon as it is done), and **I decide the material tradeoffs** (Claude stopped and asked
me before replacing the native desktop interactions, and again about the icon).

---

## 1. Feasibility research (8 topics, each verified)

**In plain words.** Before any code existed I wanted to know what macOS would actually let this app
do. So I had the question split into eight topics. One helper researched each topic in Apple's own
documentation, and a second helper then fetched every page that was cited and checked whether it
really said what the first helper claimed.

Script: [1-feasibility-research.js](workflows/1-feasibility-research.js). Evidence: [evidence/research.md](evidence/research.md). Run: 16 agents, 2.28 M tokens, 1,336 tool calls, 26 minutes.

### 1.1 Shared context block

Every research and verification agent received the same preamble.

- **Context**: the product idea in two sentences; my Mac as the target machine (macOS 26.6.2, Finder 26.4, no Xcode, Swift 6.1); two displays; my desktop's settings (sorted by date added, Stacks on, icon 36 / text 12 / spacing 26, cloud sync on).
- **Guardrails**: read-only documentation research; prefer primary Apple sources; developer.apple.com is JS-rendered, so fetch the `/tutorials/data/documentation/<path>.json` endpoint; local files may be read but no `defaults write`, no `killall`, no scripting of apps, nothing written outside a scratch directory; "Do not run experiments on the live desktop; the orchestrator does that."
- **Output contract**: every claim carries `source_kind`, a URL and a short paraphrase; confidence is `high` only when a primary Apple source states it directly; unknown means say so (`source_kind: none`), never guess; list open questions for experiments.

*Why I wanted it this way.* The ban on live experiments was the point. Only one process should
touch my real desktop, and only with capture-and-restore around every change. Research helpers were
confined to reading.

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

**In plain words.** Three parts of the app are self-contained enough to be built on their own:
icon previews, iCloud status, and talking to Finder. For each one Claude wrote the exact shape
the finished part had to have, handed it to a helper to build in a private scratch project, and
then had a second helper review it before it was allowed into the app.

Script: [2-module-implementation.js](workflows/2-module-implementation.js). Evidence: [evidence/modules.md](evidence/modules.md). Run: two runs, because the first hit a usage limit; 5 + 6 agents, 1.48 M tokens, 265 tool calls, 58 minutes.

### 2.1 Shared rules

- **Context**: the project, the toolchain, and the fact that Claude was editing core files at the same time, so "the project may not build at any given moment": do not run `swift build` in the project, do not edit any existing file, do not touch git.
- **Guardrails**: the product's hard constraints as they stood at the time, restated as a list (never modify user files, never trigger cloud downloads, no polling at idle, no subprocesses, no broad permissions, bounded memory, public APIs only). The idle rule has since changed: QuietDesk now looks at the window list once a second for as long as it is on. The story of that change is in section 5.
- **Guardrails (how to work)**: build the module in an isolated scratch SwiftPM package with a test harness (a small throwaway program that calls the module on real files, read-only, and prints what happened); only then copy the single file into the project; the module must have no dependency on other project types.

*Why I wanted it this way.* Giving each implementer an exact Swift interface to fill in, written
first, made joining the pieces mechanical. Empty placeholders with the same shape kept the rest of
the app compiling until the real files landed.

### 2.2 Module implementer (×3)

| Module | Interface it had to implement | What the harness had to prove |
|---|---|---|
| ThumbnailCache | `thumbnail(for:size:scale:) -> NSImage?`, `onReady`, `invalidate`, `removeAll`, `cancelAll`, `isFullyLocal`, `isEligible` | Cloud-only files are never handed to QuickLook (the generator runs out of process and does not inherit the app's no-download policy); bounded concurrency; a rendered PNG. |
| CloudStatusMonitor | `init(directory:)`, `start`, `stop`, `status(for:)`, `onChange`, `resourceStatus(for:)` | Event-driven status for top-level items only; a 5 s live run with a histogram; nothing that reads contents. |
| FinderAutomation | `status()`, `readDesktopPositions`, `writeDesktopPosition`, `openInfoWindows`, `openNewWindow`, typed errors | Consent preflight off the main thread; one Apple event for all positions; correct quoting of arbitrary file names; observed coordinate ranges to settle the anchor question. |

- **Output contract**: `{module, file_written, interface, verified_by_running[], caveats[], not_verified[]}`.
- **Result**: the CloudStatusMonitor implementer measured that Spotlight metadata queries carry no iCloud attributes for my Desktop, and departed from the brief with a documented FSEvents / file-presenter / Progress design instead. That is exactly the kind of departure the "say what you could not verify" rule is for.

### 2.3 Module reviewer (×3)

- **Objective**: re-derive the hard constraints against the finished file; verify API signatures against the SDK headers; compile it standalone in a fresh package; fix blockers and majors in place; report every change.
- **Output contract**: `{module, compiles_standalone, problems[{severity ∈ {blocker, major, minor}, description, fix_applied}], summary}`.
- **Result**: a cloud-download hole through 3D-model sibling files in the thumbnail eligibility list; positions paired by index from two separate Finder queries; a refresh pipeline that could stick after stop/start. All fixed before the parts went in. Details in [evidence/modules.md](evidence/modules.md).

---

## 3. Adversarial code review (6 lenses, every finding verified)

**In plain words.** Once the app worked, I wanted it attacked rather than admired. Six reviewers
each read the finished code looking for one kind of problem, and every serious thing they found was
handed to a separate helper whose job was to prove it wrong.

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

*Why I wanted it this way.* Reviewers were kept apart from verifiers on purpose. A reviewer that
has to verify its own claim tends to soften it. Several verifiers wrote small scratch programs to
reproduce a claim before they would confirm it.

---

## 4. Evidence writers and privacy checkers (this documentation)

**In plain words.** The evidence pages in this repository were written by helpers from the raw
output of the earlier rounds. That raw output mentions the real contents of my desktop, so a second
helper went over every finished page looking for anything personal and took it out.

- **Context**: the raw outputs of the earlier rounds, which mention real desktop contents.
- **Objective (writer, ×4)**: turn one raw output into a focused Markdown page with tables and links. The four jobs were the research page, the modules page, the code-review page, and the experiments folder with its README.
- **Guardrails**: a strict privacy rule. No personal file or folder names from my desktop, ever; use generic descriptions instead ("a folder", "a PDF"). Do not run the app, do not touch git, and change nothing outside the pages being written.
- **Output contract**: `{file, lines, notes}` for writers and `{file, personal_names_found[], fixed, accuracy_issues[], verdict}` for checkers.
- **Verification (checker, ×4)**: a second helper searches the finished page for personal names and fixes them in place, spot-checks five facts against the source, and confirms the Markdown renders.
- **Run**: script [5-evidence-docs.js](workflows/5-evidence-docs.js); 8 agents, 1.44 M tokens, 215 tool calls, 19 minutes. I had the privacy rule's list of examples made more general after the run.

---

## 5. Feature reviews and the documentation review (scripts 6 to 8)

**In plain words.** Two features were added after the first review round, so each one got its own
review before I let it into the project: the compact grid, and stepping aside when the desktop is
revealed. Then four helpers read the documentation as four different kinds of reader and told me
where it failed them.

Scripts: [6-review-compact-grid.js](workflows/6-review-compact-grid.js), [7-review-reveal-desktop.js](workflows/7-review-reveal-desktop.js), [8-docs-readability-and-evidence.js](workflows/8-docs-readability-and-evidence.js). Evidence: [evidence/feature-reviews.md](evidence/feature-reviews.md). Run: 47 + 26 + 7 agents, 4.04 M + 2.20 M + 1.09 M tokens, 22 + 29 + 45 minutes.

### 5.1 Shared context for a single-change review

- **Context**: one change that had not been committed yet, read with `git diff`. The block says what the change does, step by step, which facts were measured and may be treated as true (for example "no notification fires when a reveal starts"), and which product promises must survive (icons clickable exactly where they are drawn, idle work stays tiny, never doubled icons for long, the private entry point must fail safe).
- **Guardrails**: do not modify files, do not run the app, and, for the reveal review, do nothing that triggers Show Desktop. Building the package is allowed.

*Why I wanted it this way.* Telling reviewers which facts were already measured stops them from
re-arguing the experiments and points them at the code that depends on those facts.

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
- **Result**: 32 findings raised, 30 confirmed, 2 rejected, 6 added by the critics; 26 distinct problems, all resolved before the commit. The most serious one, the Dock being recognised by its translated name, could not have been found by testing on an English system. Skeptics wrote their own small probes to settle facts rather than argue from memory.

### 5.4 Reader personas and synthesizer (documentation review)

- **Context**: my standing requests for these pages: written for humans, prompts as cards, nothing personal.
- **Objective (reader, ×4)**: read an assigned set of pages as one person: a friend with no programming background, a hiring manager with five minutes, a macOS developer, a lead prompt engineer. Report at most twelve issues, each with file, line, a short quote, the problem for that reader, and a concrete suggestion.
- **Objective (synthesizer)**: check every claimed stale fact against the files, merge duplicates, and return a fix list where each item carries the exact current text and the exact replacement, so it can be applied by a plain string search.
- **Guardrails**: do not edit files; replacement text must use plain words and must not invent facts or numbers.
- **Output contract**: `{overall, score, issues[{file, line, kind ∈ {stale-or-wrong-fact, confusing, jargon-unexplained, too-long, navigation, inconsistent, typo}, quote, problem, suggestion, priority}]}` for readers; `{verdict, scores[], fixes[{file, line, priority, current_text, replacement_text, why}], rejected[]}` for the synthesizer.
- **Result**: reader scores of 6 to 7 out of 10, and 87 fixes (16 high). The main finding was not wording but drift: numbers and present-tense statements that had stopped agreeing with each other after a day of fast changes. 86 fixes applied by exact match on the first pass; the synthesizer itself rejected parts of eight reader suggestions that could not be checked.

*Why I wanted it this way.* Asking for the exact current text turns a review into a patch. It also
makes the reviewer prove the passage really exists.

---

## 6. What I would do again

1. **One block of context and hard rules per family of helpers, reused word for word.** Drift between agents comes from constraints that were paraphrased instead of repeated.
2. **Forms with fixed choices.** Anything I would later filter, count or sort had to be a fixed set of options in the form, not free text.
3. **Verification as a separate job, with a hostile default.** "Default to not supported" and "default to not real" turned plausible-but-wrong claims into rejected ones.
4. **Pipeline over barrier.** Each research topic went to its verifier the moment it finished; each finding went to its verifier without waiting for the other lenses.
5. **Isolation by contract.** Parallel implementers got an interface to fill and a scratch package to build in, and Claude kept empty placeholders in the app so it always compiled.
6. **Say what you did not verify.** Every output form had a place for it, and Claude carried those lists into the README and the validation checklist rather than dropping them.
7. **Resume, do not restart.** When a usage limit stopped the first run, the workflow was resumed. One finished implementation was replayed from cache. The two interrupted implementers ran again, found their own earlier drafts and re-checked them instead of trusting them.
8. **I own the material tradeoffs.** Claude stopped and asked me about building a custom desktop layer at all, and about the icon. It did not stop for details it could settle itself.

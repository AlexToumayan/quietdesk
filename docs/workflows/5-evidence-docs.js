export const meta = {
  name: 'quietdesk-evidence-docs',
  description: 'Convert the raw research, module and review outputs of the QuietDesk build into curated, privacy-scrubbed Markdown evidence files, then verify the scrub',
  phases: [
    { title: 'Convert', detail: 'one writer per evidence source' },
    { title: 'Scrub check', detail: 'privacy and accuracy verification' },
  ],
}

const RULES = `
CONTEXT: QuietDesk (<repo>) is a macOS menu-bar utility built in one AI-assisted session. The owner wants the repository to double as a prompt-engineering / process portfolio, so the raw agent outputs must become elegant, readable Markdown evidence files under <repo>/docs/evidence/. GitHub renders the Markdown (tables, Mermaid allowed).

PRIVACY RULES (mandatory): the raw outputs mention the owner's real desktop contents. Never copy specific personal file or folder names (people's names, document titles, project names, anything touching personal, financial or health matters, client names, course codes, app names, screenshots' names). Replace them with generic descriptions ("a folder", "a PDF", "an 80-item folder set", "a mounted disk image"). Stack bucket names (Today, Yesterday, Previous 7 Days, Previous 30 Days, month names, years, Earlier) and generic kinds are fine. Do not include the owner's email. Paths like ~/Desktop are fine. Machine facts (macOS 26.6.2, Finder 26.4, display sizes, icon 36 / text 12 / spacing 26, 148 items, iCloud Desktop sync on) are fine.

STYLE: a short intro paragraph, then tables. Cite URLs as links. Keep each file focused and under ~400 lines. Use plain, precise sentences. Where a verifier corrected or rejected a claim, show that: the point of this portfolio is that claims were checked. Do not editorialize about "AI" beyond stating which agent role produced what. Read-only otherwise: do not modify any file outside docs/evidence/ (create the directory if needed), do not run the app, do not touch git.
`

const JOBS = [
  {
    key: 'research',
    prompt: `${RULES}
TASK: Write docs/evidence/research.md from the research workflow output at <task-outputs>/w46aojm5b.output (JSON; key "result" is a list of 8 topics, each with "research" {topic, summary, findings[{claim, source_kind, url, evidence, confidence}], open_questions, recommended_experiments} and "verification" {verdicts[{claim, verdict, note, better_url}], corrections[], missing[]}). Also read <workflow-scripts>/quietdesk-feasibility-research-wf_46f24314-584.js to describe how the topics and the verifier were prompted (quote the key instructions briefly). Structure: intro (what was researched, why primary sources, how verification worked, stats: 8 topics, 16 agents, ~2.3M tokens, ~1,300 tool calls, ~26 minutes); then per topic: 2-4 sentence summary, a table of the most decision-relevant findings (claim | source kind | confidence | verifier verdict | source link) limited to ~8 rows per topic, then "Corrections from the verifier" bullets and "Open questions handed to experiments" bullets. End with a short section "What the research changed in the design" (3-6 bullets: e.g. no API exists; Show Items setting is the only supported hide; alpha hit-testing documented only as a hit-testing rule; TCC identity for ad-hoc signatures; dataless-file policy TN3150). Apply the privacy rules to any quoted text.`,
  },
  {
    key: 'modules',
    prompt: `${RULES}
TASK: Write docs/evidence/modules.md from the module workflow output at <task-outputs>/wkt25bmz6.output (JSON; "result" is a list of 3 entries {key, impl{module, file_written, interface, verified_by_running[], caveats[], not_verified[]}, review{module, compiles_standalone, problems[{severity, description, fix_applied}], summary}}), plus the prompt script <workflow-scripts>/quietdesk-modules-wf_3562815a-ff3.js. Structure: intro explaining the pattern (interface contract written first by the lead, each module built in an isolated scratch SwiftPM package against real files read-only, verified by a harness, copied in, then a skeptical reviewer re-derived constraints and fixed blockers in place; note the first run hit a usage limit and was resumed with cached results). Then per module (ThumbnailCache, CloudStatusMonitor, FinderAutomation): the public interface (code block), what the harness verified (bullets, concise), caveats worth knowing, reviewer findings table (severity | problem | fixed?), and one line on how the lead integrated it (you may read <repo>/Sources/QuietDesk/OverlayController.swift and DesktopView.swift to state where it is used). Note explicitly that CloudStatusMonitor deliberately deviated from the brief (NSMetadataQuery unusable) and why. Apply the privacy rules to any quoted file names from the harness runs.`,
  },
  {
    key: 'review',
    prompt: `${RULES}
TASK: Write docs/evidence/code-review.md from two review outputs: <task-outputs>/w3bud70fz.output (five dimensions) and <task-outputs>/wp0yzkaqz.output (module integration). Each is JSON with "result" {confirmed[{dimension, file, line, severity, summary, failure_scenario, suggested_fix, verdict{real, severity, note, fix}}], minors[], rejected[{dimension, summary, note}]}. Also read the prompt scripts <scratch>/review-core.js and review-modules.js to describe the review design (six lenses, verify-by-default-false skeptics, no live runs allowed). Structure: intro with the design and stats (core: 18 agents, ~2.1M tokens, ~30 min, 12 confirmed / 1 rejected / 28 minor; integration: 4 agents, 3 confirmed). Then a table of all confirmed findings: # | dimension | severity | file | what could go wrong (one sentence) | resolution. For the resolution column, CHECK THE CURRENT CODE under <repo>/Sources/QuietDesk/ and state whether and how each was fixed (e.g. "fixed: willSet captures the old selection"; "fixed: isSameOrDescendant guard"; if you cannot find a fix, say "not found in code"). Then the rejected finding with the verifier's reasoning (a good example of the skeptic working). Then a compact table of minor findings grouped by dimension with a status column (fixed / accepted-and-documented / open), again checked against the code and README. Finish with 3-5 bullets on what the review process caught that testing would have missed.`,
  },
  {
    key: 'experiments',
    prompt: `${RULES}
TASK: Create the directory <repo>/experiments/ containing the reproducible experiment scripts from the session and a README.md that documents each one. Copy these files from <scratch>/probe/: probe.swift (permissions + displays + window levels), probe2.swift (all low-level windows), lowwin.swift, hovertest.swift (level ordering, hit tests, tracking with cursor warps), alphatest4.swift (two stacked windows: transparent pass-through and alpha threshold), alphatest5.swift (same with a non-activating NSPanel), positions.applescript (Finder view options + every item's name/position/class), textsize.applescript and textsize10.applescript (Finder rejects text size 4, accepts 10). Recreate the .DS_Store Iloc parser as experiments/dsstore_iloc.py: a small Python 3 script that parses a COPY of ~/Desktop/.DS_Store (Bud1 header, allocator block table, TOC 'DSDB', B-tree nodes, records with types long/shor/bool/blob/type/ustr/comp/dutc) and prints the Iloc (x, y) records; it must never write to the Desktop. Also add experiments/hide-toggle.sh: a shell script that captures the current value of com.apple.WindowManager StandardHideDesktopIcons, writes true, lists low-level windows (using the compiled lowwin), restores the captured value, and diffs (this is what revealed the WindowManager click-catcher window); it must restore in all cases (trap). The README must explain for each script: what question it answers, how to build/run it (swiftc -O -o name name.swift; osascript file), what it changes (all reversible; which ones touch the live desktop for a couple of seconds), and the result observed on macOS 26.6.2 — take the results from <repo>/docs/FEASIBILITY.md sections 3 and 4 (E1-E12). Scrub any personal file names from script comments or expected output samples (the AppleScript output is not included). Do not run anything that changes system state; compiling is fine.`,
  },
]

const RESULT = { type: 'object', properties: { file: { type: 'string' }, lines: { type: 'integer' }, notes: { type: 'string' } }, required: ['file', 'notes'] }
const SCRUB = { type: 'object', properties: { file: { type: 'string' }, personal_names_found: { type: 'array', items: { type: 'string' } }, fixed: { type: 'boolean' }, accuracy_issues: { type: 'array', items: { type: 'string' } }, verdict: { type: 'string' } }, required: ['file', 'personal_names_found', 'fixed', 'verdict'] }

phase('Convert')
const out = await pipeline(
  JOBS,
  j => agent(j.prompt, { label: `write:${j.key}`, phase: 'Convert', schema: RESULT }),
  (r, j) => {
    if (!r) return null
    return agent(`${RULES}
You are the PRIVACY AND ACCURACY CHECKER for ${r.file} (and, for the experiments job, every file under <repo>/experiments/). Read the file(s). (1) Search for any personal desktop file/folder names, people's names, course codes, client names, references to personal, financial or health matters, or the owner's email; fix them in place with generic wording and list what you replaced. (2) Spot-check five factual statements against the source JSON/scripts named in the writer's task and flag any that are wrong or overstated (fix small ones in place; list the rest). (3) Confirm the Markdown renders sanely (tables have header separators, code fences closed). Report.

Writer's notes: ${r.notes}`, { label: `scrub:${j.key}`, phase: 'Scrub check', schema: SCRUB })
      .then(v => ({ key: j.key, written: r, scrub: v }))
  },
)
return out.filter(Boolean)
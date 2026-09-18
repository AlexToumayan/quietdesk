export const meta = {
  name: 'docs-readability-and-evidence',
  description: 'Fresh-eyes readability review of the QuietDesk docs by four reader personas, plus an evidence page for the two latest adversarial reviews with a privacy check',
  phases: [{ title: 'Read' }, { title: 'Synthesize' }, { title: 'Evidence' }, { title: 'Privacy check' }],
}

const REPO = '<repo>'
const BASE = `The repository is at ${REPO} (a native macOS menu-bar utility, QuietDesk, which is also a prompt-engineering
portfolio). The owner asked that the documentation be written "for humans ... as if the readers were 5", that prompts be
shown as structured cards rather than raw dumps, and that nothing personal about them or their computer appears anywhere.
Do NOT run the app or any QuietDesk binary. Do NOT run git commands that change anything.`

const FINDINGS = {
  type: 'object',
  properties: {
    overall: { type: 'string', description: 'Two or three sentences: how easy is this to read for your persona, honestly' },
    score: { type: 'integer', description: '1 (impenetrable) to 10 (effortless) for your persona' },
    issues: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          file: { type: 'string' }, line: { type: 'integer' },
          kind: { type: 'string', enum: ['stale-or-wrong-fact', 'confusing', 'jargon-unexplained', 'too-long', 'navigation', 'inconsistent', 'typo'] },
          quote: { type: 'string', description: 'Short quote (under 25 words) of the passage' },
          problem: { type: 'string' },
          suggestion: { type: 'string', description: 'Concrete replacement text or action' },
          priority: { type: 'string', enum: ['high', 'medium', 'low'] },
        },
        required: ['file', 'line', 'kind', 'quote', 'problem', 'suggestion', 'priority'],
      },
    },
  },
  required: ['overall', 'score', 'issues'],
}

const READERS = [
  { key: 'curious-friend', files: 'README.md (top to "Desktop features") and docs/CONCEPTS.md (all of it)',
    persona: `You are a curious friend of the author with NO programming background. You use a Mac every day. Read as that person:
      where do you get lost, which words are never explained, which sentences do you have to read twice, where is the explanation
      longer than the idea? Also say what works well (briefly, in "overall").` },
  { key: 'hiring-manager', files: 'README.md, docs/CASE-STUDY.md, docs/PROMPTS.md (first 150 lines and the section headings of the rest)',
    persona: `You are a hiring manager for an AI-engineering role with five minutes. You want to know: what was built, what was the
      candidate's process, what evidence backs the claims, and can you find the prompts and experiments quickly? Judge the first
      screen of each file, the navigation between files, and whether headline numbers are consistent across files.` },
  { key: 'mac-developer', files: 'docs/FEASIBILITY.md, experiments/README.md, README.md sections "Known limitations", "Permissions", "Performance", "Tests"',
    persona: `You are an experienced macOS/AppKit developer. Read for accuracy and clarity: are claims precise, are experiments
      reproducible from the text, do the numbers and statements agree with each other and with CHANGELOG.md (read its "Unreleased"
      section) and with the code where you care to check (Sources/QuietDesk)? Flag every stale statement (the project moved fast:
      compact grid, reveal desktop, scenario test, a once-a-second window-list check were added recently).` },
  { key: 'prompt-engineer', files: 'docs/PROMPTS.md (all), docs/evidence/research.md, docs/evidence/modules.md, docs/evidence/code-review.md, docs/workflows/ (skim the five .js files)',
    persona: `You are a lead prompt engineer reviewing a portfolio. Are the prompt cards well structured and self-explanatory, do the
      evidence pages show what each workflow actually produced, is anything a raw dump that should be a summary, is terminology
      consistent (agent, reviewer, skeptic, verifier, lens)? Is it clear which workflows ran and what they cost and found?` },
]

phase('Read')
const reads = await parallel(READERS.map(r => () =>
  agent(`${BASE}\n\n${r.persona}\n\nRead these files (use cat -n so you can cite line numbers): ${r.files}.
    Report at most 12 issues, highest priority first. Every issue needs the file, the line number, a short quote, what the
    problem is for YOUR persona, and a concrete suggestion. Do not pad: fewer real issues beat many weak ones. Do not edit files.`,
    { label: `read:${r.key}`, phase: 'Read', schema: FINDINGS }).then(x => x ? { ...x, reader: r.key } : null)))

phase('Synthesize')
const valid = reads.filter(Boolean)
const synthesis = await agent(`${BASE}\n\nFour readers reviewed the documentation. Their reports:\n${JSON.stringify(valid, null, 1)}\n\n
  Produce the owner-facing verdict. (1) For each "stale-or-wrong-fact" or "inconsistent" issue, CHECK it yourself against the
  files (cat -n, grep) and keep only the ones that are real; say which you rejected and why. (2) Merge duplicates. (3) Return a
  prioritized fix list where every item has file, line, the exact current text (copy it from the file so it can be found with a
  plain string search; one or two sentences at most) and the exact replacement text. Replacement text must follow the house
  style: plain words, short sentences, no em-dashes, no invented facts or numbers. (4) A three-sentence honest answer to
  "is the documentation easy to read?". Do not edit files.`,
  { label: 'synthesize', phase: 'Synthesize', schema: {
      type: 'object',
      properties: {
        verdict: { type: 'string' },
        scores: { type: 'array', items: { type: 'object', properties: { reader: { type: 'string' }, score: { type: 'integer' }, overall: { type: 'string' } }, required: ['reader', 'score', 'overall'] } },
        fixes: { type: 'array', items: { type: 'object', properties: {
          file: { type: 'string' }, line: { type: 'integer' }, priority: { type: 'string', enum: ['high', 'medium', 'low'] },
          current_text: { type: 'string' }, replacement_text: { type: 'string' }, why: { type: 'string' } },
          required: ['file', 'line', 'priority', 'current_text', 'replacement_text', 'why'] } },
        rejected: { type: 'array', items: { type: 'string' } },
      },
      required: ['verdict', 'scores', 'fixes', 'rejected'] } })

phase('Evidence')
const SOURCES = `<scratch>/tasks/wgpsyu117.output (review of the
  "compact grid" change: 4 lenses, 2 skeptics per finding, a completeness critic; 47 agents) and
  <scratch>/tasks/w4c55p7qn.output (review of the "reveal desktop" change:
  3 lenses, 2 skeptics per finding, a critic; 26 agents). Each file is JSON: {summary, agentCount, logs, result:{confirmed:[...],
  rejected:[...], critic:[...]}}; each confirmed finding has file, line, title, description, failure_scenario, severity, lens, votes.`
const written = await agent(`${BASE}\n\nWrite a NEW evidence page at ${REPO}/docs/evidence/feature-reviews.md, in the same voice and
  structure as ${REPO}/docs/evidence/code-review.md (read that first). It documents two adversarial reviews that were run on
  single features before they were committed. Sources: ${SOURCES}
  Read them with python3 (json.load). How each was resolved is recorded in ${REPO}/CHANGELOG.md ("Unreleased") and in the commit
  messages (git -C ${REPO} log -3 --format=%B for the reveal-desktop one; git -C ${REPO} log --grep="Compact grid" --format=%B for the other).
  Content: a short plain-language introduction (what an adversarial review of one change is and why it was worth it); for each
  review: the change under review in two sentences, the workflow shape (lenses, skeptics, critic, agent count), a table of the
  DISTINCT problems found (merge duplicates reported by several lenses; one row each: problem in plain words, severity, how it was
  fixed), what the skeptics rejected and why, and one paragraph on what the review taught. End with a short "pattern" section
  (what makes this workflow shape work). House style: plain words, short sentences, no em-dashes, no invented numbers (count
  from the JSON). PRIVACY: never write a path containing a user name or a session id; refer to the repository as <repo>; do not
  copy example file names from the findings other than obviously generic ones like "Report.pdf"; no personal data of any kind.
  Return the path and a one-paragraph summary of what you wrote.`, { label: 'write:feature-reviews', phase: 'Evidence' })

phase('Privacy check')
const checked = await agent(`${BASE}\n\nYou are the PRIVACY AND ACCURACY CHECKER for ${REPO}/docs/evidence/feature-reviews.md, which another agent
  just wrote from these sources: ${SOURCES}
  (1) Privacy: the page must contain no home-directory path, user name in a path, session id, scratch path, email address, real
  desktop file or folder name, hardware model or serial, or anything else that identifies the owner's computer. "<repo>" is the
  only allowed way to refer to the repository location. Fix violations in place. (2) Accuracy: every count (agents, findings,
  rejected, critic items) and every severity must match the JSON; every "how it was fixed" must be supported by CHANGELOG.md or
  the code in ${REPO}/Sources/QuietDesk. Fix errors in place. (3) Style: no em-dashes; plain words. Return what you changed and
  a final statement of whether the page is clean.`, { label: 'check:feature-reviews', phase: 'Privacy check' })

return { synthesis, evidence: { written, checked } }
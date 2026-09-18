export const meta = {
  name: 'quietdesk-feasibility-research',
  description: 'Research primary documentation for macOS desktop-label control mechanisms, then adversarially verify each claim',
  phases: [
    { title: 'Research', detail: 'one agent per mechanism topic, primary Apple sources first' },
    { title: 'Verify', detail: 'skeptic re-checks each claim against its cited source' },
  ],
}

const COMMON = `
CONTEXT: We are assessing feasibility for a small open-source macOS menu-bar utility ("QuietDesk") whose distinguishing feature is: desktop icons stay visible in their normal Finder positions, but their filename labels appear only on pointer hover (plus on selection/keyboard focus). Files must not be renamed/moved/flagged. Target machine: macOS 26.6.2 (Tahoe, Apple Silicon, Finder 26.4, NO Xcode installed (Command Line Tools + Swift 6.1 only, SwiftPM available). Two displays (Retina 2x built-in + external 1x). User's desktop uses Sort By: Date Added, Stacks grouped by Date Added, icon size 36, text size 12, icon previews on, iCloud Desktop sync on.

YOUR JOB: read-only documentation research. First call ToolSearch with query "select:WebFetch,WebSearch" to load those tools. Prefer PRIMARY sources: developer.apple.com/documentation (tip: developer.apple.com pages are JS-rendered; fetch the JSON at https://developer.apple.com/tutorials/data/documentation/<path>.json, e.g. .../documentation/appkit/nswindow/ignoresmouseevents.json), Apple support user guides (support.apple.com/guide/mac-help/...), Apple headers/sdef, WWDC session transcripts, Apple developer forums answers by Apple staff. Community sources (StackOverflow, blogs, GitHub) are acceptable but must be labelled as such. You may read local files with Bash (cat/grep) — e.g. /System/Library/CoreServices/Finder.app/Contents/Resources/Finder.sdef, /System/Library/Frameworks headers — but you MUST NOT change any system state: no 'defaults write', no 'killall', no osascript that controls apps, no launching apps, no writing outside /private/tmp. Do not run experiments on the live desktop; the orchestrator does that.

OUTPUT RULES: For every claim, give source_kind, the URL, and a SHORT paraphrase (not long quotes) of what the source says as 'evidence'. Mark confidence 'high' only if a primary Apple source states it directly. If you cannot find any source for something, say so explicitly (source_kind 'none') rather than guessing. List open questions the orchestrator should test experimentally.
`

const TOPICS = [
  {
    key: 'hide-desktop-items',
    prompt: `${COMMON}
TOPIC: Mechanisms for hiding Finder desktop items WITHOUT touching files.
Investigate: (1) The macOS Sonoma+ user setting System Settings > Desktop & Dock > "Show Items: On Desktop / In Stage Manager" — cite Apple's user guide; find whether it is backed by defaults keys in the com.apple.WindowManager domain (community reports name StandardHideDesktopIcons and HideDesktop) and whether Finder applies a change to that key live (no Finder restart) — label the defaults-key claims as community/undocumented unless Apple documents them. (2) The older 'defaults write com.apple.finder CreateDesktop -bool false' + killall Finder approach: what it does, that it requires a Finder relaunch, what is lost (context menu, drag targets). (3) Whether any public API exists for hiding desktop icons (NSWorkspace, etc.) — expected answer: none; state that with evidence of what you searched. (4) On macOS 26 Tahoe specifically: has the setting moved/renamed? Check Apple's macOS Tahoe user guide. (5) What happens to the Finder desktop window when items are hidden via the Sonoma setting: does right-click on the wallpaper still show Finder's desktop context menu, do drags onto the desktop still land in ~/Desktop, does 'click wallpaper to reveal desktop' still work? Cite community reports where Apple doesn't say.`,
  },
  {
    key: 'finder-scripting-positions',
    prompt: `${COMMON}
TOPIC: Finder's scripting dictionary as a public interface to desktop icon layout.
Investigate: (1) The 'desktop position' item property (read/write) — what coordinate system (origin, which corner, points vs pixels, center vs top-left of icon, multi-display behaviour), and whether setting it works when the desktop is 'Sort By' arranged. Cite Apple's Finder sdef (local file /System/Library/CoreServices/Finder.app/Contents/Resources/Finder.sdef) and any Apple scripting guide; community examples welcome but label them. (2) 'icon view options' of 'window of desktop': 'text size' integer — is any range documented? Do community reports show Finder accepting values below 10 or clamping? Does a change via AppleScript apply live to the desktop without relaunching Finder? (3) How Desktop 'Stacks' appear to scripting: does 'every item of desktop' list items inside stacks, and what is their desktop position? (4) Apple Events permission model: NSAppleEventsUsageDescription, the one-time Automation consent dialog, AEDeterminePermissionToAutomateTarget for preflight, error -1743 (errAEEventNotPermitted) — cite Apple docs (TN2xxx? WWDC 2018 'Your Apps and the Future of macOS Security'). (5) Performance: is 'get {name, desktop position} of every item of desktop' a single Apple Event round-trip? Any Apple guidance on batching.`,
  },
  {
    key: 'appkit-window-mechanics',
    prompt: `${COMMON}
TOPIC: AppKit/CoreGraphics window mechanics for a custom desktop-level layer.
Investigate with primary docs: (1) NSWindow.Level and CGWindowLevelKey: desktopWindow vs desktopIconWindow levels; document what CGWindowLevelForKey(.desktopIconWindow) is for. (2) NSWindow.ignoresMouseEvents — exact documented semantics (does a window that ignores mouse events still receive mouseMoved / tracking-area enter/exit events? what does Apple's doc say?). (3) Alpha-based click-through: Apple documentation stating that for non-opaque windows, mouse events in fully transparent regions pass to windows beneath (search NSWindow isOpaque docs, 'Window Programming Guide' shaped windows, 'NSWindow hasShadow', and the sample code 'RoundTransparentWindow'). Establish whether this is DOCUMENTED behaviour or only observed. Also NSWindow.windowNumber(at:belowWindowWithWindowNumber:) for programmatic hit-testing. (4) NSWindow.CollectionBehavior options relevant to a desktop layer: canJoinAllSpaces, stationary, ignoresCycle, fullScreenNone/fullScreenAuxiliary, transient; and what the docs say about Mission Control / Exposé 'Show Desktop' treatment of windows with .stationary. (5) NSTrackingArea options: activeAlways, mouseEnteredAndExited, inVisibleRect; whether enter/exit works for an app that is not active. (6) LSUIElement agent apps: can they have key windows / receive keyboard events; what happens to the menu bar when a UIElement app activates. (7) NSStatusItem / NSMenu basics are known — skip. (8) Any Apple doc on how desktop-level windows behave during Stage Manager, Show Desktop, full-screen apps — likely none; say so.`,
  },
  {
    key: 'finder-extension-limits',
    prompt: `${COMMON}
TOPIC: Whether Finder Sync extensions or any Finder extension point can alter desktop icon LABEL rendering.
Investigate Apple's FinderSync documentation (FIFinderSync, FIFinderSyncController): exactly what it can do (badges, toolbar button, contextual menu items, monitored directories, sidebar icon) and confirm it cannot change how filenames are drawn, cannot hide labels, cannot hide icons, and cannot observe hover. Also check: Quick Actions / Services, App Extensions list (App Extension Programming Guide), the deprecated Finder plugin mechanisms, and whether any macOS accessibility or 'File Provider' API influences desktop rendering (File Provider decorations show badges/labels in Finder sidebar/columns? cite FPUIExtension / NSFileProviderItemDecorating). State clearly what is impossible with citations.`,
  },
  {
    key: 'permissions-tcc',
    prompt: `${COMMON}
TOPIC: Permissions (TCC) the candidate implementation would need, and what triggers prompts.
Investigate with Apple sources: (1) Access to ~/Desktop by a non-sandboxed app: the 'Files and Folders' consent ('would like to access files in your Desktop folder'), the NSDesktopFolderUsageDescription Info.plist key, whether the syscall blocks until the user answers, and how the grant is keyed (bundle id + code signature; ad-hoc signed binaries and rebuilds). (2) Apple Events automation consent: NSAppleEventsUsageDescription, one prompt per target app, AEDeterminePermissionToAutomateTarget. (3) Global event monitors (NSEvent.addGlobalMonitorForEvents): Apple's doc on which event types require Accessibility / Input Monitoring — is mouseMoved monitoring allowed without any permission? (4) CGEvent posting (CGEventPost) — requires Accessibility trust? cite. (5) Screen Recording: is it required for CGWindowListCreateImage of your OWN windows, and for reading other windows' names via CGWindowListCopyWindowInfo? (6) Login items: SMAppService.mainApp (macOS 13+) as the supported no-helper way to launch at login; cite. (7) Launching an ad-hoc-signed or unsigned .app on macOS 15/26: Gatekeeper behaviour for apps built locally (no quarantine attribute → runs), vs downloaded (quarantine → 'Open Anyway' in Privacy & Security on Sequoia+); Developer ID + notarization cost (Apple Developer Program price) — cite Apple.`,
  },
  {
    key: 'icons-files-cloud',
    prompt: `${COMMON}
TOPIC: Rendering file icons cheaply and safely, watching the Desktop folder, and cloud-only (dataless) files.
Investigate with Apple sources: (1) NSWorkspace.icon(forFile:) and NSWorkspace.icon(for: UTType) — do they read file contents? For app bundles / custom-icon files (com.apple.FinderInfo / Icon\\r), what do they read? Do they trigger iCloud downloads of dataless files? (2) QLThumbnailGenerator with .icon representation type vs .lowQualityThumbnail/.thumbnail — which reads file content; is there a way to get Finder-like 'icon preview' thumbnails without triggering downloads (check QLThumbnailGenerationRequest and NSURL ubiquitous keys: isUbiquitousItemKey, ubiquitousItemDownloadingStatusKey, and the FileProvider 'dataless' concept / NSURL fileProtection). (3) URLResourceKeys useful for a desktop item: nameKey, localizedNameKey (display name with .localized folders), isHiddenKey, isPackageKey, isDirectoryKey, contentTypeKey, effectiveIconKey / customIconKey, isAliasFileKey, isUbiquitousItemKey, addedToDirectoryDateKey (for 'Date Added' sort). (4) Watching ~/Desktop for changes: FSEvents (FSEventStreamCreate; latency, kFSEventStreamCreateFlagFileEvents, cost) vs DispatchSource.makeFileSystemObjectSource(.write) on the directory fd (non-recursive, cheap) — cite Apple docs on each; which one also fires when Finder rewrites .DS_Store. (5) Finder's desktop sort order 'Date Added' — which attribute (kMDItemDateAdded / addedToDirectoryDate) and Finder's default arrangement (columns from top-right) — cite Apple user guide 'Arrange items on the desktop'. (6) Desktop Stacks: Apple user guide on what they group (files only? folders excluded?) and how they interact with icon positions.`,
  },
  {
    key: 'prior-art',
    prompt: `${COMMON}
TOPIC: Prior art — apps and open-source projects that draw their own icons/windows at the desktop level, and reported pitfalls.
Investigate (community sources are fine here, label them): (1) Open-source macOS projects that place NSWindows at desktop/desktop-icon level (e.g. wallpaper engines, desktop widgets, 'Übersicht', 'iCollections' (closed), 'Desktop Curtain', 'Hidden Bar' no). Find code on GitHub using CGWindowLevelForKey(.desktopIconWindow) or kCGDesktopIconWindowLevel and note what collectionBehavior/settings they use and any issues reported (Mission Control, Show Desktop gesture, Stage Manager, Sonoma 'click wallpaper to reveal desktop', full-screen, sleep/wake, display reconfiguration). (2) Any existing app (free or paid) that already offers 'desktop icon labels on hover' on macOS — if one exists, how does it work? (3) Reports on the Sonoma+ 'Show Items on Desktop' setting and defaults key StandardHideDesktopIcons — does it apply live? (4) Known .DS_Store 'Iloc' record semantics for the Desktop (coordinate origin, units) as a permission-free fallback for icon positions — cite reverse-engineering write-ups; note staleness caveats. (5) Any reports about Finder's desktop window ('Desktop' window at desktop icon level) still receiving right-clicks/drops when icons are hidden.`,
  },
  {
    key: 'tahoe-changes',
    prompt: `${COMMON}
TOPIC: macOS 26 Tahoe-specific facts that could change the design.
Investigate: (1) Apple's macOS Tahoe release notes / 'What's new' and the Tahoe Mac User Guide pages for Desktop & Dock, Finder View Options for the desktop (icon size, text size range shown in the View Options panel, label position, 'Show item info', 'Show icon preview', Stacks), and any NEW option related to desktop icon labels or hiding names. (2) Any AppKit deprecations/changes in macOS 26 relevant to: NSStatusItem, NSMenu, desktop-level NSWindow, NSTrackingArea, 'Liquid Glass' effects on menu bar extras (menu-bar icon guidelines: template images, SF Symbols). (3) Whether Finder's desktop icon window in Tahoe still exists as a full-screen window at the desktop-icon window level (community/dev reports). (4) Swift 6.1 / SwiftPM: building a macOS .app bundle without Xcode — the minimal Info.plist keys (LSUIElement, CFBundleIdentifier, NSPrincipalClass) and the need for codesign (ad-hoc) on Apple Silicon (arm64 requires a signature to run — cite Apple). (5) Menu bar extra design guidance from Apple HIG (template image, size 18-22pt, SF Symbols).`,
  },
]

const FINDINGS = {
  type: 'object',
  properties: {
    topic: { type: 'string' },
    summary: { type: 'string', description: '5-10 sentence plain-language conclusion for this topic' },
    findings: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          claim: { type: 'string' },
          source_kind: { type: 'string', enum: ['apple-developer-doc', 'apple-user-guide', 'apple-header-or-sdef', 'apple-wwdc-or-forum-staff', 'community', 'none'] },
          url: { type: 'string' },
          evidence: { type: 'string', description: 'short paraphrase of what the source says; no long quotes' },
          confidence: { type: 'string', enum: ['high', 'medium', 'low'] },
        },
        required: ['claim', 'source_kind', 'confidence'],
      },
    },
    open_questions: { type: 'array', items: { type: 'string' } },
    recommended_experiments: { type: 'array', items: { type: 'string' } },
  },
  required: ['topic', 'summary', 'findings'],
}

const VERIFY = {
  type: 'object',
  properties: {
    topic: { type: 'string' },
    verdicts: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          claim: { type: 'string' },
          verdict: { type: 'string', enum: ['supported', 'partially-supported', 'not-supported-by-cited-source', 'could-not-fetch'] },
          note: { type: 'string' },
          better_url: { type: 'string' },
        },
        required: ['claim', 'verdict'],
      },
    },
    corrections: { type: 'array', items: { type: 'string' }, description: 'claims that are wrong or overstated, with the correct statement' },
    missing: { type: 'array', items: { type: 'string' }, description: 'important facts on this topic the researcher missed' },
  },
  required: ['topic', 'verdicts'],
}

phase('Research')
const results = await pipeline(
  TOPICS,
  t => agent(t.prompt, { label: `research:${t.key}`, phase: 'Research', schema: FINDINGS }),
  (research, t) => {
    if (!research) return null
    return agent(`${COMMON}
You are a SKEPTICAL VERIFIER. A researcher produced the findings below for topic "${t.key}". For each finding with confidence 'high' or 'medium', fetch the cited URL (load tools first via ToolSearch "select:WebFetch,WebSearch"; for developer.apple.com use the /tutorials/data/documentation/...json trick) and decide whether the source actually supports the claim as stated. Default to 'not-supported-by-cited-source' if the page does not say it. Also list important facts the researcher missed and any claims that are overstated. Keep notes short.

FINDINGS JSON:
${JSON.stringify(research, null, 1)}`, { label: `verify:${t.key}`, phase: 'Verify', schema: VERIFY })
      .then(v => ({ key: t.key, research, verification: v }))
  },
)

const out = results.filter(Boolean)
log(`Research complete for ${out.length}/${TOPICS.length} topics`)
return out
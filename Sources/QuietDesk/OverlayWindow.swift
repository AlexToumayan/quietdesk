import AppKit

/// A borderless, transparent, non-activating panel one level above Finder's own desktop
/// icons (kCGDesktopIconWindowLevel + 1). It sits below every normal application window and
/// above the click-catcher window WindowManager adds at the icon level while desktop items are
/// hidden (observed on macOS 26.6). Being a non-activating panel it can take keyboard focus
/// without making QuietDesk the active application, so the menu bar can stay with Finder.
/// Hit-testing: with `ignoresMouseEvents` left at its default, the window server passes clicks on
/// fully transparent pixels through to the window beneath; setting it explicitly to false (done
/// here) makes the whole frame receive events, transparent pixels included — the three-state
/// behaviour Apple described in the AppKit 10.3 release notes, still observed on macOS 26.6.
/// The full-screen shield below keeps a 1/255-alpha layer as a second line of defence.
final class OverlayWindow: NSPanel {
    private let keyable: Bool

    init(frame: NSRect, canBecomeKey keyable: Bool = true) {
        self.keyable = keyable
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        // NSPanel: isFloatingPanel rewrites `level`, so it must be set BEFORE the desktop level.
        isFloatingPanel = false
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        becomesKeyOnlyIfNeeded = false
        worksWhenModal = true
        isExcludedFromWindowsMenu = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none
        isMovable = false
        isMovableByWindowBackground = false
        title = "QuietDesk Desktop"
    }

    override var canBecomeKey: Bool { keyable }  // the icon window takes keyboard focus; the shield never does
    override var canBecomeMain: Bool { false }

    /// Guard against anything (AppKit or a future change) moving the panel off the desktop level.
    override var level: NSWindow.Level {
        get { super.level }
        set { super.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1) }
    }
}

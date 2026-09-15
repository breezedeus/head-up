import AppKit
import SwiftUI

@MainActor
final class PrivacyOverlayController {
    private var panels: [CGDirectDisplayID: PrivacyOverlayPanel] = [:]
    private var screenObserver: NSObjectProtocol?
    private var isVisible = false
    private let settings: ScreenPrivacySettings
    private let content: PrivacyOverlayContentModel
    private var onPause: (() -> Void)?
    /// Receives the stable display ID of the screen whose target was tapped, so the
    /// recenter references the screen the user was actually facing.
    private var onRecenter: ((String) -> Void)?
    /// Whoever was frontmost when the overlay went up, so focus can go back there.
    private var previouslyActiveApp: NSRunningApplication?

    init(settings: ScreenPrivacySettings, content: PrivacyOverlayContentModel) {
        self.settings = settings
        self.content = content
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isVisible else { return }
                self.rebuildPanels()
            }
        }
    }

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    func show(
        message: String? = nil,
        onPause: @escaping () -> Void,
        onRecenter: ((String) -> Void)? = nil
    ) {
        content.message = message
        self.onPause = onPause
        let targetVisibilityChanged = (self.onRecenter == nil) != (onRecenter == nil)
        self.onRecenter = onRecenter
        guard !isVisible else {
            // The target appearing or disappearing changes the panel contents.
            if targetVisibilityChanged { rebuildPanels() }
            return
        }
        isVisible = true
        // Captured before activating, while the answer is still the user's app. Only on
        // the not-visible -> visible edge: `rebuildPanels` also runs on display changes,
        // and re-capturing then would record ourselves.
        let front = NSWorkspace.shared.frontmostApplication
        previouslyActiveApp = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front
        // Before `rebuildPanels`, so the `makeKey()` in there can take effect: the app is
        // an accessory that never activates on its own, an inactive app has no key window
        // at all, and without a key window Esc went to whatever app was frontmost — with
        // the screen covered, straight into an app the user cannot see.
        //
        // `NSApplication.shared` rather than `NSApp`: the latter is an implicitly
        // unwrapped optional and is nil in the test process, where no application
        // instance is ever created.
        NSApplication.shared.activate(ignoringOtherApps: true)
        rebuildPanels()
    }

    func hide() {
        isVisible = false
        panels.values.forEach { $0.orderOut(nil) }
        panels.removeAll()
        content.message = nil
        onPause = nil
        onRecenter = nil
        // Hand focus back, or the user is left in an accessory app with no windows and
        // has to click their own app again.
        if let previouslyActiveApp, !previouslyActiveApp.isTerminated {
            previouslyActiveApp.activate()
        }
        previouslyActiveApp = nil
    }

    private func rebuildPanels() {
        panels.values.forEach { $0.orderOut(nil) }
        panels.removeAll()

        let primaryScreen = NSScreen.main ?? NSScreen.screens.first
        for screen in NSScreen.screens {
            guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
                continue
            }
            let displaysInformation = settings.infoOnAllDisplays || screen == primaryScreen
            let panel = makePanel(for: screen)
            // Every covered screen gets its own target: whichever one the user faces
            // and taps becomes the reference, which beats assuming the primary screen.
            let stableID = Self.stableDisplayID(for: displayID)
            let recenterHandler: (() -> Void)? = onRecenter.map { handler in
                { handler(stableID) }
            }
            panel.contentView = NSHostingView(rootView: PrivacyOverlayView(
                settings: settings,
                content: content,
                displaysInformation: displaysInformation,
                onPause: { [weak self] in self?.onPause?() },
                onRecenter: recenterHandler
            ))
            panels[displayID] = panel
            panel.orderFrontRegardless()
            if screen == primaryScreen {
                panel.makeKey()
            }
        }
    }

    /// Must match `ScreenPrivacyStore.connectedDisplays()`, since the result is used to
    /// look up a saved display profile.
    private static func stableDisplayID(for displayID: CGDirectDisplayID) -> String {
        if let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() {
            return CFUUIDCreateString(nil, uuid) as String
        }
        return String(displayID)
    }

    private func makePanel(for screen: NSScreen) -> PrivacyOverlayPanel {
        let panel = PrivacyOverlayPanel(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        panel.setFrame(screen.frame, display: true)
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = false
        panel.onEscape = { [weak self] in self?.onPause?() }
        return panel
    }
}

private final class PrivacyOverlayPanel: NSPanel {
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}

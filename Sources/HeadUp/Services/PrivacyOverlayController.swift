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

    func show(message: String? = nil, onPause: @escaping () -> Void) {
        content.message = message
        self.onPause = onPause
        guard !isVisible else { return }
        isVisible = true
        rebuildPanels()
    }

    func hide() {
        isVisible = false
        panels.values.forEach { $0.orderOut(nil) }
        panels.removeAll()
        content.message = nil
        onPause = nil
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
            panel.contentView = NSHostingView(rootView: PrivacyOverlayView(
                settings: settings,
                content: content,
                displaysInformation: displaysInformation,
                onPause: { [weak self] in self?.onPause?() }
            ))
            panels[displayID] = panel
            panel.orderFrontRegardless()
            if screen == primaryScreen {
                panel.makeKey()
            }
        }
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

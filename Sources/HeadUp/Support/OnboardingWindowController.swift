import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func showIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: HeadUpDefaultsKey.onboardingCompleted) else { return }
        show()
    }

    private func show() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "欢迎使用抬头"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: GettingStartedView {
            window.performClose(nil)
        })
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
        HeadUpLog.windowing.notice("First-launch guide presented")
    }

    func windowWillClose(_ notification: Notification) {
        UserDefaults.standard.set(true, forKey: HeadUpDefaultsKey.onboardingCompleted)
        NotificationCenter.default.post(name: .headUpOnboardingCompleted, object: nil)
        window = nil
        HeadUpLog.windowing.notice("First-launch guide completed")
    }
}

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
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.delegate = self
        window.contentView = NSHostingView(rootView: GettingStartedView {
            window.performClose(nil)
        })
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
        HeadUpLog.windowing.notice("First-launch guide presented; window=\(window.windowNumber, privacy: .public)")
        captureDebugSnapshotIfRequested(from: window)
        closeDebugWindowIfRequested(window)
    }

    func windowWillClose(_ notification: Notification) {
        UserDefaults.standard.set(true, forKey: HeadUpDefaultsKey.onboardingCompleted)
        NotificationCenter.default.post(name: .headUpOnboardingCompleted, object: nil)
        window = nil
        HeadUpLog.windowing.notice("First-launch guide completed")
    }

    private func captureDebugSnapshotIfRequested(from window: NSWindow) {
        #if DEBUG
        guard let path = ProcessInfo.processInfo.environment["HEADUP_WELCOME_SNAPSHOT"],
              let contentView = window.contentView else { return }

        DispatchQueue.main.async {
            contentView.layoutSubtreeIfNeeded()
            guard let bitmap = contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds) else { return }
            contentView.cacheDisplay(in: contentView.bounds, to: bitmap)
            guard let data = bitmap.representation(using: .png, properties: [:]) else { return }
            do {
                try data.write(to: URL(fileURLWithPath: path), options: .atomic)
                HeadUpLog.windowing.notice("First-launch guide snapshot written")
            } catch {
                HeadUpLog.windowing.error("First-launch guide snapshot failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        #endif
    }

    private func closeDebugWindowIfRequested(_ window: NSWindow) {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["HEADUP_AUTOCOMPLETE_ONBOARDING"] == "1" else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            window.performClose(nil)
        }
        #endif
    }
}

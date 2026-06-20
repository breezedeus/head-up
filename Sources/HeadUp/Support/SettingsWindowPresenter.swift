import AppKit
import SwiftUI

enum HeadUpWindowID {
    static let settings = "settings"
}

@MainActor
enum SettingsWindowPresenter {
    static func present(using openWindow: OpenWindowAction) {
        HeadUpLog.windowing.notice("Settings window requested")
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: HeadUpWindowID.settings)
        bringToFront(attempt: 0)
    }

    private static func bringToFront(attempt: Int) {
        if let window = NSApp.windows.first(where: isSettingsWindow) {
            window.level = .normal
            window.collectionBehavior.insert(.moveToActiveSpace)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            HeadUpLog.windowing.notice("Settings window moved to active Space and presented")
            return
        }

        guard attempt < 12 else {
            HeadUpLog.windowing.error("Settings window was not created after retries")
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            bringToFront(attempt: attempt + 1)
        }
    }

    private static func isSettingsWindow(_ window: NSWindow) -> Bool {
        guard !(window is NSPanel) else { return false }
        if window.title == "抬头设置" { return true }
        return window.identifier?.rawValue.localizedCaseInsensitiveContains(HeadUpWindowID.settings) == true
    }
}

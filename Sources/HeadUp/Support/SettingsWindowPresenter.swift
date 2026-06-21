import AppKit
import SwiftUI

enum HeadUpWindowID {
    static let settings = "settings"
    static let guide = "guide"
}

@MainActor
enum HeadUpWindowPresenter {
    static func present(id: String, using openWindow: OpenWindowAction) {
        HeadUpLog.windowing.notice("Window requested: \(id, privacy: .public)")
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: id)
        bringToFront(id: id, attempt: 0)
    }

    private static func bringToFront(id: String, attempt: Int) {
        if let window = NSApp.windows.first(where: { isWindow($0, id: id) }) {
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
            bringToFront(id: id, attempt: attempt + 1)
        }
    }

    private static func isWindow(_ window: NSWindow, id: String) -> Bool {
        guard !(window is NSPanel) else { return false }
        let expectedTitle = id == HeadUpWindowID.settings ? "抬头设置" : "抬头使用指南"
        if window.title == expectedTitle { return true }
        return window.identifier?.rawValue.localizedCaseInsensitiveContains(id) == true
    }
}

import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        HeadUpLog.lifecycle.notice("HeadUp launched as a menu bar accessory")
    }
}

@main
struct HeadUpApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = PostureStore()

    var body: some Scene {
        MenuBarExtra {
            DashboardView(store: store)
        } label: {
            Image(systemName: store.menuBarIcon)
                .accessibilityLabel("抬头：\(store.status.title)")
        }
        .menuBarExtraStyle(.window)

        Window("抬头设置", id: HeadUpWindowID.settings) {
            SettingsView(store: store)
        }
        .defaultSize(width: 460, height: 310)
        .windowResizability(.contentSize)
    }
}

import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let onboardingWindowController = OnboardingWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        HeadUpLog.lifecycle.notice("HeadUp launched as a menu bar accessory")
        onboardingWindowController.showIfNeeded()
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
        .defaultSize(width: 480, height: 510)
        .windowResizability(.contentSize)

        Window("抬头使用指南", id: HeadUpWindowID.guide) {
            GettingStartedView()
        }
        .defaultSize(width: 540, height: 520)
        .windowResizability(.contentSize)
    }
}

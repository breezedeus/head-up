import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let onboardingWindowController = OnboardingWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let isSettingsSnapshot = ProcessInfo.processInfo.environment["HEADUP_SETTINGS_SNAPSHOT"] == "1"
        NSApp.setActivationPolicy(isSettingsSnapshot ? .regular : .accessory)
        if isSettingsSnapshot {
            NSApp.activate(ignoringOtherApps: true)
        }
        HeadUpLog.lifecycle.notice("HeadUp launched")
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
            MenuBarStatusIcon(status: store.status)
                .accessibilityLabel("抬头：\(store.status.title)")
                .background {
                    if ProcessInfo.processInfo.environment["HEADUP_SETTINGS_SNAPSHOT"] == "1" {
                        SettingsSnapshotLauncher()
                    }
                }
        }
        .menuBarExtraStyle(.window)

        Window("抬头设置", id: HeadUpWindowID.settings) {
            SettingsView(store: store)
        }
        .defaultSize(width: 570, height: 540)
        .windowResizability(.contentSize)

        Window("抬头使用指南", id: HeadUpWindowID.guide) {
            GettingStartedView()
        }
        .defaultSize(width: 540, height: 520)
        .windowResizability(.contentSize)

    }
}

private struct SettingsSnapshotLauncher: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .task {
                try? await Task.sleep(for: .milliseconds(500))
                HeadUpWindowPresenter.present(id: HeadUpWindowID.settings, using: openWindow)
            }
    }
}

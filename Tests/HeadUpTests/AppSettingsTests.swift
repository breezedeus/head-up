import Foundation
import Testing
@testable import HeadUp

@MainActor
struct AppSettingsTests {
    @Test func audibleRemindersDefaultToEnabled() {
        let suiteName = "AppSettingsTests.default-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)

        #expect(settings.audibleRemindersEnabled)
    }

    @Test func audibleRemindersPersistWhenChanged() {
        let suiteName = "AppSettingsTests.persist-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        settings.audibleRemindersEnabled = false

        let reloaded = AppSettings(defaults: defaults)
        #expect(!reloaded.audibleRemindersEnabled)
    }
}

import Foundation
import Testing
@testable import HeadUp

@MainActor
struct ScreenPrivacySettingsTests {
    @Test func privacyProtectionDefaultsToOffWithClockVisible() {
        let suiteName = "ScreenPrivacySettingsTests.default-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = ScreenPrivacySettings(defaults: defaults)

        #expect(!settings.isEnabled)
        #expect(settings.showsTime)
        #expect(settings.showsDate)
        #expect(!settings.showsWeather)
    }

    @Test func fourDirectionalAnglesAndContentPersist() {
        let suiteName = "ScreenPrivacySettingsTests.persist-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = ScreenPrivacySettings(defaults: defaults)
        settings.leftAngle = 48
        settings.rightAngle = 52
        settings.upAngle = 18
        settings.downAngle = 30
        settings.customText = "专注工作中"

        let reloaded = ScreenPrivacySettings(defaults: defaults)
        #expect(reloaded.leftAngle == 48)
        #expect(reloaded.rightAngle == 52)
        #expect(reloaded.upAngle == 18)
        #expect(reloaded.downAngle == 30)
        #expect(reloaded.customText == "专注工作中")
    }

    @Test func calibratedWorkAreaPersistsForAutomaticRecovery() {
        let suiteName = "ScreenPrivacySettingsTests.profile-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let profile = ScreenPrivacyCalibrationProfile(
            centerYaw: 12,
            centerPitch: -4,
            leftYawDirection: -1,
            upPitchDirection: 1,
            leftAngle: 42,
            rightAngle: 38,
            upAngle: 19,
            downAngle: 26
        )
        let settings = ScreenPrivacySettings(defaults: defaults)
        settings.saveCalibrationProfile(profile)

        let reloaded = ScreenPrivacySettings(defaults: defaults)
        #expect(reloaded.calibrationProfile == profile)
    }
}

import Foundation
import Testing
@testable import HeadUp

struct ScreenPrivacyAnalyzerTests {
    private let profile = ScreenPrivacyCalibrationProfile(
        centerYaw: 0,
        centerPitch: 0,
        leftYawDirection: 1,
        upPitchDirection: -1,
        leftAngle: 35,
        rightAngle: 40,
        upAngle: 20,
        downAngle: 25
    )

    @Test func horizontalExitCoversOnlyAfterConfiguredDelay() {
        let analyzer = ScreenPrivacyAnalyzer()
        let settings = ScreenPrivacyThresholds(hideDelay: 0.8, revealDelay: 0.3, hysteresis: 3)

        #expect(analyzer.process(yaw: 36, pitch: 0, at: 10, profile: profile, thresholds: settings).phase == .waitingToCover)
        #expect(analyzer.process(yaw: 36, pitch: 0, at: 10.7, profile: profile, thresholds: settings).phase == .waitingToCover)
        #expect(analyzer.process(yaw: 36, pitch: 0, at: 10.8, profile: profile, thresholds: settings).phase == .covered)
    }

    @Test func lookingUpOrDownAlsoTriggersProtection() {
        let upAnalyzer = ScreenPrivacyAnalyzer()
        let downAnalyzer = ScreenPrivacyAnalyzer()
        let settings = ScreenPrivacyThresholds(hideDelay: 0.5, revealDelay: 0.3, hysteresis: 3)

        _ = upAnalyzer.process(yaw: 0, pitch: -21, at: 20, profile: profile, thresholds: settings)
        #expect(upAnalyzer.process(yaw: 0, pitch: -21, at: 20.5, profile: profile, thresholds: settings).phase == .covered)

        _ = downAnalyzer.process(yaw: 0, pitch: 26, at: 30, profile: profile, thresholds: settings)
        #expect(downAnalyzer.process(yaw: 0, pitch: 26, at: 30.5, profile: profile, thresholds: settings).phase == .covered)
    }

    @Test func returningBeforeDelayCancelsProtection() {
        let analyzer = ScreenPrivacyAnalyzer()
        let settings = ScreenPrivacyThresholds(hideDelay: 0.8, revealDelay: 0.3, hysteresis: 3)

        _ = analyzer.process(yaw: -45, pitch: 0, at: 10, profile: profile, thresholds: settings)
        let reading = analyzer.process(yaw: 0, pitch: 0, at: 10.4, profile: profile, thresholds: settings)

        #expect(reading.phase == .watching)
        #expect(!reading.isCovered)
    }

    @Test func coveredStateRequiresInsetRecoveryRange() {
        let analyzer = ScreenPrivacyAnalyzer()
        let settings = ScreenPrivacyThresholds(hideDelay: 0, revealDelay: 0.3, hysteresis: 3)

        _ = analyzer.process(yaw: 36, pitch: 0, at: 10, profile: profile, thresholds: settings)
        #expect(analyzer.process(yaw: 34, pitch: 0, at: 11, profile: profile, thresholds: settings).phase == .covered)
        #expect(analyzer.process(yaw: 31, pitch: 0, at: 12, profile: profile, thresholds: settings).phase == .waitingToReveal)
        #expect(analyzer.process(yaw: 31, pitch: 0, at: 12.3, profile: profile, thresholds: settings).phase == .watching)
    }

    @Test func calibrationAcceptsWrappedYawAndOppositePitchDirections() throws {
        let profile = try #require(ScreenPrivacyCalibrationProfile.make(
            centerYaw: 179,
            centerPitch: 2,
            leftYaw: -151,
            rightYaw: 139,
            upPitch: -18,
            downPitch: 29
        ))

        #expect(profile.leftAngle == 30)
        #expect(profile.rightAngle == 40)
        #expect(profile.upAngle == 20)
        #expect(profile.downAngle == 27)
    }

    @Test func calibrationRejectsBoundariesOnSameSide() {
        let profile = ScreenPrivacyCalibrationProfile.make(
            centerYaw: 0,
            centerPitch: 0,
            leftYaw: 30,
            rightYaw: 20,
            upPitch: -20,
            downPitch: 25
        )

        #expect(profile == nil)
    }

    @Test func recentersAfterTemporaryTrackingLossWithoutForgettingBoundaries() {
        let recentered = profile.recentered(yaw: 82, pitch: -9)

        #expect(recentered.centerYaw == 82)
        #expect(recentered.centerPitch == -9)
        #expect(recentered.leftYawDirection == profile.leftYawDirection)
        #expect(recentered.upPitchDirection == profile.upPitchDirection)
        #expect(recentered.leftAngle == profile.leftAngle)
        #expect(recentered.rightAngle == profile.rightAngle)
        #expect(recentered.upAngle == profile.upAngle)
        #expect(recentered.downAngle == profile.downAngle)

        let offsets = recentered.offsets(yaw: 82, pitch: -9)
        #expect(abs(offsets.horizontal) < 0.001)
        #expect(abs(offsets.vertical) < 0.001)
    }
}

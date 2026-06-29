import Testing
@testable import HeadUp

struct PostureModelsTests {
    @Test func menuBarIconNamesCoverDistinctPostureStates() {
        #expect(PostureStatus.disconnected.menuBarIconName == "menu-disconnected")
        #expect(PostureStatus.calibrating(.upright).menuBarIconName == "menu-calibrating")
        #expect(PostureStatus.good.menuBarIconName == "menu-good")
        #expect(PostureStatus.caution.menuBarIconName == "menu-caution")
        #expect(PostureStatus.warning.menuBarIconName == "menu-warning")
        #expect(PostureStatus.moving.menuBarIconName == "menu-moving")
        #expect(PostureStatus.paused.menuBarIconName == "menu-paused")
    }

    @Test func activityDiagnosticsRemainStableAndPrivacySafe() {
        #expect(HeadphoneActivity.stationary.diagnosticDescription == "stationary")
        #expect(HeadphoneActivity.walking.diagnosticDescription == "walking")
        #expect(HeadphoneActivity.running.diagnosticDescription == "running")
        #expect(HeadphoneActivity.unknown.diagnosticDescription == "unknown")
    }

    @Test func availableHeadphoneMotionCountsAsInitialConnectionEvidence() {
        #expect(HeadphoneMotionService.hasInitialConnectionEvidence(isDeviceMotionAvailable: true))
        #expect(!HeadphoneMotionService.hasInitialConnectionEvidence(isDeviceMotionAvailable: false))
    }
}

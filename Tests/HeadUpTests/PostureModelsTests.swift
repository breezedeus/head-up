import Testing
@testable import HeadUp

struct PostureModelsTests {
    @Test func menuBarIconNamesCoverDistinctPostureStates() {
        #expect(PostureStatus.disconnected.menuBarIconName == "menu-disconnected")
        #expect(PostureStatus.unavailable.menuBarIconName == "menu-calibrating")
        #expect(PostureStatus.calibrating(.upright).menuBarIconName == "menu-calibrating")
        #expect(PostureStatus.good.menuBarIconName == "menu-good")
        #expect(PostureStatus.caution.menuBarIconName == "menu-caution")
        #expect(PostureStatus.warning.menuBarIconName == "menu-warning")
        #expect(PostureStatus.moving.menuBarIconName == "menu-moving")
        #expect(PostureStatus.paused.menuBarIconName == "menu-paused")
    }

    @Test func unavailableStatusDoesNotReadAsDisconnected() {
        #expect(PostureStatus.unavailable.title == "等待头部追踪")
        #expect(PostureStatus.unavailable.menuBarIconName != PostureStatus.disconnected.menuBarIconName)
    }

    @Test func activityDiagnosticsRemainStableAndPrivacySafe() {
        #expect(HeadphoneActivity.stationary.diagnosticDescription == "stationary")
        #expect(HeadphoneActivity.walking.diagnosticDescription == "walking")
        #expect(HeadphoneActivity.running.diagnosticDescription == "running")
        #expect(HeadphoneActivity.unknown.diagnosticDescription == "unknown")
    }

    @Test func availableHeadphoneMotionCountsAsInitialConnectionEvidence() {
        #expect(HeadphoneMotionService.hasInitialConnectionEvidence(
            isDeviceMotionAvailable: true,
            hasAudioConnectionEvidence: false
        ))
        #expect(HeadphoneMotionService.hasInitialConnectionEvidence(
            isDeviceMotionAvailable: false,
            hasAudioConnectionEvidence: true
        ))
        #expect(!HeadphoneMotionService.hasInitialConnectionEvidence(
            isDeviceMotionAvailable: false,
            hasAudioConnectionEvidence: false
        ))
    }

    @Test func monitoringRestartReenablesMotionUpdatesAfterPause() {
        var gate = MotionUpdateGate()
        gate.setEnabled(false)

        #expect(!gate.isEnabled)

        gate.prepareForMonitoringRestart()

        #expect(gate.isEnabled)
    }

    @Test func compatibleHeadphoneNamesMatchAirPodsAndHeadTrackingBeats() {
        #expect(HeadphoneAudioConnectionService.isCompatibleHeadphoneName("King's AirPods Pro"))
        #expect(HeadphoneAudioConnectionService.isCompatibleHeadphoneName("AirPods Max"))
        #expect(HeadphoneAudioConnectionService.isCompatibleHeadphoneName("Beats Fit Pro"))
        #expect(HeadphoneAudioConnectionService.isCompatibleHeadphoneName("Powerbeats Pro"))
        #expect(!HeadphoneAudioConnectionService.isCompatibleHeadphoneName("MacBook Pro Speakers"))
    }
}

import Testing
@testable import HeadUp

struct PostureModelsTests {
    @Test func activityDiagnosticsRemainStableAndPrivacySafe() {
        #expect(HeadphoneActivity.stationary.diagnosticDescription == "stationary")
        #expect(HeadphoneActivity.walking.diagnosticDescription == "walking")
        #expect(HeadphoneActivity.running.diagnosticDescription == "running")
        #expect(HeadphoneActivity.unknown.diagnosticDescription == "unknown")
    }
}

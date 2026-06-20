import Foundation
import Testing
@testable import HeadUp

struct PostureAnalyzerTests {
    @Test func learnsPositiveDownwardDirection() {
        let analyzer = PostureAnalyzer()
        analyzer.calibrate(uprightPitch: 2, lookDownPitch: 20)
        #expect(analyzer.downwardDirection == 1)
    }

    @Test func learnsNegativeDownwardDirection() {
        let analyzer = PostureAnalyzer()
        analyzer.calibrate(uprightPitch: 2, lookDownPitch: -20)
        #expect(analyzer.downwardDirection == -1)
    }

    @Test func warnsOnlyAfterDelayAndOnlyOncePerEpisode() throws {
        let analyzer = PostureAnalyzer()
        analyzer.calibrate(uprightPitch: 0, lookDownPitch: 20)
        let start = Date(timeIntervalSince1970: 1_000)

        _ = try #require(analyzer.process(pitch: 20, at: start, threshold: 10, reminderDelay: 5, cooldown: 60))
        let warning = try #require(analyzer.process(pitch: 20, at: start.addingTimeInterval(6), threshold: 10, reminderDelay: 5, cooldown: 60))
        let repeated = try #require(analyzer.process(pitch: 20, at: start.addingTimeInterval(7), threshold: 10, reminderDelay: 5, cooldown: 60))

        #expect(warning.isWarning)
        #expect(warning.shouldNotify)
        #expect(!repeated.shouldNotify)
    }

    @Test func recoveryResetsWarningEpisode() throws {
        let analyzer = PostureAnalyzer()
        analyzer.calibrate(uprightPitch: 0, lookDownPitch: 20)
        let start = Date(timeIntervalSince1970: 1_000)

        _ = analyzer.process(pitch: 20, at: start, threshold: 10, reminderDelay: 2, cooldown: 0)
        _ = analyzer.process(pitch: 20, at: start.addingTimeInterval(3), threshold: 10, reminderDelay: 2, cooldown: 0)

        for second in 4...20 {
            _ = analyzer.process(pitch: 0, at: start.addingTimeInterval(Double(second)), threshold: 10, reminderDelay: 2, cooldown: 0)
        }

        let recovered = try #require(analyzer.process(pitch: 0, at: start.addingTimeInterval(21), threshold: 10, reminderDelay: 2, cooldown: 0))
        #expect(!recovered.isWarning)
        #expect(recovered.sustainedDuration == 0)
    }
}

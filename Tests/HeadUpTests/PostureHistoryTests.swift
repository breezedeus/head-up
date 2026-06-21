import Foundation
import Testing
@testable import HeadUp

struct PostureHistoryTests {
    @Test func downsamplesAndPrunesOldEntries() {
        let start = Date(timeIntervalSince1970: 10_000)
        let history = PostureHistory(retention: 60, sampleInterval: 10)

        #expect(history.record(isGood: true, at: start))
        #expect(!history.record(isGood: false, at: start.addingTimeInterval(5)))
        #expect(history.record(isGood: false, at: start.addingTimeInterval(12)))
        #expect(history.record(isGood: true, at: start.addingTimeInterval(75)))
        #expect(history.entries.count == 1)
    }

    @Test func createsGoodWarningAndEmptyBins() {
        let now = Date(timeIntervalSince1970: 10_000)
        let history = PostureHistory(
            entries: [
                PostureHistoryEntry(timestamp: now.addingTimeInterval(-50), isGood: true),
                PostureHistoryEntry(timestamp: now.addingTimeInterval(-25), isGood: false),
                PostureHistoryEntry(timestamp: now.addingTimeInterval(-22), isGood: false)
            ],
            retention: 60,
            sampleInterval: 1
        )

        let bins = history.bins(count: 6, now: now)
        #expect(bins[1] == .good)
        #expect(bins[3] == .warning)
        #expect(bins[5] == .empty)
    }

    @Test func removesAllEntries() {
        let history = PostureHistory(entries: [
            PostureHistoryEntry(timestamp: Date(), isGood: true)
        ])

        history.removeAll()

        #expect(history.entries.isEmpty)
    }
}

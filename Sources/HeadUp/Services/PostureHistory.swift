import Foundation

struct PostureHistoryEntry: Codable, Equatable {
    let timestamp: Date
    let isGood: Bool
}

enum PostureBinState: Equatable {
    case empty
    case good
    case warning
}

final class PostureHistory {
    private(set) var entries: [PostureHistoryEntry]
    private let retention: TimeInterval
    private let sampleInterval: TimeInterval

    init(
        entries: [PostureHistoryEntry] = [],
        retention: TimeInterval = 60 * 60,
        sampleInterval: TimeInterval = 10
    ) {
        self.entries = entries.sorted { $0.timestamp < $1.timestamp }
        self.retention = retention
        self.sampleInterval = sampleInterval
    }

    @discardableResult
    func record(isGood: Bool, at date: Date) -> Bool {
        prune(at: date)
        if let latest = entries.last,
           date.timeIntervalSince(latest.timestamp) < sampleInterval {
            return false
        }

        entries.append(PostureHistoryEntry(timestamp: date, isGood: isGood))
        return true
    }

    func bins(count: Int = 30, now: Date = Date()) -> [PostureBinState] {
        guard count > 0 else { return [] }
        let binDuration = retention / Double(count)
        let start = now.addingTimeInterval(-retention)

        return (0..<count).map { index in
            let lower = start.addingTimeInterval(Double(index) * binDuration)
            let upper = lower.addingTimeInterval(binDuration)
            let samples = entries.filter { entry in
                entry.timestamp >= lower && (index == count - 1 ? entry.timestamp <= upper : entry.timestamp < upper)
            }
            guard !samples.isEmpty else { return .empty }
            let badCount = samples.lazy.filter { !$0.isGood }.count
            return Double(badCount) / Double(samples.count) >= 0.4 ? .warning : .good
        }
    }

    func removeAll() {
        entries.removeAll()
    }

    private func prune(at date: Date) {
        let cutoff = date.addingTimeInterval(-retention)
        entries.removeAll { $0.timestamp < cutoff }
    }
}

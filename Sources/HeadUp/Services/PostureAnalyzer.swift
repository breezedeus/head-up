import Foundation

final class PostureAnalyzer {
    var baselinePitch: Double?
    var downwardDirection: Double = 1

    private var filteredAngle = 0.0
    private var badPostureStartedAt: Date?
    private var lastNotificationAt: Date?
    private var notifiedForCurrentEpisode = false

    var isCalibrated: Bool { baselinePitch != nil }

    func calibrate(uprightPitch: Double, lookDownPitch: Double) {
        baselinePitch = uprightPitch
        downwardDirection = lookDownPitch >= uprightPitch ? 1 : -1
        resetEpisode()
        filteredAngle = 0
    }

    func process(
        pitch: Double,
        at date: Date,
        threshold: Double,
        reminderDelay: TimeInterval,
        cooldown: TimeInterval
    ) -> PostureReading? {
        guard let baselinePitch else { return nil }

        let delta = Self.normalizedAngle(pitch - baselinePitch) * downwardDirection
        let headDownAngle = max(0, delta)
        filteredAngle = filteredAngle == 0
            ? headDownAngle
            : (0.18 * headDownAngle) + (0.82 * filteredAngle)

        let recoveryThreshold = max(0, threshold - 4)
        if filteredAngle >= threshold {
            if badPostureStartedAt == nil {
                badPostureStartedAt = date
            }
        } else if filteredAngle <= recoveryThreshold {
            resetEpisode()
        }

        let duration = badPostureStartedAt.map { date.timeIntervalSince($0) } ?? 0
        let isWarning = duration >= reminderDelay
        let cooldownFinished = lastNotificationAt.map { date.timeIntervalSince($0) >= cooldown } ?? true
        let shouldNotify = isWarning && !notifiedForCurrentEpisode && cooldownFinished

        if shouldNotify {
            notifiedForCurrentEpisode = true
            lastNotificationAt = date
        }

        return PostureReading(
            angle: filteredAngle,
            sustainedDuration: duration,
            isBeyondThreshold: filteredAngle >= threshold,
            isWarning: isWarning,
            shouldNotify: shouldNotify
        )
    }

    func reset() {
        filteredAngle = 0
        resetEpisode()
    }

    private func resetEpisode() {
        badPostureStartedAt = nil
        notifiedForCurrentEpisode = false
    }

    private static func normalizedAngle(_ angle: Double) -> Double {
        var result = angle.truncatingRemainder(dividingBy: 360)
        if result > 180 { result -= 360 }
        if result < -180 { result += 360 }
        return result
    }
}

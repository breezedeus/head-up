import Foundation

/// Each display owns its samples and baseline. No samples or offsets are shared.
struct ScreenPrivacyDriftEstimator {
    private struct Observation {
        let time: TimeInterval
        let yaw: Double
    }
    private struct Track {
        var samples: [Observation] = []
        var baseline: Double?
        var correction = 0.0
    }
    private var tracks: [String: Track] = [:]
    private var previous: MotionSample?
    private var lastStored: TimeInterval?
    private var lastCheck: TimeInterval?
    static let checkInterval: TimeInterval = 10

    func corrected(_ display: ScreenPrivacyDisplayProfile) -> ScreenPrivacyCalibrationProfile {
        let base = display.calibration
        return base.recentered(
            yaw: ScreenPrivacyCalibrationProfile.normalizedAngle(base.centerYaw + (tracks[display.id]?.correction ?? 0)),
            pitch: base.centerPitch
        )
    }

    mutating func reset() { self = Self() }

    mutating func process(_ sample: MotionSample, displays: [ScreenPrivacyDisplayProfile], learningAllowed: Bool) {
        guard sample.yaw.isFinite, sample.pitch.isFinite, sample.sensorTimestamp.isFinite else { return }
        let now = sample.sensorTimestamp
        if let previous, now <= previous.sensorTimestamp || now - previous.sensorTimestamp > 5 {
            reset()
        }
        let old = previous
        previous = sample
        if lastCheck == nil { lastCheck = now }
        // Expire samples even when the user is outside or protection is active.
        for id in Array(tracks.keys) {
            tracks[id]?.samples.removeAll { now - $0.time > 60 }
        }
        guard learningAllowed else { return }
        let owners = displays.filter { corrected($0).contains(yaw: sample.yaw, pitch: sample.pitch, inset: 3) }
        // Overlaps cannot be attributed confidently to a physical display.
        if owners.count == 1, let display = owners.first, let old {
            let dt = now - old.sensorTimestamp
            let yawSpeed = abs(ScreenPrivacyCalibrationProfile.normalizedAngle(sample.yaw - old.yaw)) / dt
            let pitchSpeed = abs(sample.pitch - old.pitch) / dt
            if dt > 0, yawSpeed < 2, pitchSpeed < 2, now - (lastStored ?? -.infinity) >= 0.5 {
                var track = tracks[display.id] ?? Track()
                let yaw = ScreenPrivacyCalibrationProfile.normalizedAngle(sample.yaw - display.calibration.centerYaw)
                track.samples.append(Observation(time: now, yaw: yaw))
                tracks[display.id] = track
                lastStored = now
            }
        }
        guard now - (lastCheck ?? now) >= Self.checkInterval else { return }
        lastCheck = now
        for display in displays {
            guard var track = tracks[display.id], track.samples.count >= 20,
                  let first = track.samples.first, let last = track.samples.last,
                  last.time - first.time >= 10, now - last.time <= 2 else { continue }
            let sorted = track.samples.map(\.yaw).sorted()
            // Wide or changing reading distributions are not a reliable drift signal.
            guard sorted[sorted.count * 3 / 4] - sorted[sorted.count / 4] <= 6 else { continue }
            let middle = sorted.count / 2
            let median = sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
            if let baseline = track.baseline {
                let limit = min(15, min(display.calibration.leftAngle, display.calibration.rightAngle) * 0.5)
                let target = max(-limit, min(limit, median - baseline))
                track.correction += max(-0.5, min(0.5, (target - track.correction) * 0.25))
            } else {
                track.baseline = median
            }
            tracks[display.id] = track
        }
    }
}

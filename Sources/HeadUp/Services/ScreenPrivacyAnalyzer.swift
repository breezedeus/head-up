import Foundation

final class ScreenPrivacyAnalyzer {
    private(set) var phase: ScreenPrivacyPhase = .watching
    private var transitionStartedAt: TimeInterval?

    func process(
        yaw: Double,
        pitch: Double,
        at timestamp: TimeInterval,
        profile: ScreenPrivacyCalibrationProfile,
        thresholds: ScreenPrivacyThresholds
    ) -> ScreenPrivacyReading {
        let offsets = profile.offsets(yaw: yaw, pitch: pitch)
        let outside = offsets.horizontal > profile.leftAngle
            || offsets.horizontal < -profile.rightAngle
            || offsets.vertical > profile.upAngle
            || offsets.vertical < -profile.downAngle
        let insideRecovery = offsets.horizontal <= max(0, profile.leftAngle - thresholds.hysteresis)
            && offsets.horizontal >= -max(0, profile.rightAngle - thresholds.hysteresis)
            && offsets.vertical <= max(0, profile.upAngle - thresholds.hysteresis)
            && offsets.vertical >= -max(0, profile.downAngle - thresholds.hysteresis)

        transition(outside: outside, insideRecovery: insideRecovery, at: timestamp, thresholds: thresholds)

        return ScreenPrivacyReading(
            phase: phase,
            horizontalOffset: offsets.horizontal,
            verticalOffset: offsets.vertical
        )
    }

    func process(
        yaw: Double, pitch: Double, at timestamp: TimeInterval,
        profiles: [ScreenPrivacyCalibrationProfile], thresholds: ScreenPrivacyThresholds
    ) -> ScreenPrivacyReading {
        let outside = !profiles.contains { $0.contains(yaw: yaw, pitch: pitch) }
        let recovery = profiles.contains { $0.contains(yaw: yaw, pitch: pitch, inset: thresholds.hysteresis) }
        transition(outside: outside, insideRecovery: recovery, at: timestamp, thresholds: thresholds)
        let nearest = profiles.min {
            let a = $0.offsets(yaw: yaw, pitch: pitch)
            let b = $1.offsets(yaw: yaw, pitch: pitch)
            return hypot(a.horizontal, a.vertical) < hypot(b.horizontal, b.vertical)
        }
        let offset = nearest?.offsets(yaw: yaw, pitch: pitch) ?? (horizontal: 0, vertical: 0)
        return ScreenPrivacyReading(phase: phase, horizontalOffset: offset.horizontal, verticalOffset: offset.vertical)
    }

    private func transition(outside: Bool, insideRecovery: Bool, at timestamp: TimeInterval,
                            thresholds: ScreenPrivacyThresholds) {
        switch phase {
        case .watching:
            if outside {
                if thresholds.hideDelay <= 0 {
                    phase = .covered
                } else {
                    phase = .waitingToCover
                    transitionStartedAt = timestamp
                }
            }

        case .waitingToCover:
            if !outside {
                phase = .watching
                transitionStartedAt = nil
            } else if let startedAt = transitionStartedAt,
                      timestamp - startedAt >= thresholds.hideDelay {
                phase = .covered
                transitionStartedAt = nil
            }

        case .covered:
            if insideRecovery {
                if thresholds.revealDelay <= 0 {
                    phase = .watching
                } else {
                    phase = .waitingToReveal
                    transitionStartedAt = timestamp
                }
            }

        case .waitingToReveal:
            if !insideRecovery {
                phase = .covered
                transitionStartedAt = nil
            } else if let startedAt = transitionStartedAt,
                      timestamp - startedAt >= thresholds.revealDelay {
                phase = .watching
                transitionStartedAt = nil
            }
        }

    }

    func reset(covered: Bool = false) {
        phase = covered ? .covered : .watching
        transitionStartedAt = nil
    }
}

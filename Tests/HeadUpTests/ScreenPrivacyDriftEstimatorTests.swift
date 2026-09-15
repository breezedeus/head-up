import Foundation
import Testing
@testable import HeadUp

struct ScreenPrivacyDriftEstimatorTests {
    private func display(_ id: String, _ center: Double) -> ScreenPrivacyDisplayProfile {
        .init(id: id, name: id, calibration: .init(centerYaw: center, centerPitch: 0,
            leftYawDirection: 1, upPitchDirection: 1, leftAngle: 18, rightAngle: 18, upAngle: 15, downAngle: 15))
    }
    private func sample(_ time: Double, _ yaw: Double) -> MotionSample {
        .init(pitch: 0, roll: 0, yaw: yaw, sensorTimestamp: time, timestamp: Date(timeIntervalSince1970: time))
    }

    @Test func onlyTheObservedDisplayLearnsDrift() {
        let a = display("a", -30), b = display("b", 30)
        var estimator = ScreenPrivacyDriftEstimator()
        for i in 0...600 {
            let t = Double(i) * 0.5
            let drift = max(0, min(5, (t - 30) * 0.03))
            estimator.process(sample(t, -30 + drift), displays: [a, b], learningAllowed: true)
        }
        #expect(estimator.corrected(a).centerYaw > -27)
        #expect(estimator.corrected(b).centerYaw == 30)
    }

    @Test func screenSwitchesDoNotPullCentersTogether() {
        let a = display("a", -30), b = display("b", 30)
        var estimator = ScreenPrivacyDriftEstimator()
        for i in 0...600 {
            let t = Double(i) * 0.5
            estimator.process(sample(t, Int(t / 30).isMultiple(of: 2) ? -30 : 30), displays: [a, b], learningAllowed: true)
        }
        #expect(estimator.corrected(a).centerYaw == -30)
        #expect(estimator.corrected(b).centerYaw == 30)
    }

    @Test func overlappingSamplesAndCoveredSamplesNeverTeach() {
        let a = display("a", 0), b = display("b", 5)
        var estimator = ScreenPrivacyDriftEstimator()
        for i in 0...300 {
            let t = Double(i) * 0.5
            estimator.process(sample(t, min(8, t * 0.05)), displays: [a, b], learningAllowed: true)
        }
        #expect(estimator.corrected(a).centerYaw == 0)
        #expect(estimator.corrected(b).centerYaw == 5)
        for i in 301...600 {
            estimator.process(sample(Double(i) * 0.5, 8), displays: [a], learningAllowed: false)
        }
        #expect(estimator.corrected(a).centerYaw == 0)
    }

    @Test func circularBoundaryAndCadenceRemainStable() {
        let a = display("a", 179)
        var estimator = ScreenPrivacyDriftEstimator()
        var last = 179.0
        for i in 0...400 {
            let t = Double(i) * 0.5
            let yaw = ScreenPrivacyCalibrationProfile.normalizedAngle(179 + max(0, min(4, (t - 30) * 0.04)))
            estimator.process(sample(t, yaw), displays: [a], learningAllowed: true)
            let current = estimator.corrected(a).centerYaw
            if i % 20 != 0 { #expect(current == last) }
            #expect(abs(ScreenPrivacyCalibrationProfile.normalizedAngle(current - last)) <= 1.0 + 1e-9)
            last = current
        }
        #expect(ScreenPrivacyCalibrationProfile.normalizedAngle(last - 179) > 2)
        estimator.reset()
        #expect(estimator.corrected(a).centerYaw == 179)
    }

    @Test func preExistingOffsetIsGraduallyRemovedWithoutBaselineLock() {
        // The offset exists from the very first sample; the old baseline lock kept it forever.
        let a = display("a", 0)
        var estimator = ScreenPrivacyDriftEstimator()
        for i in 0...100 {
            let t = Double(i) * 0.5
            estimator.process(sample(t, 6), displays: [a], learningAllowed: true)
        }
        #expect(estimator.corrected(a).centerYaw > 3)
        if case .applied = estimator.status(for: "a").outcome { } else {
            Issue.record("Expected an applied evaluation, got \(estimator.status(for: "a").outcome)")
        }
    }

    @Test func pitchDriftIsCorrectedIndependently() {
        let a = display("a", 0)
        var estimator = ScreenPrivacyDriftEstimator()
        for i in 0...80 {
            let t = Double(i) * 0.5
            estimator.process(
                .init(pitch: 4, roll: 0, yaw: 0, sensorTimestamp: t, timestamp: Date(timeIntervalSince1970: t)),
                displays: [a], learningAllowed: true
            )
        }
        #expect(estimator.status(for: "a").pitchCorrection > 2)
        #expect(abs(estimator.status(for: "a").yawCorrection) < 1e-9)
        #expect(abs(estimator.corrected(a).centerPitch - 4) < 2)
    }

    @Test func suspendedLearningFreezesCorrectionAndReportsReason() {
        let a = display("a", 0)
        var estimator = ScreenPrivacyDriftEstimator()
        for i in 0...40 {
            let t = Double(i) * 0.5
            estimator.process(sample(t, 4), displays: [a], learningAllowed: true)
        }
        let frozen = estimator.status(for: "a").yawCorrection
        #expect(frozen > 0)
        for i in 41...80 {
            let t = Double(i) * 0.5
            estimator.process(sample(t, 4), displays: [a], learningAllowed: false)
        }
        #expect(estimator.status(for: "a").yawCorrection == frozen)
        #expect(estimator.status(for: "a").outcome == .learningSuspended)
    }

    @Test func sparseSamplesReportInsufficientReason() {
        let a = display("a", 0)
        var estimator = ScreenPrivacyDriftEstimator()
        for i in 0...10 {
            estimator.process(sample(Double(i), 2), displays: [a], learningAllowed: true)
        }
        guard case .insufficientSamples(let have, let needed) = estimator.status(for: "a").outcome else {
            Issue.record("Expected insufficientSamples, got \(estimator.status(for: "a").outcome)")
            return
        }
        #expect(have == 10)
        #expect(needed == ScreenPrivacyDriftEstimator.minimumSampleCount)
    }

    // MARK: Stall recovery

    /// The deadlock: drift larger than a boundary angle pushes the head out of the
    /// work area, which suspends learning, which is the only thing that could correct
    /// the drift. Without recovery the display stays covered until a recalibration.
    @Test func driftBeyondTheBoundaryStillRecovers() {
        let a = display("a", 0)
        var estimator = ScreenPrivacyDriftEstimator()
        var recovered = false
        // 25° of accumulated drift against an 18° boundary: the head is parked outside
        // the work area, so learning is suspended — and learning is the only thing
        // that could bring the work area back. `learningAllowed` is derived the way
        // the store derives it, so the loop reproduces the closed cycle.
        for i in 0...500 {
            let t = Double(i) * 0.5
            let inside = estimator.corrected(a).contains(yaw: 25, pitch: 0)
            estimator.process(sample(t, 25), displays: [a], learningAllowed: inside)
            if case .recovered = estimator.status(for: "a").outcome { recovered = true }
        }
        #expect(recovered)
        // The work area now sits on the pose actually being held, and normal learning
        // has resumed rather than staying frozen.
        #expect(abs(estimator.corrected(a).centerYaw - 25) < 1)
        #expect(estimator.corrected(a).contains(yaw: 25, pitch: 0))
        #expect(estimator.status(for: "a").outcome != .learningSuspended)
    }

    /// Recovery must not become a way to switch protection off by looking away, so it
    /// only reaches a little past a boundary.
    @Test func aDeliberateLargeTurnNeverRecovers() {
        let a = display("a", 0)
        var estimator = ScreenPrivacyDriftEstimator()
        // 60° away: far beyond `recoveryReach`, so no pose here is ever admitted.
        for i in 0...800 {
            let t = Double(i) * 0.5
            estimator.process(sample(t, 60), displays: [a], learningAllowed: false)
        }
        #expect(estimator.status(for: "a").outcome == .learningSuspended)
        #expect(estimator.corrected(a).centerYaw == 0)
    }

    /// A stall shorter than the grace period is left alone.
    @Test func shortStallsDoNotRecover() {
        let a = display("a", 0)
        var estimator = ScreenPrivacyDriftEstimator()
        for i in 0...200 {
            let t = Double(i) * 0.5
            estimator.process(sample(t, 22), displays: [a], learningAllowed: false)
        }
        #expect(estimator.status(for: "a").outcome == .learningSuspended)
        #expect(estimator.corrected(a).centerYaw == 0)
    }

    /// Recovery needs a genuinely parked head, not one passing through.
    @Test func restlessPosesDoNotRecover() {
        let a = display("a", 0)
        var estimator = ScreenPrivacyDriftEstimator()
        for i in 0...800 {
            let t = Double(i) * 0.5
            // Swings across 8°, above `recoveryMaximumSpread`, while staying slow
            // enough to pass the stationary-speed gate.
            estimator.process(sample(t, 22 + (Double(i % 8) - 4)), displays: [a], learningAllowed: false)
        }
        #expect(estimator.status(for: "a").outcome == .learningSuspended)
        #expect(estimator.corrected(a).centerYaw == 0)
    }

    /// Overlapping candidates cannot be attributed to one physical display.
    @Test func ambiguousRecoveryCandidatesAreIgnored() {
        let a = display("a", 0), b = display("b", 8)
        var estimator = ScreenPrivacyDriftEstimator()
        for i in 0...800 {
            let t = Double(i) * 0.5
            estimator.process(sample(t, 24), displays: [a, b], learningAllowed: false)
        }
        #expect(estimator.corrected(a).centerYaw == 0)
        #expect(estimator.corrected(b).centerYaw == 8)
    }

    // MARK: Stream interruptions

    /// Physical drift does not reset because the sample stream hiccupped. Dropping the
    /// correction would snap the work area back by exactly the drift it had removed.
    @Test func aStreamGapKeepsWhatWasLearned() {
        let a = display("a", 0)
        var estimator = ScreenPrivacyDriftEstimator()
        for i in 0...100 {
            estimator.process(sample(Double(i) * 0.5, 6), displays: [a], learningAllowed: true)
        }
        let learned = estimator.status(for: "a").yawCorrection
        #expect(learned > 3)
        // A gap longer than the 5s tolerance, as on an AirPods reconnect.
        estimator.process(sample(200, 6), displays: [a], learningAllowed: true)
        #expect(estimator.status(for: "a").yawCorrection == learned)
        // Drive one more evaluation: the buffer was emptied, so the window is short
        // again even though the correction survived.
        for i in 1...20 {
            estimator.process(sample(200 + Double(i) * 0.5, 6), displays: [a], learningAllowed: true)
        }
        #expect(estimator.status(for: "a").sampleCount == 20)
        #expect(estimator.status(for: "a").yawCorrection == learned)
        // A full reset is still available for when the reference center changes.
        estimator.reset()
        #expect(estimator.corrected(a).centerYaw == 0)
    }

    // MARK: Correction budget

    /// Drift is unbounded in time, so the correction must be able to exceed the old
    /// `min(15, min(left, right) * 0.5)` ceiling. A tight work area used to cap the
    /// correction at half its smallest boundary and could never catch up.
    @Test func narrowWorkAreasStillTrackLargeDrift() {
        let narrow = ScreenPrivacyDisplayProfile(id: "n", name: "n", calibration: .init(
            centerYaw: 0, centerPitch: 0, leftYawDirection: 1, upPitchDirection: 1,
            leftAngle: 8, rightAngle: 8, upAngle: 8, downAngle: 8))
        var estimator = ScreenPrivacyDriftEstimator()
        // Ramps to 20°, far past the 4° the old rule allowed for this work area.
        for i in 0...3_600 {
            let t = Double(i) * 0.5
            let inside = estimator.corrected(narrow).contains(yaw: min(20, t * 0.015), pitch: 0)
            estimator.process(sample(t, min(20, t * 0.015)), displays: [narrow], learningAllowed: inside)
        }
        #expect(estimator.status(for: "n").yawCorrection > 15)
    }

    // MARK: Feed-forward

    /// A pure proportional controller trails a ramp forever. Feeding the measured rate
    /// forward keeps the residual small enough to matter for boundary margins.
    @Test func steadyDriftIsTrackedWithSmallResidual() {
        let a = display("a", 0)
        var estimator = ScreenPrivacyDriftEstimator()
        var worstResidual = 0.0
        // 2°/min for 10 minutes.
        for i in 0...1_200 {
            let t = Double(i) * 0.5
            let drift = t * (2.0 / 60)
            estimator.process(sample(t, drift), displays: [a], learningAllowed: true)
            if t > 180 {
                worstResidual = max(worstResidual, abs(drift - estimator.status(for: "a").yawCorrection))
            }
        }
        #expect(worstResidual < 2.0)
    }

    // MARK: Per-display sample throttling

    /// The 0.5s store throttle is per display. A head creeping across the seam between
    /// two adjacent work areas is the reachable case: with a shared throttle, the
    /// display being entered loses samples to the one just left.
    @Test func crossingASeamDoesNotThrottleTheNextDisplay() {
        let a = display("a", 0), b = display("b", 36)
        var estimator = ScreenPrivacyDriftEstimator()
        // Creeps from 0° to 36° at 1°/s, below the stationary-speed limit, so poses on
        // both sides of the seam qualify.
        for i in 0...1_000 {
            let t = Double(i) * 0.05
            estimator.process(sample(t, min(36, t * 1.0)), displays: [a, b], learningAllowed: true)
        }
        #expect(estimator.status(for: "a").sampleCount > 0)
        #expect(estimator.status(for: "b").sampleCount > 0)
    }

    @Test func multipleScreenUnionPreservesCoverAndRecoveryDelay() {
        let a = display("a", -30), b = display("b", 30)
        let analyzer = ScreenPrivacyAnalyzer()
        let limits = ScreenPrivacyThresholds(hideDelay: 0.8, revealDelay: 0.3, hysteresis: 3)
        let profiles = [a.calibration, b.calibration]
        #expect(analyzer.process(yaw: -30, pitch: 0, at: 0, profiles: profiles, thresholds: limits).phase == .watching)
        #expect(analyzer.process(yaw: 0, pitch: 0, at: 1, profiles: profiles, thresholds: limits).phase == .waitingToCover)
        #expect(analyzer.process(yaw: 30, pitch: 0, at: 1.5, profiles: profiles, thresholds: limits).phase == .watching)
        _ = analyzer.process(yaw: 80, pitch: 0, at: 2, profiles: profiles, thresholds: limits)
        #expect(analyzer.process(yaw: 80, pitch: 0, at: 3, profiles: profiles, thresholds: limits).phase == .covered)
        #expect(analyzer.process(yaw: 30, pitch: 0, at: 4, profiles: profiles, thresholds: limits).phase == .waitingToReveal)
        #expect(analyzer.process(yaw: 30, pitch: 0, at: 4.5, profiles: profiles, thresholds: limits).phase == .watching)
    }
}

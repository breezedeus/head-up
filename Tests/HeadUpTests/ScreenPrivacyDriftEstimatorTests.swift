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
            #expect(abs(ScreenPrivacyCalibrationProfile.normalizedAngle(current - last)) <= 0.5)
            last = current
        }
        #expect(ScreenPrivacyCalibrationProfile.normalizedAngle(last - 179) > 2)
        estimator.reset()
        #expect(estimator.corrected(a).centerYaw == 179)
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

import Foundation

/// Why a scheduled drift check did (or did not) move a display center.
/// Diagnostics are surfaced in Settings and written to the Privacy log category.
struct ScreenPrivacyDriftStatus: Equatable {
    enum Outcome: Equatable {
        case gathering
        case applied(stepYaw: Double, stepPitch: Double)
        case steady
        case insufficientSamples(have: Int, needed: Int)
        case windowTooShort(have: TimeInterval, needed: TimeInterval)
        case samplesStale(age: TimeInterval)
        case distributionTooWide(iqrYaw: Double, iqrPitch: Double, limit: Double)
        case learningSuspended
        /// A long stall was broken by re-centering on the head pose the user
        /// actually held while covered. See `ScreenPrivacyDriftEstimator.recover`.
        case recovered(stepYaw: Double, stepPitch: Double)

        var shortText: String {
            switch self {
            case .gathering:
                return L10n.text("正在积累稳定样本")
            case .applied(let stepYaw, let stepPitch):
                return L10n.text("刚完成微调 水平 {0}° 垂直 {1}°",
                                 Self.degrees(stepYaw), Self.degrees(stepPitch))
            case .steady:
                return L10n.text("工作区中心稳定")
            case .insufficientSamples(let have, let needed):
                return L10n.text("正在收集有效样本（{0}/{1}）", "\(have)", "\(needed)")
            case .windowTooShort(let have, let needed):
                return L10n.text("采样时长不足（{0}/{1} 秒）",
                                 Self.seconds(have), Self.seconds(needed))
            case .samplesStale:
                return L10n.text("近期没有稳定样本，暂不修正")
            case .distributionTooWide:
                return L10n.text("头部活动较多，暂不修正")
            case .learningSuspended:
                return L10n.text("暂停或遮挡期间不学习")
            case .recovered(let stepYaw, let stepPitch):
                return L10n.text("已自动重新对准工作区 水平 {0}° 垂直 {1}°",
                                 Self.degrees(stepYaw), Self.degrees(stepPitch))
            }
        }

        private static func degrees(_ value: Double) -> String {
            (value >= 0 ? "+" : "") + value.formatted(.number.precision(.fractionLength(2)))
        }

        private static func seconds(_ value: TimeInterval) -> String {
            value.formatted(.number.precision(.fractionLength(0)))
        }
    }

    var sampleCount: Int = 0
    var yawCorrection: Double = 0
    var pitchCorrection: Double = 0
    var medianYawOffset: Double?
    var medianPitchOffset: Double?
    var lastEvaluatedAt: TimeInterval?
    var outcome: Outcome = .gathering
}
/// Each display owns its samples and corrections. No samples or offsets are shared.
/// Corrections are measured against the original calibration center: the first
/// batch of data is never treated as a zero-offset baseline, so drift that already
/// existed when learning started is still removed gradually.
///
/// Sensor yaw drifts without bound over a long session, so the estimator is built
/// around three ideas:
///
/// 1. **Corrections survive stream interruptions.** Physical drift does not reset
///    because AirPods dropped a few seconds of samples, so `resetSamples` clears the
///    observation buffer but keeps what has been learned. Only a new calibration
///    (which redefines the reference center) does a full `reset`.
/// 2. **The correction is bounded by rate, not by an absolute ceiling.** Drift grows
///    without bound, so any fixed cap is eventually exceeded and leaves the work area
///    permanently offset. A wrong correction is instead contained by the per-check
///    slew limit, the symmetric acceptance window, and the spread gate.
/// 3. **A stall can always be broken.** Normal learning needs the head inside the
///    work area, which is circular: correcting drift requires being inside, and
///    being inside requires the drift already corrected. `recover` breaks that loop
///    from a separate, deliberately conservative sample pool.
struct ScreenPrivacyDriftEstimator {
    private struct Observation {
        let time: TimeInterval
        let yaw: Double
        let pitch: Double
    }
    private struct Track {
        var samples: [Observation] = []
        var yawCorrection = 0.0
        var pitchCorrection = 0.0
        var status = ScreenPrivacyDriftStatus()
        /// When this display first contributed a sample, used for the settling lane.
        var learningStartedAt: TimeInterval?
        /// Per-display so one display's samples cannot throttle another's.
        var lastStored: TimeInterval?
        /// Stationary poses observed while learning was suspended.
        var recovery: [Observation] = []
    }

    private var tracks: [String: Track] = [:]
    private var previous: MotionSample?
    private var lastCheck: TimeInterval?
    /// Set on the first sample seen while learning is suspended; the recovery grace
    /// period is measured from here.
    private var stalledSince: TimeInterval?
    #if HEADUP_DEBUG
    private var lastVerboseTrace: TimeInterval?
    /// Preview builds can print at most one sample-level trace per second per estimator.
    static let verboseTraceInterval: TimeInterval = 1
    #endif

    static let checkInterval: TimeInterval = 10
    static let sampleWindow: TimeInterval = 60
    static let minimumSampleCount = 20
    static let minimumWindow: TimeInterval = 10
    static let maximumSampleAge: TimeInterval = 2
    static let maximumSpread = 6.0
    /// Largest center move per check while settling (first `settlingDuration` of a
    /// display's learning), used to clear an offset that was present at calibration.
    static let settlingStep = 1.0
    /// Steady-state limit. Deliberately close to the plausible physical drift rate
    /// (3°/min) so a user who merely sits off-center for a while cannot drag the work
    /// area as fast as real drift would.
    static let steadyStep = 0.5
    static let settlingDuration: TimeInterval = 90
    static let stepGain = 0.35
    /// Sanity bound only, not a drift budget.
    ///
    /// Sensor drift is unbounded in time, so *any* absolute ceiling on the accumulated
    /// correction is eventually exceeded and leaves the work area permanently offset —
    /// that is what the old `min(15, min(left, right) * 0.5)` rule did. What actually
    /// keeps a wrong correction in check is the per-check slew limit, the symmetric
    /// acceptance window, and the spread gate. This value only catches a runaway:
    /// past a quarter turn the yaw reference is meaningless anyway.
    static let maximumCorrectionAllowance = 90.0
    static let stationarySpeedLimit = 2.0
    static let storeInterval: TimeInterval = 0.5
    static let interiorInset = 3.0
    /// A pure proportional controller lags a ramp input forever, so the measured
    /// drift rate is projected forward over this horizon. It covers the median's own
    /// lag (~½ window) plus the controller's settling lag.
    static let feedForwardHorizon: TimeInterval = 60
    static let maximumFeedForward = 2.0
    /// Rates outside this band are noise or real head motion, not sensor drift.
    static let maximumDriftRate = 0.2

    // MARK: Stall recovery

    /// How long the work area must stay unreachable before recovery is considered.
    static let stallGracePeriod: TimeInterval = 180
    /// Recovery only reaches this far beyond a boundary. A deliberate large turn
    /// (talking to someone, leaving the desk) stays far outside and never qualifies,
    /// so protection cannot be unlocked by holding a turned pose.
    static let recoveryReach = 12.0
    static let recoveryMinimumSamples = 20
    static let recoveryMinimumWindow: TimeInterval = 30
    /// Recovery demands a much tighter pose than normal learning: the head must be
    /// genuinely parked, not merely passing through.
    static let recoveryMaximumSpread = 3.0

    func corrected(_ display: ScreenPrivacyDisplayProfile) -> ScreenPrivacyCalibrationProfile {
        let base = display.calibration
        let track = tracks[display.id]
        return base.recentered(
            yaw: ScreenPrivacyCalibrationProfile.normalizedAngle(base.centerYaw + (track?.yawCorrection ?? 0)),
            pitch: base.centerPitch + (track?.pitchCorrection ?? 0)
        )
    }

    func status(for id: String) -> ScreenPrivacyDriftStatus {
        tracks[id]?.status ?? ScreenPrivacyDriftStatus()
    }

    var statusByID: [String: ScreenPrivacyDriftStatus] {
        tracks.mapValues(\.status)
    }

    /// Full reset. Only correct when the reference center itself changes, because it
    /// discards everything learned about the sensor's drift.
    mutating func reset(reason: String = "manual") {
        if tracks.contains(where: { $0.value.yawCorrection != 0 || $0.value.pitchCorrection != 0 }) {
            HeadUpLog.privacy.info("Drift learning reset (\(reason, privacy: .public)); all display centers restored to calibration")
        } else {
            HeadUpLog.privacy.debug("Drift learning reset (\(reason, privacy: .public))")
        }
        self = Self()
    }

    /// Drops buffered observations but keeps the corrections learned so far.
    ///
    /// Used when the sample stream breaks (AirPods reconnect, sensor time jump).
    /// The accumulated physical drift is unchanged by the interruption, so throwing
    /// the correction away would snap the work area back by exactly the drift that
    /// had been compensated — usually straight out of the work area, which used to
    /// strand learning permanently.
    mutating func resetSamples(reason: String) {
        HeadUpLog.privacy.debug("Drift samples cleared (\(reason, privacy: .public)); corrections kept")
        for id in tracks.keys {
            tracks[id]?.samples.removeAll()
            tracks[id]?.recovery.removeAll()
            tracks[id]?.lastStored = nil
        }
        previous = nil
        lastCheck = nil
        stalledSince = nil
    }
    /// Returns true when a scheduled evaluation pass ran on this sample, so the caller
    /// can republish per-display diagnostics.
    @discardableResult
    mutating func process(_ sample: MotionSample, displays: [ScreenPrivacyDisplayProfile], learningAllowed: Bool) -> Bool {
        guard sample.yaw.isFinite, sample.pitch.isFinite, sample.sensorTimestamp.isFinite else { return false }
        let now = sample.sensorTimestamp
        if let previous, now <= previous.sensorTimestamp || now - previous.sensorTimestamp > 5 {
            // Keep the corrections: the head kept drifting while the stream was down.
            resetSamples(reason: "sensor time gap")
        }
        let old = previous
        previous = sample
        if lastCheck == nil { lastCheck = now }
        // Expire samples even when the user is outside or protection is active.
        for id in Array(tracks.keys) {
            tracks[id]?.samples.removeAll { now - $0.time > Self.sampleWindow }
            tracks[id]?.recovery.removeAll { now - $0.time > Self.sampleWindow }
        }
        if learningAllowed {
            stalledSince = nil
            for id in Array(tracks.keys) { tracks[id]?.recovery.removeAll() }
        } else if stalledSince == nil {
            stalledSince = now
        }

        if let old {
            let dt = now - old.sensorTimestamp
            let yawSpeed = dt > 0 ? abs(ScreenPrivacyCalibrationProfile.normalizedAngle(sample.yaw - old.yaw)) / dt : 0
            let pitchSpeed = dt > 0 ? abs(sample.pitch - old.pitch) / dt : 0
            let moving = yawSpeed >= Self.stationarySpeedLimit || pitchSpeed >= Self.stationarySpeedLimit
            if learningAllowed {
                store(sample, at: now, displays: displays, dt: dt,
                      yawSpeed: yawSpeed, pitchSpeed: pitchSpeed, moving: moving)
            } else if dt > 0, !moving {
                storeRecovery(sample, at: now, displays: displays)
            }
        }

        guard now - (lastCheck ?? now) >= Self.checkInterval else { return false }
        lastCheck = now
        for display in displays {
            evaluate(display, at: now, learningAllowed: learningAllowed)
        }
        return true
    }

    /// Buffers one in-work-area pose for normal drift learning.
    private mutating func store(
        _ sample: MotionSample, at now: TimeInterval,
        displays: [ScreenPrivacyDisplayProfile], dt: TimeInterval,
        yawSpeed: Double, pitchSpeed: Double, moving: Bool
    ) {
        let owners = displays.filter { corrected($0).contains(yaw: sample.yaw, pitch: sample.pitch, inset: Self.interiorInset) }
        // Overlaps cannot be attributed confidently to a physical display.
        guard owners.count == 1, let display = owners.first,
              let base = displays.first(where: { $0.id == display.id })?.calibration else {
            #if HEADUP_DEBUG
            traceAttribution(
                sample: sample, now: now, owners: owners, displays: displays,
                storedDisplay: nil, storedCount: nil, yawOffset: nil, pitchOffset: nil,
                yawSpeed: owners.count == 1 ? yawSpeed : nil,
                pitchSpeed: owners.count == 1 ? pitchSpeed : nil,
                moving: owners.count == 1 ? moving : false, throttled: false
            )
            #endif
            return
        }
        var track = tracks[display.id] ?? Track()
        let throttled = now - (track.lastStored ?? -.infinity) < Self.storeInterval
        let yawOffset = ScreenPrivacyCalibrationProfile.normalizedAngle(sample.yaw - base.centerYaw)
        let pitchOffset = sample.pitch - base.centerPitch
        // Collect from a symmetric window around the current corrected center rather
        // than from the whole (asymmetric, boundary-clipped) work area. Clipping the
        // sample distribution at the decision boundary biases the median back toward
        // the center, which systematically under-estimates the drift being measured.
        let radius = Self.acceptanceRadius(for: base)
        let inWindow = abs(yawOffset - track.yawCorrection) <= radius
            && abs(pitchOffset - track.pitchCorrection) <= radius
        guard dt > 0, !moving, !throttled, inWindow else {
            #if HEADUP_DEBUG
            traceAttribution(
                sample: sample, now: now, owners: owners, displays: displays,
                storedDisplay: nil, storedCount: nil, yawOffset: nil, pitchOffset: nil,
                yawSpeed: yawSpeed, pitchSpeed: pitchSpeed, moving: moving, throttled: throttled
            )
            #endif
            return
        }
        track.samples.append(Observation(time: now, yaw: yawOffset, pitch: pitchOffset))
        track.lastStored = now
        if track.learningStartedAt == nil { track.learningStartedAt = now }
        tracks[display.id] = track
        #if HEADUP_DEBUG
        traceAttribution(
            sample: sample, now: now, owners: owners, displays: displays,
            storedDisplay: display, storedCount: track.samples.count,
            yawOffset: yawOffset, pitchOffset: pitchOffset,
            yawSpeed: yawSpeed, pitchSpeed: pitchSpeed, moving: moving, throttled: throttled
        )
        #endif
    }

    /// Buffers one stationary pose held while the work area was unreachable.
    ///
    /// Attribution reuses the uniqueness rule of normal learning, on a work area
    /// widened by `recoveryReach`: a pose just outside one display qualifies, while a
    /// pose that could belong to two displays, or one far outside every display, does not.
    private mutating func storeRecovery(
        _ sample: MotionSample, at now: TimeInterval, displays: [ScreenPrivacyDisplayProfile]
    ) {
        let candidates = displays.filter {
            corrected($0).contains(yaw: sample.yaw, pitch: sample.pitch, inset: -Self.recoveryReach)
        }
        guard candidates.count == 1, let display = candidates.first,
              let base = displays.first(where: { $0.id == display.id })?.calibration else { return }
        var track = tracks[display.id] ?? Track()
        guard now - (track.recovery.last?.time ?? -.infinity) >= Self.storeInterval else { return }
        track.recovery.append(Observation(
            time: now,
            yaw: ScreenPrivacyCalibrationProfile.normalizedAngle(sample.yaw - base.centerYaw),
            pitch: sample.pitch - base.centerPitch
        ))
        tracks[display.id] = track
    }

    /// Widest symmetric offset window that still fits inside the work area interior,
    /// so the collected distribution is never clipped on one side only.
    private static func acceptanceRadius(for base: ScreenPrivacyCalibrationProfile) -> Double {
        let tightest = min(base.leftAngle, base.rightAngle, base.upAngle, base.downAngle)
        return max(0, tightest - Self.interiorInset)
    }
    #if HEADUP_DEBUG
    private mutating func traceAttribution(
        sample: MotionSample,
        now: TimeInterval,
        owners: [ScreenPrivacyDisplayProfile],
        displays: [ScreenPrivacyDisplayProfile],
        storedDisplay: ScreenPrivacyDisplayProfile?,
        storedCount: Int?,
        yawOffset: Double?,
        pitchOffset: Double?,
        yawSpeed: Double?,
        pitchSpeed: Double?,
        moving: Bool,
        throttled: Bool
    ) {
        guard now - (lastVerboseTrace ?? -.infinity) >= Self.verboseTraceInterval else { return }
        lastVerboseTrace = now
        switch owners.count {
        case 0:
            let zones = displays.map { display -> String in
                let c = corrected(display)
                let offset = c.offsets(yaw: sample.yaw, pitch: sample.pitch)
                return "\(display.name)[h\(HeadUpTrace.deg(offset.horizontal)),v\(HeadUpTrace.deg(offset.vertical)) / L\(Int(c.leftAngle)) R\(Int(c.rightAngle)) U\(Int(c.upAngle)) D\(Int(c.downAngle))]"
            }.joined(separator: " ")
            HeadUpTrace.driftVerbose("sample yaw \(HeadUpTrace.deg(sample.yaw)) pitch \(HeadUpTrace.deg(sample.pitch)) matches no display interior: \(zones)")
        case 2...:
            HeadUpTrace.driftVerbose("sample yaw \(HeadUpTrace.deg(sample.yaw)) pitch \(HeadUpTrace.deg(sample.pitch)) overlaps \(owners.count) displays \(owners.map(\.name)); not stored")
        default:
            guard let display = storedDisplay ?? owners.first else { return }
            if let storedCount, let yawOffset, let pitchOffset {
                let track = tracks[display.id]
                HeadUpTrace.driftVerbose("[\(display.name)] stored sample #\(storedCount) offset yaw \(HeadUpTrace.deg(yawOffset)) pitch \(HeadUpTrace.deg(pitchOffset)) (correction so far yaw \(HeadUpTrace.deg(track?.yawCorrection ?? 0)) pitch \(HeadUpTrace.deg(track?.pitchCorrection ?? 0)))")
            } else {
                let reason: String
                if moving, let yawSpeed, let pitchSpeed {
                    reason = "moving yawSpeed \(String(format: "%.2f", yawSpeed))°/s pitchSpeed \(String(format: "%.2f", pitchSpeed))°/s"
                } else if throttled {
                    reason = "store interval throttled"
                } else {
                    reason = "outside symmetric acceptance window"
                }
                HeadUpTrace.driftVerbose("[\(display.name)] sample rejected: \(reason)")
            }
        }
    }
    #endif

    private mutating func evaluate(_ display: ScreenPrivacyDisplayProfile, at now: TimeInterval, learningAllowed: Bool) {
        let base = display.calibration
        var track = tracks[display.id] ?? Track()
        var outcome: ScreenPrivacyDriftStatus.Outcome

        defer {
            track.status.sampleCount = track.samples.count
            track.status.yawCorrection = track.yawCorrection
            track.status.pitchCorrection = track.pitchCorrection
            track.status.lastEvaluatedAt = now
            track.status.outcome = outcome
            tracks[display.id] = track
        }

        let prefix = "[\(display.name)] evaluation at t=\(String(format: "%.1f", now))s, samples \(track.samples.count)"
        guard learningAllowed else {
            if let step = recover(&track, base: base, at: now, name: display.name) {
                outcome = .recovered(stepYaw: step.yaw, stepPitch: step.pitch)
            } else {
                outcome = .learningSuspended
                HeadUpTrace.drift("\(prefix): skip — learning suspended (paused or covered); correction frozen at yaw \(HeadUpTrace.deg(track.yawCorrection)) pitch \(HeadUpTrace.deg(track.pitchCorrection))")
            }
            return
        }
        guard track.samples.count >= Self.minimumSampleCount else {
            outcome = .insufficientSamples(have: track.samples.count, needed: Self.minimumSampleCount)
            HeadUpTrace.drift("\(prefix): skip — need \(Self.minimumSampleCount) samples")
            return
        }
        guard let first = track.samples.first, let last = track.samples.last,
              last.time - first.time >= Self.minimumWindow else {
            let span = track.samples.first.map { now - $0.time } ?? 0
            outcome = .windowTooShort(have: span, needed: Self.minimumWindow)
            HeadUpTrace.drift("\(prefix): skip — window span \(String(format: "%.1f", span))s < \(Self.minimumWindow)s")
            return
        }
        let sampleAge = now - last.time
        guard sampleAge <= Self.maximumSampleAge else {
            outcome = .samplesStale(age: sampleAge)
            HeadUpTrace.drift("\(prefix): skip — newest sample is \(String(format: "%.1f", sampleAge))s old")
            return
        }
        let yaws = track.samples.map(\.yaw).sorted()
        let pitches = track.samples.map(\.pitch).sorted()
        let iqrYaw = yaws[yaws.count * 3 / 4] - yaws[yaws.count / 4]
        let iqrPitch = pitches[pitches.count * 3 / 4] - pitches[pitches.count / 4]
        guard max(iqrYaw, iqrPitch) <= Self.maximumSpread else {
            outcome = .distributionTooWide(iqrYaw: iqrYaw, iqrPitch: iqrPitch, limit: Self.maximumSpread)
            HeadUpTrace.drift("\(prefix): skip — spread too wide (IQR yaw \(HeadUpTrace.deg(iqrYaw)) pitch \(HeadUpTrace.deg(iqrPitch)), limit \(Self.maximumSpread)°)")
            return
        }
        let medianYaw = Self.median(yaws)
        let medianPitch = Self.median(pitches)
        track.status.medianYawOffset = medianYaw
        track.status.medianPitchOffset = medianPitch

        // Feed forward the measured drift rate: a pure proportional controller trails
        // a ramp input by a fixed offset forever, and both the median and the
        // controller add lag of their own.
        let yawRate = Self.clampRate(Self.slope(track.samples, value: \.yaw))
        let pitchRate = Self.clampRate(Self.slope(track.samples, value: \.pitch))
        let yawFeedForward = Self.clampFeedForward(yawRate * Self.feedForwardHorizon)
        let pitchFeedForward = Self.clampFeedForward(pitchRate * Self.feedForwardHorizon)

        let allowance = Self.maximumCorrectionAllowance
        let targetYaw = max(-allowance, min(allowance, medianYaw + yawFeedForward))
        let targetPitch = max(-allowance, min(allowance, medianPitch + pitchFeedForward))
        let settling = now - (track.learningStartedAt ?? now) < Self.settlingDuration
        let maximumStep = settling ? Self.settlingStep : Self.steadyStep
        let stepYaw = max(-maximumStep, min(maximumStep, (targetYaw - track.yawCorrection) * Self.stepGain))
        let stepPitch = max(-maximumStep, min(maximumStep, (targetPitch - track.pitchCorrection) * Self.stepGain))
        track.yawCorrection += stepYaw
        track.pitchCorrection += stepPitch

        let saturated = abs(targetYaw) >= allowance - 1e-9 || abs(targetPitch) >= allowance - 1e-9
        let detail = "\(prefix), window \(String(format: "%.1f", last.time - first.time))s, median offset yaw \(HeadUpTrace.deg(medianYaw)) pitch \(HeadUpTrace.deg(medianPitch)), rate yaw \(String(format: "%.4f", yawRate))°/s pitch \(String(format: "%.4f", pitchRate))°/s, feed-forward yaw \(HeadUpTrace.deg(yawFeedForward)) pitch \(HeadUpTrace.deg(pitchFeedForward)), target yaw \(HeadUpTrace.deg(targetYaw)) pitch \(HeadUpTrace.deg(targetPitch)), allowance \(HeadUpTrace.deg(allowance))\(saturated ? " (saturated)" : ""), step yaw \(HeadUpTrace.deg(stepYaw)) pitch \(HeadUpTrace.deg(stepPitch)) limit \(HeadUpTrace.deg(maximumStep))\(settling ? " (settling)" : ""), total correction yaw \(HeadUpTrace.deg(track.yawCorrection)) pitch \(HeadUpTrace.deg(track.pitchCorrection)), calibrated center yaw \(HeadUpTrace.deg(base.centerYaw)) pitch \(HeadUpTrace.deg(base.centerPitch)), corrected center yaw \(HeadUpTrace.deg(base.centerYaw + track.yawCorrection)) pitch \(HeadUpTrace.deg(base.centerPitch + track.pitchCorrection))"
        if abs(stepYaw) >= 0.02 || abs(stepPitch) >= 0.02 {
            outcome = .applied(stepYaw: stepYaw, stepPitch: stepPitch)
            // Applied corrections are always visible, even in release builds.
            HeadUpLog.privacy.info("drift applied: \(detail, privacy: .public)")
        } else {
            outcome = .steady
            HeadUpTrace.drift("drift steady: \(detail)")
        }
    }
    /// Breaks a learning stall by re-centering on a pose the user demonstrably held
    /// while the work area was unreachable.
    ///
    /// Without this, drift larger than a boundary angle is unrecoverable: learning
    /// needs the head inside the work area, and drift is what put it outside. Four
    /// conditions must hold together, so this cannot be used to defeat protection by
    /// looking away:
    ///
    /// - the stall has lasted `stallGracePeriod`;
    /// - the pose is within `recoveryReach` of a single display, so a real turn away
    ///   from the desk never qualifies;
    /// - the head has been parked there for `recoveryMinimumWindow` within
    ///   `recoveryMaximumSpread`, much tighter than normal learning; and
    /// - the pose is current, not a stale buffer.
    private mutating func recover(
        _ track: inout Track, base: ScreenPrivacyCalibrationProfile,
        at now: TimeInterval, name: String
    ) -> (yaw: Double, pitch: Double)? {
        guard let stalledSince, now - stalledSince >= Self.stallGracePeriod,
              track.recovery.count >= Self.recoveryMinimumSamples,
              let first = track.recovery.first, let last = track.recovery.last,
              last.time - first.time >= Self.recoveryMinimumWindow,
              now - last.time <= Self.maximumSampleAge else { return nil }
        let yaws = track.recovery.map(\.yaw).sorted()
        let pitches = track.recovery.map(\.pitch).sorted()
        let spreadYaw = yaws[yaws.count * 3 / 4] - yaws[yaws.count / 4]
        let spreadPitch = pitches[pitches.count * 3 / 4] - pitches[pitches.count / 4]
        guard max(spreadYaw, spreadPitch) <= Self.recoveryMaximumSpread else { return nil }

        // Bounded by the recovery pool's own admission rule: every sample here already
        // had to be a stationary pose within `recoveryReach` of this display.
        let limit = Self.maximumCorrectionAllowance
        let targetYaw = max(-limit, min(limit, Self.median(yaws)))
        let targetPitch = max(-limit, min(limit, Self.median(pitches)))
        let stepYaw = targetYaw - track.yawCorrection
        let stepPitch = targetPitch - track.pitchCorrection
        guard abs(stepYaw) >= 0.02 || abs(stepPitch) >= 0.02 else { return nil }
        // Deliberately not rate-limited: the point is to escape the stall at once.
        track.yawCorrection = targetYaw
        track.pitchCorrection = targetPitch
        track.status.medianYawOffset = Self.median(yaws)
        track.status.medianPitchOffset = Self.median(pitches)
        // Old samples describe the previous center and would fight the new one.
        track.samples.removeAll()
        track.recovery.removeAll()
        track.lastStored = nil
        self.stalledSince = nil
        // Bound to locals: log interpolation is an escaping autoclosure and cannot
        // capture the inout `track`.
        let detail = "[\(name)] work area unreachable for \(String(format: "%.0f", now - stalledSince))s; "
            + "re-centered on the held pose (step yaw \(HeadUpTrace.deg(stepYaw)) pitch \(HeadUpTrace.deg(stepPitch)), "
            + "total correction yaw \(HeadUpTrace.deg(targetYaw)) pitch \(HeadUpTrace.deg(targetPitch)))"
        HeadUpLog.privacy.info("drift recovered: \(detail, privacy: .public)")
        return (stepYaw, stepPitch)
    }

    /// Least-squares slope in degrees per second over the buffered window.
    private static func slope(_ samples: [Observation], value: (Observation) -> Double) -> Double {
        guard let first = samples.first, samples.count >= 2 else { return 0 }
        let times = samples.map { $0.time - first.time }
        let values = samples.map(value)
        let count = Double(samples.count)
        let meanTime = times.reduce(0, +) / count
        let meanValue = values.reduce(0, +) / count
        var covariance = 0.0
        var variance = 0.0
        for (time, value) in zip(times, values) {
            covariance += (time - meanTime) * (value - meanValue)
            variance += (time - meanTime) * (time - meanTime)
        }
        guard variance > 1e-9 else { return 0 }
        return covariance / variance
    }

    private static func clampRate(_ rate: Double) -> Double {
        guard rate.isFinite else { return 0 }
        return max(-maximumDriftRate, min(maximumDriftRate, rate))
    }

    private static func clampFeedForward(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return max(-maximumFeedForward, min(maximumFeedForward, value))
    }

    private static func median(_ sorted: [Double]) -> Double {
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}





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
    }

    private var tracks: [String: Track] = [:]
    private var previous: MotionSample?
    private var lastStored: TimeInterval?
    private var lastCheck: TimeInterval?
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
    /// Largest center move per 10-second check (up to 6° per minute).
    static let maximumStep = 1.0
    static let stepGain = 0.3
    static let absoluteCorrectionLimit = 15.0
    static let stationarySpeedLimit = 2.0
    static let storeInterval: TimeInterval = 0.5
    static let interiorInset = 3.0

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

    mutating func reset(reason: String = "manual") {
        if tracks.contains(where: { $0.value.yawCorrection != 0 || $0.value.pitchCorrection != 0 }) {
            HeadUpLog.privacy.info("Drift learning reset (\(reason, privacy: .public)); all display centers restored to calibration")
        } else {
            HeadUpLog.privacy.debug("Drift learning reset (\(reason, privacy: .public))")
        }
        self = Self()
    }

    /// Returns true when a scheduled evaluation pass ran on this sample, so the caller
    /// can republish per-display diagnostics.
    @discardableResult
    mutating func process(_ sample: MotionSample, displays: [ScreenPrivacyDisplayProfile], learningAllowed: Bool) -> Bool {
        guard sample.yaw.isFinite, sample.pitch.isFinite, sample.sensorTimestamp.isFinite else { return false }
        let now = sample.sensorTimestamp
        if let previous, now <= previous.sensorTimestamp || now - previous.sensorTimestamp > 5 {
            reset(reason: "sensor time gap")
        }
        let old = previous
        previous = sample
        if lastCheck == nil { lastCheck = now }
        // Expire samples even when the user is outside or protection is active.
        for id in Array(tracks.keys) {
            tracks[id]?.samples.removeAll { now - $0.time > Self.sampleWindow }
        }
        if learningAllowed, let old {
            let owners = displays.filter { corrected($0).contains(yaw: sample.yaw, pitch: sample.pitch, inset: Self.interiorInset) }
            // Overlaps cannot be attributed confidently to a physical display.
            if owners.count == 1, let display = owners.first {
                let dt = now - old.sensorTimestamp
                let yawSpeed = dt > 0 ? abs(ScreenPrivacyCalibrationProfile.normalizedAngle(sample.yaw - old.yaw)) / dt : 0
                let pitchSpeed = dt > 0 ? abs(sample.pitch - old.pitch) / dt : 0
                let throttled = now - (lastStored ?? -.infinity) < Self.storeInterval
                let moving = yawSpeed >= Self.stationarySpeedLimit || pitchSpeed >= Self.stationarySpeedLimit
                if dt > 0, !moving, !throttled,
                   let base = displays.first(where: { $0.id == display.id })?.calibration {
                    var track = tracks[display.id] ?? Track()
                    let yawOffset = ScreenPrivacyCalibrationProfile.normalizedAngle(sample.yaw - base.centerYaw)
                    let pitchOffset = sample.pitch - base.centerPitch
                    track.samples.append(Observation(time: now, yaw: yawOffset, pitch: pitchOffset))
                    tracks[display.id] = track
                    lastStored = now
                    #if HEADUP_DEBUG
                    traceAttribution(
                        sample: sample, now: now, owners: owners, displays: displays,
                        storedDisplay: display, storedCount: track.samples.count,
                        yawOffset: yawOffset, pitchOffset: pitchOffset,
                        yawSpeed: yawSpeed, pitchSpeed: pitchSpeed, moving: moving, throttled: throttled
                    )
                    #endif
                } else {
                    #if HEADUP_DEBUG
                    traceAttribution(
                        sample: sample, now: now, owners: owners, displays: displays,
                        storedDisplay: nil, storedCount: nil,
                        yawOffset: nil, pitchOffset: nil,
                        yawSpeed: yawSpeed, pitchSpeed: pitchSpeed, moving: moving, throttled: throttled
                    )
                    #endif
                }
            } else {
                #if HEADUP_DEBUG
                traceAttribution(
                    sample: sample, now: now, owners: owners, displays: displays,
                    storedDisplay: nil, storedCount: nil,
                    yawOffset: nil, pitchOffset: nil,
                    yawSpeed: nil, pitchSpeed: nil, moving: false, throttled: false
                )
                #endif
            }
        }
        guard now - (lastCheck ?? now) >= Self.checkInterval else { return false }
        lastCheck = now
        for display in displays {
            evaluate(display, at: now, learningAllowed: learningAllowed)
        }
        return true
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
                    reason = "not stored"
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
            outcome = .learningSuspended
            HeadUpTrace.drift("\(prefix): skip — learning suspended (paused or covered); correction frozen at yaw \(HeadUpTrace.deg(track.yawCorrection)) pitch \(HeadUpTrace.deg(track.pitchCorrection))")
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

        let yawLimit = min(Self.absoluteCorrectionLimit, min(base.leftAngle, base.rightAngle) * 0.5)
        let pitchLimit = min(Self.absoluteCorrectionLimit, min(base.upAngle, base.downAngle) * 0.5)
        let targetYaw = max(-yawLimit, min(yawLimit, medianYaw))
        let targetPitch = max(-pitchLimit, min(pitchLimit, medianPitch))
        let stepYaw = max(-Self.maximumStep, min(Self.maximumStep, (targetYaw - track.yawCorrection) * Self.stepGain))
        let stepPitch = max(-Self.maximumStep, min(Self.maximumStep, (targetPitch - track.pitchCorrection) * Self.stepGain))
        track.yawCorrection += stepYaw
        track.pitchCorrection += stepPitch

        let detail = "\(prefix), window \(String(format: "%.1f", last.time - first.time))s, median offset yaw \(HeadUpTrace.deg(medianYaw)) pitch \(HeadUpTrace.deg(medianPitch)), target yaw \(HeadUpTrace.deg(targetYaw)) pitch \(HeadUpTrace.deg(targetPitch)), step yaw \(HeadUpTrace.deg(stepYaw)) pitch \(HeadUpTrace.deg(stepPitch)), total correction yaw \(HeadUpTrace.deg(track.yawCorrection)) pitch \(HeadUpTrace.deg(track.pitchCorrection)), calibrated center yaw \(HeadUpTrace.deg(base.centerYaw)) pitch \(HeadUpTrace.deg(base.centerPitch)), corrected center yaw \(HeadUpTrace.deg(base.centerYaw + track.yawCorrection)) pitch \(HeadUpTrace.deg(base.centerPitch + track.pitchCorrection))"
        if abs(stepYaw) >= 0.02 || abs(stepPitch) >= 0.02 {
            outcome = .applied(stepYaw: stepYaw, stepPitch: stepPitch)
            // Applied corrections are always visible, even in release builds.
            HeadUpLog.privacy.info("drift applied: \(detail, privacy: .public)")
        } else {
            outcome = .steady
            HeadUpTrace.drift("drift steady: \(detail)")
        }
    }

    private static func median(_ sorted: [Double]) -> Double {
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}

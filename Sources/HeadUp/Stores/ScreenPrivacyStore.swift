import Foundation
import AppKit

@MainActor
final class ScreenPrivacyStore: ObservableObject {
    @Published private(set) var status: ScreenPrivacyRuntimeStatus = .disabled
    @Published private(set) var calibrationStage: ScreenPrivacyCalibrationStage = .idle
    @Published private(set) var calibrationProgress = 0.0
    @Published private(set) var isCapturingCalibration = false
    @Published private(set) var horizontalOffset = 0.0
    @Published private(set) var verticalOffset = 0.0
    @Published private var calibrationErrorKey: String?
    var calibrationError: String? { calibrationErrorKey.map { L10n.text($0) } }
    @Published private(set) var isPreviewing = false

    @Published private(set) var displayProfiles: [ScreenPrivacyDisplayProfile] = []
    @Published private(set) var calibrationDisplays: [CalibrationDisplay] = []
    @Published private(set) var selectedDisplayID: String?
    @Published private(set) var captureCountdown = 0
    @Published private(set) var completedDisplayIDs: Set<String> = []
    @Published private(set) var needsSessionCalibration = false
    /// Set when the per-connection yaw datum is unknown but the saved calibration is
    /// still valid, so a one-tap recenter is enough. See `recenter(referenceDisplayID:)`.
    @Published private(set) var needsRecenter = false
    @Published private(set) var recenterCountdown = 0
    @Published private(set) var driftStatusByID: [String: ScreenPrivacyDriftStatus] = [:]
    private var driftEstimator = ScreenPrivacyDriftEstimator()
    private var captureTask: Task<Void, Never>?
    private var displayObserver: NSObjectProtocol?
    private var languageObserver: NSObjectProtocol?
    private let displaysProvider: @MainActor () -> [CalibrationDisplay]
    private let notificationCenter: NotificationCenter
    private var draftProfiles: [ScreenPrivacyDisplayProfile] = []

    struct CalibrationDisplay: Identifiable {
        let id: String
        let name: String
    }

    static func connectedDisplays() -> [CalibrationDisplay] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let displayID = CGDirectDisplayID(number.uint32Value)
            let id: String
            if let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() {
                id = CFUUIDCreateString(nil, uuid) as String
            } else { id = number.stringValue }
            return CalibrationDisplay(id: id, name: screen.localizedName)
        }
    }

    var hasPerDisplayCalibration: Bool { !displayProfiles.isEmpty }
    var canCapture: Bool { isTrackingAvailable }

    let settings: ScreenPrivacySettings
    let overlayContent = PrivacyOverlayContentModel()
    var onMotionRequirementChanged: (() -> Void)?

    private let analyzer = ScreenPrivacyAnalyzer()
    private let weatherService = WeatherService()
    private let overlayController: PrivacyOverlayController
    private var profile: ScreenPrivacyCalibrationProfile?
    private var calibrationStartedAt: TimeInterval?
    private var calibrationSamples: [(yaw: Double, pitch: Double)] = []
    private var capturedStages: [ScreenPrivacyCalibrationStage: (yaw: Double, pitch: Double)] = [:]
    private var hasArmedOnce = false
    private var isTrackingAvailable = false
    private var needsAutomaticRecentering = false
    private var isPaused = false
    /// AirPods yaw is measured from an arbitrary datum established per connection, so
    /// the absolute `centerYaw` of a saved profile is meaningless after a reconnect.
    /// The angles *between* displays are stable, so one global offset restores the
    /// whole layout. Deliberately not persisted: it belongs to this connection only.
    private var sessionYawOffset = 0.0
    private var sessionPitchOffset = 0.0
    /// Recent poses, so a recenter can use where the head actually was just before the
    /// tap rather than the single frame that happens to arrive after it.
    private var recentPoses: [(time: TimeInterval, yaw: Double, pitch: Double)] = []
    private var recenterTask: Task<Void, Never>?
    private static let recenterPoseWindow: TimeInterval = 1.0
    private var weatherTask: Task<Void, Never>?
    private var lastWeatherCity: String?
    private var lastWeatherRefresh: Date?
    #if HEADUP_DEBUG
    private var lastDriftPipelineTrace: TimeInterval?
    #endif

    /// `notificationCenter` is injectable so tests can drive display-layout and
    /// language events without touching the process-wide center, where a posted
    /// notification would reach every other store alive in the same process.
    init(
        settings: ScreenPrivacySettings,
        displaysProvider: @escaping @MainActor () -> [CalibrationDisplay] = { ScreenPrivacyStore.connectedDisplays() },
        notificationCenter: NotificationCenter = .default
    ) {
        self.displaysProvider = displaysProvider
        self.notificationCenter = notificationCenter
        self.settings = settings
        overlayController = PrivacyOverlayController(settings: settings, content: overlayContent)
        displayProfiles = settings.displayProfiles
        profile = settings.calibrationProfile
        if !displayProfiles.isEmpty {
            profile = displayProfiles.first?.calibration
            // The datum is unknown until the first pose is aligned, but the saved
            // per-display geometry is still good, so this needs a recenter rather than
            // a full recalibration.
            needsRecenter = true
        }
        needsAutomaticRecentering = profile != nil && displayProfiles.isEmpty
        hasArmedOnce = profile != nil
        status = settings.isEnabled
            ? (profile == nil ? .needsCalibration : .trackingLost)
            : .disabled
        languageObserver = notificationCenter.addObserver(forName: .headUpLanguageChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshWeather(force: true) }
        }
        displayObserver = notificationCenter.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.displayLayoutChanged() }
        }
    }

    deinit {
        if let displayObserver { notificationCenter.removeObserver(displayObserver) }
        if let languageObserver { notificationCenter.removeObserver(languageObserver) }
        captureTask?.cancel()
    }

    /// Full reset. Use only when the calibration center itself changes.
    private func resetDriftLearning(reason: String) {
        driftEstimator.reset(reason: reason)
        driftStatusByID = [:]
    }

    /// Saved profiles shifted onto this connection's yaw datum.
    private func sessionAligned(_ profiles: [ScreenPrivacyDisplayProfile]) -> [ScreenPrivacyDisplayProfile] {
        guard sessionYawOffset != 0 || sessionPitchOffset != 0 else { return profiles }
        return profiles.map { display in
            var shifted = display
            shifted.calibration = display.calibration.recentered(
                yaw: ScreenPrivacyCalibrationProfile.normalizedAngle(display.calibration.centerYaw + sessionYawOffset),
                pitch: display.calibration.centerPitch + sessionPitchOffset
            )
            return shifted
        }
    }

    /// Circular mean of the poses held over the last second, so a stray frame cannot
    /// skew the datum. Returns nil while the head is still moving.
    private func steadyRecentPose() -> (yaw: Double, pitch: Double)? {
        guard let newest = recentPoses.last else { return nil }
        let window = recentPoses.filter { newest.time - $0.time <= Self.recenterPoseWindow }
        guard window.count >= 5 else { return nil }
        let mean = averaged(window.map { (yaw: $0.yaw, pitch: $0.pitch) })
        let steady = window.allSatisfy {
            abs(ScreenPrivacyCalibrationProfile.normalizedAngle($0.yaw - mean.yaw)) <= 4
                && abs($0.pitch - mean.pitch) <= 4
        }
        return steady ? mean : nil
    }

    /// Restores the yaw datum from a single pose, assuming the head is pointed at the
    /// center of `referenceDisplayID`.
    ///
    /// A full recalibration is unnecessary after a reconnect: only the datum is
    /// unknown, and the saved geometry between displays still holds. Solving against
    /// the saved base profile (not the already-shifted one) keeps this idempotent, so
    /// tapping twice cannot compound the offset.
    ///
    /// Requires the displays not to have moved relative to each other. When the layout
    /// does change, `needsSessionCalibration` is set and this refuses outright, because
    /// no single offset can fit every screen again — a full recalibration is the only
    /// way out. Returns false without changing anything in that case.
    @discardableResult
    func recenter(referenceDisplayID: String? = nil) -> Bool {
        // Refused while a recalibration is pending: that flag means the saved geometry
        // itself is stale (a display was added, removed, or rearranged), and no single
        // offset can fit every screen again. Enforced here rather than left to the UI
        // not to offer it, so a future entry point cannot silently mask a real move.
        //
        // Refused with tracking down for a sharper reason: the pose buffer is not cleared
        // by the passage of time, and `steadyRecentPose` measures its window against the
        // newest sample's own timestamp. Without this guard a tap after a disconnect
        // succeeded off the pose held when the stream stopped, silently anchoring every
        // boundary to wherever the head happened to be at that moment.
        guard !displayProfiles.isEmpty, !needsSessionCalibration, isTrackingAvailable else { return false }
        let reference = displayProfiles.first { $0.id == referenceDisplayID } ?? displayProfiles.first
        guard let reference, let pose = steadyRecentPose() else {
            calibrationErrorKey = "头部移动较多，请正视屏幕中心后重试"
            return false
        }
        cancelRecenter()
        sessionYawOffset = ScreenPrivacyCalibrationProfile.normalizedAngle(pose.yaw - reference.calibration.centerYaw)
        sessionPitchOffset = pose.pitch - reference.calibration.centerPitch
        needsRecenter = false
        calibrationErrorKey = nil
        // Corrections were measured against the previous datum.
        resetDriftLearning(reason: "session recentered")
        analyzer.reset()
        hasArmedOnce = true
        horizontalOffset = 0
        verticalOffset = 0
        let yawOffset = sessionYawOffset
        let pitchOffset = sessionPitchOffset
        HeadUpLog.privacy.info(
            "Session recentered on [\(reference.name, privacy: .public)]: yaw offset \(HeadUpTrace.deg(yawOffset), privacy: .public), pitch offset \(HeadUpTrace.deg(pitchOffset), privacy: .public)"
        )
        if settings.isEnabled, !isPaused {
            status = resumedStatus
            overlayController.hide()
        }
        return true
    }

    /// Recenter after a countdown, for when the screen is not covered and the user has
    /// to look at the screen center first.
    func beginRecenterCountdown(delaySeconds: Int = 3) {
        guard !displayProfiles.isEmpty, !needsSessionCalibration, isTrackingAvailable, recenterCountdown == 0 else { return }
        calibrationErrorKey = nil
        recenterCountdown = max(1, delaySeconds)
        recenterTask = Task { [weak self] in
            for remaining in stride(from: max(1, delaySeconds), through: 1, by: -1) {
                guard let self, !Task.isCancelled else { return }
                self.recenterCountdown = remaining
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
            guard let self, !Task.isCancelled else { return }
            self.recenterCountdown = 0
            if self.recenter() { NSSound(named: "Pop")?.play() }
        }
    }

    func cancelRecenter() {
        recenterTask?.cancel()
        recenterTask = nil
        recenterCountdown = 0
    }

    /// Synthetic display used by the single-profile path so it gets the same drift
    /// correction as per-display calibration.
    private static let singleDisplayID = "headup.single-display"

    private func singleDisplayProfile(_ calibration: ScreenPrivacyCalibrationProfile) -> ScreenPrivacyDisplayProfile {
        ScreenPrivacyDisplayProfile(id: Self.singleDisplayID, name: L10n.text("全部屏幕"), calibration: calibration)
    }

    #if HEADUP_DEBUG
    private func traceDriftPipeline(_ sample: MotionSample, note: String) {
        guard sample.sensorTimestamp - (lastDriftPipelineTrace ?? -.infinity) >= 1 else { return }
        lastDriftPipelineTrace = sample.sensorTimestamp
        HeadUpTrace.driftVerbose("privacy pipeline raw yaw \(HeadUpTrace.deg(sample.yaw)) pitch \(HeadUpTrace.deg(sample.pitch)) — \(note)")
    }

    private func traceDriftPipeline(_ sample: MotionSample, activeDisplays: [ScreenPrivacyDisplayProfile], phase: ScreenPrivacyPhase) {
        guard sample.sensorTimestamp - (lastDriftPipelineTrace ?? -.infinity) >= 1 else { return }
        lastDriftPipelineTrace = sample.sensorTimestamp
        let detail = activeDisplays.map { display -> String in
            let corrected = driftEstimator.corrected(display)
            let offset = corrected.offsets(yaw: sample.yaw, pitch: sample.pitch)
            let inside = corrected.contains(yaw: sample.yaw, pitch: sample.pitch)
            return "\(display.name)[center y\(HeadUpTrace.deg(corrected.centerYaw)) p\(HeadUpTrace.deg(corrected.centerPitch)), offset h\(HeadUpTrace.deg(offset.horizontal)) v\(HeadUpTrace.deg(offset.vertical)), inside:\(inside)]"
        }.joined(separator: " ")
        HeadUpTrace.driftVerbose("privacy pipeline raw yaw \(HeadUpTrace.deg(sample.yaw)) pitch \(HeadUpTrace.deg(sample.pitch)), phase \(String(describing: phase)), displays \(activeDisplays.count): \(detail)")
    }
    #endif

    private func displayLayoutChanged() {
        guard !displayProfiles.isEmpty || calibrationStage != .idle else { return }
        cancelCalibration()
        needsSessionCalibration = true
        resetDriftLearning(reason: "display layout changed")
        calibrationErrorKey = "显示器布局已变化，请重新校准屏幕"
        if settings.isEnabled, !isPaused {
            status = .needsCalibration
            if settings.keepCoveredOnTrackingLoss { showOverlay(message: "显示器布局已变化，请重新校准") }
        }
    }

    /// Status to fall back to when protection resumes (enable, unpause, cancel).
    /// Ordering matters: a missing calibration outranks a dead sensor, which outranks a
    /// missing datum. Tracking comes before the datum because recentering needs a live
    /// pose to read — reporting `needsRecenter` with the sensor down would offer an
    /// action that `recenter()` refuses.
    private var resumedStatus: ScreenPrivacyRuntimeStatus {
        if profile == nil || needsSessionCalibration { return .needsCalibration }
        if !isTrackingAvailable { return .trackingLost }
        return needsRecenter ? .needsRecenter : .watching
    }

    var requiresMotionUpdates: Bool {
        settings.isEnabled || calibrationStage != .idle
    }

    var statusDetail: String {
        switch status {
        case .disabled: return L10n.text("开启后，头部离开设定工作区会自动遮挡全部屏幕")
        case .needsCalibration: return needsSessionCalibration ? L10n.text("请重新校准屏幕方向，恢复本次追踪") : L10n.text("在这里逐屏设置中心与四个边界")
        case .needsRecenter: return recenterCountdown > 0
            ? L10n.text("正视屏幕中心，{0} 秒后自动对准", "\(recenterCountdown)")
            : L10n.text("已保存的校准仍然有效，正视屏幕中心对准一次即可")
        case .calibrating: return L10n.text("保持当前方向，正在采集头部角度")
        case .watching: return L10n.text("正在监测左右转头、仰头和低头")
        case .coveringSoon: return L10n.text("回到工作区可取消遮挡")
        case .covered: return L10n.text("回到工作区，或按 Esc 暂停保护")
        case .revealingSoon: return L10n.text("保持正视即可恢复")
        case .paused: return L10n.text("从菜单栏继续后重新布防")
        case .trackingLost: return L10n.text("追踪恢复后，请在菜单栏确认并校准屏幕方向")
        }
    }

    func setEnabled(_ enabled: Bool) {
        if calibrationStage != .idle { cancelCalibration() }
        settings.isEnabled = enabled
        isPaused = false
        analyzer.reset()
        if enabled {
            status = resumedStatus
        } else {
            status = .disabled
            stopPreviewOrOverlay()
        }
        onMotionRequirementChanged?()
    }

    func startCalibration() {
        captureTask?.cancel()
        captureCountdown = 0
        calibrationDisplays = displaysProvider()
        guard !calibrationDisplays.isEmpty else {
            calibrationErrorKey = "未找到可校准的显示器"
            return
        }
        selectedDisplayID = calibrationDisplays.first?.id
        completedDisplayIDs.removeAll()
        draftProfiles.removeAll()
        resetDriftLearning(reason: "calibration started")
        needsAutomaticRecentering = false
        calibrationErrorKey = nil
        capturedStages.removeAll()
        calibrationSamples.removeAll()
        calibrationStartedAt = nil
        calibrationProgress = 0
        isCapturingCalibration = false
        calibrationStage = .center
        status = .calibrating(.center)
        stopPreviewOrOverlay()
        onMotionRequirementChanged?()
    }

    func cancelCalibration() {
        captureTask?.cancel()
        captureTask = nil
        captureCountdown = 0
        calibrationStage = .idle
        calibrationSamples.removeAll()
        capturedStages.removeAll()
        calibrationStartedAt = nil
        calibrationProgress = 0
        isCapturingCalibration = false
        status = settings.isEnabled ? (isPaused ? .paused : resumedStatus) : .disabled
        analyzer.reset()
        if settings.isEnabled, !isPaused, needsSessionCalibration, settings.keepCoveredOnTrackingLoss {
            showOverlay(message: "请校准屏幕方向后恢复保护")
        }
        onMotionRequirementChanged?()
    }

    func togglePause() {
        if isPaused {
            isPaused = false
            status = resumedStatus
            if status == .trackingLost, hasArmedOnce, settings.keepCoveredOnTrackingLoss {
                showOverlay(message: "AirPods 连接中断")
            }
        } else {
            pauseProtection()
        }
    }

    func pauseProtection() {
        isPaused = true
        isPreviewing = false
        analyzer.reset()
        overlayController.hide()
        status = .paused
    }

    func showPreview() {
        isPreviewing = true
        refreshWeather()
        overlayController.show(onPause: { [weak self] in
            self?.stopPreviewOrOverlay()
        })
    }

    func selectCalibrationDisplay(_ id: String) {
        guard calibrationDisplays.contains(where: { $0.id == id }), !isCapturingCalibration, captureCountdown == 0 else { return }
        selectedDisplayID = id
        completedDisplayIDs.remove(id)
        capturedStages.removeAll()
        calibrationSamples.removeAll()
        calibrationStartedAt = nil
        calibrationProgress = 0
        calibrationStage = .center
        status = .calibrating(.center)
        calibrationErrorKey = nil
    }

    /// Adjust one boundary angle of a calibrated display without recalibrating.
    /// The change takes effect on the next motion sample and is persisted immediately.
    func setDisplayAngle(
        id: String,
        edge keyPath: WritableKeyPath<ScreenPrivacyCalibrationProfile, Double>,
        value: Double
    ) {
        guard let index = displayProfiles.firstIndex(where: { $0.id == id }) else { return }
        let clamped = max(
            ScreenPrivacyCalibrationProfile.minimumBoundaryAngle,
            min(85, value.rounded())
        )
        guard displayProfiles[index].calibration[keyPath: keyPath] != clamped else { return }
        let name = displayProfiles[index].name
        displayProfiles[index].calibration[keyPath: keyPath] = clamped
        settings.saveDisplayProfiles(displayProfiles)
        HeadUpLog.privacy.info(
            "[\(name, privacy: .public)] boundary angle changed to \(clamped, privacy: .public)°"
        )
    }

    func previousCalibrationStep() {
        guard !isCapturingCalibration, captureCountdown == 0 else { return }
        let steps: [ScreenPrivacyCalibrationStage] = [.center, .left, .right, .up, .down]
        guard let index = steps.firstIndex(of: calibrationStage), index > 0 else { return }
        calibrationStage = steps[index - 1]
        for stage in steps[(index - 1)...] { capturedStages.removeValue(forKey: stage) }
        calibrationProgress = 0
        calibrationErrorKey = nil
        status = .calibrating(calibrationStage)
    }

    func beginCalibrationCapture(delaySeconds: Int = 3) {
        guard calibrationStage != .idle, !isCapturingCalibration, captureCountdown == 0, canCapture else { return }
        calibrationErrorKey = nil
        captureCountdown = max(0, delaySeconds)
        captureTask = Task { [weak self] in
            for remaining in stride(from: max(0, delaySeconds), through: 1, by: -1) {
                guard let self, !Task.isCancelled else { return }
                self.captureCountdown = remaining
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
            guard let self, !Task.isCancelled, self.canCapture else { return }
            self.captureCountdown = 0
            self.calibrationSamples.removeAll(keepingCapacity: true)
            self.calibrationStartedAt = nil
            self.calibrationProgress = 0
            self.isCapturingCalibration = true
            NSSound(named: "Tink")?.play()
        }
    }

    func stopPreviewOrOverlay() {
        isPreviewing = false
        overlayController.hide()
    }

    func refreshWeather(force: Bool = false) {
        weatherTask?.cancel()
        guard settings.showsWeather else {
            overlayContent.weather = nil
            overlayContent.weatherMessageKey = nil
            return
        }
        let city = settings.weatherCity
        if !force,
           city == lastWeatherCity,
           let lastWeatherRefresh,
           Date().timeIntervalSince(lastWeatherRefresh) < 1_800,
           overlayContent.weatherText != nil {
            return
        }
        overlayContent.weather = nil
        overlayContent.weatherMessageKey = "正在获取天气…"
        weatherTask = Task { [weak self] in
            guard let self else { return }
            do {
                let weather = try await weatherService.currentWeather(for: city)
                guard !Task.isCancelled else { return }
                overlayContent.weather = weather
                overlayContent.weatherMessageKey = nil
                overlayContent.weatherSymbol = weather.symbolName
                lastWeatherCity = city
                lastWeatherRefresh = Date()
            } catch {
                guard !Task.isCancelled else { return }
                overlayContent.weatherMessageKey = (error as? WeatherServiceError)?.localizationKey ?? "天气服务暂时不可用"
                overlayContent.weatherSymbol = "exclamationmark.icloud.fill"
            }
        }
    }

    func handle(_ sample: MotionSample) {
        guard sample.yaw.isFinite, sample.pitch.isFinite, sample.sensorTimestamp.isFinite else { return }
        isTrackingAvailable = true
        // Recorded before any gating below, so a recenter has poses to work with even
        // while the normal pipeline is blocked waiting for one.
        recentPoses.append((sample.sensorTimestamp, sample.yaw, sample.pitch))
        recentPoses.removeAll { sample.sensorTimestamp - $0.time > Self.recenterPoseWindow * 2 }
        if needsAutomaticRecentering, displayProfiles.isEmpty, let storedProfile = profile {
            profile = storedProfile.recentered(yaw: sample.yaw, pitch: sample.pitch)
            needsAutomaticRecentering = false
            analyzer.reset()
            horizontalOffset = 0
            verticalOffset = 0
            if settings.isEnabled, !isPaused {
                status = .watching
                overlayController.hide()
            }
        } else if status == .trackingLost, profile == nil, settings.isEnabled {
            status = .needsCalibration
        }
        if calibrationStage != .idle {
            handleCalibration(sample)
            return
        }
        guard settings.isEnabled, !isPaused else { return }
        if !displayProfiles.isEmpty {
            guard !needsSessionCalibration else {
                if status != .needsCalibration {
                    status = .needsCalibration
                    if settings.keepCoveredOnTrackingLoss { showOverlay(message: "请校准屏幕方向后恢复保护") }
                }
                #if HEADUP_DEBUG
                traceDriftPipeline(sample, note: "blocked: session recalibration required")
                #endif
                return
            }
            // The saved geometry is still good; only this connection's datum is unknown.
            guard !needsRecenter else {
                if status != .needsRecenter {
                    status = .needsRecenter
                    // No message: the target carries its own caption, on every covered
                    // screen, while a message only renders where the clock does.
                    showOverlay()
                }
                #if HEADUP_DEBUG
                traceDriftPipeline(sample, note: "blocked: awaiting session recenter")
                #endif
                return
            }
            let connected = Set(displaysProvider().map(\.id))
            let active = sessionAligned(displayProfiles).filter { connected.contains($0.id) }
            let reading = analyzer.process(
                yaw: sample.yaw, pitch: sample.pitch, at: sample.sensorTimestamp,
                profiles: active.map { driftEstimator.corrected($0) }, thresholds: settings.thresholds
            )
            let didEvaluate = driftEstimator.process(sample, displays: active, learningAllowed: reading.phase == .watching)
            if didEvaluate { driftStatusByID = driftEstimator.statusByID }
            horizontalOffset = reading.horizontalOffset
            verticalOffset = reading.verticalOffset
            #if HEADUP_DEBUG
            traceDriftPipeline(sample, activeDisplays: active, phase: reading.phase)
            #endif
            apply(reading.phase)
            return
        }
        guard let storedProfile = profile else { return }

        var effectiveProfile = storedProfile
        effectiveProfile.leftAngle = settings.leftAngle
        effectiveProfile.rightAngle = settings.rightAngle
        effectiveProfile.upAngle = settings.upAngle
        effectiveProfile.downAngle = settings.downAngle
        // The single-profile path drifts exactly like the per-display one, so it runs
        // through the same estimator instead of relying on recentering after a dropout.
        let display = singleDisplayProfile(effectiveProfile)
        let reading = analyzer.process(
            yaw: sample.yaw,
            pitch: sample.pitch,
            at: sample.sensorTimestamp,
            profile: driftEstimator.corrected(display),
            thresholds: settings.thresholds
        )
        let didEvaluate = driftEstimator.process(
            sample, displays: [display], learningAllowed: reading.phase == .watching
        )
        if didEvaluate { driftStatusByID = driftEstimator.statusByID }
        horizontalOffset = reading.horizontalOffset
        verticalOffset = reading.verticalOffset
        apply(reading.phase)
    }

    func handleTrackingAvailabilityChanged(_ available: Bool) {
        isTrackingAvailable = available
        if !available {
            // These describe where the head was before the stream stopped, and nothing
            // else prunes them: the pruning in `handle` runs only when a new sample
            // arrives. Dropped here so no pose can outlive the connection it came from.
            recentPoses.removeAll()
        }
        if !available, calibrationStage != .idle {
            cancelCalibration()
            calibrationErrorKey = "头部追踪已中断，请连接 AirPods 后重新校准"
        }
        if !available, profile != nil {
            needsAutomaticRecentering = displayProfiles.isEmpty
            // Only the per-connection yaw datum is lost here — the saved geometry and
            // the angles between displays are unchanged, so a one-tap recenter is
            // enough. Demanding a full recalibration for every earbud removal was what
            // made a saved setup look like it had been discarded.
            if !displayProfiles.isEmpty {
                needsRecenter = true
                sessionYawOffset = 0
                sessionPitchOffset = 0
                cancelRecenter()
            }
            // A full reset (not `resetSamples`) is right here: the yaw datum is
            // arbitrary per connection, so the reference center is about to be
            // redefined by recentering or recalibration, and corrections measured
            // against the old center would be meaningless. Silent stream gaps that
            // keep the same datum are handled inside the estimator, which preserves
            // the corrections.
            resetDriftLearning(reason: "tracking unavailable")
        }
        guard settings.isEnabled, !isPaused else { return }
        if available {
            if profile == nil { status = .needsCalibration }
        } else {
            analyzer.reset(covered: hasArmedOnce && settings.keepCoveredOnTrackingLoss)
            status = .trackingLost
            if hasArmedOnce, settings.keepCoveredOnTrackingLoss {
                showOverlay(message: "AirPods 追踪暂时中断，请恢复连接后校准")
            } else {
                overlayController.hide()
            }
        }
    }

    private func handleCalibration(_ sample: MotionSample) {
        guard isCapturingCalibration else { return }
        if calibrationStartedAt == nil { calibrationStartedAt = sample.sensorTimestamp }
        guard let startedAt = calibrationStartedAt else { return }
        calibrationSamples.append((sample.yaw, sample.pitch))
        let elapsed = sample.sensorTimestamp - startedAt
        calibrationProgress = min(1, elapsed / 2)
        guard elapsed >= 2, calibrationSamples.count >= 5 else { return }

        let mean = averaged(calibrationSamples)
        let stable = calibrationSamples.allSatisfy {
            abs(ScreenPrivacyCalibrationProfile.normalizedAngle($0.yaw - mean.yaw)) <= 2
                && abs($0.pitch - mean.pitch) <= 2
        }
        guard stable else {
            isCapturingCalibration = false
            calibrationErrorKey = "头部移动较多，请保持方向后重新采集"
            calibrationProgress = 0
            return
        }
        capturedStages[calibrationStage] = mean
        NSSound(named: "Pop")?.play()
        isCapturingCalibration = false
        if calibrationStage == .down {
            finishCalibration()
        } else {
            calibrationStage = calibrationStage.next
            calibrationStartedAt = nil
            calibrationSamples.removeAll(keepingCapacity: true)
            calibrationProgress = 0
            status = .calibrating(calibrationStage)
        }
    }

    private func finishCalibration() {
        guard let center = capturedStages[.center],
              let left = capturedStages[.left],
              let right = capturedStages[.right],
              let up = capturedStages[.up],
              let down = capturedStages[.down],
              let newProfile = ScreenPrivacyCalibrationProfile.make(
                centerYaw: center.yaw,
                centerPitch: center.pitch,
                leftYaw: left.yaw,
                rightYaw: right.yaw,
                upPitch: up.pitch,
                downPitch: down.pitch
              ) else {
            calibrationErrorKey = "边界角度太小或方向重复，请重新校准"
            calibrationStage = .center
            capturedStages.removeAll()
            calibrationProgress = 0
            status = .calibrating(.center)
            return
        }

        if let id = selectedDisplayID,
           let display = calibrationDisplays.first(where: { $0.id == id }) {
            draftProfiles.removeAll { $0.id == id }
            draftProfiles.append(ScreenPrivacyDisplayProfile(id: id, name: display.name, calibration: newProfile))
            completedDisplayIDs.insert(id)
            if let next = calibrationDisplays.first(where: { !completedDisplayIDs.contains($0.id) }) {
                selectCalibrationDisplay(next.id)
                return
            }
        }
        calibrationStage = .idle
        calibrationStartedAt = nil
        calibrationSamples.removeAll()
        capturedStages.removeAll()
        calibrationProgress = 0
        isCapturingCalibration = false
        needsSessionCalibration = false
        displayProfiles = draftProfiles
        settings.saveDisplayProfiles(displayProfiles)
        resetDriftLearning(reason: "calibration finished")
        profile = newProfile
        needsAutomaticRecentering = false
        settings.saveCalibrationProfile(newProfile)
        settings.leftAngle = newProfile.leftAngle.rounded()
        settings.rightAngle = newProfile.rightAngle.rounded()
        settings.upAngle = newProfile.upAngle.rounded()
        settings.downAngle = newProfile.downAngle.rounded()
        settings.isEnabled = true
        hasArmedOnce = true
        isPaused = false
        analyzer.reset()
        calibrationErrorKey = nil
        status = .watching
        onMotionRequirementChanged?()
    }

    private func averaged(_ samples: [(yaw: Double, pitch: Double)]) -> (yaw: Double, pitch: Double) {
        let radians = samples.map { $0.yaw * .pi / 180 }
        let yaw = atan2(
            radians.reduce(0) { $0 + sin($1) },
            radians.reduce(0) { $0 + cos($1) }
        ) * 180 / .pi
        let pitch = samples.reduce(0) { $0 + $1.pitch } / Double(samples.count)
        return (yaw, pitch)
    }

    private func apply(_ phase: ScreenPrivacyPhase) {
        switch phase {
        case .watching:
            if status != .watching {
                status = .watching
                overlayController.hide()
            }
        case .waitingToCover:
            status = .coveringSoon
        case .covered:
            if status != .covered {
                status = .covered
                showOverlay()
            }
        case .waitingToReveal:
            status = .revealingSoon
        }
    }

    /// The centered target is offered whenever a saved per-display layout exists:
    /// either the datum is missing, or the user judges the boundaries to have wandered
    /// and wants to re-aim them by hand without redoing the whole calibration.
    ///
    /// Withheld while tracking is down. A recenter reads the pose the head is holding
    /// right now, and with no live stream there is no such pose — offering the target
    /// there would only invite a tap that cannot mean anything.
    private func showOverlay(message: String? = nil) {
        refreshWeather()
        let offersRecenter = !displayProfiles.isEmpty && !needsSessionCalibration && isTrackingAvailable
        overlayController.show(
            message: message,
            onPause: { [weak self] in self?.pauseProtection() },
            onRecenter: offersRecenter ? { [weak self] id in self?.recenter(referenceDisplayID: id) } : nil
        )
    }
}

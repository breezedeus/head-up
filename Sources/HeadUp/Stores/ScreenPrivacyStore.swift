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
    private var driftEstimator = ScreenPrivacyDriftEstimator()
    private var captureTask: Task<Void, Never>?
    private var displayObserver: NSObjectProtocol?
    private var languageObserver: NSObjectProtocol?
    private let displaysProvider: @MainActor () -> [CalibrationDisplay]
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
    private var weatherTask: Task<Void, Never>?
    private var lastWeatherCity: String?
    private var lastWeatherRefresh: Date?

    init(settings: ScreenPrivacySettings, displaysProvider: @escaping @MainActor () -> [CalibrationDisplay] = { ScreenPrivacyStore.connectedDisplays() }) {
        self.displaysProvider = displaysProvider
        self.settings = settings
        overlayController = PrivacyOverlayController(settings: settings, content: overlayContent)
        displayProfiles = settings.displayProfiles
        profile = settings.calibrationProfile
        if !displayProfiles.isEmpty {
            profile = displayProfiles.first?.calibration
            needsSessionCalibration = true
        }
        needsAutomaticRecentering = profile != nil && displayProfiles.isEmpty
        hasArmedOnce = profile != nil
        status = settings.isEnabled
            ? (profile == nil ? .needsCalibration : .trackingLost)
            : .disabled
        languageObserver = NotificationCenter.default.addObserver(forName: .headUpLanguageChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshWeather(force: true) }
        }
        displayObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.displayLayoutChanged() }
        }
    }

    deinit {
        if let displayObserver { NotificationCenter.default.removeObserver(displayObserver) }
        if let languageObserver { NotificationCenter.default.removeObserver(languageObserver) }
        captureTask?.cancel()
    }

    private func displayLayoutChanged() {
        guard !displayProfiles.isEmpty || calibrationStage != .idle else { return }
        cancelCalibration()
        needsSessionCalibration = true
        driftEstimator.reset()
        calibrationErrorKey = "显示器布局已变化，请重新校准屏幕"
        if settings.isEnabled, !isPaused {
            status = .needsCalibration
            if settings.keepCoveredOnTrackingLoss { showOverlay(message: "显示器布局已变化，请重新校准") }
        }
    }

    var requiresMotionUpdates: Bool {
        settings.isEnabled || calibrationStage != .idle
    }

    var statusDetail: String {
        switch status {
        case .disabled: return L10n.text("开启后，头部离开设定工作区会自动遮挡全部屏幕")
        case .needsCalibration: return needsSessionCalibration ? L10n.text("请重新校准屏幕方向，恢复本次追踪") : L10n.text("在这里逐屏设置中心与四个边界")
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
            status = profile == nil || needsSessionCalibration ? .needsCalibration : (isTrackingAvailable ? .watching : .trackingLost)
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
        driftEstimator.reset()
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
        status = settings.isEnabled ? (isPaused ? .paused : (profile == nil || needsSessionCalibration ? .needsCalibration : (isTrackingAvailable ? .watching : .trackingLost))) : .disabled
        analyzer.reset()
        if settings.isEnabled, !isPaused, needsSessionCalibration, settings.keepCoveredOnTrackingLoss {
            showOverlay(message: "请校准屏幕方向后恢复保护")
        }
        onMotionRequirementChanged?()
    }

    func togglePause() {
        if isPaused {
            isPaused = false
            status = profile == nil || needsSessionCalibration ? .needsCalibration : (isTrackingAvailable ? .watching : .trackingLost)
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
                return
            }
            let connected = Set(displaysProvider().map(\.id))
            let active = displayProfiles.filter { connected.contains($0.id) }
            let reading = analyzer.process(
                yaw: sample.yaw, pitch: sample.pitch, at: sample.sensorTimestamp,
                profiles: active.map { driftEstimator.corrected($0) }, thresholds: settings.thresholds
            )
            driftEstimator.process(sample, displays: active, learningAllowed: reading.phase == .watching)
            horizontalOffset = reading.horizontalOffset
            verticalOffset = reading.verticalOffset
            apply(reading.phase)
            return
        }
        guard let storedProfile = profile else { return }

        var effectiveProfile = storedProfile
        effectiveProfile.leftAngle = settings.leftAngle
        effectiveProfile.rightAngle = settings.rightAngle
        effectiveProfile.upAngle = settings.upAngle
        effectiveProfile.downAngle = settings.downAngle
        let reading = analyzer.process(
            yaw: sample.yaw,
            pitch: sample.pitch,
            at: sample.sensorTimestamp,
            profile: effectiveProfile,
            thresholds: settings.thresholds
        )
        horizontalOffset = reading.horizontalOffset
        verticalOffset = reading.verticalOffset
        apply(reading.phase)
    }

    func handleTrackingAvailabilityChanged(_ available: Bool) {
        isTrackingAvailable = available
        if !available, calibrationStage != .idle {
            cancelCalibration()
            calibrationErrorKey = "头部追踪已中断，请连接 AirPods 后重新校准"
        }
        if !available, profile != nil {
            needsAutomaticRecentering = displayProfiles.isEmpty
            if !displayProfiles.isEmpty { needsSessionCalibration = true }
            driftEstimator.reset()
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
        driftEstimator.reset()
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

    private func showOverlay(message: String? = nil) {
        refreshWeather()
        overlayController.show(message: message, onPause: { [weak self] in
            self?.pauseProtection()
        })
    }
}

import Foundation

@MainActor
final class ScreenPrivacyStore: ObservableObject {
    @Published private(set) var status: ScreenPrivacyRuntimeStatus = .disabled
    @Published private(set) var calibrationStage: ScreenPrivacyCalibrationStage = .idle
    @Published private(set) var calibrationProgress = 0.0
    @Published private(set) var isCapturingCalibration = false
    @Published private(set) var horizontalOffset = 0.0
    @Published private(set) var verticalOffset = 0.0
    @Published private(set) var calibrationError: String?
    @Published private(set) var isPreviewing = false

    let settings: ScreenPrivacySettings
    let overlayContent = PrivacyOverlayContentModel()
    var onMotionRequirementChanged: (() -> Void)?

    private let analyzer = ScreenPrivacyAnalyzer()
    private let weatherService = WeatherService()
    private let overlayController: PrivacyOverlayController
    private var profile: ScreenPrivacyCalibrationProfile?
    private var calibrationStartedAt: Date?
    private var calibrationSamples: [(yaw: Double, pitch: Double)] = []
    private var capturedStages: [ScreenPrivacyCalibrationStage: (yaw: Double, pitch: Double)] = [:]
    private var hasArmedOnce = false
    private var isTrackingAvailable = false
    private var isPaused = false
    private var weatherTask: Task<Void, Never>?
    private var lastWeatherCity: String?
    private var lastWeatherRefresh: Date?

    init(settings: ScreenPrivacySettings) {
        self.settings = settings
        overlayController = PrivacyOverlayController(settings: settings, content: overlayContent)
        status = settings.isEnabled ? .needsCalibration : .disabled
    }

    var requiresMotionUpdates: Bool {
        settings.isEnabled || calibrationStage != .idle
    }

    var statusDetail: String {
        switch status {
        case .disabled: return "开启后，头部离开设定工作区会自动遮挡全部屏幕"
        case .needsCalibration: return "请先设置左右、上下四个工作边界"
        case .calibrating: return "保持当前方向，正在采集头部角度"
        case .watching: return "正在监测左右转头、仰头和低头"
        case .coveringSoon: return "回到工作区可取消遮挡"
        case .covered: return "回到工作区，或按 Esc 暂停保护"
        case .revealingSoon: return "保持正视即可恢复"
        case .paused: return "从菜单栏继续后重新布防"
        case .trackingLost: return "请检查 AirPods 连接；屏幕保持保护"
        }
    }

    func setEnabled(_ enabled: Bool) {
        settings.isEnabled = enabled
        isPaused = false
        analyzer.reset()
        if enabled {
            status = profile == nil ? .needsCalibration : (isTrackingAvailable ? .watching : .trackingLost)
        } else {
            status = .disabled
            stopPreviewOrOverlay()
        }
        onMotionRequirementChanged?()
    }

    func startCalibration() {
        calibrationError = nil
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
        calibrationStage = .idle
        calibrationSamples.removeAll()
        capturedStages.removeAll()
        calibrationStartedAt = nil
        calibrationProgress = 0
        isCapturingCalibration = false
        status = settings.isEnabled ? (profile == nil ? .needsCalibration : .watching) : .disabled
        onMotionRequirementChanged?()
    }

    func togglePause() {
        if isPaused {
            isPaused = false
            status = profile == nil ? .needsCalibration : (isTrackingAvailable ? .watching : .trackingLost)
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

    func beginCalibrationCapture() {
        guard calibrationStage != .idle, !isCapturingCalibration else { return }
        calibrationSamples.removeAll(keepingCapacity: true)
        calibrationStartedAt = nil
        calibrationProgress = 0
        isCapturingCalibration = true
    }

    func stopPreviewOrOverlay() {
        isPreviewing = false
        overlayController.hide()
    }

    func refreshWeather(force: Bool = false) {
        weatherTask?.cancel()
        guard settings.showsWeather else {
            overlayContent.weatherText = nil
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
        overlayContent.weatherText = "正在获取天气…"
        weatherTask = Task { [weak self] in
            guard let self else { return }
            do {
                let weather = try await weatherService.currentWeather(for: city)
                guard !Task.isCancelled else { return }
                overlayContent.weatherText = weather.displayText
                overlayContent.weatherSymbol = weather.symbolName
                lastWeatherCity = city
                lastWeatherRefresh = Date()
            } catch {
                guard !Task.isCancelled else { return }
                overlayContent.weatherText = error.localizedDescription
                overlayContent.weatherSymbol = "exclamationmark.icloud.fill"
            }
        }
    }

    func handle(_ sample: MotionSample) {
        isTrackingAvailable = true
        if status == .trackingLost, profile == nil, settings.isEnabled {
            status = .needsCalibration
        }
        if calibrationStage != .idle {
            handleCalibration(sample)
            return
        }
        guard settings.isEnabled, !isPaused, let storedProfile = profile else { return }

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
            calibrationError = "头部追踪已中断，请连接 AirPods 后重新校准"
        }
        guard settings.isEnabled, !isPaused else { return }
        if available {
            if profile == nil { status = .needsCalibration }
        } else {
            profile = nil
            analyzer.reset(covered: hasArmedOnce && settings.keepCoveredOnTrackingLoss)
            status = .trackingLost
            if hasArmedOnce, settings.keepCoveredOnTrackingLoss {
                showOverlay(message: "AirPods 连接中断")
            } else {
                overlayController.hide()
            }
        }
    }

    private func handleCalibration(_ sample: MotionSample) {
        guard isCapturingCalibration else { return }
        if calibrationStartedAt == nil { calibrationStartedAt = sample.timestamp }
        guard let startedAt = calibrationStartedAt else { return }
        calibrationSamples.append((sample.yaw, sample.pitch))
        let elapsed = sample.timestamp.timeIntervalSince(startedAt)
        calibrationProgress = min(1, elapsed / 1.25)
        guard elapsed >= 1.25, calibrationSamples.count >= 5 else { return }

        capturedStages[calibrationStage] = averaged(calibrationSamples)
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
        defer {
            calibrationStage = .idle
            calibrationStartedAt = nil
            calibrationSamples.removeAll()
            capturedStages.removeAll()
            calibrationProgress = 0
            isCapturingCalibration = false
            onMotionRequirementChanged?()
        }
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
            calibrationError = "边界角度太小或方向重复，请重新校准"
            status = .needsCalibration
            return
        }

        profile = newProfile
        settings.leftAngle = newProfile.leftAngle.rounded()
        settings.rightAngle = newProfile.rightAngle.rounded()
        settings.upAngle = newProfile.upAngle.rounded()
        settings.downAngle = newProfile.downAngle.rounded()
        settings.isEnabled = true
        hasArmedOnce = true
        isPaused = false
        analyzer.reset()
        calibrationError = nil
        status = .watching
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

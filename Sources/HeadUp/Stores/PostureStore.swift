import AppKit
import CoreMotion
import Foundation

@MainActor
final class PostureStore: ObservableObject {
    @Published private(set) var status: PostureStatus = .disconnected
    @Published private(set) var isConnected = false
    @Published private(set) var angle = 0.0
    @Published private(set) var sustainedDuration: TimeInterval = 0
    @Published private(set) var calibrationStage: CalibrationStage = .idle
    @Published private(set) var calibrationProgress = 0.0
    @Published private(set) var remindersToday = 0
    @Published private(set) var notificationsAllowed: Bool?
    @Published var isMonitoring = true {
        didSet {
            if isMonitoring {
                analyzer.reset()
                refreshStatus()
            } else {
                status = .paused
                sustainedDuration = 0
            }
        }
    }

    let settings = AppSettings()

    private let motionService = HeadphoneMotionService()
    private let analyzer = PostureAnalyzer()
    private let notificationService = NotificationService()
    private let reminderHUDController = ReminderHUDController()
    private var calibrationStartedAt: Date?
    private var calibrationSamples: [Double] = []
    private var uprightPitch: Double?
    private var totalSamples = 0
    private var goodSamples = 0

    private enum DefaultsKey {
        static let baseline = "posture.baselinePitch"
        static let direction = "posture.downwardDirection"
    }

    init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: DefaultsKey.baseline) != nil {
            analyzer.baselinePitch = defaults.double(forKey: DefaultsKey.baseline)
            analyzer.downwardDirection = defaults.double(forKey: DefaultsKey.direction) == 0
                ? 1
                : defaults.double(forKey: DefaultsKey.direction)
        }

        motionService.onSample = { [weak self] sample in
            self?.handle(sample)
        }
        motionService.onConnectionChanged = { [weak self] connected in
            self?.isConnected = connected
            self?.refreshStatus()
        }
        motionService.onError = { [weak self] error in
            if let serviceError = error as? HeadphoneMotionService.ServiceError,
               serviceError == .permissionDenied {
                self?.status = .permissionDenied
            } else {
                self?.isConnected = false
                self?.refreshStatus()
            }
        }

        if settings.notificationsEnabled {
            refreshNotificationAuthorization()
        }
        motionService.start()
        refreshStatus()
    }

    deinit {
        motionService.stop()
    }

    var goodPosturePercentage: Int {
        guard totalSamples > 0 else { return 100 }
        return Int((Double(goodSamples) / Double(totalSamples) * 100).rounded())
    }

    var connectionText: String {
        isConnected ? "AirPods 头部追踪已连接" : "未检测到兼容的 AirPods"
    }

    var menuBarIcon: String {
        switch status {
        case .warning: return "person.fill.turn.down"
        case .good: return "person.fill.checkmark"
        case .calibrating: return "scope"
        default: return "person.crop.circle.badge.questionmark"
        }
    }

    func startCalibration() {
        guard isConnected else { return }
        HeadUpLog.calibration.info("Two-stage calibration started")
        calibrationStage = .upright
        calibrationStartedAt = nil
        calibrationSamples.removeAll(keepingCapacity: true)
        uprightPitch = nil
        calibrationProgress = 0
        status = .calibrating(.upright)
        analyzer.reset()
    }

    func openMotionPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Motion") else { return }
        NSWorkspace.shared.open(url)
    }

    func refreshNotificationAuthorization() {
        notificationService.resolveAuthorization { [weak self] allowed in
            DispatchQueue.main.async {
                self?.notificationsAllowed = allowed
            }
        }
    }

    func openNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    func testReminder() {
        presentReminder(angle: max(angle, settings.threshold))
    }

    private func handle(_ sample: MotionSample) {
        isConnected = true

        if calibrationStage != .idle {
            handleCalibration(sample)
            return
        }

        guard isMonitoring else { return }
        guard let reading = analyzer.process(
            pitch: sample.pitch,
            at: sample.timestamp,
            threshold: settings.threshold,
            reminderDelay: settings.reminderDelay,
            cooldown: settings.cooldown
        ) else {
            status = .needsCalibration
            return
        }

        angle = reading.angle
        sustainedDuration = reading.sustainedDuration
        status = reading.isWarning ? .warning : .good
        totalSamples += 1
        if reading.angle < settings.threshold {
            goodSamples += 1
        }

        if reading.shouldNotify {
            remindersToday += 1
            presentReminder(angle: reading.angle)
        }
    }

    private func handleCalibration(_ sample: MotionSample) {
        if calibrationStartedAt == nil {
            calibrationStartedAt = sample.timestamp
        }

        guard let startedAt = calibrationStartedAt else { return }
        let elapsed = sample.timestamp.timeIntervalSince(startedAt)
        calibrationProgress = min(1, elapsed / 2)
        calibrationSamples.append(sample.pitch)

        guard elapsed >= 2 else { return }
        let average = calibrationSamples.reduce(0, +) / Double(calibrationSamples.count)

        switch calibrationStage {
        case .upright:
            uprightPitch = average
            HeadUpLog.calibration.info("Upright calibration stage completed")
            calibrationStage = .lookDown
            calibrationStartedAt = nil
            calibrationSamples.removeAll(keepingCapacity: true)
            calibrationProgress = 0
            status = .calibrating(.lookDown)

        case .lookDown:
            guard let uprightPitch else { return }
            analyzer.calibrate(uprightPitch: uprightPitch, lookDownPitch: average)
            UserDefaults.standard.set(uprightPitch, forKey: DefaultsKey.baseline)
            UserDefaults.standard.set(analyzer.downwardDirection, forKey: DefaultsKey.direction)
            HeadUpLog.calibration.info("Look-down stage completed; calibration saved")
            calibrationStage = .idle
            calibrationStartedAt = nil
            calibrationSamples.removeAll()
            calibrationProgress = 0
            angle = 0
            status = .good

        case .idle:
            break
        }
    }

    private func refreshStatus() {
        guard isMonitoring else {
            status = .paused
            return
        }
        guard isConnected else {
            status = .disconnected
            return
        }
        status = analyzer.isCalibrated ? .good : .needsCalibration
    }

    private func presentReminder(angle: Double) {
        if settings.notificationsEnabled, notificationsAllowed == true {
            notificationService.sendPostureReminder(angle: angle)
        } else {
            reminderHUDController.show(angle: angle)
            notificationService.playFallbackSound()
        }
    }
}

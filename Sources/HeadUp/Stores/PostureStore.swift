import AppKit
import CoreMotion
import Foundation

@MainActor
final class PostureStore: ObservableObject {
    @Published private(set) var status: PostureStatus = .disconnected
    @Published private(set) var isConnected = false
    @Published private(set) var isTrackingAvailable = false
    @Published private(set) var angle = 0.0
    @Published private(set) var sustainedDuration: TimeInterval = 0
    @Published private(set) var calibrationStage: CalibrationStage = .idle
    @Published private(set) var calibrationProgress = 0.0
    @Published private(set) var remindersToday = 0
    @Published private(set) var notificationsAllowed: Bool?
    @Published private(set) var headphoneActivity: HeadphoneActivity = .unknown
    @Published private(set) var calibrationError: String?
    @Published private(set) var launchAtLogin = false
    @Published private(set) var launchAtLoginError: String?
    @Published private(set) var recentPostureBins: [PostureBinState] = Array(repeating: .empty, count: 30)
    @Published var isMonitoring = true {
        didSet {
            if isMonitoring {
                analyzer.reset()
                motionService.restart()
                activityService.start()
                refreshStatus()
            } else {
                motionService.setMotionUpdatesEnabled(false)
                activityService.stop()
                analyzer.reset()
                status = .paused
                sustainedDuration = 0
            }
        }
    }

    let settings = AppSettings()

    private let motionService = HeadphoneMotionService()
    private let activityService = HeadphoneActivityService()
    private let loginItemService = LoginItemService()
    private let analyzer = PostureAnalyzer()
    private let notificationService = NotificationService()
    private let reminderHUDController = ReminderHUDController()
    private let defaults = UserDefaults.standard
    private var postureHistory: PostureHistory = {
        guard let data = UserDefaults.standard.data(forKey: DefaultsKey.history),
              let entries = try? JSONDecoder().decode([PostureHistoryEntry].self, from: data) else {
            return PostureHistory()
        }
        return PostureHistory(entries: entries)
    }()
    private var calibrationStartedAt: Date?
    private var calibrationSamples: [Double] = []
    private var uprightPitch: Double?
    private var totalSamples = 0
    private var goodSamples = 0
    private var lastStatisticsAt: Date?
    private var lastMotionSampleAt: Date?
    private var onboardingObserver: NSObjectProtocol?
    private var hasStartedServices = false

    private enum DefaultsKey {
        static let baseline = "posture.baselinePitch"
        static let direction = "posture.downwardDirection"
        static let statsDay = "stats.day"
        static let totalSamples = "stats.totalSamples"
        static let goodSamples = "stats.goodSamples"
        static let reminders = "stats.reminders"
        static let history = "stats.recentHistory"
    }

    init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: DefaultsKey.baseline) != nil {
            analyzer.baselinePitch = defaults.double(forKey: DefaultsKey.baseline)
            analyzer.downwardDirection = defaults.double(forKey: DefaultsKey.direction) == 0
                ? 1
                : defaults.double(forKey: DefaultsKey.direction)
        }

        loadDailyStatistics(at: Date())
        recentPostureBins = postureHistory.bins()
        launchAtLogin = loginItemService.isEnabled

        motionService.onSample = { [weak self] sample in
            self?.handle(sample)
        }
        motionService.onConnectionChanged = { [weak self] connected in
            self?.handleConnectionChanged(connected)
        }
        motionService.onTrackingAvailabilityChanged = { [weak self] available in
            self?.handleTrackingAvailabilityChanged(available)
        }
        motionService.onError = { [weak self] error in
            if let serviceError = error as? HeadphoneMotionService.ServiceError,
               serviceError == .permissionDenied {
                self?.isConnected = false
                self?.cancelCalibrationAfterDisconnect()
                self?.resetLiveSession()
                self?.status = .permissionDenied
            } else {
                self?.handleConnectionChanged(false)
            }
        }
        activityService.onActivityChanged = { [weak self] activity in
            self?.handleActivity(activity)
        }

        onboardingObserver = NotificationCenter.default.addObserver(
            forName: .headUpOnboardingCompleted,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.startServices()
            }
        }

        if defaults.bool(forKey: HeadUpDefaultsKey.onboardingCompleted) {
            startServices()
        }
    }

    deinit {
        if let onboardingObserver {
            NotificationCenter.default.removeObserver(onboardingObserver)
        }
        motionService.stop()
        activityService.stop()
    }

    var goodPosturePercentage: Int? {
        guard totalSamples > 0 else { return nil }
        return Int((Double(goodSamples) / Double(totalSamples) * 100).rounded())
    }

    var connectionText: String {
        guard isConnected else { return "未检测到兼容的 AirPods" }
        return isTrackingAvailable ? "AirPods 头部追踪已连接" : "AirPods 已连接，头部追踪暂不可用"
    }

    func startCalibration() {
        guard isConnected else { return }
        calibrationError = nil
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

    func retryMotionAccess() {
        isConnected = false
        cancelCalibrationAfterDisconnect()
        resetLiveSession()
        status = .disconnected
        motionService.stop()
        activityService.stop()
        motionService.start()
        activityService.start()
        refreshStatus()
    }

    private func startServices() {
        guard !hasStartedServices else { return }
        hasStartedServices = true
        if settings.notificationsEnabled {
            refreshNotificationAuthorization()
        }
        motionService.start()
        activityService.start()
        refreshStatus()
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

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try loginItemService.setEnabled(enabled)
            launchAtLogin = loginItemService.isEnabled
            launchAtLoginError = nil
        } catch {
            launchAtLogin = loginItemService.isEnabled
            launchAtLoginError = error.localizedDescription
            HeadUpLog.lifecycle.error("Login item update failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func clearPostureHistory() {
        let day = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
        resetDailyStatistics(day: day)
        postureHistory.removeAll()
        recentPostureBins = Array(repeating: .empty, count: 30)
        defaults.removeObject(forKey: DefaultsKey.history)
        objectWillChange.send()
    }

    func copyDiagnosticInfo() {
        let authorization = CMHeadphoneMotionManager.authorizationStatus()
        let summary = """
        HeadUp: \(HeadUpAppInfo.versionDescription)
        macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        Motion authorization: \(authorization.rawValue)
        AirPods connected: \(isConnected)
        Head tracking available: \(isTrackingAvailable)
        Headphone activity: \(headphoneActivity.diagnosticDescription)
        Monitoring enabled: \(isMonitoring)
        Calibrated: \(analyzer.isCalibrated)
        Installed in Applications: \(HeadUpAppInfo.isInstalledInApplications)
        """

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(summary, forType: .string)
        HeadUpLog.lifecycle.notice("Privacy-safe diagnostic summary copied")
    }

    private func handle(_ sample: MotionSample) {
        isConnected = true

        if let previous = lastMotionSampleAt,
           sample.timestamp.timeIntervalSince(previous) > 2 {
            resetLiveSession()
        }
        lastMotionSampleAt = sample.timestamp

        if calibrationStage != .idle {
            handleCalibration(sample)
            return
        }

        guard isMonitoring else { return }
        guard !headphoneActivity.isMoving else {
            status = .moving
            return
        }
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
        status = reading.isWarning ? .warning : (reading.isBeyondThreshold ? .caution : .good)
        recordStatistics(reading, at: sample.timestamp)

        if reading.shouldNotify {
            remindersToday += 1
            defaults.set(remindersToday, forKey: DefaultsKey.reminders)
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
            guard analyzer.calibrate(uprightPitch: uprightPitch, lookDownPitch: average) else {
                calibrationStage = .idle
                calibrationStartedAt = nil
                calibrationSamples.removeAll()
                calibrationProgress = 0
                calibrationError = "低头幅度太小，请保持坐直后重新校准"
                status = .needsCalibration
                HeadUpLog.calibration.notice("Calibration rejected because movement was too small")
                return
            }
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
        guard isTrackingAvailable else {
            status = .unavailable
            return
        }
        guard !headphoneActivity.isMoving else {
            status = .moving
            return
        }
        status = analyzer.isCalibrated ? .good : .needsCalibration
    }

    private func presentReminder(angle: Double) {
        if settings.notificationsEnabled, notificationsAllowed == true {
            notificationService.sendPostureReminder(angle: angle)
        } else {
            reminderHUDController.show(angle: angle)
        }

        if settings.audibleRemindersEnabled {
            notificationService.playReminderSound()
        }
    }

    private func recordStatistics(_ reading: PostureReading, at date: Date) {
        ensureCurrentDay(at: date)
        let isGood = reading.angle < settings.threshold

        if lastStatisticsAt.map({ date.timeIntervalSince($0) >= 1 }) ?? true {
            lastStatisticsAt = date
            totalSamples += 1
            if isGood { goodSamples += 1 }
            defaults.set(totalSamples, forKey: DefaultsKey.totalSamples)
            defaults.set(goodSamples, forKey: DefaultsKey.goodSamples)
            objectWillChange.send()
        }

        if postureHistory.record(isGood: isGood, at: date) {
            recentPostureBins = postureHistory.bins(now: date)
            if let data = try? JSONEncoder().encode(postureHistory.entries) {
                defaults.set(data, forKey: DefaultsKey.history)
            }
        }
    }

    private func loadDailyStatistics(at date: Date) {
        let day = Calendar.current.startOfDay(for: date).timeIntervalSince1970
        guard defaults.double(forKey: DefaultsKey.statsDay) == day else {
            resetDailyStatistics(day: day)
            return
        }
        totalSamples = defaults.integer(forKey: DefaultsKey.totalSamples)
        goodSamples = defaults.integer(forKey: DefaultsKey.goodSamples)
        remindersToday = defaults.integer(forKey: DefaultsKey.reminders)
    }

    private func ensureCurrentDay(at date: Date) {
        let day = Calendar.current.startOfDay(for: date).timeIntervalSince1970
        if defaults.double(forKey: DefaultsKey.statsDay) != day {
            resetDailyStatistics(day: day)
        }
    }

    private func resetDailyStatistics(day: TimeInterval) {
        totalSamples = 0
        goodSamples = 0
        remindersToday = 0
        defaults.set(day, forKey: DefaultsKey.statsDay)
        defaults.set(0, forKey: DefaultsKey.totalSamples)
        defaults.set(0, forKey: DefaultsKey.goodSamples)
        defaults.set(0, forKey: DefaultsKey.reminders)
    }

    private func handleActivity(_ activity: HeadphoneActivity) {
        headphoneActivity = activity
        if activity.isMoving {
            analyzer.reset()
            sustainedDuration = 0
            status = .moving
        } else {
            refreshStatus()
        }
    }

    private func handleConnectionChanged(_ connected: Bool) {
        HeadUpLog.motion.notice("Verified headphone connection changed; connected=\(connected, privacy: .public)")
        isConnected = connected
        if !connected {
            isTrackingAvailable = false
            cancelCalibrationAfterDisconnect()
            resetLiveSession()
        }
        refreshStatus()
    }

    private func handleTrackingAvailabilityChanged(_ available: Bool) {
        HeadUpLog.motion.notice("Headphone tracking availability changed; available=\(available, privacy: .public)")
        isTrackingAvailable = available
        if !available {
            resetLiveSession()
        }
        refreshStatus()
    }

    private func cancelCalibrationAfterDisconnect() {
        guard calibrationStage != .idle else { return }
        calibrationStage = .idle
        calibrationStartedAt = nil
        calibrationSamples.removeAll()
        calibrationProgress = 0
        uprightPitch = nil
        if !analyzer.isCalibrated {
            calibrationError = "AirPods 已断开，请重新连接后再校准"
        }
        HeadUpLog.calibration.notice("Calibration cancelled after headphones disconnected")
    }

    private func resetLiveSession() {
        analyzer.reset()
        angle = 0
        sustainedDuration = 0
        lastMotionSampleAt = nil
    }
}

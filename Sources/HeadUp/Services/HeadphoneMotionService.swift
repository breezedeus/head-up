import CoreMotion
import Foundation

final class HeadphoneMotionService: NSObject, CMHeadphoneMotionManagerDelegate {
    enum ServiceError: LocalizedError {
        case motionUnavailable
        case permissionDenied

        var errorDescription: String? {
            switch self {
            case .motionUnavailable: return "当前没有可用的 AirPods 头部运动数据"
            case .permissionDenied: return "运动与健身权限已关闭"
            }
        }
    }

    var onSample: ((MotionSample) -> Void)?
    var onConnectionChanged: ((Bool) -> Void)?
    var onTrackingAvailabilityChanged: ((Bool) -> Void)?
    var onError: ((Error) -> Void)?

    private let manager = CMHeadphoneMotionManager()
    private var hasLoggedFirstSample = false
    private var motionUpdatesEnabled = true
    private var reportedConnected = false
    private var reportedTrackingAvailable = false
    private var connectionWatchdog: DispatchWorkItem?
    private let connectionTimeout: TimeInterval = 5
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.king.headup.motion"
        queue.qualityOfService = .userInteractive
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    override init() {
        super.init()
        manager.delegate = self
    }

    func start() {
        let authorization = CMHeadphoneMotionManager.authorizationStatus()
        if authorization == .denied || authorization == .restricted {
            HeadUpLog.motion.error("Headphone motion authorization denied or restricted")
            onError?(ServiceError.permissionDenied)
            return
        }

        HeadUpLog.motion.notice("Starting headphone connection monitoring")
        manager.startConnectionStatusUpdates()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let hasCompatibleHeadphones = Self.hasInitialConnectionEvidence(
                isDeviceMotionAvailable: self.manager.isDeviceMotionAvailable
            )
            self.updateVerifiedConnection(hasCompatibleHeadphones, force: true)
            self.updateTrackingAvailability(false, force: true)
            if hasCompatibleHeadphones, self.motionUpdatesEnabled {
                self.armConnectionWatchdog()
            }
        }
        startMotionUpdatesIfAvailable()
    }

    func stop() {
        connectionWatchdog?.cancel()
        connectionWatchdog = nil
        manager.stopDeviceMotionUpdates()
        manager.stopConnectionStatusUpdates()
        hasLoggedFirstSample = false
    }

    func restart() {
        HeadUpLog.motion.notice("Restarting headphone motion session")
        stop()
        start()
    }

    func setMotionUpdatesEnabled(_ enabled: Bool) {
        motionUpdatesEnabled = enabled
        if enabled {
            startMotionUpdatesIfAvailable()
        } else {
            connectionWatchdog?.cancel()
            connectionWatchdog = nil
            manager.stopDeviceMotionUpdates()
            HeadUpLog.motion.notice("Headphone device-motion updates paused")
        }
    }

    private func startMotionUpdatesIfAvailable() {
        guard motionUpdatesEnabled else { return }
        guard manager.isDeviceMotionAvailable else {
            HeadUpLog.motion.notice("Headphone motion is currently unavailable")
            DispatchQueue.main.async { [weak self] in
                self?.updateTrackingAvailability(false)
            }
            return
        }

        guard !manager.isDeviceMotionActive else { return }

        HeadUpLog.motion.notice("Starting headphone device-motion updates; waiting for connection evidence")

        manager.startDeviceMotionUpdates(to: queue) { [weak self] motion, error in
            if let error {
                HeadUpLog.motion.error("Device-motion update failed: \(error.localizedDescription, privacy: .public)")
                DispatchQueue.main.async { self?.onError?(error) }
                return
            }

            guard let self, let attitude = motion?.attitude else { return }
            if !self.hasLoggedFirstSample {
                self.hasLoggedFirstSample = true
                HeadUpLog.motion.notice("Received first headphone motion sample")
            }
            let radiansToDegrees = 180.0 / Double.pi
            let sample = MotionSample(
                pitch: attitude.pitch * radiansToDegrees,
                roll: attitude.roll * radiansToDegrees,
                timestamp: Date()
            )

            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.motionUpdatesEnabled,
                      self.manager.isDeviceMotionActive else { return }
                self.updateVerifiedConnection(true)
                self.updateTrackingAvailability(true)
                self.armConnectionWatchdog()
                self.onSample?(sample)
            }
        }
    }

    func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        HeadUpLog.motion.notice("Motion-capable headphones connected")
        startMotionUpdatesIfAvailable()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.updateVerifiedConnection(true)
            self.updateTrackingAvailability(false)
            if self.motionUpdatesEnabled {
                self.armConnectionWatchdog()
            }
        }
    }

    func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        HeadUpLog.motion.notice("Motion-capable headphones disconnected")
        hasLoggedFirstSample = false
        manager.stopDeviceMotionUpdates()
        DispatchQueue.main.async { [weak self] in
            self?.connectionWatchdog?.cancel()
            self?.connectionWatchdog = nil
            self?.updateTrackingAvailability(false)
            self?.updateVerifiedConnection(false)
        }
    }

    private func updateVerifiedConnection(_ connected: Bool, force: Bool = false) {
        guard force || reportedConnected != connected else { return }
        reportedConnected = connected
        onConnectionChanged?(connected)
    }

    static func hasInitialConnectionEvidence(isDeviceMotionAvailable: Bool) -> Bool {
        isDeviceMotionAvailable
    }

    private func updateTrackingAvailability(_ available: Bool, force: Bool = false) {
        guard force || reportedTrackingAvailable != available else { return }
        reportedTrackingAvailable = available
        onTrackingAvailabilityChanged?(available)
    }

    private func armConnectionWatchdog() {
        connectionWatchdog?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.motionUpdatesEnabled, self.reportedConnected else { return }
            HeadUpLog.motion.notice("No headphone motion samples within liveness window; marking tracking unavailable")
            self.updateTrackingAvailability(false)
        }
        connectionWatchdog = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + connectionTimeout, execute: workItem)
    }
}

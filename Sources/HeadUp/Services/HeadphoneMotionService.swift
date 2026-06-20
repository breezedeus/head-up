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
    var onError: ((Error) -> Void)?

    private let manager = CMHeadphoneMotionManager()
    private var hasLoggedFirstSample = false
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
        startMotionUpdatesIfAvailable()
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        manager.stopConnectionStatusUpdates()
    }

    private func startMotionUpdatesIfAvailable() {
        guard manager.isDeviceMotionAvailable else {
            HeadUpLog.motion.notice("Headphone motion is currently unavailable")
            DispatchQueue.main.async { [weak self] in
                self?.onConnectionChanged?(false)
            }
            return
        }

        guard !manager.isDeviceMotionActive else { return }

        HeadUpLog.motion.notice("Starting headphone device-motion updates")
        DispatchQueue.main.async { [weak self] in
            self?.onConnectionChanged?(true)
        }

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

            DispatchQueue.main.async {
                self.onSample?(sample)
            }
        }
    }

    func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        HeadUpLog.motion.notice("Motion-capable headphones connected")
        startMotionUpdatesIfAvailable()
    }

    func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        HeadUpLog.motion.notice("Motion-capable headphones disconnected")
        hasLoggedFirstSample = false
        manager.stopDeviceMotionUpdates()
        DispatchQueue.main.async { [weak self] in
            self?.onConnectionChanged?(false)
        }
    }
}

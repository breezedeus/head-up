import CoreMotion
import Foundation

final class HeadphoneActivityService {
    var onActivityChanged: ((HeadphoneActivity) -> Void)?

    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.king.headup.activity"
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    private var managerStorage: AnyObject?

    func start() {
        guard #available(macOS 15.0, *) else { return }
        let manager: CMHeadphoneActivityManager
        if let existing = managerStorage as? CMHeadphoneActivityManager {
            manager = existing
        } else {
            let created = CMHeadphoneActivityManager()
            managerStorage = created
            manager = created
        }
        guard manager.isActivityAvailable, !manager.isActivityActive else { return }

        manager.startActivityUpdates(to: queue) { [weak self] activity, error in
            if let error {
                HeadUpLog.activity.error("Headphone activity update failed: \(error.localizedDescription, privacy: .public)")
                return
            }
            guard let activity else { return }

            let value: HeadphoneActivity
            if activity.walking {
                value = .walking
            } else if activity.running {
                value = .running
            } else if activity.stationary {
                value = .stationary
            } else {
                value = .unknown
            }

            DispatchQueue.main.async {
                self?.onActivityChanged?(value)
            }
        }
        HeadUpLog.activity.notice("Headphone activity updates started")
    }

    func stop() {
        guard #available(macOS 15.0, *) else { return }
        (managerStorage as? CMHeadphoneActivityManager)?.stopActivityUpdates()
    }
}

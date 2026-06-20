import AppKit
import Foundation
import UserNotifications

final class NotificationService {
    func resolveAuthorization(completion: @escaping (Bool) -> Void) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                HeadUpLog.reminders.notice("Notification authorization is available")
                completion(true)

            case .denied:
                HeadUpLog.reminders.notice("Notifications are disabled in System Settings")
                completion(false)

            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, error in
                    if let error {
                        HeadUpLog.reminders.error("Notification authorization failed: \(error.localizedDescription, privacy: .public)")
                    } else {
                        HeadUpLog.reminders.notice("Notification authorization resolved; granted=\(granted, privacy: .public)")
                    }
                    completion(granted)
                }

            @unknown default:
                completion(false)
            }
        }
    }

    func sendPostureReminder(angle: Double) {
        let content = UNMutableNotificationContent()
        content.title = "抬头"
        content.body = "你已经低头一会儿了。下巴轻轻抬一点，肩膀放松。"
        content.sound = .default
        content.userInfo = ["angle": angle]

        let request = UNNotificationRequest(
            identifier: "posture-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                HeadUpLog.reminders.error("Posture notification scheduling failed: \(error.localizedDescription, privacy: .public)")
            } else {
                HeadUpLog.reminders.notice("Posture notification scheduled")
            }
        }
    }

    func playFallbackSound() {
        NSSound.beep()
        HeadUpLog.reminders.notice("Played fallback posture alert sound")
    }
}

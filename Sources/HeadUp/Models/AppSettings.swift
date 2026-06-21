import Foundation

@MainActor
final class AppSettings: ObservableObject {
    private enum Key {
        static let threshold = "posture.threshold"
        static let reminderDelay = "posture.reminderDelay"
        static let cooldown = "posture.cooldown"
        static let notifications = "posture.notifications"
    }

    private let defaults: UserDefaults

    @Published var threshold: Double {
        didSet { defaults.set(threshold, forKey: Key.threshold) }
    }

    @Published var reminderDelay: Double {
        didSet { defaults.set(reminderDelay, forKey: Key.reminderDelay) }
    }

    @Published var cooldown: Double {
        didSet { defaults.set(cooldown, forKey: Key.cooldown) }
    }

    @Published var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: Key.notifications) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        threshold = defaults.object(forKey: Key.threshold) as? Double ?? 15
        reminderDelay = defaults.object(forKey: Key.reminderDelay) as? Double ?? 20
        cooldown = defaults.object(forKey: Key.cooldown) as? Double ?? 180
        notificationsEnabled = defaults.object(forKey: Key.notifications) as? Bool ?? false
    }
}

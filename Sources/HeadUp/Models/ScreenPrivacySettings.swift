import Foundation

@MainActor
final class ScreenPrivacySettings: ObservableObject {
    private enum Key {
        static let enabled = "privacy.enabled"
        static let leftAngle = "privacy.leftAngle"
        static let rightAngle = "privacy.rightAngle"
        static let upAngle = "privacy.upAngle"
        static let downAngle = "privacy.downAngle"
        static let hideDelay = "privacy.hideDelay"
        static let revealDelay = "privacy.revealDelay"
        static let backgroundStyle = "privacy.backgroundStyle"
        static let dimOpacity = "privacy.dimOpacity"
        static let showsTime = "privacy.showsTime"
        static let showsDate = "privacy.showsDate"
        static let showsSeconds = "privacy.showsSeconds"
        static let showsWeather = "privacy.showsWeather"
        static let weatherCity = "privacy.weatherCity"
        static let customText = "privacy.customText"
        static let showsCustomText = "privacy.showsCustomText"
        static let infoOnAllDisplays = "privacy.infoOnAllDisplays"
        static let keepCoveredOnTrackingLoss = "privacy.keepCoveredOnTrackingLoss"
        static let calibrationProfile = "privacy.calibrationProfile"
    }

    private let defaults: UserDefaults

    @Published var isEnabled: Bool { didSet { defaults.set(isEnabled, forKey: Key.enabled) } }
    @Published var leftAngle: Double { didSet { defaults.set(leftAngle, forKey: Key.leftAngle) } }
    @Published var rightAngle: Double { didSet { defaults.set(rightAngle, forKey: Key.rightAngle) } }
    @Published var upAngle: Double { didSet { defaults.set(upAngle, forKey: Key.upAngle) } }
    @Published var downAngle: Double { didSet { defaults.set(downAngle, forKey: Key.downAngle) } }
    @Published var hideDelay: Double { didSet { defaults.set(hideDelay, forKey: Key.hideDelay) } }
    @Published var revealDelay: Double { didSet { defaults.set(revealDelay, forKey: Key.revealDelay) } }
    @Published var backgroundStyle: ScreenPrivacyBackgroundStyle {
        didSet { defaults.set(backgroundStyle.rawValue, forKey: Key.backgroundStyle) }
    }
    @Published var dimOpacity: Double { didSet { defaults.set(dimOpacity, forKey: Key.dimOpacity) } }
    @Published var showsTime: Bool { didSet { defaults.set(showsTime, forKey: Key.showsTime) } }
    @Published var showsDate: Bool { didSet { defaults.set(showsDate, forKey: Key.showsDate) } }
    @Published var showsSeconds: Bool { didSet { defaults.set(showsSeconds, forKey: Key.showsSeconds) } }
    @Published var showsWeather: Bool { didSet { defaults.set(showsWeather, forKey: Key.showsWeather) } }
    @Published var weatherCity: String { didSet { defaults.set(weatherCity, forKey: Key.weatherCity) } }
    @Published var customText: String { didSet { defaults.set(customText, forKey: Key.customText) } }
    @Published var showsCustomText: Bool { didSet { defaults.set(showsCustomText, forKey: Key.showsCustomText) } }
    @Published var infoOnAllDisplays: Bool { didSet { defaults.set(infoOnAllDisplays, forKey: Key.infoOnAllDisplays) } }
    @Published var keepCoveredOnTrackingLoss: Bool {
        didSet { defaults.set(keepCoveredOnTrackingLoss, forKey: Key.keepCoveredOnTrackingLoss) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Key.enabled) as? Bool ?? false
        leftAngle = defaults.object(forKey: Key.leftAngle) as? Double ?? 35
        rightAngle = defaults.object(forKey: Key.rightAngle) as? Double ?? 35
        upAngle = defaults.object(forKey: Key.upAngle) as? Double ?? 20
        downAngle = defaults.object(forKey: Key.downAngle) as? Double ?? 25
        hideDelay = defaults.object(forKey: Key.hideDelay) as? Double ?? 0.8
        revealDelay = defaults.object(forKey: Key.revealDelay) as? Double ?? 0.3
        backgroundStyle = ScreenPrivacyBackgroundStyle(
            rawValue: defaults.string(forKey: Key.backgroundStyle) ?? "blur"
        ) ?? .blur
        dimOpacity = defaults.object(forKey: Key.dimOpacity) as? Double ?? 0.34
        showsTime = defaults.object(forKey: Key.showsTime) as? Bool ?? true
        showsDate = defaults.object(forKey: Key.showsDate) as? Bool ?? true
        showsSeconds = defaults.object(forKey: Key.showsSeconds) as? Bool ?? false
        showsWeather = defaults.object(forKey: Key.showsWeather) as? Bool ?? false
        weatherCity = defaults.string(forKey: Key.weatherCity) ?? ""
        customText = defaults.string(forKey: Key.customText) ?? ""
        showsCustomText = defaults.object(forKey: Key.showsCustomText) as? Bool ?? false
        infoOnAllDisplays = defaults.object(forKey: Key.infoOnAllDisplays) as? Bool ?? false
        keepCoveredOnTrackingLoss = defaults.object(forKey: Key.keepCoveredOnTrackingLoss) as? Bool ?? true
    }

    var calibrationProfile: ScreenPrivacyCalibrationProfile? {
        guard let data = defaults.data(forKey: Key.calibrationProfile) else { return nil }
        return try? JSONDecoder().decode(ScreenPrivacyCalibrationProfile.self, from: data)
    }

    func saveCalibrationProfile(_ profile: ScreenPrivacyCalibrationProfile) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        defaults.set(data, forKey: Key.calibrationProfile)
    }

    var displayProfiles: [ScreenPrivacyDisplayProfile] {
        guard let data = defaults.data(forKey: "privacy.displayProfiles") else { return [] }
        return (try? JSONDecoder().decode([ScreenPrivacyDisplayProfile].self, from: data)) ?? []
    }

    func saveDisplayProfiles(_ profiles: [ScreenPrivacyDisplayProfile]) {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        defaults.set(data, forKey: "privacy.displayProfiles")
    }

    var thresholds: ScreenPrivacyThresholds {
        ScreenPrivacyThresholds(hideDelay: hideDelay, revealDelay: revealDelay, hysteresis: 3)
    }
}

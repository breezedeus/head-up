import AppKit
import Combine
import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return L10n.text("跟随系统")
        case .simplifiedChinese: return "简体中文"
        case .english: return "English"
        }
    }

    static func resolve(_ preference: AppLanguage, preferredLanguages: [String]) -> AppLanguage {
        guard preference == .system else { return preference }
        for identifier in preferredLanguages {
            let base = identifier.replacingOccurrences(of: "_", with: "-").lowercased().split(separator: "-").first
            if base == "zh" { return .simplifiedChinese }
            if base == "en" { return .english }
        }
        return .english
    }
}

/// Explicit bundle selection also localizes strings outside the SwiftUI hierarchy,
/// such as notifications, errors, and AppKit window titles.
enum L10n {
    static let preferenceKey = "app.language"
    static var language: AppLanguage {
        AppLanguage.resolve(
            AppLanguage(rawValue: UserDefaults.standard.string(forKey: preferenceKey) ?? "") ?? .system,
            preferredLanguages: Locale.preferredLanguages
        )
    }
    static var locale: Locale { locale(for: language) }

    static func locale(for language: AppLanguage) -> Locale {
        let region = Locale.current.region?.identifier ?? (language == .simplifiedChinese ? "CN" : "US")
        return Locale(identifier: "\(language == .simplifiedChinese ? "zh-Hans" : "en")-\(region)")
    }

    private static let bundles: [AppLanguage: Bundle] = {
        var result: [AppLanguage: Bundle] = [:]
        for language in [AppLanguage.english, .simplifiedChinese] {
            if let path = Bundle.module.path(forResource: language.rawValue, ofType: "lproj"),
               let bundle = Bundle(path: path) { result[language] = bundle }
        }
        return result
    }()

    private static let placeholderExpression = try! NSRegularExpression(pattern: #"\{(\d+)\}"#)

    static func text(_ key: String, _ arguments: String...) -> String {
        format(key, arguments: arguments, language: language)
    }

    static func format(_ key: String, arguments: [String] = [], language: AppLanguage) -> String {
        let resolved = language == .system ? self.language : language
        let template = bundles[resolved]?.localizedString(forKey: key, value: key, table: nil) ?? key
        // Replace template tokens in one pass, so argument text is never reinterpreted.
        guard !arguments.isEmpty else { return template }
        let matches = placeholderExpression.matches(in: template, range: NSRange(template.startIndex..., in: template))
        var result = template
        for match in matches.reversed() {
            guard let indexRange = Range(match.range(at: 1), in: template),
                  let index = Int(template[indexRange]), arguments.indices.contains(index),
                  let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: arguments[index])
        }
        return result
    }
}

extension Notification.Name {
    static let headUpLanguageChanged = Notification.Name("HeadUpLanguageChanged")
}

@MainActor
final class AppLocalization: ObservableObject {
    static let shared = AppLocalization()
    private let defaults: UserDefaults
    private let preferredLanguages: () -> [String]
    private var observers: [NSObjectProtocol] = []
    @Published private(set) var effectiveLanguage: AppLanguage
    @Published var preference: AppLanguage {
        didSet {
            guard oldValue != preference else { return }
            defaults.set(preference.rawValue, forKey: L10n.preferenceKey)
            refresh()
        }
    }
    var locale: Locale { L10n.locale(for: effectiveLanguage) }

    init(defaults: UserDefaults = .standard, preferredLanguages: @escaping () -> [String] = { Locale.preferredLanguages }) {
        self.defaults = defaults
        self.preferredLanguages = preferredLanguages
        let preference = AppLanguage(rawValue: defaults.string(forKey: L10n.preferenceKey) ?? "") ?? .system
        self.preference = preference
        self.effectiveLanguage = AppLanguage.resolve(preference, preferredLanguages: preferredLanguages())
        for name in [NSLocale.currentLocaleDidChangeNotification, NSApplication.didBecomeActiveNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refresh() }
            })
        }
    }

    func refresh() {
        let next = AppLanguage.resolve(preference, preferredLanguages: preferredLanguages())
        guard next != effectiveLanguage else { objectWillChange.send(); return }
        effectiveLanguage = next
        NotificationCenter.default.post(name: .headUpLanguageChanged, object: nil)
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
}

import Foundation
import Testing
@testable import HeadUp

struct AppLocalizationTests {
    @Test func resolvesSystemLanguageAndRegionalVariants() {
        #expect(AppLanguage.resolve(.system, preferredLanguages: ["en-GB", "zh-Hans-CN"]) == .english)
        #expect(AppLanguage.resolve(.system, preferredLanguages: ["zh-Hant-TW", "en"]) == .simplifiedChinese)
        #expect(AppLanguage.resolve(.system, preferredLanguages: ["zh_CN"]) == .simplifiedChinese)
        #expect(AppLanguage.resolve(.system, preferredLanguages: ["fr-FR", "en-US"]) == .english)
        #expect(AppLanguage.resolve(.system, preferredLanguages: ["ja-JP"]) == .english)
        #expect(AppLanguage.resolve(.system, preferredLanguages: []) == .english)
        #expect(AppLanguage.resolve(.english, preferredLanguages: ["zh-Hans"]) == .english)
        #expect(AppLanguage.resolve(.simplifiedChinese, preferredLanguages: ["en"]) == .simplifiedChinese)
    }

    @Test func bundledTranslationsAndInterpolationWorkInBothLanguages() {
        #expect(L10n.format("屏幕保护", language: .english) == "Screen Protection")
        #expect(L10n.format("屏幕保护", language: .simplifiedChinese) == "屏幕保护")
        #expect(L10n.format("{0} 分 {1} 秒", arguments: ["2", "15"], language: .english) == "2 min 15 s")
        #expect(L10n.format("{0} 分 {1} 秒", arguments: ["2", "15"], language: .simplifiedChinese) == "2 分 15 秒")
        #expect(L10n.format("城市，例如：上海", language: .english) == "City, e.g. Shanghai")
        #expect(L10n.format("抬头：{0}", arguments: ["{1} 100%"], language: .english) == "HeadUp: {1} 100%")
        #expect(L10n.format("unknown-key", language: .english) == "unknown-key")
        #expect(WeatherService.description(for: 95, language: .english) == "Thunderstorms")
    }

    @MainActor @Test func languageChoicePersistsAndSystemModeRefreshes() throws {
        let name = "HeadUpTests.language.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        var preferred = ["zh-Hans-CN"]
        let localization = AppLocalization(defaults: defaults, preferredLanguages: { preferred })
        #expect(localization.preference == .system)
        #expect(localization.effectiveLanguage == .simplifiedChinese)
        localization.preference = .english
        #expect(defaults.string(forKey: L10n.preferenceKey) == "en")
        #expect(localization.effectiveLanguage == .english)
        let reloaded = AppLocalization(defaults: defaults, preferredLanguages: { preferred })
        #expect(reloaded.preference == .english)
        localization.preference = .system
        preferred = ["en-AU"]
        localization.refresh()
        #expect(localization.effectiveLanguage == .english)
        preferred = ["zh-Hans"]
        localization.refresh()
        #expect(localization.effectiveLanguage == .simplifiedChinese)
    }

    @Test func translationTablesHaveMatchingKeysAndPlaceholders() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let resourceRoot = root.appendingPathComponent("Sources/HeadUp/Resources")
        func table(_ language: String) throws -> [String: String] {
            let data = try Data(contentsOf: resourceRoot.appendingPathComponent("\(language).lproj/Localizable.strings"))
            return try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
        }
        let english = try table("en"), chinese = try table("zh-Hans")
        #expect(english.count >= 249)
        #expect(Set(english.keys) == Set(chinese.keys))
        let regex = try NSRegularExpression(pattern: #"\{\d+\}"#)
        func placeholders(_ value: String) -> [String] {
            regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).compactMap {
                Range($0.range, in: value).map { String(value[$0]) }
            }.sorted()
        }
        for (key, value) in english {
            #expect(!value.isEmpty)
            #expect(placeholders(key) == placeholders(value), "English placeholders: \(key)")
            #expect(placeholders(key) == placeholders(chinese[key] ?? ""), "Chinese placeholders: \(key)")
        }
    }

    @Test func everyLocalizedCallSiteKeyExistsInBothTables() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let sourceRoot = root.appendingPathComponent("Sources/HeadUp")
        func table(_ language: String) throws -> Set<String> {
            let url = root.appendingPathComponent("Sources/HeadUp/Resources/\(language).lproj/Localizable.strings")
            let data = try Data(contentsOf: url)
            let dictionary = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
            return Set(dictionary.keys)
        }
        let english = try table("en")
        let chinese = try table("zh-Hans")
        let pattern = try NSRegularExpression(pattern: #"L10n\.(?:text|format)\(\s*"((?:[^"\\]|\\.)*)""#)
        let enumerator = try #require(FileManager.default.enumerator(at: sourceRoot, includingPropertiesForKeys: nil))
        var missing = [String]()
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            let range = NSRange(source.startIndex..., in: source)
            pattern.enumerateMatches(in: source, range: range) { match, _, _ in
                guard let match, let keyRange = Range(match.range(at: 1), in: source) else { return }
                let key = String(source[keyRange])
                if !english.contains(key) || !chinese.contains(key) {
                    missing.append("\(fileURL.lastPathComponent): \(key)")
                }
            }
        }
        #expect(missing.isEmpty, "Localized keys missing from a table: \(missing)")
    }
}

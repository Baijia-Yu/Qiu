import Foundation

enum LanguagePackPreferences {
    static let defaultsKey = "preferredLanguagePackIdentities"

    static func pairKey(sourceLanguage: String, targetLanguage: String) -> String {
        "\(sourceLanguage)->\(targetLanguage)"
    }

    static func load(from defaults: UserDefaults = .standard) -> [String: String] {
        defaults.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
    }

    static func save(_ selections: [String: String], to defaults: UserDefaults = .standard) {
        defaults.set(selections, forKey: defaultsKey)
    }
}

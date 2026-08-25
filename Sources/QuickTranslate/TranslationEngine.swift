import Foundation
import CTranslateBridge

enum Language: String, Sendable {
    case english = "en"
    case chinese = "zh"
}

protocol TranslationEngine: Sendable {
    func translate(_ text: String, from source: Language, to target: Language) async throws -> String
    func unload() async
}

enum TranslationError: LocalizedError {
    case modelUnavailable(Language, Language)

    var errorDescription: String? {
        modelUnavailableMessage
    }

    private var modelUnavailableMessage: String {
        switch self {
        case .modelUnavailable(let source, let target):
            return source.rawValue + "→" + target.rawValue + " 离线模型尚未接入"
        }
    }
}

enum LanguageDetector {
    static func direction(for text: String) -> (source: Language, target: Language) {
        let meaningful = text.unicodeScalars.filter { !$0.properties.isWhitespace }
        let cjkCount = meaningful.filter { (0x4E00...0x9FFF).contains($0.value) }.count
        return cjkCount * 4 >= max(meaningful.count, 1)
            ? (.chinese, .english)
            : (.english, .chinese)
    }
}

actor TranslationCache {
    private struct Entry: Sendable {
        let value: String
        var sequence: UInt64
    }

    private var entries: [String: Entry] = [:]
    private var sequence: UInt64 = 0
    private let capacity: Int

    init(capacity: Int = 128) { self.capacity = capacity }

    func value(for key: String) -> String? {
        guard var entry = entries[key] else { return nil }
        sequence += 1
        entry.sequence = sequence
        entries[key] = entry
        return entry.value
    }

    func insert(_ value: String, for key: String) {
        sequence += 1
        entries[key] = Entry(value: value, sequence: sequence)
        guard entries.count > capacity, let oldest = entries.min(by: { $0.value.sequence < $1.value.sequence }) else { return }
        entries.removeValue(forKey: oldest.key)
    }

    func removeAll() { entries.removeAll(keepingCapacity: true) }
}

/// This actor owns only cache and model lifecycle; inference is isolated in Objective-C++.
actor LocalTranslationEngine: TranslationEngine {
    private let cache = TranslationCache(capacity: 128)
    private let packStore: LanguagePackStore
    private var loadedPackageIdentity: String?

    init(packStore: LanguagePackStore = LanguagePackStore()) {
        self.packStore = packStore
    }

    func translate(_ text: String, from source: Language, to target: Language) async throws -> String {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pack = await packStore.resolve(
            sourceLanguage: source.rawValue,
            targetLanguage: target.rawValue
        ) else {
            throw TranslationError.modelUnavailable(source, target)
        }
        let key = "\(normalized.lowercased())|\(source.rawValue)-\(target.rawValue)|\(pack.identity)"
        if let cached = await cache.value(for: key) { return cached }
        loadedPackageIdentity = pack.identity
        let result = try translateUncached(normalized, from: source, pack: pack)
        await cache.insert(result, for: key)
        return result
    }

    func unload() async {
        if let loadedPackageIdentity {
            QTNativeUnloadPackage(loadedPackageIdentity)
        }
        loadedPackageIdentity = nil
    }

    private func translateUncached(
        _ text: String,
        from source: Language,
        pack: ValidatedLanguagePack
    ) throws -> String {
        let direction: Int32 = source == .chinese ? 1 : 0
        guard let response = QTNativeTranslatePackage(
            text,
            pack.identity,
            pack.modelURL.path,
            pack.sourceTokenizerURL.path,
            pack.targetTokenizerURL.path,
            direction
        ) else {
            throw TranslationError.modelUnavailable(
                source,
                source == .chinese ? .english : .chinese
            )
        }
        let translation = String(cString: response)
        if translation.hasPrefix("ERROR: ") {
            throw NSError(domain: "QuickTranslate.NativeEngine", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: String(translation.dropFirst(7))])
        }
        return translation
    }
}

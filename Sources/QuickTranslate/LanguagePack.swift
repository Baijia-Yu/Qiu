import Foundation

/// Metadata-only description of a Qiu language pack. It never executes code.
struct LanguagePack: Codable, Identifiable, Sendable, Equatable {
    let formatVersion: Int
    let id: String
    let displayName: String
    let runtime: String
    let sourceLanguage: String
    let targetLanguage: String
    let version: String
    let license: String?
    let source: String?
    let attribution: String?
    let model: ModelResource
    let tokenizer: TokenizerResource

    struct ModelResource: Codable, Sendable, Equatable {
        let path: String
    }

    struct TokenizerResource: Codable, Sendable, Equatable {
        let source: String
        let target: String
    }
}

/// A language pack whose metadata and runtime files have both passed validation.
struct ValidatedLanguagePack: Sendable, Equatable {
    let metadata: LanguagePack
    let rootURL: URL
    let modelURL: URL
    let sourceTokenizerURL: URL
    let targetTokenizerURL: URL

    var identity: String { "\(metadata.id)@\(metadata.version)" }
}

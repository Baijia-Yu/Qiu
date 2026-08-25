import Foundation

enum LanguagePackValidationError: LocalizedError, Equatable {
    case missingManifest
    case unreadableManifest
    case unsupportedFormat(Int)
    case unsafePackageID
    case invalidVersion
    case unsupportedRuntime(String)
    case invalidLanguageCode(String)
    case unsafePath(String)
    case missingRequiredFile(String)

    var errorDescription: String? {
        switch self {
        case .missingManifest, .unreadableManifest:
            "这不是 Qiu 语言包。"
        case .unsupportedFormat:
            "这个语言包与当前版本的 Qiu 不兼容。"
        case .unsafePackageID, .invalidVersion, .invalidLanguageCode, .unsafePath:
            "这个语言包的描述文件无效。"
        case .unsupportedRuntime:
            "这个语言包使用了当前版本不支持的运行方式。"
        case .missingRequiredFile:
            "这个语言包缺少必要文件。"
        }
    }
}

enum LanguagePackValidator {
    static let supportedFormatVersion = 1
    static let supportedRuntime = "ctranslate2-marian-int8"

    static func validate(at rootURL: URL) throws -> ValidatedLanguagePack {
        let rootURL = rootURL.resolvingSymlinksInPath().standardizedFileURL
        let manifestURL = rootURL.appendingPathComponent("qiu-package.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw LanguagePackValidationError.missingManifest
        }

        guard let data = try? Data(contentsOf: manifestURL),
              let pack = try? JSONDecoder().decode(LanguagePack.self, from: data) else {
            throw LanguagePackValidationError.unreadableManifest
        }

        guard pack.formatVersion == supportedFormatVersion else {
            throw LanguagePackValidationError.unsupportedFormat(pack.formatVersion)
        }
        guard isSafePackageID(pack.id) else {
            throw LanguagePackValidationError.unsafePackageID
        }
        guard isSemanticVersion(pack.version) else {
            throw LanguagePackValidationError.invalidVersion
        }
        guard pack.runtime == supportedRuntime else {
            throw LanguagePackValidationError.unsupportedRuntime(pack.runtime)
        }
        guard isLanguageCode(pack.sourceLanguage), isLanguageCode(pack.targetLanguage) else {
            throw LanguagePackValidationError.invalidLanguageCode(
                !isLanguageCode(pack.sourceLanguage) ? pack.sourceLanguage : pack.targetLanguage
            )
        }

        let modelURL = try safeFileURL(pack.model.path, under: rootURL)
        let sourceTokenizerURL = try safeFileURL(pack.tokenizer.source, under: rootURL)
        let targetTokenizerURL = try safeFileURL(pack.tokenizer.target, under: rootURL)

        try requireFile("config.json", in: modelURL)
        try requireFile("model.bin", in: modelURL)
        try requireFile(sourceTokenizerURL.lastPathComponent, at: sourceTokenizerURL)
        try requireFile(targetTokenizerURL.lastPathComponent, at: targetTokenizerURL)

        return ValidatedLanguagePack(
            metadata: pack,
            rootURL: rootURL,
            modelURL: modelURL,
            sourceTokenizerURL: sourceTokenizerURL,
            targetTokenizerURL: targetTokenizerURL
        )
    }

    private static func safeFileURL(_ relativePath: String, under rootURL: URL) throws -> URL {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard !relativePath.isEmpty,
              !relativePath.hasPrefix("/"),
              !components.contains("..") else {
            throw LanguagePackValidationError.unsafePath(relativePath)
        }
        let resolved = rootURL.appendingPathComponent(relativePath).resolvingSymlinksInPath().standardizedFileURL
        let rootPath = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
        guard resolved.path.hasPrefix(rootPath) else {
            throw LanguagePackValidationError.unsafePath(relativePath)
        }
        return resolved
    }

    private static func requireFile(_ name: String, at url: URL) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw LanguagePackValidationError.missingRequiredFile(name)
        }
    }

    private static func requireFile(_ name: String, in directory: URL) throws {
        try requireFile(name, at: directory.appendingPathComponent(name))
    }

    private static func isSafePackageID(_ value: String) -> Bool {
        value.range(of: "^[a-z0-9._-]+$", options: .regularExpression) != nil
    }

    private static func isSemanticVersion(_ value: String) -> Bool {
        value.range(of: "^[0-9]+\\.[0-9]+\\.[0-9]+$", options: .regularExpression) != nil
    }

    private static func isLanguageCode(_ value: String) -> Bool {
        value.range(of: "^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$", options: .regularExpression) != nil
    }
}

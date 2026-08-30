import CryptoKit
import Foundation

struct OfficialModelCatalog: Decodable, Sendable {
    let formatVersion: Int
    let packages: [OfficialModelPackage]
}

struct OfficialModelPackage: Decodable, Identifiable, Sendable, Equatable {
    let packageID: String
    let displayName: String
    let sourceLanguage: String
    let targetLanguage: String
    let version: String
    let sizeBytes: Int64
    let sha256: String
    let downloadURL: URL
    let license: String?

    var id: String { identity }
    var identity: String { "\(packageID)@\(version)" }
}

enum OfficialModelCatalogError: LocalizedError, Equatable {
    case invalidResponse
    case unsupportedFormat(Int)
    case invalidPackage
    case insecureDownloadURL
    case duplicatePackage(String)
    case sizeMismatch
    case checksumMismatch

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "无法读取 Qiu 官方语言包目录。"
        case .unsupportedFormat:
            "语言包目录版本暂不受支持，请更新 Qiu。"
        case .invalidPackage:
            "官方目录中包含无效的语言包信息。"
        case .insecureDownloadURL:
            "语言包下载地址不是安全的 HTTPS 地址。"
        case .duplicatePackage(let identity):
            "官方目录中存在重复语言包：\(identity)"
        case .sizeMismatch:
            "语言包大小与官方目录不一致。"
        case .checksumMismatch:
            "语言包校验失败，文件可能不完整或已被修改。"
        }
    }
}

actor OfficialModelCatalogClient {
    static let defaultCatalogURL = URL(
        string: "https://raw.githubusercontent.com/Baijia-Yu/Qiu/main/Models/catalog-v1.json"
    )!

    private let catalogURL: URL
    private let session: URLSession

    init(catalogURL: URL = defaultCatalogURL, session: URLSession = .shared) {
        self.catalogURL = catalogURL
        self.session = session
    }

    func fetchPackages() async throws -> [OfficialModelPackage] {
        let (data, response) = try await session.data(from: catalogURL)
        try Self.validateHTTPResponse(response)
        return try Self.decodeCatalog(data)
    }

    func download(_ package: OfficialModelPackage) async throws -> URL {
        let (temporaryURL, response) = try await session.download(from: package.downloadURL)
        try Self.validateHTTPResponse(response)

        let attributes = try FileManager.default.attributesOfItem(atPath: temporaryURL.path)
        guard (attributes[.size] as? NSNumber)?.int64Value == package.sizeBytes else {
            throw OfficialModelCatalogError.sizeMismatch
        }
        guard try Self.sha256(of: temporaryURL) == package.sha256.lowercased() else {
            throw OfficialModelCatalogError.checksumMismatch
        }

        let archiveURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Qiu-\(UUID().uuidString).qiu-languagepack")
        try FileManager.default.moveItem(at: temporaryURL, to: archiveURL)
        return archiveURL
    }

    static func decodeCatalog(_ data: Data) throws -> [OfficialModelPackage] {
        let catalog = try JSONDecoder().decode(OfficialModelCatalog.self, from: data)
        guard catalog.formatVersion == 1 else {
            throw OfficialModelCatalogError.unsupportedFormat(catalog.formatVersion)
        }

        var identities = Set<String>()
        for package in catalog.packages {
            guard isSafePackageID(package.packageID),
                  isSemanticVersion(package.version),
                  isLanguageCode(package.sourceLanguage),
                  isLanguageCode(package.targetLanguage),
                  package.sourceLanguage != package.targetLanguage,
                  package.sizeBytes > 0,
                  package.sha256.count == 64,
                  package.sha256.allSatisfy({ $0.isHexDigit }) else {
                throw OfficialModelCatalogError.invalidPackage
            }
            guard package.downloadURL.scheme?.lowercased() == "https" else {
                throw OfficialModelCatalogError.insecureDownloadURL
            }
            guard identities.insert(package.identity).inserted else {
                throw OfficialModelCatalogError.duplicatePackage(package.identity)
            }
        }
        return catalog.packages
    }

    static func sha256(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var digest = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            digest.update(data: chunk)
        }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func validateHTTPResponse(_ response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode),
              response.url?.scheme?.lowercased() == "https" else {
            throw OfficialModelCatalogError.invalidResponse
        }
    }

    private static func isSafePackageID(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]*$"#, options: .regularExpression) != nil
    }

    private static func isSemanticVersion(_ value: String) -> Bool {
        value.range(of: #"^[0-9]+\.[0-9]+\.[0-9]+$"#, options: .regularExpression) != nil
    }

    private static func isLanguageCode(_ value: String) -> Bool {
        value.range(of: #"^[a-z]{2,3}(-[A-Z]{2})?$"#, options: .regularExpression) != nil
    }
}

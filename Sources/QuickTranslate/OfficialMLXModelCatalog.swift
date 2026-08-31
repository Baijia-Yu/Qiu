import Foundation
import HuggingFace

struct OfficialMLXModelCatalog: Decodable, Sendable {
    let formatVersion: Int
    let models: [OfficialMLXModel]
}

struct OfficialMLXModel: Decodable, Identifiable, Sendable, Equatable {
    let id: String
    let displayName: String
    let repositoryID: String
    let revision: String
    let downloadBytes: Int64
    let recommendedMemoryBytes: Int64
    let parameterLabel: String
    let quality: String
    let summary: String
    let license: String
}

enum OfficialMLXCatalogError: LocalizedError, Equatable {
    case invalidResponse
    case unsupportedFormat(Int)
    case invalidModel
    case duplicateModel(String)
    case requiresAppleSilicon
    case alreadyInstalled
    case unsafeInstallLocation

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "无法读取 Qiu MLX 模型目录。"
        case .unsupportedFormat: "MLX 模型目录版本暂不受支持，请更新 Qiu。"
        case .invalidModel: "MLX 模型目录中包含无效信息。"
        case .duplicateModel(let id): "MLX 模型目录中存在重复项目：\(id)"
        case .requiresAppleSilicon: "MLX 模型下载仅支持 Apple Silicon Mac。"
        case .alreadyInstalled: "这个 MLX 模型已经安装。"
        case .unsafeInstallLocation: "无法确认 MLX 模型的安全安装位置。"
        }
    }
}

actor OfficialMLXModelCatalogClient {
    static let defaultCatalogURL = URL(
        string: "https://raw.githubusercontent.com/Baijia-Yu/Qiu/main/Models/mlx-catalog-v1.json"
    )!

    private let catalogURL: URL
    private let session: URLSession

    init(catalogURL: URL = defaultCatalogURL, session: URLSession = .shared) {
        self.catalogURL = catalogURL
        self.session = session
    }

    func fetchModels() async throws -> [OfficialMLXModel] {
        let (data, response) = try await session.data(from: catalogURL)
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode),
              response.url?.scheme?.lowercased() == "https" else {
            throw OfficialMLXCatalogError.invalidResponse
        }
        return try Self.decodeCatalog(data)
    }

    static func decodeCatalog(_ data: Data) throws -> [OfficialMLXModel] {
        let catalog = try JSONDecoder().decode(OfficialMLXModelCatalog.self, from: data)
        guard catalog.formatVersion == 1 else {
            throw OfficialMLXCatalogError.unsupportedFormat(catalog.formatVersion)
        }
        var identities = Set<String>()
        for model in catalog.models {
            guard model.id.range(
                of: #"^[A-Za-z0-9][A-Za-z0-9._-]*$"#,
                options: .regularExpression
            ) != nil,
            model.repositoryID.range(
                of: #"^[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._-]*$"#,
                options: .regularExpression
            ) != nil,
            model.revision.count == 40,
            model.revision.allSatisfy(\.isHexDigit),
            model.downloadBytes > 0,
            model.recommendedMemoryBytes > model.downloadBytes,
            !model.displayName.isEmpty,
            !model.parameterLabel.isEmpty,
            !model.quality.isEmpty,
            !model.summary.isEmpty,
            !model.license.isEmpty else {
                throw OfficialMLXCatalogError.invalidModel
            }
            guard identities.insert(model.id).inserted else {
                throw OfficialMLXCatalogError.duplicateModel(model.id)
            }
        }
        return catalog.models
    }
}

actor OfficialMLXModelInstaller {
    static let downloadPatterns = [
        "*.json", "*.safetensors", "*.txt", "*.model", "*.jinja"
    ]

    private let installRoot: URL
    private let client: HubClient
    private let temporaryCacheRoot: URL?

    init(installRoot: URL? = nil, client: HubClient? = nil) {
        let resolvedInstallRoot = installRoot ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("Qiu/MLXModels", isDirectory: true)
        self.installRoot = resolvedInstallRoot
        if let client {
            self.client = client
            self.temporaryCacheRoot = nil
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.waitsForConnectivity = true
            configuration.timeoutIntervalForRequest = 120
            configuration.timeoutIntervalForResource = 3_600
            let cacheRoot = resolvedInstallRoot.appendingPathComponent(
                ".hub-cache-\(UUID().uuidString)",
                isDirectory: true
            )
            self.client = HubClient(
                session: URLSession(configuration: configuration),
                userAgent: "Qiu/MLXModelInstaller",
                cache: HubCache(cacheDirectory: cacheRoot)
            )
            self.temporaryCacheRoot = cacheRoot
        }
    }

    func install(
        _ item: OfficialMLXModel,
        progressHandler: @MainActor @Sendable @escaping (Double) -> Void
    ) async throws -> MLXModelReference {
#if !arch(arm64)
        throw OfficialMLXCatalogError.requiresAppleSilicon
#else
        guard let repository = HuggingFace.Repo.ID(rawValue: item.repositoryID) else {
            throw OfficialMLXCatalogError.invalidModel
        }
        try FileManager.default.createDirectory(at: installRoot, withIntermediateDirectories: true)
        let destination = installRoot.appendingPathComponent(item.id, isDirectory: true)
        guard destination.deletingLastPathComponent().standardizedFileURL == installRoot.standardizedFileURL else {
            throw OfficialMLXCatalogError.unsafeInstallLocation
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            throw OfficialMLXCatalogError.alreadyInstalled
        }

        let staging = installRoot.appendingPathComponent(".download-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: staging)
            if let temporaryCacheRoot {
                try? FileManager.default.removeItem(at: temporaryCacheRoot)
            }
        }
        var lastDownloadError: Error?
        for attempt in 0..<3 {
            do {
                _ = try await client.downloadSnapshot(
                    of: repository,
                    to: staging,
                    revision: item.revision,
                    matching: Self.downloadPatterns,
                    maxConcurrentDownloads: 3
                ) { progress in
                    let fraction = progress.totalUnitCount > 0
                        ? Double(progress.completedUnitCount) / Double(progress.totalUnitCount)
                        : 0
                    progressHandler(min(max(fraction, 0), 1))
                }
                lastDownloadError = nil
                break
            } catch {
                if Task.isCancelled { throw CancellationError() }
                lastDownloadError = error
                guard attempt < 2 else { break }
                try await Task.sleep(for: .seconds(attempt + 1))
            }
        }
        if let lastDownloadError { throw lastDownloadError }
        _ = try MLXModelReferenceStore.validateAndCreate(at: staging)
        try FileManager.default.moveItem(at: staging, to: destination)
        await progressHandler(1)
        return try MLXModelReferenceStore.validateAndCreate(at: destination)
            .withCatalogMetadata(item)
#endif
    }

    func removeManagedFiles(for model: MLXModelReference) throws {
        guard model.isManagedDownload else { return }
        let target = URL(fileURLWithPath: model.lastKnownPath, isDirectory: true).standardizedFileURL
        let root = installRoot.standardizedFileURL
        guard target.deletingLastPathComponent() == root,
              FileManager.default.fileExists(atPath: target.path) else {
            throw OfficialMLXCatalogError.unsafeInstallLocation
        }
        try FileManager.default.removeItem(at: target)
    }
}

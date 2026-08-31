import Foundation

struct MLXModelReference: Codable, Identifiable, Sendable, Equatable {
    let id: String
    var displayName: String
    let bookmarkData: Data?
    let lastKnownPath: String
    let modelType: String
    let weightsBytes: Int64
    let contextLength: Int?
    let addedAt: Date
    var managedCatalogIdentity: String? = nil
    var sourceRepository: String? = nil
    var license: String? = nil

    var estimatedMemoryBytes: Int64 {
        // Weights plus a conservative allowance for runtime cache and activations.
        weightsBytes + max(512 * 1_024 * 1_024, weightsBytes / 3)
    }

    var isManagedDownload: Bool { managedCatalogIdentity != nil }

    func withCatalogMetadata(_ item: OfficialMLXModel) -> MLXModelReference {
        var copy = self
        copy.managedCatalogIdentity = item.id
        copy.sourceRepository = item.repositoryID
        copy.license = item.license
        return copy
    }
}

enum MLXModelValidationError: LocalizedError, Equatable {
    case requiresAppleSilicon
    case notDirectory
    case missingConfig
    case unreadableConfig
    case missingTokenizer
    case missingWeights
    case cannotSaveAccess
    case modelUnavailable

    var errorDescription: String? {
        switch self {
        case .requiresAppleSilicon: "MLX 本地大模型仅支持 Apple Silicon Mac。"
        case .notDirectory: "请选择一个 MLX 模型目录。"
        case .missingConfig: "模型目录缺少 config.json。"
        case .unreadableConfig: "无法读取 config.json。"
        case .missingTokenizer: "模型目录缺少 tokenizer.json 或 tokenizer_config.json。"
        case .missingWeights: "模型目录中没有找到 .safetensors 权重。"
        case .cannotSaveAccess: "无法保存模型目录访问权限。"
        case .modelUnavailable: "模型目录已移动或 Qiu 无权访问，请重新添加。"
        }
    }
}

enum MLXModelReferenceStore {
    static let modelsDefaultsKey = "mlxModelReferences"
    static let selectionsDefaultsKey = "preferredMLXModelIdentities"

    static func validateAndCreate(at directory: URL) throws -> MLXModelReference {
#if !arch(arm64)
        throw MLXModelValidationError.requiresAppleSilicon
#else
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw MLXModelValidationError.notDirectory
        }

        let configURL = directory.appendingPathComponent("config.json")
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            throw MLXModelValidationError.missingConfig
        }
        guard let configData = try? Data(contentsOf: configURL),
              let config = try? JSONSerialization.jsonObject(with: configData) as? [String: Any] else {
            throw MLXModelValidationError.unreadableConfig
        }

        let hasTokenizer = ["tokenizer.json", "tokenizer_config.json"].contains {
            FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path)
        }
        guard hasTokenizer else { throw MLXModelValidationError.missingTokenizer }

        let contents = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        let weights = contents.filter { $0.pathExtension.lowercased() == "safetensors" }
        guard !weights.isEmpty else { throw MLXModelValidationError.missingWeights }
        let weightsBytes = try weights.reduce(Int64(0)) { total, url in
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            return total + Int64(values.fileSize ?? 0)
        }

        let bookmark = try? directory.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        let modelType = (config["model_type"] as? String) ?? "unknown"
        let contextLength = (config["max_position_embeddings"] as? NSNumber)?.intValue
        return MLXModelReference(
            id: UUID().uuidString,
            displayName: directory.lastPathComponent,
            bookmarkData: bookmark,
            lastKnownPath: directory.path,
            modelType: modelType,
            weightsBytes: weightsBytes,
            contextLength: contextLength,
            addedAt: Date()
        )
#endif
    }

    static func resolve(_ model: MLXModelReference) throws -> URL {
        if let bookmarkData = model.bookmarkData {
            var stale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ), !stale, FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        let fallback = URL(fileURLWithPath: model.lastKnownPath, isDirectory: true)
        guard FileManager.default.fileExists(atPath: fallback.path) else {
            throw MLXModelValidationError.modelUnavailable
        }
        return fallback
    }

    static func loadModels(from defaults: UserDefaults = .standard) -> [MLXModelReference] {
        guard let data = defaults.data(forKey: modelsDefaultsKey) else { return [] }
        return (try? JSONDecoder().decode([MLXModelReference].self, from: data)) ?? []
    }

    static func saveModels(_ models: [MLXModelReference], to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(models) {
            defaults.set(data, forKey: modelsDefaultsKey)
        }
    }

    static func loadSelections(from defaults: UserDefaults = .standard) -> [String: String] {
        defaults.dictionary(forKey: selectionsDefaultsKey) as? [String: String] ?? [:]
    }

    static func saveSelections(_ selections: [String: String], to defaults: UserDefaults = .standard) {
        defaults.set(selections, forKey: selectionsDefaultsKey)
    }
}

import Foundation

enum LanguagePackInstallError: LocalizedError, Equatable {
    case unsupportedInput
    case archiveExtractionFailed
    case packageAlreadyInstalled
    case unexpectedPackageIdentity(expected: String, actual: String)
    case cannotRemoveBuiltInPackage
    case unsafeRemovalTarget

    var errorDescription: String? {
        switch self {
        case .unsupportedInput:
            "这不是 Qiu 语言包。"
        case .archiveExtractionFailed:
            "无法打开这个 Qiu 语言包。"
        case .packageAlreadyInstalled:
            "这个版本的语言包已经安装。"
        case .unexpectedPackageIdentity(let expected, let actual):
            "下载的语言包与官方目录不一致（应为 \(expected)，实际为 \(actual)）。"
        case .cannotRemoveBuiltInPackage:
            "内置语言包不能移除。"
        case .unsafeRemovalTarget:
            "无法移除这个语言包。"
        }
    }
}

/// Imports package data into Application Support without modifying Qiu.app.
actor LanguagePackInstaller {
    private let installRoot: URL
    private let store: LanguagePackStore

    init(installRoot: URL? = nil, store: LanguagePackStore) {
        self.installRoot = installRoot ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
            .appendingPathComponent("Qiu/LanguagePacks", isDirectory: true)
        self.store = store
    }

    func install(
        from sourceURL: URL,
        expectedIdentity: String? = nil
    ) async throws -> InstalledLanguagePack {
        let fileManager = FileManager.default
        let stagingRoot = installRoot
            .appendingPathComponent(".staging", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: stagingRoot) }

        let candidate = try prepareCandidate(from: sourceURL, in: stagingRoot)
        let validated = try LanguagePackValidator.validate(at: candidate)
        if let expectedIdentity, validated.identity != expectedIdentity {
            throw LanguagePackInstallError.unexpectedPackageIdentity(
                expected: expectedIdentity,
                actual: validated.identity
            )
        }
        let destination = installRoot
            .appendingPathComponent(validated.metadata.id, isDirectory: true)
            .appendingPathComponent(validated.metadata.version, isDirectory: true)

        guard !fileManager.fileExists(atPath: destination.path) else {
            throw LanguagePackInstallError.packageAlreadyInstalled
        }
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.moveItem(at: candidate, to: destination)
        let installed = try LanguagePackValidator.validate(at: destination)
        _ = await store.reload()
        return InstalledLanguagePack(package: installed, origin: .userInstalled)
    }

    func remove(_ package: InstalledLanguagePack) async throws {
        guard package.origin == .userInstalled else {
            throw LanguagePackInstallError.cannotRemoveBuiltInPackage
        }
        let root = installRoot.resolvingSymlinksInPath().standardizedFileURL
        let target = package.package.rootURL.resolvingSymlinksInPath().standardizedFileURL
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard target.path.hasPrefix(rootPath) else {
            throw LanguagePackInstallError.unsafeRemovalTarget
        }
        try FileManager.default.removeItem(at: target)
        _ = await store.reload()
    }

    private func prepareCandidate(from sourceURL: URL, in stagingRoot: URL) throws -> URL {
        let fileManager = FileManager.default
        if sourceURL.pathExtension.lowercased() == "qiu-languagepack" {
            let extractionRoot = stagingRoot.appendingPathComponent("extracted", isDirectory: true)
            try fileManager.createDirectory(at: extractionRoot, withIntermediateDirectories: true)
            try extractArchive(sourceURL, to: extractionRoot)
            return try packageRoot(in: extractionRoot)
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw LanguagePackInstallError.unsupportedInput
        }
        let candidate = stagingRoot.appendingPathComponent("package", isDirectory: true)
        try fileManager.copyItem(at: sourceURL, to: candidate)
        return candidate
    }

    private func packageRoot(in extractionRoot: URL) throws -> URL {
        let manifest = extractionRoot.appendingPathComponent("qiu-package.json")
        if FileManager.default.fileExists(atPath: manifest.path) { return extractionRoot }

        let children = try FileManager.default.contentsOfDirectory(
            at: extractionRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        guard children.count == 1 else { throw LanguagePackInstallError.unsupportedInput }
        let candidate = children[0]
        guard FileManager.default.fileExists(atPath: candidate.appendingPathComponent("qiu-package.json").path) else {
            throw LanguagePackInstallError.unsupportedInput
        }
        return candidate
    }

    private func extractArchive(_ archiveURL: URL, to destinationURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archiveURL.path, destinationURL.path]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw LanguagePackInstallError.archiveExtractionFailed
        }
        guard process.terminationStatus == 0 else {
            throw LanguagePackInstallError.archiveExtractionFailed
        }
    }
}

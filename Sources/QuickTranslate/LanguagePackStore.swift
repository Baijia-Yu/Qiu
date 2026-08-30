import Foundation

enum LanguagePackOrigin: Sendable, Equatable {
    case builtIn
    case userInstalled
}

struct InstalledLanguagePack: Sendable, Equatable, Identifiable {
    let package: ValidatedLanguagePack
    let origin: LanguagePackOrigin

    var id: String { package.identity }
}

/// The only discovery owner for Qiu language packs. It reads fixed roots only.
actor LanguagePackStore {
    private let builtInRoot: URL
    private let userInstalledRoot: URL
    private var installed: [InstalledLanguagePack] = []
    private var hasLoaded = false

    init(
        builtInRoot: URL? = nil,
        userInstalledRoot: URL? = nil
    ) {
        let fileManager = FileManager.default
        self.builtInRoot = builtInRoot ?? Self.defaultBuiltInRoot(fileManager: fileManager)
        self.userInstalledRoot = userInstalledRoot ?? fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
            .appendingPathComponent("Qiu/LanguagePacks", isDirectory: true)
    }

    private static func defaultBuiltInRoot(fileManager: FileManager) -> URL {
        let configuredRoot = ProcessInfo.processInfo.environment["QUICK_TRANSLATE_MODEL_ROOT"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
        let bundleRoot = Bundle.main.resourceURL?
            .appendingPathComponent("LanguagePacks", isDirectory: true)
        let developmentRoot = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent("Models/LanguagePacks", isDirectory: true)
        return [configuredRoot, bundleRoot, developmentRoot]
            .compactMap { $0 }
            .first { fileManager.fileExists(atPath: $0.path) }
            ?? URL(fileURLWithPath: "/nonexistent")
    }

    @discardableResult
    func reload() -> [InstalledLanguagePack] {
        let discovered = discover(in: builtInRoot, origin: .builtIn)
            + discover(in: userInstalledRoot, origin: .userInstalled)
        installed = deduplicating(discovered)
        hasLoaded = true
        return installed
    }

    func allPackages() -> [InstalledLanguagePack] { installed }

    func resolve(
        sourceLanguage: String,
        targetLanguage: String,
        preferredIdentity: String? = nil
    ) -> ValidatedLanguagePack? {
        if !hasLoaded { _ = reload() }
        let candidates = installed.filter {
            $0.package.metadata.sourceLanguage == sourceLanguage
                && $0.package.metadata.targetLanguage == targetLanguage
        }
        if let preferredIdentity,
           let preferred = candidates.first(where: { $0.id == preferredIdentity }) {
            return preferred.package
        }
        return candidates.max {
            compareVersions($0.package.metadata.version, $1.package.metadata.version) == .orderedAscending
        }?.package
    }

    private func discover(in root: URL, origin: LanguagePackOrigin) -> [InstalledLanguagePack] {
        guard let packageDirectories = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var packs: [InstalledLanguagePack] = []
        for packageDirectory in packageDirectories {
            guard let versionDirectories = try? FileManager.default.contentsOfDirectory(
                at: packageDirectory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }
            for versionDirectory in versionDirectories {
                guard let validated = try? LanguagePackValidator.validate(at: versionDirectory) else { continue }
                packs.append(InstalledLanguagePack(package: validated, origin: origin))
            }
        }
        return packs
    }

    private func deduplicating(_ packages: [InstalledLanguagePack]) -> [InstalledLanguagePack] {
        packages.sorted { left, right in
            if left.package.metadata.id != right.package.metadata.id {
                return left.package.metadata.id < right.package.metadata.id
            }
            let versions = compareVersions(left.package.metadata.version, right.package.metadata.version)
            if versions != .orderedSame { return versions == .orderedDescending }
            return left.origin == .builtIn
        }.reduce(into: [String: InstalledLanguagePack]()) { result, item in
            result[item.id] = result[item.id] ?? item
        }.values.sorted { $0.package.metadata.displayName < $1.package.metadata.displayName }
    }

    private func compareVersions(_ left: String, _ right: String) -> ComparisonResult {
        let leftParts = left.split(separator: ".").compactMap { Int($0) }
        let rightParts = right.split(separator: ".").compactMap { Int($0) }
        for index in 0..<max(leftParts.count, rightParts.count) {
            let leftValue = index < leftParts.count ? leftParts[index] : 0
            let rightValue = index < rightParts.count ? rightParts[index] : 0
            if leftValue < rightValue { return .orderedAscending }
            if leftValue > rightValue { return .orderedDescending }
        }
        return .orderedSame
    }
}

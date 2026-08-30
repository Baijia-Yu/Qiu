import Testing
import AppKit
@testable import QuickTranslate

@Test func validatesACompleteLanguagePack() throws {
    let root = try makeLanguagePack()
    defer { try? FileManager.default.removeItem(at: root) }

    let pack = try LanguagePackValidator.validate(at: root)
    #expect(pack.identity == "opus-mt-ja-zh-int8@1.0.0")
    #expect(pack.modelURL.path.hasSuffix("ct2/model"))
    #expect(pack.sourceTokenizerURL.lastPathComponent == "source.spm")
}

@Test func rejectsPathsOutsideTheLanguagePack() throws {
    let root = try makeLanguagePack(modelPath: "../../private")
    defer { try? FileManager.default.removeItem(at: root) }

    #expect(throws: LanguagePackValidationError.unsafePath("../../private")) {
        try LanguagePackValidator.validate(at: root)
    }
}

@Test func rejectsUnsupportedLanguagePackRuntime() throws {
    let root = try makeLanguagePack(runtime: "llama.cpp")
    defer { try? FileManager.default.removeItem(at: root) }

    #expect(throws: LanguagePackValidationError.unsupportedRuntime("llama.cpp")) {
        try LanguagePackValidator.validate(at: root)
    }
}

@Test func rejectsUnsupportedLanguagePackFormatAndUnsafeID() throws {
    let unsupportedFormat = try makeLanguagePack(formatVersion: 2)
    defer { try? FileManager.default.removeItem(at: unsupportedFormat) }
    #expect(throws: LanguagePackValidationError.unsupportedFormat(2)) {
        try LanguagePackValidator.validate(at: unsupportedFormat)
    }

    let unsafeID = try makeLanguagePack(id: "../../not-a-package")
    defer { try? FileManager.default.removeItem(at: unsafeID) }
    #expect(throws: LanguagePackValidationError.unsafePackageID) {
        try LanguagePackValidator.validate(at: unsafeID)
    }
}

@Test func rejectsLanguagePackMissingRequiredModelFiles() throws {
    let root = try makeLanguagePack()
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.removeItem(at: root.appendingPathComponent("ct2/model/model.bin"))

    #expect(throws: LanguagePackValidationError.missingRequiredFile("model.bin")) {
        try LanguagePackValidator.validate(at: root)
    }
}

@Test func discoversOnlyValidPackagesFromFixedRoots() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("QiuLanguagePackStoreTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let builtIn = root.appendingPathComponent("BuiltIn", isDirectory: true)
    let user = root.appendingPathComponent("User", isDirectory: true)
    try makePackInCollection(root: builtIn, id: "opus-mt-en-zh-int8", version: "1.0.0")
    try makePackInCollection(root: user, id: "opus-mt-en-zh-int8", version: "1.1.0")
    try FileManager.default.createDirectory(at: user.appendingPathComponent("not-a-pack/1.0.0"), withIntermediateDirectories: true)

    let store = LanguagePackStore(builtInRoot: builtIn, userInstalledRoot: user)
    let packages = await store.reload()
    #expect(packages.count == 2)
    #expect(packages.contains { $0.id == "opus-mt-en-zh-int8@1.1.0" && $0.origin == .userInstalled })
    let resolved = await store.resolve(sourceLanguage: "ja", targetLanguage: "zh")
    #expect(resolved?.identity == "opus-mt-en-zh-int8@1.1.0")

    let preferred = await store.resolve(
        sourceLanguage: "ja",
        targetLanguage: "zh",
        preferredIdentity: "opus-mt-en-zh-int8@1.0.0"
    )
    #expect(preferred?.identity == "opus-mt-en-zh-int8@1.0.0")

    let missingPreferenceFallback = await store.resolve(
        sourceLanguage: "ja",
        targetLanguage: "zh",
        preferredIdentity: "missing@9.9.9"
    )
    #expect(missingPreferenceFallback?.identity == "opus-mt-en-zh-int8@1.1.0")
}

@Test func persistsPreferredLanguagePacksByDirection() throws {
    let suiteName = "QiuLanguagePackPreferencesTests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let selections = ["en->zh": "opus-mt-en-zh-int8@1.0.0"]

    LanguagePackPreferences.save(selections, to: defaults)

    #expect(LanguagePackPreferences.load(from: defaults) == selections)
}

@Test func importsAndRemovesAValidatedLanguagePackAtomically() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("QiuLanguagePackImportTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = try makeLanguagePack()
    defer { try? FileManager.default.removeItem(at: source) }
    let installRoot = root.appendingPathComponent("LanguagePacks", isDirectory: true)
    let store = LanguagePackStore(
        builtInRoot: root.appendingPathComponent("BuiltIn", isDirectory: true),
        userInstalledRoot: installRoot
    )
    let installer = LanguagePackInstaller(installRoot: installRoot, store: store)

    let installed = try await installer.install(from: source)
    #expect(installed.origin == .userInstalled)
    #expect(FileManager.default.fileExists(atPath: installRoot.appendingPathComponent("opus-mt-ja-zh-int8/1.0.0/qiu-package.json").path))
    #expect((await store.allPackages()).count == 1)

    try await installer.remove(installed)
    #expect(!FileManager.default.fileExists(atPath: installRoot.appendingPathComponent("opus-mt-ja-zh-int8/1.0.0").path))
    #expect((await store.allPackages()).isEmpty)
}

@Test func importsAQiuLanguagePackArchive() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("QiuLanguagePackArchiveTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = try makeLanguagePack()
    defer { try? FileManager.default.removeItem(at: source) }
    let archive = root.appendingPathComponent("japanese.qiu-languagepack")
    try runDitto(arguments: ["-c", "-k", source.path, archive.path])

    let installRoot = root.appendingPathComponent("LanguagePacks", isDirectory: true)
    let store = LanguagePackStore(builtInRoot: root, userInstalledRoot: installRoot)
    let installer = LanguagePackInstaller(installRoot: installRoot, store: store)
    let installed = try await installer.install(from: archive)

    #expect(installed.id == "opus-mt-ja-zh-int8@1.0.0")
}

private func makeLanguagePack(
    modelPath: String = "ct2/model",
    runtime: String = "ctranslate2-marian-int8",
    formatVersion: Int = 1,
    id: String = "opus-mt-ja-zh-int8"
) throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("QiuLanguagePackTests-\(UUID().uuidString)", isDirectory: true)
    let model = root.appendingPathComponent("ct2/model", isDirectory: true)
    let sentencePiece = root.appendingPathComponent("sentencepiece", isDirectory: true)
    try FileManager.default.createDirectory(at: model, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: sentencePiece, withIntermediateDirectories: true)
    try Data().write(to: model.appendingPathComponent("config.json"))
    try Data().write(to: model.appendingPathComponent("model.bin"))
    try Data().write(to: sentencePiece.appendingPathComponent("source.spm"))
    try Data().write(to: sentencePiece.appendingPathComponent("target.spm"))

    let manifest = """
    {
      "formatVersion": \(formatVersion),
      "id": "\(id)",
      "displayName": "日语 → 中文",
      "runtime": "\(runtime)",
      "sourceLanguage": "ja",
      "targetLanguage": "zh",
      "version": "1.0.0",
      "model": { "path": "\(modelPath)" },
      "tokenizer": {
        "source": "sentencepiece/source.spm",
        "target": "sentencepiece/target.spm"
      }
    }
    """
    try Data(manifest.utf8).write(to: root.appendingPathComponent("qiu-package.json"))
    return root
}

private func makePackInCollection(root: URL, id: String, version: String) throws {
    let source = try makeLanguagePack(formatVersion: 1, id: id)
    defer { try? FileManager.default.removeItem(at: source) }
    let destination = root.appendingPathComponent("\(id)/\(version)", isDirectory: true)
    try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.copyItem(at: source, to: destination)

    let manifestURL = destination.appendingPathComponent("qiu-package.json")
    let contents = try String(contentsOf: manifestURL, encoding: .utf8)
    try contents.replacingOccurrences(of: "\"version\": \"1.0.0\"", with: "\"version\": \"\(version)\"")
        .write(to: manifestURL, atomically: true, encoding: .utf8)
}

private func runDitto(arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    process.arguments = arguments
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw NSError(domain: "QiuLanguagePackTests", code: Int(process.terminationStatus))
    }
}

@Test func triggerShortcutMatchesOnlyItsConfiguredModifiers() {
    let shortcut = TriggerShortcut.modifiers([.command, .shift])!
    #expect(shortcut.matchesModifiers([.command, .shift]))
    #expect(!shortcut.matchesModifiers([.command]))
    #expect(!shortcut.matchesModifiers([.command, .shift, .option]))
    #expect(shortcut.displayName == "⇧ Shift + ⌘ Command")
}

@Test func triggerShortcutRoundTripsThroughPersistence() throws {
    let shortcut = TriggerShortcut.mouseButton(number: 3)
    let data = try JSONEncoder().encode(shortcut)
    #expect(try JSONDecoder().decode(TriggerShortcut.self, from: data) == shortcut)
    #expect(shortcut.displayName == "鼠标按键 4")
}

@Test func identifiesChineseToEnglish() {
    let direction = LanguageDetector.direction(for: "强化学习")
    #expect(direction.source == .chinese)
    #expect(direction.target == .english)
}

@Test func translatesWithNativeOpusBridge() async throws {
    let engine = LocalTranslationEngine()
    let translation = try await engine.translate("reinforcement", from: .english, to: .chinese)
    #expect(translation == "增强")
    await engine.unload()
    let reverse = try await engine.translate("这听起来是个好主意。", from: .chinese, to: .english)
    #expect(reverse == "That sounds like a good idea.")
}

@Test func translatesOneHundredWarmRequestsWithoutFailure() async throws {
    let engine = LocalTranslationEngine()
    for index in 0..<100 {
        let result = try await engine.translate("This is translation request number \(index).", from: .english, to: .chinese)
        #expect(!result.isEmpty)
    }
    await engine.unload()
}

@Test func translatesScientificEnglishWithoutUnknownOutput() async throws {
    let engine = LocalTranslationEngine()
    let translation = try await engine.translate(
        "environment dynamics with μ(t) ∈ I indicating the current state.",
        from: .english,
        to: .chinese
    )
    #expect(!translation.contains("⁇"), "Unexpected output: \(translation)")
    #expect(translation.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }, "Unexpected output: \(translation)")
    await engine.unload()
}

@Test func fallsBackForUncommonScientificUnicode() async throws {
    let engine = LocalTranslationEngine()
    let translation = try await engine.translate(
        "The field 𝜇 satisfies x² ≤ 1.",
        from: .english,
        to: .chinese
    )
    #expect(!translation.contains("⁇"), "Unexpected output: \(translation)")
    #expect(translation.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }, "Unexpected output: \(translation)")
    await engine.unload()
}

@Test func preservesSpecialCharactersInScientificTranslation() async throws {
    let engine = LocalTranslationEngine()
    let translation = try await engine.translate(
        "For μ(t) ∈ I, x² ≤ 1 and ΔE ≈ 0. 😀",
        from: .english,
        to: .chinese
    )
    for symbol in ["μ", "∈", "²", "≤", "Δ", "≈", "😀"] {
        #expect(translation.contains(symbol), "Missing \(symbol) in: \(translation)")
    }
    #expect(!translation.contains("⁇"), "Unexpected output: \(translation)")

    let reverse = try await engine.translate(
        "当 μ(t) ∈ I 时，保持 x² ≤ 1。😀",
        from: .chinese,
        to: .english
    )
    for symbol in ["μ", "∈", "²", "≤", "😀"] {
        #expect(reverse.contains(symbol), "Missing \(symbol) in: \(reverse)")
    }
    #expect(!reverse.contains("⁇"), "Unexpected output: \(reverse)")
    await engine.unload()
}

@Test func doesNotLeakPlaceholdersForAcademicNotation() async throws {
    let engine = LocalTranslationEngine()
    let translation = try await engine.translate(
        "We formalize an LLM-based agentic system as 𝓜 = ⟨𝓘, S, A, Ψ, Ω⟩, where 𝓘 indexes the {1, ⋯, N} agents.",
        from: .english,
        to: .chinese
    )
    for symbol in ["𝓜", "⟨", "𝓘", "Ψ", "Ω", "⟩", "⋯"] {
        #expect(translation.contains(symbol), "Missing \(symbol) in: \(translation)")
    }
    #expect(!translation.localizedCaseInsensitiveContains("ZXQ"), "Leaked placeholder: \(translation)")
    #expect(!translation.contains("9078"), "Leaked placeholder: \(translation)")
    #expect(!translation.contains("⁇"), "Unexpected output: \(translation)")
    await engine.unload()
}

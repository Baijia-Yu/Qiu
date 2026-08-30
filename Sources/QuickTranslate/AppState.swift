import AppKit
import SwiftUI

enum AppReadiness: Equatable {
    case ready
    case paused
    case needsAuthorization

    var title: String {
        switch self {
        case .ready: "已就绪"
        case .paused: "已暂停"
        case .needsAuthorization: "需要授权"
        }
    }

    var systemImage: String {
        switch self {
        case .ready: "checkmark.circle.fill"
        case .paused: "pause.circle.fill"
        case .needsAuthorization: "exclamationmark.circle.fill"
        }
    }

    var color: NSColor {
        switch self {
        case .ready: .systemGreen
        case .paused: .secondaryLabelColor
        case .needsAuthorization: .systemOrange
        }
    }
}

@MainActor
final class AppState: NSObject, ObservableObject {
    private static let shortcutDefaultsKey = "triggerShortcut"
    private static let legacyShortcutDefaultsKey = "triggerShortcutModifiers"

    @Published var isEnabled = true {
        didSet { isEnabled ? eventMonitor.start() : eventMonitor.stop() }
    }
    @Published var triggerShortcut: TriggerShortcut {
        didSet {
            if let data = try? JSONEncoder().encode(triggerShortcut) {
                UserDefaults.standard.set(data, forKey: Self.shortcutDefaultsKey)
            }
            eventMonitor.update(shortcut: triggerShortcut)
        }
    }
    @Published private(set) var accessibilityTrusted = false
    @Published private(set) var inputMonitoringTrusted = false
    @Published private(set) var installedLanguagePacks: [InstalledLanguagePack] = []
    @Published private(set) var selectedPackageIdentities: [String: String] = [:]

    private let popup = TranslationPanelController()
    private var permissionRefreshTask: Task<Void, Never>?
    private lazy var eventMonitor = SelectionEventMonitor(shortcut: triggerShortcut) { [weak self] mouseUpTime in
        Task { @MainActor in self?.translateCurrentSelection(mouseUpTime: mouseUpTime) }
    }
    private let packStore: LanguagePackStore
    private let translator: LocalTranslationEngine

    override init() {
        let packStore = LanguagePackStore()
        let selectedPackages = LanguagePackPreferences.load()
        self.packStore = packStore
        self.translator = LocalTranslationEngine(
            packStore: packStore,
            preferredPackageIdentities: selectedPackages
        )
        selectedPackageIdentities = selectedPackages
        if let data = UserDefaults.standard.data(forKey: Self.shortcutDefaultsKey),
           let stored = try? JSONDecoder().decode(TriggerShortcut.self, from: data) {
            triggerShortcut = stored
        } else if UserDefaults.standard.object(forKey: Self.legacyShortcutDefaultsKey) != nil,
                  let stored = TriggerShortcut.modifiers(
                    NSEvent.ModifierFlags(
                        rawValue: UInt(UserDefaults.standard.integer(forKey: Self.legacyShortcutDefaultsKey))
                    )
                  ) {
            triggerShortcut = stored
        } else {
            triggerShortcut = .defaultValue
        }
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        configureBundledModelPath()
        refreshPermissionStatus()
        eventMonitor.start()
        reloadLanguagePacks()
    }

    var readiness: AppReadiness {
        if !isEnabled { return .paused }
        return accessibilityTrusted && inputMonitoringTrusted ? .ready : .needsAuthorization
    }

    private func configureBundledModelPath() {
        guard let resources = Bundle.main.resourceURL else { return }
        let packRoot = resources.appendingPathComponent("LanguagePacks")
        guard FileManager.default.fileExists(atPath: packRoot.path) else { return }
        setenv("QUICK_TRANSLATE_MODEL_ROOT", packRoot.path, 1)
    }

    func refreshPermissionStatus() {
        let newAccessibilityTrusted = AXIsProcessTrusted()
        let newInputMonitoringTrusted = CGPreflightListenEventAccess()
        let permissionsChanged = newAccessibilityTrusted != accessibilityTrusted
            || newInputMonitoringTrusted != inputMonitoringTrusted

        accessibilityTrusted = newAccessibilityTrusted
        inputMonitoringTrusted = newInputMonitoringTrusted

        if permissionsChanged, isEnabled {
            eventMonitor.restartIfRunning()
        }
    }

    func requestRequiredPermissions() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        _ = CGRequestListenEventAccess()
        refreshPermissionStatus()
        watchPermissionChangesDuringAuthorization()
    }

    func languagePacks(from source: Language, to target: Language) -> [InstalledLanguagePack] {
        installedLanguagePacks.filter {
            $0.package.metadata.sourceLanguage == source.rawValue
                && $0.package.metadata.targetLanguage == target.rawValue
        }.sorted {
            if $0.package.metadata.displayName != $1.package.metadata.displayName {
                return $0.package.metadata.displayName < $1.package.metadata.displayName
            }
            return $0.package.metadata.version > $1.package.metadata.version
        }
    }

    func selectedPackageIdentity(from source: Language, to target: Language) -> String {
        selectedPackageIdentities[
            LanguagePackPreferences.pairKey(
                sourceLanguage: source.rawValue,
                targetLanguage: target.rawValue
            )
        ] ?? ""
    }

    func selectLanguagePack(_ identity: String, from source: Language, to target: Language) {
        if !identity.isEmpty {
            guard languagePacks(from: source, to: target).contains(where: { $0.id == identity }) else {
                return
            }
        }

        let key = LanguagePackPreferences.pairKey(
            sourceLanguage: source.rawValue,
            targetLanguage: target.rawValue
        )
        if identity.isEmpty {
            selectedPackageIdentities.removeValue(forKey: key)
        } else {
            selectedPackageIdentities[key] = identity
        }
        LanguagePackPreferences.save(selectedPackageIdentities)
        let selections = selectedPackageIdentities
        Task { await translator.updatePreferredPackages(selections) }
    }

    func reloadLanguagePacks() {
        Task { [weak self] in
            guard let self else { return }
            let packages = await packStore.reload()
            installedLanguagePacks = packages

            let available = Set(packages.map(\.id))
            let validSelections = selectedPackageIdentities.filter { available.contains($0.value) }
            guard validSelections != selectedPackageIdentities else { return }
            selectedPackageIdentities = validSelections
            LanguagePackPreferences.save(validSelections)
            await translator.updatePreferredPackages(validSelections)
        }
    }

    @objc private func applicationDidBecomeActive() {
        refreshPermissionStatus()
    }

    private func watchPermissionChangesDuringAuthorization() {
        permissionRefreshTask?.cancel()
        permissionRefreshTask = Task { @MainActor [weak self] in
            // TCC changes do not emit an app notification while System Settings is
            // frontmost. Poll only during this explicit authorization flow.
            for _ in 0..<120 {
                guard !Task.isCancelled else { return }
                try? await Task.sleep(for: .milliseconds(500))
                guard let self else { return }
                self.refreshPermissionStatus()
                if self.accessibilityTrusted && self.inputMonitoringTrusted {
                    return
                }
            }
        }
    }

    private func translateCurrentSelection(mouseUpTime: UInt64) {
        let metrics = LatencyMetrics(startedAt: mouseUpTime)
        guard AXIsProcessTrusted() else {
            popup.show(message: "请先在“系统设置 → 隐私与安全性 → 辅助功能”中允许 Qiu。")
            return
        }

        // The panel is deliberately shown before selection extraction and inference.
        // This keeps perceived latency low even when a target app is slow to respond.
        popup.showLoading()
        metrics.mark("T_popup")
        SelectionReader().read { [weak self] source in
            Task { @MainActor in
                metrics.mark("T_selection")
                guard let self, let source, !source.isEmpty else {
                    self?.popup.dismiss()
                    metrics.mark("no_selection")
                    return
                }
                let direction = LanguageDetector.direction(for: source)
                do {
                    let translation = try await self.translator.translate(source, from: direction.source, to: direction.target)
                    metrics.mark("T_translation")
                    self.popup.show(
                        source: source,
                        translation: translation,
                        sourceLanguage: direction.source,
                        targetLanguage: direction.target
                    )
                    metrics.mark("T_translation_visible")
                } catch {
                    self.popup.show(message: error.localizedDescription)
                }
            }
        }
    }
}

import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @State private var isRecordingShortcut = false
    @State private var recordedModifiers: NSEvent.ModifierFlags = []
    @State private var flagsMonitor: Any?

    var body: some View {
        Form {
            Section("划词翻译") {
                Toggle("启用划词翻译", isOn: $appState.isEnabled)
                LabeledContent("触发方式") {
                    HStack(spacing: 8) {
                        Button(isRecordingShortcut ? recordingLabel : appState.triggerShortcut.displayName) {
                            recordedModifiers = []
                            isRecordingShortcut = true
                        }
                        .buttonStyle(.bordered)

                        if appState.triggerShortcut != .defaultValue {
                            Button("恢复默认") {
                                appState.triggerShortcut = .defaultValue
                            }
                            .buttonStyle(.link)
                        }
                    }
                }
                Text(isRecordingShortcut ? "请按键盘按键、组合键或鼠标侧键；按 Esc 取消。" : "按住触发键并划词，松开鼠标即可翻译。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("翻译模型") {
                backendPicker(title: "英文 → 中文", source: .english, target: .chinese)
                backendPicker(title: "中文 → 英文", source: .chinese, target: .english)

                Text("轻量模式省电且响应快；MLX 模式适合论文和复杂文本，仅支持 Apple Silicon，并会占用更多内存。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                DisclosureGroup("轻量语言包选择") {
                modelPicker(title: "英文 → 中文", source: .english, target: .chinese)
                modelPicker(title: "中文 → 英文", source: .chinese, target: .english)
                }

                HStack {
                    Button {
                        appState.reloadLanguagePacks()
                    } label: {
                        Label("刷新可用模型", systemImage: "arrow.clockwise")
                    }
                    Spacer()
                    Text("自动选择会使用该方向可用的最高版本")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    ModelManagementWindowController.shared.show(appState: appState)
                } label: {
                    Label("高级模型管理…", systemImage: "externaldrive")
                }
            }

            Section("获取语言包") {
                if appState.officialModelPackages.isEmpty {
                    Button {
                        appState.loadOfficialModelCatalog()
                    } label: {
                        if appState.isLoadingModelCatalog {
                            ProgressView()
                                .controlSize(.small)
                            Text("正在读取官方目录…")
                        } else {
                            Label("查看 Qiu 官方语言包", systemImage: "shippingbox")
                        }
                    }
                    .disabled(appState.isLoadingModelCatalog)
                } else {
                    ForEach(appState.officialModelPackages) { package in
                        officialPackageRow(package)
                    }

                    Button {
                        appState.loadOfficialModelCatalog()
                    } label: {
                        Label("刷新官方目录", systemImage: "arrow.clockwise")
                    }
                    .disabled(appState.isLoadingModelCatalog || appState.downloadingPackageIdentity != nil)
                }

                if let message = appState.modelCatalogMessage {
                    Label(message, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                if let error = appState.modelCatalogError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Text("仅在点击后联网；语言包来自 Qiu 官方 GitHub Release，安装前会校验文件大小、SHA-256 与包内清单。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("MLX 大模型目录") {
#if arch(arm64)
                if appState.officialMLXModels.isEmpty {
                    Button {
                        appState.loadOfficialMLXCatalog()
                    } label: {
                        if appState.isLoadingMLXCatalog {
                            ProgressView().controlSize(.small)
                            Text("正在读取模型目录…")
                        } else {
                            Label("查看 Qiu 审核的 MLX 模型", systemImage: "brain")
                        }
                    }
                    .disabled(appState.isLoadingMLXCatalog)
                } else {
                    ForEach(appState.officialMLXModels) { model in
                        officialMLXModelRow(model)
                    }
                    Button {
                        appState.loadOfficialMLXCatalog()
                    } label: {
                        Label("刷新 MLX 模型目录", systemImage: "arrow.clockwise")
                    }
                    .disabled(
                        appState.isLoadingMLXCatalog
                            || appState.downloadingMLXModelIdentity != nil
                    )
                }

                if let message = appState.mlxCatalogMessage {
                    Label(message, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                if let error = appState.mlxCatalogError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Text("目录仅在你点击后联网。模型从 Hugging Face 的 MLX Community 固定版本下载；完成后会校验模型结构并完全离线运行。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
#else
                Label("MLX 大模型仅支持 Apple Silicon Mac", systemImage: "info.circle")
                    .foregroundStyle(.secondary)
#endif
            }

            Section("权限") {
                PermissionStatusRow(title: "辅助功能", isAllowed: appState.accessibilityTrusted, detail: "读取其他应用的选中文本")
                PermissionStatusRow(title: "输入监控", isAllowed: appState.inputMonitoringTrusted, detail: "识别划词触发键和鼠标操作")

                if appState.readiness == .needsAuthorization {
                    Button("前往授权…") { appState.requestRequiredPermissions() }
                    Text("授权后返回 Qiu 即会自动生效，无需退出或重启。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("隐私") {
                Label("完全在本地翻译", systemImage: "lock.fill")
                Text("选中的文本不会上传，也不会保存为历史记录。只有你主动查看或下载语言包时才会访问网络。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 620)
        .padding()
        .onAppear {
            appState.refreshPermissionStatus()
            installShortcutMonitor()
        }
        .onDisappear { removeShortcutMonitor() }
    }

    @ViewBuilder
    private func backendPicker(title: String, source: Language, target: Language) -> some View {
        LabeledContent(title) {
            Picker(
                "",
                selection: Binding(
                    get: {
                        let identity = appState.selectedMLXModelIdentity(from: source, to: target)
                        return identity.isEmpty ? "light" : "mlx:\(identity)"
                    },
                    set: { selection in
                        if selection == "light" {
                            appState.useLightweightBackend(from: source, to: target)
                        } else if selection.hasPrefix("mlx:") {
                            appState.selectMLXModel(
                                String(selection.dropFirst(4)),
                                from: source,
                                to: target
                            )
                        }
                    }
                )
            ) {
                Text("轻量 OPUS-MT（推荐）").tag("light")
                ForEach(appState.mlxModels) { model in
                    Text("MLX · \(model.displayName) · 高质量").tag("mlx:\(model.id)")
                }
            }
            .labelsHidden()
            .frame(width: 300)
        }
    }

    private var recordingLabel: String {
        TriggerShortcut.modifiers(recordedModifiers)?.displayName ?? "请按触发键…"
    }

    @ViewBuilder
    private func modelPicker(title: String, source: Language, target: Language) -> some View {
        let packages = appState.languagePacks(from: source, to: target)
        LabeledContent(title) {
            Picker(
                "",
                selection: Binding(
                    get: { appState.selectedPackageIdentity(from: source, to: target) },
                    set: { appState.selectLanguagePack($0, from: source, to: target) }
                )
            ) {
                Text("自动选择（推荐）").tag("")
                ForEach(packages) { pack in
                    Text(modelLabel(pack)).tag(pack.id)
                }
            }
            .labelsHidden()
            .frame(width: 300)
        }

        if packages.isEmpty {
            Text("没有找到可用于 \(title) 的本地语言包。")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    private func modelLabel(_ pack: InstalledLanguagePack) -> String {
        let origin = pack.origin == .builtIn ? "内置" : "本地"
        return "\(pack.package.metadata.displayName) · v\(pack.package.metadata.version) · \(origin)"
    }

    @ViewBuilder
    private func officialPackageRow(_ package: OfficialModelPackage) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(package.displayName)
                Text(officialPackageDetail(package))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()

            if appState.isOfficialPackageInstalled(package) {
                Label("已安装", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else if appState.downloadingPackageIdentity == package.identity {
                ProgressView()
                    .controlSize(.small)
                Text("下载中…")
                    .font(.caption)
            } else {
                Button("下载并安装") {
                    appState.downloadOfficialPackage(package)
                }
                .disabled(appState.downloadingPackageIdentity != nil)
            }
        }
    }

    private func officialPackageDetail(_ package: OfficialModelPackage) -> String {
        let size = ByteCountFormatter.string(fromByteCount: package.sizeBytes, countStyle: .file)
        let license = package.license.map { " · \($0)" } ?? ""
        return "\(package.sourceLanguage.uppercased()) → \(package.targetLanguage.uppercased()) · v\(package.version) · \(size)\(license)"
    }

    @ViewBuilder
    private func officialMLXModelRow(_ model: OfficialMLXModel) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(model.displayName)
                        Text(model.quality)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.tint.opacity(0.12), in: Capsule())
                    }
                    Text(officialMLXModelDetail(model))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(model.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                if appState.isOfficialMLXModelInstalled(model) {
                    Label("已安装", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else if appState.downloadingMLXModelIdentity == model.id {
                    VStack(alignment: .trailing, spacing: 4) {
                        ProgressView(value: appState.mlxDownloadProgress)
                            .frame(width: 92)
                        Text("\(Int(appState.mlxDownloadProgress * 100))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button("一键下载") {
                        appState.downloadOfficialMLXModel(model)
                    }
                    .disabled(appState.downloadingMLXModelIdentity != nil)
                }
            }
            Link(
                "查看模型来源与许可证",
                destination: URL(string: "https://huggingface.co/\(model.repositoryID)/tree/\(model.revision)")!
            )
            .font(.caption)
        }
        .padding(.vertical, 4)
    }

    private func officialMLXModelDetail(_ model: OfficialMLXModel) -> String {
        let download = ByteCountFormatter.string(fromByteCount: model.downloadBytes, countStyle: .file)
        let memory = ByteCountFormatter.string(fromByteCount: model.recommendedMemoryBytes, countStyle: .memory)
        return "\(model.parameterLabel) · 下载 \(download) · 建议可用内存 \(memory) · \(model.license)"
    }

    private func installShortcutMonitor() {
        guard flagsMonitor == nil else { return }
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown, .otherMouseDown]) { event in
            guard isRecordingShortcut else { return event }

            if event.type == .keyDown, event.keyCode == 53 {
                recordedModifiers = []
                isRecordingShortcut = false
                return nil
            }

            if event.type == .keyDown {
                appState.triggerShortcut = .keyboard(event: event)
                recordedModifiers = []
                isRecordingShortcut = false
                return nil
            }

            if event.type == .otherMouseDown, event.buttonNumber >= 2 {
                appState.triggerShortcut = .mouseButton(number: event.buttonNumber)
                recordedModifiers = []
                isRecordingShortcut = false
                return nil
            }

            let current = event.modifierFlags.intersection(TriggerShortcut.allowedModifiers)
            if !current.isEmpty {
                recordedModifiers.formUnion(current)
            } else if !recordedModifiers.isEmpty {
                appState.triggerShortcut = TriggerShortcut.modifiers(recordedModifiers) ?? .defaultValue
                recordedModifiers = []
                isRecordingShortcut = false
            }
            return nil
        }
    }

    private func removeShortcutMonitor() {
        if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor) }
        flagsMonitor = nil
    }
}

private struct PermissionStatusRow: View {
    let title: String
    let isAllowed: Bool
    let detail: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isAllowed ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(isAllowed ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(isAllowed ? "已允许" : detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

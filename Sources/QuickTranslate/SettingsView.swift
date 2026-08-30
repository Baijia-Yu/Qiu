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
                modelPicker(title: "英文 → 中文", source: .english, target: .chinese)
                modelPicker(title: "中文 → 英文", source: .chinese, target: .english)

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

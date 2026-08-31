import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ModelManagementView: View {
    @ObservedObject var appState: AppState
    @State private var selectedIdentity: String?
    @State private var packagePendingRemoval: InstalledLanguagePack?

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                packageList
                    .frame(minWidth: 230, idealWidth: 260, maxWidth: 320)
                detail
                    .frame(minWidth: 440, maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()
            footer
        }
        .frame(minWidth: 720, minHeight: 480)
        .onAppear { selectFirstAvailablePackage() }
        .onChange(of: appState.installedLanguagePacks.map(\.id)) { _, _ in
            selectFirstAvailablePackage()
        }
        .alert(
            "移除语言包？",
            isPresented: Binding(
                get: { packagePendingRemoval != nil },
                set: { if !$0 { packagePendingRemoval = nil } }
            ),
            presenting: packagePendingRemoval
        ) { package in
            Button("移除", role: .destructive) {
                appState.removeLanguagePack(package)
                packagePendingRemoval = nil
            }
            Button("取消", role: .cancel) { packagePendingRemoval = nil }
        } message: { package in
            Text("将从本机移除 \(package.package.metadata.displayName) v\(package.package.metadata.version)。之后可再次导入或下载。")
        }
    }

    private var selectedPackage: InstalledLanguagePack? {
        appState.installedLanguagePacks.first { $0.id == selectedIdentity }
    }

    private var packageList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("已安装模型")
                .font(.headline)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            Divider()
            List(appState.installedLanguagePacks, selection: $selectedIdentity) { package in
                VStack(alignment: .leading, spacing: 4) {
                    Text(package.package.metadata.displayName)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text("v\(package.package.metadata.version)")
                        Text(package.origin == .builtIn ? "内置" : "本地")
                        if appState.loadedPackageIdentities.contains(package.id) {
                            Text("已加载")
                                .foregroundStyle(.green)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 3)
                .tag(package.id)
            }
            .listStyle(.sidebar)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let package = selectedPackage {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    packageHeader(package)
                    packageInformation(package)
                    packageLocation(package)
                    packageActions(package)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ContentUnavailableView(
                "没有已安装模型",
                systemImage: "shippingbox",
                description: Text("导入 Qiu 语言包，或从设置中的官方目录下载。")
            )
        }
    }

    private func packageHeader(_ package: InstalledLanguagePack) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(package.package.metadata.displayName)
                    .font(.title2.weight(.semibold))
                Spacer()
                if appState.isLanguagePackSelected(package) {
                    Label("当前使用", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                }
            }
            Text(package.id)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private func packageInformation(_ package: InstalledLanguagePack) -> some View {
        let metadata = package.package.metadata
        return Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
            informationRow("语言方向", "\(metadata.sourceLanguage.uppercased()) → \(metadata.targetLanguage.uppercased())")
            informationRow("版本", metadata.version)
            informationRow("来源", package.origin == .builtIn ? "Qiu 内置" : "用户安装")
            informationRow("运行时", metadata.runtime)
            informationRow("许可证", metadata.license ?? "未声明")
            informationRow("模型来源", metadata.source ?? "未声明")
            if let attribution = metadata.attribution {
                informationRow("署名", attribution)
            }
            informationRow(
                "内存状态",
                appState.loadedPackageIdentities.contains(package.id) ? "已加载" : "未加载"
            )
        }
    }

    private func informationRow(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
        }
    }

    private func packageLocation(_ package: InstalledLanguagePack) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("本地位置")
                .font(.headline)
            Text(package.package.rootURL.path)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Button("在 Finder 中显示") {
                NSWorkspace.shared.activateFileViewerSelecting([package.package.rootURL])
            }
        }
    }

    private func packageActions(_ package: InstalledLanguagePack) -> some View {
        let loaded = appState.loadedPackageIdentities.contains(package.id)
        let busy = appState.modelManagementOperation != nil
        let supportedDirection = Language(rawValue: package.package.metadata.sourceLanguage) != nil
            && Language(rawValue: package.package.metadata.targetLanguage) != nil

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button("设为此方向模型") { appState.useLanguagePack(package) }
                    .disabled(busy || !supportedDirection || appState.isLanguagePackSelected(package))

                if loaded {
                    Button("从内存卸载") { appState.unloadLanguagePack(package) }
                        .disabled(busy)
                } else {
                    Button("加载到内存") { appState.loadLanguagePack(package) }
                        .disabled(busy)
                }

                Spacer()
                if package.origin == .userInstalled {
                    Button("移除…", role: .destructive) { packagePendingRemoval = package }
                        .disabled(busy)
                }
            }
            if !supportedDirection {
                Text("当前版本的划词方向路由仅支持 EN ↔ ZH；此包可以验证和查看，但暂不能设为划词翻译模型。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                presentImportPanel()
            } label: {
                Label("导入语言包…", systemImage: "plus")
            }
            .disabled(appState.modelManagementOperation != nil)

            Button {
                appState.reloadLanguagePacks()
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .disabled(appState.modelManagementOperation != nil)

            Button("全部卸载") { appState.unloadAllLanguagePacks() }
                .disabled(appState.modelManagementOperation != nil || appState.loadedPackageIdentities.isEmpty)

            if appState.modelManagementOperation != nil {
                ProgressView()
                    .controlSize(.small)
            }

            Spacer()
            if let message = appState.modelManagementMessage {
                Label(message, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .lineLimit(1)
            } else if let error = appState.modelManagementError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
        }
        .padding(12)
    }

    private func selectFirstAvailablePackage() {
        if let selectedIdentity,
           appState.installedLanguagePacks.contains(where: { $0.id == selectedIdentity }) {
            return
        }
        selectedIdentity = appState.installedLanguagePacks.first?.id
    }

    private func presentImportPanel() {
        let panel = NSOpenPanel()
        panel.title = "导入 Qiu 语言包"
        panel.message = "选择 .qiu-languagepack 文件或包含 qiu-package.json 的语言包目录。"
        panel.prompt = "导入"
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.resolvesAliases = true
        if let packageType = UTType(filenameExtension: "qiu-languagepack") {
            panel.allowedContentTypes = [packageType]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        appState.clearModelManagementFeedback()
        appState.importLanguagePack(from: url)
    }
}

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
                Text("选中的文本不会上传，也不会保存为历史记录。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 330)
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

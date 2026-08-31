import AppKit
import SwiftUI

@main
struct QuickTranslateApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra("Qiu", systemImage: "quote.bubble.fill") {
            Label(appState.readiness.title, systemImage: appState.readiness.systemImage)
                .foregroundStyle(Color(nsColor: appState.readiness.color))

            if appState.readiness == .needsAuthorization {
                Button("前往授权…") { appState.requestRequiredPermissions() }
                Divider()
            }

            Toggle("启用划词翻译", isOn: $appState.isEnabled)
            Text("触发键：\(appState.triggerShortcut.displayName)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider()
            Button("设置…") {
                SettingsWindowController.shared.show(appState: appState)
            }
            Button("模型管理…") {
                ModelManagementWindowController.shared.show(appState: appState)
            }
            Button("退出 Qiu") { NSApplication.shared.terminate(nil) }
        }
        .menuBarExtraStyle(.menu)
    }
}

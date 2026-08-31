import AppKit
import SwiftUI

@MainActor
final class ModelManagementWindowController: NSWindowController {
    static let shared = ModelManagementWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Qiu 模型管理"
        window.minSize = NSSize(width: 720, height: 480)
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(appState: AppState) {
        window?.contentViewController = NSHostingController(
            rootView: ModelManagementView(appState: appState)
        )
        appState.reloadLanguagePacks()
        NSApplication.shared.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

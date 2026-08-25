import AppKit

/// Passive global monitor: it observes events and never consumes them.
final class SelectionEventMonitor {
    private var monitor: Any?
    private var shortcut: TriggerShortcut
    private var triggerIsPressed = false
    private let onSelectionFinished: @Sendable (UInt64) -> Void

    init(shortcut: TriggerShortcut, onSelectionFinished: @escaping @Sendable (UInt64) -> Void) {
        self.shortcut = shortcut
        self.onSelectionFinished = onSelectionFinished
    }

    func update(shortcut: TriggerShortcut) {
        self.shortcut = shortcut
        triggerIsPressed = false
    }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseUp, .keyDown, .keyUp, .otherMouseDown, .otherMouseUp]
        ) { [weak self] event in
            guard let self else { return }
            switch event.type {
            case .keyDown where self.shortcut.matchesKeyDown(event):
                self.triggerIsPressed = true
            case .keyUp where self.shortcut.matchesKeyUp(event):
                self.triggerIsPressed = false
            case .otherMouseDown where self.shortcut.matchesMouseButton(event):
                self.triggerIsPressed = true
            case .otherMouseUp where self.shortcut.matchesMouseButton(event):
                self.triggerIsPressed = false
            case .leftMouseUp:
                guard self.triggerIsPressed || self.shortcut.matchesModifiers(event.modifierFlags) else { return }
                self.onSelectionFinished(DispatchTime.now().uptimeNanoseconds)
            default:
                break
            }
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        triggerIsPressed = false
    }
}

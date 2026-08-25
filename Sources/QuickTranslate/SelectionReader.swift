import AppKit
import ApplicationServices

@MainActor
struct SelectionReader {
    func read(completion: @escaping @Sendable (String?) -> Void) {
        if let selected = selectedTextFromAccessibility(), !selected.isEmpty {
            completion(selected)
            return
        }
        selectedTextFromClipboard(completion: completion)
    }

    private func selectedTextFromAccessibility() -> String? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused else { return nil }
        var selected: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXSelectedTextAttribute as CFString, &selected) == .success else { return nil }
        return selected as? String
    }

    private func selectedTextFromClipboard(completion: @escaping @Sendable (String?) -> Void) {
        let pasteboard = NSPasteboard.general
        let originalChangeCount = pasteboard.changeCount
        let savedItems = pasteboard.pasteboardItems?.map(copyItem)
        sendCopyShortcut()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            // Never treat the existing clipboard as a selection. Some web views do not
            // accept the synthetic copy event; in that case changeCount stays unchanged.
            guard pasteboard.changeCount != originalChangeCount else {
                completion(nil)
                return
            }
            let copied = pasteboard.string(forType: .string)
            pasteboard.clearContents()
            if let savedItems { pasteboard.writeObjects(savedItems) }
            completion(copied)
        }
    }

    private func copyItem(_ item: NSPasteboardItem) -> NSPasteboardItem {
        let copy = NSPasteboardItem()
        for type in item.types {
            if let data = item.data(forType: type) { copy.setData(data, forType: type) }
        }
        return copy
    }

    private func sendCopyShortcut() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}

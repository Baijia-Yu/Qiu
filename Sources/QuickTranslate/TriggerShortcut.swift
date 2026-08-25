import AppKit

enum TriggerShortcut: Codable, Equatable {
    case modifiers(rawValue: UInt)
    case keyboard(keyCode: UInt16, modifiersRawValue: UInt, keyLabel: String)
    case mouseButton(number: Int)

    static let defaultValue = TriggerShortcut.modifiers(
        rawValue: NSEvent.ModifierFlags([.control, .option]).rawValue
    )
    static let allowedModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .shift]

    var displayName: String {
        switch self {
        case let .modifiers(rawValue):
            return Self.modifierName(for: NSEvent.ModifierFlags(rawValue: rawValue))
        case let .keyboard(_, rawValue, keyLabel):
            let modifiers = Self.modifierName(for: NSEvent.ModifierFlags(rawValue: rawValue))
            return modifiers.isEmpty ? keyLabel : "\(modifiers) + \(keyLabel)"
        case let .mouseButton(number):
            return "鼠标按键 \(number + 1)"
        }
    }

    static func modifiers(_ modifiers: NSEvent.ModifierFlags) -> TriggerShortcut? {
        let filtered = modifiers.intersection(allowedModifiers)
        guard !filtered.isEmpty else { return nil }
        return .modifiers(rawValue: filtered.rawValue)
    }

    static func keyboard(event: NSEvent) -> TriggerShortcut {
        let modifiers = event.modifierFlags.intersection(allowedModifiers)
        return .keyboard(
            keyCode: event.keyCode,
            modifiersRawValue: modifiers.rawValue,
            keyLabel: keyLabel(for: event)
        )
    }

    func matchesModifiers(_ eventFlags: NSEvent.ModifierFlags) -> Bool {
        guard case let .modifiers(rawValue) = self else { return false }
        return eventFlags.intersection(Self.allowedModifiers).rawValue == rawValue
    }

    func matchesKeyDown(_ event: NSEvent) -> Bool {
        guard case let .keyboard(keyCode, rawValue, _) = self else { return false }
        let eventModifiers = event.modifierFlags.intersection(Self.allowedModifiers)
        return event.keyCode == keyCode && eventModifiers.rawValue == rawValue
    }

    func matchesKeyUp(_ event: NSEvent) -> Bool {
        guard case let .keyboard(keyCode, _, _) = self else { return false }
        return event.keyCode == keyCode
    }

    func matchesMouseButton(_ event: NSEvent) -> Bool {
        guard case let .mouseButton(number) = self else { return false }
        return event.buttonNumber == number
    }

    private static func modifierName(for flags: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []
        if flags.contains(.control) { parts.append("⌃ Control") }
        if flags.contains(.option) { parts.append("⌥ Option") }
        if flags.contains(.shift) { parts.append("⇧ Shift") }
        if flags.contains(.command) { parts.append("⌘ Command") }
        return parts.joined(separator: " + ")
    }

    private static func keyLabel(for event: NSEvent) -> String {
        let specialKeys: [UInt16: String] = [
            36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 53: "Esc",
            115: "Home", 116: "Page Up", 117: "Forward Delete", 119: "End",
            121: "Page Down", 123: "←", 124: "→", 125: "↓", 126: "↑",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"
        ]
        if let special = specialKeys[event.keyCode] { return special }
        let characters = event.charactersIgnoringModifiers?.trimmingCharacters(in: .whitespacesAndNewlines)
        return characters?.isEmpty == false ? characters!.uppercased() : "按键 \(event.keyCode)"
    }
}

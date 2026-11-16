import AppKit
import Carbon.HIToolbox
import MacStartCore

/// Names keys and shortcuts the way macOS menus show them, for example "⌥S", using the current keyboard layout.
@MainActor
enum KeyNames {
    /// The shortcut's modifier symbols, in the order macOS uses, followed by its key.
    static func text(for hotKey: HotKey) -> String {
        var text = ""
        if hotKey.modifiers.contains(.control) { text += "⌃" }
        if hotKey.modifiers.contains(.option) { text += "⌥" }
        if hotKey.modifiers.contains(.shift) { text += "⇧" }
        if hotKey.modifiers.contains(.command) { text += "⌘" }
        return text + name(forKeyCode: hotKey.keyCode)
    }

    /// The modifiers of a key event as shortcut modifiers.
    static func modifiers(of flags: NSEvent.ModifierFlags) -> HotKey.Modifiers {
        var modifiers: HotKey.Modifiers = []
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }
        return modifiers
    }

    /// The key's name: a symbol or word for special keys, otherwise the character the current layout types,
    /// in uppercase.
    static func name(forKeyCode keyCode: UInt16) -> String {
        if let special = specialNames[Int(keyCode)] {
            return special
        }
        return typedCharacter(forKeyCode: keyCode)?.uppercased() ?? "Key \(keyCode)"
    }

    private static func typedCharacter(forKeyCode keyCode: UInt16) -> String? {
        guard
            let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
            let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else {
            return nil
        }
        let data = Unmanaged<CFData>.fromOpaque(layoutData).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        let status = data.withUnsafeBytes { buffer -> OSStatus in
            guard let keyboardLayout = buffer.bindMemory(to: UCKeyboardLayout.self).baseAddress else {
                return OSStatus(paramErr)
            }
            return UCKeyTranslate(
                keyboardLayout,
                keyCode,
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                characters.count,
                &length,
                &characters
            )
        }
        guard status == noErr, length > 0 else {
            return nil
        }
        let text = String(utf16CodeUnits: characters, count: length)
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }

    private static let specialNames: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_ANSI_KeypadEnter: "⌤", kVK_Tab: "⇥", kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦", kVK_Escape: "⎋", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑",
        kVK_DownArrow: "↓", kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7",
        kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13",
        kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19",
        kVK_F20: "F20",
    ]
}

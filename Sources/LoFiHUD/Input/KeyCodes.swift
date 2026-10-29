import Carbon.HIToolbox
import Foundation

/// Maps the config's key names ("q", "2", "up", "space", …) to virtual key codes and back,
/// honoring the user's active keyboard layout for character keys.
enum KeyCodes {
    static let named: [String: Int] = [
        "space": kVK_Space, "enter": kVK_Return, "return": kVK_Return, "tab": kVK_Tab,
        "backspace": kVK_Delete, "delete": kVK_ForwardDelete, "escape": kVK_Escape,
        "up": kVK_UpArrow, "down": kVK_DownArrow, "left": kVK_LeftArrow, "right": kVK_RightArrow,
        "home": kVK_Home, "end": kVK_End, "page_up": kVK_PageUp, "page_down": kVK_PageDown,
        "f1": kVK_F1, "f2": kVK_F2, "f3": kVK_F3, "f4": kVK_F4, "f5": kVK_F5, "f6": kVK_F6,
        "f7": kVK_F7, "f8": kVK_F8, "f9": kVK_F9, "f10": kVK_F10, "f11": kVK_F11, "f12": kVK_F12,
        "f13": kVK_F13, "f14": kVK_F14, "f15": kVK_F15, "f16": kVK_F16,
    ]

    private static let ansi: [String: Int] = [
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E,
        "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J,
        "k": kVK_ANSI_K, "l": kVK_ANSI_L, "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O,
        "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
        "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X, "y": kVK_ANSI_Y,
        "z": kVK_ANSI_Z, "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3,
        "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8,
        "9": kVK_ANSI_9, "-": kVK_ANSI_Minus, "=": kVK_ANSI_Equal, "[": kVK_ANSI_LeftBracket,
        "]": kVK_ANSI_RightBracket, ";": kVK_ANSI_Semicolon, "'": kVK_ANSI_Quote,
        ",": kVK_ANSI_Comma, ".": kVK_ANSI_Period, "/": kVK_ANSI_Slash,
        "\\": kVK_ANSI_Backslash, "`": kVK_ANSI_Grave,
    ]

    static func keyCode(for name: String) -> Int? {
        let key = name.lowercased().trimmingCharacters(in: .whitespaces)
        if key == " " { return kVK_Space }
        if let code = named[key] { return code }
        if key.count == 1 {
            if let code = layoutMap()[key] { return code }
            return ansi[key]
        }
        return nil
    }

    /// Inverse mapping used by keybind capture in Settings.
    static func name(for keyCode: Int) -> String? {
        if let entry = named.first(where: { $0.value == keyCode && $0.key != "return" }) {
            return entry.key
        }
        if let char = translate(keyCode) { return char }
        return ansi.first(where: { $0.value == keyCode })?.key
    }

    /// Human-friendly label for a key name, e.g. "up" → "↑".
    static func display(_ name: String) -> String {
        switch name.lowercased() {
        case "up": return "↑"
        case "down": return "↓"
        case "left": return "←"
        case "right": return "→"
        case "space": return "Space"
        case "enter", "return": return "↩"
        case "tab": return "⇥"
        case "backspace": return "⌫"
        case "delete": return "⌦"
        case "escape": return "⎋"
        default: return name.uppercased()
        }
    }

    // MARK: Layout-aware translation

    private static func layoutMap() -> [String: Int] {
        var map: [String: Int] = [:]
        for code in 0..<128 {
            if let c = translate(code), map[c] == nil { map[c] = code }
        }
        return map
    }

    private static func translate(_ keyCode: Int) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let status = data.withUnsafeBytes { buf -> OSStatus in
            guard let layout = buf.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                return -1
            }
            return UCKeyTranslate(
                layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0,
                UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeys, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return nil }
        let s = String(utf16CodeUnits: chars, count: length).lowercased()
        guard s.count == 1, let scalar = s.unicodeScalars.first,
              !CharacterSet.controlCharacters.contains(scalar),
              !CharacterSet.whitespaces.contains(scalar) else { return nil }
        return s
    }
}

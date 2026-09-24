import Foundation

/// macOS 虚拟键码到音效包键位名。未列出的键走 `default`。
public enum KeyMap {
    public static func name(for keyCode: UInt16) -> String? {
        switch keyCode {
        case 49: return "space"
        case 36, 76: return "return"
        case 51: return "backspace"
        case 117: return "forward_delete"
        case 56, 60: return "shift"
        case 57: return "capslock"
        case 48: return "tab"
        case 53: return "escape"
        default: return nil
        }
    }
}

/// Shift / CapsLock 只发 flagsChanged。按下瞬间才发声，松开不发。
public enum ModifierStrike {
    public static func shouldPlay(keyCode: UInt16, shiftDown: Bool) -> Bool {
        if keyCode == 57 { return true }
        return (keyCode == 56 || keyCode == 60) && shiftDown
    }
}

/// Option+Shift+M。再按着 Command 或 Control 时不触发，避免和系统快捷键抢。
public enum Hotkey {
    public static let muteKeyCode: UInt16 = 46

    public static func isMuteToggle(keyCode: UInt16,
                                    option: Bool,
                                    shift: Bool,
                                    command: Bool,
                                    control: Bool) -> Bool {
        keyCode == muteKeyCode && option && shift && !command && !control
    }
}

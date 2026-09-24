import Cocoa
import CraftAudioCore

/// 全局快捷键：Option + Shift + M 一键静音切换。
/// 全局监视器只覆盖其他应用；本应用聚焦时要靠本地监视器。
final class HotkeyManager {
    static let shared = HotkeyManager()
    private var monitors: [Any] = []

    func start() {
        guard monitors.isEmpty else { return }
        let handler: (NSEvent) -> Void = { event in
            guard HotkeyManager.matches(event) else { return }
            DispatchQueue.main.async { Settings.shared.muted.toggle() }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: handler) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { event in
            handler(event)
            return event
        }) {
            monitors.append(local)
        }
    }

    static func matches(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return Hotkey.isMuteToggle(
            keyCode: event.keyCode,
            option: flags.contains(.option),
            shift: flags.contains(.shift),
            command: flags.contains(.command),
            control: flags.contains(.control)
        )
    }

    func stop() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
    }

    deinit { stop() }
}

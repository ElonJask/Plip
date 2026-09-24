import Cocoa
import CraftAudioCore

/// 基于 CGEventTap 的全局按键监听（只监听、不拦截，零输入影响）。
/// 需要「辅助功能」权限；未授权时自动弹系统提示并每 3 秒重试。
final class KeyListener {
    static let shared = KeyListener()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var retryTimer: Timer?

    var isListening: Bool { eventTap != nil }

    func start() {
        if setupTap() { return }
        // 触发系统授权弹窗
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        retryTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.setupTap() {
                self.retryTimer?.invalidate()
                self.retryTimer = nil
            }
        }
    }

    func stop() {
        retryTimer?.invalidate()
        retryTimer = nil
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    private func setupTap() -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let mask = CGEventMask((1 << CGEventType.keyDown.rawValue)
                               | (1 << CGEventType.flagsChanged.rawValue))
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let listener = Unmanaged<KeyListener>.fromOpaque(refcon).takeUnretainedValue()
                listener.handle(type: type, event: event)
                return Unmanaged.passUnretained(event) // 只监听，不吞事件
            },
            userInfo: refcon
        ) else { return false }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) {
        // 系统因超时禁用了 tap 时重新启用
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        switch type {
        case .keyDown:
            SoundEngine.shared.keyDown(keyCode: keyCode)
        case .flagsChanged:
            if ModifierStrike.shouldPlay(keyCode: keyCode, shiftDown: event.flags.contains(.maskShift)) {
                SoundEngine.shared.keyDown(keyCode: keyCode)
            }
        default:
            break
        }
    }
}

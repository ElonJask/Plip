import AppKit
import CoreAudio
import CraftAudioCore

/// 智能免打扰。判断交给 MutePolicy：通话应用，或前台应用自己占用麦克风时静音；
/// 后台听写和语音备忘录不静音。前台应用命中黑名单时也静音。
final class SmartMute: ObservableObject {
    static let shared = SmartMute()

    /// 当前是否处于被压制（自动静音）状态
    @Published private(set) var isSuppressed = false
    @Published private(set) var suppressReason: String = ""

    private var timer: Timer?

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.poll()
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(frontAppChanged),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
        poll()
    }

    @objc private func frontAppChanged() {
        poll()
    }

    private func poll() {
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        let decision = MutePolicy.decide(
            smartMuteEnabled: Settings.shared.smartMuteEnabled,
            frontBundleID: front,
            blacklist: Settings.shared.blacklistedBundleIDs,
            inputClients: Self.inputClients()
        )
        update(suppressed: decision.suppressed, reason: decision.reason)
    }

    private func update(suppressed: Bool, reason: String) {
        if suppressed != isSuppressed || reason != suppressReason {
            isSuppressed = suppressed
            suppressReason = reason
        }
    }

    /// 列出正在打开输入流的进程。读不到时按没人占用处理，避免误静音。
    static func inputClients() -> [AudioClient] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr, size > 0 else {
            return []
        }
        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var ids = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }

        return ids.map { object in
            AudioClient(bundleID: stringProperty(kAudioProcessPropertyBundleID, object: object),
                        runningInput: uintProperty(kAudioProcessPropertyIsRunningInput, object: object) != 0)
        }
    }

    private static func uintProperty(_ selector: AudioObjectPropertySelector, object: AudioObjectID) -> UInt32 {
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value) == noErr else { return 0 }
        return value
    }

    private static func stringProperty(_ selector: AudioObjectPropertySelector, object: AudioObjectID) -> String {
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value) == noErr,
              let value else { return "" }
        return value.takeRetainedValue() as String
    }
}

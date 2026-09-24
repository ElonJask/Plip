import Foundation

public struct AudioClient: Equatable {
    public var bundleID: String
    public var runningInput: Bool

    public init(bundleID: String, runningInput: Bool) {
        self.bundleID = bundleID
        self.runningInput = runningInput
    }
}

public struct MuteDecision: Equatable {
    public var suppressed: Bool
    public var reason: String

    public init(suppressed: Bool, reason: String) {
        self.suppressed = suppressed
        self.reason = reason
    }

    public static let clear = MuteDecision(suppressed: false, reason: "")
}

/// 决定要不要自动静音。
/// 后台的听写、语音备忘录不会静音；通话应用，或当前正在打字的那个应用自己占用麦克风时才会。
public enum MutePolicy {
    /// 常见会议 / 通话应用。只在它们确实打开了输入流时才静音。
    public static let callBundleIDs: Set<String> = [
        "us.zoom.xos",
        "com.apple.FaceTime",
        "com.apple.FaceTime.FaceTimeNotificationExtension",
        "com.tencent.meeting",
        "com.tencent.wemeet",
        "com.microsoft.teams",
        "com.microsoft.teams2",
        "com.cisco.webexmeetingsapp",
        "com.alibaba.DingTalkMac",
        "com.bytedance.macos.feishu",
        "com.electron.lark"
    ]

    public static func decide(smartMuteEnabled: Bool,
                               frontBundleID: String,
                               blacklist: [String],
                               inputClients: [AudioClient]) -> MuteDecision {
        guard smartMuteEnabled else { return .clear }

        let live = inputClients.filter(\.runningInput).map(\.bundleID).filter { !$0.isEmpty }
        if let call = live.first(where: { callBundleIDs.contains($0) }) {
            return MuteDecision(suppressed: true, reason: "通话应用正在使用麦克风（\(call)）")
        }
        if !frontBundleID.isEmpty, live.contains(frontBundleID) {
            return MuteDecision(suppressed: true, reason: "前台应用正在使用麦克风")
        }
        if !frontBundleID.isEmpty, blacklist.contains(frontBundleID) {
            return MuteDecision(suppressed: true, reason: "前台应用在黑名单中")
        }
        return .clear
    }
}

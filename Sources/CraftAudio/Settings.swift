import Foundation

/// 用户设置，UserDefaults 持久化
final class Settings: ObservableObject {
    static let shared = Settings()
    private let d = UserDefaults.standard

    @Published var masterVolume: Double {
        didSet { d.set(masterVolume, forKey: "masterVolume") }
    }
    @Published var muted: Bool {
        didSet { d.set(muted, forKey: "muted") }
    }
    @Published var smartMuteEnabled: Bool {
        didSet { d.set(smartMuteEnabled, forKey: "smartMuteEnabled") }
    }
    /// 全局连击开关（还需音效包自身开启 combo_enabled）
    @Published var comboEnabled: Bool {
        didSet { d.set(comboEnabled, forKey: "comboEnabled") }
    }
    @Published var selectedPackID: String {
        didSet { d.set(selectedPackID, forKey: "selectedPackID") }
    }
    /// 前台应用黑名单（bundle id），命中时自动静音
    @Published var blacklistedBundleIDs: [String] {
        didSet { d.set(blacklistedBundleIDs, forKey: "blacklistedBundleIDs") }
    }

    private init() {
        d.register(defaults: [
            "masterVolume": 0.8,
            "muted": false,
            "smartMuteEnabled": true,
            "comboEnabled": true,
            "selectedPackID": "",
            "blacklistedBundleIDs": ["com.apple.logic10", "com.ableton.live"]
        ])
        masterVolume = d.double(forKey: "masterVolume")
        muted = d.bool(forKey: "muted")
        smartMuteEnabled = d.bool(forKey: "smartMuteEnabled")
        comboEnabled = d.bool(forKey: "comboEnabled")
        selectedPackID = d.string(forKey: "selectedPackID") ?? ""
        blacklistedBundleIDs = d.stringArray(forKey: "blacklistedBundleIDs") ?? []
    }
}

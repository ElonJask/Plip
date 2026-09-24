import Combine
import CraftAudioCore
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var store = SoundpackStore.shared
    @ObservedObject private var smartMute = SmartMute.shared
    @ObservedObject private var loginItem = LoginItemController.shared

    @State private var accessibilityOK = AXIsProcessTrusted()
    @State private var blacklistText = ""
    private let refreshTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Plip").font(.headline)
                Spacer()
                if settings.muted {
                    Text("已静音").font(.caption).foregroundColor(.red)
                } else if smartMute.isSuppressed {
                    Text("自动静音中").font(.caption).foregroundColor(.orange)
                }
            }

            if !accessibilityOK {
                VStack(alignment: .leading, spacing: 6) {
                    Text("需要「辅助功能」权限才能监听全局按键")
                        .font(.caption).foregroundColor(.orange)
                    Button("打开系统设置授权") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }.font(.caption)
                }
                .padding(8)
                .background(Color.orange.opacity(0.12))
                .cornerRadius(8)
            }

            Picker("音效包", selection: Binding(
                get: { settings.selectedPackID },
                set: { SoundEngine.shared.selectPack(id: $0) }
            )) {
                ForEach(store.packs, id: \.id) { pack in
                    Text(pack.manifest.name).tag(pack.id)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("音量 \(Int(settings.masterVolume * 100))%").font(.caption)
                Slider(value: $settings.masterVolume, in: 0...1)
            }

            Toggle("静音（⌥⇧M）", isOn: $settings.muted)
            Toggle("连击升调模式（MC 经验球）", isOn: $settings.comboEnabled)
            Toggle("智能免打扰（通话 / 黑名单应用）", isOn: $settings.smartMuteEnabled)

            if smartMute.isSuppressed, !smartMute.suppressReason.isEmpty {
                Text(smartMute.suppressReason).font(.caption).foregroundColor(.secondary)
            }

            Toggle("开机自启", isOn: Binding(
                get: { loginItem.state.isOn },
                set: { loginItem.setEnabled($0) }
            ))
            if let message = loginItem.state.message {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Button("打开「登录项」设置") {
                    SMAppService.openSystemSettingsLoginItems()
                }.font(.caption)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("黑名单应用 Bundle ID（逗号分隔）").font(.caption)
                TextField("com.apple.logic10, com.ableton.live", text: $blacklistText)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .onSubmit { commitBlacklist() }
            }

            Divider()

            HStack {
                Button("音效包目录") {
                    NSWorkspace.shared.open(SoundpackStore.shared.userPacksDir)
                }.font(.caption)
                Spacer()
                Button("退出") {
                    NSApplication.shared.terminate(nil)
                }.font(.caption)
            }
        }
        .padding(14)
        .frame(width: 320)
        .onAppear {
            accessibilityOK = AXIsProcessTrusted()
            blacklistText = settings.blacklistedBundleIDs.joined(separator: ", ")
            loginItem.refresh()
        }
        .onReceive(refreshTimer) { _ in
            accessibilityOK = AXIsProcessTrusted()
            loginItem.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .craftAudioCommitBlacklist)) { _ in
            commitBlacklist()
        }
    }

    private func commitBlacklist() {
        let parsed = BlacklistParser.parse(blacklistText)
        if parsed != settings.blacklistedBundleIDs {
            settings.blacklistedBundleIDs = parsed
        }
    }
}

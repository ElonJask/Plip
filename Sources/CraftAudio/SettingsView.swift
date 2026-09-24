import AppKit
import Combine
import CraftAudioCore
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

/// 菜单栏弹出层。深色、分行，不用系统表单那一套堆叠。
struct SettingsView: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var store = SoundpackStore.shared
    @ObservedObject private var smartMute = SmartMute.shared
    @ObservedObject private var loginItem = LoginItemController.shared

    @State private var accessibilityOK = AXIsProcessTrusted()
    private let refreshTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    private var currentPack: Soundpack? {
        store.packs.first { $0.id == settings.selectedPackID } ?? store.packs.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if !accessibilityOK { permissionRow }
            volumeRow
            muteRow
            moreBlock
        }
        .frame(width: 268)
        .background(panel)
        .environment(\.colorScheme, .light)
        .onAppear {
            accessibilityOK = AXIsProcessTrusted()
            loginItem.refresh()
        }
        .onReceive(refreshTimer) { _ in
            accessibilityOK = AXIsProcessTrusted()
            loginItem.refresh()
        }

    }

    private var panel: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
            )
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("Plip")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ink)
            Spacer(minLength: 8)
            Menu {
                ForEach(store.packs, id: \.id) { pack in
                    Button(pack.manifest.name) {
                        SoundEngine.shared.selectPack(id: pack.id)
                        SoundEngine.shared.preview()
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(currentPack?.manifest.name ?? "无音效")
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ink)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.06), in: Capsule())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(store.packs.isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var ink: Color { Color(white: 0.12) }
    private var quiet: Color { Color(white: 0.38) }

    private var permissionRow: some View {
        Button(action: openAccessibility) {
            HStack {
                Text("打开辅助功能")
                Spacer()
                Image(systemName: "arrow.up.right")
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(Color(red: 0.95, green: 0.45, blue: 0.28))
        }
        .buttonStyle(.plain)
    }

    private var volumeRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "speaker.fill")
                .font(.system(size: 10))
                .foregroundStyle(quiet)
            Slider(value: $settings.masterVolume, in: 0...1)
                .controlSize(.small)
                .tint(Color(red: 0.18, green: 0.45, blue: 0.95))
            Text("\(Int(settings.masterVolume * 100))")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(ink)
                .lineLimit(1)
                .frame(width: 36, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var muteRow: some View {
        HStack {
            Text("静音")
                .font(.system(size: 13))
                .foregroundStyle(ink)
            Text("⌥⇧M")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(ink)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            Spacer()
            Toggle("", isOn: $settings.muted)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private var moreBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            hairline
            toggleRow("连击升调", isOn: $settings.comboEnabled)
            toggleRow("通话时静音", isOn: $settings.smartMuteEnabled)
            if smartMute.isSuppressed, !smartMute.suppressReason.isEmpty {
                Text(smartMute.suppressReason)
                    .font(.system(size: 11))
                    .foregroundStyle(quiet)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
            }
            toggleRow("开机自启", isOn: Binding(
                get: { loginItem.state.isOn },
                set: { loginItem.setEnabled($0) }
            ))
            if let message = loginItem.state.message {
                VStack(alignment: .leading, spacing: 6) {
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(red: 0.72, green: 0.36, blue: 0.05))
                        .fixedSize(horizontal: false, vertical: true)
                    Button("打开登录项") { SMAppService.openSystemSettingsLoginItems() }
                        .font(.system(size: 11, weight: .medium))
                        .buttonStyle(.plain)
                        .foregroundStyle(ink)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            }
            appBlocklist
            rowButton("添加音效包", systemImage: "plus") {
                NotificationCenter.default.post(name: .plipImportPack, object: nil)
            }
            rowButton("退出", systemImage: "power", tint: Color(red: 0.78, green: 0.16, blue: 0.12)) {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private var hairline: some View {
        Rectangle().fill(Color.black.opacity(0.08)).frame(height: 1)
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(ink)
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
    }

    private func rowButton(_ title: String, systemImage: String, tint: Color = Color(white: 0.12), action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage).frame(width: 14)
                Text(title)
                Spacer()
            }
            .font(.system(size: 12))
            .foregroundStyle(tint)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var appBlocklist: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("这些应用在前台时静音")
                    .font(.system(size: 11))
                    .foregroundStyle(quiet)
                Spacer()
                Button(action: requestPickApp) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ink)
                        .frame(width: 22, height: 22)
                        .background(Color.black.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
            }
            if settings.blacklistedBundleIDs.isEmpty {
                Text("未添加")
                    .font(.system(size: 12))
                    .foregroundStyle(quiet)
            } else {
                ForEach(settings.blacklistedBundleIDs, id: \.self) { id in
                    appRow(id)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func appRow(_ bundleID: String) -> some View {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        let name = url.flatMap { FileManager.default.displayName(atPath: $0.path) } ?? bundleID
        return HStack(spacing: 8) {
            if let url {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 16, height: 16)
            }
            Text(name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ink)
                .lineLimit(1)
            Spacer(minLength: 4)
            Button {
                settings.blacklistedBundleIDs.removeAll { $0 == bundleID }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(quiet)
            }
            .buttonStyle(.plain)
        }
    }

    private func requestPickApp() {
        NotificationCenter.default.post(name: .plipPickApp, object: nil)
    }

    private func openAccessibility() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

}

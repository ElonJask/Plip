import Cocoa
import CraftAudioCore
import SwiftUI

/// 菜单栏弹出层。不用 NSPopover，否则系统会在深色面板外面再铺一块毛玻璃。
final class StatusBarController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let panel = PlipPanel()
    private var pickingApp = false
    private let host: FittingHost<SettingsView>
    private var outsideMonitor: Any?

    override init() {
        host = FittingHost(rootView: SettingsView())
        super.init()
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "speaker.wave.2.fill",
                                   accessibilityDescription: "Plip")
            button.action = #selector(toggle)
            button.target = self
        }
        host.sizingOptions = [.intrinsicContentSize]
        host.onSizeChange = { [weak self] size in
            self?.resize(to: size)
        }
        panel.contentView = host
        panel.appearance = NSAppearance(named: .aqua)
        panel.backgroundColor = .clear
        updateIcon()
        NotificationCenter.default.addObserver(
            self, selector: #selector(muteChanged),
            name: .plipMuteChanged, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(pickAppRequested),
            name: .plipPickApp, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(importPackRequested),
            name: .plipImportPack, object: nil)
    }

    @objc private func toggle() {
        if panel.isVisible {
            close()
        } else {
            open()
        }
    }

    private func open() {
        guard let button = item.button, let window = button.window else { return }
        let size = host.fittingSize
        panel.setContentSize(size)
        let buttonOnScreen = window.convertToScreen(button.convert(button.bounds, to: nil))
        let origin = NSPoint(x: buttonOnScreen.midX - size.width / 2,
                             y: buttonOnScreen.minY - size.height - 6)
        panel.setFrameOrigin(origin)
        panel.makeKeyAndOrderFront(nil)
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closeIfClickedOutside()
        }
    }

    private func closeIfClickedOutside() {
        guard let button = item.button, let window = button.window else {
            close()
            return
        }
        let buttonOnScreen = window.convertToScreen(button.convert(button.bounds, to: nil))
        if pickingApp || buttonOnScreen.contains(NSEvent.mouseLocation) { return }
        close()
    }

    private func close() {
        if let outsideMonitor {
            NSEvent.removeMonitor(outsideMonitor)
            self.outsideMonitor = nil
        }
        panel.orderOut(nil)
    }

    private func resize(to size: NSSize) {
        guard panel.isVisible, abs(panel.frame.width - size.width) > 1 || abs(panel.frame.height - size.height) > 1 else { return }
        var frame = panel.frame
        let delta = size.height - frame.height
        frame.size = size
        frame.origin.y -= delta
        panel.setFrame(frame, display: true)
    }

    @objc private func pickAppRequested() { pickApp() }

    @objc private func importPackRequested() { importPack() }

    private func importPack() {
        pickingApp = true
        defer { pickingApp = false }
        let chooser = NSOpenPanel()
        chooser.allowedContentTypes = [.audio, .wav, .mp3, .aiff, .folder]
        chooser.allowsMultipleSelection = true
        chooser.canChooseDirectories = true
        chooser.canChooseFiles = true
        chooser.prompt = "添加"
        chooser.message = "选择音频文件，或包含 manifest.json 的音效包文件夹"
        guard chooser.runModal() == .OK else { return }
        guard let id = try? SoundpackStore.shared.importSelection(chooser.urls), !id.isEmpty else { return }
        SoundEngine.shared.selectPack(id: id)
        SoundEngine.shared.preview()
    }

    private func pickApp() {
        pickingApp = true
        defer { pickingApp = false }
        let chooser = NSOpenPanel()
        chooser.allowedContentTypes = [.application]
        chooser.allowsMultipleSelection = false
        chooser.canChooseDirectories = false
        chooser.canChooseFiles = true
        chooser.directoryURL = URL(fileURLWithPath: "/Applications")
        chooser.prompt = "添加"
        chooser.message = "选择需要在前台时静音的应用"
        guard chooser.runModal() == .OK, let url = chooser.url,
              let id = Bundle(url: url)?.bundleIdentifier else { return }
        if !Settings.shared.blacklistedBundleIDs.contains(id) {
            Settings.shared.blacklistedBundleIDs.append(id)
        }
    }

    @objc private func muteChanged() { updateIcon() }

    private func updateIcon() {
        let name = Settings.shared.muted ? "speaker.slash" : "speaker.wave.2.fill"
        guard item.button?.image?.name() != name else { return }
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Plip")
        image?.setName(name)
        item.button?.image = image
    }
}

private final class PlipPanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 268, height: 160),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: true)
        isFloatingPanel = true
        level = .statusBar
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }
}

private final class FittingHost<Content: View>: NSHostingView<Content> {
    var onSizeChange: ((NSSize) -> Void)?

    override func layout() {
        super.layout()
        onSizeChange?(fittingSize)
    }
}

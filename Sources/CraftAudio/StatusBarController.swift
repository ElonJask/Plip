import Cocoa
import Combine
import CraftAudioCore
import ServiceManagement
import WebKit

/// 菜单栏弹出层。面板是 `ui/panel.html`，和 Windows 用同一份。
final class StatusBarController: NSObject, WKScriptMessageHandler {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let panel = PlipPanel()
    private let web = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
    private var pickingApp = false
    private var outsideMonitor: Any?
    private var subscriptions = Set<AnyCancellable>()

    override init() {
        super.init()
        web.configuration.userContentController.add(self, name: "plip")
        let bootstrap = """
        window.plip = new Proxy({}, { get: (_, name) => (value) =>
          window.webkit.messageHandlers.plip.postMessage({ action: name, value }) });
        """
        web.configuration.userContentController.addUserScript(
            WKUserScript(source: bootstrap, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        web.setValue(false, forKey: "drawsBackground")
        web.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = web
        panel.backgroundColor = .clear
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: "Plip")
            button.action = #selector(toggle)
            button.target = self
        }
        loadPanel()
        updateIcon()
        NotificationCenter.default.addObserver(self, selector: #selector(muteChanged), name: .plipMuteChanged, object: nil)
        Settings.shared.objectWillChange.merge(with: SoundpackStore.shared.objectWillChange)
            .merge(with: SmartMute.shared.objectWillChange)
            .merge(with: LoginItemController.shared.objectWillChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.publishSoon() }
            .store(in: &subscriptions)
    }

    private func loadPanel() {
        let url = Bundle.main.resourceURL?.appendingPathComponent("panel.html")
            ?? URL(fileURLWithPath: "ui/panel.html")
        web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let action = body["action"] as? String else { return }
        switch action {
        case "ready", "resize":
            if action == "resize", let height = body["value"] as? Double {
                resize(height: height)
            }
            if action == "ready" { publish() }
        case "setVolume": Settings.shared.masterVolume = body["value"] as? Double ?? Settings.shared.masterVolume
        case "setMuted": Settings.shared.muted = body["value"] as? Bool ?? Settings.shared.muted
        case "setCombo": Settings.shared.comboEnabled = body["value"] as? Bool ?? Settings.shared.comboEnabled
        case "setSmartMute": Settings.shared.smartMuteEnabled = body["value"] as? Bool ?? Settings.shared.smartMuteEnabled
        case "setLogin": LoginItemController.shared.setEnabled(body["value"] as? Bool ?? false)
        case "selectPack":
            if let id = body["value"] as? String {
                SoundEngine.shared.selectPack(id: id)
                SoundEngine.shared.preview()
            }
        case "removeApp":
            if let id = body["value"] as? String {
                Settings.shared.blacklistedBundleIDs.removeAll { $0 == id }
            }
        case "openAccessibility": openAccessibility()
        case "openLogin": SMAppService.openSystemSettingsLoginItems()
        case "pickApp": pickApp()
        case "importPack": importPack()
        case "quit": NSApplication.shared.terminate(nil)
        default: break
        }
    }

    private func publishSoon() {
        DispatchQueue.main.async { [weak self] in self?.publish() }
    }

    private func publish() {
        let settings = Settings.shared
        let packs = SoundpackStore.shared.packs
        let current = packs.first { $0.id == settings.selectedPackID } ?? packs.first
        let apps = settings.blacklistedBundleIDs.map { id -> [String: String] in
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
            let name = url.flatMap { FileManager.default.displayName(atPath: $0.path) } ?? id
            return ["id": id, "name": name]
        }
        let state: [String: Any] = [
            "packName": current?.manifest.name ?? "无音效",
            "packID": current?.id ?? "",
            "packs": packs.map { ["id": $0.id, "name": $0.manifest.name] },
            "volume": settings.masterVolume,
            "muted": settings.muted,
            "combo": settings.comboEnabled,
            "smartMute": settings.smartMuteEnabled,
            "accessibility": AXIsProcessTrusted(),
            "suppressReason": SmartMute.shared.isSuppressed ? SmartMute.shared.suppressReason : "",
            "login": LoginItemController.shared.state.isOn,
            "loginMessage": LoginItemController.shared.state.message ?? "",
            "apps": apps
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: state),
              let json = String(data: data, encoding: .utf8) else { return }
        web.evaluateJavaScript("plipRender(\(json))", completionHandler: nil)
    }

    @objc private func toggle() {
        panel.isVisible ? close() : open()
    }

    private func open() {
        guard let button = item.button, let window = button.window else { return }
        publish()
        let size = panel.frame.size
        let buttonOnScreen = window.convertToScreen(button.convert(button.bounds, to: nil))
        panel.setFrameOrigin(NSPoint(x: buttonOnScreen.midX - size.width / 2, y: buttonOnScreen.minY - size.height - 6))
        panel.makeKeyAndOrderFront(nil)
        if #available(macOS 14.0, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closeIfClickedOutside()
        }
    }

    private func closeIfClickedOutside() {
        guard let button = item.button, let window = button.window else { close(); return }
        let buttonOnScreen = window.convertToScreen(button.convert(button.bounds, to: nil))
        if pickingApp || buttonOnScreen.contains(NSEvent.mouseLocation) || panel.frame.contains(NSEvent.mouseLocation) { return }
        close()
    }

    private func close() {
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor); self.outsideMonitor = nil }
        panel.orderOut(nil)
    }

    private func resize(height: Double) {
        let next = NSSize(width: 268, height: max(160, height))
        guard abs(panel.frame.height - next.height) > 1 else { return }
        var frame = panel.frame
        frame.origin.y -= next.height - frame.height
        frame.size = next
        panel.setFrame(frame, display: true)
        web.frame = NSRect(origin: .zero, size: next)
    }

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
        publish()
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
        publish()
    }

    @objc private func muteChanged() { updateIcon(); publish() }

    private func updateIcon() {
        let name = Settings.shared.muted ? "speaker.slash" : "speaker.wave.2.fill"
        guard item.button?.image?.name() != name else { return }
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Plip")
        image?.setName(name)
        item.button?.image = image
    }

    private func openAccessibility() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}

private final class PlipPanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 268, height: 280),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .statusBar
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }
}

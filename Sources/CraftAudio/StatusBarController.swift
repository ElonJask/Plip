import Cocoa
import CraftAudioCore
import SwiftUI

/// 菜单栏托盘：点击展开设置 Popover
final class StatusBarController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()

    override init() {
        super.init()
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "speaker.wave.2.fill",
                                   accessibilityDescription: "Plip")
            button.action = #selector(togglePopover)
            button.target = self
        }
        popover.contentSize = NSSize(width: 320, height: 520)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: SettingsView())
        popover.delegate = self
    }

    @objc private func togglePopover() {
        guard let button = item.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // transient popover 需要激活一下才能拿到焦点
            if #available(macOS 14.0, *) {
                NSApp.activate()
            } else {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}

extension StatusBarController: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        NotificationCenter.default.post(name: .craftAudioCommitBlacklist, object: nil)
    }
}

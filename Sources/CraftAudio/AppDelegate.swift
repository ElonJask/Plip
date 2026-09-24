import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        SoundpackStore.shared.reload()
        AudioEngine.shared.start()
        SoundEngine.shared.configure()
        SmartMute.shared.start()
        HotkeyManager.shared.start()
        KeyListener.shared.start()
        statusBar = StatusBarController()
    }

    func applicationWillTerminate(_ notification: Notification) {
        KeyListener.shared.stop()
        HotkeyManager.shared.stop()
    }
}

import Cocoa

let app = NSApplication.shared
// 无 Dock 图标，纯菜单栏常驻
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()

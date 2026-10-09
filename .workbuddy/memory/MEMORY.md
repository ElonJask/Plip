# CraftAudio 项目记忆

## 项目定位
macOS 原生极轻量按键声引擎（菜单栏 App）：Minecraft 式打击感 + ASMR。目标：内存 <30MB、按键到发声 <8ms、零 Electron。

## 技术栈与约定
- SwiftPM executable + SwiftUI（Popover），macOS 13+，arm64。无 Xcode 工程文件。
- 低延迟核心：音效包加载时按 25 音分预渲染音高变体 Buffer，播放零实时 DSP；8 路 PlayerNode 轮转截尾音。
- 按键监听：CGEventTap listen-only（主 RunLoop），需辅助功能权限；只监听不吞键。
- 音效包 = 文件夹 + manifest.json（snake_case 字段）；内置包在 .app Resources/Soundpacks，用户包在 `~/Library/Application Support/CraftAudio/Soundpacks`。
- 键位名：default/space/return/backspace/forward_delete/shift/capslock/tab/escape。

## 构建
`bash Scripts/make_app.sh` → `artifacts/CraftAudio.app`（ad-hoc 签名）。swift build 必须带 `--disable-sandbox`（本机沙盒限制）。

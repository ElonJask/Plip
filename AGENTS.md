# Plip

菜单栏按键声。SwiftPM，最低 macOS 13。

- 可测试的规则在 `Sources/CraftAudioCore`：登录项状态、按键分发、连击、静音策略、音效包合并。菜单栏进程在 `Sources/CraftAudio`，只做采集和播放。
- 版本只写两处，且必须相同：`Info.plist` 的 `CFBundleShortVersionString` 和 `VERSION`。`Scripts/check_version.sh` 核对。
- 验证：`swift test --disable-sandbox`。macOS 打包：`bash Scripts/make_app.sh`。只编译当前机器的架构，签名失败会中止。产物在 `artifacts/Plip-macos-<arch>.app` 和 `artifacts/Plip-v<version>-macos-<arch>.zip`。发布时 `macos-latest` 打 arm64，`macos-26-intel` 打 x86_64。
- Windows 打包：`bash Scripts/make_windows.sh`，产物是 `artifacts/Plip-v<version>-windows-x64.zip`。发布作业必须检出仓库后再调用 `gh`，否则找不到 git 目录。
- 开机自启用 `SMAppService.mainApp`。失败必须显示在面板上，不能用 `try?` 吞掉。Developer ID 与安装位置不在本仓库的自动流程里。
- 同名音效包以用户目录覆盖内置包。署名在 `Soundpacks/CREDITS.md`，新增包必须写进去。
- `Scripts/gen_sounds.py` 是已停用的占位音，输出到 `artifacts/deprecated-synth-packs/`，不要写回 `Soundpacks/`。

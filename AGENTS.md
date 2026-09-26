# Plip

菜单栏按键声。界面和按键声都在 Electron，同一份 `ui/panel.html` 给 macOS 与 Windows。

- 打包：`bash Scripts/make_electron.sh`。macOS 只打当前架构，Windows 在 Windows runner 上打。产物是 `artifacts/Plip-v<version>-macos-<arch>.zip` 和 `artifacts/Plip-v<version>-windows-x64.zip`。
- 版本写在 `VERSION` 和 `Info.plist`，`Scripts/check_version.sh` 核对。发布作业必须检出仓库后再调用 `gh`。
- `Sources/` 和 `windows/` 是旧实现，不再参与发布。
- 同名音效包以用户目录覆盖内置包。署名在 `Soundpacks/CREDITS.md`，新增包必须写进去。
- `Scripts/gen_sounds.py` 是已停用的占位音，输出到 `artifacts/deprecated-synth-packs/`，不要写回 `Soundpacks/`。

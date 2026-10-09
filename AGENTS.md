# Plip

菜单栏 / 通知区域按键声，仅 Electron 实现，macOS 与 Windows 共用同一份 `ui/panel.html`。

- 目录：`electron/` 主进程与测试，`ui/` 面板与播放窗口，`Soundpacks/` 内置音效，`Scripts/` 打包与素材脚本。
- 检查走本地，不依赖 GitHub 测试流水线：`bash Scripts/check.sh`（版本、语法、单元测试），`Scripts/install_hooks.sh` 启用 pre-push。新增 `*.test.js` 会被 `electron/run-tests.js` 自动执行。
- 图标：改 `Scripts/make_icons.py` 后重新生成 `electron/build/`，不要手改产物。托盘图标经 `extraResources` 放进 `tray/`。
- 打包：`bash Scripts/make_electron.sh`。macOS 只打当前架构，Windows 在 Windows runner 上打。产物是 `artifacts/Plip-v<version>-macos-<arch>.zip` 和 `artifacts/Plip-v<version>-windows-x64.zip`。
- 版本：`VERSION` 为唯一来源，`electron/package.json` 必须一致，`Scripts/check_version.sh` 核对。发布作业必须检出仓库后再调用 `gh`。
- 面板 DOM 的元素 ID 与 `electron/panel-ui.test.js` 相互依赖，改 `ui/panel.html` 时同步检查。
- 同名音效包以用户目录覆盖内置包。署名在 `Soundpacks/CREDITS.md`，新增包必须写进去。
- 打包文件清单在 `electron/package.json` 的 `build.files`，新增主进程模块要加进去。

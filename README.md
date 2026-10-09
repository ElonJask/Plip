# Plip

菜单栏 / 通知区域按键音效。无 Dock 图标，只监听按键，不拦截输入。

机械轴、方块脚步与冰雪音效均为开源录音，启动时解码进内存，按键时直接播放。

## 安装

从 [Releases](https://github.com/ElonJask/Plip/releases) 下载对应压缩包：

| 文件 | 系统 |
|---|---|
| `Plip-vX.Y.Z-macos-arm64.zip` | macOS 13+，Apple Silicon |
| `Plip-vX.Y.Z-macos-x86_64.zip` | macOS 13+，Intel |
| `Plip-vX.Y.Z-windows-x64.zip` | Windows 64 位 |

**macOS**：解压后将 `Plip.app` 移入「应用程序」，执行下面的命令移除下载隔离标记，再打开：

```bash
xattr -dr com.apple.quarantine /Applications/Plip.app
```

首次启动需要「辅助功能」权限（系统设置 → 隐私与安全性 → 辅助功能），仅用于监听按键。当前安装包未做 Developer ID 签名，因此系统可能拒绝登记「开机自启」，面板会显示原因并提供登录项入口。

**Windows**：解压后运行 `Plip.exe`，没有安装程序。图标位于任务栏通知区域，点击打开面板。

## 使用

- 面板：切换音效包、调节音量、静音、连击升调、开机自启、添加音效包。
- 静音快捷键：macOS `⌥⇧M`，Windows `Alt+Shift+M`。
- 通话时静音（仅 macOS）：Zoom、FaceTime、腾讯会议、Teams、Webex、钉钉、飞书位于前台时暂停按键声。

## 开发

需要 Node.js 20+。

```bash
cd electron
npm ci
npx electron .        # 直接运行
npm test              # 单元测试
```

打包当前系统（macOS 只打本机架构，Windows 在 Windows 上打），产物在 `artifacts/`：

```bash
bash Scripts/make_electron.sh
```

补充或更新开源音效素材：

```bash
python3 Scripts/fetch_open_packs.py
```

目录结构：

| 路径 | 作用 |
|---|---|
| `electron/` | 主进程、预加载脚本与单元测试 |
| `ui/` | 面板（`panel.html`、`panel-ui.js`）与隐藏播放窗口（`player.html`、`player-engine.js`） |
| `Soundpacks/` | 内置音效包，署名见 `CREDITS.md` |
| `Scripts/` | 打包、版本核对、素材获取 |

## 发布

`VERSION` 是版本的唯一来源，`electron/package.json` 的 `version` 必须与之一致，`Scripts/check_version.sh` 负责核对。更新两处版本后推送同版本标签：

```bash
git tag vX.Y.Z && git push origin vX.Y.Z
```

GitHub Actions 会分别在 Apple Silicon、Intel 和 Windows runner 上打包，并创建 Release。

## 音效包

机械轴录音来自 [kbsim](https://github.com/tplai/kbsim)（MIT，Thomas Lai）。方块与冰雪录音来自 [minetest_game](https://github.com/luanti-org/minetest_game)（CC BY-SA 3.0）。未使用 Minecraft 原版音效。署名见 `Soundpacks/CREDITS.md`。

| 标识 | 内容 |
|---|---|
| real-mx-blue | Cherry MX 青轴 |
| real-mx-brown | Cherry MX 茶轴 |
| real-mx-black | Cherry MX 黑轴 |
| real-box-navy | Box Navy |
| real-holy-panda | Holy Panda |
| real-alpaca | Alpaca |
| real-cream | Cream |
| real-topre | Topre |
| real-model-m | IBM Model M |
| real-blue-alps | Alps 蓝轴 |
| real-mc-steps | 草地、泥土、木板、沙子、雪 |
| real-mc-stone | 石头、金属、玻璃 |
| real-ice-snow | 冰、雪、水 |

空格、回车与退格在多数音效包中使用独立录音。连击升调由音效包配置决定，停顿后清零。每次按键在设定范围内随机偏移音高。

面板中的「添加音效包」可选择一个或多个音频文件，或一个文件夹。支持 wav、aiff、caf、mp3、m4a。文件名包含 space、enter、return、backspace 时，分别映射到对应按键，其余文件作为默认按键。已包含 `manifest.json` 的文件夹按原配置导入。

导入结果保存在用户数据目录的 `Soundpacks/` 下（macOS：`~/Library/Application Support/Plip/`，Windows：`%APPDATA%\Plip\`）。同名音效包以用户目录为准。也可直接在该目录放置如下结构：

```json
{
  "name": "My Pack",
  "version": "1.0.0",
  "author": "You",
  "rules": {
    "pitch_jitter": 0.04,
    "combo_enabled": true,
    "combo_pitch_step": 0.35,
    "combo_timeout_ms": 500,
    "combo_max_steps": 16
  },
  "key_mappings": {
    "default": { "files": ["pop_1.wav", "pop_2.wav"], "volume": 0.8 },
    "space": { "files": ["place.wav"], "volume": 0.9 },
    "return": { "files": ["enter.wav"], "volume": 1.0 },
    "backspace": { "files": ["back.wav"], "volume": 0.7 }
  }
}
```

其余键位名：`forward_delete`、`shift`、`capslock`、`tab`、`escape`。未单独配置的按键使用 `default`。`pitch_jitter` 与 `combo_pitch_step` 的单位为半音。

## 行为

按键监听使用 CGEventTap，只监听，不拦截。`StrikeSession` 决定音频文件、音高与音量。`AudioEngine` 以 8 路播放器轮换播放，连续输入时截断最早的尾音。

通话类应用在前台时，可选择自动静音。后台听写不触发静音。

规则代码位于 `Sources/CraftAudioCore`，菜单栏界面位于 `Sources/CraftAudio`。版本同时记录在 `VERSION` 与 `Info.plist`，由 `Scripts/check_version.sh` 核对。

## 平台

macOS 需要 13 及以上。Windows 包为 64 位，解压后直接运行，没有安装程序。

## 许可

代码采用 MIT 许可，见 `LICENSE`。音效许可见 `Soundpacks/CREDITS.md`。CC BY-SA 素材再分发时须保留署名，并以相同许可共享。

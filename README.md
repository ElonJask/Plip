<p align="center">
  <img src="electron/build/icon.png" width="128" alt="Plip">
</p>

<h1 align="center">Plip</h1>

<p align="center">键盘按键声，常驻菜单栏与通知区域。</p>

<p align="center">
  <a href="https://github.com/ElonJask/Plip/releases">下载</a> ·
  <a href="#音效包">音效包</a> ·
  <a href="#开发">开发</a>
</p>

---

- 全局生效，只监听按键，不拦截输入
- 13 套真实录音：机械轴、方块脚步、冰雪
- 连击升调，每次敲击音高轻微随机
- 通话应用在前台时自动静音（macOS）
- 支持导入自己的音频或音效包

## 安装

从 [Releases](https://github.com/ElonJask/Plip/releases) 下载：

| 平台 | 文件 |
|---|---|
| macOS 13+，Apple Silicon | `Plip-vX.Y.Z-macos-arm64.zip` |
| macOS 13+，Intel | `Plip-vX.Y.Z-macos-x86_64.zip` |
| Windows 64 位 | `Plip-vX.Y.Z-windows-x64.zip` |

**macOS**　解压后将 `Plip.app` 移入「应用程序」，移除隔离标记后打开：

```bash
xattr -dr com.apple.quarantine /Applications/Plip.app
```

首次启动需在「系统设置 → 隐私与安全性 → 辅助功能」中允许 Plip，授权后自动生效。安装包未经 Developer ID 签名，系统可能拒绝登记开机自启，面板会给出原因。

**Windows**　解压后运行 `Plip.exe`，无需安装。

## 使用

点击菜单栏（Windows 为通知区域）图标打开面板，右键打开快捷菜单。

| 功能 | 说明 |
|---|---|
| 音效包 | 切换当前音效 |
| 音量 | 0–100 |
| 静音 | macOS `⌥⇧M`，Windows `Alt+Shift+M` |
| 连击升调 | 连续敲击时音调逐渐升高，停顿后复位 |
| 通话时静音 | Zoom、FaceTime、腾讯会议、Teams、Webex、钉钉、飞书位于前台时暂停（仅 macOS） |
| 开机自启 | 登录时自动启动 |
| 添加音效包 | 导入音频文件或文件夹 |

## 音效包

内置 13 套，均为开源录音。

| 标识 | 内容 |
|---|---|
| `real-mx-blue` `real-mx-brown` `real-mx-black` | Cherry MX 青轴、茶轴、黑轴 |
| `real-box-navy` `real-holy-panda` `real-alpaca` | Box Navy、Holy Panda、Alpaca |
| `real-cream` `real-topre` `real-model-m` `real-blue-alps` | Cream、Topre、IBM Model M、Alps 蓝轴 |
| `real-mc-steps` `real-mc-stone` `real-ice-snow` | 方块脚步、硬质方块、冰雪与水 |

### 导入

面板中选择「添加音效包」，可选一个或多个音频文件，或一个文件夹。支持 `wav` `aiff` `caf` `mp3` `m4a`。

- 文件名含 `space`、`enter`、`return`、`backspace` 的分别对应空格、回车、退格，其余作为默认按键
- 含 `manifest.json` 的文件夹按原配置导入

### 自定义

在用户目录的 `Soundpacks/` 下新建文件夹，放入音频与 `manifest.json`。同名音效包以用户目录为准。

| 系统 | 位置 |
|---|---|
| macOS | `~/Library/Application Support/Plip/Soundpacks/` |
| Windows | `%APPDATA%\Plip\Soundpacks\` |

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
    "default":   { "files": ["pop_1.wav", "pop_2.wav"], "volume": 0.8 },
    "space":     { "files": ["place.wav"], "volume": 0.9 },
    "return":    { "files": ["enter.wav"], "volume": 1.0 },
    "backspace": { "files": ["back.wav"], "volume": 0.7 }
  }
}
```

可用键位：`default` `space` `return` `backspace` `forward_delete` `shift` `capslock` `tab` `escape`。未配置的按键使用 `default`。`pitch_jitter` 与 `combo_pitch_step` 的单位为半音，时间单位为毫秒。

## 开发

需要 Node.js 20+。

```bash
cd electron
npm ci
npx electron .
```

| 命令 | 作用 |
|---|---|
| `bash Scripts/check.sh` | 版本核对、语法检查、单元测试 |
| `bash Scripts/install_hooks.sh` | 启用推送前自动检查 |
| `bash Scripts/make_electron.sh` | 打包当前系统，产物在 `artifacts/` |
| `python3 Scripts/make_icons.py` | 重新生成图标（需要 Pillow） |
| `python3 Scripts/fetch_open_packs.py` | 获取并转换开源音效素材（需要 ffmpeg） |

macOS 只打当前架构，Windows 包在 Windows 上打。

### 结构

| 路径 | 作用 |
|---|---|
| `electron/` | 主进程、预加载脚本、单元测试 |
| `electron/build/` | 应用与托盘图标 |
| `ui/` | 面板与隐藏的播放窗口 |
| `Soundpacks/` | 内置音效包，署名见 `CREDITS.md` |
| `Scripts/` | 检查、打包、图标、素材 |

### 原理

按键由 `uiohook-napi` 全局监听。主进程根据音效包规则决定文件、音高与音量，交给隐藏窗口用 Web Audio 播放。音频启动时解码进内存，同时最多 32 路发声，超出时淡出最早的一路。

### 发布

`VERSION` 是版本的唯一来源，`electron/package.json` 须与之一致。更新后推送同版本标签，GitHub Actions 会分别打包 Apple Silicon、Intel 与 Windows 并创建 Release：

```bash
git tag vX.Y.Z && git push origin vX.Y.Z
```

## 许可

代码采用 [MIT](LICENSE)。

音效来自开源项目：

- 机械轴录音：[kbsim](https://github.com/tplai/kbsim)，MIT，Thomas Lai
- 方块与冰雪录音：[minetest_game](https://github.com/luanti-org/minetest_game)，CC BY-SA 3.0

再分发 CC BY-SA 素材须保留署名并以相同许可共享。完整署名见 [`Soundpacks/CREDITS.md`](Soundpacks/CREDITS.md)。

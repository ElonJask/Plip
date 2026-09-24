# Plip

macOS 菜单栏按键音效。无 Dock 图标，不拦截键盘输入。

机械轴、方块脚步与冰雪音效均为开源录音。音频在加载时预渲染为不同音高，按键时直接播放。

系统要求：macOS 13 及以上。

## 安装

从 [Releases](https://github.com/ElonJask/Plip/releases) 下载对应压缩包：

| 文件 | 系统 |
|---|---|
| `Plip-vX.Y.Z-macos-arm64.zip` | Apple Silicon |
| `Plip-vX.Y.Z-macos-x86_64.zip` | Intel |
| `Plip-vX.Y.Z-windows-x64.zip` | Windows 64 位 |

解压后将 `Plip.app` 移入「应用程序」。推送与 `VERSION` 一致的标签 `vX.Y.Z` 后，GitHub Actions 会分别编译这三个安装包并发布。

Windows 解压后运行 `Plip/Plip.exe`。图标出现在任务栏通知区域，左键或右键打开菜单。`Alt+Shift+M` 静音。

首次启动需要「辅助功能」权限，仅用于监听按键。当前安装包为临时签名。移入「应用程序」后执行：

```bash
xattr -dr com.apple.quarantine /Applications/Plip.app
```

该命令移除下载隔离标记，用于跳过「无法验证开发者」的拦截。开机自启使用系统登录项，需要 Developer ID 签名，且应用必须位于 `/Applications/Plip.app`。当前安装包是临时签名，勾选后面板会显示系统拒绝的原因。

面板提供音效包、音量与静音。静音快捷键为 ⌥⇧M。

开机自启若被系统要求确认，面板会显示原因并提供「登录项」入口。

## 构建

```bash
python3 Scripts/fetch_open_packs.py
bash Scripts/make_app.sh
open "artifacts/Plip-macos-$(uname -m).app"
```

macOS 打包只使用当前机器的架构。Apple Silicon、Intel 与 Windows 安装包由 GitHub Actions 分别在对应的 runner 上编译。Windows 包也可在本机交叉编译：

```bash
bash Scripts/make_windows.sh
```

仓库已包含音效包时，可跳过第一步。`make_app.sh` 依次执行测试、版本核对与签名，签名失败即停止。单独测试：

```bash
swift test --disable-sandbox
```

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

导入结果保存在 `~/Library/Application Support/Plip/Soundpacks/`。也可直接在该目录放置如下结构：

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

通话类应用占用麦克风，或当前前台应用正在使用麦克风时，自动静音。后台听写不触发静音。前台应用名单通过面板中的加号从已安装应用里选择。

规则代码位于 `Sources/CraftAudioCore`，菜单栏界面位于 `Sources/CraftAudio`。版本同时记录在 `VERSION` 与 `Info.plist`，由 `Scripts/check_version.sh` 核对。

## 平台

macOS 需要 13 及以上。Windows 包为 64 位，解压后直接运行，没有安装程序。

## 许可

代码采用 MIT 许可，见 `LICENSE`。音效许可见 `Soundpacks/CREDITS.md`。CC BY-SA 素材再分发时须保留署名，并以相同许可共享。

# Plip

macOS 菜单栏里的按键声。敲下去有声音，不占 Dock，也不改你的输入。

机械轴用的是真实录音。方块脚步、放置和冰雪也是开源游戏里的真实录音，不是合成的哔哔声。音效在加载时做成不同音高的缓冲，敲击时直接播放。

需要 macOS 13 或更新版本。

## 安装

从 [Releases](https://github.com/ElonJask/Plip/releases) 下载 `Plip.app`，放进「应用程序」，双击打开。

第一次打开会要「辅助功能」权限。Plip 只听按键，不拦截。系统设置里如果提示已损坏，是因为发布包目前用的是本机临时签名，到应用上右键打开一次即可。用 Developer ID 签名后，开机自启才能在登录时真正启动。

面板里可以换音效包、调音量、静音。⌥⇧M 也能静音，不管当前焦点在不在 Plip 上。

勾选开机自启后，如果系统还要你点允许，面板会写出原因，并打开「登录项」设置。失败不会被悄悄丢掉。

## 自己编译

```bash
python3 Scripts/fetch_open_packs.py   # 音效包已在仓库里时可以跳过
bash Scripts/make_app.sh
open artifacts/Plip.app
```

`make_app.sh` 会先跑测试、核对版本，再签名。签名失败就停，不会留一个签坏的包。`swift test --disable-sandbox` 可以单独跑测试。

## 音效包

十个机械轴来自 [kbsim](https://github.com/tplai/kbsim)（MIT，Thomas Lai）。三个方块世界来自 [minetest_game](https://github.com/luanti-org/minetest_game)（CC BY-SA 3.0）。Minecraft 原版音效没有用。署名在 `Soundpacks/CREDITS.md`。

| 包 | 听感 |
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
| real-ice-snow | 冰、雪、水花 |

空格、回车、退格在多数包里有单独的录音。连击升调只在音效包自己打开这项时才累加，停顿后清零。每次敲击还会在很小的音高范围内抖动，避免连敲听起来像同一声。

自己的包放在 `~/Library/Application Support/Plip/Soundpacks/`，面板里有按钮直接打开这个目录。文件夹名和内置包一样时，用你的那份，选择器里只出现一次。

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

键位名还有 `forward_delete`、`shift`、`capslock`、`tab`、`escape`。没有单独录音的键会回到 `default`。`pitch_jitter` 和 `combo_pitch_step` 的单位是半音。

## 它怎么工作

按键从只听不拦的 CGEventTap 进来。`StrikeSession` 决定这次发哪一个文件、音高和音量。`AudioEngine` 用 8 路播放器轮流放，打得快时最老的尾音会被截掉。

通话应用，或者你正在输入的那个应用自己打开了麦克风，会自动静音。后台的听写不会。前台应用也可以写进黑名单。黑名单在回车或关掉面板时保存。

可测试的规则在 `Sources/CraftAudioCore`。菜单栏进程在 `Sources/CraftAudio`。版本写在 `VERSION` 和 `Info.plist`，两处必须一样，`Scripts/check_version.sh` 会核对。

## 许可

代码是 MIT，见 `LICENSE`。音效包各自的许可见 `Soundpacks/CREDITS.md`，CC BY-SA 的部分再分发时要保留署名，并以同样方式共享。

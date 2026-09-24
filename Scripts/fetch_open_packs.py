#!/usr/bin/env python3
"""从开源项目抓取「真实录音」音效并生成 Plip 音效包。

音源：
  1. tplai/kbsim (MIT)            —— 13 种真实机械轴体按键录音（press/release 分离）
  2. luanti-org/minetest_game (CC BY-SA 3.0) —— 开源版 Minecraft 的脚步/放置/挖掘/破坏录音

处理：ffmpeg 解码 -> 去除首尾静音 -> 单声道 44.1kHz 16-bit -> 峰值归一化
"""
import json
import os
import shutil
import struct
import subprocess
import urllib.error
import urllib.request
import wave

FFMPEG = "/opt/homebrew/bin/ffmpeg"
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, ".."))
PACKS_DIR = os.path.join(ROOT, "Soundpacks")
CACHE_DIR = os.path.join(ROOT, ".cache", "audio")

# 钉在提交上，不用 master。升级素材时改这两个 SHA，并核对 CREDITS。
KBSIM_SHA = "ba103f3b0afa9dab80447aa2e7e2ed80b6bd80e4"
MINETEST_SHA = "c42e4d0c0ff9d27ff7b9b308c3cfc14098dd3a0f"
KBSIM = "https://raw.githubusercontent.com/tplai/kbsim/" + KBSIM_SHA + "/src/assets/audio/{sw}/press/{f}.mp3"
MINETEST = "https://raw.githubusercontent.com/luanti-org/minetest_game/" + MINETEST_SHA + "/mods/default/sounds/default_{f}.ogg"

# (包 id, 显示名, kbsim 轴体目录, 连击参数)
KEYBOARD_PACKS = [
    ("real-mx-blue", "Cherry MX 青轴·真实录音", "mxblue", None),
    ("real-mx-brown", "Cherry MX 茶轴·真实录音", "mxbrown", None),
    ("real-mx-black", "Cherry MX 黑轴·真实录音", "mxblack", None),
    ("real-box-navy", "Box Navy 厚实 Thock", "boxnavy", None),
    ("real-holy-panda", "Holy Panda 麻将音", "holypanda", None),
    ("real-alpaca", "Alpaca 线性轻柔", "alpaca", {"step": 0.08, "timeout": 600, "max": 10}),
    ("real-cream", "Cream 奶油轴", "cream", None),
    ("real-topre", "Topre 静电容·柔和", "topre", None),
    ("real-model-m", "IBM Model M 屈曲弹簧", "buckling", None),
    ("real-blue-alps", "Alps 蓝轴·复古段落", "bluealps", None),
]

# 键位映射：kbsim 的 GENERIC_R0-R4 = 5 个随机变体
KBSIM_LAYOUT = {
    "default": ["GENERIC_R0", "GENERIC_R1", "GENERIC_R2", "GENERIC_R3", "GENERIC_R4"],
    "space": ["SPACE"],
    "return": ["ENTER"],
    "backspace": ["BACKSPACE"],
}
KBSIM_OUT_NAME = {"default": "key_{i}.wav", "space": "space.wav",
                  "return": "enter.wav", "backspace": "backspace.wav"}

# Minetest 音效 -> 两个包：柔和地表 / 硬质方块
MINETEST_SOFT = {
    "default": ["grass_footstep.1", "grass_footstep.2", "grass_footstep.3",
                "dirt_footstep.1", "dirt_footstep.2",
                "wood_footstep.1", "wood_footstep.2",
                "sand_footstep.1", "sand_footstep.2", "sand_footstep.3",
                "snow_footstep.1", "snow_footstep.2"],
    "space": ["place_node.1", "place_node.2"],
    "return": ["dug_node.1", "dug_node.2"],
    "backspace": ["dig_crumbly", "gravel_dig.1"],
}
MINETEST_HARD = {
    "default": ["hard_footstep.1", "hard_footstep.2", "hard_footstep.3",
                "gravel_footstep.1", "gravel_footstep.2", "gravel_footstep.3",
                "metal_footstep.1", "metal_footstep.2", "glass_footstep"],
    "space": ["place_node_hard.1", "place_node_hard.2"],
    "return": ["dug_node.1", "dug_node.2"],
    "backspace": ["dig_choppy.1", "dig_choppy.2", "dug_metal.1"],
}

# 冰雪 / 水花 ASMR
MINETEST_ICE = {
    "default": ["ice_footstep.1", "ice_footstep.2", "ice_footstep.3",
                "snow_footstep.3", "snow_footstep.4", "snow_footstep.5"],
    "space": ["water_footstep.1", "water_footstep.2"],
    "return": ["ice_dug"],
    "backspace": ["ice_dig.1", "ice_dig.2", "ice_dig.3"],
}

KBSIM_LICENSE = """kbsim — MIT License
Copyright (c) Thomas Lai
https://github.com/tplai/kbsim

Permission is hereby granted, free of charge, to any person obtaining a copy of this
software and associated documentation files (the "Software"), to deal in the Software
without restriction, including without limitation the rights to use, copy, modify,
merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to the following
conditions: The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.
"""

MINETEST_LICENSE = """minetest_game / Luanti — CC BY-SA 3.0
Copyright (C) 2010-2023 minetest_game contributors
https://github.com/luanti-org/minetest_game

音效素材（mods/default/sounds）采用 Creative Commons Attribution-ShareAlike 3.0 Unported。
你可以自由分享、改编（含商业用途），条件是保留署名，且改编后的素材需以相同协议分发。
本包仅做格式转换（OGG -> WAV）与首尾静音裁剪，未做其他修改。
"""


def log(msg):
    print(msg, flush=True)


def _http_code(url):
    r = subprocess.run(["curl", "-sSL", "--head", "-o", "/dev/null",
                        "-w", "%{http_code}", "-m", "20", url], capture_output=True, text=True)
    return r.stdout.strip()


def fetch(url, dest, attempts=3):
    """带缓存的下载（用 curl：在代理环境下比 urllib 稳）。
    源文件不存在(404) 返回 None —— 用于处理某些轴体缺 SPACE/ENTER 录音的情况。"""
    if os.path.exists(dest) and os.path.getsize(dest) > 0:
        return dest
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    tmp = dest + ".part"
    for i in range(attempts):
        r = subprocess.run(["curl", "-fsSL", "--retry", "2", "--retry-delay", "1",
                            "-m", "60", "-o", tmp, url], capture_output=True)
        if r.returncode == 0 and os.path.getsize(tmp) > 512:
            os.replace(tmp, dest)
            return dest
        if r.returncode == 22:  # HTTP >= 400
            if os.path.exists(tmp):
                os.remove(tmp)
            log("    [skip] 源文件不存在：%s" % url.rsplit("/", 1)[-1])
            return None
    if os.path.exists(tmp):
        os.remove(tmp)
    code = _http_code(url)
    if code == "404":
        log("    [skip] 源文件不存在：%s" % url.rsplit("/", 1)[-1])
        return None
    raise RuntimeError("下载失败 (http=%s): %s" % (code, url))


def to_wav(src, dest, peak=0.8, max_dur=None):
    """解码 -> 去首尾静音 -> 单声道 44.1k 16bit -> 峰值归一化 ->（可选）截断超长尾音"""
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    tmp = dest + ".tmp.wav"
    af = ",".join([
        "silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.005",
        "areverse",
        "silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.03",
        "areverse",
    ])
    subprocess.run([FFMPEG, "-y", "-hide_banner", "-loglevel", "error", "-i", src,
                    "-af", af, "-ac", "1", "-ar", "44100", "-sample_fmt", "s16", tmp],
                   check=True)
    with wave.open(tmp, "rb") as w:
        frames = w.readframes(w.getnframes())
    samples = list(struct.unpack("<%dh" % (len(frames) // 2), frames))
    if not samples:
        raise RuntimeError("empty audio: %s" % src)
    # 超长尾音截断 + 60ms 淡出（避免每次敲击拖一条长尾巴）
    if max_dur:
        cap = int(max_dur * 44100)
        if len(samples) > cap:
            fade = int(0.06 * 44100)
            samples = samples[:cap]
            for i in range(fade):
                idx = cap - fade + i
                samples[idx] = int(samples[idx] * (1 - i / fade))
    m = max(abs(v) for v in samples) or 1
    scale = (peak * 32767) / m
    out = [max(-32768, min(32767, int(v * scale))) for v in samples]
    with wave.open(dest, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(44100)
        w.writeframes(struct.pack("<%dh" % len(out), *out))
    os.remove(tmp)
    return len(out) / 44100.0


def write_manifest(pack_dir, name, author, files_map, combo=None, jitter=0.02):
    rules = {"pitch_jitter": jitter, "combo_enabled": bool(combo)}
    if combo:
        rules.update({
            "combo_pitch_step": combo["step"],
            "combo_timeout_ms": combo["timeout"],
            "combo_max_steps": combo["max"],
        })
    mappings = {}
    for key, files in files_map.items():
        if not files:
            continue  # 该键位没有录音则跳过（引擎会自动回落到 default）
        mappings[key] = {"files": files, "volume": 0.85 if key == "default" else 0.9}
    manifest = {
        "name": name,
        "version": "1.0.0",
        "author": author,
        "engine_version": "1",
        "rules": rules,
        "key_mappings": mappings,
    }
    with open(os.path.join(pack_dir, "manifest.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)


def build_keyboard_packs():
    count = 0
    for pack_id, display, sw, combo in KEYBOARD_PACKS:
        pack_dir = os.path.join(PACKS_DIR, pack_id)
        files_map = {}
        durations = []
        for key, srcs in KBSIM_LAYOUT.items():
            out_names = []
            for i, src in enumerate(srcs):
                url = KBSIM.format(sw=sw, f=src)
                cached = os.path.join(CACHE_DIR, "kbsim", sw, src + ".mp3")
                if fetch(url, cached) is None:
                    continue  # 该轴体没有这个键位的录音（如 mxblue 无 SPACE/ENTER）
                out_name = KBSIM_OUT_NAME[key]
                out_name = out_name.format(i=i + 1) if "{i}" in out_name else out_name
                to_wav(cached, os.path.join(pack_dir, out_name))
                out_names.append(out_name)
            files_map[key] = out_names
        write_manifest(pack_dir, display, "kbsim (MIT) — Thomas Lai", files_map, combo, jitter=0.015)
        with open(os.path.join(pack_dir, "LICENSE.txt"), "w", encoding="utf-8") as f:
            f.write(KBSIM_LICENSE)
        count += 1
        log("[ok] %-18s %s  默认键 %d 个变体" % (pack_id, display, len(files_map["default"])))
    return count


def build_minetest_packs():
    count = 0
    for pack_id, display, layout in [
        ("real-mc-steps", "Minecraft 脚步·柔和地表", MINETEST_SOFT),
        ("real-mc-stone", "Minecraft 脚步·硬质方块", MINETEST_HARD),
        ("real-ice-snow", "冰雪脆响·水花 ASMR", MINETEST_ICE),
    ]:
        pack_dir = os.path.join(PACKS_DIR, pack_id)
        files_map = {}
        for key, srcs in layout.items():
            out_names = []
            for src in srcs:
                cached = os.path.join(CACHE_DIR, "minetest", src + ".ogg")
                fetch(MINETEST.format(f=src), cached)
                out_name = src.replace(".", "_") + ".wav"
                to_wav(cached, os.path.join(pack_dir, out_name), peak=0.75, max_dur=0.55)
                out_names.append(out_name)
            files_map[key] = out_names
        write_manifest(pack_dir, display, "minetest_game / Luanti (CC BY-SA 3.0)",
                       files_map, combo=None, jitter=0.05)
        with open(os.path.join(pack_dir, "LICENSE.txt"), "w", encoding="utf-8") as f:
            f.write(MINETEST_LICENSE)
        count += 1
        log("[ok] %-18s %s  默认键 %d 个变体" % (pack_id, display, len(files_map["default"])))
    return count


def write_credits():
    text = """# 音效素材署名与授权（Soundpacks）

本目录下的音效包均来自**开源项目**的真实录音，非程序合成。

## kbsim（MIT License）
真实机械轴体按键录音，作者 Thomas Lai。
仓库：https://github.com/tplai/kbsim
- real-mx-blue / real-mx-brown / real-mx-black / real-box-navy / real-holy-panda
- real-alpaca / real-cream / real-topre / real-model-m / real-blue-alps

## minetest_game / Luanti（CC BY-SA 3.0）
开源版 Minecraft 的脚步、放置方块、挖掘与破坏方块音效。
仓库：https://github.com/luanti-org/minetest_game
- real-mc-steps / real-mc-stone / real-ice-snow

授权要点：署名 + 相同方式共享（改编后的音频需以 CC BY-SA 3.0 分发）。
本目录内素材仅做了 OGG→WAV 格式转换与首尾静音裁剪。

> Minecraft 原版音效版权归 Mojang/Microsoft 所有，未在本项目中使用。
"""
    with open(os.path.join(PACKS_DIR, "CREDITS.md"), "w", encoding="utf-8") as f:
        f.write(text)


def main():
    os.makedirs(CACHE_DIR, exist_ok=True)
    n = build_keyboard_packs()
    n += build_minetest_packs()
    write_credits()
    log("\n完成：%d 个真实录音音效包 -> %s" % (n, PACKS_DIR))


if __name__ == "__main__":
    main()

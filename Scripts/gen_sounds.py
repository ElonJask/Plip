#!/usr/bin/env python3
"""已停用的合成占位音。现行音效是 Soundpacks/ 里的真实录音。

输出到 Soundpacks/，会覆盖同名目录。只在需要重新生成占位音时手动运行。
"""
import json
import os

from recipes import (
    snd_block_break,
    snd_block_hit,
    snd_block_place,
    snd_blue_click,
    snd_bubble,
    snd_dig,
    snd_hat,
    snd_kick,
    snd_land,
    snd_level_up,
    snd_orb,
    snd_pop,
    snd_rain_double,
    snd_rain_drop,
    snd_rim,
    snd_snare,
    snd_step,
    snd_step_wood,
    snd_thock,
    snd_toggle_click,
    snd_tw_back,
    snd_tw_bell,
    snd_tw_clack
)
from wavutil import write_wav

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "artifacts", "deprecated-synth-packs")

# ---------- 音效包定义 ----------

PACKS = {
    "minecraft-pop": {
        "manifest": {
            "name": "Minecraft Pop（拾取风）",
            "version": "1.0.0",
            "author": "Plip",
            "engine_version": "1",
            "rules": {"pitch_jitter": 0.05, "combo_enabled": False},
            "key_mappings": {
                "default": {"files": ["pop_1.wav", "pop_2.wav"], "volume": 0.8},
                "space": {"files": ["block_place.wav"], "volume": 0.9},
                "return": {"files": ["level_up.wav"], "volume": 1.0},
                "backspace": {"files": ["block_hit.wav"], "volume": 0.7},
                "shift": {"files": ["toggle.wav"], "volume": 0.5},
                "capslock": {"files": ["toggle.wav"], "volume": 0.5},
            },
        },
        "sounds": {
            "pop_1.wav": lambda: snd_pop(500, 950),
            "pop_2.wav": lambda: snd_pop(460, 860, dur=60, tau=20),
            "block_place.wav": lambda: snd_block_place(),
            "level_up.wav": lambda: snd_level_up(),
            "block_hit.wav": lambda: snd_block_hit(),
            "toggle.wav": lambda: snd_toggle_click(),
        },
    },
    "minecraft-xp": {
        "manifest": {
            "name": "Minecraft XP（经验球连击）",
            "version": "1.0.0",
            "author": "Plip",
            "engine_version": "1",
            "rules": {
                "pitch_jitter": 0.03,
                "combo_enabled": True,
                "combo_pitch_step": 0.35,
                "combo_timeout_ms": 500,
                "combo_max_steps": 16,
            },
            "key_mappings": {
                "default": {"files": ["orb_1.wav", "orb_2.wav"], "volume": 0.75},
                "space": {"files": ["block_place.wav"], "volume": 0.85},
                "return": {"files": ["level_up.wav"], "volume": 1.0},
                "backspace": {"files": ["block_break.wav"], "volume": 0.7},
            },
        },
        "sounds": {
            "orb_1.wav": lambda: snd_orb(1350),
            "orb_2.wav": lambda: snd_orb(1275, dur=130, tau=42),
            "block_place.wav": lambda: snd_block_place(),
            "level_up.wav": lambda: snd_level_up(),
            "block_break.wav": lambda: snd_block_break(),
        },
    },
    "mahjong-thock": {
        "manifest": {
            "name": "Mahjong Thock（麻将音轴体）",
            "version": "1.0.0",
            "author": "Plip",
            "engine_version": "1",
            "rules": {"pitch_jitter": 0.03, "combo_enabled": False},
            "key_mappings": {
                "default": {"files": ["thock_1.wav", "thock_2.wav", "thock_3.wav"], "volume": 0.85},
                "space": {"files": ["space_thock.wav"], "volume": 0.95},
                "return": {"files": ["enter_thock.wav"], "volume": 0.95},
                "backspace": {"files": ["back_thock.wav"], "volume": 0.75},
            },
        },
        "sounds": {
            "thock_1.wav": lambda: snd_thock(190),
            "thock_2.wav": lambda: snd_thock(196),
            "thock_3.wav": lambda: snd_thock(182),
            "space_thock.wav": lambda: snd_thock(150, dur=110),
            "enter_thock.wav": lambda: snd_thock(212, dur=105),
            "back_thock.wav": lambda: snd_thock(168, dur=80, click_ms=6),
        },
    },
    "bubble-pop": {
        "manifest": {
            "name": "Bubble Pop（水泡 ASMR）",
            "version": "1.0.0",
            "author": "Plip",
            "engine_version": "1",
            "rules": {"pitch_jitter": 0.06, "combo_enabled": False},
            "key_mappings": {
                "default": {"files": ["bubble_1.wav", "bubble_2.wav", "bubble_3.wav"], "volume": 0.7},
                "space": {"files": ["bubble_space.wav"], "volume": 0.8},
                "return": {"files": ["bubble_1.wav"], "volume": 0.9},
                "backspace": {"files": ["bubble_3.wav"], "volume": 0.7},
            },
        },
        "sounds": {
            "bubble_1.wav": lambda: snd_bubble(650, 1250),
            "bubble_2.wav": lambda: snd_bubble(720, 1380, dur=65),
            "bubble_3.wav": lambda: snd_bubble(590, 1150, dur=75, tau=28),
            "bubble_space.wav": lambda: snd_bubble(300, 520, dur=90, tau=32),
        },
    },
    "minecraft-steps": {
        "manifest": {
            "name": "Minecraft 脚步（踏踏）",
            "version": "1.0.0",
            "author": "Plip",
            "engine_version": "1",
            "rules": {"pitch_jitter": 0.04, "combo_enabled": False},
            "key_mappings": {
                "default": {"files": ["step_grass.wav", "step_stone.wav", "step_wood.wav", "step_snow.wav"], "volume": 0.75},
                "space": {"files": ["land.wav"], "volume": 0.85},
                "return": {"files": ["level_up.wav"], "volume": 0.9},
                "backspace": {"files": ["dig.wav"], "volume": 0.7},
            },
        },
        "sounds": {
            "step_grass.wav": lambda: snd_step(700, 85, 0.5),
            "step_stone.wav": lambda: snd_step(3000, 170, 0.55, dur=70, tau=16),
            "step_wood.wav": lambda: snd_step_wood(),
            "step_snow.wav": lambda: snd_step(1000, 70, 0.3, dur=100, tau=32, crackle=True),
            "land.wav": lambda: snd_land(),
            "dig.wav": lambda: snd_dig(),
            "level_up.wav": lambda: snd_level_up(notes=(392, 523.25, 659.25), note_ms=100),
        },
    },
    "typewriter": {
        "manifest": {
            "name": "复古打字机（回车带铃）",
            "version": "1.0.0",
            "author": "Plip",
            "engine_version": "1",
            "rules": {"pitch_jitter": 0.015, "combo_enabled": False},
            "key_mappings": {
                "default": {"files": ["tw_1.wav", "tw_2.wav", "tw_3.wav"], "volume": 0.85},
                "space": {"files": ["tw_space.wav"], "volume": 0.9},
                "return": {"files": ["tw_bell.wav"], "volume": 1.0},
                "backspace": {"files": ["tw_back.wav"], "volume": 0.75},
            },
        },
        "sounds": {
            "tw_1.wav": lambda: snd_tw_clack(2100, 150),
            "tw_2.wav": lambda: snd_tw_clack(1950, 140),
            "tw_3.wav": lambda: snd_tw_clack(2250, 165),
            "tw_space.wav": lambda: snd_tw_clack(1600, 120),
            "tw_bell.wav": lambda: snd_tw_bell(),
            "tw_back.wav": lambda: snd_tw_back(),
        },
    },
    "mech-blue": {
        "manifest": {
            "name": "青轴机械键盘",
            "version": "1.0.0",
            "author": "Plip",
            "engine_version": "1",
            "rules": {"pitch_jitter": 0.02, "combo_enabled": False},
            "key_mappings": {
                "default": {"files": ["blue_1.wav", "blue_2.wav", "blue_3.wav"], "volume": 0.8},
                "space": {"files": ["blue_space.wav"], "volume": 0.9},
                "return": {"files": ["blue_enter.wav"], "volume": 0.85},
                "backspace": {"files": ["blue_back.wav"], "volume": 0.7},
            },
        },
        "sounds": {
            "blue_1.wav": lambda: snd_blue_click(300),
            "blue_2.wav": lambda: snd_blue_click(285),
            "blue_3.wav": lambda: snd_blue_click(315),
            "blue_space.wav": lambda: snd_blue_click(180),
            "blue_enter.wav": lambda: snd_blue_click(340),
            "blue_back.wav": lambda: snd_blue_click(260),
        },
    },
    "rain": {
        "manifest": {
            "name": "雨滴轻语（ASMR）",
            "version": "1.0.0",
            "author": "Plip",
            "engine_version": "1",
            "rules": {"pitch_jitter": 0.08, "combo_enabled": False},
            "key_mappings": {
                "default": {"files": ["drop_1.wav", "drop_2.wav", "drop_3.wav"], "volume": 0.6},
                "space": {"files": ["drop_low.wav"], "volume": 0.65},
                "return": {"files": ["drop_double.wav"], "volume": 0.7},
                "backspace": {"files": ["drop_mute.wav"], "volume": 0.55},
            },
        },
        "sounds": {
            "drop_1.wav": lambda: snd_rain_drop(1200),
            "drop_2.wav": lambda: snd_rain_drop(1450, dur=100, tau=38),
            "drop_3.wav": lambda: snd_rain_drop(980, dur=140, tau=55),
            "drop_low.wav": lambda: snd_rain_drop(420, dur=180, tau=70),
            "drop_double.wav": lambda: snd_rain_double(),
            "drop_mute.wav": lambda: snd_rain_drop(650, dur=90, tau=35),
        },
    },
    "drum-kit": {
        "manifest": {
            "name": "鼓点节拍（玩家向）",
            "version": "1.0.0",
            "author": "Plip",
            "engine_version": "1",
            "rules": {"pitch_jitter": 0.02, "combo_enabled": False},
            "key_mappings": {
                "default": {"files": ["hat_1.wav", "hat_2.wav"], "volume": 0.65},
                "space": {"files": ["kick.wav"], "volume": 0.95},
                "return": {"files": ["snare.wav"], "volume": 0.9},
                "backspace": {"files": ["rim.wav"], "volume": 0.7},
            },
        },
        "sounds": {
            "hat_1.wav": lambda: snd_hat(),
            "hat_2.wav": lambda: snd_hat(dur=40, tau=12),
            "kick.wav": lambda: snd_kick(),
            "snare.wav": lambda: snd_snare(),
            "rim.wav": lambda: snd_rim(),
        },
    },
}



def main():
    for pack_id, spec in PACKS.items():
        pack_dir = os.path.join(ROOT, pack_id)
        os.makedirs(pack_dir, exist_ok=True)
        for filename, gen in spec["sounds"].items():
            write_wav(os.path.join(pack_dir, filename), gen())
        with open(os.path.join(pack_dir, "manifest.json"), "w", encoding="utf-8") as f:
            json.dump(spec["manifest"], f, ensure_ascii=False, indent=2)
        print(f"[ok] {pack_id}: {len(spec['sounds'])} sounds")


if __name__ == "__main__":
    main()

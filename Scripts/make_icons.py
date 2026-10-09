#!/usr/bin/env python3
"""生成应用图标与托盘图标，输出到 electron/build/。

依赖 Pillow；.icns 由 macOS 自带的 iconutil 生成，不在 macOS 上时跳过 .icns。
图形：蓝色圆角方块 + 白色键帽 + 声波条，与面板头部的标志一致。
"""
import math
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

OUT = Path(__file__).resolve().parent.parent / "electron" / "build"
BLUE_TOP = (92, 182, 255)
BLUE_BOTTOM = (8, 92, 226)
BAR_TOP = (46, 143, 255)
BAR_BOTTOM = (10, 98, 232)
# 声波条高度占键帽内部高度的比例，中间最高
BARS = [0.30, 0.56, 0.84, 0.50, 0.24]


def squircle_mask(size, inset):
    """超椭圆（n=5），接近 macOS 图标轮廓。"""
    scale = 4
    big = size * scale
    r = (big - 2 * inset * scale) / 2
    c = big / 2
    pts = []
    for i in range(720):
        t = 2 * math.pi * i / 720
        cos, sin = math.cos(t), math.sin(t)
        x = c + r * math.copysign(abs(cos) ** (2 / 5), cos)
        y = c + r * math.copysign(abs(sin) ** (2 / 5), sin)
        pts.append((x, y))
    mask = Image.new("L", (big, big), 0)
    ImageDraw.Draw(mask).polygon(pts, fill=255)
    return mask.resize((size, size), Image.LANCZOS)


def vertical_gradient(size, top, bottom):
    ramp = Image.linear_gradient("L").resize(size)
    return Image.composite(
        Image.new("RGB", size, bottom), Image.new("RGB", size, top), ramp
    )


def rounded(draw, box, radius, fill):
    draw.rounded_rectangle(box, radius=radius, fill=fill)


def draw_bars(canvas, box, color_top, color_bottom, width, gap, heights, solid=None):
    """在 box 内居中绘制声波条。"""
    x0, y0, x1, y1 = box
    count = len(heights)
    total = count * width + (count - 1) * gap
    left = x0 + ((x1 - x0) - total) / 2
    cy = (y0 + y1) / 2
    inner = y1 - y0
    layer = Image.new("L", canvas.size, 0)
    d = ImageDraw.Draw(layer)
    for i, h in enumerate(heights):
        bar_h = inner * h
        x = left + i * (width + gap)
        d.rounded_rectangle(
            (x, cy - bar_h / 2, x + width, cy + bar_h / 2), radius=width / 2, fill=255
        )
    if solid:
        fill = Image.new("RGB", canvas.size, solid)
    else:
        fill = vertical_gradient(canvas.size, color_top, color_bottom)
    canvas.paste(fill, (0, 0), layer)


def full_icon(size=1024):
    """完整图标：渐变方块 + 键帽 + 声波条。"""
    s = size
    base = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    inset = round(s * 0.098)
    mask = squircle_mask(s, inset)
    body = vertical_gradient((s, s), BLUE_TOP, BLUE_BOTTOM).convert("RGBA")
    # 顶部高光
    glow = Image.new("RGBA", (s, s), (255, 255, 255, 0))
    ImageDraw.Draw(glow).ellipse(
        (s * 0.05, -s * 0.5, s * 0.95, s * 0.36), fill=(255, 255, 255, 44)
    )
    glow = glow.filter(ImageFilter.GaussianBlur(s * 0.05))
    body = Image.alpha_composite(body, glow)
    base.paste(body, (0, 0), mask)

    cap = round(s * 0.44)
    cx0 = (s - cap) // 2
    cy0 = round(s * 0.5 - cap / 2 - s * 0.012)
    box = (cx0, cy0, cx0 + cap, cy0 + cap)
    radius = round(cap * 0.22)

    shadow = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    off = round(s * 0.016)
    rounded(sd, (box[0], box[1] + off, box[2], box[3] + off), radius, (4, 40, 120, 110))
    shadow = shadow.filter(ImageFilter.GaussianBlur(s * 0.022))
    base = Image.alpha_composite(base, shadow)

    key = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    kmask = Image.new("L", (s, s), 0)
    ImageDraw.Draw(kmask).rounded_rectangle(box, radius=radius, fill=255)
    key_fill = vertical_gradient((s, s), (255, 255, 255), (222, 235, 255)).convert("RGBA")
    key.paste(key_fill, (0, 0), kmask)
    base = Image.alpha_composite(base, key)

    pad = round(cap * 0.2)
    inner = (cx0 + pad, cy0 + pad, cx0 + cap - pad, cy0 + cap - pad)
    rgb = base.convert("RGB")
    bw = round(cap * 0.092)
    draw_bars(rgb, inner, BAR_TOP, BAR_BOTTOM, bw, round(bw * 0.72), BARS)
    out = rgb.convert("RGBA")
    out.putalpha(base.getchannel("A"))
    return out


def small_icon(size=256):
    """小尺寸图标：去掉键帽，白色声波条直接放在渐变方块上，16 px 也清晰。"""
    s = size
    inset = round(s * 0.04)
    mask = squircle_mask(s, inset)
    base = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    base.paste(vertical_gradient((s, s), BLUE_TOP, BLUE_BOTTOM).convert("RGBA"), (0, 0), mask)
    rgb = base.convert("RGB")
    bw = round(s * 0.11)
    box = (s * 0.2, s * 0.2, s * 0.8, s * 0.8)
    draw_bars(rgb, box, None, None, bw, round(bw * 0.62), [0.32, 0.6, 0.95, 0.54, 0.26], solid=(255, 255, 255))
    out = rgb.convert("RGBA")
    out.putalpha(base.getchannel("A"))
    return out


def template_icon(px):
    """macOS 菜单栏模板图：纯黑 + 透明，系统会按明暗自动着色。"""
    scale = 16
    s = px * scale
    layer = Image.new("L", (s, s), 0)
    d = ImageDraw.Draw(layer)
    heights = [0.30, 0.56, 0.90, 0.48, 0.22]
    width = px * 0.15 * scale
    gap = px * 0.1 * scale
    total = 5 * width + 4 * gap
    left = (s - total) / 2
    for i, h in enumerate(heights):
        bh = px * 0.92 * h * scale
        x = left + i * (width + gap)
        d.rounded_rectangle((x, s / 2 - bh / 2, x + width, s / 2 + bh / 2), radius=width / 2, fill=255)
    layer = layer.resize((px, px), Image.LANCZOS)
    img = Image.new("RGBA", (px, px), (0, 0, 0, 0))
    img.putalpha(layer)
    return img


def save_icns(master):
    if sys.platform != "darwin" or not shutil.which("iconutil"):
        print("skip .icns (需要 macOS iconutil)")
        return
    with tempfile.TemporaryDirectory() as tmp:
        iconset = Path(tmp) / "Plip.iconset"
        iconset.mkdir()
        for base in (16, 32, 128, 256, 512):
            for factor in (1, 2):
                px = base * factor
                src = small_icon(px) if px <= 64 else master.resize((px, px), Image.LANCZOS)
                name = f"icon_{base}x{base}{'@2x' if factor == 2 else ''}.png"
                src.save(iconset / name)
        subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(OUT / "icon.icns")], check=True)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    master = full_icon(1024)
    master.save(OUT / "icon.png")

    frames = []
    for px in (16, 24, 32, 48, 64, 128, 256):
        frames.append(small_icon(px) if px <= 32 else master.resize((px, px), Image.LANCZOS))
    frames[-1].save(OUT / "icon.ico", format="ICO", sizes=[(f.width, f.height) for f in frames], append_images=frames[:-1])

    template_icon(18).save(OUT / "trayTemplate.png")
    template_icon(36).save(OUT / "trayTemplate@2x.png")
    small_icon(32).save(OUT / "tray.png")
    small_icon(64).save(OUT / "tray@2x.png")
    save_icns(master)
    print("icons written to", OUT)


if __name__ == "__main__":
    main()

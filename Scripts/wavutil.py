"""WAV 合成基础工具。供已停用的占位音脚本使用。"""
import math
import os
import random
import struct
import wave

SR = 44100

def exp_env(n, tau_ms):
    tau = tau_ms / 1000.0 * SR
    return [math.exp(-i / tau) for i in range(n)]


def sine_sweep(f0, f1, n, phase=0.0):
    """f0 -> f1 线性扫频正弦"""
    out = []
    p = phase
    for i in range(n):
        f = f0 + (f1 - f0) * (i / max(n - 1, 1))
        p += 2 * math.pi * f / SR
        out.append(math.sin(p))
    return out


def sine(freq, n):
    return [math.sin(2 * math.pi * freq * i / SR) for i in range(n)]


def noise(n):
    return [random.uniform(-1, 1) for _ in range(n)]


def onepole_lowpass(x, cutoff):
    a = 1.0 - math.exp(-2 * math.pi * cutoff / SR)
    out, y = [], 0.0
    for v in x:
        y += a * (v - y)
        out.append(y)
    return out


def mix(*tracks):
    n = max(len(t) for t in tracks)
    out = [0.0] * n
    for t in tracks:
        for i, v in enumerate(t):
            out[i] += v
    return out


def mul(a, b):
    return [x * y for x, y in zip(a, b)]


def gain(x, g):
    return [v * g for v in x]


def cat(*parts):
    out = []
    for p in parts:
        out.extend(p)
    return out


def silence(n):
    return [0.0] * n


def apply_gain_ramp(x, attack_ms=0, release_ms=0):
    n = len(x)
    out = list(x)
    a = int(attack_ms / 1000 * SR)
    r = int(release_ms / 1000 * SR)
    for i in range(min(a, n)):
        out[i] *= i / max(a, 1)
    for i in range(min(r, n)):
        out[n - 1 - i] *= i / max(r, 1)
    return out


def normalize(x, peak=0.89):
    m = max((abs(v) for v in x), default=0) or 1.0
    g = peak / m
    return [v * g for v in x]


def write_wav(path, samples):
    samples = normalize(samples)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        frames = b"".join(struct.pack("<h", int(max(-1, min(1, s)) * 32767)) for s in samples)
        w.writeframes(frames)


def ms(v):
    return int(v / 1000 * SR)



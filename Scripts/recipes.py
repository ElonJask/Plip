"""占位音的音色配方。不单独运行。"""
import random

from wavutil import (
    apply_gain_ramp, cat, exp_env, gain, mix, ms, mul, noise,
    onepole_lowpass, silence, sine, sine_sweep,
)

random.seed(42)

# ---------- 音色配方 ----------

def snd_pop(f0=500, f1=950, dur=65, tau=18):
    n = ms(dur)
    body = mul(sine_sweep(f0, f1, n), exp_env(n, tau))
    click = gain(onepole_lowpass(noise(ms(3)), 6000), 0.35)
    return mix(cat(click, silence(n)), body)


def snd_orb(freq=1350, dur=140, tau=38):
    n = ms(dur)
    body1 = mul(sine_sweep(freq, freq * 1.12, n), exp_env(n, tau))
    body2 = gain(mul(sine_sweep(freq * 2, freq * 2.24, n), exp_env(n, tau * 0.6)), 0.4)
    return apply_gain_ramp(mix(body1, body2), attack_ms=1)


def snd_level_up(notes=(523.25, 659.25, 783.99, 1046.5), note_ms=95, gap_ms=0):
    parts = []
    for f in notes:
        n = ms(note_ms)
        tone = mix(mul(sine(f, n), exp_env(n, 40)),
                   gain(mul(sine(f * 2, n), exp_env(n, 25)), 0.3))
        parts.append(tone)
        if gap_ms:
            parts.append(silence(ms(gap_ms)))
    return cat(*parts)


def snd_block_place(freq=105, dur=150, tau=45):
    n = ms(dur)
    thump = mul(sine(freq, n), exp_env(n, tau))
    transient = gain(onepole_lowpass(noise(ms(12)), 900), 0.5)
    return mix(thump, cat(transient, silence(n)))


def snd_block_hit(dur=80):
    n = ms(dur)
    crackle = gain(onepole_lowpass(noise(n), 2500), 0.8)
    body = mul(sine(90, n), exp_env(n, 30))
    return mix(mul(crackle, exp_env(n, 22)), body)


def snd_block_break(dur=170):
    """连续几声碎裂噪声"""
    out = []
    for i in range(3):
        n = ms(dur // 3)
        burst = mul(gain(onepole_lowpass(noise(n), 1800 - i * 400), 0.7), exp_env(n, 18))
        out.extend(burst)
    return out


def snd_thock(freq=190, dur=95, click_ms=4):
    n = ms(dur)
    low = mul(sine(freq, n), exp_env(n, 26))
    mid = gain(mul(sine(freq * 3.6, n), exp_env(n, 9)), 0.35)
    click = gain(onepole_lowpass(noise(ms(click_ms)), 3500), 0.5)
    return mix(low, mid, cat(click, silence(n)))


def snd_bubble(f0=650, f1=1250, dur=70, tau=24):
    n = ms(dur)
    body = mul(sine_sweep(f0, f1, n), exp_env(n, tau))
    return apply_gain_ramp(body, attack_ms=4)


def snd_toggle_click(freq=2400, dur=40):
    """金属拨杆开关声"""
    n = ms(dur)
    ring = gain(mul(sine(freq, n), exp_env(n, 8)), 0.5)
    click = gain(onepole_lowpass(noise(ms(3)), 5000), 0.6)
    return mix(ring, cat(click, silence(n)))


# ---------- 脚步 / 扩展音色 ----------

def snd_step(cutoff, knock_hz, knock_gain, dur=80, tau=22, crackle=False):
    """MC 脚步基底：低通噪声「踏」+ 低频 knock"""
    n = ms(dur)
    noise_lp = onepole_lowpass(noise(n), cutoff)
    if crackle:
        noise_lp = [v * (1.0 if random.random() > 0.35 else 0.4) for v in noise_lp]
    step = mul(gain(noise_lp, 1.6), exp_env(n, tau))
    knock = gain(mul(sine(knock_hz, n), exp_env(n, tau * 1.4)), knock_gain)
    return mix(step, knock)


def snd_step_wood():
    """木板：空心 knock"""
    n = ms(85)
    hollow = mix(mul(sine(240, n), exp_env(n, 18)),
                 gain(mul(sine(480, n), exp_env(n, 14)), 0.5))
    tick = mul(gain(onepole_lowpass(noise(n), 2500), 0.8), exp_env(n, 10))
    return mix(hollow, tick)


def snd_land(dur=160):
    """跳跃落地（空格）"""
    n = ms(dur)
    body = mul(sine_sweep(95, 42, n), exp_env(n, 55))
    thud = mul(gain(onepole_lowpass(noise(n), 500), 1.1), exp_env(n, 30))
    return apply_gain_ramp(mix(body, thud), attack_ms=2)


def snd_dig(dur=90):
    """挖掘方块（退格）"""
    n = ms(dur)
    scrape = mul(gain(onepole_lowpass(noise(n), 3200), 1.4), exp_env(n, 14))
    return apply_gain_ramp(scrape, attack_ms=1)


def snd_tw_clack(ping=2100, body=150, dur=90):
    """打字机击键：击针 click + 金属簧片 ping + 机身 thump"""
    n = ms(dur)
    click = gain(onepole_lowpass(noise(ms(6)), 7000), 0.65)
    spring = gain(mul(sine(ping, n), exp_env(n, 11)), 0.45)
    thump = gain(mul(sine(body, n), exp_env(n, 24)), 0.8)
    return mix(cat(click, silence(n)), spring, thump)


def snd_tw_bell():
    """回车 = 经典换行铃「叮」+ 滑架回位"""
    bell_n = ms(800)
    bell = mix(mul(sine(2093, bell_n), exp_env(bell_n, 300)),
               gain(mul(sine(2093 * 2.76, bell_n), exp_env(bell_n, 200)), 0.35))
    car_n = ms(220)
    carriage = mul(gain(onepole_lowpass(noise(car_n), 1200), 1.2), exp_env(car_n, 90))
    return mix(bell, cat(silence(ms(380)), carriage))


def snd_tw_back(dur=70):
    """打字机退格：闷 clunk"""
    n = ms(dur)
    clunk = mul(sine(120, n), exp_env(n, 28))
    knock = mul(gain(onepole_lowpass(noise(n), 1500), 0.9), exp_env(n, 18))
    return mix(clunk, knock)


def snd_blue_click(knock=300, dur=75):
    """青轴：click 簧片（前 12ms）+ 触底 knock"""
    n = ms(dur)
    bar_n = ms(12)
    bar = mix(mul(sine(2000, bar_n), exp_env(bar_n, 8)),
              gain(onepole_lowpass(noise(bar_n), 8000), 0.5))
    bottom = mul(sine(knock, n), exp_env(n, 20))
    return mix(cat(bar, silence(n)), cat(silence(bar_n), bottom))


def snd_rain_drop(f0=1200, dur=120, tau=45):
    """雨滴 plink：快下扫正弦，软起音"""
    n = ms(dur)
    body = mul(sine_sweep(f0, f0 * 0.6, n), exp_env(n, tau))
    return apply_gain_ramp(body, attack_ms=4)


def snd_rain_double():
    """plip-plop 双滴（回车）"""
    a = snd_rain_drop(1000, dur=90, tau=40)
    b = snd_rain_drop(700, dur=140, tau=55)
    return cat(a, silence(ms(70)), b)


def snd_kick(dur=160):
    """底鼓：150→42Hz 下扫 + 击面 click"""
    n = ms(dur)
    body = mul(sine_sweep(150, 42, n), exp_env(n, 60))
    click = gain(onepole_lowpass(noise(ms(4)), 6000), 0.4)
    return apply_gain_ramp(mix(body, cat(click, silence(n))), attack_ms=1)


def snd_snare(dur=140):
    """军鼓：噪声 ratt + 220Hz 鼓腔"""
    n = ms(dur)
    rattle = mul(gain(onepole_lowpass(noise(n), 3500), 1.1), exp_env(n, 50))
    tone = gain(mul(sine(220, n), exp_env(n, 35)), 0.7)
    return mix(rattle, tone)


def snd_hat(dur=50, tau=16):
    """闭镲：高通噪声短促"""
    n = ms(dur)
    x = noise(n)
    lp = onepole_lowpass(x, 3000)
    hp = gain([a - b for a, b in zip(x, lp)], 0.8)
    return apply_gain_ramp(mul(hp, exp_env(n, tau)), attack_ms=1)


def snd_rim(dur=50):
    """鼓边击：850Hz knock + tick"""
    n = ms(dur)
    knock = mul(sine(850, n), exp_env(n, 11))
    tick = gain(onepole_lowpass(noise(ms(5)), 7000), 0.5)
    return mix(knock, cat(tick, silence(n)))



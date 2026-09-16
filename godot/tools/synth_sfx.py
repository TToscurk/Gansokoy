#!/usr/bin/env python
"""Procedural katana-combat SFX synthesizer (numpy + scipy).

Cinematic, layered sound design: band-passed noise sweeps, modal (inharmonic)
metal resonators, pitch-dropping thumps with click transients, soft-clip
saturation and short algorithmic reverb tails.  Everything is synthesized
deterministically (seeded RNG per sound) — no external assets.

Run:  python synth_sfx.py
Output: ../assets/audio/sfx/*.wav  (mono, 44.1 kHz, 16-bit, peak ≈ -1 dBFS)
"""
import os
import wave

import numpy as np
from scipy import signal

SR = 44100
PEAK_DB = -1.0
OUT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "sfx"))


# --------------------------------------------------------------------------
# Basic building blocks
# --------------------------------------------------------------------------
def n_of(dur):
    return int(round(dur * SR))


def tvec(dur):
    return np.arange(n_of(dur)) / SR


def silence(dur):
    return np.zeros(n_of(dur))


def white(rng, dur):
    return rng.standard_normal(n_of(dur))


def pink(rng, dur):
    """Pink-ish noise via Paul Kellet's 3-pole approximation (vectorized IIR)."""
    w = white(rng, dur)
    b = [0.049922035, -0.095993537, 0.050612699, -0.004408786]
    a = [1, -2.494956002, 2.017265875, -0.522189400]
    p = signal.lfilter(b, a, w)
    return p / (np.max(np.abs(p)) + 1e-9)


def brown(rng, dur):
    w = white(rng, dur)
    b = np.cumsum(w)
    b = signal.sosfilt(signal.butter(1, 20, "hp", fs=SR, output="sos"), b)
    return b / (np.max(np.abs(b)) + 1e-9)


def env_adsr(dur, a=0.005, d=0.05, s=0.6, r=0.1, curve=4.0):
    """ADSR with exponential-ish decay/release. Returns length n_of(dur)."""
    n = n_of(dur)
    na, nd, nr = n_of(a), n_of(d), n_of(r)
    ns = max(n - na - nd - nr, 0)
    att = np.linspace(0, 1, max(na, 1), endpoint=False)
    dec = s + (1 - s) * np.exp(-curve * np.linspace(0, 1, max(nd, 1)))
    sus = np.full(ns, s)
    rel = s * np.exp(-curve * np.linspace(0, 1, max(nr, 1)))
    e = np.concatenate([att, dec, sus, rel])
    if len(e) < n:
        e = np.concatenate([e, np.zeros(n - len(e))])
    return e[:n]


def env_exp(dur, tau, delay=0.0):
    """Exponential decay envelope exp(-t/tau) starting after delay."""
    t = tvec(dur)
    e = np.exp(-np.maximum(t - delay, 0) / tau)
    e[t < delay] = 0.0
    return e


def env_swell(dur, peak_pos=0.4, power=1.5):
    """Smooth hump (sin^power) for whooshes; peak_pos shifts the peak."""
    n = n_of(dur)
    x = np.linspace(0, 1, n)
    warped = np.where(x < peak_pos, 0.5 * x / peak_pos, 0.5 + 0.5 * (x - peak_pos) / (1 - peak_pos))
    return np.sin(np.pi * warped) ** power


def sweep_bandpass(x, f_start, f_end, q=2.0, block=256, curve="exp"):
    """Time-varying band-pass via short overlapping blocks (Hann cross-fade)."""
    n = len(x)
    hop = block // 2
    win = np.hanning(block)
    nblocks = int(np.ceil(n / hop)) + 1
    out = np.zeros(nblocks * hop + block)
    xp = np.concatenate([x, np.zeros(nblocks * hop + block - n)])
    zi = None
    for i in range(nblocks):
        p = i / max(nblocks - 1, 1)
        if curve == "exp":
            fc = f_start * (f_end / f_start) ** p
        else:
            fc = f_start + (f_end - f_start) * p
        fc = float(np.clip(fc, 30, SR * 0.45))
        bw = fc / q
        lo = max(fc - bw / 2, 20.0)
        hi = min(fc + bw / 2, SR * 0.47)
        sos = signal.butter(2, [lo, hi], "bandpass", fs=SR, output="sos")
        seg = xp[i * hop:i * hop + block]
        if len(seg) < block:
            seg = np.concatenate([seg, np.zeros(block - len(seg))])
        y = signal.sosfilt(sos, seg)
        out[i * hop:i * hop + block] += y * win
    return out[:n]


def bandpass(x, lo, hi, order=2):
    sos = signal.butter(order, [lo, hi], "bandpass", fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def lowpass(x, fc, order=2):
    sos = signal.butter(order, fc, "lp", fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def highpass(x, fc, order=2):
    sos = signal.butter(order, fc, "hp", fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def resonant_peak(x, fc, q=8.0, gain=1.0):
    b, a = signal.iirpeak(fc, q, fs=SR)
    return signal.lfilter(b, a, x) * gain


def modal_ring(rng, dur, base_freq, ratios=(1.0, 2.32, 3.7, 4.9, 6.4, 7.8, 9.3), decays=None,
               amps=None, detune=0.004, delay=0.0):
    """Inharmonic modal synthesis: exponentially decaying sines at non-integer ratios."""
    t = tvec(dur)
    out = np.zeros_like(t)
    k = len(ratios)
    if decays is None:
        decays = [0.35 / (1 + 0.35 * i) for i in range(k)]
    if amps is None:
        amps = [1.0 / (1 + 0.6 * i) for i in range(k)]
    for r, dcy, amp in zip(ratios, decays, amps):
        for sgn in (-1, 1):
            f = base_freq * r * (1 + sgn * detune * rng.uniform(0.5, 1.5))
            if f >= SR * 0.45:
                continue
            ph = rng.uniform(0, 2 * np.pi)
            out += amp * np.sin(2 * np.pi * f * t + ph) * env_exp(dur, dcy, delay)
    return out / k


def pitch_drop_sine(dur, f0, f1, tau, drop_tau=0.05, delay=0.0):
    """Sine whose frequency drops exponentially f0→f1; amplitude decays with tau."""
    t = tvec(dur)
    tt = np.maximum(t - delay, 0)
    f = f1 + (f0 - f1) * np.exp(-tt / drop_tau)
    phase = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(phase) * env_exp(dur, tau, delay)


def click(rng, dur, at=0.0, length=0.003, color_hp=1500.0):
    """Very short bright transient."""
    x = white(rng, dur)
    e = env_exp(dur, length, at)
    x = highpass(x * e, color_hp)
    return x


def sparse_impulses(rng, dur, rate=120.0, decay=0.004, jitter=0.6):
    """Random sparse impulses (for fire crackle / dirt)."""
    n = n_of(dur)
    imp = np.zeros(n)
    count = rng.poisson(rate * dur)
    idx = rng.integers(0, n, count)
    imp[idx] = rng.uniform(1 - jitter, 1.0, count) * rng.choice([-1, 1], count)
    kern = np.exp(-np.arange(n_of(decay * 4)) / (decay * SR))
    return signal.fftconvolve(imp, kern)[:n]


def fire_crackle(rng, dur, lo=200.0, hi=900.0, rate=180.0, hiss=0.35):
    """Filtered noise amplitude-modulated by sparse impulses + soft hiss bed."""
    base = bandpass(white(rng, dur), lo, hi, order=2)
    mod = np.abs(sparse_impulses(rng, dur, rate=rate, decay=0.006))
    mod = lowpass(mod, 3000, 1)
    mod = mod / (np.max(np.abs(mod)) + 1e-9)
    crack = base * (0.25 + mod)
    bed = bandpass(pink(rng, dur), 1500, 6000) * hiss
    return crack + bed


def tremolo(x, rate, depth=0.8, phase=0.0):
    t = np.arange(len(x)) / SR
    m = 1 - depth * 0.5 * (1 + np.sin(2 * np.pi * rate * t + phase))
    return x * m


def saturate(x, drive=2.0):
    return np.tanh(x * drive) / np.tanh(drive)


def reverb(rng, x, decay=0.5, mix=0.15, hp=200.0, damp=6000.0):
    """Algorithmic reverb: convolve with exponentially decaying filtered noise."""
    n_ir = n_of(decay)
    ir = rng.standard_normal(n_ir) * np.exp(-np.arange(n_ir) / (decay * SR / 5.0))
    ir[: n_of(0.005)] *= np.linspace(0, 1, n_of(0.005))
    ir = lowpass(highpass(ir, hp), damp)
    ir /= np.sqrt(np.sum(ir ** 2)) + 1e-9
    wet = signal.fftconvolve(x, ir)[: len(x)]
    wet *= 0.25
    return (1 - mix) * x + mix * wet


def mix(*layers):
    """Sum layers of possibly different lengths (zero-padded)."""
    n = max(len(l) for l in layers)
    out = np.zeros(n)
    for l in layers:
        out[: len(l)] += l
    return out


def gain(x, g):
    return x * g


def shift(x, dur, at):
    """Place x at time `at` inside a buffer of `dur` seconds."""
    out = silence(dur)
    s = n_of(at)
    seg = x[: max(len(out) - s, 0)]
    out[s: s + len(seg)] = seg
    return out


def finalize(x, dur=None, fade_out=0.02, fade_in=0.0005):
    """Trim/pad to dur, fade edges, DC-remove, peak normalize to PEAK_DB."""
    if dur is not None:
        n = n_of(dur)
        x = x[:n] if len(x) >= n else np.concatenate([x, np.zeros(n - len(x))])
    x = x - np.mean(x)
    x = highpass(x, 25.0, 1)
    nfi, nfo = n_of(fade_in), n_of(fade_out)
    if nfi > 0:
        x[:nfi] *= np.linspace(0, 1, nfi)
    if nfo > 0:
        x[-nfo:] *= np.linspace(1, 0, nfo) ** 1.5
    peak = np.max(np.abs(x)) + 1e-12
    x = x / peak * (10 ** (PEAK_DB / 20))
    return x


def write_wav(path, x):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    pcm = np.clip(np.round(x * 32767.0), -32768, 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


# --------------------------------------------------------------------------
# Compound sound components
# --------------------------------------------------------------------------
def whoosh(rng, dur, body_f=(900, 220), hiss_f=(6000, 2500), body_q=1.6, hiss_q=1.2,
           peak_pos=0.42, body_gain=1.0, hiss_gain=0.6, power=1.6):
    """Katana whoosh: low-mid 'body' sweep + high 'blade hiss' sweep."""
    env = env_swell(dur, peak_pos, power)
    body = sweep_bandpass(pink(rng, dur), body_f[0], body_f[1], q=body_q) * env
    hiss = sweep_bandpass(white(rng, dur), hiss_f[0], hiss_f[1], q=hiss_q) * env ** 1.3
    body /= np.max(np.abs(body)) + 1e-9
    hiss /= np.max(np.abs(hiss)) + 1e-9
    return body * body_gain + hiss * hiss_gain


def thump(rng, dur, f0=140.0, f1=48.0, tau=0.12, drop_tau=0.04, click_amt=0.5, noise_amt=0.4,
          drive=2.5, delay=0.0):
    """Drum-like thump: pitch-dropping sine + click transient + noise burst, saturated."""
    s = pitch_drop_sine(dur, f0, f1, tau, drop_tau, delay)
    c = click(rng, dur, delay, 0.002, 2000.0) * click_amt
    nb = lowpass(white(rng, dur), 900) * env_exp(dur, 0.02, delay) * noise_amt
    return saturate(s + c + nb, drive)


def steel_ring(rng, dur, base=2200.0, decay_scale=1.0, delay=0.0, bright=True):
    ratios = (1.0, 1.58, 2.32, 3.01, 3.7, 4.9, 6.4, 7.9)
    decays = [0.28 * decay_scale / (1 + 0.3 * i) for i in range(len(ratios))]
    amps = [1.0, 0.7, 0.8, 0.45, 0.5, 0.3, 0.22, 0.15] if bright else [1.0, 0.5, 0.35, 0.2, 0.15, 0.08, 0.05, 0.03]
    return modal_ring(rng, dur, base, ratios, decays, amps, detune=0.006, delay=delay)


def cloth(rng, dur, lo=300.0, hi=2500.0, flutter_rate=18.0, env=None):
    x = bandpass(pink(rng, dur), lo, hi)
    t = tvec(dur)
    fl = 0.55 + 0.45 * np.abs(np.sin(2 * np.pi * flutter_rate * t + rng.uniform(0, 3)))
    x = x * fl
    if env is not None:
        x = x * env
    return x / (np.max(np.abs(x)) + 1e-9)


def dirt(rng, dur, rate=400.0, delay=0.0, tau=0.08):
    g = sparse_impulses(rng, dur, rate=rate, decay=0.0015)
    g = bandpass(g, 700, 6000) * env_exp(dur, tau, delay)
    return g / (np.max(np.abs(g)) + 1e-9)


# --------------------------------------------------------------------------
# Sound builders
# --------------------------------------------------------------------------
def build_swing(seed, dur, body_f, hiss_f, heavy=0.0, peak_pos=0.42):
    rng = np.random.default_rng(seed)
    w = whoosh(rng, dur, body_f, hiss_f, body_gain=1.0 + heavy * 0.4, hiss_gain=0.55 - heavy * 0.1,
               peak_pos=peak_pos)
    if heavy > 0:
        sub = pitch_drop_sine(dur, 160, 70, 0.08, 0.03, delay=dur * peak_pos * 0.8) * heavy * 0.5
        w = w + sub
    w = saturate(w, 1.5)
    w = reverb(rng, w, 0.25, 0.10)
    return finalize(w, dur)


def sword_swing_1():
    return build_swing(1001, 0.24, (1100, 260), (7000, 2800))


def sword_swing_2():
    return build_swing(1002, 0.26, (950, 210), (6200, 2300), peak_pos=0.38)


def sword_swing_3():
    return build_swing(1003, 0.30, (800, 170), (5600, 2000), heavy=0.6, peak_pos=0.45)


def build_fire_swing(seed, dur, body_f, hiss_f, heavy=0.0):
    rng = np.random.default_rng(seed)
    w = whoosh(rng, dur, body_f, hiss_f, body_gain=1.0 + heavy * 0.3, hiss_gain=0.5)
    fire = fire_crackle(rng, dur, 200, 900, rate=220) * env_swell(dur, 0.5, 1.2)
    fire = fire / (np.max(np.abs(fire)) + 1e-9) * 0.75
    warm = resonant_peak(fire, 450, 2.0, 0.5)
    out = saturate(w + fire + warm, 1.8)
    out = reverb(rng, out, 0.3, 0.12)
    return finalize(out, dur)


def sword_fire_swing_1():
    return build_fire_swing(2001, 0.32, (1000, 240), (6500, 2600))


def sword_fire_swing_2():
    return build_fire_swing(2002, 0.35, (900, 200), (6000, 2200))


def sword_fire_swing_3():
    return build_fire_swing(2003, 0.40, (760, 160), (5400, 1900), heavy=0.7)


def sword_heavy():
    rng = np.random.default_rng(3001)
    dur = 0.5
    w = whoosh(rng, dur, (600, 120), (4500, 1500), body_q=1.4, peak_pos=0.4, body_gain=1.2, hiss_gain=0.45, power=1.3)
    th = thump(rng, dur, 110, 42, 0.18, 0.05, click_amt=0.2, noise_amt=0.3, delay=0.17) * 0.9
    tail = lowpass(brown(rng, dur), 250) * env_exp(dur, 0.15, 0.2) * 0.4
    out = saturate(w + th + tail, 2.0)
    out = reverb(rng, out, 0.45, 0.18)
    return finalize(out, dur, fade_out=0.04)


def sword_draw():
    rng = np.random.default_rng(4001)
    dur = 0.6
    scrape_dur = 0.24
    scr = sweep_bandpass(white(rng, scrape_dur), 800, 3000, q=6.0, block=128)
    scr = scr * env_swell(scrape_dur, 0.7, 1.0)
    # add grainy friction texture
    grain = sparse_impulses(rng, scrape_dur, rate=900, decay=0.0008)
    scr = scr + highpass(grain, 1500) * env_swell(scrape_dur, 0.7, 1.0) * 0.5
    scr = shift(scr / (np.max(np.abs(scr)) + 1e-9), dur, 0.0) * 0.8
    ring = steel_ring(rng, dur, 2600.0, decay_scale=1.7, delay=0.2)
    ring = ring / (np.max(np.abs(ring)) + 1e-9)
    tick = click(rng, dur, 0.2, 0.0015, 3000) * 0.6
    out = scr + ring * 0.9 + tick
    out = saturate(out, 1.4)
    out = reverb(rng, out, 0.5, 0.18, hp=400)
    return finalize(out, dur, fade_out=0.05)


def sword_sheathe():
    rng = np.random.default_rng(5001)
    dur = 0.5
    slide_dur = 0.3
    sl = sweep_bandpass(pink(rng, slide_dur), 2200, 900, q=3.0) * env_swell(slide_dur, 0.6, 1.2)
    sl = shift(sl / (np.max(np.abs(sl)) + 1e-9), dur, 0.0) * 0.55
    wood = pitch_drop_sine(dur, 700, 320, 0.03, 0.01, delay=0.3)
    wood = wood + resonant_peak(click(rng, dur, 0.3, 0.004, 400), 520, 6, 1.0)
    wood = wood / (np.max(np.abs(wood)) + 1e-9)
    metal = steel_ring(rng, dur, 3400.0, decay_scale=0.25, delay=0.305, bright=False)
    metal = metal / (np.max(np.abs(metal)) + 1e-9) * 0.35
    out = sl + wood + metal
    out = saturate(out, 1.5)
    out = reverb(rng, out, 0.3, 0.1, hp=300)
    return finalize(out, dur, fade_out=0.04)


def jump_takeoff():
    rng = np.random.default_rng(6001)
    dur = 0.3
    c = cloth(rng, dur, 350, 3000, 22, env_swell(dur, 0.3, 1.3)) * 0.8
    push = thump(rng, dur, 150, 70, 0.07, 0.03, click_amt=0.3, noise_amt=0.5, drive=2.0) * 0.7
    grit = dirt(rng, dur, 350, 0.0, 0.05) * 0.35
    out = reverb(rng, c + push + grit, 0.25, 0.1)
    return finalize(out, dur)


def jump_land():
    rng = np.random.default_rng(6002)
    dur = 0.38
    th = thump(rng, dur, 120, 40, 0.16, 0.04, click_amt=0.4, noise_amt=0.6, drive=3.0)
    crunch = dirt(rng, dur, 700, 0.0, 0.09) * 0.6
    c = cloth(rng, dur, 300, 2200, 15, env_exp(dur, 0.12)) * 0.5
    out = reverb(rng, th + crunch + c, 0.35, 0.14)
    return finalize(out, dur, fade_out=0.03)


def roll_whoosh():
    rng = np.random.default_rng(6003)
    dur = 0.4
    c = cloth(rng, dur, 250, 2800, 12, env_swell(dur, 0.45, 1.2))
    w = whoosh(rng, dur, (500, 180), (3500, 1600), body_gain=0.7, hiss_gain=0.25, peak_pos=0.45)
    tumble = tremolo(c, 9.0, 0.6)
    ground = thump(rng, dur, 100, 45, 0.08, 0.03, click_amt=0.1, noise_amt=0.4, drive=1.8, delay=0.22) * 0.45
    out = reverb(rng, tumble + w * 0.6 + ground, 0.3, 0.12)
    return finalize(out, dur, fade_out=0.04)


def build_hit(seed, dur, f0, f1, body_tau, sting_base, sting_decay, sting_gain, slice_gain=0.9):
    rng = np.random.default_rng(seed)
    sl = highpass(white(rng, dur), 2500) * env_exp(dur, 0.012) * slice_gain
    wet = bandpass(white(rng, dur), 400, 2500) * env_exp(dur, 0.035) * 0.6
    body = thump(rng, dur, f0, f1, body_tau, 0.03, click_amt=0.5, noise_amt=0.5, drive=2.5)
    sting = steel_ring(rng, dur, sting_base, sting_decay, delay=0.003) * sting_gain
    out = saturate(sl + wet + body + sting, 1.6)
    out = reverb(rng, out, 0.3, 0.12)
    return finalize(out, dur, fade_out=0.03)


def hit_impact_light():
    return build_hit(7001, 0.28, 180, 60, 0.07, 2800, 0.35, 0.35)


def hit_impact_heavy():
    return build_hit(7002, 0.42, 130, 40, 0.14, 2100, 0.6, 0.45, slice_gain=1.0)


def build_fire_hit(seed, dur, f0, f1, body_tau, sting_base, fire_gain=0.8, spin=False):
    rng = np.random.default_rng(seed)
    sl = highpass(white(rng, dur), 2500) * env_exp(dur, 0.012)
    body = thump(rng, dur, f0, f1, body_tau, 0.03, click_amt=0.5, noise_amt=0.5, drive=2.5)
    sting = steel_ring(rng, dur, sting_base, 0.4, delay=0.003) * 0.3
    fire = fire_crackle(rng, dur, 180, 1000, rate=260) * env_exp(dur, dur * 0.35, 0.0)
    fire = fire / (np.max(np.abs(fire)) + 1e-9) * fire_gain
    burst = bandpass(white(rng, dur), 800, 5000) * env_exp(dur, 0.05) * 0.6
    if spin:
        w = whoosh(rng, dur, (700, 300), (5000, 2500), peak_pos=0.5, power=1.0)
        w = tremolo(w, 6.0, 0.85, phase=np.pi)
        fire = tremolo(fire, 6.0, 0.5)
        out = sl * 0.7 + body * 0.8 + sting + fire + burst + w * 0.7
    else:
        out = sl + body + sting + fire + burst
    out = saturate(out, 2.0)
    out = reverb(rng, out, 0.4, 0.14)
    return finalize(out, dur, fade_out=0.04)


def hit_fire_light_1():
    return build_fire_hit(8001, 0.34, 180, 60, 0.07, 2800, 0.7)


def hit_fire_light_2():
    return build_fire_hit(8002, 0.36, 200, 65, 0.075, 3100, 0.7)


def hit_fire_heavy():
    return build_fire_hit(8003, 0.5, 130, 40, 0.15, 2100, 0.9)


def hit_fire_spin():
    return build_fire_hit(8004, 0.6, 140, 45, 0.12, 2400, 0.85, spin=True)


def deflect_clang():
    rng = np.random.default_rng(9001)
    dur = 0.45
    tr = click(rng, dur, 0.0, 0.0015, 3000) * 1.2 + highpass(white(rng, dur), 4000) * env_exp(dur, 0.006) * 0.8
    ring_a = steel_ring(rng, dur, 3200.0, 1.3, delay=0.0)
    ring_b = steel_ring(rng, dur, 2050.0, 1.1, delay=0.002)
    ring = (ring_a + ring_b * 0.8)
    ring = ring / (np.max(np.abs(ring)) + 1e-9)
    body = thump(rng, dur, 400, 180, 0.03, 0.01, click_amt=0.3, noise_amt=0.3, drive=2.0) * 0.5
    out = saturate(tr + ring * 1.1 + body, 1.5)
    out = reverb(rng, out, 0.35, 0.16, hp=500)
    return finalize(out, dur, fade_out=0.04)


def block_thud():
    rng = np.random.default_rng(9002)
    dur = 0.35
    clunk = thump(rng, dur, 260, 90, 0.06, 0.015, click_amt=0.6, noise_amt=0.7, drive=2.5)
    ring = steel_ring(rng, dur, 900.0, 0.35, bright=False)
    ring = lowpass(ring / (np.max(np.abs(ring)) + 1e-9), 1800) * 0.5
    out = lowpass(clunk + ring, 2500)
    out = saturate(out, 1.8)
    out = reverb(rng, out, 0.25, 0.1)
    return finalize(out, dur, fade_out=0.03)


def hurt_grunt_body():
    rng = np.random.default_rng(9003)
    dur = 0.4
    th = thump(rng, dur, 150, 55, 0.11, 0.035, click_amt=0.3, noise_amt=0.6, drive=3.0)
    c = cloth(rng, dur, 300, 2000, 14, env_exp(dur, 0.09)) * 0.6
    wet = bandpass(white(rng, dur), 500, 1800) * env_exp(dur, 0.04) * 0.4
    out = reverb(rng, th + c + wet, 0.3, 0.12)
    return finalize(out, dur, fade_out=0.03)


def death_collapse():
    rng = np.random.default_rng(9004)
    dur = 1.2
    th1 = thump(rng, dur, 130, 45, 0.16, 0.04, click_amt=0.3, noise_amt=0.6, drive=3.0, delay=0.0)
    th2 = thump(rng, dur, 110, 38, 0.22, 0.05, click_amt=0.2, noise_amt=0.5, drive=3.0, delay=0.25) * 0.9
    c = cloth(rng, dur, 250, 2200, 10, env_exp(dur, 0.25, 0.0) + env_exp(dur, 0.2, 0.25)) * 0.5
    d = dirt(rng, dur, 500, 0.0, 0.1) * 0.4 + dirt(rng, dur, 500, 0.25, 0.14) * 0.55
    rumble = lowpass(brown(rng, dur), 120) * env_exp(dur, 0.35, 0.25) * 0.7
    out = saturate(th1 + th2 + c + d + rumble, 1.6)
    out = reverb(rng, out, 0.7, 0.2)
    return finalize(out, dur, fade_out=0.15)


def death_kanji():
    rng = np.random.default_rng(9005)
    dur = 2.2
    t = tvec(dur)
    # huge taiko: pitch drop 120→45, saturated
    drum = pitch_drop_sine(dur, 120, 45, 0.55, 0.09)
    skin = lowpass(white(rng, dur), 1200) * env_exp(dur, 0.03) * 0.8
    stick = click(rng, dur, 0.0, 0.003, 1200) * 0.6
    drum_body = resonant_peak(lowpass(white(rng, dur), 400) * env_exp(dur, 0.12), 90, 4, 0.6)
    taiko = saturate(drum * 1.2 + skin + stick + drum_body, 3.0)
    taiko = reverb(rng, taiko, 0.9, 0.25, hp=60, damp=4000)
    # ominous drone 55 Hz with slow swell, plus fifth and sub
    swell = (np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 1.2) * (1 - np.exp(-t / 0.3))
    drone = (np.sin(2 * np.pi * 55 * t) + 0.5 * np.sin(2 * np.pi * 82.5 * t + 1.0)
             + 0.35 * np.sin(2 * np.pi * 27.5 * t) + 0.25 * np.sin(2 * np.pi * 110.5 * t + 2.0))
    drone = drone * (1 + 0.15 * np.sin(2 * np.pi * 0.7 * t))
    drone = saturate(drone, 1.5) * swell * 0.45
    air = lowpass(brown(rng, dur), 200) * swell * 0.25
    out = taiko + drone + air
    return finalize(out, dur, fade_out=0.3)


def respawn_breath():
    rng = np.random.default_rng(9006)
    dur = 1.4
    inhale_dur = 0.8
    inh = sweep_bandpass(white(rng, inhale_dur), 300, 1500, q=1.5, block=512)
    inh = inh * env_swell(inhale_dur, 0.75, 1.4)
    inh = shift(inh / (np.max(np.abs(inh)) + 1e-9), dur, 0.0) * 0.8
    t = tvec(dur)
    shimmer = np.zeros_like(t)
    for f, a in [(3520, 1.0), (4660, 0.7), (5870, 0.55), (7040, 0.4), (8380, 0.3), (9950, 0.2)]:
        ph = rng.uniform(0, 2 * np.pi)
        f2 = f * (1 + rng.uniform(-0.004, 0.004))
        e = env_swell(dur, 0.62, 1.8) * (t > 0.55)
        shimmer += a * np.sin(2 * np.pi * f2 * t + ph) * e * (1 + 0.3 * np.sin(2 * np.pi * 5.0 * t + ph))
    shimmer = shimmer / (np.max(np.abs(shimmer)) + 1e-9) * 0.28
    soft_air = bandpass(pink(rng, dur), 2000, 8000) * env_swell(dur, 0.65, 1.5) * 0.15
    out = reverb(rng, inh + shimmer + soft_air, 0.9, 0.22, hp=300)
    return finalize(out, dur, fade_out=0.2)


def form_ignite():
    rng = np.random.default_rng(9007)
    dur = 0.55
    sub = thump(rng, dur, 140, 50, 0.16, 0.04, click_amt=0.3, noise_amt=0.4, drive=2.5)
    crack = fire_crackle(rng, dur, 250, 1200, rate=350) * env_swell(dur, 0.3, 1.2)
    crack = crack / (np.max(np.abs(crack)) + 1e-9) * 0.75
    rise = sweep_bandpass(white(rng, dur), 1200, 9000, q=1.3) * env_swell(dur, 0.35, 1.3)
    rise = rise / (np.max(np.abs(rise)) + 1e-9) * 0.7
    flash = highpass(white(rng, dur), 3000) * env_exp(dur, 0.02, 0.0) * 0.6
    warm = resonant_peak(bandpass(pink(rng, dur), 200, 800), 420, 3, 1.0) * env_exp(dur, 0.18, 0.15) * 0.7
    out = saturate(sub + crack + rise + flash + warm, 2.0)
    out = reverb(rng, out, 0.45, 0.18)
    return finalize(out, dur, fade_out=0.06)


def thrust_whoosh():
    rng = np.random.default_rng(9008)
    dur = 0.35
    snap = click(rng, dur, 0.0, 0.002, 2500) * 1.0 + highpass(white(rng, dur), 3500) * env_exp(dur, 0.008) * 0.7
    core = sweep_bandpass(white(rng, dur), 5000, 1800, q=2.5) * env_swell(dur, 0.18, 1.8)
    core = highpass(core / (np.max(np.abs(core)) + 1e-9), 900) * 0.9
    body = sweep_bandpass(pink(rng, dur), 1400, 500, q=2.0) * env_swell(dur, 0.2, 2.0) * 0.35
    out = saturate(snap + core + body, 1.4)
    out = reverb(rng, out, 0.25, 0.08)
    return finalize(out, dur, fade_out=0.03)


def spin_whoosh():
    rng = np.random.default_rng(9009)
    dur = 0.7
    t = tvec(dur)
    wob = 1 + 0.06 * np.sin(2 * np.pi * 3.0 * t)
    body = sweep_bandpass(pink(rng, dur) * wob, 700, 350, q=1.6) * env_swell(dur, 0.5, 1.0)
    hiss = sweep_bandpass(white(rng, dur) * wob, 5000, 3200, q=1.3) * env_swell(dur, 0.5, 1.2)
    body = body / (np.max(np.abs(body)) + 1e-9)
    hiss = hiss / (np.max(np.abs(hiss)) + 1e-9) * 0.5
    out = tremolo(body + hiss, 3.0, 0.85, phase=-np.pi / 2)
    # per-revolution 'cut' accents
    for at in (0.13, 0.46):
        out += highpass(white(rng, dur), 3000) * env_exp(dur, 0.015, at) * 0.4
    out = saturate(out, 1.5)
    out = reverb(rng, out, 0.35, 0.12)
    return finalize(out, dur, fade_out=0.06)


def deathblow_slash():
    rng = np.random.default_rng(9010)
    dur = 0.9
    cut = click(rng, dur, 0.0, 0.002, 3000) * 1.2 + highpass(white(rng, dur), 3000) * env_exp(dur, 0.018) * 1.0
    pre = whoosh(rng, 0.14, (1600, 500), (8000, 3500), peak_pos=0.75, power=1.4) * 0.5
    body = thump(rng, dur, 110, 36, 0.28, 0.05, click_amt=0.4, noise_amt=0.6, drive=3.0, delay=0.01)
    wet = bandpass(white(rng, dur), 300, 2200) * env_exp(dur, 0.05) * 0.7
    ring = steel_ring(rng, dur, 2500.0, 2.4, delay=0.004) + steel_ring(rng, dur, 3900.0, 1.8, delay=0.006) * 0.6
    ring = ring / (np.max(np.abs(ring)) + 1e-9) * 0.8
    rumble = lowpass(brown(rng, dur), 100) * env_exp(dur, 0.35, 0.05) * 0.6
    out = mix(shift(pre, dur, 0.0), cut, body, wet, ring, rumble)
    out = saturate(out, 2.2)
    out = reverb(rng, out, 0.9, 0.24, hp=120)
    return finalize(out, dur, fade_out=0.12)


SOUNDS = {
    "sword_swing_1": sword_swing_1,
    "sword_swing_2": sword_swing_2,
    "sword_swing_3": sword_swing_3,
    "sword_fire_swing_1": sword_fire_swing_1,
    "sword_fire_swing_2": sword_fire_swing_2,
    "sword_fire_swing_3": sword_fire_swing_3,
    "sword_heavy": sword_heavy,
    "sword_draw": sword_draw,
    "sword_sheathe": sword_sheathe,
    "jump_takeoff": jump_takeoff,
    "jump_land": jump_land,
    "roll_whoosh": roll_whoosh,
    "hit_impact_light": hit_impact_light,
    "hit_impact_heavy": hit_impact_heavy,
    "hit_fire_light_1": hit_fire_light_1,
    "hit_fire_light_2": hit_fire_light_2,
    "hit_fire_heavy": hit_fire_heavy,
    "hit_fire_spin": hit_fire_spin,
    "deflect_clang": deflect_clang,
    "block_thud": block_thud,
    "hurt_grunt_body": hurt_grunt_body,
    "death_collapse": death_collapse,
    "death_kanji": death_kanji,
    "respawn_breath": respawn_breath,
    "form_ignite": form_ignite,
    "thrust_whoosh": thrust_whoosh,
    "spin_whoosh": spin_whoosh,
    "deathblow_slash": deathblow_slash,
}


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for name, builder in SOUNDS.items():
        x = builder()
        if not np.all(np.isfinite(x)):
            raise RuntimeError(f"{name}: non-finite samples")
        path = os.path.join(OUT_DIR, name + ".wav")
        write_wav(path, x)
        peak_db = 20 * np.log10(np.max(np.abs(x)) + 1e-12)
        print(f"{name + '.wav':26s} {len(x) / SR:5.2f}s  peak {peak_db:6.2f} dBFS")
    print(f"Wrote {len(SOUNDS)} files to {OUT_DIR}")


if __name__ == "__main__":
    main()

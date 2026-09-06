import math
import os
import random
import struct
import wave

SAMPLE_RATE = 44100

def write_wav(filepath, samples):
    os.makedirs(os.path.dirname(filepath), exist_ok=True)
    with wave.open(filepath, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SAMPLE_RATE)
        # normalize
        max_amp = max(abs(s) for s in samples) if samples else 1.0
        scale = 32000.0 / max(max_amp, 1e-6)
        raw = bytearray()
        for s in samples:
            val = int(max(-32767, min(32767, s * scale)))
            raw.extend(struct.pack("<h", val))
        w.writeframes(raw)
    print(f"Generated {filepath} ({len(samples)/SAMPLE_RATE:.2f}s)")

def make_whoosh(duration=0.25, f_start=900, f_end=200, resonance=12.0, noise_amount=0.6):
    n_samples = int(SAMPLE_RATE * duration)
    samples = []
    # Bandpass filter state
    y1, y2 = 0.0, 0.0
    random.seed(42)
    for i in range(n_samples):
        t = i / SAMPLE_RATE
        env = math.sin(math.pi * (i / n_samples)) ** 1.5
        # center freq sweeps down
        progress = i / n_samples
        f_center = f_start * ((f_end / f_start) ** progress)
        # simple 2-pole resonant filter on white noise + sine
        noise = (random.random() * 2.0 - 1.0) * noise_amount
        tone = math.sin(2.0 * math.pi * f_center * t) * (1.0 - noise_amount)
        x = (noise + tone) * env
        
        # 2-pole resonator approximation
        w0 = 2.0 * math.pi * f_center / SAMPLE_RATE
        r = 1.0 - (w0 / resonance)
        y0 = x + 2.0 * r * math.cos(w0) * y1 - (r * r) * y2
        y2, y1 = y1, y0
        samples.append(y0 * env)
    return samples

def make_sword_swing(variation=1):
    if variation == 1:
        return make_whoosh(0.22, 1100, 280, resonance=10.0, noise_amount=0.55)
    elif variation == 2:
        return make_whoosh(0.25, 950, 220, resonance=12.0, noise_amount=0.5)
    else:
        return make_whoosh(0.28, 800, 180, resonance=14.0, noise_amount=0.45)

def make_sword_heavy():
    n_samples = int(SAMPLE_RATE * 0.42)
    samples = []
    y1, y2 = 0.0, 0.0
    random.seed(101)
    for i in range(n_samples):
        t = i / SAMPLE_RATE
        progress = i / n_samples
        env = (math.sin(math.pi * progress) ** 1.2) * math.exp(-progress * 2.0)
        # deep rumble bass
        bass = math.sin(2.0 * math.pi * 75.0 * (1.0 - progress * 0.4) * t) * 0.8
        # swoosh
        f_center = 750.0 * (0.25 ** progress)
        noise = (random.random() * 2.0 - 1.0) * 0.5
        x = (noise + bass) * env
        w0 = 2.0 * math.pi * f_center / SAMPLE_RATE
        r = 0.94
        y0 = x + 2.0 * r * math.cos(w0) * y1 - (r * r) * y2
        y2, y1 = y1, y0
        samples.append((y0 + bass * 0.7) * env)
    return samples

def make_sword_draw():
    # metal slide scrape + sustained metallic ring
    n_samples = int(SAMPLE_RATE * 0.55)
    samples = []
    random.seed(202)
    for i in range(n_samples):
        t = i / SAMPLE_RATE
        # scrape in first 0.18s
        scrape_env = math.exp(-t * 15.0) if t < 0.2 else 0.0
        scrape = (random.random() * 2.0 - 1.0) * scrape_env * (1.0 + math.sin(2.0 * math.pi * 1200 * t))
        # metal chime ring starting around 0.08s
        t_ring = max(0.0, t - 0.06)
        ring_env = math.exp(-t_ring * 6.5) if t >= 0.06 else 0.0
        ring = (
            0.5 * math.sin(2.0 * math.pi * 1760.0 * t_ring) +
            0.35 * math.sin(2.0 * math.pi * 2640.0 * t_ring) +
            0.25 * math.sin(2.0 * math.pi * 4186.0 * t_ring) +
            0.15 * math.sin(2.0 * math.pi * 5274.0 * t_ring)
        ) * ring_env
        samples.append(scrape * 0.6 + ring * 0.8)
    return samples

def make_sword_sheathe():
    # smooth scabbard slide followed by crisp metallic click/latch
    n_samples = int(SAMPLE_RATE * 0.45)
    samples = []
    random.seed(303)
    t_click = 0.28
    for i in range(n_samples):
        t = i / SAMPLE_RATE
        # slide friction up to click
        if t < t_click:
            slide_env = (t / t_click) * math.sin(math.pi * (t / t_click))
            slide = (random.random() * 2.0 - 1.0) * slide_env * 0.4
        else:
            slide = 0.0
        # latch click at t_click
        if t >= t_click:
            dt = t - t_click
            click_env = math.exp(-dt * 60.0)
            click_wood = math.sin(2.0 * math.pi * 380.0 * dt) * click_env
            click_metal = math.sin(2.0 * math.pi * 2800.0 * dt) * math.exp(-dt * 40.0)
            click = (click_wood * 0.7 + click_metal * 0.5 + (random.random() * 2.0 - 1.0) * click_env * 0.3)
        else:
            click = 0.0
        samples.append(slide + click)
    return samples

def make_jump_takeoff():
    n_samples = int(SAMPLE_RATE * 0.22)
    samples = []
    random.seed(404)
    for i in range(n_samples):
        t = i / SAMPLE_RATE
        env = math.sin(math.pi * (i / n_samples)) ** 1.8
        f = 120.0 + 350.0 * (i / n_samples)
        puff = math.sin(2.0 * math.pi * f * t) * 0.6
        cloth = (random.random() * 2.0 - 1.0) * 0.4 * env
        samples.append((puff + cloth) * env)
    return samples

def make_jump_land():
    n_samples = int(SAMPLE_RATE * 0.28)
    samples = []
    random.seed(505)
    for i in range(n_samples):
        t = i / SAMPLE_RATE
        # punchy low thump
        thump_env = math.exp(-t * 22.0)
        f_thump = 90.0 * math.exp(-t * 15.0)
        thump = math.sin(2.0 * math.pi * f_thump * t) * thump_env
        # crunchy surface noise
        crunch_env = math.exp(-t * 35.0)
        crunch = (random.random() * 2.0 - 1.0) * crunch_env * 0.5
        samples.append(thump * 0.8 + crunch * 0.4)
    return samples

def make_roll_whoosh():
    n_samples = int(SAMPLE_RATE * 0.35)
    samples = []
    random.seed(606)
    for i in range(n_samples):
        t = i / SAMPLE_RATE
        env = math.sin(math.pi * (i / n_samples)) ** 1.5
        f = 350.0 - 150.0 * (i / n_samples)
        swoosh = math.sin(2.0 * math.pi * f * t) * 0.4
        flutter = (random.random() * 2.0 - 1.0) * 0.6
        samples.append((swoosh + flutter) * env)
    return samples

def make_hit_impact(heavy=False):
    duration = 0.36 if heavy else 0.24
    n_samples = int(SAMPLE_RATE * duration)
    samples = []
    random.seed(707 if not heavy else 808)
    for i in range(n_samples):
        t = i / SAMPLE_RATE
        # sharp slice transient
        slice_env = math.exp(-t * 45.0)
        slice_noise = (random.random() * 2.0 - 1.0) * slice_env * 0.7
        # meaty chop body
        body_env = math.exp(-t * (18.0 if not heavy else 12.0))
        f_body = (130.0 if not heavy else 85.0) * math.exp(-t * 10.0)
        body = math.sin(2.0 * math.pi * f_body * t) * body_env
        # metallic blade sting
        blade_env = math.exp(-t * 25.0)
        blade_ring = (
            math.sin(2.0 * math.pi * 1400.0 * t) * 0.4 +
            math.sin(2.0 * math.pi * 2100.0 * t) * 0.3
        ) * blade_env
        s = body * 0.8 + slice_noise * 0.6 + blade_ring * 0.5
        samples.append(s)
    return samples

def main():
    out_dir = os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "sfx")
    out_dir = os.path.abspath(out_dir)
    os.makedirs(out_dir, exist_ok=True)
    
    write_wav(os.path.join(out_dir, "sword_swing_1.wav"), make_sword_swing(1))
    write_wav(os.path.join(out_dir, "sword_swing_2.wav"), make_sword_swing(2))
    write_wav(os.path.join(out_dir, "sword_swing_3.wav"), make_sword_swing(3))
    write_wav(os.path.join(out_dir, "sword_heavy.wav"), make_sword_heavy())
    write_wav(os.path.join(out_dir, "sword_draw.wav"), make_sword_draw())
    write_wav(os.path.join(out_dir, "sword_sheathe.wav"), make_sword_sheathe())
    write_wav(os.path.join(out_dir, "jump_takeoff.wav"), make_jump_takeoff())
    write_wav(os.path.join(out_dir, "jump_land.wav"), make_jump_land())
    write_wav(os.path.join(out_dir, "roll_whoosh.wav"), make_roll_whoosh())
    write_wav(os.path.join(out_dir, "hit_impact_light.wav"), make_hit_impact(False))
    write_wav(os.path.join(out_dir, "hit_impact_heavy.wav"), make_hit_impact(True))
    print("All SFX generated successfully into:", out_dir)

if __name__ == "__main__":
    main()

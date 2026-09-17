#!/usr/bin/env python
"""戰鬥音效：CC0 真實錄音 → 專案音效。全部覆寫 assets/audio/sfx/。"""
import sys, os, numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sfx_lib import *

rng = np.random.default_rng(7)

print("== 載入來源 ==")
# 刀刃互擊：192 kHz 原始錄音，切出單次撞擊
clash = []
for pack, fn in [("medieval1", "Axe Katana Blade on Blade.wav"),
                 ("medieval1", "Dagger Katana Blade on Blade.wav"),
                 ("medieval2", "Seax Katana Blade on Blade.wav"),
                 ("medieval2", "Spear Katana Blade on Blade.wav"),
                 ("medieval1", "Mace Katana Blade.wav")]:
    p = src(pack, fn)
    if not os.path.exists(p):
        print("  缺:", fn); continue
    hits = slice_hits(load(p), thresh=0.28, min_gap=0.28, dur=0.6)
    clash += hits
    print(f"  {fn}: {len(hits)} 次撞擊")
print(f"  刀刃撞擊素材共 {len(clash)} 段")

swish = [load(src("swishes", "swishes", f"swish-{i}.wav")) for i in range(1, 14)]
print(f"  揮空聲 {len(swish)} 段")
fire = load(os.path.join(os.path.dirname(EX), "dl", "fire.wav"))
print(f"  火焰 {len(fire)/SR:.1f}s")
melee_sword = load(src("melee", "melee sounds", "sword sound.wav"))
ding = [load(src("dings", f"ding.{i}.ogg")) for i in range(1, 5)]

def pick(lst, i):
    return lst[i % len(lst)]

def fire_layer(dur, seed, lo=180, hi=2600, g=-9.0):
    """從火焰錄音取一段做火焰層。"""
    r = np.random.default_rng(seed)
    n = int(dur * SR)
    a = r.integers(0, max(len(fire) - n - 1, 1))
    seg = fire[a:a + n].copy()
    seg = hp(lp(seg, hi), lo)
    # 起音重、尾巴收
    e = np.exp(-np.linspace(0, 3.2, len(seg)))
    return gain(seg * e, g)

print("\n== 揮刀（無火）==")
for i in range(3):
    s = pick(swish, i * 3)
    s = resample_pitch(s, [1.0, 0.92, 1.12][i])
    save(f"sword_swing_{i+1}.wav", gain(s, 0.0), fout=0.08)

print("\n== 炎刃揮擊（揮空 + 火焰層）==")
for i in range(3):
    s = pick(swish, i * 3 + 1)
    s = resample_pitch(s, [1.05, 0.95, 1.18][i])
    d = len(s) / SR
    save(f"sword_fire_swing_{i+1}.wav", mix(gain(s, -1.0), fire_layer(d * 1.15, 100 + i)), fout=0.09)

print("\n== 重擊（慢揮 + 低頻撞擊）==")
heavy_s = resample_pitch(pick(swish, 5), 1.45)
heavy_c = resample_pitch(clash[rng.integers(0, len(clash))], 1.35)
save("sword_heavy.wav", mix(gain(heavy_s, -2.0), gain(lp(heavy_c, 1400), -4.0),
                            fire_layer(len(heavy_s) / SR, 55, g=-11)), fout=0.12)

print("\n== 命中（刀刃撞擊）==")
idx = rng.permutation(len(clash))
save("hit_impact_light.wav", gain(clash[idx[0]], 0.0))
save("hit_impact_heavy.wav", gain(lp(resample_pitch(clash[idx[1]], 1.3), 5000), 0.0), fout=0.09)

print("\n== 炎刃命中（撞擊 + 火焰爆燃）==")
for i, nm in enumerate(["hit_fire_light_1", "hit_fire_light_2"]):
    c = clash[idx[2 + i]]
    save(f"{nm}.wav", mix(gain(c, -1.0), fire_layer(len(c) / SR * 1.2, 200 + i, g=-7)))
c = resample_pitch(clash[idx[4]], 1.25)
save("hit_fire_heavy.wav", mix(gain(c, -1.0), fire_layer(len(c) / SR * 1.3, 210, lo=120, g=-5)), fout=0.11)
c = clash[idx[5]]
sp = resample_pitch(pick(swish, 8), 1.3)
save("hit_fire_spin.wav", mix(gain(c, -2.0), gain(sp, -4.0), fire_layer(0.75, 220, lo=140, g=-5)), fout=0.12)

print("\n== 拔刀 / 納刀 ==")
# 拔刀：金屬摩擦 —— 用 melee sword sound 的起音段 + ding 尾韻
dr = trim(melee_sword)[:int(0.55 * SR)]
save("sword_draw.wav", mix(gain(hp(dr, 400), -1.0), gain(resample_pitch(ding[3], 0.85), -12.0)), fout=0.14)
sh = resample_pitch(trim(melee_sword)[:int(0.45 * SR)], 1.18)
save("sword_sheathe.wav", gain(lp(sh, 6500), -2.0), fout=0.16)

print("\n== 彈刀 / 格擋（專用素材，不再靠調音高頂替）==")
# 彈刀：清脆金屬 —— 刀刃撞擊高音域 + ding 金屬泛音
dc = resample_pitch(clash[idx[6]], 0.82)
save("deflect_clang.wav", mix(gain(hp(dc, 800), 0.0), gain(resample_pitch(ding[1], 0.9), -9.0)), fout=0.18)
# 格擋：悶響 —— 低通 + 無泛音
bc = resample_pitch(clash[idx[7]], 1.15)
save("block_thud.wav", gain(lp(bc, 900), 0.0), fout=0.10)

print("\n== 受傷 / 倒地 ==")
hurt_c = resample_pitch(clash[idx[8]], 1.4)
save("hurt_impact.wav", gain(lp(hurt_c, 1100), -1.0), fout=0.12)
print("\n完成。")

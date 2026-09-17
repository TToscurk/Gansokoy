#!/usr/bin/env python
"""腳步 + 動物音效：CC0 素材 → 專案音效。"""
import sys, os, numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sfx_lib import *

rng = np.random.default_rng(11)
os.makedirs(os.path.join(OUT, "..", "sfx"), exist_ok=True)

print("== 腳步來源 ==")
# CC0 世界沒有真正的「草地」腳步錄音（見 docs/audio_sources.md 的說明）。
# 草地 = 落葉(leaves) 的軟脆層 + 沙地(sand) 的顆粒層，兩者疊合最接近踏草。
leaves = [load(src("diffsteps", f"leaves0{i}.ogg")) for i in (1, 2)]
gravel = load(src("diffsteps", "gravel.ogg"))
mud = load(src("diffsteps", "mud02.ogg"))
stone_src = [load(src("diffsteps", "stone01.ogg"))]
wood_src = [load(src("diffsteps", f"wood0{i}.ogg")) for i in (1, 2, 3)]
FS = src("footsteps", "Fantozzi-footsteps", "ogg")
sand = [load(os.path.join(FS, f"Fantozzi-Sand{s}{i}.ogg")) for s in "LR" for i in (1, 2, 3)]
stone = [load(os.path.join(FS, f"Fantozzi-Stone{s}{i}.ogg")) for s in "LR" for i in (1, 2, 3)]
print(f"  leaves {len(leaves)}  sand {len(sand)}  stone {len(stone)}  wood {len(wood_src)}")


def align_onset(x, thresh=0.08, pre_ms=3.0):
    """把檔頭的空白切掉，讓混音的兩層在同一瞬間落地。

    ⚠ 不對齊的話，落葉與沙地兩個來源各自的起音位置不同，混起來會像
    「踏了兩次」—— 這是 v1 聽起來糊的原因之一。
    """
    pk = np.max(np.abs(x)) + 1e-9
    hits = np.where(np.abs(x) >= pk * thresh)[0]
    if len(hits) == 0:
        return x
    a = max(0, hits[0] - int(pre_ms * 0.001 * SR))
    return x[a:]


def short_step(x, dur, decay=5.5):
    """截到 dur 秒並套指數衰減 —— 腳步是「一擊即收」，不是慢慢淡出。

    ⚠ v1 沒有這道包絡，拖尾(-40 dB) 長達 0.29-0.35 s，幾乎等於整個檔長。
      跑步步距只有 0.345 s（2.9 步/秒），每一步的尾巴還沒收完下一步就進來，
      疊成一片連續沙沙聲 —— 這就是「不乾淨」的主因。
    """
    x = align_onset(x)
    n = int(dur * SR)
    x = x[:n]
    if len(x) == 0:
        return x
    return x * np.exp(-np.linspace(0.0, decay, len(x)))


def grass_step(i, run=False):
    """草地腳步 v2：短、乾、一擊即收。

    v1 → v2 的三個改動：
      1. 硬性限長 + 指數衰減（走 0.30 s / 跑 0.24 s），跑步不再重疊
      2. 跑步的整段 mud02 低頻噪音層拿掉 —— 它給的是「悶濁」不是「重量」；
         改用 0.10 s 的短低頻落地脈衝，重量感來自瞬態而不是持續噪音
      3. 落葉層高通拉到 1350 Hz 並加低通 6200 Hz，只留草葉摩擦的脆感，
         砍掉它的刺耳嘶聲與和沙地重疊的中頻（重疊 = 糊）
    """
    pr = [0.96, 1.0, 1.04, 1.08][i % 4]
    lv = align_onset(resample_pitch(leaves[i % len(leaves)], pr))
    sd = align_onset(resample_pitch(sand[(i * 2 + 1) % len(sand)], pr * 1.02))

    dur = 0.24 if run else 0.30

    # 草葉摩擦：只要 1.35-6.2 kHz 的脆，不要更高的嘶聲
    rustle = short_step(hp(lp(lv, 6200), 1350), dur, 5.5)
    # 落地體感：90-1450 Hz，高通砍掉整段的隆隆低頻
    body = short_step(hp(lp(sd, 1450), 90), dur, 6.0)

    out = mix(
        gain(rustle, -7.0 if run else -8.5),
        gain(body, -3.5 if run else -5.0),
    )

    if run:
        # 跑步的重量：一個 0.10 s 的低頻脈衝，不是一整段泥聲。
        thud = short_step(lp(sand[(i + 2) % len(sand)], 650), 0.10, 8.0)
        out = mix(out, gain(thud, -9.0))

    return out[:int(dur * SR)]


print("\n== 草地腳步 v2（走 4 + 跑 4）==")
for i in range(4):
    # fout 縮到 25 ms：包絡已經收乾淨，長淡出只會把拖尾加回來。
    save(f"step_grass_walk_{i+1}.wav", grass_step(i), fin=0.002, fout=0.025)
for i in range(4):
    save(f"step_grass_run_{i+1}.wav", grass_step(i + 1, run=True), fin=0.002, fout=0.025)

print("\n== 其他地表（石板 / 木板 / 土路）==")
for i in range(3):
    save(f"step_stone_{i+1}.wav", gain(stone[i * 2], -1.0), fin=0.002, fout=0.04)
for i in range(3):
    save(f"step_wood_{i+1}.wav", gain(wood_src[i], -1.0), fin=0.002, fout=0.04)
for i in range(3):
    d = [gravel, mud, resample_pitch(gravel, 1.12)][i]
    save(f"step_dirt_{i+1}.wav", gain(lp(d, 5200), -1.5), fin=0.002, fout=0.04)

print("\n== 山犬（敵人）==")
# dog-growl / snarl / grumble 是 96 kHz 真實錄音；降頻並變調成大型犬科
dog_growl = load(src("dog", "dog", "dog-growl.flac"))
dog_snarl = load(src("dog", "dog", "dog-snarl.flac"))
dog_grumble = load(src("dog", "dog", "dog-grumble.flac"))
wolf_howl = load(os.path.join(CM, "wolf_howl.ogg"))

# 變慢 = 體型變大。山犬約 2.0 m，比家犬大，壓低音高。
save("wolf_growl.wav", gain(lp(resample_pitch(dog_growl, 1.35), 7000), 0.0), fout=0.12)
save("wolf_snarl.wav", gain(resample_pitch(dog_snarl, 1.28), 0.0), fout=0.10)
save("wolf_grumble.wav", gain(lp(resample_pitch(dog_grumble, 1.4), 5500), -2.0), fout=0.14)
# 撲擊：咆哮起音 + 撲出的氣音
save("wolf_attack.wav", mix(gain(resample_pitch(dog_snarl, 1.15), 0.0),
                            gain(lp(resample_pitch(dog_growl, 1.5), 1800), -6.0)), fout=0.10)
# 受傷：短促高音嗚咽
save("wolf_hurt.wav", gain(resample_pitch(trim(dog_grumble)[:int(0.35 * SR)], 0.72), 0.0), fout=0.13)
# 死亡：長嗚咽下墜
dy = resample_pitch(trim(dog_grumble), 0.8)
n = len(dy)
dy = dy * np.linspace(1.0, 0.25, n)  # 音量下墜
save("wolf_death.wav", gain(lp(dy, 4200), -1.0), fout=0.25)

# 狼嚎（公有領域錄音）：取最飽滿的一段當遠景嚎叫
hb, hw = env_blocks(wolf_howl, 100.0)
best = int(np.argmax(np.convolve(hb, np.ones(12) / 12, mode="same")))
a = max(int(best * hw - 0.5 * SR), 0)
save("wolf_howl_distant.wav", gain(lp(wolf_howl[a:a + int(4.5 * SR)], 6000), -3.0), fin=0.15, fout=0.6)

print("\n== 環境鳥鳴 ==")
# birdsCrickets 是 44.1 kHz 乾淨單音，適合近距離隨機鳥叫
for i, fn in enumerate(["bird.wav", "bird2.wav"]):
    b = load(src("birdscrickets", "birdsCrickets", fn))
    save(f"bird_chirp_{i+1}.wav", gain(b, -2.0), fout=0.08)
b3 = resample_pitch(load(src("birdscrickets", "birdsCrickets", "bird.wav")), 0.88)
save("bird_chirp_3.wav", gain(b3, -2.5), fout=0.08)
# 森林鳥那包是 8 kHz，只堪當遠景層 —— 低通掉混疊噪聲
fb = load(src("forestbirds", "Forest Birds", "Forest Birds 4.wav"))
save("bird_forest_distant.wav", gain(lp(fb, 3600), -6.0), fin=0.2, fout=0.5)

print("\n== 夜間動物 ==")
bn = load(src("birdscrickets", "birdsCrickets", "birdNight.wav"))
save("night_bird.wav", gain(bn, -3.0), fout=0.12)
# 貓頭鷹：Commons 的是 CC BY-SA（排除），改用夜鳥錄音壓低變成梟鳴
owl = resample_pitch(bn, 1.55)
save("owl_hoot.wav", gain(lp(owl, 2200), -2.0), fin=0.02, fout=0.25)
frog = load(src("birdscrickets", "birdsCrickets", "frog.wav"))
save("frog_croak.wav", gain(frog, -3.0), fout=0.10)

print("\n== 水邊（鴨 / 鯉魚）==")
# ⚠ CC0／PD 沒有鴨叫錄音（Commons 的鴨聲全是 CC BY-SA，已排除）。
# 鴨子目前只有入水／拍水聲，**叫聲仍是缺口**，見 docs/audio_sources.md。
sp = os.path.join(EX, "splash7z", "ezwa-water_splash")
for i in range(1, 4):
    p = os.path.join(sp, f"water_splash-0{i}.flac")
    if os.path.exists(p):
        save(f"water_splash_{i}.wav", gain(load(p), -3.0), fout=0.12)
# 鯉魚擺尾：小水花，音量更低、更悶
p = os.path.join(sp, "water_splash-04.flac")
if os.path.exists(p):
    save("fish_splash.wav", gain(lp(resample_pitch(load(p), 1.2), 3000), -8.0), fout=0.15)

print("\n完成。")

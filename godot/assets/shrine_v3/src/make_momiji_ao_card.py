"""伊呂波楓春季新綠葉卡：由既有的 momiji_card.png（紅）換色，保留葉形、alpha 與明暗紋理。
  python godot/assets/shrine_v3/src/make_momiji_ao_card.py
輸出 godot/assets/shrine_v3/tex/veg/momiji_ao_card.png。
做法：每個不透明畫素取 sRGB 相對亮度÷平均亮度＝明暗係數，乘上目標平均色（偏黃的嫩綠，比 broad_card 亮一點）；
     另依葉片內的明暗把色相往黃（亮處）／綠（暗處）推一點，避免整張單色。
"""
import os

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
TEX = os.path.join(HERE, '..', 'tex', 'veg')
SRC = os.path.join(TEX, 'momiji_card.png')
DST = os.path.join(TEX, 'momiji_ao_card.png')

TARGET = np.array([0.46, 0.58, 0.17])      # sRGB 平均（broad_card 是 0.35, 0.53, 0.18）
LIGHT = np.array([0.56, 0.64, 0.20])
DARK = np.array([0.30, 0.46, 0.13])

a = np.asarray(Image.open(SRC).convert('RGBA')).astype(np.float64) / 255.0
rgb, al = a[..., :3], a[..., 3]
m = al > 0.45
lum = rgb @ np.array([0.2126, 0.7152, 0.0722])
mean = lum[m].mean()
k = np.clip(lum / max(mean, 1e-4), 0.0, 2.2)
t = np.clip((k - 0.6) / 0.9, 0.0, 1.0)[..., None]
col = (DARK * (1 - t) + LIGHT * t)
col = col * (TARGET / col[m].mean(0))
out = np.clip(col * np.clip(k, 0.0, 1.6)[..., None] / np.clip(k[m].mean(), 1e-4, None), 0.0, 1.0)
img = np.dstack([out, al])
Image.fromarray((img * 255 + 0.5).astype(np.uint8), 'RGBA').save(DST)
print('[MOMIJI_AO] %s  mean sRGB %s  cover %.2f' % (os.path.relpath(DST, HERE), np.round(out[m].mean(0), 3), m.mean()))

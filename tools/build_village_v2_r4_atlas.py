#!/usr/bin/env python3
"""人間之里 V2 P5 R4：Hero 貼圖產生器。

  python tools/build_village_v2_r4_atlas.py

1. 參道鳥居 atlas（額「龍神社」、注連繩、房、紙垂）→ sando_torii/
2. 龍神像底色（dragon_statue/）：取 Protected 原檔 maps/village/gen/龍神像/龍神像_base_color.webp（唯讀），
   4096 → 2048、線性空間增益到石材目標色（與 V2_Stone 同族），另存 JPG；原檔不動。
   原檔法線貼圖實測近乎全平（RGB 平均 127／127／253，5–95 百分位 ±2）→ 不沿用。

沿用 tools/build_village_v2_textures.py（取色、紙／木、.import、.tres 規約）；不重建共享材質庫與 R1–R3 atlas。
輸出：godot/assets/village_v2/sando_torii/{sando_torii_atlas.png, atlas.json, V2_SandoTorii.tres}。
參考：docs/reference/神社/博麗神社鳥居.png（額：褐色木地、黑墨直書、古金框；注連繩＋房 3＋紙垂 2）。
額字：「龍神社」（使用者 2026-09-25 裁示）。額面實寸 0.56 × 0.90 m（build_sando_torii.py PLAQUE），
字面縮放照實寸換算，貼上後是正方字（R2 提燈教訓：atlas 區域長寬比 ≠ 實物長寬比時字會被拉扁）。
"""
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_village_v2_textures as T  # noqa: E402

G = T.G
AID = 'sando_torii'
NAME = 'V2_SandoTorii'
SIZE = 1024
PLAQUE_M = (0.56, 0.90)       # 額面寬 × 高（公尺）；與 build_sando_torii.py 一致
TEXT = '龍神社'

REGIONS = {
    'plaque': (0, 0, 512, 1024),          # 額面（含古金框）
    'rope': (512, 0, 1024, 256),          # 注連繩（u 沿繩長、v 繞一圈）
    'shide': (512, 256, 768, 512),        # 紙垂（白紙）
    'tassel': (768, 256, 1024, 512),      # 房（稻草直紋）
    'gold': (512, 512, 768, 768),         # 額框側面、飾金具
    'wood_dark': (768, 512, 1024, 768),   # 額背板側面
}


def _hex(h):
    return tuple(int(v * 255) for v in T.hexrgb(h))


def build():
    atlas = Image.new('RGB', (SIZE, SIZE), (40, 32, 26))
    R = REGIONS

    def sz(k):
        x0, y0, x1, y1 = R[k]
        return x1 - x0, y1 - y0

    # 額：淺褐木地（×albedo_k 0.42 後仍與黑字拉得開）、古金外框＋內側細框、黑墨直書三字
    w, h = sz('plaque')
    pq = T._wood_patch(w, h, '#B89060', 401).rotate(90, expand=True).resize((w, h))
    d = ImageDraw.Draw(pq)
    fx = int(w * 0.080)            # 框寬（0.045 m）
    fy = int(h * 0.050)
    d.rectangle((0, 0, w - 1, fy), fill=_hex('#C9972F'))
    d.rectangle((0, h - fy, w - 1, h - 1), fill=_hex('#C9972F'))
    d.rectangle((0, 0, fx, h - 1), fill=_hex('#C9972F'))
    d.rectangle((w - fx, 0, w - 1, h - 1), fill=_hex('#C9972F'))
    d.rectangle((fx + 8, fy + 8, w - fx - 9, h - fy - 9), outline=_hex('#7A5A22'), width=5)
    # 字：每字 0.22 m 見方 → 像素 (0.22/0.56·w, 0.22/0.90·h)
    ch_m = 0.22
    gw, gh = int(ch_m / PLAQUE_M[0] * w), int(ch_m / PLAQUE_M[1] * h)
    pitch = int(gh * 1.06)
    y0 = h // 2 - pitch
    for i, c in enumerate(TEXT):
        gl = Image.new('L', (256, 256), 0)
        T._text(gl, (128, 136), c, 232, 255, stroke=4)
        gl = gl.resize((gw, gh), Image.LANCZOS)
        pq.paste(Image.new('RGB', (gw, gh), (14, 10, 8)), (w // 2 - gw // 2, y0 + i * pitch - gh // 2), gl)
    atlas.paste(pq, R['plaque'][:2])
    # 注連繩：稻草底＋螺旋撚紋（u 沿繩長 10 撚、v 繞一圈 2 股 → 貼上管狀網格是斜向螺旋）
    w, h = sz('rope')
    base = T.hexrgb('#C8B07A')
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    stripe = 0.5 + 0.5 * np.sin((xx / w * 10.0 + yy / h * 2.0) * 2 * np.pi)
    rng = np.random.default_rng(402)
    fib = rng.normal(0, 0.05, (h, w)).astype(np.float32)
    shade = 0.72 + 0.30 * stripe + fib
    rp = np.clip(base[None, None, :] * shade[..., None], 0, 1)
    atlas.paste(Image.fromarray((rp * 255).astype(np.uint8)), R['rope'][:2])
    # 紙垂：白紙
    atlas.paste(T._paper(*sz('shide'), 403, tone='#F1EEE6'), R['shide'][:2])
    # 房：稻草直紋（v 沿垂下方向）
    w, h = sz('tassel')
    fib = rng.normal(0, 1, (1, w)).astype(np.float32)
    tv = np.clip(T.hexrgb('#C4AA70')[None, None, :] * (0.86 + 0.10 * fib[..., None]) *
                 np.linspace(1.0, 0.85, h, dtype=np.float32)[:, None, None], 0, 1)
    atlas.paste(Image.fromarray((np.broadcast_to(tv, (h, w, 3)) * 255).astype(np.uint8)), R['tassel'][:2])
    # 古金、暗木
    atlas.paste(T._cloth(*sz('gold'), '#C9972F', 404), R['gold'][:2])
    atlas.paste(T._wood_patch(*sz('wood_dark'), '#4A3222', 405), R['wood_dark'][:2])

    out = f'{G}/assets/village_v2/{AID}'
    os.makedirs(out, exist_ok=True)
    atlas.save(f'{out}/{AID}_atlas.png', optimize=True)
    uv = {k: [x0 / SIZE, y0 / SIZE, x1 / SIZE, y1 / SIZE] for k, (x0, y0, x1, y1) in R.items()}
    with open(f'{out}/atlas.json', 'w', encoding='utf-8', newline='\n') as f:
        json.dump({'_note': f'{AID} Hero atlas（UV 左上原點；Blender 端 v 要 1−v）。由 tools/build_village_v2_r4_atlas.py 產生。'
                   f' 額字「{TEXT}」（使用者 2026-09-25）；額面 {PLAQUE_M[0]}×{PLAQUE_M[1]} m、字 {ch_m} m 見方。',
                   'size': SIZE, 'regions': uv, 'font': 'kaiu.ttf（標楷體，Windows 內建）'}, f, ensure_ascii=False, indent=1)
        f.write('\n')
    T.write_import(f'res://assets/village_v2/{AID}/{AID}_atlas.png', False)
    T.write_tres(f'{out}/{NAME}.tres', NAME, {'albedo': f'res://assets/village_v2/{AID}/{AID}_atlas.png'},
                 ['roughness = 0.9'])
    print('atlas →', f'{out}/{AID}_atlas.png')


DRAGON_SRC = f'{G}/maps/village/gen/龍神像/龍神像_base_color.webp'   # Protected，唯讀
DRAGON_TARGET = '#958C78'


def build_dragon():
    out = f'{G}/assets/village_v2/dragon_statue'
    os.makedirs(out, exist_ok=True)
    im = Image.open(DRAGON_SRC).convert('RGB').resize((2048, 2048), Image.LANCZOS)
    a = np.asarray(im).astype(np.float32) / 255.0
    lin = np.where(a <= 0.04045, a / 12.92, ((a + 0.055) / 1.055) ** 2.4)
    mean_srgb = a.reshape(-1, 3).mean(0)
    tgt = np.array(T.hexrgb(DRAGON_TARGET), np.float32)
    tl = np.where(tgt <= 0.04045, tgt / 12.92, ((tgt + 0.055) / 1.055) ** 2.4)
    ml = np.where(mean_srgb <= 0.04045, mean_srgb / 12.92, ((mean_srgb + 0.055) / 1.055) ** 2.4)
    lin = np.clip(lin * (tl / np.maximum(ml, 1e-4)), 0, 1)
    srgb = np.where(lin <= 0.0031308, lin * 12.92, 1.055 * np.power(lin, 1 / 2.4) - 0.055)
    res = (np.clip(srgb, 0, 1) * 255).astype(np.uint8)
    Image.fromarray(res).save(f'{out}/dragon_statue_albedo.jpg', quality=90)
    T.write_import(f'res://assets/village_v2/dragon_statue/dragon_statue_albedo.jpg', False)
    T.write_tres(f'{out}/V2_DragonStatue.tres', 'V2_DragonStatue',
                 {'albedo': 'res://assets/village_v2/dragon_statue/dragon_statue_albedo.jpg'}, ['roughness = 0.92'])
    print('dragon albedo → mean %s（原 %s，目標 %s）' % (
        '#%02X%02X%02X' % tuple(int(v) for v in res.reshape(-1, 3).mean(0)),
        '#%02X%02X%02X' % tuple(int(v * 255) for v in mean_srgb), DRAGON_TARGET))


if __name__ == '__main__':
    build()
    build_dragon()

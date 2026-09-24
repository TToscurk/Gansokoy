#!/usr/bin/env python3
"""人間之里 V2 共享材質庫 v1 ＋ 鈴奈庵 Hero atlas 產生器（P5 R1）。

  python tools/build_village_v2_textures.py [--cache=<dir>]

來源：Poly Haven CC0（2K jpg：diffuse／nor_gl／rough）。原檔只放下載快取（預設
%LOCALAPPDATA%/hermes/cache/scratch/p5_r1/ph_src），缺檔自動下載；輸出才進 repo。
輸出：
  godot/assets/village_v2/_matlib/V2_*_{albedo,normal,rough}.jpg、V2_*.tres、matlib.json
  godot/assets/village_v2/suzunaan/suzunaan_atlas.png、suzunaan_emit.png、atlas.json、V2_Suzunaan.tres
規約：
  - 貼圖一律 2048²、Godot 端 VRAM 壓縮（寫 .import：compress/mode=2；法線 normal_map=1）。
  - 貼圖本身照「看起來對」的顏色（概念圖取色）；材質 albedo_color＝albedo_k（預設 ALBEDO_K 0.42，與
    gen_village_v2.gd 灰盒同一套反照率換算；飽和漆色個別調高並在 note 記原因），
    vertex_color_use_as_albedo＝true（深木／板材／土壁色用頂點色乘上去）。
  - 網格 UV 以公尺計：1 UV 單位＝tile_m 公尺（Blender 腳本讀 matlib.json 的 tile_m）。
  - 木紋一律沿 V（貼圖直向）；來源木紋橫向者先轉 90°（法線 R/G 同步換算）。
"""
import hashlib
import json
import math
import os
import random
import sys
import urllib.request

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

R = os.path.dirname(os.path.dirname(os.path.abspath(__file__))).replace('\\', '/')
G = R + '/godot'
LIB = G + '/assets/village_v2/_matlib'
SZ = G + '/assets/village_v2/suzunaan'
CACHE = os.path.join(os.environ.get('LOCALAPPDATA', R), 'hermes/cache/scratch/p5_r1/ph_src')
for a in sys.argv[1:]:
    if a.startswith('--cache='):
        CACHE = a[8:]
ALBEDO_K = 0.42        # 與 godot/tools/gen_village_v2.gd ALBEDO_K 相同
SIZE = 2048
FONT_KAI = 'C:/Windows/Fonts/kaiu.ttf'   # 標楷體：招牌、暖簾、貸本牌

# 目標色＝概念圖取色（docs/reference/重點地標/鈴耐庵.png、鳥居.png；vision 判讀，見 docs/plans §15）
MATS = {
    'V2_Wood': {
        'src': 'rough_wood', 'rot90': False, 'mode': 'gain', 'target': '#7A6445', 'desat': 0.15,
        'tile_m': 1.2, 'rough': (0.78, 0.95), 'normal_strength': 1.0,
        'note': '結構木（柱、梁、板、格子）。頂點色：結構深木 0.60、下見板 0.88、看板木另走 atlas。'},
    'V2_Plaster': {
        'src': 'clay_plaster', 'rot90': False, 'mode': 'luma', 'target': '#C9BEA6', 'contrast': 0.55,
        'tile_m': 2.0, 'rough': (0.85, 0.97), 'normal_strength': 0.6,
        'note': '灰泥／土壁。頂點色 0.97 ＝ #C4B9A1（概念圖二樓灰泥）；乘 (0.86,0.76,0.58) ≈ 黃土色 #A88A5E。'},
    'V2_Kawara': {
        'src': 'grey_roof_tiles', 'rot90': False, 'mode': 'gain', 'target': '#66645B', 'desat': 0.45,
        'tile_m': 2.4, 'tile_u_m': 4.24, 'columns': 16, 'courses': 10, 'downslope': '+v',
        'rough': (0.55, 0.85), 'normal_strength': 1.0,
        'note': '桟瓦：貼圖 16 欄 × 10 段（法線／反照率 FFT 實測）。U 用 tile_u_m 4.24 → 欄寬 0.265 m（桟瓦働き幅），'
                'V 用 tile_m 2.4 → 段長 0.24 m；瓦唇朝 +v（貼圖下方＝簷側，法線 G 尖峰 p1 −0.31）。'
                '屋面網格波峰對齊 crest_u（每欄一波）。'},
    'V2_Stone': {
        'src': 'rock_01', 'rot90': False, 'mode': 'gain', 'target': '#99917C', 'desat': 0.5,
        'tile_m': 1.5, 'rough': (0.80, 0.97), 'normal_strength': 1.0,
        'note': '台基石、踏石、鳥居台座。'},
    'V2_Metal': {
        'src': 'rusty_metal_sheet', 'rot90': False, 'mode': 'gain', 'target': '#454238', 'desat': 0.75,
        'tile_m': 1.0, 'rough': (0.55, 0.80), 'normal_strength': 0.8, 'metallic': 0.35,
        'note': '暗銅／鐵：鳥居笠木包板、柱箍、飾金具。'},
    'V2_WoodRed': {
        'src': 'wood_peeling_paint_weathered', 'rot90': True, 'mode': 'paint', 'paint': '#A8462E',
        'wood': '#5E4A38', 'tile_m': 1.5, 'rough': (0.65, 0.92), 'normal_strength': 0.7, 'albedo_k': 0.80,
        'note': '朱漆木（剝落處露木）：鳥居柱、貫、島木、額束。來源木紋橫向 → 轉 90°。albedo_k 0.80：飽和朱色照 '
                '0.42 會壓成暗褐（r1 預覽 vision 判讀「dark brown-maroon」），露木改暗 #5E4A38 免得淡色條紋搶畫面。'},
}


def srgb2lin(c):
    c = np.asarray(c, dtype=np.float32)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def lin2srgb(c):
    c = np.clip(np.asarray(c, dtype=np.float32), 0.0, 1.0)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1 / 2.4) - 0.055)


def hexrgb(h):
    h = h.lstrip('#')
    return np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)], dtype=np.float32)


def rgbhex(c):
    c = np.clip(np.round(np.asarray(c) * 255), 0, 255).astype(int)
    return '#%02X%02X%02X' % tuple(c)


def sha256(p):
    h = hashlib.sha256()
    with open(p, 'rb') as f:
        for b in iter(lambda: f.read(1 << 20), b''):
            h.update(b)
    return h.hexdigest()


def fetch(src):
    os.makedirs(CACHE, exist_ok=True)
    want = {'diff': 'Diffuse', 'nor': 'nor_gl', 'rough': 'Rough'}
    out = {}
    files = None
    for k, key in want.items():
        p = f'{CACHE}/{src}_{k}_2k.jpg'
        if not os.path.exists(p):
            if files is None:
                req = urllib.request.Request(f'https://api.polyhaven.com/files/{src}',
                                             headers={'User-Agent': 'Mozilla/5.0 shrine-asset-pipeline'})
                files = json.loads(urllib.request.urlopen(req, timeout=60).read())
            url = files[key]['2k']['jpg']['url']
            req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0 shrine-asset-pipeline'})
            with open(p, 'wb') as f:
                f.write(urllib.request.urlopen(req, timeout=120).read())
        out[k] = p
    return out


def load(p, rot90=False):
    a = np.asarray(Image.open(p).convert('RGB').resize((SIZE, SIZE), Image.LANCZOS), dtype=np.float32) / 255.0
    return np.ascontiguousarray(np.rot90(a, 1)) if rot90 else a


def albedo(a, m):
    lin = srgb2lin(a)
    tgt = srgb2lin(hexrgb(m.get('target', '#808080')))
    if m['mode'] == 'gain':
        lum = (lin * np.array([0.2126, 0.7152, 0.0722])).sum(-1, keepdims=True)
        lin = lin * (1 - m.get('desat', 0.0)) + lum * m.get('desat', 0.0)
        # 以 sRGB 平均貼齊目標：迭代兩次（非線性）
        for _ in range(3):
            mean = lin2srgb(lin).reshape(-1, 3).mean(0)
            lin = lin * (srgb2lin(hexrgb(m['target'])) / np.maximum(srgb2lin(mean), 1e-4))
        return lin2srgb(lin)
    if m['mode'] == 'luma':
        lum = (lin * np.array([0.2126, 0.7152, 0.0722])).sum(-1, keepdims=True)
        rel = np.power(lum / lum.mean(), m['contrast'])
        out = lin2srgb(tgt * rel)
        for _ in range(3):
            mean = out.reshape(-1, 3).mean(0)
            out = lin2srgb(srgb2lin(out) * (srgb2lin(hexrgb(m['target'])) / np.maximum(srgb2lin(mean), 1e-4)))
        return out
    if m['mode'] == 'paint':
        # 來源：深藍綠漆（R 低）＋棕木（R 高）。以「暖度」分：木 R−B 大、漆 R−B 小
        warm = a[..., 0] - a[..., 2]
        lum = (lin * np.array([0.2126, 0.7152, 0.0722])).sum(-1)
        # 門檻 0.13：露木約 15 %。來源暖度雙峰（漆 ≤0.03、木 ≥0.10；p60 0.031、p80 0.149）；
        # 0.03 → 露木 32 %、0.07 → 27.5 %，整體偏褐讀不出朱漆（vision 判讀 r1）
        wmask = np.clip((warm - 0.13) / 0.08, 0, 1)
        wmask = np.asarray(Image.fromarray((wmask * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2)),
                           dtype=np.float32)[..., None] / 255.0
        rel = np.power(lum / lum.mean(), 0.8)[..., None]
        paint = srgb2lin(hexrgb(m['paint'])) * rel
        wood = srgb2lin(hexrgb(m['wood'])) * np.power(lum / lum.mean(), 0.9)[..., None]
        return lin2srgb(paint * (1 - wmask) + wood * wmask), float(wmask.mean())
    raise ValueError(m['mode'])


def normal(a, m):
    n = a * 2.0 - 1.0
    if m.get('rot90'):
        # 影像逆時針轉 90°：切線空間向量 (x, y) → (−y, x)
        n = np.stack([-n[..., 1], n[..., 0], n[..., 2]], -1)
    s = m.get('normal_strength', 1.0)
    n[..., 0] *= s
    n[..., 1] *= s
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return n * 0.5 + 0.5


def rough(a, m):
    g = a[..., 0]
    lo, hi = m['rough']
    g = (g - g.min()) / max(g.max() - g.min(), 1e-4)
    return lo + (hi - lo) * g


def save_jpg(a, p, q=90):
    Image.fromarray(np.clip(np.round(a * 255), 0, 255).astype(np.uint8)).save(p, quality=q, subsampling=0)


def kawara_crest_u(nor, columns):
    """桟瓦法線圖：沿 U 找「波峰」相位（R 由 <0.5 轉 >0.5，法線由朝 −U 轉朝 +U），回傳 [0, 1/columns) 內的 u。"""
    prof = nor[..., 0].mean(0) - 0.5
    period = SIZE / float(columns)
    k = np.arange(SIZE)
    c = (prof * np.exp(-2j * np.pi * k / period)).sum()
    # prof ≈ A·sin(2π(u−u0)/P)：R 上升過零點 = 波峰。sin 的相位 → u0
    phase = np.angle(c) + np.pi / 2
    u0 = (-phase / (2 * np.pi)) * period
    return float((u0 % period) / SIZE)


IMPORT_TMPL = '''[remap]

importer="texture"
type="CompressedTexture2D"

[deps]

source_file="{src}"

[params]

compress/mode=2
compress/high_quality=false
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map={nm}
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=0
'''


def write_import(res_path, is_normal):
    p = G + '/' + res_path[len('res://'):] + '.import'
    if os.path.exists(p):
        # 保留既有 uid／remap：只確認壓縮參數
        s = open(p, encoding='utf-8').read()
        if 'compress/mode=2' in s and ('compress/normal_map=1' in s) == is_normal:
            return
    with open(p, 'w', encoding='utf-8', newline='\n') as f:
        f.write(IMPORT_TMPL.format(src=res_path, nm=1 if is_normal else 0))


def write_tres(path, name, tex, extra, k=ALBEDO_K):
    ids = []
    lines = []
    for i, (slot, rp) in enumerate(tex.items(), 1):
        ids.append((slot, str(i)))
        lines.append(f'[ext_resource type="Texture2D" path="{rp}" id="{i}"]')
    body = [f'resource_name = "{name}"', 'vertex_color_use_as_albedo = true',
            f'albedo_color = Color({k}, {k}, {k}, 1)']
    idm = dict(ids)
    if 'albedo' in idm:
        body.append(f'albedo_texture = ExtResource("{idm["albedo"]}")')
    body += extra
    if 'rough' in idm:
        body.append(f'roughness_texture = ExtResource("{idm["rough"]}")')
    if 'normal' in idm:
        body += ['normal_enabled = true', f'normal_texture = ExtResource("{idm["normal"]}")']
    if 'emit' in idm:
        # EMISSION_OP_MULTIPLY（1）：emission 色 × emission 貼圖；ADD（0）會把白色 emission 加在整張 atlas 上
        body += ['emission_enabled = true', 'emission = Color(1, 1, 1, 1)', 'emission_energy_multiplier = 0.4',
                 'emission_operator = 1', f'emission_texture = ExtResource("{idm["emit"]}")']
    txt = f'[gd_resource type="StandardMaterial3D" load_steps={len(lines) + 1} format=3]\n\n' + '\n'.join(lines) + \
        '\n\n[resource]\n' + '\n'.join(body) + '\n'
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.write(txt)


def build_matlib():
    os.makedirs(LIB, exist_ok=True)
    meta = {'_note': '人間之里 V2 共享材質庫 v1（P5 R1）。由 tools/build_village_v2_textures.py 產生，勿手改。',
            'version': 'v1', 'albedo_k': ALBEDO_K, 'size': SIZE, 'license': 'CC0 1.0（Poly Haven）',
            'materials': {}}
    for name, m in MATS.items():
        src = fetch(m['src'])
        a = load(src['diff'], m['rot90'])
        res = albedo(a, m)
        extra_meta = {}
        if isinstance(res, tuple):
            res, wood_frac = res
            extra_meta['exposed_wood_fraction'] = round(wood_frac, 3)
        nor = normal(load(src['nor'], m['rot90']), m)
        rgh = rough(load(src['rough'], m['rot90']), m)
        files = {}
        for k, arr, q in (('albedo', res, 90), ('normal', nor, 95), ('rough', np.repeat(rgh[..., None], 3, -1), 90)):
            fn = f'{name}_{k}.jpg'
            save_jpg(arr, f'{LIB}/{fn}', q)
            rp = f'res://assets/village_v2/_matlib/{fn}'
            write_import(rp, k == 'normal')
            files[k] = rp
        extra = [f'roughness = 1.0']
        if m.get('metallic'):
            extra.append(f'metallic = {m["metallic"]}')
        write_tres(f'{LIB}/{name}.tres', name, files, extra, m.get('albedo_k', ALBEDO_K))
        mean = res.reshape(-1, 3).mean(0)
        meta['materials'][name] = dict(
            {'tres': f'res://assets/village_v2/_matlib/{name}.tres', 'files': files, 'tile_m': m['tile_m'],
             'albedo_k': m.get('albedo_k', ALBEDO_K),
             'source': {'polyhaven_id': m['src'], 'url': f'https://polyhaven.com/a/{m["src"]}', 'license': 'CC0',
                        'sha256': {k: sha256(v) for k, v in src.items()}},
             'processing': {k: m[k] for k in m if k not in ('src', 'note', 'tile_m')},
             'target_srgb': m.get('target', m.get('paint')), 'albedo_mean_srgb': rgbhex(mean), 'note': m['note']},
            **extra_meta)
        if name == 'V2_Kawara':
            meta['materials'][name]['crest_u'] = round(kawara_crest_u(nor, m['columns']), 5)
            for k in ('tile_u_m', 'columns', 'courses', 'downslope'):
                meta['materials'][name][k] = m[k]
        print(f'{name}: {m["src"]} → mean {rgbhex(mean)}（目標 {m.get("target", m.get("paint"))}）', extra_meta)
    with open(f'{LIB}/matlib.json', 'w', encoding='utf-8', newline='\n') as f:
        json.dump(meta, f, ensure_ascii=False, indent=1)
        f.write('\n')
    return meta


# ───────────────────────── 鈴奈庵 atlas ─────────────────────────
ATLAS_REGIONS = {   # 像素（x0, y0, x1, y1），原點左上
    'sign': (0, 0, 1024, 320),            # 看板正面（自然邊木板＋鈴奈庵），3.2:1 ＝ 2.05 × 0.64 m（P4 簷 3.9 限制二樓牆高 ≈0.8 m）
    'noren': (0, 384, 1024, 640),         # 暖簾 5 片（片寬 1/5），3.5 m × 0.88 m
    'sign_wood': (0, 656, 512, 912),      # 看板側邊／背面素木
    'foliage': (512, 656, 1024, 912),     # 花盆葉叢＋淡紫花
    'swatch': (0, 928, 1024, 1184),       # 8 色塊（2 列 × 4）：見 SWATCH
    'spines': (1024, 0, 2048, 512),       # 書背 4 列（每列 128 px）
    'covers': (1024, 512, 1536, 704),     # 平放／正面朝外的書封 4 張（128×192）
    'kashihon': (1536, 512, 1664, 896),   # 「貸本」吊牌
    'shoji': (1664, 512, 1920, 1024),     # 障子（紙＋組子）
    'paper': (1920, 512, 2048, 768),      # 素紙（二樓格子窗後襯）
    'lantern': (1920, 768, 2048, 1024),   # 行燈紙面（黑色圓紋）
    'noren_back': (1024, 704, 1536, 768),  # 暖簾背面／邊（素靛）
}
SWATCH = ['#1E1B18', '#3A2E22', '#5B4A36', '#2F3A2A', '#6E5A74', '#8A7F6A', '#B8AE96', '#4A4E55']
SWATCH_NOTE = ['近黑（行燈框、鐵件）', '深褐（室內暗處）', '中褐（麻繩、竹）', '深綠（莖）', '淡紫（花）', '灰褐（陶）',
               '米白（紙邊、書口）', '藍灰（瓷瓶）']


def _wood_patch(w, h, color, seed):
    src = fetch('rough_wood')['diff']
    a = np.asarray(Image.open(src).convert('RGB'), dtype=np.float32) / 255.0
    rng = np.random.default_rng(seed)
    y0 = int(rng.integers(0, a.shape[0] - h)) if a.shape[0] > h else 0
    x0 = int(rng.integers(0, a.shape[1] - w)) if a.shape[1] > w else 0
    # 看板木紋橫向：取直向木紋再轉 90°
    crop = np.rot90(a, 1)[y0:y0 + h, x0:x0 + w]
    crop = np.asarray(Image.fromarray((crop * 255).astype(np.uint8)).resize((w, h)), dtype=np.float32) / 255.0
    lin = srgb2lin(crop)
    for _ in range(3):
        mean = lin2srgb(lin).reshape(-1, 3).mean(0)
        lin = lin * (srgb2lin(hexrgb(color)) / np.maximum(srgb2lin(mean), 1e-4))
    return Image.fromarray(np.clip(np.round(lin2srgb(lin) * 255), 0, 255).astype(np.uint8))


def _cloth(w, h, color, seed):
    rng = np.random.default_rng(seed)
    base = hexrgb(color)
    n = rng.normal(0, 0.035, (h, w, 1)).astype(np.float32)
    weave = (0.02 * np.sin(np.arange(w) * 2.1))[None, :, None] + (0.02 * np.sin(np.arange(h) * 1.7))[:, None, None]
    fade = np.linspace(1.04, 0.94, h, dtype=np.float32)[:, None, None]
    a = np.clip(base[None, None, :] * fade * (1 + n + weave), 0, 1)
    return Image.fromarray((a * 255).astype(np.uint8))


def _paper(w, h, seed, tone='#D6CDB9'):
    rng = np.random.default_rng(seed)
    base = hexrgb(tone)
    n = np.asarray(Image.fromarray((rng.normal(128, 30, (h // 4, w // 4)).clip(0, 255)).astype(np.uint8))
                   .resize((w, h), Image.BICUBIC), dtype=np.float32)[..., None] / 255.0 - 0.5
    fib = rng.normal(0, 0.02, (h, w, 1)).astype(np.float32)
    a = np.clip(base[None, None, :] * (1 + 0.10 * n + fib), 0, 1)
    return Image.fromarray((a * 255).astype(np.uint8))


def _text(img, xy, s, size, fill, vertical=False, font=FONT_KAI, stroke=0):
    d = ImageDraw.Draw(img)
    f = ImageFont.truetype(font, size)
    if not vertical:
        d.text(xy, s, font=f, fill=fill, anchor='mm', stroke_width=stroke, stroke_fill=fill)
        return
    x, y = xy
    for i, ch in enumerate(s):
        d.text((x, y + i * size * 1.02), ch, font=f, fill=fill, anchor='mm', stroke_width=stroke, stroke_fill=fill)


def build_atlas():
    os.makedirs(SZ, exist_ok=True)
    atlas = Image.new('RGB', (SIZE, SIZE), (40, 34, 28))
    emit = Image.new('RGB', (SIZE // 4, SIZE // 4), (0, 0, 0))
    rnd = random.Random(20260924)

    def box(k):
        return ATLAS_REGIONS[k]

    def size(k):
        x0, y0, x1, y1 = box(k)
        return x1 - x0, y1 - y0

    # 看板：自然邊木板（邊緣形狀由網格決定；貼圖整塊木紋）＋鈴奈庵（楷書、墨色、微磨損）
    w, h = size('sign')
    sign = _wood_patch(w, h, '#89643B', 11)
    ImageDraw.Draw(sign).rectangle((0, 0, w - 1, h - 1), outline=None)
    txt = Image.new('L', (w, h), 0)
    _text(txt, (w // 2, h // 2 + 6), '鈴奈庵', 228, 255, stroke=2)
    wear = np.asarray(txt, dtype=np.float32) / 255.0
    rng = np.random.default_rng(3)
    wear *= np.clip(0.80 + rng.normal(0, 0.18, wear.shape), 0.35, 1.0)
    sa = np.asarray(sign, dtype=np.float32) / 255.0
    ink = hexrgb('#16120E')
    sa = sa * (1 - wear[..., None] * 0.92) + ink * (wear[..., None] * 0.92)
    atlas.paste(Image.fromarray((np.clip(sa, 0, 1) * 255).astype(np.uint8)), box('sign')[:2])
    atlas.paste(_wood_patch(*size('sign_wood'), '#7C5A36', 12), box('sign_wood')[:2])

    # 暖簾：靛染 5 片；上緣 7% 深色縫邊；字＝鈴、奈、庵在第 2–4 片，字高約 57%
    w, h = size('noren')
    nor = _cloth(w, h, '#34444C', 21)
    d = ImageDraw.Draw(nor)
    d.rectangle((0, 0, w, int(h * 0.07)), fill=(34, 44, 50))
    pw = w / 5
    for i, ch in enumerate(['', '鈴', '奈', '庵', '']):
        if ch:
            _text(nor, (int(pw * (i + 0.5)), int(h * 0.55)), ch, int(h * 0.56), (204, 196, 176))
    for i in range(1, 5):   # 片與片的縫（網格也會分開；貼圖邊加暗線避免色溢）
        d.line((int(pw * i), 0, int(pw * i), h), fill=(26, 34, 38), width=3)
    atlas.paste(nor, box('noren')[:2])
    atlas.paste(_cloth(*size('noren_back'), '#2E3C43', 22), box('noren_back')[:2])

    # 書背：4 列，每列不同高度的書，靛、褐、黃土、暗紅、米白封；偶有題簽
    w, h = size('spines')
    sp = Image.new('RGB', (w, h), (30, 24, 19))
    d = ImageDraw.Draw(sp)
    cols = ['#3C4652', '#5A4632', '#8C7446', '#6E3A30', '#C9BFA6', '#4F5A45', '#7D6A55', '#2F3036', '#A89A7A']
    for row in range(4):
        x = 2
        y0, y1 = row * 128, row * 128 + 127
        while x < w - 4:
            bw = rnd.randint(14, 30)
            bh = rnd.randint(88, 122)
            c = hexrgb(rnd.choice(cols)) * rnd.uniform(0.85, 1.1)
            c = tuple(int(v) for v in np.clip(c * 255, 0, 255))
            d.rectangle((x, y1 - bh, x + bw - 2, y1 - 2), fill=c)
            if rnd.random() < 0.55:   # 題簽
                d.rectangle((x + 3, y1 - bh + 8, x + bw - 5, y1 - bh + 8 + int(bh * 0.45)), fill=(214, 205, 185))
                for k in range(3):
                    yy = y1 - bh + 14 + k * 11
                    d.line((x + bw // 2 - 1, yy, x + bw // 2 - 1, yy + 6), fill=(40, 34, 28), width=2)
            x += bw
        d.line((0, y1, w, y1), fill=(20, 16, 12), width=3)
    atlas.paste(sp, box('spines')[:2])

    # 書封：米白封面＋直書墨字
    x0, y0, x1, y1 = box('covers')
    titles = ['百鬼夜行', '妖魔本', '竹取物語', '今昔物語']
    for i, t in enumerate(titles):
        cv = _paper(128, 192, 30 + i, tone=rnd.choice(['#CFC4A8', '#D8CDB2', '#BFB295']))
        dd = ImageDraw.Draw(cv)
        dd.rectangle((0, 0, 127, 191), outline=(90, 78, 60), width=3)
        dd.rectangle((78, 12, 112, 150), fill=(226, 219, 200), outline=(120, 106, 84))
        _text(cv, (95, 32), t, 26, (30, 26, 22), vertical=True)
        for k in range(4):   # 綴じ糸
            dd.line((8, 30 + k * 42, 18, 30 + k * 42), fill=(60, 50, 40), width=2)
        atlas.paste(cv, (x0 + i * 128, y0))

    # 貸本牌
    w, h = size('kashihon')
    kb = _wood_patch(w, h, '#8A6A3E', 13).rotate(0)
    _text(kb, (w // 2, int(h * 0.30)), '貸本', 92, (22, 18, 14), vertical=True)
    atlas.paste(kb, box('kashihon')[:2])

    # 障子：紙＋組子（縱 2、橫 4）
    w, h = size('shoji')
    sj = _paper(w, h, 41)
    d = ImageDraw.Draw(sj)
    for i in range(1, 3):
        d.line((int(w * i / 3), 0, int(w * i / 3), h), fill=(88, 70, 48), width=7)
    for j in range(1, 5):
        d.line((0, int(h * j / 5), w, int(h * j / 5)), fill=(88, 70, 48), width=7)
    atlas.paste(sj, box('shoji')[:2])
    atlas.paste(_paper(*size('paper'), 42), box('paper')[:2])

    # 行燈紙：暖色紙＋黑色圓形花紋
    w, h = size('lantern')
    ln = _paper(w, h, 43, tone='#E6D2A6')
    d = ImageDraw.Draw(ln)
    cx, cy, r = w // 2, h // 2, 34
    d.ellipse((cx - r, cy - r, cx + r, cy + r), outline=(26, 22, 18), width=6)
    for k in range(5):
        ang = k * 2 * math.pi / 5 - math.pi / 2
        px, py = cx + math.cos(ang) * 17, cy + math.sin(ang) * 17
        d.ellipse((px - 9, py - 9, px + 9, py + 9), fill=(26, 22, 18))
    atlas.paste(ln, box('lantern')[:2])
    ex0, ey0, ex1, ey1 = box('lantern')
    ImageDraw.Draw(emit).rectangle((ex0 // 4, ey0 // 4, ex1 // 4 - 1, ey1 // 4 - 1), fill=(255, 205, 140))

    # 葉叢：暗綠葉紋＋淡紫花點
    w, h = size('foliage')
    fo = Image.new('RGB', (w, h), (58, 72, 40))
    d = ImageDraw.Draw(fo)
    for _ in range(900):
        x, y = rnd.randint(0, w), rnd.randint(0, h)
        c = tuple(int(v) for v in hexrgb('#596334') * 255 * rnd.uniform(0.6, 1.3))
        d.ellipse((x - 7, y - 3, x + 7, y + 3), fill=c)
    for _ in range(160):
        x, y = rnd.randint(0, w), rnd.randint(0, h)
        c = tuple(int(v) for v in hexrgb('#8D80A2') * 255 * rnd.uniform(0.85, 1.15))
        d.ellipse((x - 4, y - 4, x + 4, y + 4), fill=c)
    atlas.paste(fo, box('foliage')[:2])

    # 色塊
    x0, y0, x1, y1 = box('swatch')
    sw = (x1 - x0) // 4
    shh = (y1 - y0) // 2
    for i, c in enumerate(SWATCH):
        ImageDraw.Draw(atlas).rectangle((x0 + (i % 4) * sw, y0 + (i // 4) * shh, x0 + (i % 4 + 1) * sw - 1,
                                         y0 + (i // 4 + 1) * shh - 1), fill=tuple(int(v * 255) for v in hexrgb(c)))

    atlas.save(f'{SZ}/suzunaan_atlas.png', optimize=True)
    emit.save(f'{SZ}/suzunaan_emit.png', optimize=True)
    uv = {}
    for k, (x0, y0, x1, y1) in ATLAS_REGIONS.items():
        uv[k] = [x0 / SIZE, y0 / SIZE, x1 / SIZE, y1 / SIZE]   # 左上原點（Godot/glTF）
    sws = {}
    x0, y0, x1, y1 = ATLAS_REGIONS['swatch']
    for i, c in enumerate(SWATCH):
        cx = x0 + (i % 4 + 0.5) * sw
        cy = y0 + (i // 4 + 0.5) * shh
        sws[c] = {'uv': [cx / SIZE, cy / SIZE], 'note': SWATCH_NOTE[i]}
    with open(f'{SZ}/atlas.json', 'w', encoding='utf-8', newline='\n') as f:
        json.dump({'_note': '鈴奈庵 Hero atlas（UV 左上原點；Blender 端 v 要 1−v）。由 tools/build_village_v2_textures.py 產生。',
                   'size': SIZE, 'regions': uv, 'swatches': sws, 'font': 'kaiu.ttf（標楷體，Windows 內建）'},
                  f, ensure_ascii=False, indent=1)
        f.write('\n')
    for fn, nm in (('suzunaan_atlas.png', False), ('suzunaan_emit.png', False)):
        write_import(f'res://assets/village_v2/suzunaan/{fn}', nm)
    write_tres(f'{SZ}/V2_Suzunaan.tres', 'V2_Suzunaan',
               {'albedo': 'res://assets/village_v2/suzunaan/suzunaan_atlas.png',
                'emit': 'res://assets/village_v2/suzunaan/suzunaan_emit.png'}, ['roughness = 0.9'])
    print('atlas →', f'{SZ}/suzunaan_atlas.png')


if __name__ == '__main__':
    build_matlib()
    build_atlas()

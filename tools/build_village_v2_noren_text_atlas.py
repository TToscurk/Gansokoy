#!/usr/bin/env python3
"""人間之里 V2：暖簾の字 atlas（noren_text_kit）産生器。

  python tools/build_village_v2_noren_text_atlas.py

2026-10-21 使用者指示「布簾上沒有字的／幾何圖案的改成有相應文字的」。町家 Kit の暖簾 a–e（P6、幾何家紋のみ・無字）などを、
店の商い／屋号の字を入れた暖簾に置き換えるための atlas。machiya_kit の atlas（2048、全区画使用済み）は触らず、暖簾だけの別 atlas を足す。
入力：godot/data/village_v2_noren_text.json（cells＝暖簾 1 種：kind／text／cloth／ink、buildings／age_props／inplace_meshes は反映側が読む）。
出力：godot/assets/village_v2/noren_text_kit/{noren_text_atlas.png, noren_text_emit.png, atlas.json, NT_Noren.tres, NT_Noren_K.tres}
区画（kind）：
  kit   512×256 px・内側余白 12 px＝P6 暖簾の区画と同じ寸法・同じ UV 規約（町家 Kit 1.64×0.70 m の暖簾、arch の割れ暖簾は左右の半分ずつ）。
  age   512×256 px・字は小さめ（掀げ暖簾の水引 0.42×0.25 m 4 枚、字 2 つを 2 回）。布の色は market_kit atlas の ai／akane／kinari と同じ。
  stall 1024×224 px・内側余白 6 px（屋台の暖簾 2.24×0.45 m／木戸の水引 4.68×0.37 m）。
  1 暖簾＝字数ぶんの幅、1 幅 1 字。幅の切れ目（暗）・竿袋（上 10 %）は P6 の _noren と同じ。家紋・幾何紋は描かない。
布・字の道具は build_village_v2_textures.py（_cloth／_text）を再利用。字体＝標楷体（kaiu.ttf、他の看板と同じ）。
"""
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_village_v2_textures as T  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, '..'))
DATA = os.path.join(ROOT, 'godot', 'data', 'village_v2_noren_text.json')
OUT = os.path.join(ROOT, 'godot', 'assets', 'village_v2', 'noren_text_kit')
KINDS = {'kit': (512, 256, 12), 'age': (512, 256, 12), 'stall': (1024, 224, 6)}   # 幅, 高さ, 内側余白（px）
COLS = 4


def hex255(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def seed_of(key):
    v = 0
    for ch in key:
        v = (v * 131 + ord(ch)) % 1000003
    return 7000 + v % 900


def glyph_size(kind, n, cw, ch):
    pw = cw / n
    body_h = ch - int(ch * 0.10)
    if kind == 'age':
        return int(min(pw * 0.48, 118))      # 水引 1 枚（0.42×0.25 m）ぶんの帯に収める（反映側が帯の縦横比へ上下を切り出す）
    if kind == 'stall':
        return int(min(pw * 0.70, ch * 0.62))
    return int(min(pw * 0.74, body_h * 0.66))


def render_cell(key, spec, cloth_hex, ink_rgb):
    kind = spec.get('kind', 'kit')
    cw, ch, _ = KINDS[kind]
    text = spec['text']
    n = len(text)
    img = T._cloth(cw, ch, cloth_hex, seed_of(key))
    d = ImageDraw.Draw(img)
    pw = cw / n
    top = int(ch * 0.10)
    for i in range(1, n):                      # 幅と幅の切れ目（暗）
        x0 = int(i * pw)
        d.rectangle((x0 - 3, top, x0 + 3, ch), fill=(20, 18, 16))
    body_h = ch - top
    size = glyph_size(kind, n, cw, ch)
    stroke = max(1, int(size * 0.024))
    mask = Image.new('L', (cw, ch), 0)
    cy = top + int(body_h * 0.52)
    for i, c in enumerate(text):
        T._text(mask, (int(i * pw + pw / 2), cy), c, size, 255, vertical=False, stroke=stroke)
    mask = mask.filter(ImageFilter.GaussianBlur(0.5))
    # 染めの擦れ：低周波ノイズで字の濃さをゆらす
    rng = np.random.default_rng(seed_of(key) + 5)
    wear = np.asarray(Image.fromarray(rng.normal(128, 40, (max(ch // 16, 2), max(cw // 16, 2))).clip(0, 255).astype(np.uint8))
                      .resize((cw, ch), Image.BICUBIC), dtype=np.float32) / 255.0
    m = np.asarray(mask, dtype=np.float32) / 255.0 * np.clip(0.88 + 0.2 * wear, 0.0, 1.0)
    m = np.clip(m, 0, 1)[..., None]
    base = np.asarray(img, dtype=np.float32)
    ink = np.array(ink_rgb, dtype=np.float32)[None, None, :]
    out = base * (1 - m) + ink * m
    img = Image.fromarray(np.clip(out, 0, 255).astype(np.uint8))
    d = ImageDraw.Draw(img)
    c = hex255(cloth_hex)
    d.rectangle((0, 0, cw, top), fill=tuple(int(v * 0.55) for v in c))   # 竿袋
    return img


def main():
    doc = json.load(open(DATA, encoding='utf-8'))
    cells = doc['cells']
    small = sorted(k for k in cells if cells[k].get('kind', 'kit') in ('kit', 'age'))
    wide = sorted(k for k in cells if cells[k].get('kind', 'kit') == 'stall')
    rows_small = (len(small) + COLS - 1) // COLS
    rows_wide2 = (len(wide) + 1) // 2            # 1024 幅×224 は 2 列
    W = 2048
    H = rows_small * 256 + rows_wide2 * 224
    atlas = Image.new('RGB', (W, H), (36, 30, 26))
    regions, info = {}, {}
    for i, k in enumerate(small):
        spec = cells[k]
        cw, ch, ins = KINDS[spec.get('kind', 'kit')]
        x0, y0 = (i % COLS) * cw, (i // COLS) * ch
        atlas.paste(render_cell(k, spec, doc['cloth'][spec['cloth']], doc['ink'][spec['ink']]), (x0, y0))
        regions['noren_' + k] = [round(x0 / W, 9), round(y0 / H, 9), round((x0 + cw) / W, 9), round((y0 + ch) / H, 9)]
        info[k] = {'kind': spec.get('kind', 'kit'), 'px': [x0, y0, cw, ch], 'inset': ins, 'slots': len(spec['text'])}
    for i, k in enumerate(wide):
        spec = cells[k]
        cw, ch, ins = KINDS['stall']
        x0, y0 = (i % 2) * cw, rows_small * 256 + (i // 2) * ch
        atlas.paste(render_cell(k, spec, doc['cloth'][spec['cloth']], doc['ink'][spec['ink']]), (x0, y0))
        regions['noren_' + k] = [round(x0 / W, 9), round(y0 / H, 9), round((x0 + cw) / W, 9), round((y0 + ch) / H, 9)]
        info[k] = {'kind': 'stall', 'px': [x0, y0, cw, ch], 'inset': ins, 'slots': len(spec['text'])}
    os.makedirs(OUT, exist_ok=True)
    atlas.save(os.path.join(OUT, 'noren_text_atlas.png'))
    meta = {'_note': 'noren_text_kit atlas（UV 左上原点；Blender 端 v は 1−v）。tools/build_village_v2_noren_text_atlas.py が産生。'
                     '暖簾の字（1 幅 1 字）。kind＝kit 512×256／age 512×256／stall 1024×224。region 名＝noren_<cell id>（字の向き監査の対象）。',
            'size': W, 'atlas_px': [W, H], 'cells': info, 'regions': regions,
            'texts': {k: cells[k]['text'] for k in sorted(cells)}, 'font': 'kaiu.ttf（標楷體）'}
    json.dump(meta, open(os.path.join(OUT, 'atlas.json'), 'w', encoding='utf-8', newline='\n'), ensure_ascii=False, indent=1)
    tex = 'res://assets/village_v2/noren_text_kit/noren_text_atlas.png'
    # 発光：V2_MachiyaKit と同じ設定（白 × 発光テクスチャ × 0.4、MULTIPLY）。発光テクスチャは真っ黒（暖簾は光らない）。
    # 必須：scripts/wind.gd の _attach_cloth は「発光が有効で発光テクスチャがある」ときだけ emit_tex を渡す。
    # 渡さないと wind_cloth.gdshader の emit_tex が既定の白になり、全面が +0.4 で発光して布が白っぽく浮く。
    Image.new('RGB', (8, 8), (0, 0, 0)).save(os.path.join(OUT, 'noren_text_emit.png'))
    emit = 'res://assets/village_v2/noren_text_kit/noren_text_emit.png'
    with open(os.path.join(OUT, 'NT_Noren.tres'), 'w', encoding='utf-8', newline='\n') as f:
        f.write('[gd_resource type="StandardMaterial3D" load_steps=3 format=3]\n\n'
                '[ext_resource type="Texture2D" path="%s" id="1"]\n[ext_resource type="Texture2D" path="%s" id="2"]\n\n[resource]\n'
                'resource_name = "NT_Noren"\nvertex_color_use_as_albedo = true\nalbedo_color = Color(0.42, 0.42, 0.42, 1)\n'
                'albedo_texture = ExtResource("1")\nroughness = 0.9\nemission_enabled = true\nemission = Color(1, 1, 1, 1)\n'
                'emission_energy_multiplier = 0.4\nemission_operator = 1\nemission_texture = ExtResource("2")\n' % (tex, emit))
    with open(os.path.join(OUT, 'NT_Noren_K.tres'), 'w', encoding='utf-8', newline='\n') as f:
        f.write('[gd_resource type="ShaderMaterial" load_steps=3 format=3]\n\n'
                '[ext_resource type="Shader" path="res://maps/village_v2/kit_cal_p10/kit_cal.gdshader" id="1"]\n'
                '[ext_resource type="Texture2D" path="%s" id="2"]\n\n[resource]\n'
                'resource_name = "NT_Noren_K"\nrender_priority = 0\nshader = ExtResource("1")\n'
                'shader_parameter/albedo_tex = ExtResource("2")\nshader_parameter/k_dark = 0.75\nshader_parameter/k_mid = 0.42\n'
                'shader_parameter/k_light = 0.7\nshader_parameter/band_dark = Vector2(0.26, 0.34)\n'
                'shader_parameter/band_light = Vector2(0.55, 0.7)\nshader_parameter/roughness_v = 0.9\n'
                'shader_parameter/emission_energy = 0.4\n' % tex)
    print('cells', len(cells), '(small %d, stall %d)' % (len(small), len(wide)), 'atlas', W, 'x', H, '->', OUT)


if __name__ == '__main__':
    main()

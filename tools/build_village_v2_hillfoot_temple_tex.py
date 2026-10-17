#!/usr/bin/env python3
"""人間之里 V2：丘腳社寺（LANDMARK_HILLFOOT_TEMPLE）Hero 底色貼圖。

  python tools/build_village_v2_hillfoot_temple_tex.py
  blender -b --factory-startup --python godot/assets/blender/village_v2/build_hillfoot_temple.py

來源：使用者 2026-10-17 提供的 Tripo 模型（D:/資產glb/丘腳社寺/japanese+shrine+3d+model.glb），
原樣複製到 godot/assets/village_v2/hillfoot_temple/src/hillfoot_temple_source.glb（src/ 有 .gdignore；本腳本只讀）。
做法同龍神像（tools/build_village_v2_r4_atlas.py build_dragon）：內嵌 4096² 底色 → 2048²（LANCZOS）、
線性空間「等比增益」（不改色相）：把平均亮度對齊共享材質庫同類構材（V2_Wood／V2_Kawara／V2_Stone 底色的
平均線性亮度），因為材質 albedo_color＝albedo_k 0.42 是全村共用乘數，貼圖要與材質庫同一亮度基準。
輸出：godot/assets/village_v2/hillfoot_temple/{hillfoot_temple_albedo.jpg(.import), V2_HillfootTemple.tres}
"""
import io
import json
import os
import struct
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_village_v2_textures as T  # noqa: E402

G = T.G
AID = 'hillfoot_temple'
NAME = 'V2_HillfootTemple'
SRC = f'{G}/assets/village_v2/{AID}/src/hillfoot_temple_source.glb'
REF = ['V2_Wood', 'V2_Kawara', 'V2_Stone']


def _lin(a):
    return np.where(a <= 0.04045, a / 12.92, ((a + 0.055) / 1.055) ** 2.4)


def _srgb(lin):
    return np.where(lin <= 0.0031308, lin * 12.92, 1.055 * np.power(lin, 1 / 2.4) - 0.055)


def _lum(a):
    return float((_lin(a) @ np.array([0.2126, 0.7152, 0.0722], np.float32)).mean())


def _glb_image(path):
    b = open(path, 'rb').read()
    ln = struct.unpack('<I', b[12:16])[0]
    js = json.loads(b[20:20 + ln])
    bin0 = 20 + ln + 8
    assert len(js['images']) == 1, js['images']
    bv = js['bufferViews'][js['images'][0]['bufferView']]
    o = bin0 + bv.get('byteOffset', 0)
    return Image.open(io.BytesIO(b[o:o + bv['byteLength']])).convert('RGB')


def main():
    out = f'{G}/assets/village_v2/{AID}'
    im = _glb_image(SRC)
    src_size = im.size
    im = im.resize((2048, 2048), Image.LANCZOS)
    a = np.asarray(im).astype(np.float32) / 255.0
    ref = [_lum(np.asarray(Image.open(f'{G}/assets/village_v2/_matlib/{n}_albedo.jpg').convert('RGB'))
                .astype(np.float32) / 255.0) for n in REF]
    tgt = sum(ref) / len(ref)
    cur = _lum(a)
    gain = tgt / cur
    res = (np.clip(_srgb(np.clip(_lin(a) * gain, 0, 1)), 0, 1) * 255).astype(np.uint8)
    clipped = float((_lin(a) * gain >= 1.0).any(axis=2).mean())
    Image.fromarray(res).save(f'{out}/{AID}_albedo.jpg', quality=90)
    T.write_import(f'res://assets/village_v2/{AID}/{AID}_albedo.jpg', False)
    T.write_tres(f'{out}/{NAME}.tres', NAME, {'albedo': f'res://assets/village_v2/{AID}/{AID}_albedo.jpg'},
                 ['roughness = 0.9'])
    print('[HILLFOOT_TEX] %s %s → 2048²；亮度 %.3f → %.3f（材質庫 %s 平均 %s）；增益 ×%.3f、飽和像素 %.2f %%' % (
        os.path.basename(SRC), src_size, cur, _lum(res.astype(np.float32) / 255.0), REF,
        [round(r, 3) for r in ref], gain, clipped * 100.0))


if __name__ == '__main__':
    main()

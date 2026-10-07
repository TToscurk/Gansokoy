#!/usr/bin/env python3
"""人間之里 V2 P9 R3：竹 Kit（bamboo_kit）貼圖產生器（全部程序產生，無外部來源）。

  python tools/build_village_v2_bamboo_textures.py

重用 tools/build_village_v2_veg_textures.py 的偽 3D 葉叢卡（Card／leaf／grow…，import 使用、不修改 R1 封存檔）
與 tools/build_village_v2_textures.py 的 .import 規約。輸出（godot/assets/village_v2/bamboo_kit/tex/）：
  - 竹稈：BC_{green,dead}_{albedo,normal}.jpg（512×1024；u＝稈周、v＝一個節間，v=0＝上節、v=1＝下節）
      green：真竹系中綠＋縱向細紋＋節下白粉帶＋節環（脊＋籜痕）；個體色差交給頂點色（年齡、黃化、苔）。
      dead ：枯竹灰黃＋黴斑＋縱裂＋暗褐節。
  - 葉叢 atlas：BL_A_{albedo,normal}.png（2048×1024，8 格 512²）
      spray_a 成竹枝葉（2–5 片一簇、下垂）／spray_b 密葉（孟宗、篠）／spray_young 若竹嫩葉／spray_dry 枯葉／
      spray_hang 下垂枝端（梢頭）／sheath 筍皮（黑斑）／sheath_dry 乾筍皮／litter 落葉（俯視）
  - bamboo_tex.json：每格 region（像素、UV、bbox）、錨點、覆蓋率；Blender 端 build_bamboo_kit.py 只讀這份。
"""
import json
import math
import os
import random
import sys

import numpy as np
from PIL import Image, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_village_v2_textures as T  # noqa: E402
import build_village_v2_veg_textures as VT  # noqa: E402

OUT = T.G + '/assets/village_v2/bamboo_kit/tex'
RES = 'res://assets/village_v2/bamboo_kit/tex'
CW, CH = 512, 1024
AW, AH = 2048, 1024
V, nrm, rot, perp, hx, mix, jit = VT.V, VT.nrm, VT.rot, VT.perp, VT.hx, VT.mix, VT.jit


# ───────────────────────── 竹稈 ─────────────────────────
def _noise2(h, w, sx, sy, rng, octaves=3):
    """可平鋪（u 方向）的分形雜訊：sx／sy＝基頻格數。"""
    out = np.zeros((h, w), np.float32)
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        gx, gy = sx * (2 ** o), sy * (2 ** o)
        g = rng.standard_normal((gy + 1, gx)).astype(np.float32)
        g = np.concatenate([g, g[:, :1]], 1)   # u 方向週期
        img = Image.fromarray(g).resize((w, h), Image.BICUBIC)
        out += np.asarray(img, np.float32) * amp
        tot += amp
        amp *= 0.5
    out /= tot
    return (out - out.mean()) / (out.std() + 1e-6)


def _height_to_normal(hm, k):
    gx = (np.roll(hm, -1, 1) - np.roll(hm, 1, 1)) * 0.5
    gy = (np.roll(hm, -1, 0) - np.roll(hm, 1, 0)) * 0.5
    gy[0] = gy[1]
    gy[-1] = gy[-2]
    n = np.dstack([-gx * k, gy * k, np.ones_like(hm)])     # OpenGL 法線（+Y 朝上＝影像上方）
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    return n * 0.5 + 0.5


def build_culm(kind, seed):
    rng = np.random.default_rng(seed)
    v = np.linspace(0, 1, CH, dtype=np.float32)[:, None]
    u = np.linspace(0, 1, CW, endpoint=False, dtype=np.float32)[None, :]
    streak = _noise2(CH, CW, 64, 3, rng, 2)               # 縱向細紋（u 高頻、v 低頻）
    blot = _noise2(CH, CW, 6, 3, rng, 3)                   # 大塊色差
    fine = _noise2(CH, CW, 128, 48, rng, 1)
    hm = streak * 0.15 + fine * 0.05
    if kind == 'green':
        base = np.array(T.srgb2lin(np.array(hx('#4F6636')) / 255.0), np.float32)
        col = base[None, None, :] * (1.0 + 0.06 * streak[..., None] + 0.08 * blot[..., None])
        # 縱向極淡黃綠條（成竹表面的老化不均）
        yel = np.array(T.srgb2lin(np.array(hx('#6E7A3E')) / 255.0), np.float32)
        yb = np.clip(0.5 + 0.5 * _noise2(CH, CW, 5, 1, rng, 2), 0, 1) ** 2 * 0.35
        col = col * (1 - yb[..., None]) + yel * yb[..., None]
        # 節下白粉帶（v 0.02–0.13，斑駁）
        pw = np.clip(1.0 - (v - 0.022) / 0.075, 0, 1) ** 0.7 * (v > 0.02)
        pw = pw * np.clip(0.8 + 0.3 * _noise2(CH, CW, 24, 8, rng, 2), 0, 1)
        powder = np.array(T.srgb2lin(np.array(hx('#B4BCA6')) / 255.0), np.float32)
        col = col * (1 - 0.45 * pw[..., None]) + powder * 0.45 * pw[..., None]
        # 節間下段（v 0.7–1）略深：上節陰影＋老化
        node_dark = np.array(T.srgb2lin(np.array(hx('#3A4626')) / 255.0), np.float32)
        col = col * (1.0 - 0.10 * np.clip((v - 0.6) / 0.4, 0, 1))[..., None]
        scar = np.array(T.srgb2lin(np.array(hx('#8C8A5C')) / 255.0), np.float32)
    else:
        base = np.array(T.srgb2lin(np.array(hx('#8E8360')) / 255.0), np.float32)
        grey = np.array(T.srgb2lin(np.array(hx('#7C7A6C')) / 255.0), np.float32)
        g = np.clip(0.5 + 0.5 * blot, 0, 1)[..., None]
        col = (base * (1 - g) + grey * g) * (1.0 + 0.07 * streak[..., None])
        mold = np.clip((_noise2(CH, CW, 14, 7, rng, 3) - 0.6) * 1.0, 0, 1)
        mcol = np.array(T.srgb2lin(np.array(hx('#4C463B')) / 255.0), np.float32)
        col = col * (1 - 0.7 * mold[..., None]) + mcol * 0.7 * mold[..., None]
        # 縱裂（少數深色細線）
        for _ in range(5):
            x = int(rng.integers(0, CW))
            y0, y1 = sorted(rng.integers(0, CH, 2))
            w = int(rng.integers(1, 3))
            col[y0:y1, x:x + w] *= 0.45
            hm[y0:y1, x:x + w] -= 0.9
        node_dark = np.array(T.srgb2lin(np.array(hx('#5A4A34')) / 255.0), np.float32)
        scar = np.array(T.srgb2lin(np.array(hx('#7A6E52')) / 255.0), np.float32)
    # 節環：上節（v 0–0.018）脊＋暗線；下節（v 0.985–1）籜痕亮線
    ridge = np.exp(-((v - 0.008) / 0.007) ** 2)
    dark = np.exp(-((v - 0.015) / 0.005) ** 2)
    sc = np.exp(-((v - 0.992) / 0.004) ** 2)
    col = col * (1 - 0.75 * dark[..., None]) + node_dark * 0.75 * dark[..., None]
    col = col * (1 - 0.5 * sc[..., None]) + scar * 0.5 * sc[..., None]
    col = col * (1.0 + 0.10 * ridge[..., None])
    hm = hm + ridge * 2.2 + sc * 0.8 - dark * 0.4
    alb = T.lin2srgb(np.clip(col, 0, 1))
    nor = _height_to_normal(hm.astype(np.float32), 1.6)
    files = {}
    for k, arr, q in (('albedo', alb, 92), ('normal', nor, 95)):
        fn = f'BC_{kind}_{k}.jpg'
        Image.fromarray(np.clip(np.round(arr * 255), 0, 255).astype(np.uint8)).save(f'{OUT}/{fn}', quality=q,
                                                                                   subsampling=0)
        rp = f'{RES}/{fn}'
        T.write_import(rp, k == 'normal')
        files[k] = rp
    mean = alb.reshape(-1, 3).mean(0)
    print(f'culm {kind}: mean {T.rgbhex(mean)}')
    return {'files': files, 'albedo_mean_srgb': T.rgbhex(mean), 'size': [CW, CH],
            'uv': 'u＝稈周 0–1；v＝一個節間（0＝上節、1＝下節）'}


# ───────────────────────── 葉叢卡（cm） ─────────────────────────
LEAF_U = hx('#93A274')          # 葉背：灰綠


def bamboo_leaf(card, p, a, n, L, col, under, rng, dry=False):
    """竹葉：細長披針（長寬比 ≈ 7–9）、短葉柄、葉尖下垂、平行脈；枯葉捲曲。"""
    W = L / rng.uniform(6.8, 8.8)
    VT.leaf(card, p + a * 0.8, a, n, L, W, 'lance', col, under, rng, fold=0.18 if dry else 0.1,
            droop=rng.uniform(0.25, 0.45) if not dry else rng.uniform(0.4, 0.7), rib=True, wave=0.04 if dry else 0.0)


def leaf_rank(card, p, t, rng, n_leaf, Lr, base, tip, under, dry=False, hang=False, plane=None):
    """小枝端的葉：竹葉二列互生在同一平面（扁平、單側下垂的扇），不是 360° 放射。
    t＝小枝方向；plane＝扇面法線（大致朝觀者，帶隨機）。葉軸由小枝方向往下、左右交替張開 25–70°。"""
    n_pl = nrm(plane if plane is not None else VT.VIEW + V(rng.gauss(0, 0.3), rng.gauss(0, 0.2), 0))
    side = nrm(np.cross(t, n_pl))
    for j in range(n_leaf):
        sg = 1 if j % 2 == 0 else -1
        q = p + t * (-j * rng.uniform(2.4, 3.8))                    # 沿小枝往回排（葉鞘互生、間隔 2.4–3.8 cm）
        ang = rng.uniform(0.3, 0.75)
        a = nrm(t * math.cos(ang) + side * sg * math.sin(ang))
        a = nrm(a + V(0, -rng.uniform(0.7, 1.3) if not hang else -0.5, 0))   # 下垂（手指狀垂葉）
        nv = nrm(n_pl + V(0, rng.uniform(0.1, 0.5), 0) + VT.LIGHT * 0.35)
        nv = nrm(nv - a * float(np.dot(nv, a)))
        L = rng.uniform(*Lr) * (0.8 if j == n_leaf - 1 else 1.0)
        c = jit(mix(base, tip, rng.random()), rng, 0.09, 0.06, 0.03)
        u = mix(under, c, 0.25)
        if dry:
            c = jit(mix(hx('#B39A55'), hx('#8E6C3A'), rng.random()), rng, 0.08, 0.05, 0.03)
            u = mix(c, (200, 190, 150), 0.25)
        bamboo_leaf(card, q, a, nv, L, c, u, rng, dry)


def zigzag(p, d, L, n, rng, swing=0.38, gravity=0.0):
    """竹枝：每節小折（之字形），節處略膨。回傳節點列。"""
    pts = [np.array(p, dtype=np.float64)]
    d = nrm(np.array(d, dtype=np.float64))
    ax = nrm(np.cross(d, VT.VIEW)) if abs(float(np.dot(d, VT.VIEW))) < 0.95 else perp(d)
    for i in range(n):
        dd = nrm(rot(d, VT.VIEW, swing * (1 if i % 2 == 0 else -1) * rng.uniform(0.6, 1.1)) + V(0, -gravity * i / n, 0))
        pts.append(pts[-1] + dd * (L / n) * rng.uniform(0.85, 1.15))
    return pts


def sp_spray(card, rng, base, tip, under=LEAF_U, n_node=(4, 6), n_leaf=(3, 6), Lr=(14, 22), length=(26, 34),
             dry=False, dense=1.0, young=False):
    """竹枝（錨點＝枝基）：之字形主枝（基部只留短裸段），每節互生一條短小枝，小枝端二列葉扇下垂；
    枝端再一扇。葉集中在外側 3/4，扇面大致同一平面（竹枝葉的扁平感）。"""
    nn = rng.randint(*n_node)
    stem = zigzag(V(0, 0, 0), V(rng.uniform(-0.2, 0.2), 1, 0), rng.uniform(*length), nn + 1, rng, gravity=0.35)
    twig_col = hx('#6E7A44') if not dry else hx('#8A7A56')
    card.twig(stem, 0.42, 0.2, twig_col)
    for i in range(1, len(stem)):                     # 節環
        p = stem[i]
        card.poly([p + V(-0.55, -0.15, 0.2), p + V(0.55, -0.15, 0.2), p + V(0.5, 0.2, 0.2), p + V(-0.5, 0.2, 0.2)],
                  mul(twig_col, 0.8), VT.VIEW)
    plane = VT.VIEW + V(rng.gauss(0, 0.25), 0, 0)
    for i in range(1, len(stem)):
        p = stem[i]
        t = VT.tangent_at(stem, i)
        side = 1 if i % 2 == 0 else -1                 # 互生
        d = nrm(rot(t, VT.VIEW, side * rng.uniform(0.6, 1.05)) + V(0, -0.15, 0))
        for _ in range(max(1, int(round(dense)))):
            tw = zigzag(p, d, rng.uniform(4, 9), 2, rng, swing=0.25, gravity=0.3)
            card.twig(tw, 0.2, 0.12, twig_col)
            leaf_rank(card, tw[-1], VT.tangent_at(tw, len(tw) - 1), rng, rng.randint(*n_leaf), Lr, base, tip, under, dry,
                      plane=plane)
            d = nrm(rot(d, VT.VIEW, -side * rng.uniform(0.3, 0.6)))
    leaf_rank(card, stem[-1], VT.tangent_at(stem, len(stem) - 1), rng, rng.randint(3, 5), Lr, base, tip, under, dry,
              plane=plane)
    if young:
        # 若竹：枝端捲著的新葉（細、直立、淡色）
        for _ in range(3):
            q = stem[-1] + V(rng.uniform(-3, 3), rng.uniform(-2, 1), 0)
            a = nrm(V(rng.uniform(-0.3, 0.3), 1, 0.1))
            VT.leaf(card, q, a, nrm(VT.VIEW + V(0.2, 0, 0)), rng.uniform(6, 9), 0.9, 'lance', hx('#A6C060'),
                    hx('#B8C890'), rng, fold=0.5, droop=0.05)


def sp_hang(card, rng, base, tip, under=LEAF_U):
    """梢頭下垂枝（錨點＝頂）：枝往下彎垂，葉簇沿枝掛著。"""
    for s in range(2):
        stem = zigzag(V((s - 0.5) * 8, 0, 0), V(rng.uniform(-0.35, 0.35), -1, 0), rng.uniform(42, 56), 6, rng, swing=0.3)
        card.twig(stem, 0.4, 0.2, hx('#6E7A44'))
        for i in range(1, len(stem)):
            t = VT.tangent_at(stem, i)
            side = 1 if i % 2 == 0 else -1
            d = nrm(rot(t, VT.VIEW, side * rng.uniform(0.7, 1.2)))
            tw = zigzag(stem[i], d, rng.uniform(4, 8), 2, rng, swing=0.2, gravity=0.4)
            card.twig(tw, 0.2, 0.12, hx('#6E7A44'))
            leaf_rank(card, tw[-1], VT.tangent_at(tw, len(tw) - 1), rng, rng.randint(3, 5), (12, 19), base, tip, under,
                      hang=True)


def sp_sheath(card, rng, dry=False):
    """筍皮（籜）：長三角紙質葉鞘、黃褐底＋黑褐斑點（真竹）、縱紋、頂端小籜葉與毛緣。"""
    L, W = rng.uniform(46, 54), rng.uniform(30, 36)
    c0 = hx('#B49A62') if not dry else hx('#C2AE84')
    c1 = hx('#8A6A3E') if not dry else hx('#A28C64')
    nseg = 22
    for i in range(nseg):
        y0, y1 = L * i / nseg, L * (i + 1) / nseg
        w0 = W * (1 - (i / nseg) ** 1.6) * 0.5
        w1 = W * (1 - ((i + 1) / nseg) ** 1.6) * 0.5
        c = mix(c0, c1, (i / nseg) * 0.6)
        for sg in (-1, 1):
            n = nrm(V(sg * 0.45, 0, 1))
            card.poly([V(0, y0, 0.6), V(sg * w0, y0, 0), V(sg * w1, y1, 0), V(0, y1, 0.6)],
                      jit(mul(c, 0.93 if sg < 0 else 1.0), rng, 0.03, 0.02), n)
    # 斑點（真竹的黑褐斑）
    for _ in range(int(rng.uniform(45, 70)) if not dry else 18):
        y = rng.uniform(2, L * 0.8)
        hw = W * (1 - (y / L) ** 1.6) * 0.5
        r = rng.uniform(0.5, 1.6)
        if hw < r * 2.5:
            continue
        x = rng.uniform(-(hw - r * 2.2), hw - r * 2.2)
        sc = hx('#3A2C1E') if not dry else hx('#7A6A50')
        pts = [V(x + math.cos(a) * r * rng.uniform(0.7, 1.2), y + math.sin(a) * r * 1.6, 0.7) for a in
               np.linspace(0, 6.28, 7)[:-1]]
        card.poly(pts, sc, VT.VIEW)
    # 縱紋
    for k in range(9):
        x = (k - 4) / 4 * W * 0.4
        card.poly([V(x - 0.15, 0, 0.8), V(x + 0.15, 0, 0.8), V(x * 0.1 + 0.1, L * 0.92, 0.8), V(x * 0.1 - 0.1, L * 0.92, 0.8)],
                  mix(c1, c0, 0.4), VT.VIEW)
    # 肩部耳狀突起＋剛毛（籜耳、肩毛）
    for sg in (-1, 1):
        y = L * 0.86
        hw = W * (1 - (0.86) ** 1.6) * 0.5
        c2 = hx('#5E4A2E') if not dry else hx('#8A7A5A')
        card.poly([V(sg * hw * 0.6, y, 0.8), V(sg * (hw + 2.2), y + 0.8, 0.8), V(sg * (hw + 1.6), y + 3.0, 0.8),
                   V(sg * hw * 0.4, y + 2.0, 0.8)], c2, VT.VIEW)
        for k in range(7):
            a0 = math.radians(60 + k * 12) * sg
            q0 = V(sg * (hw + 1.8), y + 2.0, 0.9)
            card.poly([q0, q0 + V(math.sin(a0) * 4.5, math.cos(a0) * 4.5, 0), q0 + V(math.sin(a0) * 4.5 + 0.12, math.cos(a0) * 4.5, 0)],
                      c2, VT.VIEW)
    # 頂端籜葉（小、綠褐）
    VT.leaf(card, V(0, L * 0.94, 0.9), V(0, 1, 0), nrm(VT.VIEW), rng.uniform(9, 13), 2.2, 'lance',
            hx('#7C7A3E') if not dry else hx('#9A8A5C'), hx('#9C9A6A'), rng, fold=0.3, droop=0.2)


def mul(c, k):
    return VT.mul(c, k)


def sp_litter(card, rng):
    """竹落葉（俯視，錨點中心）：乾黃褐為主、少數灰綠新落葉、小枝屑；重疊、方向亂。"""
    for _ in range(int(rng.uniform(260, 320))):
        p = V(rng.uniform(-40, 40), rng.uniform(-40, 40), rng.uniform(0, 3))
        rr = 30 + 10 * math.sin(math.atan2(p[1], p[0]) * 3 + 1.3) + 6 * math.sin(math.atan2(p[1], p[0]) * 5)
        if p[0] ** 2 + p[1] ** 2 > rr ** 2:
            continue
        a = nrm(V(rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-0.1, 0.1)))
        t = rng.random()
        c = jit(mix(hx('#9C7E46'), hx('#C2A866'), rng.random()), rng, 0.1, 0.06, 0.03) if t < 0.8 else \
            jit(mix(hx('#7A8452'), hx('#98A06A'), rng.random()), rng, 0.08, 0.05)
        n = nrm(VT.VIEW + V(rng.gauss(0, 0.25), rng.gauss(0, 0.25), 0))
        n = nrm(n - a * float(np.dot(n, a)))
        L = rng.uniform(11, 19)
        VT.leaf(card, p, a, n, L, L / rng.uniform(6.5, 8.5), 'lance', c, mix(c, (190, 180, 140), 0.3), rng,
                fold=rng.uniform(0.1, 0.4), droop=0.0, rib=True, wave=0.05)
    for _ in range(14):
        p = V(rng.uniform(-35, 35), rng.uniform(-35, 35), 3.5)
        tw = VT.grow(p, V(rng.uniform(-1, 1), rng.uniform(-1, 1), 0), rng.uniform(6, 16), 3, rng, jit_amt=0.2)
        card.twig(tw, 0.3, 0.2, hx('#7A6A4C'))


LAYOUT = {
    'spray_a':     (0, 0, 512, 512, 'base', lambda c, r: sp_spray(c, r, hx('#4A6C32'), hx('#7C9A48'))),
    'spray_b':     (512, 0, 1024, 512, 'base', lambda c, r: sp_spray(c, r, hx('#46662F'), hx('#6E8C40'), n_node=(5, 7),
                                                                      n_leaf=(4, 7), Lr=(12, 19), dense=2.0)),
    'spray_young': (1024, 0, 1536, 512, 'base', lambda c, r: sp_spray(c, r, hx('#5E8636'), hx('#8EAE4C'), n_node=(3, 5),
                                                                       n_leaf=(3, 5), Lr=(11, 17), young=True)),
    'spray_dry':   (1536, 0, 2048, 512, 'base', lambda c, r: sp_spray(c, r, hx('#9A8448'), hx('#B49C5C'), n_node=(3, 5),
                                                                       n_leaf=(2, 4), Lr=(11, 17), dry=True)),
    'spray_hang':  (0, 512, 512, 1024, 'top', lambda c, r: sp_hang(c, r, hx('#4A6C32'), hx('#7A9846'))),
    'sheath':      (512, 512, 1024, 1024, 'base', lambda c, r: sp_sheath(c, r)),
    'sheath_dry':  (1024, 512, 1536, 1024, 'base', lambda c, r: sp_sheath(c, r, True)),
    'litter':      (1536, 512, 2048, 1024, 'center', lambda c, r: sp_litter(c, r)),
}


def build_atlas(seed=37):
    rgb = np.zeros((AH, AW, 3), np.uint8)
    nor = np.zeros((AH, AW, 3), np.uint8)
    nor[...] = (128, 128, 255)
    a = np.zeros((AH, AW), np.uint8)
    regions = {}
    for i, (name, (x0, y0, x1, y1, anchor, fn)) in enumerate(LAYOUT.items()):
        rng = random.Random(seed * 1000 + i)
        card = VT.Card(x1 - x0, y1 - y0, anchor)
        fn(card, rng)
        c, nm, al, mean = card.render()
        rgb[y0:y1, x0:x1] = c
        nor[y0:y1, x0:x1] = nm
        a[y0:y1, x0:x1] = al
        bx0, by0, bx1, by1 = VT.alpha_bbox(al)
        cov = float((al > 127).mean())
        regions[name] = {'px': [x0, y0, x1, y1], 'uv': [x0 / AW, y0 / AH, x1 / AW, y1 / AH], 'anchor': anchor,
                         'aspect': round((y1 - y0) / (x1 - x0), 4), 'mean_srgb': T.rgbhex(mean / 255.0),
                         'coverage': round(cov, 3), 'prims': len(card.prims), 'cm_per_px': round(1.0 / card.scale, 4),
                         'anchor_uv': [(x0 + card.anchor_px[0]) / AW, (y0 + card.anchor_px[1]) / AH],
                         'bbox_px': [x0 + bx0, y0 + by0, x0 + bx1, y0 + by1],
                         'bbox_uv': [(x0 + bx0) / AW, (y0 + by0) / AH, (x0 + bx1) / AW, (y0 + by1) / AH]}
        print(f'  BL_A.{name}: 覆蓋 {cov:.2f} 平均 {T.rgbhex(mean / 255.0)} 面 {len(card.prims)} {1.0 / card.scale:.3f} cm/px',
              flush=True)
    fa, fn_ = 'BL_A_albedo.png', 'BL_A_normal.png'
    Image.fromarray(np.dstack([rgb, a]), 'RGBA').save(f'{OUT}/{fa}', optimize=True)
    Image.fromarray(nor, 'RGB').save(f'{OUT}/{fn_}', optimize=True)
    T.write_import(f'{RES}/{fa}', False)
    T.write_import(f'{RES}/{fn_}', True)
    return {'file': f'{RES}/{fa}', 'normal': f'{RES}/{fn_}', 'size': [AW, AH], 'regions': regions}


def main():
    os.makedirs(OUT, exist_ok=True)
    meta = {'_note': 'P9 R3 竹 Kit 貼圖。由 tools/build_village_v2_bamboo_textures.py 產生，勿手改。全部程序產生（無外部來源）。'}
    meta['culm'] = {'green': build_culm('green', 101), 'dead': build_culm('dead', 202)}
    meta['atlas'] = {'A': build_atlas()}
    files = []
    for c in meta['culm'].values():
        files += list(c['files'].values())
    for a in meta['atlas'].values():
        files += [a['file'], a['normal']]
    meta['files_sha256'] = {rp: T.sha256(T.G + '/' + rp[len('res://'):]) for rp in files}
    with open(f'{OUT}/bamboo_tex.json', 'w', encoding='utf-8', newline='\n') as f:
        json.dump(meta, f, ensure_ascii=False, indent=1)
        f.write('\n')
    print('寫入', f'{OUT}/bamboo_tex.json')


if __name__ == '__main__':
    main()

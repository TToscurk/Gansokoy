#!/usr/bin/env python3
"""人間之里 V2 P9 R1：植被庫（Gensokyo Vegetation Library）貼圖產生器。

  python tools/build_village_v2_veg_textures.py [--only=bark|leaf] [--cell=<名>]

重用 tools/build_village_v2_textures.py 的 Poly Haven 下載／反照率校色／法線／.import 規約（不建平行 pipeline）。
輸出（godot/assets/village_v2/veg_kit/tex/）：
  - 樹皮：VB_<種>_albedo.jpg／VB_<種>_normal.jpg（1024²，Poly Haven CC0 bark 校色；紋理沿 V＝沿樹幹）
  - 葉叢 atlas：VL_{A,B}_albedo.png（RGBA）＋ VL_{A,B}_normal.png（切線空間，OpenGL），2048²。
    A＝針葉（杉／檜／赤松／黑松／庭園松）、柳、蕨、笹、灌木、枯枝、苔；B＝闊葉（小楢／椎／欅／樟／榎）、櫻、楓。
  - veg_tex.json：每格 region（像素＋UV）、錨點、平均色、覆蓋率、來源雜湊；Blender 端 build_veg_kit.py 只讀這份。

葉叢＝「偽 3D 繪製」：每格先在 3D 長出真正的枝序（主枝→小枝→葉／針葉／花），葉有葉柄、葉序（互生／對生／
二列／螺旋）、V 形對折、葉尖下垂、朝光偏向；再正交投影到卡片平面、依深度排序畫（前遮後）、依深度壓暗（叢內 AO），
同時輸出每個面的法線 → 法線貼圖。無照片來源（全部程序產生），沒有授權問題；顏色是概念圖取色後克制的變化。
錨點：base＝枝條基部在格底中央（卡片從樹枝長出去）；top＝下垂枝基部在格頂中央；center＝團塊中心在格中央。
"""
import json
import math
import os
import random
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_village_v2_textures as T  # noqa: E402

OUT = T.G + '/assets/village_v2/veg_kit/tex'
RES = 'res://assets/village_v2/veg_kit/tex'
BARK_SIZE = 1024
ATLAS = 2048
SS = 2  # 超取樣倍率
MARGIN = 6  # 格邊留白（px，避免 mip 互滲）

# ───────────────────────── 樹皮（Poly Haven CC0） ─────────────────────────
BARK = {
    'sugi':    {'src': 'japanese_cedar_bark', 'target': '#6A4E3C', 'desat': 0.10, 'ns': 1.0,
                'note': '杉／檜：紅褐縱向纖維狀剝皮'},
    'pine':    {'src': 'pine_bark', 'target': '#6E5646', 'desat': 0.15, 'ns': 1.0,
                'note': '松：龜甲狀深裂（黑松下部、赤松下部）'},
    'sakura':  {'src': 'sakura_bark', 'target': '#4D3E3A', 'desat': 0.10, 'ns': 0.9,
                'note': '櫻：暗紫褐、橫向皮孔'},
    'maple':   {'src': 'trident_maple_bark', 'target': '#706A5E', 'desat': 0.25, 'ns': 0.8,
                'note': '楓：灰褐平滑、細縱紋'},
    'willow':  {'src': 'bark_willow', 'target': '#5E564B', 'desat': 0.25, 'ns': 1.0,
                'note': '柳：灰褐縱深溝'},
    'zelkova': {'src': 'japanese_zelkova_bark', 'target': '#7A7264', 'desat': 0.30, 'ns': 0.9,
                'note': '欅：灰色鱗片斑駁'},
    'camphor': {'src': 'japanese_camphor_bark', 'target': '#5C4C3E', 'desat': 0.15, 'ns': 1.0,
                'note': '樟（Hero 古木）：褐色縱向細裂'},
    'hackberry': {'src': 'japanese_hackberry_bark', 'target': '#77756A', 'desat': 0.30, 'ns': 0.8,
                  'note': '榎／小楢／椎等一般雜木：灰色平滑帶苔'},
    'dead':    {'src': 'bark_brown_02', 'target': '#6F6A62', 'desat': 0.70, 'ns': 1.0,
                'note': '枯木／倒木：灰白風化'},
}


def build_bark():
    os.makedirs(OUT, exist_ok=True)
    meta = {}
    for name, m in BARK.items():
        src = T.fetch(m['src'])
        a = T.load(src['diff'])
        alb = T.albedo(a, {'mode': 'gain', 'target': m['target'], 'desat': m['desat']})
        nor = T.normal(T.load(src['nor']), {'normal_strength': m['ns']})
        files = {}
        for k, arr, q in (('albedo', alb, 90), ('normal', nor, 95)):
            img = Image.fromarray(np.clip(np.round(arr * 255), 0, 255).astype(np.uint8))
            img = img.resize((BARK_SIZE, BARK_SIZE), Image.LANCZOS)
            fn = f'VB_{name}_{k}.jpg'
            img.save(f'{OUT}/{fn}', quality=q, subsampling=0)
            rp = f'{RES}/{fn}'
            T.write_import(rp, k == 'normal')
            files[k] = rp
        mean = alb.reshape(-1, 3).mean(0)
        meta[name] = {'files': files, 'target_srgb': m['target'], 'albedo_mean_srgb': T.rgbhex(mean),
                      'note': m['note'],
                      'source': {'polyhaven_id': m['src'], 'url': f'https://polyhaven.com/a/{m["src"]}',
                                 'license': 'CC0', 'sha256': {k: T.sha256(v) for k, v in src.items()}}}
        print(f'bark {name}: {m["src"]} → mean {T.rgbhex(mean)}（目標 {m["target"]}）')
    return meta


# ───────────────────────── 向量／顏色工具 ─────────────────────────
def V(x, y, z):
    return np.array([x, y, z], dtype=np.float64)


def nrm(a):
    n = float(np.linalg.norm(a))
    return a / n if n > 1e-9 else a


def rot(v, axis, ang):
    """Rodrigues：v 繞 axis 轉 ang。"""
    k = nrm(axis)
    c, s = math.cos(ang), math.sin(ang)
    return v * c + np.cross(k, v) * s + k * float(np.dot(k, v)) * (1 - c)


def perp(d):
    a = V(0, 0, 1) if abs(d[2]) < 0.9 else V(1, 0, 0)
    return nrm(np.cross(d, a))


def hx(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def mul(c, k):
    return tuple(int(max(0, min(255, round(x * k)))) for x in c)


def mix(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def jit(c, rng, v=0.07, s=0.05, warm=0.0):
    """克制的顏色變化：亮度 ±v、往灰 ±s、暖冷 ±warm。"""
    r, g, b = [x / 255.0 for x in c]
    k = 1.0 + rng.uniform(-v, v)
    lum = 0.3 * r + 0.59 * g + 0.11 * b
    t = rng.uniform(-s, s)
    r, g, b = [(x + (lum - x) * t) * k for x in (r, g, b)]
    if warm:
        d = rng.uniform(-warm, warm)
        r, b = r + d, b - d * 0.6
    return tuple(int(max(0, min(255, round(x * 255)))) for x in (r, g, b))


VIEW = V(0, 0, 1)
LIGHT = nrm(V(0.25, 0.75, 0.6))   # 葉片朝光偏向（上方偏前）


# ───────────────────────── 偽 3D 卡片 ─────────────────────────
class Card:
    """模型空間（cm）：原點＝錨點、+y 上、+z 朝觀者。畫完 fit() 到格子像素，再依深度排序繪製。"""

    def __init__(self, w, h, anchor):
        self.w, self.h, self.anchor = w, h, anchor
        self.prims = []   # (pts Nx3, color, normal)
        self.scale = 1.0

    def poly(self, pts, col, n):
        P = np.asarray(pts, dtype=np.float64)
        if len(P) < 3:
            return
        n = nrm(np.asarray(n, dtype=np.float64))
        self.prims.append((P, col, n))

    def twig(self, pts, r0, r1, col, dark_side=0.82):
        """圓柱小枝：每段左右兩半（法線外傾），投影寬度＝2r。"""
        N = len(pts)
        for i in range(N - 1):
            p0, p1 = pts[i], pts[i + 1]
            t0, t1 = i / (N - 1), (i + 1) / (N - 1)
            ra, rb = r0 + (r1 - r0) * t0, r0 + (r1 - r0) * t1
            d = p1 - p0
            d2 = np.array([d[0], d[1]])
            L = float(np.linalg.norm(d2))
            if L < 1e-6:
                continue
            q = np.array([-d2[1], d2[0]]) / L
            qa = V(q[0], q[1], 0)
            ext = V(d2[0], d2[1], 0) / L * rb * 0.6
            mid0, mid1 = p0 - ext * 0.2, p1 + ext
            nf = nrm(VIEW - nrm(d) * float(np.dot(VIEW, nrm(d))))
            self.poly([mid0 + qa * ra, mid1 + qa * rb, mid1, mid0], col, nrm(nf + qa * 0.8))
            self.poly([mid0, mid1, mid1 - qa * rb, mid0 - qa * ra], mul(col, dark_side), nrm(nf - qa * 0.8))

    def fit(self):
        allp = np.concatenate([p[0] for p in self.prims])
        xs, ys = allp[:, 0], allp[:, 1]
        W, H, m = self.w, self.h, MARGIN
        ax_ = max(float(np.abs(xs).max()), 1e-6)
        if self.anchor == 'base':
            lo, hi = min(0.0, float(ys.min())), max(float(ys.max()), 1e-6)
            s = min((W / 2 - m) / ax_, (H - 2 * m) / (hi - lo))
            ox, oy = W / 2, m - lo * s
        elif self.anchor == 'top':
            lo, hi = min(float(ys.min()), -1e-6), max(0.0, float(ys.max()))
            s = min((W / 2 - m) / ax_, (H - 2 * m) / (hi - lo))
            ox, oy = W / 2, H - m - hi * s
        else:
            ox, oy = W / 2, H / 2
            s = min((W / 2 - m) / ax_, (H / 2 - m) / max(float(np.abs(ys).max()), 1e-6))
        out = []
        for P, c, n in self.prims:
            Q = P * s
            Q[:, 0] += ox
            Q[:, 1] += oy
            out.append((Q, c, n))
        self.prims = out
        self.scale = s
        self.anchor_px = (ox, self.h - oy)   # 影像座標（y 向下）
        return s

    def render(self, ao=0.32):
        self.fit()
        W, H = self.w * SS, self.h * SS
        rgb = Image.new('RGB', (W, H), (0, 0, 0))
        nim = Image.new('RGB', (W, H), (128, 128, 255))
        a = Image.new('L', (W, H), 0)
        dr, dn, da = ImageDraw.Draw(rgb), ImageDraw.Draw(nim), ImageDraw.Draw(a)
        zs = np.array([float(P[:, 2].mean()) for P, _, _ in self.prims])
        z0, z1 = float(np.percentile(zs, 3)), float(np.percentile(zs, 97))
        order = np.argsort(zs, kind='stable')
        for i in order:
            P, c, n = self.prims[i]
            t = min(1.0, max(0.0, (zs[i] - z0) / max(z1 - z0, 1e-6)))
            col = mul(c, 1.0 - ao + ao * t)
            if n[2] < 0:
                n = -n
            nc = tuple(int(round((float(v) * 0.5 + 0.5) * 255)) for v in n)
            pts = [(float(x) * SS, float(self.h - y) * SS) for x, y, _ in P]
            dr.polygon(pts, fill=col)
            dn.polygon(pts, fill=nc)
            da.polygon(pts, fill=255)
        rgb = rgb.resize((self.w, self.h), Image.LANCZOS)
        nim = nim.resize((self.w, self.h), Image.LANCZOS)
        a = a.resize((self.w, self.h), Image.LANCZOS)
        return dilate(rgb, nim, a)


def dilate(rgb, nim, a):
    """透明區 RGB／法線往外擴（以 alpha 加權模糊填色），避免 mip／BC 壓縮後黑邊或法線雜訊。"""
    A = np.asarray(a, dtype=np.float32)[..., None] / 255.0
    C = np.asarray(rgb, dtype=np.float32)
    Nn = np.asarray(nim, dtype=np.float32)
    wsum = max(float(A.sum()), 1.0)
    mean = (C * A).reshape(-1, 3).sum(0) / wsum
    outC, outN = C.copy(), Nn.copy()
    filled = A[..., 0] > 0.02

    def blur3(x, rad):
        return np.dstack([np.asarray(Image.fromarray(np.clip(x[..., k], 0, 255).astype(np.uint8)).filter(
            ImageFilter.GaussianBlur(rad)), dtype=np.float32) for k in range(x.shape[-1])])

    for rad in (1, 3, 8, 20):
        ab = np.asarray(Image.fromarray(np.clip(A[..., 0] * 255, 0, 255).astype(np.uint8)).filter(
            ImageFilter.GaussianBlur(rad)), dtype=np.float32) / 255.0
        cb = blur3(C * A, rad)
        nb = blur3(Nn * A, rad)
        ok = (ab > 0.03) & ~filled
        outC[ok] = cb[ok] / ab[ok][..., None]
        outN[ok] = nb[ok] / ab[ok][..., None]
        filled = filled | ok
    outC[~filled] = mean
    outN[~filled] = (128, 128, 255)
    return (np.clip(outC, 0, 255).astype(np.uint8), np.clip(outN, 0, 255).astype(np.uint8),
            np.asarray(a, dtype=np.uint8), mean)


# ───────────────────────── 生長原語 ─────────────────────────
def grow(p, d, L, n, rng, bend=None, bend_amt=0.0, jit_amt=0.08, gravity=0.0):
    """沿 d 走 L（n 段）：每段繞 bend 軸轉 bend_amt/n、加隨機擺動、往下彎 gravity。"""
    pts = [np.array(p, dtype=np.float64)]
    d = nrm(np.array(d, dtype=np.float64))
    ax = perp(d) if bend is None else nrm(bend)
    for i in range(n):
        d = rot(d, ax, bend_amt / n)
        d = nrm(d + V(rng.gauss(0, jit_amt), rng.gauss(0, jit_amt), rng.gauss(0, jit_amt)) + V(0, -gravity / n, 0))
        pts.append(pts[-1] + d * (L / n))
    return pts


def resample(pts, step):
    """折線等距重取樣（step 單位同模型）。"""
    out = [np.array(pts[0], dtype=np.float64)]
    carry = 0.0
    for i in range(1, len(pts)):
        a, b = np.array(pts[i - 1], dtype=np.float64), np.array(pts[i], dtype=np.float64)
        seg = b - a
        L = float(np.linalg.norm(seg))
        if L < 1e-9:
            continue
        s = step - carry
        while s <= L:
            out.append(a + seg * (s / L))
            s += step
        carry = L - (s - step)
    return out


def tangent_at(pts, i):
    i = max(1, min(len(pts) - 1, i))
    return nrm(pts[i] - pts[i - 1])


def outline(L, W, shape, serr=0.0, teeth=0, teeth_from=0.12, asym=0.0, wave=0.0, lobes_pinna=0):
    """葉輪廓（局部：x 橫、y 沿葉軸；葉柄端 y=0）。回傳左緣（基→尖）與右緣（基→尖）。"""
    n = max(18, teeth * 2 + 8) if teeth else 18
    if lobes_pinna:
        n = max(n, lobes_pinna * 4)
    left, right = [], []
    for i in range(n + 1):
        s = i / n
        if shape == 'obovate':        # 倒卵（小楢）：上 1/3 最寬、基部楔形
            w = math.sin(math.pi * min(1.0, s ** 0.62)) ** 0.85 * (0.35 + 0.65 * min(1.0, s / 0.35))
        elif shape == 'ovate':        # 卵形（樟、榎）：下 1/3 最寬
            w = math.sin(math.pi * s ** 1.45) ** 0.9
        elif shape == 'acuminate':    # 尾尖（櫻、欅）
            w = math.sin(math.pi * s ** 1.15) ** 0.95 * (1.0 - 0.55 * max(0.0, s - 0.62) / 0.38) ** 1.3
        elif shape == 'lance':        # 披針（柳、笹）
            w = math.sin(math.pi * s ** 1.1) ** 1.25
        elif shape == 'elliptic':
            w = math.sin(math.pi * s) ** 0.75
        else:
            w = math.sin(math.pi * s) ** 0.85
        if wave:
            w *= 1.0 + wave * math.sin(s * 9.0)
        wl = w * (1.0 - asym * (1.0 - s) ** 2)
        wr = w
        if teeth and teeth_from < s < 0.96:
            ph = (s * teeth) % 1.0
            tooth = (ph if ph < 0.75 else (1 - ph) * 3.0)   # 鋸齒：緩升急降、朝葉尖
            f = 1.0 + serr * (tooth - 0.4)
            wl *= f
            wr *= f
        if lobes_pinna and 0.05 < s < 0.96:
            ph = (s * lobes_pinna) % 1.0
            lob = 0.55 + 0.45 * math.sin(math.pi * ph) ** 0.6
            wl *= lob
            wr *= lob
        left.append((-wl * W * 0.5, s * L))
        right.append((wr * W * 0.5, s * L))
    return left, right


def leaf(card, base, a, n, L, W, shape, col, under, rng, serr=0.0, teeth=0, teeth_from=0.12, asym=0.0,
         fold=0.22, droop=0.15, rib=True, veins3=False, wave=0.0, lobes_pinna=0, rib_col=None):
    """一片葉：葉身基部 base，葉軸 a，葉面法線 n（⟂a）。V 形對折、葉尖下垂；看到背面用 under 色。"""
    side = nrm(np.cross(a, n))
    left, right = outline(L, W, shape, serr, teeth, teeth_from, asym, wave, lobes_pinna)

    def P(x, y):
        return base + a * y + side * x + n * (abs(x) * fold) - n * droop * (y / L) ** 2 * L

    facing = float(np.dot(n, VIEW)) >= 0
    c = col if facing else under
    nl, nr = nrm(n + side * fold * 1.6), nrm(n - side * fold * 1.6)
    Lp = [P(x, y) for x, y in left] + [P(0, L), P(0, 0)]
    Rp = [P(x, y) for x, y in right] + [P(0, L), P(0, 0)]
    halves = [(Lp, nl, mul(c, 0.93)), (Rp, nr, c)]
    halves.sort(key=lambda h: float(np.mean([p[2] for p in h[0]])))
    for pts, nn, cc in halves:
        card.poly(pts, cc, nn)
    if rib and L > 0:
        rc = rib_col or mix(c, (210, 205, 150), 0.25)
        w = max(L * 0.012, 0.03)
        card.poly([P(-w, 0), P(-w * 0.3, L * 0.9), P(w * 0.3, L * 0.9), P(w, 0)], rc, n)
        if veins3:
            for sg in (-1, 1):
                card.poly([P(sg * w * 0.5, L * 0.08), P(sg * W * 0.30, L * 0.55), P(sg * (W * 0.30 + w), L * 0.55),
                           P(sg * (w * 1.2), L * 0.08)], rc, n)


def leaf_frame(t, rng, spread=0.55, light_bias=0.55, out=None, ang=(0.5, 1.1), phy_az=0.0):
    """由枝條切線 t 算葉軸 a 與葉面法線 n：葉軸從枝條向外張 ang、繞枝條方位 phy_az；法線偏向光源。"""
    o = perp(t) if out is None else nrm(out - t * float(np.dot(out, t)))
    o = rot(o, t, phy_az)
    a = nrm(rot(t, np.cross(t, o), rng.uniform(*ang)))
    want = nrm(LIGHT * light_bias + V(rng.gauss(0, spread), rng.gauss(0, spread), rng.gauss(0, spread)) +
               VIEW * 0.7)
    n = nrm(want - a * float(np.dot(want, a)))
    return a, n


def needle(card, p, d, L, w, col, curve=0.0, bend_ax=None):
    """單根針葉：從 p 沿 d，微彎。投影成細長菱形。"""
    d = nrm(d)
    ax = perp(d) if bend_ax is None or float(np.linalg.norm(bend_ax)) < 1e-6 else nrm(bend_ax)
    mid = p + nrm(rot(d, ax, curve * 0.5)) * L * 0.5
    tip = mid + nrm(rot(d, ax, curve)) * L * 0.5
    dd = tip - p
    d2 = np.array([dd[0], dd[1]])
    LL = float(np.linalg.norm(d2))
    q = V(1, 0, 0) if LL < 1e-6 else V(-d2[1] / LL, d2[0] / LL, 0)
    nf = nrm(VIEW - d * float(np.dot(VIEW, d)) + ax * 0.3)
    card.poly([p + q * w * 0.5, mid + q * w * 0.4, tip, mid - q * w * 0.4, p - q * w * 0.5], col, nf)


# ───────────────────────── 各樹種（模型單位 cm） ─────────────────────────
BARK_TW = {'sugi': hx('#5A4232'), 'pine': hx('#5E4636'), 'broad': hx('#5A4C3E'), 'sakura': hx('#3E302E'),
           'maple': hx('#5E5244'), 'willow': hx('#6B6040'), 'grey': hx('#6E675E')}


def sp_sugi(card, rng, base, tip, n_main=3, droop=0.0, brown=0.0, young=False, old=0.0):
    """杉：繩狀短錐形針葉螺旋包住小枝，小枝再成叢（遠看一團團尖頭）。"""
    tw = BARK_TW['sugi']
    shoots = []
    for k in range(n_main):
        d0 = nrm(V((k - (n_main - 1) / 2) * 0.55 + rng.uniform(-0.2, 0.2), 1.0, rng.uniform(-0.5, 0.5)))
        L = rng.uniform(45, 60) * (0.75 if young else 1.0)
        main = grow(V(rng.uniform(-2, 2), 0, rng.uniform(-3, 3)), d0, L, 14, rng, bend_amt=rng.uniform(-0.4, 0.4),
                    gravity=droop)
        card.twig(main[:6], 0.55, 0.3, tw)
        shoots.append((main, 0, k))
        for i in range(3, len(main) - 1):
            t = tangent_at(main, i)
            frac = i / len(main)
            az = i * 2.39996 + rng.uniform(-0.3, 0.3)
            o = rot(perp(t), t, az)
            dl = nrm(rot(t, np.cross(t, o), rng.uniform(0.6, 1.0)))
            Ll = L * (0.42 - 0.3 * frac) * rng.uniform(0.75, 1.2)
            lat = grow(main[i], dl, Ll, 7, rng, bend_amt=rng.uniform(-0.3, 0.3), gravity=droop * 0.6)
            shoots.append((lat, 1, k))
            for j in range(1, len(lat) - 1):
                if rng.random() < 0.55:
                    t2 = tangent_at(lat, j)
                    o2 = rot(perp(t2), t2, rng.uniform(0, 6.28))
                    d2 = nrm(rot(t2, np.cross(t2, o2), rng.uniform(0.5, 0.9)))
                    shoots.append((grow(lat[j], d2, Ll * 0.4, 4, rng), 2, k))
    dead_groups = {k for k in range(n_main) if rng.random() < brown}
    for pts, lvl, k in shoots:
        rp = resample(pts, 0.5)
        n = len(rp)
        for i in range(1, n):
            t = tangent_at(rp, i)
            fr = i / max(1, n - 1)
            for j in range(4):
                az = i * 2.39996 + j * 2.094
                o = rot(perp(t), t, az)
                d = nrm(rot(t, np.cross(t, o), rng.uniform(0.55, 0.85)))
                c = mix(base, tip, max(0.0, fr - 0.55) / 0.45 * 0.9 if lvl > 0 else 0.0)
                if old and rng.random() < old * (1 - fr):
                    c = mix(c, hx('#6E6440'), rng.uniform(0.3, 0.7))
                if k in dead_groups:
                    c = mix(c, hx('#86603A'), rng.uniform(0.55, 0.9))
                needle(card, rp[i], d, rng.uniform(1.3, 1.9) * (0.8 if lvl == 2 else 1.0), 0.55,
                       jit(c, rng, 0.08, 0.04), curve=-0.5, bend_ax=np.cross(d, t))


def sp_hinoki(card, rng, base, tip, n_fan=6, open_=0.0, fine=False):
    """檜：扁平鱗葉噴枝。每個 spray＝一個平面上的羽狀三回分枝，外形像圓鈍的扇／三角；鱗葉用扇貝邊的窄帶，
    主軸與葉同色（不露綠棍），末端圓鈍二叉；6–7 個 spray 前後疊、微下垂、方向散開，中間留縫。"""
    # fine（P9 R1c 檜 final pass）：鱗葉帶寬約 0.6×、多一回分枝、扇間散開、中心少疊 → 細碎蕾絲狀噴枝（R1b 審圖：葉團偏粗、像闊葉）
    wk = 0.72 if fine else 1.0
    sprays = []
    for k in range(n_fan):
        ang = (k - (n_fan - 1) / 2) * (0.6 if fine else 0.42) + rng.uniform(-0.15, 0.15)
        d0 = nrm(V(math.sin(ang), math.cos(ang), rng.uniform(-0.2, 0.3)))
        pn = nrm(V(rng.uniform(-0.35, 0.35), rng.uniform(0.2, 0.6), 1.0))
        d0 = nrm(d0 - pn * float(np.dot(d0, pn)))
        org = V(rng.uniform(-1.5, 1.5), rng.uniform(0, 4), rng.uniform(-8, 8))
        if fine:
            org = org + d0 * rng.uniform(3, 9)          # 扇基部錯開，中心不疊成實心
        sprays.append((org, d0, pn, rng.uniform(26, 36) * (1.0 - 0.15 * abs(ang))))
    sprays.sort(key=lambda t: t[0][2])

    def strip(pts, w0, w1, pn, c0, c1):
        n = len(pts)
        for i in range(n - 1):
            fr = i / (n - 1)
            wa = w0 + (w1 - w0) * fr
            wb = w0 + (w1 - w0) * (i + 1) / (n - 1)
            t = nrm(pts[i + 1] - pts[i])
            sd = nrm(np.cross(pn, t))
            a0, a1 = pts[i], pts[i + 1]
            m = (a0 + a1) * 0.5
            c = mix(c0, c1, fr)
            card.poly([a0 + sd * wa, m + sd * (wa + wb) * 0.62, a1 + sd * wb, a1 - sd * wb, m - sd * (wa + wb) * 0.62,
                       a0 - sd * wa], c, nrm(pn + V(rng.gauss(0, 0.1), rng.gauss(0, 0.1), 0)))
        tp = pts[-1]
        t = tangent_at(pts, n - 1)
        for sg in (-1, 1):   # 圓鈍二叉
            dd = nrm(rot(t, pn, sg * 0.5))
            sd = nrm(np.cross(pn, dd))
            e = tp + dd * w1 * 2.2
            card.poly([tp + sd * w1, e + sd * w1 * 0.8, e + dd * w1 * 0.9, e - sd * w1 * 0.8, tp - sd * w1], c1, pn)

    for org, d0, pn, L0 in sprays:
        sh = jit(mix(base, tip, rng.uniform(0.0, 0.25)), rng, 0.05, 0.03)
        hi = jit(tip, rng, 0.05, 0.03)
        main = grow(org, d0, L0, 10, rng, bend=pn, bend_amt=rng.uniform(-0.3, 0.3), jit_amt=0.0, gravity=0.25)
        main = [q - pn * float(np.dot(q - org, pn)) for q in main]
        strip(main, 0.55 * wk, 0.32 * wk, pn, sh, mix(sh, hi, 0.6))
        for i in range(1, len(main) - 1):
            t = tangent_at(main, i)
            fr = i / (len(main) - 1)
            for sg in (-1, 1):
                if rng.random() > 0.92 - open_:
                    continue
                d1 = nrm(rot(t, pn, sg * rng.uniform(0.85, 1.05)))
                L1 = L0 * (0.40 * (1 - fr) ** 0.8 + 0.06) * rng.uniform(0.85, 1.1)
                b1 = grow(main[i], d1, L1, 6, rng, bend=pn, bend_amt=sg * rng.uniform(0.1, 0.4), jit_amt=0.0)
                b1 = [q - pn * float(np.dot(q - org, pn)) for q in b1]
                strip(b1, 0.42 * wk, 0.26 * wk, pn, mix(sh, hi, 0.2), mix(sh, hi, 0.75))
                for j in range(1, len(b1) - 1):
                    t2 = tangent_at(b1, j)
                    for sg2 in (-1, 1):
                        if rng.random() > 0.8 - open_:
                            continue
                        d2 = nrm(rot(t2, pn, sg2 * rng.uniform(0.8, 1.05)))
                        L2 = L1 * (0.42 * (1 - j / len(b1)) + 0.08) * rng.uniform(0.8, 1.1)
                        b2 = [b1[j], b1[j] + d2 * L2 * 0.5, b1[j] + d2 * L2]
                        b2 = [q - pn * float(np.dot(q - org, pn)) for q in b2]
                        strip(b2, 0.32 * wk, 0.22 * wk, pn, mix(sh, hi, 0.45), hi)
                        if fine and L2 > 2.2:
                            # 三回分枝：末梢再分 1–2 根短鈍小枝（外緣碎）
                            for sg3 in (-1, 1):
                                if rng.random() < 0.35:
                                    continue
                                d3 = nrm(rot(d2, pn, sg3 * rng.uniform(0.7, 1.0)))
                                q0 = b2[1] + (b2[2] - b2[1]) * rng.uniform(0.0, 0.6)
                                L3 = L2 * rng.uniform(0.3, 0.45)
                                b3 = [q0, q0 + d3 * L3 * 0.5, q0 + d3 * L3]
                                b3 = [q - pn * float(np.dot(q - org, pn)) for q in b3]
                                strip(b3, 0.24 * wk, 0.18 * wk, pn, mix(sh, hi, 0.6), hi)


def sp_pine(card, rng, base, tip, nl=(9, 14), stiff=0.5, n_shoot=5, red=True, old_yellow=0.05):
    """松枝端：主枝分 3–6 根小枝（3D 扇開），每根小枝後 2/3 密生針葉（赤松細軟淺綠、黑松粗硬深綠），頂芽。"""
    tw = BARK_TW['pine'] if not red else hx('#8A5A3E')
    trunk = grow(V(0, 0, 0), nrm(V(rng.uniform(-0.3, 0.3), 1, rng.uniform(-0.3, 0.3))), 7, 3, rng)
    card.twig(trunk, 0.9, 0.7, tw)
    tips = []
    for k in range(n_shoot):
        a = (k / n_shoot) * 2 * math.pi + rng.uniform(-0.4, 0.4)
        d = nrm(V(math.cos(a) * 0.65, 1.0, math.sin(a) * 0.65))
        L = rng.uniform(12, 26)
        sh = grow(trunk[-1] + V(0, rng.uniform(-3, 0), 0), d, L, 8, rng, bend_amt=rng.uniform(-0.7, 0.7))
        card.twig(sh, 0.55, 0.35, tw)
        tips.append(sh)
    for sh in tips:
        rp = resample(sh, 0.26)
        n = len(rp)
        for i in range(int(n * 0.2), n):
            t = tangent_at(rp, i)
            fr = (i - n * 0.3) / (n * 0.7)
            az = i * 2.39996
            o = rot(perp(t), t, az)
            for j in range(2):
                o2 = rot(o, t, j * 0.35)
                d = nrm(rot(t, np.cross(t, o2), rng.uniform(0.3, 1.0)))
                Ln = rng.uniform(*nl) * (0.7 + 0.3 * fr)
                c = mix(base, tip, rng.random() ** 1.5 * (0.5 + 0.5 * fr))
                if rng.random() < old_yellow * (1 - fr):
                    c = mix(c, hx('#A89048'), rng.uniform(0.5, 0.9))
                needle(card, rp[i], d, Ln, 0.30 if red else 0.38, jit(c, rng, 0.07, 0.04),
                       curve=(1 - stiff) * rng.uniform(0.1, 0.45), bend_ax=np.cross(d, t))
        t = tangent_at(rp, n - 1)
        bud = rp[-1] + t * 2.2
        s = perp(t)
        card.poly([rp[-1] + s * 0.45, bud + s * 0.2, bud + t * 0.6, bud - s * 0.2, rp[-1] - s * 0.45],
                  hx('#A08A60'), VIEW)


def sp_pine_pad(card, rng, base, tip, lobes=3):
    """庭園松（玉散らし）：2–4 個雲狀枝團，每團由許多斜向外的短針束構成；枝骨在下、團頂亮、團底暗。"""
    tw = BARK_TW['pine']
    centers = []
    for k in range(lobes):
        a = k / lobes * 2 * math.pi + rng.uniform(-0.5, 0.5)
        r = rng.uniform(8, 16)
        centers.append((V(math.cos(a) * r, math.sin(a) * r * 0.8, 0), rng.uniform(14, 20)))
    for c, R in centers:
        card.twig([V(0, 0, -6), c + V(0, 0, -4)], 1.0, 0.7, tw)
    for c, R in centers:
        for i in range(int(R * R * 0.42)):
            u = rng.random()
            r = R * math.sqrt(u)
            a = rng.uniform(0, 2 * math.pi)
            p = c + V(math.cos(a) * r, math.sin(a) * r * 0.85, R * 0.55 * (1 - u) + rng.uniform(-1, 1))
            radial = nrm(V(math.cos(a), math.sin(a) * 0.85, 0))
            dmain = nrm(radial * rng.uniform(0.5, 0.9) + V(0, 0, 1) * rng.uniform(0.5, 0.9) +
                        V(rng.gauss(0, 0.2), rng.gauss(0, 0.2), 0))
            shoot = p - dmain * 2.5
            t = dmain
            for j in range(rng.randint(9, 15)):
                o = rot(perp(t), t, rng.uniform(0, 6.28))
                d = nrm(rot(t, np.cross(t, o), rng.uniform(0.25, 0.75)))
                cc = mix(base, tip, (1 - u) * 0.6 + rng.uniform(0, 0.4))
                needle(card, shoot + t * rng.uniform(0, 2.5), d, rng.uniform(5, 8), 0.34, jit(cc, rng, 0.07, 0.04),
                       curve=0.15)


def sp_willow(card, rng, col, n=2, length=(85, 110), fork=0.6, curl=0.0):
    """柳：細枝從上方垂下（重力弧），1–2 次分叉，披針葉沿枝互生，大多順枝下垂、少數側向。"""
    tw = BARK_TW['willow']
    strands = []
    for k in range(n):
        x0 = (k - (n - 1) / 2) * rng.uniform(4, 7)
        d0 = nrm(V(x0 * 0.05 + rng.uniform(-0.15, 0.15), -0.6, rng.uniform(-0.4, 0.4)))
        L = rng.uniform(*length) * (1.0 if k == 0 else rng.uniform(0.6, 1.0))
        pts = grow(V(x0 * 0.4, 0, rng.uniform(-3, 3)), d0, L, 22, rng, jit_amt=0.02, gravity=0.8 + curl)
        strands.append(pts)
        if rng.random() < fork:
            i = rng.randint(4, 10)
            t = tangent_at(pts, i)
            d = nrm(rot(t, V(0, 0, 1), rng.choice((-1, 1)) * rng.uniform(0.2, 0.4)))
            strands.append(grow(pts[i], d, L * rng.uniform(0.4, 0.7), 12, rng, jit_amt=0.02, gravity=0.6))
    for pts in strands:
        card.twig(pts, 0.32, 0.18, tw)
        rp = resample(pts, 1.3)
        for i in range(1, len(rp)):
            if rng.random() < 0.12:
                continue   # 局部缺葉
            t = tangent_at(rp, i)
            sg = 1 if i % 2 else -1
            o = rot(perp(t), t, sg * 1.3 + rng.uniform(-0.4, 0.4))
            a = nrm(rot(t, np.cross(t, o), rng.uniform(0.35, 0.8)))
            nn = nrm(VIEW * 0.9 + LIGHT * 0.3 + V(rng.gauss(0, 0.4), rng.gauss(0, 0.3), 0))
            nn = nrm(nn - a * float(np.dot(nn, a)))
            Lf = rng.uniform(8, 12)
            c = jit(col, rng, 0.08, 0.04, 0.015)
            leaf(card, rp[i] + a * 0.4, a, nn, Lf, Lf * 0.2, 'lance', c, mix(c, (190, 200, 170), 0.35), rng,
                 serr=0.04, teeth=10, fold=0.15, droop=-0.05, rib=False)


def sp_broad(card, rng, base, tip, under, L=(6, 9), wr=0.5, shape='elliptic', serr=0.0, teeth=0, teeth_from=0.12,
             asym=0.0, n_shoot=4, phyllo='alt', tipcluster=0.0, zig=0.0, dens=1.0, accent=None, veins3=False,
             wave=0.0, twig_col=None, shoot_len=(22, 34)):
    """闊葉小枝：主枝→3–5 根側枝（3D 不同深度）→ 葉互生／二列（欅）、葉柄、朝光；tipcluster＝葉集中枝端（小楢）。"""
    tw = twig_col or BARK_TW['broad']
    main = grow(V(0, 0, 0), nrm(V(rng.uniform(-0.25, 0.25), 1, rng.uniform(-0.2, 0.2))), rng.uniform(38, 50), 10,
                rng, bend_amt=rng.uniform(-0.5, 0.5))
    card.twig(main, 0.75, 0.25, tw)
    shoots = [main]
    for k in range(n_shoot):
        i = int(len(main) * (0.1 + 0.65 * k / max(1, n_shoot - 1)) + rng.uniform(-1, 1))
        i = max(1, min(len(main) - 2, i))
        t = tangent_at(main, i)
        o = rot(perp(t), t, k * 2.2 + rng.uniform(-0.5, 0.5))
        d = nrm(rot(t, np.cross(t, o), rng.uniform(0.5, 1.0)))
        sh = grow(main[i], d, rng.uniform(*shoot_len) * (1.0 - 0.3 * k / n_shoot), 8, rng,
                  bend_amt=rng.uniform(-0.6, 0.6), gravity=0.2)
        if zig:
            pd = perp(d)
            sh = [p + pd * (zig * (1 if j % 2 else -1) if 0 < j < len(sh) - 1 else 0) for j, p in enumerate(sh)]
        card.twig(sh, 0.4, 0.15, tw)
        shoots.append(sh)
    items = []
    for sh in shoots:
        n = len(sh)
        for i in range(1, n):
            fr = i / (n - 1)
            if tipcluster and fr < 1 - tipcluster and rng.random() < 0.75:
                continue
            if rng.random() > dens:
                continue
            reps = 1 if phyllo in ('alt', 'dist') else 2
            if rng.random() < 0.45:
                reps += 1
            if tipcluster and fr > 1 - tipcluster * 0.5:
                reps = 4
            t = tangent_at(sh, i)
            for r in range(reps):
                if phyllo == 'dist':
                    az = (math.pi if i % 2 else 0.0) + rng.uniform(-0.2, 0.2)
                elif phyllo == 'opp':
                    az = r * math.pi + (i % 2) * math.pi / 2
                else:
                    az = i * 2.39996 + r * 2.1
                a, nvec = leaf_frame(t, rng, spread=0.5, phy_az=az, ang=(0.45, 1.05))
                Lf = rng.uniform(*L) * (0.75 + 0.25 * fr)
                c = mix(base, tip, rng.random() ** 2 * (0.4 + 0.6 * fr))
                if accent and rng.random() < accent[1] * (0.4 + 0.6 * fr):
                    c = mix(c, accent[0], rng.uniform(0.5, 1.0))
                pet = Lf * 0.12
                items.append((sh[i] + a * pet, a, nvec, Lf, jit(c, rng, 0.07, 0.04, 0.01)))
                card.twig([sh[i], sh[i] + a * pet], 0.08, 0.06, mix(tw, c, 0.5))
    rng.shuffle(items)
    for b, a, nvec, Lf, c in items:
        leaf(card, b, a, nvec, Lf, Lf * wr, shape, c, mix(c, under, 0.75), rng, serr, teeth, teeth_from, asym,
             veins3=veins3, wave=wave)


def flower(card, c, nf, r, petal, center, rng, bud=False):
    """櫻花一朵：5 瓣（瓣端淺缺刻、杯狀），花心深粉、雄蕊。"""
    e1 = perp(nf)
    e2 = nrm(np.cross(nf, e1))
    if bud:
        card.poly([c + e1 * r * 0.35, c + nf * r * 0.9, c - e1 * r * 0.35, c - nf * r * 0.2],
                  mix(petal, hx('#D88A9C'), 0.6), nrm(nf + VIEW))
        return
    rot0 = rng.uniform(0, 2 * math.pi)
    for k in range(5):
        ang = rot0 + k * 2 * math.pi / 5
        u = e1 * math.cos(ang) + e2 * math.sin(ang)
        v = nrm(np.cross(nf, u))
        pts = []
        for i in range(9):
            s = i / 8
            w = math.sin(math.pi * min(1.0, s * 1.08)) ** 0.7 * 0.55
            if s > 0.88:
                w *= 0.75   # 瓣端缺刻
            pts.append(c + u * (s * r) + v * (w * r) + nf * (s * s * r * 0.35))
        for i in range(8, -1, -1):
            s = i / 8
            w = math.sin(math.pi * min(1.0, s * 1.08)) ** 0.7 * 0.55
            pts.append(c + u * (s * r) - v * (w * r) + nf * (s * s * r * 0.35))
        pc = jit(mix(petal, hx('#F6EEEE'), rng.uniform(0, 0.4)), rng, 0.03, 0.03)
        card.poly(pts, pc, nrm(nf + u * 0.35))
    card.poly([c + e1 * r * 0.18 + nf * 0.05, c + e2 * r * 0.18 + nf * 0.05, c - e1 * r * 0.18 + nf * 0.05,
               c - e2 * r * 0.18 + nf * 0.05], center, nf)
    for k in range(7):
        ang = rng.uniform(0, 2 * math.pi)
        u = e1 * math.cos(ang) + e2 * math.sin(ang)
        tipp = c + u * r * 0.35 + nf * r * 0.25
        card.poly([c + nf * 0.06, tipp, tipp + u * 0.08], hx('#C9A060'), nf)


def sp_sakura(card, rng, petal, leafc=None, leaf_frac=0.0, density=1.0, n_shoot=5, bloom_scale=1.25):
    """櫻：暗色粗糙小枝，短枝（spur）上 2–5 朵繖形花序、花梗放射；山櫻混紅銅色嫩葉。"""
    tw = BARK_TW['sakura']
    main = grow(V(0, 0, 0), nrm(V(rng.uniform(-0.3, 0.3), 1, rng.uniform(-0.2, 0.2))), rng.uniform(40, 52), 9, rng,
                bend_amt=rng.uniform(-0.5, 0.5))
    card.twig(main, 0.6, 0.25, tw)
    shoots = [main]
    for k in range(n_shoot):
        i = max(1, min(len(main) - 2, int(len(main) * (0.25 + 0.55 * k / max(1, n_shoot - 1)))))
        t = tangent_at(main, i)
        o = rot(perp(t), t, k * 2.3 + rng.uniform(-0.4, 0.4))
        d = nrm(rot(t, np.cross(t, o), rng.uniform(0.5, 0.95)))
        sh = grow(main[i], d, rng.uniform(18, 28), 6, rng, bend_amt=rng.uniform(-0.6, 0.6))
        card.twig(sh, 0.4, 0.2, tw)
        shoots.append(sh)
    items = []
    for sh in shoots:
        for i in range(1, len(sh)):
            if rng.random() > density:
                continue
            t = tangent_at(sh, i)
            spur_d = nrm(rot(t, np.cross(t, rot(perp(t), t, rng.uniform(0, 6.28))), rng.uniform(0.6, 1.2)))
            spur = sh[i] + spur_d * 1.2
            card.twig([sh[i], spur], 0.25, 0.2, tw)
            for j in range(rng.randint(3, 5)):
                pd = nrm(spur_d * 0.6 + V(rng.gauss(0, 0.6), rng.gauss(0, 0.6), rng.gauss(0, 0.6)) + VIEW * 0.4)
                fc = spur + pd * rng.uniform(1.8, 3.2)
                card.twig([spur, fc], 0.07, 0.06, hx('#6E6A40'))
                items.append(('f', fc, nrm(pd * 0.6 + VIEW * 1.2 + V(rng.gauss(0, 0.3), rng.gauss(0, 0.3), 0)),
                              rng.uniform(1.5, 1.85) * bloom_scale, rng.random() < 0.15))
            if leafc and rng.random() < leaf_frac:
                for j in range(rng.randint(2, 3)):
                    a, nvec = leaf_frame(spur_d, rng, 0.6, ang=(0.2, 0.8), phy_az=j * 2.1)
                    items.append(('l', spur + a * 0.3, a, nvec, rng.uniform(3.5, 5.5)))
    rng.shuffle(items)
    for it in items:
        if it[0] == 'l':
            _, b, a, nvec, Lf = it
            c = jit(leafc, rng, 0.08, 0.04, 0.02)
            leaf(card, b, a, nvec, Lf, Lf * 0.42, 'acuminate', c, mix(c, (160, 140, 110), 0.4), rng, 0.25, 14,
                 fold=0.45, droop=0.1)
        else:
            _, fc, nf, r, bud = it
            flower(card, fc, nf, r, petal, hx('#C27A8C'), rng, bud)


def sp_weeping(card, rng, petal, n=2, length=(80, 105)):
    """枝垂櫻：從上方垂下的弧枝＋側生短枝，花成簇（不是串珠）：短枝上 3–5 朵、部分段落留空。"""
    tw = BARK_TW['sakura']
    arcs = []
    for k in range(n):
        x0 = (k - (n - 1) / 2) * rng.uniform(4, 8)
        d0 = nrm(V(x0 * 0.05 + rng.uniform(-0.2, 0.2), -0.5, rng.uniform(-0.4, 0.4)))
        L = rng.uniform(*length) * (1.0 if k == 0 else rng.uniform(0.55, 0.9))
        arcs.append(grow(V(x0 * 0.4, 0, rng.uniform(-3, 3)), d0, L, 18, rng, jit_amt=0.02, gravity=0.8))
    items = []
    for pts in arcs:
        card.twig(pts, 0.4, 0.15, tw)
        i = 3
        while i < len(pts) - 1:
            if rng.random() < 0.25:
                i += 2
                continue   # 留空段
            t = tangent_at(pts, i)
            d = nrm(rot(t, V(0, 0, 1), rng.choice((-1, 1)) * rng.uniform(0.3, 0.6)) + V(0, -0.3, 0))
            off = grow(pts[i], d, rng.uniform(4, 8), 4, rng, gravity=0.6)
            card.twig(off, 0.18, 0.1, tw)
            for p in off[1:]:
                for j in range(rng.randint(1, 3)):
                    pd = nrm(V(rng.gauss(0, 0.7), rng.gauss(-0.3, 0.6), rng.gauss(0.3, 0.6)))
                    fc = p + pd * rng.uniform(1.2, 2.2)
                    card.twig([p, fc], 0.06, 0.05, hx('#6E6A40'))
                    items.append((fc, nrm(pd * 0.5 + VIEW * 1.2), rng.uniform(1.6, 2.0), rng.random() < 0.12))
            i += rng.randint(1, 3)
    rng.shuffle(items)
    for fc, nf, r, bud in items:
        flower(card, fc, nf, r, petal, hx('#C27A8C'), rng, bud)


def palm_leaf(card, base, a, n, R, col, under, rng, lobes=7, depth=0.62, cup=0.12):
    """掌狀葉（雞爪槭）：7（5）裂、裂片披針有細鋸齒、深裂；葉面微杯狀。"""
    side = nrm(np.cross(a, n))
    facing = float(np.dot(n, VIEW)) >= 0
    c = col if facing else under
    spread = math.radians(260 if lobes >= 7 else 230)
    pts = []
    N = lobes * 14
    for i in range(N + 1):
        t = i / N
        ang = -spread / 2 + spread * t
        ph = (t * lobes) % 1.0
        tri = 1.0 - abs(ph - 0.5) * 2.0
        r = R * (1.0 - depth + depth * tri ** 0.55)
        r *= 1.0 - 0.32 * (abs(ang) / (spread / 2)) ** 1.5
        if i % 2 == 1 and tri > 0.2:
            r *= 1.035
        x, y = math.sin(ang) * r, math.cos(ang) * r
        pts.append(base + side * x + a * y + n * (cup * (x * x + y * y) / R))
    pts.append(base)
    card.poly(pts, c, n)
    rc = mix(c, (200, 160, 110), 0.3)
    for k in range(lobes):
        ang = -spread / 2 + spread * (k + 0.5) / lobes
        r = R * 0.85 * (1.0 - 0.32 * (abs(ang) / (spread / 2)) ** 1.5)
        e = base + side * math.sin(ang) * r + a * math.cos(ang) * r + n * cup * r
        s = nrm(np.cross(n, e - base)) * R * 0.012
        card.poly([base + s, e, base - s], rc, n)


def sp_maple(card, rng, palette, R=(3.8, 5.0), n_shoot=5, sparse=1.0, layered=True, shoot_shift=0.0):
    """楓：對生長柄掌狀葉、層狀平展的枝（葉面多朝上→側看有不少斜向葉）；palette＝[(色, 權重)…]，依枝成片變色。"""
    tw = BARK_TW['maple']
    tot = sum(w for _, w in palette)

    def pick():
        r = rng.random() * tot
        for col, w in palette:
            r -= w
            if r <= 0:
                return col
        return palette[-1][0]

    main = grow(V(0, 0, 0), nrm(V(rng.uniform(-0.4, 0.4), 1, rng.uniform(-0.2, 0.2))), rng.uniform(38, 48), 9, rng,
                bend_amt=rng.uniform(-0.6, 0.6))
    card.twig(main, 0.6, 0.2, tw)
    shoots = [main]
    for k in range(n_shoot):
        i = max(1, min(len(main) - 2, int(len(main) * (0.2 + 0.6 * k / max(1, n_shoot - 1)))))
        t = tangent_at(main, i)
        o = rot(perp(t), t, k * 2.0 + rng.uniform(-0.5, 0.5))
        d = nrm(rot(t, np.cross(t, o), rng.uniform(0.7, 1.2)))
        if layered:
            d = nrm(d * V(1, 0.45, 1))
        sh = grow(main[i], d, rng.uniform(16, 26), 6, rng, bend_amt=rng.uniform(-0.5, 0.5))
        card.twig(sh, 0.3, 0.12, tw)
        shoots.append(sh)
    items = []
    for sh in shoots:
        scol = pick()
        for i in range(1, len(sh)):
            if rng.random() > sparse:
                continue
            t = tangent_at(sh, i)
            fr = i / (len(sh) - 1)
            for sg in (-1, 1):
                o = rot(perp(t), t, (i % 2) * math.pi / 2 + (0 if sg > 0 else math.pi))
                pd = nrm(rot(t, np.cross(t, o), rng.uniform(0.7, 1.3)))
                b = sh[i] + pd * rng.uniform(2.5, 4.0)
                card.twig([sh[i], b], 0.06, 0.05, mix(tw, (170, 70, 60), 0.4))
                a = nrm(pd + V(0, 0.4, 0))
                want = nrm(V(rng.gauss(0, 0.45), 1.0, rng.gauss(0.5, 0.45)))   # 葉面朝上偏前
                nvec = nrm(want - a * float(np.dot(want, a)))
                c = pick() if rng.random() < shoot_shift else scol
                if len(palette) > 2:
                    c = mix(c, palette[0][0], 0.25 * (1 - fr))
                items.append((b, a, nvec, rng.uniform(*R), jit(c, rng, 0.07, 0.04, 0.015),
                              7 if rng.random() < 0.8 else 5))
    rng.shuffle(items)
    for b, a, nvec, r, c, lob in items:
        palm_leaf(card, b, a, nvec, r, c, mix(c, (190, 180, 150), 0.3), rng, lob, rng.uniform(0.42, 0.52))


def sp_fern(card, rng, base, tip, arch=1.0, twist=0.0, L=(60, 75)):
    """蕨（羽狀複葉）：拱形葉軸、羽片互生、羽片羽狀淺裂（連續葉身，不是點列），輪廓披針、尖端漸小。"""
    Lr = rng.uniform(*L)
    d0 = nrm(V(rng.uniform(-0.2, 0.2), 1.0, 0.3 + arch * 0.2))
    rach = grow(V(0, 0, 0), d0, Lr, 26, rng, bend=V(1, 0, 0), bend_amt=1.2 * arch, jit_amt=0.01)
    card.twig(rach, 0.35, 0.08, mul(base, 0.75))
    plane_n = nrm(V(rng.uniform(-0.2, 0.2), 0.6, 1.0))
    items = []
    for i in range(3, len(rach) - 1):
        t = tangent_at(rach, i)
        fr = i / (len(rach) - 1)
        prof = math.sin(math.pi * min(1.0, max(0.0, fr - 0.08) / 0.92) ** 0.75) * (0.55 + 0.45 * (1 - fr))
        if prof <= 0.02:
            continue
        pn = nrm(rot(plane_n, t, twist * fr))
        for sg in (-1, 1):
            side = nrm(np.cross(t, pn)) * sg
            a = nrm(side * 1.0 + t * (0.35 + 0.3 * fr))
            Lp = Lr * 0.24 * prof * rng.uniform(0.9, 1.1)
            n = nrm(pn - a * float(np.dot(pn, a)))
            c = jit(mix(base, tip, fr * 0.7), rng, 0.06, 0.03)
            items.append((rach[i] + side * 0.3 + t * (0.5 if sg > 0 else 0.0), a, n, Lp, c))
    for b, a, n, Lp, c in items:
        leaf(card, b, a, n, Lp, Lp * 0.24, 'lance', c, mix(c, (120, 140, 90), 0.4), rng, fold=0.08, droop=0.12,
             rib=True, lobes_pinna=max(3, int(Lp / 1.1)), rib_col=mul(c, 0.8))


def sp_sasa(card, rng, base, tip, n_culm=3):
    """笹（隈笹）：細稈有節，上部節出短枝，枝端 4–7 片寬披針葉展開、葉尖下垂；少數葉緣枯白。"""
    for k in range(n_culm):
        d = nrm(V(rng.uniform(-0.3, 0.3), 1, rng.uniform(-0.3, 0.3)))
        culm = grow(V((k - (n_culm - 1) / 2) * 6, 0, rng.uniform(-4, 4)), d, rng.uniform(35, 55), 8, rng,
                    bend_amt=rng.uniform(-0.3, 0.3))
        card.twig(culm, 0.35, 0.28, hx('#7A8248'))
        for i in (len(culm) - 4, len(culm) - 2, len(culm) - 1):
            p = culm[i]
            card.poly([p + V(-0.45, -0.1, 0.1), p + V(0.45, -0.1, 0.1), p + V(0.45, 0.15, 0.1),
                       p + V(-0.45, 0.15, 0.1)], hx('#5E6A3A'), VIEW)
            t = tangent_at(culm, i)
            nl = rng.randint(4, 7)
            az0 = rng.uniform(0, 6.28)
            for j in range(nl):
                o = rot(perp(t), t, az0 + j * 2 * math.pi / nl + rng.uniform(-0.3, 0.3))
                a = nrm(rot(t, np.cross(t, o), rng.uniform(0.9, 1.6)))
                nvec = nrm(LIGHT + V(rng.gauss(0, 0.4), rng.gauss(0, 0.3), rng.gauss(0, 0.4)))
                nvec = nrm(nvec - a * float(np.dot(nvec, a)))
                Lf = rng.uniform(16, 24)
                c = jit(mix(base, tip, rng.random()), rng, 0.07, 0.04)
                leaf(card, p + a * 1.5, a, nvec, Lf, Lf * 0.22, 'lance', c, mix(c, (150, 160, 120), 0.4), rng,
                     fold=0.12, droop=0.3, rib=True)
                if rng.random() < 0.3:   # 枯白葉緣
                    left, right = outline(Lf, Lf * 0.22, 'lance')
                    side = nrm(np.cross(a, nvec))
                    sel = left if rng.random() < 0.5 else right
                    seg = sel[len(sel) // 3:]
                    pts = [p + a * 1.5 + a * y + side * x * 1.02 + nvec * 0.05 for x, y in seg]
                    pts2 = [p + a * 1.5 + a * y + side * x * 0.86 + nvec * 0.05 for x, y in seg]
                    card.poly(pts + pts2[::-1], hx('#CFC9A0'), nvec)


def sp_shrub(card, rng, base, tip, under, L=(3.5, 5.5), shape='elliptic', rosette=False, n_shoot=14):
    """灌木葉叢（側看團塊，錨點中心）：枝骨從下方放射成半球，葉互生（rosette＝杜鵑：枝端 5–8 片輪生）。"""
    tw = hx('#4E4030')
    for k in range(n_shoot):
        a = rng.uniform(0, 2 * math.pi)
        el = rng.uniform(0.2, 1.3)
        d = nrm(V(math.cos(a) * math.cos(el), math.sin(el), math.sin(a) * math.cos(el)))
        sh = grow(V(0, -16, 0), d, rng.uniform(18, 26), 6, rng, bend_amt=rng.uniform(-0.5, 0.5))
        card.twig(sh, 0.35, 0.15, tw)
        idx = range(len(sh) - 2, len(sh)) if rosette else range(2, len(sh))
        for i in idx:
            t = tangent_at(sh, i)
            reps = rng.randint(5, 8) if (rosette and i == len(sh) - 1) else (2 if rosette else 1)
            for r in range(reps):
                a_, n_ = leaf_frame(t, rng, 0.5, ang=(0.6, 1.3), phy_az=i * 2.4 + r * (6.28 / max(1, reps)))
                Lf = rng.uniform(*L)
                c = jit(mix(base, tip, rng.random() ** 1.5), rng, 0.08, 0.04)
                leaf(card, sh[i] + a_ * 0.3, a_, n_, Lf, Lf * 0.45, shape, c, mix(c, under, 0.7), rng, fold=0.2,
                     droop=0.1)


def sp_twigs(card, rng, col, depth=4):
    """枯枝：遞迴分枝、粗細遞減、枝端偶爾斷折、少數芽。"""
    def br(p, d, L, r, k):
        pts = grow(p, d, L, 5, rng, bend_amt=rng.uniform(-0.6, 0.6), jit_amt=0.06)
        card.twig(pts, r, r * 0.6, jit(col, rng, 0.06, 0.04))
        if k < depth and not (k >= 2 and rng.random() < 0.15):
            for i in (2, 3, 5):
                if rng.random() < 0.75:
                    t = tangent_at(pts, i)
                    o = rot(perp(t), t, rng.uniform(0, 6.28))
                    dd = nrm(rot(t, np.cross(t, o), rng.uniform(0.35, 0.85)))
                    br(pts[min(i, len(pts) - 1)], dd, L * rng.uniform(0.45, 0.62), r * 0.62, k + 1)
        elif rng.random() < 0.3:
            card.poly([pts[-1] + V(0.15, 0, 0), pts[-1] + V(0, 0.5, 0), pts[-1] + V(-0.15, 0, 0)], hx('#7A5A40'), VIEW)
    for k in range(2):
        br(V(rng.uniform(-2, 2), 0, 0), nrm(V(rng.uniform(-0.4, 0.4), 1, rng.uniform(-0.3, 0.3))), 26, 0.9, 0)


def sp_moss(card, rng, base, tip):
    """苔（俯視）：數個隆起墊狀團塊，團內細短莖葉，團間暗縫，邊緣漸疏。"""
    for k in range(rng.randint(6, 9)):
        c0 = V(rng.uniform(-14, 14), rng.uniform(-14, 14), 0)
        R = rng.uniform(5, 9)
        N = 22
        ring = []
        for i in range(N):
            a = i / N * 2 * math.pi
            rr = R * (0.85 + 0.15 * math.sin(a * 3 + k) + rng.uniform(-0.08, 0.08))
            ring.append(c0 + V(math.cos(a) * rr, math.sin(a) * rr, 0))
        card.poly(ring, jit(mul(base, 0.8), rng, 0.05, 0.03), VIEW)
        for j in range(int(R * R * 2.2)):
            u = rng.random()
            r = R * math.sqrt(u) * 0.95
            a = rng.uniform(0, 2 * math.pi)
            p = c0 + V(math.cos(a) * r, math.sin(a) * r, (1 - u) * R * 0.5)
            d = nrm(V(rng.gauss(0, 1), rng.gauss(0, 1), 0))
            c = jit(mix(base, tip, (1 - u) ** 1.2), rng, 0.08, 0.04)
            needle(card, p, d, rng.uniform(0.6, 1.2), 0.45, c, curve=0.3)


# ───────────────────────── atlas 版面 ─────────────────────────
def layout_a():
    return {
        'sugi_a':     (0, 0, 512, 512, 'base', lambda c, r: sp_sugi(c, r, hx('#2E4A2E'), hx('#557040'), 3, 0.0, 0.0, old=0.2)),
        'sugi_b':     (512, 0, 1024, 512, 'base', lambda c, r: sp_sugi(c, r, hx('#2B452C'), hx('#4C6838'), 3, 1.2, 0.0, old=0.3)),
        'sugi_dead':  (1024, 0, 1536, 512, 'base', lambda c, r: sp_sugi(c, r, hx('#38482E'), hx('#5C6A3C'), 3, 0.6, 0.67, old=0.5)),
        'hinoki_a':   (1536, 0, 2048, 512, 'base', lambda c, r: sp_hinoki(c, r, hx('#2F5232'), hx('#5E8248'), 7, 0.0, True)),
        'hinoki_b':   (0, 512, 512, 1024, 'base', lambda c, r: sp_hinoki(c, r, hx('#2C4A2E'), hx('#557444'), 6, 0.08, True)),
        'akamatsu':   (512, 512, 1024, 1024, 'base', lambda c, r: sp_pine(c, r, hx('#46643A'), hx('#7E9458'), (8, 12), 0.35, 5, True)),
        'kuromatsu':  (1024, 512, 1536, 1024, 'base', lambda c, r: sp_pine(c, r, hx('#263E2A'), hx('#46603A'), (10, 15), 0.85, 5, False)),
        'matsu_pad':  (1536, 512, 2048, 1024, 'center', lambda c, r: sp_pine_pad(c, r, hx('#283E2C'), hx('#5A7442'), 3)),
        'willow_a':   (0, 1024, 256, 1536, 'top', lambda c, r: sp_willow(c, r, hx('#7E9850'), 2, (90, 110), 0.8)),
        'willow_b':   (256, 1024, 512, 1536, 'top', lambda c, r: sp_willow(c, r, hx('#6C8A48'), 3, (60, 100), 0.4, 0.6)),
        'sasa':       (512, 1024, 1024, 1536, 'base', lambda c, r: sp_sasa(c, r, hx('#3A5A30'), hx('#62803E'))),
        'twigs':      (1024, 1024, 1536, 1536, 'base', lambda c, r: sp_twigs(c, r, hx('#6A625A'))),
        'azalea':     (1536, 1024, 2048, 1536, 'center', lambda c, r: sp_shrub(c, r, hx('#2C4A2C'), hx('#4E6E3A'), hx('#8A9A70'), (2.2, 3.4), 'elliptic', True, 18)),
        'fern_a':     (0, 1536, 256, 2048, 'base', lambda c, r: sp_fern(c, r, hx('#3A6030'), hx('#6A8C44'), 0.6, 0.0)),
        'fern_b':     (256, 1536, 512, 2048, 'base', lambda c, r: sp_fern(c, r, hx('#33562E'), hx('#5A7A3C'), 1.4, 0.9, (50, 62))),
        'shrub':      (512, 1536, 1024, 2048, 'center', lambda c, r: sp_shrub(c, r, hx('#365630'), hx('#668646'), hx('#8E9C78'), (3.8, 5.6), 'ovate', False, 12)),
        'sugi_young': (1024, 1536, 1536, 2048, 'base', lambda c, r: sp_sugi(c, r, hx('#3C5C32'), hx('#6E8C4A'), 2, -0.3, 0.0, True)),
        'moss':       (1536, 1536, 2048, 2048, 'center', lambda c, r: sp_moss(c, r, hx('#3C5A2A'), hx('#7C8E48'))),
    }


def layout_b():
    U = hx('#9AA880')        # 一般葉背：灰綠
    return {
        'konara':      (0, 0, 512, 512, 'base', lambda c, r: sp_broad(c, r, hx('#3E5C30'), hx('#6C8C44'), U, (9, 13), 0.44, 'obovate', 0.11, 11, 0.2, 0.0, 5, 'alt', 0.55, 0.0, 1.0, None, False, 0.0, None, (18, 28))),
        'shii':        (512, 0, 1024, 512, 'base', lambda c, r: sp_broad(c, r, hx('#2A4428'), hx('#466438'), hx('#A88A58'), (6, 9), 0.36, 'elliptic', 0, 0, 0.12, 0.0, 5, 'alt', 0.0, 0.0, 1.0)),
        'keyaki':      (1024, 0, 1536, 512, 'base', lambda c, r: sp_broad(c, r, hx('#46663A'), hx('#7C9A50'), U, (4, 6.5), 0.36, 'acuminate', 0.16, 13, 0.1, 0.15, 5, 'dist', 0.0, 0.8, 0.95)),
        'kusu_a':      (1536, 0, 2048, 512, 'base', lambda c, r: sp_broad(c, r, hx('#2E4C2C'), hx('#55743C'), U, (6, 9), 0.5, 'ovate', 0, 0, 0.12, 0.0, 4, 'alt', 0.0, 0.0, 1.0, None, True, 0.04)),
        'kusu_b':      (0, 512, 512, 1024, 'base', lambda c, r: sp_broad(c, r, hx('#38582E'), hx('#6E8C44'), U, (6, 9), 0.5, 'ovate', 0, 0, 0.12, 0.0, 4, 'alt', 0.0, 0.0, 1.0, (hx('#A8AE62'), 0.35), True, 0.04)),
        'enoki':       (512, 512, 1024, 1024, 'base', lambda c, r: sp_broad(c, r, hx('#42623A'), hx('#6E8C48'), U, (5.5, 8), 0.55, 'ovate', 0.14, 9, 0.5, 0.35, 4, 'dist', 0.0, 0.4, 0.9, None, True)),
        'sakura_bloom': (1024, 512, 1536, 1024, 'base', lambda c, r: sp_sakura(c, r, hx('#F2DCDF'), None, 0.0, 0.85)),
        'sakura_yama': (1536, 512, 2048, 1024, 'base', lambda c, r: sp_sakura(c, r, hx('#F3E9E6'), hx('#8E5E42'), 0.55, 0.7)),
        'sakura_leaf': (0, 1024, 512, 1536, 'base', lambda c, r: sp_broad(c, r, hx('#3C5A32'), hx('#62803C'), U, (7, 10), 0.46, 'acuminate', 0.12, 16, 0.1, 0.0, 4, 'alt', 0.0, 0.0, 0.9, None, False, 0.0, BARK_TW['sakura'])),
        'momiji_g':    (512, 1024, 1024, 1536, 'base', lambda c, r: sp_maple(c, r, [(hx('#5A863A'), 3), (hx('#76983F'), 1)])),
        'momiji_turn': (1024, 1024, 1536, 1536, 'base', lambda c, r: sp_maple(c, r, [(hx('#6E8A3C'), 2), (hx('#B08A3A'), 1.5), (hx('#B0602E'), 1.2), (hx('#93402C'), 0.6)], shoot_shift=0.15)),
        'momiji_red':  (1536, 1024, 2048, 1536, 'base', lambda c, r: sp_maple(c, r, [(hx('#953A2A'), 3), (hx('#AE562E'), 2), (hx('#7A3428'), 1), (hx('#A87A36'), 0.4)], shoot_shift=0.25)),
        'shidare_a':   (0, 1536, 256, 2048, 'top', lambda c, r: sp_weeping(c, r, hx('#F0D6DA'), 2, (90, 110))),
        'shidare_b':   (256, 1536, 512, 2048, 'top', lambda c, r: sp_weeping(c, r, hx('#EDD0D5'), 3, (60, 95))),
        'young_broad': (512, 1536, 1024, 2048, 'base', lambda c, r: sp_broad(c, r, hx('#58803E'), hx('#8EAA58'), U, (5, 7.5), 0.5, 'elliptic', 0.1, 12, 0.12, 0.0, 3, 'alt', 0.0, 0.0, 0.85, None, False, 0.0, None, (16, 24))),
        'broad_yellow': (1024, 1536, 1536, 2048, 'base', lambda c, r: sp_broad(c, r, hx('#5C7238'), hx('#94984C'), U, (7, 10.5), 0.48, 'obovate', 0.18, 9, 0.2, 0.0, 4, 'alt', 0.35, 0.0, 0.7, (hx('#B09A48'), 0.25))),
        'momiji_g2':   (1536, 1536, 2048, 2048, 'base', lambda c, r: sp_maple(c, r, [(hx('#4C7836'), 3), (hx('#6A8E42'), 1.5)], (2.4, 3.4), 5, 0.75)),
    }


def alpha_bbox(al, thr=24, pad=3):
    """格內 alpha 的緊包框（格內像素座標 x0, y0, x1, y1；含 pad）。卡片幾何只用這一塊 → 少畫透明像素（overdraw）。"""
    ys, xs = np.nonzero(al > thr)
    if len(xs) == 0:
        return [0, 0, al.shape[1], al.shape[0]]
    return [max(0, int(xs.min()) - pad), max(0, int(ys.min()) - pad),
            min(al.shape[1], int(xs.max()) + 1 + pad), min(al.shape[0], int(ys.max()) + 1 + pad)]


def add_bbox(regions, alpha):
    for name, r in regions.items():
        x0, y0, x1, y1 = r['px']
        bx0, by0, bx1, by1 = alpha_bbox(alpha[y0:y1, x0:x1])
        r['bbox_px'] = [x0 + bx0, y0 + by0, x0 + bx1, y0 + by1]
        r['bbox_uv'] = [(x0 + bx0) / ATLAS, (y0 + by0) / ATLAS, (x0 + bx1) / ATLAS, (y0 + by1) / ATLAS]


def build_atlas(key, lay, seed, only_cell=''):
    rgb = np.zeros((ATLAS, ATLAS, 3), np.uint8)
    nor = np.zeros((ATLAS, ATLAS, 3), np.uint8)
    nor[...] = (128, 128, 255)
    a = np.zeros((ATLAS, ATLAS), np.uint8)
    regions = {}
    for i, (name, (x0, y0, x1, y1, anchor, fn)) in enumerate(lay.items()):
        if only_cell and name != only_cell:
            continue
        rng = random.Random(seed * 1000 + i)
        card = Card(x1 - x0, y1 - y0, anchor)
        fn(card, rng)
        c, nm, al, mean = card.render()
        rgb[y0:y1, x0:x1] = c
        nor[y0:y1, x0:x1] = nm
        a[y0:y1, x0:x1] = al
        cov = float((al > 127).mean())
        regions[name] = {'px': [x0, y0, x1, y1], 'uv': [x0 / ATLAS, y0 / ATLAS, x1 / ATLAS, y1 / ATLAS],
                         'anchor': anchor, 'aspect': round((y1 - y0) / (x1 - x0), 4),
                         'mean_srgb': T.rgbhex(mean / 255.0), 'coverage': round(cov, 3),
                         'prims': len(card.prims), 'cm_per_px': round(1.0 / card.scale, 4),
                         'anchor_uv': [(x0 + card.anchor_px[0]) / ATLAS, (y0 + card.anchor_px[1]) / ATLAS]}
        print(f'  {key}.{name}: 覆蓋 {cov:.2f} 平均 {T.rgbhex(mean / 255.0)} 面 {len(card.prims)} '
              f'{1.0 / card.scale:.3f} cm/px', flush=True)
    add_bbox(regions, a)
    img = Image.fromarray(np.dstack([rgb, a]), 'RGBA')
    if only_cell:
        img.save(f'{OUT}/_cell_{only_cell}.png')
        return {'regions': regions}
    fa, fn_ = f'VL_{key}_albedo.png', f'VL_{key}_normal.png'
    img.save(f'{OUT}/{fa}', optimize=True)
    Image.fromarray(nor, 'RGB').save(f'{OUT}/{fn_}', optimize=True)
    T.write_import(f'{RES}/{fa}', False)
    T.write_import(f'{RES}/{fn_}', True)
    return {'file': f'{RES}/{fa}', 'normal': f'{RES}/{fn_}', 'size': ATLAS, 'regions': regions}


def splice_cells(names):
    """只重畫指定格，貼回現有 atlas（其他格逐位元不變；整張重建會讓已核准樹種的葉貼圖跟著漂移）。"""
    mp = f'{OUT}/veg_tex.json'
    with open(mp, encoding='utf-8') as f:
        meta = json.load(f)
    for key, lay, seed in (('A', layout_a(), 11), ('B', layout_b(), 23)):
        todo = [n for n in names if n in lay]
        if not todo:
            continue
        fa, fn_ = f'{OUT}/VL_{key}_albedo.png', f'{OUT}/VL_{key}_normal.png'
        img = np.array(Image.open(fa).convert('RGBA'))
        nor = np.array(Image.open(fn_).convert('RGB'))
        regions = meta['atlas'][key]['regions']
        for i, (name, (x0, y0, x1, y1, anchor, fn)) in enumerate(lay.items()):
            if name not in todo:
                continue
            rng = random.Random(seed * 1000 + i)
            card = Card(x1 - x0, y1 - y0, anchor)
            fn(card, rng)
            c, nm, al, mean = card.render()
            img[y0:y1, x0:x1, :3] = c
            img[y0:y1, x0:x1, 3] = al
            nor[y0:y1, x0:x1] = nm
            cov = float((al > 127).mean())
            regions[name].update({'mean_srgb': T.rgbhex(mean / 255.0), 'coverage': round(cov, 3),
                                  'prims': len(card.prims), 'cm_per_px': round(1.0 / card.scale, 4),
                                  'anchor_uv': [(x0 + card.anchor_px[0]) / ATLAS, (y0 + card.anchor_px[1]) / ATLAS]})
            add_bbox({name: regions[name]}, img[..., 3])
            print(f'  splice {key}.{name}: 覆蓋 {cov:.2f} 面 {len(card.prims)} {1.0 / card.scale:.3f} cm/px', flush=True)
        Image.fromarray(img, 'RGBA').save(fa, optimize=True)
        Image.fromarray(nor, 'RGB').save(fn_, optimize=True)
    meta['files_sha256'] = {rp: T.sha256(T.G + '/' + rp[len('res://'):]) for rp in meta['files_sha256']}
    with open(mp, 'w', encoding='utf-8', newline='\n') as f:
        json.dump(meta, f, ensure_ascii=False, indent=1)
        f.write('\n')
    print('splice 寫入', mp)


def main():
    os.makedirs(OUT, exist_ok=True)
    only, cell = '', ''
    for x in sys.argv[1:]:
        if x.startswith('--only='):
            only = x[7:]
        if x.startswith('--cell='):
            cell = x[7:]
    splice = [x[9:] for x in sys.argv[1:] if x.startswith('--splice=')]
    if splice:
        splice_cells(splice[0].split(','))
        return
    if cell:
        for key, lay, seed in (('A', layout_a(), 11), ('B', layout_b(), 23)):
            if cell in lay:
                build_atlas(key, lay, seed, cell)
        return
    mp = f'{OUT}/veg_tex.json'
    meta = {}
    if os.path.exists(mp):
        with open(mp, encoding='utf-8') as f:
            meta = json.load(f)
    if only == 'meta':   # 只由現有 atlas PNG 重算 bbox（不重畫）
        for key, at in meta['atlas'].items():
            al = np.asarray(Image.open(f'{OUT}/VL_{key}_albedo.png'))[..., 3]
            add_bbox(at['regions'], al)
    meta['_note'] = ('P9 R1 植被庫貼圖。由 tools/build_village_v2_veg_textures.py 產生，勿手改。'
                     '樹皮＝Poly Haven CC0 校色；葉叢 atlas＝偽 3D 程序繪製（無外部來源）。')
    if only in ('', 'bark'):
        meta['bark'] = build_bark()
    if only == 'meta':
        pass
    if only in ('', 'leaf'):
        meta['atlas'] = {'A': build_atlas('A', layout_a(), 11), 'B': build_atlas('B', layout_b(), 23)}
    files = []
    for b in meta.get('bark', {}).values():
        files += list(b['files'].values())
    for a in meta.get('atlas', {}).values():
        files += [a['file'], a['normal']]
    meta['files_sha256'] = {rp: T.sha256(T.G + '/' + rp[len('res://'):]) for rp in files}
    with open(mp, 'w', encoding='utf-8', newline='\n') as f:
        json.dump(meta, f, ensure_ascii=False, indent=1)
        f.write('\n')
    print('寫入', mp)


if __name__ == '__main__':
    main()

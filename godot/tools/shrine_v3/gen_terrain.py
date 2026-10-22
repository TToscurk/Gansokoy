"""博麗神社 v3 地形生成：近／中／遠三層高度場＋遮罩＋預覽＋反盆地地平量測。
  cd godot && python tools/shrine_v3/gen_terrain.py [--no-preview]
輸出（maps/shrine_v3/gen/）：
  h_near.f32 / h_mid.f32 / h_far.f32   float32 row-major（z 列、x 行）
  mask_a.rgba / mask_b.rgba            地表混合遮罩（A：夯土、林床、岩、草；B：獸道、濕暗、落花、苔），0.375 m/texel
  layout.json                           Godot 端單一來源（網格規格、配置、石階、獸道、池塘…）
  horizon.json                          每個量測點 360° 地平仰角（近 150 m／全距離）
  _preview_*.png                        預覽（不進遊戲）
"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import layout as L  # noqa: E402
import terrain_lib as T  # noqa: E402

GODOT = os.path.abspath(os.path.join(HERE, '..', '..'))
OUT = os.path.join(GODOT, 'maps', 'shrine_v3', 'gen')
os.makedirs(OUT, exist_ok=True)
FONT = 'C:/Windows/Fonts/msjh.ttc'
# 預覽圖不放進 Godot 專案（避免被匯入）；放 Hermes scratch
PREV = os.path.join(os.environ.get('LOCALAPPDATA', '.'), 'hermes', 'cache', 'scratch', 'shrine_v3', 'prev')
os.makedirs(PREV, exist_ok=True)


def build_grids():
    Xn, Zn, Hn, Hn_reg, masks = T.near_height_grid()
    # 近景邊界：中景格點（每 6 m）之間的近景頂點改成兩端線性內插 → 與中景網格無 T 形裂縫
    r = int(round(L.MID['step'] / L.NEAR['step']))
    for side in ('top', 'bot', 'left', 'right'):
        if side in ('top', 'bot'):
            row = 0 if side == 'top' else Hn.shape[0] - 1
            v = Hn[row, :]
            idx = np.arange(v.size)
            anchors = idx[::r]
            Hn[row, :] = np.interp(idx, anchors, v[anchors])
        else:
            col = 0 if side == 'left' else Hn.shape[1] - 1
            v = Hn[:, col]
            idx = np.arange(v.size)
            anchors = idx[::r]
            Hn[:, col] = np.interp(idx, anchors, v[anchors])
    Xm, Zm = T.grid(L.MID)
    Hm = T.regional(Xm, Zm)
    # 中景邊界同理對齊遠景格點
    r2 = int(round(L.FAR['step'] / L.MID['step']))
    for axis in (0, 1):
        for end in (0, -1):
            if axis == 0:
                v = Hm[end, :]
            else:
                v = Hm[:, end]
            idx = np.arange(v.size)
            a = idx[::r2]
            vv = np.interp(idx, a, v[a])
            if axis == 0:
                Hm[end, :] = vv
            else:
                Hm[:, end] = vv
    Xf, Zf = T.grid(L.FAR)
    Hf = T.regional(Xf, Zf)
    return (Xn, Zn, Hn, Hn_reg, masks), (Xm, Zm, Hm), (Xf, Zf, Hf)


# ───────────────────────── 取樣（三層） ─────────────────────────
class Sampler:
    def __init__(self, near, mid, far):
        self.layers = []
        for spec, H in ((L.NEAR, near), (L.MID, mid), (L.FAR, far)):
            self.layers.append((spec, H))

    def h(self, x, z):
        x = np.asarray(x, dtype=np.float64)
        z = np.asarray(z, dtype=np.float64)
        out = np.full(x.shape, np.nan)
        for spec, H in self.layers:
            inside = (x >= spec['x0']) & (x <= spec['x1']) & (z >= spec['z0']) & (z <= spec['z1']) & np.isnan(out)
            if not inside.any():
                continue
            fx = (x[inside] - spec['x0']) / spec['step']
            fz = (z[inside] - spec['z0']) / spec['step']
            i = np.clip(np.floor(fx).astype(int), 0, H.shape[1] - 2)
            j = np.clip(np.floor(fz).astype(int), 0, H.shape[0] - 2)
            u = np.clip(fx - i, 0, 1)
            v = np.clip(fz - j, 0, 1)
            a = H[j, i] * (1 - u) + H[j, i + 1] * u
            b = H[j + 1, i] * (1 - u) + H[j + 1, i + 1] * u
            out[inside] = a * (1 - v) + b * v
        return out


def horizon(sampler, x0, z0, eye_y, n_az=180, near_r=150.0):
    """每個方位（0°＝北，順時針；北＝−z、東＝+x）回傳 (近 150 m 最大仰角, 全距離最大仰角, 該處距離)。"""
    az = np.arange(n_az) * (360.0 / n_az)
    d = np.concatenate([np.arange(1.0, 40.0, 0.5), np.geomspace(40.0, 8500.0, 520)])
    A = np.radians(az)[:, None]
    X = x0 + np.sin(A) * d[None, :]
    Z = z0 - np.cos(A) * d[None, :]
    H = sampler.h(X, Z)
    ang = np.degrees(np.arctan2(H - eye_y, d[None, :]))
    near = d[None, :] <= near_r
    an = np.where(near, ang, -90.0).max(1)
    af = np.nanmax(ang, 1)
    di = d[np.nanargmax(ang, 1)]
    return az, an, af, di


# ───────────────────────── 預覽 ─────────────────────────
def hillshade(H, step):
    gz, gx = np.gradient(H, step)
    lx, ly, lz = -0.55, 0.75, -0.35
    n = np.stack([-gx, np.ones_like(H), -gz], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    s = np.clip(n[..., 0] * lx + n[..., 1] * ly + n[..., 2] * lz, 0, 1)
    return s, np.degrees(np.arccos(np.clip(n[..., 1], -1, 1)))


def colorize(H, lo, hi):
    t = np.clip((H - lo) / (hi - lo), 0, 1)
    stops = np.array([[0.20, 0.32, 0.45], [0.30, 0.50, 0.30], [0.62, 0.66, 0.40], [0.72, 0.60, 0.45], [0.92, 0.90, 0.88]])
    pos = np.linspace(0, 1, len(stops))
    c = np.stack([np.interp(t, pos, stops[:, k]) for k in range(3)], -1)
    return c


def to_px(spec, W, Hh, x, z):
    return ((x - spec['x0']) / (spec['x1'] - spec['x0']) * W, (z - spec['z0']) / (spec['z1'] - spec['z0']) * Hh)


def preview_near(Hn, masks, path):
    sp = L.NEAR
    shade, slope = hillshade(Hn, sp['step'])
    col = colorize(Hn, -10.0, 55.0) * (0.45 + 0.75 * shade[..., None])
    img = (np.clip(col, 0, 1) * 255).astype(np.uint8)
    # 等高線：1 m 細、5 m 粗
    for iv, w in ((1.0, 40), (5.0, 110)):
        q = np.floor(Hn / iv)
        e = (np.abs(np.diff(q, axis=0, prepend=q[:1])) + np.abs(np.diff(q, axis=1, prepend=q[:, :1]))) > 0
        img[e] = (img[e] * (1 - w / 255.0)).astype(np.uint8)
    im = Image.fromarray(img).resize((img.shape[1] * 4, img.shape[0] * 4), Image.NEAREST)
    W, Hh = im.size
    dr = ImageDraw.Draw(im)
    f = ImageFont.truetype(FONT, 22)

    def poly(pts, color, width=3, close=True):
        q = [to_px(sp, W, Hh, x, z) for x, z in pts]
        if close:
            q = q + [q[0]]
        dr.line(q, fill=color, width=width)

    poly(L.PLATFORM, (255, 240, 120), 3)
    poly(L.PLAY, (255, 60, 60), 2)
    poly([(p[0], p[1]) for p in T.beast_profile()], (230, 150, 60), 5, close=False)
    poly(L.FENCE_W, (120, 70, 30), 5, close=False)
    for k in ('grove', 'pond_w'):
        poly(L.PATHS[k], (200, 170, 120), 3, close=False)
    st = L.STAIR
    poly([(-st['width'] / 2, st['z_top']), (st['width'] / 2, st['z_top']), (st['width'] / 2, L.Z_FOOT), (-st['width'] / 2, L.Z_FOOT)], (240, 240, 240), 3)
    for name, (x, z, _) in L.PLACE.items():
        px, pz = to_px(sp, W, Hh, x, z)
        dr.ellipse([px - 6, pz - 6, px + 6, pz + 6], fill=(255, 255, 255))
        dr.text((px + 8, pz - 10), name, fill=(255, 255, 255), font=f)
    for name, (x, z) in L.VIEWPOINTS.items():
        px, pz = to_px(sp, W, Hh, x, z)
        dr.rectangle([px - 7, pz - 7, px + 7, pz + 7], outline=(0, 255, 255), width=3)
    im.save(path)


def preview_mid(Hm, path, spec, lo, hi):
    shade, _ = hillshade(Hm, spec['step'])
    col = colorize(Hm, lo, hi) * (0.45 + 0.75 * shade[..., None])
    img = (np.clip(col, 0, 1) * 255).astype(np.uint8)
    q = np.floor(Hm / 25.0)
    e = (np.abs(np.diff(q, axis=0, prepend=q[:1])) + np.abs(np.diff(q, axis=1, prepend=q[:, :1]))) > 0
    img[e] = (img[e] * 0.6).astype(np.uint8)
    im = Image.fromarray(img)
    dr = ImageDraw.Draw(im)
    W, Hh = im.size
    n = L.NEAR
    a = to_px(spec, W, Hh, n['x0'], n['z0'])
    b = to_px(spec, W, Hh, n['x1'], n['z1'])
    dr.rectangle([a[0], a[1], b[0], b[1]], outline=(255, 50, 50), width=2)
    im.save(path)


def section(sampler, path):
    W, Hh = 1400, 520
    im = Image.new('RGB', (W, Hh), (250, 250, 248))
    dr = ImageDraw.Draw(im)
    f = ImageFont.truetype(FONT, 16)
    rows = [('W–E @ z=−4（左＝西）', lambda t: (t, -4.0), (-400, 300)),
            ('N–S @ x=0（左＝北）', lambda t: (0.0, t), (-300, 400))]
    for k, (lab, fn, (a, b)) in enumerate(rows):
        y0 = 30 + k * 250
        ts = np.linspace(a, b, W - 80)
        xs = np.array([fn(t)[0] for t in ts])
        zs = np.array([fn(t)[1] for t in ts])
        hs = sampler.h(xs, zs)
        lo, hi = -160.0, 120.0
        pts = [(40 + i, y0 + 220 - (h - lo) / (hi - lo) * 220) for i, h in enumerate(hs)]
        dr.line(pts, fill=(60, 90, 60), width=2)
        yP = y0 + 220 - (L.P + L.EYE - lo) / (hi - lo) * 220
        dr.line([(40, yP), (W - 40, yP)], fill=(220, 120, 60), width=1)
        dr.text((44, y0), lab + f'  （橫軸 {a}..{b} m，縱軸 {lo:.0f}..{hi:.0f} m，橘線＝前庭眼高）', fill=(0, 0, 0), font=f)
        for t in range(int(a), int(b) + 1, 50):
            px = 40 + (t - a) / (b - a) * (W - 80)
            dr.line([(px, y0 + 220), (px, y0 + 226)], fill=(0, 0, 0))
            dr.text((px - 10, y0 + 226), str(t), fill=(0, 0, 0), font=f)
    im.save(path)


def horizon_plot(results, path):
    W, Hh = 1440, 140 * len(results) + 40
    im = Image.new('RGB', (W, Hh), (250, 250, 248))
    dr = ImageDraw.Draw(im)
    f = ImageFont.truetype(FONT, 15)
    for k, (name, (az, an, af, di)) in enumerate(results.items()):
        y0 = 20 + k * 140
        lo, hi = -40.0, 40.0

        def Y(a):
            return y0 + 110 - (np.clip(a, lo, hi) - lo) / (hi - lo) * 110
        dr.line([(40, Y(0)), (W - 20, Y(0))], fill=(200, 200, 200))
        dr.line([(40 + i * 7.6, Y(af[i])) for i in range(len(az))], fill=(120, 120, 220), width=2)
        dr.line([(40 + i * 7.6, Y(an[i])) for i in range(len(az))], fill=(200, 60, 40), width=2)
        for a_ in range(0, 361, 45):
            px = 40 + a_ / 2.0 * 7.6
            dr.line([(px, y0 + 110), (px, y0 + 116)], fill=(0, 0, 0))
            dr.text((px - 10, y0 + 116), {0: 'N', 90: 'E', 180: 'S', 270: 'W', 360: 'N'}.get(a_, str(a_)), fill=(0, 0, 0), font=f)
        dr.text((44, y0), f'{name}：紅＝150 m 內地形最大仰角、藍＝全距離（−40°..+40°；灰線 0°）', fill=(0, 0, 0), font=f)
    im.save(path)


MASK_RES = 0.375   # 遮罩貼圖解析度（公尺／texel；近景網格 0.75 m 的 2 倍）


def write_masks(Hn, masks_coarse, petal_fn=None):
    """以 2 倍解析度（texel 中心）重算地表遮罩：mask_a（夯土、林床、岩、草）、mask_b（獸道、濕暗、落花、苔）。
    坡度取自近景網格本身（與畫面上的地形一致）；平台／小徑／池塘等形狀用解析函式重算。"""
    sp = L.NEAR
    W = sp['x1'] - sp['x0']
    D = sp['z1'] - sp['z0']
    nx = int(round(W / MASK_RES))
    nz = int(round(D / MASK_RES))
    xs = sp['x0'] + (np.arange(nx) + 0.5) * (W / nx)
    zs = sp['z0'] + (np.arange(nz) + 0.5) * (D / nz)
    X, Z = np.meshgrid(xs, zs)
    hreg = T.regional(X, Z)
    _, mk = T.near_edits(X, Z, hreg)
    S = Sampler(Hn, Hn, Hn)  # 只用近景層
    S.layers = [(sp, Hn)]
    h = S.h(X, Z)
    Nn = grid_normals(Hn, sp['step'])
    nrm = sample_field(Nn, sp, X, Z)
    slope = np.degrees(np.arccos(np.clip(nrm[..., 1], -1, 1)))
    plat = mk['platform']
    beast = mk['beast']
    stair = mk['stair']
    cliff = mk['cliff']
    water = mk['water']
    # ── 前庭地面：依踩踏量決定（HAKUREI_SHRINE_AREA_SPEC §6、§29；美術深化 2026-10-22）──
    #   高踩踏＝鳥居→拜殿參道兩側與拜殿前台（壓實、草少）；中踩踏＝往手水舍／倉庫／後林徑；低踩踏＝外緣、建築背後（草＋苔多）。
    zlo, zhi = L.SANDO['z1'], L.SANDO['z0']
    hw_c = np.array([L.sando_hw(min(max(float(z), zlo), zhi)) for z in zs])[:, None] * np.ones_like(X)
    dz_out = np.maximum(Z - zhi, 0.0) + np.maximum(zlo - Z, 0.0)
    ds = np.sqrt(np.maximum(np.abs(X) - hw_c, 0.0) ** 2 + dz_out ** 2)     # 到參道鋪石的距離（鋪石內＝0）
    pav = (np.abs(X) <= hw_c) & (dz_out <= 0.0)
    nz1 = T.fbm(X, Z, 7.0, 3, seed=61)
    patch = T.smoothstep(-0.05, 0.35, nz1)
    hi = (1.0 - T.smoothstep(0.3, 2.4, ds)) * plat
    med = np.zeros_like(X)
    for pts_ in (L.PATHS['to_store'], L.PATHS['to_temizuya'], [(-4.6, -18.5), (-6.0, -24.0), (-6.0, -30.5)]):
        d_, _, _ = T.polyline_dist(X, Z, pts_)
        med = np.maximum(med, 1.0 - T.smoothstep(0.4, 1.6, d_))
    traffic = np.maximum(hi, med * 0.75) * plat
    pe = list(L.PLATFORM) + [L.PLATFORM[0]]
    edge_d, _, _ = T.polyline_dist(X, Z, pe)
    edge = (1.0 - T.smoothstep(1.0, 6.5, edge_d)) * plat              # 平台外緣 6.5 m 內＝低踩踏帶
    # 開放地面：夯土為主（中央草侵入 <10%，外緣 25–45%）；踩踏處連續夯土
    dirt = np.clip(plat * (0.92 - 0.5 * edge) * (0.58 + 0.42 * patch), 0, 1)
    dirt = np.maximum(dirt, traffic * (0.86 + 0.14 * patch))
    worn = traffic
    # 建築四周 → 夯土（燈籠／狛犬台座周圍留給苔）
    for key, (px_, pz_, _) in L.PLACE.items():
        r = {'haiden': 6.0, 'torii': 3.0, 'temizuya': 2.6, 'storehouse': 3.0, 'saisen': 2.2}.get(key, 0.0)
        if r <= 0.0:
            continue
        dd = np.sqrt((X - px_) ** 2 + (Z - pz_) ** 2)
        dirt = np.maximum(dirt, (1.0 - T.smoothstep(r * 0.55, r * 1.25, dd)) * plat * 0.9)
    dirt = np.maximum(dirt, 1.0 - T.smoothstep(0.0, 1.0, ds))
    for key in ('grove', 'pond_w', 'to_store', 'to_temizuya'):
        d, _, _ = T.polyline_dist(X, Z, L.PATHS[key])
        dirt = np.maximum(dirt, (1.0 - T.smoothstep(0.35, 1.3, d)) * 0.85)
    dfoot = np.sqrt(X ** 2 + (Z - (L.Z_FOOT + 2.2)) ** 2)
    trail = np.maximum(beast, 1.0 - T.smoothstep(2.5, 4.5, dfoot))
    # 石段兩側帶（石段外 1.9–9 m）：落葉林床＋苔為主（3D 草、蕨、灌木另外種），陡坡也不露成整片岩面
    sb = (1.0 - T.smoothstep(1.9, 9.0, np.abs(X))) * T.smoothstep(9.8, 11.5, Z) * (1.0 - T.smoothstep(47.0, 50.0, Z)) * (1.0 - stair) * (1.0 - plat)
    # 岩：坡度 > 40° 或西崖（石段兩側帶放寬到 > 50°）
    rock = np.maximum(T.smoothstep(38.0, 50.0, slope) * (1.0 - sb * 0.75) + T.smoothstep(50.0, 58.0, slope) * sb * 0.75, cliff)
    rock = rock * (1.0 - stair)
    # 林床：平台外、非岩
    forest = (1.0 - plat) * (1.0 - rock) * (0.6 + 0.4 * T.smoothstep(-0.2, 0.4, T.fbm(X, Z, 11.0, 3, seed=63)))
    forest = np.clip(forest, 0, 1) * (1.0 - stair) * (1.0 - trail * 0.8)
    # 草：平台內非夯土的地方；林床裡的空地
    gn = T.fbm(X, Z, 9.0, 3, seed=65)
    grass = np.clip((1.0 - dirt) * (1.0 - rock) * (plat * 0.95 + (1.0 - plat) * (0.45 - 0.6 * gn)), 0, 1)
    grass = grass * (1.0 - water) * (1.0 - trail * 0.9)
    # 視線走廊（平台南坡 z 10–55、西崖下方）：樹被限高、林床會整片裸露成褐色 → 改成草坡＋苔為主（守社人割草維持的視野坡）
    c_s = T.smoothstep(9.0, 14.0, Z) * (1.0 - T.smoothstep(48.0, 62.0, Z)) * (1.0 - T.smoothstep(36.0, 52.0, np.abs(X)))
    c_w = T.smoothstep(-23.0, -29.0, X) * T.smoothstep(-62.0, -46.0, Z) * (1.0 - T.smoothstep(22.0, 38.0, Z))
    corr = np.maximum(c_s, c_w) * (1.0 - plat)
    gnz = T.fbm(X, Z, 5.0, 3, seed=71)
    grass = np.maximum(grass, corr * (1.0 - rock * 0.85) * (1.0 - trail * 0.9) * (1.0 - stair) * (0.55 + 0.35 * T.smoothstep(-0.3, 0.3, gnz)))
    forest = forest * (1.0 - corr * 0.7)
    # 石段兩側帶：落葉林床＋少量草紋理
    forest = np.maximum(forest, sb * (0.55 + 0.3 * T.smoothstep(-0.3, 0.3, T.fbm(X, Z, 4.0, 3, seed=75))) * (1.0 - rock))
    grass = grass * (1.0 - sb * 0.45)
    # 池塘棚地：草為主
    pc = L.POND
    dp = np.sqrt((X - pc['cx']) ** 2 + (Z - pc['cz']) ** 2)
    shelf = 1.0 - T.smoothstep(pc['shelf_r'] - 2.0, pc['shelf_r'] + 2.0, dp)
    grass = np.maximum(grass, shelf * (1.0 - water) * (1.0 - rock) * 0.9)
    forest = forest * (1.0 - shelf * 0.8)
    # 細碎石（mask_b.r 在平台上＝礫石紋理）：參道鋪石外緣 0–0.55 m 的碎石帶、建築滴水線、手水舍石台前、零星碎石斑
    grav = (1.0 - T.smoothstep(0.05, 0.6, ds)) * (ds > 0.0) * 0.8
    for (cx_, cz_, hx_, hz_) in ((0.0, -23.0 + 0.12, 4.35, 3.45), (15.2, -17.4, 2.1, 2.2), (-8.6, 0.6, 1.62, 1.8)):
        rd = np.maximum(np.abs(X - cx_) - hx_, np.abs(Z - cz_) - hz_)          # 屋簷外緣（矩形）有號距離
        grav = np.maximum(grav, (1.0 - T.smoothstep(0.0, 0.45, np.abs(rd + 0.1))) * 0.6)
    tp = L.TEMIZUYA_PAD
    dtp = np.maximum(np.maximum(tp[0] - X, X - tp[1]), np.maximum(tp[2] - Z, Z - tp[3]))
    grav = np.maximum(grav, (1.0 - T.smoothstep(0.0, 0.5, np.abs(dtp - 0.15))) * 0.55)
    grav = np.maximum(grav, 0.3 * T.smoothstep(0.58, 0.8, T.fbm(X, Z, 2.2, 2, seed=73)) * (1.0 - edge))
    trail = np.maximum(trail, grav * plat)
    # 濕暗：平台以下的林地（越低越濕）、池岸、手水舍周圍（濺水）、鋪石縫
    wet = np.clip(T.smoothstep(26.0, 12.0, h) * (1.0 - plat) * 0.75 + (1.0 - T.smoothstep(0.9, 1.6, dp / max(pc['rx'], 1e-3))) * 0.5, 0, 1)
    wet = np.maximum(wet, trail * (1.0 - plat) * 0.35)
    dtz = np.sqrt((X - (-8.6)) ** 2 + (Z - 0.6) ** 2)
    wet = np.maximum(wet, (1.0 - T.smoothstep(0.8, 2.9, dtz)) * 0.55 * (0.7 + 0.3 * patch))
    wet = np.maximum(wet, pav * 0.12)      # 審圖 r1：0.3 → 石縫太黑（像深溝）
    # 落花：櫻花林區（拜殿後、池塘四周）＋前庭零星（掃過的中軸少）
    if petal_fn is not None:
        pet = petal_fn(X, Z)
    else:
        pet = np.clip((1.0 - T.smoothstep(-30.0, -24.0, Z)) * (1.0 - T.smoothstep(30.0, 40.0, np.abs(X - 5.0))) * 0.8, 0, 1)
        pet = np.maximum(pet, (1.0 - shelf * 0.0) * (1.0 - T.smoothstep(pc['shelf_r'] - 4.0, pc['shelf_r'] + 6.0, dp)) * 0.8)
        pet = np.maximum(pet, plat * 0.18)
    pet = pet * (1.0 - water) * (1.0 - rock) * (1.0 - traffic * 0.75)
    # 審圖 r2：掃過的花瓣會被推到參道邊、燈籠台座腳 → 鋪石外 0.1–0.7 m 斷續的一條（跟著雜訊斷開）
    pet_edge = (T.smoothstep(0.05, 0.2, ds) * (1.0 - T.smoothstep(0.45, 0.9, ds))) * plat
    pet = np.maximum(pet, pet_edge * 0.55 * T.smoothstep(0.0, 0.45, T.fbm(X, Z, 2.8, 3, seed=79)))
    # 苔：林床＋岩，北向坡、濕處更多
    north = np.clip(-nrm[..., 2] * 2.0, 0, 1)
    moss = np.clip((forest * 0.5 + rock * 0.6) * (0.5 + 0.5 * T.fbm(X, Z, 6.0, 3, seed=67)) + wet * 0.25 + north * 0.2, 0, 1) * (1.0 - trail * (1.0 - plat) * 0.7)
    # 前庭苔痕：低踩踏處（外緣、北半樹蔭）成斑；高踩踏處幾乎沒有
    mn = T.smoothstep(0.2, 0.55, T.fbm(X, Z, 3.5, 3, seed=69))
    moss = np.maximum(moss, plat * (1.0 - traffic * 0.9) * mn * (0.25 + 0.45 * edge + 0.3 * T.smoothstep(-8.0, -26.0, Z)))
    # 鋪石縫（石塊之間露出的地面）與鋪石外緣
    moss = np.maximum(moss, pav * 0.45)
    moss = np.maximum(moss, (1.0 - T.smoothstep(0.0, 0.8, ds)) * (ds > 0.0) * 0.45 * (0.5 + 0.5 * mn))
    # 燈籠、狛犬台座、鳥居石台、社號標周圍
    for key, (px_, pz_, _) in L.PLACE.items():
        if key.startswith('lantern') or key.startswith('komainu') or key == 'shagohyo':
            dd = np.sqrt((X - px_) ** 2 + (Z - pz_) ** 2)
            moss = np.maximum(moss, (1.0 - T.smoothstep(0.4, 1.3, dd)) * 0.55 * (0.6 + 0.4 * mn))
    for sx_ in (-1.7, 1.7):
        dd = np.sqrt((X - sx_) ** 2 + (Z - 7.4) ** 2)
        moss = np.maximum(moss, (1.0 - T.smoothstep(0.45, 1.2, dd)) * 0.5)
    moss = np.maximum(moss, sb * 0.55 * (0.4 + 0.6 * mn))
    # 落葉（楓）：楓樹下、前庭外緣零星；掃過的中軸少
    leaf = np.zeros_like(X)
    for (mx_, mz_) in L.MAPLES:
        dd = np.sqrt((X - mx_) ** 2 + (Z - mz_) ** 2)
        leaf = np.maximum(leaf, (1.0 - T.smoothstep(1.2, 5.5, dd)) * 0.85)
    leaf = np.maximum(leaf, edge * 0.22 + sb * 0.3)
    leaf = leaf * (1.0 - traffic * 0.7) * (1.0 - water)
    # mask_c.b：鋪石接地（石縫＋石外 0.3 m 的接觸陰影）——審圖 r2：石與土同明度、邊界讀不出來
    contact = np.maximum(pav * 0.6, (1.0 - T.smoothstep(0.0, 0.3, ds)) * (ds > 0.0)) * plat
    # mask_c.a：前庭大尺度土色分區（6–12 m）：0＝暖赭（乾、外圍）→ 1＝冷褐（壓實、樹蔭、北半）
    zone = np.clip(0.5 + 0.9 * T.fbm(X, Z, 9.0, 2, seed=83) + 0.25 * traffic + 0.2 * T.smoothstep(-6.0, -24.0, Z) - 0.25 * edge, 0, 1) * plat
    A = np.stack([dirt, forest, rock, grass], -1)
    B = np.stack([trail, wet, pet, moss], -1)
    C = np.stack([worn, leaf, contact, zone], -1)
    for nm, img in (('mask_a', A), ('mask_b', B), ('mask_c', C)):
        arr = (np.clip(img, 0, 1) * 255).astype(np.uint8)
        with open(os.path.join(OUT, nm + '.rgba'), 'wb') as f:
            f.write(np.array([arr.shape[1], arr.shape[0]], dtype=np.int32).tobytes())
            f.write(arr.tobytes())
        Image.fromarray(arr, 'RGBA').save(os.path.join(PREV, '_' + nm + '.png'))
    return slope


def grid_normals(H, step):
    gz, gx = np.gradient(H, step)
    n = np.stack([-gx, np.ones_like(H), -gz], -1)
    return n / np.linalg.norm(n, axis=-1, keepdims=True)


def sample_field(F, spec, x, z):
    """F: (nz, nx, c) 依 spec 網格雙線性內插。"""
    fx = (x - spec['x0']) / spec['step']
    fz = (z - spec['z0']) / spec['step']
    i = np.clip(np.floor(fx).astype(int), 0, F.shape[1] - 2)
    j = np.clip(np.floor(fz).astype(int), 0, F.shape[0] - 2)
    u = np.clip(fx - i, 0, 1)[..., None]
    v = np.clip(fz - j, 0, 1)[..., None]
    a = F[j, i] * (1 - u) + F[j, i + 1] * u
    b = F[j + 1, i] * (1 - u) + F[j + 1, i + 1] * u
    return a * (1 - v) + b * v


def seam_blend_normals(N_in, spec_in, N_out, spec_out, width):
    """內層網格靠邊界 width m 內的法線漸變成外層網格的法線（邊界上完全相同 → 無明暗接縫）。"""
    X, Z = T.grid(spec_in)
    edge = np.minimum.reduce([X - spec_in['x0'], spec_in['x1'] - X, Z - spec_in['z0'], spec_in['z1'] - Z])
    w = (1.0 - T.smoothstep(0.0, width, edge))[..., None]
    No = sample_field(N_out, spec_out, X, Z)
    N = N_in * (1 - w) + No * w
    return N / np.linalg.norm(N, axis=-1, keepdims=True)


def export_grid(H, N, spec, path, hole=None, uv2=False):
    """寫出 Godot 讀取用的二進位網格：
    int32 nv, int32 ni, int32 has_uv2；f32 pos[nv*3]、nrm[nv*3]、uv[nv*2]、(uv2[nv*2])；int32 idx[ni]。
    三角化：(i+j) 偶 → a-d 對角，奇 → b-c 對角（與 s3lib.gd height_at 相同）；繞序 CW（Godot 正面）。"""
    nz, nx = H.shape
    X, Z = T.grid(spec)
    pos = np.stack([X, H, Z], -1).reshape(-1, 3).astype(np.float32)
    nrm = N.reshape(-1, 3).astype(np.float32)
    uv = np.stack([X, Z], -1).reshape(-1, 2).astype(np.float32)
    jj, ii = np.meshgrid(np.arange(nz - 1), np.arange(nx - 1), indexing='ij')
    a = jj * nx + ii
    b = a + 1
    c = a + nx
    d = c + 1
    even = ((ii + jj) % 2) == 0
    keep = np.ones_like(even, dtype=bool)
    if hole is not None:
        qx0 = spec['x0'] + ii * spec['step']
        qz0 = spec['z0'] + jj * spec['step']
        qx1 = qx0 + spec['step']
        qz1 = qz0 + spec['step']
        eps = 1e-6
        inside = (qx0 >= hole['x0'] - eps) & (qx1 <= hole['x1'] + eps) & (qz0 >= hole['z0'] - eps) & (qz1 <= hole['z1'] + eps)
        keep = ~inside
    t1 = np.where(even[..., None], np.stack([a, b, d], -1), np.stack([a, b, c], -1))
    t2 = np.where(even[..., None], np.stack([a, d, c], -1), np.stack([b, d, c], -1))
    idx = np.concatenate([t1[keep], t2[keep]], 0).reshape(-1).astype(np.int32)
    with open(path, 'wb') as f:
        f.write(np.array([pos.shape[0], idx.size, 1 if uv2 else 0], dtype=np.int32).tobytes())
        f.write(pos.tobytes())
        f.write(nrm.tobytes())
        f.write(uv.tobytes())
        if uv2:
            u2 = np.stack([(X - spec['x0']) / (spec['x1'] - spec['x0']), (Z - spec['z0']) / (spec['z1'] - spec['z0'])], -1)
            f.write(u2.reshape(-1, 2).astype(np.float32).tobytes())
        f.write(idx.tobytes())
    return pos.shape[0], idx.size // 3


def main():
    preview = '--no-preview' not in sys.argv
    (Xn, Zn, Hn, Hn_reg, masks), (Xm, Zm, Hm), (Xf, Zf, Hf) = build_grids()
    for name, H in (('h_near', Hn), ('h_mid', Hm), ('h_far', Hf)):
        H.astype(np.float32).tofile(os.path.join(OUT, name + '.f32'))
    Nn = grid_normals(Hn, L.NEAR['step'])
    Nm = grid_normals(Hm, L.MID['step'])
    Nf = grid_normals(Hf, L.FAR['step'])
    Nm = seam_blend_normals(Nm, L.MID, Nf, L.FAR, 120.0)
    Nn = seam_blend_normals(Nn, L.NEAR, Nm, L.MID, 10.0)
    for name, H, N, spec, hole, u2 in (('terrain_near', Hn, Nn, L.NEAR, None, True),
                                       ('terrain_mid', Hm, Nm, L.MID, L.NEAR, False),
                                       ('terrain_far', Hf, Nf, L.FAR, L.MID, False)):
        nv, nt = export_grid(H, N, spec, os.path.join(OUT, name + '.bin'), hole, u2)
        print('[gen] %s.bin verts %d tris %d' % (name, nv, nt))
    slope = write_masks(Hn, masks)
    S = Sampler(Hn, Hm, Hf)
    hz = {}
    for name, (x, z) in L.VIEWPOINTS.items():
        y = float(S.h(np.array([x]), np.array([z]))[0]) + L.EYE
        hz[name] = horizon(S, x, z, y)
    # 反盆地量測
    rep = {}
    for name, (az, an, af, di) in hz.items():
        front = (az >= 180.0) & (az <= 300.0)
        rep[name] = {
            'front_S_to_W_near_max_deg': round(float(an[front].max()), 2),
            'front_S_to_W_all_max_deg': round(float(af[front].max()), 2),
            'frac_near_gt8deg': round(float((an > 8.0).mean()), 3),
            'frac_near_lt0deg': round(float((an < 0.0).mean()), 3),
            'az_deg': az.tolist(), 'near_deg': np.round(an, 2).tolist(), 'all_deg': np.round(af, 2).tolist(),
            'all_dist_m': np.round(di, 1).tolist(),
        }
    json.dump(rep, open(os.path.join(OUT, 'horizon.json'), 'w', encoding='utf-8'), ensure_ascii=False)
    # layout.json（Godot 端單一來源）
    lay = {
        'P': L.P, 'near': L.NEAR, 'mid': L.MID, 'far': L.FAR,
        'near_n': [int(Hn.shape[1]), int(Hn.shape[0])], 'mid_n': [int(Hm.shape[1]), int(Hm.shape[0])], 'far_n': [int(Hf.shape[1]), int(Hf.shape[0])],
        'platform': L.PLATFORM, 'play': L.PLAY, 'fence_w': L.FENCE_W,
        'stair': L.STAIR, 'stair_segs': [list(s) for s in L._SEGS], 'z_foot': L.Z_FOOT, 'y_foot': L.Y_FOOT,
        'beast': T.beast_profile(), 'beast_half_w': L.BEAST_HALF_W, 'portal': list(L.PORTAL),
        'pond': L.POND, 'paths': L.PATHS, 'sando': L.SANDO, 'place': L.PLACE, 'viewpoints': L.VIEWPOINTS,
        'temizuya_pad': list(L.TEMIZUYA_PAD), 'fixed_trees': [list(t) for t in L.FIXED_TREES],
    }
    json.dump(lay, open(os.path.join(OUT, 'layout.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    # 數字摘要
    print('[gen] near %s mid %s far %s' % (Hn.shape, Hm.shape, Hf.shape))
    print('[gen] near h range %.2f..%.2f；regional@平台中心 %.2f' % (Hn.min(), Hn.max(), float(T.regional(np.array([0.0]), np.array([-8.0]))[0])))
    bp = T.beast_profile()
    print('[gen] 獸道 %d 點：y %.2f → %.2f（傳送點 %.1f, %.1f）；最大縱坡 %.1f%%' % (
        len(bp), bp[0][2], bp[-1][2], bp[-1][0], bp[-1][1],
        100.0 * max(abs(bp[i + 1][2] - bp[i][2]) / max(math.hypot(bp[i + 1][0] - bp[i][0], bp[i + 1][1] - bp[i][1]), 1e-6) for i in range(len(bp) - 1))))
    cut = Hn_reg - Hn
    pm = masks['platform'] > 0.5
    print('[gen] 平台：切方最大 %.2f m、填方最大 %.2f m' % (float(cut[pm].max()), float(-cut[pm].min())))
    for name, r in rep.items():
        print('[horizon] %-13s 南~西扇區近距最大 %+6.2f°  全距最大 %+6.2f°  近距>8° 比例 %.2f  近距<0° 比例 %.2f' % (
            name, r['front_S_to_W_near_max_deg'], r['front_S_to_W_all_max_deg'], r['frac_near_gt8deg'], r['frac_near_lt0deg']))
    if preview:
        preview_near(Hn, masks, os.path.join(PREV, '_preview_near.png'))
        preview_mid(Hm, os.path.join(PREV, '_preview_mid.png'), L.MID, -160, 200)
        preview_mid(Hf, os.path.join(PREV, '_preview_far.png'), L.FAR, -160, 700)
        section(S, os.path.join(PREV, '_preview_section.png'))
        horizon_plot(hz, os.path.join(PREV, '_preview_horizon.png'))
        print('[gen] previews written')


if __name__ == '__main__':
    main()

"""博麗神社 r3 地形生成（高度場＋貼圖遮罩＋遠景），輸出給 build_terrain.gd。

    python godot/tools/shrine_v2/gen_terrain.py [--preview]

輸出（godot/maps/shrine_v2/gen/）：
  height.f32      近景地形高度格（float32，row-major：j=z 由小到大，i=x 由小到大）
  mask.png        terrain_pbr.gdshader 的遮罩（R=路徑土 G=林床 B=大尺度明暗 A=夯土）
  vista_a.f32     中景（4 m 格，±260）；vista_b.f32 遠景（20 m 格，±1100）
  layout.json     格距／範圍／石階／參道等，GDScript 端讀這份
  _preview_*.png  俯視高度暈渲＋坡度圖（審地形用）

地形做法：每個「核心」（平台、石階廊、參道）各自長出一個往外上升的凹碗曲面（距離變換＋二次曲線），
取各曲面的下包絡（min），核心內部保持精確高度；再高斯鬆弛、加噪、限制坡度。
"""
from __future__ import annotations

import json
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
import layout as L  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
GEN = os.path.join(ROOT, "maps", "shrine_v2", "gen")
os.makedirs(GEN, exist_ok=True)

rng = np.random.default_rng(L.SEED)


# ───────────── 噪聲 ─────────────
class Noise:
    def __init__(self, seed, size=256):
        r = np.random.default_rng(seed)
        self.t = r.random((size, size)).astype(np.float64)
        self.n = size

    def value(self, x, z):
        xi = np.floor(x).astype(np.int64)
        zi = np.floor(z).astype(np.int64)
        fx = x - xi
        fz = z - zi
        fx = fx * fx * (3 - 2 * fx)
        fz = fz * fz * (3 - 2 * fz)
        n = self.n
        a = self.t[zi % n, xi % n]
        b = self.t[zi % n, (xi + 1) % n]
        c = self.t[(zi + 1) % n, xi % n]
        d = self.t[(zi + 1) % n, (xi + 1) % n]
        return (a * (1 - fx) + b * fx) * (1 - fz) + (c * (1 - fx) + d * fx) * fz

    def fbm(self, x, z, wavelength, octaves=4, gain=0.5, lac=2.0):
        out = np.zeros_like(x, dtype=np.float64)
        amp = 1.0
        tot = 0.0
        f = 1.0 / wavelength
        for o in range(octaves):
            # 每個 octave 偏移避免對齊
            out += amp * self.value(x * f + 17.3 * o, z * f - 9.1 * o)
            tot += amp
            amp *= gain
            f *= lac
        return out / tot  # 0..1

    def ridged(self, x, z, wavelength, octaves=4):
        v = self.fbm(x, z, wavelength, octaves)
        return 1.0 - np.abs(v * 2.0 - 1.0)


NZ = Noise(L.SEED)
NZ2 = Noise(L.SEED + 7)
NZ3 = Noise(L.SEED + 13)


# ───────────── 幾何距離 ─────────────
def seg_dist(px, pz, ax, az, bx, bz):
    dx, dz = bx - ax, bz - az
    ll = dx * dx + dz * dz
    t = np.clip(((px - ax) * dx + (pz - az) * dz) / (ll if ll > 0 else 1.0), 0.0, 1.0)
    cx, cz = ax + t * dx, az + t * dz
    return np.hypot(px - cx, pz - cz)


def poly_sdf(px, pz, poly):
    """多邊形有號距離：內部負、外部正。"""
    n = len(poly)
    dmin = np.full(px.shape, 1e9)
    inside = np.zeros(px.shape, bool)
    for i in range(n):
        ax, az = poly[i]
        bx, bz = poly[(i + 1) % n]
        dmin = np.minimum(dmin, seg_dist(px, pz, ax, az, bx, bz))
        cond = ((az > pz) != (bz > pz)) & (px < (bx - ax) * (pz - az) / (bz - az + 1e-12) + ax)
        inside ^= cond
    return np.where(inside, -dmin, dmin)


def rise(d, a, b, smax=0.8):
    d = np.maximum(d, 0.0)
    dcap = max((smax - a) / (2 * b), 1e-6)
    r1 = a * d + b * d * d
    r2 = a * dcap + b * dcap * dcap + smax * (d - dcap)
    return np.where(d < dcap, r1, r2)


def line_field(px, pz, samples, widths, a, b, smax, chunk=4096):
    """samples (S,3)=x,z,y；回傳 (F, dmin_core)。F=min_j(y_j + rise(max(0,d_j-w_j)))；dcore=min_j(d_j-w_j)。"""
    shp = px.shape
    px = px.ravel()
    pz = pz.ravel()
    F = np.empty(px.shape)
    D = np.empty(px.shape)
    sx, sz, sy = samples[:, 0][None, :], samples[:, 1][None, :], samples[:, 2][None, :]
    w = np.asarray(widths)[None, :] if np.ndim(widths) else widths
    for i in range(0, len(px), chunk):
        x = px[i:i + chunk, None]
        z = pz[i:i + chunk, None]
        d = np.hypot(x - sx, z - sz) - w
        f = sy + rise(d, a, b, smax)
        F[i:i + chunk] = f.min(axis=1)
        D[i:i + chunk] = d.min(axis=1)
    return F.reshape(shp), D.reshape(shp)


def line_field_n(px, pz, samples, w, a, b, smax, chunk=4096):
    """沿坡折線的場：高度取「最近樣本」的 y，再加橫向超出半寬 w 的上升量。
    （舊 line_field 取半寬內樣本的 min，沿坡的核心會被往下拉 w×坡度＝0.6–0.9 m。）"""
    shp = px.shape
    px = px.ravel()
    pz = pz.ravel()
    F = np.empty(px.shape)
    D = np.empty(px.shape)
    sx, sz, sy = samples[:, 0][None, :], samples[:, 1][None, :], samples[:, 2]
    for i in range(0, len(px), chunk):
        x = px[i:i + chunk, None]
        z = pz[i:i + chunk, None]
        d = np.hypot(x - sx, z - sz)
        k = d.argmin(axis=1)
        dm = d[np.arange(len(k)), k]
        lat = dm - w
        F[i:i + chunk] = sy[k] + rise(lat, a, b, smax)
        D[i:i + chunk] = lat
    return F.reshape(shp), D.reshape(shp)


def gauss_blur(h, sigma_cells, passes=1):
    r = int(max(1, round(sigma_cells * 3)))
    k = np.exp(-0.5 * (np.arange(-r, r + 1) / sigma_cells) ** 2)
    k /= k.sum()
    out = h
    for _ in range(passes):
        pad = np.pad(out, ((0, 0), (r, r)), mode="edge")
        out = sum(k[i] * pad[:, i:i + out.shape[1]] for i in range(len(k)))
        pad = np.pad(out, ((r, r), (0, 0)), mode="edge")
        out = sum(k[i] * pad[i:i + out.shape[0], :] for i in range(len(k)))
    return out


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def limit_slope(h, protect, step, max_slope, passes=400):
    """相鄰格高差限制。protect(0..1)：1=不動。"""
    md = max_slope * step
    mdd = max_slope * step * math.sqrt(2)
    m = 1.0 - protect
    for _ in range(passes):
        changed = 0.0
        for axis, lim, sl in ((0, md, (slice(1, None), slice(None, -1))), (1, md, None), (None, mdd, None)):
            pass
        # x 方向
        d = h[:, 1:] - h[:, :-1]
        ex = np.sign(d) * np.maximum(np.abs(d) - md, 0.0)
        wl, wr = m[:, :-1], m[:, 1:]
        tot = wl + wr + 1e-9
        h[:, :-1] += ex * wl / tot
        h[:, 1:] -= ex * wr / tot
        # z 方向
        d = h[1:, :] - h[:-1, :]
        ex = np.sign(d) * np.maximum(np.abs(d) - md, 0.0)
        wl, wr = m[:-1, :], m[1:, :]
        tot = wl + wr + 1e-9
        h[:-1, :] += ex * wl / tot
        h[1:, :] -= ex * wr / tot
        changed = float(np.abs(ex).max())
        if changed < 1e-4:
            break
    return h


# ───────────── 近景高度場 ─────────────
def build_fields(px, pz, detail=True):
    """回傳 H, dcore, parts。px,pz 為任意形狀的座標陣列。"""
    plat = L.chaikin(L.PLATEAU, 2)
    sdf0 = poly_sdf(px, pz, plat)
    # 領域扭曲：只扭曲「離核心較遠」的距離量，核心內部維持精確
    wt = smoothstep(0.0, 10.0, sdf0)
    wx = (NZ.fbm(px, pz, 64.0, 3) - 0.5) * 2.0 * 13.0 * wt
    wz = (NZ2.fbm(px, pz, 64.0, 3) - 0.5) * 2.0 * 13.0 * wt
    sdf_w = poly_sdf(px + wx, pz + wz, plat)
    # 平坦區外緣只往外「長」不規則的灣與岬（最多 2.8 m）；內部不動
    edge_n = NZ3.fbm(px, pz, 9.0, 3)
    sdf_plat = np.where(sdf0 <= 0.0, sdf0, np.maximum(sdf_w - 2.8 * edge_n, 0.0))
    aniso = 0.62 + 0.95 * NZ3.fbm(px + 311.0, pz - 77.0, 58.0, 3)     # 0.62..1.57：坡的緩急（方向性）
    # 西北偏北留一個低鞍口，從庭院能望見遠山
    aniso = aniso * (1.0 - 0.55 * np.exp(-(((px + 26.0) ** 2 + (pz + 72.0) ** 2) / (2 * 20.0 ** 2))))
    F_plat = L.Y_C + rise(sdf_plat, 0.22, 0.0042, 0.74) * aniso

    bed = L.stair_bed_smooth()
    zs = np.array([b[0] for b in bed])[::-1]
    ys = np.array([b[1] for b in bed])[::-1]
    zz = np.arange(zs.min() - 1.0, L.Z_FOOT + 1.0, 0.25)
    yy = np.interp(zz, zs, ys)
    stair_s = np.stack([np.zeros_like(zz), zz, yy], axis=1)
    F_stair, D_stair = line_field_n(px, pz, stair_s, L.BED_HALF, 0.42, 0.0035, 0.72)

    path_pts = L.catmull_rom(L.APPROACH, 0.5)
    F_path, D_path = line_field_n(px, pz, path_pts, L.APPROACH_HALF, 0.20, 0.0062, 0.72)
    # 參道場只管石階腳以南；以北若不關掉，它的 0.2 m/m 緩坡會把石階下半段的地形拉低 0.6–1.1 m
    F_path = F_path + 40.0 * (1.0 - smoothstep(L.Z_FOOT - 1.5, L.Z_FOOT + 0.5, pz))

    H = np.minimum(np.minimum(F_plat, F_stair), F_path)
    dcore = np.minimum(np.minimum(sdf_plat, D_stair), D_path)  # 負=核心內
    return H, dcore, dict(F_plat=F_plat, F_stair=F_stair, F_path=F_path, sdf_plat=sdf_plat,
                          D_stair=D_stair, D_path=D_path)


BANK_SLOPE = 0.34                  # 池岸坡度（m/m，約 19°）


def carve_pond(px, pz, H):
    p = L.POND
    th = math.radians(p["rot_deg"])
    c, s = math.cos(th), math.sin(th)
    dx, dz = px - p["cx"], pz - p["cz"]
    u = (dx * c + dz * s) / p["rx"]
    v = (-dx * s + dz * c) / p["rz"]
    ang = np.arctan2(v, u)
    wob = 1.0 + 0.16 * np.sin(ang * 2 + 0.7) + 0.09 * np.sin(ang * 3 - 1.3) + 0.05 * np.sin(ang * 5 + 2.1)
    r = np.hypot(u, v) / wob           # 1 = 水線
    # 水域：r<1 的池盆；岸坡：水線外以固定坡度升起、再平滑併入原地面。
    # （舊版岸坡用 smoothstep(1.0,1.9)，起點斜率為 0 → 水線外有一圈 ±0.1 m 的水平淺灘，
    #   水面（±0.04 m 起伏）與地形交成破碎的藍色斑塊。現在水線交點坡度固定 ≈0.34 m/m。）
    water_y = p["level"]
    depth = p["depth"]
    rim_wet = 0.10                     # 水線（r=1）處地形比水面低 0.10 m → 與水面交線落在 r≈1.047
    bed_t = np.clip(r, 0.0, 1.0)
    bed_y = (water_y - rim_wet) - (depth - rim_wet) * (1.0 - bed_t ** 2.0)
    Rm = 0.5 * (p["rx"] + p["rz"])
    d_out = np.maximum(r - 1.0, 0.0) * Rm            # 水線外水平距離（m）
    bank_y = (water_y - rim_wet) + BANK_SLOPE * d_out
    k = 0.25                                         # 平滑取小的寬度（m）
    hh = np.clip(0.5 + 0.5 * (bank_y - H) / k, 0.0, 1.0)
    shore_y = bank_y * (1.0 - hh) + H * hh - k * hh * (1.0 - hh)
    shore_y = np.minimum(shore_y, H)                 # 岸坡不高於原地面
    w_out = smoothstep(2.2, 3.2, r)                  # r 2.2→3.2 逐漸回到原地形（不留斷崖）
    shore_blend = shore_y * (1.0 - w_out) + H * w_out
    out = np.where(r < 1.0, bed_y, np.where(r < 3.2, shore_blend, H))
    return out, r


def carve_trail(px, pz, H):
    """林間步道路基：沿中線把路面切成水平（橫向無坡）、縱向取地形高度的 ±5 m 滑動平均；
    上坡側切成 ≈40° 的邊坡、下坡側填成 ≈33° 的邊坡，與自然坡面銜接。回傳 (H', 路面遮罩)。"""
    pts = L.catmull_rom(L.TRAIL, 0.5)[:, :2]
    xs, zs = px[0, :], pz[:, 0]
    step = float(xs[1] - xs[0])

    def samp(x, z):
        fx = np.clip((x - xs[0]) / step, 0, len(xs) - 1.001)
        fz = np.clip((z - zs[0]) / step, 0, len(zs) - 1.001)
        ix, iz = fx.astype(int), fz.astype(int)
        tx, tz = fx - ix, fz - iz
        return (H[iz, ix] * (1 - tx) * (1 - tz) + H[iz, ix + 1] * tx * (1 - tz)
                + H[iz + 1, ix] * (1 - tx) * tz + H[iz + 1, ix + 1] * tx * tz)

    hc = samp(pts[:, 0], pts[:, 1])
    k = 10
    hs = np.convolve(np.pad(hc, (k, k), mode="edge"), np.ones(2 * k + 1) / (2 * k + 1), mode="valid")
    P = np.stack([px.ravel(), pz.ravel()], 1)
    best_d = np.full(len(P), 1e9)
    best_i = np.zeros(len(P), int)
    for s0 in range(0, len(pts), 48):
        seg = pts[s0:s0 + 48]
        d = np.hypot(P[:, None, 0] - seg[None, :, 0], P[:, None, 1] - seg[None, :, 1])
        j = d.argmin(1)
        dm = d[np.arange(len(P)), j]
        upd = dm < best_d
        best_d[upd] = dm[upd]
        best_i[upd] = s0 + j[upd]
    dist = best_d.reshape(px.shape)
    tread = hs[best_i].reshape(px.shape)
    r_in = L.TRAIL_HALF
    dd = np.maximum(dist - r_in, 0.0)
    bank = np.where(H > tread, np.minimum(H, tread + 0.84 * dd), np.maximum(H, tread - 0.65 * dd))
    Hn = np.where(dist <= r_in, tread, bank)
    return Hn, (dist <= r_in + 0.6).astype(float)


def make_height(px, pz, step, detail=True):
    H, dcore, parts = build_fields(px, pz)
    core_w = 1.0 - smoothstep(-0.2, 3.0, dcore)       # 1=核心內（不被鬆弛/加噪）
    H_hard = H.copy()
    if detail:
        sig = 1.6 / step
        Hs = gauss_blur(H, sig, 2)
        H = np.where(dcore > 0, Hs * (1 - core_w) + H_hard * core_w, H_hard)
        # 起伏：離核心越遠越大；兩個尺度
        dd = np.maximum(dcore, 0.0)
        amp = np.clip(0.10 * dd, 0.0, 1.0)
        n1 = (NZ.fbm(px, pz, 28.0, 4) - 0.5) * 2.0
        n2 = (NZ2.fbm(px, pz, 9.0, 3) - 0.5) * 2.0
        H = H + amp * (1.35 * n1 + 0.45 * n2)
        # 山肩與支稜：離核心 14 m 外逐漸出現（不對稱、有方向性）
        spur = NZ2.ridged(px + 91.0, pz + 53.0, 44.0, 3)
        H = H + smoothstep(14.0, 38.0, dd) * (spur - 0.45) * 6.0
        # 平台內部的極輕微起伏（不影響建築腳印；建築區再壓平）
        inner = np.clip(-parts["sdf_plat"] / 3.0, 0.0, 1.0)
        n3 = (NZ3.fbm(px, pz, 14.0, 3) - 0.5) * 2.0
        H = H + inner * 0.07 * n3
    # 池塘
    H, pr = carve_pond(px, pz, H)
    # 林間步道路基（在池塘之後；不動池塘範圍）
    H, tm = carve_trail(px, pz, H)
    parts["trail_tread"] = tm
    return H, dcore, parts, pr


def build_height_grid():
    T = L.TERRAIN
    xs = np.arange(T["x0"], T["x1"] + 1e-6, T["step"])
    zs = np.arange(T["z0"], T["z1"] + 1e-6, T["step"])
    PX, PZ = np.meshgrid(xs, zs)
    H, dcore, parts, pr = make_height(PX, PZ, T["step"], True)
    # 坡度限制（核心與池水不動）
    protect = np.clip(1.0 - smoothstep(-0.2, 2.0, dcore), 0, 1)
    protect = np.maximum(protect, (pr < 1.05).astype(float))
    protect = np.maximum(protect, parts["trail_tread"])
    H = limit_slope(H, protect, T["step"], math.tan(math.radians(41.0)), 500)
    return xs, zs, PX, PZ, H.astype(np.float32), dcore, parts, pr


# ───────────── 遮罩 ─────────────
def build_mask(xs, zs, PX, PZ, H, dcore, parts, pr, size=(640, 768)):
    """遮罩對應整個近景地形矩形，UV = (x-x0)/W, (z-z0)/D。
    R=路徑碎石土  G=林床落葉  B=大尺度明暗  A=夯土。預設底層是草。"""
    T = L.TERRAIN
    W = T["x1"] - T["x0"]
    D = T["z1"] - T["z0"]
    mw, mh = size
    mxs = T["x0"] + (np.arange(mw) + 0.5) / mw * W
    mzs = T["z0"] + (np.arange(mh) + 0.5) / mh * D
    MX, MZ = np.meshgrid(mxs, mzs)

    def hs(x, z):
        fx = (x - T["x0"]) / T["step"]
        fz = (z - T["z0"]) / T["step"]
        i0 = np.clip(np.floor(fx).astype(int), 0, H.shape[1] - 2)
        j0 = np.clip(np.floor(fz).astype(int), 0, H.shape[0] - 2)
        tx, tz = fx - i0, fz - j0
        return ((H[j0, i0] * (1 - tx) + H[j0, i0 + 1] * tx) * (1 - tz)
                + (H[j0 + 1, i0] * (1 - tx) + H[j0 + 1, i0 + 1] * tx) * tz)

    Hm = hs(MX, MZ)
    gz, gx = np.gradient(Hm, D / mh, W / mw)
    slope = np.hypot(gx, gz)
    _, dc, pts = build_fields(MX, MZ)
    sdf_plat = pts["sdf_plat"]
    D_stair = pts["D_stair"]
    D_path = pts["D_path"]

    nA = NZ.fbm(MX, MZ, 5.0, 3)
    nB = NZ2.fbm(MX, MZ, 22.0, 3)
    nC = NZ3.fbm(MX, MZ, 3.0, 2)
    nD = NZ.fbm(MX + 40.0, MZ - 25.0, 11.0, 3)

    inside = -sdf_plat                                    # 平台內深度（m）
    # A 夯土：庭院（z > -27 一帶）中央最實，邊緣被草侵入（草的比例由雜訊決定，不是均勻漸層）
    front = smoothstep(-30.0, -22.0, MZ)                  # 1=庭院側
    A = smoothstep(1.0 + 4.0 * nA, 7.0 + 5.0 * nD, inside) * front
    # 參道路基：寬約 3.6 m 的夯土帶，邊緣參差
    lane = 1.0 - smoothstep(-0.6 + 1.2 * (nA - 0.5), 0.7 + 0.8 * nC, D_path)
    A = np.maximum(A, lane * 0.97)
    # 石階旁與石階腳平台：中央不長草
    stair_core = 1.0 - smoothstep(-0.6, 0.5, D_stair)
    A = np.maximum(A, stair_core * 0.9)
    # 林間步道（夯土）：庭院西側 → 拜殿後方 → 池塘西岸；邊緣參差
    tp = L.catmull_rom(L.TRAIL, 0.8)
    dtr = np.full(MX.shape, 1e9)
    for (px_, pz_) in tp:
        dtr = np.minimum(dtr, np.hypot(MX - px_, MZ - pz_))
    trail = 1.0 - smoothstep(L.TRAIL_HALF * 0.55 + 0.30 * (nA - 0.5), L.TRAIL_HALF * 1.45 + 0.25 * (nC - 0.5), dtr)
    A = np.maximum(A, trail * 0.95)

    # G 林床：離核心遠（>14 m）、陡坡、石階兩側土坡薄薄一層
    ds = np.maximum(dc, 0.0)
    G = smoothstep(18.0 + 4.0 * nB, 50.0, ds) * 0.70
    G = np.maximum(G, smoothstep(0.80, 1.15, slope + 0.10 * (nC - 0.5)) * 0.45)
    bank = smoothstep(0.3, 1.2, D_stair) * (1.0 - smoothstep(4.5, 9.0, D_stair))
    G = np.maximum(G, bank * 0.55 * (0.5 + nD))
    # 平台後半（櫻花林／池畔）：草地為主，落葉土零星
    back = 1.0 - front
    G = np.maximum(G, back * smoothstep(0.0, 6.0, inside) * 0.30 * (0.4 + 1.2 * nD))
    G = np.clip(G * (1.0 - A), 0, 1)

    # R 碎石土：參道中央、池畔
    R = (1.0 - smoothstep(-1.7, -0.2, D_path)) * smoothstep(0.38, 0.78, nC) * 0.55
    pond = L.POND
    th = math.radians(pond["rot_deg"])
    c, s_ = math.cos(th), math.sin(th)
    dx, dz = MX - pond["cx"], MZ - pond["cz"]
    u = (dx * c + dz * s_) / pond["rx"]
    v = (-dx * s_ + dz * c) / pond["rz"]
    rr = np.hypot(u, v)
    shore = smoothstep(0.85, 1.05, rr) * (1.0 - smoothstep(1.3, 1.9, rr))
    R = np.maximum(R, shore * 0.8)
    A = A * (1.0 - shore)
    R = np.clip(R, 0, 1)

    B = np.clip(0.25 + 0.7 * nB + 0.2 * (NZ.fbm(MX, MZ, 60.0, 2) - 0.5), 0, 1)
    # 池畔水線一帶變暗（濕土帶）：B 通道 ×(1−0.9) → 地表亮度 ×≈0.83
    wet = smoothstep(0.90, 1.0, rr) * (1.0 - smoothstep(1.12, 1.45, rr))
    B = B * (1.0 - 0.9 * wet)
    img = np.stack([R, G, B, A], axis=-1)
    return (np.clip(img, 0, 1) * 255 + 0.5).astype(np.uint8)


# ───────────── 遠景 ─────────────
def regional(px, pz):
    """遠景區域起伏（近景 cones 在 d>~50 m 之後交給它）。"""
    r = np.hypot(px, pz + 20.0)
    ridge = NZ.ridged(px, pz, 260.0, 4)
    hills = NZ2.fbm(px, pz, 140.0, 4)
    base = L.Y_C + 16.0 + 34.0 * ridge + 22.0 * hills
    # 往遠處升高、往南（回頭看的方向）壓成山谷再升起
    base += 0.085 * np.maximum(r - 90.0, 0.0) * (0.6 + 0.9 * ridge)
    south = smoothstep(80.0, 520.0, pz) * (1.0 - smoothstep(520.0, 1100.0, pz))
    base -= 70.0 * south * (1.0 - 0.5 * ridge)
    return base


def far_height(px, pz):
    H, dcore, parts = build_fields(px, pz)
    d = np.maximum(dcore, 0.0)
    t = smoothstep(36.0, 95.0, d)
    Rg = regional(px, pz)
    n1 = (NZ.fbm(px, pz, 28.0, 4) - 0.5) * 2.0
    Hn = H + np.clip(0.10 * d, 0, 1.0) * (1.9 * n1)
    out = Hn * (1 - t) + np.maximum(Hn * 0.0 + Rg, Hn * 0.0 + Rg) * t
    return out


def hbil_arr(H, X, Z):
    """向量化雙線性取樣（邊界夾住）。"""
    T = L.TERRAIN
    fx = np.clip((X - T["x0"]) / T["step"], 0.0, H.shape[1] - 1.0001)
    fz = np.clip((Z - T["z0"]) / T["step"], 0.0, H.shape[0] - 1.0001)
    i0 = np.floor(fx).astype(int)
    j0 = np.floor(fz).astype(int)
    tx, tz = fx - i0, fz - j0
    return (H[j0, i0] * (1 - tx) + H[j0, i0 + 1] * tx) * (1 - tz) + (H[j0 + 1, i0] * (1 - tx) + H[j0 + 1, i0 + 1] * tx) * tz


def vista_a_height(PX, PZ, Hn):
    """中景高度：近景地形範圍外，邊緣高度（夾到近景邊界）以 90 m 平滑過渡到區域起伏 → 與近景網格 C0 連續。
    （舊版直接用 far_height，近景邊緣與中景差數公尺 → 俯視時看到直線接縫與暗邊。）"""
    T = L.TERRAIN
    far = far_height(PX, PZ)
    dxo = np.maximum(np.maximum(T["x0"] - PX, PX - T["x1"]), 0.0)
    dzo = np.maximum(np.maximum(T["z0"] - PZ, PZ - T["z1"]), 0.0)
    dout = np.hypot(dxo, dzo)
    Hedge = hbil_arr(Hn, np.clip(PX, T["x0"], T["x1"]), np.clip(PZ, T["z0"], T["z1"]))
    w = smoothstep(0.0, 90.0, dout)
    return Hedge * (1.0 - w) + far * w


def write_vista_masks():
    """中景／遠景的地面遮罩（低解析度雜訊）：G 草↔林床、B 大尺度明暗。與近景共用同一支 shader → 材質在接縫處連續。"""
    from PIL import Image
    for name, half in (("vista_a_mask.png", 260.0), ("vista_b_mask.png", 1100.0)):
        n = 128
        xs = -half + (np.arange(n) + 0.5) / n * 2 * half
        PX, PZ = np.meshgrid(xs, xs)
        sc = 70.0 if half < 500 else 380.0
        g = np.clip(0.40 + 0.9 * (NZ.fbm(PX, PZ, sc, 3) - 0.5), 0.0, 1.0)
        b = np.clip(0.50 + 1.1 * (NZ2.fbm(PX + 17.0, PZ - 9.0, sc * 1.7, 3) - 0.5), 0.0, 1.0)
        img = np.stack([np.zeros_like(g), g, b, np.zeros_like(g)], axis=-1)
        Image.fromarray((np.clip(img, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA").save(os.path.join(GEN, name))


def write_canopy_tex():
    """遠景林冠貼圖（1024²、可無縫平鋪；一像素 ≈ 0.22 m，樹冠半徑 3–6.5 m）：深淺綠的樹冠團塊，左上受光，
    少量針葉深色團與淡粉櫻花團。供 shrine_vista.gdshader 的中景／遠景地面用（近景範圍外沒有真的樹）。"""
    from PIL import Image
    W = 1024
    rs = np.random.RandomState(L.SEED + 7)
    img = np.zeros((W, W, 3), np.float32)
    img[:] = np.array([0.075, 0.13, 0.06])           # 樹冠縫隙（深）
    # 底層明暗斑（低頻）
    yy, xx = np.mgrid[0:W, 0:W]
    low = 0.5 + 0.5 * np.sin(xx / W * 2 * np.pi * 3 + 0.7) * np.sin(yy / W * 2 * np.pi * 4 + 1.9)
    img *= (0.85 + 0.3 * low[..., None])
    blobs = []
    for _ in range(1300):
        blobs.append((rs.randint(0, W), rs.randint(0, W), rs.uniform(14, 30), rs.random()))
    blobs.sort(key=lambda b: b[3])                   # 以隨機「高度」排序（高的蓋在上面）
    PAL = [(0.12, 0.22, 0.085), (0.15, 0.27, 0.10), (0.18, 0.31, 0.115), (0.10, 0.19, 0.085), (0.21, 0.33, 0.13)]
    for (cx, cy, r, hgt) in blobs:
        roll = rs.random()
        if roll < 0.14:
            base = np.array([0.06, 0.13, 0.08])      # 針葉（深）
        elif roll < 0.146:
            base = np.array([0.42, 0.32, 0.34])      # 櫻（淡粉；只占 0.6%，審圖：粉紫斑塊太醒目）
        else:
            base = np.array(PAL[rs.randint(0, len(PAL))])
        base = base * (0.85 + 0.3 * hgt)
        for sub in range(6):
            a = rs.uniform(0, 2 * np.pi)
            off = r * 0.45 * np.sqrt(rs.random())
            sx, sy = cx + np.cos(a) * off, cy + np.sin(a) * off
            sr = r * rs.uniform(0.40, 0.62)
            x0, x1 = int(sx - sr - 2), int(sx + sr + 3)
            y0, y1 = int(sy - sr - 2), int(sy + sr + 3)
            xs = np.arange(x0, x1) % W
            ys = np.arange(y0, y1) % W
            gx, gy = np.meshgrid(np.arange(x0, x1) - sx, np.arange(y0, y1) - sy)
            d = np.hypot(gx, gy) / sr
            lit = np.clip(0.55 - 0.5 * (gx * 0.55 + gy * 0.75) / sr, 0.0, 1.0)
            col = base[None, None, :] * (0.70 + 0.65 * lit[..., None])
            alpha = np.clip((1.0 - d) * 2.2, 0.0, 1.0)[..., None]
            sel = np.ix_(ys, xs)
            img[sel] = img[sel] * (1 - alpha) + col * alpha
    # 細碎葉片雜訊
    nz = rs.rand(W, W, 1).astype(np.float32)
    img *= (0.92 + 0.16 * nz)
    out = (np.clip(img, 0, 1) ** (1 / 2.2) * 255 + 0.5).astype(np.uint8)   # 以 sRGB 存（shader 用 source_color）
    Image.fromarray(out, "RGB").save(os.path.join(GEN, "canopy_far.png"))


def write_vista(name, half, step, near_rect=None, hide_inside=0.0, Hn=None):
    n = int(round(2 * half / step)) + 1
    xs = -half + np.arange(n) * step
    zs = -half + np.arange(n) * step
    PX, PZ = np.meshgrid(xs, zs)
    T = L.TERRAIN
    if name.startswith("vista_a"):
        H = vista_a_height(PX, PZ, Hn)
        # 近景範圍內：壓到近景網格下方（邊緣 0 → 內部 1.6 m），不從近景裡穿出來
        depth_in = np.minimum(np.minimum(PX - T["x0"], T["x1"] - PX), np.minimum(PZ - T["z0"], T["z1"] - PZ))
        H = H - 1.6 * smoothstep(0.0, 6.0, depth_in)
    else:
        far = far_height(PX, PZ)
        va = vista_a_height(PX, PZ, Hn)
        R = near_rect["x1"]
        depth_in = R - np.maximum(np.abs(PX), np.abs(PZ))      # 距中景範圍邊緣的內縮距離（<0＝在外）
        H = np.where(depth_in > 0.0, np.minimum(far, va) - 6.0 * smoothstep(0.0, 60.0, depth_in), far)
    H.astype(np.float32).tofile(os.path.join(GEN, name))
    return dict(half=half, step=step, n=n)


def main():
    preview = "--preview" in sys.argv
    T = L.TERRAIN
    xs, zs, PX, PZ, H, dcore, parts, pr = build_height_grid()
    H.tofile(os.path.join(GEN, "height.f32"))
    slope = np.hypot(*np.gradient(H, T["step"]))
    deg = np.degrees(np.arctan(slope))
    print(f"[TERRAIN] grid {H.shape[1]}x{H.shape[0]} step {T['step']}  y {H.min():.2f}..{H.max():.2f}")
    play = (PX >= L.PLAY["x0"]) & (PX <= L.PLAY["x1"]) & (PZ >= L.PLAY["z0"]) & (PZ <= L.PLAY["z1"])
    pd = deg[play]
    print(f"[TERRAIN] 玩家範圍坡度：平均 {pd.mean():.1f}°  >30° {100*(pd>30).mean():.1f}%  >40° {100*(pd>40).mean():.1f}%  最大 {pd.max():.1f}°")
    # 平台/石階/參道核心內的平整度
    core = dcore < -0.3
    print(f"[TERRAIN] 核心格 {core.sum()}，核心內最大坡度 {deg[core].max():.1f}°")

    mask = build_mask(xs, zs, PX, PZ, H, dcore, parts, pr)
    from PIL import Image
    Image.fromarray(mask, "RGBA").save(os.path.join(GEN, "mask.png"))

    va = write_vista("vista_a.f32", 260.0, 4.0, near_rect=T, hide_inside=0.5, Hn=H.astype(float))
    vb = write_vista("vista_b.f32", 1100.0, 20.0, near_rect=dict(x0=-262.0, x1=262.0, z0=-262.0, z1=262.0), hide_inside=0.5, Hn=H.astype(float))
    write_vista_masks()
    write_canopy_tex()
    treads, landings, z_end = L.stair_plan()
    meta = dict(
        terrain=dict(x0=T["x0"], x1=T["x1"], z0=T["z0"], z1=T["z1"], step=T["step"],
                     nx=int(H.shape[1]), nz=int(H.shape[0])),
        vista_a=va, vista_b=vb,
        y_c=L.Y_C, y_foot=L.Y_FOOT, play=L.PLAY,
        stair=dict(rise=L.RISE, run=L.RUN, width=L.STAIR_W, bed_half=L.BED_HALF, flights=L.FLIGHTS,
                   landing=L.LANDING, z_foot=L.Z_FOOT, z_end=z_end, treads=treads, landings=landings),
        approach=[list(map(float, p)) for p in L.APPROACH],
        plateau=[list(p) for p in L.PLATEAU],
        pond=L.POND, place=L.PLACE, seed=L.SEED,
    )
    with open(os.path.join(GEN, "layout.json"), "w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=False, indent=1)
    print("[TERRAIN] wrote height.f32 mask.png vista_a/b layout.json")
    write_meta(H)

    if preview:
        previews(xs, zs, H, deg, mask)


def hbil(H, x, z):
    T = L.TERRAIN
    fx = (x - T["x0"]) / T["step"]
    fz = (z - T["z0"]) / T["step"]
    i0, j0 = int(math.floor(fx)), int(math.floor(fz))
    tx, tz = fx - i0, fz - j0
    return float((H[j0, i0] * (1 - tx) + H[j0, i0 + 1] * tx) * (1 - tz) + (H[j0 + 1, i0] * (1 - tx) + H[j0 + 1, i0 + 1] * tx) * tz)


def write_meta(H):
    """data/shrine_v2.meta.json：傳送點（南端參道起點）。抵達點由 main.gd 往世界原點內縮 4 m。"""
    px, pz, py = L.APPROACH[1]
    d = math.hypot(px, pz)
    ax, az = px - px / d * 4.0, pz - pz / d * 4.0
    meta = {
        "_note": "博麗神社 r3 重製（候選場景，--map=shrine_v2）。由 tools/shrine_v2/gen_terrain.py 寫出，勿手改。",
        "id": "shrine_v2",
        "connections": ["trail"],
        "safe": True,
        "mobTheme": None,
        "playSize": [L.PLAY["x1"] - L.PLAY["x0"], L.PLAY["z1"] - L.PLAY["z0"]],
        "colliders": [],
        "portals": [{
            "_note": "南端參道起點 → 獸道。y=該點地面高；arrival_ground_y=內縮 4 m 落點的地面高。",
            "target": "trail", "x": px, "y": round(hbil(H, px, pz), 3), "z": pz,
            "arrival_ground_y": round(hbil(H, ax, az), 3), "arrival_y_offset": 1.2,
        }],
    }
    out = os.path.abspath(os.path.join(ROOT, "data", "shrine_v2.meta.json"))
    with open(out, "w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=False, indent=2)
    print("[TERRAIN] wrote data/shrine_v2.meta.json portal", meta["portals"][0]["x"], meta["portals"][0]["z"], meta["portals"][0]["y"])


def previews(xs, zs, H, deg, mask):
    from PIL import Image, ImageDraw
    T = L.TERRAIN
    # 暈渲
    gz, gx = np.gradient(H.astype(float), T["step"])
    lx, lz, ly = -0.55, -0.45, 0.70
    nrm = np.sqrt(gx * gx + gz * gz + 1)
    shade = np.clip((-gx * lx - gz * lz + ly) / nrm, 0, 1)
    hn = (H - H.min()) / (H.max() - H.min())
    r = (0.25 + 0.55 * hn) * (0.35 + 0.75 * shade)
    g = (0.40 + 0.40 * (1 - hn)) * (0.35 + 0.75 * shade)
    b = (0.22 + 0.15 * hn) * (0.35 + 0.75 * shade)
    img = np.stack([r, g, b], -1)
    # 等高線（每 2 m）
    lvl = np.floor(H / 2.0)
    edge = (lvl[:-1, :-1] != lvl[1:, :-1]) | (lvl[:-1, :-1] != lvl[:-1, 1:])
    img[:-1, :-1][edge] *= 0.55
    pil = Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8))
    sc = 4
    pil = pil.resize((pil.width * sc // 2, pil.height * sc // 2), Image.LANCZOS)
    dr = ImageDraw.Draw(pil)

    def tp(x, z):
        return ((x - T["x0"]) / T["step"] * sc / 2, (z - T["z0"]) / T["step"] * sc / 2)

    dr.rectangle([*tp(L.PLAY["x0"], L.PLAY["z0"]), *tp(L.PLAY["x1"], L.PLAY["z1"])], outline=(255, 60, 60))
    poly = [tp(*p) for p in L.chaikin(L.PLATEAU, 2)]
    dr.polygon(poly, outline=(255, 255, 0))
    path = [tp(p[0], p[1]) for p in L.catmull_rom(L.APPROACH, 2.0)]
    dr.line(path, fill=(0, 255, 255), width=2)
    dr.line([tp(0, L.Z_FOOT), tp(0, L.stair_plan()[2])], fill=(255, 0, 255), width=3)
    for nm, (x, z) in L.PLACE.items():
        cx, cz = tp(x, z)
        dr.ellipse([cx - 5, cz - 5, cx + 5, cz + 5], outline=(255, 255, 255))
        dr.text((cx + 7, cz - 6), nm, fill=(255, 255, 255))
    p = L.POND
    cx, cz = tp(p["cx"], p["cz"])
    dr.ellipse([cx - 8, cz - 5, cx + 8, cz + 5], outline=(80, 160, 255))
    pil.save(os.path.join(GEN, "_preview_height.png"))
    # 坡度圖
    sl = np.clip(deg / 45.0, 0, 1)
    simg = np.stack([sl, 1 - np.abs(sl - 0.5) * 2, 1 - sl], -1)
    sp = Image.fromarray((simg * 255).astype(np.uint8)).resize(pil.size, Image.LANCZOS)
    sp.save(os.path.join(GEN, "_preview_slope.png"))
    Image.fromarray(mask[::-1][::-1], "RGBA").convert("RGB").resize((512, 640)).save(os.path.join(GEN, "_preview_mask.png"))
    print("[TERRAIN] previews written")


if __name__ == "__main__":
    main()

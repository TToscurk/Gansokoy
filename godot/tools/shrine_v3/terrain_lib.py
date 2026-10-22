"""博麗神社 v3 地形函式庫（numpy，全部向量化）。
regional(x,z)：大範圍自然地形（近／中／遠三層共用 → 層間接縫高度一致）。
near_height(x,z)：regional ＋ 只在近景範圍內生效的施作（平台整平、石階切填、獸道、池塘棚地、西崖）。
所有施作的影響範圍都在近景矩形內縮 12 m 以內 → 近景邊界高度＝regional。
"""
import math
import numpy as np
import layout as L

P = L.P


# ───────────────────────── 雜訊 ─────────────────────────
def _fade(t):
    return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)


def _grad(ix, iz, seed):
    n = (ix * 374761393 + iz * 668265263 + seed * 144269504) & 0xFFFFFFFF
    n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
    n = n ^ (n >> 16)
    a = (n & 0xFFFF).astype(np.float64) * (2.0 * math.pi / 65536.0)
    return np.cos(a), np.sin(a)


def gnoise(x, z, seed=0):
    """梯度雜訊，約 [-1, 1]。"""
    x = np.asarray(x, dtype=np.float64)
    z = np.asarray(z, dtype=np.float64)
    xi = np.floor(x).astype(np.int64)
    zi = np.floor(z).astype(np.int64)
    xf = x - xi
    zf = z - zi
    u = _fade(xf)
    v = _fade(zf)

    def d(ox, oz):
        gx, gz = _grad(xi + ox, zi + oz, seed)
        return gx * (xf - ox) + gz * (zf - oz)

    a = d(0, 0) + (d(1, 0) - d(0, 0)) * u
    b = d(0, 1) + (d(1, 1) - d(0, 1)) * u
    return (a + (b - a) * v) * 1.41421356


def fbm(x, z, scale, octaves=5, gain=0.5, lac=2.03, seed=0):
    s = 0.0
    amp = 1.0
    norm = 0.0
    f = 1.0 / scale
    for o in range(octaves):
        s = s + amp * gnoise(x * f, z * f, seed + o * 17)
        norm += amp
        amp *= gain
        f *= lac
    return s / norm


def ridged(x, z, scale, octaves=5, seed=0):
    s = 0.0
    amp = 1.0
    norm = 0.0
    f = 1.0 / scale
    w = 1.0
    for o in range(octaves):
        n = 1.0 - np.abs(gnoise(x * f, z * f, seed + o * 31))
        n = n * n * w
        w = np.clip(n * 1.6, 0.0, 1.0)
        s = s + amp * n
        norm += amp
        amp *= 0.5
        f *= 2.1
    return s / norm


def smoothstep(e0, e1, x):
    t = np.clip((np.asarray(x, dtype=np.float64) - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def smin(a, b, k):
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
    return b + (a - b) * h - k * h * (1.0 - h)


def smax(a, b, k):
    return -smin(-a, -b, k)


# ───────────────────────── 幾何工具 ─────────────────────────
def seg_dist(px, pz, ax, az, bx, bz):
    """點到線段距離與參數 t。"""
    vx, vz = bx - ax, bz - az
    L2 = vx * vx + vz * vz
    t = np.clip(((px - ax) * vx + (pz - az) * vz) / max(L2, 1e-12), 0.0, 1.0)
    dx = px - (ax + t * vx)
    dz = pz - (az + t * vz)
    return np.sqrt(dx * dx + dz * dz), t


def polyline_dist(px, pz, pts):
    """到折線的最短距離、所在線段 index、段內 t。"""
    best = np.full(np.shape(px), np.inf)
    bi = np.zeros(np.shape(px), dtype=np.int32)
    bt = np.zeros(np.shape(px))
    for i in range(len(pts) - 1):
        d, t = seg_dist(px, pz, pts[i][0], pts[i][1], pts[i + 1][0], pts[i + 1][1])
        m = d < best
        best = np.where(m, d, best)
        bi = np.where(m, i, bi)
        bt = np.where(m, t, bt)
    return best, bi, bt


def poly_sdf(px, pz, poly):
    """多邊形有號距離（內負外正）。poly 首尾不必重複。"""
    pts = list(poly)
    if pts[0] != pts[-1]:
        pts = pts + [pts[0]]
    d, _, _ = polyline_dist(px, pz, pts)
    inside = np.zeros(np.shape(px), dtype=bool)
    for i in range(len(pts) - 1):
        x1, z1 = pts[i]
        x2, z2 = pts[i + 1]
        c = ((z1 > pz) != (z2 > pz)) & (px < (x2 - x1) * (pz - z1) / ((z2 - z1) if z2 != z1 else 1e-12) + x1)
        inside ^= c
    return np.where(inside, -d, d)


# ───────────────────────── 大範圍地形 ─────────────────────────
SUMMIT = (330.0, -720.0)
_CAL = None   # 讓平台中心 regional ≈ P + 1.0（第一次呼叫時自動校正）


def _regional_raw(x, z):
    x = np.asarray(x, dtype=np.float64)
    z = np.asarray(z, dtype=np.float64)
    # 1) 神社所在的山（主峰在東北）：平滑錐體＋山脊雜訊
    dx = x - SUMMIT[0]
    dz = z - SUMMIT[1]
    d = np.sqrt(dx * dx + dz * dz)
    warp = 120.0 * fbm(x + 3000.0, z - 1700.0, 900.0, 3, seed=5)
    dd = np.maximum(d + warp, 0.0)
    mtn = -62.0 + 372.0 * np.exp(-np.power(dd / 690.0, 1.35))
    # 1b) 台地：以平台中心為圓心，把山坡的起伏壓扁（中心 0.3 倍 → 95 m 外恢復原坡）——
    #     神社是山肩上自然的緩台，不是硬切出來的平面；切填量也因此變小
    bx, bz = 0.0, -10.0
    rb = np.sqrt((x - bx) ** 2 + ((z - bz) * 0.9) ** 2)
    c0 = -62.0 + 372.0 * math.exp(-math.pow(max(math.hypot(bx - SUMMIT[0], bz - SUMMIT[1]), 0.0) / 690.0, 1.35))
    kb = 0.30 + 0.70 * smoothstep(22.0, 95.0, rb)
    mtn = c0 + (mtn - c0) * kb
    # 2) 西側大谷：谷軸 x_v(z)，西側距離 xw；谷頂在神社西緣（x≈−24）附近，上段陡、近谷底緩
    # 崖頂線在神社西緣最靠東（x≈−26，「船首」狀突出），往南、往北都向西退 → 神社所在是一塊向西突出的台地
    xv_top = (-26.0 - 0.55 * np.maximum(z - 12.0, 0.0) - 0.50 * np.maximum(-40.0 - z, 0.0)
              + 5.0 * np.sin(z / 47.0 + 0.6) * smoothstep(60.0, 200.0, np.abs(z)))
    xw = xv_top - x  # >0 = 西崖以西
    drop = 168.0 * (1.0 - np.exp(-np.maximum(xw, 0.0) / 150.0))
    valley_floor = -146.0 + 18.0 * fbm(x, z, 600.0, 3, seed=11)
    h = mtn - drop
    h = smax(h, valley_floor, 18.0)
    # 3) 南側：石階所在的坡繼續往下 → 山麓丘陵
    south = 46.0 * smoothstep(20.0, 420.0, z) + 0.02 * np.maximum(z - 420.0, 0.0)
    h = h - south * (1.0 - smoothstep(200.0, 900.0, -x))  # 西谷已經很低，不重複扣
    # 3b) 平台南緣的前坡（石階段）：z 8→50 多落 8.5 m；石階腳以南（z 52→105）淡回 → 山腳下一段較緩的林地（獸道）
    #     橫向只在中軸 ±110 m（不切整張圖）
    front = 8.5 * smoothstep(8.0, 50.0, z) * (1.0 - smoothstep(52.0, 105.0, z)) * np.exp(-np.square(x / 110.0))
    h = h - front
    # 4) 起伏：近處小、遠處大（以神社為中心的距離權重）
    r = np.sqrt(x * x + z * z)
    amp = 1.2 + 26.0 * smoothstep(60.0, 1400.0, r)
    h = h + amp * fbm(x, z, 260.0, 5, seed=3)
    h = h + 0.35 * fbm(x, z, 18.0, 3, seed=9) * (1.0 + 2.0 * smoothstep(40.0, 200.0, r))
    # 5) 遠景（刻意不圍成一圈）：
    #    北／東＝神社背後的主山塊與更高的山（背山，封閉側）；
    #    西＝谷底延伸到 2.5 km 外，接一列「低、斷續」的丘陵（有缺口），再過去是平原到地平線；
    #    西北＝妖怪之山（孤立高峰，約 6.7 km 外，地標）；
    #    南／西南＝山麓一路降到平原（開放側，地平線是霧中的低丘）。
    north_rng = smoothstep(-1600.0, -3400.0, z) * smoothstep(-2600.0, -600.0, x) * (240.0 + 420.0 * ridged(x, z, 1700.0, 5, seed=29))
    east_rng = smoothstep(1400.0, 3200.0, x) * smoothstep(2500.0, 300.0, z) * (200.0 + 360.0 * ridged(x, z, 1500.0, 5, seed=31))
    gaps = smoothstep(0.38, 0.62, fbm(x, z, 1400.0, 3, seed=37) * 0.5 + 0.5)
    west_hills = smoothstep(-2200.0, -2900.0, x) * (1.0 - smoothstep(-4600.0, -5600.0, x)) * gaps * (90.0 + 200.0 * ridged(x, z, 900.0, 4, seed=21))
    ym = (-5200.0, -4300.0)
    dym = np.sqrt((x - ym[0]) ** 2 + (z - ym[1]) ** 2)
    youkai = 980.0 * np.exp(-np.power(dym / 2300.0, 1.6)) * (0.85 + 0.15 * ridged(x, z, 700.0, 4, seed=41))
    far = np.maximum.reduce([north_rng, east_rng, west_hills, youkai])
    h = h + far
    # 6) 地平線外緣：8 km 外漸降（像地球曲率），網格邊緣落在視線地平線以下、霧裡看不到斷面
    rr = np.maximum(np.abs(x), np.abs(z))
    h = h - 420.0 * smoothstep(7200.0, 9000.0, rr)
    return h


def regional(x, z):
    global _CAL
    if _CAL is None:
        _CAL = (P + 1.0) - float(_regional_raw(np.array([0.0]), np.array([-8.0]))[0])
    return _regional_raw(x, z) + _CAL


# ───────────────────────── 近景施作 ─────────────────────────
def _stair_line_y(z):
    """石階踏面下緣連線（每段踏面前緣的高度，線性插值）：地形必須在此之下。"""
    zf, segs = L.Z_FOOT, L._SEGS
    zs = [L.STAIR['z_top']] + [s[1] for s in segs] + [zf]
    ys = [P] + [s[2] for s in segs] + [L.Y_FOOT]
    return np.interp(z, zs, ys)


def _path_design(px, pz, pts3):
    """沿 3D 折線（x, z, y）的距離、設計高。"""
    pts = [(p[0], p[1]) for p in pts3]
    d, i, t = polyline_dist(px, pz, pts)
    y0 = np.array([p[2] for p in pts3[:-1]])[i]
    y1 = np.array([p[2] for p in pts3[1:]])[i]
    return d, y0 + (y1 - y0) * t


_BEAST = None


def beast_profile():
    """獸道設計線：沿 L.BEAST_PATH 每 1 m 取 regional 高度、平滑（±6 m 視窗）、略切 0.25 m；
    起點 6 m 內接到石階腳高度 Y_FOOT。回傳 [(x, z, y)]。"""
    global _BEAST
    if _BEAST is not None:
        return _BEAST
    pts = [(p[0], p[1]) for p in L.BEAST_PATH]
    dense = []
    for i in range(len(pts) - 1):
        ax, az = pts[i]
        bx, bz = pts[i + 1]
        n = max(int(math.hypot(bx - ax, bz - az)), 1)
        for k in range(n):
            t = k / n
            dense.append((ax + (bx - ax) * t, az + (bz - az) * t))
    dense.append(pts[-1])
    xs = np.array([p[0] for p in dense])
    zs = np.array([p[1] for p in dense])
    hs = regional(xs, zs) - 0.25
    ker = np.ones(13) / 13.0
    hp = np.pad(hs, 6, mode='edge')
    hs = np.convolve(hp, ker, mode='valid')
    s = np.concatenate([[0.0], np.cumsum(np.hypot(np.diff(xs), np.diff(zs)))])
    w = smoothstep(0.0, 6.0, s)
    hs = L.Y_FOOT * (1.0 - w) + hs * w
    _BEAST = [(float(a), float(b), float(c)) for a, b, c in zip(xs, zs, hs)]
    return _BEAST


def near_edits(x, z, h):
    """在 regional 高度 h 上施作。回傳 (h_new, masks dict)。"""
    m = {}
    # 0) 施作權重：近景矩形內縮 12 m 處開始淡出
    nr = L.NEAR
    edge = np.minimum.reduce([x - nr['x0'], nr['x1'] - x, z - nr['z0'], nr['z1'] - z])
    wfade = smoothstep(4.0, 16.0, edge)

    # 1) 平台：整平到 P（微起伏 ±4 cm、往南 0.4% 排水），北／東用寬過渡（自然後坡），南側短過渡（填方坡）
    sd = poly_sdf(x, z, L.PLATFORM)
    micro = 0.04 * fbm(x, z, 6.0, 2, seed=41) + 0.004 * (z + 10.0) * -1.0 * 0.1
    band = np.where(z < -20.0, 16.0, np.where(x > 18.0, 14.0, 5.5))
    wp = 1.0 - smoothstep(0.0, band, sd)
    flat = P + micro
    h1 = h + (flat - h) * wp
    m['platform'] = (sd < 0.0).astype(np.float32)

    # 2) 池塘棚地（P+2.5）＋從前庭上去的緩坡
    pc = L.POND
    dp = np.sqrt((x - pc['cx']) ** 2 + (z - pc['cz']) ** 2)
    ws = 1.0 - smoothstep(pc['shelf_r'] - 3.0, pc['shelf_r'] + 9.0, dp)
    shelf = pc['shelf_y'] + 0.05 * fbm(x, z, 5.0, 2, seed=43)
    h1 = h1 + (shelf - h1) * ws
    rd, ri, rt = polyline_dist(x, z, L.POND_RAMP + [(pc['cx'] - 4.0, pc['cz'] + 5.5)])
    ramp_y = P + (pc['shelf_y'] - P) * np.clip((ri + rt) / len(L.POND_RAMP), 0.0, 1.0)
    wr = 1.0 - smoothstep(1.4, 4.5, rd)
    h1 = h1 + (ramp_y - h1) * wr * (1.0 - ws * 0.3)

    # 3) 池塘：自然岸線（橢圓＋擾動），底部碗形，岸坡
    th = math.radians(pc['rot_deg'])
    lx = (x - pc['cx']) * math.cos(th) + (z - pc['cz']) * math.sin(th)
    lz = -(x - pc['cx']) * math.sin(th) + (z - pc['cz']) * math.cos(th)
    ang = np.arctan2(lz / pc['rz'], lx / pc['rx'])
    wob = 1.0 + 0.13 * np.sin(2.0 * ang + 0.7) + 0.08 * np.sin(3.0 * ang - 1.2) + 0.05 * np.sin(5.0 * ang + 2.0)
    rn = np.sqrt((lx / pc['rx']) ** 2 + (lz / pc['rz']) ** 2) / wob   # 1 = 水線
    bottom = pc['level'] - pc['depth'] * np.clip(1.0 - rn * rn, 0.0, 1.0) - 0.12
    bank = pc['level'] + 0.10 + (rn - 1.0) * 1.1
    pond_h = np.where(rn < 1.0, bottom, np.minimum(bank, h1))
    wpond = 1.0 - smoothstep(1.0, 1.6, rn)
    h1 = h1 + (np.minimum(pond_h, h1) - h1) * wpond
    m['water'] = (rn < 1.0).astype(np.float32)

    # 4) 西崖：崖頂線＝柵欄線外 1.3 m；崖面 7 m 內落 17 m，再接 regional 的西坡
    fence = [(p[0] - 1.3, p[1]) for p in L.FENCE_W]
    fence = [(fence[0][0] + 2.0, fence[0][1] + 6.0)] + fence + [(fence[-1][0] + 3.0, fence[-1][1] - 9.0)]
    dc, ci, ct = polyline_dist(x, z, fence)
    # 外側判定：在折線西側（以法向量）
    side = np.zeros_like(x)
    for i in range(len(fence) - 1):
        ax, az = fence[i]
        bx, bz = fence[i + 1]
        cr = (bx - ax) * (z - az) - (bz - az) * (x - ax)
        side = np.where(ci == i, cr, side)
    out = side < 0.0          # 折線由南往北走，左側（西）為外
    endfade = smoothstep(0.0, 0.18, (ci + ct) / (len(fence) - 1)) * (1.0 - smoothstep(0.82, 1.0, (ci + ct) / (len(fence) - 1)))
    dco = np.where(out, dc, 0.0)
    # 崖高沿崖線變化（6–12 m，不是一整道等高的牆），崖帶 10 m 內落完，之後接 ~32° 的林坡（可長灌木／小樹）
    drop1 = 9.0 + 3.0 * fbm(x, z, 14.0, 2, seed=53)
    cliff = P - 0.25 - drop1 * smoothstep(0.0, 10.0, dco) - 0.62 * np.maximum(dco - 3.0, 0.0)
    rough = 1.3 * fbm(x, z, 3.0, 3, seed=47) * smoothstep(0.5, 3.0, dco) * (1.0 - smoothstep(10.0, 16.0, dco))
    wc = endfade * out * (1.0 - smoothstep(26.0, 40.0, dco))
    h1 = h1 + (np.minimum(h1, cliff + rough) - h1) * wc
    # 崖腳以外：regional 的西坡在此局部比 50° 還陡（30 m→7 m／17 m），墊到「崖線再低 3 m」為止，讓崖下是 ~32° 林坡而非第二道牆
    wfill = wc * smoothstep(8.0, 12.0, dco)
    h1 = h1 + (np.maximum(h1, cliff - 3.0) - h1) * wfill
    m['cliff'] = (wc * smoothstep(0.8, 2.5, dco) * (1.0 - smoothstep(8.0, 11.0, dco))).astype(np.float32)

    # 5) 石階：沿中軸的「脊」——踏面「內角」連線（＝前緣線再低一級 rise）下 0.12 m：地形永遠藏在石塊下，
    #    不會從每一級的內角冒出來（前緣線−0.12 會在內角高出踏面 rise−0.12≈5 cm）。兩側 1.6–5 m 回到自然坡。
    st = L.STAIR
    on = (z > st['z_top'] - 1.0) & (z < L.Z_FOOT + 3.0)
    ys = _stair_line_y(np.clip(z, st['z_top'], L.Z_FOOT)) - 0.12 - st['rise']
    ax_ = np.abs(x - st['x'])
    ws_ = (1.0 - smoothstep(st['width'] * 0.5 + 0.25, st['width'] * 0.5 + 4.5, ax_)) * on
    ws_ = ws_ * (1.0 - smoothstep(L.Z_FOOT + 0.5, L.Z_FOOT + 3.0, z)) * (1.0 - smoothstep(st['z_top'] - 0.2, st['z_top'] - 1.0, z) * (z < st['z_top']))
    # 兩側坡面略低於階線（脊狀），石階往下時兩旁視野開
    side_y = ys + 0.25 - 0.22 * np.maximum(ax_ - st['width'] * 0.5, 0.0)
    target = np.where(ax_ < st['width'] * 0.5 + 0.25, ys, np.minimum(side_y, h1 + 0.6))
    h1 = h1 + (target - h1) * ws_
    m['stair'] = ((ax_ < st['width'] * 0.5 + 0.3) & on & (z <= L.Z_FOOT)).astype(np.float32)

    # 6) 石階腳廣場 ＋ 獸道（切成 2.5 m 寬的平路，兩側 3 m 回自然坡）
    df = np.sqrt((x - 0.0) ** 2 + (z - (L.Z_FOOT + 2.2)) ** 2)
    wf = 1.0 - smoothstep(3.2, 6.5, df)
    h1 = h1 + (L.Y_FOOT - 0.02 - h1) * wf
    bd, by = _path_design(x, z, beast_profile())
    wb = 1.0 - smoothstep(L.BEAST_HALF_W, L.BEAST_HALF_W + 3.2, bd)
    h1 = h1 + (by + 0.04 * fbm(x, z, 2.0, 2, seed=53) - h1) * wb
    m['beast'] = (1.0 - smoothstep(L.BEAST_HALF_W - 0.3, L.BEAST_HALF_W + 0.5, bd)).astype(np.float32)

    # 7) 境內小徑（後山林徑）：橫坡切平，縱坡由地形決定（取沿線平滑高度）
    for key in ('grove', 'pond_w'):
        pts = L.PATHS[key]
        pd, pi, pt = polyline_dist(x, z, pts)
        # 沿線設計高＝沿線原地形的平滑值（取各點 regional 後的 h1 近似：以兩端點高度內插）
        hy = []
        for (px_, pz_) in pts:
            hy.append(float(_sample(h1, x, z, px_, pz_)))
        y0 = np.array(hy[:-1])[pi]
        y1 = np.array(hy[1:])[pi]
        py = y0 + (y1 - y0) * pt
        wpth = (1.0 - smoothstep(L.PATH_HALF_W, L.PATH_HALF_W + 2.8, pd)) * 0.85
        h1 = h1 + (py - h1) * wpth

    h_out = h + (h1 - h) * wfade
    return h_out, m


_SAMPLE_CACHE = {}


def _sample(hgrid, xg, zg, px, pz):
    """在目前的網格上找最近點高度（只供小徑設計高使用）。"""
    if np.ndim(hgrid) == 0:
        return float(hgrid)
    # xg, zg 是同形網格
    xs = xg[0, :] if np.ndim(xg) == 2 else xg
    zs = zg[:, 0] if np.ndim(zg) == 2 else zg
    if np.ndim(hgrid) == 2:
        i = int(np.clip(np.searchsorted(xs, px), 0, len(xs) - 1))
        j = int(np.clip(np.searchsorted(zs, pz), 0, len(zs) - 1))
        return hgrid[j, i]
    return float(np.mean(hgrid))


def grid(spec):
    nx = int(round((spec['x1'] - spec['x0']) / spec['step'])) + 1
    nz = int(round((spec['z1'] - spec['z0']) / spec['step'])) + 1
    xs = spec['x0'] + np.arange(nx) * spec['step']
    zs = spec['z0'] + np.arange(nz) * spec['step']
    X, Z = np.meshgrid(xs, zs)
    return X, Z


def near_height_grid():
    X, Z = grid(L.NEAR)
    h = regional(X, Z)
    h2, masks = near_edits(X, Z, h)
    return X, Z, h2, h, masks

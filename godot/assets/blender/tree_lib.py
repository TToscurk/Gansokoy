# 樹木產生器（**唯一一份**）—— 遞迴分枝骨架 + 枝端葉團。
#
# 為什麼這個檔案存在：以前有兩份互不相干的樹產生器 ——
#   * make_hieda.py：遞迴分枝，稗田邸的楓與松，**改了八版才對**
#   * make_trees.py：圓錐樹幹 + 疊 2~3 顆壓扁的球（棒棒糖）
# 稗田邸那八版的修正**從來沒有回流**到另一份，所以每開一張新圖、每加一種
# 新樹，棒棒糖就再生一次（人間之里的櫻與背景綠樹就是這樣長出來的）。
# 兩份合併成這一份之後，樹的骨架只有一個實作，修一次全圖都吃得到。
#
# 呼叫端只要提供一個 builder（見下面的 Builder 協定），本檔不 import bpy ——
# 幾何是純 Python，Blender 只負責把 verts/faces/色 灌進 mesh。
#
# ── Builder 協定 ────────────────────────────────────────────────
#   tri(a, b, c, col, flip=False)        單面三角形
#   quad(a, b, c, d, col, flip=False)    單面四邊形
#   tri2(a, b, c, col)                   **雙面**三角形（葉片用）
#   use(slot)                            切換材質槽："bark" / "foliage"
# `use` 是給「要分材質槽」的呼叫端用的（make_trees.py 要匯出 bark/foliage
# 兩個 surface，Godot 端的 tree_mesh / _sakura_mesh 靠 surface 索引分材質）。
# 顏色全在頂點色裡的呼叫端（make_hieda.py）給一個 no-op 就好。
import math
import random


def mix(a, b, t):
    return tuple(a[i] * (1.0 - t) + b[i] * t for i in range(3))


def norm3(v):
    l = math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]) or 1.0
    return (v[0] / l, v[1] / l, v[2] / l)


def basis(d):
    """給方向 d 一組正交基底 (u, v)。"""
    ref = (0.0, 0.0, 1.0) if abs(d[2]) < 0.9 else (1.0, 0.0, 0.0)
    u = norm3((d[1] * ref[2] - d[2] * ref[1], d[2] * ref[0] - d[0] * ref[2],
               d[0] * ref[1] - d[1] * ref[0]))
    v = (d[1] * u[2] - d[2] * u[1], d[2] * u[0] - d[0] * u[2], d[0] * u[1] - d[1] * u[0])
    return u, v


def bend(d, az, ang):
    """把方向 d 依方位角 az 偏開 ang 弧度。"""
    u, v = basis(d)
    ca, sa = math.cos(ang), math.sin(ang)
    cz, sz = math.cos(az), math.sin(az)
    return norm3((d[0] * ca + (u[0] * cz + v[0] * sz) * sa,
                  d[1] * ca + (u[1] * cz + v[1] * sz) * sa,
                  d[2] * ca + (u[2] * cz + v[2] * sz) * sa))


def tube(bld, pts, radii, col, sides=5):
    """沿折線掃的錐形管（枝幹）。每節點各自取正交基底 —— 會有一點扭轉，
    但枝這種細長物件看不出來，省掉 parallel transport。"""
    n = len(pts)
    rings = []
    for i, p in enumerate(pts):
        a, b = pts[max(i - 1, 0)], pts[min(i + 1, n - 1)]
        t = norm3((b[0] - a[0], b[1] - a[1], b[2] - a[2]))
        u, v = basis(t)
        ring = []
        for k in range(sides):
            ang = k / sides * math.tau
            cu, cv = math.cos(ang) * radii[i], math.sin(ang) * radii[i]
            ring.append((p[0] + u[0] * cu + v[0] * cv,
                         p[1] + u[1] * cu + v[1] * cv,
                         p[2] + u[2] * cu + v[2] * cv))
        rings.append(ring)
    for i in range(n - 1):
        for k in range(sides):
            k2 = (k + 1) % sides
            bld.quad(rings[i][k], rings[i][k2], rings[i + 1][k2], rings[i + 1][k], col)


def leaf_tuft(bld, rng, org, nrm, size, c_lo, c_hi, n_leaf=3):
    """一叢 n 片**短而寬**的葉。

    ⚠ 寬度要接近長度（0.72~0.95×）。`make_hedge.py` 踩過並寫在註解裡：
    細長三角形的葉子撒稀一點，整叢會變成仙人掌 —— 葉子完全沒有把輪廓
    打碎的效果。"""
    nx, ny, nz = nrm
    ref = (0.0, 0.0, 1.0) if abs(nz) < 0.9 else (1.0, 0.0, 0.0)
    tx, ty, tz = ny * ref[2] - nz * ref[1], nz * ref[0] - nx * ref[2], nx * ref[1] - ny * ref[0]
    tl = math.sqrt(tx * tx + ty * ty + tz * tz) or 1.0
    tx, ty, tz = tx / tl, ty / tl, tz / tl
    bx, by, bz = ny * tz - nz * ty, nz * tx - nx * tz, nx * ty - ny * tx
    for k in range(n_leaf):
        a = rng.uniform(0.0, math.tau) + k * math.tau / n_leaf
        ln = size * rng.uniform(0.85, 1.30)
        wd = ln * rng.uniform(0.72, 0.95)
        dx = nx + (tx * math.cos(a) + bx * math.sin(a)) * 0.85
        dy = ny + (ty * math.cos(a) + by * math.sin(a)) * 0.85
        dz = nz + (tz * math.cos(a) + bz * math.sin(a)) * 0.85
        dl = math.sqrt(dx * dx + dy * dy + dz * dz) or 1.0
        tip = (org[0] + dx / dl * ln, org[1] + dy / dl * ln, org[2] + dz / dl * ln)
        p1 = (org[0] + tx * wd * 0.5, org[1] + ty * wd * 0.5, org[2] + tz * wd * 0.5)
        p2 = (org[0] - tx * wd * 0.5, org[1] - ty * wd * 0.5, org[2] - tz * wd * 0.5)
        bld.tri2(p1, p2, tip, mix(c_lo, c_hi, rng.random() ** 0.7))


def canopy_from_tips(bld, rng, tips, spread, n_tuft, leaf, c_hull, c_lo, c_hi,
                     n_leaf=2, bare=0.32):
    """樹冠 = 所有枝端**周圍體積**裡的葉子聯集，不是「每個枝端一顆殼」。

    ⚠ 這是第五版才走對的路。v4 是每個枝端做一顆凹凸殼再撒葉，結果每團
    都是「深色核心 + 一圈放射狀的葉」—— 像海膽不像樹。原因是密度算不過來：
    一顆半徑 0.56 的殼表面約 3m²，要蓋滿得撒數百片葉（make_hedge.py 實測
    要 276 片/m²），24 顆殼乘起來根本撒不起，於是殼永遠露著。

    改成把葉子直接撒進枝端周圍的**體積**：密度集中在冠的外緣（真正形成
    剪影的地方），而不是平均攤在每顆殼的表面上。同樣的面數，覆蓋率完全
    不同。

    ⚠ 不放暗色團塊。v5 在粗枝端擺了 5 顆暗殼擋光，結果它們在葉子之間
    露成一顆顆深色多面體 —— 像樹上掛了幾個鳥巢。擋光改用**顏色**做：
    靠近枝端（冠內部）的葉子往暗色混，外緣的保持鮮亮。

    `bare`：葉子沿枝的哪一段開始長（0.32 = 外側 68%）。留一段裸枝在葉團
    外面，剪影才不是一坨實心的雲。"""
    if not tips:
        return
    cx = sum(t[0][0] for t in tips) / len(tips)
    cy = sum(t[0][1] for t in tips) / len(tips)
    cz = sum(t[0][2] for t in tips) / len(tips)
    ws = [t[2] for t in tips]
    tot = sum(ws) or 1.0
    for _ in range(n_tuft):
        r = rng.random() * tot
        acc = 0.0
        pick = tips[0]
        for t, wq in zip(tips, ws):
            acc += wq
            if acc >= r:
                pick = t
                break
        # 葉子：挑一枝，沿它的**外段**取點再偏移。只堆在末端一點的話，
        # 枝條會長長一段光禿禿地露在外面 —— 真的樹葉子是長在枝的
        # 外三分之一整段上的。
        ft = rng.uniform(bare, 1.0)
        tp = (pick[1][0] + (pick[0][0] - pick[1][0]) * ft,
              pick[1][1] + (pick[0][1] - pick[1][1]) * ft,
              pick[1][2] + (pick[0][2] - pick[1][2]) * ft)
        # ⚠ 半徑取 u^0.45 而不是球內均勻取樣。均勻取樣有一半的葉子落在
        # 內部被自己擋住 —— 對剪影完全沒貢獻，等於白花面數。偏外側取樣
        # 讓同樣的葉數集中在真正形成輪廓的地方（但仍不是純球面，
        # 純球面會排成一層殼、內部空掉）。
        _d = norm3((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1)))
        _rad = rng.random() ** 0.45
        ox, oy, oz = _d[0] * _rad, _d[1] * _rad, _d[2] * _rad
        sc = spread * 1.16
        p_ = (tp[0] + ox * sc, tp[1] + oy * sc, tp[2] + oz * sc * 0.82)
        nrm = norm3((p_[0] - cx, p_[1] - cy, (p_[2] - cz) * 0.7 + 0.25))
        # 內深外亮：rad 小 = 貼著枝端 = 冠內部
        lo = mix(c_hull, c_lo, min(1.0, 0.30 + _rad * 0.95))
        hi = mix(c_lo, c_hi, min(1.0, _rad * 1.15))
        leaf_tuft(bld, rng, p_, nrm, leaf, lo, hi, n_leaf=n_leaf)


def canopy_pads(bld, rng, tips, n_tuft, leaf, c_hull, c_lo, c_hi,
                flat=0.34, bulk=1.30, rmin=0.30, n_leaf=2):
    """松專用的樹冠：**幾團扁平的葉盤**，不是一整片平均的葉雲。

    ⚠ 一開始松跟楓共用 canopy_from_tips（葉子平均撒在每個枝端周圍）。
    楓對，松錯 —— 針葉小，同樣的 ntuft 攤到 48 個枝端上每處都只剩十幾片，
    整棵讀成「闊葉樹幼苗」，主幹還會有一段光禿禿的鞭子露在葉子上方。

    庭木的松（仕立て松）本來就不是平均的：葉子被剪成幾團**扁平的段**，
    段與段之間露出彎曲的枝，最頂上那團是天芯。所以這裡先把枝端依
    pad_depth 的祖先分組，每組塌成一個扁球（z 只有 flat 倍），葉量按組
    的枝長權重分。同樣的面數集中成團 → 密；團之間留空 → 骨架看得見。"""
    groups = {}
    for t in tips:
        groups.setdefault(t[3], []).append(t)
    if not groups:
        return
    tot_w = sum(sum(t[2] for t in ts) for ts in groups.values()) or 1.0
    for ts in groups.values():
        gx = sum(t[0][0] for t in ts) / len(ts)
        gy = sum(t[0][1] for t in ts) / len(ts)
        gz = sum(t[0][2] for t in ts) / len(ts)
        # 盤的半徑取「枝端離組心的散佈」——枝張得開的那組盤就大
        sp = sum(math.dist(t[0], (gx, gy, gz)) for t in ts) / len(ts)
        rad = max(rmin, sp * bulk) * rng.uniform(0.86, 1.15)
        # 每盤各自傾斜一點、扁度也不同。全部水平等厚的話會讀成「一疊盤子」
        fl = flat * rng.uniform(0.82, 1.30)
        til, taz = rng.uniform(0.06, 0.26), rng.uniform(0.0, math.tau)
        tx, ty = math.cos(taz) * til, math.sin(taz) * til
        w = sum(t[2] for t in ts)
        n = max(14, int(n_tuft * w / tot_w))
        for _ in range(n):
            _d = norm3((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1)))
            u = rng.random() ** 0.40
            ox, oy = _d[0] * rad * u, _d[1] * rad * u
            # 盤面上拱下平：頂面往上鼓一點，底面幾乎不掉下去
            oz = _d[2] * rad * u * fl * (1.35 if _d[2] > 0 else 0.62)
            p_ = (gx + ox, gy + oy, gz + oz + ox * tx + oy * ty)
            nrm = norm3((ox * 0.55, oy * 0.55, oz * 0.4 + rad * 0.62))
            # 內暗外亮 × 上亮下暗：松的段是「上面一層受光、下面全是陰影」
            t_up = 0.5 + oz / (rad * fl * 2.0 + 1e-6) * 0.5
            k = min(1.0, 0.16 + u * 0.72 + max(0.0, t_up - 0.5) * 0.66)
            lo = mix(c_hull, c_lo, k)
            hi = mix(c_lo, c_hi, min(1.0, (u * 0.70 + t_up * 0.75)))
            leaf_tuft(bld, rng, p_, nrm, leaf, lo, hi, n_leaf=n_leaf)


def grow(bld, tips, p, d, r, ln, depth, cfg, rng, gid=None, ctr=None):
    """一段枝：邊長邊收細，末端分岔；到底層就記下枝端位置給葉團用。"""
    segs = cfg.get("segs", 3)
    c_trunk = cfg.get("trunk_col", C_TRUNK)
    c_twig = cfg.get("twig_col", C_TWIG)
    pts, rr = [p], [r]
    if depth == 0:
        # 樹頭外張：真的樹幹在地面附近會擴根盤，等徑圓柱插進土裡像電線桿
        pts = [p, (p[0] + d[0] * ln * 0.10, p[1] + d[1] * ln * 0.10,
                   p[2] + d[2] * ln * 0.10)]
        rr = [r * 1.42, r]
    cur_p, cur_d = pts[-1], d
    ups = cfg["up"]
    up_k = ups[min(depth, len(ups) - 1)]
    for i in range(segs):
        cur_d = norm3((cur_d[0] + rng.uniform(-cfg["wig"], cfg["wig"]),
                       cur_d[1] + rng.uniform(-cfg["wig"], cfg["wig"]),
                       cur_d[2] + up_k))
        step = ln / segs
        cur_p = (cur_p[0] + cur_d[0] * step, cur_p[1] + cur_d[1] * step,
                 cur_p[2] + cur_d[2] * step)
        pts.append(cur_p)
        rr.append(r * (1.0 - (i + 1) / segs * cfg["taper"]))
    bld.use("bark")
    tube(bld, pts, rr, mix(c_trunk, c_twig, min(1.0, depth / 3.0)),
         sides=5 if depth == 0 else (4 if depth == 1 else 3))
    r_end = rr[-1]
    if depth >= cfg["depth"]:
        tips.append((cur_p, pts[0], ln, gid))
        return
    n = cfg["split"][min(depth, len(cfg["split"]) - 1)]
    az0 = rng.uniform(0.0, math.tau)
    pad_d = cfg.get("pad_depth")
    for c in range(n):
        leader = cfg.get("leader") and c == 0
        az = az0 + (c / float(n)) * math.tau + rng.uniform(-0.55, 0.55)
        ang = rng.uniform(*(cfg["lead_ang"] if leader else cfg["ang"]))
        lr = rng.uniform(*(cfg["lead_lratio"] if leader else cfg["lratio"]))
        g = gid
        if pad_d is not None and g is None and depth + 1 >= pad_d:
            ctr[0] += 1
            g = ctr[0]
        grow(bld, tips, cur_p, bend(cur_d, az, ang),
             r_end * rng.uniform(*cfg["rratio"]), ln * lr, depth + 1, cfg, rng,
             g, ctr)


def build_tree(bld, x, y, h, seed, cfg):
    """遞迴分枝樹。h = 目標樹高（公尺）。座標 Z-up，樹底在 z=0。"""
    rng = random.Random(seed)
    tips = []
    d0 = norm3((rng.uniform(-0.10, 0.10), rng.uniform(-0.10, 0.10), 1.0))
    grow(bld, tips, (x, y, 0.0), d0, h * cfg["trunk_r"], h * cfg["trunk_len"],
         0, cfg, rng, None, [0])
    bld.use("foliage")
    # ⚠ 葉子大小要跟樹高走。`leaf` 是**絕對公尺**（稗田邸的庭木是 8~11m 的
    # 特寫，0.50 在那個尺度剛好）；同一個值放到 4.6m 的散佈樹上，葉子相對
    # 大了 2.5 倍 —— 渲染出來是一叢尖銳的碎片，不是葉子。新的品種一律用
    # `leaf_h`（樹高的比例）；`leaf` 只留給稗田邸那三棵已定案的樹。
    leaf_sz = cfg["leaf_h"] * h if "leaf_h" in cfg else cfg["leaf"]
    if cfg.get("pad_depth") is not None:
        canopy_pads(bld, rng, tips, cfg["ntuft"],
                    leaf_sz * (h / 8.0 if "leaf_h" not in cfg else 1.0),
                    cfg["hull"], cfg["lo"], cfg["hi"],
                    flat=cfg["pad_flat"], bulk=cfg["pad_bulk"],
                    rmin=h * cfg["pad_rmin"], n_leaf=cfg.get("n_leaf", 2))
    else:
        canopy_from_tips(bld, rng, tips, h * cfg["fol"], cfg["ntuft"],
                         leaf_sz, cfg["hull"], cfg["lo"], cfg["hi"],
                         n_leaf=cfg.get("n_leaf", 2), bare=cfg.get("bare", 0.32))
    return tips


# ── 樹皮色（呼叫端可用 cfg 的 trunk_col / twig_col 覆蓋）──
C_TRUNK = (0.115, 0.086, 0.062)
C_TWIG = (0.175, 0.132, 0.094)


# ══════════════════════════ 品種 profile ══════════════════════════
# ⚠ 闊葉樹也要 leader。沒有 leader 的話樹幹在第一次分岔就消失，所有枝
# 從同一高度散開 —— 冠因此是一頂**平底的蘑菇帽**（v2 就是這樣）。
# 有 leader 主幹才會一路往上、每一層沿途甩出側枝，枝端散佈在不同高度，
# 冠的下緣才會參差。
# up 改成 per-depth：主幹向上(0.34) → 側枝漸平(0.14/0.02) → 末梢下垂(-0.12)。
# 楓的枝是外展微垂的，全部向上就是白楊。
TREE_MAPLE = dict(
    trunk_r=0.044, trunk_len=0.30, depth=4, split=(4, 2, 2, 2),
    ang=(0.62, 1.15), lratio=(0.50, 0.88), rratio=(0.54, 0.74),
    up=(0.34, 0.14, 0.02, -0.12), wig=0.30, taper=0.28,
    leader=True, lead_ang=(0.10, 0.32), lead_lratio=(0.66, 0.86),
    fol=0.072, ntuft=500, leaf=0.50, flat=0.78,
    hull=(0.048, 0.016, 0.012),
    lo=(0.520, 0.095, 0.045), hi=(0.830, 0.290, 0.095))

# 松走另一條路：pad_depth 開啟「葉盤」模式（見 canopy_pads）。枝角開得比
# 楓大(1.10~1.52)、wig 很小 —— 松枝是折線不是曲線，一節一節硬轉。
TREE_PINE = dict(
    trunk_r=0.040, trunk_len=0.30, depth=4, split=(3, 3, 2, 2),
    ang=(1.10, 1.52), lratio=(0.44, 0.64), rratio=(0.56, 0.70),
    up=(0.50, 0.02, -0.10, -0.16), wig=0.09, taper=0.22,
    leader=True, lead_ang=(0.08, 0.24), lead_lratio=(0.60, 0.74),
    pad_depth=2, ntuft=1500, leaf=0.32, pad_flat=0.34, pad_bulk=1.55,
    pad_rmin=0.080,
    fol=0.046, flat=0.40,
    hull=(0.016, 0.030, 0.018),
    lo=(0.130, 0.245, 0.115), hi=(0.265, 0.395, 0.180))

# 稗田邸的三個楓品種：差在**骨架比例**（枝角、下垂、葉量），不是只換
# seed —— 只換 seed 的話每棵的統計輪廓一樣，遠看仍是同一棵複製貼上。
MAPLE_OLD = dict(TREE_MAPLE, ang=(0.72, 1.28), up=(0.30, 0.08, -0.04, -0.20),
                 fol=0.080, ntuft=470, trunk_r=0.050)
MAPLE_MID = dict(TREE_MAPLE)
MAPLE_YNG = dict(TREE_MAPLE, ang=(0.50, 0.95), up=(0.40, 0.22, 0.10, -0.04),
                 fol=0.064, ntuft=500, trunk_r=0.038)


# ── 野生／街景用（散佈量大，面數要壓）──
# 稗田邸的楓是庭木特寫（3,000 面／棵、單株擺放）；這些是幾百上千棵的
# MultiMesh 散佈，同樣的骨架但 depth 少一層、ntuft 砍到 1/4~1/2。
# 骨架不能省：棒棒糖的病因就在骨架，砍葉量不會讓它變回棒棒糖。
FOREST_ROUND = dict(
    trunk_r=0.040, trunk_len=0.32, depth=3, split=(3, 3, 2),
    ang=(0.58, 1.10), lratio=(0.56, 0.90), rratio=(0.54, 0.74),
    up=(0.36, 0.16, 0.02), wig=0.26, taper=0.26,
    leader=True, lead_ang=(0.10, 0.34), lead_lratio=(0.68, 0.88),
    fol=0.088, ntuft=330, leaf_h=0.098, n_leaf=2, bare=0.30,
    hull=(0.055, 0.085, 0.040),
    lo=(0.135, 0.225, 0.105), hi=(0.330, 0.450, 0.190))

# 遠景／vista：420~2,600 棵那種。再砍一層 split，ntuft 只留 90。
FOREST_FAR = dict(FOREST_ROUND, split=(3, 2, 2), ntuft=185, leaf_h=0.112,
                  fol=0.082)

# 瘦高型：打破天際線用（原 tree_round_c 的角色）
FOREST_TALL = dict(FOREST_ROUND, ang=(0.42, 0.86), up=(0.46, 0.30, 0.12),
                   lratio=(0.52, 0.80), fol=0.072, ntuft=300, leaf_h=0.086)

# 野生杉：庭木松的 pad 模式不適用（那是修剪出來的）。野生針葉樹是
# 「一層層側枝往下垂」，所以用 canopy_from_tips + 大 split + 強下垂。
FOREST_PINE = dict(
    trunk_r=0.030, trunk_len=0.26, depth=3, split=(5, 3, 2),
    ang=(1.05, 1.42), lratio=(0.52, 0.72), rratio=(0.48, 0.64),
    up=(0.62, -0.10, -0.26), wig=0.10, taper=0.30,
    leader=True, lead_ang=(0.04, 0.16), lead_lratio=(0.78, 0.94),
    fol=0.062, ntuft=380, leaf_h=0.072, n_leaf=2, bare=0.22,
    hull=(0.030, 0.055, 0.030),
    lo=(0.105, 0.195, 0.100), hi=(0.245, 0.360, 0.165))

# 花樹（櫻）：骨架跟闊葉同源，但**枝更外展、更下垂**（櫻的枝是橫著長的），
# 樹皮偏灰。花色層由呼叫端傳 lo/hi 覆蓋。
SAKURA = dict(
    trunk_r=0.046, trunk_len=0.28, depth=3, split=(4, 3, 2),
    ang=(0.72, 1.26), lratio=(0.58, 0.92), rratio=(0.56, 0.76),
    up=(0.30, 0.06, -0.10), wig=0.30, taper=0.26,
    leader=True, lead_ang=(0.12, 0.38), lead_lratio=(0.62, 0.84),
    fol=0.086, ntuft=420, leaf_h=0.090, n_leaf=2, bare=0.34,
    trunk_col=(0.128, 0.104, 0.092), twig_col=(0.196, 0.160, 0.150),
    # ⚠ 花色要**淡**。第一版 hull 0.185/0.075/0.100（暗酒紅）＋ lo 0.50/0.20/0.28
    # 在引擎裡讀成洋紅 —— sato 的 Environment 有 saturation 1.24，飽和的玫瑰色
    # 會被再推一階。Blender 預覽看起來還好，**引擎內截圖才是準的**。
    hull=(0.340, 0.160, 0.200),
    lo=(0.620, 0.340, 0.400), hi=(0.980, 0.760, 0.780))

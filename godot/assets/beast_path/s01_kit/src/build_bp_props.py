"""獸道全區（S01–S03）道具與小建築——Blender 5.2.1，純頂點組裝，固定 seed、可重現。

用法：
    背景（正式輸出）：blender -b --python build_bp_props.py -- [--no-export] [--only=a,b]
    即時 Blender（MCP）：g={'__name__':'bpprops','__file__':<本檔>}; exec(open(<本檔>).read(), g); g['build_all'](export=False)
      只在自己的 collection「BP_PROPS」裡建，不重設場景、不動其他物件。
共用 build_s01_shrine.py（poly／box／loft_x／lathe／stone_jitter）與 build_s01_kit.py（MB、log）的工具（exec 載入、不改它們）。

輸出（assets/beast_path/s01_kit/glb/，與 s01 kit 同一個目錄＝Godot 端同一個載入器）：
    bp_step_stone_{a,b,c}   自然石的踏み石（不規則圓角板、上緣面取、頂面微凸；1.0×0.56 m、厚 0.45＝頂 z 0）——s01k_stone
    bp_step_log_{a,b}       土留め丸太（階段の蹴込み）——s01k_wood（同 S01 倒木）
    bp_bridge_a             丸太桁＋板橋（長 10 m 沿 X、寬 2.6 m、面＝z 0）——s01k_paint（素木）；Godot 依實際長度沿 X 伸縮
    bp_bridge_a_abut        橋台の空石積み（一端；原點＝橋端面中心、頂 z −0.10）——s01k_stone
    bp_hokora_a             木の小祠（切妻の板屋根、格子戸、注連縄＋紙垂、供物台；正面＝+Y）——s01k_paint
    bp_hokora_a_base        祠の石の基壇（二段の切石＋正面の石段三段）——s01k_stone
    bp_signpost_a           道標の柱（角柱＋笠木）；bp_signpost_board＝矢印板（+X が先端、墨書の帯）——s01k_paint
    bp_marker_a             道標石（荒削りの角柱、兜巾形の頭、正面に彫り込み）——s01k_stone
    bp_fence_post_a／bp_fence_rail_a   古い丸太の柵（杭 1.25 m、横木 1.0 m 沿 X）——s01k_paint（灰色に風化した素木）
    bp_gate_a               木戸（冠木＋板戸、小さな板屋根）——s01k_paint
    bp_offering_a／bp_offering_stone   供物（盆、握り飯、柿、盃、竹筒の枯れ花）／それを置く平たい石
    bp_stepstone_{a,b}      川の飛び石（頂が平らな丸石）——s01k_rock
    s01_lantern_a_low／s01_lantern_a_top   春日燈籠を中台上で二分した部品（倒れた燈籠用）——s01k_stone
座標：Blender Z 上；glTF Y 上（Blender −Y → Godot +Z）。原点＝地面（または記載の基準）。
頂點資料（s01k_paint）：COLOR.rgb＝塗色（sRGB）；UV0＝木紋（m）；UV1.x＝材質（0.5 素木）、UV1.y＝木紋方向（0 直立、1 水平）。
"""
import bpy, math, random, os, sys, json
from mathutils import Vector

_HERE = os.path.dirname(os.path.abspath(globals().get("__file__", r"D:/神社/shrine/godot/assets/beast_path/s01_kit/src/build_bp_props.py")))
S = {"__name__": "bp_shrine_lib", "__file__": os.path.join(_HERE, "build_s01_shrine.py")}
exec(open(os.path.join(_HERE, "build_s01_shrine.py"), encoding="utf-8").read(), S)
K = S["K"]
K["COLL"] = "BP_PROPS"
MB, poly, box, loft_x, lathe, stone_jitter = S["MB"], S["poly"], S["box"], S["loft_x"], S["lathe"], S["stone_jitter"]
loft_rings, fbm, sstep = S["loft_rings"], K["fbm"], K["sstep"]
placeholder_mat, coll = K["placeholder_mat"], K["coll"]
GLB_DIR, SRC_DIR = S["GLB_DIR"], S["SRC_DIR"]
WOODM = 0.5          # s01k_paint：素木


def grey(p, n):
    return (0.6, 0.6, 0.58)


def wood_grey(seed, base=(0.36, 0.33, 0.29), var=0.07):
    """風化した素木：灰褐、低頻の色ムラ、上向き面は日焼けで明るく灰色、下は暗い"""
    def f(p, n):
        k = fbm(Vector(p) * 1.7, seed, 2)
        up = max(n[2], 0.0) if hasattr(n, "__getitem__") else 0.0
        c = [base[i] * (1.0 + var * 2.0 * k) for i in range(3)]
        c = [c[i] * (1.0 + 0.10 * up) + 0.03 * up for i in range(3)]
        if n[2] < -0.5:
            c = [x * 0.82 for x in c]
        return tuple(min(max(x, 0.0), 1.0) for x in c)
    return f


def wood_fresh(seed):
    return wood_grey(seed, (0.44, 0.35, 0.25), 0.06)


def finish(mb, name, matname, rgb):
    ob = mb.to_object(name)
    ob.data.materials.append(placeholder_mat(matname, rgb))
    return ob


def rounded_rect(W, D, n, ex, rng, jit):
    pts = []
    for k in range(n):
        a = math.tau * k / n + 0.13
        c, s = math.cos(a), math.sin(a)
        x = (W / 2) * math.copysign(abs(c) ** (2 / ex), c)
        y = (D / 2) * math.copysign(abs(s) ** (2 / ex), s)
        r = 1.0 + rng.uniform(-jit, jit)
        pts.append(Vector((x * r, y * r, 0.0)))
    return pts


# ============================================================ 石段・踏み石
def step_stone(name, seed):
    """自然石の踏み石：不規則な多角形（7–10 角、角は丸め）、厚み 0.30–0.45 の割石。頂面は平らに近いが片側へ 1–3 cm 傾き、
    縁は不揃いに面取り。外形 ≈1.0×0.56 m（Godot で段の当たり判定に合わせて伸縮）、頂 z≈0。"""
    rng = random.Random(seed)
    mb = MB()
    nc = rng.randint(7, 10)
    angs = sorted(rng.uniform(0, math.tau) for _ in range(nc))
    base = []
    for a in angs:
        c, s = math.cos(a), math.sin(a)
        r = rng.uniform(0.82, 1.08)
        x = 0.5 * math.copysign(abs(c) ** (2 / 2.6), c) * r
        y = 0.28 * math.copysign(abs(s) ** (2 / 2.6), s) * r
        base.append(Vector((x, y, 0.0)))
    # 角を丸める（各頂点を前後の辺の 22 % 点で置き換え）
    rb = []
    for i in range(nc):
        p0, p1, p2 = base[i - 1], base[i], base[(i + 1) % nc]
        rb.append(p1.lerp(p0, 0.22))
        rb.append(p1.lerp(p2, 0.22))
    jit = stone_jitter(seed, 0.010)
    th = rng.uniform(0.30, 0.45)
    tilt = Vector((rng.uniform(-0.03, 0.03), rng.uniform(-0.04, 0.04), 0.0))
    def ring(sc, z, bev=0.0):
        out = []
        for p in rb:
            q = Vector((p.x * sc, p.y * sc, z + tilt.x * p.x + tilt.y * p.y - bev * rng.uniform(0.3, 1.0)))
            out.append(q + jit(q * 1.3))
        return out
    rings = [ring(1.04, -th), ring(1.02, -th * 0.45), ring(1.0, -0.05, 0.02), ring(0.94, -0.004, 0.012)]
    loft_rings(mb, rings, grey, 0.75, -th * 0.5, cap_bot=True, cap_top=False)
    top = rings[-1]
    cz = sum(p.z for p in top) / len(top) + 0.008
    c = mb.v((0.0, 0.0, cz), (0, 0, 1), grey((0, 0, 0), (0, 0, 1)), (0, 0), (0.76, 0.0))
    ids = [mb.v(p, (0, 0, 1), grey(p, (0, 0, 1)), (p.x, p.y), (0.76, 0.0)) for p in top]
    for i in range(len(ids)):
        mb.tri(c, ids[i], ids[(i + 1) % len(ids)])
    return finish(mb, name, "BP_stone", (0.55, 0.55, 0.52))


def step_log(name, seed):
    ob = K["log"](name, seed, 1.15, 0.115, 0.105, nlen=8, nrad=11, stub=False, split_end=False)
    return ob


# ============================================================ 板橋
def bridge(name):
    L, W = 10.0, 2.6
    mb = MB()
    rng = random.Random(77)
    # 丸太の桁（八角形断面、少し不揃い）
    for side in (-1, 1):
        yc = side * (W / 2 - 0.35)
        r = 0.17
        prof = [(yc + r * math.cos(a), -0.08 - r + r * math.sin(a)) for a in [math.tau * k / 9 for k in range(9)]]
        loft_x(mb, [-L / 2 - 0.45 + i * (L + 0.9) / 8 for i in range(9)], prof, lambda x: 0.012 * math.sin(x * 0.9 + side), wood_grey(11 + side, (0.30, 0.26, 0.21)), WOODM)
    # 横の受け木（桁の上、板の下）
    for i in range(6):
        x = -L / 2 + 0.3 + i * (L - 0.6) / 5
        box(mb, (x - 0.06, -W / 2 + 0.05, -0.15), (x + 0.06, W / 2 - 0.05, -0.065), wood_grey(21 + i, (0.31, 0.27, 0.22)), WOODM, 0)
    # 床板：幅 0.20–0.27、隙間 1–2 cm、高さと長さが少しずつ違う、端は不揃い
    x = -L / 2
    k = 0
    while x < L / 2 - 0.05:
        w = rng.uniform(0.20, 0.27)
        x1 = min(x + w, L / 2)
        dz = rng.uniform(-0.012, 0.006)
        y0 = -W / 2 + rng.uniform(-0.05, 0.06)
        y1 = W / 2 + rng.uniform(-0.06, 0.05)
        box(mb, (x, y0, -0.065 + dz), (x1, y1, 0.0 + dz), wood_grey(100 + k, (0.38, 0.34, 0.29), 0.10), WOODM, 0)
        x = x1 + rng.uniform(0.010, 0.022)
        k += 1
    # 欄干：角柱（桁の外側に添える）、笠木（丸）、中貫
    n_post = 5
    rail_y = W / 2 - 0.02
    for side in (-1, 1):
        yy = side * rail_y
        for i in range(n_post):
            px = -L / 2 + 0.25 + i * (L - 0.5) / (n_post - 1)
            box(mb, (px - 0.055, yy - 0.055, -0.40), (px + 0.055, yy + 0.055, 1.0), wood_grey(200 + i * 3 + side, (0.33, 0.30, 0.26)), WOODM, 0)
        for (zr, rr, sd) in ((0.95, 0.050, 300), (0.50, 0.035, 310)):
            prof = [(yy + rr * math.cos(a), rr * math.sin(a)) for a in [math.tau * k2 / 7 for k2 in range(7)]]
            loft_x(mb, [-L / 2 + 0.15 + i * (L - 0.3) / 10 for i in range(11)], prof, lambda x, zr=zr: zr - 0.012 * math.cos(x / L * math.pi), wood_grey(sd + side, (0.36, 0.33, 0.28)), WOODM)
    return finish(mb, name, "BP_wood", (0.35, 0.3, 0.25))


def bridge_abut(name):
    """一端の空石積み：橋の下の岸に積んだ不揃いの石（原点＝橋端の中心、x＞0 が岸側）"""
    rng = random.Random(91)
    mb = MB()
    for row in range(3):
        z0 = -0.10 - 0.30 * (row + 1)
        y = -1.45
        while y < 1.45:
            w = rng.uniform(0.38, 0.62)
            d = rng.uniform(0.45, 0.7)
            x0 = -0.15 + rng.uniform(-0.05, 0.05) - row * 0.10
            jit = stone_jitter(rng.randint(1, 999), 0.02)
            bx = [(x0, y, z0), (x0 + d, y + w - 0.03, z0 + 0.28 + rng.uniform(-0.03, 0.02))]
            ring_lo = [Vector((bx[0][0], bx[0][1], bx[0][2])), Vector((bx[1][0], bx[0][1], bx[0][2])), Vector((bx[1][0], bx[1][1], bx[0][2])), Vector((bx[0][0], bx[1][1], bx[0][2]))]
            ring_hi = [Vector((p.x + 0.03 * (1 if i in (0, 3) else -1), p.y + 0.03 * (1 if i in (0, 1) else -1), bx[1][2])) for i, p in enumerate(ring_lo)]
            ring_lo = [p + jit(p) for p in ring_lo]
            ring_hi = [p + jit(p) for p in ring_hi]
            ctr = (sum(p.x for p in ring_lo) / 4, sum(p.y for p in ring_lo) / 4, (bx[0][2] + bx[1][2]) / 2)
            for i in range(4):
                poly(mb, [ring_lo[i], ring_lo[(i + 1) % 4], ring_hi[(i + 1) % 4], ring_hi[i]], grey, 0.75, 0, ctr)
            poly(mb, ring_hi, grey, 0.75, 0, ctr)
            y += w
    return finish(mb, name, "BP_stone", (0.55, 0.55, 0.52))


# ============================================================ 小祠
def hokora_base(name):
    """祠の基壇：切石二段（同じ外形、上段 2 cm 控え）；外形 3.4×3.0 m、頂 z 0.42（Godot で layout の基壇 (w+1)×(d+1)×高さ に合わせて伸縮）。
    石段は別（bp_step_stone を Godot が既存の段の当たり判定の位置に置く）。"""
    rng = random.Random(41)
    mb = MB()
    def course(W, D, z0, z1, nx, ny, seed):
        jit = stone_jitter(seed, 0.008)
        xs = [-W / 2 + W * i / nx for i in range(nx + 1)]
        ys = [-D / 2 + D * i / ny for i in range(ny + 1)]
        for i in range(nx):
            for j in range(ny):
                if 0 < i < nx - 1 and 0 < j < ny - 1:
                    continue                                   # 外周だけ（中は見えない）
                g = 0.008
                h = z1 + rng.uniform(-0.012, 0.01)
                lo = [Vector((xs[i] + g, ys[j] + g, z0)), Vector((xs[i + 1] - g, ys[j] + g, z0)), Vector((xs[i + 1] - g, ys[j + 1] - g, z0)), Vector((xs[i] + g, ys[j + 1] - g, z0))]
                hi = [Vector((p.x + (0.02 if p.x < (xs[i] + xs[i + 1]) / 2 else -0.02), p.y + (0.02 if p.y < (ys[j] + ys[j + 1]) / 2 else -0.02), h)) for p in lo]
                lo = [p + jit(p) for p in lo]
                hi = [p + jit(p) for p in hi]
                ctr = ((xs[i] + xs[i + 1]) / 2, (ys[j] + ys[j + 1]) / 2, (z0 + h) / 2)
                for k in range(4):
                    poly(mb, [lo[k], lo[(k + 1) % 4], hi[(k + 1) % 4], hi[k]], grey, 0.75, 0, ctr)
                poly(mb, hi, grey, 0.75, 0, ctr)
    course(3.4, 3.0, -0.25, 0.17, 5, 4, 43)
    course(3.36, 2.96, 0.17, 0.42, 4, 4, 47)
    # 中央の床（上段の内側をふさぐ平石）
    box(mb, (-1.0, -0.8, 0.30), (1.0, 0.8, 0.41), grey, 0.75, 0)
    return finish(mb, name, "BP_stone", (0.55, 0.55, 0.52))


def hokora(name):
    """小祠（原点＝基壇の上面）。W×D＝2.3×1.9 m（layout の小祠 w×d 2.4–2.8 × 2.0–2.2 に Godot で伸縮）"""
    mb = MB()
    Z0 = 0.0
    W, D = 2.3, 1.9
    WG = wood_grey(5, (0.34, 0.30, 0.25))
    WD = wood_grey(6, (0.26, 0.22, 0.18))
    # 土台
    box(mb, (-W / 2 - 0.05, -D / 2 - 0.05, Z0), (W / 2 + 0.05, D / 2 + 0.05, Z0 + 0.10), WD, WOODM, 1)
    # 縁（正面の板縁）
    box(mb, (-W / 2, D / 2 + 0.05, Z0 + 0.06), (W / 2, D / 2 + 0.32, Z0 + 0.11), WG, WOODM, 1)
    H = 1.22
    zt = Z0 + 0.10 + H
    for sx in (-1, 1):
        for sy in (-1, 1):
            cx, cy = sx * (W / 2 - 0.05), sy * (D / 2 - 0.05)
            box(mb, (cx - 0.05, cy - 0.05, Z0 + 0.10), (cx + 0.05, cy + 0.05, zt), WD, WOODM, 0)
    # 側面・背面の板壁（縦板、少し凹）
    for (x0, x1, y0, y1) in ((-W / 2 + 0.03, -W / 2 + 0.05, -D / 2 + 0.05, D / 2 - 0.05), (W / 2 - 0.05, W / 2 - 0.03, -D / 2 + 0.05, D / 2 - 0.05),
                             (-W / 2 + 0.05, W / 2 - 0.05, -D / 2 + 0.03, -D / 2 + 0.05)):
        box(mb, (x0, y0, Z0 + 0.10), (x1, y1, zt - 0.06), WG, WOODM, 0)
    # 正面：内部の暗がり＋格子戸二枚
    box(mb, (-W / 2 + 0.05, D / 2 - 0.22, Z0 + 0.10), (W / 2 - 0.05, D / 2 - 0.20, zt - 0.06), lambda p, n: (0.05, 0.045, 0.04), WOODM, 0)
    yd = D / 2 - 0.06
    for sx in (-1, 1):
        x0, x1 = (0.0, W / 2 - 0.10) if sx > 0 else (-(W / 2 - 0.10), 0.0)
        z0, z1 = Z0 + 0.14, zt - 0.10
        for (a0, a1, b0, b1) in ((x0, x1, z0, z0 + 0.05), (x0, x1, z1 - 0.05, z1), (x0, x0 + 0.04, z0, z1), (x1 - 0.04, x1, z0, z1)):
            box(mb, (a0, yd - 0.02, b0), (a1, yd + 0.02, b1), WG, WOODM, 0)
        nb = 4
        for i in range(1, nb):
            xx = x0 + (x1 - x0) * i / nb
            box(mb, (xx - 0.012, yd - 0.012, z0), (xx + 0.012, yd + 0.012, z1), WG, WOODM, 0)
        for i in range(1, 6):
            zz = z0 + (z1 - z0) * i / 6
            box(mb, (x0, yd - 0.010, zz - 0.010), (x1, yd + 0.010, zz + 0.010), WG, WOODM, 1)
    # 桁・梁
    box(mb, (-W / 2 - 0.12, -D / 2 - 0.02, zt - 0.06), (W / 2 + 0.12, D / 2 + 0.02, zt + 0.04), WD, WOODM, 1)
    # 切妻屋根（棟は X 方向、軒は ±Y に出る、板葺き）：厚み 0.07、軒の出 0.42、妻の出 0.32
    zr = zt + 0.04
    ridge = zr + 0.78
    ey = D / 2 + 0.58
    ex = W / 2 + 0.42
    ROOF = wood_grey(9, (0.25, 0.23, 0.21), 0.12)
    for sy in (-1, 1):
        a = [Vector((-ex, 0.0, ridge)), Vector((ex, 0.0, ridge)), Vector((ex, sy * ey, zr - 0.04)), Vector((-ex, sy * ey, zr - 0.04))]
        b = [p + Vector((0, 0, 0.07)) for p in a]
        ctr = (0.0, sy * ey * 0.5, (ridge + zr) / 2 + 0.03)
        poly(mb, a, ROOF, WOODM, 1, (0.0, sy * ey * 0.5, (ridge + zr) / 2 + 0.6))
        poly(mb, b, ROOF, WOODM, 1, (0.0, sy * ey * 0.5, (ridge + zr) / 2 - 0.6))
        for i in range(4):
            poly(mb, [a[i], a[(i + 1) % 4], b[(i + 1) % 4], b[i]], ROOF, WOODM, 1, ctr)
        # 破風板（妻の端）
        for sx in (-1, 1):
            q = [Vector((sx * ex, 0.0, ridge + 0.09)), Vector((sx * ex, sy * (ey + 0.02), zr + 0.01)), Vector((sx * ex, sy * (ey + 0.02), zr - 0.10)), Vector((sx * ex, 0.0, ridge - 0.04))]
            q2 = [p + Vector((sx * 0.035, 0, 0)) for p in q]
            c2 = (sx * (ex + 0.017), sy * ey * 0.5, (ridge + zr) / 2)
            poly(mb, q, WD, WOODM, 1, c2)
            poly(mb, q2, WD, WOODM, 1, c2)
            for i in range(4):
                poly(mb, [q[i], q[(i + 1) % 4], q2[(i + 1) % 4], q2[i]], WD, WOODM, 1, c2)
    # 棟木（箱棟）
    box(mb, (-ex - 0.02, -0.07, ridge + 0.04), (ex + 0.02, 0.07, ridge + 0.14), WD, WOODM, 1)
    # 妻壁（三角）
    for sx in (-1, 1):
        x = sx * (W / 2 - 0.04)
        tri = [Vector((x, -D / 2 + 0.05, zt + 0.04)), Vector((x, D / 2 - 0.05, zt + 0.04)), Vector((x, 0.0, ridge - 0.02))]
        poly(mb, tri, WG, WOODM, 0, (x - sx * 0.3, 0.0, zt + 0.2))
        poly(mb, [p + Vector((-sx * 0.02, 0, 0)) for p in tri], WG, WOODM, 0, (x + sx * 0.3, 0.0, zt + 0.2))
    # 注連縄（正面の桁から垂れる）＋紙垂 3
    rope_y = D / 2 + 0.10
    rr = 0.04
    prof = [(rope_y + rr * math.cos(a), rr * math.sin(a)) for a in [math.tau * k / 6 for k in range(6)]]
    loft_x(mb, [-W / 2 + 0.05 + (W - 0.1) * i / 10 for i in range(11)], prof, lambda x: zt - 0.07 - 0.07 * (1 - (2 * x / W) ** 2),
           lambda p, n: (0.62, 0.55, 0.38), WOODM)
    for xi in (-0.62, -0.2, 0.2, 0.62):
        zz = zt - 0.07 - 0.07 * (1 - (2 * xi / W) ** 2) - 0.03
        pts = [(xi - 0.03, zz), (xi + 0.03, zz), (xi + 0.03, zz - 0.07), (xi - 0.02, zz - 0.07), (xi - 0.02, zz - 0.14), (xi + 0.04, zz - 0.14), (xi + 0.04, zz - 0.21), (xi - 0.03, zz - 0.21)]
        for (sgn) in (1, -1):
            for i in range(0, len(pts) - 2, 2):
                q = [Vector((pts[i][0], rope_y + sgn * 0.002, pts[i][1])), Vector((pts[i + 1][0], rope_y + sgn * 0.002, pts[i + 1][1])),
                     Vector((pts[i + 2][0], rope_y + sgn * 0.002, pts[i + 2][1])), Vector((pts[i + 3][0] if i + 3 < len(pts) else pts[i + 2][0], rope_y + sgn * 0.002, pts[i + 3][1] if i + 3 < len(pts) else pts[i + 2][1]))]
                poly(mb, q, lambda p, n: (0.86, 0.85, 0.80), WOODM, 0, (xi, rope_y - sgn * 0.3, zz - 0.1))
    # 供物台（縁の上）
    box(mb, (-0.22, D / 2 + 0.14, Z0 + 0.11), (0.22, D / 2 + 0.28, Z0 + 0.15), WD, WOODM, 1)
    return finish(mb, name, "BP_wood", (0.35, 0.3, 0.25))


# ============================================================ 道標・道標石・柵・木戸
def signpost(name):
    mb = MB()
    WG = wood_grey(15, (0.33, 0.29, 0.24))
    box(mb, (-0.065, -0.065, -0.35), (0.065, 0.065, 2.05), WG, WOODM, 0)
    # 笠木（小さな切妻）
    for sy in (-1, 1):
        a = [Vector((-0.13, 0.0, 2.17)), Vector((0.13, 0.0, 2.17)), Vector((0.13, sy * 0.13, 2.07)), Vector((-0.13, sy * 0.13, 2.07))]
        b = [p + Vector((0, 0, 0.035)) for p in a]
        poly(mb, a, WG, WOODM, 1, (0, sy * 0.06, 1.5))
        poly(mb, b, WG, WOODM, 1, (0, sy * 0.06, 2.8))
        for i in range(4):
            poly(mb, [a[i], a[(i + 1) % 4], b[(i + 1) % 4], b[i]], WG, WOODM, 1, (0, sy * 0.06, 2.12))
    box(mb, (-0.075, -0.075, 2.03), (0.075, 0.075, 2.08), WG, WOODM, 0)
    return finish(mb, name, "BP_wood", (0.35, 0.3, 0.25))


def signpost_board(name):
    """矢印板：根元 x=0（柱の中心）→ 先端 +X 1.0 m；兩面に墨書の帯（抽象的な筆画）"""
    mb = MB()
    WG = wood_fresh(17)
    T = 0.022
    outline = [(0.07, -0.11), (0.86, -0.11), (1.0, 0.0), (0.86, 0.11), (0.07, 0.11)]
    for sy in (-1, 1):
        pts = [Vector((x, sy * T, z)) for x, z in outline]
        poly(mb, pts, WG, WOODM, 1, (0.5, -sy * 0.5, 0.0))
    for i in range(len(outline)):
        a, b = outline[i], outline[(i + 1) % len(outline)]
        poly(mb, [Vector((a[0], -T, a[1])), Vector((b[0], -T, b[1])), Vector((b[0], T, b[1])), Vector((a[0], T, a[1]))], WG, WOODM, 1, (0.5, 0.0, 0.0))
    rng = random.Random(3)
    INK = lambda p, n: (0.08, 0.07, 0.06)
    for sy in (-1, 1):
        x = 0.16
        while x < 0.74:
            w = rng.uniform(0.05, 0.09)
            for s in range(rng.randint(2, 3)):
                zz = rng.uniform(-0.07, 0.07)
                h = rng.uniform(0.012, 0.022)
                ww = rng.uniform(0.6, 1.0) * w
                q = [Vector((x, sy * (T + 0.0015), zz - h)), Vector((x + ww, sy * (T + 0.0015), zz - h)), Vector((x + ww, sy * (T + 0.0015), zz + h)), Vector((x, sy * (T + 0.0015), zz + h))]
                poly(mb, q, INK, WOODM, 1, (x, -sy * 0.5, zz))
            x += w + 0.035
    return finish(mb, name, "BP_wood", (0.4, 0.33, 0.25))


def marker(name):
    mb = MB()
    jit = stone_jitter(71, 0.010)
    rings = []
    for (sc, z) in ((1.04, -0.25), (1.0, 0.0), (0.97, 0.75), (0.94, 0.92)):
        r = [Vector((-0.15 * sc, -0.13 * sc, z)), Vector((0.15 * sc, -0.13 * sc, z)), Vector((0.15 * sc, 0.13 * sc, z)), Vector((-0.15 * sc, 0.13 * sc, z))]
        rings.append([p + jit(p) for p in r])
    loft_rings(mb, rings, grey, 0.75, 0.4, cap_bot=True)
    # 兜巾形の頭
    apex = Vector((0.0, 0.0, 1.06))
    top = rings[-1]
    for i in range(4):
        poly(mb, [top[i], top[(i + 1) % 4], apex], grey, 0.75, 0, (0, 0, 0.8))
    # 正面（+Y）の彫り込み枠（浅い凹面）
    y = 0.13 * 0.97 + 0.002
    fr = [Vector((-0.09, y, 0.18)), Vector((0.09, y, 0.18)), Vector((0.09, y, 0.80)), Vector((-0.09, y, 0.80))]
    rec = [p - Vector((0, 0.012, 0)) for p in fr]
    for i in range(4):
        poly(mb, [fr[i], fr[(i + 1) % 4], rec[(i + 1) % 4], rec[i]], grey, 0.75, 0, (0, 0.0, 0.5))
    poly(mb, rec, grey, 0.75, 0, (0, 0.0, 0.5))
    # 彫った文字の溝（縦の短い凹み）
    rng = random.Random(5)
    for i in range(5):
        zz = 0.70 - i * 0.11
        h = rng.uniform(0.035, 0.06)
        g = [Vector((-0.02, y - 0.012, zz - h)), Vector((0.02, y - 0.012, zz - h)), Vector((0.02, y - 0.012, zz + h * 0.4)), Vector((-0.02, y - 0.012, zz + h * 0.4))]
        g2 = [p - Vector((0, 0.010, 0)) for p in g]
        for k in range(4):
            poly(mb, [g[k], g[(k + 1) % 4], g2[(k + 1) % 4], g2[k]], grey, 0.75, 0, (0, y + 0.3, zz))
        poly(mb, g2, grey, 0.75, 0, (0, y + 0.3, zz))
    return finish(mb, name, "BP_stone", (0.55, 0.55, 0.52))


def fence_post(name):
    mb = MB()
    rng = random.Random(23)
    r = 0.062
    prof = [(r * math.cos(a) * (1 + rng.uniform(-0.08, 0.08)), r * math.sin(a) * (1 + rng.uniform(-0.08, 0.08))) for a in [math.tau * k / 8 for k in range(8)]]
    # 縦に立てる：loft_x で X 方向に作ってから軸を入れ替える
    mb2 = MB()
    loft_x(mb2, [-0.25 + 1.5 * i / 6 for i in range(7)], prof, lambda x: 0.0, wood_grey(24, (0.34, 0.31, 0.27), 0.12), WOODM, end_slant=0.0)
    for i, p in enumerate(mb2.P):
        x, y, z = p
        mb2.P[i] = (y, z, x)
        nx, ny, nz = mb2.N[i]
        mb2.N[i] = (ny, nz, nx)
        u1 = mb2.U1[i]
        mb2.U1[i] = (u1[0], 1.0 - 0.0)          # 直立構件
    ob = mb2.to_object(name)
    ob.data.materials.append(placeholder_mat("BP_wood", (0.35, 0.3, 0.25)))
    return ob


def fence_rail(name):
    mb = MB()
    rng = random.Random(29)
    r = 0.042
    prof = [(r * math.cos(a) * (1 + rng.uniform(-0.1, 0.1)), r * math.sin(a) * (1 + rng.uniform(-0.1, 0.1))) for a in [math.tau * k / 7 for k in range(7)]]
    loft_x(mb, [i / 6 for i in range(7)], prof, lambda x: 0.006 * math.sin(x * 5.0), wood_grey(30, (0.36, 0.33, 0.29), 0.12), WOODM)
    return finish(mb, name, "BP_wood", (0.35, 0.3, 0.25))


def gate(name):
    mb = MB()
    WG = wood_grey(33, (0.32, 0.28, 0.23))
    WD = wood_grey(34, (0.25, 0.21, 0.17))
    for sx in (-1, 1):
        box(mb, (sx * 1.08 - 0.08, -0.08, -0.3), (sx * 1.08 + 0.08, 0.08, 2.0), WD, WOODM, 0)
    box(mb, (-1.35, -0.07, 1.86), (1.35, 0.07, 2.0), WD, WOODM, 1)               # 冠木
    for sy in (-1, 1):                                                           # 小さな板屋根
        a = [Vector((-1.45, 0.0, 2.24)), Vector((1.45, 0.0, 2.24)), Vector((1.45, sy * 0.36, 2.04)), Vector((-1.45, sy * 0.36, 2.04))]
        b = [p + Vector((0, 0, 0.045)) for p in a]
        poly(mb, a, WD, WOODM, 1, (0, sy * 0.18, 1.5))
        poly(mb, b, WD, WOODM, 1, (0, sy * 0.18, 2.9))
        for i in range(4):
            poly(mb, [a[i], a[(i + 1) % 4], b[(i + 1) % 4], b[i]], WD, WOODM, 1, (0, sy * 0.18, 2.14))
    for sx in (-1, 1):
        box(mb, (sx * 1.08 - 0.05, -0.05, 2.0), (sx * 1.08 + 0.05, 0.05, 2.16), WD, WOODM, 0)
    # 板戸：縦板 7 枚＋桟 2
    rng = random.Random(35)
    x = -0.98
    while x < 0.98:
        w = rng.uniform(0.24, 0.30)
        x1 = min(x + w, 0.98)
        box(mb, (x, -0.025, 0.12), (x1 - 0.008, 0.025, 1.70 + rng.uniform(-0.02, 0.02)), WG, WOODM, 0)
        x = x1
    for zz in (0.45, 1.30):
        box(mb, (-0.96, -0.06, zz - 0.05), (0.96, -0.025, zz + 0.05), WD, WOODM, 1)
    box(mb, (0.60, -0.09, 0.82), (0.74, -0.06, 0.98), lambda p, n: (0.10, 0.09, 0.08), WOODM, 0)  # 錠
    return finish(mb, name, "BP_wood", (0.35, 0.3, 0.25))


# ============================================================ 供物
def offering_stone(name):
    mb = MB()
    jit = stone_jitter(81, 0.02)
    prof = [(0.36, -0.10), (0.38, 0.06), (0.33, 0.14), (0.20, 0.17), (0.0, 0.175)]
    rings = lathe(mb, prof, 11, grey, 0.75, jitter=jit, cap_bot=True, smooth=False)
    return finish(mb, name, "BP_stone", (0.55, 0.55, 0.52))


def offering(name):
    mb = MB()
    Z = 0.175
    WD = wood_fresh(83)
    box(mb, (-0.17, -0.12, Z), (0.17, 0.12, Z + 0.025), WD, WOODM, 1)           # 盆（へぎ板）
    # 握り飯 ×2（白、三角の丸み）
    for (cx, cy) in ((-0.07, 0.01), (0.03, 0.04)):
        lathe(mb, [(0.0, Z + 0.025), (0.045, Z + 0.03), (0.05, Z + 0.06), (0.035, Z + 0.09), (0.0, Z + 0.10)], 3, lambda p, n: (0.88, 0.86, 0.80), WOODM,
              center=(cx, cy), phase=0.3, smooth=True)
    # 柿 ×2
    for (cx, cy) in ((0.10, -0.05), (0.12, 0.06)):
        lathe(mb, [(0.0, Z + 0.025), (0.035, Z + 0.032), (0.042, Z + 0.06), (0.03, Z + 0.085), (0.0, Z + 0.09)], 9, lambda p, n: (0.78, 0.40, 0.12), WOODM,
              center=(cx, cy), smooth=True)
    # 盃（白磁）
    lathe(mb, [(0.0, Z + 0.025), (0.025, Z + 0.027), (0.04, Z + 0.05), (0.036, Z + 0.052)], 10, lambda p, n: (0.85, 0.84, 0.80), WOODM,
          center=(-0.11, -0.07), smooth=True)
    # 竹筒の花立て＋枯れ花（茶色の茎）
    lathe(mb, [(0.035, 0.0), (0.035, Z + 0.20), (0.03, Z + 0.20)], 8, lambda p, n: (0.42, 0.45, 0.25), WOODM, center=(0.25, 0.12), cap_top=True, smooth=True)
    rng = random.Random(87)
    for i in range(5):
        a = rng.uniform(0, math.tau)
        L = rng.uniform(0.18, 0.28)
        base = Vector((0.25, 0.12, Z + 0.19))
        tip = base + Vector((math.cos(a) * 0.08, math.sin(a) * 0.08, L))
        side = Vector((-math.sin(a), math.cos(a), 0.0)) * 0.006
        nrm = side.cross(tip - base).normalized() * 0.3
        mid = (base + tip) * 0.5
        poly(mb, [base - side, base + side, tip + side, tip - side], lambda p, n: (0.42, 0.33, 0.22), WOODM, 0, mid - nrm)
        poly(mb, [base - side, base + side, tip + side, tip - side], lambda p, n: (0.42, 0.33, 0.22), WOODM, 0, mid + nrm)
    return finish(mb, name, "BP_wood", (0.4, 0.35, 0.28))


# ============================================================ 飛び石
def stepstone(name, seed, sx=1.15, sy=0.9):
    mb = MB()
    jit = stone_jitter(seed, 0.035)
    prof = [(0.44, -0.62), (0.50, -0.25), (0.49, 0.02), (0.42, 0.15), (0.28, 0.20), (0.0, 0.215)]
    rings = []
    for (r, z) in prof:
        ring = []
        for j in range(13):
            a = math.tau * j / 13 + seed
            p = Vector((r * math.cos(a) * sx, r * math.sin(a) * sy, z))
            ring.append(p + jit(p * 1.7))
        rings.append(ring)
    loft_rings(mb, rings[:-1], grey, 0.75, -0.2, cap_bot=True)
    top = rings[-2]
    c = mb.v(rings[-1][0], (0, 0, 1), (0.6, 0.6, 0.58), (0, 0), (0.76, 0.0))
    ids = [mb.v(p, (0, 0, 1), (0.6, 0.6, 0.58), (p.x, p.y), (0.76, 0.0)) for p in top]
    for i in range(len(ids)):
        mb.tri(c, ids[i], ids[(i + 1) % len(ids)])
    return finish(mb, name, "BP_stone", (0.55, 0.55, 0.52))


# ============================================================ 倒れた燈籠用の部品（春日燈籠を中台上で二分）
def _lantern_part(name, keep):
    full = S["lantern"]("__tmp_lantern")
    me = full.data
    mb = MB()
    vmap = {}
    for poly_ in me.polygons:
        zs = [me.vertices[i].co.z for i in poly_.vertices]
        zc = sum(zs) / len(zs)
        if not keep(zc):
            continue
        ids = []
        for li in poly_.loop_indices:
            vi = me.loops[li].vertex_index
            if vi not in vmap:
                co = me.vertices[vi].co
                vmap[vi] = mb.v(co, me.vertices[vi].normal, (0.6, 0.6, 0.58), (co.x, co.z), (0.76, 0.0))
            ids.append(vmap[vi])
        for i in range(1, len(ids) - 1):
            mb.tri(ids[0], ids[i], ids[i + 1])
    bpy.data.objects.remove(full, do_unlink=True)
    bpy.data.meshes.remove(me)
    return finish(mb, name, "BP_stone", (0.55, 0.55, 0.52))


def lantern_low(name):
    return _lantern_part(name, lambda z: z < 1.205)


def lantern_top(name):
    return _lantern_part(name, lambda z: z >= 1.205)


# ============================================================ 竹籠
def basket(name):
    """背負い籠（竹）：下 r0.17 → 上 r0.27、高 0.50；網代の編み目＝頂點色の市松、縁は太い巻き。内側は暗い。"""
    mb = MB()
    rng = random.Random(97)
    def weave(p, n):
        a = math.atan2(p.y, p.x)
        u = int((a / math.tau + 0.5) * 22)
        v = int(p.z / 0.045)
        k = ((u + v) % 2) * 0.10 + rng.uniform(-0.02, 0.02)
        base = (0.56, 0.45, 0.27)
        return tuple(min(max(c * (0.88 + k), 0.0), 1.0) for c in base)
    prof = [(0.0, 0.0), (0.15, 0.0), (0.17, 0.03), (0.21, 0.20), (0.25, 0.38), (0.27, 0.48)]
    lathe(mb, prof, 22, weave, WOODM, smooth=True)
    inner = [(0.255, 0.48), (0.235, 0.38), (0.195, 0.20), (0.155, 0.04), (0.0, 0.04)]
    lathe(mb, inner, 22, lambda p, n: (0.16, 0.12, 0.08), WOODM, smooth=True)
    # 縁の巻き（トーラス状）
    rim = []
    for j in range(7):
        a = math.tau * j / 7
        rim.append((0.265 + 0.022 * math.cos(a), 0.48 + 0.022 * math.sin(a)))
    for j in range(7):
        r0, z0 = rim[j]
        r1, z1 = rim[(j + 1) % 7]
        lathe(mb, [(r0, z0), (r1, z1)], 22, lambda p, n: (0.50, 0.40, 0.24), WOODM, smooth=False)
    # 背負い紐（藁縄、二本）
    for sx in (-1, 1):
        pts = [Vector((sx * 0.10, -0.25, 0.44)), Vector((sx * 0.11, -0.33, 0.30)), Vector((sx * 0.10, -0.29, 0.12))]
        for i in range(len(pts) - 1):
            a, b = pts[i], pts[i + 1]
            d = (b - a).normalized()
            side = d.cross(Vector((0, 0, 1))).normalized() * 0.014
            up = d.cross(side).normalized() * 0.014
            q = [a - side, a + side, b + side, b - side]
            q2 = [x + up for x in q]
            for k in range(4):
                poly(mb, [q[k], q[(k + 1) % 4], q2[(k + 1) % 4], q2[k]], lambda p, n: (0.55, 0.47, 0.30), WOODM, 0, ((a + b) * 0.5 + up * 0.5).to_tuple())
    return finish(mb, name, "BP_wood", (0.5, 0.4, 0.25))


# ============================================================ 農具小屋・薪
def shed(name):
    """農具小屋（納屋）：W 4.6 × D 3.6 m、軒高 2.0、棟高 3.2（layout farm_hut の寸法）。原點＝地面中心、正面（入口）＝+Y。
    石の礎（束石）＋柱＋縦板張りの壁（板ごとに色と長さが違う）、正面は開いた入口＋片引きの板戸、切妻の板葺き屋根（押さえ木）。"""
    W, D = 4.6, 3.6
    EAVE, RIDGE = 2.05, 3.2
    mb = MB()
    rng = random.Random(201)
    WG = wood_grey(202, (0.33, 0.29, 0.24), 0.10)
    WD = wood_grey(203, (0.24, 0.20, 0.16))
    # 束石
    for sx in (-1, 1):
        for sy in (-1, 0, 1):
            cx, cy = sx * (W / 2 - 0.1), sy * (D / 2 - 0.1)
            lathe(mb, [(0.20, -0.15), (0.21, 0.06), (0.17, 0.12), (0.0, 0.13)], 7, grey, 0.75, center=(cx, cy), jitter=stone_jitter(rng.randint(1, 99), 0.015), smooth=False)
    # 土台・柱・桁
    for sy in (-1, 1):
        box(mb, (-W / 2, sy * (D / 2 - 0.1) - 0.07, 0.12), (W / 2, sy * (D / 2 - 0.1) + 0.07, 0.26), WD, WOODM, 1)
    for sx in (-1, 1):
        box(mb, (sx * (W / 2 - 0.1) - 0.07, -D / 2, 0.12), (sx * (W / 2 - 0.1) + 0.07, D / 2, 0.26), WD, WOODM, 1)
    for sx in (-1, 1):
        for sy in (-1, 0, 1):
            cx, cy = sx * (W / 2 - 0.1), sy * (D / 2 - 0.1)
            box(mb, (cx - 0.07, cy - 0.07, 0.12), (cx + 0.07, cy + 0.07, EAVE), WD, WOODM, 0)
    for sy in (-1, 1):
        box(mb, (-W / 2 - 0.25, sy * (D / 2 - 0.1) - 0.07, EAVE - 0.14), (W / 2 + 0.25, sy * (D / 2 - 0.1) + 0.07, EAVE), WD, WOODM, 1)
    # 縦板の壁：背面・両側面・正面（入口 1.6 m を残す）
    def boards(x0, x1, y, axis, z0, z1, skip=None):
        x = x0
        while x < x1 - 0.02:
            w = rng.uniform(0.18, 0.26)
            xe = min(x + w, x1)
            if not (skip and skip[0] < (x + xe) / 2 < skip[1]):
                zz1 = z1 + rng.uniform(-0.03, 0.0)
                col = wood_grey(rng.randint(300, 999), (0.32, 0.28, 0.23), 0.12)
                if axis == "x":
                    box(mb, (x, y - 0.012, z0), (xe - 0.006, y + 0.012, zz1), col, WOODM, 0)
                else:
                    box(mb, (y - 0.012, x, z0), (y + 0.012, xe - 0.006, zz1), col, WOODM, 0)
            x = xe
    boards(-W / 2 + 0.03, W / 2 - 0.03, -D / 2 + 0.03, "x", 0.18, EAVE - 0.12)
    for sx in (-1, 1):
        boards(-D / 2 + 0.05, D / 2 - 0.05, sx * (W / 2 - 0.03), "y", 0.18, EAVE - 0.12)
    boards(-W / 2 + 0.03, W / 2 - 0.03, D / 2 - 0.03, "x", 0.18, EAVE - 0.12, skip=(-0.95, 0.75))
    # 妻壁（三角）
    for sx in (-1, 1):
        x = sx * (W / 2 - 0.04)
        tri = [Vector((x, -D / 2, EAVE)), Vector((x, D / 2, EAVE)), Vector((x, 0.0, RIDGE - 0.05))]
        poly(mb, tri, WG, WOODM, 0, (x - sx * 0.3, 0.0, EAVE + 0.3))
        poly(mb, [p + Vector((-sx * 0.02, 0, 0)) for p in tri], WG, WOODM, 0, (x + sx * 0.3, 0.0, EAVE + 0.3))
    # 入口の中（暗い）＋片引きの板戸（半開き）
    box(mb, (-0.95, -D / 2 + 0.2, 0.18), (0.75, -D / 2 + 0.22, EAVE - 0.14), lambda p, n: (0.05, 0.045, 0.04), WOODM, 0)
    box(mb, (0.75, D / 2 + 0.01, 0.2), (1.75, D / 2 + 0.05, EAVE - 0.18), wood_grey(207, (0.30, 0.26, 0.21)), WOODM, 0)
    box(mb, (-0.95, D / 2 - 0.05, EAVE - 0.26), (0.75, D / 2 + 0.05, EAVE - 0.14), WD, WOODM, 1)     # 鴨居
    # 切妻屋根：板葺き（段々に重ねた板の列）＋押さえ木 3 本
    ex, ey = W / 2 + 0.45, D / 2 + 0.55
    for sy in (-1, 1):
        rows = 7
        for r in range(rows):
            t0, t1 = r / rows, (r + 1) / rows + 0.04
            za = RIDGE - (RIDGE - (EAVE - 0.1)) * t0
            zb = RIDGE - (RIDGE - (EAVE - 0.1)) * min(t1, 1.0)
            ya, yb = sy * ey * t0, sy * ey * min(t1, 1.0)
            dz = rng.uniform(-0.01, 0.01)
            a = [Vector((-ex, ya, za + 0.03 + dz)), Vector((ex, ya, za + 0.03 + dz)), Vector((ex, yb, zb + dz)), Vector((-ex, yb, zb + dz))]
            b = [p + Vector((0, 0, 0.035)) for p in a]
            ctr = (0.0, (ya + yb) / 2, (za + zb) / 2)
            col = wood_grey(400 + r * 2 + (sy > 0), (0.27, 0.24, 0.21), 0.14)
            poly(mb, a, col, WOODM, 1, (0.0, (ya + yb) / 2, (za + zb) / 2 + 0.6))
            poly(mb, b, col, WOODM, 1, (0.0, (ya + yb) / 2, (za + zb) / 2 - 0.6))
            poly(mb, [a[2], a[3], b[3], b[2]], col, WOODM, 1, (0.0, (ya + yb) / 2 - sy * 0.3, (za + zb) / 2))
        for k in (0.3, 0.62, 0.9):
            yy = sy * ey * k
            zz = RIDGE - (RIDGE - (EAVE - 0.1)) * k + 0.1
            r_ = 0.045
            prof = [(yy + r_ * math.cos(a_), r_ * math.sin(a_)) for a_ in [math.tau * q / 6 for q in range(6)]]
            loft_x(mb, [-ex - 0.1 + (2 * ex + 0.2) * q / 6 for q in range(7)], prof, lambda x, zz=zz: zz, wood_grey(500 + int(k * 10), (0.30, 0.26, 0.21)), WOODM)
    box(mb, (-ex - 0.05, -0.09, RIDGE + 0.02), (ex + 0.05, 0.09, RIDGE + 0.16), WD, WOODM, 1)
    # 立てかけた農具（鍬・竹箒）を背面右に
    for k in range(2):
        x = W / 2 - 0.6 - k * 0.35
        base = Vector((x, D / 2 + 0.25, 0.0))
        top = Vector((x - 0.05, D / 2 + 0.04, 1.45 - k * 0.15))
        d = (top - base).normalized()
        side = Vector((1, 0, 0)) * 0.018
        q = [base - side, base + side, top + side, top - side]
        q2 = [p + Vector((0, 0.03, 0)) for p in q]
        for i in range(4):
            poly(mb, [q[i], q[(i + 1) % 4], q2[(i + 1) % 4], q2[i]], wood_fresh(600 + k), WOODM, 0, ((base + top) * 0.5 + Vector((0, 0.015, 0))).to_tuple())
    return finish(mb, name, "BP_wood", (0.35, 0.3, 0.25))


def firewood(name):
    """薪の山：割った薪（三角・半月断面）を三段に積む。長さ 1.0 m 沿 Y（Godot Z）、幅 0.9、高 0.55。"""
    mb = MB()
    rng = random.Random(211)
    for row in range(3):
        n = 5 - row
        for i in range(n):
            x = (i - (n - 1) / 2) * 0.18 + rng.uniform(-0.02, 0.02)
            z = 0.09 + row * 0.15
            r = rng.uniform(0.07, 0.09)
            k = rng.randint(0, 2)
            if k == 0:
                prof = [(x + r * math.cos(a), z + r * math.sin(a)) for a in [math.tau * q / 7 for q in range(7)]]
            elif k == 1:
                prof = [(x + r * math.cos(a), z + r * math.sin(a)) for a in [math.pi * q / 5 for q in range(6)]]
            else:
                prof = [(x - r, z - r * 0.6), (x + r, z - r * 0.6), (x + r * 0.2, z + r * 0.9)]
            ring0 = [Vector((px, -0.5 + rng.uniform(-0.04, 0.04), pz)) for px, pz in prof]
            ring1 = [Vector((px, 0.5 + rng.uniform(-0.04, 0.04), pz)) for px, pz in prof]
            ctr = (x, 0.0, z)
            bark = wood_grey(700 + row * 10 + i, (0.30, 0.25, 0.19), 0.15)
            for q in range(len(prof)):
                q2 = (q + 1) % len(prof)
                poly(mb, [ring0[q], ring0[q2], ring1[q2], ring1[q]], bark, WOODM, 0, ctr)
            end = lambda p, n_: (0.62, 0.50, 0.34)
            poly(mb, ring0, end, WOODM, 0, (x, 0.3, z))
            poly(mb, ring1, end, WOODM, 0, (x, -0.3, z))
    return finish(mb, name, "BP_wood", (0.4, 0.33, 0.25))


# ============================================================ 清單
ITEMS = [
    ("bp_step_stone_a", "step", lambda n: step_stone(n, 101)),
    ("bp_step_stone_b", "step", lambda n: step_stone(n, 102)),
    ("bp_step_stone_c", "step", lambda n: step_stone(n, 103)),
    ("bp_step_stone_d", "step", lambda n: step_stone(n, 104)),
    ("bp_step_stone_e", "step", lambda n: step_stone(n, 105)),
    ("bp_step_log_a", "step", lambda n: step_log(n, 111)),
    ("bp_step_log_b", "step", lambda n: step_log(n, 112)),
    ("bp_step_log_c", "step", lambda n: K["log"](n, 113, 2.4, 0.115, 0.10, nlen=14, nrad=11, stub=False, split_end=False)),
    ("bp_step_log_d", "step", lambda n: K["log"](n, 114, 2.3, 0.12, 0.105, nlen=14, nrad=11, stub=False, split_end=False)),
    ("bp_bridge_a", "arch", bridge),
    ("bp_bridge_a_abut", "arch_stone", bridge_abut),
    ("bp_hokora_a", "arch", hokora),
    ("bp_hokora_a_base", "arch_stone", hokora_base),
    ("bp_signpost_a", "arch", signpost),
    ("bp_signpost_board", "arch", signpost_board),
    ("bp_marker_a", "arch_stone", marker),
    ("bp_fence_post_a", "arch", fence_post),
    ("bp_fence_rail_a", "arch", fence_rail),
    ("bp_gate_a", "arch", gate),
    ("bp_offering_stone", "arch_stone", offering_stone),
    ("bp_offering_a", "arch", offering),
    ("bp_stepstone_a", "rock", lambda n: stepstone(n, 131)),
    ("bp_stepstone_b", "rock", lambda n: stepstone(n, 137, 0.95, 0.85)),
    ("bp_basket_a", "arch", basket),
    ("bp_shed_a", "arch", shed),
    ("bp_firewood_a", "arch", firewood),
    ("s01_lantern_a_low", "arch_stone", lantern_low),
    ("s01_lantern_a_top", "arch_stone", lantern_top),
]


def build_all(export=True, only=None):
    c = coll()
    for ob in list(c.objects):
        if any(ob.name == n for n, _, _ in ITEMS):
            me = ob.data
            bpy.data.objects.remove(ob, do_unlink=True)
            if me is not None and getattr(me, "users", 1) == 0:
                bpy.data.meshes.remove(me)
    built = []
    for name, cat, fn in ITEMS:
        if only and name not in only:
            continue
        built.append((fn(name), cat))
    man = {}
    for ob, cat in built:
        me = ob.data
        xs = [v.co.x for v in me.vertices]
        ys = [v.co.y for v in me.vertices]
        zs = [v.co.z for v in me.vertices]
        man[ob.name] = {"category": cat, "tris": sum(len(p.vertices) - 2 for p in me.polygons), "verts": len(me.vertices),
                        "size_m": [round(max(xs) - min(xs), 3), round(max(ys) - min(ys), 3), round(max(zs) - min(zs), 3)],
                        "z_min": round(min(zs), 3), "z_max": round(max(zs), 3)}
        if export:
            os.makedirs(GLB_DIR, exist_ok=True)
            for o in bpy.data.objects:
                if o is not None and o.name in bpy.context.view_layer.objects:
                    o.select_set(False)
            ob.select_set(True)
            bpy.context.view_layer.objects.active = ob
            bpy.ops.export_scene.gltf(filepath=GLB_DIR + "/" + ob.name + ".glb", export_format='GLB', use_selection=True, export_apply=True,
                                      export_yup=True, export_vertex_color='ACTIVE', export_all_vertex_colors=False, export_normals=True,
                                      export_texcoords=True, export_materials='PLACEHOLDER', export_extras=False)
    if export and not only:
        with open(SRC_DIR + "/props_manifest.json", "w", encoding="utf-8") as f:
            json.dump({"generator": "assets/beast_path/s01_kit/src/build_bp_props.py", "blender": bpy.app.version_string, "assets": man}, f, ensure_ascii=False, indent=1)
        bpy.ops.wm.save_as_mainfile(filepath=SRC_DIR + "/bp_props.blend", copy=True)
    return man


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for o in list(bpy.data.objects):
        if o.type == 'MESH' and (o.users_collection and o.users_collection[0].name != K["COLL"]):
            bpy.data.objects.remove(o, do_unlink=True)
    only = None
    for a in argv:
        if a.startswith("--only="):
            only = a[7:].split(",")
    man = build_all(export=("--no-export" not in argv), only=only)
    for a in argv:
        if a.startswith("--preview="):
            base = a[10:]
            K["preview"](base + "_big.png", ["bp_bridge_a", "bp_bridge_a_abut", "bp_hokora_a_base", "bp_hokora_a", "bp_gate_a", "bp_signpost_a"], cols=3, cam_back=16, cam_h=5.0, lens=40)
            K["preview"](base + "_small.png", ["bp_step_stone_a", "bp_step_stone_b", "bp_step_log_a", "bp_marker_a", "bp_fence_post_a", "bp_fence_rail_a",
                                              "bp_offering_stone", "bp_offering_a", "bp_stepstone_a", "bp_signpost_board", "s01_lantern_a_low", "s01_lantern_a_top"], cols=6, cam_back=4.5, cam_h=1.6, lens=40)
    for k, v in man.items():
        print("[props] %-20s %-10s tris=%6d size=%s z=[%.2f, %.2f]" % (k, v["category"], v["tris"], v["size_m"], v["z_min"], v["z_max"]))

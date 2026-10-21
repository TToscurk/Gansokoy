"""博麗神社 r3 重製：版面常數（單一事實來源）。

座標：x 東、z 南（玩家從南邊 +z 入、往北 -z 上山）、y 上。主軸 x=0。
gen_terrain.py / 其他生成器 import 這份；GDScript 端讀 maps/shrine_v2/gen/layout.json（由 gen_terrain.py 寫出）。
"""
from __future__ import annotations

import math

import numpy as np

SEED = 20261021

# ── 高度 ───────────────────────────────────────────────
Y_C = 8.32            # 境內（庭院）地面高 = 最後一階踏面頂 = 52 × 0.16
Y_FOOT = 0.0          # 石階腳地面高

# ── 石階（沿用委製石階套件的 3.2 m 雙排配置；級高/級深落在規格 §23 內）──
RISE = 0.16
RUN = 0.38
STAIR_W = 3.2          # 踏面可用寬
BED_HALF = 2.05        # 踏面半寬 1.6 + 袖石垣厚 0.45
FLIGHTS = [11, 10, 11, 10, 10]   # 5 段 52 階（規格建議每段 5–12 階）
LANDING = 2.2          # 中間平台深（規格 1.2–2.5）
Z_FOOT = 33.0          # 第一階前緣 z

# ── 玩家可活動範圍（邊界牆）──
PLAY = dict(x0=-57.0, x1=57.0, z0=-66.0, z1=80.0)
# 近景地形範圍（比 PLAY 大，牆外還有地形不露邊）
TERRAIN = dict(x0=-80.0, x1=80.0, z0=-92.0, z1=100.0, step=0.8)

# ── 參道（入口山路）控制點 (x, z, y)：南端傳送點 → 石階腳 ──
APPROACH = [
    (-5.0, 84.0, -2.00),
    (-4.0, 76.0, -1.85),
    (-1.0, 66.0, -1.50),
    (3.0, 56.0, -1.05),
    (3.6, 48.0, -0.65),
    (1.6, 41.0, -0.28),
    (0.0, 36.0, -0.06),
    (0.0, Z_FOOT, Y_FOOT),
]
APPROACH_HALF = 2.0   # 路基半寬（可走寬度約 3 m + 兩側路肩）

# ── 平台（境內＋後方）多邊形 (x, z)，順時針從前左起 ──
PLATEAU = [
    (-9.0, 4.44), (-14.5, 1.2), (-18.0, -4.0), (-20.5, -11.0), (-19.0, -19.0), (-22.0, -27.0),
    (-19.5, -35.0), (-14.0, -41.0), (-5.0, -43.5), (3.0, -47.0), (12.0, -47.5), (19.0, -43.0),
    (23.5, -35.0), (24.5, -27.0), (22.5, -19.0), (24.0, -11.0), (20.5, -4.0), (14.5, 0.8), (9.0, 4.44),
]

# ── 池塘 ──
POND = dict(cx=12.5, cz=-39.5, rx=7.5, rz=5.0, rot_deg=-20.0, level=Y_C - 0.5, depth=1.3)

# ── 林間步道（庭院西側 → 拜殿後方 → 池塘西岸）：夯土、無樹、無下層植栽。(x, z)，皆在平台內 ──
TRAIL = [(-18.0, -9.5), (-22.8, -11.2), (-24.9, -14.5), (-24.6, -19.5), (-25.3, -25.0), (-25.9, -30.0),
         (-24.6, -35.0), (-21.3, -39.6), (-17.6, -43.2), (-13.4, -45.9), (-8.8, -47.5), (-4.4, -49.2),
         (0.4, -50.6), (5.5, -52.0), (9.0, -51.8)]
# 林間步道：從庭院西緣出發，沿平台外 ≈3.5 m 的坡腰繞過拜殿後方（路基切在坡上，見 gen_terrain.carve_trail）
TRAIL_HALF = 1.1

# ── 建築與主要物件（x, z）；高度由地形決定 ──
# 拜殿 z=-28：與舊版 waypoints（拜殿 0,-28；拜訪點 0,-21）一致，不用改任務導航座標。
PLACE = dict(
    torii=(0.0, 1.0),
    haiden=(0.0, -28.0),
    temizuya=(-11.5, -3.0),      # 面向 +x（朝參道）
    storehouse=(16.0, -22.0),    # 面向 +z（南），在庭院東側
    saisen=(0.0, -22.7),         # 賽錢箱：拜殿正面石階前 1.5 m
)
# 建築腳印（中心 x,z；半寬 hx、半深 hz；已含屋簷／台階），樹木與散佈避讓用
FOOTPRINT = dict(
    haiden=(0.0, -28.0, 5.0, 4.4),
    storehouse=(16.0, -21.4, 2.5, 2.7),
    temizuya=(-11.5, -3.0, 1.9, 1.9),
    torii=(0.0, 1.0, 5.0, 1.1),
)


def stair_plan():
    """回傳 (treads, landings, z_end)。z 往北遞減。"""
    treads, landings = [], []
    z = Z_FOOT
    k = 0
    for f, n in enumerate(FLIGHTS):
        for _ in range(n):
            zf, zb = z, z - RUN
            treads.append(dict(k=k, flight=f, z_front=zf, z_back=zb, zc=(zf + zb) / 2,
                               y_top=Y_FOOT + RISE * (k + 1)))
            z = zb
            k += 1
        if f < len(FLIGHTS) - 1:
            landings.append(dict(idx=f, z_front=z, z_back=z - LANDING, zc=z - LANDING / 2,
                                 y=Y_FOOT + RISE * k))
            z -= LANDING
    return treads, landings, z


def stair_bed_curve():
    """石階底下的土床折線 [(z, y)]（z 由南到北遞減）：踏石底面 / 平台石底面高。"""
    treads, landings, _ = stair_plan()
    pts = [(Z_FOOT + 0.3, Y_FOOT - 0.02)]
    for t in treads:
        pts.append((t["zc"], t["y_top"] - RISE))
    for l in landings:
        pts.append((l["zc"], l["y"] - 0.16))
    pts.sort(key=lambda p: -p[0])
    return pts


def stair_bed_smooth():
    """石階土床的平滑中線 [(z, y)]（z 由南到北遞減）。

    每段梯跑取「各階底面中點」連成斜線再下沉 0.09 m（地形永遠略低於踏石底面、不穿出石面，
    起伏 ≤ ±0.08 m 的差由石階下的實心填塊補上）；平台段為水平線（平台石底面 - 0.09）。
    """
    treads, landings, _ = stair_plan()
    sink = 0.09
    pts = [(Z_FOOT + 0.3, Y_FOOT - 0.02)]
    by_flight = {}
    for t in treads:
        by_flight.setdefault(t["flight"], []).append(t)
    for f in sorted(by_flight):
        ts = by_flight[f]
        pts.append((ts[0]["zc"], ts[0]["y_top"] - RISE - sink))
        pts.append((ts[-1]["zc"], ts[-1]["y_top"] - RISE - sink))
        if f < len(landings):
            l = landings[f]
            pts.append((l["z_front"], l["y"] - RISE - sink))
            pts.append((l["z_back"], l["y"] - RISE - sink))
    pts.sort(key=lambda p: -p[0])
    return pts


def catmull_rom(points, step=0.5):
    """Catmull-Rom 取樣 [(x,z,y)] → ndarray (n,3)，約等距 step。"""
    p = np.array(points, float)
    p = np.vstack([p[0] + (p[0] - p[1]), p, p[-1] + (p[-1] - p[-2])])
    out = []
    for i in range(1, len(p) - 2):
        p0, p1, p2, p3 = p[i - 1], p[i], p[i + 1], p[i + 2]
        n = max(2, int(np.linalg.norm(p2[:2] - p1[:2]) / step * 1.0))
        for t in np.linspace(0, 1, n, endpoint=False):
            t2, t3 = t * t, t * t * t
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
                              + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    out.append(p[-2])
    return np.array(out)


def chaikin(poly, iters=2):
    pts = [tuple(p) for p in poly]
    for _ in range(iters):
        new = []
        n = len(pts)
        for i in range(n):
            a, b = pts[i], pts[(i + 1) % n]
            new.append((0.75 * a[0] + 0.25 * b[0], 0.75 * a[1] + 0.25 * b[1]))
            new.append((0.25 * a[0] + 0.75 * b[0], 0.25 * a[1] + 0.75 * b[1]))
        pts = new
    return pts

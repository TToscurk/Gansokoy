"""博麗神社 v3 建築與道具（全部從零建模；Godot 空間撰寫，見 s3b.py）。
  "D:/Blender/blender-5.2.1-windows-x64/blender.exe" -b --factory-startup --python godot/assets/shrine_v3/src/make_arch.py
輸出：
  godot/assets/shrine_v3/models/<name>.glb        單一網格、多材質（材質只有名字；Godot 端換成 assets/shrine_v3/mat/*.tres）
  godot/assets/shrine_v3/models/<name>.json       碰撞（Godot 空間）、標記、尺寸、面數
  godot/assets/shrine_v3/src/shrine_v3_arch.blend Blender 原始檔
設計值：docs/shrine_v3/00_空間判讀.md（拜殿 6.0×4.2 m 主體、地板 0.8 m、總高約 5.9 m；鳥居笠木 5.6 m、高 4.65 m）。
"""
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np  # noqa: E402

import s3b  # noqa: E402
from s3b import T, Rx, Ry, Rz, Builder, frame  # noqa: E402

GODOT = os.path.abspath(os.path.join(HERE, '..', '..', '..'))
OUT = os.path.join(GODOT, 'assets', 'shrine_v3', 'models')
os.makedirs(OUT, exist_ok=True)

PI = math.pi


# ───────────────────────── 屋頂工具 ─────────────────────────
class Prof:
    """屋面縱斷：y = ye + a·d + k·d²（d＝自簷口往內的水平距離），下凹曲線（簷口緩、近棟陡）。"""

    def __init__(self, ye, a, k):
        self.ye, self.a, self.k = ye, a, k

    def y(self, d):
        return self.ye + self.a * d + self.k * d * d

    def s(self, d):
        # 弧長（數值積分）
        n = 24
        tot = 0.0
        for i in range(n):
            d0 = d * i / n
            d1 = d * (i + 1) / n
            dm = (d0 + d1) * 0.5
            sl = self.a + 2 * self.k * dm
            tot += (d1 - d0) * math.sqrt(1 + sl * sl)
        return tot


def _orient(q, want):
    Q = np.array(q, float)
    n = np.cross(Q[1] - Q[0], Q[2] - Q[0])
    if np.dot(n, want) < 0:
        return q[::-1], True
    return q, False


def _quad(b, q, uv, mat, want, col):
    q2, fl = _orient(q, want)
    b.poly(q2, uv[::-1] if fl else uv, mat, False, col)


def roof_slope(b, M, xm_fn, d_list, prof, mat, t, ncol=14, top=True, soffit_to=None, col=0.95, patch=None, clip=None):
    """local：簷口在 z=+Ze 那側往 −z 升高。xm_fn(d)→該排半寬；點 (x, y(d), Ze−d) 由呼叫端給 Ze（含在 M 裡：local z=0 是簷口）。
    這裡 local 座標：簷口線 z=0，往內 z=−d。"""
    for i in range(len(d_list) - 1):
        d0, d1 = d_list[i], d_list[i + 1]
        c0 = clip(d0) if clip else 0.0
        c1 = clip(d1) if clip else 0.0
        if c0 <= 0.0 and c1 <= 0.0:
            segs = [(np.linspace(-xm_fn(d0), xm_fn(d0), ncol + 1), np.linspace(-xm_fn(d1), xm_fn(d1), ncol + 1))]
        else:
            h = max(ncol // 2, 2)
            segs = [(np.linspace(-xm_fn(d0), -c0, h + 1), np.linspace(-xm_fn(d1), -c1, h + 1)),
                    (np.linspace(c0, xm_fn(d0), h + 1), np.linspace(c1, xm_fn(d1), h + 1))]
        for (x0, x1) in segs:
          for j in range(len(x0) - 1):
              for layer in ((0.0, (0, 1, 0)),) if top else ():
                  off, want = layer
                  q = [(x0[j], prof.y(d0), -d0), (x0[j + 1], prof.y(d0), -d0), (x1[j + 1], prof.y(d1), -d1), (x1[j], prof.y(d1), -d1)]
                  uv = [(x0[j], prof.s(d0)), (x0[j + 1], prof.s(d0)), (x1[j + 1], prof.s(d1)), (x1[j], prof.s(d1))]
                  c = col
                  if patch is not None and patch(0.5 * (x0[j] + x1[j]), 0.5 * (d0 + d1)):
                      c = col * 1.22
                  Q = s3b._xf(M, q)
                  wantw = M[:3, :3] @ np.array([0, 1, 0.3])
                  _quad(b, list(Q), uv, mat, wantw, c)
              if soffit_to is not None and d1 <= soffit_to + 1e-6:
                  q = [(x0[j], prof.y(d0) - t, -d0), (x0[j + 1], prof.y(d0) - t, -d0), (x1[j + 1], prof.y(d1) - t, -d1), (x1[j], prof.y(d1) - t, -d1)]
                  uv = [(x0[j], d0), (x0[j + 1], d0), (x1[j + 1], d1), (x1[j], d1)]
                  Q = s3b._xf(M, q)
                  _quad(b, list(Q), uv, 's3_wood_old', M[:3, :3] @ np.array([0, -1, 0]), 0.62)


def fascia(b, M, pts_top, t, mat, want_local, col=0.8):
    """沿屋緣的厚度條：pts_top＝local 上緣點，往下 t。"""
    for i in range(len(pts_top) - 1):
        a = np.array(pts_top[i], float)
        c = np.array(pts_top[i + 1], float)
        q = [a - [0, t, 0], c - [0, t, 0], c, a]
        L0 = float(np.linalg.norm(c - a))
        uv = [(0, 0), (L0, 0), (L0, t), (0, t)]
        Q = s3b._xf(M, q)
        _quad(b, list(Q), uv, mat, M[:3, :3] @ np.asarray(want_local, float), col)


def rafters(b, M, xs, prof, d_from, d_to_fn, t, w=0.07, h=0.09, mat='s3_wood_old'):
    """簷下垂木：local x 位置 xs；自簷口 d_from 到 d_to_fn(x)，貼在屋底下（y(d)−t−h/2）。"""
    for x in xs:
        d1 = d_to_fn(x)
        if d1 <= d_from + 0.05:
            continue
        p0 = (x, prof.y(d_from) - t - h * 0.5 + 0.005, -d_from - 0.02)
        p1 = (x, prof.y(d1) - t - h * 0.5, -d1)
        P0 = s3b._xf(M, [p0])[0]
        P1 = s3b._xf(M, [p1])[0]
        b.beam(P0, P1, w, h, mat, bevel=0.008)


# ───────────────────────── 拜殿 ─────────────────────────
def build_haiden():
    b = Builder('haiden', seed=11)
    XS = [-3.0, -1.0, 1.0, 3.0]
    ZS = [-2.1, 0.0, 2.1]
    BASE_Y = 0.24
    FLOOR_Y = 0.82
    VER_Y = 0.78
    HEAD_Y = 3.12
    # 基壇（葛石＋夯土），前方延伸承接木階與向拜柱
    rect = [(-4.0, -3.0), (4.0, -3.0), (4.0, 3.25), (1.85, 3.25), (1.85, 4.85), (-1.85, 4.85), (-1.85, 3.25), (-4.0, 3.25)]
    b.prism(np.eye(4), [(x, z) for x, z in rect], -0.30, BASE_Y - 0.02, 's3_earth', col=1.0)
    # 葛石（邊石）：沿基壇邊緣一圈 0.30 寬
    n = len(rect)
    for i in range(n):
        a = np.array(rect[i])
        c = np.array(rect[(i + 1) % n])
        L = float(np.linalg.norm(c - a))
        k = max(1, int(L / 1.1))
        for j in range(k):
            pa = a + (c - a) * (j / k)
            pc = a + (c - a) * ((j + 1) / k)
            d = (pc - pa) / max(np.linalg.norm(pc - pa), 1e-9)
            nrm = np.array([d[1], -d[0]])   # 右手側＝外側（rect 逆時針從上看）
            # 往內縮 0.15（石條中心）
            m0 = pa - nrm * 0.15
            m1 = pc - nrm * 0.15
            jit = b.rng.uniform(-0.012, 0.012)
            b.beam((m0[0], BASE_Y - 0.12 + jit, m0[1]), (m1[0], BASE_Y - 0.12 + jit, m1[1]), 0.30, 0.30, 's3_stone', bevel=0.03, ext=-0.008)
    b.col_box(T(0, (BASE_Y - 0.30) / 2, 0.125), (8.0, BASE_Y + 0.30, 6.25), '基壇')
    b.col_box(T(0, (BASE_Y - 0.30) / 2, 4.05), (3.7, BASE_Y + 0.30, 1.6), '基壇前伸')
    # 礎石＋柱
    posts = [(x, z) for x in XS for z in (ZS[0], ZS[2])] + [(-3.0, 0.0), (3.0, 0.0)]
    for (x, z) in posts:
        oct_ = [(0.26 * math.cos(a) * b.rng.uniform(0.9, 1.08), 0.26 * math.sin(a) * b.rng.uniform(0.9, 1.08)) for a in np.linspace(0, 2 * PI, 9)[:-1]]
        b.prism(T(x, 0, z) @ Ry(b.rng.uniform(0, 1)), oct_, BASE_Y - 0.10, BASE_Y + 0.08, 's3_stone', cap_top=True)
        b.box(T(x, (BASE_Y + 0.08 + HEAD_Y) / 2, z), 0.20, HEAD_Y - BASE_Y - 0.08, 0.20, 's3_wood_old', bevel=0.02, grain='y')
    # 足固め（地板下的橫材）
    for z in (ZS[0], ZS[2]):
        b.beam((-3.1, 0.62, z), (3.1, 0.62, z), 0.12, 0.17, 's3_wood_old')
    for x in (-3.0, 3.0):
        b.beam((x, 0.62, -2.2), (x, 0.62, 2.2), 0.12, 0.17, 's3_wood_old')
    # 地板（內部看不到，做一塊）
    b.box(T(0, FLOOR_Y - 0.03, 0), 6.0, 0.06, 4.2, 's3_wood_old', grain='x')
    # 縁（前、左、右），縁束＋縁葛＋縁板
    # 前縁：z 2.1→3.0、x −3.9..3.9；側縁：x ±3.0→±3.9、z −2.1..2.1
    for i, x in enumerate(np.linspace(-3.85, 3.85, 9)):
        b.prism(T(x, 0, 2.95), [(0.14 * math.cos(a), 0.14 * math.sin(a)) for a in np.linspace(0, 2 * PI, 7)[:-1]], BASE_Y - 0.06, BASE_Y + 0.06, 's3_stone')
        b.box(T(x, (BASE_Y + 0.06 + VER_Y - 0.1) / 2, 2.95), 0.12, VER_Y - 0.1 - BASE_Y - 0.06, 0.12, 's3_wood_old', bevel=0.012, grain='y')
    for sx in (-1, 1):
        for z in np.linspace(-1.95, 1.6, 4):
            b.prism(T(sx * 3.85, 0, z), [(0.14 * math.cos(a), 0.14 * math.sin(a)) for a in np.linspace(0, 2 * PI, 7)[:-1]], BASE_Y - 0.06, BASE_Y + 0.06, 's3_stone')
            b.box(T(sx * 3.85, (BASE_Y + 0.06 + VER_Y - 0.1) / 2, z), 0.12, VER_Y - 0.1 - BASE_Y - 0.06, 0.12, 's3_wood_old', bevel=0.012, grain='y')
    b.beam((-3.95, VER_Y - 0.11, 2.95), (3.95, VER_Y - 0.11, 2.95), 0.13, 0.15, 's3_wood_old')
    for sx in (-1, 1):
        b.beam((sx * 3.85, VER_Y - 0.11, -2.2), (sx * 3.85, VER_Y - 0.11, 3.0), 0.13, 0.15, 's3_wood_old')
    # 縁板：前縁沿 x、側縁沿 z（每片 0.22 寬、2 mm 縫）
    zz = 2.12
    while zz < 3.0:
        w = min(0.22, 3.02 - zz)
        mat = 's3_wood_new' if b.rng.random() < 0.10 else 's3_wood_old'   # 少數換過的新板（修補痕跡）
        b.box(T(0, VER_Y - 0.02, zz + w / 2), 7.9, 0.04, w - 0.004, mat, bevel=0.004, grain='x')
        zz += w
    for sx in (-1, 1):
        xx = 3.02
        while xx < 3.94:
            w = min(0.22, 3.96 - xx)
            mat = 's3_wood_new' if b.rng.random() < 0.10 else 's3_wood_old'
            b.box(T(sx * (xx + w / 2), VER_Y - 0.02, -0.05), w - 0.004, 0.04, 4.3, mat, bevel=0.004, grain='z')
            xx += w
    b.col_box(T(0, (BASE_Y + VER_Y) / 2, 0.4), (7.9, VER_Y - BASE_Y, 5.2), '縁')
    # 高欄（側縁全段、前縁兩側；中間 2.4 m 留給木階）
    RAIL_H = 0.60
    def rail_run(p0, p1, posts_n):
        p0 = np.array(p0, float)
        p1 = np.array(p1, float)
        for k in range(posts_n + 1):
            p = p0 + (p1 - p0) * (k / posts_n)
            b.box(T(p[0], VER_Y + RAIL_H / 2, p[1]), 0.08, RAIL_H, 0.08, 's3_wood_old', bevel=0.01, grain='y')
        for hy, hh, ww in ((VER_Y + RAIL_H - 0.03, 0.06, 0.07), (VER_Y + 0.30, 0.05, 0.05)):
            b.beam((p0[0], hy, p0[1]), (p1[0], hy, p1[1]), ww, hh, 's3_wood_old', ext=0.04)
        d = p1 - p0
        L = float(np.linalg.norm(d))
        ang = math.atan2(d[0], d[1])
        cx, cz = (p0 + p1) / 2
        b.col_box(T(cx, VER_Y + RAIL_H / 2, cz) @ Ry(ang), (0.10, RAIL_H, L + 0.08), '高欄')
    rail_run((-3.92, -2.15), (-3.92, 2.98), 4)
    rail_run((3.92, -2.15), (3.92, 2.98), 4)
    rail_run((-3.92, 2.98), (-1.25, 2.98), 2)
    rail_run((1.25, 2.98), (3.92, 2.98), 2)
    # 木階：縁(0.78) → 基壇(0.24)，4 段，踏面 0.30，寬 2.2
    rise = (VER_Y - BASE_Y) / 4.0
    for k in range(4):
        ytop = VER_Y - rise * (k + 1)
        z0 = 3.0 + 0.30 * k
        b.box(T(0, ytop - 0.025, z0 + 0.16), 2.2, 0.05, 0.33, 's3_wood_old', bevel=0.006, grain='x')
        b.box(T(0, ytop - rise / 2, z0 + 0.30), 2.2, rise - 0.05, 0.025, 's3_wood_old', grain='x')
    for sx in (-1, 1):
        b.beam((sx * 1.13, VER_Y - 0.02, 2.98), (sx * 1.13, BASE_Y + 0.04, 4.22), 0.07, 0.24, 's3_wood_old', up=(0, 1, 0))
    st_len = math.hypot(1.2, VER_Y - BASE_Y)
    b.col_box(T(0, (VER_Y + BASE_Y) / 2 - 0.12, 3.6) @ Rx(math.atan2(VER_Y - BASE_Y, 1.2)), (2.2, 0.24, st_len + 0.05), '木階坡')
    # 牆：地覆、內法長押、頭貫；側背板壁；正面格子戸／蔀
    for z, xr in ((ZS[0], (-3.0, 3.0)), (ZS[2], (-3.0, 3.0))):
        b.beam((xr[0] - 0.1, FLOOR_Y + 0.05, z), (xr[1] + 0.1, FLOOR_Y + 0.05, z), 0.16, 0.10, 's3_wood_old')
        b.beam((xr[0] - 0.12, 2.36, z), (xr[1] + 0.12, 2.36, z), 0.12, 0.12, 's3_wood_old')
        b.beam((xr[0] - 0.28, HEAD_Y - 0.09, z), (xr[1] + 0.28, HEAD_Y - 0.09, z), 0.14, 0.18, 's3_wood_old')   # 頭貫＋木鼻
    for x in (-3.0, 3.0):
        b.beam((x, FLOOR_Y + 0.05, -2.2), (x, FLOOR_Y + 0.05, 2.2), 0.16, 0.10, 's3_wood_old')
        b.beam((x, 2.36, -2.22), (x, 2.36, 2.22), 0.12, 0.12, 's3_wood_old')
        b.beam((x, HEAD_Y - 0.09, -2.38), (x, HEAD_Y - 0.09, 2.38), 0.14, 0.18, 's3_wood_old')
    def board_wall(p0, p1, y0, y1, mat='s3_wood_old', inset=0.0):
        p0 = np.array(p0, float)
        p1 = np.array(p1, float)
        d = p1 - p0
        L = float(np.linalg.norm(d))
        ang = math.atan2(d[0], d[1])
        c = (p0 + p1) / 2
        b.box(T(c[0], (y0 + y1) / 2, c[1]) @ Ry(ang), 0.035, y1 - y0, L, mat, bevel=0.0, grain='y')
    for z in (ZS[0],):
        for i in range(3):
            board_wall((XS[i] + 0.10, z), (XS[i + 1] - 0.10, z), FLOOR_Y + 0.10, HEAD_Y - 0.18)
    for sx in (-1, 1):
        for i in range(2):
            mat = 's3_wood_new' if (sx == 1 and i == 0) else 's3_wood_old'   # 東側一間新換的板壁（修補）
            board_wall((sx * 3.0, ZS[i] + 0.10), (sx * 3.0, ZS[i + 1] - 0.10), FLOOR_Y + 0.10, HEAD_Y - 0.18, mat)
    # 正面：中間格子戸（雙扇），兩側下板＋上格子
    zf = ZS[2]
    def lattice(x0, x1, y0, y1, zc, pitch=0.11, bar=0.028):
        # 內側暗面
        b.box(T((x0 + x1) / 2, (y0 + y1) / 2, zc - 0.05), x1 - x0, y1 - y0, 0.02, 's3_interior', grain='x', col=1.0)
        # 框
        b.box(T((x0 + x1) / 2, y0 + 0.03, zc), x1 - x0, 0.06, 0.05, 's3_wood_old')
        b.box(T((x0 + x1) / 2, y1 - 0.03, zc), x1 - x0, 0.06, 0.05, 's3_wood_old')
        b.box(T(x0 + 0.03, (y0 + y1) / 2, zc), 0.06, y1 - y0, 0.05, 's3_wood_old', grain='y')
        b.box(T(x1 - 0.03, (y0 + y1) / 2, zc), 0.06, y1 - y0, 0.05, 's3_wood_old', grain='y')
        nx = max(1, int((x1 - x0 - 0.12) / pitch))
        for k in range(1, nx):
            x = x0 + 0.06 + (x1 - x0 - 0.12) * k / nx
            b.box(T(x, (y0 + y1) / 2, zc), bar, y1 - y0 - 0.12, bar, 's3_wood_old', grain='y', col=0.9)
        ny = max(1, int((y1 - y0 - 0.12) / pitch))
        for k in range(1, ny):
            y = y0 + 0.06 + (y1 - y0 - 0.12) * k / ny
            b.box(T((x0 + x1) / 2, y, zc + 0.006), x1 - x0 - 0.12, bar, bar, 's3_wood_old', grain='x', col=0.9)
    lattice(-0.90, 0.0, FLOOR_Y + 0.10, 2.30, zf + 0.02)
    lattice(0.0, 0.90, FLOOR_Y + 0.10, 2.30, zf + 0.02)
    for sx in (-1, 1):
        xa, xb = (1.10, 2.90) if sx > 0 else (-2.90, -1.10)
        board_wall((xa, zf), (xb, zf), FLOOR_Y + 0.10, 1.45)
        lattice(xa, xb, 1.45, 2.30, zf + 0.02, pitch=0.12)
    # 正面小壁（內法長押～頭貫）
    for i in range(3):
        board_wall((XS[i] + 0.10, zf), (XS[i + 1] - 0.10, zf), 2.42, HEAD_Y - 0.18)
    b.col_box(T(0, (FLOOR_Y + HEAD_Y) / 2, 0), (6.2, HEAD_Y - FLOOR_Y, 4.4), '殿身')
    # 舟肘木＋桁
    for (x, z) in posts:
        along_x = abs(z) > 1.0
        if along_x:
            b.box(T(x, HEAD_Y + 0.06, z), 0.62, 0.12, 0.16, 's3_wood_old', bevel=0.015)
        else:
            b.box(T(x, HEAD_Y + 0.06, z), 0.16, 0.12, 0.62, 's3_wood_old', bevel=0.015, grain='z')
    for z in (ZS[0], ZS[2]):
        b.beam((-3.45, HEAD_Y + 0.22, z), (3.45, HEAD_Y + 0.22, z), 0.17, 0.20, 's3_wood_old')
    for x in (-3.0, 3.0):
        b.beam((x, HEAD_Y + 0.22, -2.55), (x, HEAD_Y + 0.22, 2.55), 0.17, 0.20, 's3_wood_old')
    # ───── 屋頂（入母屋） ─────
    Xe, Ze, ye = 4.15, 3.25, 3.05
    Xg, kb, t = 2.65, 0.40, 0.22
    pr = Prof(ye, 0.42, 0.0905)
    dstar = Xe - Xg - kb       # 1.10：隅棟與螻羽交點
    dg = Xe - Xg               # 1.50：妻壁底
    yr = pr.y(Ze)
    yg = pr.y(dg)
    patch = lambda x, d: (-1.6 < x < -0.6 and 0.9 < d < 1.8)   # 前坡一處換過的屋瓦（修補痕跡，略亮）
    # 向拜屋頂（切妻、棟沿 z）：K(|x|)＝向拜屋面高。棟高於主屋簷口 → 與主屋前坡相交成谷：
    #   主屋前坡在向拜屋面之下的部分（|x| < xv(d)）不建；向拜屋面在主屋屋面之下的部分也不建（zmin）。
    kp = Prof(2.60, 0.52, 0.03)
    KXe = 1.95
    kt = 0.17

    def K(ax):
        return kp.y(KXe - min(ax, KXe))

    def xv(d):
        target = pr.y(d)
        if target >= K(0.0):
            return 0.0
        lo, hi = 0.0, KXe
        for _ in range(40):
            mid = (lo + hi) / 2
            if K(mid) > target:
                lo = mid
            else:
                hi = mid
        return lo

    def zmin_k(ax):
        """向拜屋面在 |x|=ax 處往後延伸到哪個 z（谷線／主屋簷口）。"""
        k = K(ax)
        if k > ye:
            lo, hi = 0.0, Ze
            for _ in range(40):
                mid = (lo + hi) / 2
                if pr.y(mid) < k:
                    lo = mid
                else:
                    hi = mid
            return Ze - lo
        if k > ye - t:
            return Ze
        return Ze - 0.25
    for sz in (1, -1):
        M = T(0, 0, sz * Ze) @ (np.eye(4) if sz > 0 else Ry(PI))
        dl = sorted(set([0.0, 0.3, 0.65, 1.0, dstar, 1.35, 1.7, 2.1, 2.5, 2.9, Ze]))
        if sz > 0:
            dl = sorted(set(dl + [0.12, 0.45, 0.8, 1.2, 1.5]))
        roof_slope(b, M, lambda d: (Xe - d) if d <= dstar else (Xg + kb), dl, pr, 's3_roof', t, ncol=16,
                   soffit_to=1.4, patch=patch if sz > 0 else None, clip=xv if sz > 0 else None)
        # 前後簷口厚度（前簷在向拜處斷開）
        if sz > 0:
            c0 = xv(0.0)
            fascia(b, M, [(-Xe, ye, 0.0), (-c0, ye, 0.0)], t, 's3_wood_old', (0, 0, 1))
            fascia(b, M, [(c0, ye, 0.0), (Xe, ye, 0.0)], t, 's3_wood_old', (0, 0, 1))
        else:
            fascia(b, M, [(-Xe, ye, 0.0), (Xe, ye, 0.0)], t, 's3_wood_old', (0, 0, 1))
        # 螻羽（keraba）厚度＋底面＋破風板
        for sx in (-1, 1):
            ds = np.linspace(dstar, Ze, 9)
            fascia(b, M, [(sx * (Xg + kb), pr.y(d), -d) for d in ds], t, 's3_wood_old', (sx, 0, 0))
            for i in range(len(ds) - 1):
                d0, d1 = ds[i], ds[i + 1]
                q = [(sx * Xg, pr.y(d0) - t, -d0), (sx * (Xg + kb), pr.y(d0) - t, -d0), (sx * (Xg + kb), pr.y(d1) - t, -d1), (sx * Xg, pr.y(d1) - t, -d1)]
                _quad(b, list(s3b._xf(M, q)), [(0, d0), (kb, d0), (kb, d1), (0, d1)], 's3_wood_old', M[:3, :3] @ np.array([0, -1, 0]), 0.62)
                # 破風板（貼在螻羽外側，高 0.30）
                p0 = s3b._xf(M, [(sx * (Xg + kb + 0.035), pr.y(d0) - 0.08, -d0)])[0]
                p1 = s3b._xf(M, [(sx * (Xg + kb + 0.035), pr.y(d1) - 0.08, -d1)])[0]
                b.beam(p0, p1, 0.05, 0.32, 's3_wood_old', bevel=0.006, ext=0.004)
        # 簷下垂木（前後）：每 0.30 m；角落止於隅木
        rxs = [x for x in np.arange(-3.9, 3.95, 0.30) if not (sz > 0 and abs(x) < KXe + 0.05)]
        rafters(b, M, rxs, pr, 0.04, lambda x: min(Xe - abs(x), 1.20), t)
        # 隅木（斜向）＋隅棟
        for sx in (-1, 1):
            p0 = s3b._xf(M, [(sx * (Xe - 0.02), ye - t - 0.06, -0.02)])[0]
            p1 = s3b._xf(M, [(sx * (Xe - 1.15), pr.y(1.15) - t - 0.06, -1.15)])[0]
            b.beam(p0, p1, 0.12, 0.14, 's3_wood_old')
            ds = np.linspace(0.0, dstar, 5)
            for i in range(len(ds) - 1):
                a = s3b._xf(M, [(sx * (Xe - ds[i]), pr.y(ds[i]) + 0.07, -ds[i])])[0]
                c = s3b._xf(M, [(sx * (Xe - ds[i + 1]), pr.y(ds[i + 1]) + 0.07, -ds[i + 1])])[0]
                b.beam(a, c, 0.17, 0.15, 's3_roof', bevel=0.02, ext=0.02, col=0.72)
    for sx in (1, -1):
        # 側坡（入母屋下段）：local 簷口在 x=±Xe
        M = T(sx * Xe, 0, 0) @ Ry(sx * PI / 2)
        dl = [0.0, 0.3, 0.65, 1.0, 1.25, dg]
        roof_slope(b, M, lambda d: Ze - d, dl, pr, 's3_roof', t, ncol=12, soffit_to=1.3)
        fascia(b, M, [(-Ze, ye, 0.0), (Ze, ye, 0.0)], t, 's3_wood_old', (0, 0, 1))
        rafters(b, M, np.arange(-2.85, 2.9, 0.30), pr, 0.04, lambda z: min(Ze - abs(z), 1.20), t)
        # 妻壁（三角，豎板）：底 y_g，上緣沿前後坡底面
        zs = np.linspace(-(Ze - dg), Ze - dg, 13)
        top = [(sx * Xg, max(pr.y(Ze - abs(z)) - t, yg), z) for z in zs]
        # 用扇形三角形組（以底邊中點為中心）
        cen = (sx * Xg, yg, 0.0)
        for i in range(len(top) - 1):
            tri = [cen, top[i], top[i + 1]]
            if i == 0:
                tri0 = [cen, (sx * Xg, yg, zs[0]), top[0]]
                _quad(b, tri0, [(0, yg), (zs[0], yg), (zs[0], top[0][1])], 's3_wood_old', np.array([sx, 0, 0]), 0.85)
            _quad(b, tri, [(0, yg), (top[i][2], top[i][1]), (top[i + 1][2], top[i + 1][1])], 's3_wood_old', np.array([sx, 0, 0]), 0.85)
        tri1 = [cen, top[-1], (sx * Xg, yg, zs[-1])]
        _quad(b, tri1, [(0, yg), (zs[-1], top[-1][1]), (zs[-1], yg)], 's3_wood_old', np.array([sx, 0, 0]), 0.85)
        # 妻壁的豎向押縁（細條）
        for z in np.linspace(-1.4, 1.4, 8):
            ytop = max(pr.y(Ze - abs(z)) - t, yg)
            if ytop - yg > 0.1:
                b.box(T(sx * (Xg + 0.02), (yg + ytop) / 2, z), 0.03, ytop - yg, 0.04, 's3_wood_old', grain='y', col=0.8)
        # 懸魚
        b.box(T(sx * (Xg + kb + 0.06), yr - 0.42, 0) @ Rx(PI / 4), 0.05, 0.34, 0.34, 's3_wood_old', bevel=0.01)
    # 大棟＋鬼板
    LR = Xg + kb + 0.12
    b.box(T(0, yr + 0.13, 0), 2 * LR, 0.34, 0.40, 's3_roof', bevel=0.03, col=0.70)
    b.box(T(0, yr + 0.33, 0), 2 * LR + 0.05, 0.08, 0.30, 's3_roof', bevel=0.02, col=0.62)
    for sx in (-1, 1):
        b.box(T(sx * (LR + 0.02), yr + 0.17, 0), 0.10, 0.52, 0.52, 's3_roof', bevel=0.03, col=0.55)
    # ───── 向拜 ─────
    KX = 1.30
    KZ = 4.35
    KTOP = 2.62
    for sx in (-1, 1):
        oct_ = [(0.24 * math.cos(a), 0.24 * math.sin(a)) for a in np.linspace(0, 2 * PI, 9)[:-1]]
        b.prism(T(sx * KX, 0, KZ), oct_, BASE_Y - 0.06, BASE_Y + 0.10, 's3_stone')
        b.box(T(sx * KX, (BASE_Y + 0.10 + KTOP) / 2, KZ), 0.18, KTOP - BASE_Y - 0.10, 0.18, 's3_wood_old', bevel=0.02, grain='y')
        b.col_box(T(sx * KX, (BASE_Y + KTOP) / 2, KZ), (0.22, KTOP - BASE_Y, 0.22), '向拜柱')
        # 海老虹梁：向拜柱 → 殿身正面柱（曲線以兩段近似）
        a = (sx * KX, 2.42, KZ)
        m = (sx * 1.15, 2.62, 3.1)
        c = (sx * 1.0, 2.70, ZS[2] + 0.1)
        b.beam(a, m, 0.12, 0.20, 's3_wood_old')
        b.beam(m, c, 0.12, 0.20, 's3_wood_old')
        # 向拜桁（沿 z）
        b.beam((sx * KX, KTOP + 0.09, 2.15), (sx * KX, KTOP + 0.09, KZ + 0.55), 0.16, 0.18, 's3_wood_old')
    b.beam((-KX - 0.30, 2.47, KZ), (KX + 0.30, 2.47, KZ), 0.17, 0.30, 's3_wood_old')   # 虹梁（含木鼻）
    # 向拜屋頂：切妻（棟沿 z），簷在 x=±1.95；後端依 zmin_k 收在谷線／主屋簷下
    KZ1 = KZ + 0.80
    dk = [0.0, 0.2, 0.45, 0.7, 0.95, 1.2, 1.45, 1.7, KXe]
    for sx in (-1, 1):
        for i in range(len(dk) - 1):
            xa, xb = KXe - dk[i], KXe - dk[i + 1]
            za, zb = zmin_k(xa), zmin_k(xb)
            ya, yb = kp.y(dk[i]), kp.y(dk[i + 1])
            zsa = np.linspace(za, KZ1, 9)
            zsb = np.linspace(zb, KZ1, 9)
            for j in range(8):
                q = [(sx * xa, ya, zsa[j]), (sx * xa, ya, zsa[j + 1]), (sx * xb, yb, zsb[j + 1]), (sx * xb, yb, zsb[j])]
                uv = [(zsa[j], kp.s(dk[i])), (zsa[j + 1], kp.s(dk[i])), (zsb[j + 1], kp.s(dk[i + 1])), (zsb[j], kp.s(dk[i + 1]))]
                _quad(b, q, uv, 's3_roof', np.array([sx * 0.4, 1.0, 0.0]), 0.95)
                # 底面（只在主屋簷口之前）
                sa0, sb0 = max(zsa[j], Ze - 0.3), max(zsb[j], Ze - 0.3)
                sa1, sb1 = max(zsa[j + 1], Ze - 0.3), max(zsb[j + 1], Ze - 0.3)
                if sa1 > sa0 + 1e-4 or sb1 > sb0 + 1e-4:
                    q = [(sx * xa, ya - kt, sa0), (sx * xa, ya - kt, sa1), (sx * xb, yb - kt, sb1), (sx * xb, yb - kt, sb0)]
                    _quad(b, q, [(sa0, dk[i]), (sa1, dk[i]), (sb1, dk[i + 1]), (sb0, dk[i + 1])], 's3_wood_old', np.array([0, -1, 0]), 0.62)
        # 簷口厚度（沿 z）
        zs_e = zmin_k(KXe)
        fascia(b, np.eye(4), [(sx * KXe, kp.ye, zs_e), (sx * KXe, kp.ye, KZ1)], kt, 's3_wood_old', (sx, 0, 0))
        # 前端破風
        ds = np.linspace(0.0, KXe, 7)
        for i in range(len(ds) - 1):
            p0 = (sx * KXe - sx * ds[i], kp.y(ds[i]) - 0.07, KZ1 + 0.035)
            p1 = (sx * KXe - sx * ds[i + 1], kp.y(ds[i + 1]) - 0.07, KZ1 + 0.035)
            b.beam(p0, p1, 0.05, 0.30, 's3_wood_old', bevel=0.006, ext=0.004)
        for i in range(len(ds) - 1):
            x0 = sx * (KXe - ds[i])
            x1 = sx * (KXe - ds[i + 1])
            q = [(x0, kp.y(ds[i]) - kt, KZ1), (x1, kp.y(ds[i + 1]) - kt, KZ1), (x1, kp.y(ds[i + 1]), KZ1), (x0, kp.y(ds[i]), KZ1)]
            _quad(b, q, [(0, 0), (1, 0), (1, kt), (0, kt)], 's3_wood_old', np.array([0, 0, 1]), 0.8)
        # 向拜垂木（沿 x，自桁到簷；只在主屋簷口之前）
        for z in np.arange(Ze + 0.05, KZ1 - 0.05, 0.28):
            p0 = (sx * (KX - 0.05), kp.y(KXe - KX + 0.05) - kt - 0.045, z)
            p1 = (sx * (KXe - 0.04), kp.y(0.04) - kt - 0.045, z)
            b.beam(p0, p1, 0.06, 0.08, 's3_wood_old', bevel=0.006)
    kyr = kp.y(KXe)
    zr0 = zmin_k(0.0)
    # 棟蓋往後埋進主屋屋面（蓋頂 kyr+0.20 低於主屋面處才收尾，避免端頭露出）
    dc = 0.0
    while pr.y(dc) < kyr + 0.24 and dc < Ze:
        dc += 0.02
    zc0 = Ze - dc
    b.box(T(0, kyr + 0.09, (zc0 + KZ1 + 0.06) / 2), 0.26, 0.22, KZ1 + 0.06 - zc0, 's3_roof', bevel=0.02, col=0.70, grain='z')
    # 谷（主屋前坡與向拜屋面交線）：暗色押え
    vz = [Ze - dd for dd in np.linspace(0.0, Ze - zr0, 8)]
    for sx in (-1, 1):
        pts = []
        for dd in np.linspace(0.0, Ze - zr0, 8):
            ax = xv(dd)
            pts.append((sx * ax, pr.y(dd) + 0.02, Ze - dd))
        for i in range(len(pts) - 1):
            b.beam(pts[i], pts[i + 1], 0.10, 0.05, 's3_roof', bevel=0.01, ext=0.02, col=0.55)
    # 向拜妻（虹梁上的三角板）
    tri = [(-KX, 2.62, KZ + 0.02), (KX, 2.62, KZ + 0.02), (0.0, kp.y(KXe) - kt - 0.05, KZ + 0.02)]
    _quad(b, tri, [(-KX, 2.62), (KX, 2.62), (0, 3.4)], 's3_wood_old', np.array([0, 0, 1]), 0.8)
    _quad(b, tri, [(-KX, 2.62), (KX, 2.62), (0, 3.4)], 's3_wood_old', np.array([0, 0, -1]), 0.8)
    # 注連繩（向拜前，虹梁下）＋紙垂＋房
    rope_pts = []
    rr = []
    for i in range(17):
        u = i / 16.0
        x = -1.18 + 2.36 * u
        sag = 0.20 * (1.0 - (2 * u - 1) ** 2)
        rope_pts.append((x, 2.24 - sag, KZ + 0.18))
        rr.append(0.045 + 0.055 * (1.0 - (2 * u - 1) ** 2))
    b.tube(rope_pts, rr, 's3_straw', n=10, twist=6.0)
    for u in (0.25, 0.5, 0.75):
        i = int(round(u * 16))
        p = rope_pts[i]
        b.tube([(p[0], p[1] - rr[i] * 0.6, p[2]), (p[0], p[1] - 0.42, p[2])], [0.035, 0.05], 's3_straw', n=8)
    for u in (0.14, 0.38, 0.62, 0.86):
        i = int(round(u * 16))
        p = rope_pts[i]
        shide(b, (p[0], p[1] - rr[i] * 0.7, p[2] + 0.02))
    # 鈴＋鈴緒（虹梁中央）
    b.tube([(0, 2.32, KZ - 0.13), (0, 2.12, KZ - 0.13)], [0.012, 0.012], 's3_metal', n=6)
    b.lathe(T(0, 1.92, KZ - 0.13), [(0.0, 0.0), (0.08, 0.02), (0.12, 0.09), (0.12, 0.13), (0.09, 0.19), (0.03, 0.21), (0.0, 0.215)], 's3_metal', n=14)
    b.tube([(0, 1.93, KZ - 0.13), (0.02, 1.50, KZ - 0.11), (0.0, 1.05, KZ - 0.09)], [0.022, 0.026, 0.03], 's3_rope_rw', n=8, twist=4.0)
    b.mark('front', (0, 0, KZ + 0.9))
    b.mark('worship', (0, BASE_Y, 5.6))   # 參拜者站位（賽錢箱前）
    b.mark('ridge_y', (0, yr + 0.37, 0))
    return b


def shide(b, top, h=0.34, w=0.075, n=4):
    """紙垂：之字形四折白紙（雙面）。"""
    x, y, z = top
    pts = []
    for k in range(n + 1):
        yy = y - h * k / n
        off = (w if k % 2 else 0.0)
        pts.append((x - w * 0.5 + off, yy))
    for k in range(n):
        xa, ya = pts[k]
        xb, yb = pts[k + 1]
        q = [(xa, ya, z), (xa + w, ya, z), (xb + w, yb, z), (xb, yb, z)]
        b.quad(q, [(0, 0), (1, 0), (1, 1), (0, 1)], 's3_paper', col=1.0, double=True)


# ───────────────────────── 賽錢箱 ─────────────────────────
def build_saisen():
    b = Builder('saisen', seed=21)
    W, D, H = 1.20, 0.62, 0.68
    for sx in (-1, 1):
        for sz in (-1, 1):
            b.box(T(sx * (W / 2 - 0.05), 0.03, sz * (D / 2 - 0.05)), 0.10, 0.06, 0.10, 's3_wood_dark')
    b.box(T(0, 0.06 + (H - 0.18) / 2, 0), W, H - 0.18, D, 's3_wood_dark', bevel=0.012)
    # 上框＋斜向桟（V 形往內收）
    yt = H - 0.12
    b.box(T(0, yt + 0.05, D / 2 - 0.04), W + 0.04, 0.10, 0.08, 's3_wood_dark', bevel=0.01)
    b.box(T(0, yt + 0.05, -D / 2 + 0.04), W + 0.04, 0.10, 0.08, 's3_wood_dark', bevel=0.01)
    b.box(T(-W / 2 + 0.03, yt + 0.05, 0), 0.08, 0.10, D, 's3_wood_dark', bevel=0.01, grain='z')
    b.box(T(W / 2 - 0.03, yt + 0.05, 0), 0.08, 0.10, D, 's3_wood_dark', bevel=0.01, grain='z')
    for i, z in enumerate(np.linspace(-D / 2 + 0.12, D / 2 - 0.12, 6)):
        tilt = 0.55 if z > 0 else -0.55
        b.box(T(0, yt + 0.02, z) @ Rx(tilt), W - 0.08, 0.025, 0.07, 's3_wood_old', bevel=0.004)
    b.box(T(0, yt - 0.06, 0), W - 0.08, 0.02, D - 0.1, 's3_interior', col=1.0)
    # 正面：橫帶（「奉納」的位置留空，樸素）
    b.box(T(0, 0.40, D / 2 + 0.008), W - 0.12, 0.16, 0.016, 's3_wood_old', col=0.85)
    b.col_box(T(0, H / 2, 0), (W, H, D), '賽錢箱')
    return b


# ───────────────────────── 鳥居（明神） ─────────────────────────
def build_torii():
    b = Builder('torii', seed=31)
    SPAN = 3.40
    for sx in (-1, 1):
        x0 = sx * SPAN / 2
        # 二段石台：方台＋圓形亀腹
        b.box(T(x0, 0.075, 0), 0.82, 0.30, 0.82, 's3_stone', bevel=0.035)      # y −0.075..0.225（下半埋地）
        b.lathe(T(x0, 0.22, 0), [(0.36, 0.0), (0.35, 0.08), (0.30, 0.17), (0.22, 0.24), (0.20, 0.26)], 's3_stone', n=16)
        # 根巻（黑）＋柱（微內傾）
        lean = sx * -0.018
        Mp = T(x0, 0.46, 0) @ Rz(-lean)
        b.cyl(T(x0, 0.40, 0), 0.205, 0.42, 's3_paint_black', n=16)
        b.cyl(Mp, 0.172, 3.62, 's3_paint_red', n=16, r_top=0.152, cap_top=True)
        b.col_cyl(T(x0, 2.05, 0), 0.19, 4.1, '鳥居柱')
        b.col_box(T(x0, 0.075, 0), (0.82, 0.30, 0.82), '鳥居石台')
    # 貫（含兩端出頭）
    b.box(T(0, 3.15, 0), 4.55, 0.18, 0.12, 's3_paint_red', bevel=0.012)
    # 額束＋額
    b.box(T(0, 3.66, 0), 0.17, 0.84, 0.13, 's3_paint_red', bevel=0.01, grain='y')
    b.box(T(0, 3.66, 0.085), 0.50, 0.68, 0.05, 's3_paint_black', bevel=0.01, grain='y')
    b.quad([(-0.21, 3.36, 0.112), (0.21, 3.36, 0.112), (0.21, 3.96, 0.112), (-0.21, 3.96, 0.112)], [(0, 0), (1, 0), (1, 1), (0, 1)], 's3_plaque', col=1.0)
    # 島木（朱）＋笠木（黑），兩端反り
    def curved(y0, h, d, half, lift, mat, n=26):
        xs = np.linspace(-half, half, n + 1)
        ys = [y0 + lift * (abs(x) / half) ** 2.6 for x in xs]
        for i in range(n):
            xa, xb = xs[i], xs[i + 1]
            ya, yb = ys[i], ys[i + 1]
            # 每段一個 box（沿曲線方向），兩段之間稍重疊
            b.beam((xa, ya + h / 2, 0), (xb, yb + h / 2, 0), d, h, mat, bevel=0.012, ext=0.004)
    curved(4.05, 0.20, 0.26, 2.55, 0.10, 's3_paint_red')
    curved(4.25, 0.25, 0.36, 2.80, 0.17, 's3_paint_black')
    # 注連繩（貫下）＋三房＋二紙垂
    pts = []
    rr = []
    for i in range(17):
        u = i / 16.0
        x = -1.52 + 3.04 * u
        sag = 0.26 * (1.0 - (2 * u - 1) ** 2)
        pts.append((x, 2.86 - sag, 0.0))
        rr.append(0.04 + 0.05 * (1.0 - (2 * u - 1) ** 2))
    b.tube(pts, rr, 's3_straw', n=10, twist=6.0)
    for u in (0.25, 0.5, 0.75):
        i = int(round(u * 16))
        p = pts[i]
        b.tube([(p[0], p[1] - rr[i] * 0.6, p[2]), (p[0], p[1] - 0.40, p[2])], [0.03, 0.045], 's3_straw', n=8)
    for u in (0.375, 0.625):
        i = int(round(u * 16))
        p = pts[i]
        shide(b, (p[0], p[1] - rr[i] * 0.7, p[2] + 0.05), h=0.32)
    b.mark('passage', (0, 0, 0))
    return b


# ───────────────────────── 手水舍 ─────────────────────────
def gable_roof(b, M, half_len, Ze, prof, t, mat='s3_roof', barge=True, rafter_pitch=0.30, rafter_from=None):
    """local：棟沿 x（−half_len..half_len），兩坡往 ±z，簷口在 z=±Ze。M＝放置矩陣。"""
    for sz in (1, -1):
        Ms = M @ T(0, 0, sz * Ze) @ (np.eye(4) if sz > 0 else Ry(PI))
        dl = list(np.linspace(0.0, Ze, 7))
        roof_slope(b, Ms, lambda d: half_len, dl, prof, mat, t, ncol=6, soffit_to=Ze)
        fascia(b, Ms, [(-half_len, prof.ye, 0.0), (half_len, prof.ye, 0.0)], t, 's3_wood_old', (0, 0, 1))
        ds = np.linspace(0.0, Ze, 7)
        for sx in (-1, 1):
            fascia(b, Ms, [(sx * half_len, prof.y(d), -d) for d in ds], t, 's3_wood_old', (sx, 0, 0))
            if barge:
                for i in range(len(ds) - 1):
                    p0 = s3b._xf(Ms, [(sx * (half_len + 0.03), prof.y(ds[i]) - 0.06, -ds[i])])[0]
                    p1 = s3b._xf(Ms, [(sx * (half_len + 0.03), prof.y(ds[i + 1]) - 0.06, -ds[i + 1])])[0]
                    b.beam(p0, p1, 0.04, 0.24, 's3_wood_old', bevel=0.005, ext=0.004)
        if rafter_from is not None:
            rafters(b, Ms, np.arange(-half_len + 0.12, half_len - 0.05, rafter_pitch), prof, 0.03, lambda x: rafter_from, t, w=0.05, h=0.07)
    yr = prof.y(Ze)
    Mr = M @ T(0, yr + 0.08, 0)
    b.box(Mr, 2 * half_len + 0.1, 0.18, 0.26, mat, bevel=0.02, col=0.7)
    return yr


def build_temizuya():
    b = Builder('temizuya', seed=41)
    PX, PZ = 0.95, 0.68
    TOP = 2.20
    for sx in (-1, 1):
        for sz in (-1, 1):
            oct_ = [(0.17 * math.cos(a), 0.17 * math.sin(a)) for a in np.linspace(0, 2 * PI, 9)[:-1]]
            b.prism(T(sx * PX, 0, sz * PZ), oct_, -0.08, 0.16, 's3_stone')
            b.box(T(sx * PX, (0.16 + TOP) / 2, sz * PZ), 0.14, TOP - 0.16, 0.14, 's3_wood_old', bevel=0.015, grain='y')
            b.col_box(T(sx * PX, TOP / 2, sz * PZ), (0.18, TOP, 0.18), '柱')
        b.beam((sx * PX, 1.88, -PZ - 0.12), (sx * PX, 1.88, PZ + 0.12), 0.09, 0.14, 's3_wood_old')   # 貫
    for sz in (-1, 1):
        b.beam((-PX - 0.35, TOP + 0.08, sz * PZ), (PX + 0.35, TOP + 0.08, sz * PZ), 0.13, 0.16, 's3_wood_old')   # 桁
        b.beam((-PX - 0.12, 1.88, sz * PZ), (PX + 0.12, 1.88, sz * PZ), 0.09, 0.14, 's3_wood_old')
    for sx in (-1, 1):
        b.beam((sx * PX, TOP + 0.10, -PZ - 0.02), (sx * PX, TOP + 0.10, PZ + 0.02), 0.12, 0.14, 's3_wood_old')   # 梁
    # 棟束
    b.box(T(0, TOP + 0.30, 0), 0.10, 0.36, 0.10, 's3_wood_old', grain='y')
    pr = Prof(2.18, 0.50, 0.05)
    Ze = PZ + 0.58
    yr = gable_roof(b, np.eye(4), PX + 0.50, Ze, pr, 0.14, rafter_from=0.75)
    # 水盤：外框＋內凹＋水面
    BW, BD, BH = 1.30, 0.58, 0.62
    b.box(T(0, 0.06, 0), BW + 0.20, 0.16, BD + 0.20, 's3_stone', bevel=0.03)
    ytop = 0.14 + BH
    wall = 0.10
    b.box(T(0, 0.14 + 0.18, 0), BW, 0.36, BD, 's3_stone', bevel=0.02)
    b.box(T(0, ytop - 0.13, BD / 2 - wall / 2), BW, 0.26, wall, 's3_stone', bevel=0.025)
    b.box(T(0, ytop - 0.13, -BD / 2 + wall / 2), BW, 0.26, wall, 's3_stone', bevel=0.025)
    b.box(T(BW / 2 - wall / 2, ytop - 0.13, 0), wall, 0.26, BD - 2 * wall + 0.01, 's3_stone', bevel=0.02, grain='z')
    b.box(T(-BW / 2 + wall / 2, ytop - 0.13, 0), wall, 0.26, BD - 2 * wall + 0.01, 's3_stone', bevel=0.02, grain='z')
    b.quad([(-BW / 2 + wall, ytop - 0.05, BD / 2 - wall), (BW / 2 - wall, ytop - 0.05, BD / 2 - wall), (BW / 2 - wall, ytop - 0.05, -BD / 2 + wall), (-BW / 2 + wall, ytop - 0.05, -BD / 2 + wall)],
           [(0, 0), (1, 0), (1, 1), (0, 1)], 's3_water', col=1.0)
    b.col_box(T(0, ytop / 2, 0), (BW + 0.2, ytop, BD + 0.2), '水盤')
    # 柄杓架（竹）＋柄杓三支
    b.beam((-0.45, ytop + 0.03, 0.08), (0.45, ytop + 0.03, 0.08), 0.03, 0.03, 's3_bamboo')
    for i, x in enumerate((-0.32, 0.0, 0.30)):
        b.cyl(T(x, ytop + 0.045, 0.20), 0.042, 0.065, 's3_bamboo', n=10, cap_top=False, cap_bot=True)
        b.beam((x, ytop + 0.07, 0.20), (x + 0.02, ytop + 0.05, -0.22), 0.016, 0.012, 's3_bamboo', bevel=0.003)
    # 竹筧（自後柱伸到水盤上）
    b.tube([(-PX + 0.05, 1.20, -PZ + 0.02), (-0.55, 1.05, -0.12), (-0.35, 0.98, -0.05)], [0.03, 0.03, 0.03], 's3_bamboo', n=8)
    b.mark('front', (0, 0, 1.0))
    return b


# ───────────────────────── 倉庫 ─────────────────────────
def build_storehouse():
    b = Builder('storehouse', seed=51)
    W, D = 3.0, 2.4
    SILL = 0.28
    TOP = 2.30
    xs = [-W / 2, 0.0, W / 2]
    zs = [-D / 2, D / 2]
    for x in xs:
        for z in zs:
            oct_ = [(0.20 * math.cos(a) * b.rng.uniform(0.9, 1.1), 0.20 * math.sin(a) * b.rng.uniform(0.9, 1.1)) for a in np.linspace(0, 2 * PI, 8)[:-1]]
            b.prism(T(x, 0, z), oct_, -0.10, SILL - 0.10, 's3_stone')
    for z in zs:
        b.beam((-W / 2 - 0.08, SILL - 0.04, z), (W / 2 + 0.08, SILL - 0.04, z), 0.14, 0.13, 's3_wood_old')   # 土台
    for x in (-W / 2, W / 2):
        b.beam((x, SILL - 0.04, -D / 2 - 0.08), (x, SILL - 0.04, D / 2 + 0.08), 0.14, 0.13, 's3_wood_old')
    for x in xs:
        for z in zs:
            b.box(T(x, (SILL + TOP) / 2, z), 0.13, TOP - SILL, 0.13, 's3_wood_old', bevel=0.012, grain='y')
    for x in (-W / 2, W / 2):
        b.box(T(x, (SILL + TOP) / 2, 0.0), 0.12, TOP - SILL, 0.12, 's3_wood_old', bevel=0.012, grain='y')
    # 竪板張り（四面），正面中央引き戸
    def wall(p0, p1, y0, y1, mat='s3_wood_old', off=0.0):
        p0 = np.array(p0, float)
        p1 = np.array(p1, float)
        d = p1 - p0
        L = float(np.linalg.norm(d))
        ang = math.atan2(d[0], d[1])
        c = (p0 + p1) / 2
        b.box(T(c[0], (y0 + y1) / 2, c[1]) @ Ry(ang), 0.03, y1 - y0, L, mat, grain='y')
        # 押縁（每 0.45 m 一條細木）
        n = int(L / 0.45)
        for k in range(1, n):
            p = p0 + d * (k / n)
            nrm = np.array([d[1], -d[0]]) / L
            b.box(T(p[0] + nrm[0] * off, (y0 + y1) / 2, p[1] + nrm[1] * off) @ Ry(ang), 0.025, y1 - y0, 0.035, 's3_wood_old', grain='y', col=0.85)
    wall((-W / 2, -D / 2), (W / 2, -D / 2), SILL + 0.03, TOP - 0.05, off=-0.03)
    wall((-W / 2, D / 2), (-0.62, D / 2), SILL + 0.03, TOP - 0.05, off=0.03)
    wall((0.62, D / 2), (W / 2, D / 2), SILL + 0.03, TOP - 0.05, off=0.03)
    wall((-W / 2, -D / 2), (-W / 2, D / 2), SILL + 0.03, TOP - 0.05, off=-0.03)
    wall((W / 2, -D / 2), (W / 2, -0.35), SILL + 0.03, TOP - 0.05, 's3_wood_new', off=0.03)   # 東面下半換過板
    wall((W / 2, 0.35), (W / 2, D / 2), SILL + 0.03, TOP - 0.05, off=0.03)
    # 東面小格子窗
    b.box(T(W / 2 + 0.005, 1.55, 0.0), 0.02, 0.55, 0.70, 's3_interior', col=1.0, grain='y')
    for k in range(5):
        b.box(T(W / 2 + 0.03, 1.55, -0.28 + k * 0.14), 0.03, 0.55, 0.03, 's3_wood_old', grain='y')
    b.box(T(W / 2 + 0.03, 1.29, 0.0), 0.04, 0.05, 0.76, 's3_wood_old', grain='z')
    b.box(T(W / 2 + 0.03, 1.81, 0.0), 0.04, 0.05, 0.76, 's3_wood_old', grain='z')
    b.box(T(W / 2 + 0.005, (SILL + 1.30) / 2, 0.0), 0.03, 1.30 - SILL - 0.02, 0.70, 's3_wood_old', grain='y')
    b.box(T(W / 2 + 0.005, (1.81 + TOP) / 2, 0.0), 0.03, TOP - 1.81 - 0.05, 0.70, 's3_wood_old', grain='y')
    # 正面：門框＋引き戸（半開 0.25 m 的暗縫）
    b.box(T(0, 1.10, D / 2 + 0.005), 1.24, 1.64, 0.02, 's3_interior', col=1.0)
    b.box(T(-0.04, 1.08, D / 2 + 0.035), 1.14, 1.60, 0.04, 's3_wood_dark', grain='y')
    for y in (0.40, 0.95, 1.50):
        b.box(T(-0.04, y, D / 2 + 0.06), 1.12, 0.05, 0.02, 's3_wood_dark', col=0.8)
    b.beam((-0.70, 1.92, D / 2 + 0.03), (0.70, 1.92, D / 2 + 0.03), 0.07, 0.09, 's3_wood_old')
    b.beam((-0.70, SILL + 0.02, D / 2 + 0.03), (0.70, SILL + 0.02, D / 2 + 0.03), 0.07, 0.05, 's3_wood_old')
    for x in (-0.66, 0.66):
        b.box(T(x, (SILL + 1.92) / 2, D / 2 + 0.03), 0.07, 1.92 - SILL, 0.07, 's3_wood_old', grain='y')
    # 踏み石
    b.prism(T(0, 0, D / 2 + 0.45), [(-0.35, -0.18), (0.36, -0.2), (0.38, 0.17), (-0.33, 0.2)], -0.08, 0.14, 's3_stone')
    # 桁＋屋根（切妻，棟沿 x）
    for z in zs:
        b.beam((-W / 2 - 0.45, TOP + 0.07, z), (W / 2 + 0.45, TOP + 0.07, z), 0.12, 0.14, 's3_wood_old')
    b.box(T(0, TOP + 0.45, 0), 0.10, 0.70, 0.10, 's3_wood_old', grain='y')
    # 妻壁（三角）
    pr = Prof(2.28, 0.58, 0.02)
    Ze = D / 2 + 0.48
    for sx in (-1, 1):
        ytri = pr.y(Ze) - 0.13
        tri = [(sx * W / 2, TOP, -D / 2 - 0.05), (sx * W / 2, TOP, D / 2 + 0.05), (sx * W / 2, ytri, 0.0)]
        _quad(b, tri, [(-1.2, TOP), (1.2, TOP), (0, ytri)], 's3_wood_old', np.array([sx, 0, 0]), 0.85)
    gable_roof(b, np.eye(4), W / 2 + 0.40, Ze, pr, 0.13, rafter_from=0.55)
    b.col_box(T(0, (0.0 + TOP) / 2, 0), (W + 0.16, TOP, D + 0.16), '倉庫')
    b.mark('front', (0, 0, D / 2 + 0.8))
    return b


# ───────────────────────── 石燈籠 ─────────────────────────
def build_lantern(name, s=1.0, seed=61):
    b = Builder(name, seed=seed)
    M0 = s3b.S(s)
    def hexp(r):
        return [(r * math.cos(a), r * math.sin(a)) for a in np.linspace(0, 2 * PI, 7)[:-1]]
    R30 = Ry(PI / 6)   # lathe 的 6 邊形與 prism 對齊（面朝 ±z）
    y = -0.06
    b.prism(M0, hexp(0.36), y, 0.14, 's3_stone')            # 基礎
    b.prism(M0, hexp(0.27), 0.14, 0.24, 's3_stone')
    b.lathe(M0 @ T(0, 0.24, 0), [(0.11, 0.0), (0.10, 0.40), (0.125, 0.43), (0.125, 0.47), (0.10, 0.50), (0.095, 0.90)], 's3_stone', n=14)   # 竿＋節
    b.lathe(M0 @ T(0, 1.14, 0) @ R30, [(0.13, 0.0), (0.31, 0.10), (0.31, 0.16)], 's3_stone', n=6)   # 中台（六角）
    # 火袋：六角，前後開窗（暗面）
    Yf0, Yf1 = 1.30, 1.66
    hx = hexp(0.20)
    for i in range(6):
        a = hx[i]
        c = hx[(i + 1) % 6]
        mid = ((a[0] + c[0]) / 2, (a[1] + c[1]) / 2)
        facing_front = abs(mid[0]) < 0.05
        # 角柱
        b.box(M0 @ T(a[0], (Yf0 + Yf1) / 2, a[1]), 0.06, Yf1 - Yf0, 0.06, 's3_stone', grain='y')
        if facing_front:
            # 開窗：上下框＋內暗面
            b.quad(list(s3b._xf(M0, [(a[0] * 0.8, Yf0 + 0.06, a[1] * 0.8), (c[0] * 0.8, Yf0 + 0.06, c[1] * 0.8), (c[0] * 0.8, Yf1 - 0.06, c[1] * 0.8), (a[0] * 0.8, Yf1 - 0.06, a[1] * 0.8)])),
                   [(0, 0), (1, 0), (1, 1), (0, 1)], 's3_interior', col=1.0, double=True)
        else:
            q = [(a[0], Yf0, a[1]), (c[0], Yf0, c[1]), (c[0], Yf1, c[1]), (a[0], Yf1, a[1])]
            Q = s3b._xf(M0, q)
            _quad(b, list(Q), [(0, 0), (0.2, 0), (0.2, 0.36), (0, 0.36)], 's3_stone', M0[:3, :3] @ np.array([mid[0], 0, mid[1]]), b.tint())
    # 笠（六角，簷口薄、往上收）＋寶珠
    b.lathe(M0 @ T(0, Yf1, 0) @ R30, [(0.16, 0.0), (0.42, 0.05), (0.42, 0.10), (0.20, 0.24), (0.07, 0.30)], 's3_stone', n=6)
    b.lathe(M0 @ T(0, Yf1 + 0.30, 0), [(0.06, 0.0), (0.09, 0.03), (0.075, 0.06), (0.10, 0.11), (0.085, 0.17), (0.03, 0.22), (0.0, 0.24)], 's3_stone', n=12)
    # 笠的六個角：蕨手（上翹的捲角）
    for k in range(6):
        a = PI / 6 + k * PI / 3 + PI / 6
        cx, cz = 0.41 * math.sin(a), 0.41 * math.cos(a)
        Mk = M0 @ T(cx, Yf1 + 0.115, cz) @ Ry(a) @ Rx(-0.6)
        b.box(Mk, 0.07, 0.05, 0.11, 's3_stone', bevel=0.012, grain='z')
        b.box(M0 @ T(0.45 * math.sin(a), Yf1 + 0.17, 0.45 * math.cos(a)) @ Ry(a), 0.06, 0.07, 0.05, 's3_stone', bevel=0.015)
    h = (Yf1 + 0.54) * s
    b.col_cyl(T(0, h / 2, 0), 0.32 * s, h, '石燈籠')
    return b


# ───────────────────────── 狛犬（台座在這裡建；石像本體用 metaball） ─────────────────────────
def build_komainu_base(name, seed):
    b = Builder(name, seed=seed)
    b.box(T(0, 0.08, 0), 0.92, 0.32, 0.92, 's3_stone', bevel=0.03)          # y −0.08..0.24
    b.box(T(0, 0.24 + 0.27, 0), 0.72, 0.54, 0.72, 's3_stone', bevel=0.02)   # 0.24..0.78
    b.box(T(0, 0.78 + 0.04, 0), 0.80, 0.08, 0.80, 's3_stone', bevel=0.02)   # 笠石 0.78..0.86
    b.col_box(T(0, 0.43, 0), (0.92, 0.86, 0.92), '狛犬台座')
    return b


# ───────────────────────── 小道具 ─────────────────────────
def build_props():
    out = []
    # 木箱
    b = Builder('crate', seed=71)
    b.box(T(0, 0.22, 0), 0.62, 0.40, 0.44, 's3_wood_old', bevel=0.01)
    for y in (0.06, 0.38):
        b.box(T(0, y, 0.225), 0.64, 0.05, 0.02, 's3_wood_dark')
        b.box(T(0, y, -0.225), 0.64, 0.05, 0.02, 's3_wood_dark')
    b.box(T(0, 0.43, 0), 0.64, 0.03, 0.46, 's3_wood_old', bevel=0.004)
    b.col_box(T(0, 0.22, 0), (0.64, 0.45, 0.46), '木箱')
    out.append(b)
    # 竹箒（靠牆用；原點在柄下端）
    b = Builder('broom', seed=72)
    b.tube([(0, 0.28, 0), (0, 1.45, 0)], [0.016, 0.014], 's3_bamboo', n=8)
    for k in range(18):
        a = 2 * PI * k / 18
        r = 0.05 + 0.02 * (k % 3)
        b.tube([(0, 0.32, 0), (math.sin(a) * r * 2.2, 0.0, math.cos(a) * r * 0.8)], [0.012, 0.004], 's3_straw', n=4, caps=False)
    b.tube([(0, 0.30, 0), (0, 0.36, 0)], [0.03, 0.03], 's3_straw', n=8)
    out.append(b)
    # 木桶
    b = Builder('bucket', seed=73)
    b.lathe(np.eye(4), [(0.15, 0.0), (0.17, 0.30)], 's3_wood_old', n=16, close_top=False, close_bot=True)
    b.lathe(np.eye(4), [(0.155, 0.04), (0.155, 0.05)], 's3_metal', n=16, close_top=False)
    b.lathe(T(0, 0.22, 0), [(0.168, 0.0), (0.168, 0.012)], 's3_metal', n=16, close_top=False)
    b.lathe(T(0, 0.05, 0), [(0.0, 0.0), (0.15, 0.0)], 's3_wood_dark', n=16, close_top=False)
    b.tube([(-0.17, 0.30, 0), (-0.12, 0.45, 0), (0.12, 0.45, 0), (0.17, 0.30, 0)], [0.012] * 4, 's3_wood_old', n=6)
    b.col_cyl(T(0, 0.15, 0), 0.17, 0.30, '桶')
    out.append(b)
    # 社號標（石柱「博麗神社」）
    b = Builder('shagohyo', seed=74)
    b.box(T(0, 0.05, 0), 0.62, 0.22, 0.62, 's3_stone', bevel=0.03)
    b.box(T(0, 0.16 + 0.95, 0), 0.32, 1.90, 0.32, 's3_stone', bevel=0.02, grain='y')
    b.quad([(-0.12, 0.55, 0.162), (0.12, 0.55, 0.162), (0.12, 1.95, 0.162), (-0.12, 1.95, 0.162)], [(0, 0), (1, 0), (1, 1), (0, 1)], 's3_stone_text', col=1.0)
    b.col_box(T(0, 1.03, 0), (0.62, 2.06, 0.62), '社號標')
    out.append(b)
    return out


# ───────────────────────── Blender 端 ─────────────────────────
MAT_PREVIEW = {
    's3_wood_old': (0.30, 0.23, 0.17), 's3_wood_new': (0.62, 0.50, 0.36), 's3_wood_dark': (0.17, 0.13, 0.10),
    's3_roof': (0.20, 0.21, 0.22), 's3_stone': (0.50, 0.49, 0.46), 's3_stone_moss': (0.40, 0.43, 0.33),
    's3_earth': (0.42, 0.36, 0.28), 's3_paint_red': (0.62, 0.16, 0.09), 's3_paint_black': (0.05, 0.05, 0.05),
    's3_paper': (0.92, 0.91, 0.86), 's3_straw': (0.60, 0.53, 0.33), 's3_metal': (0.45, 0.37, 0.20),
    's3_water': (0.15, 0.22, 0.22), 's3_plaque': (0.08, 0.07, 0.06), 's3_bamboo': (0.62, 0.58, 0.38),
    's3_interior': (0.03, 0.025, 0.02), 's3_rope_rw': (0.65, 0.20, 0.18), 's3_stone_text': (0.45, 0.44, 0.41),
}


def make_mats():
    import bpy
    mats = {}
    for k, c in MAT_PREVIEW.items():
        m = bpy.data.materials.get(k) or bpy.data.materials.new(k)
        m.use_nodes = True
        bsdf = m.node_tree.nodes.get('Principled BSDF')
        if bsdf:
            bsdf.inputs['Base Color'].default_value = (c[0], c[1], c[2], 1.0)
            bsdf.inputs['Roughness'].default_value = 0.85
        m.diffuse_color = (c[0], c[1], c[2], 1.0)
        mats[k] = m
    return mats


def komainu_statue(mats, name, open_mouth, mirror):
    """石像（坐姿獅子狗）：橢球組合 → 體素重網格（融成一體）→ 平滑 → 減面。原點＝像底中心（放在台座頂 y=0.86）。正面 +z。
    open_mouth＝阿形（張口，布林挖口）；否則吽形（閉口、頭上小角）。mirror＝左右鏡像（一對面向參道中線）。"""
    import bpy
    import bmesh
    from mathutils import Matrix
    sgn = -1.0 if mirror else 1.0
    bm = bmesh.new()

    def ell(c, r, rot=(0.0, 0.0, 0.0)):
        x, y, z = c
        g = bmesh.ops.create_uvsphere(bm, u_segments=20, v_segments=12, radius=1.0)
        M = (Matrix.Translation((sgn * x, -z, y)) @ Matrix.Rotation(rot[0], 4, 'X') @ Matrix.Rotation(rot[1], 4, 'Z')
             @ Matrix.Diagonal((r[0], r[2], r[1], 1.0)))
        bmesh.ops.transform(bm, matrix=M, verts=g['verts'])

    def cube(c, size):
        x, y, z = c
        g = bmesh.ops.create_cube(bm, size=1.0)
        M = Matrix.Translation((sgn * x, -z, y)) @ Matrix.Diagonal((size[0], size[2], size[1], 1.0))
        bmesh.ops.transform(bm, matrix=M, verts=g['verts'])
    cube((0, 0.03, 0.0), (0.60, 0.06, 0.42))
    for sx in (-1, 1):
        ell((sx * 0.11, 0.17, -0.10), (0.12, 0.15, 0.18))
        ell((sx * 0.12, 0.06, 0.03), (0.06, 0.05, 0.10))
    ell((0, 0.30, -0.04), (0.15, 0.22, 0.17), rot=(-0.35, 0, 0))
    ell((0, 0.42, 0.06), (0.15, 0.17, 0.14))
    for sx in (-1, 1):
        ell((sx * 0.085, 0.22, 0.13), (0.055, 0.19, 0.06))
        ell((sx * 0.09, 0.05, 0.17), (0.06, 0.05, 0.09))
    hx = 0.03
    # 頭：顱、眉稜、頰、鼻塊、吻、下顎
    ell((hx, 0.64, 0.09), (0.14, 0.12, 0.12))
    ell((hx, 0.69, 0.17), (0.13, 0.035, 0.05))                     # 眉稜
    for sx in (-1, 1):
        ell((hx + sx * 0.10, 0.60, 0.16), (0.06, 0.06, 0.07))      # 頰
        ell((hx + sx * 0.15, 0.71, 0.03), (0.03, 0.065, 0.045), rot=(0.0, sx * 0.5, 0))   # 耳
    ell((hx, 0.615, 0.235), (0.085, 0.06, 0.07))                    # 吻
    ell((hx, 0.645, 0.29), (0.05, 0.035, 0.03))                     # 鼻塊
    if open_mouth:
        ell((hx, 0.53, 0.20), (0.075, 0.035, 0.08))                 # 下顎（張口時下移）
    else:
        ell((hx, 0.56, 0.21), (0.075, 0.04, 0.075))
    # 鬃：兩圈斜向的捲束，框住頭頸
    for ring, (rad, yy, zz, cnt, sz_) in enumerate(((0.17, 0.56, 0.02, 11, 0.055), (0.13, 0.48, 0.07, 9, 0.05))):
        for k in range(cnt):
            a = -1.35 + 2.7 * k / (cnt - 1)
            cx = hx + math.sin(a) * rad
            cz = zz - math.cos(a) * rad * 0.55
            ell((cx, yy + 0.03 * math.cos(a * 1.5), cz), (sz_ * 0.8, sz_ * 1.5, sz_ * 0.9), rot=(0.4, -a * 0.6, 0))
    for k in range(3):
        ell((hx + (-0.06 + 0.06 * k), 0.43, 0.15), (0.04, 0.05, 0.035))   # 胸前捲毛
    # 前腳趾
    for sx in (-1, 1):
        for t_ in (-1, 0, 1):
            ell((sx * 0.09 + t_ * 0.035, 0.035, 0.235), (0.022, 0.025, 0.03))
    # 尾：自臀部升起的火焰狀三束
    for k, (ox, h_, lean) in enumerate(((-0.06, 0.40, 0.35), (0.0, 0.48, 0.0), (0.06, 0.40, -0.35))):
        for j in range(4):
            t = j / 3
            ell((ox * (0.4 + t), 0.20 + h_ * t, -0.25 - 0.05 * math.sin(t * PI)), (0.05 - 0.012 * t, 0.07, 0.05 - 0.01 * t), rot=(0.3, lean * t, 0))
    if not open_mouth:
        ell((hx, 0.80, 0.07), (0.022, 0.065, 0.022), rot=(-0.3, 0, 0))   # 吽形：頭上小角
    cutters = []   # (中心, 半徑)：眼窩、鼻孔、口
    for sx in (-1, 1):
        cutters.append(((hx + sx * 0.055, 0.655, 0.205), (0.026, 0.02, 0.02)))
        cutters.append(((hx + sx * 0.02, 0.64, 0.318), (0.012, 0.01, 0.012)))
    if open_mouth:
        cutters.append(((hx, 0.565, 0.265), (0.06, 0.03, 0.06)))
    else:
        cutters.append(((hx, 0.585, 0.282), (0.055, 0.005, 0.02)))
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    out = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(out)
    bpy.ops.object.select_all(action='DESELECT')
    out.select_set(True)
    bpy.context.view_layer.objects.active = out
    rm = out.modifiers.new('rm', 'REMESH')
    rm.mode = 'VOXEL'
    rm.voxel_size = 0.010
    rm.adaptivity = 0.0
    bpy.ops.object.modifier_apply(modifier='rm')
    sm = out.modifiers.new('sm', 'SMOOTH')
    sm.factor = 0.55
    sm.iterations = 5
    bpy.ops.object.modifier_apply(modifier='sm')
    bmc = bmesh.new()
    for (c, r) in cutters:
        g = bmesh.ops.create_uvsphere(bmc, u_segments=14, v_segments=8, radius=1.0)
        bmesh.ops.transform(bmc, matrix=Matrix.Translation((sgn * c[0], -c[2], c[1])) @ Matrix.Diagonal((r[0], r[2], r[1], 1.0)), verts=g['verts'])
    mc = bpy.data.meshes.new(name + '_cut')
    bmc.to_mesh(mc)
    bmc.free()
    cutter = bpy.data.objects.new(name + '_cut', mc)
    bpy.context.scene.collection.objects.link(cutter)
    bo = out.modifiers.new('cut', 'BOOLEAN')
    bo.operation = 'DIFFERENCE'
    bo.object = cutter
    bo.solver = 'EXACT'
    bpy.ops.object.modifier_apply(modifier='cut')
    bpy.data.objects.remove(cutter)
    n0 = len(out.data.polygons)
    dec = out.modifiers.new('dec', 'DECIMATE')
    dec.ratio = min(1.0, 3400.0 / max(n0, 1))
    bpy.ops.object.modifier_apply(modifier='dec')
    for p in out.data.polygons:
        p.use_smooth = True
    out.data.materials.append(mats['s3_stone'])
    col = out.data.color_attributes.new('Col', 'BYTE_COLOR', 'CORNER')
    for d in col.data:
        d.color = (0.9, 0.9, 0.9, 1.0)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=1.15, island_margin=0.02)
    bpy.ops.object.mode_set(mode='OBJECT')
    return out


def export_glb(ob, path):
    import bpy
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_apply=True,
                              export_materials='PLACEHOLDER' if False else 'EXPORT', export_image_format='NONE',
                              export_vertex_color='ACTIVE', export_yup=True, export_normals=True, export_texcoords=True)


def write_meta(b, name, ob=None, extra=None):
    lo, hi = b.bounds() if b is not None and b.polys else (np.zeros(3), np.zeros(3))
    meta = {
        'name': name, 'tris': b.tri_count() if b is not None else (len(ob.data.polygons) if ob else 0),
        'render_bounds': {'min': [float(v) for v in lo], 'max': [float(v) for v in hi]},
        'collision': b.cols if b is not None else [], 'markers': b.markers if b is not None else {},
    }
    if extra:
        meta.update(extra)
    json.dump(meta, open(os.path.join(OUT, name + '.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    return meta


def main():
    import bpy
    bpy.ops.wm.read_factory_settings(use_empty=True)
    mats = make_mats()
    builders = [build_haiden(), build_saisen(), build_torii(), build_temizuya(), build_storehouse(),
                build_lantern('lantern_l', 1.0, 61), build_lantern('lantern_s', 0.80, 62),
                build_komainu_base('komainu_base', 63)] + build_props()
    report = []
    for b in builders:
        ob = s3b.to_blender(b, mats)
        export_glb(ob, os.path.join(OUT, b.name + '.glb'))
        meta = write_meta(b, b.name)
        report.append((b.name, meta['tris'], meta['render_bounds']))
    for name, open_m, mir in (('komainu_a', True, False), ('komainu_un', False, True)):
        ob = komainu_statue(mats, name, open_m, mir)
        export_glb(ob, os.path.join(OUT, name + '.glb'))
        bb = [ob.matrix_world @ __import__('mathutils').Vector(c) for c in ob.bound_box]
        lo = [min(v[0] for v in bb), min(v[2] for v in bb), min(-v[1] for v in bb)]
        hi = [max(v[0] for v in bb), max(v[2] for v in bb), max(-v[1] for v in bb)]
        tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
        json.dump({'name': name, 'tris': tris, 'render_bounds': {'min': lo, 'max': hi}, 'collision': [], 'markers': {}},
                  open(os.path.join(OUT, name + '.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
        report.append((name, tris, {'min': lo, 'max': hi}))
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE, 'shrine_v3_arch.blend'))
    for name, tris, rb in report:
        lo, hi = rb['min'], rb['max']
        print('[ARCH] %-14s tris %6d  size %.2f×%.2f×%.2f  min y %.3f  max y %.3f' % (
            name, tris, hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2], lo[1], hi[1]))


if __name__ == '__main__':
    main()

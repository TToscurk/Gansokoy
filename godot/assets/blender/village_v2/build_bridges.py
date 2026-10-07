"""正式橋×5（Roads/Bridges/Bridge_01–05）— 人間之里 V2 P7 R2 新資產（每座橋一件資產）。

  blender -b --factory-startup --python godot/assets/blender/village_v2/build_bridges.py [-- bridge_01 …]

尺寸 authority：P4 灰盒橋（gen_village_v2.gd _bridges：橋長、寬、兩端橋面高）＋ layout terrain.bridge_spans（P0 橋長 ±10 %）。
地形／水面：tools/village_v2_bridge_survey.gd → bridge_sites.json（0.5 m 格網，相對灰盒箱頂中心）。
參考：docs/reference/橋/地基拱橋1.png（水渠橋：石橋台＋笠石、微拱木橋面、圓木柱立在錐形石墩上、三道橫木欄杆＋擬寶珠）、
      長橋.png（龍神橋：河中木排架〔方柱＋冠木＋貫＋X 斜撐〕立在石墩上、兩端切石橋台）。都不上朱漆。
使用者 2026-09-28：面數預算已核准——水渠小橋 LOD0 ≤ 15k、龍神橋 ≤ 30k。

局部座標（Godot）：原點＝灰盒橋面頂中心（兩端橋面高的平均；hero_lib bridge_frame）、只有 yaw；
  +z＝道路方向（往灰盒 end_heights[0] 那端）、+x＝右側；y 相對原點。按實長建，不縮放。
橋面縱斷（橋板頂）：y(z) = dh·z/L + rise·(1 − (2z/L)²)——兩端落在灰盒兩端橋面高（terrain gate 橋端高差不變），中間微拱。
拱度受道路縱坡 gate（10 m 視窗）限制：參考圖的 rise/span 0.08–0.12 會超坡，水渠橋取 ≈ L/40、龍神橋 L/70。
碰撞 ≤ 8（gate）：Deck＋Rail_L／R＋Abut_S／N＋河中支撐簡化 proxy ≤ 3 組。可見支撐數不受碰撞數限制（使用者 2026-09-28）：
  龍神橋依參考圖 8 座排架（水側 31.5 m、間距 3.5 m），碰撞把相鄰排架併成 3 個 convex proxy（Bents_A–C）。
"""
import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import v2_kit as K  # noqa: E402

G = K.repo_paths(__file__)
MATLIB = K.load_json(G + '/assets/village_v2/_matlib/matlib.json')
TILE = {k: v['tile_m'] for k, v in MATLIB['materials'].items()}
MATS = ['V2_Wood', 'V2_Stone', 'V2_Metal']
SITES = {b['name']: b for b in K.load_json(G + '/assets/blender/village_v2/bridge_sites.json')['bridges']}
X, Y, Z = K.X, K.Y, K.Z

PLANK_T = 0.08      # 橋板厚
RAIL_H = 0.95       # 架木頂離橋面
END_POST_H = 1.10   # 親柱頂離橋面（擬寶珠另加 0.30）
BATTER = 0.12       # 石橋台水側面：每公尺高往岸側退 0.12 m
CAP = 0.22          # 笠石厚

# faces＝兩端石橋台水側面頂緣（局部 z）；n_sup＝河中支撐站數（等分）；deck_d＝橋面結構深（橋板頂→桁底）
CFG = {
    'Bridge_01_HillFootStreet_Canal': dict(id='bridge_01', label='丘腳街水渠橋', cls='水渠橋', kind='canal',
                                           rise=0.42, faces=(-5.0, 6.0), n_sup=2, deck_d=0.45),
    'Bridge_02_DragonBridgeRoad_River': dict(id='bridge_02', label='龍神橋', cls='龍神橋', kind='long',
                                             rise=0.60, faces=(-17.0, 14.5), n_sup=8, deck_d=0.60),
    'Bridge_03_CrossStreetMid_Canal': dict(id='bridge_03', label='中通水渠橋', cls='水渠橋', kind='canal',
                                           rise=0.38, faces=(-3.8, 4.0), n_sup=1, deck_d=0.45),
    'Bridge_04_CrossStreetSouth_Canal': dict(id='bridge_04', label='南通水渠橋', cls='水渠橋', kind='canal',
                                             rise=0.35, faces=(-4.8, 4.8), n_sup=1, deck_d=0.45),
    'Bridge_05_WestLane_WestStream': dict(id='bridge_05', label='西小路小橋', cls='水渠橋', kind='canal',
                                          rise=0.30, faces=(-3.4, 3.4), n_sup=0, deck_d=0.25),
}
BUDGET = {'水渠橋': 15000, '龍神橋': 30000}
SUP_COLS = 3        # 河中支撐碰撞 proxy 上限（8 − Deck − Rail×2 − Abut×2）


class Site:
    """bridge_sites.json 的 0.5 m 格網（局部 xz；terrain／water 相對原點）。"""

    def __init__(self, b):
        g = b['grid']
        self.gx, self.gz, self.t, self.w = g['x'], g['z'], g['terrain'], g['water']

    def _idx(self, a, v):
        f = (v - a[0]) / (a[1] - a[0])
        i = max(0, min(len(a) - 2, int(math.floor(f))))
        return i, max(0.0, min(1.0, f - i))

    def T(self, x, z):
        i, fx = self._idx(self.gx, x)
        j, fz = self._idx(self.gz, z)

        def g(jj, ii):
            v = self.t[jj][ii]
            return v if v is not None else 0.0
        a = g(j, i) * (1 - fx) + g(j, i + 1) * fx
        c = g(j + 1, i) * (1 - fx) + g(j + 1, i + 1) * fx
        return a * (1 - fz) + c * fz

    def Wy(self, x, z):
        i, fx = self._idx(self.gx, x)
        j, fz = self._idx(self.gz, z)
        return self.w[j + (1 if fz > 0.5 else 0)][i + (1 if fx > 0.5 else 0)]

    def minmax(self, x0, z0, x1, z1, step=0.25):
        lo, hi = 1e9, -1e9
        nx = max(2, int(math.ceil((x1 - x0) / step)))
        nz = max(2, int(math.ceil((z1 - z0) / step)))
        for i in range(nx + 1):
            for j in range(nz + 1):
                h = self.T(x0 + (x1 - x0) * i / nx, z0 + (z1 - z0) * j / nz)
                lo, hi = min(lo, h), max(hi, h)
        return lo, hi


def face(m, ps, mat, col, out, grain=Y):
    """多邊形：依 out 決定繞向（外法線朝 out）。"""
    n = K.cross(K.sub(ps[1], ps[0]), K.sub(ps[2], ps[0]))
    if K.dot(n, out) < 0:
        ps = list(reversed(ps))
    m.poly(ps, mat, col, grain=grain)


def stations(a, b, step):
    n = max(1, int(math.ceil(abs(b - a) / step - 1e-6)))
    return [a + (b - a) * i / n for i in range(n + 1)]


def r3(p):
    return [round(v, 3) for v in p]


class Bridge:
    def __init__(self, name):
        self.name = name
        self.c = CFG[name]
        b = SITES[name]
        self.b = b
        self.s = Site(b)
        self.L, self.W, self.dh, self.hw = float(b['L']), float(b['W']), float(b['dh']), float(b['road_hw'])
        self.rise = self.c['rise']
        self.dd = self.c['deck_d']
        self.f0, self.f1 = self.c['faces']
        self.xr = self.W / 2 - 0.10                    # 欄杆中心線
        self.xa = self.W / 2 + 0.10                    # 石橋台半寬
        n = self.c['n_sup']
        self.sup = [self.f0 + (self.f1 - self.f0) * (k + 1) / (n + 1) for k in range(n)]
        if self.c['kind'] == 'long':
            self.post_x = [-(self.W / 2 - 0.45), 0.0, self.W / 2 - 0.45]
        elif self.W > 5.0:
            self.post_x = [-(self.W / 2 - 0.55), 0.0, self.W / 2 - 0.55]
        else:
            self.post_x = [-(self.W / 2 - 0.45), self.W / 2 - 0.45]
        self.z0, self.z1 = -self.L / 2, self.L / 2
        self.ze0, self.ze1 = self.z0 + 0.25, self.z1 - 0.25     # 親柱中心
        self.ground, self.cols, self.sup_info, self.bent_box = [], [], [], []

    def y(self, z):
        return self.dh * z / self.L + self.rise * (1.0 - (2.0 * z / self.L) ** 2)

    def dy(self, z):
        return self.dh / self.L - 8.0 * self.rise * z / (self.L * self.L)

    def res(self, lod, fine):
        return {0: fine, 1: fine * 2.0}.get(lod, 99.0)

    # ── 橋面：橋板（橫鋪）、縱桁、鼻隠（邊桁）、底板
    def deck(self, m, lod):
        W, L = self.W, self.L
        seg = stations(self.z0, self.z1, self.res(lod, 1.0) if lod < 2 else L / 4.0)
        yt = [self.y(z) for z in seg]
        if lod == 0:
            pw = 0.24
            n = int(L / (pw + 0.02))
            st = L / n
            for k in range(n):
                zc = self.z0 + st * (k + 0.5)
                az = K.norm((0.0, self.dy(zc), 1.0))
                ay = K.cross(az, X)
                c = K.add((0.0, self.y(zc), zc), K.mul(ay, -PLANK_T / 2))
                col = 0.50 + 0.10 * ((k * 7) % 5) / 4.0
                m.obox(c, (W / 2 - 0.13, PLANK_T / 2, (st - 0.02) / 2), 'V2_Wood', col, ax=X, ay=ay, az=az,
                       grain=X, skip=('-y',))
            gx = [-(W / 2 - 0.45), -W / 6, W / 6, W / 2 - 0.45] if W > 5 else [-(W / 2 - 0.40), 0.0, W / 2 - 0.40]
            for x in gx:
                for i in range(len(seg) - 1):
                    hmid = (self.dd - PLANK_T) / 2
                    m.beam((x, yt[i] - PLANK_T - hmid, seg[i]), (x, yt[i + 1] - PLANK_T - hmid, seg[i + 1]),
                           0.22, self.dd - PLANK_T, 'V2_Wood', 0.44, skip_ends=(0 < i < len(seg) - 2))
        # 底板：LOD0 在橋板下（縫中看到暗面）；LOD1/2 是橋面本體的底，另加頂面
        ub = PLANK_T + 0.01 if lod == 0 else self.dd
        for i in range(len(seg) - 1):
            a, b = seg[i], seg[i + 1]
            face(m, [(-W / 2 + 0.12, yt[i] - ub, a), (W / 2 - 0.12, yt[i] - ub, a),
                     (W / 2 - 0.12, yt[i + 1] - ub, b), (-W / 2 + 0.12, yt[i + 1] - ub, b)],
                 'V2_Wood', 0.30 if lod == 0 else 0.40, (0.0, -1.0, 0.0), grain=X)
            if lod > 0:
                face(m, [(-W / 2, yt[i], a), (W / 2, yt[i], a), (W / 2, yt[i + 1], b), (-W / 2, yt[i + 1], b)],
                     'V2_Wood', 0.55, Y, grain=X)
        # 鼻隠：兩側邊桁（外面齊 ±W/2、高＝結構深＋0.04）
        eb = 0.12
        for sx in (-1.0, 1.0):
            if lod == 0:
                xc = sx * (W / 2 - eb / 2)
                for i in range(len(seg) - 1):
                    hh = self.dd + 0.04
                    m.beam((xc, yt[i] + 0.02 - hh / 2, seg[i]), (xc, yt[i + 1] + 0.02 - hh / 2, seg[i + 1]),
                           eb, hh, 'V2_Wood', 0.50, skip_ends=(0 < i < len(seg) - 2))
            else:
                x = sx * W / 2
                for i in range(len(seg) - 1):
                    face(m, [(x, yt[i] - self.dd - 0.02, seg[i]), (x, yt[i + 1] - self.dd - 0.02, seg[i + 1]),
                             (x, yt[i + 1] + 0.02, seg[i + 1]), (x, yt[i] + 0.02, seg[i])],
                         'V2_Wood', 0.50, (sx, 0.0, 0.0), grain=Z)
        if lod > 0:
            for zz, sg in ((self.z0, -1.0), (self.z1, 1.0)):
                yy = self.y(zz)
                face(m, [(-W / 2, yy - self.dd - 0.02, zz), (W / 2, yy - self.dd - 0.02, zz), (W / 2, yy + 0.02, zz),
                         (-W / 2, yy + 0.02, zz)], 'V2_Wood', 0.45, (0.0, 0.0, sg))

    # ── 欄杆：地覆、平桁、架木、束；兩端親柱＋柱頭鐵板＋擬寶珠（黑銅）
    def rail(self, m, lod):
        n = max(2, int(round((self.ze1 - self.ze0) / 1.9)))
        pz = [self.ze0 + (self.ze1 - self.ze0) * k / n for k in range(n + 1)]
        for sx in (-1.0, 1.0):
            x = sx * self.xr
            if lod == 2:
                sg = stations(self.ze0, self.ze1, (self.ze1 - self.ze0) / 4.0)
                for i in range(len(sg) - 1):
                    a, b = sg[i], sg[i + 1]
                    for off in (0.06, -0.06):
                        xx = x + off
                        face(m, [(xx, self.y(a), a), (xx, self.y(b), b), (xx, self.y(b) + RAIL_H, b),
                                 (xx, self.y(a) + RAIL_H, a)], 'V2_Wood', 0.55, (1.0 if off > 0 else -1.0, 0.0, 0.0), grain=Z)
                for zc in (self.ze0, self.ze1):
                    yy = self.y(zc)
                    m.box((x - 0.13, yy - 0.05, zc - 0.13), (x + 0.13, yy + END_POST_H + 0.30, zc + 0.13),
                          'V2_Wood', 0.5, skip=('-y',))
                continue
            for i in range(len(pz) - 1):
                a, b = pz[i], pz[i + 1]
                ya, yb = self.y(a), self.y(b)
                m.beam((x, ya + 0.09, a), (x, yb + 0.09, b), 0.16 if lod == 0 else 0.14, 0.18, 'V2_Wood', 0.46,
                       skip_ends=True)
                if lod == 0:
                    m.beam((x, ya + 0.52, a), (x, yb + 0.52, b), 0.08, 0.10, 'V2_Wood', 0.60, skip_ends=True)
                m.beam((x, ya + RAIL_H - 0.05, a), (x, yb + RAIL_H - 0.05, b), 0.12, 0.10, 'V2_Wood', 0.64,
                       skip_ends=True)
            for zc in pz[1:-1]:
                yy = self.y(zc)
                m.box((x - 0.075, yy - 0.02, zc - 0.075), (x + 0.075, yy + RAIL_H + 0.04, zc + 0.075), 'V2_Wood', 0.56,
                      skip=('-y',))
            for zc in (self.ze0, self.ze1):
                yy = self.y(zc)
                h = yy + END_POST_H
                m.box((x - 0.13, yy - 0.05, zc - 0.13), (x + 0.13, h, zc + 0.13), 'V2_Wood', 0.50, skip=('-y',))
                if lod == 0:
                    m.box((x - 0.14, h - 0.20, zc - 0.14), (x + 0.14, h - 0.08, zc + 0.14), 'V2_Metal', 0.85,
                          skip=('-y', '+y'))
                    prof = [(0.0, 0.07), (0.05, 0.07), (0.07, 0.13), (0.15, 0.14), (0.23, 0.09), (0.28, 0.035),
                            (0.30, 0.012)]
                    for k in range(len(prof) - 1):
                        (h0, r0), (h1, r1) = prof[k], prof[k + 1]
                        m.cyl((x, h + h0, zc), (x, h + h1, zc), r0, r1, 10, 'V2_Metal', 0.9,
                              caps=(k == 0, k == len(prof) - 2))
                else:
                    m.cyl((x, h, zc), (x, h + 0.30, zc), 0.13, 0.02, 6, 'V2_Metal', 0.9, caps=(False, True))
        if lod == 0:
            for sx, nm in ((-1.0, 'Rail_L'), (1.0, 'Rail_R')):
                x = sx * self.xr
                pts = []
                for zc in stations(self.ze0 - 0.16, self.ze1 + 0.16, 1.0):
                    yy = self.y(min(max(zc, self.ze0), self.ze1))
                    for xx in (x - 0.15, x + 0.15):
                        pts += [[xx, yy - 0.06, zc], [xx, yy + RAIL_H + 0.06, zc]]
                for zc in (self.ze0, self.ze1):
                    yy = self.y(zc)
                    for xx in (x - 0.15, x + 0.15):
                        for zz in (zc - 0.15, zc + 0.15):
                            pts.append([xx, yy + END_POST_H + 0.32, zz])
                self.cols.append({'type': 'convex', 'name': nm, 'center': [0, 0, 0], 'points': [r3(p) for p in pts]})

    # ── 石橋台：本體（側牆、水側 batter 面、外端）＋笠石（頂面沿橋面縱斷、四周出 0.06）＋角石
    def abut(self, m, lod, side):
        s = self.s
        xa = self.xa
        za = self.f0 if side < 0 else self.f1
        zo = self.z0 + 0.30 if side < 0 else self.z1 - 0.30

        def top(z):
            return self.y(z) - PLANK_T - 0.01

        lo, _ = s.minmax(-xa, min(za, zo) - 1.5, xa, max(za, zo) + 1.5)
        yb = lo - 0.35
        hb = top(za) - CAP - yb
        zb = za - side * BATTER * hb          # 水側面底緣（往水裡伸；side<0 時水在 +z）
        st = stations(min(za, zo), max(za, zo), self.res(lod, 1.0))
        for x in (-xa, xa):
            out = (1.0 if x > 0 else -1.0, 0.0, 0.0)
            for i in range(len(st) - 1):
                a, b = st[i], st[i + 1]
                face(m, [(x, yb, a), (x, yb, b), (x, top(b) - CAP, b), (x, top(a) - CAP, a)], 'V2_Stone', 0.84, out)
            face(m, [(x, yb, za), (x, yb, zb), (x, top(za) - CAP, za)], 'V2_Stone', 0.84, out)
        face(m, [(-xa, yb, zb), (xa, yb, zb), (xa, top(za) - CAP, za), (-xa, top(za) - CAP, za)], 'V2_Stone', 0.80,
             (0.0, 0.2, float(-side)))
        face(m, [(-xa, yb, zo), (xa, yb, zo), (xa, top(zo) - CAP, zo), (-xa, top(zo) - CAP, zo)], 'V2_Stone', 0.80,
             (0.0, 0.0, float(side)))
        ov = 0.06
        zc = za - side * ov
        stc = stations(min(zc, zo), max(zc, zo), self.res(lod, 1.0))
        for i in range(len(stc) - 1):
            a, b = stc[i], stc[i + 1]
            ta, tb = top(min(max(a, min(za, zo)), max(za, zo))), top(min(max(b, min(za, zo)), max(za, zo)))
            face(m, [(-xa - ov, ta, a), (xa + ov, ta, a), (xa + ov, tb, b), (-xa - ov, tb, b)], 'V2_Stone', 0.95, Y, grain=X)
            for x in (-xa - ov, xa + ov):
                face(m, [(x, ta - CAP, a), (x, tb - CAP, b), (x, tb, b), (x, ta, a)], 'V2_Stone', 0.92,
                     (1.0 if x > 0 else -1.0, 0.0, 0.0))
        tz = top(za)
        face(m, [(-xa - ov, tz - CAP, zc), (xa + ov, tz - CAP, zc), (xa + ov, tz, zc), (-xa - ov, tz, zc)], 'V2_Stone',
             0.92, (0.0, 0.0, float(-side)))
        face(m, [(-xa - ov, tz - CAP, zc), (xa + ov, tz - CAP, zc), (xa + ov, tz - CAP, za), (-xa - ov, tz - CAP, za)],
             'V2_Stone', 0.70, (0.0, -1.0, 0.0))
        if lod == 0:
            # 角石：水側兩角，長短交錯（算木積み），往外凸 0.04
            nq = max(2, int(hb / 0.45))
            for k in range(nq):
                y0, y1 = yb + hb * k / nq, yb + hb * (k + 1) / nq - 0.02
                zf = za - side * BATTER * (top(za) - CAP - (y0 + y1) / 2)
                lx, lz = (0.70, 0.40) if k % 2 == 0 else (0.40, 0.70)
                for sx in (-1.0, 1.0):
                    x0, x1 = (xa - lx, xa + 0.04) if sx > 0 else (-xa - 0.04, -xa + lx)
                    z0, z1 = (zf - lz, zf + 0.04) if side < 0 else (zf - 0.04, zf + lz)
                    m.box((x0, y0, z0), (x1, y1, z1), 'V2_Stone', 0.74 if k % 2 else 0.88, skip=('-y',))
            # 接地件：從水側底緣往岸側延伸，取到「笠石頂仍高出範圍內最高地形 0.10 m」的最遠處（格網內插 vs 地形碰撞留餘裕）；
            # 最少取水側 batter 腳（zb～za）
            best = None
            zr = za
            while abs(zr) <= abs(zo) + 1e-6:
                q0, q1 = sorted((zb, zr))
                lo2, hi2 = s.minmax(-xa, q0, xa, q1)
                tv = min(top(z) for z in stations(min(za, zr), max(za, zr) + 1e-4, 0.25))
                if tv >= hi2 + 0.10 and yb <= lo2 - 0.2:
                    best = (q0, q1, lo2, hi2, tv)
                    zr -= side * 0.25
                else:
                    break
            if best is None:
                raise RuntimeError('%s 石橋台 %+d：沒有可驗的接地範圍' % (self.name, side))
            q0, q1, lo2, hi2, tv = best
            self.ground.append({'name': '石橋台%s' % ('−z' if side < 0 else '＋z'), 'rect': r3([-xa, q0, xa, q1]),
                                'bottom': round(yb, 3), 'top': round(tv, 3),
                                'embed_max': round(lo2 - yb + 0.05, 3), 'road_ok': [r['name'] for r in self.b['roads']]})
            pts = []
            for z in stations(min(zb, zo), max(zb, zo), 1.0):
                zz = min(max(z, min(za, zo)), max(za, zo))
                for x in (-xa - ov, xa + ov):
                    pts += [[x, yb, z], [x, top(zz), z]]
            self.cols.append({'type': 'convex', 'name': 'Abut_%s' % ('S' if side < 0 else 'N'), 'center': [0, 0, 0],
                              'points': [r3(p) for p in pts]})

    # ── 河中支撐：水渠橋＝圓木柱立在錐形石墩（柱頭枕梁、腰貫、鐵箍）；龍神橋＝方柱排架（冠木、貫二道、X 斜撐）
    def supports(self, m, lod):
        s = self.s
        long_t = self.c['kind'] == 'long'
        xs = self.post_x
        for k, zs in enumerate(self.sup):
            ytop = self.y(zs) - self.dd
            x0, x1 = xs[0] - 0.62, xs[-1] + 0.62
            lo, _ = s.minmax(x0, zs - 0.62, x1, zs + 0.62)
            fb = lo - 0.30
            wy = None
            for x in xs + [x0, x1]:
                w = s.Wy(x, zs)
                if w is not None:
                    wy = w if wy is None else max(wy, w)
            cap_h = 0.40 if long_t else 0.30
            cap_y0 = ytop - cap_h
            tops = []
            for x in xs:
                bed = s.T(x, zs)
                pt = max(bed + 0.5, (wy + 0.30) if wy is not None else bed + 0.5)
                pt = min(pt, cap_y0 - 0.6)
                tops.append(pt)
                if lod == 2:
                    continue
                seg = 10 if lod == 0 else 6
                if long_t:
                    m.cyl((x, fb, zs), (x, pt, zs), 0.60, 0.42, 8 if lod == 0 else 6, 'V2_Stone', 0.82, caps=(False, True),
                          phase=math.pi / 8)
                else:
                    m.cyl((x, fb, zs), (x, pt, zs), 0.46, 0.32, seg, 'V2_Stone', 0.82, caps=(False, True))
                pb = pt
                if lod == 0:
                    m.cyl((x, pt, zs), (x, pt + 0.10, zs), 0.38 if long_t else 0.35, 0.34 if long_t else 0.31, seg,
                          'V2_Stone', 0.92, caps=(False, True))
                    pb = pt + 0.10
                if long_t:
                    m.box((x - 0.15, pb, zs - 0.15), (x + 0.15, cap_y0, zs + 0.15), 'V2_Wood', 0.46, skip=('-y', '+y'))
                else:
                    m.cyl((x, pb, zs), (x, cap_y0, zs), 0.18, 0.18, seg, 'V2_Wood', 0.46, caps=(False, False))
                if lod == 0:
                    for yb in (pb + 0.20, cap_y0 - 0.25):
                        if long_t:
                            m.box((x - 0.165, yb, zs - 0.165), (x + 0.165, yb + 0.07, zs + 0.165), 'V2_Metal', 0.85,
                                  skip=('-y', '+y'))
                        else:
                            m.cyl((x, yb, zs), (x, yb + 0.07, zs), 0.195, 0.195, seg, 'V2_Metal', 0.85,
                                  caps=(False, False))
            if lod == 2:
                m.box((x0 + 0.12, fb, zs - 0.40), (x1 - 0.12, ytop, zs + 0.40), 'V2_Wood', 0.46, skip=('-y',))
            else:
                m.box((xs[0] - 0.40, cap_y0, zs - 0.17), (xs[-1] + 0.40, ytop, zs + 0.17), 'V2_Wood', 0.50)
                pmax = max(tops) + (0.10 if lod == 0 else 0.0)
                fr = [0.35, 0.75] if long_t else [0.5]
                for f in (fr if lod == 0 else fr[-1:]):
                    yn = pmax + 0.15 + (cap_y0 - pmax - 0.15) * f
                    m.box((xs[0] - 0.30, yn - 0.09, zs - 0.07), (xs[-1] + 0.30, yn + 0.09, zs + 0.07), 'V2_Wood', 0.52)
                if long_t and cap_y0 - pmax > 0.9:
                    yl = pmax + 0.20
                    for i in range(len(xs) - 1):
                        a, b = xs[i], xs[i + 1]
                        m.beam((a + 0.15, yl, zs + 0.10), (b - 0.15, cap_y0 - 0.08, zs + 0.10), 0.08, 0.12, 'V2_Wood', 0.48,
                               up=(0.0, 0.0, 1.0))
                        if lod == 0:
                            m.beam((b - 0.15, yl, zs - 0.10), (a + 0.15, cap_y0 - 0.08, zs - 0.10), 0.08, 0.12, 'V2_Wood',
                                   0.48, up=(0.0, 0.0, 1.0))
            if lod == 0:
                self.ground.append({'name': '橋脚%d' % (k + 1), 'rect': r3([x0, zs - 0.62, x1, zs + 0.62]),
                                    'bottom': round(fb, 3), 'top': round(ytop, 3), 'embed_max': 0.35,
                                    'road_ok': [r['name'] for r in self.b['roads']]})
                self.bent_box.append((x0 - 0.05, x1 + 0.05, zs - 0.65, zs + 0.65, fb, ytop))
                self.sup_info.append({'z': round(zs, 3), 'pier_bottom': round(fb, 3), 'pier_top': round(max(tops), 3),
                                      'deck_bottom': round(ytop, 3), 'water_y': wy, 'posts': len(xs)})

    # 河中支撐碰撞：相鄰支撐併成 ≤ SUP_COLS 個 convex proxy（每支撐的外框 8 角點 → 一組 hull）
    def support_collision(self):
        n = len(self.bent_box)
        if n == 0:
            return
        g = min(n, SUP_COLS)
        for gi in range(g):
            grp = self.bent_box[n * gi // g: n * (gi + 1) // g]
            pts = []
            for (xa, xb, za, zb, yb, yt) in grp:
                for x in (xa, xb):
                    for z in (za, zb):
                        pts += [[x, yb, z], [x, yt, z]]
            nm = ('Bent_%d' % (gi + 1)) if g == n else ('Bents_%s' % 'ABC'[gi])
            self.cols.append({'type': 'convex', 'name': nm, 'center': [0, 0, 0], 'points': [r3(p) for p in pts]})

    def deck_collision(self):
        W = self.W
        pts = []
        for z in stations(self.z0, self.z1, 1.0):
            for x in (-W / 2, W / 2):
                pts.append([x, self.y(z), z])
        for zz, sg in ((self.z0, -1.0), (self.z1, 1.0)):
            ye = self.y(zz)
            for x in (-W / 2, W / 2):
                pts.append([x, ye - 0.15, zz + sg * 0.6])       # 橋頭接坡：多伸 0.6 m、低 0.15（玩家不卡橋頭）
                pts.append([x, ye - self.dd - 0.10, zz])
        self.cols.insert(0, {'type': 'convex', 'name': 'Deck', 'center': [0, 0, 0], 'points': [r3(p) for p in pts]})

    def build(self, lod):
        m = K.Mesh('%s_LOD%d' % (self.c['id'], lod), MATS, TILE)
        self.deck(m, lod)
        self.rail(m, lod)
        self.abut(m, lod, -1)
        self.abut(m, lod, 1)
        self.supports(m, lod)
        return m


def tri_count(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    out = {}
    for o in [o for o in bpy.data.objects if o not in before]:
        if o.type == 'MESH':
            out[o.name.split('.')[0]] = sum(len(p.vertices) - 2 for p in o.data.polygons)
        bpy.data.objects.remove(o, do_unlink=True)
    return out


def main(name):
    c = CFG[name]
    bid = c['id']
    out = G + '/assets/village_v2/' + bid
    br = Bridge(name)
    b = br.b
    K.clear_scene(bpy)
    bm = K.blender_mats(bpy, MATS)
    meshes = [br.build(lod) for lod in (0, 1, 2)]
    objs = [mm.to_blender(bpy, bmats=bm) for mm in meshes]
    br.support_collision()
    br.deck_collision()
    glb = out + '/src/%s.glb' % bid
    K.export_glb(bpy, glb, objs)
    gi = out + '/src/.gdignore'
    if not os.path.exists(gi):
        open(gi, 'w').close()
    cnt = tri_count(glb)
    stats = {'LOD%d' % i: cnt['%s_LOD%d' % (bid, i)] for i in range(3)}
    v0 = meshes[0].v
    xh = max(abs(p[0]) for p in v0)
    top = max(p[1] for p in v0)
    bot = min(p[1] for p in v0)
    L, W = br.L, br.W
    gs = {
        'placement': 'bridge', 'anchor': 'Roads/Bridges/' + name, 'replaces': '',
        'p4_id': '', 'parcel': '', 'road': b['road'],
        'size': {'x_half_max': round(xh + 0.02, 3), 'z_min': round(-L / 2 - 0.05, 3), 'z_max': round(L / 2 + 0.05, 3),
                 'top': [round(top - 0.05, 3), round(top + 0.05, 3)], 'bottom': round(bot, 3)},
        'ground': br.ground,
        # 橋專屬驗收（gate _c_bridge_*）：規格＝灰盒橋（L、dh、W）＋P0 span；freeboard＝結構底離水面
        'bridge': {'L': L, 'W': W, 'dh': br.dh, 'rise': br.rise, 'road_hw': br.hw, 'water_node': b['water_node'],
                   'span': b['span'], 'deck_depth': br.dd, 'supports': [round(z, 3) for z in br.sup],
                   'rail_x': round(br.xr, 3), 'rail_h': RAIL_H, 'freeboard_min': 0.15, 'end_tol': 0.15,
                   'grade_max': 0.12},
        'shots': [['approach', 0.0, round(-(L / 2 + 8.0), 2), 0.0, 0.0],
                  ['approach_far', 0.0, round(L / 2 + 9.0, 2), 0.0, 0.0],
                  ['diag', round(W / 2 + 1.0, 2), round(-(L / 2 + 12.0), 2), 0.0, round(L / 4, 2)]],
        'walk': {'from': [0.0, round(-(L / 2 + 5.0), 2)], 'to': [0.0, round(L / 2 + 5.0, 2)]},
    }
    spec = {
        '_note': '%s 資產規格（build_bridges.py 產生；Godot 端 tools/village_v2_hero_prefab.gd、verify_village_v2_hero_gate.gd 讀取）。'
                 '放置＝P4 灰盒橋 %s（gate_spec.placement bridge：原點＝灰盒橋面頂中心、只 yaw）。' % (c['label'], name),
        'id': bid, 'landmark': '', 'kind': 'bridge', 'budget_class': c['cls'], 'label': c['label'],
        'glb': 'res://assets/village_v2/%s/src/%s.glb' % (bid, bid),
        'scene': 'res://assets/village_v2/%s/%s.scn' % (bid, bid),
        'lod_objects': ['%s_LOD%d' % (bid, i) for i in range(3)],
        'lod_ranges_m': [0, 60, 160, 0],
        'budget': {'lod0': BUDGET[c['cls']], 'lod1_ratio': 0.35, 'lod2_ratio': 0.10, 'materials': 5, 'collision': 8},
        'materials': {k: MATLIB['materials'][k]['tres'] for k in MATS},
        'spec': {'type': '石橋台＋微拱木橋面＋%s' % ('河中木排架（方柱、冠木、貫、X 斜撐）' if c['kind'] == 'long'
                                               else ('圓木柱石墩支撐' if br.sup else '單跨（淺溪，無中支撐）')),
                 'length_m': L, 'width_m': W, 'rise_m': br.rise, 'end_dh_m': br.dh, 'deck_depth_m': br.dd,
                 'span_p0': b['span'], 'rail_h_m': RAIL_H, 'end_post_h_m': END_POST_H, 'supports': br.sup_info,
                 'abutment_faces_z': [br.f0, br.f1],
                 'front': '+z＝道路方向（灰盒 end_heights[0] 那端）；原點＝灰盒橋面頂中心'},
        'gate_spec': gs,
        'collision': br.cols,
        'measured_blender': stats,
    }
    K.write_json(out + '/asset.json', spec)
    print('[BRIDGE] %s %s L %.1f W %.1f LOD %s 碰撞 %d 接地 %d x±%.2f 頂 %.2f 底 %.2f' % (
        bid, c['label'], L, W, stats, len(br.cols), len(br.ground), xh, top, bot))


argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
for nm in CFG:
    if not argv or CFG[nm]['id'] in argv:
        main(nm)

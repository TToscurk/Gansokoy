"""人間之里 V2 厨子二階・平入切妻 町家／Hero 共用建構件（P5 R2 起）。

R1 build_suzunaan.py 已驗證（Asset Gate 11 項 PASS）的做法抽成參數化版本；鈴奈庵腳本本身不動。
尺寸一律由呼叫端依 P4 greybox 記錄給（W／D／簷／脊／台基／庇），本模組不寫死任何建築尺寸。
座標與 UV 慣例同 v2_kit.py（Godot 座標、原點＝footprint 中心、+z＝正面）。
"""
import math

import v2_kit as K
from v2_kit import X, Y, Z, add, mul, norm, sub, cross, dot

# 頂點色（線性乘數；V2_Wood 平均 #7A6445 → 結構深木 ≈ 0.34、板 ≈ 0.74）— 與 R1 相同
DARK, BOARD, MID = 0.34, 0.74, 0.50


class Zushi:
    def __init__(self, W, D, eave, pitch, plinth, bot, ov_e, ov_g, his_y, his_d, mats, amat, atlas, matlib):
        self.W, self.D = W, D
        self.HW, self.HD = W / 2, D / 2
        self.EAVE, self.PITCH, self.PLINTH, self.BOT = eave, pitch, plinth, bot
        self.OV_E, self.OV_G = ov_e, ov_g
        self.RIDGE = eave + self.HD * pitch
        self.SEC = math.sqrt(1 + pitch ** 2)
        self.HIS_Y, self.HIS_D = his_y, his_d
        self.LINTEL = (2.42, 2.58)
        self.PLATE = (3.62, 3.78)
        self.MATS, self.AMAT = mats, amat
        self.RG = atlas['regions']
        self.SWATCH = {k: v['uv'] for k, v in atlas['swatches'].items()}
        self.TILE = {k: v['tile_m'] for k, v in matlib.items()}
        self.KW = matlib['V2_Kawara']

    # ── 小工具
    def rsub(self, r, fx0, fy0, fx1, fy1):
        u0, v0, u1, v1 = r
        return [u0 + (u1 - u0) * fx0, v0 + (v1 - v0) * fy0, u0 + (u1 - u0) * fx1, v0 + (v1 - v0) * fy1]

    def sw(self, hexcol):
        u, v = self.SWATCH[hexcol]
        return [u - 0.003, v - 0.003, u + 0.003, v + 0.003]

    def roof_y(self, z):
        return self.RIDGE - self.PITCH * abs(z)

    def fz(self, m, x0, x1, y0, y1, z, mat, col=1.0, region=None, grain=Y, back=False):
        """z 平面矩形；預設朝 +z（back=True 朝 −z）。"""
        if back:
            a, b, c, d = (x1, y0, z), (x0, y0, z), (x0, y1, z), (x1, y1, z)
        else:
            a, b, c, d = (x0, y0, z), (x1, y0, z), (x1, y1, z), (x0, y1, z)
        if region:
            m.rect_uv(a, b, c, d, mat, region, col)
        else:
            m.quad(a, b, c, d, mat, col, grain=grain)

    def fx(self, m, z0, z1, y0, y1, x, mat, col=1.0, region=None, grain=Y, neg=False):
        """x 平面矩形；預設朝 +x（neg=True 朝 −x）。"""
        if neg:
            a, b, c, d = (x, y0, z0), (x, y0, z1), (x, y1, z1), (x, y1, z0)
        else:
            a, b, c, d = (x, y0, z1), (x, y0, z0), (x, y1, z0), (x, y1, z1)
        if region:
            m.rect_uv(a, b, c, d, mat, region, col)
        else:
            m.quad(a, b, c, d, mat, col, grain=grain)

    def recess(self, m, x0, x1, y0, y1, zf, depth, back_region, side_region=None, floor_col=0.42, col=1.0):
        """開口後的淺室（面朝內）：背板 atlas、側板、地板、天花。"""
        zb = zf - depth
        self.fz(m, x0, x1, y0, y1, zb, self.AMAT, col, back_region)
        if side_region:
            self.fx(m, zb, zf, y0, y1, x0, self.AMAT, col * 0.7, side_region)
            self.fx(m, zb, zf, y0, y1, x1, self.AMAT, col * 0.7, side_region, neg=True)
        else:
            self.fx(m, zb, zf, y0, y1, x0, 'V2_Wood', DARK * 0.7)
            self.fx(m, zb, zf, y0, y1, x1, 'V2_Wood', DARK * 0.7, neg=True)
        m.quad((x0, y0, zf), (x1, y0, zf), (x1, y0, zb), (x0, y0, zb), 'V2_Wood', floor_col, grain=X)
        m.quad((x0, y1, zb), (x1, y1, zb), (x1, y1, zf), (x0, y1, zf), 'V2_Wood', DARK * 0.45, grain=X)

    def shelf(self, m, x0, x1, y, zf, depth, col=BOARD * 0.7):
        m.box((x0, y - 0.03, zf - depth), (x1, y, zf), 'V2_Wood', col, grain=X, skip=('-z',))

    def bars(self, m, x0, x1, y0, y1, z0, z1, pitch, bw, col=DARK):
        n = int((x1 - x0) / pitch)
        off = (x1 - x0 - (n - 1) * pitch) / 2
        for k in range(n):
            x = x0 + off + k * pitch
            m.box((x - bw / 2, y0, z0), (x + bw / 2, y1, z1), 'V2_Wood', col, grain=Y, skip=('+y', '-y', '-z'))

    def abeam(self, m, a, b, w, h, region, col=1.0, up=Y):
        """atlas 色票角材（a→b，寬 w、高 h）。"""
        d = sub(b, a)
        L = math.sqrt(dot(d, d))
        ax = norm(d)
        uu = sub(up, mul(ax, dot(up, ax)))
        if dot(uu, uu) < 1e-6:
            uu = sub(Z, mul(ax, dot(Z, ax)))
        ay = norm(uu)
        az = cross(ax, ay)
        m.abox(mul(add(a, b), 0.5), (L / 2, h / 2, w / 2), self.AMAT, {'*': region}, col, ax, ay, az)

    def disc(self, m, c, n, r, seg, region, col=1.0, up=Y):
        """圓片（法線 n）：atlas 區域內切圓貼上。"""
        n = norm(n)
        ux = norm(cross(up, n)) if abs(dot(up, n)) < 0.95 else X
        uy = cross(n, ux)
        u0, v0, u1, v1 = region
        ps, uvs = [], []
        for i in range(seg):
            t = 2 * math.pi * i / seg
            ps.append(add(c, add(mul(ux, math.cos(t) * r), mul(uy, math.sin(t) * r))))
            uvs.append((u0 + (u1 - u0) * (0.5 + 0.5 * math.cos(t)), v0 + (v1 - v0) * (0.5 - 0.5 * math.sin(t))))
        m.face(m.verts(ps), self.AMAT, uvs, col)

    def oface(self, m, ps, want_n, mat, uvs, col=1.0, smooth=False):
        """任意多邊形；依 want_n 自動決定繞序（從外面看逆時針）。"""
        n = cross(sub(ps[1], ps[0]), sub(ps[2], ps[0]))
        if dot(n, want_n) < 0:
            ps, uvs = ps[::-1], uvs[::-1]
        m.face(m.verts(ps), mat, uvs, col, smooth)

    def chochin(self, m, c, r, h, region, lod, cap_col='#1E1B18'):
        """提燈：上下兩段截錐（中段最粗），atlas 展開 u 繞一圈、字在 u 0.25（正面 +z）；上下黑色口輪。"""
        seg = 12 if lod == 0 else 8
        x, y, z = c
        u0, v0, u1, v1 = region
        vm = (v0 + v1) / 2
        m.cyl((x, y - h / 2, z), (x, y, z), r * 0.72, r, seg, self.AMAT, 1.0, caps=(False, False),
              phase=math.pi / 2, uv_atlas=[u0, vm, u1, v1])
        m.cyl((x, y, z), (x, y + h / 2, z), r, r * 0.72, seg, self.AMAT, 1.0, caps=(False, False),
              phase=math.pi / 2, uv_atlas=[u0, v0, u1, vm])
        k = self.sw(cap_col)
        m.cyl((x, y - h / 2 - 0.03, z), (x, y - h / 2 + 0.01, z), r * 0.76, r * 0.76, seg, self.AMAT, 1.0,
              caps=(True, False), uv_atlas=k)
        m.cyl((x, y + h / 2 - 0.01, z), (x, y + h / 2 + 0.03, z), r * 0.76, r * 0.76, seg, self.AMAT, 1.0,
              caps=(False, True), uv_atlas=k)

    # ── 屋根
    def main_roof(self, m, lod, ridge_ends=True):
        HW, HD, OV_G, OV_E, PITCH, SEC, RIDGE = self.HW, self.HD, self.OV_G, self.OV_E, self.PITCH, self.SEC, self.RIDGE
        TW = self.TILE['V2_Wood']
        x0, x1 = -HW - OV_G, HW + OV_G
        S = (HD + OV_E) * SEC
        for sgn in (1, -1):
            dsl = norm((0.0, -PITCH, float(sgn)))
            n = norm((0.0, 1.0, PITCH * sgn))
            o = (0.0, RIDGE, 0.0)
            K.tile_roof(m, o, dsl, n, x0, x1, S, self.KW, lod, u_sign=float(sgn), ends=(lod == 0))
            uo = add(o, mul(n, -0.15))
            m.grid(lambda i, j: add(add(uo, mul(X, x0 + (x1 - x0) * i)), mul(dsl, S * j)),
                   lambda i, j: ((x0 + (x1 - x0) * i) / TW, S * j / TW), 1, 1,
                   'V2_Wood', DARK * 0.55, mul(n, -1.0), smooth=False)
            e0 = add(add(o, mul(X, x0)), mul(dsl, S))
            e1 = add(add(o, mul(X, x1)), mul(dsl, S))
            m.beam(add(e0, mul(n, -0.05)), add(e1, mul(n, -0.05)), 0.05, 0.22, 'V2_Wood', DARK * 0.9, up=n)
            for xs in (x0, x1):
                a = add(add(o, mul(X, xs)), mul(n, -0.06))
                b = add(add(add(o, mul(X, xs)), mul(dsl, S)), mul(n, -0.06))
                m.beam(add(a, mul(dsl, -0.02)), b, 0.06, 0.26, 'V2_Wood', DARK * 0.85, up=n)
            if lod == 0:
                zw, ze = HD * sgn, (HD + OV_E - 0.06) * sgn
                k = int((x1 - x0) / 0.45)
                for i in range(k + 1):
                    xx = x0 + 0.12 + i * (x1 - x0 - 0.24) / k
                    m.beam((xx, self.roof_y(zw) - 0.19, zw), (xx, self.roof_y(ze) - 0.19, ze), 0.07, 0.08,
                           'V2_Wood', DARK * 0.8, up=Y)
        m.box((x0 - 0.02, RIDGE - 0.08, -0.16), (x1 + 0.02, RIDGE + 0.08, 0.16), 'V2_Kawara', 0.62, grain=X)
        seg = 12 if lod == 0 else 8
        m.cyl((x0 - 0.02, RIDGE + 0.08, 0), (x1 + 0.02, RIDGE + 0.08, 0), 0.11, 0.11, seg, 'V2_Kawara', 0.55,
              caps=(lod == 0, lod == 0))
        if lod == 0 and ridge_ends:
            for sx in (-1, 1):
                xe = (x1 + 0.03) * sx
                m.cyl((xe - 0.03 * sx, RIDGE + 0.02, 0), (xe + 0.02 * sx, RIDGE + 0.02, 0), 0.17, 0.17, 14,
                      'V2_Kawara', 0.5)

    def main_roof_lod2(self, m):
        HW, HD, OV_G, OV_E, PITCH, SEC, RIDGE = self.HW, self.HD, self.OV_G, self.OV_E, self.PITCH, self.SEC, self.RIDGE
        S = (HD + OV_E) * SEC
        for sgn in (1, -1):
            dsl = norm((0.0, -PITCH, float(sgn)))
            n = norm((0.0, 1.0, PITCH * sgn))
            K.tile_roof(m, (0.0, RIDGE, 0.0), dsl, n, -HW - OV_G, HW + OV_G, S, self.KW, 2, u_sign=float(sgn))
            uo = add((0.0, RIDGE, 0.0), mul(n, -0.15))
            m.grid(lambda i, j: add(add(uo, mul(X, (-HW - OV_G) + 2 * (HW + OV_G) * i)), mul(dsl, S * j)),
                   lambda i, j: (i, j), 1, 1, 'V2_Wood', DARK * 0.5, mul(n, -1.0), smooth=False)
        m.box((-HW - OV_G, RIDGE - 0.08, -0.16), (HW + OV_G, RIDGE + 0.18, 0.16), 'V2_Kawara', 0.58, grain=X)

    def hisashi(self, m, lod, segs=None, arms=None):
        """通長瓦庇（segs＝[(x0, x1), …] 可分段；中間留空給招牌）＋出桁＋腕木。"""
        HW, HD, PITCH, SEC = self.HW, self.HD, self.PITCH, self.SEC
        segs = segs or [(-HW - 0.07, HW + 0.07)]
        dsl = norm((0.0, -PITCH, 1.0))
        n = norm((0.0, 1.0, PITCH))
        o = (0.0, self.HIS_Y, HD)
        S = self.HIS_D * SEC
        TW = self.TILE['V2_Wood']
        ze = HD + self.HIS_D - 0.10
        for (x0, x1) in segs:
            if lod >= 2:
                K.tile_roof(m, o, dsl, n, x0, x1, S, self.KW, 2)
            else:
                K.tile_roof(m, o, dsl, n, x0, x1, S, self.KW, lod, u_sign=1.0, ends=(lod == 0))
            uo = add(o, mul(n, -0.10))
            m.grid(lambda i, j: add(add(uo, mul(X, x0 + (x1 - x0) * i)), mul(dsl, S * j)),
                   lambda i, j: ((x0 + (x1 - x0) * i) / TW, S * j / TW), 1, 1,
                   'V2_Wood', DARK * 0.55, mul(n, -1.0), smooth=False)
            if lod >= 2:
                continue
            e0 = add(add(o, mul(X, x0)), mul(dsl, S))
            e1 = add(add(o, mul(X, x1)), mul(dsl, S))
            m.beam(add(e0, mul(n, -0.045)), add(e1, mul(n, -0.045)), 0.045, 0.16, 'V2_Wood', DARK * 0.9, up=n)
            for xs in (x0, x1):
                a = add(add(o, mul(X, xs)), mul(n, -0.03))
                b = add(add(add(o, mul(X, xs)), mul(dsl, S)), mul(n, -0.03))
                m.beam(a, b, 0.04, 0.14, 'V2_Wood', DARK * 0.85, up=n)
            m.box((x0, 2.10, ze - 0.06), (x1, 2.24, ze + 0.06), 'V2_Wood', DARK, grain=X)
        if lod >= 2:
            return
        for xa in (arms or ()):
            m.box((xa - 0.045, 2.12, HD), (xa + 0.045, 2.24, ze + 0.10), 'V2_Wood', DARK, grain=Z, skip=('-z',))

    def his_under(self, z):
        """庇野地裏在 z 處的高度（壁際 z＝HD）。"""
        return self.HIS_Y - self.PITCH * (z - self.HD) - 0.10 * self.SEC

    def cross_gable(self, m, lod, cx, zg, yp, p2, ov, face_mat, face_col=1.0, face_region=None, trim=None,
                    gegyo=None):
        """平入主屋前坡上的千鳥破風（棟與道路垂直）。
        zg＝破風面位置（壁內）；yp＝破風棟高；p2＝破風坡度；ov＝破風面前出。
        兩坡三角屋面：(cx, yp, z_int(0)) → (cx, yp, zf2) → (cx±B, yp−p2·B, zf2)，B 使該點正好落在主屋面上。
        回傳 {'B': 屋面半寬, 'bg': 破風面底半寬, 'yb': 破風面底高}。"""
        RIDGE, PITCH = self.RIDGE, self.PITCH
        zf2 = zg + ov
        z_int0 = (RIDGE - yp) / PITCH
        B = (zf2 * PITCH - RIDGE + yp) / p2
        yb = self.roof_y(zg)
        bg = (yp - yb) / p2
        lift = 0.06
        TK = self.TILE['V2_Kawara']
        for s in (1, -1):
            n = norm((s * p2, 1.0, 0.0))
            P = [(cx, yp, z_int0), (cx, yp, zf2), (cx + s * B, yp - p2 * B, zf2)]
            P = [add(p, mul(n, lift)) for p in P]
            if s < 0:
                P = P[::-1]
            # 瓦：v 沿下坡（x 向），u 沿棟（z 向）
            uvs = [(p[2] / self.KW['tile_u_m'], abs(p[0] - cx) * math.sqrt(1 + p2 * p2) / TK) for p in P]
            m.poly(P, 'V2_Kawara', 0.95, uvs=uvs)
            # 前出部分的野地裏（z∈[zg, zf2]）
            a = (cx, yp - 0.12, zg)
            b = (cx, yp - 0.12, zf2)
            c = (cx + s * B, yp - p2 * B - 0.12, zf2)
            d = (cx + s * bg, yp - p2 * bg - 0.12, zg)
            q = [d, c, b, a] if s > 0 else [a, b, c, d]
            m.poly(q, 'V2_Wood', DARK * 0.5, grain=Z)
            # 破風板（沿前緣）
            e0 = (cx, yp + 0.02, zf2 + 0.01)
            e1 = (cx + s * B, yp - p2 * B + 0.02, zf2 + 0.01)
            if trim:
                self.abeam(m, e0, e1, 0.07, 0.24, trim, 1.0, up=Y)
            else:
                m.beam(e0, e1, 0.07, 0.24, 'V2_Wood', DARK * 0.85, up=Y)
        # 棟
        m.box((cx - 0.12, yp - 0.04 + lift, z_int0), (cx + 0.12, yp + 0.12 + lift, zf2 + 0.03), 'V2_Kawara', 0.6,
              grain=Z)
        if lod == 0:
            m.cyl((cx, yp + 0.12 + lift, z_int0), (cx, yp + 0.12 + lift, zf2 + 0.04), 0.09, 0.09, 10, 'V2_Kawara',
                  0.55, caps=(False, True))
        # 破風面（三角）
        tri = [(cx - bg, yb, zg), (cx + bg, yb, zg), (cx, yp - 0.10, zg)]
        if face_region:
            u0, v0, u1, v1 = face_region
            m.poly(tri, self.AMAT, face_col, uvs=[(u0, v1), (u1, v1), ((u0 + u1) / 2, v0)])
        else:
            m.poly(tri, face_mat, face_col, grain=X)
        if gegyo and lod == 0:
            # 懸魚：破風頂下方的菱形金具（從正面看 左→下→右→上 逆時針）
            gy, zq = yp - 0.30, zf2 + 0.05
            u, v = self.SWATCH[gegyo]
            m.poly([(cx - 0.16, gy - 0.02, zq), (cx, gy - 0.30, zq), (cx + 0.16, gy - 0.02, zq), (cx, gy + 0.18, zq)],
                   self.AMAT, 1.0, uvs=[(u - 0.003, v), (u, v + 0.003), (u + 0.003, v), (u, v - 0.003)])
        return {'B': B, 'bg': bg, 'yb': yb, 'z_int0': z_int0, 'zf2': zf2}

    # ── 側／背
    def sides_back(self, m, lod, back_door=(1.55, 2.45), side_windows=True, back_window=-1.0, win_y=(2.98, 3.42),
                   win_region='paper'):
        HW, HD, OV_E, OV_G, PLINTH = self.HW, self.HD, self.OV_E, self.OV_G, self.PLINTH
        PLATE, RIDGE = self.PLATE, self.RIDGE
        for sx in (1, -1):
            xw = (HW - 0.02) * sx
            neg = sx < 0
            self.fx(m, -HD + 0.15, HD - 0.15, PLINTH, 2.62, xw, 'V2_Wood', BOARD * 0.8, grain=Z, neg=neg)
            self.fx(m, -HD + 0.15, HD - 0.15, 2.72, PLATE[0], xw, 'V2_Plaster', 0.95, neg=neg)
            tri = [(xw, 3.70, HD - 0.15), (xw, 3.70, -HD + 0.15), (xw, RIDGE - 0.16, 0.0)]
            if sx < 0:
                tri = tri[::-1]
            m.poly(tri, 'V2_Plaster', 0.93)
            xo = HW * sx
            xi = (HW - 0.15) * sx
            lo, hi = min(xo, xi), max(xo, xi)
            m.box((lo, 2.62, -HD), (hi + 0.01 if sx > 0 else hi, 2.72, HD), 'V2_Wood', DARK, grain=Z)
            m.box((lo, PLATE[0], -HD - OV_E + 0.1), (hi, PLATE[1], HD + 0.0), 'V2_Wood', DARK, grain=Z)
            m.box((lo, PLINTH, -0.075), (hi, PLATE[0], 0.075), 'V2_Wood', DARK, grain=Y, skip=('-y',))
            m.box(((HW - 0.15) * sx if sx > 0 else -HW, PLINTH, -HD), (HW if sx > 0 else -HW + 0.15, PLATE[1], -HD + 0.15),
                  'V2_Wood', DARK, grain=Y, skip=('-y',))
        zb = -HD + 0.02
        self.fz(m, -HW + 0.15, HW - 0.15, PLINTH, 2.62, zb, 'V2_Wood', BOARD * 0.8, grain=X, back=True)
        self.fz(m, -HW + 0.15, HW - 0.15, 2.72, PLATE[0], zb, 'V2_Plaster', 0.95, back=True)
        m.box((-HW, 2.62, -HD), (HW, 2.72, -HD + 0.15), 'V2_Wood', DARK, grain=X)
        m.box((-HW - OV_G, PLATE[0], -HD - 0.01), (HW + OV_G, PLATE[1], -HD + 0.16), 'V2_Wood', DARK, grain=X)
        m.box((-0.075, PLINTH, -HD - 0.01), (0.075, PLATE[0], -HD + 0.15), 'V2_Wood', DARK, grain=Y, skip=('-y',))
        if back_door:
            a, b = back_door
            zo = -HD - 0.01
            self.fz(m, a, b, PLINTH, 2.12, zo - 0.005, 'V2_Wood', BOARD * 0.62, grain=Y, back=True)
            for (p0, p1) in ((a - 0.06, a), (b, b + 0.06)):
                m.box((p0, PLINTH, zo - 0.05), (p1, 2.18, zo), 'V2_Wood', DARK, grain=Y, skip=('+z', '-y'))
            m.box((a - 0.06, 2.12, zo - 0.05), (b + 0.06, 2.18, zo), 'V2_Wood', DARK, grain=X, skip=('+z',))
            for y in (0.75, 1.25, 1.75):
                m.box((a + 0.03, y, zo - 0.03), (b - 0.03, y + 0.03, zo - 0.005), 'V2_Wood', DARK, grain=X, skip=('+z',))
        if back_window is not None:
            self.small_window(m, lod, 'z', -HD - 0.01, back_window, 0.8, -1.0, win_y, win_region)
        if side_windows:
            for sx in (1, -1):
                self.small_window(m, lod, 'x', (HW + 0.01) * sx, 0.0, 1.0, float(sx), win_y, win_region)

    def small_window(self, m, lod, axis, plane, c, w, sgn, win_y=(2.98, 3.42), region='paper'):
        y0, y1 = win_y

        def P(t, y, d):
            return (plane + d * sgn, y, t) if axis == 'x' else (t, y, plane + d * sgn)
        a, b = c - w / 2, c + w / 2
        if (axis == 'z') == (sgn > 0):
            q = [P(a, y0, 0.005), P(b, y0, 0.005), P(b, y1, 0.005), P(a, y1, 0.005)]
        else:
            q = [P(b, y0, 0.005), P(a, y0, 0.005), P(a, y1, 0.005), P(b, y1, 0.005)]
        m.rect_uv(q[0], q[1], q[2], q[3], self.AMAT, self.RG[region] if isinstance(region, str) else region, 0.5)
        ax_t = Z if axis == 'x' else X

        def bx(t0, t1, ya, yb, d0, d1):
            lo = [0, 0, 0]
            hi = [0, 0, 0]
            ti = 2 if axis == 'x' else 0
            ni = 0 if axis == 'x' else 2
            lo[ti], hi[ti] = t0, t1
            lo[1], hi[1] = ya, yb
            n0, n1 = plane + d0 * sgn, plane + d1 * sgn
            lo[ni], hi[ni] = min(n0, n1), max(n0, n1)
            m.box(tuple(lo), tuple(hi), 'V2_Wood', DARK, grain=ax_t if t1 - t0 > yb - ya else Y)
        bx(a - 0.06, b + 0.06, y1, y1 + 0.06, 0.0, 0.06)
        bx(a - 0.06, b + 0.06, y0 - 0.06, y0, 0.0, 0.07)
        bx(a - 0.06, a, y0, y1, 0.0, 0.06)
        bx(b, b + 0.06, y0, y1, 0.0, 0.06)
        if lod == 0:
            n = int(w / 0.09)
            for k in range(1, n):
                t = a + k * w / n
                bx(t - 0.015, t + 0.015, y0, y1, 0.01, 0.045)

    def lod2_shell(self, m, front_1f_region=None):
        """遠景：牆體一盒、1F 深色店面、2F 灰泥、兩山三角。"""
        HW, HD, PLINTH, PLATE, RIDGE = self.HW, self.HD, self.PLINTH, self.PLATE, self.RIDGE
        m.box((-HW, self.BOT, -HD), (HW, PLINTH, HD), 'V2_Stone', 0.85, skip=('-y',))
        m.box((-HW + 0.02, PLINTH, -HD + 0.02), (HW - 0.02, PLATE[1], HD - 0.02), 'V2_Plaster', 0.9,
              skip=('-y', '+y', '+z'))
        if front_1f_region:
            self.fz(m, -HW + 0.02, HW - 0.02, PLINTH, self.LINTEL[1], HD - 0.02, self.AMAT, 0.8, front_1f_region)
        else:
            self.fz(m, -HW + 0.02, HW - 0.02, PLINTH, self.LINTEL[1], HD - 0.02, 'V2_Wood', DARK * 0.8, grain=X)
        self.fz(m, -HW + 0.02, HW - 0.02, self.LINTEL[1], PLATE[1], HD - 0.02, 'V2_Plaster', 0.95)
        for sx in (1, -1):
            xw = (HW - 0.02) * sx
            tri = [(xw, PLATE[1] - 0.02, HD - 0.02), (xw, PLATE[1] - 0.02, -HD + 0.02), (xw, RIDGE - 0.16, 0.0)]
            m.poly(tri[::-1] if sx < 0 else tri, 'V2_Plaster', 0.9)

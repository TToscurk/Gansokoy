"""P6 aux 附屬棟：土藏（aux_kura，2 棟）＋納屋（aux_koya，7 棟）— 人間之里 V2 新資產（不重用任何舊房屋資產）。

  blender -b --factory-startup --python godot/assets/blender/village_v2/build_aux.py

尺寸 authority：P4 greybox.json kind＝aux_kura／aux_koya（兩型各自同尺寸，逐棟由 asset.json gate_spec.instances 驗）。
  土藏 S_A_MKT_002／006：面寬 3.64 × 縱深 5.46、簷 4.2、脊 5.02、妻入（正面＝山牆）、pitch 0.45、出簷 0.40、妻側 0.30、台基 0.32。
  納屋 S_A_RSW_002…／S_A_RNE_…：面寬 2.73 × 縱深 1.82、簷 2.3、脊 2.71、平入、pitch 0.45、出簷 0.45、妻側 0.30、台基 0.32。
外觀 authority：
  土藏＝docs/reference/民宅/倉庫.PNG：粗石台＋腰石、なまこ壁（深灰瓦片斜格＋白漆喰目地、白框）、水切り、上段白漆喰（簷下污漬）、
        灰瓦切妻＋鬼瓦、入口厚框＋觀音開き扉（開啟貼牆）＋小瓦庇、上層小窗（格子＋左右開啟的深色窗扉＋小庇）、山牆漆喰紋章。
        參考圖入口在平側；P4 灰盒是妻入、正面（+z）＝山牆，入口改在山牆正面（妻入り土藏）。
  納屋＝參考圖沒有小屋（倉庫.PNG 只有土藏）；依村內既有語彙設計：石台＋土台、焦茶縦板＋押縁、角柱、灰瓦平入切妻、
        半開的板戸（引戸）、側面連子窓、左側薪棚。
材質：共享材質庫 V2_Wood／V2_Plaster／V2_Kawara／V2_Stone（頂點色給色調）；土藏的漆喰面改用資產目錄內的專用
      V2_KuraShikkui（自然暖白 #E6E0D2，tools/build_village_v2_textures.py --kura-shikkui；共享 V2_Plaster 不動）。
座標：Godot；原點＝footprint 中心、y 0＝footprint 內最高地面（base_h）、+z＝正面（P4 front_dir）。
"""
import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import v2_kit as K  # noqa: E402
from v2_kit import X, Y, Z, add, mul, norm  # noqa: E402
from v2_zushi import Zushi, DARK, BOARD  # noqa: E402

G = K.repo_paths(__file__)
ML = K.load_json(G + '/assets/village_v2/_matlib/matlib.json')['materials']
MATS = ['V2_Wood', 'V2_Plaster', 'V2_Kawara', 'V2_Stone']
NO_ATLAS = {'regions': {}, 'swatches': {}}
BOT = -0.40
PLINTH = 0.32
WHITE = 1.0          # 白漆喰：土藏的 V2_Plaster 面在 build_kura 結尾換成 V2_KuraShikkui（暖白貼圖）；納屋不用
KURA_SHIKKUI = 'V2_KuraShikkui'
KURA_SHIKKUI_TRES = 'res://assets/village_v2/aux_kura/V2_KuraShikkui.tres'
NAMAKO_TILE = 0.20   # なまこ瓦片的深灰（V2_Stone × 0.20）


def xform(p, rot):
    """rot=True：roof 在「棟沿 x」的座標系建好後轉到「棟沿 z」（繞 y −90°：x'→z、z'→−x，行列式 +1，繞序不變）。"""
    return (-p[2], p[1], p[0]) if rot else p


def merge(m, r, rot):
    b = len(m.v)
    m.v.extend(xform(p, rot) for p in r.v)
    m.f.extend((tuple(i + b for i in f[0]), f[1], f[2], f[3], f[4]) for f in r.f)


def wall_quad(m, Q, axis, plane, sgn, u0, u1, y0, y1, mat, col=1.0, grain=Y, off=0.0):
    """牆面矩形：axis 'z'＝正背面（u＝x）、'x'＝側面（u＝z）；sgn＝外法線方向；off＝沿法線外推。"""
    p = plane + off * sgn
    if axis == 'z':
        Q.fz(m, u0, u1, y0, y1, p, mat, col, grain=grain, back=sgn < 0)
    else:
        Q.fx(m, u0, u1, y0, y1, p, mat, col, grain=grain, neg=sgn < 0)


def wbox(m, axis, plane, sgn, u0, u1, y0, y1, d_in, d_out, mat, col=1.0, grain=None, skip=()):
    """貼牆方塊：沿牆 u0..u1、高 y0..y1、法線方向從 plane−d_in 到 plane+d_out。"""
    n0, n1 = plane - d_in * sgn, plane + d_out * sgn
    lo_n, hi_n = min(n0, n1), max(n0, n1)
    if axis == 'z':
        m.box((u0, y0, lo_n), (u1, y1, hi_n), mat, col, grain=grain, skip=skip)
    else:
        m.box((lo_n, y0, u0), (hi_n, y1, u1), mat, col, grain=grain, skip=skip)


def wpt(axis, plane, sgn, u, y, d):
    return (u, y, plane + d * sgn) if axis == 'z' else (plane + d * sgn, y, u)


def namako(m, Q, axis, plane, sgn, u0, u1, y0, y1, lod):
    """なまこ壁：深灰瓦片面＋白框＋（LOD0）45° 斜格漆喰目地。"""
    wall_quad(m, Q, axis, plane, sgn, u0, u1, y0, y1, 'V2_Stone', NAMAKO_TILE, off=0.004)
    fw = 0.05
    for (a, b) in ((y0, y0 + fw), (y1 - fw, y1)):
        wbox(m, axis, plane, sgn, u0, u1, a, b, 0.01, 0.025, 'V2_Plaster', WHITE, grain=X if axis == 'z' else Z)
    for u in (u0, u1 - fw):
        wbox(m, axis, plane, sgn, u, u + fw, y0 + fw, y1 - fw, 0.01, 0.025, 'V2_Plaster', WHITE, grain=Y)
    if lod > 0:
        return
    nrm = (0.0, 0.0, float(sgn)) if axis == 'z' else (float(sgn), 0.0, 0.0)
    ua, ub = u0 + fw, u1 - fw
    ya, H = y0 + fw, (y1 - fw) - (y0 + fw)
    step = NAMAKO_TILE * math.sqrt(2.0) * 0.8     # 目地間距 ≈ 0.34 m（瓦片對角 ~0.24 m 見方）
    c = ua - H
    while c <= ub + 1e-6:
        for s in (1, -1):
            # s＝1：u − dy＝c；s＝−1：u + dy＝c + H（兩組斜線共用 c 的起點）
            if s == 1:
                d0, d1 = max(0.0, ua - c), min(H, ub - c)
                pa, pb = (c + d0, d0), (c + d1, d1)
            else:
                cc = c + H
                d0, d1 = max(0.0, cc - ub), min(H, cc - ua)
                pa, pb = (cc - d0, d0), (cc - d1, d1)
            if d1 - d0 < 0.06:
                continue
            a = wpt(axis, plane, sgn, pa[0], ya + pa[1], 0.012)
            b = wpt(axis, plane, sgn, pb[0], ya + pb[1], 0.012)
            m.beam(a, b, 0.065, 0.05, 'V2_Plaster', WHITE, up=nrm)   # 目地：寬 6.5 cm、凸 5 cm（蒲鉾目地）
        c += step


def hood(m, x0, x1, y, z, depth, lod, axis='z', sgn=1.0):
    """小瓦庇（窗上／入口上）：瓦面斜板＋野地裏＋前緣。axis 'z'＝正面（沿 x）、'x'＝側面（沿 z）。"""
    rise = depth * 0.40

    def P(u, yy, d):
        return (u, yy, z + d * sgn) if axis == 'z' else (z + d * sgn, yy, u)
    top = [P(x0, y + rise, 0.0), P(x1, y + rise, 0.0), P(x1, y, depth), P(x0, y, depth)]
    under = [P(x0, y + rise - 0.06, 0.0), P(x0, y - 0.06, depth), P(x1, y - 0.06, depth), P(x1, y + rise - 0.06, 0.0)]
    # 從外（上）看逆時針：未翻時 'z'+ 的 top 法線朝下、'x'+ 朝上（負向鏡像再反一次）
    flip = (axis == 'z') == (sgn > 0)
    tq = top[::-1] if flip else top
    uq = under[::-1] if flip else under
    dsl = norm(sub3(top[2], top[1]))
    m.poly(tq, 'V2_Kawara', 0.75, grain=dsl)
    m.poly(uq, 'V2_Wood', DARK * 0.6, grain=dsl)
    a, b = P(x0, y - 0.03, depth), P(x1, y - 0.03, depth)
    m.beam(a, b, 0.06, 0.08, 'V2_Kawara', 0.6, up=Y)
    for u in (x0 + 0.08, x1 - 0.08):
        m.beam(P(u, y + rise - 0.12, 0.0), P(u, y - 0.10, depth - 0.05), 0.05, 0.05, 'V2_Wood', DARK, up=Y)


def sub3(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def window(m, Q, axis, plane, sgn, cu, w, y0, y1, lod, frame_mat='V2_Plaster', frame_col=WHITE, shutters=True):
    """塗籠小窗：漆喰外框（凸 0.08）、深色窗洞、格子、左右開啟的窗扉、小瓦庇。"""
    a, b = cu - w / 2, cu + w / 2
    fw = 0.09
    for (ua, ub, ya, yb) in ((a - fw, b + fw, y1, y1 + fw), (a - fw, b + fw, y0 - fw, y0), (a - fw, a, y0, y1),
                             (b, b + fw, y0, y1)):
        wbox(m, axis, plane, sgn, ua, ub, ya, yb, 0.01, 0.08, frame_mat, frame_col,
             grain=(X if axis == 'z' else Z) if ub - ua > yb - ya else Y)
    wall_quad(m, Q, axis, plane, sgn, a, b, y0, y1, 'V2_Wood', 0.10, off=0.01)
    if lod == 0:
        n = max(2, int(w / 0.12))
        for k in range(1, n):
            u = a + k * w / n
            wbox(m, axis, plane, sgn, u - 0.018, u + 0.018, y0, y1, -0.01, 0.05, 'V2_Wood', DARK, grain=Y)
    if shutters:
        for (ua, ub) in ((a - fw - w / 2 - 0.02, a - fw - 0.02), (b + fw + 0.02, b + fw + w / 2 + 0.02)):
            wbox(m, axis, plane, sgn, ua, ub, y0 - 0.04, y1 + 0.04, -0.01, 0.06, 'V2_Wood', 0.26, grain=Y)
    ext = (w / 2 + 0.06) if shutters else 0.10   # 庇蓋住開啟的窗扉
    hood(m, a - fw - ext, b + fw + ext, y1 + fw + 0.06, plane, 0.28, lod, axis=axis, sgn=sgn)


# ═══════════════════════════════ 土藏 ═══════════════════════════════
KW_, KD_ = 3.64, 5.46
K_EAVE, K_PITCH, K_OVE, K_OVG = 4.20, 0.45, 0.40, 0.30
KHW, KHD = KW_ / 2, KD_ / 2
K_RIDGE = K_EAVE + KHW * K_PITCH       # 妻入：棟沿 z，坡向 ±x → 脊高 = 簷 + 半面寬 × pitch
K_WAIST = (PLINTH, 0.55)              # 腰石
K_NAMA = (0.55, 1.55)                 # なまこ帶
K_MIZU = (1.55, 1.63)                 # 水切り
K_DOOR = (-0.62, 0.62, PLINTH, 2.30)  # 入口淨空（x0, x1, 門檻, 鴨居下）
K_JAMB = 0.18
K_REVEAL = 0.20                       # 入口深（內扉退入牆面）
KZF = KHD


def kura_roof(lod):
    """在「棟沿 x」的座標系用 Zushi 的主屋根（面寬＝縱深 5.46、縱深＝面寬 3.64）建好，再轉 −90°。"""
    Qr = Zushi(KD_, KW_, eave=K_EAVE, pitch=K_PITCH, plinth=PLINTH, bot=BOT, ov_e=K_OVE, ov_g=K_OVG,
               his_y=2.6, his_d=0.5, mats=MATS, amat=None, atlas=NO_ATLAS, matlib=ML)
    r = K.Mesh('roof', MATS, Qr.TILE)
    if lod >= 2:
        Qr.main_roof_lod2(r)
    else:
        Qr.main_roof(r, lod)
    return r


def build_kura(lod):
    Q = Zushi(KW_, KD_, eave=K_EAVE, pitch=K_PITCH, plinth=PLINTH, bot=BOT, ov_e=K_OVE, ov_g=K_OVG,
              his_y=2.6, his_d=0.5, mats=MATS, amat=None, atlas=NO_ATLAS, matlib=ML)
    m = K.Mesh('Kura_LOD%d' % lod, MATS, Q.TILE)
    m.box((-KHW, BOT, -KHD), (KHW, PLINTH, KHD), 'V2_Stone', 0.80, skip=('-y',))
    x0d, x1d, sill, lint = K_DOOR
    jx = x1d + K_JAMB
    # 牆段：(axis, plane, sgn, [(u0, u1)…]) — 正面入口兩側分段
    walls = [('z', KZF, 1, [(-KHW, -jx), (jx, KHW)]), ('z', -KHD, -1, [(-KHW, KHW)]),
             ('x', KHW, 1, [(-KHD, KHD)]), ('x', -KHW, -1, [(-KHD, KHD)])]
    if lod >= 2:
        m.box((-KHW + 0.02, PLINTH, -KHD + 0.02), (KHW - 0.02, K_EAVE, KHD - 0.02), 'V2_Plaster', WHITE,
              skip=('-y', '+y'))
        for (ax, pl, sg, segs) in walls:
            for (u0, u1) in segs:
                wall_quad(m, Q, ax, pl, sg, u0, u1, K_NAMA[0], K_NAMA[1], 'V2_Stone', 0.40, off=0.01)
        wall_quad(m, Q, 'z', KZF, 1, x0d, x1d, sill, lint, 'V2_Wood', 0.22, off=0.01)
    else:
        for (ax, pl, sg, segs) in walls:
            for (u0, u1) in segs:
                wbox(m, ax, pl, sg, u0, u1, K_WAIST[0], K_WAIST[1], 0.02, 0.03, 'V2_Stone', 0.78)
                namako(m, Q, ax, pl, sg, u0, u1, K_NAMA[0], K_NAMA[1], lod)
                wbox(m, ax, pl, sg, u0 - 0.02, u1 + 0.02, K_MIZU[0], K_MIZU[1], 0.02, 0.07, 'V2_Plaster', WHITE,
                     grain=X if ax == 'z' else Z)
        # 上段白漆喰（下 1.0 → 簷下 0.84：雨垂れ污漬）
        wc = [(WHITE,) * 3, (WHITE,) * 3, (0.88, 0.86, 0.82), (0.88, 0.86, 0.82)]   # 簷下雨垂れ污漬
        for (ax, pl, sg, u0, u1, y0) in (('x', KHW, 1, -KHD, KHD, K_MIZU[1]), ('x', -KHW, -1, -KHD, KHD, K_MIZU[1]),
                                         ('z', -KHD, -1, -KHW, KHW, K_MIZU[1]),
                                         ('z', KZF, 1, -KHW, -jx, K_MIZU[1]), ('z', KZF, 1, jx, KHW, K_MIZU[1]),
                                         ('z', KZF, 1, -jx, jx, lint + 0.18)):
            p = pl
            if ax == 'z':
                q = [(u0, y0, p), (u1, y0, p), (u1, K_EAVE, p), (u0, K_EAVE, p)] if sg > 0 else \
                    [(u1, y0, p), (u0, y0, p), (u0, K_EAVE, p), (u1, K_EAVE, p)]
            else:
                q = [(p, y0, u1), (p, y0, u0), (p, K_EAVE, u0), (p, K_EAVE, u1)] if sg > 0 else \
                    [(p, y0, u0), (p, y0, u1), (p, K_EAVE, u1), (p, K_EAVE, u0)]
            m.poly(q, 'V2_Plaster', wc, grain=Y)
        # 簷下漆喰鉢巻（平側）
        for sx in (1, -1):
            wbox(m, 'x', KHW * sx, sx, -KHD - 0.02, KHD + 0.02, K_EAVE - 0.26, K_EAVE, 0.02, 0.12, 'V2_Plaster',
                 0.92, grain=Z)
        # 入口：厚漆喰框＋鴨居、退入的內扉（縦板＋橫桟）、開啟貼牆的觀音扉、瓦庇、石段
        for sx in (1, -1):
            a, b = sorted((x1d * sx, jx * sx))
            m.box((a, sill, KZF - K_REVEAL), (b, lint + 0.18, KZF + 0.10), 'V2_Plaster', WHITE, grain=Y,
                  skip=('-y',))
        m.box((-jx, lint, KZF - K_REVEAL), (jx, lint + 0.18, KZF + 0.10), 'V2_Plaster', WHITE, grain=X)
        Q.fz(m, x0d, x1d, sill, lint, KZF - K_REVEAL, 'V2_Wood', 0.30, grain=Y)
        for y in (0.70, 1.30, 1.90):
            m.box((x0d + 0.04, y, KZF - K_REVEAL), (x1d - 0.04, y + 0.06, KZF - K_REVEAL + 0.03), 'V2_Wood', 0.22,
                  grain=X, skip=('-z',))
        m.box((-0.05, sill, KZF - K_REVEAL), (0.05, lint, KZF - K_REVEAL + 0.035), 'V2_Wood', 0.20, grain=Y,
              skip=('-z',))
        for sx in (1, -1):
            a, b = sorted(((jx + 0.02) * sx, (jx + 0.02 + 0.60) * sx))
            m.box((a, sill + 0.04, KZF + 0.03), (b, lint + 0.14, KZF + 0.14), 'V2_Wood', 0.26, grain=Y,
                  skip=('-z',))
            if lod == 0:
                for y in (0.75, 1.35, 1.95):
                    m.box((a + 0.05, y, KZF + 0.14), (b - 0.05, y + 0.05, KZF + 0.16), 'V2_Wood', 0.18, grain=X,
                          skip=('-z',))
        hood(m, -jx - 0.20, jx + 0.20, lint + 0.30, KZF, 0.50, lod)
        # 上層窗：正面山牆（入口上方）＋右側平側
        window(m, Q, 'z', KZF, 1, 0.0, 0.62, 3.00, 3.52, lod)
        window(m, Q, 'x', KHW, 1, -1.10, 0.62, 3.00, 3.52, lod)
    # 山牆三角（前後）＋山牆漆喰紋章
    ta = K_RIDGE - 0.16
    for sz in (1, -1):
        zz = KHD * sz
        tri = [(-KHW, K_EAVE, zz), (KHW, K_EAVE, zz), (0.0, ta, zz)]
        m.poly(tri if sz > 0 else tri[::-1], 'V2_Plaster', 0.95)
    if lod < 2:
        m.obox((0.0, K_EAVE + 0.42, KZF + 0.04), (0.17, 0.17, 0.04), 'V2_Plaster', WHITE, ax=norm((1, 1, 0)),
               ay=norm((-1, 1, 0)), az=Z)
    # 石段
    m.box((-0.75, -0.14, KZF), (0.75, 0.16, KZF + 0.45), 'V2_Stone', 0.72, skip=('-y',))
    merge(m, kura_roof(lod), True)
    # 漆喰面（牆、目地、框、鉢巻、山牆、紋章、屋根的漆喰部分）整槽改用土藏專用白漆喰；UV 已用同 tile_m 2.0 算好
    m.mats[m.mats.index('V2_Plaster')] = KURA_SHIKKUI
    return m


# ═══════════════════════════════ 納屋 ═══════════════════════════════
YW_, YD_ = 2.73, 1.82
Y_EAVE, Y_PITCH, Y_OVE, Y_OVG = 2.30, 0.45, 0.45, 0.30
YHW, YHD = YW_ / 2, YD_ / 2
Y_DOOR = (-0.45, 0.45, PLINTH, 2.02)
Y_SILL = (PLINTH, 0.44)                # 土台
Y_POST = 0.12
PILE = (-YHW - 0.68, -YHW - 0.08, -0.75, 0.75)   # 薪棚 x0, x1, z0, z1


def boards(m, Q, axis, plane, sgn, u0, u1, y0, y1, lod, col=0.56):
    wall_quad(m, Q, axis, plane, sgn, u0, u1, y0, y1, 'V2_Wood', col, grain=Y)
    if lod == 0:
        n = max(1, int(round((u1 - u0) / 0.45)))
        for k in range(1, n):
            u = u0 + k * (u1 - u0) / n
            wbox(m, axis, plane, sgn, u - 0.025, u + 0.025, y0, y1, -0.005, 0.03, 'V2_Wood', DARK * 0.55, grain=Y)


PILE_TOP = 0.90


def woodpile(m, lod):
    """薪棚：兩根枕木（埋入地面）＋ 6 層原木（木口朝前後，淺色）。"""
    x0, x1, z0, z1 = PILE
    for xs in (x0 + 0.10, x1 - 0.10):                      # 枕木（埋入地面）
        m.box((xs - 0.05, -0.25, z0 + 0.02), (xs + 0.05, 0.08, z1 - 0.02), 'V2_Wood', DARK * 0.9, grain=Z)
    if lod >= 1:
        m.box((x0 + 0.02 * lod, 0.08, z0), (x1 - 0.02 * lod, PILE_TOP - 0.02, z1), 'V2_Wood', 0.95, grain=Z,
              skip=('-y',))
        return
    r = 0.075
    for j in range(6):
        cnt = 4 if j % 2 == 0 else 3
        y = 0.08 + r + j * r * 1.72
        w = (x1 - x0) - 0.04
        for i in range(cnt):
            x = x0 + 0.02 + r + (i + 0.5 * (4 - cnt)) * (w - 2 * r) / 3.0
            jit = ((i * 7 + j * 3) % 5) * 0.012
            m.cyl((x, y, z0 + jit), (x, y, z1 - 0.03 + jit), r, r, 6, 'V2_Wood', 1.0 - 0.07 * ((i + j) % 3),
                  phase=0.3 * i)


def build_koya(lod):
    Q = Zushi(YW_, YD_, eave=Y_EAVE, pitch=Y_PITCH, plinth=PLINTH, bot=BOT, ov_e=Y_OVE, ov_g=Y_OVG,
              his_y=2.0, his_d=0.4, mats=MATS, amat=None, atlas=NO_ATLAS, matlib=ML)
    m = K.Mesh('Koya_LOD%d' % lod, MATS, Q.TILE)
    m.box((-YHW, BOT, -YHD), (YHW, PLINTH, YHD), 'V2_Stone', 0.74, skip=('-y',))
    x0d, x1d, sill, head = Y_DOOR
    top = Y_EAVE - 0.16
    if lod >= 2:
        m.box((-YHW + 0.02, PLINTH, -YHD + 0.02), (YHW - 0.02, Y_EAVE, YHD - 0.02), 'V2_Wood', BOARD * 0.58,
              grain=Y, skip=('-y', '+y'))
        Q.fz(m, x0d, 0.05, sill, head, YHD + 0.01, 'V2_Wood', 0.12)
        Q.main_roof_lod2(m)
    else:
        P = Y_POST
        # 土台＋角柱＋門柱
        for sz in (1, -1):
            m.box((-YHW, Y_SILL[0], sz * YHD - (0.12 if sz > 0 else 0)), (YHW, Y_SILL[1], sz * YHD + (0 if sz > 0 else 0.12)),
                  'V2_Wood', DARK, grain=X, skip=('-y',))
        for sx in (1, -1):
            a, b = sorted((sx * YHW, sx * (YHW - 0.12)))
            m.box((a, Y_SILL[0], -YHD + 0.12), (b, Y_SILL[1], YHD - 0.12), 'V2_Wood', DARK, grain=Z, skip=('-y',))
        for (cx, cz) in ((YHW - P / 2, YHD - P / 2), (-YHW + P / 2, YHD - P / 2), (YHW - P / 2, -YHD + P / 2),
                         (-YHW + P / 2, -YHD + P / 2)):
            m.box((cx - P / 2 - 0.01, Y_SILL[1], cz - P / 2 - 0.01), (cx + P / 2 + 0.01, Y_EAVE, cz + P / 2 + 0.01),
                  'V2_Wood', DARK, grain=Y, skip=('-y',))
        for xs in (x0d - 0.08, x1d):
            m.box((xs, Y_SILL[1], YHD - 0.10), (xs + 0.08, top, YHD + 0.01), 'V2_Wood', DARK, grain=Y, skip=('-y',))
        # 桁（前後）
        for sz in (1, -1):
            a, b = sorted((sz * (YHD - 0.12), sz * (YHD + 0.01)))
            m.box((-YHW - 0.02, top, a), (YHW + 0.02, Y_EAVE, b), 'V2_Wood', DARK * 0.9, grain=X)
        # 板壁：正面（入口兩側＋入口上）、背面、兩側
        yb = Y_SILL[1]
        boards(m, Q, 'z', YHD, 1, -YHW + P, x0d - 0.08, yb, top, lod)
        boards(m, Q, 'z', YHD, 1, x1d + 0.08, YHW - P, yb, top, lod)
        boards(m, Q, 'z', YHD, 1, x0d - 0.08, x1d + 0.08, head + 0.06, top, 1)
        boards(m, Q, 'z', -YHD, -1, -YHW + P, YHW - P, yb, top, lod)
        boards(m, Q, 'x', -YHW, -1, -YHD + P, YHD - P, yb, top, lod)
        boards(m, Q, 'x', YHW, 1, -YHD + P, -0.46, yb, top, lod)
        boards(m, Q, 'x', YHW, 1, 0.46, YHD - P, yb, top, lod)
        boards(m, Q, 'x', YHW, 1, -0.46, 0.46, yb, 1.18, lod)
        boards(m, Q, 'x', YHW, 1, -0.46, 0.46, 1.68, top, lod)
        # 側面連子窓（+x，z −0.40..0.40、y 1.18..1.68）
        Q.fx(m, -0.40, 0.40, 1.18, 1.68, YHW - 0.10, 'V2_Wood', 0.08)
        for (z0, z1, y0, y1) in ((-0.46, 0.46, 1.12, 1.18), (-0.46, 0.46, 1.68, 1.74), (-0.46, -0.40, 1.18, 1.68),
                                 (0.40, 0.46, 1.18, 1.68)):
            m.box((YHW - 0.10, y0, z0), (YHW + 0.03, y1, z1), 'V2_Wood', DARK, grain=Z if z1 - z0 > y1 - y0 else Y)
        if lod == 0:
            for k in range(1, 8):
                z = -0.40 + k * 0.10
                m.box((YHW - 0.06, 1.18, z - 0.018), (YHW + 0.01, 1.68, z + 0.018), 'V2_Wood', BOARD * 1.1, grain=Y,
                      skip=('+y', '-y'))
        # 入口：鴨居／敷居、內部（暗）、半開的板戸（引き戸，滑到右側牆前）
        m.box((x0d - 0.08, head, YHD - 0.10), (x1d + 0.08, head + 0.06, YHD + 0.03), 'V2_Wood', DARK, grain=X)
        m.box((x0d, sill, YHD - 0.10), (x1d + 0.95, sill + 0.05, YHD + 0.04), 'V2_Wood', DARK * 0.8, grain=X,
              skip=('-y',))
        Q.fz(m, x0d, x1d, sill, head, YHD - 0.62, 'V2_Wood', 0.07, grain=Y)
        Q.fx(m, YHD - 0.62, YHD - 0.10, sill, head, x0d, 'V2_Wood', 0.10, grain=Y)
        Q.fx(m, YHD - 0.62, YHD - 0.10, sill, head, x1d, 'V2_Wood', 0.10, grain=Y, neg=True)
        m.quad((x0d, head, YHD - 0.10), (x1d, head, YHD - 0.10), (x1d, head, YHD - 0.62), (x0d, head, YHD - 0.62),
               'V2_Wood', 0.06, grain=X)
        m.box((0.05, sill + 0.03, YHD + 0.04), (0.97, head, YHD + 0.075), 'V2_Wood', 1.0, grain=Y)   # 新しい板戸（壁より明るい）
        for y in (0.62, 1.20, 1.78):
            m.box((0.07, y, YHD + 0.075), (0.95, y + 0.05, YHD + 0.095), 'V2_Wood', DARK, grain=X, skip=('-z',))
        # 妻壁（板）
        for sx in (1, -1):
            xw = sx * (YHW - 0.01)
            tri = [(xw, Y_EAVE, YHD - 0.02), (xw, Y_EAVE, -YHD + 0.02), (xw, Q.RIDGE - 0.12, 0.0)]
            m.poly(tri if sx > 0 else tri[::-1], 'V2_Wood', BOARD * 0.5, grain=Y)
        Q.main_roof(m, lod)
    woodpile(m, lod)
    m.box((-0.45, -0.14, YHD), (0.45, 0.16, YHD + 0.40), 'V2_Stone', 0.70, skip=('-y',))
    return m


# ═══════════════════════════════ asset.json ═══════════════════════════════
GB = K.load_json(G + '/maps/village_v2/gen/greybox.json')['buildings']


# 後院棟：預設四鏡位中被前排町家擋住的（render 實測：S_A_MKT_006 front_l、S_A_RSW_006／018 street_far），
# 該實例改用自訂鏡位（局部 xz；front＝正前 9 m、近側兩斜角 6 m），不拍被擋的那一張。
# S_A_MKT_006／S_A_RSW_018 的 +x 斜角（near_l）仍被隔壁町家擋 → 改正面近拍。
def near_shots(zf, bid):
    if bid in ('S_A_MKT_006', 'S_A_RSW_018'):
        return [['front', 0.0, zf + 9.0], ['front_near', 0.0, zf + 5.5], ['near_r', -3.0, zf + 5.2]]
    return [['front', 0.0, zf + 9.0], ['near_l', 3.0, zf + 5.2], ['near_r', -3.0, zf + 5.2]]


SHOT_OVERRIDE = {'S_A_MKT_006', 'S_A_RSW_006', 'S_A_RSW_018'}


def instances(kind, zf):
    out = []
    for b in GB:
        if b['kind'] != kind:
            continue
        i = {'anchor': 'Districts/%s/Buildings/%s' % (b['district'], b['id']), 'p4_id': b['id'],
             'parcel': b['parcel'], 'road': b['road']}
        if b['id'] in SHOT_OVERRIDE:
            i['shots'] = near_shots(zf, b['id'])
        out.append(i)
    return out


def stats_of(objs_meshes):
    st = {}
    for lod, m in enumerate(objs_meshes):
        st['LOD%d' % lod] = m.tris()
        if lod == 0:
            xs, ys, zs = [p[0] for p in m.v], [p[1] for p in m.v], [p[2] for p in m.v]
            st['aabb'] = [[round(min(xs), 3), round(min(ys), 3), round(min(zs), 3)],
                          [round(max(xs), 3), round(max(ys), 3), round(max(zs), 3)]]
    return st


def emit(aid, label, build, spec, gate_spec, collision):
    out = G + '/assets/village_v2/' + aid
    K.clear_scene(bpy)
    meshes = [build(lod) for lod in (0, 1, 2)]
    mats = meshes[0].mats
    assert all(mm.mats == mats for mm in meshes), [mm.mats for mm in meshes]
    bm = K.blender_mats(bpy, mats)
    objs = [mm.to_blender(bpy, bmats=bm) for mm in meshes]
    K.export_glb(bpy, out + '/src/%s.glb' % aid, objs)
    st = stats_of(meshes)
    K.write_json(out + '/asset.json', {
        '_note': '%s（build_aux.py 產生；Godot 端 tools/village_v2_hero_prefab.gd、verify_village_v2_hero_gate.gd 讀取）。'
                 '尺寸 authority＝P4 greybox kind %s（同型逐棟同尺寸）；placement body＝掛在 P4 灰盒節點下，'
                 '灰盒網格隱藏、碰撞停用（village_v2_hero_lib.gd retire_body）。' % (label, spec['kind_p4']),
        'id': aid, 'landmark': '', 'kind': 'hero', 'budget_class': '町家',
        'glb': 'res://assets/village_v2/%s/src/%s.glb' % (aid, aid),
        'scene': 'res://assets/village_v2/%s/%s.scn' % (aid, aid),
        'lod_objects': [mm.name for mm in meshes],
        'lod_ranges_m': [0, 40, 110, 700],
        'budget': {'lod0': 25000, 'lod1_ratio': 0.35, 'lod2_ratio': 0.10, 'materials': 5, 'collision': 8},
        'materials': {k: (KURA_SHIKKUI_TRES if k == KURA_SHIKKUI else ML[k]['tres']) for k in mats},
        'spec': spec,
        'gate_spec': gate_spec,
        'collision': collision,
        'measured_blender': st,
    })
    print('[AUX]', aid, st)


def main():
    zf = KZF
    kura_ins = instances('aux_kura', zf)
    emit('aux_kura', '土藏', build_kura,
         {'kind_p4': 'aux_kura', 'width_m': KW_, 'depth_m': KD_, 'eave_m': K_EAVE, 'ridge_m': round(K_RIDGE, 3),
          'plinth_m': PLINTH, 'foundation_bottom_m': BOT, 'ov_eave_m': K_OVE, 'ov_gable_m': K_OVG, 'roof': 'tsuma',
          'door_clear_m': [K_DOOR[1] - K_DOOR[0], round(K_DOOR[3] - K_DOOR[2], 3)],
          'design': {'reference': 'docs/reference/民宅/倉庫.PNG',
                     'zones': ['粗石台 −0.40–0.32', '腰石 0.32–0.55', 'なまこ壁 0.55–1.55', '水切り 1.55–1.63',
                               '白漆喰 1.63–4.20'],
                     'entry': '妻入：正面山牆中央、觀音扉開啟貼牆、小瓦庇、石段'}},
         dict(kura_ins[0], **{
             'placement': 'body', 'replaces': '(灰盒本體)', 'instances': kura_ins,
             'size': {'x_half_max': round(KHW + K_OVE + 0.12, 3), 'z_min': round(-(KHD + K_OVG + 0.14), 3),
                      'z_max': round(KHD + 0.45 + 0.12, 3), 'top': [round(K_RIDGE, 3), round(K_RIDGE + 0.30, 3)],
                      'bottom': BOT},
             'body': {'w': KW_, 'd': KD_, 'eave': K_EAVE, 'ridge': round(K_RIDGE, 3), 'plinth': PLINTH,
                      'roof': 'tsuma', 'probe': {'y': 2.60, 'z': 0.90, 'xb': -1.00, 'xf': 1.60, 'yf': 3.00}},
             'door_clear': {'h': round(K_DOOR[3] - K_DOOR[2], 3), 'w': round(K_DOOR[1] - K_DOOR[0], 3),
                            'min_h': 1.9, 'min_w': 1.2},
             'ground': [
                 {'name': '台基', 'rect': [-KHW, -KHD, KHW, KHD], 'bottom': BOT, 'top': PLINTH, 'embed_max': 0.50},
                 {'name': '踏石', 'rect': [-0.75, zf, 0.75, zf + 0.45], 'bottom': -0.14, 'top': 0.16,
                  'embed_max': 0.25}],
             'walkway': {'rect': [-1.40, zf + 0.65, 1.40, zf + 1.25], 'head': 1.95, 'min_clear': 2.0, 'step': 0.25},
             'entry': [0.0, zf + 0.95], 'inside': [0.0, 0.0]}),
         [{'type': 'box', 'name': 'Body', 'center': [0, (BOT + K_EAVE) / 2, 0.10],
           'size': [KW_ + 0.10, K_EAVE - BOT, KD_ + 0.20]},
          {'type': 'convex', 'name': 'Step', 'center': [0, 0, 0], 'points': [
              [sx * 0.75, y, z] for sx in (-1, 1) for (y, z) in (
                  (-0.14, zf), (0.16, zf), (0.16, zf + 0.38), (-0.14, zf + 0.62))]}])
    zf = YHD
    koya_ins = instances('aux_koya', zf)
    x0, x1, z0, z1 = PILE
    emit('aux_koya', '納屋', build_koya,
         {'kind_p4': 'aux_koya', 'width_m': YW_, 'depth_m': YD_, 'eave_m': Y_EAVE,
          'ridge_m': round(Y_EAVE + YHD * Y_PITCH, 3), 'plinth_m': PLINTH, 'foundation_bottom_m': BOT,
          'ov_eave_m': Y_OVE, 'ov_gable_m': Y_OVG, 'roof': 'hira',
          'door_m': [Y_DOOR[1] - Y_DOOR[0], round(Y_DOOR[3] - Y_DOOR[2], 3)],
          'design': {'reference': '參考圖無小屋（倉庫.PNG 只有土藏）；依村內語彙設計',
                     'features': ['石台＋土台', '焦茶縦板＋押縁', '角柱', '灰瓦平入切妻', '半開板戸（引戸）', '側面連子窓',
                                  '左側薪棚']}},
         dict(koya_ins[0], **{
             'placement': 'body', 'replaces': '(灰盒本體)', 'instances': koya_ins,
             'size': {'x_half_max': round(max(YHW + Y_OVG + 0.05, -x0) + 0.12, 3),
                      'z_min': round(-(YHD + Y_OVE + 0.12), 3), 'z_max': round(YHD + Y_OVE + 0.12, 3),
                      'top': [round(Y_EAVE + YHD * Y_PITCH, 3), round(Y_EAVE + YHD * Y_PITCH + 0.30, 3)],
                      'bottom': BOT},
             'body': {'w': YW_, 'd': YD_, 'eave': Y_EAVE, 'ridge': round(Y_EAVE + YHD * Y_PITCH, 3),
                      'plinth': PLINTH, 'roof': 'hira', 'probe': {'y': 1.90, 'z': -0.60, 'xb': -0.62, 'xf': -1.00,
                                                                  'yf': 1.60}},
             'ground': [
                 {'name': '台基', 'rect': [-YHW, -YHD, YHW, YHD], 'bottom': BOT, 'top': PLINTH, 'embed_max': 0.50},
                 {'name': '踏石', 'rect': [-0.45, zf, 0.45, zf + 0.40], 'bottom': -0.14, 'top': 0.16,
                  'embed_max': 0.25},
                 {'name': '薪棚', 'rect': [x0, z0, x1, z1], 'bottom': -0.25, 'top': 0.08, 'embed_max': 0.35}],
             'walkway': {'rect': [-1.10, zf + 0.65, 1.10, zf + 1.25], 'head': 1.95, 'min_clear': 2.0, 'step': 0.25},
             'entry': [0.0, zf + 0.95], 'inside': [0.0, 0.0]}),
         [{'type': 'box', 'name': 'Body', 'center': [0, (BOT + Y_EAVE) / 2, 0.05],
           'size': [YW_ + 0.06, Y_EAVE - BOT, YD_ + 0.20]},
          {'type': 'convex', 'name': 'Step', 'center': [0, 0, 0], 'points': [
              [sx * 0.45, y, z] for sx in (-1, 1) for (y, z) in (
                  (-0.14, zf), (0.16, zf), (0.16, zf + 0.34), (-0.14, zf + 0.58))]},
          {'type': 'box', 'name': 'Woodpile', 'center': [(x0 + x1) / 2, (-0.25 + PILE_TOP) / 2, 0.0],
           'size': [x1 - x0, PILE_TOP + 0.25, z1 - z0]}])


main()

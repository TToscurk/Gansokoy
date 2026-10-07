"""人間之里 V2 P10 R1b Market West Rework：見世 Kit（mise_kit）— 新資產。

  blender -b --factory-startup --python godot/assets/blender/village_v2/build_mise_kit.py

讀感（TPS 3–25 m、裏通りを歩く玩家の目線）：「町家の店先が通りへ張り出し、通りが店に包まれている」——
  店の正面に付く日除け幕（屋根の庇の先から竹竿 2 本で張る）、軒提灯（壁の腕木に吊る）、路地の口の木戸（冠木＋小屋根＋扁額／水引幕＋提灯）、
  路地の吊り提灯（壁から壁へ）、茶屋の下屋（片流れの売り台＋暖簾）、緋毛氈の縁台、反物の台と掛け。
  r1 の ichi_kit（花柄の卓布・花紋の長旗・縞の日除け・独自 atlas）は全部引退：新しい atlas は作らない。
材質（すべて町で使用中・承認済みのもの）：V2_Wood・V2_Kawara（_matlib）＋MK_Market（market_kit atlas：日除け布 藍／弁柄／生成／柿渋、
  暖簾 丸紋／だんご、反物の無地、提灯、色票）＋ST_Street（street_kit atlas：大看板「市 この奥」、赤・白の提灯）。
座標：Godot（x 右、y 上、+z 前＝通り側）；原點＝壁際の接地點（壁掛けは取付點）；單位 m。*_l1＝LOD1。
  ms_maku_{ai,beni,kinari,kaki}  日除け幕 3.0 × 1.35（上端 y 2.5＝庇の先の下、前 2.15、水引 0.2、竹竿 2 本 x ±1.45・z 1.35）
  ms_noki_chochin_{aka,shiro}    軒提灯：壁板＋腕木 0.55＋筋交い、提灯 Ø0.3 × 0.42（原點＝腕木の取付點）
  ms_tsuna_chochin               吊り提灯：綱 4.4（両端の取付點 y 0、中ほど 0.28 垂れる）に提灯 5（赤白交互）
  ms_kido_{26,37,50}             木戸：柱 2（間 2.6／3.7／5.0、高 3.75）、冠木 2.62–2.86（出 0.2）、小屋根（瓦、柱の外 0.15 まで）、37＝扁額「市 この奥」・提灯 2、
                                 26／50＝藍の丸紋の水引幕（下端 2.22）・提灯 2
  ms_geya_meshi                  一膳飯の下屋（同じ形、大鍋・お櫃・椀、「めし」の暖簾）
  ms_geya_dango                  茶屋の下屋：片流れの瓦屋根（壁際 2.4・前 2.08、出 1.15、幅 3.0）、前柱 2、売り台（0.78）に団子・急須・湯呑、「だんご」の暖簾
  ms_endai_mousen                縁台（1.8 × 0.55 × 0.45）に緋毛氈
  ms_tanmono_dai                 反物の台（1.6 × 0.7 × 0.45）：畳んだ反物の山 3＋斜めの見せ板に巻いた反物
  ms_tsuri_{kaki,waraji,oke}     軒の吊るし物：庇の下の竿（壁から 0.3、幅 1.8）に吊るし柿・干し大根／草鞋・笊／手桶・柄杓（原點＝壁の取付點）
  ms_nuno_kake                   反物の掛け（1.8 × 0.45 × 1.95）：柱 2＋上の竿に無地の布 4
"""
import math
import os
import random
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import v2_kit as K  # noqa: E402

G = K.repo_paths(__file__)
OUT = G + '/assets/village_v2/mise_kit'
ML = K.load_json(G + '/assets/village_v2/_matlib/matlib.json')['materials']
ATM = K.load_json(G + '/assets/village_v2/market_kit/atlas.json')
ATS = K.load_json(G + '/assets/village_v2/street_kit/atlas.json')
RM, SM = ATM['regions'], ATM['swatches']
RS, SS = ATS['regions'], ATS['swatches']
WD = 'V2_Wood'
KW = 'V2_Kawara'
MK = 'MK_Market'
ST = 'ST_Street'
MATS = [WD, KW, MK, ST]
TILE = {WD: ML['V2_Wood']['tile_m'], KW: ML['V2_Kawara']['tile_m'], MK: 1.0, ST: 1.0}

# 木：町家 Kit・市集 R1 と同じ明るさ（独自の明るい木は使わない）
WOODC = (0.84, 0.78, 0.68)
AGED = (0.66, 0.62, 0.56)
OLD = (0.52, 0.48, 0.43)
DARK = (0.34, 0.29, 0.24)

MODS = {}
INFO = {}


def new(name, lod, note=''):
    n = name + ('_l1' if lod else '')
    m = K.Mesh(n, MATS, TILE)
    MODS[n] = m
    INFO[n] = note
    return m


# ─────────────────────────── 基本 ───────────────────────────

def swr(key):
    u, v = SM[key]
    return [u - 0.003, v - 0.003, u + 0.003, v + 0.003]


def obx(m, c, h, key, ax=K.X, ay=K.Y, az=K.Z):
    m.abox(c, h, MK, {'*': swr(key)}, 1.0, ax=ax, ay=ay, az=az)


def rbx(m, c, h, region, ax=K.X, ay=K.Y, az=K.Z, col=1.0):
    m.abox(c, h, MK, {'*': RM[region]}, col, ax=ax, ay=ay, az=az)


def cy(m, p0, p1, r0, r1, seg, key, caps=(True, True)):
    m.cyl(p0, p1, r0, r1, seg, MK, 1.0, caps=caps, uv_atlas=swr(key))


def ball(m, c, r, key, seg, squash=1.0):
    x, y, z = c
    ry = r * squash
    cy(m, (x, y - ry, z), (x, y - ry * 0.55, z), r * 0.25, r * 0.85, seg, key, caps=(True, False))
    cy(m, (x, y - ry * 0.55, z), (x, y + ry * 0.55, z), r * 0.85, r * 0.85, seg, key, caps=(False, False))
    cy(m, (x, y + ry * 0.55, z), (x, y + ry, z), r * 0.85, r * 0.25, seg, key, caps=(False, True))


def pole(m, p0, p1, r, key='take', seg=6):
    cy(m, p0, p1, r, r * 0.9, seg, key, caps=(False, True))


def post(m, x, z, y0, y1, r=0.075, col=AGED):
    m.box((x - r, y0, z - r), (x + r, y1, z + r), WD, col)


def cloth(m, a, b, c, d, mat, region, col=1.0, back=True):
    """両面の布（表裏とも正しく読める）。a 左下・b 右下・c 右上・d 左上（表から見て）。"""
    m.rect_uv(a, b, c, d, mat, region, col)
    if back:
        m.rect_uv(b, a, d, c, mat, region, col * 0.85)


def lantern(m, x, y, z, r, h, lod, region):
    """提灯：上端 y から下へ h（ST の提灯 region、上下に黒い輪）。"""
    seg = 8 if lod else 12
    u0, v0, u1, v1 = region
    cy(m, (x, y, z), (x, y - 0.03, z), r * 0.55, r * 0.62, seg, 'urushi', caps=(True, False))
    # 紙の胴は下→上へ作る（cyl は p0 に v1・p1 に v0；上→下だと半分ずつ上下逆＋左右逆になり字が割れていた、2026-10-07 修正）
    m.cyl((x, y - 0.03 - h, z), (x, y - 0.03 - h * 0.5, z), r * 0.62, r, seg, ST, 1.0, caps=(False, False), uv_atlas=[u0, (v0 + v1) / 2, u1, v1])
    m.cyl((x, y - 0.03 - h * 0.5, z), (x, y - 0.03, z), r, r * 0.62, seg, ST, 1.0, caps=(False, False), uv_atlas=[u0, v0, u1, (v0 + v1) / 2])
    cy(m, (x, y - 0.03 - h, z), (x, y - 0.06 - h, z), r * 0.62, r * 0.55, seg, 'urushi', caps=(False, True))


def sag_cloth(m, x0, x1, zb, zf, yb, yf, region, n, sag, lod):
    """斜めの日除け布：後 zb（高 yb）〜前 zf（高 yf）、x0..x1 を n 帯、各帯の中ほどが sag 垂れ、前縁は竿の間で弛む。"""
    u0, v0, u1, v1 = RM[region]
    nj = 1 if lod else 3
    for i in range(n):
        xa = x0 + (x1 - x0) * i / n
        xb = x0 + (x1 - x0) * (i + 1) / n
        for j in range(nj):
            ta, tb = j / nj, (j + 1) / nj

            def P(x, t):
                z = zb + (zf - zb) * t
                y = yb + (yf - yb) * t - sag * math.sin(math.pi * t) - 0.06 * t * math.sin(math.pi * (x - x0) / (x1 - x0))
                return (x, y, z)
            a, b, c, d = P(xa, tb), P(xb, tb), P(xb, ta), P(xa, ta)
            ua = u0 + (u1 - u0) * i / n
            ub = u0 + (u1 - u0) * (i + 1) / n
            va = v0 + (v1 - v0) * ta
            vb = v0 + (v1 - v0) * tb
            # 表＝上（日の当たる面）、裏＝下（通りから見上げる面、少し暗く）
            m.quad(d, c, b, a, MK, 1.0, uvs=[(ua, va), (ub, va), (ub, vb), (ua, vb)])
            m.quad(a, b, c, d, MK, 0.8, uvs=[(ua, vb), (ub, vb), (ub, va), (ua, va)])


# ─────────────────────────── 日除け幕 ───────────────────────────

MAKU_W = 3.0
MAKU_Z0, MAKU_Z1 = 0.42, 1.35
MAKU_Y0, MAKU_Y1 = 2.5, 2.15


def maku(key, lod):
    region = 'awn_' + key
    m = new('ms_maku_' + key, lod, '日除け幕（%s）：幅 3.0、庇の先の下（z 0.42・y 2.5）から前 1.35（y 2.15）へ張り、前縁に水引 0.2、竹竿 2 本（x ±1.45）と上端の押さえ竹、竿元に縄' % key)
    hw = MAKU_W / 2
    sag_cloth(m, -hw, hw, MAKU_Z0, MAKU_Z1, MAKU_Y0, MAKU_Y1, region, 4 if not lod else 2, 0.06, lod)
    # 水引（前縁から垂れる帯）：同じ布
    u0, v0, u1, v1 = RM[region]
    nseg = 4 if not lod else 1
    for i in range(nseg):
        xa = -hw + MAKU_W * i / nseg
        xb = -hw + MAKU_W * (i + 1) / nseg
        ya = MAKU_Y1 - 0.06 * math.sin(math.pi * (xa + hw) / MAKU_W)
        yb = MAKU_Y1 - 0.06 * math.sin(math.pi * (xb + hw) / MAKU_W)
        ua = u0 + (u1 - u0) * i / nseg
        ub = u0 + (u1 - u0) * (i + 1) / nseg
        vv = v0 + (v1 - v0) * 0.25
        m.quad((xa, ya - 0.2, MAKU_Z1 + 0.01), (xb, yb - 0.2, MAKU_Z1 + 0.01), (xb, yb, MAKU_Z1 + 0.01), (xa, ya, MAKU_Z1 + 0.01), MK, 1.0,
               uvs=[(ua, vv), (ub, vv), (ub, v0), (ua, v0)])
        m.quad((xb, yb - 0.2, MAKU_Z1 - 0.005), (xa, ya - 0.2, MAKU_Z1 - 0.005), (xa, ya, MAKU_Z1 - 0.005), (xb, yb, MAKU_Z1 - 0.005), MK, 0.8,
               uvs=[(ub, vv), (ua, vv), (ua, v0), (ub, v0)])
    # 竹竿 2 本＋上端の押さえ竹
    for sx in (-1, 1):
        x = sx * (hw - 0.05)
        pole(m, (x, 0.0, MAKU_Z1), (x, MAKU_Y1 + 0.08, MAKU_Z1), 0.022)
        if not lod:
            cy(m, (x, MAKU_Y1 - 0.02, MAKU_Z1), (x, MAKU_Y1 + 0.04, MAKU_Z1), 0.032, 0.032, 6, 'nawa', caps=(False, False))
            m.cyl((x, 0.0, MAKU_Z1), (x, 0.08, MAKU_Z1), 0.07, 0.055, 6, WD, OLD)
    pole(m, (-hw - 0.05, MAKU_Y0 + 0.01, MAKU_Z0), (hw + 0.05, MAKU_Y0 + 0.01, MAKU_Z0), 0.018)
    return m


# ─────────────────────────── 提灯 ───────────────────────────

def noki_chochin(key, lod):
    region = RS['chochin_' + key]
    m = new('ms_noki_chochin_' + key, lod, '軒提灯（%s）：壁板＋腕木 0.55＋筋交い、提灯 Ø0.3 × 0.42（原點＝腕木の壁の取付點）' % key)
    m.box((-0.05, -0.38, -0.01), (0.05, 0.08, 0.03), WD, OLD)
    m.beam((0.0, 0.0, 0.0), (0.0, 0.0, 0.58), 0.05, 0.06, WD, AGED)
    m.beam((0.0, -0.32, 0.02), (0.0, -0.02, 0.36), 0.035, 0.035, WD, OLD)
    cy(m, (0.0, -0.03, 0.52), (0.0, -0.13, 0.52), 0.004, 0.004, 3, 'nawa', caps=(False, False))
    lantern(m, 0.0, -0.13, 0.52, 0.15, 0.42, lod, region)
    return m


def tsuna_chochin(lod):
    m = new('ms_tsuna_chochin', lod, '吊り提灯：綱 4.4（両端の取付點 y 0、中ほど 0.28 垂れる）＋壁の取付板、提灯 5（赤白交互、Ø0.26 × 0.38）')
    span = 4.4
    n = 10 if not lod else 4
    pts = []
    for i in range(n + 1):
        t = i / n
        pts.append((-span / 2 + span * t, -0.28 * math.sin(math.pi * t), 0.0))
    for i in range(n):
        cy(m, pts[i], pts[i + 1], 0.014, 0.014, 5, 'nawa', caps=(False, False))
    for x in (-span / 2, span / 2):
        m.box((x - 0.04 if x > 0 else x - 0.0, -0.12, -0.06), (x + 0.0 if x > 0 else x + 0.04, 0.1, 0.06), WD, OLD)
    for k in range(5):
        t = (k + 1) / 6
        x = -span / 2 + span * t
        y = -0.28 * math.sin(math.pi * t)
        cy(m, (x, y, 0.0), (x, y - 0.1, 0.0), 0.004, 0.004, 3, 'nawa', caps=(False, False))
        lantern(m, x, y - 0.1, 0.0, 0.13, 0.38, lod, RS['chochin_aka' if k % 2 == 0 else 'chochin_shiro'])
    return m


# ─────────────────────────── 木戸 ───────────────────────────

KIDO_H = 3.75
BEAM_Y0, BEAM_Y1 = 2.62, 2.86


def small_roof(m, x0, x1, y_eave, y_ridge, dz, lod):
    """冠木の上の小さな切妻（瓦）：棟沿 x、前後へ dz。"""
    tu, tv = 4.24, 2.4
    S = math.hypot(dz, y_ridge - y_eave)
    for s in (1, -1):
        rl, rr = (x0, y_ridge, 0.0), (x1, y_ridge, 0.0)
        el, er = (x0, y_eave, s * dz), (x1, y_eave, s * dz)
        if s > 0:
            m.quad(el, er, rr, rl, KW, 1.0, uvs=[(el[0] / tu, S / tv), (er[0] / tu, S / tv), (rr[0] / tu, 0.0), (rl[0] / tu, 0.0)])
            m.quad(rl, rr, er, el, WD, 0.5)
        else:
            m.quad(er, el, rl, rr, KW, 1.0, uvs=[(-er[0] / tu, S / tv), (-el[0] / tu, S / tv), (-rl[0] / tu, 0.0), (-rr[0] / tu, 0.0)])
            m.quad(rr, rl, el, er, WD, 0.5)
        m.beam(el, er, 0.05, 0.05, WD, DARK)
    # 妻の板
    for x in (x0, x1):
        m.poly([(x, y_eave, -dz), (x, y_eave, dz), (x, y_ridge, 0.0)] if x > 0 else [(x, y_eave, dz), (x, y_eave, -dz), (x, y_ridge, 0.0)], WD, OLD)
    cy(m, (x0 - 0.06, y_ridge + 0.03, 0.0), (x1 + 0.06, y_ridge + 0.03, 0.0), 0.075, 0.075, 8 if lod else 12, 'kokuyu')


def kido(span_cm, lod):
    S = span_cm / 10.0
    hs = S / 2
    plaque = span_cm == 37
    m = new('ms_kido_%d' % span_cm, lod, '木戸：柱 2（間 %.1f、高 %.2f、根石）、冠木 %.2f–%.2f（出 0.2）、小屋根（瓦、棟 4.0）、%s、提灯 2'
            % (S, KIDO_H, BEAM_Y0, BEAM_Y1, '扁額「市 この奥」' if plaque else '藍の丸紋の水引幕（下端 2.22）'))
    for x in (-hs, hs):
        post(m, x, 0.0, -0.2, KIDO_H, 0.08, AGED)
        m.box((x - 0.15, -0.05, -0.15), (x + 0.15, 0.1, 0.15), WD, DARK)
        if not lod:
            # 柱の上の控え（斜めの方杖）
            sx = 1 if x < 0 else -1
            m.beam((x, BEAM_Y0 - 0.45, 0.0), (x + sx * 0.4, BEAM_Y0, 0.0), 0.06, 0.06, WD, OLD)
    m.box((-hs - 0.2, BEAM_Y0, -0.09), (hs + 0.2, BEAM_Y1, 0.09), WD, OLD)
    y_e = 3.55 if plaque else 3.15
    y_r = 3.95 if plaque else 3.5
    m.box((-hs - 0.1, y_e - 0.12, -0.07), (hs + 0.1, y_e - 0.02, 0.07), WD, OLD)     # 小屋根の桁
    for x in (-hs, hs):
        m.box((x - 0.05, BEAM_Y1, -0.05), (x + 0.05, y_e - 0.12, 0.05), WD, AGED)    # 柱の延長（桁まで）
    small_roof(m, -hs - 0.15, hs + 0.15, y_e, y_r, 0.48, lod)
    if plaque:
        # 扁額（冠木の上、表＝+z に「市 この奥」、裏は板）
        u0, v0, u1, v1 = RS['ichi_big']
        m.box((-0.3, BEAM_Y1 + 0.02, -0.04), (0.3, y_e - 0.16, 0.0), WD, DARK)
        m.rect_uv((-0.27, BEAM_Y1 + 0.05, 0.005), (0.27, BEAM_Y1 + 0.05, 0.005), (0.27, y_e - 0.19, 0.005), (-0.27, y_e - 0.19, 0.005), ST, RS['ichi_big'])
    else:
        # 水引幕（藍の丸紋）：冠木の下、両面
        nb = 3 if S < 3.5 else 4
        pw = (S - 0.3) / nb
        for i in range(nb):
            xa = -hs + 0.15 + i * pw + 0.01
            xb = xa + pw - 0.02
            cloth(m, (xa, BEAM_Y0 - 0.38, 0.1), (xb, BEAM_Y0 - 0.38, 0.1), (xb, BEAM_Y0 - 0.01, 0.1), (xa, BEAM_Y0 - 0.01, 0.1), MK, RM['noren_mon'])
    for x in (-hs + 0.45, hs - 0.45):
        cy(m, (x, BEAM_Y0, 0.0), (x, BEAM_Y0 - 0.12, 0.0), 0.004, 0.004, 3, 'nawa', caps=(False, False))
        lantern(m, x, BEAM_Y0 - 0.12 if plaque else BEAM_Y0 - 0.12, -0.14 if not plaque else 0.0, 0.14, 0.4, lod, RS['chochin_aka'])
    return m


# ─────────────────────────── 茶屋の下屋・縁台 ───────────────────────────

def geya(kind, lod):
    note = {'dango': '茶屋の下屋：片流れの瓦屋根（壁際 2.4・前 2.08、出 1.15、幅 3.0）、前柱 2、売り台（0.78、奥 0.45）に団子の皿・急須・湯呑・盆、「だんご」の暖簾 3 枚',
            'meshi': '一膳飯の下屋：同じ片流れ屋根・前柱・売り台に大鍋・お櫃・椀の重ね、柿渋に白「めし」の暖簾 3 枚、台下に薪束'}[kind]
    m = new('ms_geya_' + kind, lod, note)
    rng = random.Random(51001 if kind == 'dango' else 51003)
    W, D = 3.0, 1.15
    hw = W / 2
    yb, yf = 2.4, 2.08
    for x in (-hw + 0.1, hw - 0.1):
        post(m, x, D - 0.08, 0.0, yf - 0.04, 0.06, AGED)
    m.box((-hw, yf - 0.16, D - 0.14), (hw, yf - 0.04, D - 0.02), WD, OLD)             # 桁
    m.box((-hw, yb - 0.12, -0.02), (hw, yb, 0.08), WD, OLD)                          # 壁の受け材
    tu, tv = 4.24, 2.4
    S = math.hypot(D + 0.25, yb - yf + 0.08)
    el, er = (-hw - 0.15, yf - 0.06, D + 0.25), (hw + 0.15, yf - 0.06, D + 0.25)
    rl, rr = (-hw - 0.15, yb + 0.02, 0.0), (hw + 0.15, yb + 0.02, 0.0)
    m.quad(el, er, rr, rl, KW, 1.0, uvs=[(el[0] / tu, S / tv), (er[0] / tu, S / tv), (rr[0] / tu, 0.0), (rl[0] / tu, 0.0)])
    m.quad(rl, rr, er, el, WD, 0.5)
    m.beam(el, er, 0.05, 0.05, WD, DARK)
    for x in (-hw - 0.15, hw + 0.15):
        m.poly([(x, yb + 0.02, 0.0), (x, yf - 0.06, D + 0.25), (x, yf - 0.12, D + 0.25), (x, yb - 0.04, 0.0)] if x > 0 else
               [(x, yb - 0.04, 0.0), (x, yf - 0.12, D + 0.25), (x, yf - 0.06, D + 0.25), (x, yb + 0.02, 0.0)], WD, OLD)
    # 暖簾「だんご」（前の桁の下、3 枚、両面）
    u0, v0, u1, v1 = RM['noren_' + kind]
    yt = yf - 0.16
    for i in range(3):
        xa = -hw + 0.2 + i * (W - 0.4) / 3 + 0.01
        xb = -hw + 0.2 + (i + 1) * (W - 0.4) / 3 - 0.01
        ua = u0 + (u1 - u0) * i / 3
        ub = u0 + (u1 - u0) * (i + 1) / 3
        m.quad((xa, yt - 0.42, D - 0.0), (xb, yt - 0.42, D - 0.0), (xb, yt, D - 0.02), (xa, yt, D - 0.02), MK, 1.0, uvs=[(ua, v1), (ub, v1), (ub, v0), (ua, v0)])
        m.quad((xb, yt - 0.42, D - 0.015), (xa, yt - 0.42, D - 0.015), (xa, yt, D - 0.035), (xb, yt, D - 0.035), MK, 0.85, uvs=[(u0 + u1 - ub, v1), (u0 + u1 - ua, v1), (u0 + u1 - ua, v0), (u0 + u1 - ub, v0)])   # 裏：u を左右反轉（字の順も裏から正しく、2026-10-07 修正）
    # 売り台
    m.box((-hw + 0.15, 0.74, D - 0.5), (hw - 0.15, 0.78, D - 0.05), WD, WOODC)
    m.box((-hw + 0.18, 0.0, D - 0.1), (hw - 0.18, 0.74, D - 0.06), WD, OLD)
    for x in (-hw + 0.18, hw - 0.22):
        m.box((x, 0.0, D - 0.5), (x + 0.04, 0.74, D - 0.46), WD, OLD)
    if kind == 'meshi':
        y = 0.78
        for x in (-0.85, -0.3):
            cy(m, (x, y, D - 0.28), (x, y + 0.18, D - 0.28), 0.15, 0.18, 8 if lod else 12, 'tetsu', caps=(True, False))
            cy(m, (x, y + 0.18, D - 0.28), (x, y + 0.12, D - 0.28), 0.17, 0.14, 8 if lod else 12, 'shoyu', caps=(False, True))
        m.cyl((0.3, y, D - 0.27), (0.3, y + 0.2, D - 0.27), 0.15, 0.15, 12 if not lod else 8, WD, WOODC)
        for i in range(4):
            for j in range(3 if not lod else 1):
                xx, zz = 0.75 + (i % 2) * 0.12, D - 0.38 + (i // 2) * 0.13
                cy(m, (xx, y + j * 0.045, zz), (xx, y + j * 0.045 + 0.045, zz), 0.025, 0.05, 8, ['shuurushi', 'urushi'][i % 2], caps=(True, False))
        for i in range(5 if not lod else 2):
            m.cyl((-1.2, 0.2 + (i % 2) * 0.06, D - 0.45 + i * 0.07), (0.2, 0.2 + (i % 2) * 0.06, D - 0.45 + i * 0.07), 0.035, 0.035, 5, WD, OLD)
        return m
    # 盆に団子の皿・急須・湯呑
    for gx in (-0.9, -0.3, 0.35):
        m.box((gx - 0.2, 0.78, D - 0.4), (gx + 0.2, 0.8, D - 0.15), WD, DARK)
        for k in range(3 if not lod else 1):
            a = rng.uniform(-0.4, 0.4)
            c = (gx - 0.08 + k * 0.08, 0.83, D - 0.28)
            d = (math.cos(a) * 0.08, 0.0, math.sin(a) * 0.08)
            cy(m, K.sub(c, d), K.add(c, d), 0.004, 0.004, 4, 'take', caps=(False, False))
            for j, kk in enumerate(('dango_p', 'dango_w', 'dango_g')):
                ball(m, K.add(c, K.mul(d, -0.5 + 0.5 * j)), 0.017, kk, 5 if lod else 6)
    ball(m, (0.95, 0.86, D - 0.28), 0.07, 'ameyu', 8 if lod else 10, 0.8)
    for k in range(3 if not lod else 1):
        cy(m, (0.7 + k * 0.12, 0.78, D - 0.18), (0.7 + k * 0.12, 0.85, D - 0.18), 0.026, 0.032, 8, 'hakuji', caps=(True, False))
    return m


def endai_mousen(lod):
    m = new('ms_endai_mousen', lod, '縁台 1.8 × 0.55 × 0.45 に緋毛氈（前と両端に 0.12 垂れる）')
    x0, x1, z0, z1, h = -0.9, 0.9, -0.275, 0.275, 0.45
    m.box((x0, h - 0.05, z0), (x1, h - 0.01, z1), WD, WOODC)
    for x in (x0 + 0.06, x1 - 0.1):
        for z in (z0 + 0.04, z1 - 0.08):
            m.box((x, 0.0, z), (x + 0.04, h - 0.05, z + 0.04), WD, OLD)
    m.box((x0 + 0.08, 0.12, -0.02), (x1 - 0.08, 0.15, 0.02), WD, OLD)
    k = swr('mousen')
    u, v = SM['mousen']
    m.poly([(x0 + 0.02, h, z1 + 0.01), (x1 - 0.02, h, z1 + 0.01), (x1 - 0.02, h, z0 + 0.02), (x0 + 0.02, h, z0 + 0.02)], MK, 1.0, uvs=[(u, v)] * 4)
    m.poly([(x0 + 0.02, h - 0.12, z1 + 0.012), (x1 - 0.02, h - 0.12, z1 + 0.012), (x1 - 0.02, h, z1 + 0.012), (x0 + 0.02, h, z1 + 0.012)], MK, 0.9, uvs=[(u, v)] * 4)
    for x in (x0 + 0.01, x1 - 0.01):
        sx = -1 if x < 0 else 1
        ps = [(x, h - 0.12, z0 + 0.02), (x, h - 0.12, z1 + 0.01), (x, h, z1 + 0.01), (x, h, z0 + 0.02)]
        m.poly(ps if sx > 0 else list(reversed(ps)), MK, 0.85, uvs=[(u, v)] * 4)
    return m


# ─────────────────────────── 反物 ───────────────────────────

NUNO = ['nuno_ai', 'nuno_koshi', 'nuno_akane', 'nuno_nezumi', 'nuno_kasuri', 'nuno_yamabuki', 'nuno_wakakusa']


def tanmono_dai(lod):
    m = new('ms_tanmono_dai', lod, '反物の台 1.6 × 0.7 × 0.45：畳んだ反物の山 3（無地・絣）＋後ろの斜めの見せ板に巻いた反物 6')
    rng = random.Random(51002)
    h = 0.45
    m.box((-0.8, h - 0.04, -0.35), (0.8, h, 0.35), WD, WOODC)
    for x in (-0.74, 0.7):
        for z in (-0.3, 0.26):
            m.box((x, 0.0, z), (x + 0.04, h - 0.04, z + 0.04), WD, OLD)
    k = 0
    for gx in (-0.5, 0.0, 0.5):
        y = h
        for j in range(5 if not lod else 2):
            rbx(m, (gx + rng.uniform(-0.02, 0.02), y + 0.035, 0.12 + rng.uniform(-0.02, 0.02)), (0.2, 0.035, 0.15), NUNO[k % len(NUNO)])
            y += 0.07
            k += 2
    # 斜めの見せ板（後ろ、45°）に巻いた反物
    sl = K.norm((0.0, 0.7, 0.7))
    m.obox((0.0, h + 0.25, -0.22), (0.78, 0.015, 0.2), WD, OLD, ax=K.X, ay=K.norm((0.0, 0.7, -0.7)), az=sl)
    for i in range(6 if not lod else 3):
        x = -0.62 + i * (1.24 / (5 if not lod else 2))
        c0 = (x, h + 0.12, -0.08)
        c1 = (x, h + 0.42, -0.37)
        m.cyl(c0, c1, 0.055, 0.055, 6 if lod else 8, MK, 1.0, caps=(True, True), uv_atlas=RM[NUNO[(i * 3) % len(NUNO)]])
    return m


def nuno_kake(lod):
    m = new('ms_nuno_kake', lod, '反物の掛け 1.8 × 0.45 × 1.95：柱 2（根元に足）＋上の竿に無地・絣の布 4（0.38 × 1.2、裾が少し前へ）')
    for x in (-0.85, 0.85):
        post(m, x, 0.0, 0.0, 1.95, 0.035, AGED)
        m.box((x - 0.05, 0.0, -0.22), (x + 0.05, 0.05, 0.22), WD, OLD)
    pole(m, (-0.95, 1.88, 0.0), (0.95, 1.88, 0.0), 0.018)
    for i, x in enumerate((-0.6, -0.2, 0.2, 0.6)):
        r = RM[('nuno_ai', 'nuno_akane', 'nuno_kasuri', 'nuno_koshi')[i]]
        nv = 1 if lod else 3
        for j in range(nv):
            ta, tb = j / nv, (j + 1) / nv
            ya, yb = 1.86 - 1.2 * ta, 1.86 - 1.2 * tb
            za, zb = 0.06 * ta * ta, 0.06 * tb * tb
            va = r[1] + (r[3] - r[1]) * ta
            vb = r[1] + (r[3] - r[1]) * tb
            m.quad((x - 0.19, yb, zb), (x + 0.19, yb, zb), (x + 0.19, ya, za), (x - 0.19, ya, za), MK, 1.0, uvs=[(r[0], vb), (r[2], vb), (r[2], va), (r[0], va)])
            m.quad((x + 0.19, yb, zb - 0.004), (x - 0.19, yb, zb - 0.004), (x - 0.19, ya, za - 0.004), (x + 0.19, ya, za - 0.004), MK, 0.82,
                   uvs=[(r[2], vb), (r[0], vb), (r[0], va), (r[2], va)])
    return m


# ─────────────────────────── 軒の吊るし物 ───────────────────────────

def tsurimono(kind, lod):
    """庇の下の吊るし物：壁から 0.3 の竿（幅 1.8、壁の腕木 2）に商いの品を吊る。原點＝壁の取付點（竿の高さ y 0）。"""
    note = {'kaki': '吊るし柿の連 5＋干し大根の束 2（乾物・八百屋）', 'waraji': '草鞋の束 4＋笊 2＋菅笠 1（荒物・米屋）',
            'oke': '手桶 3＋柄杓 2＋笊 1（桶屋）'}[kind]
    m = new('ms_tsuri_' + kind, lod, '軒の吊るし物（%s）：竿 1.8（壁から 0.3、腕木 2）、下端 −0.75' % note)
    rng = random.Random({'kaki': 52001, 'waraji': 52002, 'oke': 52003}[kind])
    for x in (-0.8, 0.8):
        m.beam((x, 0.0, 0.0), (x, 0.0, 0.34), 0.04, 0.05, WD, OLD)
    pole(m, (-0.9, 0.0, 0.3), (0.9, 0.0, 0.3), 0.018)
    n = 6
    for i in range(n if not lod else 3):
        x = -0.75 + 1.5 * i / (n - 1 if not lod else 2)
        if kind == 'kaki':
            if i % 3 == 2:
                for j in range(3 if not lod else 1):
                    cy(m, (x + (j - 1) * 0.04, 0.0, 0.3), (x + (j - 1) * 0.05, -0.55, 0.32), 0.024, 0.01, 5, 'daikon', caps=(False, True))
            else:
                cy(m, (x, 0.0, 0.3), (x, -0.7, 0.3), 0.004, 0.004, 3, 'nawa', caps=(False, False))
                for j in range(7 if not lod else 3):
                    ball(m, (x, -0.06 - j * 0.09, 0.3), 0.034, 'kaki', 5 if lod else 6, 0.9)
        elif kind == 'waraji':
            if i in (2, 3):
                cy(m, (x, 0.0, 0.3), (x, -0.12, 0.3), 0.004, 0.004, 3, 'nawa', caps=(False, False))
                u0, v0, u1, v1 = RM['zaru']
                m.cyl((x, -0.12, 0.3), (x, -0.16, 0.3), 0.16, 0.2, 10 if not lod else 6, MK, 1.0, caps=(True, False), uv_atlas=[u0, v0, u1, v0 + (v1 - v0) * 0.3])
            else:
                cy(m, (x, 0.0, 0.3), (x, -0.62, 0.3), 0.004, 0.004, 3, 'nawa', caps=(False, False))
                u0, v0, u1, v1 = RM['straw']
                for j in range(4 if not lod else 2):
                    m.abox((x, -0.1 - j * 0.14, 0.3), (0.05, 0.11, 0.014), MK, {'*': [u0, v0, u1, v1]})
        else:
            cy(m, (x, 0.0, 0.3), (x, -0.14, 0.3), 0.004, 0.004, 3, 'nawa', caps=(False, False))
            if i % 2 == 0:
                m.cyl((x, -0.4, 0.3), (x, -0.14, 0.3), 0.11, 0.13, 10 if not lod else 6, WD, AGED, caps=(True, False))
                cy(m, (x, -0.2, 0.3), (x, -0.18, 0.3), 0.135, 0.135, 8, 'tetsu', caps=(False, False))
            else:
                cy(m, (x, -0.14, 0.3), (x, -0.5, 0.3), 0.008, 0.008, 4, 'take', caps=(False, False))
                m.cyl((x, -0.5, 0.3), (x, -0.58, 0.3), 0.05, 0.05, 8, WD, AGED, caps=(True, True))
    return m


# ─────────────────────────── r3「営業中」：商品・ばったり床几・店内の棚・蔀・掀げた暖簾 ───────────────────────────

def ssw(key):
    u, v = SS[key]
    return [u - 0.003, v - 0.003, u + 0.003, v + 0.003]


def cys(m, p0, p1, r0, r1, seg, key, caps=(True, True)):
    m.cyl(p0, p1, r0, r1, seg, ST, 1.0, caps=caps, uv_atlas=ssw(key))


def balls(m, c, r, key, seg, squash=1.0):
    x, y, z = c
    ry = r * squash
    cys(m, (x, y - ry, z), (x, y - ry * 0.55, z), r * 0.25, r * 0.85, seg, key, caps=(True, False))
    cys(m, (x, y - ry * 0.55, z), (x, y + ry * 0.55, z), r * 0.85, r * 0.85, seg, key, caps=(False, False))
    cys(m, (x, y + ry * 0.55, z), (x, y + ry, z), r * 0.85, r * 0.25, seg, key, caps=(False, True))


def zaru(m, x, y, z, r, lod):
    u0, v0, u1, v1 = RM['zaru']
    m.cyl((x, y, z), (x, y + 0.06, z), r * 0.8, r, 10 if not lod else 6, MK, 1.0, caps=(True, False), uv_atlas=[u0, v0, u1, v0 + (v1 - v0) * 0.35])


def heap(m, x, y, z, r, keys, n, rr, lod, rng, squash=0.85, st=False):
    """笊・盆の上の山：半径 r の円内に n 個の玉（半径 rr）を 2 段に。"""
    for i in range(n):
        a = rng.uniform(0, math.tau)
        d = r * math.sqrt(rng.uniform(0, 1)) * 0.75
        lay = 0 if i < n * 0.65 else 1
        c = (x + math.cos(a) * d * (0.6 if lay else 1.0), y + rr * squash + lay * rr * 1.2, z + math.sin(a) * d * (0.6 if lay else 1.0))
        (balls if st else ball)(m, c, rr * rng.uniform(0.85, 1.15), keys[i % len(keys)], 5 if lod else 7, squash)


def goods(m, kind, x0, x1, z0, z1, y, lod, rng, dense=1.0):
    """商品の帯：x0..x1 × z0..z1（奥 z0 → 手前 z1）、上面 y に商いの品を並べる。dense＝密度（1.0＝標準）。"""
    w = x1 - x0
    zc = (z0 + z1) * 0.5
    dz = z1 - z0
    if kind == 'yasai':
        n = max(2, int(w / 0.42 * dense))
        veg = [(['nasu'], 0.035, 0.75), (['kyuri'], 0.03, 1.0), (['ninjin'], 0.03, 1.2), (['kabocha'], 0.07, 0.75), (['kyabetsu'], 0.065, 0.9),
               (['satoimo'], 0.03, 0.9), (['ringo', 'kaki'], 0.04, 0.9), (['negi'], 0.03, 1.0)]
        for i in range(n):
            x = x0 + w * (i + 0.5) / n
            for row, zz in enumerate((z0 + dz * 0.3, z0 + dz * 0.75)):
                if lod and row == 0:
                    continue
                keys, rr, sq = veg[(i * 2 + row) % len(veg)]
                zaru(m, x, y, zz, min(0.17, w / n * 0.45), lod)
                heap(m, x, y + 0.04, zz, min(0.14, w / n * 0.38), keys, 9 if not lod else 3, rr, lod, rng, sq)
        if not lod:
            for i in range(max(1, int(w / 0.8))):        # 大根の束を寝かせる
                x = x0 + 0.2 + i * 0.8
                for j in range(3):
                    cy(m, (x + j * 0.06, y + 0.04, z1 - 0.05), (x + j * 0.06 + 0.05, y + 0.04, z0 + 0.05), 0.035, 0.02, 6, 'daikon')
                    cy(m, (x + j * 0.06 + 0.05, y + 0.04, z0 + 0.05), (x + j * 0.06 + 0.07, y + 0.07, z0 - 0.08), 0.025, 0.01, 5, 'daikon_leaf')
    elif kind == 'seto':
        n = max(2, int(w / 0.3 * dense))
        for i in range(n):
            x = x0 + w * (i + 0.5) / n + rng.uniform(-0.03, 0.03)
            t = i % 4
            if t == 0:                                      # 皿の重ね
                for j in range(rng.randint(3, 6) if not lod else 2):
                    cy(m, (x, y + j * 0.025, zc), (x, y + j * 0.025 + 0.022, zc), 0.1, 0.12, 10 if not lod else 6, ['hakuji', 'sometsuke'][j % 2])
            elif t == 1:                                    # 碗の重ね
                for j in range(rng.randint(2, 4) if not lod else 1):
                    cy(m, (x, y + j * 0.05, zc), (x, y + j * 0.05 + 0.06, zc), 0.05, 0.075, 10 if not lod else 6, 'sometsuke')
            elif t == 2:                                    # 甕・壺
                h = rng.uniform(0.18, 0.3)
                k = ['ameyu', 'haiyu', 'kokuyu'][i % 3]
                cy(m, (x, y, z0 + dz * 0.4), (x, y + h * 0.75, z0 + dz * 0.4), 0.07, 0.1, 10 if not lod else 6, k, caps=(True, False))
                cy(m, (x, y + h * 0.75, z0 + dz * 0.4), (x, y + h, z0 + dz * 0.4), 0.1, 0.05, 10 if not lod else 6, k, caps=(False, True))
            else:                                           # 徳利・湯呑
                for j in range(3 if not lod else 1):
                    xx = x + (j - 1) * 0.07
                    cy(m, (xx, y, z1 - 0.08), (xx, y + 0.07, z1 - 0.08), 0.03, 0.033, 8, ['hakuji', 'sometsuke', 'ameyu'][j])
    elif kind == 'nuno':
        n = max(2, int(w / 0.36 * dense))
        regs = ['nuno_ai', 'nuno_akane', 'nuno_koshi', 'nuno_kasuri', 'nuno_yamabuki', 'nuno_nezumi', 'nuno_wakakusa', 'nuno_shima']
        for i in range(n):
            x = x0 + w * (i + 0.5) / n
            yy = y
            for j in range(rng.randint(3, 6) if not lod else 2):
                rbx(m, (x + rng.uniform(-0.015, 0.015), yy + 0.03, z0 + dz * 0.6), (min(0.15, w / n * 0.45), 0.03, dz * 0.32), regs[(i * 3 + j) % len(regs)])
                yy += 0.06
        for i in range(max(2, int(w / 0.25)) if not lod else 2):   # 奥に立てた巻き反物
            x = x0 + 0.08 + (w - 0.16) * i / max(1, int(w / 0.25) - 1)
            m.cyl((x, y, z0 + 0.05), (x, y + 0.36, z0 + 0.05), 0.045, 0.045, 8 if not lod else 5, MK, 1.0, caps=(False, True), uv_atlas=RM[regs[(i * 5) % len(regs)]])
    elif kind == 'kanbutsu':
        n = max(2, int(w / 0.4 * dense))
        for i in range(n):
            x = x0 + w * (i + 0.5) / n
            if i % 3 == 2:                                  # 菰包みの袋
                m.abox((x, y + 0.17, z0 + dz * 0.45), (0.13, 0.17, 0.1), ST, {'*': RS['komo']})
                cy(m, (x - 0.13, y + 0.3, z0 + dz * 0.45), (x + 0.13, y + 0.3, z0 + dz * 0.45), 0.012, 0.012, 4, 'nawa')
            else:
                zaru(m, x, y, z0 + dz * 0.5, min(0.17, w / n * 0.45), lod)
                keys = [['mame', 'dou'], ['shiitake'], ['kuri'], ['himono'], ['ume'], ['togarashi']][(i * 5) % 6]
                heap(m, x, y + 0.04, z0 + dz * 0.5, min(0.14, w / n * 0.38), keys, 12 if not lod else 3, 0.026, lod, rng, 0.6)
    elif kind == 'kashi':
        n = max(2, int(w / 0.4 * dense))
        for i in range(n):
            x = x0 + w * (i + 0.5) / n
            t = i % 3
            obx(m, (x, y + 0.012, zc), (0.16, 0.012, dz * 0.42), 'shuurushi' if t else 'urushi')
            if t == 0:
                for j in range(4 if not lod else 2):
                    c = (x - 0.1 + j * 0.065, y + 0.04, zc)
                    cy(m, (c[0], c[1], c[2] - 0.08), (c[0], c[1], c[2] + 0.08), 0.003, 0.003, 3, 'take', caps=(False, False))
                    for k, kk in enumerate(('dango_p', 'dango_w', 'dango_g')):
                        ball(m, (c[0], c[1], c[2] - 0.04 + 0.04 * k), 0.018, kk, 5 if lod else 6)
            elif t == 1:
                for j in range(6 if not lod else 2):
                    cys(m, (x - 0.1 + (j % 3) * 0.1, y + 0.025 + (j // 3) * 0.012, zc - 0.05 + (j // 3) * 0.06),
                        (x - 0.1 + (j % 3) * 0.1, y + 0.037 + (j // 3) * 0.012, zc - 0.05 + (j // 3) * 0.06), 0.045, 0.045, 8, 'senbei')
            else:
                for j, k in enumerate(('ame_r', 'ame_w', 'ame_y')):
                    xx = x - 0.1 + j * 0.1
                    cy(m, (xx, y + 0.025, zc), (xx, y + 0.075, zc), 0.045, 0.05, 8 if not lod else 5, 'hakuji', caps=(True, False))
                    heap(m, xx, y + 0.06, zc, 0.035, [k], 5 if not lod else 1, 0.016, lod, rng, 0.8, st=True)
    elif kind == 'cha':
        obx(m, (x0 + w * 0.5, y + 0.012, zc), (w * 0.45, 0.012, dz * 0.42), 'urushi')
        n = max(2, int(w / 0.35))
        for i in range(n):
            x = x0 + w * (i + 0.5) / n
            if i % 3 == 0:
                ball(m, (x, y + 0.09, zc), 0.065, 'ameyu', 8 if not lod else 5, 0.8)
                cy(m, (x + 0.05, y + 0.09, zc), (x + 0.11, y + 0.13, zc), 0.012, 0.007, 4, 'ameyu')
            elif i % 3 == 1:
                for j in range(4 if not lod else 1):
                    cy(m, (x - 0.09 + j * 0.06, y + 0.025, zc + 0.04), (x - 0.09 + j * 0.06, y + 0.085, zc + 0.04), 0.024, 0.03, 8, 'hakuji')
            else:
                for j in range(3 if not lod else 1):
                    c = (x - 0.06 + j * 0.06, y + 0.04, zc)
                    for k, kk in enumerate(('dango_p', 'dango_w', 'dango_g')):
                        ball(m, (c[0], c[1], c[2] - 0.04 + 0.04 * k), 0.018, kk, 5 if lod else 6)
        for i in range(2 if not lod else 1):              # 茶壺
            x = x0 + 0.1 + i * (w - 0.2)
            cy(m, (x, y, z0 + 0.06), (x, y + 0.22, z0 + 0.06), 0.07, 0.07, 10 if not lod else 6, 'cha', caps=(False, True))
    elif kind == 'kome':
        n = max(2, int(w / 0.36 * dense))
        for i in range(n):
            x = x0 + w * (i + 0.5) / n
            if i % 2 == 0:                                  # 升に米
                m.box((x - 0.12, y, zc - 0.12), (x + 0.12, y + 0.14, zc + 0.12), WD, WOODC)
                obx(m, (x, y + 0.145, zc), (0.11, 0.01, 0.11), 'kome')
                cy(m, (x, y + 0.15, zc), (x, y + 0.19, zc), 0.08, 0.02, 8 if not lod else 5, 'kome', caps=(False, True))
            else:
                m.abox((x, y + 0.2, z0 + dz * 0.45), (0.13, 0.2, 0.11), ST, {'*': RS['komo']})
                cy(m, (x - 0.13, y + 0.32, z0 + dz * 0.45), (x + 0.13, y + 0.32, z0 + dz * 0.45), 0.012, 0.012, 4, 'nawa')
    elif kind == 'zakka':
        n = max(2, int(w / 0.36 * dense))
        for i in range(n):
            x = x0 + w * (i + 0.5) / n
            t = i % 4
            if t == 0:                                      # 笊の重ね
                for j in range(4 if not lod else 1):
                    zaru(m, x, y + j * 0.045, zc, 0.15, lod)
            elif t == 1:                                    # 草鞋の束
                u0, v0, u1, v1 = RM['straw']
                for j in range(4 if not lod else 1):
                    m.abox((x - 0.06 + (j % 2) * 0.12, y + 0.02 + (j // 2) * 0.04, zc), (0.05, 0.02, 0.12), MK, {'*': [u0, v0, u1, v1]})
            elif t == 2:                                    # 小桶
                m.cyl((x, y, zc), (x, y + 0.16, zc), 0.1, 0.12, 10 if not lod else 6, WD, AGED, caps=(True, False))
                cy(m, (x, y + 0.11, zc), (x, y + 0.13, zc), 0.123, 0.123, 8, 'tetsu', caps=(False, False))
            else:                                           # 縄の束・手箒
                for j in range(2):
                    cy(m, (x - 0.06 + j * 0.12, y, zc), (x - 0.06 + j * 0.12, y + 0.07, zc), 0.07, 0.07, 8 if not lod else 5, 'nawa')
                cy(m, (x - 0.15, y + 0.02, z1 - 0.06), (x + 0.15, y + 0.02, z1 - 0.06), 0.012, 0.012, 4, 'take')
    elif kind == 'sake':
        n = max(2, int(w / 0.32 * dense))
        for i in range(n):
            x = x0 + w * (i + 0.5) / n
            if i % 3 == 1:                                  # 菰樽（小）
                m.cyl((x, y, zc), (x, y + 0.3, zc), 0.13, 0.13, 10 if not lod else 6, ST, 1.0, caps=(False, True), uv_atlas=RS['komo'])
                cy(m, (x, y + 0.1, zc), (x, y + 0.12, zc), 0.135, 0.135, 8, 'nawa', caps=(False, False))
            else:                                           # 徳利と升
                for j in range(3 if not lod else 1):
                    xx = x - 0.08 + j * 0.08
                    k = ['hakuji', 'ameyu', 'sometsuke'][(i + j) % 3]
                    cy(m, (xx, y, zc), (xx, y + 0.11, zc), 0.035, 0.045, 8 if not lod else 5, k, caps=(True, False))
                    cy(m, (xx, y + 0.11, zc), (xx, y + 0.17, zc), 0.045, 0.012, 8 if not lod else 5, k, caps=(False, True))
                if not lod:
                    m.box((x - 0.05, y, z1 - 0.1), (x + 0.05, y + 0.05, z1 - 0.0), WD, WOODC)


BAT_W = 1.7
TRADES = ('yasai', 'seto', 'nuno', 'kanbutsu', 'kashi', 'cha', 'kome', 'zakka', 'sake')


def battari(kind, lod):
    """ばったり床几：店先の壁の下から跳ね下ろした台（幅 1.7、出 0.62、高 0.42）＋後ろに一段の雛壇（0.6）、両方に商品。原點＝壁際の接地點。"""
    m = new('ms_battari_' + kind, lod, 'ばったり床几（%s）：店先に跳ね下ろした台 1.7 × 0.62 × 0.42＋後段の雛壇 0.6、商品を 2 段に；営業中の印' % kind)
    rng = random.Random(53000 + TRADES.index(kind))
    hw = BAT_W / 2
    top = 0.42
    m.box((-hw, top - 0.04, 0.04), (hw, top, 0.64), WD, AGED)                    # 天板
    m.box((-hw, top - 0.1, 0.6), (hw, top - 0.04, 0.64), WD, OLD)                # 前框
    for x in (-hw + 0.06, hw - 0.1):                                             # 跳ね脚
        m.box((x, 0.0, 0.52), (x + 0.04, top - 0.04, 0.56), WD, OLD)
        m.box((x, 0.0, 0.06), (x + 0.04, top - 0.04, 0.1), WD, OLD)
    m.box((-hw + 0.02, 0.06, 0.05), (hw - 0.02, 0.1, 0.09), WD, OLD)             # 壁際の受け（蝶番の框）
    m.box((-hw + 0.04, top, 0.06), (hw - 0.04, 0.6, 0.24), WD, WOODC)            # 後段の雛壇
    goods(m, kind, -hw + 0.06, hw - 0.06, 0.28, 0.6, top, lod, rng)
    goods(m, kind, -hw + 0.08, hw - 0.08, 0.07, 0.23, 0.6, lod, rng, 0.8)
    return m


def naka(kind, lod):
    """店内の陳列：町家 Kit の店台（上面 0.72、壁から奥 0.25–0.65）に商品、奥の壁（−0.7）に棚板 2 段と商品。原點＝壁線・建物の基準高（base_h）。"""
    m = new('ms_naka_' + kind, lod, '店内の陳列（%s）：町家 Kit の開いた店の間の店台（0.72）に商品、奥の壁に棚 2 段（1.18／1.55）と商品' % kind)
    rng = random.Random(54000 + TRADES.index(kind))
    hw = 0.8
    goods(m, kind, -hw + 0.04, hw - 0.04, -0.62, -0.28, 0.72, lod, rng)
    for ys in (1.18, 1.55):
        m.box((-hw, ys - 0.03, -0.69), (hw, ys, -0.5), WD, AGED)
        for x in (-hw + 0.02, hw - 0.05):
            m.box((x, ys - 0.2, -0.69), (x + 0.03, ys - 0.03, -0.66), WD, OLD)
        goods(m, kind, -hw + 0.05, hw - 0.05, -0.68, -0.52, ys, lod, rng, 0.8)
    return m


def shitomi(lod):
    """蔀を揚げた：上半の蔀戸（1.8 × 0.7、格子）を吊り金で外へ跳ね上げる（原點＝壁線の蝶番、y 0）。"""
    m = new('ms_shitomi', lod, '揚げた蔀戸：格子の板戸 1.8 × 0.7 を蝶番（原點）から外へ 75° 跳ね上げ、吊り金 2 本で軒から吊る；営業中の印')
    a = math.radians(75.0)
    L = 0.7
    dirv = (0.0, math.cos(a), math.sin(a))                                       # 蝶番から外へ（y 上・z 前）
    nrm = (0.0, -math.sin(a), math.cos(a))
    hw = 0.9
    c = (0.0, dirv[1] * L * 0.5, dirv[2] * L * 0.5)
    m.obox(c, (hw, 0.018, L * 0.5), WD, OLD, ax=K.X, ay=K.norm(nrm), az=K.norm(dirv))           # 板
    nb = 7 if not lod else 3
    for i in range(nb):                                                          # 縦の格子
        x = -hw + 0.06 + (2 * hw - 0.12) * i / (nb - 1)
        m.obox((x, c[1] - nrm[1] * 0.025, c[2] - nrm[2] * 0.025), (0.018, 0.012, L * 0.5), WD, DARK, ax=K.X, ay=K.norm(nrm), az=K.norm(dirv))
    for t in (0.04, 0.5, 0.96):                                                   # 横框
        p = (0.0, dirv[1] * L * t - nrm[1] * 0.028, dirv[2] * L * t - nrm[2] * 0.028)
        m.obox(p, (hw, 0.012, 0.025), WD, DARK, ax=K.X, ay=K.norm(nrm), az=K.norm(dirv))
    tip = (0.0, dirv[1] * L, dirv[2] * L)
    for x in (-hw + 0.1, hw - 0.1):                                              # 吊り金（軒の垂木から）
        cy(m, (x, tip[1] - 0.01, tip[2] - 0.02), (x, tip[1] + 0.32, tip[2] - 0.12), 0.008, 0.008, 4, 'tetsu', caps=(False, False))
    return m


def noren_age(col, lod):
    """掀げた暖簾：水引（全幅 0.25、切れ目 3 本）＋両脇へ束ねて結んだ暖簾（上はひだの扇、結び目から下は丸く束ねた布）。
    中は開いて店内（棚と商品）が見える。原點＝壁線・竿の高さ（y 0）、幅 1.8 想定。"""
    reg = {'ai': RM['noren_mon'], 'beni': swr('akane'), 'kinari': swr('kinari')}[col]
    m = new('ms_noren_age_' + col, lod, '掀げた暖簾（%s）：竿＋水引 0.25（4 枚）＋両脇に束ねて結んだ布（ひだの扇＋丸い束、裾 −1.1）——戸口が開いて店内が見える' % col)
    hw = 0.88
    pole(m, (-hw - 0.04, 0.0, 0.03), (hw + 0.04, 0.0, 0.03), 0.014, 'take')
    npn = 4
    for i in range(npn):                                                         # 水引：4 枚（切れ目 0.02）
        xa = -hw + 2 * hw * i / npn + 0.01
        xb = -hw + 2 * hw * (i + 1) / npn - 0.01
        cloth(m, (xa, -0.26, 0.045), (xb, -0.26, 0.045), (xb, -0.01, 0.035), (xa, -0.01, 0.035), MK, reg)
    for s in (-1, 1):
        xo = s * hw                                                             # 外端（柱側）
        xi = s * (hw - 0.4)                                                     # 上端の内端
        xc = s * (hw - 0.07)                                                    # 結び目の中心
        nf = 4 if not lod else 2
        # 上：ひだの扇（竿 xo..xi → 結び目 xc ± 0.05）、ひだごとに前後へ揺らす
        for f in range(nf):
            ta, tb = f / nf, (f + 1) / nf
            xa_t = xo + (xi - xo) * ta
            xb_t = xo + (xi - xo) * tb
            xa_b = xc - s * 0.05 + s * 0.1 * ta
            xb_b = xc - s * 0.05 + s * 0.1 * tb
            za = 0.05 + (0.045 if f % 2 else 0.0)
            zb = 0.05 + (0.0 if f % 2 else 0.045)
            pts = [(xa_b, -0.62, za + 0.03), (xb_b, -0.62, zb + 0.03), (xb_t, -0.26, zb), (xa_t, -0.26, za)]
            if s > 0:
                pts = [pts[1], pts[0], pts[3], pts[2]]
            cloth(m, pts[0], pts[1], pts[2], pts[3], MK, reg, 1.0 - 0.06 * (f % 2))
        # 下：結び目から裾へ丸く束ねた布（楕円の筒、裾で少し開く）
        seg = 8 if not lod else 5
        m.cyl((xc, -0.6, 0.085), (xc - s * 0.02, -0.85, 0.09), 0.055, 0.075, seg, MK, 1.0, caps=(False, False), uv_atlas=reg)
        m.cyl((xc - s * 0.02, -0.85, 0.09), (xc - s * 0.05, -1.1, 0.1), 0.075, 0.1, seg, MK, 0.95, caps=(False, True), uv_atlas=reg)
        cy(m, (xc, -0.6, 0.085), (xc, -0.66, 0.085), 0.062, 0.062, 8 if not lod else 5, 'nawa', caps=(True, True))   # 結び紐
    return m


def tana(kind, lod):
    """戸口の間の奥の棚：店先の開いた間（奥 0.7）の奥壁に 3 段の棚（0.62／1.05／1.45）と商品、奥行 0.24。原點＝壁線・建物の基準高。"""
    m = new('ms_tana_' + kind, lod, '戸口の間の奥の棚（%s）：奥壁に 3 段の棚と商品——掀げた暖簾の向こうに品が見える' % kind)
    rng = random.Random(55000 + TRADES.index(kind))
    hw = 0.78
    z0, z1 = -0.69, -0.45
    for x in (-hw, hw - 0.04):
        m.box((x, 0.32, z0), (x + 0.04, 1.75, z0 + 0.04), WD, OLD)
        m.box((x, 0.32, z1 - 0.04), (x + 0.04, 1.75, z1), WD, OLD)
    for ys in (0.62, 1.05, 1.45):
        m.box((-hw, ys - 0.03, z0), (hw, ys, z1), WD, AGED)
        goods(m, kind, -hw + 0.05, hw - 0.05, z0 + 0.02, z1 - 0.02, ys, lod, rng, 0.9)
    return m


# ─────────────────────────── 書き出し ───────────────────────────

def build_all():
    for lod in (0, 1):
        for k in ('ai', 'beni', 'kinari', 'kaki'):
            maku(k, lod)
        for k in ('aka', 'shiro'):
            noki_chochin(k, lod)
        tsuna_chochin(lod)
        for s in (26, 37, 50):
            kido(s, lod)
        geya('dango', lod)
        geya('meshi', lod)
        endai_mousen(lod)
        tanmono_dai(lod)
        nuno_kake(lod)
        for k in ('kaki', 'waraji', 'oke'):
            tsurimono(k, lod)
        for k in TRADES:
            battari(k, lod)
            naka(k, lod)
            tana(k, lod)
        shitomi(lod)
        for k in ('ai', 'beni', 'kinari'):
            noren_age(k, lod)


def dims(m):
    xs = [p[0] for p in m.v]
    ys = [p[1] for p in m.v]
    zs = [p[2] for p in m.v]
    return [round(min(xs), 4), round(min(ys), 4), round(min(zs), 4), round(max(xs), 4), round(max(ys), 4), round(max(zs), 4)]


def main():
    K.clear_scene(bpy)
    build_all()
    bm = K.blender_mats(bpy, MATS)
    objs = []
    manifest = {}
    for name, m in MODS.items():
        ob = m.to_blender(bpy, bmats=bm)
        objs.append(ob)
        tri = sum(len(p.vertices) - 2 for p in ob.data.polygons)
        manifest[name] = {'tris': tri, 'dims': dims(m), 'mats': sorted({m.mats[f[1]] for f in m.f}), 'note': INFO[name]}
    K.export_glb(bpy, OUT + '/src/mise_kit.glb', objs)
    total = sum(v['tris'] for v in manifest.values())
    K.write_json(OUT + '/src/modules_blender.json', {
        '_note': 'build_mise_kit.py 產生；Godot prefab（tools/village_v2_machiya_kit_prefab.gd -- --kit=mise_kit）讀此表逐一轉成 mesh/<名>.res。',
        'materials': MATS, 'modules': manifest, 'total_tris': total})
    print('[MSKIT] %d 構件、合計 %d 三角面 → %s' % (len(manifest), total, OUT + '/src/mise_kit.glb'))
    for n, v in manifest.items():
        if not n.endswith('_l1'):
            print('[MSKIT]   %-22s %5d 面  LOD1 %4d  dims %s  mats %s' % (n, v['tris'], manifest[n + '_l1']['tris'], v['dims'], v['mats']))


main()

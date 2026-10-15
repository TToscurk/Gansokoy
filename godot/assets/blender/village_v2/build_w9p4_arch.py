"""人間之里 V2 P13 W9 Phase 4 R1：主街の輪郭差異化（7 棟）＋西巷（住宅）の 4 棟。

build_w9r2_arch.py が BUILDERS の直前でこのファイルを exec する（単独実行はしない）。既存 27 棟の builder・封存済み Kit・共用 helper は一字も変えない。
使用者 2026-10-16「主街建築差異化：正常 TPS で沿街を歩くだけで外観の変化が分かる。屋根・簷高・出入口・窓比例・二階形式を揃えない。
依建築用途設計、調色や貨架だけで差異化を名乗らない」。

診断（踏查 8 鏡位）：重複感の主因は屋根の種類ではなく『簷高 5.4／3.9・層高・窓列・門窓分格が同じ』こと。よって色や小物ではなく、
量体（高さ・幅・段）と屋根の輪郭を変える。用途は各棟の門前に既にある P10 の商い（StreetP10）に合わせた。

  MKT_005 雑貨の大店（P10＝雑貨の平台・桶山）：入母屋（棟は通りと平行・両端に妻）＋二階の出格子の通し＋軒提灯
  MKT_015 八百屋・青物問屋（P10＝野菜の看板・平台・箱詰め）：二重屋根（四方へ回る下屋＋内へ 0.9 m 引いた二階の寄棟）＋深い板庇
  MXC_001 旅籠（門前に商品なし）：高い棟（8.3 m）＋玄関の唐破風＋二階の出格子
  MXC_002 団子・菓子屋（P10＝団子の看板・菓子の平台・床几）：低い石置き板葺き（谷）＋深い板庇
  MXC_004 仕舞屋（列の北端）：寄棟の翼＋一段隆起した妻入の門棟（門の開口・大柱）
  MKT_001 秤屋（南入口の右手）：低い瓦の寄棟の中二階（棟 5.6 m・火見櫓の方角への抜けが開く）
  MKT_004 瀬戸物屋：低い石置き板葺き（棟 5.4 m）＝北隣 MKT_005 の入母屋の南端を歩行者に見せる

制約（W9 R2 の gate と同じ）：footprint・入口位置・body 碰撞は不変。側面の出簷は隣棟との間隔（0.18–0.20 m）以内（0.15 m）、前は庇 0.9 m 以内
（深い庇は 1.0–1.35 m の板庇だが前縁の下端 ≥ 2.0 m・P10 の竿／看板の体積を避ける）、頭の高さ帯（y 1.1–1.8）・戸口の前に何も置かない。
"""


def p4_lantern(P, x, ytop, z, r=0.16, h=0.38, col=1.0):
    """紙提灯（P＝無着色）。上端 ytop から吊る（吊り紐は円筒：垂直の beam は up ベクトルが退化するため使わない）。"""
    P.cyl((x, ytop - h, z), (x, ytop, z), r, r, 10, 'V2_Plaster', col, caps=(True, True))
    for yy in (ytop - h - 0.03, ytop):
        P.cyl((x, yy, z), (x, yy + 0.03, z), r * 0.78, r * 0.78, 10, 'V2_Wood', DARK * 0.8, caps=(True, True))
    P.cyl((x, ytop + 0.03, z), (x, ytop + 0.15, z), 0.010, 0.010, 4, 'V2_Wood', DARK * 0.55, caps=(False, False))


def _eave_ends(dst, XE, ZE, y_e):
    """軒先の垂木尻（四辺）。"""
    nx = max(3, int(round(2.0 * XE / 0.52)))
    for i in range(nx + 1):
        xx = -XE + 2.0 * XE * i / nx
        for sg in (1, -1):
            dst.box((xx - 0.035, y_e - 0.33, sg * (ZE + 0.03) - 0.07), (xx + 0.035, y_e - 0.2, sg * (ZE + 0.03) + 0.07), 'V2_Wood', DARK * 0.85, grain=Y)
    nz = max(3, int(round(2.0 * ZE / 0.52)))
    for i in range(nz + 1):
        zz = -ZE + 2.0 * ZE * i / nz
        for sx in (1, -1):
            dst.box((sx * (XE + 0.03) - 0.07, y_e - 0.33, zz - 0.035), (sx * (XE + 0.03) + 0.07, y_e - 0.2, zz + 0.035), 'V2_Wood', DARK * 0.85, grain=Y)


def _corner_caps(dst, XE, ZE, y_e, XG, YG, ZG):
    """隅棟の先端に巴瓦（丸い留め）。"""
    for sx in (1, -1):
        for sz in (1, -1):
            end = (sx * XE, y_e, sz * ZE)
            dn = norm(sub((sx * XG, YG, sz * ZG), end))
            c0 = add(end, (0.0, 0.11, 0.0))
            dst.cyl(c0, add(c0, mul(dn, -0.07)), 0.12, 0.12, 12, 'V2_Kawara', 0.52, caps=(True, True))


def hip_skirt(dst, lod, XG, ZG, YG, p, run):
    """裳階（もこし）：上端の矩形環 (±XG, ±ZG)・高さ YG から外へ run だけ下る台形 4 面の瓦屋根（四隅に降り棟）。
    軒先＝(±(XG+run), ±(ZG+run))、高さ＝YG−p·run。返り値＝軒先の高さ。"""
    XE, ZE = XG + run, ZG + run
    y_e = YG - p * run
    sec = math.sqrt(1 + p * p)
    SH = run * sec
    ll = 2 if lod else 0
    for sg in (1, -1):
        o = (0.0, YG, sg * ZG)
        dsl = norm((0.0, -p, float(sg)))
        n = norm((0.0, 1.0, p * sg))
        ax = (float(sg), 0.0, 0.0)
        I.tile_band(dst, o, ax, dsl, n, lambda s: -(XG + s / sec), lambda s: XG + s / sec, SH, KW, ll, ends=(lod == 0))
        if lod == 0:
            I.under(dst, o, ax, dsl, n, lambda s: -(XG + s / sec), lambda s: XG + s / sec, SH)
            a, b = (-XE, y_e, sg * ZE), (XE, y_e, sg * ZE)
            dst.beam(add(a, mul(n, -0.06)), add(b, mul(n, -0.06)), 0.07, 0.24, 'V2_Wood', DARK * 0.9, up=n)
    for sx in (1, -1):
        o = (sx * XG, YG, 0.0)
        dsl = norm((float(sx), -p, 0.0))
        n = norm((p * sx, 1.0, 0.0))
        ax = (0.0, 0.0, -float(sx))
        I.tile_band(dst, o, ax, dsl, n, lambda s: -(ZG + s / sec), lambda s: ZG + s / sec, SH, KW, ll, ends=(lod == 0))
        if lod == 0:
            I.under(dst, o, ax, dsl, n, lambda s: -(ZG + s / sec), lambda s: ZG + s / sec, SH)
            a, b = (sx * XE, y_e, -ZE), (sx * XE, y_e, ZE)
            dst.beam(add(a, mul(n, -0.06)), add(b, mul(n, -0.06)), 0.07, 0.24, 'V2_Wood', DARK * 0.9, up=n)
        for sz in (1, -1):
            I.hip_ridge(dst, (sx * XG, YG, sz * ZG), (sx * XE, y_e, sz * ZE), lod, w=0.28, h=0.18)
    if lod == 0:
        _corner_caps(dst, XE, ZE, y_e, XG, YG, ZG)
        _eave_ends(dst, XE, ZE, y_e)
    return y_e


def irimoya_roof(dst, lod, HA, HB, y_wall, p, ove, run, ovg=0.25, gw=None):
    """入母屋（棟は x 方向）：上半は切妻（妻は壁面より run だけ内側）、下半は四方へ広がる寄棟。壁頂 y_wall を通る一枚勾配 p。
    HA／HB＝壁の半長／半幅、ove＝軒の出（四辺同じ）、run＝降り棟の水平長さ、ovg＝妻の破風板の出、gw＝妻壁を描く先（壁グループ＝FIN 色が掛かる）。
    返り値＝棟高。寺子屋（P5）の main_roof と同じ構成を、W9 の Kit 瓦・棟・鬼瓦・懸魚でパラメータ化して組み直した。"""
    gw = dst if gw is None else gw
    XE, ZE = HA + ove, HB + ove
    y_e = y_wall - p * ove
    YR = y_e + p * ZE
    XG, ZG = XE - run, ZE - run
    YG = y_e + p * run
    XT = XG + ovg
    sec = math.sqrt(1 + p * p)
    SF, SG, SH = ZE * sec, ZG * sec, run * sec
    ll = 2 if lod else 0
    for sg in (1, -1):
        o = (0.0, YR, 0.0)
        dsl = norm((0.0, -p, float(sg)))
        n = norm((0.0, 1.0, p * sg))
        ax = (float(sg), 0.0, 0.0)
        I.tile_band(dst, o, ax, dsl, n, lambda s: -XT, lambda s: XT, SF, KW, ll, s_range=(0.0, SG), ends=False)
        I.tile_band(dst, o, ax, dsl, n, lambda s: -(XE - ZE + s / sec), lambda s: XE - ZE + s / sec, SF, KW, ll, s_range=(SG, SF), ends=(lod == 0))
        if lod == 0:
            I.under(dst, o, ax, dsl, n, lambda s: -XT, lambda s: XT, SG)
            o2 = add(o, mul(dsl, SG))
            I.under(dst, o2, ax, dsl, n, lambda s: -(XG + s / sec), lambda s: XG + s / sec, SF - SG)
            a, b = (-XE, y_e, sg * ZE), (XE, y_e, sg * ZE)
            dst.beam(add(a, mul(n, -0.06)), add(b, mul(n, -0.06)), 0.07, 0.24, 'V2_Wood', DARK * 0.9, up=n)
    for sx in (1, -1):
        o = (sx * XG, YG, 0.0)
        dsl = norm((float(sx), -p, 0.0))
        n = norm((p * sx, 1.0, 0.0))
        ax = (0.0, 0.0, -float(sx))
        I.tile_band(dst, o, ax, dsl, n, lambda s: -(ZG + s / sec), lambda s: ZG + s / sec, SH, KW, ll, ends=(lod == 0))
        if lod == 0:
            I.under(dst, o, ax, dsl, n, lambda s: -(ZG + s / sec), lambda s: ZG + s / sec, SH)
            a, b = (sx * XE, y_e, -ZE), (sx * XE, y_e, ZE)
            dst.beam(add(a, mul(n, -0.06)), add(b, mul(n, -0.06)), 0.07, 0.24, 'V2_Wood', DARK * 0.9, up=n)
        # 妻（破風面の三角）：漆喰＋梁・束・貫、水切り
        polyo(gw, [(sx * XG, YG, -ZG), (sx * XG, YG, ZG), (sx * XG, YR - 0.05, 0.0)], 'V2_Plaster', PL, out=(float(sx), 0.0, 0.0), grain=Y)
        if lod == 0:
            xa, xb = sorted((sx * (XG - 0.02), sx * (XG + 0.07)))
            gw.box((xa, YG, -ZG), (xb, YG + 0.15, ZG), 'V2_Wood', DARK, grain=Z)                                   # 梁
            yh = YG + 0.62
            zh = ZG * (1.0 - 0.62 / (YR - YG))
            gw.box((xa, yh, -zh), (xb, yh + 0.07, zh), 'V2_Wood', DARK, grain=Z)                                    # 貫
            gw.box((xa, YG, -0.045), (xb, YR - 0.30, 0.045), 'V2_Wood', DARK, grain=Y)                             # 束
            x0_, x1_ = sorted((sx * (XG - 0.02), sx * (XG + 0.14)))
            dst.box((x0_, YG - 0.04, -ZG), (x1_, YG + 0.10, ZG), 'V2_Wood', DARK * 0.9, grain=Z)                    # 水切り（下屋との取り合い）
            for sz in (1, -1):
                dst.beam((sx * (XT + 0.04), YR - 0.10, 0.0), (sx * (XT + 0.04), YG - 0.10, sz * (ZG + 0.08)), 0.08, 0.36, 'V2_Wood', DARK * 0.85, up=Y)   # 破風板
        for sz in (1, -1):
            I.hip_ridge(dst, (sx * XG, YG, sz * ZG), (sx * XE, y_e, sz * ZE), lod, w=0.28, h=0.18)             # 隅棟（下半の寄棟）
    Lr = 2.0 * XT
    if lod == 0:
        t = tmp()
        put(t, cached(('rg',), lambda: NS['ridge_unit']()), sx=(Lr - 2.0 * ONI_IN) / RU)
        put(dst, t, off=(-Lr * 0.5 + ONI_IN, YR - 0.03, 0.0))
        for e in (-1.0, 1.0):
            put(dst, cached(('oni',), lambda: NS['oni']()), off=(e * (Lr * 0.5 - ONI_IN), YR - 0.03, 0.0))
            put(dst, cached(('gyo',), lambda: NS['gegyo']()), off=(e * (XT - VERGE_IN), YR - 0.02, 0.0), rot=e * math.pi * 0.5)
        _corner_caps(dst, XE, ZE, y_e, XG, YG, ZG)
        _eave_ends(dst, XE, ZE, y_e)
        _rec('roof', kind='irimoya', ridge_stack=True, oni=True, hip_caps=4, eave_tails=True, gegyo=True, ove=ove)
    else:
        dst.box((-XT, YR - 0.02, -0.12), (XT, YR + 0.18, 0.12), 'V2_Kawara', 0.66, grain=X)
    return YR


def karahafu_porch(R, lod, cx, Bh, y_e, H, z0, z1):
    """唐破風の玄関屋根（棟は壁と直角）。cx＝中心 x、Bh＝半幅、y_e＝両端の高さ、H＝中央の盛り上がり、z0＝壁側（壁に差し込む）、z1＝前縁。
    前縁板は atlas の無地の暗い木色。lod0 のみ（LOD1 は 500 tri 上限のため省く）。"""
    if lod:
        return
    u, v = SW['#4A3526']
    I.karahafu(R, lod, cx, Bh, y_e, H, z0, z1, (u - 0.004, v - 0.004, u + 0.004, v + 0.004), AM)


def _shell(B, W, YE, col_side=1.0, side_grain=Z):
    """左右・背面の壁（厚 0.10）。全高 YE まで。"""
    w, zf = B.w, B.zf
    for sx in (-1.0, 1.0):
        xo, xi = sx * w / 2, sx * (w / 2 - 0.10)
        W.box((min(xo, xi), FL, -zf), (max(xo, xi), YE, zf), 'V2_Plaster', PL * col_side, grain=side_grain)
    W.box((-w / 2, FL, -zf), (w / 2, YE, -zf + 0.10), 'V2_Plaster', PL * col_side, grain=X)


# ───────────────────────── 建物ごとの組立 ─────────────────────────

def build_mkt005():
    """B_P_MKT_005 雑貨の大店（Phase 4）：入母屋の大屋根（棟 8.0 m・両端に妻・四方へ降り棟）＋二階の出格子の通し＋玄関の暖簾＋軒提灯。
    隣（左の竹籠工房 6.15 m、右の二階 7.86 m）の切妻の列の中で、屋根の頂が短く、裾が四方へ広がる輪郭。入口＝x −2.64..−0.88。"""
    B = Bld('B_P_MKT_005', 8.7998, 10.92, 5.35, fin=1, tone=2)
    w, zf = B.w, B.zf
    YE = 5.35
    wn = w / 5.0
    bays1 = [('shop_k', wn), ('shop_o', wn), ('koshi', wn), ('shop_k', wn), ('koshir', wn)]
    for lod in (0, 1):
        W, R, PR = B.W[lod], B.R[lod], B.P[lod]
        irimoya_roof(R, lod, w / 2, zf, YE, 0.48, 0.15, 1.9, 0.26, gw=W)
        eave_roof(R, lod, -w / 2 + 0.02, w / 2 - 0.02, 2.85, zf, 0.85, p=0.32, style='tile')
        if lod == 1:
            W.box((-w / 2, FL, -zf), (w / 2, YE, zf), 'V2_Plaster', PL, grain=Y)
            continue
        assert abs(row1p(B, W, -w / 2, bays1) - w / 2) < 0.02
        W.box((-w / 2, 2.88, zf - 0.10), (w / 2, 3.08, zf + 0.12), 'V2_Wood', DARK * 0.9, grain=X)       # 二階の床の見付（出桁）
        W.box((-w / 2, 3.08, zf - 0.10), (w / 2, YE, zf), 'V2_Plaster', PL, grain=X)                     # 二階の前壁
        W.box((-w / 2 - 0.02, 5.02, zf - 0.04), (w / 2 + 0.02, 5.18, zf + 0.07), 'V2_Wood', DARK, grain=X)    # 軒桁
        for i in (0, 2, 3, 4):                                                                          # 二階の出格子（玄関の真上だけ障子）
            xa = -w / 2 + wn * i
            deguchi(W, xa + 0.14, xa + wn - 0.14, 3.60, 4.90, zf, out=0.34)
        xa = -w / 2 + wn
        shoji_bay(W, xa + 0.36, xa + wn - 0.36, 3.75, 4.75, zf + 0.05, frame=DARK)
        _shell(B, W, YE)
        cloth(W, xa + 0.14, xa + wn - 0.14, 2.25, 1.55, zf + 0.04, 'noren_e', seg_w=0.86, billow=0.03, rod=True)       # 玄関の暖簾
        for xl in (-3.0, 0.0, 3.2):                                                                       # 軒提灯（庇の内側から吊る・下端 2.1 m 以上）
            p4_lantern(PR, xl, 2.55, zf + 0.45)
    B.finish()
    return B


def build_mkt015():
    """B_P_MKT_015 八百屋・青物問屋（Phase 4）：二重屋根。一階（3.14 m）の上に四方へ回る裳階、その内側へ 0.9 m 引いた二階が載り、
    頂の寄棟は棟が奥行き方向（通りへ寄棟の端を向ける）。階段状に重なる輪郭＋深い板庇（野菜の日除け）。入口＝x −2.64..−0.88。"""
    B = Bld('B_P_MKT_015', 8.8062, 10.92, 3.14, fin=2, tone=1)
    w, zf = B.w, B.zf
    ins, Y1, YT, YE2 = 0.9, 3.14, 3.50, 5.55
    HA2, HB2 = w / 2 - ins, zf - ins
    wn = w / 5.0
    bays1 = [('koshib', wn), ('shop_o', wn), ('shop_k', wn), ('shop_c', wn), ('koshib', wn)]
    bays2 = [('winb', HA2 / 2), ('win', HA2 / 2), ('win', HA2 / 2), ('winb', HA2 / 2)]          # 二階の幅 2·HA2 ＝ 4 開間
    for lod in (0, 1):
        W, R, PR = B.W[lod], B.R[lod], B.P[lod]
        hip_skirt(R, lod, HA2, HB2, YT, 0.40, 0.15 + ins)
        tm = tmp()
        hip_roof(tm, lod, HB2, HA2, YE2, 0.52, 0.45)
        put(R, tm, rot=math.pi * 0.5)
        if lod == 1:
            W.box((-w / 2, FL, -zf), (w / 2, Y1, zf), 'V2_Plaster', PL, grain=Y)
            W.box((-HA2, YT, -HB2), (HA2, YE2, HB2), 'V2_Plaster', PL, grain=Y)
            continue
        eave_roof(R, lod, -w / 2 + 0.02, 3.85, 2.62, zf, 1.0, p=0.25, style='board')           # 野菜の日除け（右端の幟の竿を避ける）
        assert abs(row1p(B, W, -w / 2, bays1) - w / 2) < 0.02
        W.box((-w / 2, 2.88, zf - 0.10), (w / 2, Y1, zf + 0.04), 'V2_Plaster', PL, grain=X)       # 一階の上の帯（裳階の取り付き）
        _shell(B, W, Y1)
        # 二階（内側へ 0.9 m 引いた箱）：前面は Kit の窓開間、側面・背面は漆喰の壁
        assert abs(row2p(B, W, -HA2, bays2, YT, YE2, dz=-ins) - HA2) < 0.02
        for sx in (-1.0, 1.0):
            xo, xi = sx * HA2, sx * (HA2 - 0.10)
            W.box((min(xo, xi), YT, -HB2), (max(xo, xi), YE2, HB2), 'V2_Plaster', PL, grain=Z)
        W.box((-HA2, YT, -HB2), (HA2, YE2, -HB2 + 0.10), 'V2_Plaster', PL, grain=X)
        W.box((-HA2 - 0.03, YT - 0.06, zf - ins - 0.04), (HA2 + 0.03, YT + 0.08, zf - ins + 0.05), 'V2_Wood', DARK, grain=X)   # 二階の土台（裳階の上端）
        xb0 = -w / 2 + wn
        cloth(W, xb0 + 0.12, xb0 + wn - 0.12, 2.25, 1.55, zf + 0.04, 'noren_d', seg_w=0.86, billow=0.03, rod=True)
    B.finish()
    return B


def build_mxc001():
    """B_P_MXC_001 旅籠（Phase 4・門前に商品なし）：高い棟（8.3 m。左右の低い隣より約 3 m 高い）＋玄関の唐破風＋二階の出格子の通し。
    一階は腰屋根、玄関だけ唐破風で受ける。入口＝x −0.44..1.31。"""
    B = Bld('B_P_MXC_001', 6.1006, 10.92, 5.6, fin=4, tone=0)
    w, zf = B.w, B.zf
    YE = 5.6
    x0 = -w / 2
    bays1 = [('koshib', 1.3074), ('shop_k', 1.3074), ('shop_o', 1.743), ('koshir', 1.7428)]
    bays2 = [('winb', 1.3074), ('win', 1.3074), ('wins', 1.743), ('winb', 1.7428)]
    for lod in (0, 1):
        W, R, PR = B.W[lod], B.R[lod], B.P[lod]
        gable_on_body(B, lod, YE, 0.50, 0.15, 0.15, False)
        if lod == 1:
            W.box((-w / 2, FL, -zf), (w / 2, YE, zf), 'V2_Plaster', PL, grain=Y)
            continue
        karahafu_porch(R, lod, 0.436, 1.35, 2.95, 0.45, zf - 0.10, zf + 0.78)
        eave_roof(R, lod, -2.85, -0.95, 3.05, zf, 0.55, p=0.30, style='tile')          # 玄関の左右の腰屋根（左端の幟の竿を避ける）
        eave_roof(R, lod, 1.85, w / 2 - 0.02, 3.05, zf, 0.55, p=0.30, style='tile')
        assert abs(row1p(B, W, x0, bays1) - w / 2) < 0.02
        W.box((-w / 2, 2.88, zf - 0.10), (w / 2, 3.56, zf + 0.03), 'V2_Plaster', PL, grain=X)         # 一階と二階の間の壁
        W.box((-w / 2 - 0.02, 3.46, zf - 0.06), (w / 2 + 0.02, 3.62, zf + 0.12), 'V2_Wood', DARK * 0.9, grain=X)   # 二階の床の見付
        assert abs(row2p(B, W, x0, bays2, 3.6, YE) - w / 2) < 0.02
        _shell(B, W, YE)
        for sx in (-1.0, 1.0):                                                                          # 高い側壁の連子窓（隣の屋根の上に見える）
            side_window(W, sx * w / 2, sx, 0.0, 4.55, 5.20, ww=1.1)
        for xl in (-1.55, 2.25):                                                                         # 玄関の脇の提灯（唐破風の外・下端 2.2 m 以上）
            p4_lantern(PR, xl, 2.75, zf + 0.34)
    B.finish()
    return B


def build_mxc002():
    """B_P_MXC_002 団子・菓子屋（Phase 4）：低い石置き板葺きの切妻平入（棟 5.3 m）。左右の瓦の二階（7.5 m／8.3 m）の間に落ちる『谷』＋
    前に 1.35 m 出た深い板庇（床几と菓子の平台の日除け）。入口＝x −1.75..0。"""
    B = Bld('B_P_MXC_002', 6.9976, 10.92, 3.7, hk='h27', fin=0, tone=0)
    w, zf = B.w, B.zf
    YE = 3.7
    wn = w / 4.0
    bays1 = [('koshir', wn), ('shop_o', wn), ('shop_k', wn), ('koshir', wn)]
    bays2 = [('mushib', wn), ('mushib', wn), ('mushib', wn), ('mushib', wn)]
    for lod in (0, 1):
        W, R, PR = B.W[lod], B.R[lod], B.P[lod]
        tm = tmp()
        H = board_roof(tm, lod, w, zf, YE, 0.30, 0.30, 0.12)                                               # 軒の出 0.30 m：P10 の幟の竿（右端・壁から 0.7 m）に軒先が触れない
        put(R, tm)
        for sx in (-1.0, 1.0):
            polyo(W, [(sx * w / 2, YE, -zf), (sx * w / 2, YE, zf), (sx * w / 2, H - 0.03, 0.0)], 'V2_Wood', BOARD * 0.68, out=(sx, 0.0, 0.0), grain=Y)
        if lod == 1:
            W.box((-w / 2, FL, -zf), (w / 2, YE, zf), 'V2_Plaster', PL, grain=Y)
            continue
        eave_roof(R, lod, -1.9, 3.0, 2.85, zf, 1.35, p=0.28, style='board', strut=True)             # 深い板庇（左の提灯の柱・右の幟の竿を避ける）
        assert abs(row1p(B, W, -w / 2, bays1) - w / 2) < 0.02
        W.box((-w / 2, 2.62, zf - 0.10), (w / 2, YE, zf), 'V2_Plaster', PL, grain=X)               # 一階の上の壁（蟲籠窓）
        assert abs(row2p(B, W, -w / 2, bays2, 2.7, YE) - w / 2) < 0.02
        W.box((-w / 2 - 0.02, YE - 0.16, zf - 0.04), (w / 2 + 0.02, YE - 0.02, zf + 0.08), 'V2_Wood', DARK, grain=X)   # 桁
        for sx in (-1.0, 1.0):                                                                          # 側面・背面は下見板張り＋柱・貫
            xo, xi = sx * w / 2, sx * (w / 2 - 0.12)
            xlo, xhi = min(xo, xi), max(xo, xi)
            W.box((xlo, FL, -zf), (xhi, YE, zf), 'V2_Wood', BOARD * 0.72, grain=Z)
            for zz in (-zf + 0.08, -1.8, 1.8, zf - 0.08):
                W.box((xlo - 0.02, FL, zz - 0.06), (xhi + 0.02, YE + 0.04, zz + 0.06), 'V2_Wood', DARK, grain=Y)
            W.box((xlo - 0.02, 1.08, -zf), (xhi + 0.02, 1.16, zf), 'V2_Wood', DARK, grain=Z)
        W.box((-w / 2, FL, -zf), (w / 2, YE, -zf + 0.12), 'V2_Wood', BOARD * 0.72, grain=X)
        cloth(W, -wn + 0.12, -0.12, 2.25, 1.55, zf + 0.04, 'noren_b', seg_w=0.8, billow=0.03, rod=True)
    B.finish()
    return B


def build_mxc004():
    """B_P_MXC_004 仕舞屋・門構え（Phase 4・列の北端）：寄棟の低い翼（左）＋一段隆起した妻入の門棟（右・壁頂 4.9 m・棟 6.1 m・前へ 0.45 m 出る）。
    門の開口（幅 1.5 m・高 2.55 m）＋大柱＋太い鴨居＋奥の暗がり。入口（門）＝x 0.44..2.20。左は隣が無い＝側面が見える。"""
    B = Bld('B_P_MXC_004', 7.9000, 10.92, 2.9, fin=3, tone=0)
    w, zf = B.w, B.zf
    gx0, gx1 = -0.45, w / 2                       # 門棟 x −0.45..3.95
    ox0, ox1 = 0.567, 2.067                       # 門の開口（Kit の戸口 0.44..2.20 の中）
    YW, YG, YO = 2.9, 4.9, 2.55
    ww = gx0 - (-w / 2)                           # 左の翼の幅 3.5 m
    for lod in (0, 1):
        W, R, PR = B.W[lod], B.R[lod], B.P[lod]
        tm = tmp()
        hip_roof(tm, lod, zf, ww / 2, YW, 0.40, 0.30)                                                  # 翼＝寄棟（棟は奥行き方向）
        put(R, tm, off=(-w / 2 + ww / 2, 0.0, 0.0), rot=math.pi * 0.5)
        tg = tmp()
        gable_roof(tg, lod, 2 * zf, (gx1 - gx0) / 2, YG, 0.50, 0.15, 0.45, tsuma=True, oni=True, gyo=True)   # 門棟＝妻入
        put(R, tg, off=((gx0 + gx1) / 2, 0.0, 0.0), rot=-math.pi * 0.5)
        if lod == 1:
            W.box((-w / 2, FL, -zf), (gx0, YW, zf), 'V2_Plaster', PL, grain=Y)
            W.box((gx0, FL, -zf), (gx1, YG, zf), 'V2_Plaster', PL, grain=Y)
            continue
        assert abs(row1p(B, W, -w / 2, [('mado', 1.75), ('mado', 1.75)]) - gx0) < 0.02       # 翼の前面＝格子窓 2
        # 翼の側面（左・見える）・背面
        W.box((-w / 2, FL, -zf), (-w / 2 + 0.10, YW, zf), 'V2_Plaster', PL, grain=Z)
        W.box((-w / 2, FL, -zf), (gx0, YW, -zf + 0.10), 'V2_Plaster', PL, grain=X)
        namako_side(W, -zf, zf, FL, 1.0, -w / 2, -1.0)
        side_window(W, -w / 2, -1.0, -2.3, 1.25, 2.10, ww=1.0)
        side_window(W, -w / 2, -1.0, 2.1, 1.25, 2.10, ww=1.0)
        # 門棟の前面：開口の左右は海鼠壁の腰、開口の上は漆喰の壁＋連子窓、右は格子窓
        W.box((gx0, YW - 0.30, zf - 0.10), (gx1, YG, zf), 'V2_Plaster', PL, grain=X)
        W.box((gx0, FL, zf - 0.10), (ox0, YO, zf), 'V2_Plaster', PL, grain=X)
        W.box((ox1, FL, zf - 0.10), (gx1, YO, zf), 'V2_Plaster', PL, grain=X)
        namako(W, gx0 + 0.04, ox0 - 0.02, FL, 1.0, zf + 0.004)
        namako(W, ox1 + 0.02, gx1 - 0.04, FL, 1.0, zf + 0.004)
        louver_window(W, 2.40, 3.60, 1.35, 2.15, zf - 0.02, n=6)
        louver_window(W, 0.75, 1.85, 3.35, 3.95, zf - 0.02, n=4)
        W.box((gx0 - 0.04, 2.78, zf - 0.02), (gx1 + 0.04, 2.90, zf + 0.06), 'V2_Wood', DARK * 0.9, grain=X)       # 翼との取り合い（見切り）
        # 門棟の側壁（左は翼の屋根の上に見える・右は外）と背面
        W.box((gx0, YW, -zf), (gx0 + 0.10, YG, zf), 'V2_Plaster', PL, grain=Z)
        W.box((gx1 - 0.10, FL, -zf), (gx1, YG, zf), 'V2_Plaster', PL, grain=Z)
        W.box((gx0, FL, -zf), (gx1, YG, -zf + 0.10), 'V2_Plaster', PL, grain=X)
        # 門：大柱・鴨居・冠木、奥の暗がり、開いた観音扉
        for xp in (ox0 - 0.10, ox1 + 0.10):
            W.box((xp - 0.15, FL, zf - 0.06), (xp + 0.15, YO + 0.2, zf + 0.12), 'V2_Wood', DARK, grain=Y)
            W.box((xp - 0.22, 0.0, zf - 0.12), (xp + 0.22, 0.20, zf + 0.18), 'V2_KitStoneTri', 0.8)
        W.box((ox0 - 0.28, YO, zf - 0.10), (ox1 + 0.28, YO + 0.22, zf + 0.16), 'V2_Wood', DARK, grain=X)             # 鴨居
        W.box((ox0 - 0.36, YO + 0.30, zf - 0.08), (ox1 + 0.36, YO + 0.46, zf + 0.12), 'V2_Wood', DARK * 0.9, grain=X)   # 冠木
        W.box((ox0, FL, zf - 1.5), (ox1, YO, zf - 1.46), 'V2_Wood', 0.10, grain=X)                                  # 門の奥（暗い裏）
        W.box((ox0, FL, zf - 1.5), (ox0 + 0.04, YO, zf), 'V2_Wood', DARK * 0.4, grain=Z)
        W.box((ox1 - 0.04, FL, zf - 1.5), (ox1, YO, zf), 'V2_Wood', DARK * 0.4, grain=Z)
        W.box((ox0, YO - 0.04, zf - 1.5), (ox1, YO, zf), 'V2_Wood', DARK * 0.4, grain=X)
        W.box((ox0, FL, zf - 1.5), (ox1, FL + 0.03, zf), 'V2_KitStoneTri', 0.45)                                   # 土間
        W.box((ox0 - 0.02, FL, zf - 0.55), (ox0 + 0.06, YO - 0.1, zf - 0.08), 'V2_Wood', DARK * 0.8, grain=Z)       # 観音扉（開いて壁に付く）
        W.box((ox1 - 0.06, FL, zf - 0.55), (ox1 + 0.02, YO - 0.1, zf - 0.08), 'V2_Wood', DARK * 0.8, grain=Z)
        p4_lantern(PR, ox0 + 0.75, YO + 0.0, zf + 0.12, r=0.15, h=0.35)
    B.finish()
    return B


def _board_sides(W, w, zf, YE):
    """下見板張りの側壁・背面（柱・貫つき）。MXC_002 と同じ構成を低い店に使い回す。"""
    for sx in (-1.0, 1.0):
        xo, xi = sx * w / 2, sx * (w / 2 - 0.12)
        xlo, xhi = min(xo, xi), max(xo, xi)
        W.box((xlo, FL, -zf), (xhi, YE, zf), 'V2_Wood', BOARD * 0.72, grain=Z)
        for zz in (-zf + 0.08, -1.8, 1.8, zf - 0.08):
            W.box((xlo - 0.02, FL, zz - 0.06), (xhi + 0.02, YE + 0.04, zz + 0.06), 'V2_Wood', DARK, grain=Y)
        W.box((xlo - 0.02, 1.08, -zf), (xhi + 0.02, 1.16, zf), 'V2_Wood', DARK, grain=Z)
    W.box((-w / 2, FL, -zf), (w / 2, YE, -zf + 0.12), 'V2_Wood', BOARD * 0.72, grain=X)


def build_mkt001():
    """B_P_MKT_001 秤屋・乾物の店（Phase 4）：南入口の右手に立つ、低い瓦の寄棟の中二階（棟 5.6 m・隣の二階は 7.5–7.9 m）。
    棟は奥行き方向＝通りへ寄棟の端を向ける『帽子』の輪郭。二階は低い虫籠窓、一階は瓦の庇を深めにする。
    門から見たとき、これまで 7.86 m の屋根の壁だった南入口の右手が低く開き、火見櫓の方角への抜けも広がる。入口＝x 0.52..2.28。"""
    B = Bld('B_P_MKT_001', 7.0, 10.92, 4.1, hk='h27', fin=2, tone=1)
    w, zf = B.w, B.zf
    YE = 4.1
    bays1 = [('shop_k', 2.01), ('koshir', 2.01), ('shop_o', 1.76), ('koshib', 1.22)]
    bays2 = [('mushib', 2.01), ('mushi', 2.01), ('mushi', 1.76), ('mushib', 1.22)]
    for lod in (0, 1):
        W, R, PR = B.W[lod], B.R[lod], B.P[lod]
        tm = tmp()
        hip_roof(tm, lod, zf, w / 2, YE, 0.42, 0.40)                                   # 棟は奥行き方向（通りへ寄棟の端）
        put(R, tm, rot=math.pi * 0.5)
        if lod == 1:
            W.box((-w / 2, FL, -zf), (w / 2, YE, zf), 'V2_Plaster', PL, grain=Y)
            continue
        eave_roof(R, lod, -w / 2 + 0.02, w / 2 - 0.02, 2.80, zf, 0.95, p=0.30, style='tile', strut=True)
        assert abs(row1p(B, W, -w / 2, bays1) - w / 2) < 0.02
        W.box((-w / 2, 2.72, zf - 0.10), (w / 2, YE, zf), 'V2_Plaster', PL, grain=X)       # 一階の上の壁（低い中二階）
        assert abs(row2p(B, W, -w / 2, bays2, 2.8, YE) - w / 2) < 0.02
        W.box((-w / 2 - 0.02, YE - 0.16, zf - 0.04), (w / 2 + 0.02, YE - 0.02, zf + 0.07), 'V2_Wood', DARK, grain=X)   # 桁
        _shell(B, W, YE)
        cloth(W, 0.52 + 0.12, 2.28 - 0.12, 2.35, 1.6, zf + 0.04, 'noren_a', seg_w=0.86, billow=0.03, rod=True)
    B.finish()
    return B


def build_mkt004():
    """B_P_MKT_004 瀬戸物屋（Phase 4）：南の隣（MKT_003＝6.15 m）と北の隣（MKT_005＝入母屋）の間に、棟 5.4 m の石置き板葺きの低い店を挟む。
    これまで 7.86 m の壁だった MKT_005 の入母屋の南端（寄棟の裾と妻）が南から歩いてくる人に見えるようになる＝両方の輪郭が読める。
    下見板張りの低い二階（虫籠窓）＋1.0 m の板庇。前の陳列台（P10＝x −0.55..1.42）と桶山には触れない。入口＝x 1.30..3.05（Kit の shop_o と同じ）。"""
    B = Bld('B_P_MKT_004', 6.1, 10.92, 3.7, hk='h27', fin=0, tone=0)
    w, zf = B.w, B.zf
    YE = 3.7
    bays1 = [('koshib', 0.8), ('shop_k', 1.5), ('koshir', 2.05), ('shop_o', 1.75)]
    bays2 = [('mushib', 0.8), ('mushi', 1.5), ('mushi', 1.025), ('mushi', 1.025), ('mushi', 1.75)]
    for lod in (0, 1):
        W, R, PR = B.W[lod], B.R[lod], B.P[lod]
        tm = tmp()
        H = board_roof(tm, lod, w, zf, YE, 0.34, 0.45, 0.12)
        put(R, tm)
        for sx in (-1.0, 1.0):
            polyo(W, [(sx * w / 2, YE, -zf), (sx * w / 2, YE, zf), (sx * w / 2, H - 0.03, 0.0)], 'V2_Wood', BOARD * 0.68, out=(sx, 0.0, 0.0), grain=Y)
        if lod == 1:
            W.box((-w / 2, FL, -zf), (w / 2, YE, zf), 'V2_Plaster', PL, grain=Y)
            continue
        eave_roof(R, lod, -w / 2 + 0.02, w / 2 - 0.02, 2.62, zf, 1.0, p=0.28, style='board', strut=True)
        assert abs(row1p(B, W, -w / 2, bays1) - w / 2) < 0.02
        W.box((-w / 2, 2.55, zf - 0.10), (w / 2, YE, zf), 'V2_Plaster', PL, grain=X)
        assert abs(row2p(B, W, -w / 2, bays2, 2.6, YE) - w / 2) < 0.02
        W.box((-w / 2 - 0.02, YE - 0.16, zf - 0.04), (w / 2 + 0.02, YE - 0.02, zf + 0.08), 'V2_Wood', DARK, grain=X)
        _board_sides(W, w, zf, YE)
        cloth(W, 1.30 + 0.12, 3.05 - 0.12, 2.25, 1.55, zf + 0.04, 'noren_c', seg_w=0.86, billow=0.03, rod=True)
    B.finish()
    return B


# ───────────────────────── 西巷（WestAlley・住宅）の 4 棟（Phase 4 B）─────────────────────────
# 巷の東列 024｜025｜026 は隣り合う同じ寸法の平屋〜厨子で、屋根の高さ・形・素材が揃って見えた（5.36／5.36／6.36 m・瓦の切妻平入）。
# 東列を『横に広い瓦の入母屋（名主）｜低い板葺き（貧しい家）｜細長く高い妻入のせり出し二階（仕立て屋）』にし、西列の 012 は越屋根の寄棟の農家にする。
# 巷幅 3 m で戸口の前が狭いので、庇は短く（≤ 0.8 m・前縁の下端 ≥ 2.05 m）、深い庇は掛けない（RSW_047 の教訓）。

def build_rsw024():
    """B_P_RSW_024 名主の家（Phase 4 B）：横に広い瓦の入母屋の平屋（壁 3.5 m・棟 約 5.9 m）＋玄関の唐破風＋縁側の障子 3 間。巷の東列（隣は板葺きの低い家と
    妻入の細長い家）の中で、この家だけが『横に広い入母屋』の輪郭をつくる。入口＝x 0.45..2.25（Kit の戸口と同じ）。"""
    B = Bld('B_P_RSW_024', 8.1, 10.92, 3.5, fin=4, tone=1)
    w, zf = B.w, B.zf
    YE = 3.5
    xd0 = 0.45
    for lod in (0, 1):
        W, R, PR = B.W[lod], B.R[lod], B.P[lod]
        irimoya_roof(R, lod, w / 2, zf, YE, 0.40, 0.50, 1.4, 0.22, gw=W)                                 # 壁 3.5 m・軒の出 0.5 m・勾配 0.40 → 軒先 3.3 m（相機の最大 2.9 m より上）
        if lod == 1:
            W.box((-w / 2, FL, -zf), (w / 2, YE, zf), 'V2_Plaster', PL, grain=Y)
            continue
        karahafu_porch(R, lod, 1.35, 1.10, 3.10, 0.40, zf - 0.10, zf + 0.55)                               # 玄関の唐破風：前縁 3.0 m 以上・出 0.55 m（相機が壁際で玄関の前に来ても庇が頭より上）
        assert abs(row1p(B, W, xd0, [('door', 1.8), ('koshir', 1.8)]) - w / 2) < 0.02
        W.box((xd0, 2.84, zf - 0.02), (w / 2, YE, zf), 'V2_Plaster', PL, grain=X)                    # 戸口の上（Kit の高さ 2.9 m と壁頂 3.5 m の継ぎ）
        wb = (xd0 + w / 2) / 3.0                                                                      # 戸口の左：障子 3 間（縁側）
        xl = -w / 2
        for k in range(3):
            xa, xb = xl + k * (xd0 - xl) / 3.0, xl + (k + 1) * (xd0 - xl) / 3.0
            W.box((xa, FL, zf - 0.02), (xb, 0.95, zf), 'V2_Wood', BOARD, grain=X)
            shoji_bay(W, xa, xb, 0.95, 2.45, zf)
        W.box((xl, 2.45, zf - 0.05), (xd0, YE, zf), 'V2_Plaster', PL, grain=X)
        engawa(W, xl + 0.10, xd0 - 0.34, zf, 0.5, 0.55)                                                  # 戸口の淨空帯（戸口幅＋0.05 m）に縁側を掛けない
        _shell(B, W, YE)
        for sx in (-1.0, 1.0):                                                                          # 宅間から見える側面の窓
            side_window(W, sx * w / 2, sx, -1.4, 1.2, 2.2, ww=0.9)
            side_window(W, sx * w / 2, sx, 2.0, 1.2, 2.2, ww=0.9)
    B.finish()
    return B


def build_rsw025():
    """B_P_RSW_025 板葺きの低い家（Phase 4 B）：石置き板葺きの平入（壁 2.9 m・棟 4.8 m＝東列で一番低い）。左右の隣（名主の入母屋 約 5.9 m・細長い妻入 6.0 m）の間に
    屋根が落ちる。庇は付けない（巷が狭い）。薪・籠は Enrich 層（A4）で戸口の脇に置く。入口＝x −1.35..0.45（Kit の戸口と同じ）。"""
    B = Bld('B_P_RSW_025', 4.5, 10.92, 2.9, hk='h27', fin=0, tone=0)
    w, zf = B.w, B.zf
    YE = 2.9
    for lod in (0, 1):
        W, R, PR = B.W[lod], B.R[lod], B.P[lod]
        tm = tmp()
        H = board_roof(tm, lod, w, zf, YE, 0.34, 0.40, 0.12)
        put(R, tm)
        for sx in (-1.0, 1.0):
            polyo(W, [(sx * w / 2, YE, -zf), (sx * w / 2, YE, zf), (sx * w / 2, H - 0.03, 0.0)], 'V2_Wood', BOARD * 0.68, out=(sx, 0.0, 0.0), grain=Y)
        if lod == 1:
            W.box((-w / 2, FL, -zf), (w / 2, YE, zf), 'V2_Plaster', PL, grain=Y)
            continue
        assert abs(row1p(B, W, -w / 2, [('amado', 0.9), ('door', 1.8), ('koshib', 1.8)]) - w / 2) < 0.02
        W.box((-w / 2, 2.68, zf - 0.04), (w / 2, YE, zf), 'V2_Plaster', PL, grain=X)
        W.box((-w / 2 - 0.02, YE - 0.14, zf - 0.04), (w / 2 + 0.02, YE - 0.02, zf + 0.08), 'V2_Wood', DARK, grain=X)
        _board_sides(W, w, zf, YE)
    B.finish()
    return B


def build_rsw026():
    """B_P_RSW_026 仕立て屋の細長い家（Phase 4 B）：瓦の妻入（壁 4.7 m・棟 6.0 m）＋二階が一階より 0.38 m せり出す出桁造り（腕木が並ぶ）。東列で一番高く、
    巷に三角の妻面を向ける。一階の庇は短く（0.6 m）、せり出した二階が巷に被さる。入口＝x 0.90..2.70（Kit の戸口と同じ）。"""
    B = Bld('B_P_RSW_026', 5.4, 10.92, 4.7, hk='h27', fin=2, tone=1)
    w, zf = B.w, B.zf
    YE, Y2, out = 4.7, 3.0, 0.38
    zc = zf + out
    bays1 = [('koshib', 1.8), ('koshi', 1.8), ('door', 1.8)]
    bays2 = [('win', 1.8), ('win', 1.8), ('win', 1.8)]
    for lod in (0, 1):
        W, R, PR = B.W[lod], B.R[lod], B.P[lod]
        H = gable_on_body(B, lod, YE, 0.62, 0.50, 0.50, True)
        eave_roof(R, lod, -w / 2 + 0.02, w / 2 - 0.02, 2.90, zf, 0.60, p=0.32, style='tile')
        if lod == 1:
            W.box((-w / 2, FL, -zf), (w / 2, Y2, zf), 'V2_Plaster', PL, grain=Y)
            W.box((-w / 2, Y2, -zf), (w / 2, YE, zc), 'V2_Plaster', PL, grain=Y)
            continue
        assert abs(row1p(B, W, -w / 2, bays1) - w / 2) < 0.02
        W.box((-w / 2, 2.72, zf - 0.04), (w / 2, Y2, zc), 'V2_Wood', DARK * 0.9, grain=X)             # 二階の床裏・出桁
        nbk = 7
        for i in range(nbk):                                                                           # 腕木
            xb = -w / 2 + 0.25 + (w - 0.5) * i / (nbk - 1)
            W.beam((xb, 2.62, zf - 0.02), (xb, 2.82, zc - 0.06), 0.09, 0.15, 'V2_Wood', DARK)
        assert abs(row2p(B, W, -w / 2, bays2, Y2 + 0.2, YE - 0.5, dz=out) - w / 2) < 0.02
        W.box((-w / 2, Y2, zc - 0.10), (w / 2, YE, zc), 'V2_Plaster', PL, grain=X)                     # 二階の前壁（窓の周り）
        W.box((-w / 2 - 0.02, YE - 0.16, zc - 0.04), (w / 2 + 0.02, YE - 0.02, zc + 0.08), 'V2_Wood', DARK, grain=X)
        for sx in (-1.0, 1.0):
            xo, xi = sx * w / 2, sx * (w / 2 - 0.10)
            W.box((min(xo, xi), FL, -zf), (max(xo, xi), YE, zf), 'V2_Plaster', PL, grain=Z)
            W.box((min(xo, xi), Y2 - 0.1, zf), (max(xo, xi), YE, zc), 'V2_Plaster', PL, grain=Z)
            side_window(W, sx * w / 2, sx, 0.0, 3.4, 4.3, ww=0.9)
            side_window(W, sx * w / 2, sx, -3.0, 3.4, 4.3, ww=0.9)
            side_window(W, sx * w / 2, sx, 1.2, 1.2, 2.1, ww=0.8)
        W.box((-w / 2, FL, -zf), (w / 2, YE, -zf + 0.10), 'V2_Plaster', PL, grain=X)
    B.finish()
    return B


def build_rsw012():
    """B_P_RSW_012 越屋根の農家（Phase 4 B）：低い瓦の寄棟（壁 2.9 m・棟 約 4.2 m）＋棟上の越屋根（煙出し）＋縁側の障子 3 間。西列で唯一の『帽子＋煙突』の輪郭。
    入口＝x −1.35..0.45（Kit の戸口と同じ）。"""
    B = Bld('B_P_RSW_012', 6.29, 10.92, 2.9, fin=2, tone=2)
    w, zf = B.w, B.zf
    YE = 2.9
    xd0 = -1.35
    for lod in (0, 1):
        W, R, PR = B.W[lod], B.R[lod], B.P[lod]
        H = hip_on_body(B, lod, YE, 0.36, 0.52)                                                        # 軒の出 0.52 m・勾配 0.36＝Kit の軒先の高さ（巷は 3 m・カメラが壁際で庇の下に入る）
        koshi_turret(B, lod, H, 1.55, math.pi * 0.5)
        if lod == 1:
            W.box((-w / 2, FL, -zf), (w / 2, YE, zf), 'V2_Plaster', PL, grain=Y)
            continue
        assert abs(row1p(B, W, -w / 2, [('koshib', xd0 + w / 2), ('door', 1.8)]) - (xd0 + 1.8)) < 0.02
        xs0 = xd0 + 1.8                                                                                # 戸口の右：障子 3 間（縁側）
        for k in range(3):
            xa, xb = xs0 + k * (w / 2 - xs0) / 3.0, xs0 + (k + 1) * (w / 2 - xs0) / 3.0
            W.box((xa, FL, zf - 0.02), (xb, 0.95, zf), 'V2_Wood', BOARD, grain=X)
            shoji_bay(W, xa, xb, 0.95, 2.45, zf)
        W.box((xs0, 2.45, zf - 0.05), (w / 2, YE, zf), 'V2_Plaster', PL, grain=X)
        engawa(W, xs0 + 0.34, w / 2 - 0.10, zf, 0.45, 0.55)                                              # 戸口の淨空帯に縁側を掛けない
        _shell(B, W, YE)
        for sx in (-1.0, 1.0):
            side_window(W, sx * w / 2, sx, -1.2, 1.2, 2.2, ww=0.9)
            side_window(W, sx * w / 2, sx, 2.2, 1.2, 2.2, ww=0.9)
    B.finish()
    return B


P4_BUILDERS = [build_mkt005, build_mkt015, build_mkt001, build_mkt004, build_mxc001, build_mxc002, build_mxc004,
               build_rsw024, build_rsw025, build_rsw026, build_rsw012]

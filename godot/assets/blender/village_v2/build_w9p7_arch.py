"""人間之里 V2 P13 W9 Phase 7（MCP-first 試行）：主街南段の残り候補 4 棟（002・017・018・007）から 2 棟（MKT_017・MKT_018）。

build_w9r2_arch.py が P6_BUILDERS の直後でこのファイルを exec する（単独実行はしない）。既存 44 棟の builder・封存 Kit・共用 helper は不変。
使用者 2026-10-16「Transition to MCP-First 3D Production」：Godot MCP で 4 棟を調べ、正常 TPS で改善量の大きい 1–2 棟を選び、Blender MCP で形を詰めて、
既存の決定論的 pipeline（この builder → GLB → prefab → bake）へ永続化する。Blender の live セッションは試作の場で、正本はこのファイル。
選定（Phase 6 最終の正常 TPS 24 視点の ID パス：候補 4 棟の画面占有の合計）：018 77 %・017 58 %・002 35 %・007 27 %。
  017 は南入口で対の 002 とほぼ鏡写しの平入二階（vision）・両隣に家がなく妻が両方とも丸見え → 本卯建の造り酒屋（入口の目印）。
  018 は井戸の辻に南の妻を向ける低い厨子二階、妻が無地の大きな板に読める → 表低奥高の非対称の切妻（辻から見える妻の輪郭を変える）。
  002 は 017 を変えれば鏡写しが解ける。007 は S100 以外で画面占有が小さい。→ 本回は見送り。
制約（実測、body 局部座標）：footprint・入口・body 碰撞（017 頂 5.40 m／018 頂 3.90 m）は不変、見える壁・軒はその上。屋根の碰撞は足さない。
  017：前に W9 杉玉（x 1.17–2.30・y 2.24–3.26・z 4.98–6.42）と P10 酒の幟（x 2.25–2.88・y ≤ 3.79・z 5.53–5.88）→ 下屋は x ≤ 2.12 で止め袖卯建で納める。
       両側 2 m 以内に建物なし（−x に P10 干し物 y ≤ 1.88）。
  018：+x は 019（ART_REVIEW）の壁まで 0.204 m・019 の螻羽 0.08 m → 018 の +x の螻羽は 0.06 m に詰める。−x は井戸（壁から 1.85 m・y ≤ 2.25）。
       前に P10 桶山（x 1.76–3.14・y ≤ 1.28）・W9 鉢（y ≤ 0.57）。
"""


def _udatsu(W, R, sx, w, zf, ze, YE, H, p, t_in=0.18, t_out=0.28, udh=0.95, below=0.45):
    """本卯建：妻壁（x＝sx·w/2 の内 t_in・外 t_out）を屋面より udh 上へ立ち上げ、屋面に沿って軒先 z＝±ze まで。上端に瓦の笠と冠瓦、棟上に合掌塊。"""
    xa, xb = sx * (w / 2 - t_in), sx * (w / 2 + t_out)
    xo, xi = (xb, xa)
    yr = lambda z: H - p * abs(z)
    for sg in (1.0, -1.0):
        z1 = sg * ze
        top0, top1, bot0, bot1 = yr(0.0) + udh, yr(z1) + udh, yr(0.0) - below, yr(z1) - below
        polyo(W, [(xo, bot0, 0.0), (xo, bot1, z1), (xo, top1, z1), (xo, top0, 0.0)], 'V2_Plaster', PL, out=(sx, 0.0, 0.0), grain=Z)     # 外面
        polyo(W, [(xi, bot0, 0.0), (xi, bot1, z1), (xi, top1, z1), (xi, top0, 0.0)], 'V2_Plaster', PL * 0.94, out=(-sx, 0.0, 0.0), grain=Z)  # 内面（屋面の上が見える）
        polyo(W, [(xa, bot1, z1), (xb, bot1, z1), (xb, top1, z1), (xa, top1, z1)], 'V2_Plaster', PL * 0.9, out=(0.0, 0.0, sg), grain=Y)   # 軒先の木口
        zw = sg * zf                                                                                                      # 壁より外（軒の下）の下面
        polyo(W, [(xa, yr(zw) - below, zw), (xb, yr(zw) - below, zw), (xb, bot1, z1), (xa, bot1, z1)], 'V2_Plaster', PL * 0.8, out=(0.0, -1.0, 0.0), grain=Z)
        xm = (xa + xb) / 2
        R.beam((xm, top0 + 0.05, 0.0), (xm, top1 + 0.05, z1 + sg * 0.12), abs(xb - xa) + 0.24, 0.10, 'V2_Kawara', 0.66)            # 瓦の笠（両側へ 0.12 張り出す）
        R.cyl((xm, top0 + 0.14, 0.0), (xm, top1 + 0.14, z1 + sg * 0.12), 0.055, 0.055, 8, 'V2_Kawara', 0.58, caps=(False, True))     # 冠瓦
        put(R, cached(('oni',), lambda: NS['oni']()), off=(xm, top1 + 0.06, z1 + sg * 0.10), sx=0.7, sy=0.7, sz=0.7, rot=-sg * math.pi * 0.5)   # 笠の軒先の小鬼
    W.box((min(xa, xb) - 0.02, yr(0.0) - below, -0.22), (max(xa, xb) + 0.02, yr(0.0) + udh + 0.12, 0.22), 'V2_Plaster', PL, grain=Y)  # 棟上の合掌塊
    R.box((min(xa, xb) - 0.05, yr(0.0) + udh + 0.12, -0.26), (max(xa, xb) + 0.05, yr(0.0) + udh + 0.19, 0.26), 'V2_Kawara', 0.66, grain=Z)


def build_mkt017():
    """B_P_MKT_017 酒屋（Phase 7・南入口の西）：本卯建の造り酒屋。壁 5.6 m・勾配 0.55 の切妻平入（棟 約 8.35 m＝向かいの 002 より 0.9 m 高い）、
    両妻を屋面より 0.95 m 上へ立ち上げ、妻面より 0.28 m 出した本卯建（瓦の笠・軒先に小鬼）、二階は白漆喰の塗籠に虫籠窓 3、両妻に蔵窓・焼杉の腰板・二階床の水切り瓦。
    一階は酒格子・戸口（Kit と同じ x −0.8665..0.8665）・店台＋瓦の下屋（杉玉の上・酒の幟の手前 x ≤ 2.12 で止め、袖卯建で納める）。白漆喰＋銀鼠（FIN 2）。"""
    B = Bld('B_P_MKT_017', 5.2, 10.01, 5.6, fin=2, tone=0)
    w, zf = B.w, B.zf
    YE, P, OVE = 5.6, 0.55, 0.55
    H = YE + P * zf
    bays1 = [('koshi', 1.7335), ('shop_o', 1.733), ('shop_k', 1.7335)]
    bays2 = [('mushi', 1.7335), ('mushi', 1.733), ('mushi', 1.7335)]
    X1 = 2.12                                                                # 下屋の右端（P10 酒の幟 x ≥ 2.25 の手前）
    for lod in (0, 1):
        W, R, PR = B.W[lod], B.R[lod], B.P[lod]
        tm = tmp()
        gable_roof(tm, lod, w, zf, YE, P, OVE, 0.0, tsuma=False)            # 螻羽の出 0＝屋面の端が卯建の内側に入る
        put(R, tm)
        eave_roof(R, lod, -w / 2 + 0.02, X1, 4.05, zf, 0.80, p=0.30, style='tile')          # r2：出 1.0→0.80（杉玉が庇の影に沈んだ）。壁際 4.05：庇の桁の下端 ≈3.45 m を杉玉の吊り木（≤ 3.30 m）より上へ（3.80 だと交差 16）
        for sx in (-1.0, 1.0):
            _udatsu(W, R, sx, w, zf, zf + OVE - 0.06, YE, H, P)
        if lod == 1:
            W.box((-w / 2, FL, -zf), (w / 2, YE, zf), 'V2_Plaster', PL, grain=Y)
            continue
        assert abs(row1p(B, W, -w / 2, bays1) - w / 2) < 0.02
        _shell(B, W, YE)
        W.box((-w / 2, 2.9, zf - 0.10), (w / 2, 3.08, zf + 0.02), 'V2_Wood', DARK * 0.9, grain=X)          # 差し鴨居
        W.box((-w / 2, 3.08, zf - 0.10), (w / 2, 4.20, zf), 'V2_Plaster', PL, grain=X)                     # 下屋の上の小壁
        assert abs(row2p(B, W, -w / 2, bays2, 4.20, YE - 0.18) - w / 2) < 0.02
        W.box((-w / 2, YE - 0.18, zf - 0.10), (w / 2, YE, zf + 0.06), 'V2_Plaster', PL, grain=X)          # 軒下の塗り込め
        # 袖卯建（下屋の右端・幟の手前 z ≤ zf+0.50）：下端は下屋の屋面に埋める
        W.box((X1 - 0.02, 3.80, zf), (X1 + 0.20, 5.20, zf + 0.50), 'V2_Plaster', PL, grain=Y)
        R.box((X1 - 0.05, 5.20, zf - 0.02), (X1 + 0.23, 5.26, zf + 0.53), 'V2_Kawara', 0.70, grain=Z)
        # 両妻：Kit の妻壁（束・貫）を平らな白漆喰で塗り込める＋焼杉の腰板・二階床の水切り瓦・蔵窓
        for sx in (-1.0, 1.0):
            x0 = sx * w / 2
            xg = sx * (w / 2 + 0.07)                                                                       # r2：0.012 では Kit の束・貫が透けた → 0.07 出した一枚の塗籠
            polyo(W, [(xg, 3.36, -zf + 0.02), (xg, 3.36, zf - 0.02), (xg, YE - 0.02, zf - 0.02), (xg, H - 0.30, 0.0), (xg, YE - 0.02, -zf + 0.02)],
                  'V2_Plaster', PL, out=(sx, 0.0, 0.0), grain=Y)
            for zz in (-zf + 0.02, zf - 0.02):                                                             # 塗籠の小口（前後）
                polyo(W, [(x0, 3.36, zz), (xg, 3.36, zz), (xg, YE - 0.02, zz), (x0, YE - 0.02, zz)], 'V2_Plaster', PL * 0.92, out=(0.0, 0.0, 1.0 if zz > 0 else -1.0), grain=Y)
            W.box((min(x0, x0 + sx * 0.035), FL, -zf), (max(x0, x0 + sx * 0.035), 1.75, zf), 'V2_Wood', DARK * 0.75, grain=Y)
            R.box((min(x0, x0 + sx * 0.16), 3.28, -zf), (max(x0, x0 + sx * 0.16), 3.36, zf), 'V2_Kawara', 0.62, grain=Z)
            for zc in (-2.2, 2.2):
                kura_window_side(W, xg, sx, zc, 4.15, 4.90)
        W.box((-w / 2 - 0.02, YE - 0.16, -zf - 0.04), (w / 2 + 0.02, YE, -zf + 0.02), 'V2_Wood', DARK, grain=X)   # 背面の軒桁
        W.box((1.62, 3.27, zf), (1.85, 3.42, zf + 0.09), 'V2_Wood', DARK, grain=X)                          # 杉玉の吊り木の受け（吊り木の端は壁から 0.065 m：上に被せて取り付きを見せる。gate 箱 y ≤ 3.26 の上）
        cloth(W, -0.8665 + 0.10, 0.8665 - 0.10, 2.30, 1.55, zf + 0.04, 'noren_a', seg_w=0.8, billow=0.03, rod=True)
    B.finish()
    return B


def gable_asym(dst, lod, xl, xr, zr, H, zf_, pf, pb, ovf, ovb):
    """表低奥高の切妻：棟は z＝zr（奥へ寄せる）・高さ H。前坡（+z）は勾配 pf で z＝zf_ の壁へ＋軒の出 ovf、後坡は pb で z＝−zf_ の壁へ＋出 ovb。
    妻の螻羽は x＝xl..xr（左右別の出：隣家側を詰める）。Kit の屋面単位・螻羽・棟・鬼瓦・垂木尻を使う（gable_roof と同じ部品）。"""
    L = xr - xl
    Lp = L - END_TRIM * 2.0
    Sf = (zf_ - zr) + ovf - EAVE_TRIM
    Sb = (zf_ + zr) + ovb - EAVE_TRIM
    roof_row(dst, lod, xl + END_TRIM, Lp, Sf, pf, (0.0, H, zr), rot=0.0)
    roof_row(dst, lod, -(xr - END_TRIM), Lp, Sb, pb, (0.0, H, zr), rot=math.pi)
    if lod == 0:
        for xe in (xl + VERGE_IN, xr - VERGE_IN):
            put(dst, NS['verge'](Sf, pf, ''), off=(xe, H, zr))
            put(dst, NS['verge'](Sb, pb, ''), off=(xe, H, zr), rot=math.pi)
        t = tmp()
        put(t, cached(('rg',), lambda: NS['ridge_unit']()), sx=(L - 2.0 * ONI_IN) / RU)
        put(dst, t, off=(xl + ONI_IN, H, zr))
        for xe in (xl + ONI_IN, xr - ONI_IN):
            put(dst, cached(('oni',), lambda: NS['oni']()), off=(xe, H, zr))
        wl = xr - xl - 0.4
        nx = max(3, int(round(wl / 0.52)))
        for (yt, zt) in ((H - pf * (zf_ - zr) - pf * ovf, zf_ + ovf - EAVE_TRIM + 0.02), (H - pb * (zf_ + zr) - pb * ovb, -(zf_ + ovb - EAVE_TRIM + 0.02))):
            for i in range(nx + 1):
                xx = xl + 0.2 + wl * i / nx
                dst.box((xx - 0.035, yt - 0.33, zt - 0.07), (xx + 0.035, yt - 0.2, zt + 0.07), 'V2_Wood', DARK * 0.85, grain=Y)
        _rec('roof', kind='gable', ridge_stack=True, oni=True, hip_caps=0, eave_tails=True, gegyo=False, ove=ovf)
    else:
        dst.box((xl, H - 0.02, zr - 0.12), (xr, H + 0.18, zr + 0.12), 'V2_Kawara', 0.66, grain=X)


def build_mkt018():
    """B_P_MKT_018 住宅（Phase 7・井戸の辻に南の妻を向ける）：表低奥高の非対称切妻。棟を奥へ 1.0 m 寄せ（棟 6.85 m）、
    表（通り側）は厨子二階の低い軒（壁 4.05 m・深い軒の出 0.75 m）、奥は本二階（壁 5.35 m）。辻から見える妻は左右非対称の五角形になり、
    真壁の柱・胴差、一階の勝手口と格子、奥の二階に出格子。+x（019 側）の螻羽の出は 0.06 m に詰め、−x（辻側）は 0.30 m。
    表は Kit と同じ間割り（入口＝x −0.435..1.305）：格子・戸口・格子＋二階は土壁の粗格子の虫籠窓、戸口だけ板の霧除け。煤け（FIN 3）・瓦は標準。"""
    B = Bld('B_P_MKT_018', 6.09, 10.92, 4.05, fin=3, tone=0)
    w, zf = B.w, B.zf
    YF, YB, H, ZR = 4.05, 5.35, 6.85, -1.0
    PF, PB = (H - YF) / (zf - ZR), (H - YB) / (zf + ZR)
    OVF, OVB, GL, GR = 0.60, 0.45, 0.30, 0.06                      # r2：表の軒の出 0.75→0.60（表の一階が軒の影の帯に沈んだ）
    bays1 = [('koshib', 0.87), ('koshi', 1.74), ('door', 1.74), ('koshi', 1.74)]
    bays2 = [('mushib', 0.87), ('mushib', 1.74), ('mushib', 1.74), ('mushib', 1.74)]

    def side_wall(W, sx, col):
        x = sx * w / 2
        pts = [(x, FL, -zf), (x, FL, zf), (x, YF, zf), (x, H - 0.10, ZR), (x, YB, -zf)]
        polyo(W, pts, 'V2_Plaster', col, out=(sx, 0.0, 0.0), grain=Z)
        xi = sx * (w / 2 - 0.10)
        polyo(W, [(xi, q[1], q[2]) for q in pts], 'V2_Plaster', col, out=(-sx, 0.0, 0.0), grain=Z)

    for lod in (0, 1):
        W, R, PR = B.W[lod], B.R[lod], B.P[lod]
        gable_asym(R, lod, -w / 2 - GL, w / 2 + GR, ZR, H, zf, PF, PB, OVF, OVB)
        for sx in (-1.0, 1.0):
            side_wall(W, sx, PL)
        W.box((-w / 2, FL, -zf), (w / 2, YB, -zf + 0.10), 'V2_Plaster', PL, grain=X)                      # 背面
        if lod == 1:
            W.box((-w / 2, FL, zf - 0.10), (w / 2, YF, zf), 'V2_Plaster', PL, grain=X)
            continue
        assert abs(row1p(B, W, -w / 2, bays1) - w / 2) < 0.02
        W.box((-w / 2, 2.9, zf - 0.10), (w / 2, 3.05, zf + 0.04), 'V2_Wood', DARK * 0.9, grain=X)        # 差し鴨居
        assert abs(row2p(B, W, -w / 2, bays2, 3.05, YF) - w / 2) < 0.02
        W.box((-w / 2 - 0.02, YF - 0.16, zf - 0.04), (w / 2 + 0.02, YF, zf + 0.07), 'V2_Wood', DARK, grain=X)   # 軒桁
        eave_roof(R, lod, -0.435 - 0.10, 1.305 + 0.10, 2.78, zf, 0.55, p=0.28, style='board')             # 戸口の霧除け
        # 辻側（−x）の妻：真壁（柱 5・胴差・梁）、一階に格子・勝手口、奥の二階に出格子、焼杉の腰板
        xs = -w / 2
        for zp in (-zf + 0.06, -2.7, ZR, 2.2, zf - 0.06):
            ytop = (YB + (H - YB) * (zp + zf) / (zf + ZR)) if zp <= ZR else (H - PF * (zp - ZR))
            W.box((xs - 0.05, FL, zp - 0.07), (xs + 0.01, ytop - 0.12, zp + 0.07), 'V2_Wood', DARK, grain=Y)
        W.box((xs - 0.06, 2.88, -zf), (xs + 0.01, 3.04, zf), 'V2_Wood', DARK * 0.9, grain=Z)             # 胴差
        W.box((xs - 0.06, YF - 0.14, -zf), (xs + 0.01, YF, zf), 'V2_Wood', DARK * 0.9, grain=Z)          # 二階の梁
        ts = tmp()
        x = -zf
        for kind, wn in (('plain', 1.06), ('koshi', 1.75), ('door', 1.75), ('plain', 1.06), ('koshi', 1.75), ('koshi', 1.75), ('plain', 1.80)):   # r2：表寄りの空白 3.5 m に格子を 1 間足す
            if kind != 'plain':
                put(ts, FR(kind, wn, B.hk), off=(x, 0.0, w / 2))
            x += wn
        deguchi(ts, -4.30, -2.10, 4.05, 5.05, w / 2, out=0.30)                                           # 奥の二階の出格子（辻向き）
        put(W, ts, rot=-math.pi * 0.5)
        W.box((xs - 0.035, FL, 3.70), (xs, 1.05, zf - 0.13), 'V2_Wood', DARK * 0.75, grain=Y)            # 焼杉の腰板（表の角）
        side_window(W, xs, -1.0, 3.2, 3.25, 3.85, ww=1.1)                                                 # 表寄りの厨子の連子窓
        side_window(W, xs, -1.0, 0.9, 3.30, 4.05, ww=0.9)                                                 # r2：表寄りの二階（屋根裏）の窓
        side_window(W, xs, -1.0, -1.45, 4.15, 4.95, ww=0.8)                                               # r2：奥の二階の 2 つ目の窓（出格子の隣）
        cloth(W, -0.435 + 0.10, 1.305 - 0.10, 2.25, 1.55, zf + 0.04, 'noren_c', seg_w=0.8, billow=0.03, rod=True)
    B.finish()
    return B


P7_BUILDERS = [build_mkt017, build_mkt018]

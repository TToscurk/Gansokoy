"""人間之里 V2 P13 W9 Phase 7（MCP-first 試行）：主街南段の残り候補 4 棟（002・017・018・007）から 2 棟（MKT_017・MKT_018）。

build_w9r2_arch.py が P6_BUILDERS の直後でこのファイルを exec する（単独実行はしない）。既存 44 棟の builder・封存 Kit・共用 helper は不変。
使用者 2026-10-16「Transition to MCP-First 3D Production」：Godot MCP で 4 棟を調べ、正常 TPS で改善量の大きい 1–2 棟を選び、Blender MCP で形を詰めて、
既存の決定論的 pipeline（この builder → GLB → prefab → bake）へ永続化する。Blender の live セッションは試作の場で、正本はこのファイル。
選定（Phase 6 最終の正常 TPS 24 視点の ID パス：候補 4 棟の画面占有の合計）：018 77 %・017 58 %・002 35 %・007 27 %。
  017 は南入口で対の 002 とほぼ鏡写しの平入二階（vision）・両隣に家がなく妻が両方とも丸見え → 酒屋（入口の目印）。r2 の本卯建の造り酒屋は高すぎ（頂 9.49 m）→ r3（2026-10-21）で厨子二階の町家に下げた。
  018 は井戸の辻に南の妻を向ける低い厨子二階、妻が無地の大きな板に読める → 表低奥高の非対称の切妻（辻から見える妻の輪郭を変える）。
  002 は 017 を変えれば鏡写しが解ける。007 は S100 以外で画面占有が小さい。→ 本回は見送り。
制約（実測、body 局部座標）：footprint・入口・body 碰撞（017 頂 5.40 m／018 頂 3.90 m）は不変、見える壁・軒はその上。屋根の碰撞は足さない。
  017：前に W9 杉玉（x 1.17–2.30・y 2.24–3.26・z 4.98–6.42）と P10 酒の幟（x 2.25–2.88・y ≤ 3.79・z 5.53–5.88）→ r3：下屋は x ≤ 1.05（杉玉の手前）で止め、両端を袖卯建で納める。
       両側 2 m 以内に建物なし（−x に P10 干し物 y ≤ 1.88）。
  018：+x は 019（ART_REVIEW）の壁まで 0.204 m・019 の螻羽 0.08 m → 018 の +x の螻羽は 0.06 m に詰める。−x は井戸（壁から 1.85 m・y ≤ 2.25）。
       前に P10 桶山（x 1.76–3.14・y ≤ 1.28）・W9 鉢（y ≤ 0.57）。
"""


def build_mkt017():
    """B_P_MKT_017 酒屋（Phase 7 r3・2026-10-21 使用者「外觀很突兀」で作り直し）：厨子二階の町家の酒屋。
    r2（壁 5.6 m・勾配 0.55・棟 8.35 m・高さ 0.95 m／厚さ 0.46 m の本卯建＝実測頂 9.49 m、周り 30 m の棟は 4.5–7.6 m）が
    細い間口 5.2 m に対して塔のように突き出ていた → 町の Kit と同じ勾配 0.45・壁 4.55 m（棟 6.80 m）に下げ、本卯建を外して
    両妻は Kit の螻羽（出 0.30）・鬼瓦・妻壁の束貫で納める（隣の町家と同じ屋根の言葉）。
    一階は酒格子・戸口（Kit と同じ x −0.8665..0.8665）・店台。瓦の下屋は戸口と格子の上だけ（x ≤ 1.05）：右の間口の前には
    W9 杉玉（x 1.17–2.30・腕木 y 2.95）と P10 酒の幟（x 2.25–2.88・y ≤ 3.79）が立つので、杉玉は二階の床下の差し鴨居から吊る。
    下屋の両端は Kit の袖卯建（庇上の小さな防火袖壁）。二階は白漆喰の虫籠窓 3。両妻の一階は焼杉の板張り＋水切り瓦、二階は漆喰に蔵窓 2。
    白漆喰＋銀鼠（FIN 2）。"""
    B = Bld('B_P_MKT_017', 5.2, 10.01, 4.55, fin=2, tone=0)
    w, zf = B.w, B.zf
    YE, P, OVE, OVG = 4.55, 0.45, 0.55, 0.30
    bays1 = [('koshi', 1.7335), ('shop_o', 1.733), ('shop_k', 1.7335)]
    bays2 = [('mushi', 1.7335), ('mushi', 1.733), ('mushi', 1.7335)]
    X1 = 1.05                                                                # 下屋の右端（杉玉 x ≥ 1.17 の手前）
    YH = 3.30                                                                # 下屋の壁際の屋面線（胴差 2.94–3.12＝差し鴨居と同じ高さ）
    for lod in (0, 1):
        W, R, PR = B.W[lod], B.R[lod], B.P[lod]
        tm = tmp()
        gable_roof(tm, lod, w, zf, YE, P, OVE, OVG, tsuma=False)
        put(R, tm)
        eave_roof(R, lod, -w / 2 + 0.02, X1, YH, zf, 0.85, p=0.30, style='tile')
        if lod == 1:
            W.box((-w / 2, FL, -zf), (w / 2, YE, zf), 'V2_Plaster', PL, grain=Y)
            continue
        assert abs(row1p(B, W, -w / 2, bays1) - w / 2) < 0.02
        _shell(B, W, YE)
        W.box((-w / 2, 2.9, zf - 0.10), (w / 2, 3.08, zf + 0.02), 'V2_Wood', DARK * 0.9, grain=X)          # 差し鴨居（杉玉の腕木 y 2.95 がここに取り付く）
        W.box((-w / 2, 3.08, zf - 0.10), (w / 2, 3.50, zf), 'V2_Plaster', PL, grain=X)                     # 下屋の上の小壁
        assert abs(row2p(B, W, -w / 2, bays2, 3.50, YE - 0.18) - w / 2) < 0.02
        W.box((-w / 2, YE - 0.18, zf - 0.10), (w / 2, YE, zf + 0.06), 'V2_Plaster', PL, grain=X)          # 軒下の塗り込め
        for xu in (-w / 2 + 0.13, X1 - 0.12):                                                            # 袖卯建（下屋の両端・Kit の構件）
            put(W, cached(('ud62',), lambda: NS['udatsu'](0.62)), off=(xu, YH, zf))
        # 両妻：一階＝焼杉の板張り（台基〜2.85）＋水切り瓦、二階＝漆喰（Kit の妻壁の束・貫はそのまま見せる）＋蔵窓 2
        for sx in (-1.0, 1.0):
            x0 = sx * w / 2
            W.box((min(x0, x0 + sx * 0.035), FL, -zf), (max(x0, x0 + sx * 0.035), 2.85, zf), 'V2_Wood', DARK * 0.62, grain=Y)
            nb_ = int(round(2 * zf / 0.45))
            for i in range(1, nb_):                                                                        # 板張りの押縁（0.45 m 毎）
                zb_ = -zf + 2 * zf * i / nb_
                W.box((min(x0, x0 + sx * 0.06), FL, zb_ - 0.018), (max(x0, x0 + sx * 0.06), 2.85, zb_ + 0.018), 'V2_Wood', DARK * 0.5, grain=Y)
            R.box((min(x0, x0 + sx * 0.15), 2.85, -zf), (max(x0, x0 + sx * 0.15), 2.93, zf), 'V2_Kawara', 0.62, grain=Z)
            for zc in (-2.2, 2.2):                                                                         # r3b：蔵窓（灰色の塊に読めた）→ 町家の連子窓
                side_window(W, x0, sx, zc, 3.50, 4.10, ww=0.9)
        W.box((-w / 2 - 0.02, YE - 0.16, -zf - 0.04), (w / 2 + 0.02, YE, -zf + 0.02), 'V2_Wood', DARK, grain=X)   # 背面の軒桁
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

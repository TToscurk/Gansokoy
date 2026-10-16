"""人間之里 V2 P13 W9 Phase 6：主街南段の建築多様性（MKT_019・MKT_021・MKT_022・MKT_003）。

build_w9r2_arch.py が P5_BUILDERS の直後でこのファイルを exec する（単独実行はしない）。既存 40 棟の builder・封存 Kit・共用 helper は不変。
使用者 2026-10-16：候補 8 棟（002・017・018・003・019・021・022・007）の現況輪郭と正常 TPS 可視度を見て、改善余地の大きい 4 棟を選ぶ。
選定の根拠（scratch 調査：主街中心線を北上 10 視点・南下 6 視点の正常 TPS＋ID パス）：
  019→020→021→022 の西列が同じ高さ（棟 7.86 m）の平入二階の連続で一番単調（vision）、画面占有は 019 最大 27.6 %、021 27.0 %、022 27.9 %。
  003 は東列の市ブロック南端（南の 40 m の空地から北上する間ずっと正面に来る角地）、最大 26.1 %。
  017／002（南入口の対）・018・007 は今回見送り。

街並みの組み立て（西列 南→北：018 厨子 6.9｜019｜020 妻入の豆腐屋 5.95（承認済）｜021｜022｜辻、東列：003｜004 板葺 5.4｜005 入母屋 8.0）：
  019 荒物屋＝出桁造りの緩勾配平入（棟 約 7.0 m、二階が 0.40 m せり出す・一階は蔀戸と揚げ縁）。
  021 薬種問屋＝黒漆喰の店蔵（壁 5.9 m・重い箱棟と大鬼瓦・棟 約 8.6 m＋箱棟＝列で一番高い・二階は塗籠に観音扉の窓 3・鉢巻・020 側に袖卯建）。
  022 茶屋（辻の角）＝寄棟の二階（棟 約 7.0 m、通りへ寄棟の端を向ける・二階は手摺と簾の格子窓・一階は開け放し）。
  003 飯屋（東列の南の角）＝本二階の大きな妻入（壁 6.25 m・棟 約 8.0 m・懸魚と扠首組の妻）＋南面（空地側）の板葺きの下屋・格子の間割り・出格子＋棟の煙出し。

制約（実測、各棟の局部座標。W9 R2 の gate と同じ）：footprint・入口位置・body 碰撞は不変、屋根の碰撞は足さない。
  側面：019 の −x は 018 の Kit が壁から 0.12 m（y 2–6.8）→ 螻羽 0.08 m。021 の −x は 020 の庇が壁面まで（y ≤ 4.3）、+x は 022 まで 0.685 m。
        003 の −x は 004 の螻羽が壁から 0.04 m・y ≤ 5.78 → 003 の垂木尻の下端を 5.83 m に置く（壁 6.25・出 0.20）。
  前（gate の others_for の箱）：019・021 は全部 y ≤ 1.77。022 は大幟 x 1.06–1.67・y ≤ 3.72・壁から 0.53 m → 一階の庇は出 0.45 m。
        003 は赤提灯 x −2.57..−1.80・y ≤ 2.45（壁際）→ 庇の前縁の下端 ≥ 2.5 m、大幟 x 3.61–4.21・y ≤ 3.72 → 前の庇は x ≤ 3.50 で止める。
        003 の南面の地面には P10 の桶屋の作業物（y ≤ 0.52）→ 下屋は y 3.1 m・出 1.25 m（庇柱なし）。
"""


def build_mkt019():
    """B_P_MKT_019 荒物屋（Phase 6）：出桁造りの緩勾配平入。二階の前壁が 0.40 m 前へ出て、その下端に出し桁の木口 9 本と桁が並ぶ（深い影の帯）。
    屋根は勾配 0.30・軒の出 1.0 m（せり出した二階のさらに 0.5 m 先）。一階は蔀戸 3 間（吊り上げ・突っ支い棒なし）＋揚げ縁 2・戸口に暖簾。
    入口＝x 0..1.75（Kit と同じ）。聚楽壁＋弁柄（FIN 1）・瓦は風化の暖褐（tone 2）。"""
    B = Bld('B_P_MKT_019', 7.0, 10.92, 5.4, fin=1, tone=2)
    w, zf = B.w, B.zf
    YE, P, OUT, Y2 = 5.4, 0.30, 0.40, 3.40                                  # r3：せり出し 0.50→0.40（床裏の影の帯を細く）。Y2＝出し桁の上端：
    # 立面際の既定 TPS 相機の高さ（足元＋1.7＋8.5×sin(−pitch)≈3.22 m）より出桁の下端（Y2−0.16＝3.24）を上に置く（相機がせり出しに入らない）
    YT = YE - P * OUT                                                        # せり出した前壁の頂（屋面の下）
    bays1 = [('shop_k', 1.75), ('shop_k', 1.75), ('shop_o', 1.75), ('shop_k', 1.75)]
    bays2 = [('amado', 1.75), ('winb', 1.75), ('winb', 1.75), ('amado', 1.75)]
    for lod in (0, 1):
        W, R, PR = B.W[lod], B.R[lod], B.P[lod]
        gable_on_body(B, lod, YE, P, 1.0, 0.08, False)
        if lod == 1:
            W.box((-w / 2, FL, -zf), (w / 2, YE, zf), 'V2_Plaster', PL, grain=Y)
            W.box((-w / 2, Y2, zf), (w / 2, YT, zf + OUT), 'V2_Plaster', PL, grain=Y)
            continue
        assert abs(row1p(B, W, -w / 2, bays1) - w / 2) < 0.02
        _shell(B, W, YE)
        W.box((-w / 2, 2.9, zf - 0.10), (w / 2, 3.08, zf + 0.02), 'V2_Wood', DARK * 0.9, grain=X)        # 差し鴨居
        W.box((-w / 2, 3.08, zf - 0.10), (w / 2, Y2, zf), 'V2_Plaster', PL, grain=X)                    # 小壁（一階の上）
        # 出桁：床梁の木口 9 本＋先端の桁＋せり出しの床裏
        for i in range(9):
            xb = -w / 2 + 0.18 + (w - 0.36) * i / 8.0
            W.box((xb - 0.07, Y2 - 0.16, zf - 0.02), (xb + 0.07, Y2 + 0.06, zf + OUT + 0.10), 'V2_Wood', BOARD * 0.75, grain=Z)     # r2：木口を明るく（影の帯に沈んだ）
        W.box((-w / 2 - 0.04, Y2 - 0.04, zf + OUT - 0.06), (w / 2 + 0.04, Y2 + 0.16, zf + OUT + 0.12), 'V2_Wood', BOARD * 0.7, grain=X)   # 出桁
        W.box((-w / 2, Y2 + 0.06, zf), (w / 2, Y2 + 0.15, zf + OUT), 'V2_Wood', BOARD * 0.95, grain=X)                                     # 床裏
        assert abs(row2p(B, W, -w / 2, bays2, Y2 + 0.15, YT, dz=OUT) - w / 2) < 0.02
        W.box((-w / 2, Y2 + 0.15, zf), (w / 2, YE, zf + 0.04), 'V2_Plaster', PL, grain=X)                # せり出しの奥の壁（隙間を見せない）
        for sx in (-1.0, 1.0):                                                                           # せり出しの側板（上辺は屋面に沿う）
            polyo(W, [(sx * w / 2, Y2 + 0.06, zf), (sx * w / 2, Y2 + 0.06, zf + OUT), (sx * w / 2, YT, zf + OUT), (sx * w / 2, YE - 0.01, zf)],
                  'V2_Plaster', PL, out=(sx, 0.0, 0.0), grain=Z)
        W.box((-w / 2 - 0.02, YT - 0.14, zf + OUT - 0.04), (w / 2 + 0.02, YT, zf + OUT + 0.06), 'V2_Wood', DARK, grain=X)   # 軒桁
        for (xa, xb) in ((-3.5, -1.75), (-1.75, 0.0), (1.75, 3.5)):                                      # 蔀戸（突っ支い棒なし＝足元を空ける）
            shitomi(W, xa + 0.04, xb - 0.04, 2.45, zf + 0.02, rise=0.38, out=0.62, struts=False)
        for (xa, xb) in ((-3.5, -1.75), (-1.75, 0.0)):                                                   # 揚げ縁（P10 の平台 x ≥ 1.72 の前は空ける）
            agari_en(W, xa + 0.05, xb - 0.05, zf, y=0.62, out=0.42)
        cloth(W, 0.12, 1.63, 2.25, 1.60, zf + 0.04, 'noren_c', seg_w=0.75, billow=0.03, rod=True)
    B.finish()
    return B


def build_mkt021():
    """B_P_MKT_021 薬種問屋（Phase 6）：黒漆喰の店蔵。壁 5.9 m（隣の二階より 0.5 m 高い）＋勾配 0.48 の重い切妻＋箱棟（高さ 0.48 m）と大鬼瓦。
    二階は全面の塗籠（暗い漆喰・観音扉の窓 3）、軒下に二段の鉢巻、020（低い妻入）側に袖卯建、020 の屋根の上に見える南の妻壁に蔵窓 2。
    一階は Kit の間割りのまま（格子・店台・戸口）＋瓦の下屋庇。入口＝x 0.439..2.194。煤け（FIN 3）・瓦は標準。"""
    B = Bld('B_P_MKT_021', 7.9, 10.92, 5.9, fin=3, tone=0)
    w, zf = B.w, B.zf
    YE, P, OVE, OVG = 5.9, 0.48, 0.45, 0.12
    KP = PL * 0.95                                                           # 塗籠の漆喰（FIN 3 と掛けて暗い灰。r2：0.78 は窓の黒と同じ値に沈んだ）
    bays1 = [('koshi', 0.878), ('shop_k', 1.755), ('koshir', 1.756), ('shop_o', 1.756), ('shop_k', 1.755)]
    wins = [(-2.4, 0.80, 3.95, 4.85), (0.0, 0.80, 3.95, 4.85), (2.4, 0.80, 3.95, 4.85)]
    for lod in (0, 1):
        W, R, PR = B.W[lod], B.R[lod], B.P[lod]
        tm = tmp()
        H = gable_roof(tm, lod, w, zf, YE, P, OVE, OVG, tsuma=False)
        put(R, tm)
        eave_roof(R, lod, -w / 2 + 0.27, w / 2 - 0.02, 3.15, zf, 1.0, p=0.30, style='tile')
        L = w + OVG * 2.0
        if lod == 1:
            W.box((-w / 2, FL, -zf), (w / 2, YE, zf), 'V2_Plaster', KP, grain=Y)
            R.box((-L / 2 + 0.4, H, -0.26), (L / 2 - 0.4, H + 0.45, 0.26), 'V2_Kawara', 0.5, grain=X)
            continue
        assert abs(row1p(B, W, -w / 2, bays1) - w / 2) < 0.02
        _shell(B, W, YE, col_side=0.8)
        W.box((-w / 2, 2.9, zf - 0.10), (w / 2, 3.25, zf + 0.05), 'V2_Plaster', KP, grain=X)              # 一階の上の帯
        nurigome(W, w, zf, 3.25, YE - 0.58, wins, t=0.17, col=KP)                                        # 二階の塗籠
        for (xc, ww_, y0, y1) in wins:
            kura_win_front(W, xc, y0, y1, zf + 0.17, ww=ww_)
            a0, a1, b0, b1 = xc - ww_ / 2 - 0.11, xc + ww_ / 2 + 0.11, y0 - 0.11, y1 + 0.11       # 窓の額縁（一段明るい漆喰の段）
            for lo, hi in (((a0 - 0.08, b0 - 0.08), (a0, b1 + 0.08)), ((a1, b0 - 0.08), (a1 + 0.08, b1 + 0.08)),
                           ((a0, b1), (a1, b1 + 0.08)), ((a0, b0 - 0.08), (a1, b0))):
                W.box((lo[0], lo[1], zf + 0.17), (hi[0], hi[1], zf + 0.25), 'V2_Plaster', PL * 1.35, grain=Y)
        W.box((-w / 2 - 0.03, YE - 0.58, zf - 0.02), (w / 2 + 0.03, YE - 0.36, zf + 0.22), 'V2_Plaster', KP, grain=X)   # 鉢巻（下段）
        W.box((-w / 2 - 0.06, YE - 0.36, zf - 0.02), (w / 2 + 0.06, YE - 0.20, zf + 0.34), 'V2_Plaster', KP, grain=X)   # 鉢巻（上段＝軒裏まで塗り込め）
        W.box((-w / 2, YE - 0.22, zf - 0.10), (w / 2, YE, zf), 'V2_Plaster', KP, grain=X)
        # 袖卯建（020 側・二階の高さ）：壁から前へ 0.62 m の防火の袖壁＋瓦の笠
        W.box((-w / 2, 3.15, zf), (-w / 2 + 0.24, YE + 0.12, zf + 0.62), 'V2_Plaster', KP, grain=Y)
        R.box((-w / 2 - 0.04, YE + 0.12, zf - 0.06), (-w / 2 + 0.28, YE + 0.24, zf + 0.68), 'V2_Kawara', 0.55, grain=Z)
        # 妻壁は軸組みを塗り込めた平らな暗い漆喰＋南（020 の屋根の上に見える面）に蔵窓 2
        for sx in (-1.0, 1.0):
            polyo(W, [(sx * (w / 2 + 0.012), YE - 0.02, -zf + 0.05), (sx * (w / 2 + 0.012), YE - 0.02, zf - 0.05), (sx * (w / 2 + 0.012), H - 0.10, 0.0)],
                  'V2_Plaster', KP, out=(sx, 0.0, 0.0), grain=Y)
        for zc in (-1.7, 1.7):
            kura_window_side(W, -w / 2, -1.0, zc, 4.55, 5.30)
        # 箱棟（重い棟）＋笠＋大鬼瓦
        R.box((-L / 2 + 0.38, H - 0.08, -0.27), (L / 2 - 0.38, H + 0.40, 0.27), 'V2_Kawara', 0.50, grain=X)
        R.box((-L / 2 + 0.33, H + 0.40, -0.32), (L / 2 - 0.33, H + 0.48, 0.32), 'V2_Kawara', 0.62, grain=X)
        for e in (-1.0, 1.0):
            put(R, cached(('oni',), lambda: NS['oni']()), off=(e * (L / 2 - 0.30), H + 0.30, 0.0), sx=1.7, sy=1.7, sz=1.7)
        cloth(W, 0.439 + 0.10, 2.194 - 0.10, 2.30, 1.55, zf + 0.04, 'noren_a', seg_w=0.8, billow=0.03, rod=True)
    B.finish()
    return B


def build_mkt022():
    """B_P_MKT_022 茶屋（Phase 6・辻の北の角）：寄棟の二階（勾配 0.45・出 0.45・棟 約 7.0 m＝隣の店蔵より 1.6 m 低い）。
    棟は奥行き方向＝通りと辻の両方へ寄棟の斜面を向ける『帽子』。二階は手摺と半ば巻いた簾の格子窓 4 間、一階は開け放しの土間＋浅い板庇（大幟の手前）。
    辻側（+x）にも角から 3 間、二階の手摺・簾の格子窓と一階の格子・店台を回す。入口＝x −1.7525..0（Kit と同じ）。白漆喰＋銀鼠（FIN 2）・いぶし銀（tone 1）。"""
    B = Bld('B_P_MKT_022', 7.01, 10.92, 5.4, fin=2, tone=1)
    w, zf = B.w, B.zf
    YE, P, OV = 5.4, 0.45, 0.45
    bw = w / 4.0
    bays1 = [('shop_o', bw), ('shop_o', bw), ('shop_k', bw), ('shop_o', bw)]
    bays2 = [('wins', bw)] * 4
    for lod in (0, 1):
        W, R, PR = B.W[lod], B.R[lod], B.P[lod]
        hip_on_body(B, lod, YE, P, OV)
        eave_roof(R, lod, -w / 2 + 0.02, w / 2 - 0.02, 2.95, zf, 0.45, p=0.28, style='board')
        if lod == 1:
            W.box((-w / 2, FL, -zf), (w / 2, YE, zf), 'V2_Plaster', PL, grain=Y)
            continue
        assert abs(row1p(B, W, -w / 2, bays1) - w / 2) < 0.02
        W.box((-w / 2, 2.9, zf - 0.10), (w / 2, 3.05, zf + 0.06), 'V2_Wood', DARK * 0.9, grain=X)        # 差し鴨居
        assert abs(row2p(B, W, -w / 2, bays2, 3.05, YE) - w / 2) < 0.02
        _shell(B, W, YE)
        W.box((-w / 2 - 0.02, YE - 0.16, zf - 0.04), (w / 2 + 0.02, YE, zf + 0.07), 'V2_Wood', DARK, grain=X)    # 軒桁
        # 辻側（+x）：二階の手摺・簾の格子窓を角から 3 間回し、一階も格子と店台で辻へ顔を向ける（r2：側面が空の白壁に読めた）
        ts = tmp()
        for i, (k1, k2) in enumerate((('koshi', 'wins'), ('shop_k', 'wins'), ('koshi', 'wins'))):
            xs = -zf + 1.75 * i
            put(ts, FR(k1, 1.75, B.hk), off=(xs, 0.0, w / 2))
            put(ts, UP(k2, 1.75, 3.05, YE), off=(xs, 0.0, w / 2))
        put(W, ts, rot=math.pi * 0.5)
        W.box((w / 2 - 0.01, 2.9, -zf), (w / 2 + 0.06, 3.05, zf), 'V2_Wood', DARK * 0.9, grain=Z)      # 側面の胴差
        cloth(W, -bw * 2 + 0.10, -0.10, 2.25, 1.62, zf + 0.04, 'noren_b', seg_w=0.8, billow=0.03, rod=True)
    B.finish()
    return B


def build_mkt003():
    """B_P_MKT_003 飯屋（Phase 6・東列の南の角）：厨子の妻入を本二階の大きな妻入へ（壁 6.25 m・勾配 0.45・棟 約 8.0 m）。
    正面の妻は平らな漆喰に扠首組と束・懸魚、二階に出格子 2、一階は Kit の間割り＋板の霧除け庇（出 0.35 m・大幟の手前で止める）。
    南の面（空地からの北上で長く正面に来る面）に板葺きの下屋（y 3.1 m・出 1.25 m）、その下に格子と勝手口の間割り、二階に出格子 2 と柱 5、棟に竈の煙出し。
    北の面は窓なし（004 の螻羽が壁から 0.04 m に来る＝窓枠が交差した）。入口＝x −1.317..0.439（Kit と同じ）。新木＋生成り（FIN 4）・いぶし銀（tone 1）。"""
    B = Bld('B_P_MKT_003', 7.9, 10.01, 6.25, fin=4, tone=1)
    w, zf = B.w, B.zf
    YE, P, OVE = 6.25, 0.45, 0.20      # r4：壁 6.1→6.25・軒の出 0.30→0.20＝北の垂木尻の下端 5.83 m を 004 の螻羽（≤ 5.78 m・壁から 0.04 m）より上へ（三角形交差 11→0）
    bays1 = [('plain', 0.878), ('koshi', 1.755), ('shop_o', 1.756), ('shop_c', 1.755), ('koshi', 0.878), ('koshi', 0.878)]
    for lod in (0, 1):
        W, R, PR = B.W[lod], B.R[lod], B.P[lod]
        tm = tmp()
        H = gable_roof(tm, lod, B.d, w / 2, YE, P, OVE, 0.35, tsuma=True, oni=True)
        put(R, tm, rot=-math.pi * 0.5)
        eave_roof(R, lod, -w / 2 + 0.02, 3.50, 3.10, zf, 0.35, p=0.30, style='board')                  # 霧除けの板庇。r1 瓦 0.90 → r3 板 0.35（西列を向く TPS の相機が立面から 0.87 m・y 3.24 で庇の上を舐める）
        ts = tmp()
        eave_roof(ts, lod, -3.9, 3.9, 3.10, w / 2, 1.25, p=0.30, style='board')                        # 南（+x）の下屋（板葺き）：+z 向きに組んで +90° 回す
        put(R, ts, rot=math.pi * 0.5)
        koshi_turret(B, lod, H, 2.0, -math.pi * 0.5, z=-1.4)
        if lod == 1:
            W.box((-w / 2, FL, -zf), (w / 2, YE, zf), 'V2_Plaster', PL, grain=Y)
            continue
        assert abs(row1p(B, W, -w / 2, bays1) - w / 2) < 0.02
        _shell(B, W, YE)
        W.box((-w / 2, 2.9, zf - 0.10), (w / 2, 3.15, zf + 0.06), 'V2_Wood', DARK * 0.9, grain=X)        # 差し鴨居
        W.box((-w / 2, 3.15, zf - 0.10), (w / 2, YE, zf), 'V2_Plaster', PL, grain=X)                    # 二階の前壁
        W.box((-w / 2 - 0.02, YE - 0.16, zf - 0.04), (w / 2 + 0.02, YE, zf + 0.07), 'V2_Wood', DARK, grain=X)    # 妻の梁
        for (xa, xb) in ((-3.40, -1.00), (0.90, 3.30)):
            deguchi(W, xa, xb, 4.05, 5.25, zf, out=0.32)
        # 正面の妻：平らな漆喰＋扠首 2・束 3
        polyo(W, [(-w / 2 + 0.05, YE, zf + 0.012), (w / 2 - 0.05, YE, zf + 0.012), (0.0, H - 0.08, zf + 0.012)], 'V2_Plaster', PL)
        W.beam((-w / 2 + 0.45, YE + 0.06, zf + 0.05), (0.0, H - 0.42, zf + 0.05), 0.13, 0.08, 'V2_Wood', DARK)
        W.beam((w / 2 - 0.45, YE + 0.06, zf + 0.05), (0.0, H - 0.42, zf + 0.05), 0.13, 0.08, 'V2_Wood', DARK)
        for xs in (-1.25, 0.0, 1.25):
            top = H - 0.42 - abs(xs) * P * 1.05
            W.beam((xs, YE + 0.06, zf + 0.045), (xs, top, zf + 0.045), 0.10, 0.07, 'V2_Wood', DARK)
        # 南の面（+x）：下屋の下は Kit の格子・勝手口の間割り、二階は出格子 2 と柱 5（真壁）（r2：大きな無地の漆喰の箱に読めた）
        ts1 = tmp()
        x = -zf
        for kind, wn in (('plain', 1.255), ('koshi', 1.75), ('door', 1.75), ('koshi', 1.75), ('koshi', 1.75), ('plain', 1.755)):
            if kind != 'plain':
                put(ts1, FR(kind, wn, B.hk), off=(x, 0.0, w / 2))
            x += wn
        for (za, zb) in ((-4.0, -1.6), (-0.6, 1.8)):
            deguchi(ts1, za, zb, 4.15, 5.35, w / 2, out=0.30)
        put(W, ts1, rot=math.pi * 0.5)
        for zp in (-zf + 0.06, -2.1, 0.0, 2.1, zf - 0.06):
            W.box((w / 2 - 0.01, 3.15, zp - 0.07), (w / 2 + 0.05, YE - 0.05, zp + 0.07), 'V2_Wood', DARK, grain=Y)
        W.box((w / 2 - 0.01, 2.9, -zf), (w / 2 + 0.06, 3.15, zf), 'V2_Wood', DARK * 0.9, grain=Z)      # 側面の胴差
        cloth(W, -1.317 + 0.12, 0.439 - 0.12, 2.30, 1.62, zf + 0.04, 'noren_d', seg_w=0.8, billow=0.03, rod=True)
    B.finish()
    return B


P6_BUILDERS = [build_mkt019, build_mkt021, build_mkt022, build_mkt003]

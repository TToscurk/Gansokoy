"""人間之里 V2 P13 W9 Phase 5：主街中段の 2 棟（MKT_023 市の角の米屋・MKT_028 隠居の仕舞屋）。

build_w9r2_arch.py が P4_BUILDERS の直後でこのファイルを exec する（単独実行はしない）。既存 38 棟の builder・封存済み Kit・共用 helper は一字も変えない。
使用者 2026-10-16（Phase 5 指派）：MKT_023＝正常 TPS で読める角地の輪郭（屋根・立面・街角の性格。小物を足すだけにしない）、
P10 R2 封存の街道附件（提灯・看板・幟）とその掛点は全部保持し、新建築の方を既存の制約に合わせる。
MKT_028＝隣の商家と対比のある住宅型。北から先に撮ってから設計を決める（北からは 029〔二階・間隔 0.2 m〕に完全に隠れる：
ID パスで画面の 0.06–0.12 %。見えるのは通りの向かい側から＝正面の構成と屋根の輪郭で読ませる）。

  MKT_023 市の角の米屋（主街×中橫街の北西角。南面＝中橫街に面する 10.9 m の長い面）：
    総二階（壁 5.5 m）＋入母屋（棟は主街と平行・南の妻を中橫街へ向ける。勾配 0.45・棟 約 8.0 m＝北隣 024〔7.34 m〕より少し高い角の『門柱』）
    ＋一階の回り庇（主街側と中橫街側の二面、角は隅棟で回す。壁際 3.85 m＝P10 の提灯綱・大看板の上）＋二階の出格子を主街側 2・中橫街側 2＋一階は米屋格子（平格子）。
    これまで角に向いていたのは無地の妻壁（vision：倉庫の側壁のよう）→ 角を回る庇・二面の出格子・入母屋の妻で『二面とも店の顔』にする。
  MKT_028 隠居の仕舞屋（027〔二階・飯屋〕と 029〔二階・土蔵の商家〕の間の平屋）：
    妻入の切妻（棟 約 4.7 m・生成りの壁の妻に粗い白木の木連格子＋懸魚）＋新木の格子と生成りの壁＋出格子 2 間＋格子戸と半暖簾＋段違いの霧除け庇（戸口の上だけ瓦で高く深く）。
    商家の開いた店先・連続した瓦庇・二階の窓列がない＝閉じた住まいの顔。

制約（W9 R2 の gate と同じ）：footprint・入口位置・body 碰撞は不変、屋根の碰撞は足さない。側面の出簷は隣棟との間隔以内
（028 の 029 側は 0.2 m → 0.15 m）、頭の高さ帯（y 1.1–1.8）・戸口の前に何も置かない。
023 の前と南の P10 附件（実頂点の範囲・023 局部）：提灯綱 000 z 6.28–6.54・y ≤ 3.34、市の大看板 x −2.20..−0.70・z 6.04–6.62・y ≤ 2.50、
大幟 x −3.15..−2.75・z 6.16–7.28、中橫街の提灯綱 096 x ≤ −3.16（竿 (−3.23, 5.27)）→ 前の出は z ≤ 5.96、南の出は x ≥ −3.10。
"""


def skirt_L(dst, lod, XG, ZG, YG, p, run, x_end, z_start):
    """角を回る一階の庇（L 字）：主街側（+z、x −XG〜x_end）と南側（−x、z z_start〜+ZG）の二面。角（−XG, +ZG）は隅棟で回す。
    hip_skirt（四方の裳階）と同じ屋面の組み方を二面だけにしたもの。返り値＝軒先の高さ。"""
    XE, ZE = XG + run, ZG + run
    y_e = YG - p * run
    sec = math.sqrt(1 + p * p)
    SH = run * sec
    ll = 2 if lod else 0
    # 主街側（+z）：左端（角）は隅棟へ広がり、右端（024 側）は真っ直ぐ切る
    o = (0.0, YG, ZG)
    dsl = norm((0.0, -p, 1.0))
    n = norm((0.0, 1.0, p))
    ax = (1.0, 0.0, 0.0)
    I.tile_band(dst, o, ax, dsl, n, lambda s: -(XG + s / sec), lambda s: x_end, SH, KW, ll, ends=(lod == 0))
    if lod == 0:
        I.under(dst, o, ax, dsl, n, lambda s: -(XG + s / sec), lambda s: x_end, SH)
        dst.beam(add((-XE, y_e, ZE), mul(n, -0.06)), add((x_end, y_e, ZE), mul(n, -0.06)), 0.07, 0.24, 'V2_Wood', DARK * 0.9, up=n)
    # 南側（−x）：奥の端は真っ直ぐ切り、手前（角）は隅棟へ
    o = (-XG, YG, 0.0)
    dsl = norm((-1.0, -p, 0.0))
    n2 = norm((-p, 1.0, 0.0))
    ax = (0.0, 0.0, 1.0)
    I.tile_band(dst, o, ax, dsl, n2, lambda s: z_start, lambda s: ZG + s / sec, SH, KW, ll, ends=(lod == 0))
    if lod == 0:
        I.under(dst, o, ax, dsl, n2, lambda s: z_start, lambda s: ZG + s / sec, SH)
        dst.beam(add((-XE, y_e, z_start), mul(n2, -0.06)), add((-XE, y_e, ZE), mul(n2, -0.06)), 0.07, 0.24, 'V2_Wood', DARK * 0.9, up=n2)
        dst.beam((-XG, YG + 0.03, z_start - 0.02), (-XE - 0.02, y_e + 0.03, z_start - 0.02), 0.035, 0.12, 'V2_Wood', DARK * 0.9)   # 奥の端のけらば板（切り口を見せない・細く）
    I.hip_ridge(dst, (-XG, YG, ZG), (-XE, y_e, ZE), lod, w=0.28, h=0.18)
    if lod == 0:
        end = (-XE, y_e, ZE)
        dn = norm(sub((-XG, YG, ZG), end))
        c0 = add(end, (0.0, 0.11, 0.0))
        dst.cyl(c0, add(c0, mul(dn, -0.07)), 0.12, 0.12, 12, 'V2_Kawara', 0.52, caps=(True, True))     # 隅棟の先の巴瓦
        nx = max(3, int(round((x_end + XE) / 0.52)))                                                  # 軒先の垂木尻（二面）
        for i in range(nx + 1):
            xx = -XE + (x_end + XE) * i / nx
            dst.box((xx - 0.035, y_e - 0.33, ZE + 0.03 - 0.07), (xx + 0.035, y_e - 0.2, ZE + 0.03 + 0.07), 'V2_Wood', DARK * 0.85, grain=Y)
        nz = max(3, int(round((ZE - z_start) / 0.52)))
        for i in range(nz + 1):
            zz = z_start + (ZE - z_start) * i / nz
            dst.box((-XE - 0.03 - 0.07, y_e - 0.33, zz - 0.035), (-XE - 0.03 + 0.07, y_e - 0.2, zz + 0.035), 'V2_Wood', DARK * 0.85, grain=Y)
    return y_e


def _skirt_L_frame(W, XG, ZG, YG, p, run, x_end, z_start):
    """L 字庇の壁際（雨押さえ・胴差）と腕木（1.1 m 以内の間隔）。lod0 のみ。"""
    y_e = YG - p * run
    W.box((-XG, YG - 0.05, ZG - 0.04), (x_end, YG + 0.06, ZG + 0.03), 'V2_Kawara', 0.75, grain=X)          # 雨押さえ（主街側）
    W.box((-XG - 0.03, YG - 0.05, z_start), (-XG + 0.04, YG + 0.06, ZG), 'V2_Kawara', 0.75, grain=Z)        # 雨押さえ（南側）
    nb = max(2, int(math.ceil((x_end + XG) / 1.1)))
    for i in range(nb + 1):
        xb = -XG + 0.15 + (x_end + XG - 0.3) * i / nb
        W.beam((xb, YG - 0.20, ZG - 0.02), (xb, y_e - 0.22, ZG + run - 0.12), 0.07, 0.10, 'V2_Wood', DARK)
    nb = max(2, int(math.ceil((ZG - z_start) / 1.1)))
    for i in range(nb + 1):
        zb = z_start + 0.15 + (ZG - z_start - 0.3) * i / nb
        W.beam((-XG + 0.02, YG - 0.20, zb), (-XG - run + 0.12, y_e - 0.22, zb), 0.07, 0.10, 'V2_Wood', DARK)


def build_mkt023():
    """B_P_MKT_023 市の角の米屋（Phase 5）：主街×中橫街の北西角。総二階＋入母屋（南の妻を中橫街へ）＋角を回る一階の瓦庇＋二面の出格子。
    入口＝x −0.867..0.867（Kit の shop_o と同じ）。北隣 024（油屋・白い塗籠・いぶし銀の瓦）と色を分け、瓦は風化の暖褐（tone 2）。"""
    B = Bld('B_P_MKT_023', 5.2, 10.92, 5.5, hk='h29', fin=2, tone=2)
    w, zf = B.w, B.zf
    # 一階の回り庇は P10 封存の提灯綱（gate の箱 y ≤ 3.30・x ±2.62・z ≥ 4.89）と大看板（y ≤ 2.46）の上を通す → 壁際 3.85 m・出 0.45 m
    # （軒先の垂木尻の下端 3.39 m・前端 z 6.01＜大幟の箱 6.09）。そのぶん二階が上がり、棟の勾配を 0.45 に落として棟高を 約 8.0 m に保つ。
    YE, Y1, RUN = 5.5, 3.85, 0.45
    bays1 = [('koshib', 0.867), ('koshib', 0.866), ('shop_o', 1.733), ('shop_k', 1.734)]   # 米屋格子 2 間・入口・店台
    Z0 = -zf + 0.25                                                                     # 南面（中橫街）の回り庇・腰板・格子窓は奥まで通す（r1 自己審圖：途中で切れた庇と奥の無地の壁が『倉の側面』に見えた）
    for lod in (0, 1):
        W, R, PR = B.W[lod], B.R[lod], B.P[lod]
        irimoya_roof(R, lod, w / 2, zf, YE, 0.45, 0.45, 1.40, 0.25, gw=W)
        skirt_L(R, lod, w / 2, zf, Y1, 0.30, RUN, w / 2 - 0.02, Z0)
        if lod == 1:
            W.box((-w / 2, FL, -zf), (w / 2, YE, zf), 'V2_Plaster', PL, grain=Y)
            continue
        _skirt_L_frame(W, w / 2, zf, Y1, 0.30, RUN, w / 2 - 0.02, Z0)
        assert abs(row1p(B, W, -w / 2, bays1) - w / 2) < 0.02
        W.box((-w / 2, 2.90, zf - 0.10), (w / 2, 3.06, zf + 0.06), 'V2_Wood', DARK * 0.9, grain=X)       # 差し鴨居（店構えの上）
        W.box((-w / 2, 3.06, zf - 0.10), (w / 2, Y1, zf), 'V2_Plaster', PL, grain=X)                     # 小壁（提灯綱の背景）
        W.box((-w / 2, Y1, zf - 0.10), (w / 2, YE, zf), 'V2_Plaster', PL, grain=X)                       # 二階の前壁（床の見付は庇の雨押さえが兼ねる＝暗い帯を重ねない）
        W.box((-w / 2 - 0.02, YE - 0.16, zf - 0.04), (w / 2 + 0.02, YE, zf + 0.07), 'V2_Wood', DARK, grain=X)    # 軒桁
        for (xa, xb) in ((-2.40, -0.30), (0.30, 2.40)):                                                   # 主街側の出格子 2
            deguchi(W, xa, xb, 4.20, 5.05, zf, out=0.30)
        _shell(B, W, YE)
        # 中橫街側（南面 x＝−w/2）：二階の出格子 2・一階の連子窓 2・腰板・差し鴨居・角柱
        tm = tmp()
        for (za, zb) in ((-4.9, -2.6), (-1.9, 0.9), (1.5, 4.9)):
            deguchi(tm, za, zb, 4.20, 5.05, w / 2, out=0.30)
        put(W, tm, rot=-math.pi * 0.5)
        for zc in (-3.75, -1.25, 1.25, 3.85):
            side_window(W, -w / 2, -1.0, zc, 0.95, 2.45, ww=1.5)
        W.box((-w / 2 - 0.03, FL, Z0), (-w / 2 + 0.01, 0.85, zf), 'V2_Wood', BOARD * 0.8, grain=Z)       # 腰板
        W.box((-w / 2 - 0.06, 2.90, Z0), (-w / 2 + 0.01, 3.06, zf), 'V2_Wood', DARK * 0.9, grain=Z)      # 差し鴨居（南面）
        W.box((-w / 2 - 0.05, FL, zf - 0.13), (-w / 2 + 0.08, YE, zf + 0.05), 'V2_Wood', DARK, grain=Y)    # 角柱（通し柱）
        # 背面（市の口＝西から正面に見える妻側）：二階の出格子 1・腰板・差し鴨居（r2 自己審圖：無地の端壁が『未完成の側面』に見えた）
        tm = tmp()
        deguchi(tm, -1.3, 1.3, 4.20, 5.05, zf, out=0.30)
        tm.box((-w / 2, FL, zf - 0.01), (w / 2, 0.85, zf + 0.03), 'V2_Wood', BOARD * 0.8, grain=X)
        tm.box((-w / 2, 2.90, zf - 0.01), (w / 2, 3.06, zf + 0.05), 'V2_Wood', DARK * 0.9, grain=X)
        put(W, tm, rot=math.pi)
        cloth(W, -0.867 + 0.12, 0.867 - 0.12, 2.35, 1.6, zf + 0.04, 'noren_b', seg_w=0.86, billow=0.03, rod=True)   # 入口の暖簾
    B.finish()
    return B


def kitsure(dst, zf, half, ye, H, p, step=0.20):
    """木連格子（妻の三角を縦横の細い格子で覆う）：妻面（z＝zf）の少し前。三角＝|x| ≤ (H−y)/p、y ≥ ye。"""
    zo = zf + 0.035
    y = ye + 0.12
    while y < H - 0.25:
        hw = (H - y) / p - 0.10
        if hw > 0.15:
            dst.box((-hw, y - 0.015, zf), (hw, y + 0.015, zo), 'V2_Wood', BOARD * 1.15, grain=X)
        y += step
    nx = int(half / step)
    for i in range(-nx, nx + 1):
        x = i * step
        top = H - abs(x) * p - 0.12
        if top - (ye + 0.10) > 0.12:
            dst.box((x - 0.015, ye + 0.10, zf), (x + 0.015, top, zo), 'V2_Wood', BOARD * 1.15, grain=Y)
    dst.box((-half - 0.04, ye - 0.02, zf - 0.02), (half + 0.04, ye + 0.12, zf + 0.06), 'V2_Wood', DARK, grain=X)   # 妻の梁


def build_mkt028():
    """B_P_MKT_028 隠居の仕舞屋（Phase 5）：妻入の切妻の平屋（棟 約 4.7 m）＋木連格子の妻＋懸魚、下見板の壁、出格子 2 間・格子戸・半暖簾、
    段違いの霧除け庇（左右は低い板庇、戸口の上だけ一段高く深い瓦庇）。入口＝x −0.437..1.309（Kit の戸口と同じ）。"""
    B = Bld('B_P_MKT_028', 6.11, 10.92, 3.0, hk='h27', fin=4, tone=0)     # 新木＋生成りの壁（両隣＝白っぽい漆喰＋暗い木。r2 の聚楽＋弁柄は日陰で泥色に沈んだ → 明るい白木の格子で値の差を作る）
    w, zf = B.w, B.zf
    YE, P = 3.0, 0.55
    xd0, xd1 = -0.437, 1.309
    bays1 = [('koshi', 1.309), ('koshi', 1.309), ('door', 1.746), ('mado', 1.746)]
    for lod in (0, 1):
        W, R, PR = B.W[lod], B.R[lod], B.P[lod]
        tm = tmp()
        H = gable_roof(tm, lod, B.d, w / 2, YE, P, 0.15, 0.40, tsuma=True, oni=True)        # 029 側の間隔 0.2 m → 軒の出 0.15 m
        put(R, tm, rot=-math.pi * 0.5)
        if lod == 1:
            W.box((-w / 2, FL, -zf), (w / 2, YE, zf), 'V2_Wood', BOARD * 0.72, grain=Y)
            continue
        eave_roof(R, lod, -w / 2 + 0.02, xd0 - 0.12, 2.62, zf, 0.55, p=0.30, style='board')             # 霧除け（左）
        eave_roof(R, lod, xd0 - 0.12, xd1 + 0.12, 2.86, zf, 0.80, p=0.30, style='tile')                 # 戸口の上：一段高く深い瓦庇
        eave_roof(R, lod, xd1 + 0.12, w / 2 - 0.02, 2.62, zf, 0.55, p=0.30, style='board')             # 霧除け（右）
        assert abs(row1p(B, W, -w / 2, bays1) - w / 2) < 0.02
        W.box((-w / 2, 2.62, zf - 0.08), (w / 2, YE, zf), 'V2_Plaster', PL * 1.25, grain=X)             # 霧除けの上の小壁（土壁。r2：正面が暗い → 明るめ）
        polyo(W, [(-w / 2, YE, zf + 0.012), (w / 2, YE, zf + 0.012), (0.0, H, zf + 0.012)], 'V2_Plaster', PL * 1.25)   # 妻の土壁（FIN が掛かる壁グループに描く）
        kitsure(W, zf, w / 2, YE, H, P, step=0.34)
        _board_sides(W, w, zf, YE)
        cloth(W, xd0 + 0.16, xd1 - 0.08, 2.20, 1.78, zf + 0.04, 'noren_c', seg_w=0.8, billow=0.02, rod=True)   # 半暖簾
        for k in range(6):                                                                             # 右の窓の下の犬矢来
            xx = xd1 + 0.18 + k * (w / 2 - 0.12 - xd1 - 0.18) / 5.0
            W.beam((xx, 0.88, zf + 0.01), (xx, 0.05, zf + 0.32), 0.03, 0.03, 'V2_Wood', BOARD * 0.55)
        W.beam((xd1 + 0.12, 0.88, zf + 0.02), (w / 2 - 0.08, 0.88, zf + 0.02), 0.04, 0.04, 'V2_Wood', BOARD * 0.55)
    B.finish()
    return B


P5_BUILDERS = [build_mkt023, build_mkt028]

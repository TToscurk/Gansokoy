# 入母屋屋根 —— 共用サブシステム
#
# `make_machiya.py` の `_roof()` は**切妻専用**で、あの一棟の中に閉じている。
# 鐘楼・寺子屋・火見櫓・格の高い店は入母屋が要る —— 同じ屋根を四回書き直す
# 前に、ここに一本出しておく。使う側は「三角形を積む builder」を渡すだけ
# （`quad / tri / box` の三つしか呼ばない）ので、MB でも B でも動く。
#
# ── 繞序について ────────────────────────────────────────────────
# 面の向きは**発明しない**。屋根面・鼻隠し・軒裏・妻壁は
# `make_machiya.py::_roof()` の並び順と flip をそのまま踏襲する
# （あれは 169 棟＋美術審査を通っている実績のある向き）。箱と柱は
# `box()` / `_leg()` の慣例。Blender は両面描画なので、ここを自分の
# 直感で書き直すと Godot で初めて消える。
#
# ── 入母屋の作図 ────────────────────────────────────────────────
# 母屋の高さ z_wall、勾配 pitch（弧度）、出簷 overhang。
#
#   ridge_z = z_wall + (D/2)·tanθ      棟は**壁面**に錨を打つ（切妻と同じ規矩）
#   eave_z  = z_wall - overhang·tanθ   出簷は同じ勾配で外へ下へ回る
#
# 破風（妻）の起点 `gable_at` は「軒から棟までの高さの何割で妻壁が立つか」。
# 四面同勾配にするには、水平方向の後退量が四面とも等しくなければならない
# ので、妻壁の x 位置は自由変数ではなく **xg = hw - hd·g** で決まる。棟の
# 長さもそれで決まる（棟は妻壁で終わる）。ここを別々に指定できるように
# すると、隅棟の勾配だけが違う「入母屋のようなもの」が出来る。
import math


def beam(bld, a, b, r, mat):
    """二点間の角材（柱・貫・垂木・隅棟・高欄、全部これ）。
    `make_town.py::_leg()` と同じ構成。"""
    d = [b[i] - a[i] for i in range(3)]
    L = math.sqrt(sum(c * c for c in d)) or 1.0
    d = [c / L for c in d]
    up = (0.0, 0.0, 1.0) if abs(d[2]) < 0.9 else (1.0, 0.0, 0.0)
    sx = [d[1] * up[2] - d[2] * up[1], d[2] * up[0] - d[0] * up[2],
          d[0] * up[1] - d[1] * up[0]]
    sl = math.sqrt(sum(c * c for c in sx)) or 1.0
    sx = [c / sl for c in sx]
    sy = [d[1] * sx[2] - d[2] * sx[1], d[2] * sx[0] - d[0] * sx[2],
          d[0] * sx[1] - d[1] * sx[0]]

    def corner(p, i, j):
        return tuple(p[k] + sx[k] * i * r + sy[k] * j * r for k in range(3))

    for (i0, j0, i1, j1) in ((-1, -1, 1, -1), (1, -1, 1, 1),
                             (1, 1, -1, 1), (-1, 1, -1, -1)):
        bld.quad(corner(a, i0, j0), corner(a, i1, j1),
                 corner(b, i1, j1), corner(b, i0, j0), mat)

    # ── 木口（端蓋）──────────────────────────────────────────
    # 側面 4 枚だけだと角材は**両端が開いた筒**になる。多くの角度では
    # 気付かないが、端が空中で終わる材（腕木の下端・撞木・高欄の端）
    # では筒の内側が直接見えてしまい、「接いでいない」как見える。
    # これが `non_manifold_edges` が常に頂点数と同じ値を返していた理由でも
    # ある——壊れた指標ではなく、全ての辺が開いていると正しく報告して
    # いた。ここを塞ぐと初めてあの数字が意味を持つ。
    #
    # 巻き方向：(sx, sy, d) は右手系（sx × sy = d）。b 側は法線 +d なので
    # (sx, sy) 平面で反時計回り、a 側は法線 -d なので逆順。
    bld.quad(corner(b, -1, -1), corner(b, 1, -1),
             corner(b, 1, 1), corner(b, -1, 1), mat)
    bld.quad(corner(a, -1, -1), corner(a, -1, 1),
             corner(a, 1, 1), corner(a, 1, -1), mat)


def frustum4(bld, cx, cy, z0, z1, hw0, hd0, hw1, hd1, mat, cap=None,
             skip_bottom=True):
    """矩形の錐台（石垣基壇・袴腰）。リングは xy 平面で反時計回り、
    面は `box()` と同じ「下リング → 上リング」の順（＝同じ向き）。"""
    def ring(z, hw, hd):
        return [(cx - hw, cy - hd, z), (cx + hw, cy - hd, z),
                (cx + hw, cy + hd, z), (cx - hw, cy + hd, z)]
    lo, hi = ring(z0, hw0, hd0), ring(z1, hw1, hd1)
    for k in range(4):
        k2 = (k + 1) % 4
        bld.quad(lo[k], lo[k2], hi[k2], hi[k], mat)
    if cap:
        bld.quad(hi[0], hi[1], hi[2], hi[3], cap)
    if not skip_bottom:
        bld.quad(lo[3], lo[2], lo[1], lo[0], mat)
    return hi


def irimoya_roof(bld, cx, cy, z_wall, W, D, pitch, overhang=1.35, thick=0.18,
                 gable_at=0.55, kawara="KAWARA", soffit="WOOD_LT",
                 barge="WOOD_LT", gable_wall="PLASTER", gyogyo_mat="WOOD",
                 rafters=True, courses=True, gyogyo=True, onigawara=True,
                 sori=0.0):
    """入母屋屋根一式。棟は x 方向（平入り）。

    構成：野地 → 鼻隠し → 軒裏 → 垂木 → 葺き足 → 隅棟 → 妻壁 →
          破風板 → 懸魚 → 棟（熨斗＋冠）→ 鬼瓦。

    戻り値は寸法辞書 —— 呼ぶ側が「軒がどこまで下りてくるか」を知らないと、
    軒の下に吊る物（梵鐘・提灯・暖簾）が屋根を突き抜ける。"""
    hw = W / 2.0 + overhang
    hd = D / 2.0 + overhang
    t = math.tan(pitch)
    eave_z = z_wall - overhang * t
    eave_edge_z = eave_z + sori
    ridge_z = z_wall + (D / 2.0) * t
    g = gable_at
    z_b = eave_z + (ridge_z - eave_z) * g
    xg = hw - hd * g                      # 妻壁の位置＝棟の半長（従属変数）
    assert xg > 0.35, "gable_at %.2f が深すぎて棟が消える（xg=%.2f）" % (g, xg)
    assert z_b < ridge_z - 0.05, "妻壁が棟に届いている"

    # ── 屋根面（前後の大面）────────────────────────────────────
    # 並びは _roof() と同一：上の稜 → 下の軒。
    # ⚠ flip は **(sy < 0)**。(sy > 0) だと法線が下向き —— Blender の双面
    # 描画では見えるが Godot では上から剔除され、屋根が抜ける。
    for sy in (1, -1):
        ye = cy + sy * hd
        yb = cy + sy * hd * (1.0 - g)
        bld.quad((cx - xg, yb, z_b), (cx + xg, yb, z_b),
                 (cx + hw, ye, eave_edge_z), (cx - hw, ye, eave_edge_z),
                 kawara, flip=(sy < 0))
        bld.quad((cx - xg, cy, ridge_z), (cx + xg, cy, ridge_z),
                 (cx + xg, yb, z_b), (cx - xg, yb, z_b),
                 kawara, flip=(sy < 0))

    # ── 屋根面（左右の隅＝降り棟の面）──────────────────────────
    # 前後の面を z 軸まわりに +90° 回した関係：sx=+1 ↔ sy=-1。
    for sx in (1, -1):
        xe = cx + sx * hw
        xb = cx + sx * xg
        bld.quad((xb, cy - hd * (1.0 - g), z_b), (xb, cy + hd * (1.0 - g), z_b),
                 (xe, cy + hd, eave_edge_z), (xe, cy - hd, eave_edge_z),
                 kawara, flip=(sx > 0))

    # ── 鼻隠し（軒口の小口）＋ 軒裏（仰視面）── 四周 ────────────
    # ⚠ 軒裏は四隅で **留め（45°）** に切る。四面とも全幅で張ると、隅で
    # 二枚が交差して屋根面を**下から突き破る** —— 隅から木の羽根が生えた
    # ように見える。最初の版がまさにそれで、5 枚全部に写っていた。
    # 出は四面とも overhang+0.05 なので、留めは常にちょうど 45°。
    y_in = D / 2.0 - 0.05
    x_in = W / 2.0 - 0.05
    inset = hd - y_in                      # ＝ hw - x_in ＝ overhang + 0.05
    for sy in (1, -1):
        ye = cy + sy * hd
        yi = cy + sy * y_in
        bld.quad((cx - hw, ye, eave_edge_z), (cx + hw, ye, eave_edge_z),
                 (cx + hw, ye, eave_edge_z - thick), (cx - hw, ye, eave_edge_z - thick),
                 kawara, flip=(sy < 0))
        bld.quad((cx - hw, ye, eave_edge_z - thick), (cx + hw, ye, eave_edge_z - thick),
                 (cx + hw - inset, yi, z_wall - thick),
                 (cx - hw + inset, yi, z_wall - thick),
                 soffit, flip=(sy < 0))
    for sx in (1, -1):
        xe = cx + sx * hw
        xi = cx + sx * x_in
        bld.quad((xe, cy - hd, eave_edge_z), (xe, cy + hd, eave_edge_z),
                 (xe, cy + hd, eave_edge_z - thick), (xe, cy - hd, eave_edge_z - thick),
                 kawara, flip=(sx > 0))
        bld.quad((xe, cy - hd, eave_edge_z - thick), (xe, cy + hd, eave_edge_z - thick),
                 (xi, cy + hd - inset, z_wall - thick),
                 (xi, cy - hd + inset, z_wall - thick),
                 soffit, flip=(sx > 0))

    # ── 垂木（出簷の分だけ。壁の内側は見えない）──────────────
    # 垂木も留めの内側だけ —— 隅は隅木の領分で、そこに平行垂木を伸ばすと
    # 軒裏と同じ理由で交差する。
    if rafters:
        zr = z_wall - thick - 0.02
        ze = eave_edge_z - thick - 0.02
        hx = hw - inset
        n = max(7, int(2 * hx / 0.46))
        for sy in (1, -1):
            for k in range(n + 1):
                x = cx - hx + k * (2 * hx / n)
                beam(bld, (x, cy + sy * y_in, zr), (x, cy + sy * hd, ze),
                     0.036, "WOOD")
        hy = hd - inset
        n = max(7, int(2 * hy / 0.46))
        for sx in (1, -1):
            for k in range(n + 1):
                y = cy - hy + k * (2 * hy / n)
                beam(bld, (cx + sx * x_in, y, zr), (cx + sx * hw, y, ze),
                     0.036, "WOOD")

    # ── 葺き足（瓦の列。遠景でこれが無いと屋根が一枚の板になる）──
    if courses:
        ncourse = 5
        for k in range(1, ncourse + 1):
            f = float(k) / (ncourse + 1)
            z = eave_z + (ridge_z - eave_z) * f
            dx = hd * min(f, g)                     # 隅の切り込み量
            for sy in (1, -1):
                y = cy + sy * hd * (1.0 - f)
                beam(bld, (cx - (hw - dx), y, z), (cx + (hw - dx), y, z),
                     0.045, kawara)
            if f < g:                               # 隅面は妻壁の下だけ
                for sx in (1, -1):
                    x = cx + sx * (hw - hd * f)
                    beam(bld, (x, cy - hd * (1.0 - f), z),
                         (x, cy + hd * (1.0 - f), z), 0.045, kawara)

    # ── 隅棟（入母屋がそう読めるかどうかは、この四本で決まる）──
    for sx in (1, -1):
        for sy in (1, -1):
            beam(bld, (cx + sx * hw, cy + sy * hd, eave_edge_z + 0.04),
                 (cx + sx * xg, cy + sy * hd * (1.0 - g), z_b + 0.04),
                 0.085, kawara)

    # ── 妻壁 ＋ 破風板 ＋ 懸魚 ──────────────────────────────
    for sx in (1, -1):
        gx = cx + sx * xg
        yf, yk = cy - hd * (1.0 - g), cy + hd * (1.0 - g)
        bld.tri((gx, yf, z_b), (gx, yk, z_b), (gx, cy, ridge_z),
                gable_wall, flip=(sx < 0))
        for sy in (1, -1):
            beam(bld, (gx + sx * 0.045, cy + sy * hd * (1.0 - g), z_b),
                 (gx + sx * 0.045, cy, ridge_z + 0.05), 0.085, barge)
        if gyogyo:
            # 懸魚は破風から**吊り下がる**——下に何も無いので底面が要る。
            bld.box(gx + sx * 0.075, cy, ridge_z - 0.36, 0.09, 0.34, 0.44,
                    gyogyo_mat, skip_bottom=False)

    # ── 棟：熨斗瓦の層 + 冠瓦 + 鬼瓦 ──────────────────────────
    # 熨斗瓦の箱は**屋根面まで下ろして埋める**。底面を ridge_z に合わせると、
    # 箱は y 方向に ±0.24 あるのに屋根面はそこで既に ridge_z - 0.24·tan(pitch)
    # まで下がっているため、大棟に沿って三角形の空洞が通しで開く。妻壁の
    # 三角形は頂点が ridge_z の一点なのでそれを塞げず、妻側から見ると
    # 大棟の下に暗い隙間が抜けて見える。実物の熨斗瓦も屋根面に座るので、
    # 下端を屋根面より下に落とすのが形としても正しい。
    #
    # `skip_bottom=False` は必須。box() は既定で底面を省く（地面や他の材に
    # 座る箱では見えないので面数の節約になる）が、屋根は薄い殻であって
    # 中身は鐘室の空気なので、下ろした熨斗瓦の底は**そのまま空洞に face
    # している**。省いたままだと妻側から箱の内側が見えて、大棟の下に黒い
    # 楔が現れる——上の空洞を塞いだ結果、今度は箱自身が穴になる。
    _nz = 0.24 * math.tan(pitch) + 0.03      # 箱の半幅における屋根面の落差
    bld.box(cx, cy, ridge_z + 0.075 - _nz / 2.0,
            2 * xg + 0.26, 0.48, 0.15 + _nz, kawara, skip_bottom=False)
    beam(bld, (cx - xg - 0.13, cy, ridge_z + 0.22),
         (cx + xg + 0.13, cy, ridge_z + 0.22), 0.13, kawara)
    if onigawara:
        for sx in (1, -1):
            # 鬼瓦は大棟の端に立つ。妻側は下が抜けているので底面が要る。
            bld.box(cx + sx * (xg + 0.16), cy, ridge_z + 0.30,
                    0.12, 0.34, 0.50, kawara, skip_bottom=False)

    return {"ridge_z": ridge_z, "eave_z": eave_z, "gable_z": z_b,
            "gable_x": xg, "hw": hw, "hd": hd,
            "top_z": ridge_z + 0.55, "soffit_z": z_wall - thick}

# PHASE 2.5 —— 店先・生活の道具（facade & life dressing components）
#
#   blender -b -P godot/assets/blender/make_facade.py -- godot/assets/models
#
# ══════════════════════════════════════════════════════════════════════
# なぜ make_props.py に足さないのか
# ══════════════════════════════════════════════════════════════════════
# make_props.py は「有機造型を彫る」ための場所（龍・鴨・鯉・岩）で、
# もう検証済みの出力が village 全体に散っている。Phase 2.5 が足すのは
# **店の顔と暮らしの痕跡**という別の目的の一群なので、別ファイルにする。
# 唯一の例外は `prop_chochin` —— 既存が明らかに新しい品質基準を下回って
# いる（10 面の提灯は眼高で黄色い多角形の塊に読める）ので**差し替え**る。
# 差し替えの範囲と代償は docs/PROJECT_STATE.md の Known Risks に書く。
#
# ── 這一輪的構圖原則（道具を散らすのではなく、業を語る）──
#   店  ：商品が**街を向いて**並ぶ。客の動線の上に置く
#   住  ：物は**壁際に寄せて**しまう。街に出さない
#   工房：物は**仕事のまわり**に置く。戸口と水場から手の届く範囲
# 同じ樽でも、積み方と置き場所で「売り物」と「道具」に分かれる。
import bpy
import math
import random
import sys
import os

OUT_DIR = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "godot/assets/models"
os.makedirs(OUT_DIR, exist_ok=True)
TAU = math.pi * 2

# ── 幾何ヘルパ ──
# ⚠ make_props.py と同じ実装をここに複製している。import しないのは、
#   あちらがモジュール末尾で make_dragon() 以下を**素で呼んでいる**ため
#   —— import した瞬間に全資産が再生成されてしまう。
#   四つの小さな関数を写すほうが、検証済みのファイルに手を入れるより安い。


def clear():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for m in list(bpy.data.meshes):
        bpy.data.meshes.remove(m)


def box_verts(cx, cy, cz, sx, sy, sz):
    v = [(cx + dx * sx / 2, cy + dy * sy / 2, cz + dz * sz / 2)
         for dx, dy, dz in [(-1, -1, -1), (1, -1, -1), (1, 1, -1), (-1, 1, -1),
                            (-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)]]
    f = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    return v, f


def merge(*parts):
    verts, faces = [], []
    for pv, pf in parts:
        off = len(verts)
        verts.extend(pv)
        faces.extend([tuple(i + off for i in f) for f in pf])
    return verts, faces


def sweep(path_pts, radii, sides=8, close_start=True, close_end=True, squash=None):
    verts, faces = [], []
    n = len(path_pts)
    for i, p in enumerate(path_pts):
        a = path_pts[max(i - 1, 0)]
        b = path_pts[min(i + 1, n - 1)]
        t = [b[k] - a[k] for k in range(3)]
        tl = math.sqrt(sum(c * c for c in t)) or 1.0
        t = [c / tl for c in t]
        up = (0.0, 1.0, 0.0) if abs(t[1]) < 0.9 else (1.0, 0.0, 0.0)
        u = [t[1] * up[2] - t[2] * up[1], t[2] * up[0] - t[0] * up[2],
             t[0] * up[1] - t[1] * up[0]]
        ul = math.sqrt(sum(c * c for c in u)) or 1.0
        u = [c / ul for c in u]
        v = [t[1] * u[2] - t[2] * u[1], t[2] * u[0] - t[0] * u[2],
             t[0] * u[1] - t[1] * u[0]]
        sw, sh = squash[i] if squash else (1.0, 1.0)
        for s in range(sides):
            ang = TAU * s / sides
            r = radii[i]
            verts.append((p[0] + (u[0] * math.cos(ang) * sw + v[0] * math.sin(ang) * sh) * r,
                          p[1] + (u[1] * math.cos(ang) * sw + v[1] * math.sin(ang) * sh) * r,
                          p[2] + (u[2] * math.cos(ang) * sw + v[2] * math.sin(ang) * sh) * r))
    for i in range(n - 1):
        for s in range(sides):
            s2 = (s + 1) % sides
            faces.append((i * sides + s, i * sides + s2,
                          (i + 1) * sides + s2, (i + 1) * sides + s))
    if close_start:
        faces.append(tuple(range(sides - 1, -1, -1)))
    if close_end:
        faces.append(tuple(range((n - 1) * sides, n * sides)))
    return verts, faces


def mesh_from(name, verts, faces, color_fn=None, smooth=True):
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    if color_fn:
        attr = me.color_attributes.new(name="Col", type="BYTE_COLOR", domain="CORNER")
        for poly in me.polygons:
            for li in poly.loop_indices:
                v = me.vertices[me.loops[li].vertex_index]
                r, g, b = color_fn(v.co, poly.normal)
                attr.data[li].color = (r, g, b, 1.0)
    if smooth:
        for p in me.polygons:
            p.use_smooth = True
    return ob


def export(ob, name):
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    ob.name = name
    path = os.path.join(OUT_DIR, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, use_selection=True, export_format="GLB",
                              export_yup=True, export_apply=True)
    print("exported %s（%d 面）" % (path, len(ob.data.polygons)))


# ── 色（make_props.py のパレットと同じ系統。町並みの色相を割らない）──
W_LT = (0.300, 0.235, 0.165)        # 明るい木
W_DK = (0.165, 0.135, 0.110)        # 暗い木
W_ST = (0.245, 0.195, 0.145)        # 樽板
STRAW = (0.560, 0.470, 0.275)       # 藁・俵
ROPE = (0.400, 0.345, 0.235)        # 縄
AI = (0.115, 0.150, 0.235)          # 藍染
AI_LT = (0.230, 0.295, 0.400)       # 藍の淡い方（何度も染めていない反）
CEDAR = (0.230, 0.310, 0.165)       # 杉葉（青い杉玉）
CEDAR_DRY = (0.330, 0.280, 0.150)   # 枯れかけの杉葉
CLAY = (0.135, 0.120, 0.115)        # 藍甕の釉
# ⚠ 提灯の紙は (0.78,0.56,0.23) だと画面では**金色の卵**に読める（Phase 2.5
# の一回目のレンダで判明）。紙は白に近い暖色で、火を入れていない昼間は
# くすんでいる —— 彩度を落として明度を上げるほうが「紙」に見える
PAPER = (0.720, 0.640, 0.480)       # 提灯の火袋（昼・火なし）
SIGN = (0.700, 0.655, 0.560)        # 看板の字板
BAMBOO = (0.325, 0.270, 0.170)      # 竹の笊（既存 prop_basket より暗い）
# ⚠ 簾に STRAW を流用したら黄色すぎて画面で浮いた（c2/c7）。
# 日に焼けた竹は彩度が低く、屋根や腰板の色域に近い
BAMBOO_DRY = (0.360, 0.315, 0.205)  # 簾（日焼けした竹）
GOODS = (0.300, 0.255, 0.150)       # 盛った乾物・穀


# ── 布のヘルパ（PHASE 2.6）──
# 布が変形に使ってよい割合の下限。クリアランスが厳しくても**ここまでは
# 残す** —— 0 にすると布ではなく板になる。これ以上詰まる場所は、変形では
# なく**配置**が間違っている（そのときは配置を直すこと）。
CLOTH_FLOOR = 0.28


def cloth_strip(cx, top_z, w, h, rows=6, cols=4, sway=0.06, bow=0.035,
                tilt=0.0, phase=0.0, ripple=0.014,
                clear_front=None, clear_side=None, thick=0.012):
    """吊るした布の一枚。**平らな長方形ではなく**、下端ほど前へ流れ
    （sway・t^1.8）、幅方向に膨らみ（bow）、細かい波（ripple）が入る。

    ── PHASE 2.6b：クリアランス規則（再利用可能・個別パッチにしない）──
    `clear_front` … 手前にある物（庇の前桁・隣の柱・次の布）までの空き[m]。
        前方向の最大振れは sway+bow+ripple+thick。これが空きを超えるとき、
        **三つをまとめて同じ率で**縮める —— 形の比率は保ったまま量だけ落ちる。
    `clear_side` … 幅方向の空き[m]。tilt による裾の横ずれ |tilt|·w を頭打ちに。
    どちらも None なら無制限（既存の呼び出しはそのまま）。

    ⚠ 縮める率には下限 `CLOTH_FLOOR` がある。呼び出し側が非現実的な
      クリアランスを渡しても布は板にならない —— 代わりに**まだ当たる**。
      当たったらそれは配置のバグで、変形で隠すべきではない。

    ⚠ 面は**表裏二枚**貼る。厚み 0 の一枚板は Godot が背面剔除して、
      裏へ回った瞬間に消える —— docs §3 の参道と同じ罠。表裏を最初から
      張れば、巻き順の向きを推理する必要そのものが消える。"""
    if clear_front is not None:
        peak = sway + bow + ripple + thick
        if peak > 1e-6:
            k = max(CLOTH_FLOOR, min(1.0, clear_front / peak))
            sway, bow, ripple = sway * k, bow * k, ripple * k
    if clear_side is not None and abs(tilt) * w > clear_side:
        tilt = math.copysign(clear_side / max(w, 1e-6), tilt)
    # ⚠ 裏面は**頂点ごと複製**して 0.012 奥にずらす。最初は同じ頂点で
    # 巻き順だけ反転した面を重ねたが、from_pydata の検証が「重複面」として
    # **黙って捨てて**いた（"Mesh not valid" の警告＋面数が半分で発覚）。
    front = []
    for j in range(rows + 1):
        t = j / rows
        z = top_z - t * h
        for i in range(cols + 1):
            u = i / cols
            x = cx - w / 2 + u * w + tilt * t * w
            y = -(sway * (t ** 1.8) + bow * math.sin(u * math.pi) * t
                  + ripple * math.sin((u * 2.2 + phase) * TAU) * t)
            front.append((x, y, z))
    back = [(x, y + thick, z) for x, y, z in front]
    verts = front + back
    off = len(front)
    faces = []
    for j in range(rows):
        for i in range(cols):
            a = j * (cols + 1) + i
            b = a + 1
            c = a + cols + 2
            d = a + cols + 1
            faces.append((a, b, c, d))
            faces.append((off + a, off + d, off + c, off + b))
    return verts, faces


def make_noren(name, width, n_flap, base_col, h=0.62, seed=7):
    """暖簾 v2（PHASE 2.6）。旧 prop_noren_a/b は**箱を並べただけ**で、
    建築の質が上がった今、正面のど真ん中で一番「プリミティブ」に見える
    ものになっていた。ここでは布として作る：
      ・上端 0.09 は縫い合わせた一枚（かけ）—— 分かれるのは裾だけ
      ・flap ごとに長さ ±2cm、揺れの位相、傾き 0.5° を変える
      ・裾は前へ流れ、幅方向に膨らむ（cloth_strip）
    ⚠ village が使う旧資産は残す。これは**新名義**で slice だけが参照する。
    アンカーは旧と同じ：竿の中心 z≈0、布は下へ。"""
    clear()
    rng = random.Random(seed)
    # ⚠ gap 0.022 は正面から見ると 1px も無く、暖簾が**一枚の板**に読めた
    # （c2 の正対カットで発覚）。0.055 なら裾の割れが距離をおいても残る。
    # clear_side に gap/2 を渡してあるので、広げても裾は隣と当たらない。
    gap = 0.055
    fw = (width - (n_flap - 1) * gap) / n_flap
    parts = [sweep([(-width / 2 - 0.06, 0, 0.012), (width / 2 + 0.06, 0, 0.012)],
                   [0.022, 0.022], sides=7)]                        # 掛竿
    band_h = 0.09
    # ⚠ 上帯の天は竿の**下端**（0.012−0.022 = −0.010）から。最初は 0.004 で
    # 始めていて、竿の芯を布が貫いていた（d2 の近景で発覚）。
    band_top = -0.011
    parts.append(cloth_strip(0.0, band_top, width, band_h, rows=2, cols=8,
                             sway=0.010, bow=0.016, ripple=0.005,
                             clear_front=0.05))                      # かけ（上帯）
    for i in range(n_flap):
        cx2 = -width / 2 + fw / 2 + i * (fw + gap)
        hh = h - band_h + rng.uniform(-0.050, 0.030)      # 裾の高さを揃えない
        # 隣の裾と当たらない範囲でしか傾けない（gap の半分まで）
        fv, ff = cloth_strip(cx2, band_top - band_h, fw, hh, rows=6, cols=3,
                             sway=rng.uniform(0.05, 0.09),
                             bow=rng.uniform(0.02, 0.045),
                             tilt=rng.uniform(-0.02, 0.02),
                             phase=rng.random(),
                             clear_front=0.16, clear_side=gap * 0.5)
        # 一枚ずつ奥行きをずらす —— 全部が同一平面に並ぶと、割れていても
        # 面としては一枚に見える。0〜18mm でいい
        dy = -rng.uniform(0.0, 0.018)
        parts.append(([(x, y + dy, z) for x, y, z in fv], ff))
    v, f = merge(*parts)

    def col(co, n):
        if co.z > -0.005 and abs(co.y) < 0.03 and co.z > 0.0:
            return W_DK                                              # 竿
        t = -co.z / h
        k = 1.0 - 0.16 * t                                           # 裾ほど沈む
        if co.z < -h * 0.86:
            k *= 1.28                                                # 裾の縫い代
        # 布の膨らみで受ける光：前に出ている所（y が浅い）ほど明るい
        k *= 1.0 + 0.7 * (co.y + 0.06)
        return tuple(min(1.0, max(0.0, c * k)) for c in base_col)

    export(mesh_from(name, v, f, col, smooth=False), name)


def make_taru():
    """樽 v2（PHASE 2.6）。旧 prop_barrel は 10 面スイープで、酒屋の店先で
    三角積みの**主役**になった途端、多角形の胴が一番目立つ欠点になった。
    16 面＋箍を**幾何**で三本（旧は色を塗っただけ）＋天端の縁。
    ⚠ 旧資産は village が使うので残す。寸法・アンカーは旧と同じ
    （接地 z=0、高さ 0.78、最大半径 0.315）。"""
    clear()
    zs = [0.00, 0.025, 0.11, 0.40, 0.67, 0.755, 0.78]
    rr = [0.262, 0.292, 0.306, 0.322, 0.306, 0.292, 0.262]
    parts = [sweep([(0, 0, z) for z in zs], rr, sides=16)]
    for hz, hr in ((0.135, 0.310), (0.40, 0.325), (0.655, 0.311)):   # 箍
        parts.append(sweep([(0, 0, hz - 0.019), (0, 0, hz + 0.019)],
                           [hr + 0.007, hr + 0.007], sides=16))
    parts.append(sweep([(0, 0, 0.755), (0, 0, 0.79)],
                       [0.268, 0.262], sides=16))                    # 天端の縁
    v, f = merge(*parts)

    def col(co, n):
        for hz in (0.135, 0.40, 0.655):
            if abs(co.z - hz) < 0.024 and math.hypot(co.x, co.y) > 0.30:
                return (0.150, 0.125, 0.100)                         # 箍（鉄・竹）
        if n.z > 0.7 and co.z > 0.7:
            return (0.285, 0.230, 0.160)                             # 鏡（天板）
        stave = int((math.atan2(co.y, co.x) + TAU) / TAU * 16) % 2
        k = (0.90 + 0.11 * stave) * (0.90 + 0.20 * co.z / 0.78)
        return tuple(min(1.0, c * k) for c in W_ST)

    export(mesh_from("prop_taru", v, f, col, smooth=False), "prop_taru")


def make_kago():
    """竹籠 v2（PHASE 2.6）。旧 prop_basket（9 面の二段積み）の前景版。
    12 面・口縁の巻きを幾何で・編み目は環×縦の市松。接地 z=0。"""
    clear()
    zs = [0.00, 0.035, 0.14, 0.30, 0.43]
    rr = [0.140, 0.198, 0.243, 0.262, 0.246]
    parts = [sweep([(0, 0, z) for z in zs], rr, sides=12)]
    parts.append(sweep([(0, 0, 0.408), (0, 0, 0.452)],
                       [0.258, 0.252], sides=12))                    # 口縁の巻き
    v, f = merge(*parts)

    def col(co, n):
        if co.z > 0.405:
            return tuple(min(1.0, c * 1.20) for c in BAMBOO)
        ring = int(co.z / 0.048) % 2
        stave = int((math.atan2(co.y, co.x) + TAU) / TAU * 12) % 2
        k = 0.82 + 0.11 * ring + 0.10 * stave
        return tuple(min(1.0, c * k) for c in BAMBOO)

    export(mesh_from("prop_kago", v, f, col, smooth=False), "prop_kago")


def make_sudare():
    """簾（PHASE 2.6・立面の上段を埋める垂直要素）。虫籠窓や二階の窓の
    外に掛ける日除け。横桟の縞＋下端の巻き＋吊り紐二本。
    アンカーは上端 z=0（提灯と同じ規約）、正面 −y。"""
    clear()
    # ⚠ H 1.04 では庇の上端と主屋根の軒裏のあいだ（f_a で約 1.05m）に
    # 吊り紐ぶんが入らなかった。0.78 なら余裕 0.13m。
    W, H = 0.92, 0.78
    parts = [cloth_strip(0.0, 0.0, W, H, rows=5, cols=3,
                         sway=0.045, bow=0.012, ripple=0.004,
                         clear_front=0.13)]
    parts.append(sweep([(-W / 2, -0.052, -H), (W / 2, -0.052, -H)],
                       [0.034, 0.034], sides=8))                     # 下端の巻き
    for sx in (1, -1):                                               # 吊り紐
        parts.append(sweep([(sx * W * 0.30, -0.006, 0.08),
                            (sx * W * 0.30, -0.010, -H * 0.55)],
                           [0.006, 0.006], sides=4))
    v, f = merge(*parts)

    def col(co, n):
        if co.z > 0.02 or (abs(abs(co.x) - W * 0.30) < 0.012 and co.y > -0.03):
            return ROPE
        if co.z < -H + 0.05:
            k = 0.95 + 0.10 * (int((co.x + 1.0) / 0.05) % 2)
            return tuple(min(1.0, c * k) for c in W_ST)              # 巻き
        slat = int(-co.z / 0.032) % 2                                # 横桟の縞
        k = (0.88 + 0.13 * slat) * (1.0 + 0.35 * (co.y + 0.05))
        return tuple(min(1.0, max(0.0, c * k)) for c in BAMBOO_DRY)

    export(mesh_from("prop_sudare", v, f, col, smooth=False), "prop_sudare")


def make_hoshigaki():
    """干し柿の吊るし紐（PHASE 2.6・軒下の垂直要素）。八百屋・乾物屋の
    軒から下がる縄に柿が連なる —— 季節の記号で、遠目にも橙の点列で読める。
    アンカーは上端 z=0。"""
    clear()
    rng = random.Random(41)
    parts = [sweep([(0, 0, 0.0), (0, 0, -0.86)], [0.008, 0.008], sides=4)]
    kakis = []
    for k in range(6):
        z = -0.13 - k * 0.125
        dx = (0.030 if k % 2 == 0 else -0.030) + rng.uniform(-0.008, 0.008)
        kakis.append((dx, z))
        parts.append(sweep([(dx, 0, z + 0.038), (dx, 0, z + 0.012),
                            (dx, 0, z - 0.030), (dx, 0, z - 0.048)],
                           [0.012, 0.042, 0.038, 0.012], sides=7))
    v, f = merge(*parts)

    def col(co, n):
        for dx, z in kakis:
            if abs(co.x - dx) < 0.05 and abs(co.z - z + 0.005) < 0.055:
                k = 0.85 + 0.30 * max(0.0, n.z) + 0.10 * math.sin(co.x * 60)
                return tuple(min(1.0, c * k) for c in (0.560, 0.265, 0.095))
        return ROPE

    export(mesh_from("prop_hoshigaki", v, f, col, smooth=False), "prop_hoshigaki")


def make_somenuno():
    """染め上げた反物を高く干す一枚（PHASE 2.6・紺屋の上段用）。
    monohoshi（低い物干し）より上、軒に近い高さから 1.9m 垂れる。
    アンカーは上端 z=0。"""
    clear()
    parts = [sweep([(-0.26, 0, 0.008), (0.26, 0, 0.008)], [0.016, 0.016], sides=6)]
    # ⚠ 1.88m では庇と主屋根のあいだ（約 1.09m）に絶対入らず、庇を
    # 突き抜けていた（d3 の近景）。庇の**下**に吊る前提の 1.26m に。
    parts.append(cloth_strip(0.0, 0.0, 0.42, 1.26, rows=7, cols=3,
                             sway=0.13, bow=0.045, ripple=0.018, phase=0.3,
                             clear_front=0.20))
    v, f = merge(*parts)

    def col(co, n):
        if co.z > -0.01 and abs(co.y) < 0.03:
            return W_DK
        t = -co.z / 1.26
        base = tuple(AI[i] * (0.75 + 0.5 * t) for i in range(3))     # 下ほど濃い
        k = 1.0 + 0.6 * (co.y + 0.08)
        return tuple(min(1.0, max(0.0, c * k)) for c in base)

    export(mesh_from("prop_somenuno", v, f, col, smooth=False), "prop_somenuno")


# ══════════════════════════════════ 提灯（差し替え）══════════════════
def make_chochin():
    """既存は 10 面・輪なし・紐なしで、眼高だと黄色い多角形の塊に読めた。

    上下の輪・骨の稜・吊り紐・家紋の帯を入れて 16 面に。
    ⚠ **アンカーと寸法は変えない**（上端 z=0、全長 0.52、最大半径 0.175）
      —— 既存の配置コードが持っている座標をそのまま使えるようにする。
    """
    clear()
    zs = [0.0, -0.028, -0.075, -0.14, -0.26, -0.38, -0.445, -0.492, -0.52]
    rr = [0.052, 0.062, 0.118, 0.158, 0.176, 0.158, 0.118, 0.066, 0.056]
    body = sweep([(0, 0, z) for z in zs], rr, sides=16)
    parts = [body]
    # 上下の輪（竹の口輪。ここが無いと「紙の袋」に見えない）
    parts.append(sweep([(0, 0, 0.004), (0, 0, -0.030)], [0.058, 0.058], sides=16))
    parts.append(sweep([(0, 0, -0.490), (0, 0, -0.524)], [0.062, 0.062], sides=16))
    # 吊り紐（上に伸びる。軒桁に掛かっているという情報）
    # ⚠ 0.30 は庇の下に収まらなかったので 0.16。UP_CHOCHIN と揃えること
    parts.append(sweep([(0, 0, 0.16), (0, 0, 0.004)], [0.009, 0.009], sides=5))
    v, f = merge(*parts)

    def col(co, n):
        if co.z > 0.02:
            return ROPE
        if co.z > -0.034 or co.z < -0.486:
            return W_DK                                  # 口輪
        rib = int((math.atan2(co.y, co.x) + TAU) / TAU * 16) % 2
        # 家紋の帯：胴の真ん中に一本、暗い横帯（字は入れない）
        crest = -0.30 < co.z < -0.22
        k = (1.04 - 0.48 * abs(co.z + 0.26) / 0.26) * (0.93 + 0.09 * rib)
        base = W_DK if crest else PAPER
        if crest:
            return base
        return tuple(min(1.0, c * (0.56 + 0.42 * k)) for c in base)

    export(mesh_from("prop_chochin", v, f, col, smooth=False), "prop_chochin")


# ══════════════════════════════════ 杉玉 ═══════════════════════════════
def make_sugidama():
    """酒屋の看板。新酒ができると青い杉玉を吊るし、枯れる速さで
    酒の熟成を知らせる —— 字の読めない客にも通じる、町で一番強い商標。

    アンカーは上端 z=0（提灯と同じ規約）。玉の中心 z=−0.46、直径 0.62。"""
    clear()
    rng = random.Random(83)
    cz, R = -0.46, 0.31
    n_ring = 9
    zs, rs = [], []
    for i in range(n_ring):
        t = i / (n_ring - 1)
        zs.append(cz + R * math.cos(math.pi * t))
        rs.append(R * math.sin(math.pi * t) * rng.uniform(0.93, 1.07))
    rs[0] = 0.02
    rs[-1] = 0.02
    ball = sweep([(0, 0, z) for z in zs], rs, sides=14)
    # 杉葉の房：球面から短い枝を生やす。無いとただの緑の球
    parts = [ball]
    for k in range(46):
        a = rng.uniform(0, TAU)
        e = math.acos(rng.uniform(-0.92, 0.92))
        d = (math.sin(e) * math.cos(a), math.sin(e) * math.sin(a), math.cos(e))
        p0 = (d[0] * R * 0.86, d[1] * R * 0.86, cz + d[2] * R * 0.86)
        ln = rng.uniform(0.045, 0.105)
        p1 = (p0[0] + d[0] * ln, p0[1] + d[1] * ln, p0[2] + d[2] * ln)
        parts.append(sweep([p0, p1], [0.030, 0.006], sides=4))
    # 吊り縄 + 玉を締める輪
    parts.append(sweep([(0, 0, 0.0), (0, 0, cz + R * 0.9)], [0.011, 0.011], sides=5))
    v, f = merge(*parts)

    def col(co, n):
        if co.z > cz + R * 0.92:
            return ROPE
        # 上から枯れる：てっぺんが茶、下がまだ青い（吊るして数か月）
        t = (co.z - (cz - R)) / (2 * R)
        base = tuple(CEDAR[i] * (1 - t * 0.72) + CEDAR_DRY[i] * (t * 0.72) for i in range(3))
        k = 0.82 + 0.30 * max(0.0, n.z)
        return tuple(min(1.0, c * k) for c in base)

    export(mesh_from("prop_sugidama", v, f, col, smooth=False), "prop_sugidama")


# ══════════════════════════════════ 米俵 ═══════════════════════════════
def make_tawara():
    """横に寝かせた俵。縄の胴締め三本と、両端の**藁の巻き終わり**が
    無いと、ただの円柱に見える。地面アンカー（z=0 が接地）。"""
    clear()
    L, R = 0.74, 0.205
    body = sweep([(-L / 2, 0, R), (-L / 2 + 0.06, 0, R * 1.03),
                  (L / 2 - 0.06, 0, R * 1.03), (L / 2, 0, R)],
                 [R * 0.86, R, R, R * 0.86], sides=11)
    parts = [body]
    for bx in (-0.22, 0.0, 0.22):                       # 縄の胴締め
        parts.append(sweep([(bx - 0.022, 0, R), (bx + 0.022, 0, R)],
                           [R * 1.06, R * 1.06], sides=11))
    v, f = merge(*parts)

    def col(co, n):
        if any(abs(co.x - bx) < 0.030 for bx in (-0.22, 0.0, 0.22)):
            return ROPE
        # 藁の縦目：角度で明暗を割る
        ang = math.atan2(co.y, co.z - R)
        stripe = int((ang + TAU) / TAU * 11) % 2
        k = (0.86 + 0.14 * stripe) * (0.84 + 0.24 * max(0.0, n.z))
        if abs(co.x) > L / 2 - 0.07:                    # 巻き終わりの端
            k *= 0.88
        return tuple(min(1.0, c * k) for c in STRAW)

    export(mesh_from("prop_tawara", v, f, col, smooth=False), "prop_tawara")


# ══════════════════════════════════ 見世棚 ═════════════════════════════
def make_misedai():
    """見世棚（みせだな）：格子の下から街へ張り出す**商品を並べる台**。

    町家が「家」ではなく「店」に見えるかどうかは、ほぼこれ一つで決まる。
    平台 + 奥に少し起こした斜めの棚（商品が客に見えるように傾ける）。
    正面が −y、地面アンカー。"""
    clear()
    W, D = 1.34, 0.62
    parts = [
        box_verts(0, 0, 0.415, W, D, 0.052),                     # 平台
        box_verts(0, D / 2 - 0.03, 0.575, W, 0.05, 0.28),        # 奥の背板
    ]
    for sx in (1, -1):                                            # 脚
        for sy in (1, -1):
            parts.append(box_verts(sx * (W / 2 - 0.07), sy * (D / 2 - 0.07),
                                   0.195, 0.062, 0.062, 0.39))
        parts.append(box_verts(sx * (W / 2 - 0.07), 0, 0.115, 0.05, D - 0.20, 0.045))
    # 斜めの陳列棚（前を低く）—— 傾きは 12° ほど
    tilt = math.radians(12)
    sv, sf = box_verts(0, 0.06, 0.66, W - 0.10, 0.44, 0.042)
    sv = [(x, 0.06 + (y - 0.06) * math.cos(tilt) - (z - 0.66) * math.sin(tilt),
           0.66 + (y - 0.06) * math.sin(tilt) + (z - 0.66) * math.cos(tilt))
          for x, y, z in sv]
    parts.append((sv, sf))
    v, f = merge(*parts)

    def col(co, n):
        base = W_LT if co.z > 0.38 else W_DK
        k = 1.10 if n.z > 0.7 else (0.82 if co.z < 0.06 else 1.0)
        return tuple(min(1.0, c * k) for c in base)

    export(mesh_from("prop_misedai", v, f, col, smooth=False), "prop_misedai")


# ══════════════════════════════════ 藍甕 ═══════════════════════════════
def make_aigame():
    """紺屋の藍甕。地面に**埋めて**使う（藍は温度が命）ので、
    地表に出ているのは口縁と厚い唇だけ。中は藍液で真っ暗。

    「屋根に煙出しがある家＝火を使う家」と対になる情報。地面アンカー。"""
    clear()
    parts = [
        sweep([(0, 0, 0.0), (0, 0, 0.11), (0, 0, 0.165)],
              [0.360, 0.372, 0.352], sides=14),                  # 甕の肩
        sweep([(0, 0, 0.150), (0, 0, 0.190)], [0.372, 0.352], sides=14),  # 唇
        sweep([(0, 0, 0.128), (0, 0, 0.132)], [0.300, 0.300], sides=14,
              close_start=False),                                 # 液面
    ]
    v, f = merge(*parts)

    def col(co, n):
        if co.z < 0.14 and abs(co.x) < 0.31 and abs(co.y) < 0.31 and n.z > 0.7:
            return (0.055, 0.075, 0.115)                          # 藍液（ほぼ黒）
        stripe = int((math.atan2(co.y, co.x) + TAU) / TAU * 14) % 2
        k = (0.90 + 0.14 * stripe) * (0.86 + 0.26 * max(0.0, n.z))
        return tuple(min(1.0, c * k) for c in CLAY)

    export(mesh_from("prop_aigame", v, f, col, smooth=False), "prop_aigame")


# ══════════════════════════════════ 物干し（反物）═══════════════════════
def make_monohoshi():
    """染めた反物を干す竿。紺屋の**看板より強い看板** ——
    藍の布が風に揺れているのが街から見えれば、字は要らない。

    正面が −y（布は −y 側に垂れる）、地面アンカー。"""
    clear()
    rng = random.Random(29)
    H, SPAN = 2.05, 2.70
    parts = []
    for sx in (1, -1):                                            # 柱
        parts.append(box_verts(sx * SPAN / 2, 0, H / 2, 0.085, 0.085, H))
        parts.append(box_verts(sx * (SPAN / 2 - 0.16), 0, H - 0.22,
                               0.30, 0.055, 0.055))               # 方杖
    parts.append(sweep([(-SPAN / 2 - 0.10, 0, H - 0.05),
                        (SPAN / 2 + 0.10, 0, H - 0.05)], [0.038, 0.038], sides=7))
    # 反物：幅 0.36 の布を四枚。長さと揺れを一枚ずつ変える
    # PHASE 2.6：箱 → cloth_strip。平板のままだと「青い長方形が四枚」で、
    # 紺屋の一番の見せ場が一番プリミティブに見えていた
    cloth = []
    for i in range(4):
        cx = -0.99 + i * 0.66
        ln = rng.uniform(1.15, 1.52)
        cv, cf = cloth_strip(cx, H - 0.05, 0.36, ln, rows=7, cols=3,
                             sway=rng.uniform(0.06, 0.12),
                             bow=rng.uniform(0.02, 0.05),
                             tilt=rng.uniform(-0.03, 0.03), phase=rng.random(),
                             clear_front=0.22, clear_side=0.12)
        cv = [(x, y - 0.055, z) for x, y, z in cv]
        parts.append((cv, cf))
        cloth.append((cx, H - 0.05 - ln))
    v, f = merge(*parts)

    def col(co, n):
        for cx, bot in cloth:
            if abs(co.x - cx) < 0.21 and co.z < H - 0.02 and -0.30 < co.y < -0.02:
                # 染めの濃淡：一枚ごとに回数が違う。下ほど濃い（液に長く浸かる）
                deep = (int((co.x + 1.6) / 0.66) % 2) == 0
                base = AI if deep else AI_LT
                k = 0.86 + 0.26 * (1.0 - (co.z - bot) / max(0.4, H - bot))
                return tuple(min(1.0, c * k) for c in base)
        return W_DK

    export(mesh_from("prop_monohoshi", v, f, col, smooth=False), "prop_monohoshi")


# ══════════════════════════════════ 立て看板 ═══════════════════════════
def make_kanban_tate():
    """壁に立てかける看板。吊り看板（prop_kanban）が「軒の下」なら、
    こちらは「地面」—— 二つ揃うと店の格が上がる。地面アンカー、正面 −y。"""
    clear()
    lean = math.radians(8)
    parts = []
    bv, bf = box_verts(0, 0, 0.62, 0.66, 0.055, 1.16)             # 板
    bv = [(x, y - (z - 0.62) * math.sin(lean), z) for x, y, z in bv]
    parts.append((bv, bf))
    for sy in (1, -1):                                            # 字板（両面）
        sv, sf = box_verts(0, sy * 0.036, 0.66, 0.44, 0.020, 0.84)
        sv = [(x, y - (z - 0.62) * math.sin(lean), z) for x, y, z in sv]
        parts.append((sv, sf))
    for sx in (1, -1):                                            # 脚
        parts.append(box_verts(sx * 0.27, 0.13, 0.055, 0.07, 0.36, 0.09))
    v, f = merge(*parts)

    def col(co, n):
        # ⚠ 最初は字板を SIGN（明るいクリーム）にしていた。近くでは看板だが、
        # 15m 離れると**白いカプセル**にしか見えず、街のどのカットにも
        # 「未完成の白い物体」が写り込んでいた（三カットで発覚するまで
        # 提灯や村民のせいだと誤診し続けた）。実物の立て看板は板そのもので、
        # 字は墨。白い面積を作らないほうが正しい。
        if abs(co.y) > 0.040 and abs(co.x) < 0.24 and 0.22 < co.z < 1.10:
            k = 1.06 if co.z > 0.66 else 0.94                     # 上下で板を割る
            return tuple(min(1.0, c * k) for c in W_LT)
        return W_DK if co.z < 0.12 else W_ST

    export(mesh_from("prop_kanban_tate", v, f, col, smooth=False), "prop_kanban_tate")


# ══════════════════════════════════ 薪束 ═══════════════════════════════
def make_takigi():
    """割った薪を積んだ束。紺屋は藍を建てるのに火を絶やせない ——
    煙出しと対になる「この家は火を使う」の地面側の証拠。地面アンカー。"""
    clear()
    rng = random.Random(53)
    parts = []
    rows, per = 5, 7
    for r in range(rows):
        for i in range(per):
            if r == rows - 1 and i > per - 3:
                continue                                          # 一番上は崩す
            x = -0.62 + i * (1.24 / (per - 1)) + rng.uniform(-0.014, 0.014)
            z = 0.055 + r * 0.105 + rng.uniform(-0.006, 0.006)
            ln = rng.uniform(0.40, 0.50)
            rr = rng.uniform(0.045, 0.062)
            parts.append(sweep([(x, -ln / 2, z), (x, ln / 2, z)],
                               [rr, rr], sides=6))
    v, f = merge(*parts)

    def col(co, n):
        # 木口（両端）は白っぽく、樹皮側は暗い —— 割った薪の見え方
        end = abs(abs(co.y) - 0.24) < 0.09
        base = (0.470, 0.400, 0.300) if end else W_ST
        k = 0.84 + 0.26 * max(0.0, n.z) + 0.10 * (int(co.z / 0.105) % 2)
        return tuple(min(1.0, c * k) for c in base)

    export(mesh_from("prop_takigi", v, f, col, smooth=False), "prop_takigi")


def make_zaru():
    """笊（ざる）：見世棚に**平たく盛る**ための浅い竹籠。

    ⚠ 既存の prop_basket（深い籠の二段積み）を縮めて棚に載せたら、画面では
    「金色の椀」に読めた —— 形が深すぎ、色が明るすぎる。商品を客に見せる
    器は浅くて口が広い。別資産にしたのは prop_basket が village 中に
    散っていて、色を変えると村全体が変わるから。
    地面アンカー（棚の上に置くときは配置側で持ち上げる）。"""
    clear()
    parts = [
        sweep([(0, 0, 0.0), (0, 0, 0.045), (0, 0, 0.115)],
              [0.150, 0.245, 0.300], sides=12),                  # 笊
        sweep([(0, 0, 0.100), (0, 0, 0.125)], [0.305, 0.298], sides=12),  # 口縁
        # 盛った商品（低い山。高くすると「桶に入れた」になる）
        sweep([(0, 0, 0.085), (0, 0, 0.135), (0, 0, 0.165)],
              [0.250, 0.205, 0.055], sides=12, close_start=False),
    ]
    v, f = merge(*parts)

    def col(co, n):
        if co.z > 0.128 or (co.z > 0.082 and math.hypot(co.x, co.y) < 0.262):
            k = 0.88 + 0.26 * max(0.0, n.z)
            return tuple(min(1.0, c * k) for c in GOODS)          # 商品
        if co.z > 0.096:
            return tuple(min(1.0, c * 1.22) for c in BAMBOO)      # 口縁
        ring = int(co.z / 0.038) % 2
        stave = int((math.atan2(co.y, co.x) + TAU) / TAU * 12) % 2
        k = 0.84 + 0.11 * ring + 0.09 * stave
        return tuple(min(1.0, c * k) for c in BAMBOO)

    export(mesh_from("prop_zaru", v, f, col, smooth=False), "prop_zaru")


make_chochin()
make_zaru()
make_sugidama()
make_noren("prop_noren_ai", 2.05, 5, AI, seed=7)
make_noren("prop_noren_kaki", 1.50, 4, (0.430, 0.195, 0.115), h=0.55, seed=19)
make_taru()
make_kago()
make_sudare()
make_hoshigaki()
make_somenuno()
make_tawara()
make_misedai()
make_aigame()
make_monohoshi()
make_kanban_tate()
make_takigi()
print("done")

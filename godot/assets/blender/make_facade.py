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
GOODS = (0.300, 0.255, 0.150)       # 盛った乾物・穀


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
    parts.append(sweep([(0, 0, 0.30), (0, 0, 0.004)], [0.009, 0.009], sides=5))
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
    cloth = []
    for i in range(4):
        cx = -0.99 + i * 0.66
        ln = rng.uniform(1.15, 1.52)
        sway = rng.uniform(-0.07, 0.07)
        cv, cf = box_verts(cx, -0.055, H - 0.05 - ln / 2, 0.36, 0.022, ln)
        bot = H - 0.05 - ln
        cv = [(x, y + sway * (1.0 - (z - bot) / ln), z) for x, y, z in cv]
        parts.append((cv, cf))
        cloth.append((cx, bot))
    v, f = merge(*parts)

    def col(co, n):
        for cx, bot in cloth:
            if abs(co.x - cx) < 0.19 and co.z < H - 0.02 and abs(co.y) < 0.13:
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
make_tawara()
make_misedai()
make_aigame()
make_monohoshi()
make_kanban_tate()
make_takigi()
print("done")

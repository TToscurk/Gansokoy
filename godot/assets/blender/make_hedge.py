# 生垣（刈込みの植栽）產生器（Blender headless）：
#   blender -b -P godot/assets/blender/make_hedge.py -- godot/assets/models
#
# 為什麼要有這支：v15 的生垣是「橢圓球 + cellular 葉貼圖」，
# 使用者一眼看穿 ——「很像西瓜黏上去」。他是對的，而且原因很具體：
#
#   1. **輪廓是光滑的。** 真正的樹籬輪廓是**碎的** —— 幾百根小枝葉戳出來，
#      逆光時邊緣是毛的。光滑的封閉曲面不管貼什麼圖都是水果。
#   2. **球體是錯的形狀。** 刈込み生垣是修剪過的**條狀塊體**（上緣略圓、
#      側面近垂直），不是一顆一顆的球。
#   3. **貼圖幫不了忙。** cellular 花紋投影到橢圓球上，就是西瓜皮的紋路。
#
# 所以這裡不做球，做：粗胚塊體（有雜訊、低模）+ 表面撒 ~200 叢小枝葉
# 把輪廓打碎 + 底下露幾根枝幹。顏色走頂點色（跟 make_props.py 同慣例）：
# 內部深、外緣亮、枝尖偏黃綠。
#
# 產出：hedge_a（密實・修剪整齊）/ hedge_b（高・略散）/ hedge_c（矮寬）
import bpy
import bmesh
import math
import random
import sys
import os

OUT_DIR = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "godot/assets/models"
os.makedirs(OUT_DIR, exist_ok=True)

# 一個模組的尺寸（公尺）。沿著生垣線每 MODULE_LEN 擺一個。
MODULE_LEN = 2.4

# 葉色：由內到外、由老到新。同一叢裡也要混，不然整排是同一個綠。
# ⚠ 這些值是**線性**的 —— glTF 的 COLOR_0 不做色彩空間轉換，
# 寫什麼進去 Godot 就當線性反照率讀什麼。第一版照 sRGB 的直覺填
# （0.145, 0.255, 0.105），在引擎裡暗得像墨綠塑膠。
# ⚠ 殼（HULL）要**很暗**。它是樹籬的內部，本來就照不到光；
# 第一版把殼做成中綠，結果整條像一面塗綠的牆、葉子像插在上面的刺。
# 殼的工作只是「擋住視線」，看得到殼就是做錯了。
# 壓太暗的話背光那一面會變成純黑的剪影（0.006 就是這樣）。
HULL_DARK = (0.020, 0.034, 0.016)
HULL_MID = (0.046, 0.072, 0.032)
LEAF_DEEP = (0.105, 0.180, 0.085)
LEAF_MID = (0.255, 0.400, 0.170)
LEAF_LIT = (0.420, 0.560, 0.220)
LEAF_NEW = (0.600, 0.680, 0.290)
STEM = (0.230, 0.185, 0.135)


def clear():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for m in list(bpy.data.meshes):
        bpy.data.meshes.remove(m)


def mix(a, b, t):
    return tuple(a[i] * (1.0 - t) + b[i] * t for i in range(3))


def P(x, up, depth):
    """(沿長邊, 高度, 進深) → Blender 座標。

    ⚠ **Blender 是 Z-up。** 這支第一版整個用 Y 當高度寫（Godot 的習慣），
    再配上 export_yup=True —— 匯出時又轉了一次，結果整條樹籬是**躺著**的：
    在 Godot 裡看到的是它的底面（法線朝內 → 全黑）、枝葉全擠在一條邊上、
    枝幹變成水平的棒子。make_props.py 是照 Blender 原生 Z-up 寫的，
    這支也要跟著。"""
    return (x, depth, up)


class Builder:
    """把所有三角形累積起來，最後一次建 mesh —— 一叢一物件的話
    Blender 端會慢十倍，而且 join 之後頂點色容易掉。"""

    def __init__(self):
        self.verts = []
        self.faces = []
        self.cols = []          # 每個 face 一個顏色（BYTE_COLOR / CORNER 展開時用）

    def tri(self, a, b, c, col, flip=False):
        i = len(self.verts)
        self.verts += [a, c, b] if flip else [a, b, c]
        self.faces.append((i, i + 1, i + 2))
        self.cols.append(col)

    def quad(self, a, b, c, d, col, flip=False):
        self.tri(a, b, c, col, flip)
        self.tri(a, c, d, col, flip)

    def tri2(self, a, b, c, col):
        """雙面：同一片葉子正反各一張。
        ⚠ 不能只靠材質的 CULL_DISABLED —— 那只讓背面**畫得出來**，
        照明用的還是原本朝另一邊的法線，結果背面全黑。
        葉子是薄片，正反都要被光照到，就得各給一張自己的面。"""
        self.tri(a, b, c, col)
        self.tri(a, b, c, col, flip=True)

    def quad2(self, a, b, c, d, col):
        self.tri2(a, b, c, col)
        self.tri2(a, c, d, col)

    def build(self, name, smooth=False):
        me = bpy.data.meshes.new(name)
        me.from_pydata(self.verts, [], self.faces)
        me.update()
        ob = bpy.data.objects.new(name, me)
        bpy.context.collection.objects.link(ob)
        attr = me.color_attributes.new(name="Col", type="BYTE_COLOR", domain="CORNER")
        for fi, poly in enumerate(me.polygons):
            r, g, b = self.cols[fi]
            for li in poly.loop_indices:
                attr.data[li].color = (r, g, b, 1.0)
            poly.use_smooth = smooth
        return ob


def make_surf(half_len, half_d, h, lumps):
    """樹籬的參數曲面。**殼與枝葉必須共用同一個函式** ——
    第一版兩邊各寫一次略有出入的公式，枝葉就撒不到殼的側面上，
    留下大片光滑的殼（又變回一顆瓜）。"""
    def surf(u, v):
        # u: -1..1 沿長邊   v: 0..1 由底到頂
        taper = 1.0 - 0.18 * v * v                       # 修剪過的收分
        cap = math.sin(v * math.pi * 0.5)                # 上緣渾圓
        wob = (math.sin(u * 5.1 + v * 2.3) * 0.5 + math.sin(u * 11.7) * 0.3) * lumps
        x = u * half_len
        y = v * h + wob * 0.35
        z = half_d * taper * math.cos(v * math.pi * 0.5) ** 0.35 * (1.0 + wob)
        return x, y, z, cap
    return surf


def surf_normal(surf, u, v, sd, half_len, h):
    """用有限差分求外法線 —— 枝葉要沿著殼的外法線長出去。"""
    du = 0.02
    dv = 0.02
    x0, y0, z0, _ = surf(u, v)
    xu, yu, zu, _ = surf(min(1.0, u + du), v)
    xv, yv, zv, _ = surf(u, min(1.0, v + dv))
    au = (xu - x0, yu - y0, (zu - z0) * sd)
    av = (xv - x0, yv - y0, (zv - z0) * sd)
    nx = au[1] * av[2] - au[2] * av[1]
    ny = au[2] * av[0] - au[0] * av[2]
    nz = au[0] * av[1] - au[1] * av[0]
    nl = math.sqrt(nx * nx + ny * ny + nz * nz) or 1.0
    nx, ny, nz = nx / nl, ny / nl, nz / nl
    if nz * sd < 0.0:                    # 保證朝外
        nx, ny, nz = -nx, -ny, -nz
    return nx, ny, nz


def hull(bld, surf, half_len, rows=7, cols=13):
    """粗胚塊體：擋住視線用。看得到它就是枝葉撒得不夠。"""
    for ri in range(rows):
        for ci in range(cols):
            v0 = ri / rows
            v1 = (ri + 1) / rows
            u0 = -1.0 + 2.0 * ci / cols
            u1 = -1.0 + 2.0 * (ci + 1) / cols
            for sd in (-1.0, 1.0):
                x00, y00, z00, c0 = surf(u0, v0)
                x10, y10, z10, _ = surf(u1, v0)
                x11, y11, z11, c1 = surf(u1, v1)
                x01, y01, z01, _ = surf(u0, v1)
                col = mix(HULL_DARK, HULL_MID, 0.25 + 0.5 * (c0 + c1) * 0.5)
                # ⚠ sd=-1 是鏡射，繞序不跟著反的話法線指進樹籬內部 → 整片黑
                bld.quad(P(x00, y00, z00 * sd), P(x10, y10, z10 * sd),
                         P(x11, y11, z11 * sd), P(x01, y01, z01 * sd), col, flip=(sd < 0))
    # 兩端封口
    for sd in (-1.0, 1.0):
        for ri in range(rows):
            v0 = ri / rows
            v1 = (ri + 1) / rows
            _, y0, z0, _ = surf(sd, v0)
            _, y1, z1, _ = surf(sd, v1)
            x = sd * half_len
            bld.quad(P(x, y0, -z0), P(x, y0, z0), P(x, y1, z1), P(x, y1, -z1),
                     mix(HULL_DARK, HULL_MID, 0.1), flip=(sd < 0))


def sprig(bld, rng, org, nrm, size, tone):
    """一叢小枝葉：三片細長的葉片從同一點岔開。
    這是**打碎輪廓**的關鍵 —— 沒有這層，不管塊體怎麼捏都是一顆瓜。"""
    # 建一組正交基底（nrm 為主軸）
    nx, ny, nz = nrm
    up = (0.0, 1.0, 0.0) if abs(ny) < 0.9 else (1.0, 0.0, 0.0)
    tx = ny * up[2] - nz * up[1]
    ty = nz * up[0] - nx * up[2]
    tz = nx * up[1] - ny * up[0]
    tl = math.sqrt(tx * tx + ty * ty + tz * tz) or 1.0
    tx, ty, tz = tx / tl, ty / tl, tz / tl
    bx = ny * tz - nz * ty
    by = nz * tx - nx * tz
    bz = nx * ty - ny * tx

    # 一叢 5 片小葉。**短而寬**，不是長刺 —— 第一版每片是細長三角形，
    # 撒稀一點就變成仙人掌。一片葉 = 一個雙面三角形（2 個三角形面），
    # 這樣才撒得起數量（數量才是輪廓變碎的關鍵）。
    # 葉根往內縮一點，讓殼看不到葉子是「插」上去的。
    # 葉根埋進殼裡，殼的邊緣才不會露出來
    org = (org[0] - nx * 0.075, org[1] - ny * 0.075, org[2] - nz * 0.075)
    for k in range(5):
        a = rng.uniform(0, math.tau) + k * math.tau / 5.0
        spread = rng.uniform(0.75, 1.55)
        ln = size * rng.uniform(1.05, 1.85)
        wd = size * rng.uniform(0.38, 0.62)
        dx = nx + (tx * math.cos(a) + bx * math.sin(a)) * spread
        dy = ny + (ty * math.cos(a) + by * math.sin(a)) * spread + 0.40
        dz = nz + (tz * math.cos(a) + bz * math.sin(a)) * spread
        dl = math.sqrt(dx * dx + dy * dy + dz * dz) or 1.0
        dx, dy, dz = dx / dl, dy / dl, dz / dl
        tip = (org[0] + dx * ln, org[1] + dy * ln, org[2] + dz * ln)
        # 葉根的寬度沿著切向展開
        p1 = (org[0] + tx * wd, org[1] + ty * wd, org[2] + tz * wd)
        p2 = (org[0] - tx * wd, org[1] - ty * wd, org[2] - tz * wd)
        c = mix(LEAF_MID, LEAF_LIT, tone * rng.uniform(0.3, 1.0))
        if rng.random() < 0.18:                  # 少數新芽，讓綠色有顆粒感
            c = mix(c, LEAF_NEW, rng.uniform(0.4, 0.9))
        elif rng.random() < 0.25:                # 少數陰影葉
            c = mix(c, LEAF_DEEP, rng.uniform(0.3, 0.7))
        bld.tri2(P(*p1), P(*p2), P(*tip), c)


def make_hedge(name, seed, half_len, half_d, h, n_sprig, lumps, stems=5):
    clear()
    rng = random.Random(seed)
    bld = Builder()
    surf = make_surf(half_len, half_d, h, lumps)
    hull(bld, surf, half_len)

    # 側面與上緣：在**同一個曲面**上均勻取樣，殼才不會露出來。
    # v 不加權 —— 第一版把取樣往頂端擠，側面禿掉一大片。
    for _ in range(n_sprig):
        u = rng.uniform(-1.0, 1.0)
        v = rng.uniform(0.06, 1.0)
        sd = 1.0 if rng.random() < 0.5 else -1.0
        x, y, z, _ = surf(u, v)
        nrm = surf_normal(surf, u, v, sd, half_len, h)
        tone = min(1.0, 0.25 + v * 0.6 + rng.uniform(0.0, 0.35))
        sprig(bld, rng, (x, y, z * sd), nrm, rng.uniform(0.062, 0.115), tone)
    # 頂脊：側面取樣在 v→1 時會收到中線上，頂面要另外補
    for _ in range(n_sprig // 4):
        u = rng.uniform(-1.0, 1.0)
        _, ytop, _, _ = surf(u, 1.0)
        z = rng.uniform(-0.55, 0.55) * half_d
        sprig(bld, rng, (u * half_len, ytop - 0.03, z), (0.0, 1.0, 0.0),
              rng.uniform(0.065, 0.120), min(1.0, 0.8 + rng.uniform(0.0, 0.2)))

    # 底下的枝幹：樹籬不是浮在地上的，腳下看得到木質莖
    for i in range(stems):
        sx = (-1.0 + 2.0 * (i + 0.5) / stems) * half_len * 0.85 + rng.uniform(-0.1, 0.1)
        sz = rng.uniform(-0.3, 0.3) * half_d
        r = rng.uniform(0.020, 0.035)
        top = h * rng.uniform(0.35, 0.6)
        for k in range(4):
            a0 = k * math.tau / 4.0
            a1 = (k + 1) * math.tau / 4.0
            p0 = P(sx + math.cos(a0) * r, -0.05, sz + math.sin(a0) * r)
            p1 = P(sx + math.cos(a1) * r, -0.05, sz + math.sin(a1) * r)
            q0 = P(sx + math.cos(a0) * r * 0.6, top, sz + math.sin(a0) * r * 0.6)
            q1 = P(sx + math.cos(a1) * r * 0.6, top, sz + math.sin(a1) * r * 0.6)
            bld.quad(p0, p1, q1, q0, STEM)

    ob = bld.build(name, smooth=False)
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    path = os.path.join(OUT_DIR, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, use_selection=True, export_format="GLB",
                              export_yup=True, export_apply=True)
    print("exported %s（%d 三角形）" % (path, len(bld.faces)))


# 三種：密實修剪整齊 / 高而略散 / 矮寬。沿線隨機挑，一排才不是同一個模具。
make_hedge("hedge_a", 71, MODULE_LEN * 0.5, 0.36, 1.26, 1750, 0.055, stems=5)
make_hedge("hedge_b", 137, MODULE_LEN * 0.5, 0.32, 1.55, 1950, 0.105, stems=4)
make_hedge("hedge_c", 293, MODULE_LEN * 0.5, 0.44, 1.00, 1550, 0.075, stems=6)
print("done")

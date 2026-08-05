# 稗田邸・豪邸主屋（Blender headless）：
#   blender -b -P godot/assets/blender/make_hieda.py -- godot/assets/models
#   blender -b -P godot/assets/blender/preview.py -- hieda_main
#
# 美術規格 §1.2「建築模組進 Blender，從難度最高的開始」的第一件。
# 使用者的計畫：稗田邸整棟重做成**村外的豪宅大院**，不放在村內街區。
# 這支先打樣「主屋」一棟 —— 過了預覽關再做門樓／塀／庭園配置。
#
# 跟 gen_village 的箱子堆有什麼不同（不同才有進 Blender 的理由）：
#   1. **入母屋是一體成形的網格**：四注斜面 + 上段切妻 + 妻壁內收，
#      不是箱子旋轉拼裝（v19 的隅屋根戳出屋端就是拼裝的極限）
#   2. **簷口有起翹**（軒反り）：屋簷角往上揚 —— 豪邸氣勢的一半在這條曲線
#   3. 柱樑格子直接長在牆上，位置照京間模數（1.82m）
#
# 顏色照管線慣例走頂點色（COLOR_0，線性值），Godot 端配 vc 材質。
import bpy
import math
import sys
import os

OUT_DIR = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "godot/assets/models"
os.makedirs(OUT_DIR, exist_ok=True)

KEN = 1.82                     # 京間一間（美術規格 §3.1 的模數）

# 顏色（線性）。plaster 亮、木部灰褐、瓦藍灰 —— 對齊去髒後的村內材質。
C_PLASTER = (0.760, 0.740, 0.690)
C_WOOD = (0.165, 0.135, 0.110)
C_WOOD_LT = (0.240, 0.200, 0.160)
C_KAWARA = (0.310, 0.360, 0.450)
C_KAWARA_DK = (0.272, 0.318, 0.405)
C_RIDGE = (0.160, 0.190, 0.250)
C_STONE = (0.520, 0.520, 0.500)
C_SHOJI = (0.870, 0.850, 0.780)
C_ENGAWA = (0.420, 0.330, 0.240)


class B:
    """quad/tri 累積器（同 make_hedge 的 Builder，Z-up）。"""

    def __init__(self):
        self.verts = []
        self.faces = []
        self.cols = []

    def tri(self, a, b, c, col, flip=False):
        i = len(self.verts)
        self.verts += [a, c, b] if flip else [a, b, c]
        self.faces.append((i, i + 1, i + 2))
        self.cols.append(col)

    def quad(self, a, b, c, d, col, flip=False):
        self.tri(a, b, c, col, flip)
        self.tri(a, c, d, col, flip)

    def box(self, cx, cy, cz, sx, sy, sz, col, col_top=None):
        """軸對齊方塊（cx,cy = 平面、cz = 高度中心；Blender Z-up）。"""
        hx, hy, hz = sx / 2, sy / 2, sz / 2
        v = [(cx - hx, cy - hy, cz - hz), (cx + hx, cy - hy, cz - hz),
             (cx + hx, cy + hy, cz - hz), (cx - hx, cy + hy, cz - hz),
             (cx - hx, cy - hy, cz + hz), (cx + hx, cy - hy, cz + hz),
             (cx + hx, cy + hy, cz + hz), (cx - hx, cy + hy, cz + hz)]
        ct = col_top or col
        self.quad(v[0], v[1], v[5], v[4], col)          # -y
        self.quad(v[2], v[3], v[7], v[6], col)          # +y
        self.quad(v[1], v[2], v[6], v[5], col)          # +x
        self.quad(v[3], v[0], v[4], v[7], col)          # -x
        self.quad(v[7], v[4], v[5], v[6], ct)           # top（z-up 繞序：從上看逆時針）
        self.quad(v[0], v[3], v[2], v[1], col)          # bottom

    def build(self, name):
        me = bpy.data.meshes.new(name)
        me.from_pydata(self.verts, [], self.faces)
        me.update()
        ob = bpy.data.objects.new(name, me)
        bpy.context.collection.objects.link(ob)
        attr = me.color_attributes.new(name="Col", type="BYTE_COLOR", domain="CORNER")
        for fi, poly in enumerate(me.polygons):
            r, g, b2 = self.cols[fi]
            for li in poly.loop_indices:
                attr.data[li].color = (r, g, b2, 1.0)
            poly.use_smooth = False
        return ob


def eave_profile(t, lift):
    """軒反り：簷口往外走時的抬升量。t=0 屋脊側、t=1 簷口。
    前 70% 直線、末 30% 上翹 —— 日本屋根的反りは端に集中する。"""
    if t < 0.7:
        return 0.0
    k = (t - 0.7) / 0.3
    return lift * k * k


def irimoya(bld, w, d, base_z, rise, gable_frac=0.45, overhang=1.6,
            lift=0.55, steps=9):
    """入母屋屋頂（一體網格）。
    w/d = 牆身平面尺寸；base_z = 簷桁高；rise = 屋脊相對高；
    gable_frac = 上段切妻佔全寬比例；overhang = 出簷；lift = 軒反り。

    做法：沿「屋脊 → 簷口」掃 steps 段，每段是一圈截面 ——
    截面在上段是切妻（只有前後兩坡），過了 gable_frac 的高度之後
    四邊都收（四注）。用參數 s（0=脊 1=簷）：
      z(s)   = base_z + rise*(1-s) + 軒反り
      前後坡 y = ±(d/2+overhang)*s ... 直線斜面
      左右坡 x 端點：上段固定在 ±w*gable_frac/2（切妻端），
                      下段線性外擴到 ±(w/2+overhang)
    """
    hw, hd = w / 2, d / 2
    gx = w * gable_frac / 2          # 上段切妻的半寬
    # 下段（四注）從哪個 s 開始：上段佔 rise 的 45%
    s_hip = 0.45

    def ring(s):
        """一圈截面的四個角（x±, y±）與 z。"""
        z = base_z + rise * (1.0 - s) + eave_profile(s, lift)
        y = (hd + overhang) * s if s > 0 else 0.0
        if s <= s_hip:
            x = gx + (0.0 if s <= 0 else s / s_hip * 0.0)   # 上段：x 固定
            x = gx
        else:
            k = (s - s_hip) / (1.0 - s_hip)
            x = gx + (hw + overhang - gx) * k
        return x, y, z

    thick = 0.22
    prev = None
    for i in range(steps + 1):
        s = i / steps
        x, y, z = ring(s)
        cur = (x, y, z)
        if prev is not None:
            x0, y0, z0 = prev
            x1, y1, z1 = cur
            shade = C_KAWARA if i % 2 == 0 else C_KAWARA_DK   # 瓦的層次感
            # 前後兩坡（y 正負各一片）
            bld.quad((-x0, y0, z0), (x0, y0, z0), (x1, y1, z1), (-x1, y1, z1), shade)
            bld.quad((x0, -y0, z0), (-x0, -y0, z0), (-x1, -y1, z1), (x1, -y1, z1), shade)
            # 左右坡（只有下段外擴時才有面積）
            if x1 > x0 + 0.01:
                bld.quad((x0, y0, z0), (x0, -y0, z0), (x1, -y1, z1), (x1, y1, z1), shade)
                bld.quad((-x0, -y0, z0), (-x0, y0, z0), (-x1, y1, z1), (-x1, -y1, z1), shade)
            # 屋面厚度：簷口那一段補側緣
            if i == steps:
                for sy in (1, -1):
                    bld.quad((-x1, sy * y1, z1), (x1, sy * y1, z1),
                             (x1, sy * y1, z1 - thick), (-x1, sy * y1, z1 - thick),
                             C_KAWARA_DK, flip=(sy < 0))
                bld.quad((x1, y1, z1), (x1, -y1, z1), (x1, -y1, z1 - thick),
                         (x1, y1, z1 - thick), C_KAWARA_DK)
                bld.quad((-x1, -y1, z1), (-x1, y1, z1), (-x1, y1, z1 - thick),
                         (-x1, -y1, z1 - thick), C_KAWARA_DK)
        prev = cur

    # 上段妻壁（三角形，內收在切妻端）
    zt = base_z + rise
    x_h, y_h, z_h = ring(s_hip)
    for sx in (1, -1):
        bld.tri((sx * gx, y_h, z_h), (sx * gx, -y_h, z_h), (sx * gx, 0, zt),
                C_PLASTER, flip=(sx < 0))
        # 破風板（妻壁的邊框）
        for sy in (1, -1):
            bld.quad((sx * gx * 1.01, sy * y_h, z_h), (sx * gx * 1.01, 0, zt),
                     (sx * gx * 1.01, 0, zt - 0.18),
                     (sx * gx * 1.01, sy * y_h, z_h - 0.18),
                     C_WOOD, flip=(sx > 0) != (sy > 0))
    # 大棟（屋脊）+ 鬼瓦
    bld.box(0, 0, zt + 0.10, gx * 2 + 0.5, 0.5, 0.34, C_RIDGE)
    for sx in (1, -1):
        bld.box(sx * (gx + 0.25), 0, zt + 0.14, 0.45, 0.62, 0.5, C_RIDGE)


def make_hieda_main(name="hieda_main"):
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    bld = B()
    # 平面：14 間 × 8 間（25.5 × 14.6）—— 豪邸等級
    w = 14 * KEN
    d = 8 * KEN
    f1 = 3.9                    # 一層層高
    f2 = 3.1                    # 二層層高
    pod = 0.85                  # 基壇高

    # 基壇（石）＋ 正面石階
    bld.box(0, 0, pod / 2, w + 2.2, d + 2.2, pod, C_STONE)
    for i in range(4):
        t = (i + 0.5) / 4
        bld.box(0, -(d / 2 + 1.1) - (1 - t) * 1.5, pod * t - 0.11,
                4.2, 0.55, 0.24, C_STONE)

    # ── 一層 ──
    z0 = pod
    bld.box(0, 0, z0 + f1 / 2, w, d, f1, C_PLASTER)
    # 腰壁（下見板）
    bld.box(0, 0, z0 + 0.55, w + 0.08, d + 0.08, 1.1, C_WOOD_LT)
    # 柱：照一間一根（正背面），角柱加粗
    n_post = 15
    for i in range(n_post):
        px = -w / 2 + i * KEN * (14 / (n_post - 1))
        fat = 0.24 if i in (0, n_post - 1) else 0.17
        for sy in (1, -1):
            bld.box(px, sy * (d / 2 + 0.04), z0 + f1 / 2, fat, 0.13, f1, C_WOOD)
    for sy in (1, -1):          # 土台與桁
        bld.box(0, sy * (d / 2 + 0.05), z0 + 0.09, w + 0.2, 0.15, 0.18, C_WOOD)
        bld.box(0, sy * (d / 2 + 0.05), z0 + f1 - 0.10, w + 0.2, 0.15, 0.20, C_WOOD)
        bld.box(0, sy * (d / 2 + 0.05), z0 + 2.30, w + 0.2, 0.13, 0.15, C_WOOD)
    # 正面：障子帶（柱間白紙）
    for i in range(n_post - 1):
        px = -w / 2 + (i + 0.5) * KEN * (14 / (n_post - 1))
        bld.box(px, -(d / 2 + 0.02), z0 + 1.75, KEN * 0.78, 0.06, 1.15, C_SHOJI)
    # 縁側（迴廊）＋ 束柱與高欄
    for sy in (1, -1):
        bld.box(0, sy * (d / 2 + 1.05), z0 + 0.12, w + 1.4, 2.0, 0.22, C_ENGAWA)
        bld.box(0, sy * (d / 2 + 1.95), z0 + 0.95, w + 1.4, 0.11, 0.11, C_WOOD)
        for i in range(13):
            px = -w / 2 + i * (w / 12)
            bld.box(px, sy * (d / 2 + 1.95), z0 + 0.5, 0.09, 0.09, 0.9, C_WOOD)

    # ── 裳階（一二層之間的環繞簷）──
    # ⚠ 一圈**四角斜接**的裙簷，不是四片獨立斜板 —— 第一版四片板在轉角
    # 互不相接，preview 一眼看到四個懸空的翼片。內外兩圈矩形、
    # 四個側面自然在角上斜接（跟入母屋同一種掃法）。
    z1 = z0 + f1
    sk = 1.7
    xi, yi = (w - 3.6) / 2 - 0.4, (d - 2.6) / 2 - 0.4     # 內圈：塞進二層牆裡
    xo, yo = w / 2 + sk, d / 2 + sk                        # 外圈：壓過縁側
    zi, zo = z1 + 0.62, z1 - 0.05
    ci = [(-xi, -yi), (xi, -yi), (xi, yi), (-xi, yi)]
    co = [(-xo, -yo), (xo, -yo), (xo, yo), (-xo, yo)]
    for k in range(4):
        a0, a1 = ci[k], ci[(k + 1) % 4]
        b0, b1 = co[k], co[(k + 1) % 4]
        bld.quad((a0[0], a0[1], zi), (a1[0], a1[1], zi),
                 (b1[0], b1[1], zo), (b0[0], b0[1], zo), C_KAWARA, flip=True)
        # 簷口厚度
        bld.quad((b0[0], b0[1], zo), (b1[0], b1[1], zo),
                 (b1[0], b1[1], zo - 0.16), (b0[0], b0[1], zo - 0.16), C_KAWARA_DK, flip=True)

    # ── 二層（內收）──
    w2 = w - 3.6
    d2 = d - 2.6
    bld.box(0, 0, z1 + f2 / 2, w2, d2, f2, C_PLASTER)
    for sy in (1, -1):
        bld.box(0, sy * (d2 / 2 + 0.03), z1 + f2 - 1.35, w2 * 0.86, 0.08, 1.05, C_WOOD)  # 窗帶
        bld.box(0, sy * (d2 / 2 + 0.05), z1 + 0.10, w2 + 0.15, 0.13, 0.16, C_WOOD)
        bld.box(0, sy * (d2 / 2 + 0.05), z1 + f2 - 0.10, w2 + 0.15, 0.13, 0.16, C_WOOD)
    for i in range(9):
        px = -w2 / 2 + i * (w2 / 8)
        for sy in (1, -1):
            bld.box(px, sy * (d2 / 2 + 0.03), z1 + f2 / 2, 0.15, 0.11, f2, C_WOOD)

    # ── 入母屋屋頂（軒反り）──
    irimoya(bld, w2, d2, z1 + f2, rise=3.6, gable_frac=0.42, overhang=2.0, lift=0.6)

    ob = bld.build(name)
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    path = os.path.join(OUT_DIR, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, use_selection=True, export_format="GLB",
                              export_yup=True, export_apply=True)
    print("exported %s（%d 面）" % (path, len(bld.faces)))


make_hieda_main()
print("done")

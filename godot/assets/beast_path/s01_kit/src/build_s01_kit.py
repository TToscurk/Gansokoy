"""獸道 S01 R4 Demo 環境資產 Kit 生成器（Blender 5.2.1，bpy＋bmesh，純程序、固定 seed、可重現）。

用法：
    背景（正式輸出）：blender -b --python build_s01_kit.py -- [--preview]
    即時 Blender（MCP）：exec(open(r".../build_s01_kit.py", encoding="utf-8").read()); build_all(export=False)
      只在自己的 collection「S01_KIT」裡建，不重設場景、不動其他物件。
輸出（assets/beast_path/s01_kit/）：
    glb/<name>.glb      每件一個 GLB（Y 向上、單一網格、原點＝貼地點）
    src/s01_kit.blend   全部資產的 Blender 原始檔
    src/kit_manifest.json  每件的尺寸、三角面數、類別
座標：Blender Z 向上；原點在「地面」：岩、根、木頭有一部分在 z<0（埋進地裡的部分）。

植物的頂點資料（對 Godot 的 meadow_grass.gdshader；重用、不改）：
    COLOR.rgb  葉色（sRGB 數值直接寫入；glTF 原樣傳到 Godot，量過）
    UV0.y      葉根 0 → 葉尖 1（風的權重；Blender 這邊存 1−t，glTF 會翻 v）
    UV1        (相位 0–1, 剛性 0–1)（同上，v 存 1−剛性）
岩／木頭的顏色（苔、環境遮蔽、腳邊泥土）在 Godot 擺放後依地形算（同 rock_builder.gd 的規則），這裡只出形狀與 UV。

設計（使用者 S01 Blender 資產方向，2026-10-16）：
    岩：不是方盒、不是水平疊板。橢球＋一組隨機『斜』切面（夾平成節理面，避開接近水平的切面）＋穿過岩體的節理裂縫
        （V 形凹槽，多為直立／斜向）＋兩層起伏；崖面岩由 2–3 個不同方向的岩體交疊（交線＝節理），岩肋沿落水線拉長。
    草：2–3 個株立（tiller），葉近直立、上半段才往任意方向垂（不成放射扇）；高草帶穗。
    羊齒：拱形葉軸＋左右羽片（中段最長），一叢 7–11 片，其中一兩片老葉偏黃。
    灌木：多枝條＋枝端成簇的小葉；熊笹：細稈＋頂端 4–6 片下垂的披針葉。
    落葉堆：不規則外形的一片，葉片有捲曲、疊放，配色褐／赭／灰褐／少量紅；細枝。
    苔：低矮起伏的墊狀，外緣收進地面下。
    木：倒木（樹皮縱紋、斷裂端的木刺）、斷枝、露出地面的根群（根往外延伸後潛入地下）。
"""
import bpy, bmesh, math, random, os, sys, json
from mathutils import Vector, Matrix, Euler, noise

OUT = r"D:/神社/shrine/godot/assets/beast_path/s01_kit"
GLB_DIR = OUT + "/glb"
SRC_DIR = OUT + "/src"
COLL = "S01_KIT"


# ============================================================ 共用
def fbm(p, seed, octaves=3, lac=2.03, gain=0.5):
    v, a, f = 0.0, 1.0, 1.0
    for _ in range(octaves):
        v += a * noise.noise(Vector((p.x * f + seed * 1.71, p.y * f - seed * 0.93, p.z * f + seed * 0.37)))
        a *= gain
        f *= lac
    return v


def lerp(a, b, t):
    return a + (b - a) * t


def lerp3(a, b, t):
    return (lerp(a[0], b[0], t), lerp(a[1], b[1], t), lerp(a[2], b[2], t))


def sstep(e0, e1, x):
    t = min(1.0, max(0.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


class MB:
    """簡單的網格累加器：頂點（位置、法線、顏色、UV0、UV1）＋三角形。"""

    def __init__(self):
        self.P, self.N, self.C, self.U0, self.U1, self.F = [], [], [], [], [], []

    def v(self, p, n=(0, 0, 1), c=(1, 1, 1), u0=(0, 0), u1=(0, 0)):
        self.P.append(tuple(p))
        self.N.append(tuple(Vector(n).normalized()))
        self.C.append((c[0], c[1], c[2], 1.0))
        self.U0.append((u0[0], 1.0 - u0[1]))           # glTF 會翻 v
        self.U1.append((u1[0], 1.0 - u1[1]))
        return len(self.P) - 1

    def tri(self, a, b, c):
        self.F.append((a, b, c))

    def quad(self, a, b, c, d):
        self.F.append((a, b, c))
        self.F.append((a, c, d))

    def to_object(self, name, custom_normals=True):
        me = bpy.data.meshes.new(name)
        me.from_pydata(self.P, [], self.F)
        me.update()
        ca = me.color_attributes.new("Col", 'FLOAT_COLOR', 'POINT')
        for i, c in enumerate(self.C):
            ca.data[i].color = c
        me.color_attributes.active_color = ca
        uv0 = me.uv_layers.new(name="UVMap")
        uv1 = me.uv_layers.new(name="UV2")
        for li, lp in enumerate(me.loops):
            uv0.data[li].uv = self.U0[lp.vertex_index]
            uv1.data[li].uv = self.U1[lp.vertex_index]
        if custom_normals:
            me.shade_smooth()
            me.normals_split_custom_set_from_vertices(self.N)
        ob = bpy.data.objects.new(name, me)
        coll().objects.link(ob)
        return ob


def coll():
    c = bpy.data.collections.get(COLL)
    if c is None:
        c = bpy.data.collections.new(COLL)
        bpy.context.scene.collection.children.link(c)
    return c


def clear_coll():
    c = bpy.data.collections.get(COLL)
    if c is None:
        return
    for ob in list(c.objects):
        me = ob.data
        bpy.data.objects.remove(ob, do_unlink=True)
        if me is not None and me.users == 0:
            bpy.data.meshes.remove(me)


def placeholder_mat(name, rgb):
    m = bpy.data.materials.get(name)
    if m is None:
        m = bpy.data.materials.new(name)
        m.diffuse_color = (rgb[0], rgb[1], rgb[2], 1.0)
    return m


# ============================================================ 植物
def blade(mb, base, az, lean, droop, az2, length, width, segs, cb, ct, phase, stiff, up_bias=0.62, tipw=0.0):
    """一片葉：從 base 出發，與垂直的夾角從 lean 漸增到 lean+droop（上半段才轉向 az2）。"""
    pts = []
    p = Vector(base)
    dl = length / segs
    for i in range(segs + 1):
        t = i / segs
        pts.append((p.copy(), t))
        ang = lean + droop * (t ** 1.7)
        a = lerp(az, az2, sstep(0.35, 1.0, t))
        d = Vector((math.sin(ang) * math.cos(a), math.sin(ang) * math.sin(a), math.cos(ang)))
        p = p + d * dl
    ids = []
    for i, (q, t) in enumerate(pts):
        if i + 1 < len(pts):
            fwd = (pts[i + 1][0] - q).normalized()
        else:
            fwd = (q - pts[i - 1][0]).normalized()
        side = fwd.cross(Vector((0, 0, 1)))
        if side.length < 1e-4:
            side = Vector((-math.sin(az), math.cos(az), 0))
        side.normalize()
        nf = side.cross(fwd).normalized()
        if nf.z < 0:
            nf = -nf
        n = (nf * (1 - up_bias) + Vector((0, 0, 1)) * up_bias).normalized()
        w = width * (1.0 - t ** 1.6) + tipw * t
        col = lerp3(cb, ct, t ** 0.8)
        if i == len(pts) - 1 and tipw <= 0:
            ids.append((mb.v(q, n, col, (0.5, t), (phase, stiff)),))
        else:
            ids.append((mb.v(q - side * w * 0.5, n, col, (0.0, t), (phase, stiff)), mb.v(q + side * w * 0.5, n, col, (1.0, t), (phase, stiff))))
    for i in range(len(ids) - 1):
        a, b = ids[i], ids[i + 1]
        if len(b) == 1:
            mb.tri(a[0], a[1], b[0])
        else:
            mb.quad(a[0], a[1], b[1], b[0])


G_BASE = (0.17, 0.22, 0.10)
G_TIP = (0.42, 0.48, 0.24)
D_BASE = (0.30, 0.28, 0.18)
D_TIP = (0.64, 0.58, 0.38)


def grass_clump(name, seed, n_blades, h, w, dry, tillers=(2, 3), seedheads=0, spread=0.10, lean=(0.05, 0.28), droop=(0.35, 1.25), segs=3, warm=0.0, basal=0, col=None):
    rng = random.Random(seed)
    mb = MB()
    gb, gt, db, dt = col if col else (G_BASE, G_TIP, D_BASE, D_TIP)
    nt = rng.randint(*tillers)
    tc = []
    a_c = rng.uniform(0, math.tau)
    for k in range(nt):
        a = a_c + rng.uniform(-1.1, 1.1)                       # 株立偏向同一側（叢心不在原點正中）
        r = rng.uniform(0.3, 1.0) * spread
        tc.append((Vector((math.cos(a) * r, math.sin(a) * r, 0.0)), rng.uniform(0, math.tau), rng.uniform(0.03, 0.14)))
    for b in range(n_blades):
        c, taz, tl = tc[b % nt]
        base = c + Vector((rng.gauss(0, 0.018), rng.gauss(0, 0.018), -0.01))
        az = taz + rng.gauss(0, 0.7)
        ln = rng.uniform(h[0], h[1]) * rng.uniform(0.55, 1.0)
        isdry = rng.random() < dry
        cb = db if isdry else gb
        ct = dt if isdry else gt
        tint = rng.uniform(0.85, 1.12)
        cb = (cb[0] * tint, cb[1] * tint, cb[2] * tint)
        ct = lerp3(ct, (0.52, 0.50, 0.30) if not isdry else (0.68, 0.60, 0.44), rng.uniform(0, 0.4) + warm)
        blade(mb, base, az, tl + abs(rng.gauss(0, 1)) * (lean[1] - lean[0]) * 0.5 + lean[0], rng.uniform(*droop), az + rng.gauss(0, 1.4),
              ln, w * rng.uniform(0.8, 1.25), segs, cb, ct, rng.random(), 0.0)
    # 基部的短葉：較寬、往外倒，讓叢有「底」（不是一束細莖）
    for b in range(basal):
        c, taz, tl = tc[rng.randrange(nt)]
        base = c + Vector((rng.gauss(0, 0.03), rng.gauss(0, 0.03), -0.01))
        az = rng.uniform(0, math.tau)
        ln = rng.uniform(h[0], h[1]) * rng.uniform(0.25, 0.48)
        isdry = rng.random() < dry * 1.4
        cb = db if isdry else gb
        ct = lerp3(dt if isdry else gt, (0.40, 0.42, 0.22), rng.uniform(0, 0.5))
        blade(mb, base, az, rng.uniform(0.45, 0.9), rng.uniform(0.6, 1.3), az + rng.gauss(0, 0.8), ln, w * rng.uniform(1.1, 1.5), 2, cb, ct, rng.random(), 0.1)
    for s in range(seedheads):
        c, taz, tl = tc[s % nt]
        base = c + Vector((rng.gauss(0, 0.015), rng.gauss(0, 0.015), -0.01))
        az = taz + rng.gauss(0, 0.5)
        ln = h[1] * rng.uniform(1.05, 1.3)
        lean_s = tl + rng.uniform(0.02, 0.12)
        blade(mb, base, az, lean_s, rng.uniform(0.15, 0.4), az, ln, 0.006, 3, (0.30, 0.32, 0.18), (0.58, 0.54, 0.36), rng.random(), 0.55)
        # 穗：莖頂附近 5–8 支短小穗
        ang = lean_s + 0.3
        top = base + Vector((math.sin(ang) * math.cos(az), math.sin(ang) * math.sin(az), math.cos(ang))) * ln * 0.92
        for q in range(rng.randint(5, 8)):
            a2 = az + rng.uniform(-1.2, 1.2)
            blade(mb, top + Vector((0, 0, -q * 0.018)), a2, rng.uniform(0.5, 1.0), 0.4, a2, rng.uniform(0.05, 0.09), 0.012, 1,
                  (0.55, 0.50, 0.34), (0.70, 0.62, 0.45), rng.random(), 0.3)
    ob = mb.to_object(name)
    ob.data.materials.append(placeholder_mat("S01K_grass", (0.3, 0.4, 0.15)))
    return ob


FERN_B = (0.13, 0.20, 0.08)
FERN_T = (0.36, 0.48, 0.20)


def fern(name, seed, n_fronds, L, pairs=16, old=1, elev_deg=(34, 80), bend_add=(50, 80), pinna_k=0.30, rach_seg=10, pw=0.28, fcol=None):
    rng = random.Random(seed)
    mb = MB()
    a0 = rng.uniform(0, math.tau)
    azs = []
    a = a0
    for f in range(n_fronds):                                # 方位不均：一側密、一側留缺口（不是對稱的扇）
        azs.append(a)
        a += rng.uniform(0.35, 1.0) * (math.tau / n_fronds) * 1.15
    rng.shuffle(azs)
    for f in range(n_fronds):
        az = azs[f] + rng.gauss(0, 0.12)
        ln = rng.uniform(L[0], L[1])
        e_deg = rng.uniform(*elev_deg)
        elev = math.radians(e_deg)                          # 起始仰角
        bend = math.radians(rng.uniform(*bend_add) + max(0.0, 80 - e_deg) * 0.6)   # 越低的葉越往下垂
        isold = f < old
        fb, ft = fcol if fcol else (FERN_B, FERN_T)
        cb = fb if not isold else (0.26, 0.26, 0.10)
        ct = ft if not isold else (0.58, 0.52, 0.22)
        tint = rng.uniform(0.88, 1.10)
        ct = (ct[0] * tint, ct[1] * tint, ct[2] * tint)
        nseg = rach_seg
        P = [Vector((math.cos(az) * 0.03, math.sin(az) * 0.03, 0.02))]
        dirs = []
        for i in range(nseg):
            t = (i + 0.5) / nseg
            e = elev - bend * (t ** 1.4)
            d = Vector((math.cos(e) * math.cos(az), math.cos(e) * math.sin(az), math.sin(e)))
            dirs.append(d)
            P.append(P[-1] + d * ln / nseg)
        side = Vector((-math.sin(az), math.cos(az), 0.0))

        def rach(t):
            x = t * nseg
            i = min(int(x), nseg - 1)
            u = x - i
            return P[i].lerp(P[i + 1], u), dirs[i]
        # 葉軸（細帶）
        ids = []
        for i in range(nseg + 1):
            t = i / nseg
            q, d = rach(min(t, 0.999))
            n = (side.cross(d).normalized() * 0.4 + Vector((0, 0, 0.6))).normalized()
            if n.z < 0:
                n = -n
            w = 0.010 * (1 - t) + 0.002
            col = lerp3((0.12, 0.15, 0.06), (0.30, 0.34, 0.14), t)
            ids.append((mb.v(q - side * w, n, col, (0, t), (rng.random(), 0.5)), mb.v(q + side * w, n, col, (1, t), (rng.random(), 0.5))))
        for i in range(nseg):
            mb.quad(ids[i][0], ids[i][1], ids[i + 1][1], ids[i + 1][0])
        # 羽片
        ph = rng.random()
        for j in range(pairs):
            t = 0.10 + 0.88 * (j + 0.5) / pairs
            q, d = rach(t)
            lp = ln * pinna_k * math.sin(math.pi * min(1.0, t ** 0.75)) * (1.0 - 0.25 * t) + 0.012
            for sgn in (-1, 1):
                sd = (side * sgn).normalized()
                pd = (sd * math.cos(math.radians(38)) + d * math.sin(math.radians(38)))
                pd = (pd + Vector((0, 0, -0.18 - 0.25 * t))).normalized()
                wpn = lp * pw
                nrm = pd.cross(d.cross(pd)).normalized()
                nrm = d.cross(pd).normalized() * sgn
                if nrm.z < 0:
                    nrm = -nrm
                nrm = (nrm * 0.45 + Vector((0, 0, 0.55))).normalized()
                perp = nrm.cross(pd).normalized()
                cb2 = lerp3(cb, ct, t * 0.6)
                ct2 = lerp3(cb, ct, 0.55 + 0.45 * t)
                if isold and rng.random() < 0.5:
                    ct2 = lerp3(ct2, (0.48, 0.34, 0.16), 0.6)
                tw = t + 0.04
                b0 = mb.v(q + perp * wpn * 0.20, nrm, cb2, (0, t), (ph, 0.35))
                b1 = mb.v(q - perp * wpn * 0.20, nrm, cb2, (1, t), (ph, 0.35))
                m0 = mb.v(q + pd * lp * 0.45 + perp * wpn * 0.5, nrm, lerp3(cb2, ct2, 0.5), (0, tw), (ph, 0.35))
                m1 = mb.v(q + pd * lp * 0.45 - perp * wpn * 0.5, nrm, lerp3(cb2, ct2, 0.5), (1, tw), (ph, 0.35))
                tp = mb.v(q + pd * lp + Vector((0, 0, -0.01)), nrm, ct2, (0.5, tw + 0.03), (ph, 0.35))
                mb.quad(b0, b1, m1, m0)
                mb.tri(m0, m1, tp)
    ob = mb.to_object(name)
    ob.data.materials.append(placeholder_mat("S01K_fern", (0.2, 0.35, 0.12)))
    return ob


def leaf(mb, c, fwd, up, L, W, cb, ct, ph, stiff, t_wind, droop=0.15):
    """小葉（5 頂點）：葉柄端 c，葉尖方向 fwd，葉面法線 up。"""
    fwd = fwd.normalized()
    side = up.cross(fwd).normalized()
    up2 = fwd.cross(side).normalized()
    n = (up2 * 0.55 + Vector((0, 0, 0.45))).normalized()
    a = mb.v(c, n, cb, (0.5, t_wind), (ph, stiff))
    m0 = mb.v(c + fwd * L * 0.42 + side * W * 0.5 - up2 * L * droop * 0.3, n, lerp3(cb, ct, 0.6), (0, t_wind), (ph, stiff))
    m1 = mb.v(c + fwd * L * 0.42 - side * W * 0.5 - up2 * L * droop * 0.3, n, lerp3(cb, ct, 0.6), (1, t_wind), (ph, stiff))
    tp = mb.v(c + fwd * L - up2 * L * droop, n, ct, (0.5, t_wind), (ph, stiff))
    mb.tri(a, m1, m0)
    mb.tri(m0, m1, tp)


def tube(mb, pts, radii, sides, col0, col1, t0=0.0, t1=1.0, ph=0.0, stiff=1.0, uv_scale=None):
    """沿點列的細管（植物莖用 meadow 頂點資料；木頭用 uv_scale 給樹皮 UV）。"""
    rings = []
    n = len(pts)
    acc = 0.0
    for i in range(n):
        if i > 0:
            acc += (pts[i] - pts[i - 1]).length
        d = (pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]).normalized()
        ref = Vector((0, 0, 1)) if abs(d.z) < 0.9 else Vector((1, 0, 0))
        s1 = d.cross(ref).normalized()
        s2 = d.cross(s1).normalized()
        t = i / (n - 1)
        ring = []
        for j in range(sides + (1 if uv_scale else 0)):
            a = math.tau * j / sides
            off = s1 * math.cos(a) + s2 * math.sin(a)
            col = lerp3(col0, col1, t)
            if uv_scale:
                uv = (j / sides, acc / uv_scale)
                ring.append(mb.v(pts[i] + off * radii[i], off, col, uv, (0, 0)))
            else:
                ring.append(mb.v(pts[i] + off * radii[i], (off * 0.5 + Vector((0, 0, 0.5))), col, (j / sides, lerp(t0, t1, t)), (ph, stiff)))
        rings.append(ring)
    m = sides + (1 if uv_scale else 0)
    for i in range(n - 1):
        for j in range(sides):
            j2 = (j + 1) % m if not uv_scale else j + 1
            mb.quad(rings[i][j], rings[i][j2], rings[i + 1][j2], rings[i + 1][j])
    return rings


def shrub(name, seed, H=0.9, R=0.65, n_stems=7, leaves=360):
    rng = random.Random(seed)
    mb = MB()
    tips = []
    for s in range(n_stems):
        az = rng.uniform(0, math.tau)
        el = math.radians(rng.uniform(55, 82))
        ln = rng.uniform(0.6, 1.0) * H / math.sin(el) * 0.95
        pts = [Vector((rng.gauss(0, 0.04), rng.gauss(0, 0.04), -0.02))]
        d = Vector((math.cos(el) * math.cos(az), math.cos(el) * math.sin(az), math.sin(el)))
        for i in range(5):
            d = (d + Vector((rng.gauss(0, 0.15), rng.gauss(0, 0.15), -0.05 * i))).normalized()
            pts.append(pts[-1] + d * ln / 5)
        tube(mb, pts, [0.016 * (1 - i / 6) + 0.004 for i in range(len(pts))], 4, (0.20, 0.16, 0.11), (0.28, 0.22, 0.15), 0.0, 0.8, rng.random(), 0.9)
        for i in range(2, len(pts)):
            tips.append((pts[i], d))
            # 側枝
            if rng.random() < 0.6:
                a2 = az + rng.choice((-1, 1)) * rng.uniform(0.6, 1.3)
                e2 = math.radians(rng.uniform(15, 45))
                d2 = Vector((math.cos(e2) * math.cos(a2), math.cos(e2) * math.sin(a2), math.sin(e2)))
                q = [pts[i], pts[i] + d2 * 0.14, pts[i] + d2 * 0.27 + Vector((0, 0, -0.02))]
                tube(mb, q, [0.007, 0.005, 0.003], 3, (0.24, 0.19, 0.13), (0.28, 0.22, 0.15), 0.6, 0.9, rng.random(), 0.8)
                tips.append((q[1], d2))
                tips.append((q[2], d2))
    ctr = Vector((0, 0, H * 0.55))
    for k in range(leaves):
        tp, d = tips[rng.randrange(len(tips))]
        c = tp + Vector((rng.gauss(0, 0.07), rng.gauss(0, 0.07), rng.gauss(0, 0.05)))
        out = (c - Vector((0, 0, H * 0.25))).normalized()
        fwd = (out + Vector((rng.gauss(0, 0.6), rng.gauss(0, 0.6), rng.gauss(0, 0.4) + 0.2))).normalized()
        up = (out * 0.6 + Vector((0, 0, 0.8)) + Vector((rng.gauss(0, 0.3), rng.gauss(0, 0.3), 0))).normalized()
        dist = (c - ctr).length / max(R, 0.1)
        ao = lerp(0.62, 1.0, min(1.0, dist))
        cb = (0.10 * ao, 0.17 * ao, 0.06 * ao)
        ct = lerp3((0.22, 0.33, 0.12), (0.32, 0.40, 0.15), rng.random())
        ct = (ct[0] * ao, ct[1] * ao, ct[2] * ao)
        L = rng.uniform(0.055, 0.095)
        leaf(mb, c, fwd, up, L, L * rng.uniform(0.42, 0.55), cb, ct, rng.random(), 0.3, min(1.0, c.z / H))
    ob = mb.to_object(name)
    ob.data.materials.append(placeholder_mat("S01K_shrub", (0.15, 0.3, 0.1)))
    return ob


def forb(name, seed, n_stems=6, H=(0.30, 0.55), rosette=0, Lr=(0.10, 0.17), col_a=(0.30, 0.37, 0.21), col_b=(0.39, 0.45, 0.27), leaves=(5, 8), spread=0.10):
    """闊葉草本叢：n_stems 支直立莖（互生葉、約 137.5° 葉序、下大上小，一半的葉帶側裂片）＋ rosette 片貼地蓮座葉。"""
    rng = random.Random(seed)
    mb = MB()
    cb = (0.09, 0.13, 0.05)
    for s_ in range(n_stems):
        az = rng.uniform(0, math.tau)
        r = math.sqrt(rng.random()) * spread
        base = Vector((math.cos(az) * r, math.sin(az) * r, -0.02))
        h = rng.uniform(*H)
        lean = rng.uniform(0.05, 0.30)
        az2 = rng.uniform(0, math.tau)
        d = Vector((math.sin(lean) * math.cos(az2), math.sin(lean) * math.sin(az2), math.cos(lean)))
        pts = [base]
        for i in range(4):
            d = (d + Vector((rng.gauss(0, 0.08), rng.gauss(0, 0.08), 0.0))).normalized()
            pts.append(pts[-1] + d * h / 4)
        tube(mb, pts, [0.006, 0.005, 0.004, 0.003, 0.002], 3, (0.20, 0.24, 0.12), (0.30, 0.35, 0.18), 0.0, 0.9, rng.random(), 0.7)
        nl = rng.randint(*leaves)
        ph = rng.uniform(0, math.tau)
        for k in range(nl):
            t = 0.18 + 0.8 * k / nl
            i = min(int(t * 4), 3)
            f = t * 4 - i
            c = pts[i].lerp(pts[i + 1], f)
            la = ph + k * 2.4 + rng.gauss(0, 0.25)
            out = Vector((math.cos(la), math.sin(la), 0.0))
            fwd = (out + Vector((0, 0, rng.uniform(0.15, 0.6)))).normalized()
            up = (Vector((0, 0, 1)) - out * 0.35).normalized()
            L = rng.uniform(0.08, 0.14) * (1.25 - 0.55 * t)
            ct = lerp3(col_a, col_b, rng.random())
            leaf(mb, c, fwd, up, L, L * 0.5, cb, ct, rng.random(), 0.4, t, droop=0.25)
            if rng.random() < 0.5:                      # 側裂片
                side = up.cross(fwd).normalized() * rng.choice((-1, 1))
                leaf(mb, c + fwd * L * 0.2, (fwd + side * 0.7).normalized(), up, L * 0.6, L * 0.32, cb, ct, rng.random(), 0.4, t, droop=0.2)
    for k in range(rosette):
        la = k * 2.4 + rng.gauss(0, 0.2)
        out = Vector((math.cos(la), math.sin(la), 0.0))
        fwd = (out + Vector((0, 0, rng.uniform(0.12, 0.45)))).normalized()
        L = rng.uniform(*Lr)
        ct = lerp3(col_a, col_b, rng.random())
        leaf(mb, out * 0.01 + Vector((0, 0, -0.005)), fwd, Vector((0, 0, 1)), L, L * rng.uniform(0.62, 0.8), cb, ct, rng.random(), 0.5, 0.25, droop=0.45)
    ob = mb.to_object(name)
    ob.data.materials.append(placeholder_mat("S01K_forb", (0.2, 0.32, 0.12)))
    return ob


def sasa(name, seed, n_culms=14, H=(0.45, 0.8), spread=0.45):
    rng = random.Random(seed)
    mb = MB()
    for c in range(n_culms):
        a = rng.uniform(0, math.tau)
        r = math.sqrt(rng.random()) * spread
        base = Vector((math.cos(a) * r, math.sin(a) * r, -0.02))
        h = rng.uniform(*H)
        lean = rng.uniform(0.04, 0.22)
        az = rng.uniform(0, math.tau)
        top = base + Vector((math.sin(lean) * math.cos(az), math.sin(lean) * math.sin(az), math.cos(lean))) * h
        tube(mb, [base, base.lerp(top, 0.5), top], [0.005, 0.004, 0.003], 3, (0.26, 0.30, 0.14), (0.36, 0.40, 0.20), 0.0, 0.85, rng.random(), 0.85)
        nl = rng.randint(4, 6)
        for k in range(nl):
            la = az + k * math.tau / nl + rng.gauss(0, 0.3)
            st = top + Vector((0, 0, -rng.uniform(0, 0.06)))
            ln = rng.uniform(0.15, 0.23)
            cb = (0.14, 0.24, 0.08)
            ct = lerp3((0.30, 0.42, 0.15), (0.50, 0.52, 0.30), rng.uniform(0.0, 0.35))    # 熊笹葉緣冬天會枯白：葉尖偏淡
            blade(mb, st, la, math.radians(rng.uniform(55, 75)), math.radians(rng.uniform(25, 55)), la, ln, ln * 0.17, 3, cb, ct, rng.random(), 0.25, up_bias=0.5)
    ob = mb.to_object(name)
    ob.data.materials.append(placeholder_mat("S01K_sasa", (0.2, 0.35, 0.12)))
    return ob


LITTER_PAL = [(0.36, 0.24, 0.12), (0.52, 0.36, 0.14), (0.22, 0.15, 0.09), (0.40, 0.35, 0.28), (0.46, 0.30, 0.13), (0.30, 0.22, 0.14), (0.55, 0.26, 0.10)]
LITTER_W = [0.24, 0.20, 0.16, 0.14, 0.12, 0.10, 0.04]


def litter(name, seed, size=(2.6, 2.0), n=230, twigs=4):
    rng = random.Random(seed)
    mb = MB()
    pockets = [(rng.uniform(-0.3, 0.3) * size[0], rng.uniform(-0.3, 0.3) * size[1], rng.uniform(0.18, 0.38) * min(size)) for _ in range(rng.randint(2, 4))]
    placed = 0
    tries = 0
    while placed < n and tries < n * 20:
        tries += 1
        x = rng.uniform(-0.5, 0.5) * size[0]
        y = rng.uniform(-0.5, 0.5) * size[1]
        rr = math.sqrt((2 * x / size[0]) ** 2 + (2 * y / size[1]) ** 2)
        edge = 0.72 + 0.28 * fbm(Vector((x * 1.3, y * 1.3, 0.5)), seed, 2)
        dens = (1.0 - sstep(edge - 0.35, edge, rr)) * 0.35
        for (px, py, pr) in pockets:                       # 堆積處（窪、根邊）：疊得多
            dens = max(dens, math.exp(-((x - px) ** 2 + (y - py) ** 2) / (pr * pr)) * (1.0 - sstep(edge - 0.2, edge + 0.1, rr)))
        if rng.random() > dens:
            continue
        placed += 1
        L = rng.uniform(0.05, 0.10)
        W = L * rng.uniform(0.38, 0.62)
        yaw = rng.uniform(0, math.tau)
        fwd = Vector((math.cos(yaw), math.sin(yaw), rng.uniform(-0.15, 0.15)))
        up = Vector((rng.gauss(0, 0.18), rng.gauss(0, 0.18), 1.0)).normalized()
        col = rng.choices(LITTER_PAL, LITTER_W)[0]
        k = rng.uniform(0.82, 1.15) * lerp(1.0, 0.82, dens)        # 中央較深（疊得多、較濕）
        col = (col[0] * k, col[1] * k, col[2] * k)
        z = 0.004 + rng.random() * 0.012 * dens
        c = Vector((x, y, z)) - fwd * L * 0.5
        side = up.cross(fwd).normalized()
        nn = up
        curl = rng.uniform(0.004, 0.012)
        a = mb.v(c, nn, col, (0.5, 0.7), (0, 1))
        m0 = mb.v(c + fwd * L * 0.40 + side * W * 0.5 + up * curl, nn, col, (0, 0.7), (0, 1))
        m1 = mb.v(c + fwd * L * 0.40 - side * W * 0.5 + up * curl, nn, col, (1, 0.7), (0, 1))
        mm = mb.v(c + fwd * L * 0.45 - up * 0.002, nn, (col[0] * 0.9, col[1] * 0.9, col[2] * 0.9), (0.5, 0.7), (0, 1))
        tp = mb.v(c + fwd * L + up * curl * 0.6, nn, col, (0.5, 0.7), (0, 1))
        mb.tri(a, mm, m0)
        mb.tri(a, m1, mm)
        mb.tri(m0, mm, tp)
        mb.tri(mm, m1, tp)
    for t in range(twigs):
        x = rng.uniform(-0.35, 0.35) * size[0]
        y = rng.uniform(-0.35, 0.35) * size[1]
        yaw = rng.uniform(0, math.tau)
        ln = rng.uniform(0.18, 0.45)
        d = Vector((math.cos(yaw), math.sin(yaw), 0))
        p0 = Vector((x, y, 0.012))
        tube(mb, [p0, p0 + d * ln * 0.5 + Vector((0, 0, 0.004)), p0 + d * ln], [0.007, 0.006, 0.004], 3, (0.22, 0.17, 0.12), (0.30, 0.24, 0.17), 0.7, 0.7, 0, 1)
    ob = mb.to_object(name)
    ob.data.materials.append(placeholder_mat("S01K_litter", (0.4, 0.28, 0.14)))
    return ob


def moss(name, seed, size=(1.3, 1.0), res=(16, 13)):
    rng = random.Random(seed)
    mb = MB()
    nx, ny = res
    blobs = [(0.0, 0.0, 0.42)] + [(rng.uniform(-0.45, 0.45) * size[0], rng.uniform(-0.4, 0.4) * size[1], rng.uniform(0.08, 0.22)) for _ in range(4)]
    ids = {}
    for j in range(ny + 1):
        for i in range(nx + 1):
            x = (i / nx - 0.5) * size[0] + rng.uniform(-0.015, 0.015)
            y = (j / ny - 0.5) * size[1] + rng.uniform(-0.015, 0.015)
            m = 0.0
            for (bx, by, br) in blobs:
                rr = math.sqrt(((x - bx) / br) ** 2 + ((y - by) / (br * 0.8)) ** 2)
                edge = 0.85 + 0.3 * fbm(Vector((x * 2.2, y * 2.2, br)), seed, 2)
                m = max(m, 1.0 - sstep(edge - 0.3, edge, rr))
            m *= sstep(-0.42, -0.22, fbm(Vector((x * 5.5, y * 5.5, 3.3)), seed + 7, 1))      # 破洞
            bump = 0.5 + 0.5 * fbm(Vector((x * 7.0, y * 7.0, 1.3)), seed + 3, 2)
            z = m * (0.025 + 0.055 * bump) - (1 - m) * 0.025
            col = lerp3((0.22, 0.28, 0.09), (0.40, 0.44, 0.15), bump * m)
            ids[(i, j)] = (mb.v((x, y, z), (0, 0, 1), col, (0.5, 0.7), (0, 1)), z)
    for j in range(ny):
        for i in range(nx):
            q = [ids[(i, j)], ids[(i + 1, j)], ids[(i + 1, j + 1)], ids[(i, j + 1)]]
            if max(v[1] for v in q) <= 0.0:
                continue
            mb.quad(q[0][0], q[1][0], q[2][0], q[3][0])
    ob = mb.to_object(name, custom_normals=False)
    ob.data.shade_smooth()
    ob.data.materials.append(placeholder_mat("S01K_moss", (0.3, 0.38, 0.12)))
    return ob


def twigs(name, seed, n=9, area=1.3):
    rng = random.Random(seed)
    mb = MB()
    for t in range(n):
        x = rng.uniform(-0.5, 0.5) * area
        y = rng.uniform(-0.5, 0.5) * area
        yaw = rng.uniform(0, math.tau)
        ln = rng.uniform(0.25, 0.75)
        r = rng.uniform(0.006, 0.013)
        d = Vector((math.cos(yaw), math.sin(yaw), 0))
        sd = Vector((-d.y, d.x, 0))
        bend = rng.gauss(0, 0.05)
        pts = [Vector((x, y, r)) + d * ln * (k / 3) + sd * bend * math.sin(math.pi * k / 3) for k in range(4)]
        col = lerp3((0.20, 0.15, 0.10), (0.34, 0.27, 0.19), rng.random())
        tube(mb, pts, [r, r * 0.9, r * 0.75, r * 0.5], 4, col, col, 0.7, 0.7, 0, 1)
        if rng.random() < 0.5:
            a = yaw + rng.choice((-1, 1)) * rng.uniform(0.4, 0.8)
            d2 = Vector((math.cos(a), math.sin(a), 0))
            p0 = pts[1]
            tube(mb, [p0, p0 + d2 * ln * 0.25, p0 + d2 * ln * 0.45], [r * 0.7, r * 0.55, r * 0.4], 3, col, col, 0.7, 0.7, 0, 1)
    ob = mb.to_object(name)
    ob.data.materials.append(placeholder_mat("S01K_twig", (0.3, 0.22, 0.15)))
    return ob


# ============================================================ 岩
def _rand_dir(rng, max_up=0.72, allow_top=False):
    """切面法線：避開接近水平的切面（|n.z| 太大＝水平節理面＝疊石板感）。"""
    while True:
        v = Vector((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1)))
        if v.length < 1e-6:
            continue
        v.normalize()
        if abs(v.z) <= max_up or (allow_top and v.z > 0 and v.z < 0.93):
            return v


def joint_set(rng, dip_deg=(25, 40)):
    """一組節理：兩組近直立的節理（交角 60–85°）＋一組斜傾的層面（傾角 25–40°，不水平）。回傳 [(法線, 權重)]。"""
    az = rng.uniform(0, math.tau)
    az2 = az + math.radians(rng.uniform(60, 85))
    dip = math.radians(rng.uniform(*dip_deg))
    daz = az + math.radians(rng.uniform(20, 70))
    return [(Vector((math.cos(az), math.sin(az), rng.uniform(-0.12, 0.12))).normalized(), 1.0),
            (Vector((math.cos(az2), math.sin(az2), rng.uniform(-0.12, 0.12))).normalized(), 0.8),
            (Vector((math.sin(dip) * math.cos(daz), math.sin(dip) * math.sin(daz), math.cos(dip))).normalized(), 0.45)]


def _joint_dir(rng, joints):
    ws = [w for _, w in joints]
    n, _ = rng.choices(joints, ws)[0]
    j = Vector((rng.gauss(0, 0.13), rng.gauss(0, 0.13), rng.gauss(0, 0.13)))
    v = (n + j).normalized()
    if n.z > 0.6:                    # 層面只切上方（頂面斜傾），不切出底下的水平板
        return v
    return v if rng.random() < 0.5 else -v


def rock_shell(bm, seed, size, center, rot, n_cuts=9, cut_depth=(0.55, 0.85), cracks=3, crack_w=0.10, crack_d=0.10,
               lump=0.14, micro=0.025, subdiv=4, top_cut=True, crack_vertical=0.75, joints=None):
    """一個岩體：橢球 → 斜切面夾平（節理面）→ 穿過岩體的裂縫（V 形凹槽）→ 起伏。加進 bm。"""
    rng = random.Random(seed)
    tb = bmesh.new()
    bmesh.ops.create_icosphere(tb, subdivisions=subdiv, radius=1.0)
    hx, hy, hz = size[0] * 0.5, size[1] * 0.5, size[2] * 0.5
    for v in tb.verts:
        p = v.co.copy()
        p *= 1.0 + lump * fbm(p * 0.9, seed, 3)
        v.co = Vector((p.x * hx, p.y * hy, p.z * hz))
    planes = []
    rinv = rot.to_matrix().inverted()

    def jit(v, a):
        return (v + Vector((rng.gauss(0, a), rng.gauss(0, a), rng.gauss(0, a)))).normalized()

    def sup_of(n):
        return max(v.co.dot(n) for v in tb.verts)
    if joints:
        # 節理在世界座標裡是同一組方向（整塊岩共用）：兩組直立節理各切兩側
        for (jn, w) in joints[:2]:
            for sgn in (1, -1):
                n = rinv @ jit(jn * sgn, 0.07)
                planes.append((n, sup_of(n) * rng.uniform(0.60, 0.84)))
        n = rinv @ jit(joints[2][0], 0.06)                 # 斜傾的頂面（層面，不水平）
        planes.append((n, sup_of(n) * rng.uniform(0.70, 0.88)))
        for k in range(max(0, n_cuts - 5)):               # 角部破斷：斜的小切面
            n = _rand_dir(rng, 0.70)
            planes.append((n, sup_of(n) * rng.uniform(0.74, 0.92)))
    else:
        for k in range(n_cuts):
            n = _rand_dir(rng, 0.72, allow_top=(top_cut and k == 0))
            planes.append((n, sup_of(n) * rng.uniform(*cut_depth)))
    for n, d in planes:
        for v in tb.verts:
            e = v.co.dot(n) - d
            if e > 0:
                v.co -= n * e
    # 裂縫：直立／斜向為主（|n.z| 小＝直立的面）
    for k in range(cracks):
        if joints:
            n = rinv @ _joint_dir(rng, joints[:2] if rng.random() < crack_vertical else joints)
        elif rng.random() < crack_vertical:
            n = Vector((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 0.25))).normalized()
        else:
            n = _rand_dir(rng, 0.8)
        off = rng.uniform(-0.35, 0.35)
        o = Vector((hx * off * n.x, hy * off * n.y, hz * off * n.z))
        w = max(crack_w * rng.uniform(0.7, 1.3) * max(size) * 0.5, 0.09)
        dep = crack_d * rng.uniform(0.6, 1.3) * max(size) * 0.5
        # 裂縫不一定貫穿：用另一個方向的 noise 決定裂縫開口沿線的深淺
        for v in tb.verts:
            dist = (v.co - o).dot(n)
            if abs(dist) < w:
                f = (1.0 - abs(dist) / w) ** 2
                g = sstep(-0.2, 0.4, fbm(v.co * 0.8, seed + 11 * k, 2))
                inward = -v.co.normalized()
                v.co += inward * dep * f * g
    tb.normal_update()
    for v in tb.verts:
        v.co += v.normal * (micro * 1.6 * fbm(v.co * 0.9, seed + 3, 2) + micro * fbm(v.co * 3.1, seed + 5, 2) + micro * 0.4 * fbm(v.co * 9.0, seed + 9, 1))
    m = Matrix.Translation(center) @ rot.to_matrix().to_4x4()
    bmesh.ops.transform(tb, matrix=m, verts=tb.verts)
    me = bpy.data.meshes.new("_tmp")
    tb.to_mesh(me)
    tb.free()
    bm.from_mesh(me)
    bpy.data.meshes.remove(me)


def rock_finish(name, bm, sharp_deg=34.0):
    bm.normal_update()
    sharp = [e for e in bm.edges if len(e.link_faces) == 2 and e.calc_face_angle(0.0) > math.radians(sharp_deg)]
    bmesh.ops.split_edges(bm, edges=sharp)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.shade_smooth()
    ob = bpy.data.objects.new(name, me)
    coll().objects.link(ob)
    ob.data.materials.append(placeholder_mat("S01K_rock", (0.45, 0.43, 0.40)))
    return ob


def rock_cliff(name, seed, W, H, D, shells=3, below=1.0):
    """崖面岩段：2–3 個不同方向的岩體交疊（交線＝節理），整體高而不方。"""
    rng = random.Random(seed)
    bm = bmesh.new()
    J = joint_set(rng)
    for s in range(shells):
        f = 1.0 if s == 0 else rng.uniform(0.55, 0.75)
        sz = (W * (0.62 if s == 0 else 0.45) * rng.uniform(0.9, 1.1), D * rng.uniform(0.8, 1.0) * (1.0 if s == 0 else 0.85), H * f * rng.uniform(0.92, 1.08) + below)
        cx = 0.0 if s == 0 else (1 if s == 1 else -1) * W * rng.uniform(0.20, 0.28)
        cy = (0.0 if s == 0 else rng.uniform(-0.05, 0.25) * D)
        cz = sz[2] * 0.5 - below * rng.uniform(0.9, 1.15)
        rot = Euler((math.radians(rng.uniform(-6, 6)), math.radians(rng.uniform(-6, 6)), math.radians(rng.uniform(-12, 12))), 'XYZ')
        rock_shell(bm, seed * 7 + s, sz, Vector((cx, cy, cz)), rot, n_cuts=rng.randint(8, 10), cut_depth=(0.5, 0.8), cracks=1,
                   lump=0.05, micro=0.022, subdiv=5 if s == 0 else 4, joints=J, crack_w=0.08, crack_d=0.05)
    return rock_finish(name, bm)


def rock_simple(name, seed, size, below, n_cuts=8, cracks=2, subdiv=4, lump=0.14, tilt=(0, 0, 0), micro=0.025, crack_w=0.10, crack_d=0.10, joints=True, cut_depth=(0.55, 0.85)):
    bm = bmesh.new()
    rot = Euler(tuple(math.radians(a) for a in tilt), 'XYZ')
    J = joint_set(random.Random(seed + 999)) if joints else None
    rock_shell(bm, seed, size, Vector((0, 0, size[2] * 0.5 - below)), rot, n_cuts=n_cuts, cracks=cracks, subdiv=subdiv, lump=lump, micro=micro,
               crack_w=crack_w, crack_d=crack_d, joints=J, cut_depth=cut_depth)
    return rock_finish(name, bm)


def debris(name, seed, n=7, area=1.6):
    rng = random.Random(seed)
    bm = bmesh.new()
    for k in range(n):
        s = rng.uniform(0.14, 0.48) * (1.0 if k < 2 else 0.7)
        sz = (s * rng.uniform(0.9, 1.4), s * rng.uniform(0.7, 1.1), s * rng.uniform(0.45, 0.8))
        x = rng.gauss(0, 0.32) * area
        y = rng.gauss(0, 0.22) * area
        rot = Euler((math.radians(rng.uniform(-30, 30)), math.radians(rng.uniform(-30, 30)), rng.uniform(0, math.tau)), 'XYZ')
        rock_shell(bm, seed * 13 + k, sz, Vector((x, y, sz[2] * 0.5 - sz[2] * rng.uniform(0.35, 0.55))), rot, n_cuts=rng.randint(7, 10), cut_depth=(0.45, 0.75), cracks=0, subdiv=3, lump=0.08, micro=0.008)
    return rock_finish(name, bm, 38.0)


# ============================================================ 木
def log(name, seed, L, r0, r1, nlen=26, nrad=14, stub=False, split_end=True, hollow=False, squash=1.0):
    rng = random.Random(seed)
    mb = MB()
    pts = []
    radii = []
    bend = rng.uniform(0.04, 0.10) * L
    for i in range(nlen + 1):
        t = i / nlen
        x = (t - 0.5) * L
        r = lerp(r0, r1, t ** 0.8) * (1 + 0.13 * fbm(Vector((x * 0.45, 0.3, 0.1)), seed, 2))
        y = math.sin(t * math.pi) * bend * 0.5 + 0.04 * fbm(Vector((x * 0.5, 1.7, 0)), seed, 2)
        z = r0 * 0.92 + math.sin(t * math.pi) * bend * 0.25
        pts.append(Vector((x, y, z)))
        radii.append(r)
    circ = math.tau * (r0 + r1) * 0.5
    scars = [(rng.uniform(0, math.tau), rng.uniform(0.15, 0.85) * L, rng.uniform(0.08, 0.16)) for _ in range(rng.randint(2, 4))]
    rings = []
    acc = 0.0
    for i in range(nlen + 1):
        if i > 0:
            acc += (pts[i] - pts[i - 1]).length
        d = (pts[min(i + 1, nlen)] - pts[max(i - 1, 0)]).normalized()
        s1 = d.cross(Vector((0, 0, 1))).normalized()
        s2 = d.cross(s1).normalized()
        ring = []
        for j in range(nrad + 1):
            a = math.tau * j / nrad
            ridge = 1.0 + 0.045 * math.sin(a * 9 + 2.0 * fbm(Vector((acc * 1.2, a, 0.5)), seed + 3, 2)) + 0.03 * fbm(Vector((acc * 2.5, a * 2, 0)), seed + 4, 2)
            ridge *= 1.0 + 0.10 * math.cos(2 * a + 0.7 * fbm(Vector((acc * 0.4, 0, 2)), seed, 1))        # 斷面不正圓
            for (sa, sx, sr) in scars:                                                             # 枝痕的隆起
                da = math.atan2(math.sin(a - sa), math.cos(a - sa))
                ridge *= 1.0 + 0.22 * math.exp(-(da * da) / 0.12 - ((acc - sx) ** 2) / (sr * sr))
            off = s1 * math.cos(a) + s2 * math.sin(a) * squash
            ring.append(mb.v(pts[i] + off * radii[i] * ridge, off, (1, 1, 1), (j / nrad * (circ / 1.0), acc / 1.0), (0, 0)))
        rings.append(ring)
    for i in range(nlen):
        for j in range(nrad):
            mb.quad(rings[i][j], rings[i][j + 1], rings[i + 1][j + 1], rings[i + 1][j])
    # 兩端：斷裂（木刺）或鋸平的老斷面
    for end, sgn in ((0, -1), (nlen, 1)):
        c = pts[end]
        d = (pts[min(end + 1, nlen)] - pts[max(end - 1, 0)]).normalized() * sgn
        s1 = d.cross(Vector((0, 0, 1))).normalized()
        s2 = d.cross(s1).normalized()
        jag = split_end and (end == nlen or rng.random() < 0.7)
        if hollow:
            # 腐朽的中空端：外圈一道朽木緣，往內凹成暗的空洞（不是新鮮斷面）
            inner = []
            for j in range(nrad + 1):
                a = math.tau * j / nrad
                off = s1 * math.cos(a) + s2 * math.sin(a) * squash
                inner.append(mb.v(c + off * radii[end] * rng.uniform(0.55, 0.7) - d * rng.uniform(0.0, 0.05), -d, (0.46, 0.36, 0.25), (math.cos(a) * 0.3, math.sin(a) * 0.3), (0, 0)))
            ctr = mb.v(c - d * rng.uniform(0.35, 0.6), -d, (0.10, 0.08, 0.06), (0, 0), (0, 0))
            for j in range(nrad):
                if sgn < 0:
                    mb.quad(rings[end][j], inner[j], inner[j + 1], rings[end][j + 1])
                    mb.tri(inner[j], ctr, inner[j + 1])
                else:
                    mb.quad(rings[end][j + 1], inner[j + 1], inner[j], rings[end][j])
                    mb.tri(inner[j + 1], ctr, inner[j])
            continue
        inner = []
        for j in range(nrad + 1):
            a = math.tau * j / nrad
            off = s1 * math.cos(a) + s2 * math.sin(a)
            bundle = max(0.0, math.sin(a * 3 + seed + end)) ** 2           # 木刺成束（順木紋）
            ext = ((0.15 + 1.1 * bundle) * rng.uniform(0.5, 1.0) if jag else rng.uniform(0.0, 0.03)) * radii[end] * 2.2
            inner.append(mb.v(c + off * radii[end] * 0.72 + d * ext, d, (0.85, 0.78, 0.66), (math.cos(a) * 0.3, math.sin(a) * 0.3), (0, 0)))
        ctr = mb.v(c + d * (0.04 if jag else 0.0) * radii[end], d, (0.70, 0.60, 0.48), (0, 0), (0, 0))
        for j in range(nrad):
            if sgn > 0:
                mb.quad(rings[end][j], inner[j], inner[j + 1], rings[end][j + 1])
                mb.tri(inner[j], ctr, inner[j + 1])
            else:
                mb.quad(rings[end][j + 1], inner[j + 1], inner[j], rings[end][j])
                mb.tri(inner[j + 1], ctr, inner[j])
    if stub:
        i = int(nlen * 0.62)
        base = pts[i]
        d = Vector((0.25, 0.55, 0.8)).normalized()
        q = [base - d * radii[i] * 0.3, base + d * radii[i] * 0.9, base + d * 0.42, base + d * 0.66 + Vector((0.05, 0, 0))]
        tube(mb, q, [radii[i] * 0.62, radii[i] * 0.50, radii[i] * 0.30, radii[i] * 0.16], 7, (1, 1, 1), (1, 1, 1), uv_scale=1.0)
    if squash != 1.0:
        # 斷面壓扁後底部會離地（z min > 0）：整根往下移，讓地面線回到 z=0（擺放的貼地以 z≈0 的頂點為地面線）
        zmin = min(q[2] for q in mb.P)
        mb.P = [(q[0], q[1], q[2] - zmin) for q in mb.P]
    ob = mb.to_object(name, custom_normals=False)
    ob.data.shade_smooth()
    ob.data.materials.append(placeholder_mat("S01K_wood", (0.35, 0.28, 0.2)))
    return ob


def roots(name, seed, n=6, R=(1.2, 2.3), r0=0.17):
    """根群：主根 2 條朝 +X（擺放時轉向下坡）又粗又長，其他細短、不等距；樹幹在原點（半徑約 0.3 m 的部分被樹幹蓋住）。"""
    rng = random.Random(seed)
    mb = MB()
    azs = [rng.uniform(-0.5, -0.15), rng.uniform(0.15, 0.6)] + [rng.uniform(0.9, 5.4) for _ in range(n - 2)]
    for k in range(n):
        az = azs[k]
        main = k < 2
        ln = rng.uniform(*R) * (1.0 if main else rng.uniform(0.35, 0.6))
        nseg = 9
        pts, rad = [], []
        lat = rng.gauss(0, 0.25)
        for i in range(nseg + 1):
            t = i / nseg
            a = az + lat * math.sin(t * math.pi) + 0.15 * fbm(Vector((t * 3, k, 0)), seed, 1)
            rr = 0.22 + ln * t
            z = 0.16 * (1 - t) ** 1.2 + 0.06 * math.sin(t * math.pi * 1.4) * rng.uniform(0.6, 1.2) - 0.22 * sstep(0.7, 1.0, t)
            pts.append(Vector((math.cos(a) * rr, math.sin(a) * rr, z)))
            rad.append(r0 * (1.0 if main else 0.55) * (1 - t) ** 1.3 * rng.uniform(0.85, 1.1) + 0.016)
        tube(mb, pts, rad, 7, (1, 1, 1), (1, 1, 1), uv_scale=0.8)
        if main or rng.random() < 0.3:
            j = rng.randint(3, 5)
            a2 = az + rng.choice((-1, 1)) * rng.uniform(0.5, 0.9)
            p0 = pts[j]
            q = [p0, p0 + Vector((math.cos(a2), math.sin(a2), -0.02)) * 0.35, p0 + Vector((math.cos(a2), math.sin(a2), -0.12)) * 0.7]
            tube(mb, q, [rad[j] * 0.65, rad[j] * 0.45, 0.012], 5, (1, 1, 1), (1, 1, 1), uv_scale=0.8)
    ob = mb.to_object(name, custom_normals=False)
    ob.data.shade_smooth()
    ob.data.materials.append(placeholder_mat("S01K_wood", (0.35, 0.28, 0.2)))
    return ob


def branch(name, seed, L=2.3, r0=0.065):
    rng = random.Random(seed)
    mb = MB()
    pts = []
    rad = []
    for i in range(9):
        t = i / 8
        x = (t - 0.5) * L
        pts.append(Vector((x, 0.12 * math.sin(t * 2.6) + 0.04 * rng.gauss(0, 1), r0 * (1 - 0.6 * t) + 0.01 + 0.06 * math.sin(t * 3.1) ** 2)))
        rad.append(r0 * (1 - 0.65 * t) + 0.008)
    tube(mb, pts, rad, 7, (1, 1, 1), (1, 1, 1), uv_scale=0.6)
    for k in range(3):
        j = rng.randint(2, 6)
        a = rng.choice((-1, 1)) * rng.uniform(0.5, 0.9)
        d = Vector((math.cos(a), math.sin(a), 0.0))
        ln = rng.uniform(0.35, 0.8)
        p0 = pts[j]
        up = rng.uniform(-0.02, 0.25)
        q = [p0, p0 + d * ln * 0.5 + Vector((0, 0, up)), p0 + d * ln + Vector((0, 0, up * 0.6 - 0.03))]
        tube(mb, q, [rad[j] * 0.6, rad[j] * 0.42, 0.01], 5, (1, 1, 1), (1, 1, 1), uv_scale=0.6)
    ob = mb.to_object(name, custom_normals=False)
    ob.data.shade_smooth()
    ob.data.materials.append(placeholder_mat("S01K_wood", (0.35, 0.28, 0.2)))
    return ob


# ============================================================ R5 新資產
def fuki(name, seed, n_leaves=7, H=(0.24, 0.50), R=(0.11, 0.19), spread=0.16, lod=0):
    """蕗（フキ）：地下莖叢生；長葉柄頂端一片圓腎形大葉（葉柄側有缺口）、葉緣微波上翹、遠端稍垂、朝外上方。"""
    rng = random.Random(seed)
    mb = MB()
    nseg = 12 if lod == 0 else 7
    for k in range(n_leaves):
        az = rng.uniform(0, math.tau)
        r0 = math.sqrt(rng.random()) * spread
        base = Vector((math.cos(az) * r0, math.sin(az) * r0, -0.02))
        h = rng.uniform(*H)
        lean = rng.uniform(0.05, 0.26)
        out = Vector((math.cos(az), math.sin(az), 0.0))
        top = base + (out * math.sin(lean) + Vector((0, 0, math.cos(lean)))) * h
        ph = rng.random()
        t_w = min(1.0, h / max(H[1], 0.01))
        if lod == 0:
            tube(mb, [base, base.lerp(top, 0.55) + out * h * 0.04, top], [0.007, 0.006, 0.005], 3, (0.22, 0.27, 0.12), (0.30, 0.36, 0.17), 0.0, t_w * 0.8, ph, 0.7)
        rr = rng.uniform(*R)
        tilt = math.radians(rng.uniform(12, 38))
        n = (Vector((0, 0, 1)) * math.cos(tilt) + out * math.sin(tilt)).normalized()
        fwd = (out - n * out.dot(n)).normalized()
        side = n.cross(fwd).normalized()
        ctr = top + fwd * rr * 0.55
        cb = lerp3((0.18, 0.28, 0.10), (0.22, 0.32, 0.12), rng.random())
        ce = lerp3((0.24, 0.35, 0.13), (0.29, 0.40, 0.16), rng.random())       # 葉緣只比葉心亮一點（太亮會讀成一圈亮線）
        c_id = mb.v(ctr - n * rr * 0.05, n, cb, (0.5, t_w), (ph, 0.6))
        notch = math.radians(rng.uniform(9, 16))
        ri, ro = [], []
        for j in range(nseg + 1):
            a = -math.pi + notch + (math.tau - 2 * notch) * j / nseg
            d = fwd * math.cos(a) + side * math.sin(a)
            wav = 1.0 + 0.06 * math.sin(a * 7 + seed + k) + 0.04 * rng.uniform(-1, 1)
            p_in = ctr + d * rr * 0.5 * wav + n * rr * 0.02
            p_out = ctr + d * rr * wav + n * rr * (0.10 + 0.05 * math.sin(a * 3 + k)) - n * rr * 0.14 * max(0.0, math.cos(a))
            ri.append(mb.v(p_in, n, lerp3(cb, ce, 0.5), (0.5, t_w), (ph, 0.6)))
            ro.append(mb.v(p_out, n, ce, (0.5, t_w), (ph, 0.6)))
        for j in range(nseg):
            mb.tri(c_id, ri[j], ri[j + 1])
            mb.quad(ri[j], ro[j], ro[j + 1], ri[j + 1])
    ob = mb.to_object(name)
    ob.data.materials.append(placeholder_mat("S01K_herb", (0.2, 0.34, 0.12)))
    return ob


def broad_herb(name, seed, n_leaves=10, L=(0.20, 0.32), W=0.66, cb=(0.24, 0.34, 0.18), ct=(0.42, 0.53, 0.31), lod=0):
    """擬寶珠（ギボウシ）型：根生葉、長柄＋卵形葉身（中肋 V 摺），由內往外拱、葉尖下垂。"""
    rng = random.Random(seed)
    mb = MB()
    segs = 6 if lod == 0 else 3
    for k in range(n_leaves):
        az = k * 2.4 + rng.gauss(0, 0.3)
        elev = math.radians(rng.uniform(38, 66))
        droop = math.radians(rng.uniform(35, 65))
        ln = rng.uniform(*L)
        pet = ln * rng.uniform(0.35, 0.6)
        ph = rng.random()
        out = Vector((math.cos(az), math.sin(az), 0.0))
        base = Vector((rng.gauss(0, 0.025), rng.gauss(0, 0.025), -0.02))
        d0 = Vector((math.cos(elev) * out.x, math.cos(elev) * out.y, math.sin(elev)))
        p = base + d0 * pet
        if lod == 0:
            tube(mb, [base, base.lerp(p, 0.5), p], [0.006, 0.005, 0.004], 3, (0.18, 0.24, 0.12), (0.24, 0.31, 0.15), 0.0, 0.35, ph, 0.6)
        side = Vector((-out.y, out.x, 0.0))
        tint = rng.uniform(0.88, 1.1)
        c0 = (cb[0] * tint, cb[1] * tint, cb[2] * tint)
        c1 = (ct[0] * tint, ct[1] * tint, ct[2] * tint)
        rows = []
        for i in range(segs + 1):
            t = i / segs
            e = elev * 0.75 - droop * t ** 1.4
            d = Vector((math.cos(e) * out.x, math.cos(e) * out.y, math.sin(e)))
            nrm = side.cross(d).normalized()
            if nrm.z < 0:
                nrm = -nrm
            w = W * ln * math.sin(math.pi * min(1.0, 0.08 + 0.92 * t) ** 0.8) * 0.5
            fold = 0.06 * w
            col = lerp3(c0, c1, 0.3 + 0.7 * t)
            tw = 0.35 + 0.65 * t
            nn = (nrm * 0.5 + Vector((0, 0, 0.5))).normalized()
            rows.append((mb.v(p - side * w - nrm * fold, nn, col, (0, tw), (ph, 0.5)),
                         mb.v(p, nn, lerp3(col, c0, 0.25), (0.5, tw), (ph, 0.5)),
                         mb.v(p + side * w - nrm * fold, nn, col, (1, tw), (ph, 0.5))))
            p = p + d * ln / segs
        for i in range(segs):
            a, b = rows[i], rows[i + 1]
            mb.quad(a[0], a[1], b[1], b[0])
            mb.quad(a[1], a[2], b[2], b[1])
    ob = mb.to_object(name)
    ob.data.materials.append(placeholder_mat("S01K_herb", (0.2, 0.34, 0.12)))
    return ob


def sapling(name, seed, H=1.6, kind="maple", n_br=5, leaves=70, autumn=0.05):
    """林下幼樹：細幹、上半段 4–6 支斜上的枝，枝端成平展的葉叢（林下的光往上，葉面朝上）。kind＝maple（掌狀五裂）／broad（卵形葉）。"""
    rng = random.Random(seed)
    mb = MB()
    pts = [Vector((0, 0, -0.03))]
    d = Vector((rng.gauss(0, 0.08), rng.gauss(0, 0.08), 1.0)).normalized()
    for i in range(6):
        d = (d + Vector((rng.gauss(0, 0.07), rng.gauss(0, 0.07), 0.0))).normalized()
        pts.append(pts[-1] + d * H / 6)
    tube(mb, pts, [0.021 * (1 - i / 7) + 0.004 for i in range(len(pts))], 5, (0.23, 0.19, 0.14), (0.30, 0.26, 0.18), 0.0, 1.0, rng.random(), 0.85)
    tips = [(pts[-1], d, 1.0), (pts[-2], d, 0.9)]
    for b in range(n_br):
        t = 0.38 + 0.55 * (b + rng.random() * 0.6) / n_br
        i = min(int(t * 6), 5)
        f = t * 6 - i
        p0 = pts[i].lerp(pts[i + 1], f)
        az = b * 2.4 + rng.gauss(0, 0.4)
        el = math.radians(rng.uniform(18, 48))
        ln = H * rng.uniform(0.18, 0.32) * (1.25 - 0.55 * t)
        dd = Vector((math.cos(el) * math.cos(az), math.cos(el) * math.sin(az), math.sin(el)))
        q = [p0, p0 + dd * ln * 0.5 + Vector((0, 0, ln * 0.05)), p0 + dd * ln - Vector((0, 0, ln * 0.04))]
        tube(mb, q, [0.007, 0.005, 0.003], 3, (0.26, 0.22, 0.16), (0.30, 0.26, 0.18), t, min(1.0, t + 0.15), rng.random(), 0.7)
        tips += [(q[1], dd, t), (q[2], dd, min(1.0, t + 0.1))]
    if kind == "maple":
        ca, cbb, cbase = (0.24, 0.36, 0.11), (0.40, 0.49, 0.17), (0.14, 0.22, 0.07)
    else:
        ca, cbb, cbase = (0.20, 0.32, 0.10), (0.33, 0.43, 0.15), (0.12, 0.20, 0.07)
    for k in range(leaves):
        tp, dd, t = tips[rng.randrange(len(tips))]
        c = tp + Vector((rng.gauss(0, 0.055), rng.gauss(0, 0.055), rng.gauss(0, 0.025)))
        yaw = rng.uniform(0, math.tau)
        fwd = Vector((math.cos(yaw), math.sin(yaw), rng.uniform(-0.25, 0.1))).normalized()
        up = Vector((rng.gauss(0, 0.2), rng.gauss(0, 0.2), 1.0)).normalized()
        side = up.cross(fwd).normalized()
        ct = lerp3(ca, cbb, rng.random())
        if rng.random() < autumn:
            ct = lerp3((0.62, 0.30, 0.10), (0.70, 0.46, 0.14), rng.random())
        ph = rng.random()
        if kind == "maple":
            L = rng.uniform(0.065, 0.095)
            for lobe in (-1.25, -0.62, 0.0, 0.62, 1.25):
                f2 = (fwd * math.cos(lobe) + side * math.sin(lobe)).normalized()
                leaf(mb, c, f2, up, L * (1.0 - 0.28 * abs(lobe)), L * 0.36, cbase, ct, ph, 0.5, t, droop=0.1)
        else:
            L = rng.uniform(0.08, 0.13)
            leaf(mb, c, fwd, up, L, L * 0.50, cbase, ct, ph, 0.5, t, droop=0.15)
    ob = mb.to_object(name)
    ob.data.materials.append(placeholder_mat("S01K_sapling", (0.2, 0.34, 0.12)))
    return ob


def kumazasa(name, seed, n_culms=10, H=(0.38, 0.72), spread=0.42, lod=0):
    """隈笹型（R5）：細稈只在上端分出 1–2 節，每節 4–7 片寬披針形大葉（長 18–27 cm、寬 4.5–6 cm）近水平展開成「葉傘」；
    很多叢連在一起時上面是一層連續的葉面（不是一根根細稈）。葉緣微淡（隈）。"""
    rng = random.Random(seed)
    mb = MB()
    segs = 3 if lod == 0 else 2
    for c in range(n_culms):
        a = rng.uniform(0, math.tau)
        r = math.sqrt(rng.random()) * spread
        base = Vector((math.cos(a) * r, math.sin(a) * r, -0.02))
        h = rng.uniform(*H)
        az = a + rng.gauss(0, 0.6)
        lean = rng.uniform(0.10, 0.35)
        out = Vector((math.cos(az), math.sin(az), 0.0))
        mid = base + Vector((0, 0, h * 0.55)) + out * h * math.sin(lean) * 0.35
        top = base + Vector((0, 0, h * math.cos(lean))) + out * h * math.sin(lean)
        ph = rng.random()
        if lod == 0:
            tube(mb, [base, mid, top], [0.0045, 0.004, 0.003], 3, (0.24, 0.28, 0.13), (0.32, 0.36, 0.18), 0.0, 0.85, ph, 0.85)
        nodes = [top, base.lerp(top, rng.uniform(0.70, 0.82))]
        if rng.random() < 0.5:
            nodes.append(base.lerp(top, rng.uniform(0.52, 0.62)))
        for ni, nd in enumerate(nodes):
            nl = (rng.randint(4, 6) if ni == 0 else rng.randint(3, 4)) if lod == 0 else (3 if ni == 0 else 2)
            for k in range(nl):
                la = az + (k - (nl - 1) / 2) * rng.uniform(0.6, 0.95) + rng.gauss(0, 0.25) + ni * 2.1
                ln = rng.uniform(0.18, 0.27) * (1.0 if ni == 0 else 0.9)
                wd = ln * rng.uniform(0.21, 0.26)
                el0 = math.radians(rng.uniform(5, 28))
                dr = math.radians(rng.uniform(20, 45))
                d0 = Vector((math.cos(la), math.sin(la), 0.0))
                side = Vector((-math.sin(la), math.cos(la), 0.0))
                cb = lerp3((0.10, 0.19, 0.06), (0.13, 0.22, 0.07), rng.random())
                ct = lerp3((0.20, 0.31, 0.10), (0.27, 0.36, 0.13), rng.random())
                rim = rng.random() < 0.35
                p = nd + d0 * 0.012
                rows = []
                for i in range(segs + 1):
                    tt = i / segs
                    e = el0 - dr * tt ** 1.5
                    dv = Vector((math.cos(e) * d0.x, math.cos(e) * d0.y, math.sin(e)))
                    w = wd * 0.5 * math.sin(math.pi * min(1.0, 0.12 + 0.88 * tt)) ** 0.6
                    nrm = (side.cross(dv).normalized() * 0.6 + Vector((0, 0, 0.4))).normalized()
                    if nrm.z < 0:
                        nrm = -nrm
                    col = lerp3(cb, ct, tt)
                    ce = lerp3(col, (0.52, 0.50, 0.34), 0.45) if (rim and tt > 0.3) else col
                    fold = w * 0.18
                    uy = (0.5 + 0.5 * tt) * min(1.0, (nd.z + 0.05) / 0.5)      # UV.y＝風權重／底部 AO：葉在稈頂，不從葉基變暗
                    rows.append((mb.v(p - side * w - nrm * fold, nrm, ce, (0, uy), (ph, 0.45)),
                                 mb.v(p, nrm, col, (0.5, uy), (ph, 0.45)),
                                 mb.v(p + side * w - nrm * fold, nrm, ce, (1, uy), (ph, 0.45))))
                    p = p + dv * ln / segs
                for i in range(segs):
                    a0, b0 = rows[i], rows[i + 1]
                    mb.quad(a0[0], a0[1], b0[1], b0[0])
                    mb.quad(a0[1], a0[2], b0[2], b0[1])
    ob = mb.to_object(name)
    ob.data.materials.append(placeholder_mat("S01K_sasa", (0.2, 0.35, 0.12)))
    return ob


def stump(name, seed, H=0.7, r=0.26, n_roots=5):
    """殘株：樹幹斷在 0.5–0.8 m，斷口參差（木刺）、中心朽成暗洞；根張往外延伸後潛入地下。"""
    rng = random.Random(seed)
    mb = MB()
    nrad, nlen = 14, 7
    circ = math.tau * r
    jag = [0.04 + 0.32 * max(0.0, math.sin(math.tau * j / nrad * 2 + seed)) ** 2 * rng.uniform(0.4, 1.0) for j in range(nrad + 1)]
    jag[nrad] = jag[0]
    rings = []
    for i in range(nlen + 1):
        t = i / nlen
        ring = []
        for j in range(nrad + 1):
            a = math.tau * j / nrad
            z = -0.15 + (H + 0.15) * t + (jag[j] if i == nlen else 0.0)
            rr = r * (1.0 + 0.5 * (1 - t) ** 3) * (1 + 0.07 * math.sin(a * 6 + seed) + 0.05 * fbm(Vector((a, z * 3, 0.3)), seed, 2))
            off = Vector((math.cos(a), math.sin(a), 0.0))
            ring.append(mb.v(off * rr + Vector((0, 0, z)), off, (1, 1, 1), (j / nrad * circ, z + 0.15), (0, 0)))
        rings.append(ring)
    for i in range(nlen):
        for j in range(nrad):
            mb.quad(rings[i][j], rings[i][j + 1], rings[i + 1][j + 1], rings[i + 1][j])
    inner = []
    for j in range(nrad + 1):
        a = math.tau * j / nrad
        off = Vector((math.cos(a), math.sin(a), 0.0))
        inner.append(mb.v(off * r * 0.72 + Vector((0, 0, H + jag[j] * 0.6 - 0.02)), Vector((0, 0, 1)), (0.66, 0.54, 0.38), (math.cos(a) * 0.3, math.sin(a) * 0.3), (0, 0)))
    ctr = mb.v(Vector((0, 0, H - 0.22)), Vector((0, 0, 1)), (0.10, 0.08, 0.06), (0, 0), (0, 0))
    for j in range(nrad):
        mb.quad(rings[nlen][j], rings[nlen][j + 1], inner[j + 1], inner[j])      # 斷口朝上（繞向：外緣 → 內緣）
        mb.tri(inner[j + 1], ctr, inner[j])
    for k in range(n_roots):
        az = math.tau * k / n_roots + rng.gauss(0, 0.3)
        ln = rng.uniform(0.6, 1.3)
        pts, rad = [], []
        for i in range(7):
            t = i / 6
            rr = r * 0.7 + ln * t
            pts.append(Vector((math.cos(az) * rr, math.sin(az) * rr, 0.12 * (1 - t) ** 1.2 - 0.18 * sstep(0.6, 1.0, t))))
            rad.append(r * 0.42 * (1 - t) ** 1.2 + 0.015)
        tube(mb, pts, rad, 6, (1, 1, 1), (1, 1, 1), uv_scale=0.8)
    ob = mb.to_object(name, custom_normals=False)
    ob.data.shade_smooth()
    ob.data.materials.append(placeholder_mat("S01K_wood", (0.35, 0.28, 0.2)))
    return ob


def branch_pile(name, seed, n=4, L=(1.2, 2.3)):
    """枯枝堆：幾支斷枝交疊（下面的貼地、上面的架在上面），各帶 1–2 支側枝。"""
    rng = random.Random(seed)
    mb = MB()
    for k in range(n):
        yaw = rng.uniform(0, math.tau) if k == 0 else yaw0 + rng.uniform(-1.0, 1.0)
        if k == 0:
            yaw0 = yaw
        Lk = rng.uniform(*L)
        r0 = rng.uniform(0.025, 0.055)
        dx, dy = math.cos(yaw), math.sin(yaw)
        o = Vector((rng.gauss(0, 0.3), rng.gauss(0, 0.3), 0.0))
        pts, rad = [], []
        for i in range(7):
            t = i / 6
            x = (t - 0.5) * Lk
            lift = (0.035 * k + 0.02) * math.sin(t * math.pi)
            pts.append(o + Vector((dx * x - dy * 0.06 * math.sin(t * 3 + k), dy * x + dx * 0.06 * math.sin(t * 3 + k), r0 + lift)))
            rad.append(r0 * (1 - 0.6 * t) + 0.006)
        tube(mb, pts, rad, 5, (1, 1, 1), (1, 1, 1), uv_scale=0.6)
        for q in range(rng.randint(1, 2)):
            j = rng.randint(2, 4)
            a = yaw + rng.choice((-1, 1)) * rng.uniform(0.5, 0.9)
            d = Vector((math.cos(a), math.sin(a), 0.0))
            ln = rng.uniform(0.25, 0.55)
            p0 = pts[j]
            tube(mb, [p0, p0 + d * ln * 0.5 + Vector((0, 0, 0.03)), p0 + d * ln], [rad[j] * 0.6, rad[j] * 0.4, 0.006], 4, (1, 1, 1), (1, 1, 1), uv_scale=0.6)
    ob = mb.to_object(name, custom_normals=False)
    ob.data.shade_smooth()
    ob.data.materials.append(placeholder_mat("S01K_wood", (0.35, 0.28, 0.2)))
    return ob


# ============================================================ 清單
SEDGE_COL = ((0.11, 0.17, 0.08), (0.27, 0.36, 0.17), (0.28, 0.27, 0.17), (0.55, 0.50, 0.33))
SHADE_COL = ((0.12, 0.19, 0.08), (0.30, 0.42, 0.18), (0.26, 0.26, 0.16), (0.50, 0.48, 0.30))
GRASS = {
    "s01_grass_tall_a": dict(seed=101, n_blades=62, h=(0.55, 0.85), w=0.014, dry=0.12, seedheads=3, basal=22, spread=0.14),
    "s01_grass_tall_b": dict(seed=102, n_blades=54, h=(0.42, 0.68), w=0.016, dry=0.22, seedheads=0, tillers=(3, 3), basal=26, spread=0.18, lean=(0.10, 0.45)),
    "s01_grass_tall_c": dict(seed=103, n_blades=46, h=(0.60, 0.95), w=0.013, dry=0.45, seedheads=5, warm=0.15, basal=18, spread=0.12),
    "s01_grass_short_a": dict(seed=111, n_blades=46, h=(0.14, 0.30), w=0.011, dry=0.15, tillers=(2, 3), spread=0.11, lean=(0.15, 0.55), droop=(0.6, 1.4), segs=2, basal=10),
    "s01_grass_short_b": dict(seed=112, n_blades=40, h=(0.18, 0.36), w=0.012, dry=0.35, tillers=(2, 3), spread=0.13, lean=(0.20, 0.60), droop=(0.7, 1.5), segs=2, warm=0.1, basal=10),
    # R5：輪廓不同的草——稀疏直立帶穗（茅草型）、拱垂細葉的莎草（林緣、濕處）、林下低矮寬葉草（ササガヤ／チヂミザサ型）
    "s01_grass_tall_d": dict(seed=104, n_blades=28, h=(0.50, 0.82), w=0.010, dry=0.38, seedheads=7, tillers=(4, 5), spread=0.22, lean=(0.02, 0.15), droop=(0.12, 0.45), basal=14),
    "s01_sedge_a": dict(seed=105, n_blades=88, h=(0.45, 0.70), w=0.008, dry=0.05, tillers=(1, 1), spread=0.05, lean=(0.12, 0.45), droop=(0.9, 1.7), segs=5, basal=0, col=SEDGE_COL),
    "s01_shadegrass_a": dict(seed=113, n_blades=44, h=(0.12, 0.24), w=0.019, dry=0.06, tillers=(4, 6), spread=0.26, lean=(0.45, 0.95), droop=(0.4, 0.9), segs=2, basal=0, col=SHADE_COL),
}
FERN = {
    "s01_fern_a": dict(seed=121, n_fronds=9, L=(0.55, 0.85)),
    "s01_fern_b": dict(seed=122, n_fronds=7, L=(0.38, 0.62), pairs=14, old=2),
    # R5：直立的劍羊齒冠（中心直立、外圈拱垂，0.7 m 高）與林床小羊齒
    "s01_fern_c": dict(seed=123, n_fronds=10, L=(0.66, 1.05), pairs=15, old=2, elev_deg=(50, 82), bend_add=(70, 100), pinna_k=0.25, pw=0.34, fcol=((0.10, 0.17, 0.07), (0.27, 0.40, 0.15))),
    "s01_fern_d": dict(seed=124, n_fronds=6, L=(0.20, 0.36), pairs=8, old=0, elev_deg=(40, 76), pinna_k=0.34, fcol=((0.14, 0.22, 0.08), (0.42, 0.52, 0.22))),
}


def grass_lod1(k):
    k = dict(k)
    k["n_blades"] = max(8, k["n_blades"] // 3)
    k["w"] = k["w"] * 1.7
    k["basal"] = k.get("basal", 0) // 3
    k["seedheads"] = (k.get("seedheads", 0) + 1) // 2
    k["segs"] = max(2, k.get("segs", 3) - 1)
    return k


def fern_lod1(k):
    k = dict(k)
    k["pairs"] = max(5, k.get("pairs", 16) // 2)
    k["rach_seg"] = 6
    k["pw"] = k.get("pw", 0.28) * 1.6
    return k


KIT = [
    # name, category, builder
    *[(n, "veg_grass", (lambda kw: (lambda nm: grass_clump(nm, **kw)))(kw)) for n, kw in GRASS.items()],
    *[(n, "veg_fern", (lambda kw: (lambda nm: fern(nm, **kw)))(kw)) for n, kw in FERN.items()],
    ("s01_shrub_a", "veg_shrub", lambda n: shrub(n, 131, 0.95, 0.65, 7, 380)),
    ("s01_sasa_a", "veg_shrub", lambda n: sasa(n, 141, 16, (0.42, 0.75), 0.42)),
    ("s01_sasa_b", "veg_shrub", lambda n: kumazasa(n, 142, 8)),
    ("s01_shrub_b", "veg_shrub", lambda n: shrub(n, 132, 0.62, 0.85, 9, 300)),
    ("s01_forb_a", "veg_forb", lambda n: forb(n, 181, 9, (0.32, 0.62), rosette=4, leaves=(7, 10), spread=0.12)),
    ("s01_forb_b", "veg_forb", lambda n: forb(n, 182, 3, (0.20, 0.38), rosette=9, Lr=(0.10, 0.17), col_a=(0.18, 0.28, 0.09), col_b=(0.27, 0.36, 0.13), leaves=(3, 5), spread=0.04)),
    ("s01_fuki_a", "veg_herb", lambda n: fuki(n, 191, 7)),
    ("s01_fuki_b", "veg_herb", lambda n: fuki(n, 192, 11, H=(0.16, 0.38), R=(0.08, 0.14), spread=0.30)),
    ("s01_herb_broad_a", "veg_herb", lambda n: broad_herb(n, 193, 11)),
    ("s01_sapling_a", "veg_sapling", lambda n: sapling(n, 195, 1.65, "maple", 8, 150, autumn=0.06)),
    ("s01_sapling_b", "veg_sapling", lambda n: sapling(n, 196, 1.15, "broad", 7, 200, autumn=0.0)),
    ("s01_litter_a", "litter", lambda n: litter(n, 151, (2.6, 2.0), 240, 4)),
    ("s01_litter_b", "litter", lambda n: litter(n, 152, (1.8, 1.5), 150, 2)),
    ("s01_moss_a", "moss", lambda n: moss(n, 161, (1.3, 1.0))),
    ("s01_twigs_a", "litter", lambda n: twigs(n, 171, 9, 1.4)),
    ("s01_rock_cliff_a", "rock", lambda n: rock_cliff(n, 201, 5.2, 3.9, 3.0, 3, 1.1)),
    ("s01_rock_cliff_b", "rock", lambda n: rock_cliff(n, 202, 4.0, 2.9, 2.6, 2, 0.9)),
    ("s01_rock_outcrop_c", "rock", lambda n: rock_simple(n, 203, (6.0, 4.0, 2.9), 1.1, n_cuts=10, cracks=1, subdiv=5, lump=0.05, tilt=(0, 9, 15), crack_w=0.08, crack_d=0.05)),
    ("s01_rock_rib_d", "rock", lambda n: rock_simple(n, 204, (2.3, 2.0, 6.6), 1.3, n_cuts=10, cracks=1, subdiv=5, lump=0.05, tilt=(6, -4, 0), crack_w=0.08, crack_d=0.05)),
    ("s01_mossstone_a", "rock", lambda n: rock_simple(n, 211, (1.3, 1.1, 0.85), 0.25, n_cuts=8, cracks=0, subdiv=4, lump=0.08, micro=0.014)),
    ("s01_mossstone_b", "rock", lambda n: rock_simple(n, 212, (1.0, 0.8, 0.5), 0.16, n_cuts=8, cracks=0, subdiv=3, lump=0.08, micro=0.012, tilt=(0, 14, 0))),
    ("s01_debris_a", "rock", lambda n: debris(n, 221, 7, 1.6)),
    ("s01_log_a", "wood", lambda n: log(n, 301, 4.2, 0.27, 0.20, stub=False)),
    ("s01_log_b", "wood", lambda n: log(n, 302, 3.0, 0.17, 0.13, stub=True)),
    ("s01_log_c", "wood", lambda n: log(n, 303, 3.6, 0.31, 0.26, hollow=True, squash=0.82, split_end=False)),
    ("s01_stump_a", "wood", lambda n: stump(n, 331, 0.72, 0.27, 5)),
    ("s01_roots_a", "wood", lambda n: roots(n, 311, 6, (1.3, 2.4), 0.17)),
    ("s01_roots_b", "wood", lambda n: roots(n, 312, 8, (0.9, 1.9), 0.14)),
    ("s01_branch_a", "wood", lambda n: branch(n, 321, 2.4, 0.065)),
    ("s01_branch_pile_a", "wood", lambda n: branch_pile(n, 322, 4)),
    # LOD1（遠景減面版：Godot 端 25–30 m 以外換用；名稱＝原名＋_lod1）
    *[(n + "_lod1", "lod", (lambda kw: (lambda nm: grass_clump(nm, **grass_lod1(kw))))(kw)) for n, kw in GRASS.items()],
    *[(n + "_lod1", "lod", (lambda kw: (lambda nm: fern(nm, **fern_lod1(kw))))(kw)) for n, kw in FERN.items()],
    ("s01_fuki_a_lod1", "lod", lambda n: fuki(n, 191, 7, lod=1)),
    ("s01_fuki_b_lod1", "lod", lambda n: fuki(n, 192, 11, H=(0.16, 0.38), R=(0.08, 0.14), spread=0.30, lod=1)),
    ("s01_herb_broad_a_lod1", "lod", lambda n: broad_herb(n, 193, 11, lod=1)),
    ("s01_forb_a_lod1", "lod", lambda n: forb(n, 181, 5, (0.32, 0.62), rosette=2, leaves=(4, 6), spread=0.12)),
    ("s01_sasa_a_lod1", "lod", lambda n: sasa(n, 141, 8, (0.42, 0.75), 0.42)),
    ("s01_sasa_b_lod1", "lod", lambda n: kumazasa(n, 142, 8, lod=1)),
]


def build_all(export=True, only=None):
    clear_coll()
    built = []
    for name, cat, fn in KIT:
        if only and name not in only:
            continue
        ob = fn(name)
        built.append((ob, cat))
    man = {}
    if export:
        os.makedirs(GLB_DIR, exist_ok=True)
        os.makedirs(SRC_DIR, exist_ok=True)
    for ob, cat in built:
        me = ob.data
        ntri = sum(len(p.vertices) - 2 for p in me.polygons)
        xs = [v.co.x for v in me.vertices]
        ys = [v.co.y for v in me.vertices]
        zs = [v.co.z for v in me.vertices]
        man[ob.name] = {"category": cat, "tris": ntri, "verts": len(me.vertices),
                        "size_m": [round(max(xs) - min(xs), 3), round(max(ys) - min(ys), 3), round(max(zs) - min(zs), 3)],
                        "z_min": round(min(zs), 3), "z_max": round(max(zs), 3)}
        if export:
            for o in bpy.data.objects:
                if o is not None and o.name in bpy.context.view_layer.objects:
                    o.select_set(False)
            ob.select_set(True)
            bpy.context.view_layer.objects.active = ob
            bpy.ops.export_scene.gltf(filepath=GLB_DIR + "/" + ob.name + ".glb", export_format='GLB', use_selection=True, export_apply=True,
                                      export_yup=True, export_vertex_color='ACTIVE', export_all_vertex_colors=False, export_normals=True,
                                      export_texcoords=True, export_materials='PLACEHOLDER', export_extras=False)
    if export:
        with open(SRC_DIR + "/kit_manifest.json", "w", encoding="utf-8") as f:
            json.dump({"generator": "assets/beast_path/s01_kit/src/build_s01_kit.py", "blender": bpy.app.version_string, "assets": man}, f, ensure_ascii=False, indent=1)
        bpy.ops.wm.save_as_mainfile(filepath=SRC_DIR + "/s01_kit.blend", copy=True)
    return man


def preview(path, names=None, cols=6, cam_back=34, cam_h=22, lens=30):
    """把資產排成一格一格，用 Workbench（頂點色）渲染一張總覽圖；左邊放一根 1.7 m 的參考柱（不匯出）。"""
    c = coll()
    obs = [o for o in c.objects if o.type == 'MESH' and not o.name.startswith("S01K_ref") and (names is None or o.name in names)]
    for o in list(c.objects):
        if o.type == 'MESH':
            o.hide_render = o not in obs and not o.name.startswith("S01K_ref")
    x = 0.0
    rowy = 0.0
    rowh = 0.0
    for i, ob in enumerate(obs):
        dims = ob.dimensions
        if i % cols == 0 and i > 0:
            rowy -= rowh + 1.0
            rowh = 0.0
            x = 0.0
        ob.location = (x + dims.x * 0.5, rowy, 0)
        x += dims.x + 0.8
        rowh = max(rowh, dims.y)
    ref = bpy.data.objects.get("S01K_ref")
    if ref is None:
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.transform(bm, matrix=Matrix.Translation((0, 0, 0.85)) @ Matrix.Diagonal((0.06, 0.06, 1.7, 1)), verts=bm.verts)
        me = bpy.data.meshes.new("S01K_ref")
        bm.to_mesh(me)
        bm.free()
        ref = bpy.data.objects.new("S01K_ref", me)
        c.objects.link(ref)
    ref.location = (-0.6, 0, 0)
    sc = bpy.context.scene
    sc.render.engine = 'BLENDER_WORKBENCH'
    sc.display.shading.light = 'STUDIO'
    sc.display.shading.color_type = 'VERTEX'
    sc.render.resolution_x = 2400
    sc.render.resolution_y = 1400
    cam = bpy.data.objects.get("S01K_cam")
    if cam is None:
        cam = bpy.data.objects.new("S01K_cam", bpy.data.cameras.new("S01K_cam"))
        c.objects.link(cam)
    xs = [o.location.x for o in obs]
    ys = [o.location.y for o in obs]
    cx, cy = (min(xs) + max(xs)) * 0.5, (min(ys) + max(ys)) * 0.5
    cam.location = (cx, cy - cam_back, cam_h)
    cam.rotation_euler = (math.radians(90 - math.degrees(math.atan2(cam_h, cam_back))), 0, 0)
    cam.data.lens = lens
    sc.camera = cam
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for o in list(bpy.data.objects):            # 背景模式：清掉預設方塊等（不在 S01_KIT 的東西不匯出，但清掉讓總覽乾淨）
        if o.type == 'MESH' and (o.users_collection and o.users_collection[0].name != COLL):
            bpy.data.objects.remove(o, do_unlink=True)
    only = None
    for a in argv:
        if a.startswith("--only="):
            only = a[7:].split(",")
    man = build_all(export=("--no-export" not in argv), only=only)
    for k, v in man.items():
        print("[kit] %-20s %-10s tris=%5d size=%s z=[%.2f, %.2f]" % (k, v["category"], v["tris"], v["size_m"], v["z_min"], v["z_max"]))
    for a in argv:
        if a.startswith("--preview="):
            base = a[10:]
            veg = [k for k, cat, _ in KIT if cat.startswith("veg") or cat in ("litter", "moss")]
            hard = [k for k, cat, _ in KIT if cat in ("rock", "wood")]
            preview(base + "_veg.png", veg, cols=5, cam_back=7.5, cam_h=3.2, lens=35)
            preview(base + "_hard.png", hard, cols=4, cam_back=24, cam_h=9, lens=40)
            print("[kit] preview ->", base)

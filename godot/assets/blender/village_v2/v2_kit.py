"""人間之里 V2 資產建模 kit（P5 R1 起；鈴奈庵、南大門鳥居、之後的町家 kit 共用）。

在 headless Blender 裡執行（numpy 內建）：
  blender -b --factory-startup --python godot/assets/blender/village_v2/build_suzunaan.py

慣例（全部資產共用，不要在各資產腳本裡改）：
  - 座標一律寫 **Godot 座標**（x 右、y 上、+z 朝正面／道路），單位公尺；建立 Blender 物件時才換成
    Blender (x, −z, y)，glTF 匯出（+Y up）後在 Godot 還原成原值。
  - 原點＝footprint 中心、y 0＝設計地面（資產自己的台基／基礎往下埋，見各資產 embed）。
  - UV 一律 glTF 慣例（左上原點）。共享材質（_matlib/matlib.json）用「公尺 ÷ tile_m」；
    木紋沿 V → 材料長軸給 grain 向量。Hero atlas 用 atlas.json 的像素區域。
  - 頂點色＝反照率乘數（材質 vertex_color_use_as_albedo）。1.0＝貼圖原色。
  - 面的繞序：從外面看逆時針（右手系）。Blender／glTF／Godot 都是這個方向，不要各自翻。
  - 平面著色的面各自一組頂點；smooth=True 的圓柱／圓弧共用頂點。
"""
import json
import math
import os

V3 = tuple


def add(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def mul(a, s):
    return (a[0] * s, a[1] * s, a[2] * s)


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def norm(a):
    l = math.sqrt(dot(a, a)) or 1.0
    return (a[0] / l, a[1] / l, a[2] / l)


def lerp(a, b, t):
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t)


X, Y, Z = (1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0)


class Mesh:
    """單一 LOD 的網格：頂點＋面（每面：頂點索引、材質、每角 UV、每角顏色、smooth）。"""

    def __init__(self, name, mats, tile):
        self.name = name
        self.mats = list(mats)          # 材質名（slot 順序）
        self.tile = tile                # {材質名: tile_m}，atlas 材質不在內
        self.v = []
        self.f = []                     # (idx tuple, mat_i, uv tuple, col tuple, smooth)

    # ── 低階
    def verts(self, ps):
        b = len(self.v)
        self.v.extend(ps)
        return list(range(b, b + len(ps)))

    def face(self, idx, mat, uvs, col=1.0, smooth=False):
        """col：純量（灰階乘數）、(r, g, b)，或每角一組 [(r, g, b), …]。"""
        if isinstance(col, (int, float)):
            cols = [(float(col),) * 3] * len(idx)
        elif isinstance(col[0], (int, float)):
            cols = [tuple(col)] * len(idx)
        else:
            cols = [tuple(c) for c in col]
            assert len(cols) == len(idx), '每角顏色數量不符'
        self.f.append((tuple(idx), self.mats.index(mat), tuple(uvs), tuple(cols), smooth))

    def tris(self):
        return sum(len(f[0]) - 2 for f in self.f)

    # ── UV
    def tuv(self, mat, p, n, grain=Y, off=(0.0, 0.0)):
        """共享材質：公尺 ÷ tile_m 的平面投影。v 沿 grain（木紋／瓦列／板長方向）。"""
        t = self.tile[mat]
        g = sub(grain, mul(n, dot(grain, n)))
        if dot(g, g) < 1e-6:            # 木口：grain 垂直於面 → 任取面內軸
            g = sub(X, mul(n, dot(X, n))) if abs(n[0]) < 0.9 else sub(Z, mul(n, dot(Z, n)))
        g = norm(g)
        u_ax = cross(g, n)
        return (dot(p, u_ax) / t + off[0], -dot(p, g) / t + off[1])

    # ── 平面
    def poly(self, ps, mat, col=1.0, grain=Y, uvs=None, off=(0.0, 0.0)):
        n = norm(cross(sub(ps[1], ps[0]), sub(ps[2], ps[0])))
        if n == (0.0, 0.0, 0.0) or dot(n, n) < 0.5:
            n = norm(cross(sub(ps[2], ps[1]), sub(ps[3] if len(ps) > 3 else ps[0], ps[1])))
        if uvs is None:
            uvs = [self.tuv(mat, p, n, grain, off) for p in ps]
        self.face(self.verts(ps), mat, uvs, col)

    def quad(self, a, b, c, d, mat, col=1.0, grain=Y, uvs=None, off=(0.0, 0.0)):
        self.poly([a, b, c, d], mat, col, grain, uvs, off)

    def rect_uv(self, a, b, c, d, mat, region, col=1.0, flip_u=False):
        """atlas 區域貼滿 a(左下) b(右下) c(右上) d(左上)。region＝[u0, v0, u1, v1]（左上原點）。"""
        u0, v0, u1, v1 = region
        if flip_u:
            u0, u1 = u1, u0
        self.quad(a, b, c, d, mat, col, uvs=[(u0, v1), (u1, v1), (u1, v0), (u0, v0)])

    # ── 方塊（可旋轉）：center、半邊長 (hx, hy, hz)、局部軸 ax/ay/az（單位正交）
    def obox(self, c, h, mat, col=1.0, ax=X, ay=Y, az=Z, grain=None, skip=(), cols=None, off=(0.0, 0.0)):
        hx, hy, hz = h
        if grain is None:
            L = max(h)
            grain = ax if hx == L else (ay if hy == L else az)

        def P(i, j, k):
            return add(c, add(mul(ax, i * hx), add(mul(ay, j * hy), mul(az, k * hz))))
        faces = {
            '+x': [P(1, -1, 1), P(1, -1, -1), P(1, 1, -1), P(1, 1, 1)],
            '-x': [P(-1, -1, -1), P(-1, -1, 1), P(-1, 1, 1), P(-1, 1, -1)],
            '+y': [P(-1, 1, 1), P(1, 1, 1), P(1, 1, -1), P(-1, 1, -1)],
            '-y': [P(-1, -1, -1), P(1, -1, -1), P(1, -1, 1), P(-1, -1, 1)],
            '+z': [P(-1, -1, 1), P(1, -1, 1), P(1, 1, 1), P(-1, 1, 1)],
            '-z': [P(1, -1, -1), P(-1, -1, -1), P(-1, 1, -1), P(1, 1, -1)],
        }
        for k, ps in faces.items():
            if k in skip:
                continue
            self.poly(ps, mat, (cols or {}).get(k, col), grain, off=off)

    def box(self, lo, hi, mat, col=1.0, grain=None, skip=(), cols=None, off=(0.0, 0.0)):
        c = mul(add(lo, hi), 0.5)
        h = mul(sub(hi, lo), 0.5)
        self.obox(c, h, mat, col, grain=grain, skip=skip, cols=cols, off=off)

    def beam(self, a, b, w, h, mat, col=1.0, up=Y, skip_ends=False, off=(0.0, 0.0)):
        """a→b 的角材：寬 w（水平）、高 h（沿 up 在垂直於長軸的分量）。"""
        d = sub(b, a)
        L = math.sqrt(dot(d, d))
        ax = norm(d)
        uu = sub(up, mul(ax, dot(up, ax)))
        if dot(uu, uu) < 1e-6:
            uu = sub(Z, mul(ax, dot(Z, ax)))
        ay = norm(uu)
        az = cross(ax, ay)
        self.obox(mul(add(a, b), 0.5), (L / 2, h / 2, w / 2), mat, col, ax, ay, az, grain=ax,
                  skip=('+x', '-x') if skip_ends else (), off=off)

    # ── 圓柱／截錐：p0→p1，半徑 r0→r1，seg 段；smooth 側面共用頂點
    def cyl(self, p0, p1, r0, r1, seg, mat, col=1.0, caps=(True, True), phase=0.0, uv_atlas=None, arc=None):
        d = norm(sub(p1, p0))
        ref = X if abs(d[0]) < 0.9 else Z
        e1 = norm(cross(d, ref))
        e2 = cross(d, e1)
        a0, a1 = arc if arc else (0.0, 2 * math.pi)
        full = arc is None
        n = seg if full else seg + 1
        ang = [a0 + (a1 - a0) * i / seg + phase for i in range(n)]
        ring0 = [add(p0, add(mul(e1, math.cos(t) * r0), mul(e2, math.sin(t) * r0))) for t in ang]
        ring1 = [add(p1, add(mul(e1, math.cos(t) * r1), mul(e2, math.sin(t) * r1))) for t in ang]
        L = math.sqrt(dot(sub(p1, p0), sub(p1, p0)))
        t = self.tile.get(mat)
        i0 = self.verts(ring0)
        i1 = self.verts(ring1)
        # 側面：共用頂點，UV 環繞（u＝弧長／tile），接縫處 u 不連續可接受（木紋貼圖本身可平鋪）
        for i in range(seg):
            j = (i + 1) % n if full else i + 1
            if uv_atlas:
                u0, v0, u1, v1 = uv_atlas
                uvs = [(u0 + (u1 - u0) * i / seg, v1), (u0 + (u1 - u0) * (i + 1) / seg, v1),
                       (u0 + (u1 - u0) * (i + 1) / seg, v0), (u0 + (u1 - u0) * i / seg, v0)]
            else:
                ua = (a1 - a0) * i / seg * (r0 + r1) / 2 / t
                ub = (a1 - a0) * (i + 1) / seg * (r0 + r1) / 2 / t
                uvs = [(ua, 0.0), (ub, 0.0), (ub, -L / t), (ua, -L / t)]
            self.face([i0[i], i0[j], i1[j], i1[i]], mat, uvs, col, smooth=True)
        if uv_atlas:                    # atlas 材質沒有 tile_m：蓋面取色票中心
            cu = ((uv_atlas[0] + uv_atlas[2]) * 0.5, (uv_atlas[1] + uv_atlas[3]) * 0.5)
        if caps[0] and full:
            ps = list(reversed(ring0))
            self.poly(ps, mat, col, grain=e1, uvs=[cu] * len(ps) if uv_atlas else None)
        if caps[1] and full:
            self.poly(list(ring1), mat, col, grain=e1, uvs=[cu] * len(ring1) if uv_atlas else None)

    # ── 輸出成 Blender 物件
    def grid(self, P, UV, ni, nj, mat, col, want_n, smooth=True):
        """(ni+1)×(nj+1) 共用頂點網格。P(i, j)／UV(i, j)；朝向依 want_n 自動決定（看第一格法線）。"""
        idx = self.verts([P(i, j) for j in range(nj + 1) for i in range(ni + 1)])
        uv = [UV(i, j) for j in range(nj + 1) for i in range(ni + 1)]

        def k(i, j):
            return j * (ni + 1) + i
        a, b, c = self.v[idx[k(0, 0)]], self.v[idx[k(1, 0)]], self.v[idx[k(1, 1)]]
        flip = dot(cross(sub(b, a), sub(c, b)), want_n) < 0
        for j in range(nj):
            for i in range(ni):
                q = [k(i, j), k(i + 1, j), k(i + 1, j + 1), k(i, j + 1)]
                if flip:
                    q = q[::-1]
                self.face([idx[t] for t in q], mat, [uv[t] for t in q], col, smooth)

    def abox(self, c, h, mat, rects, col=1.0, ax=X, ay=Y, az=Z, skip=()):
        """atlas 方塊：rects＝{面: [u0, v0, u1, v1]}，'*' 為預設；面鍵同 obox（+x −x +y −y +z −z）。
        每面照「從外面看」左下→右下→右上→左上貼（+y 面以 +z 側為下、−y 面以 −z 側為下）。"""
        hx, hy, hz = h

        def P(i, j, k):
            return add(c, add(mul(ax, i * hx), add(mul(ay, j * hy), mul(az, k * hz))))
        faces = {
            '+x': [P(1, -1, 1), P(1, -1, -1), P(1, 1, -1), P(1, 1, 1)],
            '-x': [P(-1, -1, -1), P(-1, -1, 1), P(-1, 1, 1), P(-1, 1, -1)],
            '+y': [P(-1, 1, 1), P(1, 1, 1), P(1, 1, -1), P(-1, 1, -1)],
            '-y': [P(-1, -1, -1), P(1, -1, -1), P(1, -1, 1), P(-1, -1, 1)],
            '+z': [P(-1, -1, 1), P(1, -1, 1), P(1, 1, 1), P(-1, 1, 1)],
            '-z': [P(1, -1, -1), P(-1, -1, -1), P(-1, 1, -1), P(1, 1, -1)],
        }
        for k2, ps in faces.items():
            if k2 in skip:
                continue
            r = rects.get(k2, rects.get('*'))
            self.rect_uv(ps[0], ps[1], ps[2], ps[3], mat, r, col)

    def to_blender(self, bpy, collection=None, bmats=None):
        me = bpy.data.meshes.new(self.name)
        bv = [(p[0], -p[2], p[1]) for p in self.v]
        me.from_pydata(bv, [], [list(f[0]) for f in self.f])
        me.update()
        uvl = me.uv_layers.new(name='UVMap')
        col = me.color_attributes.new(name='Col', type='FLOAT_COLOR', domain='CORNER')
        li = 0
        for pi, f in enumerate(self.f):
            poly = me.polygons[pi]
            poly.material_index = f[1]
            poly.use_smooth = bool(f[4])
            for k in range(len(f[0])):
                u, v = f[2][k]
                uvl.data[poly.loop_start + k].uv = (u, 1.0 - v)
                c = f[3][k]
                col.data[poly.loop_start + k].color = (c[0], c[1], c[2], 1.0)
            li += len(f[0])
        for m in self.mats:
            me.materials.append(bmats[m] if bmats else None)
        # 五邊以上的面（看板、圓蓋）先三角化：Blender 只對三／四邊面算切線，有一個 ngon 整個網格就不輸出
        # TANGENT（glTF exporter 警告 Could not calculate tangents），法線貼圖在 Godot 會失效。
        # bmesh.triangulate 保留 UV、頂點色、材質索引與平滑旗標。
        import bmesh
        bmm = bmesh.new()
        bmm.from_mesh(me)
        ng = [f for f in bmm.faces if len(f.verts) > 4]
        if ng:
            bmesh.ops.triangulate(bmm, faces=ng)
        bmm.to_mesh(me)
        bmm.free()
        me.update()
        ob = bpy.data.objects.new(self.name, me)
        (collection or bpy.context.scene.collection).objects.link(ob)
        return ob


def blender_mats(bpy, names):
    """匯出用的佔位材質：名字＝_matlib／atlas 的 .tres 名；Godot 端 prefab 產生器依名字換成正式材質。"""
    out = {}
    for n in names:
        m = bpy.data.materials.get(n) or bpy.data.materials.new(n)
        m.use_nodes = True
        bsdf = m.node_tree.nodes.get('Principled BSDF')
        if bsdf is not None:
            # 讓頂點色在 Blender 預覽也可見；glTF exporter 會因此輸出 COLOR_0
            vc = m.node_tree.nodes.new('ShaderNodeVertexColor')
            vc.layer_name = 'Col'
            m.node_tree.links.new(vc.outputs['Color'], bsdf.inputs['Base Color'])
        out[n] = m
    return out


def tile_roof(m, origin, dsl, n, x0, x1, S, kw, lod, mat='V2_Kawara', col=1.0, u_sign=1.0,
              amp=0.022, step=0.028, seg_per_col=4, ends=True):
    """桟瓦屋面（共享 V2_Kawara 貼圖對齊的幾何）。
    origin＝上緣（棟或壁際）x=0 的點；dsl＝下坡單位向量；n＝屋面外法線；x0..x1 沿 X；S＝坡長。
    貼圖實測（matlib）：每 tile 16 欄 × 10 段、瓦唇朝 +v、欄波峰在 crest_u。
    u＝u_sign·x／tile_u_m（背坡給 −1，從外面看 u 仍向右）；v＝s／tile_m＋v0。
    LOD0：欄向正弦起伏（波峰對齊 crest_u）＋每段瓦唇鋸齒＋簷口瓦當；LOD1+：平面（同 UV）。"""
    tu, tv = kw['tile_u_m'], kw['tile_m']
    cols, cour = kw['columns'], kw['courses']
    crest = kw['crest_u']
    phi = 0.57                              # 瓦唇在每段的相位（法線 G 尖峰 bin 11/20）
    v0 = ((0.98 + phi - S / tv * cour) % 1.0) / cour     # 簷口剛好落在最後一段的瓦唇前

    def B(x, s):
        return add(origin, add(mul(X, x), mul(dsl, s)))

    def U(x):
        return u_sign * x / tu

    def V(s):
        return s / tv + v0

    def cor(x):
        return amp * math.cos(2 * math.pi * (U(x) - crest) * cols)

    if lod >= 2:
        dmid = step * 0.5
        m.grid(lambda i, j: add(B(x0 + (x1 - x0) * i, S * j), mul(n, dmid)),
               lambda i, j: (U(x0 + (x1 - x0) * i), V(S * j)), 1, 1, mat, col, n, smooth=False)
        return {'v0': v0}
    ncol = max(1, int(round(abs(x1 - x0) / (tu / cols))))
    if lod == 1:
        # 中距離：保留欄向起伏（簷口輪廓），不做每段瓦唇；每欄 2 段
        ni = ncol * 2
        xs = [x0 + (x1 - x0) * i / ni for i in range(ni + 1)]
        m.grid(lambda i, j: add(B(xs[i], S * j), mul(n, cor(xs[i]) + step * 0.5)),
               lambda i, j: (U(xs[i]), V(S * j)), ni, 1, mat, col, n)
        return {'v0': v0, 'cols': ncol}
    ni = ncol * seg_per_col
    xs = [x0 + (x1 - x0) * i / ni for i in range(ni + 1)]

    def q(s):
        return V(s) * cour - phi
    k0 = math.ceil(q(0.0) + 1e-6)
    bounds = []
    k = k0
    while True:
        s = ((k + phi) / cour - v0) * tv
        if s >= S - 1e-4:
            break
        if s > 1e-4:
            bounds.append(s)
        k += 1
    edges = [0.0] + bounds + [S]
    for a, b in zip(edges, edges[1:]):
        da = 0.0 if a in bounds else step * (q(a) - math.floor(q(a)))
        db = step if b not in bounds else step
        if b == S:
            db = step * min(1.0, q(S) - math.floor(q(S)) + 0.02)
        m.grid(lambda i, j: add(B(xs[i], a if j == 0 else b), mul(n, cor(xs[i]) + (da if j == 0 else db))),
               lambda i, j: (U(xs[i]), V(a if j == 0 else b)), ni, 1, mat, col, n)
    for s in bounds:
        m.grid(lambda i, j: add(B(xs[i], s), mul(n, cor(xs[i]) + (step if j == 0 else 0.0))),
               lambda i, j: (U(xs[i]), V(s) - (0.004 if j == 0 else 0.0)), ni, 1, mat, col * 0.85, dsl)
    info = {'v0': v0, 'courses': len(edges) - 1, 'cols': ncol}
    if ends:
        # 簷口瓦當：每欄波峰一個，軸沿下坡
        kmin = math.ceil((min(U(x0), U(x1)) - crest) * cols)
        kmax = math.floor((max(U(x0), U(x1)) - crest) * cols)
        for kk in range(kmin, kmax + 1):
            u = crest + kk / cols
            x = u * tu / u_sign
            if min(x0, x1) + 0.12 > x or x > max(x0, x1) - 0.12:
                continue
            c = add(B(x, S), mul(n, amp + step * 0.55))
            m.cyl(add(c, mul(dsl, -0.03)), add(c, mul(dsl, 0.02)), 0.068, 0.068, 10, mat, col * 0.9,
                  caps=(False, True))
    return info


def export_glb(bpy, path, objs):
    for o in bpy.context.scene.objects:
        o.select_set(o in objs)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_yup=True,
                              export_apply=False, export_normals=True, export_tangents=True,
                              export_materials='EXPORT', export_vertex_color='ACTIVE',
                              export_all_vertex_colors=False, export_image_format='NONE', export_extras=True)


def clear_scene(bpy):
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for m in list(bpy.data.meshes):
        bpy.data.meshes.remove(m)
    for m in list(bpy.data.materials):
        bpy.data.materials.remove(m)


def load_json(p):
    with open(p, encoding='utf-8') as f:
        return json.load(f)


def write_json(p, d):
    with open(p, 'w', encoding='utf-8', newline='\n') as f:
        json.dump(d, f, ensure_ascii=False, indent=1)
        f.write('\n')


def repo_paths(file):
    here = os.path.dirname(os.path.abspath(file))
    godot = os.path.normpath(os.path.join(here, '..', '..', '..'))
    return godot.replace('\\', '/')

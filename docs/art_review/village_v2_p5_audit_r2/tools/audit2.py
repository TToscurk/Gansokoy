"""P5 Asset Audit r2（唯讀；原檔不寫回）。
blender -b --factory-startup --python audit2.py -- <outdir> <jobs.json> [name,name...]

每個資產：import → join → 依 job 定的「人尺度依據」縮放成公尺、底面置 0、XY 置中 → 量：
  幾何：三角面、位置合併後的 boundary / non-manifold 邊、退化面、連通島、浮空碎塊（離主體 > 5 cm 且不著地）
  接地：底部 1 m 帶的格點最低點 → 周邊著地率、周邊最大離地、底面傾斜與起伏、底部土台比
  Pivot：原檔原點相對底面中心
  UV：面積加權 texel 密度（px/m）、UV 塌陷（抹色）面積比、UV 出界比
  材質：Principled 的 metallic / roughness / emission / alpha、貼圖統計（黑、白、洋紅、金屬比例）
  渲染（EEVEE、Standard）：兩個透視、正面全身（1.70 m 人形＋0.5 m 標尺）、正面低段、側面低段、
        底面仰視、背面檢查（紅＝背面）、1.5 m 水平剖面（看內部肉塊）
"""
import bpy, sys, json, math, os, time
import numpy as np
from mathutils import Vector, Euler
from mathutils.bvhtree import BVHTree

argv = sys.argv[sys.argv.index("--") + 1:]
OUT = argv[0]
JOBS = json.load(open(argv[1], encoding="utf-8"))
ONLY = set(argv[2].split(",")) if len(argv) > 2 and argv[2] else None
os.makedirs(OUT, exist_ok=True)


def log(*a):
    print("[A2]", *a, flush=True)


# ---------------------------------------------------------------- import / normalise
def load(job):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=job["path"])
    sc = bpy.context.scene
    meshes = [o for o in sc.objects if o.type == "MESH"]
    n_obj = len(meshes)
    for o in list(sc.objects):
        if o.type not in ("MESH",) and o.type != "EMPTY":
            bpy.data.objects.remove(o, do_unlink=True)
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    for o in [o for o in sc.objects if o.type == "EMPTY"]:
        bpy.data.objects.remove(o, do_unlink=True)
    if len(meshes) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    n = len(ob.data.vertices)
    co = np.empty(n * 3, np.float64)
    ob.data.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    lo, hi = co.min(0), co.max(0)
    size0 = hi - lo
    if job.get("auto") and size0.max() >= 3.0:
        s = 1.0
        job["basis"] = "原檔已是公尺（最大邊 %.1f）" % size0.max()
    elif job.get("scale"):
        s = float(job["scale"])
    elif job.get("fit_x"):
        s = float(job["fit_x"]) / size0[0]
    elif job.get("fit_max"):
        s = float(job["fit_max"]) / size0.max()
    else:
        s = 1.0
    cx, cy = (lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2
    ob.location = (-cx * s, -cy * s, -lo[2] * s)
    ob.scale = (s, s, s)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    pivot = {"orig_units_size": [round(float(x), 4) for x in size0],
             "origin_rel_bottom_center_m": [round(-cx * s, 3), round(-cy * s, 3), round(-lo[2] * s, 3)],
             "origin_height_frac": round(float(-lo[2] / size0[2]), 3) if size0[2] else 0}
    return ob, s, n_obj, pivot


def arrays(ob):
    me = ob.data
    me.calc_loop_triangles()
    nv = len(me.vertices)
    V = np.empty(nv * 3, np.float64); me.vertices.foreach_get("co", V); V = V.reshape(-1, 3)
    nt = len(me.loop_triangles)
    T = np.empty(nt * 3, np.int64); me.loop_triangles.foreach_get("vertices", T); T = T.reshape(-1, 3)
    L = np.empty(nt * 3, np.int64); me.loop_triangles.foreach_get("loops", L); L = L.reshape(-1, 3)
    M = np.empty(nt, np.int64); me.loop_triangles.foreach_get("material_index", M)
    if me.uv_layers.active:
        uv = np.empty(len(me.loops) * 2, np.float64); me.uv_layers.active.data.foreach_get("uv", uv)
        UV = uv.reshape(-1, 2)[L]
    else:
        UV = None
    return V, T, UV, M


# ---------------------------------------------------------------- geometry
def components(nv, E):
    lab = np.arange(nv, dtype=np.int64)
    u, v = E[:, 0], E[:, 1]
    for _ in range(300):
        lu, lv = lab[u], lab[v]
        if np.array_equal(lu, lv):
            break
        m = np.minimum(lu, lv)
        np.minimum.at(lab, lu, m)
        np.minimum.at(lab, lv, m)
        while True:
            nl = lab[lab]
            if np.array_equal(nl, lab):
                break
            lab = nl
    return lab


def geometry(V, T):
    H = float(V[:, 2].max())
    ext = float(np.ptp(V, axis=0).max())
    eps = max(ext * 1e-5, 1e-5)
    q = np.round(V / eps).astype(np.int64)
    _, mid = np.unique(q, axis=0, return_inverse=True)
    mid = mid.reshape(-1)
    nvm = int(mid.max()) + 1
    TM = mid[T]
    a, b, c = V[T[:, 0]], V[T[:, 1]], V[T[:, 2]]
    area = 0.5 * np.linalg.norm(np.cross(b - a, c - a), axis=1)
    degen = (area < 1e-8) | (TM[:, 0] == TM[:, 1]) | (TM[:, 1] == TM[:, 2]) | (TM[:, 0] == TM[:, 2])
    good = ~degen
    TG = TM[good]
    E = np.vstack([TG[:, [0, 1]], TG[:, [1, 2]], TG[:, [2, 0]]])
    E.sort(axis=1)
    ue, cnt = np.unique(E, axis=0, return_counts=True)
    lab = components(nvm, ue)
    roots, vl = np.unique(lab, return_inverse=True)
    nisl = len(roots)
    # 每個島：頂點數、bbox
    vcount = np.bincount(vl, minlength=nisl)
    Vm = np.zeros((nvm, 3)); Vm[mid] = V
    ilo = np.full((nisl, 3), 1e18); ihi = np.full((nisl, 3), -1e18)
    for k in range(3):
        np.minimum.at(ilo[:, k], vl, Vm[:, k]); np.maximum.at(ihi[:, k], vl, Vm[:, k])
    # 三角面所屬島
    tisl = vl[TG[:, 0]]
    tcount = np.bincount(tisl, minlength=nisl)
    order = np.argsort(-vcount)
    big = vcount[order[0]]
    main_mask = vcount >= max(big * 0.05, 50)
    # 主體 BVH
    tri_main = TG[main_mask[tisl]]
    bvh = BVHTree.FromPolygons(Vm.tolist(), tri_main.tolist(), all_triangles=True)
    floating = []
    rng = np.random.default_rng(1)
    small = [i for i in order if not main_mask[i]]
    # 依島整理頂點索引
    sort_v = np.argsort(vl, kind="stable")
    starts = np.searchsorted(vl[sort_v], np.arange(nisl))
    ends = np.append(starts[1:], len(vl))
    checked = 0
    for i in small:
        if ilo[i, 2] <= 0.03:
            continue  # 著地
        idx = sort_v[starts[i]:ends[i]]
        if len(idx) > 24:
            idx = rng.choice(idx, 24, replace=False)
        dmin = 1e9
        for vi in idx:
            hit = bvh.find_nearest(Vector(Vm[vi]), 0.5)
            if hit[0] is not None:
                dmin = min(dmin, hit[3])
                if dmin <= 0.05:
                    break
        checked += 1
        if dmin > 0.05:
            floating.append((int(tcount[i]), float(min(dmin, 0.5)), [round(float(x), 2) for x in (ilo[i] + ihi[i]) / 2],
                             [round(float(x), 2) for x in ihi[i] - ilo[i]]))
    floating.sort(key=lambda t: -t[0])
    ntri = len(T)
    return {
        "tris": int(ntri), "verts": int(len(V)), "verts_pos_merged": int(nvm),
        "degenerate_tris": int(degen.sum()),
        "edges": int(len(ue)), "boundary_edges": int((cnt == 1).sum()), "nonmanifold_edges": int((cnt > 2).sum()),
        "boundary_edge_frac": round(float((cnt == 1).mean()), 4), "nonmanifold_edge_frac": round(float((cnt > 2).mean()), 4),
        "islands": int(nisl), "main_islands": int(main_mask.sum()),
        "largest_island_tri_frac": round(float(tcount[order[0]] / max(len(TG), 1)), 3),
        "floating_islands": len(floating), "floating_tris": int(sum(f[0] for f in floating)),
        "floating_top": floating[:6], "small_islands_checked": checked,
    }, area


def grounding(V, T):
    H = float(V[:, 2].max())
    xy = V[:, :2]
    ext = float(np.ptp(xy, axis=0).max())
    cs = max(0.2, ext / 60.0)
    band = min(1.0, 0.15 * H)
    sel = V[:, 2] <= band
    P = V[sel]
    lo = xy.min(0)
    ij = np.floor((P[:, :2] - lo) / cs).astype(np.int64)
    nx, ny = int(ij[:, 0].max()) + 2, int(ij[:, 1].max()) + 2
    flat = ij[:, 0] * ny + ij[:, 1]
    minz = np.full(nx * ny, np.inf)
    np.minimum.at(minz, flat, P[:, 2])
    occ = np.isfinite(minz).reshape(nx, ny)
    mz = minz.reshape(nx, ny)
    pad = np.pad(occ, 1)
    inner = pad[:-2, 1:-1] & pad[2:, 1:-1] & pad[1:-1, :-2] & pad[1:-1, 2:]
    perim = occ & ~inner
    pz = mz[perim]
    allz = mz[occ]
    tol = 0.05
    res = {"cell_m": round(cs, 3), "band_m": round(band, 2),
           "lower_cells": int(occ.sum()), "contact_frac": round(float((allz <= tol).mean()), 3),
           "perim_cells": int(perim.sum()), "perim_contact_frac": round(float((pz <= tol).mean()), 3),
           "perim_gap_p90_m": round(float(np.percentile(pz, 90)), 3), "perim_gap_max_m": round(float(pz.max()), 3),
           "perim_p05_m": round(float(np.percentile(pz, 5)), 3)}
    # 底面傾斜／起伏：周邊中離地 < 0.3 m 的格
    ii, jj = np.nonzero(perim)
    zz = mz[perim]
    k = zz < 0.3
    if k.sum() >= 6:
        A = np.c_[ii[k] * cs, jj[k] * cs, np.ones(k.sum())]
        coef, *_ = np.linalg.lstsq(A, zz[k], rcond=None)
        r = zz[k] - A @ coef
        res["base_tilt_deg"] = round(math.degrees(math.atan(math.hypot(coef[0], coef[1]))), 2)
        res["base_unevenness_m"] = round(float(np.ptp(r)), 3)
    # 土台／地盤比：最底 3% 高度帶 vs 30–60% 高度帶 的 XY 範圍
    def rng_xy(m):
        q = xy[m]
        return np.ptp(q, axis=0) if len(q) else np.zeros(2)
    b0 = rng_xy(V[:, 2] <= 0.03 * H)
    b1 = rng_xy((V[:, 2] >= 0.3 * H) & (V[:, 2] <= 0.6 * H))
    res["bottom_vs_mid_xy_ratio"] = [round(float(b0[0] / b1[0]), 2) if b1[0] else None,
                                     round(float(b0[1] / b1[1]), 2) if b1[1] else None]
    return res


def uvstats(V, T, UV, M, area, mats_tex_w):
    if UV is None:
        return {"uv": "NONE"}
    ua = 0.5 * np.abs((UV[:, 1, 0] - UV[:, 0, 0]) * (UV[:, 2, 1] - UV[:, 0, 1]) -
                      (UV[:, 2, 0] - UV[:, 0, 0]) * (UV[:, 1, 1] - UV[:, 0, 1]))
    ok = area > 1e-8
    tw = np.array([mats_tex_w.get(int(m), 1024) for m in range(int(M.max()) + 1)])[M]
    dens = np.sqrt(np.where(ok, ua / np.maximum(area, 1e-12), 0)) * tw  # px/m
    w = area[ok]; d = dens[ok]
    order = np.argsort(d); cw = np.cumsum(w[order]) / w.sum()
    p = lambda q: float(d[order][np.searchsorted(cw, q)])
    med = p(0.5)
    out = (UV < -0.01) | (UV > 1.01)
    return {"texel_px_per_m_p10": round(p(0.10), 1), "texel_px_per_m_p50": round(med, 1),
            "texel_px_per_m_p90": round(p(0.90), 1),
            "uv_collapsed_area_frac": round(float(w[d < 0.1 * med].sum() / w.sum()), 4),
            "uv_outside_01_tri_frac": round(float(out.any(axis=(1, 2)).mean()), 4)}


# ---------------------------------------------------------------- materials
def img_stats(img):
    try:
        c = img.copy(); c.scale(192, 192)
        px = np.empty(192 * 192 * 4, np.float32); c.pixels.foreach_get(px); bpy.data.images.remove(c)
    except Exception as e:
        return {"err": str(e)}
    px = px.reshape(-1, 4)[:, :3]
    lum = px @ np.array([0.2126, 0.7152, 0.0722])
    mx, mn = px.max(1), px.min(1)
    sat = np.where(mx > 1e-4, (mx - mn) / np.maximum(mx, 1e-4), 0)
    return {"size": list(img.size), "mean_rgb": [round(float(x), 3) for x in px.mean(0)],
            "lum_mean": round(float(lum.mean()), 3), "black_frac": round(float((lum < 0.03).mean()), 3),
            "white_frac": round(float((lum > 0.97).mean()), 3),
            "magenta_frac": round(float(((px[:, 0] > 0.7) & (px[:, 1] < 0.3) & (px[:, 2] > 0.7)).mean()), 4),
            "sat_mean": round(float(sat.mean()), 3),
            "g_mean": round(float(px[:, 1].mean()), 3), "b_mean": round(float(px[:, 2].mean()), 3),
            "b_gt05_frac": round(float((px[:, 2] > 0.5).mean()), 3)}


def upstream_images(sock, depth=0, seen=None):
    seen = seen if seen is not None else set()
    out = []
    if depth > 6:
        return out
    for l in sock.links:
        n = l.from_node
        if n.name in seen:
            continue
        seen.add(n.name)
        if n.type == "TEX_IMAGE" and n.image:
            out.append(n.image)
        for s in n.inputs:
            if s.is_linked:
                out += upstream_images(s, depth + 1, seen)
    return out


def materials(ob, M):
    used = np.bincount(M, minlength=len(ob.material_slots))
    res = []; texw = {}; tex_bytes = 0; seen_img = set()
    for i, slot in enumerate(ob.material_slots):
        m = slot.material
        d = {"slot": i, "name": m.name if m else None, "tri_frac": round(float(used[i] / max(len(M), 1)), 3) if i < len(used) else 0}
        if m and m.use_nodes:
            bs = next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
            if bs:
                for key in ("Base Color", "Metallic", "Roughness", "Normal", "Emission Color", "Emission Strength", "Alpha"):
                    s = bs.inputs.get(key)
                    if s is None:
                        continue
                    if s.is_linked:
                        imgs = upstream_images(s)
                        d[key] = {"linked": True, "images": [im.name for im in imgs]}
                        if key in ("Base Color", "Metallic", "Roughness") and imgs:
                            st = img_stats(imgs[0])
                            d[key]["stats"] = st
                            if key == "Base Color":
                                texw[i] = imgs[0].size[0]
                    else:
                        v = s.default_value
                        d[key] = [round(float(x), 3) for x in v] if hasattr(v, "__len__") else round(float(v), 3)
            d["blend"] = getattr(m, "surface_render_method", getattr(m, "blend_method", "?"))
        res.append(d)
    for im in bpy.data.images:
        if im.name in seen_img or not im.size[0]:
            continue
        seen_img.add(im.name)
        tex_bytes += im.size[0] * im.size[1] * 4 * 4 // 3
    return res, texw, tex_bytes


# ---------------------------------------------------------------- render
def mat_simple(name, rgb, emit=0.0, rough=0.8):
    m = bpy.data.materials.new(name); m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*rgb, 1)
    b.inputs["Roughness"].default_value = rough
    if emit:
        b.inputs["Emission Color"].default_value = (*rgb, 1)
        b.inputs["Emission Strength"].default_value = emit
    return m


def backface_mat():
    m = bpy.data.materials.new("BF"); m.use_nodes = True; nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    o = nt.nodes.new("ShaderNodeOutputMaterial"); g = nt.nodes.new("ShaderNodeNewGeometry")
    mx = nt.nodes.new("ShaderNodeMixShader"); df = nt.nodes.new("ShaderNodeBsdfDiffuse"); em = nt.nodes.new("ShaderNodeEmission")
    df.inputs["Color"].default_value = (0.7, 0.7, 0.7, 1); em.inputs["Color"].default_value = (1, 0, 0, 1)
    nt.links.new(g.outputs["Backfacing"], mx.inputs[0]); nt.links.new(df.outputs[0], mx.inputs[1])
    nt.links.new(em.outputs[0], mx.inputs[2]); nt.links.new(mx.outputs[0], o.inputs["Surface"])
    m.use_backface_culling = False
    return m


def add_box(name, size, loc, mat):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    o = bpy.context.active_object; o.name = name; o.scale = size
    o.data.materials.append(mat)
    return o


def setup_scene(H, bb):
    sc = bpy.context.scene
    for eng in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
        try:
            sc.render.engine = eng; break
        except Exception:
            pass
    try:
        sc.eevee.taa_render_samples = 16
    except Exception:
        pass
    sc.view_settings.view_transform = "Standard"
    w = bpy.data.worlds.new("W"); sc.world = w; w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.62, 0.66, 0.72, 1)
    w.node_tree.nodes["Background"].inputs[1].default_value = 0.7
    sd = bpy.data.lights.new("sun", "SUN"); sd.energy = 3.5
    so = bpy.data.objects.new("sun", sd); so.rotation_euler = Euler((math.radians(50), 0, math.radians(35)))
    sc.collection.objects.link(so)
    ground = add_box("GROUND", (600, 600, 0.02), (0, 0, -0.01), mat_simple("g", (0.30, 0.30, 0.28), rough=1))
    fig_m = mat_simple("fig", (1.0, 0.45, 0.08), emit=0.4)
    fx, fy = bb[0][0] - 1.0, bb[0][1] - 1.5
    bpy.ops.mesh.primitive_cylinder_add(radius=0.22, depth=1.45, location=(fx, fy, 0.725))
    b = bpy.context.active_object; b.data.materials.append(fig_m)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.12, location=(fx, fy, 1.58))
    h = bpy.context.active_object; h.data.materials.append(fig_m)
    rod_h = int(min(max(3, math.ceil(H)), 20) * 2)
    red, white = mat_simple("r", (0.85, 0.05, 0.05), 0.3), mat_simple("w", (0.95, 0.95, 0.95), 0.3)
    for k in range(rod_h):
        add_box(f"rod{k}", (0.09, 0.09, 0.5), (fx - 0.6, fy, 0.25 + 0.5 * k), red if k % 2 == 0 else white)
    cam_d = bpy.data.cameras.new("cam"); cam = bpy.data.objects.new("cam", cam_d); sc.collection.objects.link(cam)
    sc.camera = cam
    return sc, cam, ground, (fx, fy)


def render(sc, path, rx, ry):
    sc.render.resolution_x, sc.render.resolution_y = rx, ry
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)


def look(cam, loc, target):
    cam.location = Vector(loc)
    cam.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()


def ortho_view(sc, cam, path, center, direction, w, h, rx=1400, up="Z"):
    cam.data.type = "ORTHO"
    ry = int(max(320, min(1100, rx * h / max(w, 1e-3))))
    cam.data.ortho_scale = max(w, h * rx / ry) * 1.04
    d = Vector(direction).normalized()
    loc = Vector(center) - d * 400
    cam.location = loc
    upv = "Y" if up == "Z" else "Z"
    q = d.to_track_quat("-Z", "Y")
    cam.rotation_euler = q.to_euler()
    cam.data.clip_start, cam.data.clip_end = 1, 2000
    render(sc, path, rx, ry)


def renders(name, ob, H, bb):
    sc, cam, ground, (fx, fy) = setup_scene(H, bb)
    lo, hi = Vector(bb[0]), Vector(bb[1])
    alo = Vector((min(lo.x, fx - 1.0), min(lo.y, fy - 0.5), 0)); ahi = Vector((hi.x, hi.y, max(hi.z, 2.0)))
    c = (alo + ahi) / 2
    R = (ahi - alo).length / 2
    cam.data.type = "PERSP"; cam.data.lens = 35; cam.data.clip_start = 0.1; cam.data.clip_end = 5000
    dist = R / math.sin(math.radians(22)) * 1.02
    base = os.path.join(OUT, name)
    for tag, az, el in (("A_persp_front", -35, 18), ("B_persp_back", 145, 18)):
        a, e = math.radians(az), math.radians(el)
        dvec = Vector((math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e)))
        look(cam, c + dvec * dist, c)
        render(sc, f"{base}_{tag}.png", 1000, 750)
    W = ahi.x - alo.x
    ortho_view(sc, cam, f"{base}_C_front_full.png", ((alo.x + ahi.x) / 2, 0, (0 + ahi.z) / 2), (0, 1, 0), W + 1, ahi.z + 0.6)
    zt = min(H, 3.6) + 0.3
    ortho_view(sc, cam, f"{base}_D_front_low.png", ((alo.x + ahi.x) / 2, 0, (zt - 0.3) / 2), (0, 1, 0), W + 0.6, zt + 0.3)
    D = ahi.y - alo.y
    ortho_view(sc, cam, f"{base}_E_side_low.png", (0, (alo.y + ahi.y) / 2, (zt - 0.3) / 2), (-1, 0, 0), D + 0.6, zt + 0.3)
    ground.hide_render = True
    sc.world.node_tree.nodes["Background"].inputs[1].default_value = 1.4
    ortho_view(sc, cam, f"{base}_F_underside.png", ((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, 0), (0, 0, 1), hi.x - lo.x + 1, hi.y - lo.y + 1, rx=1000)
    sc.world.node_tree.nodes["Background"].inputs[1].default_value = 0.7
    # 剖面：自上往下，切在 1.5 m（塔／像：0.3 H）
    zc = 1.5 if H > 5 else 0.5 * H
    cam.data.type = "ORTHO"
    cam.location = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, H + 20)); cam.rotation_euler = Euler((0, 0, 0))
    wx, wy = hi.x - lo.x + 1, hi.y - lo.y + 1
    ry = int(max(320, min(1100, 1000 * wy / wx)))
    cam.data.ortho_scale = max(wx, wy * 1000 / ry) * 1.04
    cam.data.clip_start, cam.data.clip_end = H + 20 - zc, H + 60
    render(sc, f"{base}_H_section.png", 1000, ry)
    ground.hide_render = False
    # 背面檢查
    bpy.context.view_layer.material_override = backface_mat()
    cam.data.type = "PERSP"; cam.data.clip_start = 0.1; cam.data.clip_end = 5000
    a, e = math.radians(-35), math.radians(18)
    look(cam, c + Vector((math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e))) * dist, c)
    render(sc, f"{base}_G_backface.png", 1000, 750)
    bpy.context.view_layer.material_override = None


# ---------------------------------------------------------------- main
results = []
for job in JOBS:
    if ONLY and job["name"] not in ONLY:
        continue
    t0 = time.time()
    try:
        ob, s, n_obj, pivot = load(job)
        V, T, UV, M = arrays(ob)
        H = float(V[:, 2].max())
        lo, hi = V.min(0), V.max(0)
        geo, area = geometry(V, T)
        gr = grounding(V, T)
        mats, texw, tex_bytes = materials(ob, M)
        uvs = uvstats(V, T, UV, M, area, texw)
        r = {"name": job["name"], "path": job["path"], "slot": job.get("slot"), "basis": job.get("basis"),
             "scale_applied": round(s, 4), "objects_in_file": n_obj,
             "size_m": [round(float(x), 2) for x in hi - lo], "pivot": pivot, "geometry": geo, "grounding": gr,
             "uv": uvs, "materials": mats, "n_materials": len(mats), "tex_mem_mb_uncompressed": round(tex_bytes / 2**20, 1)}
        log(job["name"], "measured", round(time.time() - t0, 1), "s")
        renders(job["name"], ob, H, [lo.tolist(), hi.tolist()])
        r["seconds"] = round(time.time() - t0, 1)
    except Exception as e:
        import traceback; traceback.print_exc()
        r = {"name": job["name"], "path": job["path"], "error": repr(e)}
    results.append(r)
    json.dump(results, open(os.path.join(OUT, f"audit_{os.getpid()}.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    log(job["name"], "done", r.get("seconds"))

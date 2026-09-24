import bpy, sys, json, numpy as np
argv = sys.argv[sys.argv.index("--") + 1:]
jobs = [("博麗鳥居", "D:/神社/shrine/godot/assets/shrine/博麗鳥居.glb", 9.6),
        ("大鳥居", "D:/神社/shrine/godot/assets/landmark/大鳥居.glb", 20.0)]
out = {}
for name, path, s in jobs:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    names = [o.name for o in bpy.context.scene.objects]
    V = []; E = []; off = 0
    dg = bpy.context.evaluated_depsgraph_get()
    for o in objs:
        m = o.evaluated_get(dg).to_mesh()
        a = np.empty(len(m.vertices) * 3); m.vertices.foreach_get("co", a)
        a = a.reshape(-1, 3) @ np.array(o.matrix_world)[:3, :3].T + np.array(o.matrix_world)[:3, 3]
        e = np.empty(len(m.edges) * 2, dtype=np.int64); m.edges.foreach_get("vertices", e)
        V.append(a); E.append(e.reshape(-1, 2) + off); off += len(a)
    V = np.concatenate(V) * s; E = np.concatenate(E)
    V[:, 2] -= V[:, 2].min(); V[:, :2] -= (V[:, :2].min(0) + V[:, :2].max(0)) / 2
    H = V[:, 2].max()
    # 取柱身高度帶（避開台座與笠木）
    res = {"objects": names, "H": round(float(H), 2)}
    for zf in (0.30, 0.45):
        z = zf * H
        za, zb = V[E[:, 0], 2], V[E[:, 1], 2]
        k = (za - z) * (zb - z) < 0
        t = ((z - za[k]) / (zb[k] - za[k]))[:, None]
        b = V[E[k, 0]] + t * (V[E[k, 1]] - V[E[k, 0]])
        L, R = b[b[:, 0] < 0], b[b[:, 0] > 0]
        res[f"z{zf}"] = {"z_m": round(float(z), 2),
                         "clear_opening_m": round(float(R[:, 0].min() - L[:, 0].max()), 2),
                         "pillar_centre_span_m": round(float((R[:, 0].min() + R[:, 0].max()) / 2 - (L[:, 0].min() + L[:, 0].max()) / 2), 2),
                         "pillar_dia_m": [round(float(np.ptp(L[:, 0])), 2), round(float(np.ptp(R[:, 0])), 2)]}
    out[name] = res
json.dump(out, open(argv[0], "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print("[TORII]", json.dumps(out, ensure_ascii=False))

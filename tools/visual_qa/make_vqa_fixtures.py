"""P2 Visual QA 測試建築（Blender 內執行；全部輸出到 --out，不碰專案資產）。

  blender -b --factory-startup --python tools/visual_qa/make_vqa_fixtures.py -- --out=<dir>

每個 fixture 產生 <name>.blend、<name>.glb、<name>.arch.json。單位公尺，Blender −Y＝正面（Godot +Z）。
"""
import json
import os
import sys

import bpy

ARGS = dict(a.lstrip("-").partition("=")[::2] for a in (sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []))
OUT = ARGS.get("out") or os.path.join(os.environ.get("TMPDIR", "."), "vqa_fixtures")
os.makedirs(OUT, exist_ok=True)

COLORS = {"base": (0.55, 0.53, 0.50), "post": (0.55, 0.12, 0.08), "beam": (0.60, 0.16, 0.10),
          "roof": (0.20, 0.22, 0.26), "wall": (0.85, 0.80, 0.68), "lean": (0.25, 0.25, 0.28)}


def reset():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for m in list(bpy.data.meshes):
        bpy.data.meshes.remove(m)


def mat(key):
    name = "m_" + key
    m = bpy.data.materials.get(name)
    if m is None:
        m = bpy.data.materials.new(name)
        m.diffuse_color = (*COLORS[key], 1.0)
        m.use_nodes = True
        m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*COLORS[key], 1.0)
    return m


def box(name, size, center, key):
    import bmesh
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co.x *= size[0]
        v.co.y *= size[1]
        v.co.z *= size[2]
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat(key))
    ob = bpy.data.objects.new(name, me)
    ob.location = center
    bpy.context.scene.collection.objects.link(ob)
    return ob


def gable(name, width, depth, rise, z0, x_off=0.0, x_ext=0.0, key="roof", thick=0.12):
    """切妻屋頂（棟沿 X）：實心三角柱（底面坐在梁上），封閉網格。x_ext＞0 只延長 +X 端（非對稱）。"""
    import bmesh
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    x0, x1 = -width / 2 + x_off, width / 2 + x_off + x_ext
    d = depth / 2
    pts = [(-d, z0), (d, z0), (0.0, z0 + rise)]
    a = [bm.verts.new((x0, y, z)) for y, z in pts]
    b = [bm.verts.new((x1, y, z)) for y, z in pts]
    bm.faces.new(a[::-1])
    bm.faces.new(b)
    n = len(pts)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((a[i], a[j], b[j], b[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat(key))
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def shrine(roof_dx=0.0, post_e_gap=0.0, roof_w=5.0, roof_ext=0.0, tenon=False):
    """小型社殿骨架：基壇 → 兩柱 → 梁 → 切妻屋頂。"""
    box("base", (4.4, 3.0, 0.2), (0, 0, 0.1), "base")
    ph = 3.3 if tenon else 3.0  # 榫接版：柱子直通到梁頂，梁貫穿柱頭（貫）
    box("post_W", (0.24, 0.24, ph), (-1.6, 0, 0.2 + ph / 2), "post")
    box("post_E", (0.24, 0.24, ph - post_e_gap), (1.6, 0, 0.2 + post_e_gap + (ph - post_e_gap) / 2), "post")
    if tenon:
        box("beam", (3.44, 0.2, 0.28), (0, 0, 3.36), "beam")
    else:
        box("beam", (4.0, 0.3, 0.3), (0, 0, 3.35), "beam")
    gable("roof", roof_w, 3.4, 1.0, 3.5, x_off=roof_dx, x_ext=roof_ext)


def shrine_map(bid, extra=None, sym=True, coax=True, tenon=False):
    comps = {"base": {"object": "base", "type": "plinth", "role": "support"},
             "post_W": {"object": "post_W", "type": "post"}, "post_E": {"object": "post_E", "type": "post"},
             "beam": {"object": "beam", "type": "beam"}, "roof": {"object": "roof", "type": "roof"}}
    cons = [{"id": "pw_on_base", "type": "SUPPORT", "a": "post_W", "b": "base"},
            {"id": "pe_on_base", "type": "SUPPORT", "a": "post_E", "b": "base"},
            {"id": "roof_on_beam", "type": "SUPPORT", "a": "roof", "b": "beam"}]
    if tenon:
        cons += [{"id": "beam_tenon_W", "type": "OVERLAP_ALLOWED", "a": "beam", "b": "post_W", "max_depth": 0.25,
                  "region": {"min": [-1.8, -0.2, 3.15], "max": [-1.4, 0.2, 3.55]}},
                 {"id": "beam_tenon_E", "type": "OVERLAP_ALLOWED", "a": "beam", "b": "post_E", "max_depth": 0.25,
                  "region": {"min": [1.4, -0.2, 3.15], "max": [1.8, 0.2, 3.55]}}]
    else:
        cons += [{"id": "beam_on_pw", "type": "SUPPORT", "a": "beam", "b": "post_W"},
                 {"id": "beam_on_pe", "type": "SUPPORT", "a": "beam", "b": "post_E"}]
    if coax:
        cons.append({"id": "roof_centered", "type": "COAXIAL", "a": "beam", "b": "roof", "axis": "frame:up", "tol": 0.02})
    if sym:
        cons.append({"id": "roof_symmetric", "type": "SYMMETRIC", "a": "roof", "b": "roof",
                     "plane": {"point": [0, 0, 0], "normal": "x"}, "tol": 0.02})
    m = {"building_id": bid, "style": "japanese_shrine", "frame": {"origin": [0, 0, 0], "front": "-Y"},
         "components": comps, "constraints": cons, "check_detached": True}
    if extra:
        m.update(extra)
    return m


def house_asym():
    """正常但不對稱的日式町家：主屋＋單側下屋（片流れ）＋偏側入口（玄關不在中軸）。"""
    box("base", (6.4, 4.4, 0.2), (0.5, 0, 0.1), "base")
    box("body", (4.0, 4.0, 2.8), (-0.6, 0, 0.2 + 1.4), "wall")
    gable("roof", 4.8, 4.8, 1.2, 3.0, x_off=-0.6)
    box("lean_wall", (1.8, 4.0, 2.0), (2.3, 0, 0.2 + 1.0), "wall")
    # 下屋屋頂：單坡斜板（簡化成薄盒、以 Y 軸旋轉）
    lean = box("lean_roof", (2.3, 4.6, 0.12), (2.45, 0, 2.45), "lean")
    lean.rotation_euler = (0, 0.32, 0)
    box("entry", (1.0, 0.1, 2.0), (1.0, -2.05, 0.2 + 1.0), "beam")  # 偏側入口（在下屋那一側）
    bpy.context.view_layer.update()
    comps = {"base": {"object": "base", "type": "plinth"}, "body": {"object": "body", "type": "wall"},
             "roof": {"object": "roof", "type": "roof"}, "lean_wall": {"object": "lean_wall", "type": "wall"},
             "lean_roof": {"object": "lean_roof", "type": "roof", "role": "lean_to"},
             "entry": {"object": "entry", "type": "entrance", "role": "decor"}}
    cons = [{"id": "body_on_base", "type": "SUPPORT", "a": "body", "b": "base"},
            {"id": "lean_on_base", "type": "SUPPORT", "a": "lean_wall", "b": "base"},
            {"id": "roof_on_body", "type": "SUPPORT", "a": "roof", "b": "body"},
            # 下屋屋頂插進主屋牆與下屋牆（日式下屋的正常搭接）
            {"id": "lean_into_body", "type": "OVERLAP_ALLOWED", "a": "lean_roof", "b": "body", "max_depth": 0.4},
            {"id": "lean_on_wall", "type": "OVERLAP_ALLOWED", "a": "lean_roof", "b": "lean_wall", "max_depth": 0.4}]
    return {"building_id": "asym_house", "style": "japanese_house", "frame": {"origin": [0, 0, 0], "front": "-Y"},
            "components": comps, "constraints": cons, "check_detached": False,
            "intentional_asymmetry": ["lean_wall", "lean_roof", "entry"]}


def save(name, spec):
    bpy.context.view_layer.update()
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, name + ".blend"))
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, name + ".glb"), export_format="GLB", export_yup=True,
                              export_apply=True, use_selection=False)
    with open(os.path.join(OUT, name + ".arch.json"), "w", encoding="utf-8") as f:
        json.dump(spec, f, ensure_ascii=False, indent=1)
    print(f"[VQA-FIX] {name}")


def main():
    reset(); shrine(); save("ok", shrine_map("ok"))
    reset(); shrine(roof_dx=0.18); save("roof_offset", shrine_map("roof_offset"))
    reset(); shrine(post_e_gap=0.007); save("post_float", shrine_map("post_float"))
    # 同一棟，但連接表的構件 id 和物件名不同（真實資產常見：s01 鳥居 torii → s01_torii_a）
    m = shrine_map("post_float_cid")
    ren = {"post_E": "hashira_E", "base": "kidan"}
    m["components"] = {ren.get(k, k): v for k, v in m["components"].items()}
    for c in m["constraints"]:
        for k in ("a", "b"):
            c[k] = ren.get(c[k], c[k])
    save("post_float_cid", m)
    # 非對稱屋頂但社殿 profile 期待左右對稱、也沒宣告意圖 → 應該是 REVIEW（不是 FAIL）
    reset(); shrine(roof_ext=1.2); save("asym_roof", shrine_map("asym_roof", sym=False, coax=False))
    reset(); shrine(tenon=True); save("tenon", shrine_map("tenon", tenon=True))
    reset(); shrine(roof_w=6.2); save("wide_roof", shrine_map("wide_roof"))
    # 模組接縫：兩片牆模組以 SNAP 對接（無縫）
    reset()
    box("wall_A", (2.0, 0.2, 2.6), (-1.0, 0, 1.3), "wall")
    box("wall_B", (2.0, 0.2, 2.6), (1.0, 0, 1.3), "wall")
    save("module", {"building_id": "module", "style": "generic_modular", "frame": {"origin": [0, 0, 0], "front": "-Y"},
                    "components": {"wall_A": {"object": "wall_A", "type": "wall"}, "wall_B": {"object": "wall_B", "type": "wall"}},
                    "constraints": [{"id": "seam", "type": "SNAP", "a": "wall_A", "b": "wall_B", "tol": 0.002}],
                    "check_detached": False})
    reset(); spec = house_asym(); save("asym_house", spec)


main()
sys.stdout.flush()
os._exit(0)

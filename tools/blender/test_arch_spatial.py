"""arch_spatial 回歸測試（Blender 端，最小測試場景，不碰正式資產）。

blender -b --factory-startup --python tools/blender/test_arch_spatial.py -- [--glb-out=<dir>]
  每個案例在記憶體內建場景 → 驗證 → 比對預期狀態。失敗 exit 1。
  --glb-out：另外匯出座標測試 GLB＋預期值 JSON，給 godot/tools/arch_glb_probe.gd 做 Blender↔Godot 實測比對。
"""
import json
import math
import os
import sys
import time

import bmesh
import bpy
from mathutils import Euler, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import arch_spatial as A  # noqa: E402

RESULTS = []


def reset():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for m in list(bpy.data.meshes):
        bpy.data.meshes.remove(m)


def box(name, size, loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1), parent=None, open_top=False):
    """尺寸直接用頂點 ±size/2 建（不靠 primitive size／scale 換算）。"""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    if open_top:
        top = [f for f in bm.faces if f.normal.z > 0.9]
        bmesh.ops.delete(bm, geom=top, context="FACES_ONLY")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    if parent:
        ob.parent = parent
    ob.location = loc
    ob.rotation_euler = Euler([math.radians(a) for a in rot])
    ob.scale = scale
    return ob


def plane(name, size, loc=(0, 0, 0), rot=(0, 0, 0)):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=size / 2)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = loc
    ob.rotation_euler = Euler([math.radians(a) for a in rot])
    return ob


def empty(name, loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1), parent=None, size=0.5):
    ob = bpy.data.objects.new(name, None)
    ob.empty_display_size = size
    bpy.context.scene.collection.objects.link(ob)
    if parent:
        ob.parent = parent
    ob.location = loc
    ob.rotation_euler = Euler([math.radians(a) for a in rot])
    ob.scale = scale
    return ob


def upd():
    bpy.context.view_layer.update()


def check(case, label, got, want, detail=""):
    ok = got == want
    RESULTS.append((case, label, ok, got, want, detail))
    print(f"{'ok ' if ok else 'BAD'} [{case}] {label}: got {got} want {want} {detail}")


def run(constraints, **kw):
    upd()
    spec = {"building_id": "test", "constraints": constraints, **kw}
    return A.evaluate(spec, cache_path=kw.pop("cache", None) if "cache" in kw else None, undeclared="off", detached=False)


def status(rep, rid):
    for r in rep["results"]:
        if r["rule_id"] == rid:
            return r["status"], r
    return None, None


def near(a, b, tol=1e-5):
    return all(abs(x - y) <= tol for x, y in zip(a, b))


# ── 柱梁基本組 ──
def post_beam(dz=0.0, dx=0.0):
    box("post", (0.24, 0.24, 3.0), (0, 0, 1.5))
    box("beam", (4.0, 0.24, 0.30), (dx, 0, 3.15 + dz))


def case_01_aligned():
    reset(); post_beam()
    rep = run([{"id": "c", "type": "CONTACT", "a": "beam", "b": "post"},
               {"id": "s", "type": "SUPPORT", "a": "beam", "b": "post"}])
    check(1, "柱梁貼合 CONTACT", status(rep, "c")[0], "PASS")
    check(1, "柱梁貼合 SUPPORT", status(rep, "s")[0], "PASS")


def case_02_gap5mm():
    reset(); post_beam(dz=0.005)
    rep = run([{"id": "c", "type": "CONTACT", "a": "beam", "b": "post"},
               {"id": "s", "type": "SUPPORT", "a": "beam", "b": "post"}])
    st, r = status(rep, "c")
    check(2, "5mm 間隙 CONTACT", st, "FAIL", f"gap={r['actual']}")
    check(2, "間隙量測 ≈5mm", abs(r["actual"]["gap"] - 0.005) < 2e-4, True)
    check(2, "修正向量 ≈ -5mm Z", r["fix"] is not None and abs(r["fix"]["translate"][2] + 0.005) < 2e-4, True)
    st, r = status(rep, "s")
    check(2, "5mm 間隙 SUPPORT=FLOATING", (st, "FLOATING" in r["suggestion"]), ("FAIL", True))


def case_03_penetration():
    reset(); post_beam(dz=-0.05)
    rep = run([{"id": "c", "type": "CONTACT", "a": "beam", "b": "post"},
               {"id": "n", "type": "NO_INTERSECTION", "a": "beam", "b": "post"}])
    st, r = status(rep, "n")
    check(3, "柱梁非預期穿插 NO_INTERSECTION", st, "FAIL", f"depth={r['actual']}")
    check(3, "穿透深度 ≈50mm（±解析度）", abs(r["actual"]["depth"] - 0.05) < 0.01, True)
    check(3, "CONTACT 也判穿插", status(rep, "c")[0], "FAIL")


def tenon_scene(dx=0.0):
    box("post", (0.24, 0.24, 3.0), (0, 0, 1.5))
    box("beam", (4.0, 0.24, 0.30), (0, 0, 3.15))
    box("tenon", (0.08, 0.08, 0.20), (dx, 0, 3.0 + 0.10 - 0.0))  # 3.0~3.2：伸入梁 0.2
    region = box("REGION_mortise", (0.10, 0.10, 0.22), (0, 0, 3.1))
    region.hide_set(True)


def case_04_tenon():
    reset(); tenon_scene()
    rep = run([{"id": "ok", "type": "OVERLAP_ALLOWED", "a": "tenon", "b": "beam", "region": "REGION_mortise", "max_depth": 0.21},
               {"id": "strict", "type": "NO_INTERSECTION", "a": "tenon", "b": "beam"}])
    check(4, "合法榫接 OVERLAP_ALLOWED（在榫眼區）", status(rep, "ok")[0], "PASS", str(status(rep, "ok")[1]["actual"]))
    check(4, "同一榫接若宣告 NO_INTERSECTION 則 FAIL（規則分型）", status(rep, "strict")[0], "FAIL")
    reset(); tenon_scene(dx=0.30)
    rep = run([{"id": "ok", "type": "OVERLAP_ALLOWED", "a": "tenon", "b": "beam", "region": "REGION_mortise", "max_depth": 0.21}])
    check(4, "榫頭偏離榫眼 0.3m → 區域外 FAIL", status(rep, "ok")[0], "FAIL", status(rep, "ok")[1]["suggestion"])


def case_05_tiles():
    reset()
    # 屋瓦（薄板）沿 20° 斜面，上片壓在下片上搭接 0.08m、下壓 2mm
    s = math.radians(20)
    d = Vector((math.cos(s), 0, math.sin(s)))
    n = Vector((-math.sin(s), 0, math.cos(s)))
    box("tile_a", (0.40, 0.30, 0.02), tuple(d * 0.0), (0, -20, 0))
    box("tile_b", (0.40, 0.30, 0.02), tuple(d * 0.32 + n * 0.018), (0, -20, 0))
    rep = run([{"id": "lap", "type": "OVERLAP_ALLOWED", "a": "tile_b", "b": "tile_a", "max_depth": 0.01}])
    check(5, "屋瓦搭接 OVERLAP_ALLOWED", status(rep, "lap")[0], "PASS", str(status(rep, "lap")[1]["actual"]))
    reset()
    box("tile_a", (0.40, 0.30, 0.02), (0, 0, 0), (0, -20, 0))
    box("tile_b", (0.40, 0.30, 0.02), tuple(d * 0.32 + n * 0.045), (0, -20, 0))
    rep = run([{"id": "lap", "type": "OVERLAP_ALLOWED", "a": "tile_b", "b": "tile_a", "max_depth": 0.01}])
    check(5, "屋瓦脫開 25mm → FAIL（應搭接）", status(rep, "lap")[0], "FAIL", status(rep, "lap")[1]["suggestion"])


def case_06_roof_offset():
    for off, want in ((0.0, "PASS"), (0.12, "FAIL")):
        reset()
        box("body", (4.0, 3.0, 3.0), (0, 0, 1.5))
        box("roof", (5.0, 4.0, 0.5), (off, 0, 3.25))
        rep = run([{"id": "ax", "type": "COAXIAL", "a": "body", "b": "roof", "axis": "frame:up", "tol": 0.02}])
        st, r = status(rep, "ax")
        check(6, f"屋頂中心偏 {off} m COAXIAL", st, want, f"offset={r['actual']['offset']:.4f}")
    check(6, "偏移量在建築座標的右向分量 = -0.12（建築面朝 -Y，右=-X）",
          abs(r["actual"]["offset_frame_rfu"][0] + 0.12) < 1e-6, True)


def walls(root_rot=37.0, shift=0.0):
    root = empty("root", (5, -3, 0.4), (0, 0, root_rot))
    box("wall_a", (2.0, 0.2, 3.0), (-1.0, 0, 1.5), parent=root)
    box("wall_b", (2.0, 0.2, 3.0), (1.0 + shift, 0, 1.5), parent=root)
    empty("anc_a", (0.0, 0, 1.5), parent=root)  # wall_a 右緣
    empty("anc_b", (0.0 + shift, 0, 1.5), parent=root)  # wall_b 左緣
    return root


def case_07_rotated_module():
    reset(); walls()
    rep = run([{"id": "anc", "type": "SNAP", "a": "wall_b", "b": "wall_a", "anchor_a": "anc_b", "anchor_b": "anc_a"},
               {"id": "flush", "type": "SNAP", "a": "wall_b", "b": "wall_a"},
               {"id": "par", "type": "PARALLEL", "a": "wall_a", "b": "wall_b", "axis": "local:X"}],
              frame={"origin": "root", "front": "local:-Y@root"})
    check(7, "旋轉 37° 模組錨點 SNAP", status(rep, "anc")[0], "PASS")
    check(7, "旋轉 37° 模組接縫齊平 SNAP", status(rep, "flush")[0], "PASS", str(status(rep, "flush")[1]["actual"]))
    check(7, "旋轉模組 PARALLEL", status(rep, "par")[0], "PASS")
    reset(); walls(shift=0.01)
    rep = run([{"id": "anc", "type": "SNAP", "a": "wall_b", "b": "wall_a", "anchor_a": "anc_b", "anchor_b": "anc_a"},
               {"id": "flush", "type": "SNAP", "a": "wall_b", "b": "wall_a"}],
              frame={"origin": "root", "front": "local:-Y@root"})
    st, r = status(rep, "anc")
    check(7, "模組錯開 10mm 錨點 FAIL", st, "FAIL")
    check(7, "錯開量在建築座標＝沿右軸 10mm", abs(abs(r["actual"]["delta_frame"][0]) - 0.01) < 1e-6, True,
          str(r["actual"]["delta_frame"]))
    check(7, "模組錯開 10mm 接縫 FAIL", status(rep, "flush")[0], "FAIL", str(status(rep, "flush")[1]["actual"]))


def case_08_nonuniform():
    reset()
    ob = box("post", (1, 1, 1), (2, 1, 1.5), (0, 0, 30), scale=(0.24, 0.30, 3.0))
    upd()
    b = A.bounds_info(ob)
    ob_ext = sorted(b["obb_upright"]["extents"])
    check(8, "非均勻縮放：直立 OBB 尺寸 = 0.24/0.30/3.0", near(ob_ext, [0.24, 0.30, 3.0], 1e-5), True, str(ob_ext))
    check(8, "非均勻縮放：物件軸 OBB 尺寸", near(b["obb_object"]["extents"], [0.24, 0.30, 3.0], 1e-6), True)
    check(8, "直立 OBB yaw = 30°（mod 90）", abs(b["obb_upright"]["yaw_mod90_deg"] - 30.0) < 0.01 or
          abs(b["obb_upright"]["yaw_mod90_deg"] - 60.0) < 0.01, True, f"{b['obb_upright']['yaw_mod90_deg']:.3f}")
    aabb = b["world_aabb"]["size"]
    exp_x = 0.24 * math.cos(math.radians(30)) + 0.30 * math.sin(math.radians(30))
    check(8, "旋轉後世界 AABB 寬 = 解析值", abs(aabb[0] - exp_x) < 1e-6, True, f"{aabb[0]:.6f} vs {exp_x:.6f}")
    box("ground", (6, 6, 0.2), (2, 1, -0.1))
    rep = run([{"id": "s", "type": "SUPPORT", "a": "post", "b": "ground"}])
    check(8, "非均勻縮放柱 SUPPORT 地面", status(rep, "s")[0], "PASS")


def case_09_negative():
    reset()
    ob = box("post", (0.24, 0.24, 3.0), (0, 0, 1.5), scale=(-1, 1, 1))
    box("ground", (2, 2, 0.2), (0, 0, -0.1))
    upd()
    g = A.geom_from_object(ob)
    down = sum(1 for nrm in g.normals if nrm.dot(Vector((0, 0, -1))) > 0.99)
    out = all(nrm.dot(c - g.centroid()) > 0 for nrm, c in
              zip(g.normals, [(g.verts[a] + g.verts[b] + g.verts[c2]) / 3 for a, b, c2 in g.tris]))
    check(9, "負縮放 det<0 被標記", A.transform_info(ob)["negative_scale"], True)
    check(9, "負縮放後法線仍朝外", out, True, f"down-facing tris={down}")
    rep = run([{"id": "s", "type": "SUPPORT", "a": "post", "b": "ground"}])
    check(9, "負縮放柱 SUPPORT", status(rep, "s")[0], "PASS")


def case_10_parent():
    reset()
    par = empty("parent", (10, 0, 0), (0, 0, 90), scale=(2, 2, 2))
    ch = box("child", (1.0, 0.5, 0.25), (1, 0, 0), parent=par)
    upd()
    b = A.bounds_info(ch)
    check(10, "Parent 旋轉 90°＋縮放 2：世界尺寸 (1,2,0.5)", near(b["world_aabb"]["size"], [1.0, 2.0, 0.5], 1e-6), True,
          str([round(x, 6) for x in b["world_aabb"]["size"]]))
    check(10, "Parent：世界中心 (10,2,0)", near(b["aabb_center"], [10, 2, 0], 1e-6), True, str(b["aabb_center"]))
    ti = A.transform_info(ch)
    check(10, "Parent：子物件世界 X 軸 = +Y", near(ti["world_axes"]["X"], [0, 1, 0], 1e-6), True)
    sk = empty("skewp", (0, 0, 0), (0, 0, 0), scale=(1, 3, 1))
    s2 = box("skewc", (1, 1, 1), (0, 0, 0), (0, 0, 45), parent=sk)
    upd()
    check(10, "父層非均勻＋子旋轉 → 斜切被偵測、物件軸 OBB 拒算", (A.transform_info(s2)["shear_cos"] > 1e-4, A.obb_object(s2)),
          (True, None))


def case_19_coplanar():
    reset()
    box("lower", (1, 1, 1), (0, 0, 0.5))
    box("upper", (1, 1, 1), (0, 0, 1.5))
    rep = run([{"id": "n", "type": "NO_INTERSECTION", "a": "upper", "b": "lower"},
               {"id": "c", "type": "CONTACT", "a": "upper", "b": "lower"}])
    check(19, "共面接觸不算穿插", status(rep, "n")[0], "PASS", str(status(rep, "n")[1]["actual"]))
    check(19, "共面接觸 CONTACT", status(rep, "c")[0], "PASS")


def case_20_nonmanifold():
    reset()
    box("cup", (1, 1, 1), (0, 0, 0.5), open_top=True)
    plane("sheet", 1.6, (0, 0, 0.5), (0, 90, 0))
    rep = run([{"id": "n", "type": "NO_INTERSECTION", "a": "sheet", "b": "cup"}])
    check(20, "兩個非封閉網格相交 → UNKNOWN（不猜）", status(rep, "n")[0], "UNKNOWN")
    reset()
    box("cup", (1, 1, 1), (0, 0, 0.5), open_top=True)
    box("ball", (0.3, 0.3, 0.3), (0, 0, 0.5))
    upd()
    pen = A.penetration(A.geom_from_object(bpy.data.objects["ball"]), A.geom_from_object(bpy.data.objects["cup"]))
    check(20, "封閉體完全在開口杯內：三角形不交且杯非封閉 → 不誤報穿插", pen["intersects"], False)


def case_sym_cont():
    reset()
    box("post_L", (0.24, 0.24, 3), (-1.5, 0, 1.5))
    box("post_R", (0.24, 0.24, 3), (1.5, 0, 1.5))
    rep = run([{"id": "sym", "type": "SYMMETRIC", "a": "post_L", "b": "post_R"}])
    check("sym", "左右柱對稱", status(rep, "sym")[0], "PASS")
    bpy.data.objects["post_R"].location.x = 1.53
    rep = run([{"id": "sym", "type": "SYMMETRIC", "a": "post_L", "b": "post_R"}])
    check("sym", "右柱外移 30mm → 不對稱 FAIL", status(rep, "sym")[0], "FAIL", status(rep, "sym")[1]["suggestion"])
    reset()
    rises = [0.15, 0.15, 0.15, 0.15]
    for i, r in enumerate(rises):
        box(f"step{i}", (1.2, 0.3, 0.15 * (i + 1)), (0, -0.3 * i, 0.075 * (i + 1)))
    names = [f"step{i}" for i in range(4)]
    rep = run([{"id": "st", "type": "CONTINUOUS", "components": names, "rise_max": 0.2}])
    check("cont", "石階級高連續", status(rep, "st")[0], "PASS", str(status(rep, "st")[1]["actual"]["rises"]))
    bpy.data.objects["step3"].scale.z = (0.15 * 4 + 0.04) / (0.15 * 4)
    bpy.data.objects["step3"].location.z = (0.15 * 4 + 0.04) / 2
    rep = run([{"id": "st", "type": "CONTINUOUS", "components": names, "rise_max": 0.2}])
    check("cont", "最後一階高 40mm → FAIL", status(rep, "st")[0], "FAIL", status(rep, "st")[1]["suggestion"])
    reset()
    for i, x in enumerate((0.0, 1.8, 3.6, 5.6)):
        box(f"p{i}", (0.2, 0.2, 2), (x, 0, 1))
    rep = run([{"id": "ev", "type": "EVEN_SPACING", "components": ["p0", "p1", "p2", "p3"], "axis": "x"}])
    check("soft", "柱距不均（軟約束）→ WARN 不是 FAIL", status(rep, "ev")[0], "WARN")
    rep = run([{"id": "perp", "type": "PERPENDICULAR", "a": "p0", "b": "p1", "axis_a": "local:Z", "axis_b": "local:X"},
               {"id": "cl", "type": "CLEARANCE_REQUIRED", "a": "p0", "b": "p1", "min": 1.5, "max": 1.7}])
    check("misc", "PERPENDICULAR", status(rep, "perp")[0], "PASS")
    check("misc", "CLEARANCE 淨距 1.6 m 在 [1.5,1.7]", status(rep, "cl")[0], "PASS", str(status(rep, "cl")[1]["actual"]))


def case_support_embed():
    """回歸：柱腳埋入支撐體比射線起點深（曾誤判成懸空 494 mm）；非封閉柱（無底蓋）改用最低頂點法。"""
    for dz, emb, want, tag in ((-0.30, 0.01, "FAIL", "OVER_EMBEDDED"), (-0.30, 0.35, "PASS", ""), (-0.02, 0.03, "PASS", "")):
        reset()
        box("base", (1.0, 1.0, 0.6), (0, 0, 0.0))
        box("post", (0.3, 0.3, 3.0), (0, 0, 0.3 + 1.5 + dz))
        rep = run([{"id": "s", "type": "SUPPORT", "a": "post", "b": "base", "embed_max": emb}])
        st, r = status(rep, "s")
        check("emb", f"封閉柱埋入 {-dz} m（embed_max {emb}）", (st, tag in r["suggestion"]), (want, True),
              f"median={r['actual']['median_gap']}")
    for dz, want, tag in ((-0.02, "PASS", ""), (0.005, "FAIL", "FLOATING"), (-0.30, "FAIL", "OVER_EMBEDDED")):
        reset()
        box("base", (1.0, 1.0, 0.6), (0, 0, 0.0))
        tube = box("post", (0.3, 0.3, 3.0), (0, 0, 0.3 + 1.5 + dz), open_top=True)
        me = tube.data  # 再拿掉底蓋 → 開口圓筒（同鳥居實物）
        bm = bmesh.new(); bm.from_mesh(me)
        bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.normal.z < -0.9], context="FACES_ONLY")
        bm.to_mesh(me); bm.free()
        rep = run([{"id": "s", "type": "SUPPORT", "a": "post", "b": "base", "embed_max": 0.03}])
        st, r = status(rep, "s")
        check("emb", f"開口柱（非封閉）dz={dz}", (st, tag in r["suggestion"], r["method"].startswith("lowest")),
              (want, True, True), f"median={r['actual']['median_gap']}")
    reset()
    base = box("base", (1.0, 1.0, 0.6), (0, 0, 0.0))
    bm = bmesh.new(); bm.from_mesh(base.data)  # 拿掉一個側面 → 台座也不封閉
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.normal.x > 0.9], context="FACES_ONLY")
    bm.to_mesh(base.data); bm.free()
    tube = box("post", (0.3, 0.3, 3.0), (0, 0, 0.3 + 1.5 - 0.30), open_top=True)
    rep = run([{"id": "s", "type": "SUPPORT", "a": "post", "b": "base", "embed_max": 0.03}])
    check("emb", "兩者都不封閉＋柱腳在台座正中（上下等距）→ UNKNOWN 不猜", status(rep, "s")[0], "UNKNOWN",
          status(rep, "s")[1]["suggestion"])
    reset()
    box("cup", (1, 1, 1), (0, 0, 0.5), open_top=True)
    plane("sheet", 1.6, (0, 0, 0.5), (0, 90, 0))
    upd()
    rep = A.scan(building_id="u")
    st, r = status(rep, "UNDECLARED_UNMEASURABLE")
    check("emb", "scan：非封閉相交彙總成一列 UNKNOWN", (st, r["actual"]["pairs"] if r else None), ("UNKNOWN", 1))


def case_detached():
    reset()
    box("ground", (6, 6, 0.2), (0, 0, -0.1))
    box("post", (0.24, 0.24, 3), (0, 0, 1.5))
    box("beam", (4, 0.24, 0.3), (0, 0, 3.15))
    box("ornament", (0.2, 0.2, 0.2), (0, 0, 3.40))
    upd()
    rep = A.scan(building_id="detached")
    st, r = status(rep, "DETACHED")
    check("scan", "零件全部連到地面", st, "PASS")
    bpy.data.objects["ornament"].location.z = 3.50
    upd()
    rep = A.scan(building_id="detached")
    st, r = status(rep, "DETACHED")
    check("scan", "裝飾浮起 0.1 m → DETACHED", (st, r["actual"]["floating_parts"]), ("FAIL", ["ornament"]))


def case_21_perf():
    reset()
    box("ground", (60, 60, 0.2), (14, 14, -0.1))
    n = 0
    for i in range(14):
        for j in range(14):
            box(f"post_{i}_{j}", (0.24, 0.24, 3), (i * 2, j * 2, 1.5)); n += 1
            box(f"beam_{i}_{j}", (2.0, 0.24, 0.3), (i * 2 + 1.0 - 0.12 + 0.12, j * 2, 3.15)); n += 1
    upd()
    t = time.time()
    rep = A.scan(building_id="perf")
    dt = time.time() - t
    st, r = status(rep, "DETACHED")
    check(21, f"效能：{n + 1} 物件 scan", st, "PASS", f"{dt:.2f} s, edges={r['actual']['contact_edges']}")
    RESULTS.append((21, "perf_seconds", dt < 120, round(dt, 2), "<120", f"{n+1} objects"))
    names = [f"beam_{i}_{j}" for i in range(14) for j in range(14)]
    cons = [{"id": f"s{k}", "type": "SUPPORT", "a": nm, "b": nm.replace("beam", "post")} for k, nm in enumerate(names)]
    t = time.time()
    rep = run(cons)
    dt2 = time.time() - t
    check(21, f"效能：{len(cons)} 條 SUPPORT 約束", rep["summary"]["PASS"], len(cons), f"{dt2:.2f} s")


def case_22_cache(tmp):
    reset()
    root = empty("root")
    box("post", (0.24, 0.24, 3.0), (0, 0, 1.5), parent=root)
    box("beam", (4.0, 0.24, 0.30), (0, 0, 3.15), parent=root)
    cpath = os.path.join(tmp, "arch_cache_test.json")
    if os.path.exists(cpath):
        os.remove(cpath)
    spec = {"building_id": "cache", "constraints": [{"id": "c", "type": "CONTACT", "a": "beam", "b": "post"}]}
    upd(); r1 = A.evaluate(spec, cpath, undeclared="off", detached=False)
    upd(); r2 = A.evaluate(spec, cpath, undeclared="off", detached=False)
    check(22, "第二次相同場景命中快取", (r2["results"][0]["cached"], r2["results"][0]["status"]), (True, "PASS"))
    bpy.data.objects["beam"].location.z += 0.006
    upd(); r3 = A.evaluate(spec, cpath, undeclared="off", detached=False)
    check(22, "子物件移動 6mm → 快取失效且改判 FAIL", (r3["results"][0]["cached"], r3["results"][0]["status"]), (False, "FAIL"))
    bpy.data.objects["beam"].location.z -= 0.006
    root.location.x += 3.0
    upd(); r4 = A.evaluate(spec, cpath, undeclared="off", detached=False)
    check(22, "父物件移動 → 世界網格變 → 不沿用舊結果", r4["results"][0]["cached"], False)
    mod = bpy.data.objects["post"].modifiers.new("solid", "DISPLACE")
    mod.strength = 0.004
    upd(); r5 = A.evaluate(spec, cpath, undeclared="off", detached=False)
    check(22, "加修改器（評估後網格變）→ 快取失效", r5["results"][0]["cached"], False)


def case_frame():
    reset()
    root = empty("root", (0, 0, 0), (0, 0, 90))
    empty("MARK_Front", (0, -1, 0), parent=root)  # 建築正面 = root 本地 -Y → 世界 +X
    box("post_right", (0.2, 0.2, 2), (-1.0, 0, 1), parent=root)  # 本地 -X = 建築右側
    upd()
    fr = A.frame_from_spec({"origin": "root", "front": "MARK_Front"})
    p = A.geom_from_object(bpy.data.objects["post_right"]).centroid()
    lp = fr.to_local(p)
    check("frame", "建築座標：正面向量 = 世界 +X", near(list(fr.front), [1, 0, 0], 1e-6), True, str(list(fr.front)))
    check("frame", "右柱在建築座標 right>0（世界 Y<0）", (lp.x > 0.9, p.y < 0), (True, True), f"local={list(lp)}")


def export_glb(out_dir):
    """座標實測：匯出有 Parent／旋轉／非均勻／負縮放的組合，寫出 Blender 端換算後的 Godot 預期值。"""
    reset()
    root = empty("root", (3, -2, 0.5), (0, 0, 30))
    box("post", (0.24, 0.24, 3.0), (1, 0, 1.5), parent=root)
    box("beam", (1, 1, 1), (0, 0.5, 3.15), (0, 0, 15), scale=(4.0, 0.24, 0.30), parent=root)
    box("mirror", (0.5, 0.3, 0.2), (-1, -1, 0.1), scale=(-1, 1, 1), parent=root)
    box("front_marker", (0.1, 0.1, 0.1), (0, -2, 0.05), parent=root)  # 建築正面（Blender -Y）
    upd()
    exp = {}
    for nm in ("post", "beam", "mirror", "front_marker"):
        g = A.geom_from_object(bpy.data.objects[nm])
        pts = [A.blender_to_godot(v) for v in g.verts]
        exp[nm] = {"min": [min(p[i] for p in pts) for i in range(3)], "max": [max(p[i] for p in pts) for i in range(3)]}
    os.makedirs(out_dir, exist_ok=True)
    glb = os.path.join(out_dir, "arch_axis_test.glb")
    bpy.ops.export_scene.gltf(filepath=glb, export_format="GLB", export_yup=True, export_apply=True)
    with open(os.path.join(out_dir, "arch_axis_test.expect.json"), "w", encoding="utf-8") as f:
        json.dump(exp, f, indent=1)
    print("[GLB]", glb)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    tmp = next((a.split("=", 1)[1] for a in argv if a.startswith("--tmp=")), os.environ.get("TMPDIR", "."))
    glb_out = next((a.split("=", 1)[1] for a in argv if a.startswith("--glb-out=")), None)
    t = time.time()
    for fn in (case_01_aligned, case_02_gap5mm, case_03_penetration, case_04_tenon, case_05_tiles, case_06_roof_offset,
               case_07_rotated_module, case_08_nonuniform, case_09_negative, case_10_parent, case_19_coplanar,
               case_20_nonmanifold, case_support_embed, case_sym_cont, case_detached, case_frame):
        fn()
    case_22_cache(tmp)
    if "--no-perf" not in argv:
        case_21_perf()
    if glb_out:
        export_glb(glb_out)
    bad = [r for r in RESULTS if not r[2]]
    print(f"\n[ARCH-TEST] {len(RESULTS) - len(bad)}/{len(RESULTS)} ok, {time.time() - t:.1f} s")
    for r in bad:
        print("  BAD", r)
    sys.exit(1 if bad else 0)


main()

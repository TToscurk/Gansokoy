"""arch_check — 建築構件驗證 CLI（唯讀：不改場景、不存 .blend）。

  blender -b <asset.blend> --python tools/blender/arch_check.py -- --map=<x.arch.json> [--out=report.json] [--cache=c.json]
  blender -b --factory-startup --python tools/blender/arch_check.py -- --glb=<asset.glb> --scan [--split] [--out=...]
  blender -b <asset.blend> --python tools/blender/arch_check.py -- --transforms [--objects=a,b]

  --map        連接表／約束 JSON（格式見 docs/arch_spatial/README.md）
  --scan       沒有連接表：懸空零件（接觸圖不連到地面）＋未宣告穿插
  --split      scan 時把單一網格拆成連通島（Tripo 單網格建築）
  --glb        先匯入 GLB 到空場景（來源檔不動）；glTF Y-up 會被 Blender 匯入器轉回 Z-up
  --undeclared warn|fail|off   map 模式下未宣告的穿插怎麼記（預設 warn）
  --transforms 只輸出 Phase 1 座標／尺寸／OBB 報告
exit：有 FAIL → 1；只有 UNKNOWN → 3；其餘 0。
"""
import json
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import arch_spatial as A  # noqa: E402


def _args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = {}
    for a in argv:
        k, _, v = a.lstrip("-").partition("=")
        out[k] = v if v else True
    return out


def main():
    a = _args()
    if a.get("glb"):
        for o in list(bpy.data.objects):
            bpy.data.objects.remove(o, do_unlink=True)
        bpy.ops.import_scene.gltf(filepath=a["glb"])
    if a.get("scale"):  # 只縮放記憶體中的場景（來源檔不動），讓公尺容差對應遊戲內實際尺寸
        s = float(a["scale"])
        for o in bpy.context.scene.objects:
            if o.parent is None:
                o.matrix_world = __import__("mathutils").Matrix.Scale(s, 4) @ o.matrix_world
    bpy.context.view_layer.update()
    if a.get("godot-expect"):
        rep = A.godot_expect(front_node=a.get("front-node") or None)
        with open(a["godot-expect"], "w", encoding="utf-8") as f:
            json.dump(rep, f, ensure_ascii=False, indent=1)
        print(f"[ARCH] godot expect {len(rep['nodes'])} nodes → {a['godot-expect']}")
        return 0
    if a.get("transforms"):
        names = a["objects"].split(",") if a.get("objects") else [o.name for o in bpy.context.scene.objects if o.type == "MESH"]
        rep = {"transforms": [A.transform_info(bpy.data.objects[n]) for n in names],
               "bounds": [A.bounds_info(bpy.data.objects[n]) for n in names]}
        txt = json.dumps(rep, ensure_ascii=False, indent=1, default=A._jsonable)
        if a.get("out"):
            open(a["out"], "w", encoding="utf-8").write(txt)
        print(txt if not a.get("out") else f"[ARCH] transforms → {a['out']}")
        return 0
    if a.get("map"):
        with open(a["map"], encoding="utf-8") as f:
            spec = json.load(f)
        want_graph = bool(a.get("graph") or a.get("query") or a.get("fix-preview"))
        res = A.evaluate(spec, a.get("cache") or None, undeclared=a.get("undeclared", "warn"),
                         detached=spec.get("check_detached", True), return_graph=want_graph)
        rep, graph = res if want_graph else (res, None)
        if a.get("graph"):
            with open(a["graph"], "w", encoding="utf-8") as f:
                json.dump(graph.to_json(), f, ensure_ascii=False, indent=1, default=A._jsonable)
            print(f"[ARCH] graph {len(graph.nodes)} nodes / {len(graph.edges)} edges → {a['graph']}")
        if a.get("query"):
            for q in str(a["query"]).split(";"):
                ans = A.run_query(graph, q)
                print(f"[ARCH-Q] {q}\n" + (ans if isinstance(ans, str) else json.dumps(ans, ensure_ascii=False, indent=1, default=A._jsonable)))
        if a.get("fix-preview"):
            fp = A.fix_preview(spec, rep, graph, carry=a.get("carry", "dependents"))
            with open(a["fix-preview"], "w", encoding="utf-8") as f:
                json.dump(fp, f, ensure_ascii=False, indent=1, default=A._jsonable)
            for p in fp["previews"]:
                print(f"[ARCH-FIX] {p['verdict']:9} {p['rule_id']}: 移 {p['moved']} {p['fix']['translate']} "
                      f"新 FAIL {p['new_failures']} {p['note']}")
            print(f"[ARCH-FIX] scene_restored={fp['scene_restored']} written={fp['written']}")
        rep.pop("graph", None)
    elif a.get("scan"):
        rep = A.scan(building_id=a.get("id", os.path.basename(a.get("glb", "") or bpy.data.filepath) or "scan"),
                     split=bool(a.get("split")), undeclared=a.get("undeclared", "warn"))
        if a.get("graph"):  # 沒有連接表：每個網格物件一個不透明節點（內部構件無法辨識）
            gs = [A.SceneGraph.opaque(rep["building_id"], o, len(A.split_islands(A.geom_from_object(o))) if a.get("split") else None)
                  for o in bpy.context.scene.objects if o.type == "MESH" and o.visible_get()]
            out = {"building_id": rep["building_id"], "nodes": {k: v for g in gs for k, v in g.nodes.items()},
                   "edges": [], "limits": [x for g in gs for x in g.limits]}
            with open(a["graph"], "w", encoding="utf-8") as f:
                json.dump(out, f, ensure_ascii=False, indent=1, default=A._jsonable)
            for x in out["limits"]:
                print("[ARCH] LIMIT", x)
    else:
        print(__doc__)
        return 2
    if a.get("out"):
        with open(a["out"], "w", encoding="utf-8") as f:
            json.dump(rep, f, ensure_ascii=False, indent=1, default=A._jsonable)
    if a.get("targets"):  # P2 Visual QA：非 PASS 結果 → 特寫目標＋每個網格物件的 Blender 世界 AABB
        cmap = {}
        if a.get("map"):
            for cid, ent in (spec.get("components") or {}).items():
                ob = A._find_object(cid, ent)
                cmap[cid] = ob.name if ob is not None else cid
        vt = A.visual_targets(rep, cid_map=cmap)
        with open(a["targets"], "w", encoding="utf-8") as f:
            json.dump(vt, f, ensure_ascii=False, indent=1, default=A._jsonable)
        print(f"[ARCH] visual targets {len(vt['targets'])} → {a['targets']}")
    print(A.summary_text(rep))
    s = rep["summary"]
    return 1 if s["FAIL"] else (3 if s["UNKNOWN"] and not s["PASS"] else 0)


try:
    code = main()
except Exception as e:  # noqa: BLE001
    import traceback
    traceback.print_exc()
    print(f"[ARCH] ERROR {e}")
    code = 2
sys.stdout.flush()
os._exit(code)

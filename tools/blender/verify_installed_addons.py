"""實測驗證已安裝 extension：不看清單，直接檢查每個套件是否真的註冊了功能。

對每個 extension，檢查它是否至少註冊了 operator / panel / 屬性群組之一。
只出現在偏好設定但沒註冊任何東西 = 實際上是壞的。
"""
import json

import bpy

# 安裝前就存在的（Blender 內建 + 使用者原有）
PREEXISTING = {
    "Tripo3d_Blender_Bridge", "bl_pkg", "blender_mcp", "cycles",
    "io_anim_bvh", "io_curve_svg", "io_mesh_uv_layout",
    "io_scene_fbx", "io_scene_gltf2", "pose_library", "rigify",
    "bl_ext.user_default.meshy",
}

ops_modules = {m for m in dir(bpy.ops) if not m.startswith("_")}
panel_names = {c.__name__ for c in bpy.types.Panel.__subclasses__()}
menu_names = {c.__name__ for c in bpy.types.Menu.__subclasses__()}
pg_names = {c.__name__ for c in bpy.types.PropertyGroup.__subclasses__()}
scene_props = {p for p in dir(bpy.types.Scene)}
obj_props = {p for p in dir(bpy.types.Object)}

enabled = sorted(a.module for a in bpy.context.preferences.addons)
ext = [m for m in enabled if m.startswith("bl_ext.")]

report = {"total_enabled": len(enabled), "extensions": len(ext),
          "alive": [], "suspect": []}

for mod in ext:
    short = mod.split(".")[-1]
    if mod in PREEXISTING or short in PREEXISTING:
        continue
    key = short.lower().replace("_", "")
    hits = []
    for o in ops_modules:
        if key.startswith(o.lower().replace("_", "")[:6]) or \
           o.lower().replace("_", "")[:6] in key:
            if len(o) >= 4:
                hits.append("ops." + o)
                break
    for nm in panel_names:
        n = nm.lower().replace("_", "")
        if key[:6] in n or n[:6] in key:
            hits.append("panel." + nm)
            break
    for nm in pg_names:
        n = nm.lower().replace("_", "")
        if key[:6] in n or n[:6] in key:
            hits.append("pg." + nm)
            break
    for p in scene_props | obj_props:
        n = p.lower().replace("_", "")
        if len(n) >= 5 and (key[:6] in n or n[:6] in key):
            hits.append("prop." + p)
            break
    if hits:
        report["alive"].append({"mod": short, "evidence": hits[:3]})
    else:
        report["suspect"].append(short)

print("VERIFYSTART" + json.dumps(report, ensure_ascii=False) + "VERIFYEND")

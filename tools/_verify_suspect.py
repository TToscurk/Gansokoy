"""逐一實測 suspect 套件：直接找它們註冊的 operator / panel，不靠名稱比對。

前一版用模組名比對 operator 名，名稱不像就誤判為壞掉。本版改為：
對每個模組，匯入它並列出其註冊的 bpy 類別。
"""
import json
import sys

import bpy

SUSPECT = ["Real_Time_Paths", "RigFlex", "ani_offset", "easeit",
           "fk_ik_snapping_tools", "humanoid_remap_studio", "mixamo_rig",
           "momentum", "openvat", "quickpath_rknz"]

out = {}
for short in SUSPECT:
    mod_name = f"bl_ext.blender_org.{short}"
    m = sys.modules.get(mod_name)
    if m is None:
        out[short] = {"state": "NOT_LOADED"}
        continue
    classes = []
    for attr in dir(m):
        obj = getattr(m, attr, None)
        if isinstance(obj, type) and issubclass(
                obj, (bpy.types.Operator, bpy.types.Panel, bpy.types.Menu,
                      bpy.types.PropertyGroup)):
            classes.append(obj.__name__)
    # 子模組也算
    for sub in list(sys.modules):
        if sub.startswith(mod_name + "."):
            sm = sys.modules[sub]
            for attr in dir(sm):
                obj = getattr(sm, attr, None)
                if isinstance(obj, type) and issubclass(
                        obj, (bpy.types.Operator, bpy.types.Panel)):
                    classes.append(obj.__name__)
    # 實際可呼叫的 operator bl_idname
    idnames = []
    for attr in dir(m):
        obj = getattr(m, attr, None)
        if isinstance(obj, type) and issubclass(obj, bpy.types.Operator):
            bi = getattr(obj, "bl_idname", None)
            if bi:
                idnames.append(bi)
    out[short] = {"state": "LOADED", "n_classes": len(set(classes)),
                  "sample": sorted(set(classes))[:5], "ops": idnames[:5]}

print("SUSSTART" + json.dumps(out, ensure_ascii=False) + "SUSEND")

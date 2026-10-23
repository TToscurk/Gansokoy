"""把彩繪玻璃貼圖貼到緣一耳飾面板。

耳飾材質原本只有素灰 Principled BSDF，無任何貼圖節點。Tripo 產生的 UV 是
散的（同一世界高度分佈在整張 UV），直接貼圖會亂，故對面板部分重投影一組
平面 UV（正面朝 -Y）。

只更動兩個耳飾物件，其餘場景不碰。
"""
import json
import math
from collections import defaultdict, deque

import bmesh
import bpy
import numpy as np

TEX = r"D:/神社/shrine/work/yoriichi_earring/earring_panel.png"
OBJS = ["耳飾右", "耳飾左"]
UV_NAME = "panel_uv"
# 面板：連通分量中最大且最長的一塊（實測 96 頂點、4.53 cm 高）
PANEL_MIN_H = 0.03


def log(*a):
    print("EAR", *a)


def components(me):
    adj = defaultdict(list)
    for e in me.edges:
        a, b = e.vertices
        adj[a].append(b)
        adj[b].append(a)
    seen, out = set(), []
    for i in range(len(me.vertices)):
        if i in seen:
            continue
        q, c = deque([i]), []
        seen.add(i)
        while q:
            x = q.popleft()
            c.append(x)
            for y in adj[x]:
                if y not in seen:
                    seen.add(y)
                    q.append(y)
        if len(c) >= 8:
            out.append(c)
    return out


def main():
    img = bpy.data.images.get("earring_panel") or bpy.data.images.load(TEX)
    img.name = "earring_panel"
    img.colorspace_settings.name = "sRGB"
    log("image", img.name, list(img.size))

    report = {}
    for name in OBJS:
        o = bpy.data.objects.get(name)
        if not o:
            log("missing", name)
            continue
        me = o.data
        M = o.matrix_world
        V = np.array([[(M @ v.co).x, (M @ v.co).y, (M @ v.co).z]
                      for v in me.vertices])

        # --- 找面板：z 跨度最大的連通分量 ---
        comps = components(me)
        panel = max(comps, key=lambda c: V[c][:, 2].max() - V[c][:, 2].min())
        P = V[panel]
        h = float(P[:, 2].max() - P[:, 2].min())
        if h < PANEL_MIN_H:
            log("panel too small", name, h)
            continue
        pset = set(panel)
        x0, x1 = float(P[:, 0].min()), float(P[:, 0].max())
        z0, z1 = float(P[:, 2].min()), float(P[:, 2].max())

        # --- 建立專用 UV 層並平面投影（正面朝 -Y）---
        uv = me.uv_layers.get(UV_NAME) or me.uv_layers.new(name=UV_NAME)
        me.uv_layers.active = uv
        data = uv.data
        for poly in me.polygons:
            for li in poly.loop_indices:
                vi = me.loops[li].vertex_index
                if vi in pset:
                    w = M @ me.vertices[vi].co
                    u = (float(w.x) - x0) / max(x1 - x0, 1e-9)
                    v = (float(w.z) - z0) / max(z1 - z0, 1e-9)
                    # 背面左右鏡像，圖案才不會反
                    n = (M.to_3x3() @ poly.normal)
                    if n.y > 0:
                        u = 1.0 - u
                    data[li].uv = (u, v)
                else:
                    # 非面板（扣環、半球）：推到貼圖外框的暗金屬區
                    data[li].uv = (0.02, 0.5)

        # --- 材質：接上貼圖 ---
        mat = me.materials[0] if me.materials else None
        if mat is None:
            mat = bpy.data.materials.new(name + "_mat")
            me.materials.append(mat)
        mat.use_nodes = True
        nt = mat.node_tree
        bsdf = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
        if bsdf is None:
            bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
            out = next((n for n in nt.nodes if n.type == "OUTPUT_MATERIAL"),
                       None) or nt.nodes.new("ShaderNodeOutputMaterial")
            nt.links.new(bsdf.outputs[0], out.inputs[0])

        tex = next((n for n in nt.nodes
                    if n.type == "TEX_IMAGE" and n.name == "EarringPanelTex"),
                   None)
        if tex is None:
            tex = nt.nodes.new("ShaderNodeTexImage")
            tex.name = "EarringPanelTex"
            tex.location = (bsdf.location.x - 400, bsdf.location.y)
        tex.image = img
        tex.interpolation = "Closest"

        uvmap = next((n for n in nt.nodes
                      if n.type == "UVMAP" and n.name == "EarringUV"), None)
        if uvmap is None:
            uvmap = nt.nodes.new("ShaderNodeUVMap")
            uvmap.name = "EarringUV"
            uvmap.location = (tex.location.x - 220, tex.location.y)
        uvmap.uv_map = UV_NAME
        nt.links.new(uvmap.outputs[0], tex.inputs[0])
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        # 金屬框＋玻璃：偏低粗糙、些微金屬感
        bsdf.inputs["Metallic"].default_value = 0.35
        bsdf.inputs["Roughness"].default_value = 0.42

        report[name] = {"panel_verts": len(panel),
                        "panel_h_cm": round(h * 100, 2),
                        "panel_w_cm": round((x1 - x0) * 100, 2),
                        "uv_layer": UV_NAME,
                        "mat": mat.name}
        log("done", name, report[name])

    print("EARDONE" + json.dumps(report, ensure_ascii=False) + "EAREND")


main()

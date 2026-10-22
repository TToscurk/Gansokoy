"""陰陽玉彩蛋：內部資產 godot/assets/shrine/陰陽玉.glb（＝D:/資產glb/博麗神社/陰陽玉.glb，MD5 相同；使用者 2026-10-22 指定）
轉成 shrine_v3 用的輕量版。只讀原檔，不改它。
  "D:/Blender/blender-5.2.1-windows-x64/blender.exe" -b --factory-startup --python godot/assets/shrine_v3/src/make_onmyoudama.py
輸出：
  models/onmyoudama.glb / .json   直徑 0.26 m（規格 §26：0.18–0.35）、原點＝底部中心、材質名 s3_onmyoudama、減面到 ~4k 三角形
  tex/gen/onmyoudama_base.png、onmyoudama_normal.png   原 4096² → 512²（拳頭大的小物）
材質（s3mat.gd s3_onmyoudama）：原檔粗糙度貼圖平均 ≈0.01（亮面塑膠感）→ 改固定 0.66、金屬 0（規格 §27：0.55–0.80、0、不發光）。
"""
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import s3b  # noqa: E402  （export_glb／dump_json：暫存檔＋改名重試）

GODOT = os.path.abspath(os.path.join(HERE, '..', '..', '..'))
SRC = os.path.join(GODOT, 'assets', 'shrine', '陰陽玉.glb')
SRC_TEX = os.path.join(GODOT, 'assets', 'shrine')
OUT_M = os.path.join(GODOT, 'assets', 'shrine_v3', 'models')
OUT_T = os.path.join(GODOT, 'assets', 'shrine_v3', 'tex', 'gen')
DIAM = 0.26
TARGET_TRIS = 4000
TEX = 512


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=SRC)
    obs = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    assert len(obs) == 1, obs
    ob = obs[0]
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    n0 = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    mod = ob.modifiers.new('dec', 'DECIMATE')
    mod.ratio = min(1.0, TARGET_TRIS / max(n0, 1))
    bpy.ops.object.modifier_apply(modifier=mod.name)
    # 尺寸：原檔直徑 1 m、底部在 y=0（Blender z=0）→ 縮成 0.26 m
    dims = ob.dimensions.copy()
    s = DIAM / max(dims.x, dims.y, dims.z)
    ob.scale = (ob.scale[0] * s, ob.scale[1] * s, ob.scale[2] * s)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    zmin = min((ob.matrix_world @ v.co).z for v in ob.data.vertices)
    for v in ob.data.vertices:
        v.co.z -= zmin
    for p in ob.data.polygons:
        p.use_smooth = True
    mat = ob.data.materials[0]
    mat.name = 's3_onmyoudama'
    n1 = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    os.makedirs(OUT_M, exist_ok=True)
    s3b.export_glb(os.path.join(OUT_M, 'onmyoudama.glb'), export_format='GLB', use_selection=True,
                   export_apply=True, export_image_format='NONE', export_yup=True)
    dims = ob.dimensions
    s3b.dump_json({'name': 'onmyoudama', 'tris': n1, 'src_tris': n0, 'source': 'res://assets/shrine/陰陽玉.glb',
                   'render_bounds': {'min': [-dims.x / 2, 0.0, -dims.y / 2], 'max': [dims.x / 2, dims.z, dims.y / 2]},
                   'collision': [], 'markers': {}},
                  os.path.join(OUT_M, 'onmyoudama.json'), ensure_ascii=False, indent=1)
    # 貼圖 4096 → 512
    os.makedirs(OUT_T, exist_ok=True)
    for kind, out in (('basecolor', 'onmyoudama_base.png'), ('normal', 'onmyoudama_normal.png')):
        p = os.path.join(SRC_TEX, '陰陽玉_yin+yang+sphere+3d+model_%s.jpg' % kind)
        img = bpy.data.images.load(p)
        img.scale(TEX, TEX)
        img.filepath_raw = os.path.join(OUT_T, out)
        img.file_format = 'PNG'
        img.save()
    print('[ONMYOUDAMA] tris %d -> %d  size %.3f x %.3f x %.3f m' % (n0, n1, dims.x, dims.y, dims.z))


if __name__ == '__main__':
    main()

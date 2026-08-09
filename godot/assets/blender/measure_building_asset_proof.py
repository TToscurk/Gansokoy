"""Print reproducible geometry metrics for the standalone building proof GLBs."""
import bpy
import glob
import json
import os

rows = []
for path in glob.glob(os.path.abspath("godot/assets/models/asset_proof_*.glb")):
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    bpy.ops.import_scene.gltf(filepath=path)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    points = [o.matrix_world @ v.co for o in meshes for v in o.data.vertices]
    material_names = sorted({m.name for o in meshes for m in o.data.materials if m})
    rows.append({
        "file": os.path.basename(path),
        "faces": sum(len(o.data.polygons) for o in meshes),
        "triangles": sum(len(o.data.loop_triangles) for o in meshes),
        "materials": len(material_names),
        "material_names": material_names,
        "dimensions_xyz_m": [round(max(p[i] for p in points) - min(p[i] for p in points), 3) for i in range(3)],
    })
print("METRICS=" + json.dumps(sorted(rows, key=lambda r: r["file"])))

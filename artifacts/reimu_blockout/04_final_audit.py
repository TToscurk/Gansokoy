import bpy, json, math
from pathlib import Path
ROOT=Path('D:/神社/shrine/artifacts/reimu_blockout')
scene=bpy.data.scenes['Reimu_Blockout_v001']
bpy.context.window.scene=scene
scene.camera=bpy.data.objects['Reimu_Front']
scene.render.filepath=str(ROOT/'front.png')
for area in bpy.context.screen.areas:
    if area.type=='VIEW_3D':
        area.spaces.active.region_3d.view_perspective='CAMERA'
        area.spaces.active.overlay.show_overlays=False
        area.spaces.active.shading.type='MATERIAL'
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'reimu_8head_v002.blend'),check_existing=False)
bpy.context.view_layer.update()
head=bpy.data.objects['Reimu_Head']
zs=[(head.matrix_world@v.co).z for v in head.data.vertices]
sole_z=min((bpy.data.objects['Reimu_Shoe_sole_'+s].matrix_world@v.co).z for s in ('L','R') for v in bpy.data.objects['Reimu_Shoe_sole_'+s].data.vertices)
ratio=(max(zs)-sole_z)/(max(zs)-min(zs))
assert abs(ratio-8)<0.0001
assert abs(max(zs)-sole_z-1.65)<0.0001
assert set(o.name for o in bpy.data.scenes['Scene'].objects)=={'Cube','Light','Camera'}
invalid=[]; base_vertices=0; base_faces=0; evaluated_tris=0
bounds=[]
deps=bpy.context.evaluated_depsgraph_get()
for ob in scene.objects:
    if ob.type=='MESH':
        base_vertices+=len(ob.data.vertices);base_faces+=len(ob.data.polygons)
        for v in ob.data.vertices:
            if not all(math.isfinite(c) for c in v.co):invalid.append(ob.name)
    if ob.type in ('MESH','CURVE'):
        ev=ob.evaluated_get(deps);me=ev.to_mesh();me.calc_loop_triangles()
        evaluated_tris+=len(me.loop_triangles)
        bounds.extend([(ob.matrix_world@v.co).z for v in me.vertices])
        ev.to_mesh_clear()
assert not invalid
# Blender refuses library reads of its current file. Verify a byte-identical
# temporary copy, inspect its datablock directory, then remove the copy.
import shutil, hashlib
verification_copy=ROOT/'_readback_verify.blend'
shutil.copyfile(ROOT/'reimu_8head_v002.blend',verification_copy)
saved_sha256=hashlib.sha256((ROOT/'reimu_8head_v002.blend').read_bytes()).hexdigest()
assert hashlib.sha256(verification_copy.read_bytes()).hexdigest()==saved_sha256
with bpy.data.libraries.load(str(verification_copy),link=False) as (stored,unused):
    stored_scenes=list(stored.scenes)
    stored_objects=list(stored.objects)
verification_copy.unlink()
assert scene.name in stored_scenes
assert all(o.name in stored_objects for o in scene.objects)
outputs=[]
for name in ('reimu_8head_v002.blend','front.png','side.png','back.png','reimu_turnaround_v002.jpg'):
    p=ROOT/name
    assert p.is_file() and p.stat().st_size>0
    outputs.append({'file':str(p),'bytes':p.stat().st_size})
report={'status':'ART_REVIEW','scene':scene.name,'saved_file':bpy.data.filepath,'head_height_m':max(zs)-min(zs),'sole_to_crown_m':max(zs)-sole_z,'head_ratio':ratio,'accessorized_bounds_z_m':[min(bounds),max(bounds)],'scene_object_count':len(scene.objects),'base_mesh_vertices':base_vertices,'base_mesh_faces':base_faces,'evaluated_triangles':evaluated_tris,'finite_coordinates':True,'saved_scene_verified':True,'original_scene_preserved':True,'outputs':outputs,'not_done':['facial sculpt and deformation topology','natural flowing hair silhouette','cloth thickness and collision audit','UVs and painted textures','rigging and skin weights','Godot import and performance validation']}
(ROOT/'measurements.json').write_text(json.dumps(report,indent=2,ensure_ascii=False),encoding='utf-8')
print(json.dumps(report,ensure_ascii=False))

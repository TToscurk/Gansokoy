"""Persist and measure the refined asset, with targeted geometric clearance probes."""
import bpy, json, math, shutil, hashlib
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
ROOT=Path('D:/神社/shrine/artifacts/reimu_blockout')
scene=bpy.context.scene
assert Path(bpy.data.filepath).name=='reimu_8head_v003_work.blend'
scene.name='Reimu_Refined_v003'
scene['review_status']='ART_REVIEW'
scene['scope']='Detailed character blockout; facial topology, hands, rigging and game optimization still pending'
scene.camera=bpy.data.objects['Reimu_Front']
scene.render.resolution_x=900;scene.render.resolution_y=1200
scene.render.filepath=str(ROOT/'v003_front.png')
for area in bpy.context.screen.areas:
    if area.type=='VIEW_3D':
        area.spaces.active.region_3d.view_perspective='CAMERA'
        area.spaces.active.shading.type='MATERIAL'
        area.spaces.active.overlay.show_overlays=False
bpy.context.view_layer.update()
deps=bpy.context.evaluated_depsgraph_get()
head=bpy.data.objects['Reimu_Head']
zs=[(head.matrix_world@v.co).z for v in head.data.vertices]
sole=min((bpy.data.objects['Reimu_Shoe_sole_'+side].matrix_world@v.co).z for side in ('L','R') for v in bpy.data.objects['Reimu_Shoe_sole_'+side].data.vertices)
ratio=(max(zs)-sole)/(max(zs)-min(zs))
assert abs(ratio-8)<.0001
assert abs(max(zs)-sole-1.65)<.0001
# Probe covered crown band, not the intentionally open face region.
cap=bpy.data.objects['Reimu_Hair_cap'];bvh=BVHTree.FromObject(cap,deps)
clear=[];misses=0
for v in head.data.vertices:
    p=head.matrix_world@v.co
    if not 1.615<p.z<1.64:continue
    direction=Vector((p.x,p.y-.013,0)).normalized()
    hit=bvh.ray_cast(p,direction,.08)
    if hit[0] is None:misses+=1
    else:clear.append(hit[3])
scalp={'region':'anatomical head vertices, 1.615 < Z < 1.640 m; outward horizontal ray into hair cap','hits':len(clear),'misses':misses,'min_clearance_m':min(clear) if clear else None}
# Probe evaluated calf vertices against the new sock in the covered ankle band.
ankles={}
for side in ('L','R'):
    leg=bpy.data.objects['Reimu_Leg_'+side];ev=leg.evaluated_get(deps);me=ev.to_mesh()
    sock=bpy.data.objects['Reimu_Sock_'+side];tree=BVHTree.FromObject(sock,deps)
    cx=-.091 if side=='L' else .091
    distances=[];miss=0
    for v in me.vertices:
        p=leg.matrix_world@v.co
        if not .11<p.z<.175:continue
        direction=Vector((p.x-cx,p.y-.012,0)).normalized()
        h=tree.ray_cast(p,direction,.05)
        if h[0] is None:miss+=1
        else:distances.append(h[3])
    ev.to_mesh_clear()
    ankles[side]={'region':'.110 < Z < .175 m calf vertices','hits':len(distances),'misses':miss,'min_clearance_m':min(distances) if distances else None}
meshverts=0;meshfaces=0;tris=0
for ob in scene.objects:
    if ob.type=='MESH':
        meshverts+=len(ob.data.vertices);meshfaces+=len(ob.data.polygons)
        assert all(math.isfinite(c) for v in ob.data.vertices for c in v.co)
    if ob.type in ('MESH','CURVE'):
        ev=ob.evaluated_get(deps);me=ev.to_mesh();me.calc_loop_triangles();tris+=len(me.loop_triangles);ev.to_mesh_clear()
assert set(o.name for o in bpy.data.scenes['Scene'].objects)=={'Cube','Light','Camera'}
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'reimu_8head_v003.blend'),check_existing=False)
copy=ROOT/'_v003_readback.blend';shutil.copyfile(ROOT/'reimu_8head_v003.blend',copy)
sha=hashlib.sha256((ROOT/'reimu_8head_v003.blend').read_bytes()).hexdigest()
assert hashlib.sha256(copy.read_bytes()).hexdigest()==sha
with bpy.data.libraries.load(str(copy),link=False) as (stored,unused):
    stored_scene_names=list(stored.scenes);stored_object_names=list(stored.objects)
copy.unlink()
assert scene.name in stored_scene_names
assert all(ob.name in stored_object_names for ob in scene.objects)
outputs=[]
for name in ('reimu_8head_v003.blend','v003_front.png','v003_side.png','v003_back.png','v003_face.png'):
    p=ROOT/name;assert p.is_file() and p.stat().st_size>0
    outputs.append({'path':str(p),'bytes':p.stat().st_size})
report={'version':'v003','status':'ART_REVIEW','scene':scene.name,'saved_file':bpy.data.filepath,'sha256':sha,'sole_to_crown_m':max(zs)-sole,'head_height_m':max(zs)-min(zs),'head_ratio':ratio,'object_count':len(scene.objects),'base_mesh_vertices':meshverts,'base_mesh_faces':meshfaces,'evaluated_triangles':tris,'covered_crown_probe':scalp,'covered_ankle_probes':ankles,'original_scene_preserved':True,'saved_datablocks_read_back':True,'outputs':outputs,'limits':['Targeted ray probes are not a complete cloth/body intersection audit','Face and body still separate meshes; no animation-ready retopology','Hands are still anatomical proxies','No UV paint, rigging or skin weights','Not imported or benchmarked in Godot','Reference likeness remains subject to user review']}
(ROOT/'measurements_v003.json').write_text(json.dumps(report,indent=2,ensure_ascii=False),encoding='utf-8')
print(json.dumps(report,ensure_ascii=False))

import bpy, json
from pathlib import Path
from mathutils import Vector
scene=bpy.data.scenes['Reimu_Blockout_v001']
bpy.context.window.scene=scene
head=bpy.data.objects['Reimu_Head']
zs=[(head.matrix_world@v.co).z for v in head.data.vertices]
sole_min=min((bpy.data.objects['Reimu_Shoe_sole_'+side].matrix_world@v.co).z for side in ('L','R') for v in bpy.data.objects['Reimu_Shoe_sole_'+side].data.vertices)
deps=bpy.context.evaluated_depsgraph_get()
triangles=0; vertices=0
for ob in scene.objects:
    if ob.type in ('MESH','CURVE'):
        ev=ob.evaluated_get(deps); me=ev.to_mesh()
        me.calc_loop_triangles(); triangles+=len(me.loop_triangles); vertices+=len(me.vertices)
        ev.to_mesh_clear()
report={'saved_file':bpy.data.filepath,'file_exists':Path(bpy.data.filepath).is_file(),'file_bytes':Path(bpy.data.filepath).stat().st_size,'scene':scene.name,'scene_object_count':len(scene.objects),'anatomical_crown_z_m':max(zs),'chin_z_m':min(zs),'sole_z_m':sole_min,'head_height_m':max(zs)-min(zs),'stature_m':max(zs)-sole_min,'head_ratio':(max(zs)-sole_min)/(max(zs)-min(zs)),'evaluated_vertices':vertices,'evaluated_triangles':triangles,'original_scene_objects':[(o.name,o.type) for o in bpy.data.scenes['Scene'].objects],'review_status':'ART_REVIEW','limitations':['separate anatomical pieces, not deformation-ready','face feature proxies require sculpt and retopology','no UV textures, rig, weights or animation','stature measured in shoes, excludes hair and bow']}
Path('D:/神社/shrine/artifacts/reimu_blockout/measurements.json').write_text(json.dumps(report,indent=2,ensure_ascii=False),encoding='utf-8')
print(json.dumps(report,ensure_ascii=False))
scene.camera=bpy.data.objects['Reimu_Front']
scene.render.filepath='D:/神社/shrine/artifacts/reimu_blockout/front.png'
bpy.ops.render.render(write_still=True)
print('FRONT_RENDER_COMPLETE')

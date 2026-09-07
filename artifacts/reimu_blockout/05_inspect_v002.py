import bpy, json
from pathlib import Path
scene=bpy.context.scene
assert scene.name=='Reimu_Blockout_v001', 'Unexpected active scene; stop before editing'
assert Path(bpy.data.filepath).name=='reimu_8head_v002.blend', 'Unexpected active file'
print(json.dumps({'file':bpy.data.filepath,'scene':scene.name,'object_count':len(scene.objects),'head':{'bounds':list(map(list,bpy.data.objects['Reimu_Head'].bound_box))},'eye_objects':[ob.name for ob in bpy.data.collections['Reimu_Face'].objects], 'hair_objects':[ob.name for ob in bpy.data.collections['Reimu_Hair'].objects]},ensure_ascii=False))
scene.camera=bpy.data.objects['Reimu_FaceClose']
scene.render.resolution_x=1000;scene.render.resolution_y=1000
scene.render.filepath='D:/神社/shrine/artifacts/reimu_blockout/v002_face_baseline.png'
bpy.ops.render.render(write_still=True)
scene.camera=bpy.data.objects['Reimu_Front']
scene.render.resolution_x=900;scene.render.resolution_y=1200
print('BASELINE_FACE_RENDERED')

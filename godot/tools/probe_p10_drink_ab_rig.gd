extends SceneTree
func _initialize():
 run.call_deferred()
func run():
 var n=load("res://characters/npc/chaya_f01/chaya_f01.tscn").instantiate()
 root.add_child(n)
 await process_frame
 var sk: Skeleton3D=n.find_child("GeneralSkeleton",true,false)
 var names=[]
 for i in sk.get_bone_count(): names.append(sk.get_bone_name(i))
 print("BONES ",names)
 for mi in sk.find_children("*","MeshInstance3D",true,false):
  var m: Mesh=mi.mesh
  var info=[]
  for s in m.get_surface_count():
   var a=m.surface_get_arrays(s)
   info.append([s,m.surface_get_material(s).resource_name if m.surface_get_material(s) else "",a[Mesh.ARRAY_VERTEX].size(),a[Mesh.ARRAY_BONES]!=null])
  print("MESH ",mi.name," skin=",mi.skin!=null," ",info)
 for b in ["Head","Neck","LeftEye","RightEye","Jaw","LeftShoulder","LeftUpperArm","LeftLowerArm","LeftHand","Hips"]:
  var i=sk.find_bone(b)
  if i>=0: print(b," ",sk.get_bone_global_rest(i).origin)
 quit()

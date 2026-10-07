extends SceneTree
func _initialize():
 run.call_deferred()
func run():
 var n=load("res://characters/npc/chaya_f01/chaya_f01.tscn").instantiate()
 root.add_child(n)
 await process_frame
 var ap: AnimationPlayer=n.player
 var lib=AnimationLibrary.new()
 lib.add_animation(&"drink",load("res://animations/npc_activity_p10/chaya_f01/drinking_a030_grounded.res"))
 ap.add_animation_library(&"act",lib)
 ap.play(&"act/drink")
 ap.speed_scale=0
 var sk=n.find_child("GeneralSkeleton",true,false)
 for t in [0.0,3.34,4.0,4.45,4.8]:
  ap.seek(t,true)
  for i in 2: await process_frame
  print("time ",t)
  for b in ["Head","LeftHand","LeftMiddleProximal","LeftIndexProximal","LeftMiddleDistal"]:
   print(b," ",sk.get_bone_global_pose(sk.find_bone(b)))
 quit()

extends SceneTree
## 非 headless Forward+、最新 village_v2、10:00。正式玩家 instance＋實際輸入／碰撞行走；不寫正式角色。
const VG=preload("res://tools/verify_village_v2_population.gd")
const CAPTURE_SIZE=Vector2i(1920,1080)
var v: Node3D
var player: CharacterBody3D
var cam: Camera3D
var helper: SceneTree
var sp: PhysicsDirectSpaceState3D
var outdir: String
var activity: Node3D
func _initialize():
 run.call_deferred()
func camera_at(vw: Dictionary):
 var d=vw.duplicate(true)
 var dx=float(vw.target[0])-float(vw.player[0])
 var dz=float(vw.target[1])-float(vw.player[1])
 d.player=[player.global_position.x,player.global_position.z]
 d.target=[player.global_position.x+dx,player.global_position.z+dz]
 cam.global_transform=helper._tps(v,sp,d)
func snap(name: String) -> int:
 for i in 8: await process_frame
 await RenderingServer.frame_post_draw
 var image=root.get_texture().get_image()
 if root.size!=CAPTURE_SIZE or image.get_size()!=CAPTURE_SIZE or absf(cam.get_camera_projection().determinant())<=1e-8:
  push_error("[POPSHOT] Invalid capture viewport: window %s, image %s"%[root.size,image.get_size()])
  return 2
 var err=image.save_png(outdir+name+".png")
 if err!=OK:
  push_error("[POPSHOT] PNG save failed: %s (%s)"%[name,err])
  return 3
 print("[POPSHOT] ",name," size ",image.get_size()," FOV ",cam.fov," player ",player.global_position," cam ",cam.global_position)
 return OK
func run():
 # Windows 會將含標題列的 1080p 視窗壓成 1061px client area；在審圖行程移除裝飾並鎖實際尺寸。
 root.borderless=true
 root.position=Vector2i.ZERO
 root.size=CAPTURE_SIZE
 for i in 8: await process_frame
 if root.size!=CAPTURE_SIZE:
  push_error("[POPSHOT] Cannot lock 1920x1080 viewport: %s"%root.size)
  quit(2)
  return
 var args=OS.get_cmdline_user_args()
 outdir=args[0]
 DirAccess.make_dir_recursive_absolute(outdir)
 v=(load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
 root.add_child(v)
 for nm in ["Debug","Portals","QuestAnchors"]:
  if v.has_node(nm): v.get_node(nm).visible=false
 for n in v.get_node("Districts").find_children("*ParcelLines*","",true,false): n.visible=false
 for i in 20: await process_frame
 sp=v.get_world_3d().direct_space_state
 for c in root.get_children():
  if c.has_method("set_hour"): c.set_hour(10.0); c.set_process(false)
 helper=VG.new()
 player=(load("res://characters/yoriichi/player_yoriichi.tscn") as PackedScene).instantiate()
 player.add_to_group("player")
 root.add_child(player)
 player.set_physics_process(false)
 var yaw=Node3D.new()
 root.add_child(yaw)
 player.set("input_yaw_node",yaw)
 cam=Camera3D.new()
 cam.fov=75.0
 cam.near=0.05
 cam.far=900.0
 root.add_child(cam)
 cam.make_current()
 var pop=v.get_node("Population/PopulationP10") as Node3D
 activity=v.get_node_or_null("Population/ActivityP10")
 if activity==null:
  activity=Node3D.new()
  activity.set_script(load("res://scripts/npc_activity_overlay.gd"))
  v.get_node("Population").add_child(activity)
 for i in 4: await process_frame
 var actors=pop.find_children("*","AnimatableBody3D",true,false)
 if "--baseline-walk" in args: activity.set_enabled(false)
 var views: Array=JSON.parse_string(FileAccess.get_file_as_string("res://tools/shot_village_v2_population_views.json"))
 for vw: Dictionary in views:
  if "--walk-only" in args and not vw.has("walk"): continue
  for b in actors: b.set_physics_process(false)
  var p=Vector2(vw.player[0],vw.player[1])
  player.global_position=Vector3(p.x,VG._ground(sp,p)+0.03,p.y)
  player.velocity=Vector3.ZERO
  var f=(Vector2(vw.target[0],vw.target[1])-p).normalized()
  yaw.rotation.y=atan2(-f.x,-f.y)
  player.rotation.y=yaw.rotation.y
  camera_at(vw)
  if vw.has("walk"):
   for b in actors: b.set_physics_process(String(b.get("mode"))=="patrol")
   player.set_physics_process(true)
   Input.action_press("move_forward")
   var start=player.global_position
   for k in 6:
    for j in 36:
     await physics_frame
     camera_at(vw)
    var capture_error: int=await snap("5_walk_through_%02d"%k)
    if capture_error!=OK:
     Input.action_release("move_forward")
     player.set_physics_process(false)
     helper.free()
     quit(capture_error)
     return
   Input.action_release("move_forward")
   player.set_physics_process(false)
   print("[POPWALK] travelled ",start.distance_to(player.global_position)," start ",start," end ",player.global_position)
  else:
   # 凍結相同 animation phase：BEFORE/AFTER は人口の表示だけを変える
   for b in actors:
    var ap=b.get_node("NPC").find_child("AnimationPlayer",true,false) as AnimationPlayer
    ap.speed_scale=0.0
   pop.visible=true
   var capture_error: int=await snap(String(vw.name)+"_after")
   if capture_error!=OK:
    helper.free()
    quit(capture_error)
    return
   activity.set_enabled(false)
   for b in actors: b.get_node("NPC").player.speed_scale=0.0
   capture_error=await snap(String(vw.name)+"_before")
   if capture_error!=OK:
    helper.free()
    quit(capture_error)
    return
   activity.set_enabled(true)
   for b in actors:
    var npc=b.get_node("NPC")
    (npc.find_child("AnimationPlayer",true,false) as AnimationPlayer).speed_scale=float(npc.get("speed_scale"))
 helper.free()
 quit()

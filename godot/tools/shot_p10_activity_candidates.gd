extends SceneTree
## Isolated rendered review; never saves world or frozen resources.
var world: Node3D
var cam: Camera3D
func _initialize():
 run.call_deferred()
func run():
 root.borderless=true
 root.position=Vector2i.ZERO
 root.size=Vector2i(1920,1080)
 world=load("res://maps/village_v2/village_v2.tscn").instantiate()
 root.add_child(world)
 for nm in ["Debug","Portals","QuestAnchors"]:
  if world.has_node(nm): world.get_node(nm).visible=false
 for n in world.get_node("Districts").find_children("*ParcelLines*","",true,false): n.visible=false
 for i in 20: await process_frame
 for n in root.get_children():
  if n.has_method("set_hour"): n.set_hour(10.0); n.set_process(false)
 var pop=world.get_node("Population/PopulationP10")
 for b in pop.find_children("*","AnimatableBody3D",true,false):
  b.set_physics_process(false)
  b.get_node("NPC").player.speed_scale=0.0
 cam=Camera3D.new()
 cam.near=0.04
 cam.far=900
 cam.fov=35
 root.add_child(cam)
 cam.make_current()
 var outdir=OS.get_cmdline_user_args()[0]
 DirAccess.make_dir_recursive_absolute(outdir)
 var snap=JSON.parse_string(FileAccess.get_file_as_string("res://data/village_v2_p10r3b_snapshot.json"))
 var manifest=[]
 for cid in ["shufu_f01","nunoya_f01","takigi_m01","sakanaya_m01","chaya_f01","setomono_f01","yakusou_f01","kozo_m01"]:
  var actor: Node3D
  for a in snap.actors:
   if a.model.strip_edges().replace('"','')==cid:
    actor=pop.get_node(a.node_path)
    break
  var npc=actor.get_node("NPC")
  var ap: AnimationPlayer=npc.player
  var old=ap.current_animation
  var files=DirAccess.get_files_at("res://animations/npc_activity_p10/"+cid)
  for f in files:
   if not f.ends_with("_grounded.res"): continue
   var an: Animation=load("res://animations/npc_activity_p10/%s/%s"%[cid,f])
   var lib=AnimationLibrary.new()
   lib.add_animation(&"candidate",an)
   if ap.has_animation_library(&"review"): ap.remove_animation_library(&"review")
   ap.add_animation_library(&"review",lib)
   ap.play(&"review/candidate")
   ap.speed_scale=0.0
   var key=cid+"__"+f.trim_suffix("_grounded.res")
   for view in 4:
    var angle=view*PI/2
    var offset=actor.global_basis*Vector3(sin(angle)*3.3,1.0,cos(angle)*3.3)
    cam.global_position=actor.global_position+offset
    cam.look_at(actor.global_position+Vector3(0,0.85,0))
    for phase in 8:
     ap.seek(an.length*phase/8.0,true)
     for i in 3: await process_frame
     await RenderingServer.frame_post_draw
     var image=root.get_texture().get_image()
     if image.get_size()!=Vector2i(1920,1080): quit(2); return
     var name="%s_v%d_p%d.png"%[key,view,phase]
     if image.save_png(outdir+name)!=OK: quit(3); return
     manifest.append({"file":name,"candidate":key,"view":view,"phase":phase,"time":an.length*phase/8.0,"actor":String(actor.get_path()),"clip_length":an.length,"camera":str(cam.global_transform)})
   print("[ACTCAND] captured ",key," length ",an.length)
  ap.play(old)
  ap.speed_scale=0.0
 var file=FileAccess.open(outdir+"capture.json",FileAccess.WRITE)
 file.store_string(JSON.stringify(manifest,"  "))
 quit(0)

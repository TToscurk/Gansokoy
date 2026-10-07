extends SceneTree
## ACT coverage: 16 identities, 7 private assignments, 5 types, evaluated animation and small prop placement.
const ACT=preload("res://scripts/npc_activity_overlay.gd")
const POP=preload("res://tools/verify_village_v2_population.gd")
const PL=preload("res://tools/village_v2_population_lib.gd")
var checks=[]
var fails=0
func _initialize(): run.call_deferred()
func check(label: String,ok: bool,detail=""):
 checks.append({"label":label,"pass":ok,"detail":detail})
 if not ok: fails+=1
 print("[ACT] ","PASS " if ok else "FAIL ",label," ",detail)
func valid(e: Dictionary) -> bool:
 var clip: Animation=e.lib.get_animation(StringName(e.slot))
 if clip==null or clip.length<0.5 or clip.get_track_count()<30: return false
 if e.sk.find_bone("Hips")<0 or e.sk.find_bone("LeftHand")<0: return false
 if not e.ap.is_playing() or e.ap.root_node!=NodePath("../Armature"): return false
 if e.prop!=null:
  if not e.prop.visible or absf(e.prop.global_basis.determinant())<1e-8: return false
  # Cup body centre (foot + half height along the cup axis) within 0.10 m of the knuckle bone: the fitted grip
  # (R3c Drink A/B 2026-10-07) puts the axis ~4.5 cm outside the palm skin, centre 0.088 m from LeftMiddleProximal.
  if e.prop_kind=="cup" and (e.prop.global_position+e.prop.global_basis.y*0.036).distance_to((e.sk.global_transform*e.sk.get_bone_global_pose(e.sk.find_bone("LeftMiddleProximal"))).origin)>0.10: return false
  if e.prop_kind=="crate":
   var palm=(e.sk.global_transform*e.sk.get_bone_global_pose(e.sk.find_bone("LeftMiddleProximal"))).origin
   var bounds: AABB=e.prop.mesh.get_aabb()
   var local=e.prop.global_transform.affine_inverse()*palm
   if local.distance_to(bounds.position+Vector3(bounds.size.x,bounds.size.y*0.5,bounds.size.z*0.5))>0.06: return false
 return true
func triangle_box(a: Vector3,b: Vector3,c: Vector3,box: AABB) -> bool:
 var center=box.get_center()
 var half=box.size*0.5
 a-=center; b-=center; c-=center
 var edges=[b-a,c-b,a-c]
 var axes=[Vector3.RIGHT,Vector3.UP,Vector3.BACK,(b-a).cross(c-a)]
 for edge in edges:
  for axis in [Vector3.RIGHT,Vector3.UP,Vector3.BACK]: axes.append(edge.cross(axis))
 for axis: Vector3 in axes:
  if axis.length_squared()<1e-14: continue
  var radius=half.dot(axis.abs())
  var av=a.dot(axis); var bv=b.dot(axis); var cv=c.dot(axis)
  if minf(av,minf(bv,cv))>radius or maxf(av,maxf(bv,cv)) < -radius: return false
 return true
func render_prop_hits(index,prop: MeshInstance3D) -> Array:
 var box=prop.mesh.get_aabb()
 # 10 mm controlled contact allowance; not an AABB-as-collision decision.
 var inset=Vector3.ONE*0.01/prop.global_basis.get_scale()
 box=AABB(box.position+inset,box.size-2*inset)
 var world_box=prop.global_transform*box
 var inv=prop.global_transform.affine_inverse()
 var hits=[]
 for item in index.items:
  if not item[0].intersects(world_box): continue
  var faces=index.faces(item)
  for i in range(0,faces.size(),3):
   if triangle_box(inv*faces[i],inv*faces[i+1],inv*faces[i+2],box):
    hits.append(item[3]); break
 return hits
func run():
 var args=OS.get_cmdline_user_args()
 var out="res://../docs/art_review/village_v2_p10_population/activity_r1/act_gate.json"
 for a in args:
  if a.begins_with("--out="): out=a.trim_prefix("--out=")
 var snapshot=JSON.parse_string(FileAccess.get_file_as_string("res://data/village_v2_p10r3b_snapshot.json"))
 var known=[]
 for a in snapshot.actors: known.append(a.node_path)
 var types={}
 var plan_ok=snapshot.count==16 and ACT.ASSIGN.size()==7
 for path in ACT.ASSIGN:
  var a=ACT.ASSIGN[path]
  types[a[0]]=true
  var clip: Animation=load(ACT.ROOT_ANIM+a[1]+"/"+a[2]+"_grounded.res")
  var good=path in known and clip!=null and clip.length>0.5 and clip.get_track_count()>30 and a[3] in ["idle","walk"]
  check("plan "+path,good)
  plan_ok=plan_ok and good
 check("scope16/7 assignments/5 types",plan_ok and types.size()==5,str(types.keys()))
 if not "--plan" in args:
  var world: Node3D=load("res://maps/village_v2/village_v2.tscn").instantiate()
  root.add_child(world)
  for i in 4: await process_frame
  var pop=world.get_node("Population/PopulationP10")
  var overlay=world.get_node_or_null("Population/ActivityP10")
  if overlay==null:
   overlay=Node3D.new()
   overlay.set_script(ACT)
   world.get_node("Population").add_child(overlay)
   for i in 4: await process_frame
  var actors=pop.find_children("*","AnimatableBody3D",true,false)
  check("runtime16/no duplicates",actors.size()==16 and overlay.entries.size()==7)
  var phases={}
  for e in overlay.entries: phases[e.path]=e.ap.current_animation_position
  for i in 24: await physics_frame
  var advanced=0
  for e in overlay.entries:
   if e.ap.is_playing() and absf(float(phases[e.path])-e.ap.current_animation_position)>0.05: advanced+=1
  check("real runtime animation advance",advanced==7,str(advanced))
  var excluded: Array[RID]=[]
  for b in actors:
   b.set_physics_process(false)
   excluded.append(b.get_rid())
  for e in overlay.entries:
   if e.has("body"): excluded.append(e.body.get_rid())
  var sp=world.get_world_3d().direct_space_state
  var render_index=PL.RenderIndex.new(world)
  var records=[]
  for e in overlay.entries:
   e.ap.play(StringName(e.slot))
   e.ap.speed_scale=0
   var errors=0
   var max_ground=0.0
   var clash_depth=0.0
   var support_gap=0.0
   var render_hits={}
   var rest={}
   for bn in ["LeftFoot","RightFoot","LeftToes","RightToes"]:
    rest[bn]=e.sk.get_bone_global_rest(e.sk.find_bone(bn)).origin.y
   var samples=1 if "--quick" in args else ceili(e.clip.length*30)
   for frame in samples:
    e.ap.seek(frame/30.0,true)
    for i in 2: await process_frame
    overlay.update_props()
    if not valid(e): errors+=1
    var lo=INF
    for bn in rest:
     lo=minf(lo,e.sk.get_bone_global_pose(e.sk.find_bone(bn)).origin.y-float(rest[bn]))
    max_ground=maxf(max_ground,absf(lo))
    if e.prop!=null:
     for path in render_prop_hits(render_index,e.prop): render_hits[path]=true
    if e.prop_kind=="crate" or e.prop_kind=="stool":
     var bounds: AABB=e.prop.mesh.get_aabb()
     var shape=BoxShape3D.new()
     var sc=e.prop.global_basis.get_scale()
     shape.size=bounds.size*sc
     var q=PhysicsShapeQueryParameters3D.new()
     q.shape=shape
     q.transform=Transform3D(e.prop.global_basis.orthonormalized(),e.prop.global_transform*bounds.get_center())
     q.exclude=excluded
     q.collision_mask=1
     var contacts=sp.collide_shape(q,32)
     if frame==0 and not contacts.is_empty():
      for hit in sp.intersect_shape(q,16):
       var collider=hit.collider
       var owner_id=collider.shape_find_owner(hit.shape)
       var shape_node=collider.shape_owner_get_owner(owner_id)
       print("[ACTCONTACT] ",e.path," ",shape_node.get_path()," ",shape_node.global_transform," bounds ",shape_node.shape.get_debug_mesh().get_aabb())
     for j in range(0,contacts.size(),2): clash_depth=maxf(clash_depth,contacts[j].distance_to(contacts[j+1]))
    if e.prop_kind=="stool" and frame==0:
     for x in [-0.18,0.18]:
      for z in [-0.13,0.13]:
       var pos=e.body.global_transform*Vector3(x,0,z)
       var q=PhysicsRayQueryParameters3D.create(pos+Vector3.UP*0.2,pos-Vector3.UP*0.3,1,excluded)
       var hit=sp.intersect_ray(q)
       support_gap=maxf(support_gap,99.0 if hit.is_empty() else absf(pos.y-hit.position.y))
   # Feet rest grounding and prop clearance are technical coverage, not garment certification.
   var ok=errors==0 and max_ground<0.012 and render_hits.is_empty() and support_gap<0.055
   records.append({"actor":e.path,"type":e.type,"samples30fps":samples,"invalid_frames":errors,"foot_rest_error_m":max_ground,"prop_coarse_proxy_depth_m":clash_depth,"prop_render_triangle_hits":render_hits.keys(),"stool_support_gap_m":support_gap})
   check("evaluated30fps "+e.path,ok,JSON.stringify(records[-1]))
  if "--negatives" in args:
   var e=overlay.entries[0]
   e.ap.play(StringName(e.slot)); e.ap.seek(0.0,true); overlay.update_props()
   e.ap.stop()
   check("negative stopped/Tpose",not valid(e))
   e.ap.play(StringName(e.slot))
   var old=e.ap.root_node
   e.ap.root_node=NodePath("../BadRoot")
   check("negative wrong animation root",not valid(e))
   e.ap.root_node=old
   var original=e.lib.get_animation(StringName(e.slot))
   var blank=Animation.new()
   e.lib.remove_animation(StringName(e.slot)); e.lib.add_animation(StringName(e.slot),blank)
   check("negative zero-track clip",not valid(e))
   var short=original.duplicate(true)
   short.length=0.0
   e.lib.remove_animation(StringName(e.slot)); e.lib.add_animation(StringName(e.slot),short)
   check("negative zero-length clip",not valid(e))
   e.lib.remove_animation(StringName(e.slot)); e.lib.add_animation(StringName(e.slot),original)
   for ep in overlay.entries:
    if ep.prop==null: continue
    ep.ap.play(StringName(ep.slot)); ep.ap.seek(0.0,true); overlay.update_props()
    var transform=ep.prop.global_transform
    ep.prop.global_position+=Vector3(2,0,0)
    if ep.prop_kind in ["crate","cup"]: check("negative detached "+ep.prop_kind,not valid(ep))
    ep.prop.global_transform=transform
    ep.prop.visible=false
    check("negative hidden "+ep.prop_kind,not valid(ep))
    ep.prop.visible=true
   var extra=AnimatableBody3D.new()
   extra.name="NegativePopulation17"
   extra.collision_layer=0
   pop.add_child(extra)
   check("negative added population",pop.find_children("*","AnimatableBody3D",true,false).size()!=snapshot.count)
   extra.queue_free()
  var f=FileAccess.open(out,FileAccess.WRITE)
  f.store_string(JSON.stringify({"status":"TECHNICAL_PASS" if fails==0 else "FAIL","checks":checks,"samples":records,"visual":"ART_REVIEW only; numerical foot/prop tests do not certify clothing"},"  "))
 else:
  var f=FileAccess.open(out,FileAccess.WRITE)
  f.store_string(JSON.stringify({"checks":checks,"fails":fails},"  "))
 quit(0 if fails==0 else 2)

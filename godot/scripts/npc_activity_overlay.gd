extends Node3D
## R3c private runtime overlay. Does not edit sealed actor, wrapper or resources.
const ROOT_ANIM="res://animations/npc_activity_p10/"
const ASSIGN={
 "Market/M2_shufu_f01": ["Talk","shufu_f01","talk_general_a030","idle"],
 "Market/M4_sakanaya_m01": ["Carry","sakanaya_m01","box_idle_a038","idle"],
 "Market/M5_setomono_f01": ["Sit","setomono_f01","sitting_breathing_a030","idle"],
 "Market/M7_kozo_m01": ["YouthShortStep","kozo_m01","light_walk_s100_a030","walk"],
 "MarketWest/W1_nunoya_f01": ["Talk","nunoya_f01","talk_general_a040","idle"],
 "MarketWest/W2_shufu_f01": ["Talk","shufu_f01","talk_general_a030","idle"],
 "MarketWest/W3_chaya_f01": ["Drink","chaya_f01","drinking_im1_a030","idle"]
}
## W3 tea-cup grip, in LeftHand axes: cup foot centre = LeftMiddleProximal + cup_grip, cup up-axis = cup_axis.
## R3c Drink A/B (2026-10-07): fitted by tools/fit_p10_drink_cup.py on CPU-skinned vertices of chaya_f01 ×
## drinking_im1_a030 — upright within ~15° while held low, leaning ~75° toward the face at the sip with the
## near rim ~1 cm from the lips, fingers pressing the wall ≤ 4 mm, never floating, no face / sleeve / torso
## vertex inside the cup. The old fixed grip (offset 0.020,0,0.022, axis −hand.x) sank the cup ~2 cm into
## the fingers and up to 3 cm into the face, and turned it past horizontal at the sip.
var cup_grip:=Vector3(0.04,-0.02,0.09)
var cup_axis:=Vector3(-0.9624,0.2634,-0.0662)
var entries: Array=[]
var population: Node3D
var enabled=true
# Only used by independent review captures; empty in normal runtime.
var review_only=""
func _ready():
 initialize.call_deferred()
func initialize():
 population=get_parent().get_node_or_null("PopulationP10")
 if population==null: push_error("[ACT] missing sealed population"); return
 for path in ASSIGN:
  var a=ASSIGN[path]
  var actor=population.get_node(path)
  var npc=actor.get_node("NPC")
  var ap: AnimationPlayer=npc.player
  var lib=ap.get_animation_library(&"").duplicate() as AnimationLibrary
  var baseline=lib.get_animation(StringName(a[3]))
  var clip: Animation=load(ROOT_ANIM+a[1]+"/"+a[2]+"_grounded.res")
  if clip==null or clip.get_track_count()<30: push_error("[ACT] invalid clip "+path); return
  lib.remove_animation(StringName(a[3]))
  lib.add_animation(StringName(a[3]),clip)
  ap.remove_animation_library(&"")
  ap.add_animation_library(&"",lib)
  var sk=npc.find_child("GeneralSkeleton",true,false) as Skeleton3D
  var e={"path":path,"type":a[0],"actor":actor,"npc":npc,"ap":ap,"sk":sk,"lib":lib,"baseline":baseline,"slot":a[3],"clip":clip,"prop":null,"prop_kind":""}
  if a[0]=="Carry":
   e.prop=mesh_prop("res://assets/village_v2/suzu_kit/mesh/sz_hako.res")
   e.prop_kind="crate"
  elif a[0]=="Sit":
   e.prop=mesh_prop("res://assets/village_v2/suzu_kit/mesh/sz_stool.res")
   e.prop_kind="stool"
   e.body=StaticBody3D.new()
   e.body.collision_layer=1
   e.body.collision_mask=0
   add_child(e.body)
   for i in 5:
    var cs=CollisionShape3D.new()
    cs.shape=BoxShape3D.new()
    e.body.add_child(cs)
  elif a[0]=="Drink":
   e.prop=tea_cup()
   add_child(e.prop)
   e.prop_kind="cup"
  entries.append(e)
  npc.play_clip(npc.animation,float(npc.start_time))
 update_props()
 print("[ACT] private overlay ",entries.size()," assignments; population ",population.find_children("*","AnimatableBody3D",true,false).size())
func mesh_prop(path: String) -> MeshInstance3D:
 var mi=MeshInstance3D.new()
 mi.mesh=load(path)
 mi.set_meta("reused_mesh",path)
 add_child(mi)
 return mi
func tea_cup() -> MeshInstance3D:
 # No standalone cup in market/street kit: small lathed ceramic, no new stall/kit changes.
 var st=SurfaceTool.new()
 st.begin(Mesh.PRIMITIVE_TRIANGLES)
 var rings=[Vector2(0.027,0),Vector2(0.036,0.072),Vector2(0.029,0.072),Vector2(0.021,0.012)]
 for j in 3:
  for i in 32:
   var aa=TAU*i/32.0
   var bb=TAU*(i+1)/32.0
   var p=[Vector3(sin(aa)*rings[j].x,rings[j].y,cos(aa)*rings[j].x),Vector3(sin(bb)*rings[j].x,rings[j].y,cos(bb)*rings[j].x),Vector3(sin(bb)*rings[j+1].x,rings[j+1].y,cos(bb)*rings[j+1].x),Vector3(sin(aa)*rings[j+1].x,rings[j+1].y,cos(aa)*rings[j+1].x)]
   for k in [0,1,2,0,2,3]: st.add_vertex(p[k])
 # closed bottom: outer foot disc (y 0) and inner floor (y 0.012) — the cup must not read as an open tube
 for disc in [[0.027,0.0],[0.021,0.012]]:
  for i in 32:
   var aa=TAU*i/32.0
   var bb=TAU*(i+1)/32.0
   st.add_vertex(Vector3(0,disc[1],0))
   st.add_vertex(Vector3(sin(aa)*disc[0],disc[1],cos(aa)*disc[0]))
   st.add_vertex(Vector3(sin(bb)*disc[0],disc[1],cos(bb)*disc[0]))
 st.generate_normals()
 var mi=MeshInstance3D.new()
 mi.mesh=st.commit()
 var mat=StandardMaterial3D.new()
 mat.albedo_color=Color(0.85,0.82,0.73)
 mat.roughness=0.4
 mat.cull_mode=BaseMaterial3D.CULL_DISABLED
 mi.material_override=mat
 mi.set_meta("new_small_prop_reason","No standalone cup mesh in frozen market/street kits")
 return mi
## Cup frame in hand space from its up-axis (the cup is rotationally symmetric; roll is arbitrary).
## Same construction as tools/fit_p10_drink_cup.py basis().
static func cup_basis(u: Vector3) -> Basis:
 u=u.normalized()
 var ref=Vector3(0,0,1) if absf(u.z)<0.9 else Vector3(1,0,0)
 var x=u.cross(ref).normalized()
 return Basis(x,u,x.cross(u))
func bone(e: Dictionary,nm: String) -> Transform3D:
 return e.sk.global_transform*e.sk.get_bone_global_pose(e.sk.find_bone(nm))
func update_props():
 for e in entries:
  if e.prop==null: continue
  e.prop.visible=enabled and (review_only.is_empty() or e.path==review_only)
  if e.prop_kind=="crate":
   var left=bone(e,"LeftMiddleProximal").origin
   var right=bone(e,"RightMiddleProximal").origin
   var x=(left-right).normalized()
   var front: Vector3=e.actor.global_basis.z
   var z=(front-x*front.dot(x)).normalized()
   var y=z.cross(x).normalized()
   var b=Basis(x,y,z)
   var bounds: AABB=e.prop.mesh.get_aabb()
   var scale_v=Vector3(left.distance_to(right),0.20,0.30)/bounds.size
   var center=(left+right)*0.5
   e.prop.global_transform=Transform3D(b*Basis.from_scale(scale_v),center-(b*Basis.from_scale(scale_v))*bounds.get_center())
  elif e.prop_kind=="stool":
   if not e.has("seat"):
    e.seat=bone(e,"Hips").origin-e.actor.global_basis.z*0.05-Vector3(0,0.11,0)
   var seat: Vector3=e.seat
   var bounds: AABB=e.prop.mesh.get_aabb()
   var height=seat.y-e.actor.global_position.y
   var s=Vector3(0.46,height,0.36)/bounds.size
   var b: Basis=e.actor.global_basis*Basis.from_scale(s)
   var base=Vector3(seat.x,e.actor.global_position.y,seat.z)
   e.prop.global_transform=Transform3D(b,base-b*Vector3(bounds.get_center().x,bounds.position.y,bounds.get_center().z))
   e.body.global_transform=Transform3D(e.actor.global_basis,base)
   e.body.collision_layer=1 if enabled else 0
   var shapes=e.body.get_children()
   shapes[0].shape.size=Vector3(0.46,0.04,0.36)
   shapes[0].position=Vector3(0,height-0.02,0)
   for i in 4:
    shapes[i+1].shape.size=Vector3(0.045,maxf(height-0.04,0.01),0.045)
    shapes[i+1].position=Vector3(-0.18 if i%2==0 else 0.18,(height-0.04)*0.5,-0.13 if i<2 else 0.13)
  elif e.prop_kind=="cup":
   var hand=bone(e,"LeftHand")
   var palm=bone(e,"LeftMiddleProximal").origin
   e.prop.global_transform=Transform3D(hand.basis*cup_basis(cup_axis),palm+hand.basis*cup_grip)
func _process(_dt):
 update_props()
func set_enabled(value: bool):
 enabled=value
 for e in entries:
  e.lib.remove_animation(StringName(e.slot))
  e.lib.add_animation(StringName(e.slot),e.clip if value else e.baseline)
  e.npc.play_clip(e.npc.animation,float(e.npc.start_time))
 update_props()

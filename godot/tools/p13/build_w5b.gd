extends SceneTree
## Production integration into the already mounted overlay. No host/P1/collision edits.
const W4 := preload("res://tools/village_v2_sando_w4_lib.gd")
const W5 := preload("res://tools/village_v2_sando_w5a_lib.gd")
const SA := preload("res://tools/village_v2_shrine_approach_lib.gd")
const UP := preload("res://tools/p13/w5b_upper_plan.gd")
func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	if not "--build" in OS.get_cmdline_user_args() or DisplayServer.get_name()=="headless":
		push_error("W5B requires explicit --build and rendering display; no write performed")
		quit(2)
		return
	var v: Node3D = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	var old := v.get_node_or_null(W4.NODE_NAME)
	if old:
		v.remove_child(old)
		old.free()
	root.add_child(v)
	for i in 5:
		await physics_frame
	var cl := SA.centerline()
	var H := SA.ramp_profile(v, cl)
	var st := SA.steps(cl, H)
	var rp := SA.ramp_points(st, H)
	var upper := UP.plan(cl, H, st, rp)
	if upper.is_empty():
		quit(2)
		return
	var sp := v.get_world_3d().direct_space_state
	var lamps: Array = []
	for e in SA.lantern_specs(cl,H,st,sp):
		if not lamps.has(float(e["s"])):
			lamps.append(float(e["s"]))
	var rest := W4.r8_without_range((v.get_node("ShrineApproachP10/StoneSteps") as MeshInstance3D).mesh as ArrayMesh,cl,Vector2i(744,UP.END))
	print("[W5B] original triangles %d removed %d remaining %d" % [int(rest.get_meta("total")),int(rest.get_meta("removed")),int(rest.get_meta("total"))-int(rest.get_meta("removed"))])
	var lower := W4.replan(cl,H,st,rp)
	var kr := W4.pilot_k_range(st)
	W4.flags = {}
	W5.integrated = true
	W5.scope_lo = kr.x
	W5.scope_hi = kr.y
	W5.setup(v,sp,cl)
	var ov := W4.build(cl,H,lower,[W4.outer_profile(sp,cl,kr,-1.0),W4.outer_profile(sp,cl,kr,1.0)],
		[W4.outer_profile(sp,cl,kr,-1.0,W4.U_FAR),W4.outer_profile(sp,cl,kr,1.0,W4.U_FAR)],lamps,rest)
	print("[W5B] lower %d elements; stats %s" % [lower.size(),str(W5.stats)])
	kr = Vector2i(UP.START,UP.END)
	W5.scope_lo = kr.x
	W5.scope_hi = kr.y
	W5.setup(v,sp,cl)
	W4.flags = {"mesh_seed":UP.SEED,"initial_y":UP.initial_y(st)}
	var top := W4.build(cl,H,upper,[W4.outer_profile(sp,cl,kr,-1.0),W4.outer_profile(sp,cl,kr,1.0)],
		[W4.outer_profile(sp,cl,kr,-1.0,W4.U_FAR),W4.outer_profile(sp,cl,kr,1.0,W4.U_FAR)],lamps,null)
	top.set_script(null)
	top.name = "W5Upper"
	ov.add_child(top)
	top.owner = ov
	for n in top.find_children("*","",true,false):
		# Do not expand imported vegetation instances; their PackedScene remains owner.
		if n.owner == top:
			n.owner = ov
	(top.get_node("W4Soil") as MeshInstance3D).material_override = (v.get_node("Terrain/MainTerrain") as MeshInstance3D).material_override
	print("[W5B] upper %d elements; s=%.2f..%.2f; stats %s" % [upper.size(),UP.START*0.05,UP.END*0.05,str(W5.stats)])
	W4.flags = {}
	W5.scope_lo = 744
	W5.scope_hi = 1284
	ov.set_meta("integrated_range",Vector2(37.2,UP.END*0.05))
	var wind := SA.winding_bad(ov)
	var ps := PackedScene.new()
	var ok: bool = int(wind[0]) == 0 and ov.find_children("*","CollisionObject3D",true,false).is_empty()
	if ok:
		ok = ps.pack(ov)==OK and ResourceSaver.save(ps,W4.OUTPUT,ResourceSaver.FLAG_COMPRESS)==OK
	if ok:
		var saved := (ResourceLoader.load(W4.OUTPUT,"",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
		ok = saved.get_node_or_null("W5Upper/W4Steps") != null
		saved.free()
	print("[W5B] save+readback %s winding %s collision bodies %d" % [str(ok),str(wind),ov.find_children("*","CollisionObject3D",true,false).size()])
	ov.free()
	quit(0 if ok else 1)

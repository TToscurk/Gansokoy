extends SceneTree
## P13 W1 Architecture Pilot 審圖撮影（非 headless、Forward+、10:00）。同一プロセス・同一鏡位で overlay の enabled を切替えて Before／After。
##   godot --path . --script res://tools/p13/shot_arch_pilot.gd -- <outdir/>
const AL := preload("res://tools/village_v2_arch_pilot_lib.gd")

var cam: Camera3D
var v: Node3D
var ov: Node3D
var sp: PhysicsDirectSpaceState3D

func _init() -> void:
	_run.call_deferred()

func _g(x: float, z: float) -> float:
	var hit := sp.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x, 80, z), Vector3(x, -40, z)))
	return float(hit.position.y) if not hit.is_empty() else 0.8

func _shot(path: String) -> void:
	for i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(path)
	print("SHOT ", path)

func _pair(outdir: String, nm: String, eye: Vector3, at: Vector3, fov := 60.0) -> void:
	cam.fov = fov
	cam.global_transform = Transform3D(Basis(), eye).looking_at(at, Vector3.UP)
	ov.call("apply", false)
	await _shot(outdir + nm + "_before.png")
	ov.call("apply", true)
	await _shot(outdir + nm + "_after.png")

func _run() -> void:
	var outdir: String = OS.get_cmdline_user_args()[0]
	DisplayServer.window_set_size(Vector2i(1600, 900))
	v = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	root.add_child(v)
	for nm in ["Debug", "Portals", "QuestAnchors"]:
		if v.has_node(nm):
			v.get_node(nm).visible = false
	ov = v.get_node_or_null(AL.NODE_NAME) as Node3D
	if ov == null:
		ov = (ResourceLoader.load(AL.OUTPUT, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
		v.add_child(ov)
	await process_frame
	for n in root.find_children("*", "", true, false):
		if n.has_method("set_hour"):
			n.call("set_hour", 10.0)
	cam = Camera3D.new()
	cam.far = 900.0
	root.add_child(cam)
	cam.make_current()
	for i in 30:
		await process_frame
	sp = v.get_world_3d().direct_space_state
	# ① 主街 北→南（review_start main_street と同じ視線、TPS 眼高＋肩越し 2.6 m）
	var a := Vector2(241.0, 44.0)
	await _pair(outdir, "01_main_south", Vector3(a.x, _g(a.x, a.y) + 2.6, a.y), Vector3(262.0, _g(262, -20) + 2.0, -20.0))
	# ② 反方向 南→北
	var b := Vector2(266.0, -14.0)
	await _pair(outdir, "02_main_north", Vector3(b.x, _g(b.x, b.y) + 2.6, b.y), Vector3(242.0, _g(242, 44) + 2.0, 44.0))
	# ③ やや高い視角（屋根の輪廓）
	var c := Vector2(232.0, 46.0)
	await _pair(outdir, "03_roofs_high", Vector3(c.x, _g(c.x, c.y) + 14.0, c.y), Vector3(258.0, _g(258, 12) + 3.0, 12.0), 55.0)
	# ④ 細部：代表 3 棟（正面 9 m、眼高）
	var recs := AL.greybox_recs()
	for id: String in ["B_P_MKT_005", "B_P_MKT_010", "B_P_MKT_006"]:
		var body := v.get_node("Districts/%s/Buildings/%s" % [recs[id]["district"], id]) as Node3D
		var cen := body.global_position
		var fd := Vector2(recs[id]["front_dir"][0], recs[id]["front_dir"][1]).normalized()
		var e := Vector2(cen.x, cen.z) + fd * 10.0
		await _pair(outdir, "04_detail_" + id, Vector3(e.x, _g(e.x, e.y) + 1.7, e.y), Vector3(cen.x, cen.y + 3.0, cen.z), 58.0)
	quit(0)

extends SceneTree
## P11 R2B TASK02：道路の層を低い視点で撮る（非 headless、Forward+、10:00、只讀）。
##   godot --path . --script res://tools/p11r2b/shot_road_layers.gd -- <outdir/> [tag]
## 各機位 V0＝現行、R＝Roads 全体を隠す（地形の道路塗りだけ）。
const VIEWS := [
	# name, cam xyz, look xyz
	["main_low", Vector3(245.3, 0.0, 46.0), Vector3(245.3, 0.0, 30.0), 0.25, 0.9],
	["main_side", Vector3(250.0, 0.0, 42.4), Vector3(243.0, 0.0, 42.4), 0.12, 0.3],
	["riverside_low", Vector3(498.0, 0.0, -95.5), Vector3(506.0, 0.0, -95.5), 0.25, 0.8],
	["rivernorth_low", Vector3(375.0, 0.0, -200.7), Vector3(385.0, 0.0, -200.7), 0.25, 0.8],
	["crossmid_low", Vector3(327.0, 0.0, -29.9), Vector3(335.0, 0.0, -29.9), 0.2, 0.7],
	["hillfoot_low", Vector3(358.0, 0.0, -131.0), Vector3(366.0, 0.0, -131.0), 0.25, 1.2],
	["lane_low", Vector3(276.6, 0.0, -83.0), Vector3(276.6, 0.0, -92.0), 0.2, 0.6],
]
var v: Node3D
var cam: Camera3D

func _init() -> void:
	_run.call_deferred()

func _gy(x: float, z: float) -> float:
	var sp := v.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 120.0, z), Vector3(x, -40.0, z))
	var ex: Array[RID] = []
	for k in 16:
		q.exclude = ex
		var hit := sp.intersect_ray(q)
		if hit.is_empty():
			return 0.0
		if String((hit.collider as Node).name).begins_with("TerrainCollision"):
			return hit.position.y
		ex.append(hit.rid)
	return 0.0

func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var outdir: String = a[0]
	var tag: String = a[1] if a.size() > 1 else "x"
	DirAccess.make_dir_recursive_absolute(outdir)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	v = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	root.add_child(v)
	for nm in ["Debug", "Portals", "QuestAnchors"]:
		if v.has_node(nm):
			v.get_node(nm).visible = false
	for n in v.get_node("Districts").find_children("*ParcelLines*", "", true, false):
		n.visible = false
	await process_frame
	for c in root.get_children():
		if c.has_method("set_hour"):
			c.set_hour(10.0)
	cam = Camera3D.new()
	cam.near = 0.03
	cam.far = 1200.0
	cam.fov = 70.0
	root.add_child(cam)
	cam.make_current()
	for i in 30:
		await process_frame
	for vw in VIEWS:
		var cp: Vector3 = vw[1]
		var lk: Vector3 = vw[2]
		cp.y = _gy(cp.x, cp.z) + float(vw[3])
		lk.y = _gy(lk.x, lk.z) + float(vw[4])
		cam.global_transform = Transform3D(Basis(), cp).looking_at(lk, Vector3.UP)
		for variant in ["V0", "R"]:
			(v.get_node("Roads") as Node3D).visible = variant == "V0"
			for i in 12:
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(outdir + "%s_%s_%s.png" % [tag, vw[0], variant])
		(v.get_node("Roads") as Node3D).visible = true
	print("[ROADSHOT] done")
	quit(0)

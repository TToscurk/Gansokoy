extends SceneTree
## P11 R2C A 審圖（非 headless、只讀）：修正した道路の TPS（目線 1.7 m・後方 4 m・高さ 2.2 m）＋低視角（0.25 m）。
##   godot --path . --script res://tools/p11r2c/shot_road_tps.gd -- <outdir/> <tag>
const VIEWS := [
	# name, 立ち位置 xz, 見る方向の点 xz
	["riverside", Vector2(496.0, -95.5), Vector2(506.0, -95.5)],
	["rivernorth", Vector2(372.0, -200.7), Vector2(385.0, -200.7)],
	["crossmid", Vector2(325.0, -29.9), Vector2(336.0, -29.9)],
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

func _shot(path: String, eye: Vector3, at: Vector3) -> void:
	cam.global_transform = Transform3D(Basis(), eye).looking_at(at, Vector3.UP)
	for i in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)

func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var outdir: String = a[0]
	var tag: String = a[1]
	DirAccess.make_dir_recursive_absolute(outdir)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	v = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	root.add_child(v)
	for nm in ["Debug", "Portals", "QuestAnchors"]:
		if v.has_node(nm):
			v.get_node(nm).visible = false
	await process_frame
	for c in root.get_children():
		if c.has_method("set_hour"):
			c.set_hour(10.0)
	cam = Camera3D.new()
	cam.near = 0.03
	cam.fov = 70.0
	root.add_child(cam)
	cam.make_current()
	for i in 30:
		await process_frame
	for vw in VIEWS:
		var p: Vector2 = vw[1]
		var t: Vector2 = vw[2]
		var f := (t - p).normalized()
		var gp := _gy(p.x, p.y)
		var gt := _gy(t.x, t.y)
		var player := Vector3(p.x, gp + 1.7, p.y)
		await _shot(outdir + "%s_%s_tps.png" % [tag, vw[0]], player - Vector3(f.x, 0, f.y) * 4.0 + Vector3.UP * 0.5, Vector3(t.x, gt + 0.8, t.y))
		await _shot(outdir + "%s_%s_low.png" % [tag, vw[0]], Vector3(p.x, gp + 0.25, p.y), Vector3(t.x, gt + 0.6, t.y))
	print("[RTPS] done ", tag)
	quit(0)

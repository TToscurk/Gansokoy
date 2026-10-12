extends SceneTree
## P13 W1B 補充：①實走停止點の碰撞體特定（overlay ON／OFF 両方）②MKT_006 工坊の撮り直し（TPS を道の中央から＋正面眼高の別カメラ）
##   godot --path . --script res://tools/p13/shot_w1b_fix.gd -- <outdir/>
const AL := preload("res://tools/village_v2_arch_pilot_lib.gd")

var main: Node
var player: CharacterBody3D
var ov: Node3D
var out := ""


func _init() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await _frames(12)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + name + ".png")
	print("SHOT ", name)


func _ground(x: float, z: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 60, z), Vector3(x, -30, z))
	q.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	return float(hit.position.y) if not hit.is_empty() else 0.0


func _probe(tag: String, p: Vector2) -> void:
	var cap := CapsuleShape3D.new()
	cap.radius = 0.45
	cap.height = 1.7
	var qp := PhysicsShapeQueryParameters3D.new()
	qp.shape = cap
	qp.transform = Transform3D(Basis.IDENTITY, Vector3(p.x, _ground(p.x, p.y) + 0.85 + 0.36, p.y))
	qp.exclude = [player.get_rid(), (main.get("map_root") as Node).get_node("Collision/TerrainCollision").get_rid()]
	var hits: Array = []
	for r: Dictionary in player.get_world_3d().direct_space_state.intersect_shape(qp, 8):
		hits.append(String((main.get("map_root") as Node).get_path_to(r["collider"] as Node)))
	print("[PROBE] %s (%.1f,%.1f)：%s" % [tag, p.x, p.y, str(hits)])


func _run() -> void:
	out = OS.get_cmdline_user_args()[0]
	DisplayServer.window_set_size(Vector2i(1600, 900))
	var sf := root.get_node_or_null("/root/StoryFlags")
	if sf:
		sf.set_flag("woke_in_trail", true)
		sf.set_flag("met_reimu", true)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(60)
	main.call("load_map", "village_v2", "")
	await _frames(90)
	player = main.get("player")
	var mr: Node3D = main.get("map_root")
	for nm in ["Debug", "Portals", "QuestAnchors"]:
		var n := mr.get_node_or_null(nm) as Node3D
		if n:
			n.visible = false
	for cl in root.find_children("*", "CanvasLayer", true, false):
		(cl as CanvasLayer).visible = false
	var dn := root.get_node_or_null("/root/DayNight")
	if dn:
		dn.call("set_hour", 10.0)
		dn.set("flowing", false)
	ov = (load(AL.OUTPUT) as PackedScene).instantiate()
	mr.add_child(ov)
	await _frames(5)
	player.global_position = Vector3(240, _ground(240, 44) + 0.1, 44)
	await physics_frame
	for on in [true, false]:
		ov.set("enabled", on)
		await physics_frame
		for p in [Vector2(255.9, 7.0), Vector2(255.4, 9.5), Vector2(255.0, 12.0)]:
			_probe("overlay %s" % ("ON" if on else "OFF"), p)
	# MKT_006：道の中央（建物中心＋正面方向 10.5 m）から TPS
	var c := Vector2(260.2, 14.3)
	var f := Vector2(-0.9485, -0.3168)
	var at := c + f * 10.5
	player.velocity = Vector3.ZERO
	player.global_position = Vector3(at.x, _ground(at.x, at.y) + 0.05, at.y)
	player.call("snap_yaw", atan2(-(c.x - at.x), -(c.y - at.y)))
	await _frames(45)
	ov.set("enabled", false)
	await _shot("05_tps_MKT_006_workshop_before")
	ov.set("enabled", true)
	await _shot("05_tps_MKT_006_workshop_after")
	# 正面眼高 1.6 m・建物前 8 m の別カメラ（店先の奥＝作業台が見える高さ）
	var cam := Camera3D.new()
	cam.fov = 55.0
	root.add_child(cam)
	cam.make_current()
	var e := c + f * 8.0
	var by := (mr.get_node("Districts/Market/Buildings/B_P_MKT_006") as Node3D).global_position.y
	cam.global_transform = Transform3D(Basis(), Vector3(e.x, _ground(e.x, e.y) + 1.6, e.y)).looking_at(Vector3(c.x, by + 2.4, c.y), Vector3.UP)
	player.visible = false
	ov.set("enabled", false)
	await _shot("05b_detail_MKT_006_before")
	ov.set("enabled", true)
	await _shot("05b_detail_MKT_006_after")
	print("[DONE]")
	quit(0)

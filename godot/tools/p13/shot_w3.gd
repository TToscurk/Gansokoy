extends SceneTree
## P13 W3：土渠樣本（T0、伏越し出口→末端）の根因計測＋同鏡位 Before／診断／After、MKT_018 接地の局部確認。
## 非 headless、Forward+、10:00、正式 main.tscn・village_v2.tscn（場景・封存ファイルは書かない；樣本は記憶體内で適用）。
##   godot --path . --script res://tools/p13/shot_w3.gd -- <outdir/>
const CS := preload("res://tools/village_v2_canal_sample_lib.gd")

var main: Node
var player: CharacterBody3D
var mr: Node3D
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


func _terrain_h(x: float, z: float) -> float:
	var tc := mr.get_node("Collision/TerrainCollision") as CollisionObject3D
	var sp := player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 60, z), Vector3(x, -30, z))
	q.collide_with_bodies = true
	var ex: Array[RID] = [player.get_rid()]
	for i in 12:
		q.exclude = ex
		var hit := sp.intersect_ray(q)
		if hit.is_empty():
			return NAN
		if hit.rid == tc.get_rid():
			return float(hit.position.y)
		ex.append(hit.rid)
	return NAN


func _ground_any(x: float, z: float) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 60, z), Vector3(x, -30, z))
	q.exclude = [player.get_rid()]
	return player.get_world_3d().direct_space_state.intersect_ray(q)


func _place(at: Vector2, look: Vector2) -> void:
	player.velocity = Vector3.ZERO
	var h := _terrain_h(at.x, at.y)
	player.global_position = Vector3(at.x, (h if not is_nan(h) else 0.5) + 0.05, at.y)
	player.call("snap_yaw", atan2(-(look.x - at.x), -(look.y - at.y)))
	await _frames(45)


func _triple(tag: String) -> void:
	# ① TPS（玩家相機）：FarmPath_5 東から T0 沿いに南西を見る
	await _place(Vector2(336.5, 66.0), Vector2(327.0, 57.0))
	await _shot("01_tps_" + tag)
	var cam := Camera3D.new()
	cam.far = 900.0
	cam.fov = 55.0
	root.add_child(cam)
	cam.make_current()
	player.visible = false
	# ② 低視角：渠岸と地形の交界（眼高 0.45 m、堤の外 2.5 m から渠沿いに）
	cam.global_transform = Transform3D(Basis(), Vector3(331.2, 0.75, 63.0)).looking_at(Vector3(327.0, 0.35, 58.0), Vector3.UP)
	await _shot("02_low_" + tag)
	# ③ 稍高視角：区間全体の輪郭
	cam.global_transform = Transform3D(Basis(), Vector3(343.0, 11.0, 66.0)).looking_at(Vector3(329.0, 0.2, 60.0), Vector3.UP)
	await _shot("03_high_" + tag)
	player.visible = true
	cam.queue_free()
	await _frames(2)
	var pc := player.find_child("Camera3D", true, false) as Camera3D
	if pc:
		pc.make_current()


## MKT_018 前：玩家の実接地（is_on_floor・床の collider・足元短距離 ray）と、Wave 2 の walk 計測（y=60 から下向き＝最初の hit）を同じ点で比較
func _mkt018() -> void:
	var c := Vector2(233.9, 34.0)
	var f := Vector2(0.9487, 0.3162)
	var side := Vector2(-0.3162, 0.9487)
	var a := c + f * 4.5 + side * 3.0
	var b := c + f * 4.5 - side * 3.0
	await _place(a, b)
	var worst := 0.0
	var rec := ""
	Input.action_press("move_forward")
	for fr in 60 * 10:
		var p := Vector2(player.global_position.x, player.global_position.z)
		if p.distance_to(b) < 1.0:
			break
		if fr % 6 == 0:
			var d := b - p
			player.call("snap_yaw", atan2(-d.x, -d.y))
		await physics_frame
		if fr % 10 == 0:
			var hit := _ground_any(p.x, p.y)
			var old_dy := absf(player.global_position.y - float(hit.position.y)) if not hit.is_empty() else 0.0
			if old_dy > worst:
				var sp := player.get_world_3d().direct_space_state
				var q := PhysicsRayQueryParameters3D.create(player.global_position + Vector3(0, 0.3, 0), player.global_position + Vector3(0, -0.5, 0))
				q.exclude = [player.get_rid()]
				var near := sp.intersect_ray(q)
				var th := _terrain_h(p.x, p.y)
				worst = old_dy
				rec = "player(%.2f,%.3f,%.2f) on_floor=%s floor_collider=%s；Wave2 計測 ray（y60→）の hit＝%s y=%.3f（差 %.2f）；足元 0.3/−0.5 m ray＝%s y=%s；地形 TerrainCollision y=%.3f（足元−地形 %.3f）" % [
					player.global_position.x, player.global_position.y, player.global_position.z, player.is_on_floor(),
					String(mr.get_path_to(player.get_last_slide_collision().get_collider() as Node)) if player.get_slide_collision_count() > 0 and player.get_last_slide_collision().get_collider() is Node else "-",
					String(mr.get_path_to(hit.collider as Node)) if not hit.is_empty() else "-", float(hit.position.y) if not hit.is_empty() else NAN, old_dy,
					String(mr.get_path_to(near.collider as Node)) if not near.is_empty() else "なし", ("%.3f" % float(near.position.y)) if not near.is_empty() else "-",
					th, player.global_position.y - th]
	Input.action_release("move_forward")
	print("[MKT018] 最大差 %.2f m の点：%s" % [worst, rec])


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
	mr = main.get("map_root")
	for nm in ["Debug", "Portals", "QuestAnchors"]:
		var nd := mr.get_node_or_null(nm) as Node3D
		if nd:
			nd.visible = false
	for cl in root.find_children("*", "CanvasLayer", true, false):
		(cl as CanvasLayer).visible = false
	var dn := root.get_node_or_null("/root/DayNight")
	if dn:
		dn.call("set_hour", 10.0)
		dn.set("flowing", false)
	# 計測：樣本窓の土渠頂点
	var st := CS.earth_stats(mr)
	print("[CANAL] 樣本窓の土渠頂点 %d、法線下向き %d、急斜面(ny<0.7) %d、外法(|u|>0.7) %d、重み（COLOR|UV2）の種類 %s" % [st["verts"], st["normal_down"], st["steep_ny_lt_0.7"], st["outer_slope_verts"], str(st["distinct_weights"])])
	var em := CS._find(mr, "earth")
	var gm := em.material_override as ShaderMaterial
	print("[CANAL] 土渠材質 shader=%s ground_k=%s use_vertex_weights=%s（地形と同 shader）" % [gm.shader.resource_path, gm.get_shader_parameter("ground_k"), gm.get_shader_parameter("use_vertex_weights")])
	var wm := CS._find(mr, "water")
	var wmat := wm.material_override as ShaderMaterial
	print("[CANAL] 水面 tint=%s clarity=%s rough=%s" % [wmat.get_shader_parameter("water_tint"), wmat.get_shader_parameter("clarity"), wmat.get_shader_parameter("rough_base")])
	# Before
	await _triple("before")
	# 診断：重みを全部「草」に（幾何は同じ）→ 黒い帯が消えれば原因は重み（材質）、残れば幾何・陰影
	var k := CS.apply(mr, "diag_grass")
	await _place(Vector2(336.5, 66.0), Vector2(327.0, 57.0))
	await _shot("diag_tps_weights_all_grass")
	CS.restore(mr, k)
	# After
	var k2 := CS.apply(mr, "fix")
	print("[CANAL] 適用：土渠頂点 %d、樣本水面三角形 %d" % [int(k2.get("earth_verts", 0)), int(k2.get("water_tris", 0))])
	await _triple("after")
	CS.restore(mr, k2)
	await _mkt018()
	print("[DONE]")
	quit(0)

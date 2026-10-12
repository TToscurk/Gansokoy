extends SceneTree
## P13 W2 審圖撮影＋局部實測（非 headless、Forward+、10:00、正式 main.tscn・正式 village_v2.tscn；overlay なし）。
##   godot --path . --script res://tools/p13/shot_w2.gd -- <outdir/>
## ① TPS：主街 正／反・MKT_010 住居・MKT_006 工房・MKT_018・農家  ② 高視角：屋根・農家
## ③ MKT_018 相機實測：玩家を棟の周り 8 点に置き、相機を 12 方向へ回して相機が建物外殻（Kit LOD0 AABB）内に入る回数
## ④ 實走：主街 39 棟の前／FarmPath_5 → 渡し板 → A2 前 → A1 戸口
var main: Node
var player: CharacterBody3D
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


func _place(at: Vector2, look: Vector2) -> void:
	player.velocity = Vector3.ZERO
	player.global_position = Vector3(at.x, _ground(at.x, at.y) + 0.05, at.y)
	player.call("snap_yaw", atan2(-(look.x - at.x), -(look.y - at.y)))
	await _frames(45)


func _walk(label: String, pts: Array) -> int:
	await _place(pts[0], pts[1])
	var stuck := 0
	var maxdy := 0.0
	var fails: Array = []
	for i in range(1, pts.size()):
		var tgt: Vector2 = pts[i]
		var last := Vector2(player.global_position.x, player.global_position.z)
		var still := 0
		var ok := false
		Input.action_press("move_forward")
		for f in 60 * 30:
			var p := Vector2(player.global_position.x, player.global_position.z)
			var d := tgt - p
			if d.length() < 1.2:
				ok = true
				break
			if f % 6 == 0:
				player.call("snap_yaw", atan2(-d.x, -d.y))
			await physics_frame
			var np := Vector2(player.global_position.x, player.global_position.z)
			still = still + 1 if np.distance_to(last) < 0.01 else 0
			last = np
			if f % 20 == 0:
				maxdy = maxf(maxdy, absf(player.global_position.y - _ground(np.x, np.y)))
			if still > 90 or player.global_position.y < -20:
				break
		Input.action_release("move_forward")
		if not ok:
			stuck += 1
			fails.append("→%s 停止 @(%.1f,%.1f)" % [tgt, player.global_position.x, player.global_position.z])
	print("[WALK] %s：区間 %d、未到達 %d、足元−地面 最大 %.2f m %s" % [label, pts.size() - 1, stuck, maxdy, str(fails)])
	return stuck


func _cam_test(mr: Node3D) -> void:
	var body := mr.get_node("Districts/Market/Buildings/B_P_MKT_018") as Node3D
	var kit := body.get_node("Kit") as Node3D
	var ab := AABB()
	var first := true
	for mi: MeshInstance3D in kit.get_node("LOD0").get_children():
		if mi.mesh == null:
			continue
		var a := mi.transform * mi.mesh.get_aabb()
		ab = a if first else ab.merge(a)
		first = false
	var w := float(body.get_meta("width_m"))
	var d := float(body.get_meta("depth_m"))
	var cam := get_root().get_camera_3d()
	var bx := body.global_transform
	var inside := 0
	var n := 0
	var worst := ""
	# 棟の周り 8 点（正面・側面・角、壁から 1.0 m）
	var pts: Array = []
	for sx in [-1.0, 0.0, 1.0]:
		for sz in [-1.0, 0.0, 1.0]:
			if sx == 0.0 and sz == 0.0:
				continue
			pts.append(Vector3(sx * (w * 0.5 + 1.0), 0, sz * (d * 0.5 + 1.0)))
	for lp: Vector3 in pts:
		var wp := bx * lp
		for k in 12:
			var yaw := k * TAU / 12.0
			player.velocity = Vector3.ZERO
			player.global_position = Vector3(wp.x, _ground(wp.x, wp.z) + 0.05, wp.z)
			player.call("snap_yaw", yaw)
			await _frames(20)
			var c := bx.affine_inverse() * cam.global_position
			n += 1
			# 外殻の内側（壁の内側かつ屋根面の下）：屋根面は棟（x=0）から両妻へ下がる平入近似＝高さ ab.end.y − 0.45·|z|
			var roof_y := ab.end.y - 0.45 * absf(c.z)
			if absf(c.x) < w * 0.5 - 0.05 and absf(c.z) < d * 0.5 - 0.05 and c.y > ab.position.y and c.y < roof_y:
				inside += 1
				worst = "player %s yaw %d° cam_local %s" % [lp, int(rad_to_deg(yaw)), c.snappedf(0.01)]
	print("[CAM018] 8 点 × 12 方向＝%d：相機が建物外殻内 %d %s；碰撞箱高 %.2f（簷 3.9 まで）" % [n, inside, worst,
		((body.get_node("Shape") as CollisionShape3D).shape as BoxShape3D).size.y])


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
	print("[SCENE] ArchPilotP13 %s、FarmsteadP13 %s" % [mr.get_node_or_null("ArchPilotP13") != null, mr.get_node_or_null("FarmsteadP13") != null])
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
	# ① TPS
	await _place(Vector2(241.0, 44.0), Vector2(262.0, -20.0))
	await _shot("01_tps_main_south")
	await _place(Vector2(262.0, -18.0), Vector2(242.0, 40.0))
	await _shot("02_tps_main_north")
	await _place(Vector2(276.0, -64.0), Vector2(293.0, -112.0))
	await _shot("02b_tps_main_north_section")
	await _place(Vector2(262.4, -14.0), Vector2(269.1, -10.9))
	await _shot("04_tps_MKT_010_house")
	var c6 := Vector2(260.2, 14.3)
	var f6 := Vector2(-0.9485, -0.3168)
	await _place(c6 + f6 * 10.5, c6)
	await _shot("05_tps_MKT_006_workshop")
	var c18 := Vector2(233.9, 34.0)
	var f18 := Vector2(0.9487, 0.3162)
	await _place(c18 + f18 * 10.0, c18)
	await _shot("06_tps_MKT_018_zushi")
	await _place(Vector2(337.0, 70.2), Vector2(319.0, 80.0))
	await _shot("07_tps_farmstead")
	await _place(Vector2(326.0, 76.0), Vector2(318.0, 82.0))
	await _shot("07b_tps_farmstead_near")
	# ② 高視角＋細部（別カメラ）
	var cam2 := Camera3D.new()
	cam2.far = 900.0
	cam2.fov = 55.0
	root.add_child(cam2)
	cam2.make_current()
	cam2.global_transform = Transform3D(Basis(), Vector3(228.0, 16.0, 50.0)).looking_at(Vector3(258.0, 4.0, 10.0), Vector3.UP)
	await _shot("03_roofs_high")
	var e6 := c6 + f6 * 7.5
	cam2.global_transform = Transform3D(Basis(), Vector3(e6.x, _ground(e6.x, e6.y) + 1.6, e6.y)).looking_at(Vector3(c6.x, 1.6, c6.y), Vector3.UP)
	player.visible = false
	await _shot("05b_eye_MKT_006_workshop")
	cam2.global_transform = Transform3D(Basis(), Vector3(330.0, 7.0, 92.0)).looking_at(Vector3(319.0, 2.5, 79.0), Vector3.UP)
	await _shot("08_farmstead_thatch")
	cam2.global_transform = Transform3D(Basis(), Vector3(352.0, 34.0, 112.0)).looking_at(Vector3(322.0, 0.0, 72.0), Vector3.UP)
	await _shot("09_farm_high")
	player.visible = true
	cam2.queue_free()
	await _frames(2)
	var pc := player.find_child("Camera3D", true, false) as Camera3D
	if pc:
		pc.make_current()
	# ③ MKT_018 相機
	await _cam_test(mr)
	# ④ 實走
	var s1 := await _walk("主街 南→北（39 棟の前、市集西の既知点 (255.9,7.0) を避けず通過）",
		[Vector2(236.0, 80.0), Vector2(242.0, 40.0), Vector2(250.0, 18.0), Vector2(257.0, -2.0), Vector2(262.0, -20.0), Vector2(271.0, -50.0), Vector2(280.0, -80.0), Vector2(290.0, -105.0)])
	var s2 := await _walk("MKT_018 前（正面 1.5 m）",
		[Vector2(237.0, 30.0), c18 + f18 * 4.5 + Vector2(-0.3162, 0.9487) * 3.0, c18 + f18 * 4.5 + Vector2(0.3162, -0.9487) * 3.0])
	var s3 := await _walk("FarmPath_5 → 渡し板 → A2 前 → A1 戸口",
		[Vector2(338.0, 70.3), Vector2(331.5, 70.4), Vector2(326.6, 70.6), Vector2(325.3, 74.3), Vector2(323.4, 79.0), Vector2(322.6, 82.6)])
	print("[DONE] walk_stuck=%d" % [s1 + s2 + s3])
	quit(0)

extends SceneTree
## P13 W1B 審圖撮影＋短距離實走（非 headless、Forward+、10:00）。正式 main.tscn の玩家・TPS 相機を使う（main.gd は変更しない）。
##   godot --path . --script res://tools/p13/shot_w1b.gd -- <outdir/>
## ① TPS（玩家相機）主街 正／反方向・MKT_010・MKT_006・農家（同一鏡位で overlay OFF／ON）
## ② 高視角（別カメラ）屋根・農田俯瞰
## ③ 農家配置圖（2D 画像：稗田邸圍牆禁區・田塊・支線・農道・A1／A2 出簷込み外形）
## ④ 短距離實走：主街 4 区間＋農道→農家前（overlay ON、move_forward、卡住／落下を記録）
const AL := preload("res://tools/village_v2_arch_pilot_lib.gd")

var main: Node
var player: CharacterBody3D
var ov: Node3D
var cam2: Camera3D
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


func _tps_pair(name: String, at: Vector2, look: Vector2) -> void:
	await _place(at, look)
	ov.set("enabled", false)
	await _shot(name + "_before")
	ov.set("enabled", true)
	await _shot(name + "_after")


func _walk(label: String, pts: Array) -> Dictionary:
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
			if d.length() < 1.5:
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
	return {"stuck": stuck}


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
	# ── selftest：切替で二重表示なし・OFF で元へ ──
	var tg: PackedStringArray = ov.get("targets")
	var bad := 0
	for on in [true, false, true, false, true]:
		ov.set("enabled", on)
		await process_frame
		for p in tg:
			var k := mr.get_node(NodePath(p)).get_node("Kit") as Node3D
			if k.visible == on or (ov.get_node(String(p).get_file()) as Node3D).visible != on:
				bad += 1
		for p in ov.get("hide_nodes"):
			if (mr.get_node(NodePath(p)) as Node3D).visible == on:
				bad += 1
	print("[SELF] 切替 5 回：二重表示／戻り漏れ %d" % bad)
	# ── ① TPS（玩家相機）──
	await _tps_pair("01_tps_main_south", Vector2(241.0, 44.0), Vector2(262.0, -20.0))
	await _tps_pair("02_tps_main_north", Vector2(262.0, -18.0), Vector2(242.0, 40.0))
	await _tps_pair("04_tps_MKT_010_house", Vector2(262.4, -14.0), Vector2(269.1, -10.9))
	await _tps_pair("05_tps_MKT_006_workshop", Vector2(253.0, 11.2), Vector2(260.2, 14.3))
	await _tps_pair("07_tps_farmstead", Vector2(336.0, 70.5), Vector2(319.0, 79.0))
	# ── ② 高視角 ──
	cam2 = Camera3D.new()
	cam2.far = 900.0
	cam2.fov = 55.0
	root.add_child(cam2)
	cam2.make_current()
	cam2.global_transform = Transform3D(Basis(), Vector3(228.0, 16.0, 50.0)).looking_at(Vector3(258.0, 4.0, 10.0), Vector3.UP)
	ov.set("enabled", false)
	await _shot("03_roofs_high_before")
	ov.set("enabled", true)
	await _shot("03_roofs_high_after")
	cam2.global_transform = Transform3D(Basis(), Vector3(352.0, 34.0, 112.0)).looking_at(Vector3(322.0, 0.0, 72.0), Vector3.UP)
	await _shot("06_farm_high")
	cam2.global_transform = Transform3D(Basis(), Vector3(420.0, 120.0, 90.0)).looking_at(Vector3(380.0, 0.0, 0.0), Vector3.UP)
	await _shot("06b_farm_overview_hieda")
	cam2.queue_free()
	await _frames(2)
	var pc := player.find_child("Camera3D", true, false) as Camera3D
	if pc:
		pc.make_current()
	# ── ④ 短距離實走（overlay ON）──
	var w1 := await _walk("主街 中段→北（11 棟の前）", [Vector2(241.0, 44.0), Vector2(250.0, 18.0), Vector2(257.0, -2.0), Vector2(262.0, -18.0), Vector2(255.0, 12.0)])
	var w2 := await _walk("FarmPath_5→農家 A1／A2 前庭", [Vector2(338.0, 70.0), Vector2(328.0, 72.5), Vector2(325.0, 77.0), Vector2(338.0, 70.0)])
	print("[DONE] selftest_bad=%d walk_stuck=%d" % [bad, int(w1["stuck"]) + int(w2["stuck"])])
	quit(0)

extends SceneTree
## 戰鬥攝影機遮擋實測（V1.3；非 headless、真渲染、正式 main.tscn＋玩家＋CameraAdapter＋SpringArm3D）。
## 玩家放在 S04 戰鬥圓的幾個半徑×方位（含圓邊的岩石／樹旁），每個位置把鏡頭轉 N 個方向（相機在玩家背後），量：
##   ① SpringArm3D 實際臂長（被岩／樹幹碰撞拉近多少；預設 8.5 m）
##   ② 玩家在畫面上的可見率＝「玩家顯示」與「玩家隱藏」兩張畫面在玩家投影框內的逐像素差 ÷ 投影框面積，
##      再除以開闊處（最內圈）的中位數＝相對可見率（1＝跟空地一樣看得到；< 0.5＝被擋掉一半以上——葉子、樹枝、岩石都算，不只碰撞體）
##   ③ 相機→身體 4 點（1.6／1.25／0.9／0.45 m）的物理射線被誰擋
## 只量，不改任何東西。
##   godot --path godot --script res://tools/beast_path/cam_occlusion_beast_path.gd -- --out=<dir> [--hour=10] [--radii=6,12,17,19.5] [--angles=12] [--yaws=8]
const BP := preload("res://tools/beast_path/bp_lib.gd")

var main: Node
var player: CharacterBody3D
var adapter: Node
var arm: SpringArm3D
var lib: BP


func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	var out := ""
	var hour := 10.0
	var radii: Array = [6.0, 12.0, 17.0, 19.5]
	var n_ang := 12
	var n_yaw := 8
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		elif a.begins_with("--hour="):
			hour = float(a.trim_prefix("--hour="))
		elif a.begins_with("--radii="):
			radii = Array(a.trim_prefix("--radii=").split(",")).map(func(s: String) -> float: return float(s))
		elif a.begins_with("--angles="):
			n_ang = int(a.trim_prefix("--angles="))
		elif a.begins_with("--yaws="):
			n_yaw = int(a.trim_prefix("--yaws="))
	if out == "":
		push_error("需要 --out=<dir>")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(out)
	lib = BP.new()
	lib.setup(true, true)
	get_root().size = Vector2i(1600, 900)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	var t0 := Time.get_ticks_msec()
	while true:
		await physics_frame
		player = main.get("player")
		if player and String(main.get("current_id")) == "beast_path" and player.is_on_floor():
			break
		if Time.get_ticks_msec() - t0 > 120000:
			print("[CAM] ✗ 120 秒內沒進到 beast_path")
			quit(2)
			return
	adapter = player.get_node("CameraAdapter")
	adapter.set_process_unhandled_input(false)
	player.set_process_unhandled_input(false)
	arm = adapter.get("arm")
	var dn := root.get_node_or_null("DayNight")
	if dn != null:
		dn.set("flowing", false)
		dn.call("set_hour", hour)
	for _i in 12:
		await process_frame
	var sbn := main.find_child("ShadowBudget", true, false)
	if sbn != null:
		sbn.call("apply", true)
	for cl in root.find_children("*", "CanvasLayer", true, false):
		(cl as CanvasLayer).visible = false
	var cam: Camera3D = player.get_viewport().get_camera_3d()
	var space := player.get_world_3d().direct_space_state
	var target_d := float(adapter.get("default_distance"))
	print("[CAM] 進圖 OK；hour=%.1f；相機 fov=%.0f°；預設臂長 %.2f m；SpringArm margin %.2f、collision_mask %d" % [hour, cam.fov, target_d, arm.margin, arm.collision_mask])
	var samples: Array = []
	var ref := -1.0
	var saved := 0
	for ri in radii.size():
		var r := float(radii[ri])
		for k in n_ang:
			var deg := 360.0 * float(k) / float(n_ang) + (15.0 if ri % 2 == 1 else 0.0)
			var q := lib.arena_pos(deg, r)
			for j in n_yaw:
				var face := 360.0 * float(j) / float(n_yaw)
				await _put(q, -deg_to_rad(face), -0.18, target_d)
				adapter.set("_arm_eff", -1.0)
				for _i in 6:
					await physics_frame
				for _i in 6:
					await process_frame
				var hit := arm.get_hit_length()
				var cp := cam.global_position
				var pp := player.global_position
				var blocked: Array = []
				for hgt: float in [1.6, 1.25, 0.9, 0.45]:
					var rq := PhysicsRayQueryParameters3D.create(cp, pp + Vector3(0.0, hgt, 0.0), 0xFFFFFFFF)
					rq.exclude = [player.get_rid()]
					var h := space.intersect_ray(rq)
					if not h.is_empty():
						blocked.append("%.2f:%s" % [hgt, _owner_name(h["collider"] as Node)])
				var A := get_root().get_texture().get_image()
				player.visible = false
				for _i in 4:
					await process_frame
				var B := get_root().get_texture().get_image()
				player.visible = true
				var rect := _player_rect(cam)
				var vis := _diff_ratio(A, B, rect) if rect.size.x >= 2 and rect.size.y >= 2 else -1.0
				var rec := {"r": r, "deg": deg, "face": face, "x": snappedf(pp.x, 0.01), "z": snappedf(pp.z, 0.01),
					"arm": snappedf(hit, 0.01), "vis": snappedf(vis, 0.001), "rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y], "ray_blocked": blocked}
				if k == 0 and j == 0:
					A.save_png(out.path_join("ref_r%04.1f.png" % r))
				if ref > 0.0 and vis >= 0.0:
					rec["rel"] = snappedf(vis / ref, 0.01)
					if (rec["rel"] < 0.5 or hit < 4.0) and saved < 40:
						var nm := "occ_r%04.1f_d%03d_f%03d.png" % [r, int(deg), int(face)]
						A.save_png(out.path_join(nm))
						rec["png"] = nm
						saved += 1
				samples.append(rec)
		if ri == 0:
			var v0: Array = samples.filter(func(s: Dictionary) -> bool: return float(s["vis"]) >= 0.0).map(func(s: Dictionary) -> float: return float(s["vis"]))
			v0.sort()
			ref = float(v0[v0.size() / 2])
			for s: Dictionary in samples:
				s["rel"] = snappedf(float(s["vis"]) / ref, 0.01) if float(s["vis"]) >= 0.0 else -1.0
			print("[CAM] 基準（r=%.1f 開闊處 %d 個樣本的中位數）可見率 %.3f" % [r, v0.size(), ref])
	# ---- 統計
	var n := samples.size()
	var invalid := 0
	var occ50: Array = []
	var occ25: Array = []
	var arm_short: Array = []
	var ray_any := 0
	var by_r := {}
	for s: Dictionary in samples:
		var rk := "%.1f" % float(s["r"])
		if not by_r.has(rk):
			by_r[rk] = {"n": 0, "occ50": 0, "arm_lt6": 0, "arm_min": 99.0, "rel_min": 9.0, "invalid": 0}
		var br: Dictionary = by_r[rk]
		br["n"] += 1
		br["arm_min"] = minf(float(br["arm_min"]), float(s["arm"]))
		if float(s["arm"]) < 6.0:
			arm_short.append(s)
			br["arm_lt6"] += 1
		if not (s["ray_blocked"] as Array).is_empty():
			ray_any += 1
		if float(s.get("rel", -1.0)) < 0.0:
			invalid += 1
			br["invalid"] += 1
			continue
		br["rel_min"] = minf(float(br["rel_min"]), float(s["rel"]))
		if float(s["rel"]) < 0.5:
			occ50.append(s)
			br["occ50"] += 1
		if float(s["rel"]) < 0.25:
			occ25.append(s)
	var summ := {"hour": hour, "samples": n, "invalid_rect": invalid, "ref_vis": ref, "rel_lt_0_5": occ50.size(), "rel_lt_0_25": occ25.size(),
		"arm_lt_6m": arm_short.size(), "ray_blocked_any": ray_any, "by_radius": by_r, "target_arm": target_d}
	print("[CAM] ═══ %d 樣本（投影框無效 %d）：相對可見率 < 0.5 的 %d、< 0.25 的 %d；臂被拉到 < 6 m 的 %d；射線擋到身體任一點的 %d ═══" % [n, invalid, occ50.size(), occ25.size(), arm_short.size(), ray_any])
	for rk2 in by_r:
		print("[CAM]   r=%s m：%s" % [rk2, str(by_r[rk2])])
	occ50.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["rel"]) < float(b["rel"]))
	for s2: Dictionary in occ50.slice(0, 12):
		print("[CAM]   遮擋 rel=%.2f arm=%.2f r=%.1f deg=%.0f face=%.0f @(%.1f,%.1f) ray=%s %s" % [float(s2["rel"]), float(s2["arm"]), float(s2["r"]), float(s2["deg"]), float(s2["face"]), float(s2["x"]), float(s2["z"]), str(s2["ray_blocked"]), String(s2.get("png", ""))])
	arm_short.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["arm"]) < float(b["arm"]))
	for s3: Dictionary in arm_short.slice(0, 8):
		print("[CAM]   臂短 arm=%.2f rel=%.2f r=%.1f deg=%.0f face=%.0f @(%.1f,%.1f) %s" % [float(s3["arm"]), float(s3["rel"]), float(s3["r"]), float(s3["deg"]), float(s3["face"]), float(s3["x"]), float(s3["z"]), String(s3.get("png", ""))])
	var f := FileAccess.open(out.path_join("cam_occlusion.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"summary": summ, "samples": samples}, "  "))
	f.close()
	quit(0)


func _owner_name(n: Node) -> String:
	var c := n
	for _i in 4:
		if c == null or c.get_parent() == null:
			break
		if c is StaticBody3D or c is CollisionObject3D:
			c = c.get_parent()
		else:
			break
	return String(c.name) if c != null else "?"


## 玩家碰撞膠囊（身體本體；不用網格 AABB——角色底下掛的特效／殘影網格框很大，會把投影框撐到半個畫面）的世界 AABB 投影到畫面的矩形
func _player_rect(cam: Camera3D) -> Rect2i:
	var ab := AABB(player.global_position + Vector3(-0.35, 0.0, -0.35), Vector3(0.7, 1.75, 0.7))
	for c in player.get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape is CapsuleShape3D:
			var cs := c as CollisionShape3D
			var cap := cs.shape as CapsuleShape3D
			var ctr := cs.global_position
			ab = AABB(ctr - Vector3(cap.radius, cap.height * 0.5, cap.radius), Vector3(cap.radius * 2.0, cap.height, cap.radius * 2.0))
			break
	var vs := get_root().size
	var mn := Vector2(1e9, 1e9)
	var mx := Vector2(-1e9, -1e9)
	for i in 8:
		var c2 := ab.get_endpoint(i)
		if cam.is_position_behind(c2):
			return Rect2i()
		var sp := cam.unproject_position(c2)
		mn = mn.min(sp)
		mx = mx.max(sp)
	mn = mn.clamp(Vector2.ZERO, Vector2(vs))
	mx = mx.clamp(Vector2.ZERO, Vector2(vs))
	return Rect2i(Vector2i(mn), Vector2i(mx - mn))


## 投影框內「顯示／隱藏玩家」兩張畫面不同的像素比例（每 2 px 取樣；RGB 差和 > 0.12）
func _diff_ratio(A: Image, B: Image, rc: Rect2i) -> float:
	if rc.size.x < 2 or rc.size.y < 2:
		return 0.0
	var cnt := 0
	var tot := 0
	var y := rc.position.y
	while y < rc.end.y:
		var x := rc.position.x
		while x < rc.end.x:
			var a := A.get_pixel(x, y)
			var b := B.get_pixel(x, y)
			if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.12:
				cnt += 1
			tot += 1
			x += 2
		y += 2
	return float(cnt) / float(maxi(tot, 1))


func _put(q: Vector2, yaw: float, pitch: float, dist: float) -> void:
	var sp := player.get_world_3d().direct_space_state
	var rq := PhysicsRayQueryParameters3D.create(Vector3(q.x, 80.0, q.y), Vector3(q.x, -60.0, q.y), player.collision_mask)
	rq.exclude = [player.get_rid()]
	var r := sp.intersect_ray(rq)
	player.velocity = Vector3.ZERO
	player.global_position = Vector3(q.x, (float((r["position"] as Vector3).y) if not r.is_empty() else 2.0) + 0.2, q.y)
	adapter.set("_target_yaw", yaw)
	adapter.set("_target_pitch", pitch)
	adapter.set("_current_pitch", pitch)
	adapter.set("_target_distance", dist)
	adapter.set("_current_distance", dist)
	if player.has_method("snap_yaw"):
		player.snap_yaw(yaw)
	for i in 30:
		await physics_frame

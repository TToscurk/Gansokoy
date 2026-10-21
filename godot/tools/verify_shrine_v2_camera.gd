extends SceneTree
## 第三人稱鏡頭碰撞（真 main.tscn、真 Player＋CameraAdapter、SpringArm3D 遮罩 1、margin 0.2、肩偏 0.4 m）。
##   godot --headless --path godot --script tools/verify_shrine_v2_camera.gd -- --map=shrine_v2 [--region=x0,x1,z0,z1] [--samples=150]
## 在指定範圍內隨機取 N 個站位 × 隨機朝向／俯仰（固定種子），逐一檢查：
##   C1 鏡頭不在實心碰撞體內（intersect_point，遮罩 1，排除玩家）——只統計，不判失敗（見下）
##   C2 鏡頭在地面之上（向下射線必須命中、且命中點不高於鏡頭 3 cm）
##   C3 鏡頭到頭部的視線無遮擋（射線不得命中）
##   C4 彈簧臂沒縮成 0（鏡頭離頭部 ≥ 0.4 m）
## 同一支腳本可對舊圖（--map=shrine --region=...）跑，當作「共用鏡頭裝置本身」的基準：
## 肩偏 0.4 m 讓鏡頭可能偏離射線 0.4 m，因此「射線沒擋到、鏡頭點卻落在細樹幹內」是裝置特性，不是場景錯誤——
## C1 只比兩張圖的違規率，C2–C4 才是硬性判定。

var fails := 0
var main: Node
var player: CharacterBody3D
var region := [-45.0, 45.0, -60.0, 70.0]
var n_samples := 150


func _init() -> void:
	_run.call_deferred()


func check(label: String, ok: bool) -> void:
	print("[CAM2] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		fails += 1


func _settle(n: int = 3) -> void:
	for i in n:
		await physics_frame
		await process_frame


func _ground(x: float, z: float) -> float:
	var space := player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 140.0, z), Vector3(x, -30.0, z))
	q.exclude = [player.get_rid()]
	var hit := space.intersect_ray(q)
	return float(hit["position"].y) if hit.size() > 0 else NAN


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--region="):
			var p := a.substr(9).split(",")
			region = [float(p[0]), float(p[1]), float(p[2]), float(p[3])]
		elif a.begins_with("--samples="):
			n_samples = int(a.substr(10))
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _settle(40)
	player = main.player
	print("[CAM2] 地圖 %s；範圍 %s；取樣 %d" % [main.current_id, str(region), n_samples])
	player.set("input_locked", true)
	var adapter: Node = player.get_node("CameraAdapter")
	var arm: SpringArm3D = player.get_node("Pivot/SpringArm3D")
	var cam: Camera3D = null
	for c in arm.get_children():
		if c is Camera3D:
			cam = c
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261022
	var n := 0
	var bad_inside := 0
	var bad_under := 0
	var bad_los := 0
	var bad_collapsed := 0
	var shortened := 0
	var worst: Array = []
	var tries := 0
	while n < n_samples and tries < n_samples * 6:
		tries += 1
		var gx := rng.randf_range(region[0], region[1])
		var gz := rng.randf_range(region[2], region[3])
		var g := _ground(gx, gz)
		if is_nan(g):
			continue
		var yaw := rng.randf_range(0.0, TAU)
		var pitch := rng.randf_range(-0.6, 0.3)
		player.velocity = Vector3.ZERO
		player.global_position = Vector3(gx, g + 0.1, gz)
		adapter.snap_yaw(yaw)
		adapter.set("_target_pitch", pitch)
		adapter.set("_current_pitch", pitch)
		await _settle(10)
		if not player.is_on_floor():
			continue                       # 落在樹幹上方／斜坡太陡滑走的點不計
		var space := player.get_world_3d().direct_space_state
		var cp := cam.global_position
		var head := player.global_position + Vector3(0, 1.7, 0)
		n += 1
		var pq := PhysicsPointQueryParameters3D.new()
		pq.position = cp
		pq.collision_mask = 1
		pq.exclude = [player.get_rid()]
		var inside := space.intersect_point(pq, 4)
		if inside.size() > 0:
			bad_inside += 1
			worst.append("(%.1f,%.1f) yaw%.0f° 鏡頭在 %s 內" % [gx, gz, rad_to_deg(yaw), str((inside[0]["collider"] as Node).get_parent().name)])
		var rq := PhysicsRayQueryParameters3D.create(cp, cp + Vector3(0, -200.0, 0))
		rq.exclude = [player.get_rid()]
		var rh := space.intersect_ray(rq)
		if rh.size() == 0 or float(rh["position"].y) > cp.y + 0.03:
			bad_under += 1
			worst.append("(%.1f,%.1f) yaw%.0f° 鏡頭在地面下（cam y=%.2f，上方地面 %s，差 %s m）" % [gx, gz, rad_to_deg(yaw), cp.y, "無" if rh.size() == 0 else "%.2f" % float(rh["position"].y), "-" if rh.size() == 0 else "%.2f" % (float(rh["position"].y) - cp.y)])
		var lq := PhysicsRayQueryParameters3D.create(cp, head)
		lq.exclude = [player.get_rid()]
		lq.collision_mask = 1
		var lh := space.intersect_ray(lq)
		if lh.size() > 0 and cp.distance_to(head) > 0.3:
			bad_los += 1
			worst.append("(%.1f,%.1f) yaw%.0f° 視線被 %s 擋" % [gx, gz, rad_to_deg(yaw), str((lh["collider"] as Node).get_parent().name)])
		if cp.distance_to(head) < 0.4:
			bad_collapsed += 1
			worst.append("(%.1f,%.1f) yaw%.0f° 鏡頭離頭部僅 %.2f m" % [gx, gz, rad_to_deg(yaw), cp.distance_to(head)])
		if arm.get_hit_length() < 8.0:
			shortened += 1
	print("[CAM2] 有效取樣 %d；彈簧臂被擋住而縮短（<8 m）%d（%.0f%%）" % [n, shortened, 100.0 * shortened / maxf(n, 1)])
	print("[CAM2] RATE inside=%d/%d (%.1f%%)  under_ground=%d (%.1f%%)  los=%d (%.1f%%)  collapsed=%d (%.1f%%)" % [
		bad_inside, n, 100.0 * bad_inside / maxf(n, 1), bad_under, 100.0 * bad_under / maxf(n, 1),
		bad_los, 100.0 * bad_los / maxf(n, 1), bad_collapsed, 100.0 * bad_collapsed / maxf(n, 1)])
	check("C2 鏡頭不會跑到地面下（%d/%d）" % [bad_under, n], bad_under == 0)
	check("C3 鏡頭到頭部視線無遮擋（%d/%d）" % [bad_los, n], bad_los == 0)
	check("C4 彈簧臂沒縮成 0（%d/%d）" % [bad_collapsed, n], bad_collapsed == 0)
	check("C5 有取樣到被碰撞體擋住的情況（%d）" % shortened, shortened > 0)
	for w in worst.slice(0, 8):
		print("[CAM2]   ✗ ", w)
	print("[CAM2] failures=%d" % fails)
	quit(fails)

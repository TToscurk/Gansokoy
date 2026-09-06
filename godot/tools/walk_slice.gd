extends SceneTree
## Walk the REAL player (scenes/player.tscn, CharacterBody3D + move_and_slide)
## into things and report where it stops. This is the ground truth: shape
## queries can be mis-placed, but if the character controller itself is
## stopped by a wall, the wall works.
##
## Each leg: teleport player to A, set velocity toward B for N physics frames,
## report distance travelled vs requested.

const SPEED := 6.0
const FRAMES := 240   # 4 s at 60 Hz = up to 24 m

var _main: Node


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := ResourceLoader.load("res://scenes/main.tscn", "PackedScene") as PackedScene
	_main = packed.instantiate()
	root.add_child(_main)
	await process_frame
	_main.load_map("slice", "")
	for i in 6:
		await physics_frame

	var player: CharacterBody3D = _main.player
	# Drive the REAL controller through InputMap actions so step-up / snap /
	# whatever else _physics_process does is exercised. World-axis input: clear
	# the camera yaw reference and rotate the pivot so "move_forward" = the
	# leg's direction.
	var drives_itself: bool = player.get("input_yaw_node") != null
	var yaw_node: Node3D = null
	if drives_itself:
		yaw_node = player.get("input_yaw_node")
	print("[實走] 膠囊 r=%.2f h=%.2f  floor_max_angle=%.0f°  max_slides=%d  控制器=%s" % [
		_capsule(player).x, _capsule(player).y, rad_to_deg(player.floor_max_angle), player.max_slides,
		"真實 _physics_process" if drives_itself else "外部 velocity"])
	if not drives_itself:
		player.set_physics_process(false)

	# Coordinates from tools/probe_audit_targets.gd (2026-09-03): building
	# centres, torii legs (probe_torii_legs), bridge ends (probe_teahouse_bridge).
	# Approach each building from the street side, 5–6 m out from its centre.
	var legs := [
		{"n": "主街往北走（應暢通）", "a": Vector3(236, 1.0, 10), "d": Vector3(0, 0, 1), "want": "free"},
		{"n": "穿過大鳥居中央", "a": Vector3(236, 1.0, 96), "d": Vector3(0, 0, 1), "want": "free"},
		{"n": "撞大鳥居左柱", "a": Vector3(231, 1.0, 96), "d": Vector3(0, 0, 1), "want": "stop"},
		{"n": "撞大鳥居右柱", "a": Vector3(241, 1.0, 96), "d": Vector3(0, 0, 1), "want": "stop"},
		{"n": "撞町家 machiya_西_00", "a": Vector3(236, 1.0, -55.9), "d": Vector3(-1, 0, 0), "want": "stop"},
		{"n": "撞商家 shouka_東_02", "a": Vector3(236, 1.0, -19.8), "d": Vector3(1, 0, 0), "want": "stop"},
		{"n": "撞倉庫_Mesh", "a": Vector3(236, 1.0, 63.0), "d": Vector3(1, 0, 0), "want": "stop"},
		{"n": "撞霧雨店", "a": Vector3(244.2, 1.0, 4.0), "d": Vector3(0, 0, -1), "want": "stop"},
		# 鯢吞亭 2026-09-04 由使用者移到 (213.6, −94.4)。舊探針起點 (258, −5.5)
		# 指著空地，走完 25 m 沒撞到任何東西還掉到 y=−1.78 —— 那是「探針指錯
		# 地方」，不是碰撞壞掉。起點放在建築西側 8 m，往東走。
		{"n": "撞鯢吞亭", "a": Vector3(205, 1.0, -94.4), "d": Vector3(1, 0, 0), "want": "stop"},
		{"n": "撞鈴奈庵", "a": Vector3(236, 1.0, -67.7), "d": Vector3(-1, 0, 0), "want": "stop"},
		{"n": "撞寺子屋", "a": Vector3(300, 1.0, 34.6), "d": Vector3(1, 0, 0), "want": "stop"},
		{"n": "水路底撞石砌護岸", "a": Vector3(284, -1.5, -22), "d": Vector3(-1, 0, 0), "want": "stop"},
		{"n": "走進東河（應有河床）", "a": Vector3(430, 1.0, 20), "d": Vector3(1, 0, 0), "want": "free"},
		# 龍石像橋 (yawed ~17°): walk its own long axis. West end has the
		# measured 1.11 m step (probe_teahouse_bridge) — this is the test that
		# decides whether it needs a ramp.
		{"n": "龍石像橋 西→東 上橋", "a": Vector3(394.4, 0.5, -134.9), "d": Vector3(1.0, 0, -0.31), "want": "free", "frames": 700},
		{"n": "龍石像橋 東→西 上橋", "a": Vector3(452.1, 0.5, -152.9), "d": Vector3(-1.0, 0, 0.31), "want": "free", "frames": 700},
		# 路燈：2026-09-04 新增 CylinderShape3D 碰撞（gen_lamp_collision.gd）。
		# 起點必須是**空地**，x 必須用碰撞中心而非路燈根節點座標。
		#   - 第一版起點 z=78：probe_lamp_hit.gd 量出 (241.09, 78) 到 z=84 整段
		#     都在 machiya_東_11 的碰撞體內部，角色開場被埋在町家裡，控制器推開
		#     後路徑偏移反而繞過燈柱，於是誤報「暢通」。
		#   - 第二版用 x=241.09：那是路燈**根節點**的 x，但碰撞修正後圓柱對齊的
		#     是網格中心 x=239.67（相差 1.42 m 的「模型偏移」）。走 241.09 只擦過
		#     圓柱邊緣，同樣誤報暢通。
		# 現在直接用 gen_lamp_collision.gd 印出的碰撞中心。
		{"n": "撞路燈_03（東側）", "a": Vector3(239.67, 1.0, 92.0), "d": Vector3(0, 0, -1), "want": "stop"},
		{"n": "兩排路燈之間走主街", "a": Vector3(236.1, 1.0, 92.0), "d": Vector3(0, 0, -1), "want": "free"},
	]

	var fails := 0
	for leg in legs:
		player.global_position = leg["a"]
		player.velocity = Vector3.ZERO
		for i in 3:
			await physics_frame
		var start: Vector3 = player.global_position
		var dir: Vector3 = (leg["d"] as Vector3).normalized()
		var frames: int = leg.get("frames", FRAMES)
		var peak_y := start.y
		if drives_itself:
			# move_forward is -Z in the yaw node's frame; yaw so that -Z = dir.
			yaw_node.global_rotation.y = atan2(-dir.x, -dir.z)
			Input.action_press("move_forward")
			Input.action_press("sprint")
		for i in frames:
			if not drives_itself:
				player.velocity = dir * SPEED + Vector3(0, minf(player.velocity.y - 22.0 / 60.0, 0.0), 0)
				player.move_and_slide()
			peak_y = maxf(peak_y, player.global_position.y)
			await physics_frame
		if drives_itself:
			Input.action_release("move_forward")
			Input.action_release("sprint")
		var end: Vector3 = player.global_position
		var travelled := Vector2(end.x - start.x, end.z - start.z).length()
		var speed: float = float(player.get("run_speed")) if drives_itself else SPEED
		var asked := speed * frames / 60.0
		var fell := end.y < -8.0  # river bed is Y≈-5.2 by design; below that is off-map
		var stopped := travelled < asked * 0.6
		var ok: bool = (leg["want"] == "stop" and stopped and not fell) or (leg["want"] == "free" and not stopped and not fell)
		if not ok:
			fails += 1
		print("%-22s 走了 %5.1f / %4.1f m  終點Y %6.2f 最高Y %5.2f  %s" % [
			leg["n"], travelled, asked, end.y, peak_y,
			("✓" if ok else "✗") + (" 掉出地圖" if fell else (" 被擋" if stopped else " 暢通"))])

	print("[實走] 失敗 %d / %d" % [fails, legs.size()])
	print("done")
	quit(0)


func _capsule(p: CharacterBody3D) -> Vector2:
	for c in p.get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape is CapsuleShape3D:
			var s: CapsuleShape3D = (c as CollisionShape3D).shape
			return Vector2(s.radius, s.height)
	return Vector2.ZERO

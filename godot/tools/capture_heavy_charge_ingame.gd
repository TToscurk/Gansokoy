extends SceneTree
## RMB 長按蓄力拔刀斬：實機連拍（真的站在地上、真的拿著刀、真的有敵人）。
##
## 執行（要視窗，不能 --headless）：
##   godot --path godot -s tools/capture_heavy_charge_ingame.gd
##
## 在 main.tscn（正式光照／glow）裡把一隻站樁武士放到玩家正前方 6 m，
## 按住 RMB 走完整段：舉刀凍住 → 蓄 3 s → 閃光 → 衝刺 → 落刀 → 刀光尾巴 → 收勢。
## 兩個角度各拍一組：側面（看衝刺距離與腳步）、3/4 背視角（玩家實際看到的）。
## 每張截圖旁邊印出：蓄力進度、與敵距離、刀尖速度、upper 層倍率 —— 圖是證據，數字是尺。

const OUT_DIR := "user://heavy_charge_ingame"
const SHOTS := [
	{"t": 0.00, "name": "00_press",   "label": "按下"},
	{"t": 0.35, "name": "01_freeze",  "label": "舉刀凍住"},
	{"t": 1.00, "name": "02_charge1", "label": "蓄 1/3"},
	{"t": 2.00, "name": "03_charge2", "label": "蓄 2/3"},
	{"t": 2.90, "name": "04_almost",  "label": "快滿"},
	{"t": 3.03, "name": "05_flash",   "label": "滿蓄閃光"},
	{"t": 3.14, "name": "06_dash",    "label": "衝刺中"},
	{"t": 3.26, "name": "07_arrive",  "label": "抵達落刀"},
	{"t": 3.40, "name": "08_slash",   "label": "刀光"},
	{"t": 3.70, "name": "09_tail",    "label": "尾巴"},
	{"t": 4.30, "name": "10_recover", "label": "收勢"},
]
const ANGLES := [
	{"name": "side", "yaw_offset": PI * 0.5, "dist": 6.5, "pitch": -0.12},
	{"name": "back34", "yaw_offset": PI * 0.78, "dist": 4.8, "pitch": -0.32},
]


func _initialize() -> void:
	var flags: Node = get_root().get_node_or_null("StoryFlags")
	if flags != null:
		flags.set_flag("woke_in_trail", true)

	var scene: PackedScene = load("res://scenes/main.tscn")
	var main: Node = scene.instantiate()
	get_root().add_child(main)
	for i in 60:
		await process_frame

	var player: Node = main.get("player")
	if player == null:
		push_error("[蓄力斬] 找不到玩家")
		quit(1)
		return

	var dir := DirAccess.open("user://")
	if dir != null and not dir.dir_exists("heavy_charge_ingame"):
		dir.make_dir("heavy_charge_ingame")

	# 拔刀（直接切狀態）、鎖輸入、站好。
	player.set("sword_state", 2)
	player.call("_apply_sword_visibility")
	player.set("input_locked", true)
	for i in 10:
		await process_frame
	var origin: Vector3 = player.global_position
	var facing_yaw: float = player.get("_visual").global_rotation.y
	var fwd := Vector3(sin(facing_yaw), 0.0, cos(facing_yaw))
	print("[蓄力斬] 著地 = %s、位置 = %s、面向 yaw = %.2f" % [player.call("is_on_floor"), origin, facing_yaw])

	# 站樁武士：正前方 6 m。
	var enemy: Node3D = (load("res://characters/combat/enemy_samurai.tscn") as PackedScene).instantiate()
	main.add_child(enemy)
	enemy.global_position = origin + fwd * 6.0
	await process_frame
	enemy.set_physics_process(false)
	enemy.posture.max_health = 1000.0
	enemy.posture.health = 1000.0
	var combat: Node = main.get("combat")
	if combat != null and combat.has_method("rescan_enemies"):
		combat.rescan_enemies()

	var pivot: Node3D = player.get_node_or_null("Pivot")
	var arm: SpringArm3D = player.get_node_or_null("Pivot/SpringArm3D")
	var adapter: Node = player.get_node_or_null("CameraAdapter")

	for angle in ANGLES:
		# 重置：回原點、面向、敵人滿血。
		player.set("input_locked", true)
		player.global_position = origin
		player.velocity = Vector3.ZERO
		player.global_rotation.y = 0.0
		player.get("_visual").global_rotation.y = facing_yaw
		enemy.global_position = origin + fwd * 6.0
		enemy.posture.health = 1000.0
		if adapter != null:
			adapter.set("_target_yaw", facing_yaw + float(angle.yaw_offset))
			adapter.set("_target_pitch", float(angle.pitch))
			adapter.set("_target_distance", float(angle.dist))
			adapter.set("_current_distance", float(angle.dist))
		if arm != null:
			arm.spring_length = float(angle.dist)
		if pivot != null:
			pivot.rotation.y = facing_yaw + float(angle.yaw_offset)
			pivot.rotation.x = float(angle.pitch)
		for i in 20:
			await process_frame

		# 按住 RMB：input_locked 要放開才讀得到（_unhandled_input 會擋），改直接呼叫 begin_heavy_charge。
		player.set("input_locked", false)
		Input.action_press("attack_heavy")
		var ok: bool = player.call("begin_heavy_charge")
		print("[蓄力斬/%s] begin_heavy_charge = %s" % [angle.name, ok])
		if not ok:
			quit(1)
			return

		var elapsed := 0.0
		var shot_i := 0
		var prev_tip: Vector3 = player.get("_blade_tip").global_position
		var hp0: float = enemy.posture.health
		while shot_i < SHOTS.size():
			await RenderingServer.frame_post_draw
			var dt: float = get_root().get_process_delta_time()
			elapsed += dt
			var tip: Vector3 = player.get("_blade_tip").global_position
			var tip_v: float = (tip - prev_tip).length() / maxf(dt, 0.0001)
			prev_tip = tip
			var target: float = float(SHOTS[shot_i]["t"])
			if elapsed >= target:
				var img: Image = get_root().get_texture().get_image()
				var path: String = "%s/hc_%s_%s.png" % [OUT_DIR, angle.name, SHOTS[shot_i]["name"]]
				img.save_png(path)
				var d: Vector3 = player.global_position - enemy.global_position
				d.y = 0.0
				print("  %s  t=%.2f s  charge=%.2f  frozen=%s  dash_left=%.2f m  dist=%.2f m  tip_v=%.1f m/s  ts_upper=%.2f  enemy_hp=%.0f → %s" % [
					SHOTS[shot_i]["label"], elapsed, player.call("heavy_charge_progress"), player.get("_heavy_frozen"),
					player.get("_iai_dash_remaining"), d.length(), tip_v,
					float(player.get("_tree").get("parameters/ts_upper/scale")), enemy.posture.health,
					ProjectSettings.globalize_path(path)])
				shot_i += 1
			if elapsed > 5.0:
				break
		Input.action_release("attack_heavy")
		print("[蓄力斬/%s] 敵人掉血 %.1f、剩餘 fx 節點：charge_fx active=%s、streaks=%s" % [
			angle.name, hp0 - enemy.posture.health, player.get("_charge_fx").is_active(),
			player.get_node_or_null("IaiDashStreaks") != null])
		for i in 40:
			await process_frame

	print("[蓄力斬] 連拍完成：%s" % ProjectSettings.globalize_path(OUT_DIR))
	quit(0)

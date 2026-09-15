extends SceneTree
## 捌ノ型 陽華突：實機發招連拍（真的站在地上、真的拿著刀）。
##
## 執行：
##   godot --path godot -s tools/capture_form08_ingame.gd
##   （要視窗，不能 --headless）
##
## 這是最終驗收畫面：Godot 的 HandSocket 掛刀、AnimationTree 混合、
## 真實光照。Blender 預覽的掛刀只是模擬，這裡才是玩家會看到的。

const OUT_DIR := "user://form08_ingame"
## 動畫 1.25 s ÷ thrust_speed_scale 1.6 ≈ 0.78 s。
## 取蓄力、突刺、留、收四個時點（比例對應 Blender 的 f7/f12/f17/f30）。
const SHOTS := [
	{"t": 0.00, "name": "00_kamae",  "label": "架"},
	{"t": 0.23, "name": "07_tame",   "label": "蓄"},
	{"t": 0.39, "name": "12_tsuki",  "label": "突"},
	{"t": 0.55, "name": "17_tome",   "label": "留"},
	{"t": 0.78, "name": "30_osame",  "label": "收"},
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
		push_error("[捌型] 找不到玩家")
		quit(1)
		return

	# 相機拉到側面 —— 突刺是前後方向的動作，正面看不出行程。
	var pivot: Node3D = player.get_node_or_null("Pivot")
	var arm: SpringArm3D = player.get_node_or_null("Pivot/SpringArm3D")
	if arm != null:
		arm.spring_length = 4.6
	if pivot != null:
		pivot.rotation.y = player.global_rotation.y + PI * 0.5

	# 拔刀（不播拔刀動畫，直接切狀態 —— 我們要拍的是突刺）
	player.set("sword_state", 2)          # DRAWN
	player.call("_apply_sword_visibility")
	player.set("sun_mastery", 3)          # 捌型 required_mastery = 3
	player.set("sun_breath_gauge", 100.0)
	player.set("action_state", 0)         # FREE
	player.set("input_locked", true)      # 不要被輸入干擾
	for i in 10:
		await process_frame

	var grounded: bool = player.call("is_on_floor")
	print("[捌型] 著地 = %s、位置 = %s" % [grounded, player.global_position])

	var ok: bool = player.call("execute_form", 8)
	print("[捌型] execute_form(8) = %s（原因：%s）" % [
		ok, player.call("form_block_reason", 8)])
	if not ok:
		push_error("[捌型] 發不出來，無法拍攝")
		quit(1)
		return

	var dir := DirAccess.open("user://")
	if dir != null and not dir.dir_exists("form08_ingame"):
		dir.make_dir("form08_ingame")

	var elapsed := 0.0
	var shot_i := 0
	while shot_i < SHOTS.size():
		await RenderingServer.frame_post_draw
		elapsed += get_root().get_process_delta_time()
		var target: float = float(SHOTS[shot_i]["t"])
		if elapsed >= target:
			var img: Image = get_root().get_texture().get_image()
			var path: String = "%s/form08_%s.png" % [OUT_DIR, SHOTS[shot_i]["name"]]
			img.save_png(path)
			print("  %s  t=%.2f s → %s" % [
				SHOTS[shot_i]["label"], elapsed, ProjectSettings.globalize_path(path)])
			shot_i += 1
		if elapsed > 2.0:
			break

	print("[捌型] 連拍完成：%s" % ProjectSettings.globalize_path(OUT_DIR))
	quit(0)

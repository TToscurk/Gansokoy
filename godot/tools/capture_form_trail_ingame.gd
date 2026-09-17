extends SceneTree
## 型刀光實機連拍：陸ノ型 飛輪陽炎（橫斬＋長尾）與 貳ノ型 碧羅天（旋轉）。
##
## 執行：
##   godot --path godot -s tools/capture_form_trail_ingame.gd
##   （要視窗，不能 --headless；只讀場景、寫 PNG 到 user://，不碰 .tscn）
##
## 驗的是兩件 headless 判不了的事：
##   1. 收招後火還掛著（陸型 real 0.37 s、trail.lifetime 0.50 s → 拍到 0.9 s）
##   2. 旋轉型的火圈是刀掃出來的，不是掛在角色身上的環

const OUT_DIR := "user://form_trail_ingame"
const SHOTS := {
	6: [0.08, 0.20, 0.32, 0.45, 0.62, 0.90],
	2: [0.25, 0.55, 0.85, 1.15, 1.45, 1.90],
}


func _initialize() -> void:
	create_timer(60.0).timeout.connect(func(): push_error("watchdog"); quit(2))
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
		push_error("找不到玩家")
		quit(1)
		return

	var dir := DirAccess.open("user://")
	if dir != null and not dir.dir_exists("form_trail_ingame"):
		dir.make_dir("form_trail_ingame")

	# 3/4 俯視：橫斬與旋轉都是水平面的動作，側面正視會壓成一條線。
	var pivot: Node3D = player.get_node_or_null("Pivot")
	var arm: SpringArm3D = player.get_node_or_null("Pivot/SpringArm3D")
	if arm != null:
		arm.spring_length = 5.2
	if pivot != null:
		pivot.rotation.y = player.global_rotation.y + PI * 0.75
		pivot.rotation.x = deg_to_rad(-22.0)

	player.set("sword_state", 2)
	player.call("_apply_sword_visibility")
	player.set("sun_mastery", 4)
	player.set("input_locked", true)
	for i in 10:
		await process_frame

	for form_id in [6, 2]:
		player.set("sun_breath_gauge", 100.0)
		player.set("action_state", 0)
		for i in 30:
			await process_frame
		var ok: bool = player.call("execute_form", form_id, true)
		print("[型%d] execute_form = %s（%s）" % [form_id, ok, player.call("form_block_reason", form_id)])
		if not ok:
			continue
		var elapsed := 0.0
		var shot_i := 0
		var times: Array = SHOTS[form_id]
		while shot_i < times.size():
			await RenderingServer.frame_post_draw
			elapsed += get_root().get_process_delta_time()
			if elapsed >= float(times[shot_i]):
				var img: Image = get_root().get_texture().get_image()
				var path := "%s/form%02d_t%03d.png" % [OUT_DIR, form_id, int(round(float(times[shot_i]) * 100.0))]
				img.save_png(path)
				print("  t=%.2f  runs=%d  → %s" % [elapsed, player._sword_trail._runs.size(), ProjectSettings.globalize_path(path)])
				shot_i += 1
			if elapsed > 3.0:
				break
		# 等尾巴燒完再下一招
		for i in 90:
			await process_frame

	print("完成：%s" % ProjectSettings.globalize_path(OUT_DIR))
	quit(0)

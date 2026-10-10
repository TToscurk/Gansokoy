extends SceneTree
## 人間之里 V2 實走驗證（F5 同路徑，需要 GPU 視窗，不能 --headless）。
##
##   Godot --rendering-method gl_compatibility --path godot --script res://tools/walk_village_v2.gd [-- --out=<png 前綴>]
##
## main.tscn 當 current_scene、load_map("village_v2", "trail")，以 move_forward 動作沿 ROUTE 走，
## 每個路點用 snap_yaw 對準。每段印一行 [WALK] ✓/✗；結尾 quit(失敗數)。
## 失敗＝該段 40 秒內沒走到 2.5 m 內（卡住、掉出地圖都算），或全程腳下與地形高差 > MAX_FOOT_GAP。
## P0 凍結基準（v2-layout-0.3，2026-09-23 r3）：19/19 段抵達，最大高差 0.07 m。

const MAX_FOOT_GAP := 0.3
const ROUTE := [
	["南入口", Vector2(224, 164)],
	["鳥居下", Vector2(234, 101)],
	["主街南段", Vector2(236, 80)],
	["主街中段", Vector2(242, 40)],
	["主街", Vector2(262, -20)],
	["主街北段", Vector2(280, -80)],
	["主街北端", Vector2(300, -130)],
	["丘腳街東", Vector2(342, -128)],
	["水渠橋東", Vector2(370, -128)],
	["回丘腳街", Vector2(342, -128)],
	["龍神道", Vector2(356, -152)],
	["龍神像旁", Vector2(372, -178)],
	["龍神橋西", Vector2(378, -205)],
	["龍神橋東", Vector2(420, -205)],
	["回龍神橋西", Vector2(378, -205)],
	["龍神道回丘腳", Vector2(342, -128)],
	["主街北端", Vector2(300, -130)],
	["參道 1", Vector2(292, -160)],
	["參道 2", Vector2(280, -190)],
]

var out := ""
var main: Node
var player: CharacterBody3D


func _init() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _snap(tag: String) -> void:
	if out == "":
		return
	var img := root.get_texture().get_image()
	if img != null:
		img.save_png("%s_%s.png" % [out, tag])


func _ground(x: float, z: float) -> float:
	var space := player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 200, z), Vector3(x, -50, z))
	q.exclude = [player.get_rid()]
	var hit := space.intersect_ray(q)
	return hit.position.y if hit else -INF


func _hide_ui() -> void:
	for cl in root.find_children("*", "CanvasLayer", true, false):
		(cl as CanvasLayer).visible = false
	var dbg: Node = main.map_root.get_node_or_null("Debug")
	if dbg:
		dbg.visible = false


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	var sf := root.get_node("/root/StoryFlags")
	sf.set_flag("woke_in_trail", true)
	sf.set_flag("met_reimu", true)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	# P11 R2：--candidate=A|B|C（候補スクリプトをメモリ上で差し替え、ファイル不変；tools/p11r2/p11r2_swap.gd）
	var _cand: String = preload("res://tools/p11r2/p11r2_swap.gd").parse(OS.get_cmdline_user_args())
	if _cand != "":
		print("[P11R2] candidate ", preload("res://tools/p11r2/p11r2_swap.gd").apply(main, _cand))
	root.add_child(main)
	current_scene = main
	await _frames(60)
	main.load_map("village_v2", "trail")
	await _frames(90)
	player = main.player
	print("[WALK] map=%s 落地 (%.1f, %.2f, %.1f) 地面 %.2f" % [main.current_id,
		player.global_position.x, player.global_position.y, player.global_position.z,
		_ground(player.global_position.x, player.global_position.z)])
	_hide_ui()
	var fails := 0
	var max_dy := 0.0
	var seg := 0
	for wp in ROUTE:
		var target: Vector2 = wp[1]
		var t0 := Time.get_ticks_msec()
		var stuck_frames := 0
		var last := Vector2(player.global_position.x, player.global_position.z)
		var reached := false
		Input.action_press("move_forward")
		for f in 60 * 40:
			var p := Vector2(player.global_position.x, player.global_position.z)
			var d := target - p
			if d.length() < 2.5:
				reached = true
				break
			if f % 6 == 0:
				player.snap_yaw(atan2(-d.x, -d.y))
			await physics_frame
			var np := Vector2(player.global_position.x, player.global_position.z)
			stuck_frames = stuck_frames + 1 if np.distance_to(last) < 0.01 else 0
			last = np
			if f % 30 == 0:
				var gy := _ground(np.x, np.y)
				if gy != -INF:
					max_dy = maxf(max_dy, absf(player.global_position.y - gy))
			if stuck_frames > 90 or player.global_position.y < -20.0:
				break
		Input.action_release("move_forward")
		await _frames(4)
		var pp := player.global_position
		var gy2 := _ground(pp.x, pp.z)
		if not reached:
			fails += 1
		print("[WALK] %s %-10s → (%.0f,%.0f) 位置 (%.1f, %.2f, %.1f) 腳下地面 %.2f 差 %.2f  %d ms%s" % [
			"✓" if reached else "✗", wp[0], target.x, target.y, pp.x, pp.y, pp.z, gy2,
			pp.y - gy2, Time.get_ticks_msec() - t0, "（卡住）" if stuck_frames > 90 else ""])
		if seg % 3 == 0 or not reached:
			await _frames(20)
			_snap("%02d" % seg)
		seg += 1
	if max_dy > MAX_FOOT_GAP:
		fails += 1
	print("[WALK] 結果：%d/%d 段抵達、最大 |玩家y−地面| %.2f m（上限 %.2f m）；失敗 %d" % [
		ROUTE.size() - (fails - (1 if max_dy > MAX_FOOT_GAP else 0)), ROUTE.size(), max_dy, MAX_FOOT_GAP, fails])
	quit(fails)

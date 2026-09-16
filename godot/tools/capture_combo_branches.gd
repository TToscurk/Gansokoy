extends SceneTree
## 左右鍵互搭連段實機連拍：段1 → RMB → 陸型（火光）→ 段2 → RMB → 伍型 → 段3 → RMB → 拾貳型；
## 再拍 RMB → LMB → 拾壹型。每一型在關鍵時點截圖（真實光照、掛刀、刀光、起手火光）。
##   godot --path godot -s tools/capture_combo_branches.gd   （要視窗）
## 輸出 user://combo_ingame/<name>.png

const OUT_DIR := "user://combo_ingame"

var _cam: Camera3D = null
var _player: Node3D = null
var _elapsed := 0.0
var _n := 0


func _follow() -> void:
	var vis: Node3D = _player.get_node_or_null("BodyVisual")
	var b: Basis = vis.global_transform.basis if vis != null else _player.global_transform.basis
	# 側前 3/4：看得到刀的行程與火光
	var eye: Vector3 = _player.global_position + b.z * 2.4 + (-b.x) * 2.6 + Vector3(0, 1.3, 0)
	_cam.look_at_from_position(eye, _player.global_position + Vector3(0, 0.9, 0))


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_root().get_texture().get_image()
	var path := "%s/%02d_%s.png" % [OUT_DIR, _n, name]
	img.save_png(path)
	print("  %s  t=%.2f  form=%d stage=%d anim=%s → %s" % [name, _elapsed, _player.get("active_form"),
		_player.get("combo_stage"), _player.get("_active_attack_name"), ProjectSettings.globalize_path(path)])
	_n += 1


func _frames(n: int) -> void:
	for i in n:
		await process_frame
		_elapsed += get_root().get_process_delta_time()
		_follow()


## 等到 active_form == id（最多 max 幀），然後再等 extra 幀拍在動作最大處。
func _until_form(id: int, max_f := 90) -> bool:
	for i in max_f:
		await _frames(1)
		if int(_player.get("active_form")) == id:
			return true
	return false


func _initialize() -> void:
	var flags: Node = get_root().get_node_or_null("StoryFlags")
	if flags != null:
		flags.set_flag("woke_in_trail", true)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(main)
	for i in 60:
		await process_frame
	_player = main.get("player")
	var dm: Node = get_root().get_node_or_null("DialogueManager")
	if dm != null:
		dm.set("_dialogue_id", "__capture_mute__")
	var dir := DirAccess.open("user://")
	if dir != null and not dir.dir_exists("combo_ingame"):
		dir.make_dir("combo_ingame")
	_cam = Camera3D.new()
	get_root().add_child(_cam)
	_cam.fov = 42.0
	_cam.current = true
	_player.set("sword_state", 2)
	_player.call("_apply_sword_visibility")
	_player.set("input_locked", true)
	_player.set("sun_mastery", 4)
	await _frames(10)
	print("[連段] 著地 = %s、位置 = %s" % [_player.call("is_on_floor"), _player.global_position])
	await _shot("idle")

	# 段1 → RMB → 陸型
	_player.call("request_primary_attack")
	await _frames(3)
	await _shot("stage1")
	_player.call("request_heavy_cut")
	var ok := await _until_form(6)
	await _shot("form06_ignite")
	await _frames(8)
	await _shot("form06_sweep")
	print("[連段] 陸型 = %s" % ok)
	await _frames(40)

	# 段1 → 段2 → RMB → 伍型
	_player.call("request_primary_attack")
	await _frames(2)
	_player.call("request_primary_attack")
	for i in 40:
		await _frames(1)
		if int(_player.get("combo_stage")) == 2:
			break
	await _shot("stage2")
	_player.call("request_heavy_cut")
	ok = await _until_form(5)
	await _frames(1)
	await _shot("form05_ignite")
	await _frames(7)
	await _shot("form05_rising")
	print("[連段] 伍型 = %s" % ok)
	await _frames(40)

	# 段1 → 段2 → 段3 → RMB → 拾貳型
	_player.call("request_primary_attack")
	await _frames(2)
	_player.call("request_primary_attack")
	for i in 40:
		await _frames(1)
		if int(_player.get("combo_stage")) == 2:
			break
	_player.call("request_primary_attack")
	for i in 40:
		await _frames(1)
		if int(_player.get("combo_stage")) == 3:
			break
	await _shot("stage3")
	_player.call("request_heavy_cut")
	ok = await _until_form(12)
	await _frames(4)
	await _shot("form12_raise")
	await _frames(6)
	await _shot("form12_chop")
	await _frames(12)
	await _shot("form12_rise")
	print("[連段] 拾貳型 = %s" % ok)
	await _frames(45)

	# RMB 聚力 → LMB → 拾壹型
	_player.call("request_heavy_cut")
	await _frames(3)
	await _shot("heavy_cut")
	_player.call("request_primary_attack")
	ok = await _until_form(11)
	await _frames(4)
	await _shot("form11_dodge")
	await _frames(7)
	await _shot("form11_counter")
	print("[連段] 拾壹型 = %s" % ok)
	await _frames(30)

	print("[連段] 連拍完成：%s" % ProjectSettings.globalize_path(OUT_DIR))
	quit(0)

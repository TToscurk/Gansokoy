extends SceneTree
## 死亡演出實機連拍：倒地 → 壓暗 → 「死」 → 全黑 → 重生淡入。
##   godot --path godot -s tools/capture_death_ingame.gd   （要視窗）
## 輸出 user://death_ingame/death_<t>.png

const OUT_DIR := "user://death_ingame"
const SHOTS := [0.6, 1.6, 2.6, 3.6, 4.6, 5.6, 6.4]

var _cam: Camera3D = null
var _player: Node3D = null


func _follow() -> void:
	var vis: Node3D = _player.get_node_or_null("BodyVisual")
	var b: Basis = vis.global_transform.basis if vis != null else _player.global_transform.basis
	var eye: Vector3 = _player.global_position + b.z * 2.6 + (-b.x) * 2.0 + Vector3(0, 1.4, 0)
	_cam.look_at_from_position(eye, _player.global_position + Vector3(0, 0.8, 0))


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
	if dir != null and not dir.dir_exists("death_ingame"):
		dir.make_dir("death_ingame")
	_cam = Camera3D.new()
	get_root().add_child(_cam)
	_cam.fov = 45.0
	_cam.current = true
	_player.set("sword_state", 2)
	_player.call("_apply_sword_visibility")
	for i in 10:
		await process_frame
	var start: Vector3 = _player.global_position
	_player.global_position = start + Vector3(2.5, 0, 0)   # 離出生點 2.5 m，看得出重生有搬回去
	for i in 5:
		await process_frame
	_player.call("take_hit", {"damage": 100000.0, "posture_damage": 0.0})
	var t := 0.0
	var i := 0
	while i < SHOTS.size():
		await RenderingServer.frame_post_draw
		t += get_root().get_process_delta_time()
		_follow()
		if t >= float(SHOTS[i]):
			var img: Image = get_root().get_texture().get_image()
			var path := "%s/death_%02d.png" % [OUT_DIR, int(SHOTS[i] * 10)]
			img.save_png(path)
			print("  t=%.1f pos=%s → %s" % [t, _player.global_position, ProjectSettings.globalize_path(path)])
			i += 1
	print("[死] 起點 %s、重生後 %s、距離 %.2f m" % [start, _player.global_position, start.distance_to(_player.global_position)])
	quit(0)

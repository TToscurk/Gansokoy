extends SceneTree
## 反應動畫組：實機連拍（真地面、真掛刀、AnimationTree 混合）。
##
##   godot --path godot -s tools/capture_react_ingame.gd   （要視窗）
##
## 輸出 user://react_ingame/react_<tag>.png：架勢 / 格擋 / 彈刀 / 受擊 / 軀幹爆 / 死亡。

const OUT_DIR := "user://react_ingame"

var _cam: Camera3D = null
var _player: Node3D = null


## 前 3/4 側 2.9 m，看向胸口。BodyVisual 才是視覺朝向（Player 根不一定）。
func _follow() -> void:
	if _cam == null or _player == null:
		return
	var vis: Node3D = _player.get_node_or_null("BodyVisual")
	var b: Basis = vis.global_transform.basis if vis != null else _player.global_transform.basis
	var fwd: Vector3 = b.z   # README：BodyVisual 面朝 +Z（_on_hit_target 用 _visual.basis.z 當前向）
	var right: Vector3 = -b.x
	var eye: Vector3 = _player.global_position + fwd * 2.2 + right * 1.8 + Vector3(0, 1.3, 0)
	_cam.look_at_from_position(eye, _player.global_position + Vector3(0, 0.95, 0))


func _frames(n: int) -> void:
	for i in n:
		await physics_frame
		_follow()
		await process_frame


func _hit(dmg := 20.0, pdmg := 12.0) -> Dictionary:
	return {"damage": dmg, "posture_damage": pdmg, "hit_dir": Vector3(0, 0, -1), "hit_pos": Vector3(0, 1, 0)}


func _shot(name: String) -> void:
	_follow()
	await RenderingServer.frame_post_draw
	var img: Image = get_root().get_texture().get_image()
	var path := "%s/react_%s.png" % [OUT_DIR, name]
	img.save_png(path)
	print("  shot %s → %s" % [name, ProjectSettings.globalize_path(path)])


func _initialize() -> void:
	var flags: Node = get_root().get_node_or_null("StoryFlags")
	if flags != null:
		flags.set_flag("woke_in_trail", true)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(main)
	await _frames(60)
	var player: Node = main.get("player")
	if player == null:
		push_error("[react] 找不到玩家")
		quit(1)
		return
	var dir := DirAccess.open("user://")
	if dir != null and not dir.dir_exists("react_ingame"):
		dir.make_dir("react_ingame")

	# 自己的相機：玩家相機 adapter 每幀 lerp 回預設 8.5 m，拍不到動作。
	# 前 3/4 側，2.8 m，看向胸口。
	# 相機掛在玩家底下（受擊會後退 1.6 m，固定相機會把人拍出畫面），
	# 位置寫在玩家 local：前 3/4 側 2.8 m，看向胸口。
	var p: Node3D = player
	# 對話一開就蓋畫面（醒來獨白 Area3D 就在 spawn 旁）：把 DialogueManager 標成
	# 已在對話中（_dialogue_id 非空 → start() 直接回 false），整段拍攝都不會開對話。
	var dm: Node = get_root().get_node_or_null("DialogueManager")
	if dm != null:
		dm.set("_dialogue_id", "__capture_mute__")
	# 相機放世界層，每幀跟著玩家（_follow）：視覺朝向用 BodyVisual 的 -Z。
	_cam = Camera3D.new()
	root.add_child(_cam)
	_cam.fov = 45.0
	_cam.current = true
	_player = p
	_follow()
	player.set("sword_state", 2)
	player.call("_apply_sword_visibility")
	player.set("input_locked", true)
	await _frames(10)
	await _shot("00_idle")

	# 架勢
	player.set("input_locked", false)
	player.call("begin_guard")
	await _frames(int(0.35 * 60))
	await _shot("01_guard")
	# 格擋受衝（晚舉盾）
	player.call("take_hit", _hit())
	await _frames(4)
	await _shot("02_block")
	await _frames(30)
	# 彈刀：放開重舉
	player.call("end_guard")
	await _frames(20)
	player.posture.heal_full()
	player.call("begin_guard")
	await _frames(1)
	player.call("take_hit", _hit())
	await _frames(3)
	await _shot("03_deflect")
	await _frames(30)
	player.call("end_guard")
	await _frames(20)
	# 受擊
	player.posture.heal_full()
	player.call("take_hit", _hit())
	await _frames(4)
	await _shot("04_hit")
	await _frames(40)
	# 軀幹爆
	player.posture.heal_full()
	while not player.posture.is_broken() and player.posture.health > 5.0:
		player.call("take_hit", _hit(1.0, 40.0))
		await _frames(1)
	await _frames(12)
	await _shot("05_stagger")
	await _frames(int(player.posture.break_time * 60) + 20)
	# 死亡
	player.posture.heal_full()
	await _frames(5)
	player.call("take_hit", _hit(10000.0, 0.0))
	await _frames(int(1.2 * 60))
	await _shot("06_dying")
	await _frames(int(2.2 * 60))
	await _shot("07_dead")
	print("[react] 完成：%s" % ProjectSettings.globalize_path(OUT_DIR))
	quit(0)

extends SceneTree
## 冥想姿勢候選：把 Dead clip 定格在幾個時間點，從側前方拍下來看哪一格像跪坐。
##   <godot_console.exe> --path godot --script res://tools/_shot_sit_candidates.gd -- --map=slice
const OUT := "D:/神社/shrine/work/shots/meditation/"
const CANDIDATES := [0.0, 0.35, 0.70, 1.05, 1.40, 1.80]

var _main: Node


func _init() -> void:
	_run.call_deferred()


func _settle(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame


func _shot(name: String) -> void:
	await _settle(12)
	await RenderingServer.frame_post_draw
	await process_frame
	DirAccess.make_dir_recursive_absolute(OUT)
	root.get_viewport().get_texture().get_image().save_png(OUT + name + ".png")
	print("[SHOT] ", name)


func _run() -> void:
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	await _settle(6)
	var ui := root.find_child("DialogueUI", true, false)
	if ui != null:
		ui.queue_free()
	var day := root.get_node_or_null("/root/DayNight")
	if day != null:
		day.set("flowing", false)
		day.call("set_hour", 11.0)
	_main.load_map("slice", "trail")
	await _settle(90)

	var player: Node3D = _main.player
	player.set("input_locked", true)
	player.velocity = Vector3.ZERO
	player.global_position = Vector3(-13.78, 6.0, -26.82)
	await _settle(40)

	# 側前方固定鏡位：距 3.2 m、高 1.35 m，看向角色胸口
	var cam := Camera3D.new()
	cam.fov = 45.0
	_main.add_child(cam)
	cam.current = true
	var look := player.global_position + Vector3(0.0, 0.65, 0.0)
	cam.global_position = look + Vector3(2.6, 0.75, 2.0)
	cam.look_at(look, Vector3.UP)
	await _settle(10)

	var anim: AnimationPlayer = null
	for n in player.find_children("*", "AnimationPlayer", true, false):
		anim = n
		break
	var tree: AnimationTree = null
	for n in player.find_children("*", "AnimationTree", true, false):
		tree = n
		break
	if anim == null:
		print("[SHOT] 找不到 AnimationPlayer")
		quit(1)
		return
	if tree != null:
		tree.active = false
	var clip_name := ""
	for n in anim.get_animation_list():
		if String(n).to_lower().contains("dead"):
			clip_name = String(n)
	print("[SHOT] 用 clip=", clip_name, " 長度=", anim.get_animation(clip_name).length)
	for t in CANDIDATES:
		anim.play(clip_name)
		anim.seek(t, true)
		anim.speed_scale = 0.0
		await _shot("sit_t%.2f" % float(t))
	anim.speed_scale = 0.0
	print("[SHOT] 完成")
	quit(0)

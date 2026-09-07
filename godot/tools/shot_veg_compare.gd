extends SceneTree
## 減面前後對照截圖：河岸灌木、街景樹、遠景各一張，固定機位。
##   Godot --path godot --resolution 1280x720 --script tools/shot_veg_compare.gd -- <tag>
const OUT := "D:/神社/shrine/work/shots/veg/"
const SHOTS := [
	# name, cam xyz, look xyz
	["1_riverbank", Vector3(300.0, 6.0, 40.0), Vector3(300.0, 2.0, 10.0)],
	["2_street_trees", Vector3(250.0, 8.0, 60.0), Vector3(250.0, 4.0, 10.0)],
	["3_wide", Vector3(300.0, 55.0, 240.0), Vector3(280.0, 0.0, 40.0)],
	["4_shrub_close", Vector3(296.0, 3.0, 22.0), Vector3(300.0, 1.5, 12.0)],
]
var main: Node
var tag := "before"


func _init() -> void:
	_run.call_deferred()


func _settle(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		tag = a
	DirAccess.make_dir_recursive_absolute(OUT)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _settle(20)
	main.load_map("slice", "")
	await _settle(60)
	main.player.visible = false
	# ⚠ --script 模式編譯期看不到 autoload（Identifier not found: DayNight），
	#   一律動態取節點。
	var dn: Node = root.get_node_or_null("/root/DayNight")
	if dn != null:
		dn.set("flowing", false)
		dn.call("set_hour", 11.0)
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.current = true
	cam.far = 1200.0
	for s in SHOTS:
		cam.global_position = s[1]
		cam.look_at(s[2])
		await _settle(40)
		var img := main.get_viewport().get_texture().get_image()
		var p := "%s%s_%s.png" % [OUT, s[0], tag]
		img.save_png(p)
		print("[VEGSHOT] %s" % p)
	quit(0)

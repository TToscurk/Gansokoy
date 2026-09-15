extends SceneTree
## 遠景樹 r2 前後對照截圖。VistaTrees 已刪，這裡改切換四個「遠景樹_*」節點。
##   Godot --path godot --script tools/shot_vista_trees_ab.gd

const OUT := "D:/神社/shrine/_review/shrine_trees/"
## [檔名, 相機位置, 看向]
const SHOTS := [
	["A_court_south", Vector3(0.0, 0.9, 0.0), Vector3(0.0, -2.0, 70.0)],
	["B_exit_down", Vector3(0.0, 0.6, 47.0), Vector3(0.0, -2.5, 90.0)],
	["C_pad_south", Vector3(0.0, -3.2, 72.0), Vector3(0.0, -4.0, 140.0)],
	# ⚠ 境內 z≈−10 是拜殿月台（y≈3.5）底下，相機放那會拍到石板背面、畫面倒轉。
	#   往西的機位改放 z=+20（參道上，地面 y≈−1.2）。
	["D_court_west", Vector3(0.0, 0.5, 20.0), Vector3(-70.0, 2.0, 5.0)],
	["E_aerial", Vector3(0.0, 60.0, 140.0), Vector3(0.0, -2.0, 30.0)],
]


func _init() -> void:
	_run.call_deferred()


func _wait(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var scn: Node3D = load("res://maps/shrine/shrine.tscn").instantiate()
	root.add_child(scn)
	await _wait(40)
	var groups: Array = []
	for c in scn.get_children():
		if String(c.name).begins_with("遠景樹_"):
			groups.append(c)
	print("GROUPS %d" % groups.size())
	var cam := Camera3D.new()
	cam.far = 3000.0
	scn.add_child(cam)
	cam.current = true
	for s in SHOTS:
		cam.global_position = s[1]
		cam.look_at(s[2], Vector3.UP)
		await _wait(8)
		var path: String = OUT + "%s_r2.png" % s[0]
		root.get_viewport().get_texture().get_image().save_png(path)
		print("[V] %s" % path)
	quit(0)

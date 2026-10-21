extends SceneTree
## 地形診斷：用中性灰材質＋斜光拍地形本身（排除貼圖／遮罩），確認橫紋是幾何還是材質。
##   godot --path godot --resolution 1280x720 --script res://tools/shrine_v2/diag_terrain.gd -- --out=<dir> [--wire=1]
## 相機清單寫在下方 CAMS（x,y,z → look x,y,z）。需要畫面。

const CAMS := [
	["d1_stairtop", [0, 10.5, 10], [0, 9, -30]],
	["d2_west_slope", [-12, 11, -10], [-40, 14, -10]],
	["d3_valley", [0, 3.5, 62], [0, 5, 20]],
	["d4_overview", [75, 75, 115], [0, 6, -10]],
]

var _out := "D:/神社/shrine/_review/shrine_v2/diag"


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var wire := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a == "--wire=1":
			wire = true
	DirAccess.make_dir_recursive_absolute(_out)
	var world := Node3D.new()
	root.add_child(world)
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.62, 0.72, 0.84)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.58, 0.62)
	e.ambient_light_energy = 0.6
	we.environment = e
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.7
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-35, 140, 0)
	world.add_child(sun)
	var mi := MeshInstance3D.new()
	mi.mesh = load("res://maps/shrine_v2/gen/terrain.res")
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.72, 0.72, 0.70)
	m.roughness = 1.0
	if wire:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0.05, 0.05, 0.05)
		m.wireframe = true if false else false
	mi.material_override = m
	world.add_child(mi)
	var cam := Camera3D.new()
	cam.far = 3000.0
	world.add_child(cam)
	cam.current = true
	for c in CAMS:
		var p: Array = c[1]
		var l: Array = c[2]
		cam.global_position = Vector3(p[0], p[1], p[2])
		cam.look_at(Vector3(l[0], l[1], l[2]))
		for i in 6:
			await process_frame
		root.get_texture().get_image().save_png("%s/%s.png" % [_out, c[0]])
		print("[DIAG] ", c[0])
	quit()

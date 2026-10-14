extends SceneTree
## P13 W9：w9_kit 審圖（非 headless）。全 22 構件 LOD0 を 1 枚に並べ、正面斜め／近接の 2 画面を保存する。
##   godot --path . --script res://tools/p13/w9/w9_kit_review.gd -- OUTDIR [name1,name2,…]
## 光：日照 10:00 相当（太陽 −48°／方位 −35°）＋ 天空 ambient。地面は一枚の薄い平面（V2 草地に近い緑灰）。
const DIR := "res://assets/village_v2/w9_kit"

var cam: Camera3D
var outdir := ""


func _init() -> void:
	_run.call_deferred()


func _shot(path: String, pos: Vector3, look: Vector3, fov := 38.0) -> void:
	cam.fov = fov
	cam.global_position = pos
	cam.look_at(look, Vector3.UP)
	await process_frame
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(path)
	print("[W9R] ", path)


func _run() -> void:
	var a := OS.get_cmdline_user_args()
	outdir = a[0]
	DirAccess.make_dir_recursive_absolute(outdir)
	var only: PackedStringArray = a[1].split(",") if a.size() > 1 else PackedStringArray()
	var _tag := a[2] if a.size() > 2 else "k"
	root.size = Vector2i(1600, 900)
	var man: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIR + "/src/modules_blender.json"))["modules"]
	var names: Array = []
	var kit_of := {}
	for n: String in man:
		if not n.ends_with("_l1") and (only.is_empty() or n.trim_prefix("w9_") in only or n in only):
			names.append(n)
			kit_of[n] = "w9_kit"
	for o: String in only:
		if o.contains(":"):
			var kn := o.split(":")
			var jf := "res://assets/village_v2/%s/src/modules_blender.json" % kn[0]
			var mm: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(jf))["modules"]
			if mm.has(kn[1]):
				man[kn[1]] = mm[kn[1]]
				names.append(kn[1])
				kit_of[kn[1]] = kn[0]
			else:
				print("[W9R] 無し ", o)
	var w := Node3D.new()
	root.add_child(w)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.62, 0.7, 0.8)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.72, 0.76, 0.84)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	w.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	w.add_child(sun)
	var cols := mini(6, maxi(names.size(), 1))
	var rows := ceili(names.size() / float(cols))
	var gap := 3.4
	var gr := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(gap * cols + 4.0, gap * rows + 4.0)
	gr.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.36, 0.40, 0.30)
	gm.roughness = 1.0
	gr.material_override = gm
	gr.position = Vector3(gap * (cols - 1) / 2.0, -0.01, gap * (rows - 1) / 2.0)
	w.add_child(gr)
	var i := 0
	var centers := {}
	for n: String in names:
		var mi := MeshInstance3D.new()
		mi.mesh = load("res://assets/village_v2/%s/mesh/%s.res" % [kit_of[n], n])
		mi.name = n
		var c := i % cols
		var r := i / cols
		mi.position = Vector3(gap * c, 0.0, gap * r)
		w.add_child(mi)
		centers[n] = mi.position
		i += 1
	cam = Camera3D.new()
	w.add_child(cam)
	cam.current = true
	var cx := gap * (cols - 1) / 2.0
	var cz := gap * (rows - 1) / 2.0
	await _shot(outdir + "/%s_all.png" % _tag, Vector3(cx, 11.0, cz + gap * rows * 1.05 + 3.5), Vector3(cx, 0.8, cz), 46.0)
	# 個別の近接（0.6 画面幅で 3/4 から）
	var idx := 0
	for n: String in names:
		var p: Vector3 = centers[n]
		var dim: Array = man[n]["dims"]
		var hgt: float = maxf(float(dim[4]), 0.5)
		var wid: float = maxf(float(dim[3]) - float(dim[0]), 0.6)
		var d := maxf(hgt, wid) * 2.0 + 0.8
		await _shot(outdir + "/%s_%02d_%s.png" % [_tag, idx, n.trim_prefix("w9_")], p + Vector3(d * 0.55, hgt * 0.55 + 0.2, d * 0.85), p + Vector3(0, hgt * 0.45, 0), 40.0)
		idx += 1
	quit(0)

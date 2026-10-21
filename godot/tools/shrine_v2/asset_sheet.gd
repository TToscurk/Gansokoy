extends SceneTree
## shrine_v2 資產目視頁：每個資產拍一張 3/4 視角小圖（自動依 AABB 取景），存成 tile_XX.png。
## 需要畫面（不可加 --headless）：
##   godot --path godot --resolution 560x560 --script res://tools/shrine_v2/asset_sheet.gd -- --out=<dir> --list=<a>|<b>|...
## 可選：--yaw=35 --pitch=16 --dist=2.2；清單項目可寫成 "path@yaw" 針對單項覆寫朝向。
## 只負責拍 tile；拼圖／標籤由 tools/shrine_v2/make_sheet.py 做。

var _out := "D:/神社/shrine/_review/shrine_v2/sheet"
var _yaw := 35.0
var _pitch := 16.0
var _dist := 2.3


func _init() -> void:
	_run.call_deferred()


func _walk(n: Node, xf: Transform3D, acc: Array) -> void:
	var cur := xf
	if n is Node3D:
		cur = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var mi := n as MeshInstance3D
		if mi.visible:
			acc.append(cur * mi.mesh.get_aabb())
	for c in n.get_children():
		_walk(c, cur, acc)


func _run() -> void:
	var list: PackedStringArray = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--list="):
			list = a.substr(7).split("|")
		elif a.begins_with("--yaw="):
			_yaw = float(a.substr(6))
		elif a.begins_with("--pitch="):
			_pitch = float(a.substr(8))
		elif a.begins_with("--dist="):
			_dist = float(a.substr(7))
	DirAccess.make_dir_recursive_absolute(_out)

	var world := Node3D.new()
	root.add_child(world)
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.62, 0.68, 0.74)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.70, 0.72, 0.76)
	e.ambient_light_energy = 0.9
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = e
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	world.add_child(sun)
	sun.rotation_degrees = Vector3(-48, 150, 0)
	# 地面小圓盤：看出腳底
	var ground := MeshInstance3D.new()
	var gm := CylinderMesh.new()
	gm.top_radius = 6.0
	gm.bottom_radius = 6.0
	gm.height = 0.02
	ground.mesh = gm
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.40, 0.42, 0.36)
	ground.material_override = gmat
	world.add_child(ground)
	var cam := Camera3D.new()
	cam.fov = 38.0
	cam.near = 0.02
	cam.far = 2000.0
	world.add_child(cam)
	cam.current = true

	var idx := 0
	var names: Array[String] = []
	for item in list:
		var path := String(item)
		var yaw := _yaw
		if "@" in path:
			var parts := path.split("@")
			path = parts[0]
			yaw = float(parts[1])
		if not path.begins_with("res://"):
			path = "res://" + path
		var res := ResourceLoader.load(path)
		var inst: Node3D = null
		if res is PackedScene:
			inst = (res as PackedScene).instantiate() as Node3D
		elif res is Mesh:
			var mi0 := MeshInstance3D.new()
			mi0.mesh = res as Mesh
			inst = mi0
		if inst == null:
			print("[SHEET] 載入失敗 ", path)
			continue
		world.add_child(inst)
		await process_frame
		var boxes: Array = []
		_walk(inst, Transform3D.IDENTITY, boxes)
		var bb: AABB
		var first := true
		for b in boxes:
			if first:
				bb = b
				first = false
			else:
				bb = bb.merge(b)
		if first:
			print("[SHEET] 無網格 ", path)
			inst.queue_free()
			continue
		# 底面對齊 y=0，讓地盤圓盤當腳底
		inst.position.y -= bb.position.y
		bb.position.y = 0.0
		var c := bb.get_center()
		var r := maxf(bb.size.length() * 0.5, 0.05)
		ground.scale = Vector3(maxf(r * 0.45, 0.05), 1, maxf(r * 0.45, 0.05))
		var dir := Vector3(sin(deg_to_rad(yaw)), 0, cos(deg_to_rad(yaw)))
		var cp := c + dir * (r * _dist) + Vector3(0, r * _dist * tan(deg_to_rad(_pitch)), 0)
		cam.global_position = cp
		cam.look_at(c, Vector3.UP)
		for i in 5:
			await process_frame
		var img := root.get_texture().get_image()
		var p := "%s/tile_%02d.png" % [_out, idx]
		img.save_png(p)
		names.append("%02d|%s|%.2f x %.2f x %.2f" % [idx, path.get_file(), bb.size.x, bb.size.y, bb.size.z])
		print("[SHEET] %s" % names[-1])
		idx += 1
		inst.queue_free()
		await process_frame
	var f := FileAccess.open(_out + "/list.txt", FileAccess.WRITE)
	for n in names:
		f.store_line(n)
	f.close()
	quit()

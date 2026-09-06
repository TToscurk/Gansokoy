extends SceneTree
## 火見櫓細部審查：在預覽場景加入四台固定 Camera3D，供 MCP cinematic 逐台擷取。
## 動機：MCP 的 view_target 會改寫節點名中的「櫓」字導致 NODE_NOT_FOUND；
## 改由場景內相機取景，避開路徑傳輸問題。

func _init() -> void:
	var path: String = "res://maps/hinomiyagura/hinomiyagura.tscn"
	var scn: PackedScene = load(path)
	var root: Node3D = scn.instantiate() as Node3D

	# 先移除舊相機（可重跑）
	for c in root.get_children():
		if c is Camera3D:
			root.remove_child(c)
			c.free()

	var cams: Array = [
		# name, pos, look_at, fov, current
		["Cam_Top", Vector3(7.0, 16.5, 7.0), Vector3(0.0, 13.2, 0.0), 26.0, true],
		["Cam_Mid", Vector3(9.0, 8.0, 9.0), Vector3(0.0, 8.0, 0.0), 30.0, false],
		["Cam_Base", Vector3(6.0, 1.4, 6.0), Vector3(0.0, 2.2, 0.0), 34.0, false],
		["Cam_Far", Vector3(34.0, 9.0, 34.0), Vector3(0.0, 7.5, 0.0), 30.0, false],
	]
	for spec in cams:
		var cam: Camera3D = Camera3D.new()
		cam.name = spec[0]
		cam.position = spec[1]
		cam.fov = spec[3]
		cam.current = spec[4]
		root.add_child(cam)
		cam.owner = root
		cam.look_at(spec[2], Vector3.UP)

	var packed: PackedScene = PackedScene.new()
	packed.pack(root)
	var err: int = ResourceSaver.save(packed, path)
	print("CAMS_ADDED %d  save=%s" % [cams.size(), "OK" if err == OK else "FAIL"])
	root.free()
	quit()

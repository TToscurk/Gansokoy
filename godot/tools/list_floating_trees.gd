extends "res://tools/fix_shrine_tree_ground.gd"
## 全圖浮空樹：列出（--dry）或直接回寫 shrine.tscn。
##
##   Godot --headless --path godot --script tools/list_floating_trees.gd [-- --dry]
##
## ⚠ 回寫會整份 pack 覆寫 shrine.tscn。編輯器開著時，必須在寫完後用
##   MCP `scene_open(path, force_reload=true)` 讓編輯器重讀磁碟，
##   否則編輯器記憶體裡的舊版會在下次存檔時蓋回去。
## ⚠ 取樣高度時圖內要取 Terrain 與 Vista 的**較低者**：南出口走廊把 Vista
##   挖低了，只看 Terrain 會把走廊外緣的樹留在半空。

const THRESH := 0.35


func _run() -> void:
	var dry := "--dry" in OS.get_cmdline_user_args()
	var ps := load(SCENE) as PackedScene
	var rootn := ps.instantiate() as Node3D
	root.add_child(rootn)
	await process_frame
	var terr: MeshInstance3D = _find_terrain(rootn)
	var grid := _build_grid(terr)
	var vista_node := rootn.get_node_or_null("Vista") as MeshInstance3D
	var vgrid := _build_grid(vista_node)
	var out: Array = []
	for n in _walk(rootn):
		if _species(String(n.name)) == "":
			continue
		var node3 := n as Node3D
		if node3 == null:
			continue
		var box := _merged_aabb(node3)
		if box.size == Vector3.ZERO:
			continue
		var cx: float = box.position.x + box.size.x * 0.5
		var cz: float = box.position.z + box.size.z * 0.5
		var ab: AABB = grid["aabb"]
		var inside: bool = (cx > ab.position.x and cx < ab.position.x + ab.size.x
			and cz > ab.position.z and cz < ab.position.z + ab.size.z)
		var gy: float = _sample(grid, cx, cz) if inside else _sample(vgrid, cx, cz)
		if inside:
			var vy := _sample(vgrid, cx, cz)
			if not is_nan(vy):
				gy = minf(gy, vy)
		if is_nan(gy):
			continue
		var drift: float = box.position.y - (gy - SINK)
		if drift > THRESH:
			var p := node3.global_position
			out.append({"path": String(rootn.get_path_to(node3)),
				"x": snappedf(p.x, 0.001), "y_old": snappedf(p.y, 0.001),
				"y_new": snappedf(p.y - drift, 0.001), "z": snappedf(p.z, 0.001),
				"drift": snappedf(drift, 0.01), "src": "terrain" if inside else "vista"})
			if not dry:
				node3.global_position -= Vector3(0.0, drift, 0.0)
	out.sort_custom(func(a, b): return a.drift > b.drift)
	print("FLOATING %d" % out.size())
	print("FLOAT_LIST " + JSON.stringify(out))
	if dry:
		print("DRY RUN — 未寫檔")
		quit(0)
		return
	var packed := PackedScene.new()
	_reown(rootn, rootn)
	var err := packed.pack(rootn)
	if err != OK:
		print("pack 失敗 %d" % err)
		quit(1)
		return
	err = ResourceSaver.save(packed, SCENE)
	print("SAVE %s err=%d" % [SCENE, err])
	quit(0 if err == OK else 1)

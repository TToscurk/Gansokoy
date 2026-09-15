extends "res://tools/fix_shrine_tree_ground.gd"
## 南出口走廊挖低 Vista 之後，邊界遮蔽林在缺口兩側浮空——只量出口帶
## （z 60–100、|x| < 34）內的樹，印出每棵該落到的 y。不寫檔；套用由 MCP 做
## （編輯器開著時不能用 pack 整份覆寫 shrine.tscn）。
##   Godot --headless --path godot --script tools/ground_shrine_exit_trees.gd

const Z0 := 60.0
const Z1 := 100.0
const XH := 34.0


func _run() -> void:
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
		var p := node3.global_position
		if p.z < Z0 or p.z > Z1 or absf(p.x) > XH:
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
		# 圖內但已在走廊切坡外緣：Terrain 與 Vista 取低者（Vista 在圖內也被壓低了）
		if inside:
			var vy := _sample(vgrid, cx, cz)
			if not is_nan(vy):
				gy = minf(gy, vy)
		if is_nan(gy):
			continue
		var drift: float = box.position.y - (gy - SINK)
		if absf(drift) > 0.02:
			out.append({"path": String(rootn.get_path_to(node3)), "x": snappedf(p.x, 0.001), "z": snappedf(p.z, 0.001),
				"y_old": snappedf(p.y, 0.001), "y_new": snappedf(p.y - drift, 0.001), "drift": snappedf(drift, 0.01),
				"src": "terrain+vista" if inside else "vista"})
	print("EXIT_TREES " + JSON.stringify(out))
	quit(0)

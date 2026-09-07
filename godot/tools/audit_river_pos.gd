extends SceneTree
## 河岸植被的實際位置：用來擺對照機位（大河在 x≈430，不是村內水路 x≈300）。
##   Godot --headless --path godot --script tools/audit_river_pos.gd
var main: Node


func _init() -> void:
	_run.call_deferred()


func _settle(n: int = 4) -> void:
	for i in n:
		await physics_frame
		await process_frame


func _run() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _settle(20)
	main.load_map("slice", "")
	await _settle(50)
	var rv: Node = main.map_root.get_node_or_null("RiverVegetation")
	if rv == null:
		print("[RPOS] 找不到 RiverVegetation")
		quit(1)
		return
	var minv := Vector2(INF, INF)
	var maxv := Vector2(-INF, -INF)
	var total := 0
	# 各 z 帶的植被 x 中心，用來對準河道走向
	var by_z: Dictionary = {}
	var stack: Array[Node] = [rv]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.push_back(c)
		if not (n is MultiMeshInstance3D):
			continue
		var mmi := n as MultiMeshInstance3D
		var mm := mmi.multimesh
		if mm == null:
			continue
		for i in mm.instance_count:
			var t: Transform3D = mmi.global_transform * mm.get_instance_transform(i)
			var p := Vector2(t.origin.x, t.origin.z)
			total += 1
			minv.x = minf(minv.x, p.x); minv.y = minf(minv.y, p.y)
			maxv.x = maxf(maxv.x, p.x); maxv.y = maxf(maxv.y, p.y)
			var zk := int(round(p.y / 50.0)) * 50
			var e: Array = by_z.get(zk, [INF, -INF, 0])
			e[0] = minf(e[0], p.x); e[1] = maxf(e[1], p.x); e[2] = int(e[2]) + 1
			by_z[zk] = e
	print("[RPOS] 植株總數 %d，範圍 x[%.0f, %.0f] z[%.0f, %.0f]"
		% [total, minv.x, maxv.x, minv.y, maxv.y])
	var keys := by_z.keys()
	keys.sort()
	for k in keys:
		var e: Array = by_z[k]
		if int(e[2]) < 20:
			continue
		print("[RPOS] z≈%-6d 西岸 x=%.0f 東岸 x=%.0f 中心 x=%.0f （%d 株）"
			% [k, e[0], e[1], (float(e[0]) + float(e[1])) * 0.5, e[2]])
	quit(0)

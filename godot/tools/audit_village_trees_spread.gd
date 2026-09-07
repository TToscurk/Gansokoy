extends SceneTree
## 五份 VillageTrees 各自的世界範圍與樹的實際座標分佈。
## 用來判斷「是刻意鋪四個角落，還是誤複製疊在一起」，並產生對照拍照機位。
##   Godot --headless --path godot --script tools/audit_village_trees_spread.gd
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
	await _settle(40)
	var mr: Node = main.map_root
	var groups := []
	for c in mr.get_children():
		if String(c.name).begins_with("VillageTrees"):
			groups.append(c)
	var all_pts: Array = []
	for g in groups:
		var pts: Array = []
		var stack: Array[Node] = [g]
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
			if not (n as Node3D).is_visible_in_tree():
				continue
			for i in mm.instance_count:
				var t: Transform3D = mmi.global_transform * mm.get_instance_transform(i)
				pts.append(Vector2(t.origin.x, t.origin.z))
		if pts.is_empty():
			print("[SPREAD] %s 無可見樹" % g.name)
			continue
		var minv := Vector2(INF, INF)
		var maxv := Vector2(-INF, -INF)
		var sum := Vector2.ZERO
		for p in pts:
			minv.x = minf(minv.x, p.x); minv.y = minf(minv.y, p.y)
			maxv.x = maxf(maxv.x, p.x); maxv.y = maxf(maxv.y, p.y)
			sum += p
		var mid: Vector2 = sum / float(pts.size())
		print("[SPREAD] %-16s 樹=%-4d x[%.0f, %.0f] z[%.0f, %.0f] 範圍=%.0f×%.0f 重心=(%.0f, %.0f)"
			% [g.name, pts.size(), minv.x, maxv.x, minv.y, maxv.y,
			maxv.x - minv.x, maxv.y - minv.y, mid.x, mid.y])
		all_pts.append([String(g.name), minv, maxv, mid, pts.size()])
	# 兩兩比對：範圍是否重疊（誤複製的話會大量重疊）
	print("[SPREAD] ── 兩兩範圍重疊 ──")
	for i in all_pts.size():
		for j in range(i + 1, all_pts.size()):
			var a: Array = all_pts[i]
			var b: Array = all_pts[j]
			var ox := minf(a[2].x, b[2].x) - maxf(a[1].x, b[1].x)
			var oz := minf(a[2].y, b[2].y) - maxf(a[1].y, b[1].y)
			var overlap := ox > 0.0 and oz > 0.0
			print("[SPREAD] %-14s × %-14s %s（x 重疊 %.0f m、z 重疊 %.0f m）"
				% [a[0], b[0], "重疊" if overlap else "不重疊", maxf(0.0, ox), maxf(0.0, oz)])
	# 全體範圍，給俯瞰鏡位用
	var gmin := Vector2(INF, INF)
	var gmax := Vector2(-INF, -INF)
	for a in all_pts:
		gmin.x = minf(gmin.x, a[1].x); gmin.y = minf(gmin.y, a[1].y)
		gmax.x = maxf(gmax.x, a[2].x); gmax.y = maxf(gmax.y, a[2].y)
	print("[SPREAD] 全體 x[%.0f, %.0f] z[%.0f, %.0f] 中心=(%.0f, %.0f)"
		% [gmin.x, gmax.x, gmin.y, gmax.y, (gmin.x + gmax.x) * 0.5, (gmin.y + gmax.y) * 0.5])
	# 產生拍照清單：每份一張俯瞰 + 全體一張
	var shots: Array = []
	var tags := {"VillageTrees": "A", "VillageTrees2": "B", "VillageTrees3": "C",
		"VillageTrees4": "D", "VillageTrees5": "E"}
	for a in all_pts:
		var mid: Vector2 = a[3]
		var span: float = maxf(a[2].x - a[1].x, a[2].y - a[1].y)
		var h: float = maxf(60.0, span * 0.9)
		shots.append({"name": "grp_%s" % tags.get(a[0], a[0]),
			"cam": [mid.x, h, mid.y + h * 0.55], "look": [mid.x, 0.0, mid.y], "time": 11})
	var cx: float = (gmin.x + gmax.x) * 0.5
	var cz: float = (gmin.y + gmax.y) * 0.5
	var gspan: float = maxf(gmax.x - gmin.x, gmax.y - gmin.y)
	shots.append({"name": "all_top", "cam": [cx, gspan * 1.15, cz + 1.0],
		"look": [cx, 0.0, cz], "time": 11})
	var f := FileAccess.open("res://../work/tree_group_shots.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(shots))
	f.close()
	print("[SPREAD] 已寫出拍照清單 %d 張" % shots.size())
	quit(0)

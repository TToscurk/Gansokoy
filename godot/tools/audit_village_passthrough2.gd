extends SceneTree
## 逐棟穿模體檢：對每一棟建物／物件個別掃掠，而不是整個群組。
## ⚠ 群組層級的 AABB 對 187 m 長的街區毫無意義（中間有空隙就算 0% 覆蓋）。
##   Godot --headless --path godot --script tools/audit_village_passthrough2.gd
var main: Node
var space: PhysicsDirectSpaceState3D


func _init() -> void:
	_run.call_deferred()


func _settle(n: int = 4) -> void:
	for i in n:
		await physics_frame
		await process_frame


## 在腰高沿 z 方向射穿 aabb，回報被擋住的比例
func _sweep(wb: AABB, y: float) -> float:
	var hits := 0
	var steps := 10
	for i in steps:
		var t := (float(i) + 0.5) / float(steps)
		var x := wb.position.x + wb.size.x * t
		var q := PhysicsRayQueryParameters3D.create(
			Vector3(x, y, wb.position.z - 1.5), Vector3(x, y, wb.end.z + 1.5))
		q.exclude = [main.player.get_rid()] as Array[RID]
		if space.intersect_ray(q).has("position"):
			hits += 1
	return 100.0 * float(hits) / float(steps)


## 找出「一棟」的單位：帶 scene_file_path 的節點（instanced GLB），
## 或群組底下第一層具名 Node3D。
func _units(top: Node) -> Array:
	var out: Array = []
	var stack: Array[Node] = [top]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		if n != top and n.scene_file_path != "":
			out.append(n)
			continue          # 不再往下鑽，這就是一棟
		for c in n.get_children():
			stack.push_back(c)
	if out.is_empty():
		for c in top.get_children():
			if c is Node3D:
				out.append(c)
	return out


func _aabb_of(n: Node) -> AABB:
	var wb := AABB()
	var first := true
	var stack: Array[Node] = [n]
	while stack.size() > 0:
		var m: Node = stack.pop_back()
		for c in m.get_children():
			stack.push_back(c)
		if not (m is MeshInstance3D) or not (m as Node3D).is_visible_in_tree():
			continue
		var b: AABB = (m as Node3D).global_transform * (m as MeshInstance3D).get_aabb()
		if first:
			wb = b
			first = false
		else:
			wb = wb.merge(b)
	return wb if not first else AABB()


func _run() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _settle(20)
	main.load_map("slice", "")
	await _settle(50)
	space = main.get_viewport().get_world_3d().direct_space_state
	var groups := ["B1_Street", "MachiCanal", "EastBankDressing", "路燈街牌", "岩石"]
	var bad: Array = []
	for gname in groups:
		var g: Node = main.map_root.get_node_or_null(gname)
		if g == null:
			continue
		print("[P2] ══ %s ══" % gname)
		for u in _units(g):
			var wb := _aabb_of(u)
			if wb.size.y < 0.6 or wb.size.length() < 0.5:
				continue
			if wb.size.x > 120.0 or wb.size.z > 120.0:
				continue
			var y: float = wb.position.y + minf(1.0, wb.size.y * 0.4)
			var cov := _sweep(wb, y)
			if cov >= 60.0:
				continue        # 擋得住，不列出
			var c: Vector3 = wb.get_center()
			print("[P2] %s %-30s 中心=(%.1f, %.1f) 尺寸=%.1f×%.1f×%.1f 覆蓋=%.0f%%"
				% ["✗" if cov < 30.0 else "△", u.name, c.x, c.z,
				wb.size.x, wb.size.y, wb.size.z, cov])
			if cov < 30.0:
				bad.append([String(u.name), wb])
	print("[P2] ── 完全穿模 %d 個 ──" % bad.size())
	for b in bad:
		var wb: AABB = b[1]
		var c: Vector3 = wb.get_center()
		print("[P2] {\"name\":\"%s\", \"pos\":[%.2f, %.2f, %.2f], \"size\":[%.2f, %.2f, %.2f]},"
			% [b[0], c.x, c.y, c.z, wb.size.x, wb.size.y, wb.size.z])
	quit(0)

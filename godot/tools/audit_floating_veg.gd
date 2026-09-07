extends SceneTree
## 浮空植被偵測：找出離地過高的植株（磁碟狀態，與編輯器未存檔的修改無關）。
##   Godot --headless --path godot --script tools/audit_floating_veg.gd
var main: Node
var space: PhysicsDirectSpaceState3D


func _init() -> void:
	_run.call_deferred()


func _settle(n: int = 4) -> void:
	for i in n:
		await physics_frame
		await process_frame


func _ground(x: float, z: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 300.0, z), Vector3(x, -80.0, z))
	q.exclude = [main.player.get_rid()] as Array[RID]
	var hit := space.intersect_ray(q)
	return hit.position.y if hit.has("position") else -INF


func _run() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _settle(20)
	main.load_map("slice", "")
	await _settle(50)
	space = main.get_viewport().get_world_3d().direct_space_state
	var rv: Node = main.map_root.get_node_or_null("RiverVegetation")
	if rv == null:
		print("[FLOAT] 找不到 RiverVegetation")
		quit(1)
		return
	var by_node: Dictionary = {}
	var stack: Array[Node] = [rv]
	var worst := []
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
		var parent_nm := String(n.get_parent().name)
		for i in mm.instance_count:
			var t: Transform3D = mmi.global_transform * mm.get_instance_transform(i)
			var gy := _ground(t.origin.x, t.origin.z)
			if gy == -INF:
				continue
			var dy := t.origin.y - gy
			if dy > 2.0:
				var e: Array = by_node.get(parent_nm, [0, 0.0, Vector3.ZERO])
				e[0] = int(e[0]) + 1
				if dy > float(e[1]):
					e[1] = dy
					e[2] = t.origin
				by_node[parent_nm] = e
				worst.append([dy, t.origin, String(n.name), parent_nm])
	worst.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
	print("[FLOAT] 浮空（離地 >2 m）植株 %d 株" % worst.size())
	print("[FLOAT] ── 最嚴重的 15 株 ──")
	for i in mini(15, worst.size()):
		var w: Array = worst[i]
		var p: Vector3 = w[1]
		print("[FLOAT] 離地 %6.2f m  (%.0f, %.1f, %.0f)  %s / %s"
			% [w[0], p.x, p.y, p.z, w[3], w[2]])
	print("[FLOAT] ── 依 scatter 節點 ──")
	var keys := by_node.keys()
	keys.sort()
	for k in keys:
		var e: Array = by_node[k]
		print("[FLOAT] %-22s %d 株浮空，最高 %.2f m" % [k, e[0], e[1]])
	quit(0)

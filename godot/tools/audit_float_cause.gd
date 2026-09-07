extends SceneTree
## 浮空根因：比對「產生器算的地面」與「實際碰撞地面」。
## 產生器用 _ground_y() 純數學算高度（不射線），若實際地形另有東西就會對不上。
##   Godot --headless --path godot --script tools/audit_float_cause.gd
var main: Node
var space: PhysicsDirectSpaceState3D


func _init() -> void:
	_run.call_deferred()


func _settle(n: int = 4) -> void:
	for i in n:
		await physics_frame
		await process_frame


## 射線由上往下，逐層列出打到誰
func _chain(x: float, z: float) -> String:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 300.0, z), Vector3(x, -80.0, z))
	var ex: Array[RID] = [main.player.get_rid()]
	var parts := []
	for k in 6:
		q.exclude = ex
		var hit := space.intersect_ray(q)
		if not hit.has("position"):
			break
		var col: Object = hit.get("collider")
		parts.append("%s y=%.2f" % [col.name if col else "?", hit.position.y])
		ex.append(hit.rid)
	return "  ←  ".join(parts)


func _run() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _settle(20)
	main.load_map("slice", "")
	await _settle(50)
	space = main.get_viewport().get_world_3d().direct_space_state
	# 浮空最嚴重的幾個點，以及一個正常點對照
	var pts := [
		[319.0, -347.0, "浮空 15.4 m"],
		[359.0, -227.0, "浮空 15.4 m"],
		[422.0, -247.0, "浮空 15.3 m"],
		[420.0, -51.0, "浮空 15.3 m"],
		[430.0, 0.0, "河心（村內）"],
		[430.0, 100.0, "河心（村內）"],
	]
	for p in pts:
		print("[CAUSE] (%.0f, %.0f) %s" % [p[0], p[1], p[2]])
		print("[CAUSE]    射線：%s" % _chain(float(p[0]), float(p[1])))
	# 實際植株的 y 值分佈（不查地面，只看植株自己的高度）
	var rv: Node = main.map_root.get_node_or_null("RiverVegetation")
	var ys: Array = []
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
			ys.append(t.origin.y)
	ys.sort()
	if ys.size() > 0:
		print("[CAUSE] 植株 y 值：最低 %.2f 中位 %.2f 最高 %.2f（共 %d 株）"
			% [ys[0], ys[ys.size() / 2], ys[ys.size() - 1], ys.size()])
		# 分佈直方
		var buckets: Dictionary = {}
		for y in ys:
			var b := int(floor(float(y) / 2.0)) * 2
			buckets[b] = int(buckets.get(b, 0)) + 1
		var keys := buckets.keys()
		keys.sort()
		for k in keys:
			print("[CAUSE]   y %+3d ~ %+3d : %d 株" % [k, int(k) + 2, buckets[k]])
	quit(0)

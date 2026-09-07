extends SceneTree
## 人間之里穿模體檢：沿地面掃描，找出「看得到但走得過去」的物件。
## 對每個建物／構造物的 AABB 做水平掃掠，回報碰撞覆蓋率。
##   Godot --headless --path godot --script tools/audit_village_passthrough.gd
var main: Node
var space: PhysicsDirectSpaceState3D


func _init() -> void:
	_run.call_deferred()


func _settle(n: int = 4) -> void:
	for i in n:
		await physics_frame
		await process_frame


## 在 y 高度上、沿 axis 方向掃過 aabb，回報「被擋住的比例」
func _sweep(wb: AABB, y: float) -> float:
	var hits := 0
	var total := 0
	var steps := 12
	for i in steps:
		var t := (float(i) + 0.5) / float(steps)
		# 沿 x 掃：從 -z 邊射到 +z 邊
		var x := wb.position.x + wb.size.x * t
		var from := Vector3(x, y, wb.position.z - 2.0)
		var to := Vector3(x, y, wb.end.z + 2.0)
		var q := PhysicsRayQueryParameters3D.create(from, to)
		q.exclude = [main.player.get_rid()] as Array[RID]
		total += 1
		if space.intersect_ray(q).has("position"):
			hits += 1
	return 100.0 * float(hits) / maxf(1.0, float(total))


func _run() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _settle(20)
	main.load_map("slice", "")
	await _settle(50)
	space = main.get_viewport().get_world_3d().direct_space_state
	var mr: Node = main.map_root
	# 檢查對象：頂層節點底下每個具名的建物／構造物
	var targets := []
	for top in mr.get_children():
		var nm := String(top.name)
		if nm.begins_with("Portal_") or nm in ["Terrain", "UnifiedGround", "GroundUnderlay",
				"地面碰撞_刷筆用", "建物碰撞", "路燈碰撞", "場景效能裁剪", "天象系統",
				"BasinHills", "RiverVegetation", "灌木叢", "草筆刷_矮草"]:
			continue
		# 取這個節點的世界 AABB
		var wb := AABB()
		var first := true
		var stack: Array[Node] = [top]
		while stack.size() > 0:
			var n: Node = stack.pop_back()
			for c in n.get_children():
				stack.push_back(c)
			if not (n is MeshInstance3D):
				continue
			if not (n as Node3D).is_visible_in_tree():
				continue
			var b: AABB = (n as Node3D).global_transform * (n as MeshInstance3D).get_aabb()
			if first:
				wb = b
				first = false
			else:
				wb = wb.merge(b)
		if first or wb.size.y < 0.8:
			continue
		if wb.size.x > 200.0 or wb.size.z > 200.0:
			continue   # 地形級大物件不算穿模對象
		targets.append([nm, wb])
	print("[PASS] 檢查 %d 個物件（腰高 1.0 m 掃掠，覆蓋率 <30%% 視為可穿過）" % targets.size())
	var bad := []
	for t in targets:
		var wb: AABB = t[1]
		var y: float = wb.position.y + minf(1.0, wb.size.y * 0.4)
		var cov := _sweep(wb, y)
		var mark := "✗ 穿模" if cov < 30.0 else ("△ 部分" if cov < 70.0 else "✓")
		print("[PASS] %s %-22s 中心=(%.0f, %.0f) 尺寸=%.1f×%.1f×%.1f m 覆蓋=%.0f%%"
			% [mark, t[0], wb.get_center().x, wb.get_center().z,
			wb.size.x, wb.size.y, wb.size.z, cov])
		if cov < 30.0:
			bad.append([t[0], wb])
	print("[PASS] ── 可穿過的物件 %d 個，建議碰撞箱參數 ──" % bad.size())
	for b in bad:
		var wb: AABB = b[1]
		var c: Vector3 = wb.get_center()
		print("[PASS] %-22s pos=(%.2f, %.2f, %.2f) size=(%.2f, %.2f, %.2f)"
			% [b[0], c.x, c.y, c.z, wb.size.x, wb.size.y, wb.size.z])
	quit(0)

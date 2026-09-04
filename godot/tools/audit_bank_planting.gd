extends SceneTree
## Audit the generated bank planting numerically.
##
## Why numbers instead of a screenshot: the editor viewport draws the collision
## debug wireframe and a large selection gizmo over this area, and a vision pass
## on that image describes the overlay rather than the plants. Grounding,
## spacing, and clustering are all measurable — measure them.
##
## Checks:
##   - grounding: distance from each instance origin to the surface below it
##   - trespass : anything sitting on revetment stone or below the waterline
##   - spread   : bounding extent and occupied 8 m cells along the bank
##   - clumping : per-cell counts, to confirm the distribution is uneven
##   - variety  : yaw and scale spread, to confirm instances are not clones
##
## Run: godot --headless --path godot --script tools/audit_bank_planting.gd

const SCENE := "res://maps/slice/slice.tscn"
const GROUP := "河岸植生"
const WATER_Y := -5.15
const CELL := 8.0


func _init() -> void:
	root.call_deferred("add_child", load(SCENE).instantiate())
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await physics_frame
	await physics_frame

	var scene := root.get_child(root.get_child_count() - 1)
	var space: PhysicsDirectSpaceState3D = scene.get_world_3d().direct_space_state

	var grp := scene.find_child(GROUP, true, false)
	if grp == null:
		print("[fail] %s 不在場景中" % GROUP)
		quit(1)
		return

	var plants: Array = []
	for cat in grp.get_children():
		for p in cat.get_children():
			plants.append({"node": p, "cat": cat.name})

	print("植株 %d 株，分 %d 類\n" % [plants.size(), grp.get_child_count()])

	var float_max := 0.0
	var floating := 0
	var sunk := 0
	var on_stone := 0
	var in_water := 0
	var cells := {}
	var yaws: Array = []
	var scales: Array = []
	var minx := INF
	var maxx := -INF
	var minz := INF
	var maxz := -INF

	for e in plants:
		var n: Node3D = e["node"]
		var pos := n.global_transform.origin
		minx = min(minx, pos.x)
		maxx = max(maxx, pos.x)
		minz = min(minz, pos.z)
		maxz = max(maxz, pos.z)

		# Grounding: cast from just above the instance and compare.
		var q := PhysicsRayQueryParameters3D.new()
		q.from = pos + Vector3.UP * 5.0
		q.to = pos + Vector3.DOWN * 20.0
		var r: Dictionary = space.intersect_ray(q)
		if not r.is_empty():
			var gy: float = r["position"].y
			var d := pos.y - gy
			float_max = max(float_max, abs(d))
			if d > 0.25:
				floating += 1
			elif d < -0.25:
				sunk += 1
			var nm: String = r["collider"].name
			if nm.begins_with("EastRiverRevetment"):
				on_stone += 1

		if pos.y <= WATER_Y + 0.2:
			in_water += 1

		var key := Vector2i(int(floor(pos.x / CELL)), int(floor(pos.z / CELL)))
		cells[key] = cells.get(key, 0) + 1

		var b := n.global_transform.basis
		scales.append(b.get_scale().y)
		yaws.append(b.get_euler().y)

	print("== 貼地 ==")
	print("  浮空 (>0.25m): %d" % floating)
	print("  陷入 (>0.25m): %d" % sunk)
	print("  最大偏差: %.3f m" % float_max)

	print("\n== 越界 ==")
	print("  站在石砌護岸上: %d" % on_stone)
	print("  低於水面: %d" % in_water)

	print("\n== 分佈 ==")
	print("  範圍 X %.1f~%.1f (%.1fm)   Z %.1f~%.1f (%.1fm)" % [
		minx, maxx, maxx - minx, minz, maxz, maxz - minz])
	print("  佔用 %d 個 %.0fm 格" % [cells.size(), CELL])
	var counts: Array = []
	for k in cells:
		counts.append(cells[k])
	counts.sort()
	if not counts.is_empty():
		print("  每格株數: 最少 %d / 中位 %d / 最多 %d  (疏密比 %.1fx)" % [
			counts[0], counts[counts.size() / 2], counts[-1],
			float(counts[-1]) / max(counts[0], 1)])

	print("\n== 變化度 ==")
	scales.sort()
	yaws.sort()
	if not scales.is_empty():
		print("  縮放 %.2f ~ %.2f (中位 %.2f)" % [
			scales[0], scales[-1], scales[scales.size() / 2]])
		print("  朝向 %.0f° ~ %.0f°" % [
			rad_to_deg(yaws[0]), rad_to_deg(yaws[-1])])

	var ok := floating == 0 and sunk == 0 and on_stone == 0 and in_water == 0
	print("\n%s" % ("[PASS] 全部貼地、無越界" if ok else "[CHECK] 有問題見上"))
	quit(0)

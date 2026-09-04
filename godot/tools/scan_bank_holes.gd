extends SceneTree
## Dense hole-scan across the east bank strip.
##
## Why this exists: the coarse coverage audit samples each mesh's AABB on a 3x5
## grid, which is far too sparse for UnifiedGround (6.2 million m²) — a hole a
## few metres wide along the bank would pass unnoticed while being exactly the
## place the user is trying to paint. This scans the bank corridor at 2 m
## spacing and reports contiguous gaps, plus which body answers where.
##
## Run: godot --headless --path godot --script tools/scan_bank_holes.gd

const SCENE := "res://maps/slice/slice.tscn"

# Corridor around the east river: revetment spans X 306.8~559.0. Scan a little
# wider on both sides to catch the ground/revetment seam.
const X0 := 280.0
const X1 := 480.0
const Z0 := -200.0
const Z1 := 200.0
const STEP := 2.0


func _init() -> void:
	root.call_deferred("add_child", load(SCENE).instantiate())
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await physics_frame
	await physics_frame

	var scene := root.get_child(root.get_child_count() - 1)
	var space: PhysicsDirectSpaceState3D = scene.get_world_3d().direct_space_state

	var tally := {}
	var holes: Array = []
	var total := 0

	var x := X0
	while x <= X1:
		var z := Z0
		while z <= Z1:
			var q := PhysicsRayQueryParameters3D.new()
			q.from = Vector3(x, 200.0, z)
			q.to = Vector3(x, -100.0, z)
			var r: Dictionary = space.intersect_ray(q)
			total += 1
			if r.is_empty():
				holes.append(Vector2(x, z))
			else:
				var nm: String = r["collider"].name
				tally[nm] = tally.get(nm, 0) + 1
			z += STEP
		x += STEP

	print("東岸走廊掃描  X %.0f~%.0f  Z %.0f~%.0f  間距 %.1fm  共 %d 點\n" % [
		X0, X1, Z0, Z1, STEP, total])

	var keys := tally.keys()
	keys.sort()
	for k in keys:
		print("  %-30s %6d 點 (%.1f%%)" % [k, tally[k], 100.0 * tally[k] / total])
	print("  %-30s %6d 點 (%.1f%%)" % ["<無碰撞>", holes.size(), 100.0 * holes.size() / total])

	if not holes.is_empty():
		var minx := INF
		var maxx := -INF
		var minz := INF
		var maxz := -INF
		for h in holes:
			minx = min(minx, h.x)
			maxx = max(maxx, h.x)
			minz = min(minz, h.y)
			maxz = max(maxz, h.y)
		print("\n破洞範圍: X %.1f~%.1f  Z %.1f~%.1f" % [minx, maxx, minz, maxz])
		print("前 12 個破洞座標:")
		for i in min(12, holes.size()):
			print("  (%.1f, %.1f)" % [holes[i].x, holes[i].y])
	else:
		print("\n[無破洞] 走廊內每一點都有碰撞回應")

	# Also report the height the ray lands at along one cross-section, so a bank
	# that is covered but at an unexpected Y shows up.
	print("\n橫剖面 Z=0，每 5m 一點的落點高度與命中對象:")
	var xx := X0
	while xx <= X1:
		var q2 := PhysicsRayQueryParameters3D.new()
		q2.from = Vector3(xx, 200.0, 0.0)
		q2.to = Vector3(xx, -100.0, 0.0)
		var r2: Dictionary = space.intersect_ray(q2)
		if r2.is_empty():
			print("  X %6.1f   <無碰撞>" % xx)
		else:
			print("  X %6.1f   Y %7.2f   %s" % [xx, r2["position"].y, r2["collider"].name])
		xx += 5.0

	quit(0)

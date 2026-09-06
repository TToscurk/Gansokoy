extends SceneTree
## Report the actual height-above-water distribution of plantable bank points.
##
## Why: the planting run keeps rejecting most candidates on the height band, and
## two rounds of guessing the bands from a single cross-section have not worked.
## Measure the real distribution first, then set bands from it.
##
## Run: godot --headless --path godot --script tools/hist_bank_heights.gd

const SCENE := "res://maps/slice/slice.tscn"
const WATER_Y := -5.15
const X_LO := 400.0
const X_HI := 436.0
const Z0 := -200.0
const Z1 := 200.0


func _init() -> void:
	root.call_deferred("add_child", load(SCENE).instantiate())
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await physics_frame
	await physics_frame

	var scene := root.get_child(root.get_child_count() - 1)
	var space: PhysicsDirectSpaceState3D = scene.get_world_3d().direct_space_state

	var heights: Array = []
	var slopes: Array = []
	var stone := 0
	var water := 0

	var z := Z0
	while z < Z1:
		var x := X_LO
		while x <= X_HI:
			var q := PhysicsRayQueryParameters3D.new()
			q.from = Vector3(x, 60.0, z)
			q.to = Vector3(x, -60.0, z)
			var r: Dictionary = space.intersect_ray(q)
			x += 1.0
			if r.is_empty():
				continue
			var nm: String = r["collider"].name
			if nm.begins_with("EastRiverRevetment"):
				stone += 1
				continue
			var hit: Vector3 = r["position"]
			var h := hit.y - WATER_Y
			if h <= 0.35:
				water += 1
				continue
			heights.append(h)
			var n: Vector3 = r["normal"]
			slopes.append(rad_to_deg(acos(clampf(n.dot(Vector3.UP), -1.0, 1.0))))
		z += 2.0

	heights.sort()
	slopes.sort()
	print("可種點 %d 個（石砌剔除 %d，水下剔除 %d）\n" % [heights.size(), stone, water])
	if heights.is_empty():
		quit(0)
		return

	print("離水高度分位:")
	for p in [0, 5, 10, 25, 50, 75, 90, 95, 100]:
		var i: int = clampi(int(heights.size() * p / 100.0), 0, heights.size() - 1)
		print("  P%-3d  %.2f m" % [p, heights[i]])

	print("\n坡度分位:")
	for p in [50, 75, 90, 95, 100]:
		var i: int = clampi(int(slopes.size() * p / 100.0), 0, slopes.size() - 1)
		print("  P%-3d  %.1f°" % [p, slopes[i]])

	print("\n直方圖（每 0.5m）:")
	var buckets := {}
	for h in heights:
		var b := int(floor(h / 0.5))
		buckets[b] = buckets.get(b, 0) + 1
	var keys := buckets.keys()
	keys.sort()
	for k in keys:
		var bar := ""
		var n: int = int(buckets[k] * 60.0 / heights.size())
		for i in n:
			bar += "#"
		print("  %5.1f~%4.1f m  %5d  %s" % [k * 0.5, (k + 1) * 0.5, buckets[k], bar])
	quit(0)

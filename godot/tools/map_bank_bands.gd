extends SceneTree
## Map the plantable strip along the east river bank.
##
## Why this exists: before scattering anything, the actual geometry has to be
## known — where the revetment stone ends, where the maintenance path runs, how
## steep each band is. Planting by eye on a cross-section guess is how you get
## bushes standing in the water or floating over the stone cap.
##
## Method: cast down at 1 m spacing across the corridor, record the hit body,
## height and surface slope, then group X into bands and report what each band
## is. The output tells us which X range is soil (plantable), which is stone
## (not plantable), and which is water (never).
##
## Run: godot --headless --path godot --script tools/map_bank_bands.gd

const SCENE := "res://maps/slice/slice.tscn"
const X0 := 290.0
const X1 := 450.0
const STEP_X := 2.0
# Sample several Z lines so a local dip does not masquerade as a band.
const Z_LINES := [-120.0, -60.0, 0.0, 60.0, 120.0]


func _init() -> void:
	root.call_deferred("add_child", load(SCENE).instantiate())
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await physics_frame
	await physics_frame

	var scene := root.get_child(root.get_child_count() - 1)
	var space: PhysicsDirectSpaceState3D = scene.get_world_3d().direct_space_state

	print("東岸橫剖面（%d 條測線平均）" % Z_LINES.size())
	print("%-8s %-26s %-9s %-8s %s" % ["X", "命中", "高度Y", "坡度°", "判定"])

	var x := X0
	while x <= X1:
		var ys: Array = []
		var slopes: Array = []
		var names := {}
		for z in Z_LINES:
			var q := PhysicsRayQueryParameters3D.new()
			q.from = Vector3(x, 200.0, z)
			q.to = Vector3(x, -100.0, z)
			var r: Dictionary = space.intersect_ray(q)
			if r.is_empty():
				continue
			ys.append(r["position"].y)
			var n: Vector3 = r["normal"]
			slopes.append(rad_to_deg(acos(clampf(n.dot(Vector3.UP), -1.0, 1.0))))
			var nm: String = r["collider"].name
			names[nm] = names.get(nm, 0) + 1

		if ys.is_empty():
			print("%-8.1f %-26s" % [x, "<無碰撞>"])
			x += STEP_X
			continue

		var ysum := 0.0
		for v in ys:
			ysum += v
		var ssum := 0.0
		for v in slopes:
			ssum += v
		var avg_y := ysum / ys.size()
		var avg_s := ssum / slopes.size()

		var top := ""
		var best := 0
		for k in names:
			if names[k] > best:
				best = names[k]
				top = k

		# Plantable = soil, gentle enough to stand on, above the waterline.
		var verdict := ""
		if top.begins_with("EastRiverRevetment"):
			verdict = "石砌護岸 — 不種"
		elif avg_y < -5.0:
			verdict = "水面下 — 不種"
		elif avg_s > 40.0:
			verdict = "太陡 — 不種"
		else:
			verdict = "可種"

		print("%-8.1f %-26s %-9.2f %-8.1f %s" % [x, top, avg_y, avg_s, verdict])
		x += STEP_X

	quit(0)

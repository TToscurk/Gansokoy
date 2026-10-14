extends SceneTree
## P13 W5C read-only: exact placement of ForestP9 plants near the upper approach (s=86..102): center s/lat, AABB lateral reach, height above stone.
const SA := preload("res://tools/village_v2_shrine_approach_lib.gd")
func _init() -> void:
	_run.call_deferred()
func _run() -> void:
	var v: Node3D = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	root.add_child(v)
	for i in 8:
		await physics_frame
	var cl := SA.centerline()
	var H := SA.ramp_profile(v, cl)
	var fp := v.get_node("Vegetation/ForestP9")
	for n in fp.find_children("*", "MeshInstance3D", true, false):
		var g := n as MeshInstance3D
		if not (String(g.name) == "LOD0"):
			continue
		var wb := g.global_transform * g.get_aabb()
		var c := wb.get_center()
		var best := INF
		var bk := 0
		for k in range(1500, cl.size()):
			var d := cl[k].distance_to(Vector2(c.x, c.z))
			if d < best:
				best = d
				bk = k
		if bk * 0.05 < 84.0 or bk * 0.05 > 103.0 or best > 7.0:
			continue
		var t := SA.tangent(cl, bk)
		var nr := Vector2(-t.y, t.x)
		var lat := (Vector2(c.x, c.z) - cl[bk]).dot(nr)
		# lateral reach of AABB corners
		var lo := INF
		var hi := -INF
		for ix in 2:
			for iz in 2:
				var corner := Vector2(wb.position.x + wb.size.x * ix, wb.position.z + wb.size.z * iz)
				var l2 := (corner - cl[bk]).dot(nr)
				lo = minf(lo, l2)
				hi = maxf(hi, l2)
		print("[FP] %s  node_origin=(%.2f,%.2f,%.2f) center s=%.2f lat=%.2f  aabb_lat=[%.2f..%.2f] y=[%.2f..%.2f] stoneY=%.2f  scale=%s" % [String(v.get_path_to(g.get_parent())), g.get_parent().global_position.x, g.get_parent().global_position.y, g.get_parent().global_position.z, bk * 0.05, lat, lo, hi, wb.position.y, wb.end.y, H[bk], str((g.get_parent() as Node3D).scale)])
	quit(0)

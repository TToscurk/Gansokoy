extends SceneTree
## P13 W5C read-only diagnostic: which vegetation/props intrude the walking corridor of the upper approach?
## Needs a rendering display (MultiMesh data). godot --path . --script res://tools/p13/diag_w5c_veg.gd -- 89 100.5
const SA := preload("res://tools/village_v2_shrine_approach_lib.gd")
const LATS := [-1.2, -0.6, 0.0, 0.6, 1.2]
const HS := [0.25, 0.7, 1.2, 1.7]

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var s0 := float(a[0]) if a.size() > 0 else 89.0
	var s1 := float(a[1]) if a.size() > 1 else 100.5
	var v: Node3D = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	root.add_child(v)
	for i in 8:
		await physics_frame
	await process_frame
	var cl := SA.centerline()
	var H := SA.ramp_profile(v, cl)
	var kmin := int(s0 / 0.05)
	var kmax := mini(int(s1 / 0.05), cl.size() - 1)
	# corridor sample points: (world pos, s, lat)
	var pts: Array = []
	for k in range(kmin, kmax + 1, 4):
		var t := SA.tangent(cl, k)
		var nr := Vector2(-t.y, t.x)
		for lat: float in LATS:
			for h: float in HS:
				var p := cl[k] + nr * lat
				pts.append([Vector3(p.x, H[k] + h, p.y), k * 0.05, lat, h])
	var bb := AABB(Vector3(cl[kmin].x, H[kmin], cl[kmin].y), Vector3.ZERO)
	for pt in pts:
		bb = bb.expand(pt[0])
	bb = bb.grow(2.0)
	var report := {}
	var total_inst := 0
	for n in v.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		if not g.is_visible_in_tree():
			continue
		var grp := _group(v, g)
		if n is MultiMeshInstance3D:
			var mm := (n as MultiMeshInstance3D).multimesh
			if mm == null or mm.mesh == null:
				continue
			var lab := mm.mesh.get_aabb()
			var rad := maxf(lab.size.x, lab.size.z) * 0.5
			for i in mm.instance_count:
				var tr := g.global_transform * mm.get_instance_transform(i)
				var o := tr.origin
				if not bb.has_point(o):
					continue
				var wb := tr * lab
				var hit := false
				var best_s := 0.0
				var best_lat := 0.0
				for pt in pts:
					if wb.has_point(pt[0]):
						hit = true
						best_s = pt[1]
						best_lat = pt[2]
						break
				if hit:
					total_inst += 1
					var key := "%s :: %s (MM %s)" % [grp, g.name, mm.mesh.resource_name if mm.mesh.resource_name != "" else mm.mesh.get_class()]
					var e: Dictionary = report.get(key, {"n": 0, "smin": 1e9, "smax": -1e9, "lat": []})
					e["n"] += 1
					e["smin"] = minf(e["smin"], best_s)
					e["smax"] = maxf(e["smax"], best_s)
					(e["lat"] as Array).append(best_lat)
					e["ex"] = "origin=(%.1f,%.1f,%.1f) size=(%.2f,%.2f,%.2f)" % [o.x, o.y, o.z, wb.size.x, wb.size.y, wb.size.z]
					report[key] = e
		else:
			var wb2 := g.global_transform * g.get_aabb()
			if not bb.intersects(wb2):
				continue
			var hit2 := false
			var bs := 0.0
			var bl := 0.0
			for pt in pts:
				if wb2.has_point(pt[0]):
					hit2 = true
					bs = pt[1]
					bl = pt[2]
					break
			if hit2:
				total_inst += 1
				var key2 := "%s :: %s (%s)" % [grp, v.get_path_to(n), n.get_class()]
				var e2: Dictionary = report.get(key2, {"n": 0, "smin": 1e9, "smax": -1e9, "lat": []})
				e2["n"] += 1
				e2["smin"] = minf(e2["smin"], bs)
				e2["smax"] = maxf(e2["smax"], bs)
				(e2["lat"] as Array).append(bl)
				e2["ex"] = "aabb pos=(%.1f,%.1f,%.1f) size=(%.2f,%.2f,%.2f)" % [wb2.position.x, wb2.position.y, wb2.position.z, wb2.size.x, wb2.size.y, wb2.size.z]
				report[key2] = e2
	var keys := report.keys()
	keys.sort()
	for k2 in keys:
		var e3: Dictionary = report[k2]
		print("[VEG] %s  n=%d s=%.1f..%.1f  %s" % [k2, e3["n"], e3["smin"], e3["smax"], e3["ex"]])
	print("[VEG] corridor-intersecting items total=%d groups=%d" % [total_inst, report.size()])
	quit(0)

func _group(v: Node, n: Node) -> String:
	var p := v.get_path_to(n)
	var parts := String(p).split("/")
	return "/".join(parts.slice(0, mini(2, parts.size() - 1)))

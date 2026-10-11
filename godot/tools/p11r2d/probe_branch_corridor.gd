extends SceneTree
## P11 R2D 可行性檢查 3（只讀、非 headless：MultiMesh 実例を読むため）：N0／T0 支線の通り道（中心線 ±0.8 m）に
## 入る可見物（MeshInstance3D の頂点が地面＋0.03 より上、MultiMesh 実例の原点）を層ごとに数える。
## 碰撞を持たない封存層（P9 地被・草地・環境、P10 道具・NPC）が支線と重なるかを確かめる。
##   godot --path . --script res://tools/p11r2d/probe_branch_corridor.gd
const FZ := preload("res://tools/village_v2_farmland_zone.gd")
const HALF := 0.8
const ZL := preload("res://tools/village_v2_farmland_zone.gd")

func _init() -> void:
	_run.call_deferred()

func _d(p: Vector2, pl: PackedVector2Array) -> Array:
	var best := INF
	var bs := 0.0
	var acc := 0.0
	for k in pl.size() - 1:
		var q := Geometry2D.get_closest_point_to_segment(p, pl[k], pl[k + 1])
		var d := q.distance_to(p)
		if d < best:
			best = d
			bs = acc + pl[k].distance_to(q)
		acc += pl[k].distance_to(pl[k + 1])
	return [best, bs]

func _grp(path: String) -> String:
	var parts := path.split("/")
	return "/".join(parts.slice(0, mini(3, parts.size())))

func _run() -> void:
	var v: Node3D = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	root.add_child(v)
	for i in 8:
		await process_frame
	var routes := {}
	var bbs := {}
	for k in ZL.BRANCHES:
		var pl := PackedVector2Array()
		for a in ZL.BRANCHES[k]["pts"]:
			pl.append(Vector2(a[0], a[1]))
		routes[k] = pl
		var r := Rect2(pl[0], Vector2.ZERO)
		for p in pl:
			r = r.expand(p)
		bbs[k] = r.grow(HALF + 0.2)
	var res := {"N0": {}, "T0": {}}
	for mi: MeshInstance3D in v.find_children("*", "MeshInstance3D", true, false):
		var path := String(v.get_path_to(mi))
		if path.begins_with("Terrain") or path.begins_with("Water") or path.begins_with("Debug") or path.begins_with("Roads") or path.begins_with("Portals") or path.contains("/Branches/") or path.contains("/Ground/"):
			continue
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var ab := mi.global_transform * mi.get_aabb()
		var r2 := Rect2(ab.position.x, ab.position.z, ab.size.x, ab.size.z)
		for k in routes:
			if not r2.intersects(bbs[k]):
				continue
			var xf := mi.global_transform
			var n := 0
			var smin := INF
			var smax := -INF
			for s in mi.mesh.get_surface_count():
				var vs: PackedVector3Array = mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
				var stepn := maxi(1, vs.size() / 4000)
				for q in range(0, vs.size(), stepn):
					var w := xf * vs[q]
					var p2 := Vector2(w.x, w.z)
					if not (bbs[k] as Rect2).has_point(p2):
						continue
					var dd: Array = _d(p2, routes[k])
					if float(dd[0]) > HALF:
						continue
					if w.y < FZ.ground_h(p2) + 0.03:
						continue
					n += 1
					smin = minf(smin, dd[1])
					smax = maxf(smax, dd[1])
			if n > 0:
				var g := _grp(path)
				var e: Dictionary = res[k].get(g, {"n": 0, "nodes": {}, "s": [INF, -INF]})
				e.n += n
				e.nodes[path] = true
				e.s = [minf(e.s[0], smin), maxf(e.s[1], smax)]
				res[k][g] = e
	for mmi: MultiMeshInstance3D in v.find_children("*", "MultiMeshInstance3D", true, false):
		var path := String(v.get_path_to(mmi))
		var mm := mmi.multimesh
		if mm == null or not mmi.is_visible_in_tree():
			continue
		var xf := mmi.global_transform
		for k in routes:
			var n := 0
			var smin := INF
			var smax := -INF
			for i in mm.instance_count:
				var t := xf * mm.get_instance_transform(i)
				var p2 := Vector2(t.origin.x, t.origin.z)
				if not (bbs[k] as Rect2).has_point(p2):
					continue
				var dd: Array = _d(p2, routes[k])
				if float(dd[0]) > HALF:
					continue
				n += 1
				smin = minf(smin, dd[1])
				smax = maxf(smax, dd[1])
			if n > 0:
				var g := _grp(path) + "（MM）"
				var e: Dictionary = res[k].get(g, {"n": 0, "nodes": {}, "s": [INF, -INF]})
				e.n += n
				e.nodes[path] = true
				e.s = [minf(e.s[0], smin), maxf(e.s[1], smax)]
				res[k][g] = e
	for k in res:
		print("[COR] ===== %s 支線（中心線 ±%.1f m）" % [k, HALF])
		for g in res[k]:
			var e: Dictionary = res[k][g]
			var names: Array = (e.nodes as Dictionary).keys()
			print("[COR]  %-48s 頂点／実例 %5d  区間 s %.1f–%.1f  ノード %d %s" % [g, e.n, e.s[0], e.s[1], names.size(), str(names.slice(0, 3))])
	quit(0)

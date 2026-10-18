extends SceneTree
## W9 建築閃爍調查（headless 幾何）：對每棟被 W9 overlay（ArchW9R2P13＋EnrichW9*）改過的建築，
## 在 3 個距離帶（10／70／130 m，依 visibility_range 判定同時可見的網格）找「不同 MeshInstance 之間的共面重疊三角形」：
##   取樣 A 的三角形（重心＋3 個內點），沿 A 法線 ±2 cm 射線打 B 的 trimesh；命中距離 < EPS 且法線平行（|dot| > 0.98）＝共面重疊。
## 輸出：建築 id、A／B 節點路徑、重疊取樣數／面積估計、最小距離、世界座標樣本。
## 也列出 LOD 範圍：overlay L0/L1 vs Kit LOD0/1/2（begin/end/margin/fade）。
##   godot --headless --path godot --script res://tools/diag_village_v2_w9_zfight.gd -- [--id=<building>] [--eps=0.004]

const TMP := 1 << 23
var only := ""
var eps := 0.004
var bands := [10.0, 70.0, 130.0]


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--id="):
			only = a.get_slice("=", 1)
		elif a.begins_with("--eps="):
			eps = float(a.get_slice("=", 1))
	_run.call_deferred()


func _vis_at(gi: GeometryInstance3D, d: float) -> bool:
	var b := gi.visibility_range_begin
	var e := gi.visibility_range_end
	return d >= b and (e <= 0.0 or d < e)


func _run() -> void:
	var scn: Node3D = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	root.add_child(scn)
	for i in 8:
		await process_frame
	var arch := scn.get_node("ArchW9R2P13")
	print("[zf] ArchW9R2P13 children=%d hidden_count=%d copied=%d" % [arch.get_child_count(), arch.get("hidden_count"), arch.get("copied_surfaces")])
	var bodies := {}   # body Node3D → [overlay nodes]
	for b in arch.get_children():
		var body := scn.get_node_or_null(NodePath(String(b.get_meta("body_path", ""))))
		if body:
			if not bodies.has(body):
				bodies[body] = []
			bodies[body].append(b)
	# EnrichW9*：w9_b → body id
	for en in ["EnrichW9P13", "EnrichW9P3", "EnrichW9P4", "EnrichW9P8"]:
		var r := scn.get_node_or_null(en)
		if r == null:
			continue
		for it in r.find_children("*", "Node3D", true, false):
			var fb := String(it.get_meta("w9_b", ""))
			if fb == "":
				continue
			for body in bodies.keys():
				if String((body as Node).name) == fb:
					if not bodies[body].has(it):
						bodies[body].append(it)
	print("[zf] buildings=%d" % bodies.size())
	var total_pairs := 0
	for body: Node3D in bodies.keys():
		var id := String(body.name)
		if only != "" and id != only:
			continue
		var geos: Array = []
		for g in body.find_children("*", "MeshInstance3D", true, false):
			if (g as MeshInstance3D).is_visible_in_tree() and (g as MeshInstance3D).mesh != null:
				geos.append(g)
		for ov in bodies[body]:
			if ov is MeshInstance3D and (ov as MeshInstance3D).is_visible_in_tree():
				geos.append(ov)
			for g in (ov as Node).find_children("*", "MeshInstance3D", true, false):
				if (g as MeshInstance3D).is_visible_in_tree() and (g as MeshInstance3D).mesh != null:
					geos.append(g)
		# 每個 mesh 一個臨時 body
		var rid_of := {}
		var holders: Array = []
		for gi: MeshInstance3D in geos:
			var sb := StaticBody3D.new()
			sb.collision_layer = TMP
			sb.collision_mask = 0
			scn.add_child(sb)
			var cs := CollisionShape3D.new()
			cs.shape = gi.mesh.create_trimesh_shape()
			(cs.shape as ConcavePolygonShape3D).backface_collision = true
			sb.add_child(cs)
			sb.global_transform = gi.global_transform
			rid_of[gi] = sb.get_rid()
			holders.append(sb)
		await physics_frame
		await physics_frame
		var sp := scn.get_world_3d().direct_space_state
		var found := {}
		for d in bands:
			var vis: Array = geos.filter(func(g): return _vis_at(g, d))
			var vis_rids: Array[RID] = []
			for g in vis:
				vis_rids.append(rid_of[g])
			for ga: MeshInstance3D in vis:
				var xf := ga.global_transform
				var others: Array[RID] = []
				for r in vis_rids:
					if r != rid_of[ga]:
						others.append(r)
				if others.is_empty():
					continue
				var ex: Array[RID] = [rid_of[ga]]
				for r in rid_of.values():
					if not others.has(r) and r != rid_of[ga]:
						ex.append(r)
				for s in ga.mesh.get_surface_count():
					var arr := ga.mesh.surface_get_arrays(s)
					var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
					var idx = arr[Mesh.ARRAY_INDEX]
					var nt: int = (idx.size() if idx != null else v.size()) / 3
					var step := maxi(1, nt / 1500)
					var t := 0
					while t < nt:
						var a := xf * v[idx[t * 3] if idx != null else t * 3]
						var b := xf * v[idx[t * 3 + 1] if idx != null else t * 3 + 1]
						var c := xf * v[idx[t * 3 + 2] if idx != null else t * 3 + 2]
						var nrm := (b - a).cross(c - a)
						var area := nrm.length() * 0.5
						if area < 1e-5:
							t += step
							continue
						nrm = nrm.normalized()
						for w in [Vector3(1, 1, 1) / 3.0, Vector3(0.6, 0.2, 0.2), Vector3(0.2, 0.6, 0.2), Vector3(0.2, 0.2, 0.6)]:
							var p: Vector3 = a * w.x + b * w.y + c * w.z
							var q := PhysicsRayQueryParameters3D.create(p + nrm * 0.02, p - nrm * 0.02, TMP)
							q.exclude = ex
							var h := sp.intersect_ray(q)
							if h.is_empty():
								continue
							var dist: float = absf((h.position - p).dot(nrm))
							if dist > eps or (h.normal as Vector3).dot(nrm) < 0.98:   # 只算同向（背對背的兩面在 cull_back 下不會互搶）
								continue
							var gb: MeshInstance3D = null
							for g in rid_of:
								if rid_of[g] == h.rid:
									gb = g
							var pa := String(scn.get_path_to(ga))
							var pb := String(scn.get_path_to(gb))
							var key := (pa + " ⟷ " + pb) if pa < pb else (pb + " ⟷ " + pa)
							if not found.has(key):
								found[key] = {"n": 0, "area": 0.0, "dmin": 1.0, "p": p, "bands": {}}
							found[key]["n"] += 1
							found[key]["area"] += area * 0.25 * step
							found[key]["dmin"] = minf(found[key]["dmin"], dist)
							found[key]["bands"][d] = true
						t += step
		for sb in holders:
			sb.queue_free()
		await physics_frame
		if found.is_empty():
			continue
		for k in found:
			var f: Dictionary = found[k]
			total_pairs += 1
			print("[zf] %s  %s  n=%d 面積≈%.2f m² 最小距 %.4f m  帶 %s  樣本 (%.2f, %.2f, %.2f)" % [id, k, f["n"], f["area"], f["dmin"], (f["bands"] as Dictionary).keys(), f["p"].x, f["p"].y, f["p"].z])
	print("[zf] 共面重疊配對 %d" % total_pairs)
	quit(0)

extends SceneTree
## P13 W3B：T0 木槽の台（Bed）の平面範囲（木槽中心から 1.0 m）に、他層の可見物（メッシュ／MultiMesh／碰撞）が触れているかの調査（唯讀、headless 可）。
const SCENE := "res://maps/village_v2/village_v2.tscn"
const FLib := preload("res://tools/village_v2_farmland_lib.gd")
const ZLib := preload("res://tools/village_v2_farmland_zone.gd")


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var P: Dictionary = FLib.plan()
	var pts: Array = []     # [Vector2 p, float ground]
	for br: Dictionary in P["zone"]["branches"]:
		if br["id"] != "T0":
			continue
		for r: Dictionary in br["runs"]:
			if r["kind"] != "open":
				continue
			var line: PackedVector2Array = r["line"]
			for sp: Array in ZLib.branch_spans(r):
				if sp[0] != "trough":
					continue
				var s: float = float(sp[1])
				while s <= float(sp[2]):
					var p: Vector2 = FLib.at_s(line, s)[0]
					pts.append([p, ZLib.ground_h(p), ZLib.branch_water(r, s)])
					s += 0.5
	print("[BEDX] 木槽の取樣点 %d" % pts.size())
	var v: Node3D = (load(SCENE) as PackedScene).instantiate()
	root.add_child(v)
	await process_frame
	var skip_prefix := ["Terrain", "Water", "Collision", "Debug", "Navigation", "Portals", "QuestAnchors", "Lighting"]
	var hits := {}
	var nchk := 0
	for n in v.find_children("*", "VisualInstance3D", true, false):
		var vi := n as VisualInstance3D
		var path := String(v.get_path_to(vi))
		if path.get_slice("/", 0) in skip_prefix or path.contains("/Branches/") or path.contains("/Plots/") or path.contains("EarthBanks"):
			continue
		if not (vi is MeshInstance3D or vi is MultiMeshInstance3D):
			continue
		var ab: AABB = vi.global_transform * vi.get_aabb()
		# 木槽の台の外接範囲に入らなければ除外
		var near := false
		for q: Array in pts:
			var p: Vector2 = q[0]
			if ab.position.x - 1.0 <= p.x and p.x <= ab.end.x + 1.0 and ab.position.z - 1.0 <= p.y and p.y <= ab.end.z + 1.0:
				near = true
				break
		if not near:
			continue
		nchk += 1
		# 頂点（メッシュ）／実例（MultiMesh）が台の範囲（木槽中心から 1.0 m、地面〜水面）に入るか
		var cnt := 0
		if vi is MeshInstance3D and (vi as MeshInstance3D).mesh != null:
			var xf := vi.global_transform
			for s in (vi as MeshInstance3D).mesh.get_surface_count():
				for vv: Vector3 in (vi as MeshInstance3D).mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
					var w := xf * vv
					for q: Array in pts:
						if Vector2(w.x, w.z).distance_to(q[0]) <= 1.0 and w.y >= float(q[1]) - 0.02 and w.y <= float(q[2]) + 0.3:
							cnt += 1
							break
		elif vi is MultiMeshInstance3D:
			var mm := (vi as MultiMeshInstance3D).multimesh
			if mm != null and DisplayServer.get_name() != "headless":
				for i in mm.instance_count:
					var o := (vi.global_transform * mm.get_instance_transform(i)).origin
					for q: Array in pts:
						if Vector2(o.x, o.z).distance_to(q[0]) <= 1.0 and o.y >= float(q[1]) - 0.02 and o.y <= float(q[2]) + 0.3:
							cnt += 1
							break
			else:
				cnt = -1    # headless では MultiMesh の位置を読めない（未検証）
		if cnt != 0:
			hits[path] = cnt
	print("[BEDX] 範囲に近い可見ノード %d、台の範囲に頂点／実例が入るもの %d" % [nchk, hits.size()])
	for k in hits:
		print("[BEDX]   ", k, " ", hits[k])
	quit(0)

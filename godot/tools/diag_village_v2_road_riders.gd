extends SceneTree
## 「騎在路面上」的東西有多少：把路面往下貼地時，這些會變成浮空。非 headless（要讀 MultiMesh）。
##   ① 可見網格（非 Roads／Terrain）的頂點：y 落在「舊路面 + 0..0.05」且舊路面高於地形 2 cm 以上
##   ② MultiMesh instance 原點：同上
## 依節點群組彙總。

const TR := 1 << 21
const TT := 1 << 22


func _init() -> void:
	_run.call_deferred()


func _meshes(n: Node, out: Array, cls: String) -> void:
	if n.is_class(cls) and n.get("multimesh" if cls == "MultiMeshInstance3D" else "mesh") != null:
		out.append(n)
	for c in n.get_children():
		_meshes(c, out, cls)


func _body(scn: Node, nodes: Array, layer: int) -> void:
	var sb := StaticBody3D.new()
	sb.collision_layer = layer
	sb.collision_mask = 0
	scn.add_child(sb)
	for mi: MeshInstance3D in nodes:
		var cs := CollisionShape3D.new()
		cs.shape = mi.mesh.create_trimesh_shape()
		sb.add_child(cs)
		cs.global_transform = mi.global_transform


func _run() -> void:
	var scn: Node3D = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	root.add_child(scn)
	for i in 6:
		await process_frame
	var roads: Array = []
	for g in ["MainStreet", "SecondaryRoads", "Alleys", "FarmPaths"]:
		_meshes(scn.get_node("Roads/" + g), roads, "MeshInstance3D")
	var terr: Array = []
	_meshes(scn.get_node("Terrain"), terr, "MeshInstance3D")
	_body(scn, roads, TR)
	_body(scn, terr, TT)
	for i in 3:
		await physics_frame
	var sp := scn.get_world_3d().direct_space_state
	var road_aabb := AABB()
	for mi: MeshInstance3D in roads:
		road_aabb = road_aabb.merge(mi.global_transform * mi.get_aabb()) if road_aabb.size != Vector3.ZERO else mi.global_transform * mi.get_aabb()
	var stat := {}
	var probe := func(p: Vector3, key: String) -> void:
		var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 1.0, 0), p - Vector3(0, 1.0, 0), TR)
		var hr := sp.intersect_ray(q)
		if hr.is_empty():
			return
		var q2 := PhysicsRayQueryParameters3D.create(p + Vector3(0, 2.0, 0), p - Vector3(0, 2.0, 0), TT)
		var ht := sp.intersect_ray(q2)
		if ht.is_empty():
			return
		var ry: float = hr.position.y
		var ty: float = ht.position.y
		if ry - ty < 0.02:
			return
		var dy := p.y - ry
		if dy < -0.004 or dy > 0.05:
			return
		if not stat.has(key):
			stat[key] = [0, 0.0]
		stat[key][0] += 1
		stat[key][1] = maxf(stat[key][1], ry - ty)
	var meshes: Array = []
	_meshes(scn, meshes, "MeshInstance3D")
	for mi: MeshInstance3D in meshes:
		var path := String(scn.get_path_to(mi))
		if path.begins_with("Roads/") or path.begins_with("Terrain/") or not mi.is_visible_in_tree():
			continue
		var ab := mi.global_transform * mi.get_aabb()
		if not ab.grow(0.5).intersects(road_aabb):
			continue
		var key := "mesh " + "/".join(path.split("/").slice(0, 3))
		var xf := mi.global_transform
		for s in mi.mesh.get_surface_count():
			var v: PackedVector3Array = mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			for p in v:
				var w := xf * p
				if w.y > ab.position.y + 0.5:
					continue   # 只看網格底部附近的頂點（立在路上的東西的底）
				probe.call(w, key)
	var mms: Array = []
	_meshes(scn, mms, "MultiMeshInstance3D")
	var mm_total := 0
	for mmi: MultiMeshInstance3D in mms:
		if not mmi.is_visible_in_tree():
			continue
		var path := String(scn.get_path_to(mmi))
		var key := "mm   " + "/".join(path.split("/").slice(0, 3))
		var mm := mmi.multimesh
		var xf := mmi.global_transform
		for i in mm.instance_count:
			var w := xf * mm.get_instance_transform(i).origin
			mm_total += 1
			probe.call(w, key)
	print("[ride] MultiMesh instance 總數 %d" % mm_total)
	var keys := stat.keys()
	keys.sort()
	for k in keys:
		print("[ride] %-70s n=%6d  該處舊路面離地最大 %.3f" % [k, stat[k][0], stat[k][1]])
	quit(0)

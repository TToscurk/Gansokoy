extends SceneTree
## P11 R2B TASK06（只讀、headless）：石燈籠の底（LOD0 頂点の最低）と足元の地形（TerrainCollision）の差。
## 參道（ShrineApproachP10/Lanterns）と龍神像前（WatersideP9 の gk_toro_kasuga）。
func _init() -> void:
	_run.call_deferred()

func _ground(sp: PhysicsDirectSpaceState3D, x: float, z: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 80, z), Vector3(x, -20, z))
	var ex: Array[RID] = []
	for t in 16:
		q.exclude = ex
		var h := sp.intersect_ray(q)
		if h.is_empty():
			return NAN
		if String((h.collider as Node).name).begins_with("TerrainCollision"):
			return h.position.y
		ex.append(h.rid)
	return NAN

func _run() -> void:
	var v: Node3D = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	root.add_child(v)
	for i in 4:
		await physics_frame
	var sp := v.get_world_3d().direct_space_state
	var mesh: Mesh = load("res://assets/village_v2/garden_kit/mesh/gk_toro_kasuga.res")
	print("[TORO] mesh aabb ", mesh.get_aabb())
	var found := 0
	for mi in v.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).mesh
		if m == null or m.resource_path != mesh.resource_path:
			continue
		_report(sp, String(v.get_path_to(mi)), (mi as MeshInstance3D).global_transform, m)
		found += 1
	for mm in v.find_children("*", "MultiMeshInstance3D", true, false):
		var mmesh := (mm as MultiMeshInstance3D).multimesh
		if mmesh and mmesh.mesh and mmesh.mesh.resource_path == mesh.resource_path:
			print("[TORO] MultiMesh ", v.get_path_to(mm), " n=", mmesh.instance_count, "（headless では位置不明）")
	print("[TORO] instances ", found)
	quit(0)

func _report(sp: PhysicsDirectSpaceState3D, path: String, xf: Transform3D, m: Mesh) -> void:
	var vs: PackedVector3Array = m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var lo := INF
	for p in vs:
		lo = minf(lo, (xf * p).y)
	var gaps := []
	var bot := []
	for p in vs:
		var w := xf * p
		if w.y < lo + 0.02:
			var g := _ground(sp, w.x, w.z)
			if not is_nan(g):
				gaps.append(w.y - g)
	gaps.sort()
	print("[TORO] %-60s 底 %.3f  底頂点-地面: min %+.3f max %+.3f (n %d)" % [path, lo, gaps[0] if gaps.size() else NAN, gaps[-1] if gaps.size() else NAN, gaps.size()])

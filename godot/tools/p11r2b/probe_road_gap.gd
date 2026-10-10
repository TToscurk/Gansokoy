extends SceneTree
## P11 R2B TASK02 診断（只讀、headless）：道路 ribbon 頂點と地形コリジョン（射線）の高さ差を道路ごとに集計。
## RoadBaseP10 の runtime 差し替え後の mesh も対象（_ready 後に計測）。
##   godot --headless --path . --script res://tools/p11r2b/probe_road_gap.gd -- [out.json]
const SCENE := "res://maps/village_v2/village_v2.tscn"

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var v: Node3D = (load(SCENE) as PackedScene).instantiate()
	root.add_child(v)
	for i in 4:
		await physics_frame
	var sp := v.get_world_3d().direct_space_state
	var terr_rid: RID = (v.get_node("Collision/TerrainCollision") as CollisionObject3D).get_rid()
	var out := {}
	for mi in v.get_node("Roads").find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).mesh
		if m == null or m.get_surface_count() == 0:
			continue
		var path := String(v.get_path_to(mi))
		if path.begins_with("Roads/Bridges"):
			continue
		var arr := m.surface_get_arrays(0)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var xf: Transform3D = (mi as Node3D).global_transform
		var gaps := PackedFloat32Array()
		var worst := Vector3()
		var wg := -INF
		var stepn := maxi(1, vs.size() / 1500)
		for k in range(0, vs.size(), stepn):
			var w := xf * vs[k]
			var q := PhysicsRayQueryParameters3D.create(w + Vector3.UP * 5.0, w - Vector3.UP * 20.0)
			var ex: Array[RID] = []
			var g := -INF
			for t in 6:
				q.exclude = ex
				var h := sp.intersect_ray(q)
				if h.is_empty():
					break
				if h.rid == terr_rid:
					g = h.position.y
					break
				ex.append(h.rid)
			if g == -INF:
				continue
			var d := w.y - g
			gaps.append(d)
			if d > wg:
				wg = d
				worst = w
		if gaps.is_empty():
			continue
		var s := Array(gaps)
		s.sort()
		var n := s.size()
		var mat := (mi as MeshInstance3D).material_override
		var cull := ""
		if mat is ShaderMaterial and (mat as ShaderMaterial).shader:
			var code := (mat as ShaderMaterial).shader.code
			cull = "cull_disabled" if code.find("cull_disabled") >= 0 else ("cull_front" if code.find("cull_front") >= 0 else "cull_back")
		out[path] = {"n": n, "min": s[0], "p50": s[n / 2], "p95": s[int(n * 0.95)], "max": s[n - 1],
			"gt015": s.filter(func(x): return x > 0.15).size(), "gt025": s.filter(func(x): return x > 0.25).size(),
			"worst": [snappedf(worst.x, 0.1), snappedf(worst.y, 0.01), snappedf(worst.z, 0.1)], "cull": cull}
		print("%-44s n=%5d min=%+.3f p50=%+.3f p95=%+.3f max=%+.3f >0.15:%d >0.25:%d %s worst=%s" % [path, n, s[0], s[n / 2], s[int(n * 0.95)], s[n - 1], out[path].gt015, out[path].gt025, cull, out[path].worst])
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		var f := FileAccess.open(args[0], FileAccess.WRITE)
		f.store_string(JSON.stringify(out, "\t"))
	quit(0)

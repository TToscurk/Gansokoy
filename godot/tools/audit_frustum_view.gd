extends SceneTree
## Frustum census from a fixed camera: which objects are inside the view
## frustum and how many triangles they contribute. Approximates the visible
## pass so we can see what is actually drawn from the street.
## Run windowed or headless (frustum math only).

const VIEWS := [
	{"name": "主街街道", "pos": Vector3(235.0, 1.7, -10.0), "look": Vector3(235.0, 3.0, 60.0)},
	{"name": "河岸水車", "pos": Vector3(430.0, 4.0, 10.0), "look": Vector3(300.0, 2.0, 20.0)},
]
var _cache := {}


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := ResourceLoader.load("res://maps/slice/slice.tscn", "PackedScene") as PackedScene
	var scene := packed.instantiate()
	root.add_child(scene)
	for i in 4:
		await process_frame
	for v in VIEWS:
		var cam := Camera3D.new()
		cam.fov = 72.0
		cam.far = 4000.0
		root.add_child(cam)
		cam.global_position = v["pos"]
		cam.look_at(v["look"], Vector3.UP)
		var planes := cam.get_frustum()
		var rows: Array = []
		_walk(scene, planes, cam.global_position, rows)
		rows.sort_custom(func(a, b): return a["tris"] > b["tris"])
		var total := 0
		for r in rows:
			total += r["tris"]
		print("=== %s：視錐內 %d 個物件，%s 面 ===" % [v["name"], rows.size(), _fmt(total)])
		for i in min(25, rows.size()):
			var r = rows[i]
			print("  %-62s %10s ×%-4d %5.0f m" % [String(r["path"]).substr(maxi(0, String(r["path"]).length() - 62)), _fmt(r["tris"]), r["inst"], r["dist"]])
		cam.queue_free()
	print("done")
	quit(0)


func _walk(n: Node, planes: Array, eye: Vector3, rows: Array) -> void:
	if n is GeometryInstance3D and (n as Node3D).is_visible_in_tree():
		var gi := n as GeometryInstance3D
		var aabb := gi.global_transform * gi.get_aabb()
		var inside := true
		for p in planes:
			if (p as Plane).is_point_over(aabb.position) and _all_corners_over(p, aabb):
				inside = false
				break
		var d := eye.distance_to(aabb.get_center())
		if inside and (gi.visibility_range_end <= 0.0 or d < gi.visibility_range_end):
			var mesh: Mesh = null
			var inst := 1
			if gi is MeshInstance3D:
				mesh = (gi as MeshInstance3D).mesh
			elif gi is MultiMeshInstance3D and (gi as MultiMeshInstance3D).multimesh != null:
				mesh = (gi as MultiMeshInstance3D).multimesh.mesh
				inst = (gi as MultiMeshInstance3D).multimesh.instance_count
			if mesh != null:
				var t := _tris(mesh) * inst
				if t > 0:
					rows.append({"path": gi.get_path(), "tris": t, "inst": inst, "dist": d})
	for c in n.get_children():
		_walk(c, planes, eye, rows)


func _all_corners_over(p: Plane, b: AABB) -> bool:
	for i in 8:
		if not p.is_point_over(b.get_endpoint(i)):
			return false
	return true


func _tris(mesh: Mesh) -> int:
	if _cache.has(mesh):
		return _cache[mesh]
	var t := 0
	for i in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(i)
		if arr.is_empty():
			continue
		var idx = arr[Mesh.ARRAY_INDEX]
		t += (idx.size() / 3) if idx != null and idx.size() > 0 else (arr[Mesh.ARRAY_VERTEX].size() / 3)
	_cache[mesh] = t
	return t


func _fmt(n: int) -> String:
	var s := str(n)
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return out

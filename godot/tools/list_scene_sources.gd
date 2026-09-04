extends SceneTree
## List every distinct source GLB used by maps/slice with its triangle count and
## instance count, so decimation targets the files the scene really loads.
##
## Needed because the buildings are referenced through nested sub-scenes
## (maps/village/gen/..., maps/slice/gen/b1_street.tscn), so grepping slice.tscn
## for "assets/machiya" finds almost nothing and would send the batch job at the
## wrong files.

func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := ResourceLoader.load("res://maps/slice/slice.tscn", "PackedScene") as PackedScene
	var scene := packed.instantiate()

	# mesh resource -> {tris, count}
	var by_mesh: Dictionary = {}
	_walk(scene, by_mesh)

	var rows: Array = []
	for path in by_mesh:
		rows.append({"path": path, "tris": by_mesh[path]["tris"],
			"n": by_mesh[path]["n"]})
	rows.sort_custom(func(a, b): return a["tris"] * a["n"] > b["tris"] * b["n"])

	var grand := 0
	print("%-46s %10s %5s %12s" % ["來源", "單體面數", "數量", "小計"])
	for r in rows:
		var sub: int = r["tris"] * r["n"]
		grand += sub
		if sub < 200000:
			continue
		print("%-46s %10d %5d %12d" % [r["path"], r["tris"], r["n"], sub])
	print("合計 %d 三角面" % grand)
	print("done")
	quit(0)


func _walk(n: Node, acc: Dictionary) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh != null:
			var p := mi.mesh.resource_path
			if p == "":
				# Mesh embedded in an imported scene: attribute it to the scene.
				p = String(mi.name) + " (內嵌)"
			if not acc.has(p):
				acc[p] = {"tris": _tris(mi.mesh), "n": 0}
			acc[p]["n"] += 1
	for c in n.get_children():
		_walk(c, acc)


func _tris(m: Mesh) -> int:
	var t := 0
	for s in m.get_surface_count():
		var arr := m.surface_get_arrays(s)
		if arr.is_empty():
			continue
		var idx = arr[Mesh.ARRAY_INDEX]
		if idx != null and idx.size() > 0:
			t += idx.size() / 3
		else:
			var v = arr[Mesh.ARRAY_VERTEX]
			if v != null:
				t += v.size() / 3
	return t

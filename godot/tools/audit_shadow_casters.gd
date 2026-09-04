extends SceneTree
## What is in the shadow pass? For every GeometryInstance3D that still casts,
## report tris × instances, so we can see who owns the 28M-vs-5.6M gap
## bench_slice showed between shadow on/off.

var _cache := {}


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := ResourceLoader.load("res://maps/slice/slice.tscn", "PackedScene") as PackedScene
	var scene := packed.instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame  # let 場景效能裁剪 apply

	var rows: Array = []
	_walk(scene, rows)
	rows.sort_custom(func(a, b): return a["tris"] > b["tris"])
	var total := 0
	for r in rows:
		total += r["tris"]
	print("=== 仍在投影的物件（裁剪後）===  合計 %s 面" % _fmt(total))
	print("%-52s %12s %6s %6s" % ["節點", "投影面數", "實例", "類型"])
	for i in min(40, rows.size()):
		var r = rows[i]
		var p := String(r["path"])
		print("%-60s %12s %6d %6s" % [p.substr(maxi(0, p.length() - 60)), _fmt(r["tris"]), r["inst"], r["kind"]])
	# Group by top-level ancestor
	var by := {}
	for r in rows:
		by[r["group"]] = by.get(r["group"], 0) + r["tris"]
	var ks := by.keys()
	ks.sort_custom(func(a, b): return by[a] > by[b])
	print("\n--- 依群組 ---")
	for k in ks:
		if by[k] < 100000:
			break
		print("  %-30s %s" % [String(k).substr(0, 30), _fmt(by[k])])
	print("done")
	quit(0)


func _walk(n: Node, rows: Array, group: String = "") -> void:
	if n.get_parent() != null and n.get_parent().get_parent() == root:
		group = String(n.name)
	if n is GeometryInstance3D and (n as GeometryInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and (n as Node3D).is_visible_in_tree():
		var mesh: Mesh = null
		var inst := 1
		var kind := "MI"
		if n is MeshInstance3D:
			mesh = (n as MeshInstance3D).mesh
		elif n is MultiMeshInstance3D:
			var mm := (n as MultiMeshInstance3D).multimesh
			if mm != null:
				mesh = mm.mesh
				inst = mm.instance_count
			kind = "MM"
		if mesh != null:
			var t := _tris(mesh) * inst
			if t > 0:
				rows.append({"path": n.get_path(), "tris": t, "inst": inst, "kind": kind, "group": group})
	for c in n.get_children():
		_walk(c, rows, group)


func _tris(mesh: Mesh) -> int:
	if _cache.has(mesh):
		return _cache[mesh]
	var t := 0
	for i in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(i)
		if arr.is_empty():
			continue
		var idx = arr[Mesh.ARRAY_INDEX]
		if idx != null and idx.size() > 0:
			t += idx.size() / 3
		else:
			var v = arr[Mesh.ARRAY_VERTEX]
			if v != null:
				t += v.size() / 3
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

extends SceneTree
## Cost census for maps/slice: what is actually expensive, ranked.
##
## Why measure before optimising: this scene has accumulated a lot in one
## session — 113k grass tufts, 291 bank plants, 1600+ scatter MultiMeshes, a new
## 892k-triangle collision body, real-time sky, volumetric fog, precipitation
## and 14 shadow-casting lights. Any of those could dominate, and guessing wrong
## means paying for an optimisation that buys nothing. Count everything, sort by
## cost, and only then decide.
##
## Reports per category: node count, triangle count, and the specific flags that
## drive GPU cost (shadow casting, transparency, GI mode).
##
## Run: godot --headless --path godot --script tools/audit_scene_cost.gd

const SCENE := "res://maps/slice/slice.tscn"


func _init() -> void:
	var packed: PackedScene = load(SCENE)
	if packed == null:
		push_error("cannot load %s" % SCENE)
		quit(1)
		return
	var root := packed.instantiate()

	var groups := {}     # top-level node name -> stats
	var totals := {
		"nodes": 0, "mesh": 0, "tris": 0, "mm": 0, "mm_inst": 0,
		"shadow": 0, "lights": 0, "particles": 0, "collision_tris": 0,
	}

	for child in root.get_children():
		var s := {
			"nodes": 0, "mesh": 0, "tris": 0, "mm": 0, "mm_inst": 0,
			"shadow": 0, "lights": 0, "particles": 0, "collision_tris": 0,
			"visible": child.visible if child is Node3D else true,
		}
		_walk(child, s)
		groups[child.name] = s
		for k in totals:
			totals[k] += s[k]

	# Rank by triangles actually submitted: MultiMesh instances multiply their
	# mesh's triangle count, which is where the real cost hides.
	var names := groups.keys()
	names.sort_custom(func(a, b): return groups[a]["tris"] > groups[b]["tris"])

	print("=== maps/slice 成本普查 ===\n")
	print("%-26s %10s %8s %9s %8s %7s %6s %s" % [
		"節點", "三角面", "網格", "MM實例", "投影", "光源", "粒子", "可見"])

	for n in names:
		var g = groups[n]
		if g["tris"] == 0 and g["lights"] == 0 and g["particles"] == 0:
			continue
		print("%-26s %10s %8d %9d %8d %7d %6d %s" % [
			n.substr(0, 26),
			_fmt(g["tris"]), g["mesh"], g["mm_inst"],
			g["shadow"], g["lights"], g["particles"],
			"" if g["visible"] else "隱藏"])

	print("\n--- 合計 ---")
	print("  三角面      %s" % _fmt(totals["tris"]))
	print("  MeshInstance %d" % totals["mesh"])
	print("  MultiMesh    %d 個，共 %s 個實例" % [totals["mm"], _fmt(totals["mm_inst"])])
	print("  投影物件     %d" % totals["shadow"])
	print("  光源         %d" % totals["lights"])
	print("  粒子系統     %d" % totals["particles"])
	print("  碰撞三角面   %s" % _fmt(totals["collision_tris"]))

	root.free()
	quit(0)


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


func _walk(node: Node, s: Dictionary) -> void:
	s["nodes"] += 1

	if node is MultiMeshInstance3D:
		var mi := node as MultiMeshInstance3D
		s["mm"] += 1
		var mm := mi.multimesh
		if mm != null:
			var n := mm.instance_count
			s["mm_inst"] += n
			if mm.mesh != null:
				s["tris"] += _tris(mm.mesh) * n
		if mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			s["shadow"] += 1
	elif node is MeshInstance3D:
		var m := node as MeshInstance3D
		s["mesh"] += 1
		if m.mesh != null:
			s["tris"] += _tris(m.mesh)
		if m.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			s["shadow"] += 1
	elif node is Light3D:
		s["lights"] += 1
	elif node is GPUParticles3D or node is CPUParticles3D:
		s["particles"] += 1
	elif node is CollisionShape3D:
		var cs := node as CollisionShape3D
		if cs.shape is ConcavePolygonShape3D:
			s["collision_tris"] += (cs.shape as ConcavePolygonShape3D).get_faces().size() / 3

	for c in node.get_children():
		_walk(c, s)


func _tris(mesh: Mesh) -> int:
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
	return t

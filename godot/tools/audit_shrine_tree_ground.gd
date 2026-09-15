extends SceneTree
## 換樹後落地驗收：載入 shrine.tscn，量每棵樹世界 AABB 底邊 vs 地形高度。
##   Godot --headless --path godot --script tools/audit_shrine_tree_ground.gd

const SCENE := "res://maps/shrine/shrine.tscn"
const TREES := ["大衫", "2大衫", "普通樹", "針葉樹1", "針葉樹2glb", "針葉林樹3", "針葉林樹4"]


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var ps := load(SCENE) as PackedScene
	var rootn := ps.instantiate() as Node3D
	root.add_child(rootn)
	await process_frame
	var terr: MeshInstance3D = _find_terrain(rootn)
	if terr == null:
		print("找不到地形")
		quit()
		return
	var tri: PackedVector3Array = terr.mesh.get_faces()
	var tb: AABB = terr.global_transform * terr.mesh.get_aabb()
	print("地形節點 %s  三角 %d  AABB %s  size %s"
		% [terr.get_path(), tri.size() / 3, tb.position, tb.size])
	# 地形自身的世界變換要套到頂點上，否則取樣的是本地座標。
	var xf: Transform3D = terr.global_transform
	for i in tri.size():
		tri[i] = xf * tri[i]
	var dbg := 0

	var stats: Dictionary = {}
	var floats := 0
	var sunk := 0
	var total := 0
	var worst := 0.0
	for n in _walk(rootn):
		var nm: String = n.name
		var species := ""
		for t in TREES:
			if nm.begins_with(t):
				species = t
				break
		if species == "":
			continue
		var mi: MeshInstance3D = _first_mesh(n)
		if mi == null:
			continue
		var box: AABB = mi.global_transform * mi.mesh.get_aabb()
		var p := box.position + Vector3(box.size.x * 0.5, 0.0, box.size.z * 0.5)
		var gy := _terrain_y(tri, p.x, p.z)
		if is_nan(gy):
			continue
		var drift := box.position.y - gy
		if dbg < 6:
			dbg += 1
			print("  DBG %-14s bottom %+.3f  ground %+.3f  xz (%.1f, %.1f)"
				% [nm, box.position.y, gy, p.x, p.z])
		total += 1
		if drift > 0.35:
			floats += 1
		elif drift < -0.6:
			sunk += 1
		if absf(drift) > absf(worst):
			worst = drift
		if not stats.has(species):
			stats[species] = [0, 0.0, 0.0]
		stats[species][0] += 1
		stats[species][1] += drift
		stats[species][2] = maxf(stats[species][2], absf(drift))
	for k in stats:
		var s: Array = stats[k]
		print("%-10s %4d 棵  平均落差 %+.3f m  最大 %.3f m  高 %.2f m"
			% [k, s[0], s[1] / float(s[0]), s[2], 0.0])
	print("AUDIT total=%d floating(>0.35)=%d sunk(<-0.6)=%d worst=%+.3f m"
		% [total, floats, sunk, worst])
	quit()


func _terrain_y(tri: PackedVector3Array, x: float, z: float) -> float:
	var best := NAN
	var bd := 1e9
	var i := 0
	while i < tri.size():
		var a: Vector3 = tri[i]
		var d: float = (a.x - x) * (a.x - x) + (a.z - z) * (a.z - z)
		if d < bd:
			bd = d
			best = a.y
		i += 3
	return best


func _find_terrain(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D and String(n.name).findn("terrain") >= 0:
		return n
	if n is MeshInstance3D and String(n.name).find("地形") >= 0:
		return n
	for c in n.get_children():
		var r := _find_terrain(c)
		if r != null:
			return r
	return null


func _first_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		return n
	for c in n.get_children():
		var r := _first_mesh(c)
		if r != null:
			return r
	return null


func _walk(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out

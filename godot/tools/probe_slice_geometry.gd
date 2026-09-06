extends SceneTree
## Per-mesh geometry for 鯢吞亭 / 霧雨店 / 龍石像橋, read from a CLEAN instantiation
## of slice.tscn with the runtime LOD cull disabled — the same conditions
## gen_building_collision.gd bakes under.
##
## Why not main.tscn: 場景效能裁剪 swaps meshes at runtime, and setting 啟用=false
## afterwards does not put the originals back. Reading AABBs there reports the
## merged LOD mesh for every node in a building (all three 霧雨店 meshes came back
## with identical 124167 tris and an identical AABB), which is not the geometry
## the colliders were built from.
##
## Run: godot --headless --path godot --script tools/probe_slice_geometry.gd

const TARGETS := ["鯢吞亭", "霧雨店", "龍石像橋"]

var _root: Node3D


func _init() -> void:
	var packed: PackedScene = load("res://maps/slice/slice.tscn")
	_root = packed.instantiate()
	root.add_child(_root)
	var cull := _root.get_node_or_null("場景效能裁剪")
	if cull != null:
		cull.set("啟用", false)
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await process_frame

	var bc := _root.get_node_or_null("建物碰撞")
	var hulls := {}
	if bc != null:
		for c in bc.get_children():
			var cs: CollisionShape3D = c.get_child(0)
			if cs == null or cs.shape == null:
				continue
			hulls[String(c.name)] = {
				"box": cs.global_transform * cs.shape.get_debug_mesh().get_aabb(),
				"kind": cs.shape.get_class(),
			}

	for t in TARGETS:
		var n := _root.get_node_or_null(t)
		print("── %s ──" % t)
		if n == null:
			print("  節點不存在")
			continue
		for mi in _meshes(n):
			if mi.mesh == null:
				continue
			var b: AABB = mi.global_transform * mi.get_aabb()
			var key := "%s_%s" % [t, mi.name]
			var line := "  %-44s tris %7d  底 %6.2f 頂 %6.2f  XZ %5.2f×%5.2f" % [
				mi.name, _tris(mi.mesh), b.position.y, b.position.y + b.size.y,
				b.size.x, b.size.z]
			if hulls.has(key):
				var h: Dictionary = hulls[key]
				var hb: AABB = h["box"]
				var d: Vector3 = hb.get_center() - b.get_center()
				line += "\n      碰撞 %-22s 底 %6.2f 頂 %6.2f  XZ %5.2f×%5.2f  偏移 %.2f m" % [
					h["kind"], hb.position.y, hb.position.y + hb.size.y,
					hb.size.x, hb.size.z, d.length()]
				hulls.erase(key)
			else:
				line += "\n      碰撞 無"
			print(line)

	var leftover := []
	for k in hulls.keys():
		for t in TARGETS:
			if String(k).begins_with(t):
				leftover.append(k)
	if not leftover.is_empty():
		print("── 對不上任何 mesh 的碰撞體 ──")
		for k in leftover:
			print("  %s" % k)

	print("done")
	quit(0)


func _meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out


func _tris(m: Mesh) -> int:
	var t := 0
	for s in m.get_surface_count():
		var arr := m.surface_get_arrays(s)
		if arr.is_empty():
			continue
		var idx = arr[Mesh.ARRAY_INDEX]
		t += (idx.size() / 3) if idx != null and idx.size() > 0 else (arr[Mesh.ARRAY_VERTEX].size() / 3)
	return t

extends SceneTree
## 圍牆四個外端的候選折牆位置：列出會相交的可見網格（只量，不改）。
## Godot --headless --path godot --script tools/probe_wall_corners.gd

# 主牆外端（實測）：南牆 x 212.29 / 260.07 @ z 96.24..98.79；北牆 x 212.76 / 258.02 @ z -78.17..-75.62
const CANDS: Array = [
	["SW_in",  AABB(Vector3(211.0, 0.0, 77.0),  Vector3(3.0, 5.0, 19.5))],
	["SW_out", AABB(Vector3(211.0, 0.0, 98.5),  Vector3(3.0, 5.0, 19.5))],
	["SE_in",  AABB(Vector3(258.5, 0.0, 77.0),  Vector3(3.0, 5.0, 19.5))],
	["SE_out", AABB(Vector3(258.5, 0.0, 98.5),  Vector3(3.0, 5.0, 19.5))],
	["NW_in",  AABB(Vector3(211.5, 0.0, -78.5), Vector3(3.0, 5.0, 19.5))],
	["NW_out", AABB(Vector3(211.5, 0.0, -97.5), Vector3(3.0, 5.0, 19.5))],
	["NE_in",  AABB(Vector3(256.5, 0.0, -78.5), Vector3(3.0, 5.0, 19.5))],
	["NE_out", AABB(Vector3(256.5, 0.0, -97.5), Vector3(3.0, 5.0, 19.5))],
	# 沿牆線往外延伸（袖石垣收尾）
	["S_W_ext", AABB(Vector3(204.0, 0.0, 95.5),  Vector3(8.3, 5.0, 4.0))],
	["S_E_ext", AABB(Vector3(260.1, 0.0, 95.5),  Vector3(8.3, 5.0, 4.0))],
	["N_W_ext", AABB(Vector3(204.5, 0.0, -79.0), Vector3(8.3, 5.0, 4.0))],
	["N_E_ext", AABB(Vector3(258.0, 0.0, -79.0), Vector3(8.3, 5.0, 4.0))],
]
const SKIP: Array = ["UnifiedGround", "GroundUnderlay", "Terrain", "BasinHills", "StreetPaving"]

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var scn: Node3D = load("res://maps/slice/slice.tscn").instantiate()
	root.add_child(scn)
	await process_frame
	var meshes: Array = []
	var stack: Array = [scn]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is MeshInstance3D and n.mesh != null and n.is_visible_in_tree() and not (n.name in SKIP):
			meshes.append([n.get_path(), n.global_transform * n.mesh.get_aabb()])
		elif n is MultiMeshInstance3D and n.multimesh != null and n.is_visible_in_tree():
			var mm: MultiMesh = n.multimesh
			for j in mm.instance_count:
				var p: Vector3 = n.global_transform * mm.get_instance_transform(j).origin
				meshes.append([String(n.get_path()) + "#" + str(j), AABB(p - Vector3(0.3, 0, 0.3), Vector3(0.6, 1, 0.6))])
	for c in CANDS:
		var box: AABB = c[1]
		var hits: Array = []
		var mm_hits := 0
		for m in meshes:
			if box.intersects(m[1]):
				if "#" in String(m[0]):
					mm_hits += 1
				else:
					hits.append("%s %s" % [m[0], m[1]])
		print("CORNER %s box=%s  mesh_hits=%d  multimesh_hits=%d" % [c[0], box, hits.size(), mm_hits])
		for h in hits.slice(0, 12):
			print("   HIT " + h)
	quit(0)

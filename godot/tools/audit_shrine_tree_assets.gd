extends SceneTree
## 神社樹木稽核：列出場景用到的每種樹資產＋數量，並把每種渲染成一張轉台圖，
## 用來認出「三角形葉片的舊式低模樹」。
##   Godot --path godot --script tools/audit_shrine_tree_assets.gd

const OUT := "D:/神社/shrine/_review/shrine_trees/"


func _init() -> void:
	_run.call_deferred()


func _wait(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var scn: Node3D = load("res://maps/shrine/shrine.tscn").instantiate()
	root.add_child(scn)
	await _wait(10)
	# 1. 每個 instance 的 scene_file_path 統計（依父群組分）
	var counts: Dictionary = {}
	var stack: Array = [scn]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n.scene_file_path != "" and n != scn:
			var grp := String(n.get_parent().name)
			var key := n.scene_file_path + " @ " + grp
			counts[key] = counts.get(key, 0) + 1
	var keys: Array = counts.keys()
	keys.sort()
	for k in keys:
		print("ASSET_USE %5d  %s" % [counts[k], k])
	# 2. MultiMesh
	stack = [scn]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh != null:
			var mm: MultiMesh = (n as MultiMeshInstance3D).multimesh
			var m: Mesh = mm.mesh
			print("MULTIMESH %s count=%d mesh=%s surfaces=%d faces=%d aabb=%s" % [
				scn.get_path_to(n), mm.instance_count, m.resource_path if m else "null",
				m.get_surface_count() if m else 0, (m.get_faces().size() / 3) if m else 0,
				m.get_aabb() if m else AABB()])
	quit(0)

extends SceneTree
## 樹木 MultiMesh 節點路徑盤點：確認「同名多節點」是真重複還是分區塊。
##   Godot --headless --path godot --script tools/audit_tree_dupes.gd
var main: Node


func _init() -> void:
	_run.call_deferred()


func _settle(n: int = 4) -> void:
	for i in n:
		await physics_frame
		await process_frame


func _run() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _settle(20)
	main.load_map("slice", "")
	await _settle(40)
	var mr: Node = main.map_root
	var stack: Array[Node] = [mr]
	var rows := []
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.push_back(c)
		if n is MultiMeshInstance3D:
			var mmi := n as MultiMeshInstance3D
			var mm := mmi.multimesh
			if mm == null:
				continue
			var nm := String(n.name)
			if not (nm.begins_with("Trees_") or nm.begins_with("Grove") or nm.begins_with("TakeFence")):
				continue
			# 頭三個實例的世界座標，用來判斷是不是同一批
			var s := ""
			for i in mini(2, mm.instance_count):
				var t: Transform3D = mmi.global_transform * mm.get_instance_transform(i)
				s += "(%.1f,%.1f) " % [t.origin.x, t.origin.z]
			rows.append([mr.get_path_to(n), nm, mm.instance_count, mm.mesh.get_rid(), s,
				mmi.visible, (n as Node3D).is_visible_in_tree()])
	rows.sort_custom(func(a, b): return String(a[1]) < String(b[1]))
	for r in rows:
		print("[DUP] %-34s inst=%-5d meshRID=%s vis=%s/%s inst0=%s"
			% [String(r[0]), r[2], str(r[3]), r[5], r[6], r[4]])
	print("[DUP] 節點數 %d" % rows.size())
	quit(0)

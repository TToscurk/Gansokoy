extends SceneTree
## 獸道 場景盤點（唯讀）：數 beast_path.tscn 內各類道具／森林實例，供審圖報告引用。
##   godot --headless --path godot --script res://tools/beast_path/inventory_beast_path.gd
func _initialize() -> void:
	var inst := (ResourceLoader.load("res://maps/beast_path/beast_path.tscn", "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	root.add_child(inst)
	var kinds := {}
	var specs := {}
	var colliders := 0
	var meshes := 0
	var tris := 0
	for n in inst.find_children("*", "", true, false):
		if n.has_meta("bp_kind"):
			var k := String(n.get_meta("bp_kind"))
			kinds[k] = int(kinds.get(k, 0)) + 1
		if n is CollisionShape3D:
			colliders += 1
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			meshes += 1
			var m := (n as MeshInstance3D).mesh
			for s in m.get_surface_count():
				var arr := m.surface_get_arrays(s)
				if arr.size() > Mesh.ARRAY_INDEX and arr[Mesh.ARRAY_INDEX] != null and (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() > 0:
					tris += (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
				elif arr[Mesh.ARRAY_VERTEX] != null:
					tris += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	var slabs := 0
	for n in inst.find_children("*", "Node3D", true, false):
		if n.has_meta("bp_slab"):
			slabs += 1
	var forest_n := 0
	var species := {}
	for f in inst.find_children("Forest", "Node3D", true, false):
		for c in (f as Node).get_children():
			forest_n += 1
			var key := String(c.name).get_slice("_", 0)
			species[key] = int(species.get(key, 0)) + 1
	var ks := kinds.keys()
	ks.sort()
	print("== 道具（bp_kind）==")
	for k in ks:
		print("  %-16s %d" % [k, kinds[k]])
	print("== 其他 ==")
	print("  崖岩片（bp_slab）  %d" % slabs)
	print("  森林實例           %d" % forest_n)
	print("  CollisionShape3D   %d" % colliders)
	print("  MeshInstance3D     %d  （非森林 prefab 內部的網格三角形合計 %d）" % [meshes, tris])
	quit(0)

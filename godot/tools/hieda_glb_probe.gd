# hieda_blockout.glb 到底是什麼 —— 搬之前要先知道搬的是什麼
#
#   godot --headless --path godot --script tools/hieda_glb_probe.gd
#
# 「把完整版搬過去」聽起來像複製貼上，但 blockout 是 Blender 那邊 join 成
# 一份的**烘焙網格**：沒有地形、沒有碰撞、沒有分件。這支把它拆開來報
# —— 幾個 surface、幾個 mesh 節點、材質怎麼來的、有沒有水面、面數多少。
extends SceneTree


func _init() -> void:
	for path in ["res://assets/models/hieda_blockout.glb",
			"res://assets/models/hieda_main.glb"]:
		_probe(path)
	_probe_modules()
	quit(0)


func _probe(path: String) -> void:
	print("\n════ %s ════" % path)
	var ps: PackedScene = load(path)
	if ps == null:
		print("  ✗ 載不到")
		return
	var n: Node = ps.instantiate()
	var meshes := 0
	var tris := 0
	var surfaces := 0
	var mats := {}
	var has_uv := false
	var has_col := false
	var stack: Array[Node] = [n]
	while stack.size() > 0:
		var c: Node = stack.pop_back()
		for g in c.get_children():
			stack.push_back(g)
		if not (c is MeshInstance3D):
			continue
		meshes += 1
		var m: Mesh = (c as MeshInstance3D).mesh
		if m == null:
			continue
		print("  節點 %s：%d surface" % [c.name, m.get_surface_count()])
		for s in m.get_surface_count():
			surfaces += 1
			var arr := m.surface_get_arrays(s)
			var vc: int = (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			var ic := 0
			if arr[Mesh.ARRAY_INDEX] != null:
				ic = (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size()
			tris += (ic / 3) if ic > 0 else (vc / 3)
			if arr[Mesh.ARRAY_TEX_UV] != null:
				has_uv = true
			if arr[Mesh.ARRAY_COLOR] != null:
				has_col = true
			var mt: Material = m.surface_get_material(s)
			var mk: String = "(無)" if mt == null else (
				mt.resource_name if mt.resource_name != "" else mt.get_class())
			mats[mk] = int(mats.get(mk, 0)) + 1
			var extra := ""
			if mt is StandardMaterial3D:
				var sm := mt as StandardMaterial3D
				extra = "　vc_albedo=%s cull=%d albedo=%s tex=%s" % [
					sm.vertex_color_use_as_albedo, sm.cull_mode,
					sm.albedo_color, "有" if sm.albedo_texture != null else "無"]
			print("      surface %d：%d 頂點 / %d 三角　材質 %s%s"
				% [s, vc, (ic / 3) if ic > 0 else (vc / 3), mk, extra])
	print("  → mesh 節點 %d、surface %d、三角 %d、UV %s、頂點色 %s"
		% [meshes, surfaces, tris, "有" if has_uv else "無", "有" if has_col else "無"])
	print("  → 材質種類：%s" % str(mats.keys()))
	n.queue_free()


func _probe_modules() -> void:
	print("\n════ 植栽模組（MultiMesh 用）════")
	var txt := FileAccess.get_file_as_string("res://data/hieda_garden.instances.json")
	var man: Dictionary = JSON.parse_string(txt)
	var tot := 0
	for k in man["modules"]:
		var glb: String = man["modules"][k]["glb"]
		var ok := ResourceLoader.exists(glb)
		var n: int = (man["modules"][k]["xforms"] as Array).size()
		tot += n
		print("  %-16s %3d 實例　%s　%s" % [k, n, glb.get_file(), "✓" if ok else "✗ 資產不存在"])
	print("  → 共 %d 實例" % tot)
	# maps/hieda/gen/*.res 是不是還能載
	var d := DirAccess.open("res://maps/hieda/gen")
	if d == null:
		print("  ✗ maps/hieda/gen 不存在")
		return
	var n_ok := 0
	var n_bad := 0
	for f in d.get_files():
		if not f.ends_with(".res"):
			continue
		var mm: MultiMesh = load("res://maps/hieda/gen/" + f) as MultiMesh
		if mm == null:
			n_bad += 1
			print("    ✗ %s 載不到" % f)
			continue
		if mm.instance_count == 0 or mm.mesh == null:
			n_bad += 1
			print("    ✗ %s instance_count=%d mesh=%s" % [f, mm.instance_count, mm.mesh])
			continue
		n_ok += 1
	print("  → maps/hieda/gen/*.res：%d 個可用、%d 個有問題" % [n_ok, n_bad])

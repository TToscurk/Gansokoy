extends SceneTree
## 場景裡到底還有幾棵紅葉樹？換色有沒有真的寫進 .tscn？
##   Godot --headless --path godot --script tools/probe_red_leaves.gd

func _init() -> void:
	var ps := load("res://maps/trail/trail.tscn") as PackedScene
	var root := ps.instantiate() as Node3D
	var red := 0
	var green := 0
	var no_override := 0
	var samples: Array = []
	for mi in _mesh_nodes(root):
		var m := mi as MeshInstance3D
		if m.mesh.get_surface_count() < 2:
			continue
		# 用樹皮（surface 0）辨識樹種 —— 葉子可能已被換掉
		var bark := m.mesh.surface_get_material(0)
		var bark_tex := ""
		if bark is StandardMaterial3D and (bark as StandardMaterial3D).albedo_texture != null:
			bark_tex = (bark as StandardMaterial3D).albedo_texture.resource_path.get_file()
		if not bark_tex.begins_with("Bark_TwistedTree"):
			continue
		# 實際生效的材質：override 優先，否則 mesh 自己的 surface material
		var eff := m.get_surface_override_material(1)
		if eff == null:
			eff = m.mesh.surface_get_material(1)
		var t := ""
		if eff is StandardMaterial3D and (eff as StandardMaterial3D).albedo_texture != null:
			t = (eff as StandardMaterial3D).albedo_texture.resource_path.get_file()
		if t.begins_with("Leaves_NormalTree"):
			green += 1
		else:
			red += 1
			if samples.size() < 3:
				samples.append("%s tex=%s" % [m.name, t])
	print("[RED] TwistedTree：仍紅 %d ／ 已換綠 %d" % [red, green])
	for s in samples:
		print("[RED]   樣本 %s" % s)
	root.free()
	quit(0)

func _mesh_nodes(n: Node) -> Array:
	var o := []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null: o.append(n)
	for c in n.get_children(): o.append_array(_mesh_nodes(c))
	return o

extends SceneTree
## 路燈是否真的不再投影？直接讀場景樹裡每個 MeshInstance3D 的 cast_shadow。
##
##   Godot --headless --path godot --script tools/verify_lamp_shadow.gd
##
## road_lamp.tscn 用 index="0" 覆寫實例內部的 mesh_node。那個覆寫語法只有在
## GLB 的子節點順序不變時才對得上，所以不能假設它生效——要實際載入來看。

func _init() -> void:
	var packed: PackedScene = load("res://maps/slice/slice.tscn")
	var src := packed.instantiate()

	var on := 0
	var off := 0
	var tris_off := 0
	for lamp in _lamps(src):
		for mi in _meshes(lamp):
			var m := mi as MeshInstance3D
			var t := 0
			if m.mesh != null:
				for s in m.mesh.get_surface_count():
					t += m.mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX].size() / 3
			if m.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				off += 1
				tris_off += t
			else:
				on += 1
				print("[SH] ✗ %s/%s 仍在投影（%d 面）" % [lamp.name, m.name, t])

	print("[SH] 路燈網格：投影關閉 %d 個、仍開啟 %d 個" % [off, on])
	print("[SH] 省下的投影面數：%d" % tris_off)
	print("[SH] %s" % ("✓ 全部關閉" if on == 0 else "✗ 有漏網的"))

	src.free()
	print("[SH] done")
	quit(0)


func _lamps(node: Node) -> Array:
	var out: Array = []
	if node is Node3D and node.is_in_group("village_lamps"):
		out.append(node)
	for c in node.get_children():
		out.append_array(_lamps(c))
	return out


func _meshes(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(_meshes(c))
	return out

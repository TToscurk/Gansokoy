extends SceneTree
## 鋪石候選資產體檢：尺寸、原點、三角面、貼圖平均色。
##   Godot --headless --path godot --script tools/probe_paving_assets.gd

const NAT := "res://assets/nature/"
const V := ["Pebble_Square_1","Pebble_Square_2","Pebble_Square_3","Pebble_Square_4","Pebble_Square_5","Pebble_Square_6","Pebble_Round_1","Pebble_Round_2","Pebble_Round_3","Pebble_Round_4","Pebble_Round_5"]


func _init() -> void:
	for v in V:
		_one(NAT + v + ".gltf")
	quit(0)


func _one(path: String) -> void:
	var ps := load(path) as PackedScene
	var inst := ps.instantiate() as Node3D
	var box: Variant = null
	var tris := 0
	var col := Color(0, 0, 0)
	var src := "-"
	for m in _meshes(inst):
		var mi := m as MeshInstance3D
		var b := _rel(mi, inst) * mi.get_aabb()
		box = b if box == null else (box as AABB).merge(b)
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			tris += (idx.size() if idx.size() > 0
				else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
			var mat := mi.mesh.surface_get_material(s) as StandardMaterial3D
			if mat != null:
				col = mat.albedo_color
				src = "albedo_color"
				if mat.albedo_texture != null:
					var img := mat.albedo_texture.get_image()
					if img.is_compressed():
						img = img.duplicate(); img.decompress()
					col = _avg(img)
					src = mat.albedo_texture.resource_path.get_file()
	inst.free()
	var bb: AABB = box
	print("[PAVE] %-24s %5.2f x %5.3f x %5.2f  min.y %+.3f  tris %5d  色 %.2f %.2f %.2f  H %5.1f S %.2f V %.2f  %s"
		% [path.get_file().get_basename(), bb.size.x, bb.size.y, bb.size.z, bb.position.y, tris,
			col.r, col.g, col.b, col.h * 360.0, col.s, col.v, src])


func _avg(img: Image) -> Color:
	var step := maxi(1, int(maxf(img.get_width(), img.get_height()) / 64.0))
	var r := 0.0; var g := 0.0; var b := 0.0; var n := 0
	for y in range(0, img.get_height(), step):
		for x in range(0, img.get_width(), step):
			var c := img.get_pixel(x, y)
			if c.a < 0.5: continue
			r += c.r; g += c.g; b += c.b; n += 1
	return Color(r / maxf(n, 1), g / maxf(n, 1), b / maxf(n, 1))


func _meshes(n: Node) -> Array:
	var o := []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		o.append(n)
	for c in n.get_children():
		o.append_array(_meshes(c))
	return o


func _rel(n: Node3D, root: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t

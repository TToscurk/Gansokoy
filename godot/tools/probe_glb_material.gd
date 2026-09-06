extends SceneTree
## 抓 GLB 內建材質的貼圖路徑與參數，好讓程序化面共用同一張。
##   Godot --headless --path godot --script tools/probe_glb_material.gd

const T := [
	"res://assets/shrine/袖石垣.glb",
	"res://assets/shrine/收頭石.glb",
	"res://assets/shrine/踏石.glb",
]


func _init() -> void:
	for p in T:
		_one(p)
	quit(0)


func _one(path: String) -> void:
	var ps := load(path) as PackedScene
	if ps == null:
		print("[MAT] %s 載入失敗" % path)
		return
	var inst := ps.instantiate() as Node3D
	var label := path.get_file().get_basename()
	for m in _meshes(inst):
		var mi := m as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s) as StandardMaterial3D
			if mat == null:
				print("[MAT] %s surface %d 無 StandardMaterial3D" % [label, s])
				continue
			var alb := "null"
			var alb_size := "-"
			if mat.albedo_texture != null:
				alb = mat.albedo_texture.resource_path
				var img := mat.albedo_texture.get_image()
				if img != null:
					alb_size = "%dx%d" % [img.get_width(), img.get_height()]
			var nor := mat.normal_texture.resource_path if mat.normal_texture != null else "null"
			var rgh := mat.roughness_texture.resource_path if mat.roughness_texture != null else "null"
			print("[MAT] %-8s albedo=%s (%s)" % [label, alb, alb_size])
			print("[MAT]          normal=%s" % nor)
			print("[MAT]          rough_tex=%s  roughness=%.2f  metallic=%.2f  albedo_color=(%.2f,%.2f,%.2f)"
				% [rgh, mat.roughness, mat.metallic,
					mat.albedo_color.r, mat.albedo_color.g, mat.albedo_color.b])
			print("[MAT]          uv1_scale=%s triplanar=%s"
				% [str(mat.uv1_scale), str(mat.uv1_triplanar)])
	inst.free()


func _meshes(n: Node) -> Array:
	var o := []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		o.append(n)
	for c in n.get_children():
		o.append_array(_meshes(c))
	return o

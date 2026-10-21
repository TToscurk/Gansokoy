extends SceneTree
## 由 gen_terrain.py 的輸出建出 Godot 資源：
##   maps/shrine_v2/gen/terrain.res      近景地形 ArrayMesh（含法線、UV=0..1 對遮罩）
##   maps/shrine_v2/gen/vista_a.res      中景（±260 m、4 m 格）
##   maps/shrine_v2/gen/vista_b.res      遠景（±1100 m、20 m 格）
##   maps/shrine_v2/gen/ground_mask.res  遮罩貼圖（ImageTexture，帶 mipmap）
## godot --headless --path godot --script res://tools/shrine_v2/build_terrain.gd

const S2 := preload("res://tools/shrine_v2/s2lib.gd")


func _init() -> void:
	_run.call_deferred()


func _build_grid(h: PackedFloat32Array, nx: int, nz: int, x0: float, z0: float, step: float,
		uv_w: float, uv_d: float, flip_hide: bool) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	verts.resize(nx * nz)
	norms.resize(nx * nz)
	uvs.resize(nx * nz)
	for j in nz:
		for i in nx:
			var k := j * nx + i
			var x := x0 + i * step
			var z := z0 + j * step
			verts[k] = Vector3(x, h[k], z)
			var hl: float = h[j * nx + maxi(i - 1, 0)]
			var hr: float = h[j * nx + mini(i + 1, nx - 1)]
			var hu: float = h[maxi(j - 1, 0) * nx + i]
			var hd: float = h[mini(j + 1, nz - 1) * nx + i]
			var dx := (hr - hl) / (float(mini(i + 1, nx - 1) - maxi(i - 1, 0)) * step)
			var dz := (hd - hu) / (float(mini(j + 1, nz - 1) - maxi(j - 1, 0)) * step)
			norms[k] = Vector3(-dx, 1.0, -dz).normalized()
			uvs[k] = Vector2((x - x0) / uv_w, (z - z0) / uv_d)
	var idx := PackedInt32Array()
	idx.resize((nx - 1) * (nz - 1) * 6)
	var n := 0
	for j in nz - 1:
		for i in nx - 1:
			var a := j * nx + i
			var b := a + 1
			var c := a + nx
			var d := c + 1
			if (i + j) % 2 == 0:
				idx[n] = a; idx[n + 1] = b; idx[n + 2] = d
				idx[n + 3] = a; idx[n + 4] = d; idx[n + 5] = c
			else:
				idx[n] = a; idx[n + 1] = b; idx[n + 2] = c
				idx[n + 3] = b; idx[n + 4] = d; idx[n + 5] = c
			n += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


func _read_f32(path: String) -> PackedFloat32Array:
	var f := FileAccess.open(path, FileAccess.READ)
	var a := f.get_buffer(f.get_length()).to_float32_array()
	f.close()
	return a


func _run() -> void:
	var l := S2.load_layout()
	var t: Dictionary = l["terrain"]
	var nx := int(t["nx"])
	var nz := int(t["nz"])
	var x0 := float(t["x0"])
	var z0 := float(t["z0"])
	var step := float(t["step"])
	var h := _read_f32(S2.GEN + "height.f32")
	assert(h.size() == nx * nz)
	var W := float(t["x1"]) - x0
	var D := float(t["z1"]) - z0
	var mesh := _build_grid(h, nx, nz, x0, z0, step, W, D, false)
	mesh.resource_name = "shrine_v2_terrain"
	var err := ResourceSaver.save(mesh, S2.GEN + "terrain.res")
	print("[TERRAIN] terrain.res err=%d verts=%d tris=%d aabb=%s" % [err, nx * nz, (nx - 1) * (nz - 1) * 2, mesh.get_aabb()])

	for key in ["vista_a", "vista_b"]:
		var vi: Dictionary = l[key]
		var n := int(vi["n"])
		var half := float(vi["half"])
		var st := float(vi["step"])
		var vh := _read_f32(S2.GEN + key + ".f32")
		var vm := _build_grid(vh, n, n, -half, -half, st, 2.0 * half, 2.0 * half, false)
		vm.resource_name = "shrine_v2_" + key
		var e2 := ResourceSaver.save(vm, S2.GEN + key + ".res")
		print("[TERRAIN] %s.res err=%d verts=%d aabb=%s" % [key, e2, n * n, vm.get_aabb()])

	var img := Image.load_from_file(ProjectSettings.globalize_path(S2.GEN + "mask.png"))
	img.convert(Image.FORMAT_RGBA8)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	tex.resource_name = "shrine_v2_ground_mask"
	var e3 := ResourceSaver.save(tex, S2.GEN + "ground_mask.res")
	print("[TERRAIN] ground_mask.res err=%d size=%s" % [e3, img.get_size()])
	# 中景／遠景遮罩、落花密度圖：PNG → ImageTexture（含 mipmap）
	for nm in ["vista_a_mask", "vista_b_mask", "petal_mask", "canopy_far"]:
		var pth := ProjectSettings.globalize_path(S2.GEN + nm + ".png")
		if not FileAccess.file_exists(pth):
			print("[TERRAIN] 缺 %s.png（先跑 gen_terrain.py／gen_placements.py）" % nm)
			continue
		var im := Image.load_from_file(pth)
		im.convert(Image.FORMAT_RGBA8)
		im.generate_mipmaps()
		var t2 := ImageTexture.create_from_image(im)
		t2.resource_name = "shrine_v2_" + nm
		var e4 := ResourceSaver.save(t2, S2.GEN + nm + ".res")
		print("[TERRAIN] %s.res err=%d size=%s" % [nm, e4, im.get_size()])
	quit()

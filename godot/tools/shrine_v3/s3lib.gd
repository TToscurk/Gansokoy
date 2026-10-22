extends RefCounted
## shrine_v3 共用函式庫：配置讀取、近景高度場取樣（與 gen_terrain.py export_grid 同一個三角剖分 → 結果＝網格實際高度）。
## 用法：const S3 := preload("res://tools/shrine_v3/s3lib.gd") ； S3.height_at(x, z)

const GEN := "res://maps/shrine_v3/gen/"

static var layout: Dictionary = {}
static var _h: PackedFloat32Array = PackedFloat32Array()
static var _nx := 0
static var _nz := 0
static var _x0 := 0.0
static var _z0 := 0.0
static var _step := 1.0


static func load_layout() -> Dictionary:
	if not layout.is_empty():
		return layout
	layout = JSON.parse_string(FileAccess.get_file_as_string(GEN + "layout.json"))
	return layout


static func load_height() -> void:
	if _h.size() > 0:
		return
	var l := load_layout()
	var nr: Dictionary = l["near"]
	_nx = int(l["near_n"][0])
	_nz = int(l["near_n"][1])
	_x0 = float(nr["x0"])
	_z0 = float(nr["z0"])
	_step = float(nr["step"])
	var f := FileAccess.open(GEN + "h_near.f32", FileAccess.READ)
	_h = f.get_buffer(f.get_length()).to_float32_array()
	f.close()
	assert(_h.size() == _nx * _nz, "h_near.f32 大小不符")


static func grid_h(i: int, j: int) -> float:
	return _h[clampi(j, 0, _nz - 1) * _nx + clampi(i, 0, _nx - 1)]


## 重心座標取樣：(i+j) 偶 = a-d 對角，奇 = b-c 對角。
static func height_at(x: float, z: float) -> float:
	load_height()
	var fx := (x - _x0) / _step
	var fz := (z - _z0) / _step
	var i := clampi(int(floor(fx)), 0, _nx - 2)
	var j := clampi(int(floor(fz)), 0, _nz - 2)
	var u := clampf(fx - float(i), 0.0, 1.0)
	var v := clampf(fz - float(j), 0.0, 1.0)
	var ha := grid_h(i, j)
	var hb := grid_h(i + 1, j)
	var hc := grid_h(i, j + 1)
	var hd := grid_h(i + 1, j + 1)
	if (i + j) % 2 == 0:
		if u >= v:
			return ha + (hb - ha) * u + (hd - hb) * v
		return ha + (hd - hc) * u + (hc - ha) * v
	if u + v <= 1.0:
		return ha + (hb - ha) * u + (hc - ha) * v
	return hd + (hc - hd) * (1.0 - u) + (hb - hd) * (1.0 - v)


static func normal_at(x: float, z: float, e := 0.5) -> Vector3:
	var dx := height_at(x + e, z) - height_at(x - e, z)
	var dz := height_at(x, z + e) - height_at(x, z - e)
	return Vector3(-dx / (2.0 * e), 1.0, -dz / (2.0 * e)).normalized()


## 腳印 3×3 點的最低／最高地面（接地用）。
static func footprint_range(cx: float, cz: float, hw: float, hd: float, yaw: float) -> Vector2:
	var lo := INF
	var hi := -INF
	var basis := Basis(Vector3.UP, yaw)
	for ox in [-1.0, 0.0, 1.0]:
		for oz in [-1.0, 0.0, 1.0]:
			var w := basis * Vector3(float(ox) * hw, 0, float(oz) * hd)
			var y := height_at(cx + w.x, cz + w.z)
			lo = minf(lo, y)
			hi = maxf(hi, y)
	return Vector2(lo, hi)


## 讀 export_grid 寫的二進位網格 → ArrayMesh（含法線、UV＝世界 xz、UV2＝遮罩 0..1）。
static func load_grid_mesh(path: String) -> ArrayMesh:
	var f := FileAccess.open(path, FileAccess.READ)
	var hdr := f.get_buffer(12).to_int32_array()
	var nv := hdr[0]
	var ni := hdr[1]
	var has_uv2 := hdr[2] == 1
	var pos := f.get_buffer(nv * 12).to_float32_array()
	var nrm := f.get_buffer(nv * 12).to_float32_array()
	var uv := f.get_buffer(nv * 8).to_float32_array()
	var uv2 := PackedFloat32Array()
	if has_uv2:
		uv2 = f.get_buffer(nv * 8).to_float32_array()
	var idx := f.get_buffer(ni * 4).to_int32_array()
	f.close()
	var v3 := PackedVector3Array()
	var n3 := PackedVector3Array()
	var t2 := PackedVector2Array()
	var t22 := PackedVector2Array()
	v3.resize(nv)
	n3.resize(nv)
	t2.resize(nv)
	if has_uv2:
		t22.resize(nv)
	for k in nv:
		v3[k] = Vector3(pos[k * 3], pos[k * 3 + 1], pos[k * 3 + 2])
		n3[k] = Vector3(nrm[k * 3], nrm[k * 3 + 1], nrm[k * 3 + 2])
		t2[k] = Vector2(uv[k * 2], uv[k * 2 + 1])
		if has_uv2:
			t22[k] = Vector2(uv2[k * 2], uv2[k * 2 + 1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v3
	arr[Mesh.ARRAY_NORMAL] = n3
	arr[Mesh.ARRAY_TEX_UV] = t2
	if has_uv2:
		arr[Mesh.ARRAY_TEX_UV2] = t22
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


static func ensure_dir(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))


## 存檔＋重試：Windows 上偶發「Cannot save file」（ERR_CANT_OPEN 19；剛寫過的檔被其他程序短暫鎖住）。
## 2026-10-22 美術深化實測：同一管線兩次各有一個檔（shrine_v3.tscn、terrain_near.tres）第一次存不進去，重跑就好。
static func save_retry(res: Resource, path: String, tries := 6) -> int:
	var e := ResourceSaver.save(res, path)
	var n := 1
	while e != OK and n < tries:
		OS.delay_msec(400)
		e = ResourceSaver.save(res, path)
		n += 1
	if e != OK:
		push_error("[s3lib] 存檔失敗 %s err=%d（重試 %d 次）" % [path, e, n])
	elif n > 1:
		print("[s3lib] %s 第 %d 次才存進去" % [path, n])
	return e

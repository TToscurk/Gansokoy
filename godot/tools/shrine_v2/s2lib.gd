extends RefCounted
## shrine_v2 共用函式庫：版面讀取、高度場取樣（與 build_terrain.gd 使用同一個三角剖分，結果＝網格實際高度）。
## 用法：const S2 := preload("res://tools/shrine_v2/s2lib.gd") ； S2.height_at(x, z)

const GEN := "res://maps/shrine_v2/gen/"

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
	var txt := FileAccess.get_file_as_string(GEN + "layout.json")
	layout = JSON.parse_string(txt)
	return layout


static func load_height() -> void:
	if _h.size() > 0:
		return
	var l := load_layout()
	var t: Dictionary = l["terrain"]
	_nx = int(t["nx"])
	_nz = int(t["nz"])
	_x0 = float(t["x0"])
	_z0 = float(t["z0"])
	_step = float(t["step"])
	var f := FileAccess.open(GEN + "height.f32", FileAccess.READ)
	_h = f.get_buffer(f.get_length()).to_float32_array()
	f.close()
	assert(_h.size() == _nx * _nz, "height.f32 大小不符")


static func grid_h(i: int, j: int) -> float:
	return _h[clampi(j, 0, _nz - 1) * _nx + clampi(i, 0, _nx - 1)]


## 重心座標取樣（與 build_terrain 同一個對角線規則：(i+j) 偶 = a-d 對角，奇 = b-c 對角）。
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
		# 對角 a-d：u>=v 在 (a,b,d)，否則 (a,d,c)
		if u >= v:
			return ha + (hb - ha) * u + (hd - hb) * v
		return ha + (hd - hc) * u + (hc - ha) * v
	# 對角 b-c：u+v<=1 在 (a,b,c)，否則 (b,d,c)
	if u + v <= 1.0:
		return ha + (hb - ha) * u + (hc - ha) * v
	return hd + (hc - hd) * (1.0 - u) + (hb - hd) * (1.0 - v)


static func normal_at(x: float, z: float, e := 0.6) -> Vector3:
	var dx := height_at(x + e, z) - height_at(x - e, z)
	var dz := height_at(x, z + e) - height_at(x, z - e)
	return Vector3(-dx / (2.0 * e), 1.0, -dz / (2.0 * e)).normalized()


## 以腳印四角＋中心取最小／最大地面高度（建築接地用）。
static func footprint_range(cx: float, cz: float, hw: float, hd: float, yaw: float) -> Vector2:
	var lo := INF
	var hi := -INF
	var basis := Basis(Vector3.UP, yaw)
	for p in [Vector2(-hw, -hd), Vector2(hw, -hd), Vector2(-hw, hd), Vector2(hw, hd), Vector2(0, 0),
			Vector2(-hw, 0), Vector2(hw, 0), Vector2(0, -hd), Vector2(0, hd)]:
		var w := basis * Vector3(p.x, 0, p.y)
		var y := height_at(cx + w.x, cz + w.z)
		lo = minf(lo, y)
		hi = maxf(hi, y)
	return Vector2(lo, hi)


static func ensure_dir(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))

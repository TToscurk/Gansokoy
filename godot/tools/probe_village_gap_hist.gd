extends SceneTree
## 統計街廓內各淨空半徑的可用格數與分布，決定補樹參數。

const CELL := 2.0
const X0 := 196.0
const X1 := 280.0
const Z0 := -90.0
const Z1 := 130.0
const SKIP_NODES := ["Terrain", "UnifiedGround", "GroundUnderlay", "BasinHills",
	"EastRiverWater", "EastRiverRevetment", "Shrubs", "Ferns", "GrassTall",
	"GrassFlower", "RiverVegetation", "VillageTrees", "VillageTrees2", "Vista"]
const MAIN_ST := Rect2(232.0, -90.0, 10.0, 220.0)
const SIGHT := Rect2(213.0, 94.0, 44.0, 172.0)
const CANAL := Rect2(277.0, -226.0, 20.0, 462.0)

var _occ: Array = []
var _nx := 0
var _nz := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var scn = load("res://maps/slice/slice.tscn").instantiate()
	root.add_child(scn)
	await process_frame
	_nx = int((X1 - X0) / CELL)
	_nz = int((Z1 - Z0) / CELL)
	_occ.resize(_nx * _nz)
	_occ.fill(false)
	for top in scn.get_children():
		if String(top.name) in SKIP_NODES:
			continue
		for mi in _meshes(top):
			var b: AABB = mi.global_transform * mi.mesh.get_aabb()
			if b.size.y < 0.8:
				continue
			for gx in range(maxi(int(floor((b.position.x - X0) / CELL)), 0),
					mini(int(floor((b.position.x + b.size.x - X0) / CELL)) + 1, _nx)):
				for gz in range(maxi(int(floor((b.position.z - Z0) / CELL)), 0),
						mini(int(floor((b.position.z + b.size.z - Z0) / CELL)) + 1, _nz)):
					_occ[gz * _nx + gx] = true

	var hist: Dictionary = {}
	var samples: Dictionary = {}
	for gz in range(1, _nz - 1):
		for gx in range(1, _nx - 1):
			if _occ[gz * _nx + gx]:
				continue
			var x: float = X0 + gx * CELL
			var z: float = Z0 + gz * CELL
			if MAIN_ST.has_point(Vector2(x, z)) or SIGHT.has_point(Vector2(x, z)) \
					or CANAL.has_point(Vector2(x, z)):
				continue
			var c := _clearance(gx, gz, 10)
			hist[c] = int(hist.get(c, 0)) + 1
			if not samples.has(c):
				samples[c] = []
			if samples[c].size() < 6:
				samples[c].append("(%.0f,%.0f)" % [x, z])
	var keys: Array = hist.keys()
	keys.sort()
	for k in keys:
		print("clr=%2d  格數=%4d  例 %s" % [k, hist[k], ", ".join(samples[k])])
	quit()


func _clearance(gx: int, gz: int, cap: int) -> int:
	for r in range(1, cap + 1):
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				var x := gx + dx
				var z := gz + dz
				if x < 0 or z < 0 or x >= _nx or z >= _nz:
					return r - 1
				if _occ[z * _nx + x]:
					return r - 1
	return cap


func _meshes(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out

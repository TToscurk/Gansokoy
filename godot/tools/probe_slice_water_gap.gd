extends SceneTree
## check_map 報 slice 六個水面埋在地下，但實拍水路正常。逐點量清楚。
##
##   Godot --headless --path godot --script tools/probe_slice_water_gap.gd
##
## 量三件事：水面世界高、該處地面最低（合併 Terrain + UnifiedGround）、
## 以及那個格子裡地面高度的分布——如果同一格同時有渠底與岸頂，
## 「最低點」可能落在完全不相干的地方。

const CELL := 4.0

var _gmin := {}
var _gmax := {}


func _init() -> void:
	var ps := load("res://maps/slice/slice.tscn") as PackedScene
	var root := ps.instantiate() as Node3D
	for nm in ["Terrain", "UnifiedGround"]:
		var mi := root.find_child(nm, true, false) as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var vs: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var xf := _world_xf(mi)
		for v in vs:
			var w: Vector3 = xf * v
			var c := Vector2i(int(floor(w.x / CELL)), int(floor(w.z / CELL)))
			if not _gmin.has(c):
				_gmin[c] = w.y
				_gmax[c] = w.y
			else:
				_gmin[c] = minf(_gmin[c], w.y)
				_gmax[c] = maxf(_gmax[c], w.y)
		print("[GAP] 併入 %-14s 頂點 %d" % [nm, vs.size()])
	print("[GAP] 高度場 %d 格" % _gmin.size())

	for nm in ["UpstreamWater", "DownstreamWater", "Reach_Lower", "Reach_Upper",
			"FeederWater", "FeederSplash"]:
		var mi := root.find_child(nm, true, false) as MeshInstance3D
		if mi == null or mi.mesh == null:
			print("[GAP] %s 找不到" % nm)
			continue
		var vs: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var xf := _world_xf(mi)
		# 取水面中央的一個頂點當代表
		var v: Vector3 = xf * vs[vs.size() / 2]
		var c := Vector2i(int(floor(v.x / CELL)), int(floor(v.z / CELL)))
		var lo: Variant = _gmin.get(c)
		var hi: Variant = _gmax.get(c)
		if lo == null:
			print("[GAP] %-16s 水面 y=%.2f @ (%.0f, %.0f) — 該格**沒有地面資料**"
				% [nm, v.y, v.x, v.z])
			continue
		print("[GAP] %-16s 水面 y=%.2f @ (%.0f, %.0f) ｜ 該格地面 %.2f ~ %.2f ｜ 水-地底 %+.2f"
			% [nm, v.y, v.x, v.z, lo, hi, v.y - float(lo)])
	root.free()
	quit(0)


func _world_xf(n: Node) -> Transform3D:
	var t := Transform3D()
	var cur: Node = n
	while cur != null and cur is Node3D:
		t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t

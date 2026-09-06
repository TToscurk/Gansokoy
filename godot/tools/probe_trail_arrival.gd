extends SceneTree
## 傳送點的「到達地面高」：玩家不是落在傳送點上，而是往地圖中心退 4 m
## 的位置（main.gd:_arrival_for_portal）。獸道南北兩端地形有坡，那 4 m
## 內可能抬升好幾公尺 —— 北端實測差 2.1 m，玩家直接埋進土裡。
##
##   Godot --headless --path godot --script tools/probe_trail_arrival.gd

func _init() -> void:
	var ps := load("res://maps/trail/trail.tscn") as PackedScene
	var root := ps.instantiate() as Node3D
	var terrain := root.get_node_or_null("Terrain") as MeshInstance3D
	var arr: Array = terrain.mesh.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var res := int(round(sqrt(float(vs.size()))))
	var half := 340.0
	var step := 2.0 * half / float(res - 1)

	# 與 meta.json 的 portals 同步
	var portals := [
		{"x": 8.64, "z": -313.6, "name": "北·神社"},
		{"x": 9.56, "z": 320.0, "name": "南·人里"},
	]
	for p in portals:
		var px: float = p.x
		var pz: float = p.z
		# main.gd：inward = 從傳送點指向原點，正規化後推 4 m
		var inward := Vector3(0.0, 0.0, 0.0) - Vector3(px, 0.0, pz)
		inward.y = 0.0
		var arrival := Vector3(px, 0.0, pz)
		if inward.length() > 0.01:
			arrival += inward.normalized() * 4.0
		var gy_portal := _y(vs, res, half, step, px, pz)
		var gy_arrival := _y(vs, res, half, step, arrival.x, arrival.z)
		print("[ARR] %-8s 傳送點(%.2f, %.1f) 地面 %.2f ｜ 到達點(%.2f, %.1f) 地面 %.2f ｜ 落差 %+.2f m"
			% [p.name, px, pz, gy_portal, arrival.x, arrival.z, gy_arrival, gy_arrival - gy_portal])
		print("[ARR]     → meta.json 應填 arrival_ground_y = %.2f" % gy_arrival)
	root.free()
	quit(0)


func _y(vs: PackedVector3Array, res: int, half: float, step: float, x: float, z: float) -> float:
	var fi := clampf((x + half) / step, 0.0, float(res - 1))
	var fj := clampf((z + half) / step, 0.0, float(res - 1))
	var i0 := int(floor(fi)); var j0 := int(floor(fj))
	var i1 := mini(i0 + 1, res - 1); var j1 := mini(j0 + 1, res - 1)
	var tx := fi - float(i0); var tz := fj - float(j0)
	return lerpf(lerpf(vs[j0 * res + i0].y, vs[j0 * res + i1].y, tx),
		lerpf(vs[j1 * res + i0].y, vs[j1 * res + i1].y, tx), tz)

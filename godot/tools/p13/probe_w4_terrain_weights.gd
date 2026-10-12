extends SceneTree
## P13 Wave 4：参道の両脇の地形頂点ウェイト（COLOR＝trodden,gravel,mud,rock／UV＝forest,farm／UV2＝wet,street）の実測（唯讀、headless）。
##   土の裾 W4Soil のウェイトを周囲の地形に合わせるため。参道周辺の可視地形は NorthHill（主）と MainTerrain／RiverTerrain の重なり。
const SA := preload("res://tools/village_v2_shrine_approach_lib.gd")


func _init() -> void:
	_run.call_deferred()


func _band(vs: PackedVector3Array, cols: PackedColorArray, uv: PackedVector2Array, uv2: PackedVector2Array, cl: PackedVector2Array, rng_k: Vector2i, lo: float, hi: float, tag: String) -> void:
	var n := 0
	var s := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	for i in vs.size():
		var p := Vector2(vs[i].x, vs[i].z)
		var best := INF
		for k in range(rng_k.x, rng_k.y + 1, 6):
			best = minf(best, cl[k].distance_to(p))
		if best >= lo and best < hi:
			n += 1
			var c := cols[i]
			s[0] += c.r
			s[1] += c.g
			s[2] += c.b
			s[3] += c.a
			s[4] += uv[i].x
			s[5] += uv[i].y
			s[6] += uv2[i].x
			s[7] += uv2[i].y
	if n > 0:
		print("[W4T] %s 中心線から %.1f–%.1f m：頂点 %d・trodden %.2f gravel %.2f mud %.2f rock %.2f｜forest %.2f farm %.2f｜wet %.2f street %.2f" % [tag, lo, hi, n, s[0] / n, s[1] / n, s[2] / n, s[3] / n, s[4] / n, s[5] / n, s[6] / n, s[7] / n])


func _run() -> void:
	var v: Node3D = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	root.add_child(v)
	await process_frame
	var cl := SA.centerline()
	var rng_k := Vector2i(int(37.2 / 0.05), int(64.2 / 0.05))
	for nodename in ["NorthHill", "MainTerrain", "RiverTerrain"]:
		var mt := v.get_node("Terrain/" + nodename) as MeshInstance3D
		var arr := mt.mesh.surface_get_arrays(0)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
		var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		var uv2: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2]
		print("[W4T] %s 頂点 %d" % [nodename, vs.size()])
		for b in [[0.0, 1.5], [1.5, 2.6], [2.6, 4.0], [4.0, 7.0]]:
			_band(vs, cols, uv, uv2, cl, rng_k, float(b[0]), float(b[1]), nodename)
	quit(0)

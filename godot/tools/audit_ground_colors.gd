extends SceneTree
## 量產出物：抽樣 slice_unified_ground.res 的 COLOR.r（草權重），
## 回報村落平台內「草 / 裸土」的實際比例與幾個定點取樣。

const PROBES: Array = [
	["街心 z=0", 235.0, 0.0],
	["街心 z=60", 235.0, 60.0],
	["廣場中心", 223.0, 25.0],
	["西裏路地", 216.6, -20.0],
	["街廓外 40m", 275.0, 0.0],
	["街廓外 80m", 315.0, 0.0],
	["平台西側空地", 120.0, 0.0],
	["平台北側空地", 0.0, -240.0],
]

func _init() -> void:
	var mesh: ArrayMesh = load("res://maps/slice/gen/slice_unified_ground.res")
	if mesh == null:
		push_error("ground mesh load failed")
		quit()
		return
	var arr: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	print("VERTS %d" % verts.size())
	var inside: int = 0
	var grassy: int = 0
	var bare: int = 0
	var best: Array = []
	for p in PROBES:
		best.append([1e9, 0.0])
	for i in range(verts.size()):
		var v: Vector3 = verts[i]
		var g: float = cols[i].r
		if absf(v.x) < 300.0 and absf(v.z) < 300.0:
			inside += 1
			if g > 0.6:
				grassy += 1
			elif g < 0.25:
				bare += 1
		for k in range(PROBES.size()):
			var d: float = Vector2(v.x - PROBES[k][1], v.z - PROBES[k][2]).length()
			if d < best[k][0]:
				best[k] = [d, g]
	print("PLATEAU_VERTS %d  grass>0.6 %d (%.1f%%)  bare<0.25 %d (%.1f%%)" % [
		inside, grassy, 100.0 * float(grassy) / float(maxi(inside, 1)),
		bare, 100.0 * float(bare) / float(maxi(inside, 1))])
	for k in range(PROBES.size()):
		print("PROBE %-14s grass=%.2f (取樣點距離 %.1fm)" % [PROBES[k][0], best[k][1], best[k][0]])
	quit()

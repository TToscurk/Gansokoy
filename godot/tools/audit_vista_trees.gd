extends SceneTree
## 遠景樹 r2 驗收：面數、貼地、走廊留空、境內淨空。
##
##   Godot --headless --path godot --script tools/audit_vista_trees.gd
##
## ⚠ 不載入 shrine.tscn（3 萬節點 headless 要好幾分鐘）——只讀 gen/ 下的資源。
## ⚠ 從磁碟 load 回來的 MultiMesh **讀不出 transform**：get_instance_transform()
##   一律回 identity、`buffer` 是空的，掛進場景樹過一幀也一樣（實測 754 棵
##   全量成原點，是假結果）。所以座標驗收對 `_points.json` —— 那是
##   gen_shrine_vista_trees.gd 寫 .res 時同步存下的同一份最終分布。
##   .res 只用來核對 instance_count 與每棵面數。

const DIR := "res://maps/shrine/gen/vista_trees_r2/"
const POINTS := DIR + "_points.json"
const VISTA_MESH := "res://maps/shrine/gen/vista_exit.res"
const NAMES := ["針葉樹1", "針葉林樹3", "針葉林樹4", "普通樹"]
const KEEP_OUT := 82.0
const GAP_HALF := 13.0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	# ── 1. 每群的實例數與面數（讀 .res）──
	var total := 0
	var total_faces := 0
	for nm in NAMES:
		var mm: MultiMesh = load(DIR + nm + ".res")
		if mm == null:
			print("VT_GROUP %s LOAD_FAIL" % nm)
			continue
		var fpm := mm.mesh.get_faces().size() / 3 if mm.mesh else 0
		total += mm.instance_count
		total_faces += fpm * mm.instance_count
		print("VT_GROUP %-10s %4d 棵 × %4d 面 = %7d 面" % [nm, mm.instance_count, fpm, fpm * mm.instance_count])

	# ── 2. 座標驗收（讀 _points.json）──
	var f := FileAccess.open(POINTS, FileAccess.READ)
	if f == null:
		print("VT_POINTS MISSING %s —— 先跑 gen_shrine_vista_trees.gd" % POINTS)
		quit(1)
		return
	var pts: Array = []
	for e in (JSON.parse_string(f.get_as_text()) as Array):
		pts.append(Vector3(e[0], e[1], e[2]))
	if pts.size() != total:
		print("VT_MISMATCH _points.json %d 筆 ≠ .res 合計 %d 棵" % [pts.size(), total])

	var vmesh: ArrayMesh = load(VISTA_MESH)
	var tri: PackedVector3Array = vmesh.get_faces()
	var b: AABB = vmesh.get_aabb()
	var cell := 24.0
	var buckets: Dictionary = {}
	var ti := 0
	while ti < tri.size():
		var xmin := 1e9; var xmax := -1e9; var zmin := 1e9; var zmax := -1e9
		for k in 3:
			var q: Vector3 = tri[ti + k]
			xmin = minf(xmin, q.x); xmax = maxf(xmax, q.x)
			zmin = minf(zmin, q.z); zmax = maxf(zmax, q.z)
		for gx in range(int(floor((xmin - b.position.x) / cell)), int(floor((xmax - b.position.x) / cell)) + 1):
			for gz in range(int(floor((zmin - b.position.z) / cell)), int(floor((zmax - b.position.z) / cell)) + 1):
				var key := Vector2i(gx, gz)
				if not buckets.has(key):
					buckets[key] = PackedInt32Array()
				buckets[key].append(ti)
		ti += 3

	var floaty := 0
	var worst := 0.0
	var worst_at := Vector3.ZERO
	var near_court := 0
	var in_gap := 0
	var dmin := 1e9
	for p in pts:
		var pp: Vector3 = p
		var d := Vector2(pp.x, pp.z).length()
		dmin = minf(dmin, d)
		if d < KEEP_OUT:
			near_court += 1
		if pp.z > 55.0 and absf(pp.x) < GAP_HALF:
			in_gap += 1
		var gx := int(floor((pp.x - b.position.x) / cell))
		var gz := int(floor((pp.z - b.position.z) / cell))
		# ⚠ 必須用**重心內插**，不能取最近頂點：遠景網格 18 m 一格，
		#   斜坡上最近頂點跟真實地表差好幾公尺，會報出一堆假的「浮空」。
		#   （這裡跟 gen_shrine_vista_trees.gd 的取樣法必須一致。）
		var best := 1e9
		var gy := NAN
		for dx in [0, -1, 1]:
			for dz in [0, -1, 1]:
				var key := Vector2i(gx + dx, gz + dz)
				if not buckets.has(key):
					continue
				for idx in buckets[key]:
					var y := _bary_y(tri[idx], tri[idx + 1], tri[idx + 2], pp.x, pp.z)
					if not is_nan(y):
						gy = y
						best = -1.0
						break
					for k in 3:
						var v: Vector3 = tri[idx + k]
						var dd: float = (v.x - pp.x) * (v.x - pp.x) + (v.z - pp.z) * (v.z - pp.z)
						if dd < best:
							best = dd
							gy = v.y
				if best < 0.0:
					break
			if best < 0.0:
				break
		if is_nan(gy):
			continue
		var drift: float = pp.y - gy
		if drift > 1.0:
			floaty += 1
			if floaty <= 12:
				print("VT_FLOAT x=%7.1f y=%7.2f z=%7.1f gy=%7.2f drift=%+6.2f" % [pp.x, pp.y, pp.z, gy, drift])
		if absf(drift) > absf(worst):
			worst = drift
			worst_at = pp
	print("VT_TOTAL %d 棵  %d 面  最近 %.1f m  境內(<%dm) %d  走廊(z>55,|x|<%d) %d"
		% [total, total_faces, dmin, KEEP_OUT, near_court, GAP_HALF, in_gap])
	print("VT_GROUND 浮空>1m = %d 棵  最大偏差 %+.2f m @ (%.1f, %.1f, %.1f)"
		% [floaty, worst, worst_at.x, worst_at.y, worst_at.z])
	quit(0)


func _bary_y(a: Vector3, b3: Vector3, c: Vector3, x: float, z: float) -> float:
	var d := (b3.z - c.z) * (a.x - c.x) + (c.x - b3.x) * (a.z - c.z)
	if absf(d) < 1e-9:
		return NAN
	var w0: float = ((b3.z - c.z) * (x - c.x) + (c.x - b3.x) * (z - c.z)) / d
	var w1: float = ((c.z - a.z) * (x - c.x) + (a.x - c.x) * (z - c.z)) / d
	var w2: float = 1.0 - w0 - w1
	if w0 < -1e-4 or w1 < -1e-4 or w2 < -1e-4:
		return NAN
	return a.y * w0 + b3.y * w1 + c.y * w2

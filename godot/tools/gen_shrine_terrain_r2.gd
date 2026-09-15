extends SceneTree
## 博麗神社 地形收邊 r2（後處理，不重跑 gen_shrine_blockout）
##
##   Godot --headless --path godot --script tools/gen_shrine_terrain_r2.gd [-- --dry]
##
## 輸入：maps/shrine/gen/terrain_exit.res、vista_exit.res（gen_shrine_exit 的產物，
##       shrine.tscn 現在掛的就是這兩個）
## 輸出：maps/shrine/gen/terrain_r2.res、vista_r2.res —— 掛接由 MCP 做，不動 .tscn。
##
## 修四件事（audit_shrine_terrain.gd 實測 2026-09-15）：
##   1. 石階腳被抬高：gen 第 6 段「境內外圍緩降」把 COURT_Y 3.2 混進石階南端
##      14 m 內，x=0 z=0 地形 0.73 但最低階頂面 0.00 → 兩階＋收頭石埋土 0.86 m。
##      → 石階腳 z∈[−0.5, 7] 中軸帶壓回「最低階頂 0.00 → 參道」的斜面。
##   2. 圖內陡坡 9.6% 格 >35°、最陡 75°（北谷壁 z −60~−50、西北走廊邊、南出口
##      兩肩）。→ 坡度限制鬆弛：相鄰頂點高差 > tan(35°)×格距 就對半拉近，
##      受保護區（境內／石階／參道／出口走廊）權重 0 不動，迭代到收斂。
##   3. 地形↔Vista 接縫：Vista 第一圈（|x|=90）比地形邊緣低 5–14 m（西側盆地
##      高斯拉的），玩家隔著牆看出去是一道 13 m 斷崖。→ 90 圈頂點改成
##      「地形邊緣高 → 108 圈」的 1/3 內插；72 圈（圖內重疊帶）壓到地形 −0.3。
##   4. Vista 與地形重疊帶（72–75 m）有 2342 處 Vista 高於地形 → 會從地面穿出。
##      第 3 點的 72 圈下壓一併解決。
##
## ⚠ 頂點順序：SurfaceTool.generate_normals() 之後不是 row-major，一律依座標
##   重排成格子再算（audit 第一版沒重排，印出 90° 的假斷崖）。

const IN_T := "res://maps/shrine/gen/terrain_exit.res"
const IN_V := "res://maps/shrine/gen/vista_exit.res"
const OUT_T := "res://maps/shrine/gen/terrain_r2.res"
const OUT_V := "res://maps/shrine/gen/vista_r2.res"
const HALF := 75.0
const VEXT := 900.0
const VRES := 101
const SLOPE_DEG := 35.0
const MAX_PASSES := 3000
const VISTA_TINT := Color(0.74, 0.79, 0.62)

# 與 gen_shrine_blockout / gen_shrine_exit 同一組常數
const COURT_W := 27.0
const Z_COURT_N := -31.5
const Z_COURT_S := -9.5
const STEP_W := 3.2
const STAIR_S := -0.1          # 主石階最低階南緣（_stair_plan[0].z1）
const APPROACH_HW := 1.5 + 7.0
const Z_ENTRY := 53.0
const EXIT_CUT_HALF := 4.4
const EXIT_Z0 := 52.0
const DAIS_W := 34.0
const DAIS_Z_N := -34.0
const DAIS_Z_S := -11.0

var _g: PackedFloat32Array      # 地形高度格 res×res（row-major, j=z）
var _res := 0
var _step := 0.0
var _w: PackedFloat32Array      # 可動權重 0..1
var _tsrc: ArrayMesh
var _vsrc: ArrayMesh


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var dry := "--dry" in OS.get_cmdline_user_args()
	_tsrc = load(IN_T)
	_vsrc = load(IN_V)
	_load_terrain()
	_build_weights()
	var before := _slope_stats()
	_fix_stair_foot()
	var after_foot := _slope_stats()
	var passes := _relax()
	var after := _slope_stats()
	_report_remaining()
	print("[R2] 坡度 >%.0f°：原 %d 格（%.1f%%，最陡 %.1f°） → 石階腳修正後 %d → 鬆弛 %d 回後 %d 格（%.1f%%，最陡 %.1f°）"
		% [SLOPE_DEG, before[0], 100.0 * before[0] / before[1], before[2],
			after_foot[0], passes, after[0], 100.0 * after[0] / after[1], after[2]])
	var moved := _height_delta_stats()
	print("[R2] 地形頂點位移：%d 個 > 5 cm，最大 %+.2f m @ (%.1f, %.1f)，最大下切 %+.2f m @ (%.1f, %.1f)"
		% [moved[0], moved[1], moved[2].x, moved[2].y, moved[3], moved[4].x, moved[4].y])
	var prof := ""
	var zz := -2.0
	while zz <= 7.0:
		prof += "%+.1f:%.2f " % [zz, h_at(0.0, zz)]
		zz += 0.5
	print("[R2] 中軸剖面 x=0（最低階頂 0.00）: " + prof)

	var vmesh := _fix_vista()
	if dry:
		print("[R2] DRY RUN — 未寫檔")
		quit(0)
		return
	var tm := _rebuild_terrain()
	var err := ResourceSaver.save(tm, OUT_T)
	print("[R2] saved %s err=%d" % [OUT_T, err])
	err = ResourceSaver.save(vmesh, OUT_V)
	print("[R2] saved %s err=%d" % [OUT_V, err])
	quit(0)


# ── 地形格 ──
func _load_terrain() -> void:
	var v: PackedVector3Array = _tsrc.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	_res = int(round(sqrt(float(v.size()))))
	assert(_res * _res == v.size())
	_step = 2.0 * HALF / float(_res - 1)
	_g.resize(v.size())
	for p in v:
		_g[_idx(p.x, p.z)] = p.y
	print("[R2] terrain %d×%d step %.3f" % [_res, _res, _step])


func _idx(x: float, z: float) -> int:
	return int(round((z + HALF) / _step)) * _res + int(round((x + HALF) / _step))


func _xz(i: int) -> Vector2:
	return Vector2(-HALF + (i % _res) * _step, -HALF + (i / _res) * _step)


func h_at(x: float, z: float) -> float:
	var fx := (x + HALF) / _step
	var fz := (z + HALF) / _step
	var i := clampi(int(floor(fx)), 0, _res - 2)
	var j := clampi(int(floor(fz)), 0, _res - 2)
	var tx := clampf(fx - i, 0.0, 1.0)
	var tz := clampf(fz - j, 0.0, 1.0)
	var a := _g[j * _res + i]
	var b := _g[j * _res + i + 1]
	var c := _g[(j + 1) * _res + i]
	var d := _g[(j + 1) * _res + i + 1]
	if tx + tz <= 1.0:
		return a + (b - a) * tx + (c - a) * tz
	return d + (c - d) * (1.0 - tx) + (b - d) * (1.0 - tz)


## 受保護區權重：0 = 不動。邊緣 3 m 漸變，避免保護區邊線變成新的台階。
func _build_weights() -> void:
	_w.resize(_g.size())
	for i in _g.size():
		var p := _xz(i)
		var x := p.x
		var z := p.y
		var d := INF   # 到最近保護區的距離（負 = 在裡面）
		# 境內＋白石庭院（含 4 m pad，與 gen 的 court_pad 同）
		d = minf(d, _box_dist(x, z, -(COURT_W * 0.5 + 4.0), COURT_W * 0.5 + 4.0, Z_COURT_N - 10.0, Z_COURT_S))
		d = minf(d, _box_dist(x, z, -DAIS_W * 0.5 - 1.0, DAIS_W * 0.5 + 1.0, DAIS_Z_N - 1.0, DAIS_Z_S + 1.0))
		# 主石階帶（含兩側 3 m 貼合斜面）
		d = minf(d, _box_dist(x, z, -(STEP_W * 0.5 + 3.0), STEP_W * 0.5 + 3.0, Z_COURT_S - 0.5, 7.0))
		# 參道走廊
		d = minf(d, _box_dist(x, z, -APPROACH_HW, APPROACH_HW, STAIR_S, Z_ENTRY + 4.0))
		# 南出口走廊（gen_shrine_exit CUT_HALF + 路肩）
		d = minf(d, _box_dist(x, z, -(EXIT_CUT_HALF + 1.5), EXIT_CUT_HALF + 1.5, EXIT_Z0 - 2.0, HALF + 1.0))
		_w[i] = clampf(d / 3.0, 0.0, 1.0)


func _box_dist(x: float, z: float, x0: float, x1: float, z0: float, z1: float) -> float:
	var dx := maxf(maxf(x0 - x, x - x1), 0.0)
	var dz := maxf(maxf(z0 - z, z - z1), 0.0)
	var outside := sqrt(dx * dx + dz * dz)
	if outside > 0.0:
		return outside
	return -minf(minf(x - x0, x1 - x), minf(z - z0, z1 - z))


# ── 1. 石階腳 ──
## z∈[STAIR_S, STAIR_S+7]、|x|<STEP_W/2+3 的帶內：目標高 = 最低階頂 0.00 往南
## 平滑接到 z=+7 現況；橫向 3 m 外漸回原地形。石階本體的 BoxShape 碰撞會蓋住
## 帶內，地形只需要「不高過踏面」。
func _fix_stair_foot() -> void:
	var z_end := STAIR_S + 7.0
	var h_end := h_at(0.0, z_end)
	var n := 0
	for i in _g.size():
		var p := _xz(i)
		if p.y < STAIR_S - 1.0 or p.y > z_end or absf(p.x) > STEP_W * 0.5 + 3.0:
			continue
		var t := clampf((p.y - STAIR_S) / (z_end - STAIR_S), 0.0, 1.0)
		var axis_h := lerpf(0.0, h_end, smoothstep(0.0, 1.0, t))
		# 石階最下段 1 m 北側（踏面下方）也壓到 ≤ 0
		if p.y < STAIR_S:
			axis_h = 0.0
		var lat := smoothstep(STEP_W * 0.5, STEP_W * 0.5 + 3.0, absf(p.x))
		var target := lerpf(axis_h, _g[i], lat)
		# 只往下壓，不抬（抬會把路面頂到踏面之上）
		if target < _g[i] - 0.005:
			_g[i] = target
			n += 1
	print("[R2] 石階腳：壓低 %d 個頂點（z %+.1f ~ %+.1f，目標 0.00 → %.2f）" % [n, STAIR_S, z_end, h_end])


# ── 2. 坡度限制 ──
## 經典 slope-limit：任一邊兩端高差 > lim 就把**可動的高端往下削**到 low+lim；
## 高端受保護（境內平台邊）才把可動的低端抬到 high−lim。Gauss-Seidel 逐點更新，
## 單調收斂，不會像「兩端各拉一半」那樣在一個頂點上累加四條邊的位移而過衝
## （第一版鬆弛實測把陡格從 2468 拉到 3688）。
## 對角邊也算（三角面法線含對角），上限 ×√2。用 33° 留 2° 餘裕。
## 逐**三角形**限制：直角三角形 (a,b,c) 的坡度 = |(Δx, Δz)|/step；兩條直角邊
## 各自 ≤ lim 不夠（兩邊都到頂 → 42.6°），要限制向量長度。超限時削較大的那條
## 分量到 sqrt(L² − 另一條²)。可動端依權重分攤。Gauss-Seidel，單調收斂。
func _relax() -> int:
	var L := tan(deg_to_rad(SLOPE_DEG - 1.5)) * _step
	var passes := 0
	while passes < MAX_PASSES:
		passes += 1
		var fixed := 0
		for j in _res - 1:
			for i in _res - 1:
				var a := j * _res + i
				var b := a + 1
				var c := a + _res
				var d := c + 1
				# 兩個三角形：直角在 a（邊 a-b, a-c）與直角在 d（邊 d-c, d-b）
				for tri in [[a, b, c], [d, c, b]]:
					var o: int = tri[0]
					var e1: int = tri[1]
					var e2: int = tri[2]
					var g1 := _g[e1] - _g[o]
					var g2 := _g[e2] - _g[o]
					if g1 * g1 + g2 * g2 <= L * L + 1e-6:
						continue
					fixed += 1
					# 削較大的分量
					var big := e1 if absf(g1) >= absf(g2) else e2
					var gb := g1 if big == e1 else g2
					var other := g2 if big == e1 else g1
					var want := sqrt(maxf(L * L - other * other, 0.0))
					var excess := absf(gb) - want
					if excess <= 0.0:
						continue
					var hi := big if gb > 0.0 else o
					var lo := o if gb > 0.0 else big
					var whi := _w[hi]
					var wlo := _w[lo]
					if whi + wlo <= 0.0:
						continue
					var share_hi := whi / (whi + wlo)
					_g[hi] -= excess * share_hi
					_g[lo] += excess * (1.0 - share_hi)
		if fixed == 0:
			break
	return passes


func _report_remaining() -> void:
	var buckets := {}
	var both_protected := 0
	var total := 0
	for j in _res - 1:
		for i in _res - 1:
			var a := j * _res + i
			var b := a + 1
			var c := a + _res
			var pa := Vector3(0, _g[a], 0)
			var pb := Vector3(_step, _g[b], 0)
			var pc := Vector3(0, _g[c], _step)
			var nrm := (pb - pa).cross(pc - pa).normalized()
			var deg := rad_to_deg(acos(clampf(absf(nrm.y), 0.0, 1.0)))
			if deg <= SLOPE_DEG:
				continue
			total += 1
			if _w[a] == 0.0 and _w[b] == 0.0 and _w[c] == 0.0:
				both_protected += 1
			var p := _xz(a)
			var key := "(%d,%d)" % [int(floor(p.x / 10.0)) * 10, int(floor(p.y / 10.0)) * 10]
			buckets[key] = buckets.get(key, 0) + 1
	var keys := buckets.keys()
	keys.sort_custom(func(p, q): return buckets[p] > buckets[q])
	var s := ""
	for k in keys.slice(0, 10):
		s += "%s×%d " % [k, buckets[k]]
	print("[R2] 殘留陡格 %d，其中三頂點全受保護 %d；10 m 格分布：%s" % [total, both_protected, s])


func _slope_stats() -> Array:
	var bad := 0
	var n := 0
	var worst := 0.0
	for j in _res - 1:
		for i in _res - 1:
			var a := Vector3(0, _g[j * _res + i], 0)
			var b := Vector3(_step, _g[j * _res + i + 1], 0)
			var c := Vector3(0, _g[(j + 1) * _res + i], _step)
			var nrm := (b - a).cross(c - a).normalized()
			var deg := rad_to_deg(acos(clampf(absf(nrm.y), 0.0, 1.0)))
			n += 1
			worst = maxf(worst, deg)
			if deg > SLOPE_DEG:
				bad += 1
	return [bad, n, worst]


func _height_delta_stats() -> Array:
	var v: PackedVector3Array = _tsrc.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var n := 0
	var up := 0.0
	var up_at := Vector2.ZERO
	var dn := 0.0
	var dn_at := Vector2.ZERO
	for p in v:
		var d := _g[_idx(p.x, p.z)] - p.y
		if absf(d) > 0.05:
			n += 1
		if d > up:
			up = d
			up_at = Vector2(p.x, p.z)
		if d < dn:
			dn = d
			dn_at = Vector2(p.x, p.z)
	return [n, up, up_at, dn, dn_at]


func _rebuild_terrain() -> ArrayMesh:
	var a: Array = _tsrc.surface_get_arrays(0)
	var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		var p := verts[i]
		verts[i] = Vector3(p.x, _g[_idx(p.x, p.z)], p.z)
	return _commit(a, verts, _tsrc.surface_get_material(0))


func _commit(a: Array, verts: PackedVector3Array, mat: Material) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var uvs: PackedVector2Array = a[Mesh.ARRAY_TEX_UV] if a[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
	var cols: PackedColorArray = a[Mesh.ARRAY_COLOR] if a[Mesh.ARRAY_COLOR] != null else PackedColorArray()
	for i in verts.size():
		if uvs.size() > i:
			st.set_uv(uvs[i])
		if cols.size() > i:
			st.set_color(cols[i])
		st.add_vertex(verts[i])
	for k in (a[Mesh.ARRAY_INDEX] as PackedInt32Array):
		st.add_index(k)
	st.generate_normals()
	var m := st.commit()
	if mat != null:
		m.surface_set_material(0, mat)
	return m


# ── 3./4. Vista 接縫：裙帶重建 ──
## 舊做法（72 圈壓到地形下／搬到 75 線）都留缝：Vista 18 m 一格，地形 0.94 m
## 一格，兩者之間永遠有噪聲落差。正解：
##   1. 刪掉所有落在圖內（任一頂點 max(|x|,|z|) < 90−ε）的 Vista 三角形；
##   2. 90 圈頂點高度 = lerp(地形邊緣, 108 圈, 0.33)，限 ±6 m（南出口缺口不動）；
##   3. 用**地形邊緣的 161 個頂點**當內圈，跟 90 圈頂點織成一條裙帶。
##      接縫零落差（同一組座標與高度），15 m 內坡度由第 2 步控制。
func _fix_vista() -> ArrayMesh:
	var a: Array = _vsrc.surface_get_arrays(0)
	var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var vstep := 2.0 * VEXT / float(VRES - 1)        # 18 m
	var grid := {}
	for i in verts.size():
		var p := verts[i]
		grid[Vector2i(int(round((p.x + VEXT) / vstep)), int(round((p.z + VEXT) / vstep)))] = i
	var i90 := int(round((-90.0 + VEXT) / vstep))
	var j90 := int(round((90.0 + VEXT) / vstep))
	var i108 := i90 - 1
	var j108 := j90 + 1
	# ── 2. 90 圈高度 ──
	var ring90 := 0
	var worst_before := 0.0
	var worst_after := 0.0
	for key in grid.keys():
		var gi: int = key.x
		var gj: int = key.y
		var on90 := (gi == i90 or gi == j90) and gj >= i90 and gj <= j90 \
			or (gj == i90 or gj == j90) and gi >= i90 and gi <= j90
		if not on90:
			continue
		var vi: int = grid[key]
		var p := verts[vi]
		if p.z > 48.0 and absf(p.x) < 40.0:
			continue          # 南出口缺口：gen_shrine_exit 的剖面
		var edge := h_at(clampf(p.x, -HALF, HALF), clampf(p.z, -HALF, HALF))
		var gi2 := gi
		var gj2 := gj
		if gi == i90: gi2 = i108
		if gi == j90: gi2 = j108
		if gj == i90: gj2 = i108
		if gj == j90: gj2 = j108
		var far_y := p.y
		if grid.has(Vector2i(gi2, gj2)):
			far_y = verts[grid[Vector2i(gi2, gj2)]].y
		worst_before = maxf(worst_before, absf(p.y - edge))
		var ny := clampf(lerpf(edge, far_y, 0.33), edge - 6.0, edge + 6.0)
		verts[vi] = Vector3(p.x, ny, p.z)
		worst_after = maxf(worst_after, absf(ny - edge))
		ring90 += 1
	# ── 1. 保留外圈三角形 ──
	var out_v := PackedVector3Array()
	var out_i := PackedInt32Array()
	var remap := {}
	var dropped := 0
	var k := 0
	while k < idx.size():
		var keep := true
		for q in 3:
			var p := verts[idx[k + q]]
			if maxf(absf(p.x), absf(p.z)) < 90.0 - 0.5:
				keep = false
		if keep:
			for q in 3:
				var vi := idx[k + q]
				if not remap.has(vi):
					remap[vi] = out_v.size()
					out_v.append(verts[vi])
				out_i.append(remap[vi])
		else:
			dropped += 1
		k += 3
	# ── 3. 裙帶 ──
	# 四邊各自：內圈 = 地形邊緣頂點（含兩端角），外圈 = 90 圈頂點（含兩端角）。
	# 依沿邊參數 t 兩指標合併，逐段出三角形；角點兩邊共用同一個 90 角頂點。
	var sides := [
		# [固定軸, 固定值(內), 固定值(外), 沿邊軸]
		["z", -HALF, -90.0, "x"],
		["z", HALF, 90.0, "x"],
		["x", -HALF, -90.0, "z"],
		["x", HALF, 90.0, "z"],
	]
	var strip_tris := 0
	for sd in sides:
		var fixed: String = sd[0]
		var inner_c: float = sd[1]
		var outer_c: float = sd[2]
		# 內圈：地形格邊緣
		var inner := PackedVector3Array()
		for n in _res:
			var t := -HALF + n * _step
			var px := t if fixed == "z" else inner_c
			var pz := inner_c if fixed == "z" else t
			inner.append(Vector3(px, _g[_idx(px, pz)], pz))
		# 外圈：90 圈那一排，t 從 −90 到 +90
		var outer := PackedVector3Array()
		for n in range(i90, j90 + 1):
			var key := Vector2i(n, i90 if outer_c < 0.0 else j90) if fixed == "z" \
				else Vector2i(i90 if outer_c < 0.0 else j90, n)
			if not grid.has(key):
				push_error("90 圈缺頂點 %s" % key)
				continue
			outer.append(verts[grid[key]])
		# 合併
		var ia := 0
		var oa := 0
		var base := out_v.size()
		for v in inner:
			out_v.append(v)
		var obase := out_v.size()
		for v in outer:
			out_v.append(v)
		var axis_of := func(v: Vector3) -> float: return v.x if fixed == "z" else v.z
		while ia < inner.size() - 1 or oa < outer.size() - 1:
			var adv_inner := false
			if oa >= outer.size() - 1:
				adv_inner = true
			elif ia >= inner.size() - 1:
				adv_inner = false
			else:
				# 誰的下一個點參數小就先走誰（外圈 −90..90 對映到 −75..75 比例）
				var ti: float = axis_of.call(inner[ia + 1])
				var to: float = axis_of.call(outer[oa + 1]) * (HALF / 90.0)
				adv_inner = ti <= to
			var tri: Array
			if adv_inner:
				tri = [base + ia, base + ia + 1, obase + oa]
				ia += 1
			else:
				tri = [base + ia, obase + oa + 1, obase + oa]
				oa += 1
			# 統一朝上（與地形格同：(b−a)×(c−a).y < 0）
			var pa := out_v[tri[0]]
			var pb := out_v[tri[1]]
			var pc := out_v[tri[2]]
			if (pb - pa).cross(pc - pa).y > 0.0:
				var tmp: int = tri[1]
				tri[1] = tri[2]
				tri[2] = tmp
			out_i.append(tri[0]); out_i.append(tri[1]); out_i.append(tri[2])
			strip_tris += 1
	print("[R2] Vista：刪圖內三角 %d、90 圈調高 %d 點（邊緣落差最大 %.2f → %.2f m）、裙帶 %d 三角（內圈 %d×4 頂點與地形邊完全重合）"
		% [dropped, ring90, worst_before, worst_after, strip_tris, _res])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in out_v:
		st.set_uv(Vector2(v.x, v.z))
		st.add_vertex(v)
	for ii in out_i:
		st.add_index(ii)
	st.generate_normals()
	var m := st.commit()
	# 色差收邊：實拍（ab_east_seam_noveg）地形邊緣 ≈ (255,240,170)，Vista ≈ (195,187,105)，
	# 整條 75 m 線是一道明暗分界。Vista 的 albedo 提到接近地形（地形已裁到 255，
	# 只能逼近）。原 (0.56,0.62,0.42)。
	var vmat := _vsrc.surface_get_material(0)
	if vmat is StandardMaterial3D:
		vmat = (vmat as StandardMaterial3D).duplicate()
		(vmat as StandardMaterial3D).albedo_color = VISTA_TINT
	m.surface_set_material(0, vmat)
	return m

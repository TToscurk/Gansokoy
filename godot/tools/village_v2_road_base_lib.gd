extends RefCounted
## P10 R5a ROUND 2 — Road Base Regeneration Pilot（使用者 2026-10-09 ROUND 2 §3；D3 CONDITIONAL：最小作用域・可重現・快照＋依存確認）。
## overlay `RoadBaseP10`（gen/road_base_p10.scn，root、PropFixP10 之後）：対象 3 本の道の MeshInstance3D の mesh を runtime で差し替える
## （元の road_*.res は不変・雜湊を gate が記録；enabled=false で元の mesh に戻す）。材質は GroundPilotP10 のまま（UV／UV2 の規約を守る）。
## 根因（R5a ROUND 1 審圖「道路仍然很寬、邊緣相對規整、沒有滲透感」／MASTER AUDIT R5a）：
##   gen_village_v2.gd `_ribbon`＝折線を 2 m ごとに取り、左右 2 点だけの平らな帯を「道の高さ＋0.10 m」に置く
##   → ①地形から 10 cm 浮く（路肩が段になる、足が路面に 10 cm 埋まる）②幅一定・定規の直線 ③横断が平ら（地形の横勾配を無視）。
## Pilot（使用者参考写真：林と田の間の農道＝曲がった不揃いの縁・草の侵入・露出した土・轍・中央の草）：
##   · 1 m ごと・横 7 点（u＝±1, ±0.66, ±0.33, 0）、各点＝P1 地形（TerrainCollision）＋持ち上げ：芯 3–6 cm、縁 −1.5 cm（縁は地形に潜る）
##   · 半幅＝元の半幅 × 0.78–0.95（よく使う区間ほど広い）× ゆらぎ、中心線の蛇行（元の路幅の中だけ：|蛇行|＋半幅 ≤ 元の半幅）
##   · 端・交差点の 6 m は蛇行と幅ゆらぎを 0 へ（他の道とのつながりは元どおり）
##   · 区間ごとの使われ方 traffic（0 田の奥 … 1 村の出入口）を UV2.y＝1＋traffic に入れる → pilot shader が轍・中央草・路肩草・砂利を変える
##   · 元の網格が切れている所（水の上＝橋が受け持つ）は切ったまま；南橫街は橋より東だけ再生（西＝町の区間は元の三角形を逐字コピー、境目 8 m で滑らかに）
## 変えない：P1 地形・碰撞（道に碰撞なし）・P3 道路の折線／幅の記録・P8 田・P9 地被・NPC（地形の上を歩く）。
## ROUND 3（使用者 §3：舊路寬の直線の土色帯の根因を切り分けてから直す）：
##   切り分け（tools/diag_village_v2_road_band.gd、同機位 A–E）で帯＝P7 地形（FarmlandTerrain）の頂点重み trodden（COLOR.r）と確定：
##   gen_village_v2.gd `_road_halo`＝道の芯から hw−0.3〜hw＋1.6 m（ROAD_HALO）を 2 m 格子で踩み固め土に塗る（農道なら芯 ±2.8 m）。
##   → 同じ式で「対象 3 本の旧い帯」と「ほかの道・巷道の帯」を再計算し、対象の帯が支配している頂点だけ、再生した道の芯・幅・使われ方で
##     塗り直す（地形の格子 2 m の補間で帯が広がらないよう、塗りは路面の内側〔半幅 −0.6、halo 0–0.3〕だけ；道の土色は再生道 mesh が担う）。ほかの道・水辺・建物の塗りは不変、頂点位置・法線・UV は不変（COLOR.r だけ）。
##   runtime で FarmlandTerrain の mesh を差し替え（terrain_farmlandterrain.res は不変・enabled=false で元へ）＝P7 limited correction の Pilot。

const NODE_NAME := "RoadBaseP10"
const OUTPUT := "res://maps/village_v2/gen/road_base_p10.scn"
const SCRIPT := "res://maps/village_v2/scripts_p10/road_base.gd"
const ART_REVISION := "P10 R5a ROUND 3 road base pilot r3：P7 地形の踩み固め重み（舊路寬の直線の帯の根因）を再生道に合わせて局部修正（FarmlandTerrain、COLOR.r だけ）；r2：農道の幅 0.66–0.82×・蛇行 0.34（元の路幅の中）、南橫街は橋のすぐ東（x 330）から 0.52–0.70× へ絞る・蛇行 0.6；r1：農道 2 本＋南橫街の田の区間を地形なり・不揃いの幅・蛇行・区間別の使われ方で再生（ART_REVIEW）"
const LAYOUT := "res://maps/village_v2/layout_v2.json"
const STEP := 1.0
const US := [-1.0, -0.66, -0.33, 0.0, 0.33, 0.66, 1.0]
const EDGE_LIFT := -0.015
const MID_LIFT_U := 0.85          # |u| ≤ 0.66 は芯の持ち上げ、0.85 で 0、1.0 で EDGE_LIFT
const TAPER := 6.0                # 端・交差点からこの距離で蛇行／幅ゆらぎを 0 へ
const SEAM_BLEND := 8.0
## P7 地形の踩み固め重み（gen_village_v2.gd `_ground_weights`／`_road_halo` と同じ式）
const TERRAIN_NODE := "Terrain/FarmlandTerrain"
const PARCEL_LIB := "res://tools/village_v2_parcel_lib.gd"
const OLD_HALO := 1.6            # gen ROAD_HALO
const NEW_HALO := [0.0, 0.3]     # 再生道：田の奥 → 村側
## P7 地形の格子は 2 m：格子点の重みが線形補間で ±2 m に広がる → 再生道の塗りは路面の内側（半幅 −0.6 m）だけに置き、
##   道の土色は再生道 mesh 自身（pilot shader の轍・路肩草）に任せる。塗りの幅×使われ方（traffic、田の奥＝0）。
##   r3a：半幅 −0.6 だけでは格子線上に乗る直線区間（FarmPath_1 は x＝372 の格子列そのもの）で芯の列 0.85 が ±2 m に補間されて残った。
const NEW_PAINT_INSET := 0.6
const TR_K := 0.85               # tr = max(wb·0.72, halo·0.85)
const GRID := 2.0                # layout frame grid_step
const GRID_X0 := 0.0
const GRID_Z0 := -340.0
const MATCH_TOL := 0.04          # 「対象の帯が支配」判定：tr0 ≈ 0.85·max(対象, ほか) の許容
## 対象（小範囲）：traffic＝[[s m, 0..1], …]（間は線形）；junctions＝他の道と交わる点（蛇行を 0 へ）
const ROADS := {
	"Roads/FarmPaths/FarmPath_1": {"name": "FarmPath_1", "lift": 0.045, "hw_k": [0.66, 0.82], "meander": 0.34, "seed": 7011,
		"traffic": [[0.0, 0.7], [30.0, 0.6], [70.0, 0.95], [100.0, 0.5], [160.0, 0.2]],
		"junctions": [[372, 0], [372, 40], [372, 70]]},
	"Roads/FarmPaths/FarmPath_4": {"name": "FarmPath_4", "lift": 0.030, "hw_k": [0.66, 0.82], "meander": 0.34, "seed": 7041,
		"traffic": [[0.0, 0.85], [32.0, 0.65], [100.0, 0.3], [216.0, 0.12]],
		"junctions": [[372, 0], [440, 0], [500, 0]]},
	"Roads/SecondaryRoads/CrossStreetSouth": {"name": "CrossStreetSouth", "lift": 0.060, "hw_k": [0.52, 0.70], "meander": 0.60, "seed": 7051,
		"seam_x": 330.0, "traffic": [[158.0, 1.0], [205.0, 0.8]],
		"junctions": [[372, 40]]},
}


static func layout_road(name: String) -> Dictionary:
	var L: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	for r in L["roads"]:
		if String(r["name"]) == name:
			return r
	return {}


static func _noise(s: float, seed: int) -> float:
	# 決定的な 1 次元の滑らかなゆらぎ（−1..1）：3 つの正弦の和、seed で位相
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var v := 0.0
	var amp := [0.6, 0.3, 0.1]
	var lam := [37.0, 17.0, 7.3]
	for i in 3:
		v += float(amp[i]) * sin(TAU * s / float(lam[i]) + r.randf_range(0.0, TAU))
	return v


static func _traffic(cfg: Dictionary, s: float) -> float:
	var tr: Array = cfg["traffic"]
	if s <= float(tr[0][0]):
		return float(tr[0][1])
	for i in tr.size() - 1:
		var a: Array = tr[i]
		var b: Array = tr[i + 1]
		if s <= float(b[0]):
			return lerpf(float(a[1]), float(b[1]), (s - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.001))
	return float(tr[tr.size() - 1][1])


## 折線の 1 m ごとの点：[{s, p, t}]
static func samples(pts: Array) -> Array:
	var out := []
	var s0 := 0.0
	for i in pts.size() - 1:
		var a := Vector2(float(pts[i][0]), float(pts[i][1]))
		var b := Vector2(float(pts[i + 1][0]), float(pts[i + 1][1]))
		var L := a.distance_to(b)
		var t := (b - a) / L
		var k := 0 if i == 0 else 1
		var n := int(floor(L / STEP))
		for j in range(k, n + 1):
			var d := minf(j * STEP, L)
			out.append({"s": s0 + d, "p": a + t * d, "t": t})
		if L - n * STEP > 0.05:
			out.append({"s": s0 + L, "p": b, "t": t})
		s0 += L
	return out


## 元の網格：覆う s 区間（UV.y）と、境目の左右頂点
static func orig_info(mesh: ArrayMesh) -> Dictionary:
	var arr := mesh.surface_get_arrays(0)
	var vs0: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var uv0: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var uv20: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2] if arr[Mesh.ARRAY_TEX_UV2] != null else PackedVector2Array()
	# 索引付き（再生した網格）→ 三角形ごとに展開
	var vs := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx = arr[Mesh.ARRAY_INDEX]
	if idx != null and (idx as PackedInt32Array).size() > 0:
		for i in (idx as PackedInt32Array):
			vs.append(vs0[i])
			uv.append(uv0[i])
			uv2.append(uv20[i] if uv20.size() > i else Vector2.ZERO)
	else:
		vs = vs0
		uv = uv0
		uv2 = uv20
	var segs := []
	for t in vs.size() / 3:
		var lo := INF
		var hi := -INF
		for k in 3:
			lo = minf(lo, uv[t * 3 + k].y)
			hi = maxf(hi, uv[t * 3 + k].y)
		segs.append([lo, hi])
	segs.sort_custom(func(a, b): return a[0] < b[0])
	var merged := []
	for sg in segs:
		if not merged.is_empty() and float(sg[0]) <= float(merged[merged.size() - 1][1]) + 0.01:
			merged[merged.size() - 1][1] = maxf(float(merged[merged.size() - 1][1]), float(sg[1]))
		else:
			merged.append([float(sg[0]), float(sg[1])])
	return {"vs": vs, "uv": uv, "uv2": uv2, "cover": merged}


static func covered(cover: Array, s0: float, s1: float) -> bool:
	for c in cover:
		if s0 >= float(c[0]) - 0.01 and s1 <= float(c[1]) + 0.01:
			return true
	return false


static func terrain_y(sp: PhysicsDirectSpaceState3D, x: float, z: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 80.0, z), Vector3(x, -30.0, z))
	var ex: Array[RID] = []
	for i in 16:
		q.exclude = ex
		var h := sp.intersect_ray(q)
		if h.is_empty():
			return NAN
		if String((h["collider"] as Node).name).begins_with("TerrainCollision"):
			return float(h["position"].y)
		ex.append(h["rid"])
	return NAN


static func _lift_u(u: float, core: float) -> float:
	var a := absf(u)
	if a <= 0.66:
		return core
	if a <= MID_LIFT_U:
		return lerpf(core, 0.0, (a - 0.66) / (MID_LIFT_U - 0.66))
	return lerpf(0.0, EDGE_LIFT, (a - MID_LIFT_U) / (1.0 - MID_LIFT_U))


## 1 本の計画：{rows:[{s, hw, off, traffic, pts:[Vector3×7]}], keep_tris:[[v,uv,uv2]×3], seam_s, hw0, stats}
static func plan_road(v: Node3D, path: String, cfg: Dictionary, overrides := {}) -> Dictionary:
	var lr := layout_road(String(cfg["name"]))
	var hw0 := float(lr["half_w"])
	var mi := v.get_node(path) as MeshInstance3D
	var oi := orig_info(mi.mesh as ArrayMesh)
	var sp := v.get_world_3d().direct_space_state
	var smp := samples(lr["pts"])
	var s_end := float(smp[smp.size() - 1]["s"])
	var juncs := []
	for j in cfg["junctions"]:
		juncs.append(Vector2(float(j[0]), float(j[1])))
	var lift := float(overrides.get("lift", cfg["lift"]))
	var hwk: Array = overrides.get("hw_k", cfg["hw_k"])
	var mea := float(overrides.get("meander", cfg["meander"]))
	var seam_s := -1.0
	if cfg.has("seam_x"):
		# 境目＝元の網格の頂点の s（2 m ごとの元の取り方）のうち、x ≥ seam_x で最小のもの
		var ovs: PackedVector3Array = oi["vs"]
		var ouv: PackedVector2Array = oi["uv"]
		var best := INF
		for i in ovs.size():
			var w: Vector3 = mi.global_transform * ovs[i]
			if w.x >= float(cfg["seam_x"]) and ouv[i].y < best:
				best = ouv[i].y
		seam_s = best
		# 境目の行（s＝seam_s ちょうど）を先頭に
		var sp0 := {}
		for i in smp.size() - 1:
			if float(smp[i]["s"]) <= seam_s and float(smp[i + 1]["s"]) >= seam_s:
				var f := (seam_s - float(smp[i]["s"])) / maxf(float(smp[i + 1]["s"]) - float(smp[i]["s"]), 0.001)
				sp0 = {"s": seam_s, "p": (smp[i]["p"] as Vector2).lerp(smp[i + 1]["p"], f), "t": smp[i + 1]["t"]}
				break
		var smp2 := [sp0]
		for e in smp:
			if float(e["s"]) > seam_s + 0.3:
				smp2.append(e)
		smp = smp2
	var rows := []
	for e in smp:
		var s := float(e["s"])
		var p: Vector2 = e["p"]
		var t: Vector2 = e["t"]
		var n := Vector2(-t.y, t.x)
		var tr := _traffic(cfg, s)
		# 端・交差点・境目からの距離 → ゆらぎの重み
		var dmin := minf(s, s_end - s)
		if seam_s >= 0.0:
			dmin = minf(dmin, s - seam_s)
		for j: Vector2 in juncs:
			dmin = minf(dmin, p.distance_to(j))
		var wgt := smoothstep(0.0, TAPER, dmin)
		var k_hw := lerpf(float(hwk[0]), float(hwk[1]), tr) * (1.0 + 0.07 * _noise(s, int(cfg["seed"]) + 1))
		var hw := lerpf(hw0, hw0 * minf(k_hw, 0.97), wgt) if seam_s < 0.0 else lerpf(hw0, hw0 * minf(k_hw, 0.97), wgt * smoothstep(0.0, SEAM_BLEND, s - seam_s))
		var off := mea * _noise(s, int(cfg["seed"])) * wgt
		off = clampf(off, -(hw0 - hw - 0.04), hw0 - hw - 0.04) if hw0 - hw - 0.04 > 0.0 else 0.0
		var c := p + n * off
		var pts := []
		for u: float in US:
			var q := c + n * (u * hw)
			var ty := terrain_y(sp, q.x, q.y)
			pts.append(Vector3(q.x, ty + _lift_u(u, lift), q.y))
		rows.append({"s": s, "hw": hw, "off": off, "traffic": tr, "pts": pts})
	# 境目：元の網格の s＝seam_s の左右頂点へ最初の行を合わせ、SEAM_BLEND m で新しい横断へ
	var keep := []
	if seam_s >= 0.0:
		var vs: PackedVector3Array = oi["vs"]
		var uv: PackedVector2Array = oi["uv"]
		var uv2: PackedVector2Array = oi["uv2"]
		for tt in vs.size() / 3:
			var ok := true
			for k in 3:
				if uv[tt * 3 + k].y > seam_s + 0.001:
					ok = false
			if ok:
				keep.append([[vs[tt * 3], vs[tt * 3 + 1], vs[tt * 3 + 2]], [uv[tt * 3], uv[tt * 3 + 1], uv[tt * 3 + 2]], [uv2[tt * 3], uv2[tt * 3 + 1], uv2[tt * 3 + 2]]])
		var L := Vector3.ZERO
		var R := Vector3.ZERO
		var bl := INF
		var br := INF
		for i in vs.size():
			if absf(uv[i].y - seam_s) < 0.01:
				if uv[i].x > 0.0 and absf(uv[i].y - seam_s) < bl:
					L = mi.global_transform * vs[i]
					bl = absf(uv[i].y - seam_s)
				elif uv[i].x < 0.0 and absf(uv[i].y - seam_s) < br:
					R = mi.global_transform * vs[i]
					br = absf(uv[i].y - seam_s)
		for r: Dictionary in rows:
			var wb := smoothstep(0.0, SEAM_BLEND, float(r["s"]) - seam_s)
			var flat := []
			for ui in US.size():
				var u := float(US[ui])
				var fp: Vector3 = R.lerp(L, (u + 1.0) * 0.5)
				var np: Vector3 = (r["pts"] as Array)[ui]
				# 横位置は新しい行（同じ s の元の左右を結ぶ線上＝元の帯）、高さだけ元の帯から地形なりへ
				var ylin := lerpf(R.y, L.y, (u + 1.0) * 0.5)
				flat.append(Vector3(np.x, lerpf(ylin, np.y, wb), np.z) if wb > 0.0 else fp)
			r["pts"] = flat
	return {"rows": rows, "keep": keep, "seam_s": seam_s, "hw0": hw0, "cover": oi["cover"], "lift": lift, "inv": mi.global_transform.affine_inverse()}


static func make_mesh(pl: Dictionary) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in pl["keep"]:
		for i in 3:
			st.set_normal(Vector3.UP)
			st.set_uv(k[1][i])
			st.set_uv2(k[2][i])
			st.add_vertex(k[0][i])
	var rows: Array = pl["rows"]
	var inv: Transform3D = pl.get("inv", Transform3D.IDENTITY)   # 行は世界座標 → 道の MeshInstance の局部へ
	for ri in rows.size() - 1:
		var a: Dictionary = rows[ri]
		var b: Dictionary = rows[ri + 1]
		if not covered(pl["cover"], float(a["s"]), float(b["s"])):
			continue
		for ui in US.size() - 1:
			var a0: Vector3 = inv * (a["pts"][ui] as Vector3)
			var a1: Vector3 = inv * (a["pts"][ui + 1] as Vector3)
			var b0: Vector3 = inv * (b["pts"][ui] as Vector3)
			var b1: Vector3 = inv * (b["pts"][ui + 1] as Vector3)
			var ua0 := Vector2(float(US[ui]), float(a["s"]))
			var ua1 := Vector2(float(US[ui + 1]), float(a["s"]))
			var ub0 := Vector2(float(US[ui]), float(b["s"]))
			var ub1 := Vector2(float(US[ui + 1]), float(b["s"]))
			var wa := Vector2(float(a["hw"]), 1.0 + float(a["traffic"]))
			var wb := Vector2(float(b["hw"]), 1.0 + float(b["traffic"]))
			# 元の _ribbon と同じ巻き順（u 大→小、a→b）で表が上
			_tri(st, [a1, a0, b1], [ua1, ua0, ub1], [wa, wa, wb])
			_tri(st, [a0, b0, b1], [ua0, ub0, ub1], [wa, wb, wb])
	st.index()
	st.generate_normals()
	return st.commit()


static func _tri(st: SurfaceTool, v: Array, uv: Array, uv2: Array) -> void:
	for i in 3:
		st.set_uv(uv[i])
		st.set_uv2(uv2[i])
		st.add_vertex(v[i])


## ─────────────────────────── P7 地形の踩み固め重みの局部修正 ───────────────────────────
static func _dense(pts: Array, maxstep: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in pts.size() - 1:
		var a: Vector2 = pts[k]
		var b: Vector2 = pts[k + 1]
		var n := maxi(1, int(ceil(a.distance_to(b) / maxstep)))
		for s in n:
			out.append(a.lerp(b, float(s) / n))
	out.append(pts[pts.size() - 1])
	return out


## 線群 [{pts: PackedVector2Array（dense）, hw: PackedFloat32Array（各点）, halo: PackedFloat32Array（各点）}] の格子点 (i, j) での halo
static func _halo_grid(lines: Array, i: int, j: int) -> float:
	var q := Vector2(GRID_X0 + i * GRID, GRID_Z0 + j * GRID)
	var best := 0.0
	for ln: Dictionary in lines:
		var bb: Rect2 = ln["bb"]
		if not bb.has_point(q):
			continue
		var pts: PackedVector2Array = ln["pts"]
		var hws: PackedFloat32Array = ln["hw"]
		var hls: PackedFloat32Array = ln["halo"]
		for k in pts.size():
			var d := q.distance_to(pts[k])
			var hw := hws[k]
			var w := 1.0 - smoothstep(hw - 0.3, hw + hls[k], d)
			if w > best:
				best = w
	return best


## 頂点 (x, z) の halo：格子点ならその値、格子でない（格心点）なら 4 隅の双線形（gen の _sample と同じ）
static func _halo_at(lines: Array, cache: Dictionary, x: float, z: float) -> float:
	var fi := (x - GRID_X0) / GRID
	var fj := (z - GRID_Z0) / GRID
	var i0 := int(floor(fi))
	var j0 := int(floor(fj))
	var tx := fi - i0
	var tz := fj - j0
	var h := func(i: int, j: int) -> float:
		var key := Vector2i(i, j)
		if not cache.has(key):
			cache[key] = _halo_grid(lines, i, j)
		return float(cache[key])
	var H: Callable = h
	if tx < 1e-4 and tz < 1e-4:
		return float(H.call(i0, j0))
	return lerpf(lerpf(float(H.call(i0, j0)), float(H.call(i0 + 1, j0)), tx), lerpf(float(H.call(i0, j0 + 1)), float(H.call(i0 + 1, j0 + 1)), tx), tz)


static func _line(pts: PackedVector2Array, hw: PackedFloat32Array, halo: PackedFloat32Array) -> Dictionary:
	var bb := Rect2(pts[0], Vector2.ZERO)
	var m := 0.0
	for k in pts.size():
		bb = bb.expand(pts[k])
		m = maxf(m, hw[k] + halo[k])
	return {"pts": pts, "hw": hw, "halo": halo, "bb": bb.grow(m + 0.6)}


static func _const_line(pts: Array, hw: float, halo: float) -> Dictionary:
	var dp := _dense(pts, 1.0)
	var a := PackedFloat32Array()
	var b := PackedFloat32Array()
	a.resize(dp.size())
	b.resize(dp.size())
	a.fill(hw)
	b.fill(halo)
	return _line(dp, a, b)


## 3 群の線：対象の旧い帯（old）、ほかの道・巷道（other）、再生道（new）
static func halo_lines(v: Node3D, plans: Dictionary) -> Dictionary:
	var Lj: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	var targets := {}
	for k in ROADS:
		targets[String(ROADS[k]["name"])] = k
	var old := []
	var other := []
	var new := []
	for r in Lj["roads"]:
		var nm := String(r["name"])
		var pts := []
		for q in r["pts"]:
			pts.append(Vector2(float(q[0]), float(q[1])))
		var hw := float(r["half_w"])
		if not targets.has(nm):
			other.append(_const_line(pts, hw, OLD_HALO))
			continue
		var pl: Dictionary = plans[targets[nm]]
		var seam := float(pl["seam_s"])
		if seam < 0.0:
			old.append(_const_line(pts, hw, OLD_HALO))
		else:
			# 町の区間（s < seam）は「ほか」、田の区間（s ≥ seam）が対象
			var dp := _dense(pts, 1.0)
			var s := 0.0
			var town := []
			var farm := []
			for k in dp.size():
				if k > 0:
					s += dp[k].distance_to(dp[k - 1])
				if s <= seam + 0.5:
					town.append(dp[k])
				if s >= seam - 0.5:
					farm.append(dp[k])
			other.append(_const_line(town, hw, OLD_HALO))
			old.append(_const_line(farm, hw, OLD_HALO))
		# 再生道：行の芯（蛇行込み）・半幅・使われ方
		var cpts := PackedVector2Array()
		var chw := PackedFloat32Array()
		var chl := PackedFloat32Array()
		for row: Dictionary in pl["rows"]:
			var ps: Array = row["pts"]
			var c3: Vector3 = ps[3]
			cpts.append(Vector2(c3.x, c3.z))
			# 塗りの幅は使われ方に比例（田の奥＝0：道の土色は mesh だけ、村側ほど路面の内側に踩み固めが残る）
			chw.append(maxf(float(row["hw"]) - NEW_PAINT_INSET, 0.3) * float(row["traffic"]))
			chl.append(lerpf(float(NEW_HALO[0]), float(NEW_HALO[1]), float(row["traffic"])))
		new.append(_line(cpts, chw, chl))
	var PL = load(PARCEL_LIB)
	for r in PL.lanes(Lj):
		var pts2 := []
		for q in r["pts"]:
			pts2.append(q as Vector2)
		other.append(_const_line(pts2, float(r["hw"]), OLD_HALO))
	return {"old": old, "other": other, "new": new}


## FarmlandTerrain の COLOR.r を局部修正した新しい mesh と統計
static func terrain_fix(v: Node3D, plans: Dictionary, tol := MATCH_TOL) -> Dictionary:
	var mi := v.get_node(TERRAIN_NODE) as MeshInstance3D
	var src := mi.mesh as ArrayMesh
	var arr := src.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var cs: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	var lines := halo_lines(v, plans)
	var c_old := {}
	var c_oth := {}
	var c_new := {}
	var out := cs.duplicate()
	var changed := PackedInt32Array()
	var band_old := 0
	var band_new := 0
	var mismatch := 0
	var maxd := 0.0
	var xf := mi.global_transform
	for i in vs.size():
		var w: Vector3 = xf * vs[i]
		# 対象の線の近く（bb）だけ調べる
		var near := false
		for ln: Dictionary in lines["old"] + lines["new"]:
			if (ln["bb"] as Rect2).has_point(Vector2(w.x, w.z)):
				near = true
				break
		if not near:
			continue
		var ho := _halo_at(lines["old"], c_old, w.x, w.z)
		if ho <= 0.0:
			continue
		var hh := _halo_at(lines["other"], c_oth, w.x, w.z)
		var tr0 := cs[i].r
		var in_band := ho >= 0.3 and tr0 >= 0.3 * TR_K
		if in_band:
			band_old += 1
		if absf(tr0 - TR_K * maxf(ho, hh)) > tol or ho <= hh + 0.02 - (1.0 if tol > 0.5 else 0.0):
			if in_band:
				band_new += 1
			continue
		var strict_ok := absf(tr0 - TR_K * maxf(ho, hh)) <= MATCH_TOL and ho > hh + 0.02
		var hn := _halo_at(lines["new"], c_new, w.x, w.z)
		var tr1 := TR_K * maxf(hh, hn)
		# 頂点色は 8 bit（元の圧縮フラグ）→ 1/255 未満の差は保存で消えるので変えない
		if absf(tr1 - tr0) < 0.006:
			if in_band:
				band_new += 1
			continue
		out[i] = Color(tr1, cs[i].g, cs[i].b, cs[i].a)
		changed.append(i)
		if not strict_ok:
			mismatch += 1
		maxd = maxf(maxd, absf(tr1 - tr0))
		if in_band and tr1 >= 0.3 * TR_K:
			band_new += 1
	var arr2 := arr.duplicate()
	arr2[Mesh.ARRAY_COLOR] = out
	var m := ArrayMesh.new()
	# 元と同じ圧縮フラグ（法線・接線の量子化を元と同一に）
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr2, [], {}, src.surface_get_format(0))
	m.resource_name = "RoadBase_FarmlandTerrain"
	m.custom_aabb = src.custom_aabb
	return {"mesh": m, "changed": changed, "max_delta": maxd, "band_old": band_old, "band_new": band_new, "verts": vs.size(), "mismatch": mismatch}


static func build(v: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = NODE_NAME
	root.set_script(load(SCRIPT))
	root.set_meta("art_revision", ART_REVISION)
	root.set_meta("phase", "P10 R5a ROUND 2 road base pilot")
	var paths := PackedStringArray()
	var meshes: Array[Mesh] = []
	var keys := ROADS.keys()
	keys.sort()
	for k in keys:
		var pl := plan_road(v, k, ROADS[k])
		var m := make_mesh(pl)
		m.resource_name = "RoadBase_" + String(ROADS[k]["name"])
		paths.append(k)
		meshes.append(m)
	var plans := {}
	for k in keys:
		plans[k] = plan_road(v, k, ROADS[k])
	var tf := terrain_fix(v, plans)
	paths.append(TERRAIN_NODE)
	meshes.append(tf["mesh"])
	root.set_meta("terrain_changed", (tf["changed"] as PackedInt32Array).size())
	root.set("road_paths", paths)
	root.set("road_meshes", meshes)
	return root

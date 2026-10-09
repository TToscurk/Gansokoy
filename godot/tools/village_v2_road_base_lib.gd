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

const NODE_NAME := "RoadBaseP10"
const OUTPUT := "res://maps/village_v2/gen/road_base_p10.scn"
const SCRIPT := "res://maps/village_v2/scripts_p10/road_base.gd"
const ART_REVISION := "P10 R5a ROUND 2 road base pilot r2：農道の幅 0.66–0.82×・蛇行 0.34（元の路幅の中）、南橫街は橋のすぐ東（x 330）から 0.52–0.70× へ絞る・蛇行 0.6；r1：農道 2 本＋南橫街の田の区間を地形なり・不揃いの幅・蛇行・区間別の使われ方で再生（ART_REVIEW）"
const LAYOUT := "res://maps/village_v2/layout_v2.json"
const STEP := 1.0
const US := [-1.0, -0.66, -0.33, 0.0, 0.33, 0.66, 1.0]
const EDGE_LIFT := -0.015
const MID_LIFT_U := 0.85          # |u| ≤ 0.66 は芯の持ち上げ、0.85 で 0、1.0 で EDGE_LIFT
const TAPER := 6.0                # 端・交差点からこの距離で蛇行／幅ゆらぎを 0 へ
const SEAM_BLEND := 8.0
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
	root.set("road_paths", paths)
	root.set("road_meshes", meshes)
	return root

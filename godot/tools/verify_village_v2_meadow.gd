extends SceneTree
## 人間之里 V2 P9 R5-3 Upright Grass / Meadow Layer（全村擴張）：規劃 gate＋反向＋烘焙＋掛載＋場景級驗證＋審圖機位。
##   規劃＋gate（唯讀）：Godot --headless --path godot --script res://tools/verify_village_v2_meadow.gd
##   反向：             ... -- --negatives（各案が狙った項目で FAIL すること；MDW_NEG_ONLY=名,名 で絞り込み）
##   烘焙 overlay：     Godot --path godot --script ... -- --build（非 headless 必須：MultiMesh Build Rule）
##   掛進場景：         ... -- --attach（Vegetation/GroundcoverP9 の後に MeadowP9；既に掛かっていれば何もしない）
##   場景驗證：         Godot --path godot --script ... -- --scene（掛載順序・三層距離・影・MultiMesh 矩陣）
##   成本：             Godot --path godot --script ... -- --cost（INFO：審圖機位の GPU 增量）
##   審圖機位：         ... -- --views=res://tools/shot_village_v2_meadow_views.json（A–H 8 類×2 か所×近景／中景を自動選定）
##   診斷地図：         ... -- --map=<dir>（全村の擺放図 PNG；正式證據ではない）
## gate は技術證據であって美術判定ではない（Gate PASS ≠ ART PASS）。各項一行 [MDW] PASS/FAIL、結尾 quit(失敗項數)。

const MD := preload("res://tools/village_v2_meadow_lib.gd")
const GC := preload("res://tools/village_v2_groundcover_lib.gd")
const VL := preload("res://tools/village_v2_groundcover_village.gd")
const MVL := preload("res://tools/village_v2_groundcover_mvillage.gd")
const RLib := preload("res://tools/village_v2_riverbank_lib.gd")
const MMG := preload("res://tools/village_v2_mm_bake_guard.gd")
const SCENE := "res://maps/village_v2/village_v2.tscn"
const REPORT := "res://data/village_v2_p9r53_meadow.json"
const R5_SEAL := "res://data/village_v2_p9r5_seal.json"
const SEAL := "res://data/village_v2_p9r53_seal.json"
const VIEWS := "res://tools/shot_village_v2_meadow_views.json"
const ORDER := ["ForestP9", "BambooP9", "HiedaGardenP9", "ShrineGroveP9", "SchoolYardP9", "WatersideP9", "TowerYardP9", "SuzunaanP9", "GeidonteiP9", "KirisameP9", "GroundcoverP9", "MeadowP9"]
const CATS := ["natural_meadow", "open_grassland", "village_edge", "forest_edge", "forest_clearing", "farm_edge", "irrigation_edge", "stream_bank", "slope", "unused_lot", "narrow_gap", "backyard_corner", "village_open"]
const CAT_MIN := [60, 60, 60, 60, 10, 60, 30, 40, 60, 40, 10, 30, 60]
const ART := {"A_meadow": ["natural_meadow"], "B_edge": ["village_edge"], "C_forest": ["forest_edge"], "D_farm": ["farm_edge"],
	"E_stream": ["stream_bank", "irrigation_edge"], "F_slope": ["slope"], "G_yard": ["backyard_corner", "narrow_gap"], "H_open": ["village_open", "unused_lot"]}
const SOA := ["p", "y", "s", "w", "yaw", "h", "k", "tag", "comm", "tier", "col"]

var fails := 0
var failed_labels: Array = []
var quiet := false
var all_labels: Array = []


func check(label: String, ok: bool) -> void:
	all_labels.append(label)
	if not quiet:
		print("[MDW] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		fails += 1
		failed_labels.append(label)


func info(label: String) -> void:
	if not quiet:
		print("[MDW] INFO " + label)


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if "--attach" in args:
		quit(_attach())
		return
	if "--seal" in args:
		quit(_seal())
		return
	var v: Node3D = (load(SCENE) as PackedScene).instantiate()
	if "--scene" in args:
		root.add_child(v)
		await process_frame
		_scene(v)
		print("[MDW] 結果：%d 項失敗（scene）" % fails)
		quit(fails)
		return
	if "--cost" in args:
		root.add_child(v)
		await _cost(v)
		quit(0)
		return
	for nm in ["GroundcoverP9", MD.NODE_NAME]:
		var o := v.get_node_or_null("Vegetation/" + nm)
		if o:
			o.get_parent().remove_child(o)
			o.free()
	root.add_child(v)
	await physics_frame
	var t0 := Time.get_ticks_msec()
	var P: Dictionary = MD.base_plan(v)
	info("封存 groundcover 規劃の再計算 %d ms（讀み取り専用）" % (Time.get_ticks_msec() - t0))
	var MC := MD.context(P, v)
	info("meadow 文脈 %d ms（Props・NPC 立ち位置 %d、村外の距離場 1 m）" % [MC["ms"], MC["n_props"]])
	var F := MD.fields(P, MC)
	info("1 m 場 %d ms（%d×%d、縁のこぼれ %d セル）" % [F["ms"], F["nx"], F["nz"], int(F.get("spill", 0))])
	var M := MD.plan(P, MC, F)
	info("規劃 %d ms：%d 株（%s）" % [M["ms"], M["n"], _kind_summary(M)])
	var cats := _cats(P, MC, M)
	for s: String in args:
		if s.begins_with("--map="):
			_maps(P, MC, M, s.trim_prefix("--map="))
		if s.begins_with("--views="):
			_views(P, MC, M, cats, s.trim_prefix("--views="))
		if s.begins_with("--transect="):
			# 診斷：線分上 1 m ごとの 地形の草の塗り G・語意密度 S（1 m 場）・tag・半径 0.7 m の株數（帯の原因が地面の塗りか規劃かを切り分ける）
			var a2 := s.trim_prefix("--transect=").split(",")
			var p0 := Vector2(float(a2[0]), float(a2[1]))
			var p1 := Vector2(float(a2[2]), float(a2[3]))
			var L := int(p0.distance_to(p1))
			var aP2: PackedVector2Array = M["p"]
			for k in L + 1:
				var q := p0.lerp(p1, float(k) / maxf(1.0, L))
				var G := GC.grass_w(P["CV"], q) if MD.inside(q) else (MC["TWX"] as GC.TerrainW).grass(q)
				var ci := MD.f_idx(F, q)
				var Sv: float = (F["S"] as PackedFloat32Array)[ci] if ci >= 0 else -1.0
				var tg: int = (F["TAG"] as PackedByteArray)[ci] if ci >= 0 else 0
				var bl: int = (F["blk"] as PackedByteArray)[ci] if ci >= 0 else 1
				var cnt := 0
				for i in aP2.size():
					if aP2[i].distance_squared_to(q) < 0.49:
						cnt += 1
				info("transect %5.1f m (%.1f, %.1f)：G %.2f  S %.2f  tag %-7s blk %d  株 %d  %s" % [k, q.x, q.y, G, Sv, MD.TAG_NAMES[tg], bl, cnt, "#".repeat(cnt)])
		if s.begins_with("--dump="):
			var a := s.trim_prefix("--dump=").split(",")
			var c := Vector2(float(a[0]), float(a[1]))
			var cnt := {}
			for i in int(M["n"]):
				if (M["p"] as PackedVector2Array)[i].distance_to(c) < float(a[2]):
					var key := "%s/%s" % [MD.TAG_NAMES[(M["tag"] as PackedByteArray)[i]], MD.KIND_NAMES[(M["k"] as PackedByteArray)[i]]]
					cnt[key] = int(cnt.get(key, 0)) + 1
			info("dump %s：%s" % [str(c), str(cnt)])
	if "--negatives" in args:
		quit(_negatives(P, MC, F, M, cats))
		return
	var rep := _checks(P, MC, M, cats)
	# R5-3 封存後は重烘しない（2026-10-05 使用者裁定）：封存中は --build を拒否、使用者の同意がある時だけ MDW_ALLOW_REBAKE=1
	if "--build" in args and FileAccess.file_exists(SEAL) and OS.get_environment("MDW_ALLOW_REBAKE") != "1":
		var sl: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SEAL))
		if String(sl.get("status", "")) == "ART_APPROVED":
			check("R5-3 封存中（%s）：--build は拒否（重烘は使用者の同意後に MDW_ALLOW_REBAKE=1、封存を更新すること）" % SEAL, false)
			print("[MDW] 結果：%d 項失敗（build 拒否）" % fails)
			quit(fails)
			return
	if "--build" in args and fails == 0:
		check("永久 build rule：MultiMesh build 需要 rendering display（--build 不可加 --headless）", MMG.display_ok())
	if "--build" in args and fails == 0:
		var r := MD.bake(M)
		_bake_audit(r, M)
		if fails > 0:
			r.free()
			print("[MDW] 結果：%d 項失敗（存檔しない）" % fails)
			quit(fails)
			return
		MD.own(r, r)
		var ps := PackedScene.new()
		check("pack overlay", ps.pack(r) == OK)
		check("save %s" % MD.OUTPUT, ResourceSaver.save(ps, MD.OUTPUT, ResourceSaver.FLAG_COMPRESS) == OK)
		var rb := MMG.audit_saved_scene(MD.OUTPUT)
		check("永久 build rule：存檔後回讀 overlay，全部 instance transform 非零（%s）" % MMG.summary(rb), MMG.ok(rb))
		rep["overlay"] = {"path": MD.OUTPUT, "mb": FileAccess.get_file_as_bytes(MD.OUTPUT).size() / 1048576.0, "items": r.get_meta("items"),
			"mid_items": r.get_meta("mid_items"), "near_nodes": r.get_meta("near_nodes"), "mid_nodes": r.get_meta("mid_nodes")}
		info("overlay %.2f MB、近級 instance %d（節點 %d）、中級 instance %d（節點 %d）" % [rep["overlay"]["mb"], rep["overlay"]["items"], rep["overlay"]["near_nodes"], rep["overlay"]["mid_items"], rep["overlay"]["mid_nodes"]])
		r.free()
		var f := FileAccess.open(REPORT, FileAccess.WRITE)
		f.store_string(JSON.stringify(rep, "  ", false))
		f.close()
	print("[MDW] 結果：%d 項失敗" % fails)
	quit(fails)


func _kind_summary(M: Dictionary) -> String:
	var c := PackedInt32Array()
	c.resize(MD.KIND_NAMES.size())
	for k in (M["k"] as PackedByteArray):
		c[k] += 1
	var out := PackedStringArray()
	for k in MD.KIND_NAMES.size():
		out.append("%s %d" % [MD.KIND_NAMES[k], c[k]])
	return "、".join(out)


# ─────────────────────────── 類別（多重ラベル） ───────────────────────────

func _seam(P: Dictionary, MC: Dictionary, p: Vector2) -> float:
	return GC.seam_d(P["CV"], p) if MD.inside(p) else -(MC["seamX"] as GC.DGrid).at(p)


func _water_e(P: Dictionary, MC: Dictionary, p: Vector2) -> float:
	return (GC.wdist(P["CV"], p) if MD.inside(p) else maxf((MC["waterX"] as GC.DGrid).at(p), 0.0)) - GC.RB_CORE


func _farm_d(P: Dictionary, MC: Dictionary, p: Vector2) -> float:
	return MVL.fdist(P["MV"], p) if MD.inside(p) else (MC["farmX"] as GC.DGrid).at(p)


func _bw(P: Dictionary, p: Vector2) -> float:
	return MVL.bdist(P["CV"], P["MV"], p) if MD.inside(p) else 99.0


func _cat_of(P: Dictionary, MC: Dictionary, p: Vector2, tag: int) -> int:
	var CV: Dictionary = P["CV"]
	var m := 0
	var bw := _bw(P, p)
	var sd := _seam(P, MC, p)
	var e := _water_e(P, MC, p)
	var fd := _farm_d(P, MC, p)
	var ins := MD.inside(p)
	if tag == MD.T_OUTSIDE or (tag == MD.T_MEADOW and bw > 20.0):
		m |= 1 << 0
	if tag == MD.T_WILD:
		m |= 1 << 1
	if bw >= 10.0 and bw <= 45.0 and tag in [MD.T_MEADOW, MD.T_WILD, MD.T_LOT, MD.T_OUTSIDE, MD.T_OPEN, MD.T_FARM_TR]:
		m |= 1 << 2
	if sd > -6.0 and sd < 3.5:
		m |= 1 << 3
	if sd < -2.0:
		var enc := 0
		for d: Vector2 in [Vector2(18, 0), Vector2(-18, 0), Vector2(0, 18), Vector2(0, -18)]:
			if _seam(P, MC, p + d) > 0.0:
				enc += 1
		if enc >= 3:
			m |= 1 << 4
	if fd > 0.3 and fd < 8.0:
		m |= 1 << 5
	if e < 5.0 and fd < 30.0:
		m |= 1 << 6
	elif e < 6.0:
		m |= 1 << 7
	if MVL.slope(CV, p) > 0.28:
		m |= 1 << 8
	if tag == MD.T_LOT:
		m |= 1 << 9
	if ins and VL.wall_d(CV, p) < 3.0:
		var wn := MVL.wall_near(P["MV"], p)
		if wn[1] != null and MVL.alley_k(P["MV"], p, wn[1]) > 0.5:
			m |= 1 << 10
	if tag in [MD.T_CORNER, MD.T_WALL]:
		m |= 1 << 11
	if ins and tag in [MD.T_WILD, MD.T_LOT, MD.T_WALK, MD.T_WORK, MD.T_OPEN] and bw < 25.0:
		m |= 1 << 12
	return m


func _cats(P: Dictionary, MC: Dictionary, M: Dictionary) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(int(M["n"]))
	var aP: PackedVector2Array = M["p"]
	var aT: PackedByteArray = M["tag"]
	for i in int(M["n"]):
		out[i] = _cat_of(P, MC, aP[i], aT[i])
	return out


# ─────────────────────────── 規劃 gate ───────────────────────────

func _grid(M: Dictionary, F: Dictionary) -> PackedInt32Array:
	var g := PackedInt32Array()
	g.resize(int(F["nx"]) * int(F["nz"]))
	for p in (M["p"] as PackedVector2Array):
		var k := MD.f_idx(F, p)
		if k >= 0:
			g[k] += 1
	return g


func _checks(P: Dictionary, MC: Dictionary, M: Dictionary, cats: PackedInt32Array) -> Dictionary:
	var CV: Dictionary = P["CV"]
	var F: Dictionary = M["F"]
	var n: int = M["n"]
	var aP: PackedVector2Array = M["p"]
	var aH: PackedFloat32Array = M["h"]
	var aK: PackedByteArray = M["k"]
	var aT: PackedByteArray = M["tag"]
	var rep := {"n": n}
	var nx: int = F["nx"]
	var nz: int = F["nz"]
	var o: Vector2 = F["o"]
	var blk: PackedByteArray = F["blk"]
	var aS: PackedFloat32Array = F["S"]
	# 1 Kit
	var K := MD.kit()
	var kit_ok := K.size() == 9
	var kit_txt := PackedStringArray()
	for k in K.size():
		var e: Dictionary = K[k]
		kit_ok = kit_ok and int(e["tris"]) >= 20 and int(e["tris"]) <= 80 and int(e["tris_mid"]) <= int(0.45 * int(e["tris"])) and int(e["tris_mid"]) >= 3 and float(e["h"]) >= 0.15 and float(e["h"]) <= 0.62
		kit_txt.append("%s %d/%d△ %.2fm" % [e["name"], e["tris"], e["tris_mid"], e["h"]])
	check("Kit（Pilot p8 と同一）：立ち草 7＋羊歯＋笹（近級 20–80△、中級 ≤ 45 %%、丈 0.15–0.62 m）：%s" % "、".join(kit_txt), kit_ok)
	# 2 禁區（全株を正確に再判定）
	var bad := {}
	for i in n:
		var br := MD.blocked(P, MC, aP[i])
		if br != "":
			bad[br] = int(bad.get(br, 0)) + 1
	check("禁區：建物・軒下 0.75 m・路面＋0.2 m・小径の芯・水面・P7 核心／構件・P8 農田・封存構圖・竹林・樹幹 0.55 m・Props／NPC 立ち位置・植物節點 → 違反 %d %s（%d 株）" % [_sum(bad), str(bad), n], bad.is_empty() and n > 0)
	# 3 接地
	var gbad := 0
	var aY: PackedFloat32Array = M["y"]
	for i in n:
		if absf(aY[i] - (MVL.top_h(P, aP[i]) - MD.SINK)) > 0.005:
			gbad += 1
	check("接地：根元＝可見最上面 −%.2f m、偏差 > 5 mm の株 %d" % [MD.SINK, gbad], gbad == 0)
	# 4 立體
	var ng := 0
	var nt := 0
	var tiny := 0
	for i in n:
		if aK[i] in MD.GRASS_KINDS:
			ng += 1
			if aH[i] >= 0.3:
				nt += 1
		if aH[i] < 0.12:
			tiny += 1
	var tr := float(nt) / maxf(1.0, float(ng))
	check("立體：立ち草 %d 株の丈 ≥ 0.30 m %.0f %%（≥ 40 %%）、< 0.12 m %d（= 0）" % [ng, tr * 100.0, tiny], tr >= 0.4 and tiny == 0)
	# 5 類別覆蓋
	var cc := PackedInt32Array()
	cc.resize(CATS.size())
	for i in n:
		for b in CATS.size():
			if cats[i] & (1 << b):
				cc[b] += 1
	var cat_ok := true
	var ctxt := PackedStringArray()
	for b in CATS.size():
		cat_ok = cat_ok and cc[b] >= CAT_MIN[b]
		ctxt.append("%s %d" % [CATS[b], cc[b]])
	rep["cats"] = Array(cc)
	check("類別覆蓋（各 ≥ 下限）：%s" % "、".join(ctxt), cat_ok)
	# 6 群れ・高さ群
	var G := _grid(M, F)
	var wins: Array = []
	var hwin: Array = []
	var hsum := PackedFloat32Array()
	hsum.resize(nx * nz)
	for i in n:
		var k := MD.f_idx(F, aP[i])
		if k >= 0:
			hsum[k] += aH[i]
	for wj in range(0, nz - 4, 4):
		for wi in range(0, nx - 4, 4):
			var cnt := 0
			var okc := 0
			var hs := 0.0
			for dj in 4:
				for di in 4:
					var k := (wj + dj) * nx + wi + di
					if blk[k] == 0 and aS[k] > 0.05:
						okc += 1
					cnt += G[k]
					hs += hsum[k]
			if okc >= 10:
				wins.append(float(cnt) / okc)
				if cnt >= 20:
					hwin.append(hs / cnt)
	var wcv := _cv(wins)
	var hcv := _cv(hwin)
	check("群れ：4 m 窗の密度 變動係數 %.2f（≥ 0.50、均一 scatter 禁止）・局所の平均丈 變動係數 %.2f（≥ 0.12、高さ群）" % [wcv, hcv], wcv >= 0.5 and hcv >= 0.12)
	# 7 斑の形
	var dense := {}
	for k in G.size():
		if G[k] >= 3:
			dense[Vector2i(k % nx, k / nx)] = true
	var comps := _components(dense)
	var big := 0
	var round_n := 0
	var abrupt := 0
	var bcells := 0
	var sol_list: Array = []
	for comp: Array in comps:
		if comp.size() < 20:
			continue
		big += 1
		var pts := PackedVector2Array()
		for c: Vector2i in comp:
			pts.append(Vector2(c.x, c.y))
			pts.append(Vector2(c.x + 1, c.y))
			pts.append(Vector2(c.x, c.y + 1))
			pts.append(Vector2(c.x + 1, c.y + 1))
		var hull := Geometry2D.convex_hull(pts)
		var sol := float(comp.size()) / maxf(absf(_poly_area(hull)), 1.0)
		sol_list.append(sol)
		if sol > 0.84:
			round_n += 1
		for c: Vector2i in comp:
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q1 := c + d
				if dense.has(q1):
					continue
				var q2 := c + d * 2
				if q1.x < 0 or q2.x < 0 or q1.y < 0 or q2.y < 0 or q2.x >= nx or q2.y >= nz:
					continue
				var k1 := q1.y * nx + q1.x
				var k2 := q2.y * nx + q2.x
				if blk[k1] == 1 or blk[k2] == 1:
					continue
				bcells += 1
				if G[k1] == 0 and G[k2] == 0:
					abrupt += 1
	var rr := float(round_n) / maxf(1.0, float(big))
	var ar := float(abrupt) / maxf(1.0, float(bcells))
	sol_list.sort()
	var med_sol: float = sol_list[sol_list.size() / 2] if not sol_list.is_empty() else 0.0
	rep["patch"] = {"components": big, "round_share": rr, "solidity_median": med_sol, "abrupt_share": ar}
	check("斑の形：密な斑 %d 個（≥ 20 m²）のうち円／楕円（凸包充足率 > 0.84）%.0f %%（≤ 15 %%、中央値 %.2f）、dense → 2 m 先まで空の急な縁 %.0f %%（≤ 30 %%）" % [big, rr * 100.0, med_sol, ar * 100.0],
		big >= 20 and rr <= 0.15 and ar <= 0.3)
	# 8 道路の帯
	var rb := [[0, 0], [0, 0], [0, 0]]
	var seg := {}
	for j in nz:
		for i in nx:
			var k := j * nx + i
			if blk[k] == 1:
				continue
			var c := o + Vector2(i + 0.5, j + 0.5)
			if not MD.inside(c):
				continue
			var rsd := VL.road_sd(CV, c)
			var bi := -1
			if rsd >= 0.2 and rsd < 1.5:
				bi = 0
			elif rsd >= 1.5 and rsd < 3.0:
				bi = 1
			elif rsd >= 3.0 and rsd < 6.0:
				bi = 2
			if bi < 0:
				continue
			rb[bi][0] += 1
			rb[bi][1] += G[k]
			if rsd >= 1.0 and rsd < 3.5:
				var sk := Vector2i(floori(c.x / 6.0), floori(c.y / 6.0))
				if not seg.has(sk):
					seg[sk] = [0, 0]
				seg[sk][0] += 1
				seg[sk][1] += G[k]
	var d0 := float(rb[0][1]) / maxf(1.0, float(rb[0][0]))
	var d1 := float(rb[1][1]) / maxf(1.0, float(rb[1][0]))
	var d2 := float(rb[2][1]) / maxf(1.0, float(rb[2][0]))
	var sd_list: Array = []
	for sk in seg:
		if int(seg[sk][0]) >= 6:
			sd_list.append(float(seg[sk][1]) / float(seg[sk][0]))
	var scv := _cv(sd_list)
	check("道路：路縁 0.2–1.5 m %.2f ≤ 1.5–3 m %.2f×1.1 ≤ 3–6 m %.2f×1.2（單調・縁に峰なし）、1–3.5 m 帯の 6 m 区間 變動係數 %.2f（≥ 0.6、等寬帶なし）" % [d0, d1, d2, scv],
		d0 <= d1 * 1.1 + 0.05 and d1 <= d2 * 1.2 + 0.05 and scv >= 0.6)
	# 9 農田の外緣
	var fseg := {}
	for i in n:
		var p := aP[i]
		var fd := _farm_d(P, MC, p)
		if fd > 0.3 and fd < 8.0 and _bw(P, p) > 4.0:
			var sk := Vector2i(floori(p.x / 6.0), floori(p.y / 6.0))
			if not fseg.has(sk):
				fseg[sk] = [0, 0.0]
			fseg[sk][0] += 1
			fseg[sk][1] += fd
	var fcells := {}
	# r6c：田の縁 0.5–3 m の「埋まり率」（株のある 1 m セル／空きセル）——固定幅の帯は全区間でほぼ 1 になる
	var focc := {}
	for j in nz:
		for i in nx:
			var k := j * nx + i
			if blk[k] == 1:
				continue
			var c := o + Vector2(i + 0.5, j + 0.5)
			var fd := _farm_d(P, MC, c)
			if fd > 0.3 and fd < 8.0 and _bw(P, c) > 4.0:
				var sk := Vector2i(floori(c.x / 6.0), floori(c.y / 6.0))
				fcells[sk] = int(fcells.get(sk, 0)) + 1
				if fd >= 0.5 and fd < 3.0:
					if not focc.has(sk):
						focc[sk] = [0, 0]
					focc[sk][0] += 1
					if G[k] > 0:
						focc[sk][1] += 1
	# 使用者裁定：「不要做固定寬度的 grass strip」→ 帯の幅（届く距離）と沿線の密度が区間ごとに揺らぐこと（空白の強制ではない）
	var reach: Array = []
	var fdens: Array = []
	var nseg := 0
	for sk in fcells:
		if int(fcells[sk]) < 8:
			continue
		nseg += 1
		var cntf: int = fseg[sk][0] if fseg.has(sk) else 0
		fdens.append(float(cntf) / float(fcells[sk]))
		if cntf >= 8:
			reach.append(float(fseg[sk][1]) / cntf)
	var rcv := _cv(reach)
	var dcv := _cv(fdens)
	var occ: Array = []
	for sk in focc:
		if int(focc[sk][0]) >= 4:
			occ.append(float(focc[sk][1]) / float(focc[sk][0]))
	var ocv := _cv(occ)
	check("農田の外緣：6 m 区間 %d の帯の届く距離 變動係數 %.2f（≥ 0.25）・沿線の密度 變動係數 %.2f（≥ 0.35）・田縁 0.5–3 m の埋まり率 變動係數 %.2f（≥ 0.35）＝固定幅・一定密度の帯なし" % [nseg, rcv, dcv, ocv],
		nseg >= 20 and rcv >= 0.25 and dcv >= 0.35 and ocv >= 0.35)
	# 10 樹の輪・建物の輪
	var tr_ring := 0
	var tr_n := 0
	for t: Array in MC["trees"]:
		var tp: Vector2 = t[0]
		var sec := PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0])
		var inner := 0
		var outer := 0
		for dj in range(-6, 7):
			for di in range(-6, 7):
				var k := MD.f_idx(F, tp + Vector2(di, dj))
				if k < 0:
					continue
				var dd := Vector2(di, dj).length()
				if dd >= 0.6 and dd < 2.5:
					inner += G[k]
					if G[k] > 0:
						sec[int(fposmod(atan2(dj, di) / TAU * 8.0, 8.0))] = 1
				elif dd >= 3.0 and dd < 6.0:
					outer += G[k]
		if inner + outer < 4:
			continue
		tr_n += 1
		var full := 0
		for s in sec:
			full += s
		if full == 8 and float(inner) / 16.0 > 2.0 * float(outer) / 85.0:
			tr_ring += 1
	var trr := float(tr_ring) / maxf(1.0, float(tr_n))
	var hb_ring := 0
	var hb_n := 0
	for ob: Dictionary in CV["obb"]:
		var hh: Vector2 = ob["h"]
		var oc: Vector2 = ob["o"]
		var bx: Vector2 = ob["bx"]
		var bz: Vector2 = ob["bz"]
		var segs := 0
		var hit := 0
		for e in 4:
			var nrm: Vector2 = [-bz, bx, bz, -bx][e]
			var tan: Vector2 = [bx, bz, -bx, -bz][e]
			var half: float = [hh.x, hh.y, hh.x, hh.y][e]
			var off: float = [hh.y, hh.x, hh.y, hh.x][e]
			var t := -half
			while t <= half:
				var q: Vector2 = oc + nrm * (off + 1.7) + tan * t
				t += 1.0
				if MD.blocked(P, MC, q) in ["building", "road", "frontage", "farm", "water", "ext"]:
					continue
				segs += 1
				var k := MD.f_idx(F, q)
				if k >= 0 and G[k] > 0:
					hit += 1
		if segs < 8:
			continue
		hb_n += 1
		if float(hit) / segs >= 0.8:
			hb_ring += 1
	check("輪：樹 %d 本のうち周りだけ全周に草 %d（%.0f %%、≤ 5 %%）、建物 %d 棟のうち壁沿い 1.7 m の 80 %% 以上に草 %d（= 0）" % [tr_n, tr_ring, trr * 100.0, hb_n, hb_ring], trr <= 0.05 and hb_ring == 0)
	# 11 群落
	var comm := {}
	var aC: PackedInt32Array = M["comm"]
	for i in n:
		if not (aK[i] in MD.GRASS_KINDS):
			continue
		var cid: int = aC[i]
		if not comm.has(cid):
			comm[cid] = PackedInt32Array([0, 0, 0, 0, 0, 0, 0])
		var arr0: PackedInt32Array = comm[cid]
		arr0[aK[i]] += 1
		comm[cid] = arr0
	var cn := 0
	var cok := 0
	var doms := {}
	for cid in comm:
		var arr: PackedInt32Array = comm[cid]
		var tot := 0
		var mx := 0
		var mk := 0
		for k in arr.size():
			tot += arr[k]
			if arr[k] > mx:
				mx = arr[k]
				mk = k
		if tot < 40:
			continue
		cn += 1
		var many := 0
		for k in arr.size():
			if arr[k] >= 0.1 * tot:
				many += 1
		if float(mx) / tot >= 0.5 and many <= 3:
			cok += 1
		doms[mk] = int(doms.get(mk, 0)) + 1
	var cr := float(cok) / maxf(1.0, float(cn))
	var dmax := 0
	for k in doms:
		dmax = maxi(dmax, int(doms[k]))
	check("群落：40 株以上の群落 %d のうち dominant ≥ 50 %%・10 %% 以上の種 ≤ 3 が %.0f %%（≥ 85 %%）、dominant の種類 %d（≥ 3）・最多 %.0f %%（≤ 60 %%）" % [cn, cr * 100.0, doms.size(), 100.0 * dmax / maxf(1.0, float(cn))],
		cn >= 30 and cr >= 0.85 and doms.size() >= 3 and float(dmax) / maxf(1.0, float(cn)) <= 0.6)
	# 12 語意
	var th := {}
	for i in n:
		var t: int = aT[i]
		if not th.has(t):
			th[t] = [0, 0.0]
		th[t][0] += 1
		th[t][1] += aH[i]
	var mh := func(t: int) -> float: return float(th[t][1]) / float(th[t][0]) if th.has(t) else 0.0
	var low_max := 0.0
	for i in n:
		if aT[i] == MD.T_ROAD or aT[i] == MD.T_PATH:
			low_max = maxf(low_max, aH[i])
	var spot_n := 0
	for i in n:
		if MD.inside(aP[i]) and MD._spot(P, aP[i]) > 0.6:
			spot_n += 1
	var edge_h := (float(mh.call(MD.T_FOREST)) + float(mh.call(MD.T_FARM)) + float(mh.call(MD.T_WATER))) / 3.0
	var corner_n: int = th[MD.T_CORNER][0] if th.has(MD.T_CORNER) else 0
	check("語意：路・小径の脇の最大丈 %.2f m（≤ 0.26）、作業地面の芯の株 %d（≤ 20）、林緣・農田・水際の平均丈 %.2f ≥ 後場 %.2f＋0.08、後院の隅・路地 %d 株（≥ 100）" % [low_max, spot_n, edge_h, float(mh.call(MD.T_YARD)), corner_n],
		low_max <= 0.26 and spot_n <= 20 and edge_h >= float(mh.call(MD.T_YARD)) + 0.08 and corner_n >= 100)
	# 13 R5 Macro Ground は重畫しない
	var seal: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(R5_SEAL))
	var gk := "godot/maps/village_v2/gen/groundcover_p9.scn"
	check("R5 Macro Ground 不重畫：%s の雜湊＝R5 封存時（立ち草は別 overlay %s）" % [gk.get_file(), MD.OUTPUT.get_file()], FileAccess.get_sha256(GC.OUTPUT) == String(seal["frozen"][gk]))
	return rep


func _sum(d: Dictionary) -> int:
	var s := 0
	for k in d:
		s += int(d[k])
	return s


func _cv(a: Array) -> float:
	if a.size() < 2:
		return 0.0
	var m := 0.0
	for x: float in a:
		m += x
	m /= a.size()
	var s := 0.0
	for x: float in a:
		s += (x - m) * (x - m)
	return sqrt(s / a.size()) / maxf(m, 1e-6)


func _poly_area(pts: PackedVector2Array) -> float:
	var a := 0.0
	for i in pts.size():
		var p := pts[i]
		var q := pts[(i + 1) % pts.size()]
		a += p.x * q.y - q.x * p.y
	return a * 0.5


func _components(cells: Dictionary) -> Array:
	var seen := {}
	var out: Array = []
	for c: Vector2i in cells:
		if seen.has(c):
			continue
		var comp: Array = []
		var stk := [c]
		seen[c] = true
		while not stk.is_empty():
			var q: Vector2i = stk.pop_back()
			comp.append(q)
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var r := q + d
				if cells.has(r) and not seen.has(r):
					seen[r] = true
					stk.append(r)
		out.append(comp)
	return out


# ─────────────────────────── 烘焙後の檢查 ───────────────────────────

func _bake_audit(r: Node3D, M: Dictionary) -> void:
	var n_near := 0
	var n_mid := 0
	var ok_n := true
	var ok_m := true
	for c in r.get_node("Near").get_children():
		var g := c as MultiMeshInstance3D
		n_near += g.multimesh.instance_count
		ok_n = ok_n and g.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON and g.visibility_range_end > 0.0 and g.visibility_range_end <= MD.NEAR_OUT.y + MD.NEAR_CHUNK * 0.71 + 2.5 \
			and g.multimesh.custom_aabb.size.x <= MD.NEAR_CHUNK + 2.5 and g.multimesh.custom_aabb.size.z <= MD.NEAR_CHUNK + 2.5
	for c in r.get_node("Mid").get_children():
		var g := c as MultiMeshInstance3D
		n_mid += g.multimesh.instance_count
		ok_m = ok_m and g.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and g.visibility_range_end <= MD.MID_OUT.y + MD.MID_CHUNK * 0.71 + 2.5 \
			and g.multimesh.custom_aabb.size.x <= MD.MID_CHUNK + 2.5
	var mr := float(n_mid) / maxf(1.0, float(n_near))
	check("三層距離：近級 %d 株（0–%.0f m で縮んで消える・影あり・%d m 分塊・緊 AABB）＋中級 %d 株（%.0f %%、%.0f–%.0f m・影なし・幅広の低面網格・%d m 分塊）＋%.0f m 以遠は 3D 草 0" % [
		n_near, MD.NEAR_OUT.y, int(MD.NEAR_CHUNK), n_mid, mr * 100.0, MD.NEAR_OUT.x, MD.MID_OUT.y, int(MD.MID_CHUNK), MD.MID_OUT.y],
		ok_n and ok_m and n_near == int(M["n"]) and mr >= 0.25 and mr <= 0.6)


# ─────────────────────────── 反向 ───────────────────────────

func _copy(M: Dictionary) -> Dictionary:
	var M2 := M.duplicate()
	for key in SOA:
		M2[key] = (M[key] as Variant).duplicate()
	return M2


## 反向用の追加：Packed 配列は値型なので、追加分は Array（參照型）に溜めて _flush で一度に連結する
func _append(M: Dictionary, P: Dictionary, p: Vector2, k: int, h: float, tag: int, cid: int) -> void:
	if not M.has("_add"):
		var A0 := {}
		for key in SOA:
			A0[key] = []
		M["_add"] = A0
	var A: Dictionary = M["_add"]
	(A["p"] as Array).append(p)
	(A["y"] as Array).append(MVL.top_h(P, p) - MD.SINK)
	(A["s"] as Array).append(1.0)
	(A["w"] as Array).append(1.0)
	(A["yaw"] as Array).append(0.0)
	(A["h"] as Array).append(h)
	(A["k"] as Array).append(k)
	(A["tag"] as Array).append(tag)
	(A["comm"] as Array).append(cid)
	(A["tier"] as Array).append(0)
	(A["col"] as Array).append(Color.WHITE)


func _flush(M: Dictionary) -> void:
	if not M.has("_add"):
		return
	var A: Dictionary = M["_add"]
	var pp: PackedVector2Array = M["p"]
	pp.append_array(PackedVector2Array(A["p"]))
	M["p"] = pp
	for key in ["y", "s", "w", "yaw", "h"]:
		var f: PackedFloat32Array = M[key]
		f.append_array(PackedFloat32Array(A[key]))
		M[key] = f
	for key in ["k", "tag", "tier"]:
		var b: PackedByteArray = M[key]
		b.append_array(PackedByteArray(A[key]))
		M[key] = b
	var ci: PackedInt32Array = M["comm"]
	ci.append_array(PackedInt32Array(A["comm"]))
	M["comm"] = ci
	var cc: PackedColorArray = M["col"]
	cc.append_array(PackedColorArray(A["col"]))
	M["col"] = cc
	M["n"] = pp.size()
	M.erase("_add")


func _filter(M: Dictionary, keep: Callable) -> Dictionary:
	var idx := PackedInt32Array()
	for i in int(M["n"]):
		if keep.call(i):
			idx.append(i)
	var M2 := M.duplicate()
	var sp: PackedVector2Array = M["p"]
	var op := PackedVector2Array()
	for i in idx:
		op.append(sp[i])
	M2["p"] = op
	for key in ["y", "s", "w", "yaw", "h"]:
		var sf: PackedFloat32Array = M[key]
		var of := PackedFloat32Array()
		for i in idx:
			of.append(sf[i])
		M2[key] = of
	for key in ["k", "tag", "tier"]:
		var sb: PackedByteArray = M[key]
		var ob := PackedByteArray()
		for i in idx:
			ob.append(sb[i])
		M2[key] = ob
	var si: PackedInt32Array = M["comm"]
	var oi := PackedInt32Array()
	for i in idx:
		oi.append(si[i])
	M2["comm"] = oi
	var sc: PackedColorArray = M["col"]
	var oc := PackedColorArray()
	for i in idx:
		oc.append(sc[i])
	M2["col"] = oc
	M2["n"] = idx.size()
	return M2


func _negatives(P: Dictionary, MC: Dictionary, F: Dictionary, M: Dictionary, cats: PackedInt32Array) -> int:
	var target := {"n_road": "禁區", "n_float": "接地", "n_tiny": "立體", "n_uniform": "群れ", "n_circle": "斑の形", "n_band": "道路", "n_fixedfarm": "農田の外緣",
		"n_ring": "輪", "n_treering": "輪", "n_evenmix": "群落", "n_nocorner": "語意", "n_nostream": "類別覆蓋"}
	var CV: Dictionary = P["CV"]
	var nx: int = F["nx"]
	var nz: int = F["nz"]
	var o: Vector2 = F["o"]
	var blk: PackedByteArray = F["blk"]
	var bad := 0
	var only := OS.get_environment("MDW_NEG_ONLY")
	for nm: String in target:
		if only != "" and not (nm in only.split(",")):
			continue
		var M2: Dictionary
		var c2 := cats
		match nm:
			"n_tiny", "n_uniform", "n_evenmix":
				var P2 := P.duplicate()
				P2["_neg_" + nm.trim_prefix("n_")] = true
				M2 = MD.plan(P2, MC, F)
				c2 = _cats(P, MC, M2)
			"n_float":
				M2 = _copy(M)
				var ay: PackedFloat32Array = M2["y"]
				for i in range(0, ay.size(), 7):
					ay[i] += 0.3
				M2["y"] = ay
			"n_road":
				M2 = _copy(M)
				var na := 0
				for j in range(0, nz, 3):
					for i in range(0, nx, 3):
						var c := o + Vector2(i + 0.5, j + 0.5)
						if na < 60 and MD.blocked(P, MC, c) in ["road", "path", "eave", "farm"]:
							_append(M2, P, c, MD.K_TALL, 0.5, MD.T_OPEN, 0)
							na += 1
			"n_circle":
				M2 = _filter(M, func(_i: int) -> bool: return false)
				var aP: PackedVector2Array = M["p"]
				var centers: Array = []
				for i in range(0, aP.size(), 97):
					var c: Vector2 = aP[i]
					if centers.any(func(q: Vector2) -> bool: return q.distance_to(c) < 12.0):
						continue
					centers.append(c)
					var y := -4.0
					while y <= 4.0:
						var x := -4.0
						while x <= 4.0:
							if Vector2(x, y).length() <= 4.0:
								_append(M2, P, c + Vector2(x, y), MD.K_MEDIUM, 0.4, MD.T_MEADOW, i)
							x += 0.5
						y += 0.5
				c2 = _cats(P, MC, M2)
			"n_band":
				M2 = _copy(M)
				for j in nz:
					for i in nx:
						var c := o + Vector2(i + 0.5, j + 0.5)
						if MD.inside(c) and blk[j * nx + i] == 0:
							var rsd := VL.road_sd(CV, c)
							if rsd >= 0.8 and rsd < 2.0:
								for q in 5:
									_append(M2, P, c + Vector2(0.2 * q - 0.4, 0.17 * q - 0.3), MD.K_MEDIUM, 0.35, MD.T_OPEN, 0)
				c2 = _cats(P, MC, M2)
			"n_fixedfarm":
				# 田の外緣の既存株を全部抜いてから、固定幅（0.5–3 m 密・3–8 m 疎）の一様な帯に置き換える（足すだけだと既存の揺らぎで帯が隠れる）
				var aPf: PackedVector2Array = M["p"]
				M2 = _filter(M, func(i: int) -> bool:
					var fdi := _farm_d(P, MC, aPf[i])
					return not (fdi > 0.3 and fdi < 8.0 and _bw(P, aPf[i]) > 4.0))
				for j in nz:
					for i in nx:
						if blk[j * nx + i] == 1:
							continue
						var c := o + Vector2(i + 0.5, j + 0.5)
						var fd := _farm_d(P, MC, c)
						if fd >= 0.5 and fd < 3.0 and _bw(P, c) > 4.0:
							for q in 4:
								_append(M2, P, c + Vector2(0.25 * q - 0.4, 0.2 * q - 0.3), MD.K_TALL, 0.5, MD.T_FARM, 0)
						elif fd >= 3.0 and fd < 8.0 and _bw(P, c) > 4.0:
							_append(M2, P, c, MD.K_SHORT, 0.2, MD.T_FARM, 0)
				c2 = _cats(P, MC, M2)
			"n_ring":
				M2 = _copy(M)
				for ob: Dictionary in CV["obb"]:
					var hh: Vector2 = ob["h"]
					var bx: Vector2 = ob["bx"]
					var bz: Vector2 = ob["bz"]
					for e in 4:
						var nrm: Vector2 = [-bz, bx, bz, -bx][e]
						var tan: Vector2 = [bx, bz, -bx, -bz][e]
						var half: float = [hh.x, hh.y, hh.x, hh.y][e]
						var off: float = [hh.y, hh.x, hh.y, hh.x][e]
						var t := -half
						while t <= half:
							_append(M2, P, (ob["o"] as Vector2) + nrm * (off + 1.7) + tan * t, MD.K_MEDIUM, 0.35, MD.T_WALL, 0)
							t += 0.5
				c2 = _cats(P, MC, M2)
			"n_treering":
				M2 = _copy(M)
				for t: Array in MC["trees"]:
					for a in 24:
						for rr in [0.9, 1.5, 2.1]:
							_append(M2, P, (t[0] as Vector2) + Vector2(cos(a * TAU / 24.0), sin(a * TAU / 24.0)) * float(rr), MD.K_MEDIUM, 0.35, MD.T_OPEN, 0)
				c2 = _cats(P, MC, M2)
			"n_nocorner":
				M2 = _filter(M, func(i: int) -> bool: return (M["tag"] as PackedByteArray)[i] != MD.T_CORNER)
				c2 = _cats(P, MC, M2)
			"n_nostream":
				M2 = _filter(M, func(i: int) -> bool: return (cats[i] & ((1 << 7) | (1 << 6))) == 0)
				c2 = _cats(P, MC, M2)
		if M2.has("_add"):
			_flush(M2)
			c2 = _cats(P, MC, M2)
		fails = 0
		failed_labels.clear()
		all_labels.clear()
		quiet = true
		var rp := _checks(P, MC, M2, c2)
		quiet = false
		var hit := failed_labels.any(func(l: String) -> bool: return l.begins_with(String(target[nm])))
		print("[MDW] %s 反向 %s → 「%s」必須 FAIL（失敗項 %d：%s）" % ["PASS" if hit else "FAIL", nm, target[nm], failed_labels.size(), " ／ ".join(failed_labels.map(func(l: String) -> String: return l.left(10)))])
		if not hit:
			bad += 1
			for l: String in all_labels:
				if l.begins_with(String(target[nm])):
					print("[MDW]     狙いを外した：%s" % l)
	print("[MDW] 結果：%d 項失敗（negatives）" % bad)
	return bad


# ─────────────────────────── 審圖機位 ───────────────────────────

func _views(P: Dictionary, MC: Dictionary, M: Dictionary, cats: PackedInt32Array, out_path: String) -> void:
	var S: RLib.TriSampler = P["CV"]["S"]
	var aP: PackedVector2Array = M["p"]
	var views: Array = []
	var Hall := {}
	for i in int(M["n"]):
		var c := Vector2i(floori(aP[i].x / 2.0), floori(aP[i].y / 2.0))
		Hall[c] = int(Hall.get(c, 0)) + 1
	var used: Array = []
	for an: String in ART:
		var mask := 0
		for cn: String in ART[an]:
			mask |= 1 << CATS.find(cn)
		var H := {}
		for i in int(M["n"]):
			if cats[i] & mask:
				var c := Vector2i(floori(aP[i].x / 2.0), floori(aP[i].y / 2.0))
				H[c] = int(H.get(c, 0)) + 1
		var wins: Array = []
		for c: Vector2i in H:
			var s := 0
			for a in range(-2, 2):
				for b in range(-2, 2):
					s += int(H.get(c + Vector2i(a, b), 0))
			wins.append([s, Vector2(c.x * 2.0 + 1.0, c.y * 2.0 + 1.0)])
		wins.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) > int(b[0]))
		var picked := 0
		var tried := 0
		for w: Array in wins:
			if picked >= 2 or tried > 400:
				break
			var c: Vector2 = w[1]
			if used.any(func(q: Vector2) -> bool: return q.distance_to(c) < 40.0):
				continue
			tried += 1
			var pair: Array = []
			for rr: float in [7.0, 17.0]:
				var best: Array = []
				for k in 24:
					var a := TAU * k / 24.0
					var st := c + Vector2(cos(a), sin(a)) * rr
					if MD.blocked(P, MC, st) not in ["", "path", "road", "plant", "eave"]:
						continue
					var f := (c - st).normalized()
					var back := st - f * 3.6
					var hs := S.h(st.x, st.y)
					if is_nan(S.h(back.x, back.y)) or is_nan(hs) or S.h(back.x, back.y) - hs > 0.8 or absf(hs - S.h(c.x, c.y)) > 2.0:
						continue
					var cam := Vector3(back.x, hs + 2.2, back.y)
					var tgt := Vector3(c.x, S.h(c.x, c.y) + 0.3, c.y)
					var clear := true
					for t2 in range(1, 12):
						var q3 := cam.lerp(tgt, t2 / 12.0)
						var th2 := S.h(q3.x, q3.z)
						if not is_nan(th2) and th2 > q3.y - 0.25:
							clear = false
					for tr: Array in MC["trees"]:
						if not clear:
							break
						var tp: Vector2 = tr[0]
						if tp.distance_to(back) < float(tr[1]) + 1.0:
							clear = false
						elif Geometry2D.get_closest_point_to_segment(tp, back, back.lerp(c, 0.6)).distance_to(tp) < float(tr[1]) * 0.6:
							clear = false
					if MD.inside(back) and VL.wall_d(P["CV"], back) < 0.6:
						clear = false
					if not clear:
						continue
					var n2 := 0
					for t in range(-2, 3):
						var q := st + f * float(t)
						n2 += int(Hall.get(Vector2i(floori(q.x / 2.0), floori(q.y / 2.0)), 0))
					if best.is_empty() or n2 < int(best[0]):
						best = [n2, st]
				if best.is_empty():
					break
				var s2: Vector2 = best[1]
				pair.append(["%s_%d_%s" % [an, picked + 1, "near" if rr < 10.0 else "mid"], snappedf(s2.x, 0.1), snappedf(s2.y, 0.1), snappedf(c.x, 0.1), snappedf(c.y, 0.1), -0.2 if rr < 10.0 else -0.16, 3.6, 1.4])
			if pair.size() == 2:
				views.append_array(pair)
				used.append(c)
				picked += 1
		info("機位 %s：%d か所" % [an, picked])
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(views, " "))
	f.close()
	info("審圖機位 %d → %s" % [views.size(), out_path])


# ─────────────────────────── 封存（R5-3） ───────────────────────────

func _seal_mismatch(seal: Dictionary) -> PackedStringArray:
	var repo := (ProjectSettings.globalize_path("res://") + "..").simplify_path() + "/"
	var docs := repo + "docs/art_review/village_v2_p9_vegetation/"
	var bad := PackedStringArray()
	for grp: String in ["frozen", "art_review_images", "evidence"]:
		var d: Dictionary = seal[grp]
		for k: String in d:
			var path: String = (repo + k) if grp == "frozen" else (docs + k)
			if not FileAccess.file_exists(path):
				bad.append("%s 不存在" % k)
			elif FileAccess.get_sha256(path) != String(d[k]):
				bad.append("%s 雜湊變了" % k)
	return bad


func _seal() -> int:
	var seal: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SEAL))
	var bad := _seal_mismatch(seal)
	var n: int = seal["frozen"].size() + seal["art_review_images"].size() + seal["evidence"].size()
	check("P9 R5-3 封存 %d 檔雜湊一致（凍結 %d、ART_REVIEW 圖 %d、證據 %d；不符 %d：%s）" % [n, seal["frozen"].size(),
		seal["art_review_images"].size(), seal["evidence"].size(), bad.size(), ", ".join(bad.slice(0, 4))], bad.is_empty())
	var txt := FileAccess.get_file_as_string(SCENE)
	var idx: Array = []
	for nm: String in ORDER:
		idx.append(txt.find("[node name=\"%s\" parent=\"Vegetation\"" % nm))
	var ord_ok: bool = int(idx[0]) >= 0
	for k in range(1, idx.size()):
		ord_ok = ord_ok and int(idx[k]) > int(idx[k - 1])
	check("village_v2.tscn 掛載 Vegetation/%s（%s）" % [" → ".join(ORDER), MD.OUTPUT], ord_ok and txt.contains(MD.OUTPUT))
	var sh := FileAccess.get_file_as_string(MD.SHADER)
	check("風：wind_strength 既定値＝%s（P9 最終値、使用者裁定）" % seal["wind_strength"], sh.contains("uniform float wind_strength = %s;" % seal["wind_strength"]))
	var neg_seal := seal.duplicate(true)
	var k0: String = neg_seal["frozen"].keys()[0]
	neg_seal["frozen"][k0] = "0".repeat(64)
	var nb := _seal_mismatch(neg_seal)
	check("反向：竄改 %s 期望雜湊 → 偵測到 1 筆不符（實際 %d）" % [k0, nb.size() - bad.size()], nb.size() == bad.size() + 1)
	print("[MDW] 結果：%d 項失敗（seal）" % fails)
	return fails


# ─────────────────────────── 掛載・場景 ───────────────────────────

func _attach() -> int:
	var txt := FileAccess.get_file_as_string(SCENE)
	if not FileAccess.file_exists(MD.OUTPUT):
		push_error("找不到 %s（先 --build 成功才可 attach）" % MD.OUTPUT)
		return 1
	if txt.contains("gen/meadow_p9.scn"):
		print("[MDW] attach：已掛 MeadowP9（不重複、不寫場景）")
		return 0
	var nl := "\r\n" if txt.contains("\r\n") else "\n"
	var lines := txt.split(nl)
	var out := PackedStringArray()
	var done := false
	var i := 0
	while i < lines.size():
		var ln := lines[i]
		out.append(ln)
		if not done and ln.begins_with("[node name=\"GroundcoverP9\" parent=\"Vegetation\""):
			i += 1
			while i < lines.size() and not lines[i].begins_with("["):
				out.append(lines[i])
				i += 1
			out.append("[node name=\"%s\" parent=\"Vegetation\" instance=ExtResource(\"p9r53_meadow\")]" % MD.NODE_NAME)
			out.append("")
			done = true
			continue
		i += 1
	if not done:
		push_error("找不到 Vegetation/GroundcoverP9")
		return 1
	var last_ext := -1
	for k in out.size():
		if out[k].begins_with("[ext_resource"):
			last_ext = k
	out.insert(last_ext + 1, "[ext_resource type=\"PackedScene\" path=\"%s\" id=\"p9r53_meadow\"]" % MD.OUTPUT)
	var f := FileAccess.open(SCENE, FileAccess.WRITE)
	f.store_string(nl.join(out))
	f.close()
	print("[MDW] attach：加 Vegetation/%s（GroundcoverP9 之後）→ %s" % [MD.NODE_NAME, SCENE])
	return 0


func _scene(v: Node3D) -> void:
	var go := v.get_node_or_null("Vegetation/" + MD.NODE_NAME) as Node3D
	var names: Array = []
	for c in v.get_node("Vegetation").get_children():
		names.append(String(c.name))
	var ok := true
	for k in ORDER.size() - 1:
		if not (ORDER[k] in names and ORDER[k + 1] in names) or names.find(ORDER[k]) > names.find(ORDER[k + 1]):
			ok = false
	check("場景已掛 Vegetation/%s（1 個），順序 %s" % [MD.NODE_NAME, " → ".join(ORDER)], go != null and ok and names.count(MD.NODE_NAME) == 1)
	if go == null:
		return
	check("art_revision＝%s、visible" % go.get_meta("art_revision", "?"), String(go.get_meta("art_revision", "")) == MD.ART_REVISION and go.visible)
	var n_cs := go.find_children("*", "CollisionShape3D", true, false).size()
	var nn := go.get_node("Near").get_child_count()
	var nm := go.get_node("Mid").get_child_count()
	var lv_ok := true
	for c in go.get_node("Near").get_children():
		lv_ok = lv_ok and (c as GeometryInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON and String(((c as GeometryInstance3D).material_override as ShaderMaterial).shader.resource_path) == MD.SHADER
	for c in go.get_node("Mid").get_children():
		lv_ok = lv_ok and (c as GeometryInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and String(((c as GeometryInstance3D).material_override as ShaderMaterial).shader.resource_path) == MD.SHADER
	check("近級 %d 節點（影あり）＋中級 %d 節點（影なし）、meadow_grass shader、碰撞 %d（立ち草は碰撞なし）" % [nn, nm, n_cs], nn > 0 and nm > 0 and n_cs == 0 and lv_ok)
	var zr := MMG.audit_node(go)
	if not bool(zr["display"]):
		info("MultiMesh instance 矩陣：headless 讀不到（非 headless 跑 --scene 才檢查）")
	else:
		check("永久 build rule：場景中 MeadowP9 全部 instance transform 非零（%s）" % MMG.summary(zr), MMG.ok(zr))
	var gc := v.get_node_or_null("Vegetation/GroundcoverP9")
	check("封存 GroundcoverP9 仍掛載・visible・%s" % GC.OUTPUT, gc != null and gc.visible and gc.scene_file_path == GC.OUTPUT)
	info("Props/MarketP10（並行中の P10）：%s" % ("掛載中" if v.get_node_or_null("Props/MarketP10") != null else "なし"))


# ─────────────────────────── 成本（INFO、非 headless）───────────────────────────

func _cost(v: Node3D) -> void:
	if not MMG.display_ok():
		info("--cost は rendering display が必要（headless 不可）")
		return
	for nm in ["Debug", "Portals", "QuestAnchors"]:
		if v.has_node(nm):
			v.get_node(nm).visible = false
	for c in root.get_children():
		if c.has_method("set_hour"):
			c.set_hour(10.0)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var vp := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.far = 900.0
	root.add_child(cam)
	cam.make_current()
	var g := v.get_node("Vegetation/" + MD.NODE_NAME) as Node3D
	var views: Array = JSON.parse_string(FileAccess.get_file_as_string(VIEWS))
	var sp := v.get_world_3d().direct_space_state
	for i in 30:
		await process_frame
	var worst := 0.0
	for vw in views:
		var pp := Vector2(float(vw[1]), float(vw[2]))
		var tt := Vector2(float(vw[3]), float(vw[4]))
		var q := PhysicsRayQueryParameters3D.create(Vector3(pp.x, 60.0, pp.y), Vector3(pp.x, -20.0, pp.y))
		var gy := 0.0
		var ex: Array[RID] = []
		for k in 12:
			q.exclude = ex
			var hit := sp.intersect_ray(q)
			if hit.is_empty():
				break
			if String((hit.collider as Node).name).begins_with("TerrainCollision"):
				gy = hit.position.y
				break
			ex.append(hit.rid)
		var f := (tt - pp).normalized()
		var side := Vector2(-f.y, f.x)
		var pitch := float(vw[5])
		var piv := Vector3(pp.x, gy + 1.6, pp.y) + Vector3(side.x, 0.0, side.y) * float(vw[7]) * 0.5
		var look := Vector3(f.x * cos(pitch), sin(pitch), f.y * cos(pitch))
		var cp := piv - look * float(vw[6]) + Vector3(side.x, 0.0, side.y) * float(vw[7]) * 0.5
		cam.global_transform = Transform3D(Basis(), cp).looking_at(cp + look, Vector3.UP)
		var t := {true: [], false: []}
		for rep in 3:
			for vis in [false, true]:
				g.visible = vis
				for i in 20:
					await process_frame
				var acc := 0.0
				for i in 40:
					await process_frame
					acc += RenderingServer.viewport_get_measured_render_time_gpu(vp)
				t[vis].append(acc / 40.0)
		(t[true] as Array).sort()
		(t[false] as Array).sort()
		var on: float = t[true][1]
		var off: float = t[false][1]
		worst = maxf(worst, on - off)
		info("cost %s：GPU OFF %.2f ms → ON %.2f ms（%+.2f ms、3 回の中央値）" % [vw[0], off, on, on - off])
	g.visible = true
	info("cost：最差の機位 %+.2f ms（Forward+、%s、VSync off；INFO＝P12 資料、catastrophic のみ阻止；並行する他の Godot 行程があると汚染される）" % [worst, str(DisplayServer.window_get_size())])


# ─────────────────────────── 診斷地図 ───────────────────────────

func _maps(P: Dictionary, MC: Dictionary, M: Dictionary, dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var F: Dictionary = M["F"]
	var nx: int = F["nx"]
	var nz: int = F["nz"]
	var s := 2
	var img := Image.create(nx * s, nz * s, false, Image.FORMAT_RGB8)
	var blk: PackedByteArray = F["blk"]
	var aS: PackedFloat32Array = F["S"]
	for j in nz:
		for i in nx:
			var k := j * nx + i
			var c := Color(0.1, 0.1, 0.1) if blk[k] == 1 else Color(0.32, 0.28, 0.22).lerp(Color(0.26, 0.36, 0.2), aS[k])
			img.fill_rect(Rect2i(i * s, j * s, s, s), c)
	var cols := [Color(0.62, 0.8, 0.4), Color(0.25, 0.75, 0.25), Color(0.0, 0.5, 0.05), Color(0.85, 0.55, 0.95), Color(0.95, 0.85, 0.3), Color(0.2, 0.85, 0.8), Color(0.95, 1.0, 0.7), Color(0.0, 0.25, 0.25), Color(0.15, 0.3, 0.75)]
	var o: Vector2 = F["o"]
	var aP: PackedVector2Array = M["p"]
	var aK: PackedByteArray = M["k"]
	for i in int(M["n"]):
		var q := (aP[i] - o) * s
		var x := int(q.x)
		var z := int(q.y)
		if x >= 0 and z >= 0 and x < img.get_width() and z < img.get_height():
			img.set_pixel(x, z, cols[aK[i]])
	img.save_png(dir.path_join("meadow_village_map.png"))
	info("診斷地図 → %s（2 px/m、灰＝禁區、地＝語意密度、點＝株の種）" % dir)

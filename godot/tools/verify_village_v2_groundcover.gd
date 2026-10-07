extends SceneTree
## 人間之里 V2 P9 R5 Groundcover：Pilot 4 區（r10f ART_APPROVED、凍結）＋全村擴張（R5-2）の規劃 gate＋烘焙＋掛載＋場景級驗證。
##   Pilot gate（既存 15 項）は Pilot 部分だけ、全村 gate（[全村] 項）は擴張部分だけを見る。Pilot r10f の規劃・地面 digest 不一致＝FAIL。
##   規劃＋gate（唯讀）：Godot --headless --path godot --script res://tools/verify_village_v2_groundcover.gd
##   反向：             ... -- --negatives（sealed／road／grid／ring／forest／water 各自瞄準項 FAIL）
##   烘焙 overlay：     ... -- --build
##   掛進場景：         ... -- --attach（在 Vegetation/KirisameP9 後加 GroundcoverP9；先確認 Editor 無 unsaved、F5 已停）
##   場景驗證：         ... -- --scene（掛載順序、MultiMesh 分塊、無碰撞、接地抽樣）
## 每項一行 [GC] PASS/FAIL；INFO 不計失敗；結尾 quit(失敗項數)。

const GC := preload("res://tools/village_v2_groundcover_lib.gd")
const RLib := preload("res://tools/village_v2_riverbank_lib.gd")
const MMG := preload("res://tools/village_v2_mm_bake_guard.gd")
const VL := preload("res://tools/village_v2_groundcover_village.gd")
const ML := preload("res://tools/village_v2_groundcover_macro.gd")
const MVL := preload("res://tools/village_v2_groundcover_mvillage.gd")
const SCENE := "res://maps/village_v2/village_v2.tscn"
const REPORT := "res://data/village_v2_p9r5_groundcover.json"
const SEAL := "res://data/village_v2_p9r5_seal.json"
const ORDER := ["ForestP9", "BambooP9", "HiedaGardenP9", "ShrineGroveP9", "SchoolYardP9", "WatersideP9", "TowerYardP9", "SuzunaanP9", "GeidonteiP9", "KirisameP9", "GroundcoverP9"]

var fails := 0
var failed_labels: Array = []
var quiet := false


func check(label: String, ok: bool) -> void:
	if not quiet:
		print("[GC] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		fails += 1
		failed_labels.append(label)


func info(label: String) -> void:
	if not quiet:
		print("[GC] INFO " + label)


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
		await _scene(v)
		print("[GC] 結果：%d 項失敗（scene）" % fails)
		quit(fails)
		return
	var old := v.get_node_or_null("Vegetation/" + GC.NODE_NAME)
	if old:
		old.get_parent().remove_child(old)
		old.free()
	root.add_child(v)
	await physics_frame
	var P: Dictionary = GC.plan(v)
	VL.extend(P, v)
	ML.extend(P, v)
	MVL.extend(P, v)
	var MVc: Dictionary = P["MV"]
	info("規劃 Pilot %d＋全村 r5（林緣・溪岸）%d＋Macro Pilot %d＋全村 Macro %d MultiMesh instance、Pilot %d＋全村 %d 節點（Pilot %d ms、全村 r5 %d ms、Macro Pilot %d ms、全村 Macro %d ms）" % [
		P["n_pilot_items"], int(P["n_village_items"]) - int(P["n_pilot_items"]), int(P["n_macro_items"]) - int(P["n_village_items"]), (P["items"] as Array).size() - int(P["n_macro_items"]),
		P["n_pilot_nodes"], int(P["n_village_nodes"]) - int(P["n_pilot_nodes"]), P["ms"], P["ms_village"], P["ms_macro"], P["ms_mv"]])
	info("全村 Macro：壁 %d 面、背戸 %d、小径 %d、作業地面・踏み荒らし %d、交差・巷口・轉角 %d、街區 %d、小區 %d" % [(MVc["walls"] as Array).size(), (MVc["doors"] as Array).size(),
		(MVc["paths"] as Array).size(), (MVc["spots"] as Array).size(), (MVc["xs"] as Array).size(), (MVc["blocks"] as Array).size(), (MVc["seeds"] as Array).size()])
	if "--negatives" in args:
		var target := {"sealed": "禁區", "road": "禁區", "grid": "開闊草地", "ring": "牆腳", "forest": "林緣", "water": "水際", "bare": "樹根", "dirt": "地形語意", "band": "邊界",
			"isolated": "水際", "flatbank": "溪岸地面", "nofloor": "林床", "lawnfill": "土場語意", "coredeep": "溪岸 P7 核心淡入"}
		var bad := 0
		# GC_NEG_ONLY=名前,名前 で反向を絞る（診断用；正式の記錄は全件）
		var only := OS.get_environment("GC_NEG_ONLY")
		var Pp := _pilot_view(P)
		for nm: String in target:
			if only != "" and not (nm in only.split(",")):
				continue
			var P2 := Pp.duplicate()
			P2["items"] = (Pp["items"] as Array).duplicate(true)
			P2["nodes"] = (Pp["nodes"] as Array).duplicate(true)
			fails = 0
			failed_labels.clear()
			quiet = true
			_inject(P2, nm)
			_checks(P2)
			quiet = false
			var hit := failed_labels.any(func(l: String) -> bool: return l.begins_with(String(target[nm])))
			print("[GC] %s 反向 %s → 「%s」必須 FAIL（失敗項 %d）" % ["PASS" if hit else "FAIL", nm, target[nm], failed_labels.size()])
			if not hit:
				bad += 1
		# 全村の反向（擴張部分）
		# 一般類の 4 案（v_grid／v_ring／v_dirtfill／v_trodden）は一般類の退役（P9 R5 Macro Expansion）に伴い全村 Macro の反向（mv_*）へ置換
		var vtarget := {"v_sealed": "[全村] 禁區", "v_farm": "[全村] 禁區", "v_forest": "[全村] 林緣",
			"v_nofloor": "[全村] 林床", "v_isolated": "[全村] 水際", "v_coredeep": "[全村] 溪岸 P7", "v_freeze": "[全村] Pilot r10f 凍結", "v_p7piece": "[全村] 禁區"}
		var dg: Array = VL.pilot_digest(P, true)
		for nm: String in vtarget:
			if only != "" and not (nm in only.split(",")):
				continue
			var P3 := P.duplicate()
			P3["items"] = (P["items"] as Array).slice(0, int(P["n_village_items"])).duplicate(true)
			P3["nodes"] = (P["nodes"] as Array).slice(0, int(P["n_village_nodes"])).duplicate(true)
			P3.erase("n_village_items")
			P3.erase("n_village_nodes")
			P3["_ground_sha"] = dg[1]
			fails = 0
			failed_labels.clear()
			quiet = true
			_vinject(P3, nm)
			_vchecks(P3)
			quiet = false
			var hit2 := failed_labels.any(func(l: String) -> bool: return l.begins_with(String(vtarget[nm])))
			print("[GC] %s 反向 %s → 「%s」必須 FAIL（失敗項 %d）" % ["PASS" if hit2 else "FAIL", nm, vtarget[nm], failed_labels.size()])
			if not hit2:
				bad += 1
		# Macro Pilot の反向
		var mtarget := {"m_sealed": "[Macro] 禁區", "m_p7": "[Macro] 禁區", "m_fill": "[Macro] 留白", "m_tiny": "[Macro] 主角＝地面",
			"m_speckle": "[Macro] 尺度", "m_ring": "[Macro] C 牆腳", "m_noditch": "[Macro] B 交界序列", "m_nopath": "[Macro] B 交界序列"}
		for nm: String in mtarget:
			if only != "" and not (nm in only.split(",")):
				continue
			var P4 := P.duplicate()
			P4["items"] = (P["items"] as Array).slice(0, int(P["n_macro_items"])).duplicate(true)
			P4.erase("n_macro_items")
			P4["M"] = (P["M"] as Dictionary).duplicate(true)
			fails = 0
			failed_labels.clear()
			quiet = true
			_minject(P4, nm)
			_mchecks(P4)
			quiet = false
			var hit3 := failed_labels.any(func(l: String) -> bool: return l.begins_with(String(mtarget[nm])))
			print("[GC] %s 反向 %s → 「%s」必須 FAIL（失敗項 %d）" % ["PASS" if hit3 else "FAIL", nm, mtarget[nm], failed_labels.size()])
			if not hit3:
				bad += 1
		# 全村 Macro（MV）・可見最上面（Surface）・m9 凍結の反向
		var m9g: String = MVL.m9_digest(P, true)[1]
		var mvtarget := {"mv_sealed": "[MV] 禁區", "mv_farm": "[MV] 禁區", "mv_road": "[MV] 路肩", "mv_fill": "[MV] 主角＝地面", "mv_tiny": "[MV] 主角＝地面",
			"mv_speckle": "[MV] 尺度", "mv_ring": "[MV] 後院牆腳", "mv_fixedband": "[MV] 農田交界", "mv_noditch": "[MV] 農田交界", "mv_uniform": "[MV] 語意分類",
			"mv_nolift": "[Surface] 可見最上面", "mv_m9": "[Macro Pilot] m9 凍結"}
		for nm: String in mvtarget:
			if only != "" and not (nm in only.split(",")):
				continue
			var P5 := P.duplicate()
			P5["items"] = (P["items"] as Array).duplicate(true)
			P5["_m9_ground_sha"] = m9g
			fails = 0
			failed_labels.clear()
			quiet = true
			_mvinject(P5, nm)
			if nm == "mv_nolift":
				_schecks(P5)
			else:
				_mvchecks(P5)
			quiet = false
			var hit5 := failed_labels.any(func(l: String) -> bool: return l.begins_with(String(mvtarget[nm])))
			print("[GC] %s 反向 %s → 「%s」必須 FAIL（失敗項 %d%s）" % ["PASS" if hit5 else "FAIL", nm, mvtarget[nm], failed_labels.size(), "" if hit5 else "：" + " ／ ".join(failed_labels.map(func(l: String) -> String: return l.left(40)))])
			if not hit5:
				bad += 1
		print("[GC] 結果：%d 項失敗（negatives）" % bad)
		quit(bad)
		return
	var rep := _checks(_pilot_view(P))
	rep["village"] = _vchecks(P)
	rep["macro"] = _mchecks(P)
	rep["mvillage"] = _mvchecks(P)
	rep["surface"] = _schecks(P)
	if "--build" in args and fails == 0:
		# --headless 的 dummy RenderingServer 存檔不寫 MultiMesh 實例資料（instance 數與 AABB 在、矩陣全 0 → 全部看不見）
		#   → --build 必須非 headless（與 P8 farmland 同）
		check("永久 build rule：MultiMesh build 需要 rendering display（--build 不可加 --headless）", MMG.display_ok())
	if "--build" in args and fails == 0:
		var tb := Time.get_ticks_msec()
		# 可見最上面ルール：Pilot・全村 r5 の items／nodes は烘焙用の複製で持ち上げ、地面網格は烘焙後に持ち上げる
		# P9 R5 限定解封（P10 R1b、使用者授權 2026-10-05）：路地 1 の歩く芯から地被 instance を除いた複製で烘焙（規劃・digest は不變）
		var Pb := MVL.p10_clear(MVL.surface_copy(P))
		var cut: Dictionary = Pb["p10_cleared"]
		var r := VL.bake_all(Pb)
		ML.bake_macro(P, r)
		MVL.bake_mv(P, r)
		var nl := MVL.lift_ground(P, r)
		info("烘焙 %d ms（全村 r5 地面 %d 區塊・%d 頂點；Macro Pilot 地面 %d 頂點；全村 Macro 地面 %d 區塊・%d 頂點；可見最上面へ持ち上げた Pilot／r5 地面頂點 %d）" % [Time.get_ticks_msec() - tb,
			r.get_meta("village_ground_chunks"), r.get_meta("village_ground_verts"), r.get_meta("macro_ground_verts"), r.get_meta("mv_ground_chunks"), r.get_meta("mv_ground_verts"), nl])
		_vground_audit(P, r)
		_mground_audit(P, r)
		_mvground_audit(P, r)
		_surface_audit(P, r)
		var left := MVL.p10_audit(r)
		check("[P10 限定解封] 路地 1 の歩く芯（%s）：烘焙後の地被 instance %d（= 0）、除いた instance Pilot %d・全村 r5 %d・Macro Pilot %d・全村 Macro %d（規劃 digest は不變）" % [
			str(MVL.P10_CLEAR), left, cut["pilot"], cut["village"], cut["macro"], cut["mv"]], left == 0 and int(cut["mv"]) > 0)
		r.set_meta("p10_cleared", cut)
		if fails > 0:
			# 地面の獨立檢查が FAIL のときは存檔しない（壊れた overlay を磁碟に残さない）
			r.free()
			print("[GC] 結果：%d 項失敗（存檔しない）" % fails)
			quit(fails)
			return
		GC.own(r, r)
		var ps := PackedScene.new()
		check("pack overlay", ps.pack(r) == OK)
		check("save %s" % GC.OUTPUT, ResourceSaver.save(ps, GC.OUTPUT, ResourceSaver.FLAG_COMPRESS) == OK)
		var rb := MMG.audit_saved_scene(GC.OUTPUT)
		check("永久 build rule：存檔後回讀 overlay，全部 instance transform 非零（%s）" % MMG.summary(rb), MMG.ok(rb))
		rep["overlay"] = {"path": GC.OUTPUT, "mb": FileAccess.get_file_as_bytes(GC.OUTPUT).size() / 1048576.0, "items": r.get_meta("items"),
			"nodes": r.get_meta("nodes"), "multimesh_nodes": r.get_meta("multimesh_nodes"), "village_ground_chunks": r.get_meta("village_ground_chunks"), "village_ground_verts": r.get_meta("village_ground_verts")}
		info("overlay %.2f MB、instance %d、節點 %d、MultiMesh 分塊節點 %d" % [rep["overlay"]["mb"], rep["overlay"]["items"], rep["overlay"]["nodes"], rep["overlay"]["multimesh_nodes"]])
		r.free()
		var f := FileAccess.open(REPORT, FileAccess.WRITE)
		f.store_string(JSON.stringify(rep, "  ", false))
		f.close()
	print("[GC] 結果：%d 項失敗" % fails)
	quit(fails)


func _inject(P: Dictionary, nm: String) -> void:
	var C: Dictionary = P["C"]
	var S: RLib.TriSampler = C["S"]
	var items: Array = P["items"]
	match nm:
		"sealed":
			var s: Array = (C["sealed"] as Array)[0]
			var q := (s[1] as Rect2).get_center()
			items.append(GC.gi(S, GC.K_FINE, q, 0.3, 1.0, 0.0, Color(1, 1, 1), "lawn", "tuft"))
		"road":
			var sg: Array = GC.ZONES["street"]["segs"][0]
			var q := ((sg[0] as Vector2) + (sg[1] as Vector2)) * 0.5
			items.append(GC.gi(S, GC.K_FINE, q, 0.3, 1.0, 0.0, Color(1, 1, 1), "street", "tuft"))
		"grid":
			var rect: Rect2 = GC.ZONES["lawn"]["rect"]
			var x := rect.position.x + 0.5
			while x < rect.end.x:
				var z := rect.position.y + 0.5
				while z < rect.end.y:
					var q := Vector2(x, z)
					if GC.blocked(C, q) == "":
						items.append(GC.gi(S, GC.K_FINE, q, 0.3, 1.0, 0.0, Color(1, 1, 1), "lawn", "tuft"))
					z += 1.2
				x += 1.2
		"ring":
			for o: Dictionary in C["obb"]:
				var cz := GC.zone_of(o["o"])
				if cz == "":
					continue
				var hh: Vector2 = o["h"]
				var t := -1.0
				while t <= 1.0:
					for q in [Vector2(t * hh.x, -hh.y - 0.3), Vector2(t * hh.x, hh.y + 0.3)]:
						var w: Vector2 = (o["o"] as Vector2) + (o["bx"] as Vector2) * q.x + (o["bz"] as Vector2) * q.y
						items.append(GC.gi(S, GC.K_ROSETTE, w, 1.0, 1.0, 0.0, Color(1, 1, 1), cz, "wallfoot"))
					t += 0.05
				var t2 := -1.0
				while t2 <= 1.0:
					for q in [Vector2(-hh.x - 0.3, t2 * hh.y), Vector2(hh.x + 0.3, t2 * hh.y)]:
						var w: Vector2 = (o["o"] as Vector2) + (o["bx"] as Vector2) * q.x + (o["bz"] as Vector2) * q.y
						items.append(GC.gi(S, GC.K_ROSETTE, w, 1.0, 1.0, 0.0, Color(1, 1, 1), cz, "wallfoot"))
					t2 += 0.05
				break
		"forest":
			# 外側（林緣 10–14 m）を林縁より密にする
			var fr: Rect2 = GC.ZONES["forest"]["rect"]
			var x := fr.position.x
			while x < fr.end.x:
				var z := fr.position.y
				while z < fr.end.y:
					var q := Vector2(x, z)
					var fd := GC.forest_d(C, q)
					if fd > 10.0 and fd < 14.0 and GC.blocked(C, q) == "":
						items.append(GC.gi(S, GC.K_FINE, q, 0.3, 1.0, 0.0, Color(1, 1, 1), "forest", "tuft"))
					z += 0.5
				x += 0.5
		"isolated":
			# 蘆を 1 本だけ群落から 8 m 岸沿いに離す（孤立單叢）
			for n: Dictionary in P["nodes"]:
				if String(n["id"]).begins_with("wk_reed"):
					var q: Vector2 = n["p"]
					var tg := GC.wgrad(C, q)
					var far := q + Vector2(-tg.y, tg.x) * 8.0
					n["p"] = far
					break
		"flatbank":
			P["_neg_flat_bank"] = true
		"coredeep":
			# 核心の奥（水際まで）と P7 構件の上にも描く
			P["_neg_core_deep"] = true
		"nofloor":
			P["_neg_no_floor"] = true
		"lawnfill":
			# 土場全体に 1.2 m 間隔で草叢（均一な草坪化）
			var rect: Rect2 = GC.ZONES["lawn"]["rect"]
			var x := rect.position.x
			while x < rect.end.x:
				var z := rect.position.y
				while z < rect.end.y:
					var q := Vector2(x, z)
					if GC.blocked(C, q) == "" and GC.grass_w(C, q) >= 0.0 and GC.grass_w(C, q) < GC.GRASS_MIN:
						items.append(GC.gi(S, GC.K_SHORT, q, 0.25, 1.0, 0.0, Color(1, 1, 1), "lawn", "dirt"))
					z += 1.2
				x += 1.2
		"band":
			# 境界に沿って草叢の帯（全區間）
			for zn in ["street", "lawn"]:
				var bbz := GC.zone_bbox(zn)
				var ex := bbz.position.x
				while ex < bbz.end.x:
					var ez := bbz.position.y
					while ez < bbz.end.y:
						var q := Vector2(ex, ez)
						var gw := GC.grass_w(C, q)
						if GC.zone_of(q) == zn and gw >= 0.45 and gw <= 0.6 and GC.blocked(C, q) == "":
							items.append(GC.gi(S, GC.K_FINE, q, 0.3, 1.0, 0.0, Color(1, 1, 1), zn, "tuft"))
						ez += 0.7
					ex += 0.7
		"dirt":
			# 地形が土・路肩の所に草叢を立てる
			var rect: Rect2 = GC.ZONES["lawn"]["rect"]
			var k := 0
			var x := rect.position.x
			while x < rect.end.x and k < 60:
				var z := rect.position.y
				while z < rect.end.y and k < 60:
					var q := Vector2(x, z)
					if GC.blocked(C, q) == "" and GC.grass_w(C, q) >= 0.0 and GC.grass_w(C, q) < 0.2:
						items.append(GC.gi(S, GC.K_FINE, q, 0.3, 1.0, 0.0, Color(1, 1, 1), "lawn", "tuft"))
						k += 1
					z += 1.0
				x += 1.0
		"bare":
			# 根元を埋める
			for t: Dictionary in (C["trees"] as Array).slice(0, 40):
				items.append(GC.gi(S, GC.K_MOSS, (t["p"] as Vector2) + Vector2(0.15, 0.0), 1.0, 1.0, 0.0, Color(1, 1, 1), "forest", "root"))
		"water":
			for n: Dictionary in P["nodes"]:
				if String(n["id"]).begins_with("wk_reed"):
					n["p"] = (n["p"] as Vector2) + Vector2(14.0, 0.0)


func _checks(P: Dictionary) -> Dictionary:
	var C: Dictionary = P["C"]
	var S: RLib.TriSampler = C["S"]
	var items: Array = P["items"]
	var nodes: Array = P["nodes"]
	var rep := {"date": Time.get_datetime_string_from_system(), "items": items.size(), "nodes": nodes.size(), "stats": P["stats"]}
	# ── 1 接地：instance 底＝地表 −0.01〜−0.03、節點＝地表 −0.02〜−0.03
	var fl := 0
	for it: Dictionary in items + nodes:
		var p: Vector2 = it["p"]
		var dy := float(it["y"]) - S.h(p.x, p.y)
		if dy > 0.005 or dy < -0.06:
			fl += 1
	check("接地：%d 件（MultiMesh instance 底・植物節點 origin vs 地表）偏差超出 %d" % [items.size() + nodes.size(), fl], fl == 0)
	# ── 2 禁區：封存 overlay・P7 河岸・P8 農田・水面・建物・道路中央・障礙物（frontage 等）
	var bad: Array = []
	for it: Dictionary in items + nodes:
		var p: Vector2 = it["p"]
		if String(it.get("tag", "")) == "rootflare":
			continue                                # 樹根の張り出しは幹元から生える（禁區判定の外、接地は別に見る）
		var allow := String(it.get("zone", "")) == "street" and String(it.get("tag", "")) == "tuft"
		var why := GC.blocked(C, p, allow)
		if why == "" and String(it.get("kind", "")) == "tree":
			var r := 0.35 * (it["sc"] as Vector3).x
			for d in [Vector2(r, 0), Vector2(-r, 0), Vector2(0, r), Vector2(0, -r)]:
				var w2 := GC.blocked(C, p + d)
				if w2.begins_with("sealed") or w2 == "building" or w2 == "road":
					why = w2
		if why != "":
			bad.append("%s@(%.1f,%.1f)→%s" % [it.get("id", GC.KIND_NAMES[int(it.get("k", 0))]), p.x, p.y, why])
	check("禁區：封存 Hero composition／P7 河岸／P8 農田／水面／建物／路面中央 侵入 %d %s" % [bad.size(), ", ".join(bad.slice(0, 4))], bad.is_empty())
	# ── 3 開闊草地：留白（1 m 内に地被がある面積 ≤ 45 %、≥ 6 %）、群れ（最近鄰距離の変動係數 ≥ 0.6＝固定間隔でない）
	var rect: Rect2 = GC.ZONES["lawn"]["rect"]
	var lawn_pts: Array = []
	for it: Dictionary in items:
		if String(it["zone"]) == "lawn" and String(it["tag"]) in ["tuft", "flower"]:
			lawn_pts.append(it["p"])
	var cov := 0
	var tot := 0
	var cell := {}
	for q: Vector2 in lawn_pts:
		var k := Vector2i(floori(q.x), floori(q.y))
		if not cell.has(k):
			cell[k] = []
		cell[k].append(q)
	var gx := rect.position.x + 0.5
	while gx < rect.end.x:
		var gz := rect.position.y + 0.5
		while gz < rect.end.y:
			var q := Vector2(gx, gz)
			gz += 1.0
			if GC.blocked(C, q) != "" or GC.wall_d(C, q) < 1.2 or GC.grass_w(C, q) < GC.GRASS_MIN:
				continue
			tot += 1
			var hit := false
			for dx in [-1, 0, 1]:
				for dz in [-1, 0, 1]:
					for w: Vector2 in cell.get(Vector2i(floori(q.x) + dx, floori(q.y) + dz), []):
						if w.distance_to(q) < 1.0:
							hit = true
			if hit:
				cov += 1
		gx += 1.0
	var cov_r := float(cov) / maxf(1.0, tot)
	var nn: Array = []
	for i in range(0, lawn_pts.size(), 3):
		var q: Vector2 = lawn_pts[i]
		var best := 99.0
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				for w: Vector2 in cell.get(Vector2i(floori(q.x) + dx, floori(q.y) + dz), []):
					var d := w.distance_to(q)
					if d > 0.001:
						best = minf(best, d)
		if best < 99.0:
			nn.append(best)
	var mean := 0.0
	for d: float in nn:
		mean += d
	mean /= maxf(1.0, nn.size())
	var var_ := 0.0
	for d: float in nn:
		var_ += (d - mean) * (d - mean)
	var cv := sqrt(var_ / maxf(1.0, nn.size())) / maxf(mean, 1e-6)
	check("開闊草地：地形が草の面積のうち地被 1 m 圏 %.1f %%（6–45 %%＝大片留白）、最近鄰距離の變動係數 %.2f（≥ 0.6＝群れ、固定間隔でない）" % [cov_r * 100.0, cv],
		cov_r >= 0.06 and cov_r <= 0.45 and cv >= 0.6)
	rep["lawn"] = {"coverage": cov_r, "nn_cv": cv}
	# 近地層 micro（8–15 cm の低い株）は留白率の外：密度だけ上限を見る（≤ 0.3 株/m²＝鋪滿にしない）
	var n_micro := 0
	for it: Dictionary in items:
		if String(it["tag"]) == "micro":
			n_micro += 1
	var micro_d := n_micro / maxf(1.0, float(tot))
	check("開闊草地 近地層 micro：%d 株、草の面積あたり %.2f 株/m²（0.03–0.3＝疎ら、鋪滿にしない）" % [n_micro, micro_d], micro_d >= 0.03 and micro_d <= 0.3)
	# ── 4 牆腳：断続（各建物の周長のうち牆腳地被が 0.8 m 以内にある割合 ≤ 60 %、全体で ≥ 1 棟は有り）
	var wf: Array = []
	for it: Dictionary in items:
		if String(it["tag"]) == "wallfoot":
			wf.append(it["p"])
	var worst := 0.0
	var n_b := 0
	for o: Dictionary in C["obb"]:
		if GC.zone_of(o["o"]) == "" and not (GC.in_zone("street", o["o"]) or GC.in_zone("lawn", o["o"])):
			continue
		var hh: Vector2 = o["h"]
		var per := 0
		var got := 0
		for e in 4:
			for s in 20:
				var t := -1.0 + 2.0 * (s + 0.5) / 20.0
				var q: Vector2 = [Vector2(t * hh.x, -hh.y - 0.3), Vector2(hh.x + 0.3, t * hh.y), Vector2(-t * hh.x, hh.y + 0.3), Vector2(-hh.x - 0.3, -t * hh.y)][e]
				var w: Vector2 = (o["o"] as Vector2) + (o["bx"] as Vector2) * q.x + (o["bz"] as Vector2) * q.y
				per += 1
				for f: Vector2 in wf:
					if f.distance_to(w) < 0.8:
						got += 1
						break
		var r := float(got) / maxf(1.0, per)
		if got > 0:
			n_b += 1
		worst = maxf(worst, r)
	check("牆腳：建物周長の被覆 最大 %.0f %%（≤ 60 %%＝完整一圈にしない）、牆腳地被のある建物 %d 棟（≥ 1）" % [worst * 100.0, n_b], worst <= 0.6 and n_b >= 1)
	rep["wallfoot"] = {"worst": worst, "buildings": n_b}
	# ── 5 林緣：林緣距離（ForestP9 樹點基準）の帯ごとに被覆が漸密（外 9–15 m < 中 3.5–9 m < 縁 −1.5–3.5 m）、かつ蕨・笹・低木の被覆比率が林側で高い
	var bands := [[9.0, 15.0], [3.5, 9.0], [-1.5, 3.5]]
	var frect: Rect2 = GC.ZONES["forest"]["rect"]
	var b_area := [0.0, 0.0, 0.0]
	var fx := frect.position.x + 0.5
	while fx < frect.end.x:
		var fz := frect.position.y + 0.5
		while fz < frect.end.y:
			var q := Vector2(fx, fz)
			fz += 1.0
			if GC.blocked(C, q) != "":
				continue
			var fdq := GC.forest_d(C, q)
			for bi in 3:
				if fdq >= float(bands[bi][0]) and fdq < float(bands[bi][1]):
					b_area[bi] += 1.0
		fx += 1.0
	var dens: Array = []
	var shrub_r: Array = []
	for bi in 3:
		var b: Array = bands[bi]
		var n_all := 0.0
		var n_sh := 0.0
		for it: Dictionary in items + nodes:
			if String(it.get("zone", "")) != "forest" or String(it.get("tag", "")) == "root":
				continue
			var fd := GC.forest_d(C, it["p"])
			if fd >= float(b[0]) and fd < float(b[1]):
				var area := 0.12
				if String(it.get("kind", "")) == "tree":
					var sc := (it["sc"] as Vector3).x
					area = (1.6 if String(it["id"]) == "shrub_a" else 1.1) * sc * sc
				elif int(it.get("k", 0)) == GC.K_LITTER:
					area = 0.5
				n_all += area
				if String(it.get("kind", "")) == "tree":
					n_sh += area
		dens.append(n_all / maxf(float(b_area[bi]), 1.0))
		shrub_r.append(n_sh / maxf(1.0, n_all))
	check("林緣：被覆 外 %.3f → 中 %.3f → 縁 %.3f m²/m²（漸密；帯面積 %d／%d／%d m²）、蕨・笹・低木の被覆比率 %.0f %% → %.0f %% → %.0f %%" % [dens[0], dens[1], dens[2],
		b_area[0], b_area[1], b_area[2], shrub_r[0] * 100.0, shrub_r[1] * 100.0, shrub_r[2] * 100.0],
		dens[0] < dens[1] and dens[1] < dens[2] and shrub_r[0] <= shrub_r[1] and shrub_r[1] <= shrub_r[2] and b_area[0] > 50.0 and b_area[2] > 50.0)
	rep["forest"] = {"density": dens, "shrub_ratio": shrub_r, "band_area": b_area}
	# 樹根：裸根（幹から 0.4 m 以内に地被なし）
	var bare_bad := 0
	var n_flare := 0
	for it: Dictionary in items + nodes:
		if String(it.get("tag", "")) == "rootflare":
			n_flare += 1
			continue
		if GC.trunk_d(C, it["p"]) < 0.4:
			bare_bad += 1
	var n_root := 0
	for it: Dictionary in items:
		if String(it["tag"]) == "root":
			n_root += 1
	# 林縁の樹の overlay 輪：半徑 0.6／1.0／1.4 m × 8 方位の（苔＋腐植＋落葉）平均 ≥ 0.5、襟（0.6–0.9 m）の苔 ≥ 0.2
	var n_et := 0
	var n_ring := 0
	var ring_sum := 0.0
	for t: Dictionary in C["trees"]:
		var tp: Vector2 = t["p"]
		if not frect.grow(-4.0).has_point(tp):
			continue
		var edge := false
		for a in 8:
			if GC.forest_d(C, tp + Vector2(cos(a * TAU / 8.0), sin(a * TAU / 8.0)) * (float(t["cr"]) + 2.5)) > 0.0:
				edge = true
				break
		if not edge:
			continue
		n_et += 1
		var rs := 0.0
		var ms := 0.0
		for a in 8:
			var dv := Vector2(cos(a * TAU / 8.0), sin(a * TAU / 8.0))
			for rr in [0.6, 1.0, 1.4]:
				var w := GC.gwt(P, tp + dv * rr)
				rs += w[1] + w[4] + w[3]
			ms += GC.gwt(P, tp + dv * 0.75)[1]
		rs /= 24.0
		ms /= 8.0
		ring_sum += rs
		if rs >= 0.5 and ms >= 0.2:
			n_ring += 1
	var ring_r := float(n_ring) / maxf(1.0, n_et)
	check("樹根：林縁の樹 %d 本のうち overlay の苔・腐植・落葉の輪（平均 ≥ 0.5、苔の襟 ≥ 0.2）が立つ %d 本（%.0f %% ≥ 80 %%，輪の平均 %.2f）；張り出した根 %d 本（≥ 4 × 林縁の樹）；3D 根元組 %d（≥ 20）、樹幹 0.4 m 以内の 3D 地被（根以外）%d（0＝裸根を殘す）" % [
		n_et, n_ring, ring_r * 100.0, ring_sum / maxf(1.0, n_et), n_flare, n_root, bare_bad], n_et >= 5 and ring_r >= 0.8 and n_flare >= 4 * n_et and n_root >= 20 and bare_bad == 0)
	rep["roots"] = {"edge_trees": n_et, "ring_ok": n_ring}
	# ── 5b 林床（forest-floor-first）：① 林縁帯（樹點 fd −3〜1 m）の地面 overlay（落葉＋腐植＋苔＋土）≥ 0.4 が 70 % 以上、
	#     ② 林床の縁（地形 forest 層の境）から草側へのこぼれ幅：平均 ≥ 0.8 m、標準偏差 ≥ 0.5 m（尺で引いた平行帯にしない）、
	#     ③ 蕨・笹・低木は群落（2.2 m 以内に他 2 株以上が 70 % 以上）
	var nf := 0
	var nf_ok := 0
	var ffx := frect.position.x + 0.25
	while ffx < frect.end.x:
		var ffz := frect.position.y + 0.25
		while ffz < frect.end.y:
			var q := Vector2(ffx, ffz)
			ffz += 0.5
			if GC.zone_inset("forest", q) < 4.0 or GC.blocked(C, q) != "":
				continue
			var fdq := GC.forest_d(C, q)
			if fdq < -3.0 or fdq > 1.0:
				continue
			nf += 1
			var w := GC.gwt(P, q)
			if w[1] + w[2] + w[3] + w[4] >= 0.4:
				nf_ok += 1
		ffx += 0.5
	var spills: Array = []
	var sz := frect.position.y + 4.0
	while sz < frect.end.y - 4.0:
		# 各 z で林床の縁（seam_d が + から − に変わる所）を西から探し、そこから草側（−x）へ落葉 ≥ 0.3 の幅を測る
		var x0 := frect.position.x + 4.0
		var seam_x := INF
		while x0 < frect.end.x - 4.0:
			if GC.seam_d(C, Vector2(x0, sz)) >= 0.0:
				seam_x = x0
				break
			x0 += 0.25
		if seam_x < INF:
			var ext := 0.0
			var xx := seam_x
			while xx > seam_x - 6.0:
				var q := Vector2(xx, sz)
				if GC.blocked(C, q) != "" or GC.gwt(P, q)[3] < 0.3:
					break
				ext = seam_x - xx
				xx -= 0.2
			spills.append(ext)
		sz += 1.0
	var sm := 0.0
	for x: float in spills:
		sm += x
	sm /= maxf(1.0, spills.size())
	var sv := 0.0
	for x: float in spills:
		sv += (x - sm) * (x - sm)
	var ssd := sqrt(sv / maxf(1.0, spills.size()))
	var und: Array = []
	for n: Dictionary in nodes:
		if String(n.get("zone", "")) == "forest" and String(n.get("kind", "")) == "tree":
			und.append(n["p"])
	var clus := 0
	for q: Vector2 in und:
		var c2 := 0
		for w: Vector2 in und:
			if w != q and w.distance_to(q) < 2.2:
				c2 += 1
		if c2 >= 2:
			clus += 1
	var fr := float(nf_ok) / maxf(1.0, nf)
	var cr := float(clus) / maxf(1.0, und.size())
	check("林床：林縁帯の地面 overlay ≥ 0.4 が %.0f %%（≥ 70 %%，%d 點）、林床のこぼれ幅 平均 %.2f m（≥ 0.8）標準偏差 %.2f m（≥ 0.5，%d 斷面）、蕨・笹・低木の群落率 %.0f %%（≥ 70 %%，%d 株）" % [
		fr * 100.0, nf, sm, ssd, spills.size(), cr * 100.0, und.size()], nf > 50 and fr >= 0.7 and sm >= 0.8 and ssd >= 0.5 and cr >= 0.7)
	rep["forest_floor"] = {"cover": fr, "spill_mean": sm, "spill_sd": ssd, "cluster": cr}
	# ── 6 水際（r10）：蘆は數個の小群落（1.6 m 連結で 1 群 ≥ 5 株、群數 3–10、孤立單叢 0）、水からの距離 蘆 < 菅・花菖蒲 < 草叢、蘆は核心の外 0–1.8 m
	var reeds: Array = []
	var wd_of := {"reed": [], "bank": [], "tuft": []}
	for it: Dictionary in items + nodes:
		if String(it.get("zone", "")) != "stream":
			continue
		var tg := String(it.get("tag", ""))
		if wd_of.has(tg):
			(wd_of[tg] as Array).append(GC.wdist(C, it["p"]))
		if tg == "reed":
			reeds.append(it["p"])
	var lab := []
	lab.resize(reeds.size())
	lab.fill(-1)
	var n_col := 0
	for i0 in reeds.size():
		if lab[i0] >= 0:
			continue
		var stack := [i0]
		lab[i0] = n_col
		while not stack.is_empty():
			var a: int = stack.pop_back()
			for b in reeds.size():
				if lab[b] < 0 and (reeds[a] as Vector2).distance_to(reeds[b]) < 1.6:
					lab[b] = n_col
					stack.append(b)
		n_col += 1
	var sizes := []
	sizes.resize(n_col)
	sizes.fill(0)
	for l: int in lab:
		sizes[l] += 1
	var small := 0
	for z0: int in sizes:
		if z0 < 5:
			small += 1
	var mw := {}
	for k: String in wd_of:
		var a: Array = wd_of[k]
		var sm2 := 0.0
		for x: float in a:
			sm2 += x
		mw[k] = sm2 / maxf(1.0, a.size())
	var reed_max := 0.0
	for x: float in wd_of["reed"]:
		reed_max = maxf(reed_max, x)
	check("水際：蘆 %d 株＝%d 群落（各群 %s；5 株未滿の群・孤立 %d）、水面からの平均距離 蘆 %.1f m（最大 %.1f ≤ %.1f）< 菅・花菖蒲 %.1f m < 草叢 %.1f m" % [
		reeds.size(), n_col, str(sizes), small, mw["reed"], reed_max, GC.RB_CORE + 1.8, mw["bank"], mw["tuft"]],
		reeds.size() > 0 and n_col >= 3 and n_col <= 10 and small == 0 and reed_max <= GC.RB_CORE + 1.8 and float(mw["reed"]) < float(mw["bank"]) and float(mw["bank"]) < float(mw["tuft"]))
	rep["stream"] = {"mean_d": mw, "colonies": sizes}
	# ── 6b 溪岸地面（substrate-first）：① 核心の外 0.6–3.0 m の地面 overlay ≥ 0.5 が 85 % 以上（連續）、② 帯の順（卵石 < 泥 < 苔、重み付き平均距離）、
	#     ③ 泥帯の外縁が岸と平行な直線にならない（斷面ごとの外縁距離の標準偏差 ≥ 0.4 m）、④ 植物は點綴（植物の被覆 ≤ 地面帯の 15 %）
	var srect: Rect2 = GC.ZONES["stream"]["rect"]
	var ns := 0
	var ns_ok := 0
	var acc := {"peb": [0.0, 0.0], "mud": [0.0, 0.0], "moss": [0.0, 0.0]}
	var edges: Array = []
	var sx := srect.position.x + 0.25
	while sx < srect.end.x:
		var sz2 := srect.position.y + 0.25
		while sz2 < srect.end.y:
			var q := Vector2(sx, sz2)
			sz2 += 0.5
			if GC.zone_inset("stream", q) < 4.0 or GC.blocked(C, q) != "":
				continue
			var e := GC.wdist(C, q) - GC.RB_CORE
			if e < 0.0 or e > 7.0:
				continue
			var w := GC.gwt(P, q)
			if e >= 0.6 and e <= 3.0:
				ns += 1
				if w[0] + w[1] + w[2] + w[3] + w[4] + w[5] >= 0.5:
					ns_ok += 1
			acc["peb"][0] += w[5] * e
			acc["peb"][1] += w[5]
			acc["mud"][0] += w[4] * e
			acc["mud"][1] += w[4]
			acc["moss"][0] += w[1] * e
			acc["moss"][1] += w[1]
			# 斷面の起點：核心の縁（e 0.0–0.5）の格子點から勾配方向に泥の外縁を探す
			if e < 0.5 and int(floor(q.y * 2.0)) % 4 == 0:
				var g := GC.wgrad(C, q)
				var t := 0.0
				var last := -1.0
				while t < 8.0:
					var qq := q + g * t
					if GC.gwt(P, qq)[4] >= 0.3:
						last = GC.wdist(C, qq) - GC.RB_CORE
					t += 0.2
				if last >= 0.0:
					edges.append(last)
		sx += 0.5
	var em := 0.0
	for x: float in edges:
		em += x
	em /= maxf(1.0, edges.size())
	var ev := 0.0
	for x: float in edges:
		ev += (x - em) * (x - em)
	var esd := sqrt(ev / maxf(1.0, edges.size()))
	var d_peb: float = acc["peb"][0] / maxf(1e-6, acc["peb"][1])
	var d_mud: float = acc["mud"][0] / maxf(1e-6, acc["mud"][1])
	var d_moss: float = acc["moss"][0] / maxf(1e-6, acc["moss"][1])
	var plant_a := 0.0
	for it: Dictionary in items + nodes:
		if String(it.get("zone", "")) != "stream":
			continue
		var tg := String(it.get("tag", ""))
		plant_a += {"reed": 0.3, "bank": 0.4, "tuft": 0.15}.get(tg, 0.0)
	var band_a := float(ns) * 0.25 * 2.0
	var cont := float(ns_ok) / maxf(1.0, ns)
	check("溪岸地面：核心外 0.6–3.0 m の地面 overlay ≥ 0.5 が %.0f %%（≥ 85 %%，%d 點）、帯の順 卵石 %.2f m < 泥 %.2f m < 苔 %.2f m、泥帯外縁 平均 %.2f m 標準偏差 %.2f m（≥ 0.4，%d 斷面）、植物被覆 %.1f m² ／地面帯 %.0f m²＝%.1f %%（≤ 15 %%）" % [
		cont * 100.0, ns, d_peb, d_mud, d_moss, em, esd, edges.size(), plant_a, band_a, plant_a / maxf(1.0, band_a) * 100.0],
		ns > 100 and cont >= 0.85 and d_peb < d_mud and d_mud < d_moss and esd >= 0.4 and edges.size() >= 10 and plant_a / maxf(1.0, band_a) <= 0.15)
	rep["stream_ground"] = {"continuity": cont, "order": [d_peb, d_mud, d_moss], "mud_edge_sd": esd}
	# ── 6c P7 核心淡入（2026-10-03 許可）：① 核心內の overlay は外緣から 0.5 m 以內だけ、② P7 構件が覆う地面には描かない、
	#     ③ 交界（核心外緣 −0.25〜+0.1 m の露出地面）の overlay ≥ 0.25 が 60 % 以上＝斷層が消えている
	var n_deep := 0
	var n_onp7 := 0
	var n_seam := 0
	var n_seam_ok := 0
	var cx := srect.position.x + 0.125
	while cx < srect.end.x:
		var cz := srect.position.y + 0.125
		while cz < srect.end.y:
			var q := Vector2(cx, cz)
			cz += 0.25
			if GC.zone_inset("stream", q) < 4.0:
				continue
			var br := GC.blocked(C, q)
			if br != "" and br != "riverbank":
				continue
			var e := GC.wdist(C, q) - GC.RB_CORE
			var drawn := GC.stream_ground_ok(P, q, br)
			var w := GC.gwt(P, q)
			var sumw := w[0] + w[1] + w[2] + w[3] + w[4] + w[5]
			if br == "riverbank" and drawn and sumw > 0.02:
				if e < -GC.RB_FADE - 0.05:
					n_deep += 1
				if GC.p7_covered(C, q):
					n_onp7 += 1
			if e >= -0.25 and e <= 0.1 and not GC.p7_covered(C, q):
				n_seam += 1
				if drawn and sumw >= 0.25:
					n_seam_ok += 1
		cx += 0.25
	var seam_r := float(n_seam_ok) / maxf(1.0, n_seam)
	check("溪岸 P7 核心淡入：核心外緣より 0.5 m 超の內側に描いた點 %d（0）、P7 構件の上に描いた點 %d（0）、交界の露出地面で overlay ≥ 0.25 が %.0f %%（≥ 60 %%，%d 點）" % [n_deep, n_onp7, seam_r * 100.0, n_seam],
		n_deep == 0 and n_onp7 == 0 and n_seam > 50 and seam_r >= 0.6)
	rep["stream_core_fade"] = {"deep": n_deep, "on_p7": n_onp7, "seam_cover": seam_r}
	# ── 7 邊界（路肩・土／草）：地形の草／土の境界（草重み 0.45–0.55）1 m 格子のうち、1.0 m 以内に草叢がある割合 10–60 %（直線を切るが帯にしない）
	var tp: Array = []
	for it: Dictionary in items:
		if String(it["tag"]) == "tuft" and String(it["zone"]) in ["street", "lawn"]:
			tp.append(it["p"])
	var th := {}
	for q: Vector2 in tp:
		var k := Vector2i(floori(q.x), floori(q.y))
		if not th.has(k):
			th[k] = []
		th[k].append(q)
	var segs := 0
	var segs_hit := 0
	for zn in ["street", "lawn"]:
		var bbz := GC.zone_bbox(zn)
		var ex := bbz.position.x + 0.5
		while ex < bbz.end.x:
			var ez := bbz.position.y + 0.5
			while ez < bbz.end.y:
				var q := Vector2(ex, ez)
				ez += 1.0
				if GC.zone_of(q) != zn or GC.blocked(C, q) != "":
					continue
				var gw := GC.grass_w(C, q)
				if gw < 0.45 or gw > 0.55:
					continue
				segs += 1
				var hit := false
				for dx in [-1, 0, 1]:
					for dz in [-1, 0, 1]:
						for w: Vector2 in th.get(Vector2i(floori(q.x) + dx, floori(q.y) + dz), []):
							if w.distance_to(q) < 1.0:
								hit = true
				if hit:
					segs_hit += 1
			ex += 1.0
	var sr := float(segs_hit) / maxf(1.0, segs)
	check("邊界：地形の草／土の境界 %d m のうち草叢が 1 m 以内にある %.0f %%（10–60 %%＝直線を切るが帯にしない）" % [segs, sr * 100.0], segs >= 20 and sr >= 0.1 and sr <= 0.6)
	rep["edge"] = {"ratio": sr, "boundary_m": segs}
	# ── 8 地形語意：草叢（tuft）は地形が草として描かれている所だけ（路面・踏み固め土・林床・田の上に立てない）
	var n_t := 0
	var n_bad := 0
	for it: Dictionary in items:
		if String(it["tag"]) != "tuft":
			continue
		n_t += 1
		var lim := GC.grass_min(String(it["zone"]), String(it["zone"]) == "street")
		if GC.grass_w(C, it["p"]) < lim - GC.FEATHER - 0.01:
			n_bad += 1
	check("地形語意：草叢 %d 株のうち地形の草重みが下限（區別下限 − 羽毛 0.25）未滿 %d（0＝路面・裸土・林床の上に草叢なし）" % [n_t, n_bad], n_t > 0 and n_bad == 0)
	# ── 9 土場語意（鈴奈庵北空地 r10）：地形が土のセル（牆腳 0.8 m 外）で ① 中央（草から 5 m・壁から 4 m 超）と通行線 1.2 m 内に土の草叢・草色 overlay なし、
	#     ② 土の草叢 1 m 圏 2–25 %、草色 overlay（苔 ≥ 0.3）≤ 25 %（均一な草坪にしない）、③ 草叢は縁寄り（草叢の縁距離の平均 ≤ セル平均 × 0.6）
	var lrect: Rect2 = GC.ZONES["lawn"]["rect"]
	var dt: Array = []
	for it: Dictionary in items:
		if String(it["tag"]) == "dirt":
			dt.append(it["p"])
	var dh := {}
	for q: Vector2 in dt:
		var k := Vector2i(floori(q.x), floori(q.y))
		if not dh.has(k):
			dh[k] = []
		dh[k].append(q)
	var n_cell := 0
	var n_cov := 0
	var n_green := 0
	var n_center_bad := 0
	var n_path_bad := 0
	var edge_sum := 0.0
	var lx := lrect.position.x + 0.5
	while lx < lrect.end.x:
		var lz := lrect.position.y + 0.5
		while lz < lrect.end.y:
			var q := Vector2(lx, lz)
			lz += 1.0
			if GC.zone_of(q) != "lawn" or GC.blocked(C, q) != "" or GC.grass_w(C, q) >= GC.GRASS_MIN or GC.grass_w(C, q) < 0.0 or GC.wall_d(C, q) < 0.8:
				continue
			n_cell += 1
			var ed := minf(GC.gdist(C, q), GC.wall_d(C, q))
			edge_sum += ed
			var hit := false
			for dx in [-1, 0, 1]:
				for dz in [-1, 0, 1]:
					for w: Vector2 in dh.get(Vector2i(floori(q.x) + dx, floori(q.y) + dz), []):
						if w.distance_to(q) < 1.0:
							hit = true
			var green := GC.gwt(P, q)[1] >= 0.3
			if hit:
				n_cov += 1
			if green:
				n_green += 1
			var center := GC.gdist(C, q) > 5.0 and GC.wall_d(C, q) > 4.0
			if center and (hit or green):
				n_center_bad += 1
				if not quiet:
					info("土場 中央の草 @(%.1f,%.1f) tuft=%s green=%s dg=%.2f wall=%.2f inv=%.2f" % [q.x, q.y, hit, green, GC.gdist(C, q), GC.wall_d(C, q), GC.lawn_inv(C, q)])
			if GC.lawn_path_d(q) < 1.2 and (hit or green):
				n_path_bad += 1
				if not quiet:
					info("土場 通行線の草 @(%.1f,%.1f) tuft=%s green=%s pd=%.2f inv=%.2f" % [q.x, q.y, hit, green, GC.lawn_path_d(q), GC.lawn_inv(C, q)])
		lx += 1.0
	var t_edge := 0.0
	for q: Vector2 in dt:
		t_edge += minf(GC.gdist(C, q), GC.wall_d(C, q))
	t_edge /= maxf(1.0, dt.size())
	var c_edge := edge_sum / maxf(1.0, n_cell)
	var covr := float(n_cov) / maxf(1.0, n_cell)
	var grr := float(n_green) / maxf(1.0, n_cell)
	check("土場語意：土のセル %d m²、土の草叢 %d 株の 1 m 圏 %.1f %%（2–25 %%）、草色 overlay %.1f %%（≤ 25 %%）、中央の草 %d・通行線上の草 %d（0）、草叢の縁距離 %.2f m ≤ セル平均 %.2f × 0.6" % [
		n_cell, dt.size(), covr * 100.0, grr * 100.0, n_center_bad, n_path_bad, t_edge, c_edge],
		n_cell > 200 and covr >= 0.02 and covr <= 0.25 and grr <= 0.25 and n_center_bad == 0 and n_path_bad == 0 and t_edge <= c_edge * 0.6)
	rep["dirt_yard"] = {"cover": covr, "green": grr, "tuft_edge_d": t_edge, "cell_edge_d": c_edge}
	info("內訳 %s" % str(P["stats"]))
	return rep


func _attach() -> int:
	var txt := FileAccess.get_file_as_string(SCENE)
	if not FileAccess.file_exists(GC.OUTPUT):
		push_error("找不到 %s（先 --build 成功才可 attach）" % GC.OUTPUT)
		return 1
	if txt.contains("gen/groundcover_p9.scn"):
		push_error("已經掛過 GroundcoverP9")
		return 1
	var nl := "\r\n" if txt.contains("\r\n") else "\n"
	var lines := txt.split(nl)
	var out := PackedStringArray()
	var done := false
	var i := 0
	while i < lines.size():
		var ln := lines[i]
		out.append(ln)
		if not done and ln.begins_with("[node name=\"KirisameP9\" parent=\"Vegetation\""):
			i += 1
			while i < lines.size() and not lines[i].begins_with("["):
				out.append(lines[i])
				i += 1
			out.append("[node name=\"GroundcoverP9\" parent=\"Vegetation\" instance=ExtResource(\"p9r5_gc\")]")
			out.append("")
			done = true
			continue
		i += 1
	if not done:
		push_error("找不到 Vegetation/KirisameP9")
		return 1
	var last_ext := -1
	for k in out.size():
		if out[k].begins_with("[ext_resource"):
			last_ext = k
	out.insert(last_ext + 1, "[ext_resource type=\"PackedScene\" path=\"%s\" id=\"p9r5_gc\"]" % GC.OUTPUT)
	var f := FileAccess.open(SCENE, FileAccess.WRITE)
	f.store_string(nl.join(out))
	f.close()
	print("[GC] attach：加 Vegetation/GroundcoverP9 → %s" % SCENE)
	return 0


func _scene(v: Node3D) -> void:
	var go := v.get_node_or_null("Vegetation/" + GC.NODE_NAME) as Node3D
	var names: Array = []
	for c in v.get_node("Vegetation").get_children():
		names.append(String(c.name))
	var ok := true
	for k in ORDER.size() - 1:
		if not (ORDER[k] in names and ORDER[k + 1] in names) or names.find(ORDER[k]) > names.find(ORDER[k + 1]):
			ok = false
	check("場景已掛 Vegetation/%s，順序 %s" % [GC.NODE_NAME, " → ".join(ORDER)], go != null and ok)
	if go == null:
		return
	var n_mm := go.find_children("*", "MultiMeshInstance3D", true, false).size()
	var n_cs := go.find_children("*", "CollisionShape3D", true, false).size()
	var no_shadow := true
	for mmi in go.find_children("*", "MultiMeshInstance3D", true, false):
		if (mmi as GeometryInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF or (mmi as GeometryInstance3D).visibility_range_end <= 0.0:
			no_shadow = false
	check("MultiMesh 分塊 %d 節點（全部不投影＋visibility range）、碰撞 %d（地被は碰撞なし）" % [n_mm, n_cs], n_mm > 0 and n_cs == 0 and no_shadow)
	var vgn := go.get_node_or_null("Ground/Village")
	var n_vg := 0
	var vg_ok := vgn != null
	if vgn != null:
		for g in vgn.find_children("G_*", "MeshInstance3D", true, false):
			n_vg += 1
			if (g as GeometryInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF or (g as GeometryInstance3D).visibility_range_end <= 0.0:
				vg_ok = false
	check("[全村] 地面 overlay 區塊 %d（一般／林緣／溪岸、全部不投影＋visibility range）、art_revision＝%s" % [n_vg, go.get_meta("art_revision", "?")], vg_ok and n_vg > 50 and String(go.get_meta("art_revision", "")) == VL.ART_REVISION)
	var mgn := go.get_node_or_null("Ground/Macro")
	var n_mg := 0
	var mg_ok := mgn != null
	if mgn != null:
		for g in mgn.get_children():
			n_mg += 1
			if not (g is MeshInstance3D) or (g as GeometryInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF or (g as GeometryInstance3D).visibility_range_end <= 0.0 \
					or not String(((g as MeshInstance3D).mesh.surface_get_material(0) as ShaderMaterial).shader.resource_path).ends_with("gc_macro.gdshader"):
				mg_ok = false
	check("[Macro] 地面 overlay %d 區（A／B／C、gc_macro shader、不投影＋visibility range）" % n_mg, mg_ok and n_mg == ML.DESIGN.size())
	var mvn := go.get_node_or_null("Ground/MacroVillage")
	var n_mv := 0
	var mv_ok := mvn != null
	if mvn != null:
		for g in mvn.get_children():
			n_mv += 1
			if not (g is MeshInstance3D) or (g as GeometryInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF or (g as GeometryInstance3D).visibility_range_end <= 0.0 \
					or not String(((g as MeshInstance3D).mesh.surface_get_material(0) as ShaderMaterial).shader.resource_path).ends_with("gc_macro.gdshader"):
				mv_ok = false
	check("[MV] 全村 Macro 地面 overlay %d 區塊（gc_macro shader、不投影＋visibility range）" % n_mv, mv_ok and n_mv > 50)
	var zr := MMG.audit_node(go)
	if not bool(zr["display"]):
		info("MultiMesh instance 矩陣：headless 讀不到（非 headless 跑 --scene 才檢查）")
	else:
		check("永久 build rule：場景中 GroundcoverP9 全部 instance transform 非零（%s）" % MMG.summary(zr), MMG.ok(zr))
	info("GroundcoverP9：instance %s、植物節點 %s" % [go.get_meta("items", "?"), go.get_meta("nodes", "?")])
	if bool(zr["display"]):
		# P9 R5 限定解封（P10 R1b）：路地 1 の歩く芯に地被 instance なし＋反向（芯の中に 1 instance を足すと検出）
		var left := MVL.p10_audit(go)
		var probe := MultiMeshInstance3D.new()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.instance_count = 1
		var c: Vector2 = (MVL.P10_CLEAR[0] as Rect2).get_center()
		mm.set_instance_transform(0, Transform3D(Basis(), Vector3(c.x, 1.0, c.y)))
		probe.multimesh = mm
		go.add_child(probe)
		var neg := MVL.p10_audit(go)
		go.remove_child(probe)
		probe.free()
		check("[P10 限定解封] 場景：路地 1 の歩く芯の地被 instance %d（= 0）；反向：芯に 1 つ足すと %d（= 1）" % [left, neg - left], left == 0 and neg - left == 1)


## Pilot 部分だけの P（既存 Pilot gate／反向はこれを見る）
func _pilot_view(P: Dictionary) -> Dictionary:
	var Pp := P.duplicate()
	Pp["items"] = (P["items"] as Array).slice(0, int(P["n_pilot_items"]))
	Pp["nodes"] = (P["nodes"] as Array).slice(0, int(P["n_pilot_nodes"]))
	return Pp


func _vitems(P: Dictionary) -> Array:
	return (P["items"] as Array).slice(int(P["n_pilot_items"]), int(P.get("n_village_items", (P["items"] as Array).size())))


func _vnodes(P: Dictionary) -> Array:
	return (P["nodes"] as Array).slice(int(P["n_pilot_nodes"]), int(P.get("n_village_nodes", (P["nodes"] as Array).size())))


func _vinject(P: Dictionary, nm: String) -> void:
	var CV: Dictionary = P["CV"]
	var S: RLib.TriSampler = CV["S"]
	var items: Array = P["items"]
	match nm:
		"v_sealed":
			var r: Rect2 = (CV["SH"] as VL.RectHash).rects[0]
			items.append(GC.gi(S, GC.K_FINE, r.get_center(), 0.3, 1.0, 0.0, Color(1, 1, 1), "v_lawn", "tuft"))
		"v_farm":
			var q := Vector2(300.0, 60.0)
			var x := 250.0
			while x < 480.0 and is_nan((CV["FS"] as RLib.TriSampler).h(q.x, q.y)):
				x += 3.0
				q = Vector2(x, 60.0)
			items.append(GC.gi(S, GC.K_FINE, q, 0.3, 1.0, 0.0, Color(1, 1, 1), "v_lawn", "tuft"))
		"v_grid":
			# 開闊草地全体に 1.1 m 間隔で草叢（均一 scatter・空地を埋める）
			var x := VL.BB.position.x
			while x < VL.BB.end.x:
				var z := VL.BB.position.y
				while z < VL.BB.end.y:
					var q := Vector2(x, z)
					if VL.blocked_v(CV, q) == "" and GC.grass_w(CV, q) >= 0.6 and VL.is_gen(CV, q):
						items.append(GC.gi(S, GC.K_FINE, q, 0.3, 1.0, 0.0, Color(1, 1, 1), "v_lawn", "tuft"))
					z += 1.1
				x += 1.1
		"v_ring":
			for o: Dictionary in CV["obb"]:
				if VL.in_pilot(o["o"]):
					continue
				var hh: Vector2 = o["h"]
				for e in 4:
					for k in 60:
						var t := -1.0 + 2.0 * k / 59.0
						var q: Vector2 = [Vector2(t * hh.x, -hh.y - 0.3), Vector2(hh.x + 0.3, t * hh.y), Vector2(-t * hh.x, hh.y + 0.3), Vector2(-hh.x - 0.3, -t * hh.y)][e]
						items.append(GC.gi(S, GC.K_ROSETTE, (o["o"] as Vector2) + (o["bx"] as Vector2) * q.x + (o["bz"] as Vector2) * q.y, 1.0, 1.0, 0.0, Color(1, 1, 1), "v_wall", "wallfoot"))
				break
		"v_forest":
			# 林の外 10–14 m を林縁より密にする
			var x := VL.BB.position.x
			while x < VL.BB.end.x:
				var z := VL.BB.position.y
				while z < VL.BB.end.y:
					var q := Vector2(x, z)
					var fd := GC.forest_d(CV, q)
					if fd > 9.5 and fd < 14.0 and VL.blocked_v(CV, q) == "":
						items.append(GC.gi(S, GC.K_FINE, q, 0.3, 1.0, 0.0, Color(1, 1, 1), "v_forest", "tuft"))
					z += 0.5
				x += 0.5
		"v_nofloor":
			P["_neg_no_floor_v"] = true
		"v_isolated":
			for n: Dictionary in _vnodes(P):
				if String(n["id"]).begins_with("wk_reed"):
					var q: Vector2 = n["p"]
					var tg := GC.wgrad(CV, q)
					n["p"] = q + Vector2(-tg.y, tg.x) * 8.0
					break
		"v_coredeep":
			P["_neg_core_deep_v"] = true
		"v_dirtfill":
			var x := VL.BB.position.x
			while x < VL.BB.end.x:
				var z := VL.BB.position.y
				while z < VL.BB.end.y:
					var q := Vector2(x, z)
					var gw := GC.grass_w(CV, q)
					if VL.blocked_v(CV, q) == "" and gw >= 0.0 and gw < GC.GRASS_MIN and VL.is_gen(CV, q):
						items.append(GC.gi(S, GC.K_SHORT, q, 0.25, 1.0, 0.0, Color(1, 1, 1), "v_dirt", "dirt"))
					z += 1.2
				x += 1.2
		"v_trodden":
			# 道路の縁 0–1.5 m（常走區）の草に密な草叢
			var x := VL.BB.position.x
			while x < VL.BB.end.x:
				var z := VL.BB.position.y
				while z < VL.BB.end.y:
					var q := Vector2(x, z)
					var rs := VL.road_sd(CV, q)
					if rs > 0.2 and rs < 1.5 and VL.blocked_v(CV, q) == "" and GC.grass_w(CV, q) >= 0.5 and VL.is_gen(CV, q):
						items.append(GC.gi(S, GC.K_FINE, q, 0.3, 1.0, 0.0, Color(1, 1, 1), "v_lawn", "tuft"))
					z += 0.4
				x += 0.4
		"v_p7piece":
			# P7 構件（核心外の杭・石・護岸）の上に蘆を 1 本
			var x := VL.BB.position.x + 0.25
			var done := false
			while x < VL.BB.end.x and not done:
				var z := VL.BB.position.y + 0.25
				while z < VL.BB.end.y and not done:
					var q := Vector2(x, z)
					if GC.wdist(CV, q) > GC.RB_CORE + 0.3 and GC.wdist(CV, q) < 4.0 and VL.p7_covered(CV, q):
						(P["nodes"] as Array).append(GC.wnode(S, "wk_reed", q, 0.8, RandomNumberGenerator.new(), "v_stream", "reed"))
						done = true
					z += 0.5
				x += 0.5
		"v_freeze":
			var it: Dictionary = items[7]
			it["p"] = (it["p"] as Vector2) + Vector2(0.01, 0.0)


## 全村 gate（擴張部分）
func _vchecks(P: Dictionary) -> Dictionary:
	var CV: Dictionary = P["CV"]
	var S: RLib.TriSampler = CV["S"]
	var items := _vitems(P)
	var nodes := _vnodes(P)
	var rep := {"items": items.size(), "nodes": nodes.size()}
	var BB: Rect2 = VL.BB
	# ── V0 Pilot r10f 凍結：Pilot 規劃（items／nodes）と Pilot 4 區の地面網格が r10f と同一
	var dg: Array = VL.pilot_digest(P, not P.has("_ground_sha"))
	var gsha: String = P.get("_ground_sha", dg[1])
	check("[全村] Pilot r10f 凍結：Pilot 規劃 sha %s…（r10f %s…）、Pilot 地面 sha %s…（r10f %s…）" % [String(dg[0]).left(12), VL.PILOT_R10F_PLAN_SHA.left(12), gsha.left(12), VL.PILOT_R10F_GROUND_SHA.left(12)],
		dg[0] == VL.PILOT_R10F_PLAN_SHA and gsha == VL.PILOT_R10F_GROUND_SHA)
	# ── V1 接地＋禁區（封存 composition／P7 核心／P8 農田／水面／建物／frontage／路面中央／Pilot 區）
	var fl := 0
	var bad: Array = []
	for it: Dictionary in items + nodes:
		var p: Vector2 = it["p"]
		var dy := float(it["y"]) - S.h(p.x, p.y)
		if dy > 0.005 or dy < -0.06:
			fl += 1
		if String(it.get("tag", "")) == "rootflare":
			continue
		var why := VL.blocked_v(CV, p, String(it.get("zone", "")) == "v_road")
		if why == "" and String(it.get("kind", "")) == "tree":
			var r := 0.35 * (it["sc"] as Vector3).x
			for d in [Vector2(r, 0), Vector2(-r, 0), Vector2(0, r), Vector2(0, -r)]:
				var w2 := VL.blocked_v(CV, p + d)
				if w2.begins_with("sealed") or w2 == "building" or w2 == "road" or w2 == "farm" or w2 == "pilot" or w2 == "p7piece":
					why = w2
		if why != "":
			bad.append("%s@(%.1f,%.1f)→%s" % [it.get("id", GC.KIND_NAMES[int(it.get("k", 0))]), p.x, p.y, why])
	check("[全村] 禁區：%d 件中 封存 composition・竹林・P7 核心・P7 構件／橋・P8 農田・水面・建物・frontage・路面中央・Pilot 區 侵入 %d %s；接地偏差 %d" % [items.size() + nodes.size(), bad.size(), ", ".join(bad.slice(0, 4)), fl],
		bad.is_empty() and fl == 0)
	# ── V4 林緣：林緣距離の帯ごとに被覆が漸密（外 9–15 < 中 3.5–9 < 縁 −1.5–3.5 m）、蕨・笹・低木は林側ほど多い
	var bands := [[9.0, 15.0], [3.5, 9.0], [-1.5, 3.5]]
	var b_area := [0.0, 0.0, 0.0]
	var fx := BB.position.x + 0.5
	while fx < BB.end.x:
		var fz := BB.position.y + 0.5
		while fz < BB.end.y:
			var q := Vector2(fx, fz)
			fz += 1.0
			var fdq := GC.forest_d(CV, q)
			if fdq < -1.5 or fdq >= 15.0 or VL.blocked_v(CV, q) != "" or VL.memb(CV, q).z > 0.5:
				continue
			for bi in 3:
				if fdq >= float(bands[bi][0]) and fdq < float(bands[bi][1]):
					b_area[bi] += 1.0
		fx += 1.0
	var dens: Array = []
	var shrub_r: Array = []
	for bi in 3:
		var b: Array = bands[bi]
		var n_all := 0.0
		var n_sh := 0.0
		for it: Dictionary in items + nodes:
			if String(it.get("zone", "")) != "v_forest" or String(it.get("tag", "")) in ["root", "rootflare"]:
				continue
			var fd := GC.forest_d(CV, it["p"])
			if fd >= float(b[0]) and fd < float(b[1]):
				var area := 0.12
				if String(it.get("kind", "")) == "tree":
					var sc := (it["sc"] as Vector3).x
					area = (1.6 if String(it["id"]) == "shrub_a" else 1.1) * sc * sc
				elif int(it.get("k", 0)) == GC.K_LITTER:
					area = 0.5
				n_all += area
				if String(it.get("kind", "")) == "tree":
					n_sh += area
		dens.append(n_all / maxf(float(b_area[bi]), 1.0))
		shrub_r.append(n_sh / maxf(1.0, n_all))
	check("[全村] 林緣：被覆 外 %.3f → 中 %.3f → 縁 %.3f m²/m²（漸密；帯面積 %d／%d／%d m²）、蕨・笹・低木比率 %.0f → %.0f → %.0f %%" % [dens[0], dens[1], dens[2],
		b_area[0], b_area[1], b_area[2], shrub_r[0] * 100.0, shrub_r[1] * 100.0, shrub_r[2] * 100.0],
		dens[0] < dens[1] and dens[1] < dens[2] and shrub_r[0] <= shrub_r[1] and shrub_r[1] <= shrub_r[2] and b_area[2] > 500.0)
	rep["forest"] = {"density": dens, "shrub_ratio": shrub_r, "band_area": b_area}
	# ── V5 林床（forest-floor-first）：林床層の縁帯（seam −0.5〜+1.5 m）の地面 overlay ≥ 0.4 が 70 % 以上、蕨・笹・低木は群落（2.2 m 以内に他 2 株以上 ≥ 70 %）
	var nf := 0
	var nf_ok := 0
	var sx := BB.position.x + 0.5
	while sx < BB.end.x:
		var sz := BB.position.y + 0.5
		while sz < BB.end.y:
			var q := Vector2(sx, sz)
			sz += 1.0
			var sd := GC.seam_d(CV, q)
			if sd < -0.5 or sd > 1.5 or VL.blocked_v(CV, q) != "" or VL.memb(CV, q).y < 0.5:
				continue
			nf += 1
			var w := VL.gwt_v(P, q)
			if w[1] + w[2] + w[3] + w[4] >= 0.4:
				nf_ok += 1
		sx += 1.0
	var und: Array = []
	for n: Dictionary in nodes:
		if String(n.get("zone", "")) == "v_forest" and String(n.get("kind", "")) == "tree":
			und.append(n["p"])
	var UH := _hash1(und)
	var clus := 0
	for q: Vector2 in und:
		if _count1(UH, q, 2.2) >= 3:
			clus += 1
	var fr := float(nf_ok) / maxf(1.0, nf)
	var cr := float(clus) / maxf(1.0, und.size())
	check("[全村] 林床：林床層の縁帯 %d 點のうち地面 overlay ≥ 0.4 が %.0f %%（≥ 70 %%）、蕨・笹・低木 %d 株の群落率 %.0f %%（≥ 70 %%）" % [nf, fr * 100.0, und.size(), cr * 100.0],
		nf > 300 and fr >= 0.7 and cr >= 0.7)
	rep["forest_floor"] = {"cover": fr, "cluster": cr, "under": und.size()}
	# ── V6 水際：蘆は小群落（1.6 m 連結で各群 ≥ 5、孤立 0、群數 ≥ 3）、自然岸だけ、水からの距離 蘆 < 菅・花菖蒲 < 草叢、植物被覆 ≤ 15 %
	var reeds: Array = []
	var wd_of := {"reed": [], "bank": [], "tuft": []}
	var cover := 0.0
	for it: Dictionary in items + nodes:
		if String(it.get("zone", "")) != "v_stream":
			continue
		var tg := String(it.get("tag", ""))
		if wd_of.has(tg):
			(wd_of[tg] as Array).append(GC.wdist(CV, it["p"]))
		if tg == "reed":
			reeds.append(it["p"])
		if String(it.get("kind", "")) == "mesh":
			cover += 0.45
		elif tg == "tuft":
			cover += 0.06
	var sizes := _components(reeds, 1.6)
	var small := 0
	for z0: int in sizes:
		if z0 < 5:
			small += 1
	var unnat := 0
	for q: Vector2 in reeds:
		if VL.bank_nat(CV, q) < 0.45:
			unnat += 1
	var mw := {}
	for k: String in wd_of:
		var a: Array = wd_of[k]
		var m := 0.0
		for x: float in a:
			m += x
		mw[k] = m / maxf(1.0, a.size())
	var band_a := 0.0
	var bx := BB.position.x + 0.5
	while bx < BB.end.x:
		var bz := BB.position.y + 0.5
		while bz < BB.end.y:
			var q := Vector2(bx, bz)
			bz += 1.0
			var e := GC.wdist(CV, q) - GC.RB_CORE
			if e >= 0.0 and e < 6.0 and VL.blocked_v(CV, q) == "":
				band_a += 1.0
		bx += 1.0
	var cov_s := cover / maxf(1.0, band_a)
	check("[全村] 水際：蘆 %d 株＝%d 群落（5 株未滿・孤立 %d、護岸側 %d）、水からの平均距離 蘆 %.1f < 菅・花菖蒲 %.1f < 草叢 %.1f m、植物被覆 %.1f %%（≤ 15 %%，岸帯 %d m²）" % [
		reeds.size(), sizes.size(), small, unnat, mw["reed"], mw["bank"], mw["tuft"], cov_s * 100.0, band_a],
		sizes.size() >= 3 and small == 0 and unnat == 0 and mw["reed"] < mw["bank"] and mw["bank"] < mw["tuft"] and cov_s <= 0.15)
	rep["water"] = {"reeds": reeds.size(), "colonies": sizes.size(), "cover": cov_s}
	# ── V7 溪岸 P7：核心外緣より 0.5 m 超の內側に描かない、P7 構件の上に描かない、交界の露出地面は ≥ 50 % で淡入
	var n_deep := 0
	var n_onp7 := 0
	var n_seam := 0
	var n_seam_ok := 0
	var cx := BB.position.x + 1.0
	while cx < BB.end.x:
		var cz := BB.position.y + 1.0
		while cz < BB.end.y:
			var c2 := Vector2(cx, cz)
			cz += 2.0
			var wd2 := GC.wdist(CV, c2)
			if wd2 < 0.0 or wd2 > 4.5 or VL.in_pilot(c2):
				continue
			for ii in 8:
				for jj in 8:
					var q := c2 + Vector2(-1.0 + 0.25 * ii + 0.125, -1.0 + 0.25 * jj + 0.125)
					var e := GC.wdist(CV, q) - GC.RB_CORE
					if e < -1.4 or e > 0.6:
						continue
					var br := VL.blocked_v(CV, q)
					if br != "" and br != "riverbank":
						continue
					var w := VL.gwt_v(P, q)
					var sw := w[0] + w[1] + w[2] + w[3] + w[4] + w[5]
					var cov7 := VL.p7_covered(CV, q)
					if sw > 0.02:
						if e < -GC.RB_FADE - 0.05:
							n_deep += 1
						if cov7:
							n_onp7 += 1
					if e >= -0.25 and e <= 0.1 and not cov7:
						n_seam += 1
						if sw >= 0.25:
							n_seam_ok += 1
		cx += 2.0
	var seam_r := float(n_seam_ok) / maxf(1.0, n_seam)
	check("[全村] 溪岸 P7 核心淡入：核心外緣より 0.5 m 超の內側に描いた點 %d（0）、P7 構件の上 %d（0）、交界の露出地面で overlay ≥ 0.25 が %.0f %%（≥ 50 %%，%d 點）" % [n_deep, n_onp7, seam_r * 100.0, n_seam],
		n_deep == 0 and n_onp7 == 0 and n_seam > 200 and seam_r >= 0.5)
	rep["core_fade"] = {"deep": n_deep, "on_p7": n_onp7, "seam": seam_r}
	# ── V10 擴張覆蓋（全村の各類別に実際に入ったか；INFO を兼ねる）
	var n_flare := 0
	for it: Dictionary in items:
		if String(it["tag"]) == "rootflare":
			n_flare += 1
	var n_gen := 0
	for it: Dictionary in items:
		if String(it["zone"]) in ["v_lawn", "v_dirt", "v_wall", "v_road"]:
			n_gen += 1
	check("[全村] 擴張覆蓋（林緣・溪岸）：林床縁帯 %d 點、蕨・笹・低木 %d、蘆群落 %d、張り出し根 %d（0）、退役した一般類（草地・土場・牆腳・路肩の micro）%d 件（0＝全村 Macro が担う）" % [nf, und.size(), sizes.size(), n_flare, n_gen],
		und.size() > 100 and sizes.size() >= 3 and n_flare == 0 and n_gen == 0)
	return rep


func _hash1(pts: Array) -> Dictionary:
	var H := {}
	for q: Vector2 in pts:
		var k := Vector2i(floori(q.x), floori(q.y))
		if not H.has(k):
			H[k] = []
		(H[k] as Array).append(q)
	return H


func _near1(H: Dictionary, q: Vector2, r: float) -> bool:
	var n := int(ceil(r))
	var k := Vector2i(floori(q.x), floori(q.y))
	for dx in range(-n, n + 1):
		for dz in range(-n, n + 1):
			for w: Vector2 in H.get(k + Vector2i(dx, dz), []):
				if w.distance_to(q) < r:
					return true
	return false


func _count1(H: Dictionary, q: Vector2, r: float) -> int:
	var n := int(ceil(r))
	var k := Vector2i(floori(q.x), floori(q.y))
	var c := 0
	for dx in range(-n, n + 1):
		for dz in range(-n, n + 1):
			for w: Vector2 in H.get(k + Vector2i(dx, dz), []):
				if w.distance_to(q) < r:
					c += 1
	return c


func _nn_cv(pts: Array, H: Dictionary) -> float:
	var nn: Array = []
	for i in range(0, pts.size(), 3):
		var q: Vector2 = pts[i]
		var best := 99.0
		var k := Vector2i(floori(q.x), floori(q.y))
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				for w: Vector2 in H.get(k + Vector2i(dx, dz), []):
					var d := w.distance_to(q)
					if d > 0.001:
						best = minf(best, d)
		if best < 99.0:
			nn.append(best)
	var mean := 0.0
	for d: float in nn:
		mean += d
	mean /= maxf(1.0, nn.size())
	var v := 0.0
	for d: float in nn:
		v += (d - mean) * (d - mean)
	return sqrt(v / maxf(1.0, nn.size())) / maxf(mean, 1e-6)


func _components(pts: Array, link: float) -> Array:
	var H := _hash1(pts)
	var idx := {}
	for i in pts.size():
		idx[pts[i]] = i
	var lab := []
	lab.resize(pts.size())
	lab.fill(-1)
	var sizes: Array = []
	for i0 in pts.size():
		if lab[i0] >= 0:
			continue
		var st := [i0]
		lab[i0] = sizes.size()
		var cnt := 0
		while not st.is_empty():
			var a: int = st.pop_back()
			cnt += 1
			var q: Vector2 = pts[a]
			var k := Vector2i(floori(q.x), floori(q.y))
			for dx in [-2, -1, 0, 1, 2]:
				for dz in [-2, -1, 0, 1, 2]:
					for w: Vector2 in H.get(k + Vector2i(dx, dz), []):
						var b: int = idx[w]
						if lab[b] < 0 and w.distance_to(q) < link:
							lab[b] = sizes.size()
							st.append(b)
		sizes.append(cnt)
	return sizes


## 烘焙後の全村地面網格を頂點ごとに独立検査（不透明度 > 0.02 の頂點が 農田・建物・封存・水面・frontage・P7 核心の奥・P7 構件の上・Pilot 内部 に無いこと）
func _vground_audit(P: Dictionary, r: Node3D) -> void:
	var CV: Dictionary = P["CV"]
	var n_v := 0
	var bad := {}
	for g in r.get_node("Ground/Village").find_children("G_*", "MeshInstance3D", true, false):
		var m := (g as MeshInstance3D).mesh
		var arr := m.surface_get_arrays(0)
		var V: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var Cc: PackedColorArray = arr[Mesh.ARRAY_COLOR]
		var U: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		var U2: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2]
		var cls := String(g.get_parent().name)
		for i in V.size():
			var a := (Cc[i].r + Cc[i].g + Cc[i].b + Cc[i].a + U[i].x + U[i].y) * U2[i].y
			if a <= 0.02:
				continue
			n_v += 1
			var p := Vector2(V[i].x, V[i].z)
			var br := VL.blocked_v(CV, p, true, 1.25)
			var why := ""
			if br == "farm" or br == "building" or br == "water" or br == "frontage" or br.begins_with("sealed"):
				why = br
			elif br == "pilot" and VL.pilot_k(p) >= 0.999:
				why = "pilot"
			elif GC.wdist(CV, p) < GC.RB_CORE - GC.RB_FADE - 0.05 and (CV["RB"] as VL.RectHash).hit(p) != "":
				why = "p7core"
			elif VL.p7_covered(CV, p):
				why = "p7piece"
			if why != "":
				bad[why] = int(bad.get(why, 0)) + 1
	check("[全村] 地面網格 獨立檢查：不透明頂點 %d のうち 農田・建物・水面・frontage・封存・Pilot 內部・P7 核心の奥・P7 構件上 %d %s" % [n_v, bad.values().reduce(func(a, b): return a + b, 0), str(bad)],
		n_v > 50000 and bad.is_empty())


## Macro 地面網格の獨立檢查（不透明度 > 0.02 の頂點が 農田・建物・水面・frontage・封存・Pilot・P7 核心の奥・P7 構件上 に無い）
func _mground_audit(P: Dictionary, r: Node3D) -> void:
	var CV: Dictionary = P["CV"]
	var mg := r.get_node_or_null("Ground/Macro")
	var n_v := 0
	var bad := {}
	if mg != null:
		for g in mg.get_children():
			var arr := ((g as MeshInstance3D).mesh as ArrayMesh).surface_get_arrays(0)
			var V: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var Cc: PackedColorArray = arr[Mesh.ARRAY_COLOR]
			var U: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
			var U2: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2]
			var CU: PackedFloat32Array = arr[Mesh.ARRAY_CUSTOM0]
			for i in V.size():
				var a := (Cc[i].r + Cc[i].g + Cc[i].b + Cc[i].a + U[i].x + U[i].y + CU[i * 4] + CU[i * 4 + 1]) * U2[i].y
				if a <= 0.02:
					continue
				n_v += 1
				var p := Vector2(V[i].x, V[i].z)
				var br := VL.blocked_v(CV, p, true, 0.8, true)
				var why := ""
				if br == "farm" or br == "building" or br == "water" or br == "frontage" or br == "pilot" or br.begins_with("sealed"):
					why = br
				elif VL.p7_covered(CV, p):
					why = "p7piece"
				elif GC.wdist(CV, p) < GC.RB_CORE - GC.RB_FADE - 0.05 and (CV["RB"] as VL.RectHash).hit(p) != "":
					why = "p7core"
				if why != "":
					bad[why] = int(bad.get(why, 0)) + 1
	check("[Macro] 地面網格 獨立檢查：不透明頂點 %d のうち 農田・建物・水面・frontage・封存・Pilot・P7 核心の奥・P7 構件上 %d %s" % [n_v, bad.values().reduce(func(a, b): return a + b, 0), str(bad)],
		n_v > 5000 and bad.is_empty())


func _mitems(P: Dictionary) -> Array:
	return (P["items"] as Array).slice(int(P["n_village_items"]), int(P.get("n_macro_items", (P["items"] as Array).size())))


func _minject(P: Dictionary, nm: String) -> void:
	var CV: Dictionary = P["CV"]
	var S: RLib.TriSampler = CV["S"]
	var items: Array = P["items"]
	match nm:
		"m_sealed":
			# 區 C の建物の中に草叢
			for o: Dictionary in CV["obb"]:
				if ML.zone_of(o["o"]) == "C":
					items.append(GC.gi(S, GC.K_FINE, o["o"], 0.4, 1.0, 0.0, Color(1, 1, 1), "m_C", "rough"))
					break
		"m_p7":
			var r: Rect2 = VL.MACRO_ZONES["B"]
			var x := r.position.x + 0.25
			var done := false
			while x < r.end.x and not done:
				var z := r.position.y + 0.25
				while z < r.end.y and not done:
					var q := Vector2(x, z)
					if VL.p7_covered(CV, q):
						items.append(GC.gi(S, GC.K_STEM, q, 0.6, 1.0, 0.0, Color(1, 1, 1), "m_B", "rough"))
						done = true
					z += 0.5
				x += 0.5
		"m_fill":
			# 區 A の開けた草地全体に 1.2 m 間隔で丈の高い草叢（空地を埋める）
			var r: Rect2 = VL.MACRO_ZONES["A"]
			var x := r.position.x + 4.0
			while x < r.end.x - 4.0:
				var z := r.position.y + 4.0
				while z < r.end.y - 4.0:
					var q := Vector2(x, z)
					if VL.blocked_v(CV, q, false, 0.35, true) == "" and GC.grass_w(CV, q) >= 0.5:
						items.append(GC.gi(S, GC.K_FINE, q, 0.45, 1.0, 0.0, Color(1, 1, 1), "m_A", "rough"))
					z += 1.2
				x += 1.2
		"m_tiny":
			# 小草の數で稼ぐ：區 B に 0.12 m の草を 0.5 m 間隔で敷く
			var r: Rect2 = VL.MACRO_ZONES["B"]
			var x := r.position.x + 4.0
			while x < r.end.x - 4.0:
				var z := r.position.y + 4.0
				while z < r.end.y - 4.0:
					var q := Vector2(x, z)
					if VL.blocked_v(CV, q, false, 0.35, true) == "" and GC.grass_w(CV, q) >= 0.5:
						items.append(GC.gi(S, GC.K_SHORT, q, 0.12, 1.0, 0.0, Color(1, 1, 1), "m_B", "pathedge"))
					z += 0.5
				x += 0.5
		"m_speckle":
			P["_neg_speckle"] = true
		"m_ring":
			P["_neg_ring"] = true
		"m_noditch":
			P["_neg_noditch"] = true
		"m_nopath":
			# 渠沿いの小径と農路を消す
			var Z: Dictionary = P["M"]["zones"]["B"]
			Z["paths"] = (Z["paths"] as Array).filter(func(pl: Array) -> bool: return (pl[0] as Array).size() < 5)
			Z["spots"] = []


## Macro Pilot gate（三區）——ART 判定は同機位 BEFORE／AFTER の目視。ここは構造の機械検査だけ（coverage／pixel diff を美術の証拠にしない）
func _mchecks(P: Dictionary) -> Dictionary:
	var CV: Dictionary = P["CV"]
	var S: RLib.TriSampler = CV["S"]
	var M: Dictionary = P["M"]
	var items := _mitems(P)
	var rep := {"items": items.size()}
	# ── M0 禁區＋接地
	var bad: Array = []
	var fl := 0
	for it: Dictionary in items:
		var p: Vector2 = it["p"]
		var dy := float(it["y"]) - ML.top_h(P, p)
		if dy > 0.005 or dy < -0.06:
			fl += 1
		var why := ""
		if ML.zone_of(p) == "":
			why = "zone外"
		else:
			why = VL.blocked_v(CV, p, false, 0.35, true)
			if why == "" and VL.p7_covered(CV, p):
				why = "p7piece"
			elif why == "" and GC.wdist(CV, p) < GC.RB_CORE:
				why = "p7core"
		if why != "":
			bad.append("%s@(%.1f,%.1f)→%s" % [GC.KIND_NAMES[int(it.get("k", 0))], p.x, p.y, why])
	check("[Macro] 禁區：%d 件中 建物・frontage・封存・P7 核心／構件・P8 農田・水面・路面・Pilot r10f 區・三區外 侵入 %d %s；接地偏差 %d" % [items.size(), bad.size(), ", ".join(bad.slice(0, 4)), fl],
		bad.is_empty() and fl == 0)
	# ── 0.5 m 格子で地面重みを取る（三區）
	var G := {}
	var H := _hash1(items.map(func(it: Dictionary) -> Vector2: return it["p"]))
	var tall_pts: Array = []
	var n_tiny := 0
	var n_grass := 0
	for it: Dictionary in items:
		var k := int(it["k"])
		if k in GC.GRASS_KINDS:
			n_grass += 1
			if float(it["h"]) < 0.2:
				n_tiny += 1
			elif float(it["h"]) >= 0.3:
				tall_pts.append(it["p"])
	var TH := _hash1(tall_pts)
	var zr := {}
	for zn: String in VL.MACRO_ZONES:
		var r: Rect2 = VL.MACRO_ZONES[zn]
		var cells := {}
		var nx := int(r.size.x / 0.5)
		var nz := int(r.size.y / 0.5)
		for j in nz:
			for i in nx:
				var p := r.position + Vector2(i * 0.5 + 0.25, j * 0.5 + 0.25)
				if ML.inset(zn, p) < ML.FADE or not ML.vertex_ok_m(P, p):
					continue
				var w: Variant = ML.ground_m(P, p)
				cells[Vector2i(i, j)] = w
		G[zn] = cells
	# ── M1 尺度：使用痕跡（土・碎石・泥・木屑）／枯れ草／濃い草／踏まれた草 の各斑を 4 近傍で連結し、面積を測る
	var tot_area := 0.0
	var big_area := 0.0
	var tiny_area := 0.0
	var n_big := {}
	var by_cls := {}
	for zn: String in G:
		var cells: Dictionary = G[zn]
		for cls in ["use", "dry", "lush", "worn"]:
			var on := {}
			for g: Vector2i in cells:
				var w: Variant = cells[g]
				if w == null:
					continue
				var c: Color = w[0]
				var u: Vector2 = w[2]
				var cu: Vector2 = w[3]
				var v := 0.0
				match cls:
					"use": v = c.r + c.b + c.a + u.x + u.y
					"dry": v = cu.x
					"lush": v = c.g
					"worn": v = cu.y
				if v >= 0.3:
					on[g] = true
			var seen := {}
			for g0: Vector2i in on:
				if seen.has(g0):
					continue
				var st := [g0]
				seen[g0] = true
				var cnt := 0
				while not st.is_empty():
					var g: Vector2i = st.pop_back()
					cnt += 1
					for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
						if on.has(g + d) and not seen.has(g + d):
							seen[g + d] = true
							st.append(g + d)
				var a := cnt * 0.25
				tot_area += a
				var key := "%s.%s" % [zn, cls]
				var bk: Array = by_cls.get(key, [0.0, 0.0, 0.0])
				bk[0] += a
				if a >= 9.0:
					big_area += a
					bk[1] += a
					n_big[zn] = int(n_big.get(zn, 0)) + 1
				elif a < 1.0:
					tiny_area += a
					bk[2] += a
				by_cls[key] = bk
	var big_r := big_area / maxf(tot_area, 1.0)
	var tiny_r := tiny_area / maxf(tot_area, 1.0)
	rep["scale"] = {"painted_m2": tot_area, "big_ratio": big_r, "tiny_ratio": tiny_r, "big_patches": n_big, "by_class": by_cls}
	var diag: Array = []
	for key: String in by_cls:
		var bk: Array = by_cls[key]
		diag.append("%s %.0f/%.0f/%.1f" % [key, bk[0], bk[1], bk[2]])
	info("[Macro] 尺度 內訳（區.類 面積／9 m² 以上／1 m² 未満）：" + "、".join(diag))
	check("[Macro] 尺度：地面の斑 %.0f m² のうち 9 m² 以上の連結斑 %.0f%%、1 m² 未満の小斑 %.1f%%；9 m² 以上の斑 A %d／B %d／C %d" % [tot_area, big_r * 100.0, tiny_r * 100.0,
		n_big.get("A", 0), n_big.get("B", 0), n_big.get("C", 0)], big_r >= 0.8 and tiny_r <= 0.05 and int(n_big.get("A", 0)) >= 4 and int(n_big.get("B", 0)) >= 4 and int(n_big.get("C", 0)) >= 3)
	# ── M2 留白（A）：開けた草地の 40 % 以上が無地（地面重み < 0.15 かつ 1.5 m 以内に 3D なし）、最大の無地塊 ≥ 150 m²
	var A: Dictionary = G["A"]
	var ra: Rect2 = VL.MACRO_ZONES["A"]
	var lawn := 0
	var blank := {}
	for g: Vector2i in A:
		var p := ra.position + Vector2(g.x * 0.5 + 0.25, g.y * 0.5 + 0.25)
		if GC.grass_w(CV, p) < 0.5:
			continue
		lawn += 1
		var w: Variant = A[g]
		var tw := 0.0
		if w != null:
			var c: Color = w[0]
			tw = c.r + c.g + c.b + c.a + (w[2] as Vector2).x + (w[2] as Vector2).y + (w[3] as Vector2).x + (w[3] as Vector2).y
		if tw < 0.15 and not _near1(H, p, 1.5):
			blank[g] = true
	var seen2 := {}
	var big_blank := 0
	for g0: Vector2i in blank:
		if seen2.has(g0):
			continue
		var st := [g0]
		seen2[g0] = true
		var cnt := 0
		while not st.is_empty():
			var g: Vector2i = st.pop_back()
			cnt += 1
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if blank.has(g + d) and not seen2.has(g + d):
					seen2[g + d] = true
					st.append(g + d)
		big_blank = maxi(big_blank, cnt)
	var blank_r := float(blank.size()) / maxf(1.0, lawn)
	rep["blank_A"] = {"ratio": blank_r, "largest_m2": big_blank * 0.25}
	check("[Macro] 留白（A）：開けた草地 %.0f m² の %.0f%% が無地、最大の無地塊 %.0f m²" % [lawn * 0.25, blank_r * 100.0, big_blank * 0.25], blank_r >= 0.4 and big_blank * 0.25 >= 150.0)
	# ── M3 主角＝地面：丈 ≥ 0.3 m の草は「縁」（edge_k ≥ 0.05）だけ、0.2 m 未満の小草は草の 30 % 以下
	var interior_tall := 0
	for q: Vector2 in tall_pts:
		var zn := ML.zone_of(q)
		if zn == "" or ML.edge_k(P, zn, q) < 0.05:
			interior_tall += 1
	check("[Macro] 主角＝地面：丈 0.3 m 以上の草 %d 件のうち 縁でない所 %d；0.2 m 未満の小草 %d／%d（%.0f%%）" % [tall_pts.size(), interior_tall, n_tiny, n_grass, 100.0 * n_tiny / maxf(1.0, n_grass)],
		interior_tall == 0 and n_tiny <= 0.3 * n_grass)
	# ── M4 B 交界序列：田の外緣の草溝 → 農路 → 渠沿いの小径 → 背戸の支線／作業場
	var B: Dictionary = G["B"]
	var rb: Rect2 = VL.MACRO_ZONES["B"]
	var fg: GC.DGrid = M["fgrid"]
	var ditch_n := 0
	var ditch_ok := 0
	var ditch_sum := 0.0
	var farm_path := 0.0
	var canal_path := 0.0
	for g: Vector2i in B:
		var p := rb.position + Vector2(g.x * 0.5 + 0.25, g.y * 0.5 + 0.25)
		var w: Variant = B[g]
		var fd := fg.at(p)
		var lm := 0.0
		var so := 0.0
		if w != null:
			lm = (w[0] as Color).g + (w[2] as Vector2).x
			so = (w[0] as Color).b
		if fd > 0.3 and fd < 2.0:
			ditch_n += 1
			ditch_sum += lm
			if lm >= 0.25:
				ditch_ok += 1
		if (w != null) and (w[0] as Color).a >= 0.3 and (w[0] as Color).r + so + (w[0] as Color).a >= 0.8:
			farm_path += 0.25
		var e := GC.wdist(CV, p) - GC.RB_CORE
		if so >= 0.7 and e > 0.0 and e < 6.0 and p.x < 345.0:
			canal_path += 0.25
	var doors: Array = M["zones"]["B"]["doors"]
	var door_ok := 0
	for d: Array in doors:
		# 背戸の前（雨落ちの外 4 m 以内）に小径か作業場がある
		var q: Vector2 = (d[0] as Vector2) + (d[1] as Vector2) * 0.6
		var used := ML.path_d(M["zones"]["B"], q).x < 0.6
		for t in [1.5, 2.5, 3.3, 4.0]:
			if float(ML.spot_k(M["zones"]["B"], (d[0] as Vector2) + (d[1] as Vector2) * float(t))[0]) > 0.3:
				used = true
		if used:
			door_ok += 1
	var dm := ditch_sum / maxf(1.0, ditch_n)
	var dr := float(ditch_ok) / maxf(1.0, ditch_n)
	rep["B_seq"] = {"ditch_mean": dm, "ditch_ratio": dr, "yard_work_m2": farm_path, "canal_path_m2": canal_path, "doors": doors.size(), "doors_ok": door_ok}
	check("[Macro] B 交界序列：田の外緣 0.3–2 m 草溝 平均 %.2f・%.0f%% 成立；渠沿いの農路 %.0f m²；後場の作業場（木屑＋踏み土）%.0f m²；背戸 %d／%d が小径・作業場に接続" % [dm, dr * 100.0, canal_path, farm_path, door_ok, doors.size()],
		dm >= 0.35 and dr >= 0.6 and farm_path >= 8.0 and canal_path >= 20.0 and door_ok == doors.size())
	# ── M5 C 牆腳：背面の壁で 牆腳裸土は途切れる（25–90 %）、雨落ち線は 40 % 以上；完全な一周の建物 0；後院の小径 ≥ 30 m²
	var C: Dictionary = M["zones"]["C"]
	var foot_s := 0.0
	var foot_n := 0
	var drip_s := 0.0
	var ring := 0
	var per_b := {}
	for w: ML.Wall in C["walls"]:
		var L := w.a.distance_to(w.b)
		var n := int(L / 0.25)
		var f := 0
		var dps := 0
		var m := 0
		for i in n:
			var t := (i + 0.5) / n
			var q0 := w.a.lerp(w.b, t)
			if ML.zone_of(q0) != "C" or ML.inset("C", q0) < ML.FADE:
				continue
			var p1 := q0 + w.n * 0.3
			var p2 := q0 + w.n * 0.88
			if not ML.vertex_ok_m(P, p1):
				continue
			m += 1
			var w1: Variant = ML.ground_m(P, p1)
			var w2: Variant = ML.ground_m(P, p2)
			if w1 != null and (w1[0] as Color).b >= 0.4:
				f += 1
			if w2 != null and (w2[2] as Vector2).y >= 0.3:
				dps += 1
		if m < 8:
			continue
		if not per_b.has(w.bld):
			per_b[w.bld] = [0, 0]
		per_b[w.bld][0] += f
		per_b[w.bld][1] += m
		if w.back:
			foot_s += float(f) / m
			drip_s += float(dps) / m
			foot_n += 1
	var ring_names: Array = []
	for b: String in per_b:
		if float(per_b[b][0]) / maxf(1.0, per_b[b][1]) >= 0.95:
			ring += 1
			ring_names.append(b)
	var cp := 0.0
	for g: Vector2i in G["C"]:
		var w: Variant = G["C"][g]
		if w != null and (w[0] as Color).b >= 0.5:
			cp += 0.25
	var fm := foot_s / maxf(1.0, foot_n)
	var dmn := drip_s / maxf(1.0, foot_n)
	rep["C_wall"] = {"back_walls": foot_n, "foot_mean": fm, "drip_mean": dmn, "ring_buildings": ring, "path_m2": cp}
	check("[Macro] C 牆腳：背面の壁 %d 面で 牆腳裸土 平均 %.0f%%（途切れる）、雨落ち線 平均 %.0f%%；一周つながった建物 %d %s；後院の踏み土 %.0f m²" % [foot_n, fm * 100.0, dmn * 100.0, ring, str(ring_names), cp],
		foot_n >= 4 and fm >= 0.25 and fm <= 0.9 and dmn >= 0.75 and ring == 0 and cp >= 30.0)
	return rep


# ─────────────────────────── 全村 Macro（P9 R5 Macro Expansion） ───────────────────────────

## 検証側の可見最上面（地形・路面・P4 院子地面の max；generator の top_h とは別実装）
func _top(P: Dictionary, p: Vector2) -> float:
	var CV: Dictionary = P["CV"]
	var h := (CV["S"] as RLib.TriSampler).h(p.x, p.y)
	for smp: RLib.TriSampler in [CV["R"], (P["M"] as Dictionary)["YS"]]:
		var v := smp.h(p.x, p.y)
		if not is_nan(v):
			h = maxf(h, v)
	return h


func _mvitems(P: Dictionary) -> Array:
	return (P["items"] as Array).slice(int(P["n_macro_items"]))


func _mvinject(P: Dictionary, nm: String) -> void:
	var CV: Dictionary = P["CV"]
	var MV: Dictionary = P["MV"]
	var items: Array = P["items"]
	var rng := RandomNumberGenerator.new()
	match nm:
		"mv_sealed":
			var r: Rect2 = (CV["SH"] as VL.RectHash).rects[0]
			items.append(MVL._gi(P, GC.K_FINE, r.get_center(), 0.4, 1.0, 0.0, Color(1, 1, 1), "mv_wild", "rough", rng))
		"mv_farm":
			var fr: Rect2 = MV["frect"]
			var done := false
			var x := fr.position.x + 20.0
			while x < fr.end.x and not done:
				var z := fr.position.y + 20.0
				while z < fr.end.y and not done:
					var q := Vector2(x, z)
					if MVL.fdist(MV, q) < -2.0 and VL.BB.has_point(q):
						items.append(MVL._gi(P, GC.K_FINE, q, 0.4, 1.0, 0.0, Color(1, 1, 1), "mv_meadow", "rough", rng))
						done = true
					z += 3.0
				x += 3.0
		"mv_road":
			P["_neg_mv_road"] = true
		"mv_fill", "mv_tiny":
			# 最大の半荒／村邊の小區の内部を埋める（fill＝1.2 m 間隔の丈草、tiny＝0.5 m 間隔の 0.12 m 草）
			var best := -1
			for si in (MV["seeds"] as Array).size():
				var sd: Dictionary = MV["seeds"][si]
				if (int(sd["cls"]) == 1 or int(sd["cls"]) == 2) and (best < 0 or int(sd["n_int"]) > int(MV["seeds"][best]["n_int"])):
					best = si
			var sd0: Dictionary = MV["seeds"][best]
			var c0: Vector2 = sd0["p"]
			var stp := 1.2 if nm == "mv_fill" else 0.5
			var x := c0.x - 30.0
			while x < c0.x + 30.0:
				var z := c0.y - 30.0
				while z < c0.y + 30.0:
					var q := Vector2(x, z)
					z += stp
					var bi := MVL.block_at(MV, q)
					if bi != int(sd0["block"]) or VL.wall_d(CV, q) < 6.0 or GC.grass_w(CV, q) < 0.5:
						continue
					if nm == "mv_fill":
						items.append(MVL._gi(P, GC.K_FINE, q, 0.45, 1.0, 0.0, Color(1, 1, 1), "mv_wild", "rough", rng))
					else:
						items.append(MVL._gi(P, GC.K_SHORT, q, 0.12, 1.0, 0.0, Color(1, 1, 1), "mv_wild", "pathedge", rng))
				x += stp
		"mv_speckle":
			P["_neg_mv_speckle"] = true
		"mv_ring":
			P["_neg_mv_ring"] = true
		"mv_fixedband":
			P["_neg_mv_fixedband"] = true
		"mv_noditch":
			P["_neg_mv_noditch"] = true
		"mv_uniform":
			P["_neg_mv_uniform"] = true
		"mv_nolift":
			P["_neg_nolift"] = true
		"mv_m9":
			var it: Dictionary = items[int(P["n_village_items"]) + 3]
			it["p"] = (it["p"] as Vector2) + Vector2(0.01, 0.0)


## 全村 Macro gate——ART 判定は同機位 BEFORE／AFTER の目視。ここは構造の機械検査だけ（coverage／pixel diff を美術の証拠にしない）
func _mvchecks(P: Dictionary) -> Dictionary:
	var CV: Dictionary = P["CV"]
	var MV: Dictionary = P["MV"]
	var BB: Rect2 = VL.BB
	var items := _mvitems(P)
	var rep := {"items": items.size()}
	# ── MV0 Macro Pilot m9（A/B/C）凍結
	var dg: Array = MVL.m9_digest(P, not P.has("_m9_ground_sha"))
	var gsha: String = P.get("_m9_ground_sha", dg[1])
	check("[Macro Pilot] m9 凍結：規劃 sha %s…（m9 %s…）、地面 sha %s…（m9 %s…）" % [String(dg[0]).left(12), MVL.M9_PLAN_SHA.left(12), gsha.left(12), MVL.M9_GROUND_SHA.left(12)],
		dg[0] == MVL.M9_PLAN_SHA and gsha == MVL.M9_GROUND_SHA)
	rep["m9"] = [dg[0], gsha]
	if MVL.M9_PLAN_SHA == "":
		info("[Macro Pilot] m9 digest（初回記錄用）plan=%s ground=%s" % [dg[0], gsha])
	# ── MV1 禁區＋接地（可見最上面）
	var bad: Array = []
	var fl := 0
	for it: Dictionary in items:
		var p: Vector2 = it["p"]
		var dy := float(it["y"]) - _top(P, p)
		if dy > 0.005 or dy < -0.06:
			fl += 1
		var why := VL.blocked_v(CV, p)
		if why == "trunk" or why == "obstacle":
			why = ""
		if why == "" and (CV["SH"] as VL.RectHash).hit(p) != "":
			why = "sealed"
		if why == "" and VL.p7_covered(CV, p):
			why = "p7piece"
		elif why == "" and GC.wdist(CV, p) < GC.RB_CORE:
			why = "p7core"
		if why != "":
			bad.append("%s@(%.1f,%.1f)→%s" % [GC.KIND_NAMES[int(it.get("k", 0))], p.x, p.y, why])
	check("[MV] 禁區：%d 件中 建物・frontage・封存（R4 Hero・竹林）・P7 核心／構件・P8 農田・水面・路面・Pilot／Macro Pilot 區 侵入 %d %s；接地（可見最上面）偏差 %d" % [items.size(), bad.size(), ", ".join(bad.slice(0, 4)), fl],
		bad.is_empty() and fl == 0 and items.size() > 1000)
	# ── 0.5 m 格子：全村 Macro 領域（街區セル）の地面重み [use, dry, lush, worn, tot, gw, dw, seed]
	var nx: int = MV["nx"]
	var bid: PackedInt32Array = MV["bid"]
	var G := {}
	for k in bid.size():
		var bi := bid[k]
		if bi < 0:
			continue
		for sub in 4:
			var q := BB.position + Vector2(k % nx + 0.25 + 0.5 * (sub % 2), k / nx + 0.25 + 0.5 * (sub / 2))
			if not MVL.vertex_ok_mv(P, q):
				continue
			var w: Variant = MVL.ground_mv(P, q)
			var f := PackedFloat32Array([0, 0, 0, 0, 0, maxf(GC.grass_w(CV, q), 0.0), VL.wall_d(CV, q), float(MVL.sub_at(MV, q, bi)[0])])
			if w != null:
				var c: Color = w[0]
				var u: Vector2 = w[2]
				var cu: Vector2 = w[3]
				f[0] = c.r + c.b + c.a + u.x + u.y + float(w[4])
				f[1] = cu.x
				f[2] = c.g
				f[3] = cu.y
				f[4] = f[0] + f[1] + f[2] + f[3]
			G[Vector2i(floori((q.x - BB.position.x) * 2.0), floori((q.y - BB.position.y) * 2.0))] = f
	# ── MV2 尺度：使用痕跡・枯れ草・濃い草・踏まれた草の各斑の連結成分（0.5 m 格子）
	var tot_area := 0.0
	var big_area := 0.0
	var tiny_area := 0.0
	var by_cls := {}
	for ci in 4:
		var on := {}
		for g: Vector2i in G:
			if (G[g] as PackedFloat32Array)[ci] >= 0.3:
				on[g] = true
		var seen := {}
		for g0: Vector2i in on:
			if seen.has(g0):
				continue
			var stk := [g0]
			seen[g0] = true
			var cnt := 0
			while not stk.is_empty():
				var g: Vector2i = stk.pop_back()
				cnt += 1
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					if on.has(g + d) and not seen.has(g + d):
						seen[g + d] = true
						stk.append(g + d)
			var a := cnt * 0.25
			tot_area += a
			var key: String = ["use", "dry", "lush", "worn"][ci]
			var bk: Array = by_cls.get(key, [0.0, 0.0, 0.0])
			bk[0] += a
			if a >= 9.0:
				big_area += a
				bk[1] += a
			elif a < 1.0:
				tiny_area += a
				bk[2] += a
			by_cls[key] = bk
	var big_r := big_area / maxf(tot_area, 1.0)
	var tiny_r := tiny_area / maxf(tot_area, 1.0)
	var diag: Array = []
	for key: String in by_cls:
		diag.append("%s %.0f/%.0f/%.1f" % [key, by_cls[key][0], by_cls[key][1], by_cls[key][2]])
	info("[MV] 尺度 內訳（類 面積／9 m² 以上／1 m² 未満）：" + "、".join(diag))
	rep["scale"] = {"painted_m2": tot_area, "big_ratio": big_r, "tiny_ratio": tiny_r, "by_class": by_cls}
	check("[MV] 尺度：地面の斑 %.0f m² のうち 9 m² 以上の連結斑 %.0f%%、1 m² 未満の小斑 %.1f%%" % [tot_area, big_r * 100.0, tiny_r * 100.0], tot_area > 3000.0 and big_r >= 0.8 and tiny_r <= 0.05)
	# ── MV3 語意分類：小區ごとの語意（常走／半荒／村邊草地／臨時作業／未使用留白）と言語（主の留白＋次の斑＋縁の侵入）
	var seeds: Array = MV["seeds"]
	var st := {}
	for g: Vector2i in G:
		var f: PackedFloat32Array = G[g]
		if f[6] <= 6.0:
			continue
		var si := int(f[7])
		if not st.has(si):
			st[si] = [0, 0, 0, 0, 0, 0]
		var a: Array = st[si]
		a[0] += 1
		if f[4] < 0.15:
			a[1] += 1
		for ci in 4:
			if f[ci] >= 0.25:
				a[2 + ci] += 1
	var cls_area := {}
	var cls_n := {}
	var n_big := 0
	var n_ok := 0
	var vk := {}
	var weak: Array = []
	for si: int in st:
		var a: Array = st[si]
		if int(a[0]) < 1200:
			continue
		n_big += 1
		var cls := MVL.eff_cls(P, seeds[si])
		cls_area[cls] = float(cls_area.get(cls, 0.0)) + a[0] * 0.25
		cls_n[cls] = int(cls_n.get(cls, 0)) + 1
		var blank_r := float(a[1]) / float(a[0])
		var n_lang := 0
		for ci in 4:
			if float(a[2 + ci]) / float(a[0]) >= 0.04:
				n_lang += 1
		var vo: Vector2 = Vector2.ZERO if P.has("_neg_mv_uniform") else seeds[si]["vo"]
		vk["%d|%d|%d" % [cls, int(vo.x), int(vo.y)]] = true
		if blank_r >= (0.1 if cls == 3 else 0.15) and n_lang >= 1:
			n_ok += 1
		else:
			weak.append("%s#%d(blank %.0f%%,lang %d)" % [MVL.CLS_NAMES[cls], si, blank_r * 100.0, n_lang])
	var tot_i := 0.0
	var max_share := 0.0
	for c: int in cls_area:
		tot_i += float(cls_area[c])
	var parts: Array = []
	for c: int in cls_area:
		max_share = maxf(max_share, float(cls_area[c]) / maxf(tot_i, 1.0))
		parts.append("%s %d 區 %.0f m²" % [MVL.CLS_JA[c], cls_n[c], cls_area[c]])
	rep["classes"] = {"area": cls_area, "n": cls_n, "weak": weak}
	check("[MV] 語意分類：300 m² 以上の小區 %d（%s）、語意 %d 種（≥ 4）、最大の語意 %.0f%%（≤ 60 %%）、留白＋次の斑が成立 %d／%d（≥ 85 %%）、模板の重複 %d %s" % [n_big, "、".join(parts), cls_area.size(),
		max_share * 100.0, n_ok, n_big, n_big - vk.size(), ", ".join(weak.slice(0, 4))],
		n_big >= 12 and cls_area.size() >= 4 and max_share <= 0.6 and n_ok >= int(ceil(0.85 * n_big)) and vk.size() == n_big)
	# ── MV4 留白：草の内部（建物 6 m 超）の 35 % 以上が無地（地面重み < 0.15 かつ 1.5 m 以内に 3D なし）、最大の無地塊 ≥ 300 m²
	var IH := _hash1(items.map(func(it: Dictionary) -> Vector2: return it["p"]))
	var lawn := 0
	var blank := {}
	for g: Vector2i in G:
		var f: PackedFloat32Array = G[g]
		if f[5] < 0.5 or f[6] <= 6.0:
			continue
		lawn += 1
		if f[4] < 0.15:
			var q := BB.position + Vector2(g.x * 0.5 + 0.25, g.y * 0.5 + 0.25)
			if not _near1(IH, q, 1.5):
				blank[g] = true
	var seen2 := {}
	var big_blank := 0
	for g0: Vector2i in blank:
		if seen2.has(g0):
			continue
		var stk := [g0]
		seen2[g0] = true
		var cnt := 0
		while not stk.is_empty():
			var g: Vector2i = stk.pop_back()
			cnt += 1
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if blank.has(g + d) and not seen2.has(g + d):
					seen2[g + d] = true
					stk.append(g + d)
		big_blank = maxi(big_blank, cnt)
	var blank_r2 := float(blank.size()) / maxf(1.0, lawn)
	rep["blank"] = {"ratio": blank_r2, "largest_m2": big_blank * 0.25, "lawn_m2": lawn * 0.25}
	check("[MV] 留白：草の内部 %.0f m² の %.0f%% が無地（≥ 35 %%）、最大の無地塊 %.0f m²（≥ 300）" % [lawn * 0.25, blank_r2 * 100.0, big_blank * 0.25], blank_r2 >= 0.35 and big_blank * 0.25 >= 300.0)
	# ── MV5 主角＝地面：丈 0.3 m 以上の草は縁だけ、0.2 m 未満の小草は草の 30 % 以下
	var n_grass := 0
	var n_tiny := 0
	var n_tall := 0
	var interior_tall := 0
	for it: Dictionary in items:
		if not (int(it["k"]) in GC.GRASS_KINDS):
			continue
		n_grass += 1
		if float(it["h"]) < 0.2:
			n_tiny += 1
		elif float(it["h"]) >= 0.3:
			n_tall += 1
			if MVL.edge_k_mv(P, it["p"]) < 0.05:
				interior_tall += 1
	rep["tall"] = {"grass": n_grass, "tiny": n_tiny, "tall": n_tall, "interior_tall": interior_tall}
	check("[MV] 主角＝地面：丈 0.3 m 以上の草 %d 件のうち 縁でない所 %d；0.2 m 未満の小草 %d／%d（%.0f%%，≤ 30 %%）" % [n_tall, interior_tall, n_tiny, n_grass, 100.0 * n_tiny / maxf(1.0, n_grass)],
		interior_tall == 0 and n_tiny <= 0.3 * n_grass and n_grass > 500)
	# ── MV6 農田交界：(a) 田の縁が開けた地面に直接接する所／(b) 水渠が田と村の間にある所 の起点から外へ、
	#   縁の草（草溝・渠上の濃い草・房の丈草）→ 農路／裸土 → 疎らな草 の序列、農路の位置は場所で変わる（固定幅の帯でない）
	var samples: Array = []
	var SHs := {}
	for k in bid.size():
		if bid[k] < 0:
			continue
		var c := BB.position + Vector2(k % nx + 0.5, k / nx + 0.5)
		if VL.pilot_k(c) > 0.0:
			continue
		var fd := MVL.fdist(MV, c)
		var wdc := GC.wdist(CV, c)
		var typ := 0
		if fd >= 0.3 and fd <= 1.6:
			typ = 1
		elif fd < 35.0 and fd > wdc + 2.0 and wdc - GC.RB_CORE >= 2.4 and wdc - GC.RB_CORE <= 3.6:
			typ = 2
		if typ == 0:
			continue
		var hk := Vector2i(floori(c.x / 2.5), floori(c.y / 2.5))
		if SHs.has(hk):
			continue
		SHs[hk] = true
		samples.append([c, typ, MVL.bdist(CV, MV, c) < 45.0])
	var IHr := _hash1(items.filter(func(it: Dictionary) -> bool: return String(it["tag"]) == "rough").map(func(it: Dictionary) -> Vector2: return it["p"]))
	var n_s := 0
	var n_t := [0, 0, 0]
	var n_strip := 0
	var n_track := 0
	var n_vil := 0
	var n_sparse := 0
	var tcs := PackedFloat32Array()
	var sws := [[], [], []]
	for sm: Array in samples:
		var c: Vector2 = sm[0]
		var typ: int = sm[1]
		var nrm := Vector2.ZERO
		var p0 := c
		if typ == 1:
			var g2 := Vector2(MVL.fdist(MV, c + Vector2(0.5, 0)) - MVL.fdist(MV, c - Vector2(0.5, 0)), MVL.fdist(MV, c + Vector2(0, 0.5)) - MVL.fdist(MV, c - Vector2(0, 0.5)))
			if g2.length() < 0.2:
				continue
			nrm = g2.normalized()
			p0 = c - nrm * (MVL.fdist(MV, c) - 0.3)
		else:
			nrm = GC.wgrad(CV, c)
			if nrm.length() < 0.5:
				continue
			nrm = nrm.normalized()
			p0 = c - nrm * (GC.wdist(CV, c) - GC.RB_CORE - 0.4)
		n_s += 1
		n_t[typ] += 1
		var strip := false
		var track := false
		var sparse := false
		var best_so := 0.0
		var best_t := 0.0
		var sw := 0.0
		var in_strip := true
		var t := 0.0
		while t < 14.0:
			var q := p0 + nrm * t
			t += 0.25
			if not MVL.vertex_ok_mv(P, q):
				continue
			var w: Variant = MVL.ground_mv(P, q)
			if w == null:
				continue
			var lu_md := (w[0] as Color).g + (w[2] as Vector2).x
			var so := (w[0] as Color).b
			var ds := (w[3] as Vector2).x + (w[3] as Vector2).y
			if t <= 3.5 and (lu_md >= 0.15 or _near1(IHr, q, 1.0)):
				strip = true
			if in_strip:
				if lu_md >= 0.15:
					sw = t
				elif t > 0.75:
					in_strip = false
			if t > 1.0 and t < 10.0 and so >= 0.6:
				track = true
				if so > best_so:
					best_so = so
					best_t = t
			if t > 2.0 and ds >= 0.25:
				sparse = true
		if strip:
			n_strip += 1
			(sws[typ] as Array).append(sw)
		if bool(sm[2]):
			n_vil += 1
			if track:
				n_track += 1
				tcs.append(best_t)
		if sparse:
			n_sparse += 1
	var tm := 0.0
	for x: float in tcs:
		tm += x
	tm /= maxf(1.0, tcs.size())
	# 固定幅の帯でない：田の縁（渠越しは渠の縁）から農路の中心までの距離の四分位範囲÷中央値（建物までの余地・坡度・道路で変わる）
	var swm := 0.0
	var nsw := 0
	for ty in [1, 2]:
		for x: float in sws[ty]:
			swm += x
			nsw += 1
	swm /= maxf(1.0, nsw)
	var swcv := 99.0
	if tcs.size() >= 15:
		var arr: Array = Array(tcs)
		arr.sort()
		swcv = (float(arr[(arr.size() * 3) / 4]) - float(arr[arr.size() / 4])) / maxf(float(arr[arr.size() / 2]), 1e-6)
	var sr := float(n_strip) / maxf(1.0, n_s)
	var tr := float(n_track) / maxf(1.0, n_vil)
	var spr := float(n_sparse) / maxf(1.0, n_s)
	rep["farm_edge"] = {"samples": n_s, "direct": n_t[1], "canal": n_t[2], "strip": sr, "strip_w_mean": swm, "strip_w_cv": swcv, "near_houses": n_vil, "track": tr, "track_pos_mean": tm, "sparse": spr}
	check("[MV] 農田交界：田の外緣 %d 點（直接 %d・渠越し %d）で 縁の草（草溝・渠上の濃い草・房）%.0f%%（≥ 60 %%；幅 平均 %.1f m）、農路の位置の四分位範囲／中央値 %.2f（≥ 0.25＝固定幅の帯でない）→ 農路／裸土（建物 45 m 以内の %d 點の %.0f%%、≥ 30 %%、途切れる；位置 平均 %.1f m）→ 疎らな草・乾草 %.0f%%（≥ 30 %%）" % [n_s, n_t[1], n_t[2], sr * 100.0, swm, swcv, n_vil, tr * 100.0, tm, spr * 100.0],
		n_s >= 40 and sr >= 0.6 and nsw >= 20 and tcs.size() >= 15 and swcv >= 0.25 and n_vil >= 30 and tr >= 0.3 and spr >= 0.3)
	# ── MV7 後院牆腳：背面の壁で 軒下の裸土は途切れる（25–90 %）、雨落ち線 ≥ 75 %、一周つながった建物 0、背戸の ≥ 60 % が小径か作業地面へ
	var foot_s := 0.0
	var drip_s := 0.0
	var foot_n := 0
	var per_b := {}
	for w: ML.Wall in MV["walls"]:
		var mid := (w.a + w.b) * 0.5
		if VL.pilot_k(mid + w.n * 1.0) > 0.0 or VL.in_pilot(mid + w.n * 1.0):
			continue
		var L := w.a.distance_to(w.b)
		var n := int(L / 0.25)
		var f := 0
		var dps := 0
		var m := 0
		for i in n:
			var q0 := w.a.lerp(w.b, (i + 0.5) / n)
			var p1 := q0 + w.n * 0.3
			var p2 := q0 + w.n * 1.03
			if not MVL.vertex_ok_mv(P, p1) or not MVL.vertex_ok_mv(P, p2):
				continue
			m += 1
			var w1: Variant = MVL.ground_mv(P, p1)
			var w2: Variant = MVL.ground_mv(P, p2)
			if w1 != null and (w1[0] as Color).b >= 0.4:
				f += 1
			if w2 != null and (w2[2] as Vector2).y >= 0.3:
				dps += 1
		if m < 8:
			continue
		if not per_b.has(w.bld):
			per_b[w.bld] = [0, 0, 0]
		per_b[w.bld][0] += f
		per_b[w.bld][1] += m
		per_b[w.bld][2] += 1
		if w.back:
			foot_s += float(f) / m
			drip_s += float(dps) / m
			foot_n += 1
	var ring := 0
	var ring_n: Array = []
	for b: String in per_b:
		# 一周＝測れた壁が 3 面以上あり、その 95 % 以上が軒下の裸土（封存・路面に接して 1–2 面しか測れない棟は判定しない）
		if int(per_b[b][2]) >= 3 and float(per_b[b][0]) / maxf(1.0, per_b[b][1]) >= 0.95:
			ring += 1
			ring_n.append(b)
	var dconn := 0
	var doors: Array = MV["doors"]
	for d: Array in doors:
		var dp: Vector2 = d[0]
		var dn: Vector2 = d[1]
		var used := MVL.path_d(MV, dp + dn * 0.6).x < 0.6
		for t2 in [1.5, 2.5, 3.3, 4.0]:
			if float(MVL.spot_k(MV, dp + dn * float(t2))[0]) > 0.3:
				used = true
		if used:
			dconn += 1
	var fm := foot_s / maxf(1.0, foot_n)
	var dmn := drip_s / maxf(1.0, foot_n)
	var dcr := float(dconn) / maxf(1.0, doors.size())
	rep["backyard"] = {"back_walls": foot_n, "eave": fm, "drip": dmn, "ring": ring, "doors": doors.size(), "doors_conn": dcr}
	check("[MV] 後院牆腳：背面の壁 %d 面で 軒下の裸土 平均 %.0f%%（25–90 %%、途切れる）、雨落ち線 平均 %.0f%%（≥ 75 %%）；一周つながった建物 %d %s；背戸 %d の %.0f%% が小径・作業地面へ（≥ 60 %%）" % [foot_n, fm * 100.0, dmn * 100.0, ring, ",".join(ring_n.slice(0, 4)), doors.size(), dcr * 100.0],
		foot_n >= 30 and fm >= 0.25 and fm <= 0.9 and dmn >= 0.75 and ring == 0 and dcr >= 0.6)
	# ── MV8 路肩：路面 0.6 m より奥に描かない、路面の縁は土・砂利だけ（草系 0）、交差・巷口・轉角の ≥ 80 % で路肩が広がる、路肩の幅は場所で変わる
	var deep := 0
	var on_road_grass := 0
	var n_edge := 0
	var gx := BB.position.x + 0.25
	while gx < BB.end.x:
		var gz := BB.position.y + 0.25
		while gz < BB.end.y:
			var q := Vector2(gx, gz)
			gz += 0.5
			var rs := VL.road_sd(CV, q)
			if rs >= 0.0 or rs < -4.0:
				continue
			if not MVL.vertex_ok_mv(P, q):
				continue
			var w: Variant = MVL.ground_mv(P, q)
			if w == null:
				continue
			if rs < -0.7:
				deep += 1
			else:
				n_edge += 1
				if (w[0] as Color).g + (w[3] as Vector2).x + (w[3] as Vector2).y > 0.02:
					on_road_grass += 1
		gx += 0.5
	var nx_ok := 0
	var nx_all := 0
	for x: Array in MV["xs"]:
		var c: Vector2 = x[0]
		var r: float = x[1]
		var best := 0.0
		var n_ring := 0
		for ai in 24:
			var a := ai * TAU / 24.0
			for rr in [r * 0.55, r * 0.8, r]:
				var q: Vector2 = c + Vector2(cos(a), sin(a)) * float(rr)
				var rs := VL.road_sd(CV, q)
				if rs < 0.2 or rs > 3.0 or not MVL.vertex_ok_mv(P, q) or VL.pilot_k(q) > 0.0 or VL.memb(CV, q).x < 0.5:
					continue
				n_ring += 1
				var w: Variant = MVL.ground_mv(P, q)
				if w != null:
					var cc: Color = w[0]
					best = maxf(best, cc.r + cc.b + (w[3] as Vector2).y + float(w[4]))
		if n_ring < 6:
			continue
		nx_all += 1
		if best >= 0.3:
			nx_ok += 1
	var shw := PackedFloat32Array()
	var RE: MVL.Bucket = MV["RE"]
	var cnt_re := 0
	for key: Vector2i in RE.cell:
		for q0: Vector2 in RE.cell[key]:
			cnt_re += 1
			if cnt_re % 3 != 0 or VL.pilot_k(q0) > 0.0 or VL.memb(CV, q0).x < 0.5:
				continue
			var g3 := Vector2(VL.road_sd(CV, q0 + Vector2(0.4, 0)) - VL.road_sd(CV, q0 - Vector2(0.4, 0)), VL.road_sd(CV, q0 + Vector2(0, 0.4)) - VL.road_sd(CV, q0 - Vector2(0, 0.4)))
			if g3.length() < 0.2:
				continue
			var nrm := g3.normalized()
			var p0 := q0 - nrm * VL.road_sd(CV, q0)
			var wd := 0.0
			var t := 0.0
			while t < 6.0:
				var q := p0 + nrm * t
				t += 0.25
				if not MVL.vertex_ok_mv(P, q):
					break
				var w: Variant = MVL.ground_mv(P, q)
				if w == null or (w[0] as Color).b + (w[0] as Color).r + (w[3] as Vector2).y + float(w[4]) < 0.15:
					break
				wd = t
			shw.append(wd)
	var sm := 0.0
	for x: float in shw:
		sm += x
	sm /= maxf(1.0, shw.size())
	var sv := 0.0
	for x: float in shw:
		sv += (x - sm) * (x - sm)
	var scv := sqrt(sv / maxf(1.0, shw.size())) / maxf(sm, 1e-6)
	var xr := float(nx_ok) / maxf(1.0, nx_all)
	rep["road"] = {"deep": deep, "edge_grass": on_road_grass, "edge_pts": n_edge, "x_ok": nx_ok, "x_all": nx_all, "shoulder_mean": sm, "shoulder_cv": scv}
	check("[MV] 路肩：路面 0.6 m より奥に描いた點 %d（0）、路面の縁の草系 %d／%d（0）、交差・巷口・轉角 %d／%d で路肩が広がる（≥ 80 %%）、路肩の幅 平均 %.1f m・變動係數 %.2f（≥ 0.25）" % [deep, on_road_grass, n_edge, nx_ok, nx_all, sm, scv],
		deep == 0 and on_road_grass == 0 and nx_all >= 8 and xr >= 0.8 and scv >= 0.25 and shw.size() >= 100)
	return rep


## 可見最上面ルール（正式 build rule）：全 items／nodes（Pilot・全村 r5・Macro Pilot・全村 Macro）が地形・路面・P4 院子地面の最上面に載る
func _schecks(P: Dictionary) -> Dictionary:
	var CV: Dictionary = P["CV"]
	var S: RLib.TriSampler = CV["S"]
	var YS: RLib.TriSampler = (P["M"] as Dictionary)["YS"]
	var Pb := MVL.surface_copy(P)
	var n_all := 0
	var n_bad := 0
	var n_yard := 0
	var ex: Array = []
	for it: Dictionary in (Pb["items"] as Array) + (Pb["nodes"] as Array):
		if String(it.get("tag", "")) == "rootflare":
			continue
		var p: Vector2 = it["p"]
		n_all += 1
		var top := _top(P, p)
		var yh := YS.h(p.x, p.y)
		if not is_nan(yh) and yh > S.h(p.x, p.y) + 0.02:
			n_yard += 1
		var dy := float(it["y"]) - top
		if dy > 0.005 or dy < -0.07:
			n_bad += 1
			if ex.size() < 4:
				ex.append("%s@(%.1f,%.1f) dy %.3f" % [it.get("id", GC.KIND_NAMES[int(it.get("k", 0))]), p.x, p.y, dy])
	check("[Surface] 可見最上面：items／nodes %d 件（うち P4 院子地面の上 %d）のうち 地形・路面・院子地面の最上面から外れた件 %d %s" % [n_all, n_yard, n_bad, ", ".join(ex)],
		n_bad == 0 and n_yard >= 50)
	return {"all": n_all, "yard": n_yard, "bad": n_bad}


## 全村 Macro 地面網格の獨立檢查（不透明 > 0.02 の頂點が 農田・建物・水面・frontage・封存・Pilot 内部・P7 核心の奥・P7 構件上・路面の 0.6 m より奥 に無い）
func _mvground_audit(P: Dictionary, r: Node3D) -> void:
	var CV: Dictionary = P["CV"]
	var mg := r.get_node_or_null("Ground/MacroVillage")
	var n_v := 0
	var bad := {}
	if mg != null:
		for g in mg.get_children():
			var arr := ((g as MeshInstance3D).mesh as ArrayMesh).surface_get_arrays(0)
			var V: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var Cc: PackedColorArray = arr[Mesh.ARRAY_COLOR]
			var U: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
			var U2: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2]
			var CU: PackedFloat32Array = arr[Mesh.ARRAY_CUSTOM0]
			for i in V.size():
				var a := (Cc[i].r + Cc[i].g + Cc[i].b + Cc[i].a + U[i].x + U[i].y + CU[i * 4] + CU[i * 4 + 1] + CU[i * 4 + 2]) * U2[i].y
				if a <= 0.02:
					continue
				n_v += 1
				var p := Vector2(V[i].x, V[i].z)
				var br := VL.blocked_v(CV, p, true, 0.65)
				var why := ""
				if br == "pilot" and (VL.pilot_k(p) >= 0.999):
					why = "pilot"
				elif br == "farm" or br == "building" or br == "water" or br == "frontage" or br == "road" or br.begins_with("sealed"):
					why = br
				elif (CV["SH"] as VL.RectHash).hit(p) != "":
					why = "sealed"
				elif VL.p7_covered(CV, p):
					why = "p7piece"
				elif GC.wdist(CV, p) < GC.RB_CORE - GC.RB_FADE - 0.05 and (CV["RB"] as VL.RectHash).hit(p) != "":
					why = "p7core"
				if why != "":
					bad[why] = int(bad.get(why, 0)) + 1
	check("[MV] 地面網格 獨立檢查：不透明頂點 %d のうち 農田・建物・水面・frontage・路面の奥・封存・Pilot 内部・P7 核心の奥・P7 構件上 %d %s" % [n_v, bad.values().reduce(func(a, b): return a + b, 0), str(bad)],
		n_v > 50000 and bad.is_empty())


## 可見最上面ルール（烘焙後）：全地面網格（Pilot・全村 r5・Macro Pilot・全村 Macro）の不透明頂點が最上面の +0.004–0.035 m にある
func _surface_audit(P: Dictionary, r: Node3D) -> void:
	var YS: RLib.TriSampler = (P["M"] as Dictionary)["YS"]
	var S: RLib.TriSampler = (P["CV"] as Dictionary)["S"]
	var n_v := 0
	var n_y := 0
	var bad := {}
	for g in r.get_node("Ground").find_children("*", "MeshInstance3D", true, false):
		var am := (g as MeshInstance3D).mesh as ArrayMesh
		if am == null:
			continue
		var arr := am.surface_get_arrays(0)
		var V: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var Cc: PackedColorArray = arr[Mesh.ARRAY_COLOR]
		var U: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		var U2: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2]
		var CU: Variant = arr[Mesh.ARRAY_CUSTOM0]
		var grp := String(g.get_parent().name) if String(g.get_parent().name) != "Ground" else "Pilot"
		for i in V.size():
			var a := Cc[i].r + Cc[i].g + Cc[i].b + Cc[i].a + U[i].x + U[i].y
			if CU != null:
				a += (CU as PackedFloat32Array)[i * 4] + (CU as PackedFloat32Array)[i * 4 + 1] + (CU as PackedFloat32Array)[i * 4 + 2]
			if a * U2[i].y <= 0.02:
				continue
			n_v += 1
			var p := Vector2(V[i].x, V[i].z)
			var top := _top(P, p)
			var yh := YS.h(p.x, p.y)
			if not is_nan(yh) and yh > S.h(p.x, p.y) + 0.02:
				n_y += 1
			var dy := V[i].y - top
			if dy < 0.004 or dy > 0.035:
				bad[grp] = int(bad.get(grp, 0)) + 1
	check("[Surface] 地面網格 可見最上面：不透明頂點 %d（うち P4 院子地面の上 %d）のうち 最上面の +0.004–0.035 m から外れた頂點 %d %s" % [n_v, n_y, bad.values().reduce(func(a, b): return a + b, 0), str(bad)],
		bad.is_empty() and n_y > 1000)


# ─────────────────────────── 封存（--seal，P9 R5 Groundcover ART_APPROVED 2026-10-04） ───────────────────────────

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
	check("P9 R5 封存 %d 檔雜湊一致（凍結 %d、ART_REVIEW 圖 %d、證據 %d；不符 %d：%s）" % [n, seal["frozen"].size(),
		seal["art_review_images"].size(), seal["evidence"].size(), bad.size(), ", ".join(bad.slice(0, 4))], bad.is_empty())
	var txt := FileAccess.get_file_as_string(SCENE)
	var idx: Array = []
	for nm: String in ORDER:
		idx.append(txt.find("[node name=\"%s\" parent=\"Vegetation\"" % nm))
	var ord_ok: bool = int(idx[0]) >= 0
	for k in range(1, idx.size()):
		ord_ok = ord_ok and int(idx[k]) > int(idx[k - 1])
	check("village_v2.tscn 掛載 Vegetation/%s（%s）" % [" → ".join(ORDER), GC.OUTPUT], ord_ok and txt.contains(GC.OUTPUT))
	var neg_seal := seal.duplicate(true)
	var k0: String = neg_seal["frozen"].keys()[0]
	neg_seal["frozen"][k0] = "0".repeat(64)
	var nb := _seal_mismatch(neg_seal)
	check("反向：竄改 %s 期望雜湊 → 偵測到 1 筆不符（實際 %d）" % [k0, nb.size() - bad.size()], nb.size() == bad.size() + 1)
	print("[GC] 結果：%d 項失敗（seal）" % fails)
	return fails

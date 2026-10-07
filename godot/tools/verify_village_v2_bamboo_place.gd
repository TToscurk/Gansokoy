extends SceneTree
## 人間之里 V2 P9 R3 Bamboo／Village Edge：竹林擺放規劃＋場景級擺放驗證＋烘焙＋掛載＋審圖鏡位。
##   規劃＋gate（唯讀）：Godot --headless --path godot --script res://tools/verify_village_v2_bamboo_place.gd
##   反向：             ... -- --neg=road|float|r2|path|dome|r2scene（各自瞄準一項，必須讓那一項 FAIL）；-- --negatives 一次跑完
##   烘焙 overlay：     Godot --path godot --resolution 640x360 --script ... -- --build（MultiMesh 需非 headless）
##   掛進場景：         ... --headless ... -- --attach（village_v2.tscn 文字層級加 Vegetation/BambooP9 instance；先確認沒有編輯器開著）
##   場景驗證：         ... --headless ... -- --scene（已掛載的場景：稈基射線接地、稈碰撞 vs 建物／R2 樹幹／橋／地標 shape 查詢、
##                       踏跡小徑與入口膠囊實走、instance uniform 節點總數）
##   審圖鏡位：         ... --headless ... -- --shots（寫 tools/shots/village_v2_p9r3_{before,after}.json；1.7 m 眼高、10:00）
##   封存：             ... --headless ... -- --seal（data/village_v2_p9r3_seal.json：竹 Kit＋竹林擺放 生成器／gate／overlay／
##                       ART_REVIEW 總表／證據 sha256＋記憶體竄改反向；P9 R3 ART_APPROVED 2026-10-02）
## R2 林帶（forest_p9.scn）封存不動；竹只放進 R2 留下的空間，與 R2 樹幹／灌木／樹冠保持距離。
## 每項一行 [BPLACE] PASS/FAIL；INFO 不計失敗；結尾 quit(失敗項數)。

const BP := preload("res://tools/village_v2_bamboo_place_lib.gd")
const FLib := preload("res://tools/village_v2_forest_lib.gd")
const RLib := preload("res://tools/village_v2_riverbank_lib.gd")
const SCENE := "res://maps/village_v2/village_v2.tscn"
const LAYOUT := "res://maps/village_v2/layout_v2.json"
const REPORT := "res://data/village_v2_p9r3_bamboo.json"
const SEAL := "res://data/village_v2_p9r3_seal.json"
const UNIFORM_NODES_MAX := 32768   # project.godot buffer_size 524288 / 16
const EYE := 1.7

var fails := 0
var neg := ""
var failed_labels: Array = []
var quiet := false


func check(label: String, ok: bool) -> void:
	if not quiet:
		print("[BPLACE] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		fails += 1
		failed_labels.append(label)


func info(label: String) -> void:
	if not quiet:
		print("[BPLACE] INFO " + label)


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	for a: String in args:
		if a.begins_with("--neg="):
			neg = a.trim_prefix("--neg=")
	if "--attach" in args:
		quit(_attach())
		return
	if "--seal" in args:
		quit(_seal())
		return
	var L: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	var v: Node3D = (load(SCENE) as PackedScene).instantiate()
	if "--scene" in args or neg == "r2scene":
		root.add_child(v)
		await _scene(v, L)
		print("[BPLACE] 結果：%d 項失敗（scene）" % fails)
		quit(fails)
		return
	var old := v.get_node_or_null("Vegetation/" + BP.NODE_NAME)
	if old:
		old.get_parent().remove_child(old)
		old.free()
	if "--shots" in args:
		quit(_shots(v, L))
		return
	var P: Dictionary = BP.plan(v, L)
	var items: Array = P["items"]
	info("規劃 %d 件（%d ms）；拒絕原因 %s" % [items.size(), P["ms"], str(P["rejected"])])
	if "--negatives" in args:
		var target := {"road": "禁區", "float": "接地", "r2": "R2 共存", "path": "踏跡小徑", "dome": "頂線起伏"}
		var bad := 0
		for nm: String in target:
			var cp: Array = []
			for it: Dictionary in items:
				cp.append(it.duplicate())
			neg = nm
			fails = 0
			failed_labels.clear()
			quiet = true
			_inject(cp, P)
			_checks(cp, P)
			quiet = false
			var hit := failed_labels.any(func(l: String) -> bool: return l.begins_with(String(target[nm])))
			print("[BPLACE] %s 反向 %s → 「%s」必須 FAIL（失敗項 %d：%s）" % ["PASS" if hit else "FAIL", nm, target[nm],
				failed_labels.size(), " / ".join(failed_labels.map(func(l: String) -> String: return l.substr(0, 12)))])
			if not hit:
				bad += 1
		v.free()
		print("[BPLACE] 結果：%d 項失敗（negatives）" % bad)
		quit(bad)
		return
	if neg != "":
		_inject(items, P)
	var rep := _checks(items, P)
	if neg != "":
		print("[BPLACE] negative=%s 失敗 %d 項" % [neg, fails])
		v.free()
		quit(fails)
		return
	if "--build" in args and fails == 0:
		if DisplayServer.get_name() == "headless":
			check("--build 需要非 headless（MultiMesh 實例資料）", false)
		else:
			var r := BP.bake(items)
			BP.own(r, r)
			var ps := PackedScene.new()
			check("pack overlay", ps.pack(r) == OK)
			var e := ResourceSaver.save(ps, BP.OUTPUT, ResourceSaver.FLAG_COMPRESS)
			check("save %s" % BP.OUTPUT, e == OK)
			rep["overlay"] = {"path": BP.OUTPUT, "mb": FileAccess.get_file_as_bytes(BP.OUTPUT).size() / 1048576.0,
				"near_mesh_nodes": r.get_meta("near_mesh_nodes"), "multimesh_nodes": r.get_meta("multimesh_nodes"),
				"multimesh_instances": r.get_meta("multimesh_instances"), "culm_shapes": r.get_meta("culm_shapes")}
			info("overlay %.1f MB、近級逐稈 MeshInstance %d、MultiMesh 節點 %d（實例 %d）、稈碰撞 %d" % [rep["overlay"]["mb"],
				rep["overlay"]["near_mesh_nodes"], rep["overlay"]["multimesh_nodes"], rep["overlay"]["multimesh_instances"],
				rep["overlay"]["culm_shapes"]])
			r.free()
			var f := FileAccess.open(REPORT, FileAccess.WRITE)
			f.store_string(JSON.stringify(rep, "  ", false))
			f.close()
	v.free()
	print("[BPLACE] 結果：%d 項失敗" % fails)
	quit(fails)


func _inject(items: Array, P: Dictionary) -> void:
	var culms: Array = items.filter(func(it: Dictionary) -> bool: return String(it["layer"]) in ["core", "edge", "invade"])
	match neg:
		"road":
			var L: Dictionary = (P["ctx"] as FLib.Ctx).L
			for r: Dictionary in L["lanes"]:
				if String(r["name"]) == "WestBankLane":
					culms[0]["p"] = Vector2(float(r["pts"][2][0]), float(r["pts"][2][1]))
		"float":
			culms[culms.size() / 2]["y"] = float(culms[culms.size() / 2]["y"]) + 0.5
		"r2":
			# 一稈種在最近的 R2 樹幹上
			var r2: Array = P["r2"]
			for t: Array in r2:
				if float(t[4]) > 0.1 and (t[0] as Vector2).x < 120.0:
					culms[1]["p"] = (t[0] as Vector2) + Vector2(0.05, 0.0)
					break
		"path":
			var pa: Array = BP.PATHS[0][0]
			culms[2]["p"] = Vector2(float(pa[2][0]), float(pa[2][1]))
		"dome":
			# 頂線整齊（每稈離地同高 12 m）＝修剪樹籬／圓頂
			var M := BP.modules()
			for it: Dictionary in culms:
				it["sc"] = 12.0 / float(M[it["id"]]["height"])


func _top(it: Dictionary, M: Dictionary) -> float:
	return float(it["y"]) + float(M[it["id"]]["height"]) * float(it["sc"])


func _checks(items: Array, P: Dictionary) -> Dictionary:
	var C: FLib.Ctx = P["ctx"]
	var M := BP.modules()
	var culms: Array = items.filter(func(it: Dictionary) -> bool: return String(it["layer"]) in ["core", "edge", "invade"])
	var rep := {"date": Time.get_datetime_string_from_system(), "items": items.size(), "culms": culms.size()}
	# ── 1 禁區
	var bad := {}
	for it: Dictionary in items:
		var why := FLib.blocked(C, it["p"])
		if why != "":
			bad[why] = int(bad.get(why, 0)) + 1
	check("禁區：%d 件（竹稈 %d）落點全在可種地（建成區 +%.0f／農田／道路半寬 +%.0f／水渠溪 +%.0f／整平區／入口 %.0f m）；違規 %s" % [
		items.size(), culms.size(), FLib.M_BUILT, FLib.M_ROAD, FLib.M_CHANNEL, FLib.PORTAL_CLEAR, str(bad)], bad.is_empty())
	# ── 2 接地：稈基不得高於稈周 8 點最低地面（不浮）、埋深 ≤ 0.6 m；地被貼地 ±5 cm
	var fl := 0
	var dp := 0
	var wf := 0.0
	var wd := 0.0
	for it: Dictionary in items:
		var p: Vector2 = it["p"]
		var y := float(it["y"])
		var c := C.S.h(p.x, p.y)
		if String(it["layer"]) == "litter":
			if absf(y - c) > 0.05:
				fl += 1
			continue
		var lo := c
		for k in 8:
			var a := k * TAU / 8.0
			var h := C.S.h(p.x + cos(a) * 0.12, p.y + sin(a) * 0.12)
			if not is_nan(h):
				lo = minf(lo, h)
		if y > lo + 0.005:
			fl += 1
			wf = maxf(wf, y - lo)
		if c - y > 0.6:
			dp += 1
			wd = maxf(wd, c - y)
	check("接地：竹稈／筍基不浮（≤ 稈周最低地面）、埋深 ≤ 0.6 m；落葉地被貼地 ±5 cm：浮 %d（最大 %.2f m）、過深 %d（最大 %.2f m）" % [
		fl, wf, dp, wd], fl == 0 and dp == 0)
	# ── 3 R2 共存（封存林帶）：竹稈離 R2 樹幹 ≥ 樹幹半徑＋稈半徑＋0.3 m；離 R2 地被 ≥ 0.3 m；核心竹不在 R2 林冠樹冠半徑 0.5 倍內
	var r2g: BP.Grid = P["r2_grid"]
	var hit_t := 0
	var hit_u := 0
	var hit_c := 0
	var dmin := INF
	for it: Dictionary in culms:
		var p: Vector2 = it["p"]
		for t: Array in r2g.near(p, 8.0):
			var d := p.distance_to(t[0])
			if float(t[4]) > 0.0:
				dmin = minf(dmin, d - float(t[4]) - float(it["r"]))
				if d < float(t[4]) + float(it["r"]) + 0.3:
					hit_t += 1
			elif String(t[1]) in FLib.UNDER_IDS and d < 0.3:
				hit_u += 1
			if String(it["layer"]) == "core" and String(t[3]) in ["canopy", "sub", "slope"] and not (String(t[1]) in FLib.YOUNG_IDS) \
					and d < float(t[5]) * 0.5:
				hit_c += 1
	check("R2 共存：竹稈 vs R2 樹幹淨距最小 %.2f m（≥ 0.3）、穿樹幹 %d、壓地被 %d、核心竹進 R2 樹冠半徑 0.5 倍 %d" % [dmin, hit_t, hit_u, hit_c],
		hit_t == 0 and hit_u == 0 and hit_c == 0)
	# ── 4 踏跡小徑＋林內空洞：路寬內無竹稈；R2 樹幹也不擋（淨寬 ≥ 1.4 m＝膠囊 0.6＋兩側 0.4）
	var on_path := 0
	var in_clear := 0
	for it: Dictionary in items:
		if String(it["layer"]) in ["litter"]:
			continue
		if BP.path_d(it["p"]) < 0.0:
			on_path += 1
		if (BP.in_clearing(it["p"]) or BP.in_mouth(it["p"])) and String(it["layer"]) != "shoot" and not it.get("gate", false):
			in_clear += 1
	var r2_on_path := 0
	for t: Array in P["r2"]:
		if float(t[4]) > 0.0 and BP.path_d(t[0]) < float(t[4]):
			r2_on_path += 1
	# 小徑可讀：路寬內不得有落葉地被 patch 蓋到（patch 半徑 1.75 m × 縮放）
	var lit_on := 0
	for it: Dictionary in items:
		if String(it["layer"]) == "litter" and BP.path_d(it["p"]) < 1.75 * float(it["sc"]) - 0.5 - 0.01:
			lit_on += 1
	var gates := items.filter(func(it: Dictionary) -> bool: return it.get("gate", false)).size()
	check("踏跡小徑：%d 條路寬內竹稈 %d、R2 樹幹 %d、落葉蓋路 %d；林內空洞＋入口喇叭口 %d 個內竹稈 %d；入口門柱 %d／%d" % [BP.PATHS.size(),
		on_path, r2_on_path, lit_on, BP.CLEARINGS.size() + BP.MOUTHS.size(), in_clear, gates, BP.MOUTHS.size() * 2],
		on_path == 0 and r2_on_path == 0 and in_clear == 0 and lit_on == 0 and gates == BP.MOUTHS.size() * 2)
	# ── 5 空間結構：核心密／林緣疏（密度比 ≥ 2）；林緣有若竹／淡竹／傾き竹；侵入帶存在（與 R2 交界不切直線）
	var by := {}
	for it: Dictionary in culms:
		var g := String(it["grove"])
		if not by.has(g):
			by[g] = {"core": 0, "edge": 0, "invade": 0, "a_core": 0.0, "a_edge": 0.0, "lean_out": 0, "lean": 0, "ids": {}}
		var e: Dictionary = by[g]
		e[it["layer"]] = int(e[it["layer"]]) + 1
		(e["ids"] as Dictionary)[it["id"]] = int((e["ids"] as Dictionary).get(it["id"], 0)) + 1
		if String(it["id"]) == "take_lean":
			e["lean"] = int(e["lean"]) + 1
			# 傾向（本地 +x 旋 yaw）朝林外 ±60°
			var dirv := Vector2(cos(float(it["yaw"])), -sin(float(it["yaw"])))
			if dirv.dot(it["out"]) > 0.5:
				e["lean_out"] = int(e["lean_out"]) + 1
	# 面積：0.5 m 格估各 grove 的核心（s ≥ 0.6）與林緣（0.35–0.6）面積
	var F: BP.Field = P["field"]
	for G: Dictionary in BP.GROVES:
		var g := String(G["name"])
		if not by.has(g):
			continue
		for b: Array in G["blobs"]:
			pass
	var acc := {}
	var x := 40.0
	while x < 170.0:
		var z := -200.0
		while z < 130.0:
			var p := Vector2(x, z)
			var sg: Array = F.at(p)
			if float(sg[0]) >= BP.S_INVADE and int(sg[1]) >= 0 and FLib.blocked(C, p) == "" and BP.path_d(p) >= 0.15 and not BP.in_clearing(p):
				var g := String(BP.GROVES[int(sg[1])]["name"])
				if not acc.has(g):
					acc[g] = [0.0, 0.0]
				(acc[g] as Array)[0 if float(sg[0]) >= BP.S_CORE else 1] += 1.0
			z += 1.0
		x += 1.0
	var struct_ok := true
	var parts: Array = []
	for g: String in by:
		var e: Dictionary = by[g]
		var ac: Array = acc.get(g, [1.0, 1.0])
		var dc := float(e["core"]) / maxf(float(ac[0]), 1.0)
		var de := float(e["edge"]) / maxf(float(ac[1]), 1.0)
		var ratio := dc / maxf(de, 1e-3)
		var lean_ok := int(e["lean"]) == 0 or float(e["lean_out"]) / float(e["lean"]) >= 0.8
		var big := float(ac[0]) > 150.0
		if big and (ratio < 2.0 or not lean_ok):
			struct_ok = false
		parts.append("%s 核心 %.2f／林緣 %.2f 稈/m²（×%.1f）、侵入 %d、傾き竹朝外 %d/%d" % [g, dc, de, ratio, e["invade"], e["lean_out"], e["lean"]])
	var inv_ok := int(by.get("A_入口竹林", {}).get("invade", 0)) > 0
	check("空間結構：%s；大竹林（核心 > 150 m²）密度比 ≥ 2、傾き竹 ≥ 80 %% 朝林外、A 竹林有侵入帶" % "；".join(parts), struct_ok and inv_ok)
	rep["groves"] = by
	# ── 6 頂線起伏（遠景不得像圓頂樹籬）：每個大竹林沿長軸 4 m 帶取最高稈頂，相鄰帶高差的標準差 ≥ 0.6 m，
	#      且核心稈頂高的變異係數 ≥ 0.08（整片同高＝修剪樹籬）
	var dome_ok := true
	var dparts: Array = []
	for g: String in by:
		var cs: Array = culms.filter(func(it: Dictionary) -> bool: return String(it["grove"]) == g)
		var core: Array = cs.filter(func(it: Dictionary) -> bool: return String(it["layer"]) == "core")
		if core.size() < 40:
			continue
		var tops: Array = core.map(func(it: Dictionary) -> float: return _top(it, M) - float(it["y"]))
		var cv := FLib_cv(tops)
		# 長軸＝主成分
		var mean := Vector2.ZERO
		for it: Dictionary in cs:
			mean += it["p"]
		mean /= cs.size()
		var sxx := 0.0
		var sxz := 0.0
		var szz := 0.0
		for it: Dictionary in cs:
			var d: Vector2 = (it["p"] as Vector2) - mean
			sxx += d.x * d.x
			sxz += d.x * d.y
			szz += d.y * d.y
		var ang := 0.5 * atan2(2.0 * sxz, sxx - szz)
		var ax := Vector2(cos(ang), sin(ang))
		var bands := {}
		for it: Dictionary in cs:
			var k := floori(((it["p"] as Vector2) - mean).dot(ax) / 4.0)
			bands[k] = maxf(float(bands.get(k, -INF)), _top(it, M) - float(it["y"]))   # 離地稈高（地形坡度不算起伏）
		var ks := bands.keys()
		ks.sort()
		var diffs: Array = []
		for i in range(1, ks.size()):
			diffs.append(float(bands[ks[i]]) - float(bands[ks[i - 1]]))
		var sd := _sd(diffs)
		if cv < 0.08 or sd < 0.6:
			dome_ok = false
		dparts.append("%s 核心稈高 CV %.2f、長軸 4 m 帶頂線高差 σ %.2f m（%d 帶）" % [g, cv, sd, ks.size()])
	check("頂線起伏（離地稈高）：%s（CV ≥ 0.08、σ ≥ 0.6 m）" % "；".join(dparts), dome_ok and not dparts.is_empty())
	# ── 7 稈距與種別：最小稈距 ≥ 0.5 m；竹林 7 型＋筍＋落葉都有用到
	var g2 := BP.Grid.new()
	for it: Dictionary in culms:
		g2.add(it["p"], it)
	var close := 0
	var smin := INF
	for it: Dictionary in culms:
		for o: Dictionary in g2.near(it["p"], 1.0):
			if o == it:
				continue
			var d := (it["p"] as Vector2).distance_to(o["p"])
			smin = minf(smin, d)
			if d < 0.5:
				close += 1
	var ids := {}
	for it: Dictionary in items:
		ids[it["id"]] = int(ids.get(it["id"], 0)) + 1
	check("稈距／種別：最小稈距 %.2f m（≥ 0.5，違規 %d）；使用 %d／9 種 %s" % [smin, close / 2, ids.size(), str(ids)],
		close == 0 and ids.size() == 9)
	rep["ids"] = ids
	# ── 8 instance uniform 節點總數（R2 林帶＋竹）≤ buffer_size／16
	var near_n := culms.size() * BP.NEAR_LODS
	var r2_nodes := 18803
	var rj: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/village_v2_p9r2_forest.json"))
	if rj is Dictionary:
		r2_nodes = int(rj.get("instance_uniform_nodes", r2_nodes))
	var est := r2_nodes + near_n + 600
	check("instance uniform 節點：R2 %d＋竹近級 %d＋MultiMesh（估 ≤ 600）＝%d ≤ %d" % [r2_nodes, near_n, est, UNIFORM_NODES_MAX],
		est <= UNIFORM_NODES_MAX)
	info("西林與村緣：竹稈 %d（核心 %d／林緣 %d／侵入 %d）、筍 %d、落葉地被 %d" % [culms.size(),
		culms.filter(func(i: Dictionary) -> bool: return i["layer"] == "core").size(),
		culms.filter(func(i: Dictionary) -> bool: return i["layer"] == "edge").size(),
		culms.filter(func(i: Dictionary) -> bool: return i["layer"] == "invade").size(),
		int(ids.get("takenoko", 0)), int(ids.get("take_litter", 0))])
	return rep


static func FLib_cv(a: Array) -> float:
	var m := 0.0
	for x: float in a:
		m += x
	m /= maxf(a.size(), 1)
	return _sd(a) / maxf(m, 1e-6)


static func _sd(a: Array) -> float:
	if a.size() < 2:
		return 0.0
	var m := 0.0
	for x: float in a:
		m += x
	m /= a.size()
	var s := 0.0
	for x: float in a:
		s += (x - m) * (x - m)
	return sqrt(s / (a.size() - 1))


# ─────────────────────────── 掛載 ───────────────────────────

func _attach() -> int:
	var txt := FileAccess.get_file_as_string(SCENE)
	if txt.is_empty():
		push_error("讀不到 " + SCENE)
		return 1
	if txt.contains("gen/bamboo_p9.scn"):
		push_error("已經掛過 BambooP9")
		return 1
	var nl := "\r\n" if txt.contains("\r\n") else "\n"
	var lines := txt.split(nl)
	var out := PackedStringArray()
	var done := false
	var i := 0
	while i < lines.size():
		var ln := lines[i]
		out.append(ln)
		if not done and ln.begins_with("[node name=\"ForestP9\" parent=\"Vegetation\""):
			i += 1
			while i < lines.size() and not lines[i].begins_with("["):
				out.append(lines[i])
				i += 1
			out.append("[node name=\"BambooP9\" parent=\"Vegetation\" instance=ExtResource(\"p9r3_bamboo\")]")
			out.append("")
			done = true
			continue
		i += 1
	if not done:
		push_error("找不到 Vegetation/ForestP9（R2 林帶未掛載）")
		return 1
	var last_ext := -1
	for k in out.size():
		if out[k].begins_with("[ext_resource"):
			last_ext = k
	out.insert(last_ext + 1, "[ext_resource type=\"PackedScene\" path=\"%s\" id=\"p9r3_bamboo\"]" % BP.OUTPUT)
	var f := FileAccess.open(SCENE, FileAccess.WRITE)
	f.store_string(nl.join(out))
	f.close()
	print("[BPLACE] attach：加 Vegetation/BambooP9 → %s" % SCENE)
	return 0


# ─────────────────────────── 場景級擺放驗證（已掛載） ───────────────────────────

func _scene(v: Node3D, L: Dictionary) -> void:
	var bo := v.get_node_or_null("Vegetation/" + BP.NODE_NAME) as Node3D
	check("場景已掛 Vegetation/%s" % BP.NODE_NAME, bo != null)
	if bo == null:
		return
	for i in 4:
		await physics_frame
	var space := v.get_world_3d().direct_space_state
	var terrain := v.get_node("Collision/TerrainCollision") as StaticBody3D
	var bamboo_rids: Array[RID] = []
	for sb in bo.get_node("Collision").get_children():
		bamboo_rids.append((sb as StaticBody3D).get_rid())
	# 1 稈基射線接地（只認地形）
	var culms: Array = []
	for t in bo.get_node("Near").find_children("*", "Node3D", true, false):
		if t.has_meta("veg_id"):
			culms.append(t)
	if neg == "r2scene":
		# 反向：把一稈搬到最近的 R2 樹幹上（記憶體）＋它的碰撞同步搬
		var fo := v.get_node("Vegetation/ForestP9")
		for sb in fo.get_node("Collision").get_children():
			var cs := sb.get_child(0) as CollisionShape3D
			if (cs.global_position.x < 118.0):
				var c0 := bo.get_node("Collision").get_child(0).get_child(0) as CollisionShape3D
				c0.global_position = cs.global_position
				break
		for i in 3:
			await physics_frame
	var fl := 0
	var sunk := 0
	var nohit := 0
	var worst := 0.0
	for t: Node3D in culms:
		var p := t.global_position
		var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 6, 0), p - Vector3(0, 6, 0))
		var ex: Array[RID] = bamboo_rids.duplicate()
		var y_hit := NAN
		for k in 8:
			q.exclude = ex
			var r := space.intersect_ray(q)
			if r.is_empty():
				break
			if r["collider"] == terrain:
				y_hit = float((r["position"] as Vector3).y)
				break
			ex.append(r["rid"])
		if is_nan(y_hit):
			nohit += 1
			continue
		var gap := p.y - y_hit
		worst = maxf(worst, gap)
		if gap > 0.05:
			fl += 1
		if gap < -0.6:
			sunk += 1
	check("場景接地（%d 稈基向下射線只認地形）：浮 > 0.05 m %d（最大 %.3f）、埋 > 0.6 m %d、射線落空 %d" % [culms.size(), fl, worst, sunk, nohit],
		fl == 0 and sunk == 0 and nohit == 0)
	# 2 稈碰撞 vs 其他所有碰撞（建物、R2 樹幹、橋、地標、河岸；排除地形與竹自己）
	var hits := {}
	var n_sh := 0
	for sb: StaticBody3D in bo.get_node("Collision").get_children():
		for cs: CollisionShape3D in sb.get_children():
			var qp := PhysicsShapeQueryParameters3D.new()
			qp.shape = cs.shape
			qp.transform = cs.global_transform
			var ex: Array[RID] = bamboo_rids.duplicate()
			ex.append(terrain.get_rid())
			qp.exclude = ex
			for r: Dictionary in space.intersect_shape(qp, 4):
				var col := r["collider"] as Node
				var key := String(v.get_path_to(col)).get_slice("/", 0) + "/" + String(v.get_path_to(col)).get_slice("/", 1)
				hits[key] = int(hits.get(key, 0)) + 1
			n_sh += 1
	check("稈碰撞 shape 查詢：%d 根圓柱 vs 建物／R2 樹幹／橋／地標／河岸 接觸 %s" % [n_sh, str(hits) if hits else "0"], hits.is_empty())
	# 3 實走：踏跡小徑每 0.5 m、入口 3 處，膠囊（r 0.3、h 1.7）只碰地形
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.7
	var S := RLib.terrain_sampler(v)
	var blocked_pts: Array = []
	var n_probe := 0
	for pa: Array in BP.PATHS:
		var pts := PackedVector2Array()
		for q: Array in pa[0]:
			pts.append(Vector2(float(q[0]), float(q[1])))
		for i in pts.size() - 1:
			var n := maxi(1, int(pts[i].distance_to(pts[i + 1]) / 0.5))
			for k in n:
				var q := pts[i].lerp(pts[i + 1], float(k) / n)
				var h := S.h(q.x, q.y)
				var qp := PhysicsShapeQueryParameters3D.new()
				qp.shape = cap
				qp.transform = Transform3D(Basis.IDENTITY, Vector3(q.x, h + 0.3 + 0.85 + 0.05, q.y))
				qp.exclude = [terrain.get_rid()]
				n_probe += 1
				var r := space.intersect_shape(qp, 1)
				if not r.is_empty():
					blocked_pts.append("(%.1f, %.1f) %s" % [q.x, q.y, (r[0]["collider"] as Node).name])
	check("實走：踏跡小徑膠囊探針 %d 點（r 0.3、h 1.7、離地 5 cm）被擋 %d %s" % [n_probe, blocked_pts.size(),
		", ".join(blocked_pts.slice(0, 4))], blocked_pts.is_empty())
	# 4 instance uniform 實際節點總數
	var nodes := 0
	for n in v.get_node("Vegetation").find_children("*", "GeometryInstance3D", true, false):
		nodes += 1
	check("instance uniform 節點（Vegetation 下 GeometryInstance3D）%d ≤ %d" % [nodes, UNIFORM_NODES_MAX], nodes <= UNIFORM_NODES_MAX)
	info("BambooP9：稈 %d、近級節點 %s、MultiMesh 節點 %s（實例 %s）" % [culms.size(), bo.get_meta("near_mesh_nodes", "?"),
		bo.get_meta("multimesh_nodes", "?"), bo.get_meta("multimesh_instances", "?")])


# ─────────────────────────── 審圖鏡位 ───────────────────────────

## [名稱, 相機 xz, 看向 xz, 看向高（相對地面）, 眼高（相對地面）]
const SHOTS := [
	["p9r3_a_entry", Vector2(133.0, 10.8), Vector2(93, -15.5), 3.0, EYE],
	["p9r3_a_path_in", Vector2(118.8, 1.1), Vector2(93, -15.5), 2.2, EYE],
	["p9r3_a_inside", Vector2(106.0, -7.5), Vector2(91, -17.5), 2.6, EYE],
	["p9r3_a_inside_back", Vector2(91.5, -17.0), Vector2(113, -3.2), 2.2, EYE],
	["p9r3_a_clearing", Vector2(101.5, -23.0), Vector2(89.5, -17.5), 9.0, EYE],
	["p9r3_a_upslope", Vector2(50, -24), Vector2(95, -26), 4.0, EYE],
	["p9r3_edge_lane_mid", Vector2(136, -46), Vector2(95, -30), 4.0, EYE],
	["p9r3_edge_lane_n", Vector2(134, -128), Vector2(100, -145), 4.0, EYE],
	["p9r3_b_stream", Vector2(122, -150), Vector2(92, -168), 3.5, EYE],
	["p9r3_join_south", Vector2(112, 12), Vector2(85, -25), 5.0, EYE],
	["p9r3_join_north", Vector2(110, -75), Vector2(90, -40), 5.0, EYE],
	["p9r3_sw_corner", Vector2(168, 104), Vector2(118, 96), 3.5, EYE],
	["p9r3_sw_stream", Vector2(140, 60), Vector2(112, 95), 3.5, EYE],
	["p9r3_far_crossmid", Vector2(200, -20), Vector2(95, -28), 6.0, EYE],
	["p9r3_far_south_field", Vector2(192, 118), Vector2(110, 85), 6.0, EYE],
	["p9r3_far_hill_lane", Vector2(140, -232), Vector2(95, -165), 5.0, EYE],
	["p9r3_far_upslope", Vector2(30, -40), Vector2(105, -15), 6.0, EYE],
	["p9r3_far_hillfoot", Vector2(250, -150), Vector2(95, -150), 6.0, EYE],
]


func _shots(v: Node3D, L: Dictionary) -> int:
	var S := RLib.terrain_sampler(v)
	var before: Array = []
	var after: Array = []
	for s: Array in SHOTS:
		var c: Vector2 = s[1]
		var l: Vector2 = s[2]
		var hc := S.h(c.x, c.y)
		var hl := S.h(l.x, l.y)
		var e := {"name": String(s[0]), "cam": [c.x, snappedf(hc + float(s[4]), 0.01), c.y],
			"look": [l.x, snappedf(hl + float(s[3]), 0.01), l.y], "hud": false, "time": 10}
		var eb := e.duplicate(true)
		eb["hide"] = ["Debug", "Portals", "Vegetation/BambooP9"]
		e["hide"] = ["Debug", "Portals"]
		before.append(eb)
		after.append(e)
	# 全村遠景（高空斜俯視、西側）
	for extra: Array in [["p9r3_far_air_w", [190, 55, 30], [90, 4, -45]], ["p9r3_overview_w", [210, 110, 120], [90, 0, -50]]]:
		var e := {"name": extra[0], "cam": extra[1], "look": extra[2], "hud": false, "time": 10, "hide": ["Debug", "Portals"]}
		var eb := e.duplicate(true)
		eb["hide"] = ["Debug", "Portals", "Vegetation/BambooP9"]
		before.append(eb)
		after.append(e)
	for pair: Array in [["res://tools/shots/village_v2_p9r3_before.json", before], ["res://tools/shots/village_v2_p9r3_after.json", after]]:
		var f := FileAccess.open(String(pair[0]), FileAccess.WRITE)
		f.store_string(JSON.stringify(pair[1], " ", false))
		f.close()
		print("[BPLACE] 寫入 %s（%d 張）" % [pair[0], (pair[1] as Array).size()])
	v.free()
	return 0


# ─────────────────────────── 封存（--seal，P9 R3 ART_APPROVED 2026-10-02） ───────────────────────────

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
	check("P9 R3 封存 %d 檔雜湊一致（凍結 %d、ART_REVIEW 總表 %d、證據 %d；不符 %d：%s）" % [n, seal["frozen"].size(),
		seal["art_review_images"].size(), seal["evidence"].size(), bad.size(), ", ".join(bad.slice(0, 4))], bad.is_empty())
	# 掛載：village_v2.tscn 仍掛 Vegetation/BambooP9 → gen/bamboo_p9.scn
	var txt := FileAccess.get_file_as_string(SCENE)
	check("village_v2.tscn 掛載 Vegetation/BambooP9（%s）" % BP.OUTPUT, txt.contains("[node name=\"BambooP9\" parent=\"Vegetation\"")
		and txt.contains(BP.OUTPUT))
	var neg_seal := seal.duplicate(true)
	var k0: String = neg_seal["frozen"].keys()[0]
	neg_seal["frozen"][k0] = "0".repeat(64)
	var nb := _seal_mismatch(neg_seal)
	check("反向：竄改 %s 期望雜湊 → 偵測到 1 筆不符（實際 %d）" % [k0, nb.size() - bad.size()], nb.size() == bad.size() + 1)
	print("[BPLACE] 結果：%d 項失敗（seal）" % fails)
	return fails

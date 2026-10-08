extends SceneTree
## P10 R4b Human-Use Expansion Batch 1（root 直下 HumanUseExpansionP10、HumanUseP10 の次）gate（回歸 tag HUX）。
##   godot --headless --path godot --script res://tools/verify_village_v2_human_use_exp.gd -- [--negatives] [--build] [--dump=<json>] [--meadow-cache=<json>]
##   godot --headless --path godot --script res://tools/verify_village_v2_human_use_exp.gd -- --attach   （root 直下・HumanUseP10 の次に掛ける）
##   godot --headless --path godot --script res://tools/verify_village_v2_human_use_exp.gd -- --scene    （掛載後：擴張層自身＋R4 の 50 件 snapshot が独立に一致）
##   --meadow-cache は設計の反復用。gate の本番は付けない（MeadowP9 規劃株を毎回同 seed で再計算）。MultiMesh なし → headless build 可。
##   --snapshot=<json>  掛載済み場景の HumanUseExpansionP10 全件（id・zone・cluster・who・why・anchor・世界位置・朝向）を書き出す（封存用）
##   --seal  封存（data/village_v2_p10r4b_seal.json：雜湊＋掛載＋場景＝snapshot＋snapshot の A/B＝承認時 r3 の A/B＋C 群・rejected id なし＋R4 の 50 件不変）。
##           使用者裁定 2026-10-08：A 農田・B 住宅＝ART_APPROVED（A/B FINAL）、C 水岸＝ART_REJECTED（rejected_c() に記録だけ）。
##           封存中は --build／--attach を拒否（HUX_ALLOW_REBAKE=1＝使用者が reopen した時だけ、その後 seal を更新）。
const HX := preload("res://tools/village_v2_human_use_exp_lib.gd")
const HU := preload("res://tools/village_v2_human_use_lib.gd")
const MD := preload("res://tools/village_v2_meadow_lib.gd")
const SL := preload("res://tools/village_v2_street_lib.gd")
const RLib := preload("res://tools/village_v2_riverbank_lib.gd")
const SCENE := "res://maps/village_v2/village_v2.tscn"
const R4_SNAPSHOT := "res://data/village_v2_p10r4_snapshot.json"
const PROPS_SEALED := ["MarketP10", "StreetP10", "MarketWestP10", "EnvironmentP9"]
const POP_ORDER := ["PopulationP10", "ActivityP10", "CoreP10", "ActivityCoreP10", "EntranceCueP10", "OuterP10", "ActivityOuterP10"]
const MAX_ITEMS := 90
const COHESION := 2.5
const SPAN_MAX := 20.0
const REF_DIST := {"field": 6.0, "route": 6.0, "building": 4.5, "water": 6.0, "work_surface": 7.0, "storage": 4.0, "bridge": 7.0}
const ZONE_RANGE := {"A": [5, 5], "B": [5, 5], "C": [0, 0]}   # 使用者裁定 2026-10-08：A 5・B 5・C 水岸擴張 0
const SEAL := "res://data/village_v2_p10r4b_seal.json"
const SNAPSHOT := "res://data/village_v2_p10r4b_snapshot.json"
const APPROVED_R3 := "docs/art_review/village_v2_p10_props/human_use_exp_b1/gate/plan_r3.json"   # 使用者が審圖した r3 の計画（repo 相対）
const R4_THRESH := ["hu_senba", "hu_tomi", "hu_momiboshi"]
const COMMON_HH := ["sk_teoke", "kr_houki", "hu_seoikago", "sk_tensui"]
var fails := 0


func check(msg: String, ok: bool) -> void:
	print("[HUX] %s %s" % ["PASS" if ok else "FAIL", msg])
	if not ok:
		fails += 1


func info(msg: String) -> void:
	print("[HUX] INFO " + msg)


func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	var args := OS.get_cmdline_user_args()
	if ("--attach" in args or "--build" in args) and _sealed() and OS.get_environment("HUX_ALLOW_REBAKE") != "1":
		check("P10 R4b Batch 1 A/B FINAL 封存中（%s）：--build／--attach は拒否（使用者が reopen した時だけ HUX_ALLOW_REBAKE=1、封存を更新すること）" % SEAL, false)
		quit(1)
		return
	if "--attach" in args:
		quit(_attach())
		return
	var v: Node3D = (load(SCENE) as PackedScene).instantiate()
	if "--seal" in args:
		root.add_child(v)
		await physics_frame
		quit(_seal(v))
		return
	for s0: String in args:
		if s0.begins_with("--snapshot="):
			root.add_child(v)
			await physics_frame
			_snapshot(v, s0.trim_prefix("--snapshot="))
			quit(0)
			return
	if "--scene" in args:
		root.add_child(v)
		await physics_frame
		await _scene(v)
		print("[HUX] 結果：%d 項失敗（scene）" % fails)
		quit(fails)
		return
	var own := v.get_node_or_null(HX.NODE_NAME)
	if own:
		own.get_parent().remove_child(own)
		own.free()
	root.add_child(v)
	await physics_frame
	var mp := _meadow(v)
	var P := HX.plan(v, mp)
	_plan_checks(P)
	for s: String in args:
		if s.begins_with("--dump="):
			_dump(P, s.trim_prefix("--dump="))
	if "--negatives" in args:
		_negatives(P)
	if "--build" in args:
		_build(P)
	print("[HUX] 結果：%d 項失敗" % fails)
	quit(fails)


## MeadowP9 規劃株：R5-3 封存時の Props で同 seed 再計算（EnvironmentP9・R4・R4b は不可視）
func _meadow(v: Node3D) -> PackedVector2Array:
	var t0 := Time.get_ticks_msec()
	var cache := ""
	for s: String in OS.get_cmdline_user_args():
		if s.begins_with("--meadow-cache="):
			cache = s.trim_prefix("--meadow-cache=")
	if cache != "" and FileAccess.file_exists(cache):
		var raw: Array = JSON.parse_string(FileAccess.get_file_as_string(cache))
		var pc := PackedVector2Array()
		for i in range(0, raw.size(), 2):
			pc.append(Vector2(raw[i], raw[i + 1]))
		info("MeadowP9 規劃株：キャッシュ %s（%d 株、設計反復用）" % [cache, pc.size()])
		return pc
	var held: Array = []
	for nm in ["GroundcoverP9", "MeadowP9"]:
		var o := v.get_node_or_null("Vegetation/" + nm)
		if o:
			held.append([o, o.get_parent(), o.get_index()])
			o.get_parent().remove_child(o)
	var hid: Array = []
	for nm in ["Props/EnvironmentP9", HU.NODE_NAME, HX.NODE_NAME]:
		var o := v.get_node_or_null(nm) as Node3D
		if o and o.visible:
			o.visible = false
			hid.append(o)
	var Pm: Dictionary = MD.base_plan(v)
	var MC := MD.context(Pm, v)
	var Fm := MD.fields(Pm, MC)
	var Mm := MD.plan(Pm, MC, Fm)
	for o: Node3D in hid:
		o.visible = true
	for h: Array in held:
		(h[1] as Node).add_child(h[0])
		(h[1] as Node).move_child(h[0], int(h[2]))
	var pts: PackedVector2Array = Mm["p"]
	info("MeadowP9 規劃株を同 seed で再計算 %d ms：%d 株" % [Time.get_ticks_msec() - t0, pts.size()])
	if cache != "":
		var raw: Array = []
		for q in pts:
			raw.append(snappedf(q.x, 0.001))
			raw.append(snappedf(q.y, 0.001))
		var f := FileAccess.open(cache, FileAccess.WRITE)
		f.store_string(JSON.stringify(raw))
		f.close()
	return pts


# ─────────────────────────── helpers ───────────────────────────

func _edge_d(C: Dictionary, a: Dictionary, b: Dictionary) -> float:
	var pa := HU.corners(C, a)
	var pb := HU.corners(C, b)
	if not Geometry2D.intersect_polygons(pa, pb).is_empty():
		return 0.0
	var d := 1e9
	for i in 4:
		for q in pb:
			d = minf(d, Geometry2D.get_closest_point_to_segment(q, pa[i], pa[(i + 1) % 4]).distance_to(q))
		for q in pa:
			d = minf(d, Geometry2D.get_closest_point_to_segment(q, pb[i], pb[(i + 1) % 4]).distance_to(q))
	return d


func _is_micro(C: Dictionary, id: String) -> bool:
	return HU.long_side(C, id) < 0.35 and HU.height(C, id) < 0.35


func _is_mid(C: Dictionary, id: String) -> bool:
	return HU.height(C, id) >= 0.9 or HU.long_side(C, id) >= 1.6


func _ref_ok(C: Dictionary, cl: Dictionary) -> bool:
	var r: Vector2 = cl["ref"]
	match String(cl["anchor"]):
		"field":
			return not is_nan((C["P8"] as RLib.TriSampler).h(r.x, r.y))
		"route":
			return not is_nan((C["R"] as RLib.TriSampler).h(r.x, r.y))
		"water":
			return not is_nan((C["WS"] as RLib.TriSampler).h(r.x, r.y))
		"bridge":
			return (C["bridges"] as Array).any(func(b: Rect2) -> bool: return b.has_point(r))
		"building":
			for b: Dictionary in C["bld"]:
				if String(b["name"]) == String(cl.get("bld", "")):
					return absf(SL.obb_d(b, r)) <= 0.05
			return false
		"work_surface":
			for g in (C["hero_g"] as HU.Grid).at(r) + (C["sealed_g"] as HU.Grid).at(r) + (C["p10_g"] as HU.Grid).at(r):
				if (g as Rect2).has_point(r):
					return true
			return false
	return false


func _of(items: Array, cl_id: String) -> Array:
	return items.filter(func(it: Dictionary) -> bool: return String(it["cluster"]) == cl_id)


func _cohesion(C: Dictionary, items: Array) -> Array:
	var bad: Array = []
	for it: Dictionary in items:
		var best := 1e9
		for o: Dictionary in items:
			if o != it and String(o["cluster"]) == String(it["cluster"]):
				best = minf(best, _edge_d(C, it, o))
		if best > COHESION:
			bad.append("%s@%s %.1f m" % [it["id"], it["cluster"], best])
	return bad


func _sig(items: Array) -> Dictionary:
	var sig := {}
	for it: Dictionary in items:
		var k := String(it["cluster"])
		if not sig.has(k):
			sig[k] = {}
		sig[k][String(it["id"])] = int(sig[k].get(String(it["id"]), 0)) + 1
	return sig


func _jaccard(a: Dictionary, b: Dictionary) -> float:
	var inter := 0
	var uni := 0
	var keys: Array = a.keys()
	for k in b.keys():
		if not a.has(k):
			keys.append(k)
	for k in keys:
		inter += mini(int(a.get(k, 0)), int(b.get(k, 0)))
		uni += maxi(int(a.get(k, 0)), int(b.get(k, 0)))
	return float(inter) / maxf(1.0, float(uni))


## R4（封存）の cluster の組成：snapshot から
func _r4_sig() -> Dictionary:
	var snap: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(R4_SNAPSHOT))
	return _sig(snap["items"])


func _asset_bad(C: Dictionary, items: Array) -> Array:
	var bad: Array = []
	for it: Dictionary in items:
		var id := String(it["id"])
		var pre := id.substr(0, 3)
		if not (HU.KIT_OF.has(pre) or pre == HX.NEW_PREFIX) or not C["D"].has(id):
			bad.append(id + "（kit 外）")
			continue
		if HX.ALLOW.has(pre) and not (id in HX.ALLOW[pre]):
			bad.append(id + "（Hero 固有・店の中身）")
		if pre == HX.NEW_PREFIX and not (id in HX.NEW_IDS):
			bad.append(id + ("（ART_REJECTED の rejected candidate）" if id in HX.REJECTED_NEW_IDS else "（新規の登録外）"))
		for lod in ["", "_l1"]:
			if not ResourceLoader.exists(HX.mesh_dir(id) + id + lod + ".res"):
				bad.append(id + lod + "（mesh なし）")
	return bad


## 岸の割合：水面の縁（4 m 格子）のうち、R4＋R4b の生活痕跡から 6 m 以内の割合
func _bank_share(C: Dictionary, items: Array) -> Array:
	var WS: RLib.TriSampler = C["WS"]
	var pts: Array = []
	for it: Dictionary in items:
		pts.append(it["p"])
	var snap: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(R4_SNAPSHOT))
	for it: Dictionary in snap["items"]:
		pts.append(Vector2(float(it["position"][0]), float(it["position"][2])))
	var bank := 0
	var used := 0
	for i in range(100, 560, 4):
		for j in range(-260, 150, 4):
			var p := Vector2(i, j)
			if is_nan(WS.h(p.x, p.y)):
				continue
			var edge := false
			for o in [Vector2(4, 0), Vector2(-4, 0), Vector2(0, 4), Vector2(0, -4)]:
				if is_nan(WS.h(p.x + o.x, p.y + o.y)):
					edge = true
			if not edge:
				continue
			bank += 1
			if pts.any(func(q: Vector2) -> bool: return q.distance_to(p) < 6.0):
				used += 1
	return [bank, used]


# ─────────────────────────── plan gate ───────────────────────────

func _plan_checks(P: Dictionary) -> void:
	var C: Dictionary = P["C"]
	var items: Array = P["items"]
	var clusters: Array = P["clusters"]
	info("文脈 R4 %d ms＋拡張 %d ms・計画 %d 件／%d cluster、落とした %d、地面 decal %d 面群、R4 件 %d" % [C["ms"], C["exp_ms"], items.size(), clusters.size(),
		(C["dropped"] as Array).size(), C["n_ground_decal"], C["n_r4"]])
	for d in C["dropped"]:
		info("  落とした：" + str(d))
	# 1 資產：重用優先・新規は缺件だけ
	var kit_j: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/village_v2/%s/src/modules_blender.json" % HX.NEW_KIT))
	var new_ok := true
	var new_txt: Array = []
	for n: String in kit_j["modules"]:
		var m: Dictionary = kit_j["modules"][n]
		if not n.ends_with("_l1"):
			new_txt.append("%s %d△" % [n, int(m["tris"])])
			new_ok = new_ok and int(m["tris"]) <= 800 and (n in HX.NEW_IDS or n in HX.REJECTED_NEW_IDS)
		for mt in m["mats"]:
			new_ok = new_ok and String(mt) in ["V2_Wood", "ST_Street"]
	var ids := {}
	var reuse := 0
	for it: Dictionary in items:
		ids[String(it["id"])] = int(ids.get(String(it["id"]), 0)) + 1
		if not String(it["id"]).begins_with(HX.NEW_PREFIX):
			reuse += 1
	var ab := _asset_bad(C, items)
	check("資產：%d 種 %d 件、既存 Kit・R4 humanuse_kit の重用 %d 件（%.0f %%）、新規 %s の配置は缺件 %d 種だけ（kit：%s；rejected candidate %s は配置しない；LOD0 ≤ 800△・材質 V2_Wood／ST_Street）；Hero 固有・kit 外・mesh 欠け・rejected %s" % [
		ids.size(), items.size(), reuse, 100.0 * reuse / maxf(1, items.size()), HX.NEW_KIT, HX.NEW_IDS.size(), "、".join(new_txt), str(HX.REJECTED_NEW_IDS), str(ab)],
		ab.is_empty() and new_ok and reuse * 100 >= 80 * items.size())
	# 2 設計どおり・構成
	var zc := {}
	var n_design := 0
	var short: Array = []
	var n_min := 999
	for cl: Dictionary in clusters:
		zc[String(cl["zone"])] = int(zc.get(String(cl["zone"]), 0)) + 1
		n_design += int(cl["n_design"])
		n_min = mini(n_min, int(cl["n"]))
		if int(cl["n"]) != int(cl["n_design"]):
			short.append(cl["id"])
	check("設計どおり：%d cluster、設計 %d 件すべて合法な位置に置けた（落とし %d・欠け cluster %s）" % [clusters.size(), n_design, (C["dropped"] as Array).size(), str(short)],
		(C["dropped"] as Array).is_empty() and short.is_empty())
	var ob := _official_bad(clusters, items)
	check("正式の Batch 1（使用者裁定 2026-10-08）：群 %d（＝%d）＝A 農田 %d（＝5）・B 住宅 %d（＝5）・C 水岸擴張 %d（＝0、ART_REJECTED）、各群 ≥ 3 件（最小 %d）、件數 %d ≤ %d；rejected 群 %s・rejected 資產 %s は出力しない——違反 %s" % [
		clusters.size(), HX.OFFICIAL_CLUSTERS, zc.get("A", 0), zc.get("B", 0), zc.get("C", 0), n_min, items.size(), MAX_ITEMS, str(HX.REJECTED_CLUSTERS), str(HX.REJECTED_NEW_IDS), str(ob)],
		ob.is_empty() and n_min >= 3 and items.size() <= MAX_ITEMS)
	var sv := _plan_vs_snapshot(items)
	if sv.size() == 1 and String(sv[0]) == "no-snapshot":
		info("snapshot なし（封存前）：計画＝snapshot の照合は省略")
	else:
		check("計画＝封存 snapshot（%s）：全件の id・zone・cluster・who・why・anchor・位置 ≤ 1 cm・朝向 ≤ 0.5°——不符 %s" % [SNAPSHOT, str(sv.slice(0, 4))], sv.is_empty())
	# 3 中型の輪郭
	var no_mid: Array = []
	var micro_heavy: Array = []
	var n_micro := 0
	for cl: Dictionary in clusters:
		var mine := _of(items, String(cl["id"]))
		var has_mid := false
		var mc := 0
		for it: Dictionary in mine:
			has_mid = has_mid or _is_mid(C, String(it["id"]))
			if _is_micro(C, String(it["id"])):
				mc += 1
		if not has_mid:
			no_mid.append(cl["id"])
		n_micro += mc
		if mc * 100 > 34 * maxi(1, mine.size()):
			micro_heavy.append("%s %d/%d" % [cl["id"], mc, mine.size()])
	check("中型の輪郭：全群に高さ ≥ 0.9 m か長辺 ≥ 1.6 m の核（無い %s）、微小物 群ごと ≤ 34 %%（超過 %s）・全體 %d/%d（≤ 15 %%）" % [str(no_mid), str(micro_heavy), n_micro, items.size()],
		no_mid.is_empty() and micro_heavy.is_empty() and n_micro * 100 <= 15 * items.size())
	# 4 誰が・なぜ・依附
	var no_story := 0
	for it: Dictionary in items:
		if String(it["who"]).strip_edges() == "" or String(it["why"]).strip_edges() == "" or not (String(it["anchor"]) in HX.ANCHOR_TYPES):
			no_story += 1
	check("「誰が使う？なぜここ？」：全 %d 件に who・why・anchor 型——欠け %d" % [items.size(), no_story], no_story == 0)
	var ref_bad: Array = []
	var ref_txt: Array = []
	for cl: Dictionary in clusters:
		var dmin := 1e9
		for it: Dictionary in _of(items, String(cl["id"])):
			for q in HU.corners(C, it):
				dmin = minf(dmin, q.distance_to(cl["ref"]))
		var lim: float = REF_DIST[String(cl["anchor"])]
		var rk := _ref_ok(C, cl)
		ref_txt.append("%s %s %.1f m" % [cl["id"], cl["anchor"], dmin])
		if not rk or dmin > lim:
			ref_bad.append("%s（型 %s、%.1f m > %.1f）" % [cl["id"], "OK" if rk else "NG", dmin, lim])
	check("依附：依附先の点が宣言どおりの型（田・農道・建物の裏の壁・水面・橋・作業面）、最寄りの件まで上限内——%s；違反 %s" % ["、".join(ref_txt), str(ref_bad)], ref_bad.is_empty())
	# 5 禁區・接地（見えている最上面）
	var bad: Array = []
	var worst := 0.0
	var on_raised := 0
	for it: Dictionary in items:
		var w := HX.why(C, it, items)
		if w != "":
			bad.append("%s@%s %s" % [it["id"], it["cluster"], w])
		worst = maxf(worst, HX.relief(C, it))
		var p: Vector2 = it["p"]
		if HX.top_h(C, p) > (C["S"] as RLib.TriSampler).h(p.x, p.y) + 0.01:
			on_raised += 1
	check("禁區：R4 の全禁區（路面・店先帯・建物・戸口・背戸の通り道・水・P7・橋・Hero・P8 の田／畦／水路・封存 overlay・樹幹・EnvironmentP9・NPC・MeadowP9）＋核心商業區（市場中心 r %.0f m・P10 市集／主街／市集西の構件 +%.0f m）＋R4 の 50 件 +%.1f m・R4 Pilot 区 +%.0f m → 違反 %d %s" % [
		HX.CORE_R, HX.P10_COMMERCE_PAD, HX.R4_PAD, HX.R4_ZONE_PAD, bad.size(), str(bad.slice(0, 6))], bad.is_empty())
	check("接地＝見えている最上面：地形・路面・P4 院子・P8・封存 overlay の地面 decal の max を足元 5 点で取り、その最低点に置く（地形より高い面に乗る件 %d／%d）、足元の起伏 最大 %.3f m（≤ %.2f）" % [
		on_raised, items.size(), worst, HU.RELIEF_MAX], worst <= HU.RELIEF_MAX)
	# 6 封存を崩さない：MeadowP9・EnvironmentP9・NPC
	var gin := 0
	for it: Dictionary in items:
		gin += HU.meadow_in(C, HU.aabb2(C, it).grow(HU.MEADOW_PAD))
	check("MeadowP9 不重烘：規劃株 %d のうち拡張の AABB +%.1f m 内 %d 株（= 0）" % [int(C["meadow_n"]), HU.MEADOW_PAD, gin], gin == 0 and int(C["meadow_n"]) > 100000)
	var env_min := 1e9
	var npc_min := 1e9
	for it: Dictionary in items:
		for a: Vector2 in C["env_anchor"]:
			env_min = minf(env_min, (it["p"] as Vector2).distance_to(a))
		for t: Vector2 in C["npc"]:
			for q in HU.corners(C, it):
				npc_min = minf(npc_min, q.distance_to(t))
	check("EnvironmentP9：構件から ≥ %.1f m・錨から ≥ %.1f m（最近 %.1f m）；NPC 51 人（増やさない・動かさない）の立ち位置まで最近 %.2f m（≥ %.1f）・往復路 +%.1f、Marker3D なし" % [
		HU.ENV_PAD, HU.ENV_ANCHOR_PAD, env_min, npc_min, HU.NPC_PAD, HU.PATROL_PAD], env_min >= HU.ENV_ANCHOR_PAD and npc_min >= HU.NPC_PAD and (C["npc"] as Array).size() == 51)
	# 7 成組
	var coh := _cohesion(C, items)
	var span_bad: Array = []
	for cl: Dictionary in clusters:
		var mine := _of(items, String(cl["id"]))
		var r := Rect2(mine[0]["p"], Vector2.ZERO)
		for it: Dictionary in mine:
			r = r.expand(it["p"])
		if r.size.length() > SPAN_MAX:
			span_bad.append("%s %.1f m" % [cl["id"], r.size.length()])
	check("成組：各件は同じ群の別の件から ≤ %.1f m（孤立 %s）、群の広がり ≤ %.0f m（超過 %s）" % [COHESION, str(coh), SPAN_MAX, str(span_bad)], coh.is_empty() and span_bad.is_empty())
	# 8 非均一・複製なし
	var sig := _sig(items)
	var r4 := _r4_sig()
	var jr4 := 0.0
	var jr4_txt := ""
	for k in sig:
		for k4 in r4:
			var j := _jaccard(sig[k], r4[k4])
			if j > jr4:
				jr4 = j
				jr4_txt = "%s↔R4 %s" % [k, k4]
	var thresh: Array = []
	for k in sig:
		if R4_THRESH.all(func(id: String) -> bool: return (sig[k] as Dictionary).has(id)):
			thresh.append(k)
	var jb := 0.0
	var bkeys: Array = []
	for cl: Dictionary in clusters:
		if String(cl["zone"]) == "B":
			bkeys.append(String(cl["id"]))
	for i in bkeys.size():
		for j in range(i + 1, bkeys.size()):
			jb = maxf(jb, _jaccard(sig[bkeys[i]], sig[bkeys[j]]))
	var jall := 0.0
	var keys := sig.keys()
	for i in keys.size():
		for j in range(i + 1, keys.size()):
			jall = maxf(jall, _jaccard(sig[keys[i]], sig[keys[j]]))
	var rep_bad: Array = []
	for z in ["A", "B", "C"]:
		var cnt := {}
		for cl: Dictionary in clusters:
			if String(cl["zone"]) != z:
				continue
			for id in sig[String(cl["id"])]:
				cnt[id] = int(cnt.get(id, 0)) + 1
		for id in cnt:
			if int(cnt[id]) > 2:
				rep_bad.append("%s:%s×%d" % [z, id, cnt[id]])
	var common := 0
	for k in bkeys:
		if COMMON_HH.any(func(id: String) -> bool: return (sig[k] as Dictionary).has(id)):
			common += 1
	check("非均一：R4 の 10 群との組成類似度 最大 %.2f（≤ 0.50、%s）・R4 の脫穀一式（千歯＋唐箕＋籾干し）の再利用 %s・本批の群どうし最大 %.2f（≤ 0.50）・住宅 %d 戸どうし最大 %.2f（≤ 0.34）・同じ物が一つの區で 3 群以上 %s・桶／手桶／箒／籠のある戸 %d／%d（≤ 2）" % [
		jr4, jr4_txt, str(thresh), jall, bkeys.size(), jb, str(rep_bad), common, bkeys.size()],
		jr4 <= 0.5 and thresh.is_empty() and jall <= 0.5 and jb <= 0.34 and rep_bad.is_empty() and common <= 2)
	var bs := _bank_share(C, items)
	check("自然の岸を残す：水面の縁 %d 格（4 m）のうち生活痕跡（R4＋R4b）から 6 m 以内 %d 格（%.0f %%、≤ 15 %%）、本批の水岸群 %d（＝0：C 水岸擴張は ART_REJECTED、R4 Pilot C は封存のまま）" % [
		int(bs[0]), int(bs[1]), 100.0 * int(bs[1]) / maxf(1, int(bs[0])), zc.get("C", 0)], int(bs[0]) > 100 and int(bs[1]) * 100 <= 15 * int(bs[0]) and int(zc.get("C", 0)) == 0)
	for cl: Dictionary in clusters:
		info("%s（%s・%s、%s）：%s" % [cl["id"], HX.ZONE_NAME[String(cl["zone"])], cl["anchor"], cl["anchor_desc"], "・".join(_of(items, String(cl["id"])).map(func(it: Dictionary) -> String: return String(it["id"])))])


func _dump(P: Dictionary, path: String) -> void:
	var out: Array = []
	for it: Dictionary in P["items"]:
		out.append({"id": it["id"], "zone": it["zone"], "cluster": it["cluster"], "anchor": it["anchor"], "who": it["who"], "why": it["why"],
			"p": [snappedf((it["p"] as Vector2).x, 0.01), snappedf(float(it["y"]), 0.01), snappedf((it["p"] as Vector2).y, 0.01)],
			"yaw_deg": snappedf(rad_to_deg(float(it["yaw"])), 0.1)})
	var cls: Array = []
	for c: Dictionary in P["clusters"]:
		cls.append({"id": c["id"], "zone": c["zone"], "anchor": c["anchor"], "anchor_desc": c["anchor_desc"], "n": c["n"], "n_design": c["n_design"],
			"center": [snappedf((c["center"] as Vector2).x, 0.01), snappedf((c["center"] as Vector2).y, 0.01)],
			"ref": [snappedf((c["ref"] as Vector2).x, 0.01), snappedf((c["ref"] as Vector2).y, 0.01)]})
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"art_revision": HX.ART_REVISION, "zones": HX.ZONE_NAME, "items": out, "clusters": cls}, "\t"))
	f.close()
	info("計画 → " + path)


# ─────────────────────────── 反向 ───────────────────────────

func _neg(name: String, caught: bool) -> void:
	check("反向 %s → 偵測" % name, caught)


func _probe(C: Dictionary, items: Array, id: String, p: Vector2) -> String:
	var it := HX.item(C, id, p, Vector2(0, 1), {"zone": "A", "cluster": "NEG", "anchor": "field", "who": "x", "why": "x"})
	return HX.why(C, it, items)


func _negatives(P: Dictionary) -> void:
	var C: Dictionary = P["C"]
	var items: Array = P["items"]
	_neg("核心商業區（市場中心）に置く＝core", _probe(C, items, "sk_box", HX.CORE_CENTER + Vector2(5, 5)) == "core")
	var snap: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(R4_SNAPSHOT))
	var r4p := Vector2(float(snap["items"][3]["position"][0]), float(snap["items"][3]["position"][2]))
	var wr := _probe(C, items, "sk_box", r4p)
	_neg("R4 封存の件の上（%s）に置く＝r4／r4zone（%s）" % [snap["items"][3]["id"], wr], wr in ["r4", "r4zone"])
	_neg("R4 Pilot A の区（381, 10：件の無い所）に置く＝r4zone", _probe(C, items, "sk_box", Vector2(381.0, 10.0)) == "r4zone")
	_neg("P8 の田の中（470, 30）に置く＝p8", _probe(C, items, "sk_box", Vector2(470.0, 30.0)) == "p8")
	_neg("水渠の水面（314, 60）に置く＝water", _probe(C, items, "sk_box", Vector2(314.0, 60.0)) == "water")
	_neg("FarmPath_2 の路面（440, 30）に置く＝road", _probe(C, items, "sk_box", Vector2(440.0, 30.0)) == "road")
	var n0: Vector2 = (C["npc"] as Array)[45]
	var wn := _probe(C, items, "sk_box", n0 + Vector2(0.3, 0.0))
	_neg("NPC の立ち位置 0.3 m（%s）＝npc 等" % wn, wn in ["npc", "core", "commerce"])
	var b048: Dictionary = (C["bld"] as Array).filter(func(b: Dictionary) -> bool: return String(b["name"]) == "B_P_RSW_048")[0]
	var door := (b048["o"] as Vector2) - (b048["az"] as Vector2) * (float(b048["d"]) * 0.5 + 0.9)
	var wd := _probe(C, items, "sk_box", door)
	_neg("背戸の通り道（RSW_048 の裏戸の前 0.9 m）＝backdoor（%s）" % wd, wd in ["backdoor", "building"])
	var it_out := HX.item(C, "sk_box", Vector2(600.0, 600.0), Vector2(0, 1), {"scope": Rect2(0, 0, 10, 10)})
	_neg("群の範圍（中心 ± %.0f m）の外＝scope" % HX.GROUP_R, HX.why(C, it_out, items) == "scope")
	var tmp := C["meadow"] as Dictionary
	var it_m := HX.item(C, "sk_box", Vector2(500.5, 500.5), Vector2(0, 1), {})
	tmp[Vector2i(1001, 1001)] = 1
	var wm2 := HU.meadow_in(C, HU.aabb2(C, it_m).grow(HU.MEADOW_PAD))
	tmp.erase(Vector2i(1001, 1001))
	_neg("足元の AABB +0.4 に MeadowP9 株 1 つ＝計數 %d" % wm2, wm2 == 1)
	# 組成（コピーして壊す）
	var thr: Array = items.duplicate(true)
	var xa1 := _of(thr, "XA1_shukka")
	for k in mini(3, xa1.size()):
		(xa1[k] as Dictionary)["id"] = R4_THRESH[k]
	var sg := _sig(thr)
	_neg("XA1 を R4 の脫穀一式（千歯＋唐箕＋籾干し）に差し替える", R4_THRESH.all(func(id: String) -> bool: return (sg["XA1_shukka"] as Dictionary).has(id)))
	var dup: Array = items.duplicate(true)
	var b1 := _of(dup, "XB1_some")
	var b2 := _of(dup, "XB2_okeya")
	for k in mini(b1.size(), b2.size()):
		(b2[k] as Dictionary)["id"] = b1[k]["id"]
	var sd := _sig(dup)
	_neg("XB2 を XB1 と同じ組成にする（Jaccard %.2f > 0.34）" % _jaccard(sd["XB1_some"], sd["XB2_okeya"]), _jaccard(sd["XB1_some"], sd["XB2_okeya"]) > 0.34)
	var r4 := _r4_sig()
	_neg("R4 の B1（堆柴戶）をそのまま写す（Jaccard 1.00 > 0.50）", _jaccard(r4["B1_maki"], r4["B1_maki"]) > 0.5)
	var iso: Array = items.duplicate(true)
	(iso[1] as Dictionary)["p"] = (iso[1]["p"] as Vector2) + Vector2(12.0, 25.0)
	_neg("1 件を群から 28 m 離す＝孤立", not _cohesion(C, iso).is_empty())
	_neg("霧雨店の茸（kr_kinoko）・鈴奈庵の本箱（sz_hako）を使う＝Hero 固有", not _asset_bad(C, [{"id": "kr_kinoko"}]).is_empty() and not _asset_bad(C, [{"id": "sz_hako"}]).is_empty())
	_neg("依附先の型を偽る（橋の ref を田の中へ）", not _ref_ok(C, {"anchor": "bridge", "ref": Vector2(470.0, 30.0)}))
	# 使用者裁定の正式構成（rejected の C 群を戻す・rejected 資產を使う・A/B を 1 群減らす）
	var rc: Array = (P["clusters"] as Array).duplicate(true)
	var ri: Array = items.duplicate(true)
	for cl: Dictionary in HX.rejected_c():
		rc.append({"id": cl["id"], "zone": cl["zone"]})
		for e: Array in cl["items"]:
			ri.append({"id": e[0], "cluster": cl["id"], "zone": "C"})
	var rb := _official_bad(rc, ri)
	_neg("rejected_c()（ART_REJECTED の水岸 3 群）を正式計画に戻す（%d 件の違反）" % rb.size(), not rb.is_empty())
	var di: Array = items.duplicate(true)
	(di[0] as Dictionary)["id"] = "hx_doroage"
	_neg("rejected candidate hx_doroage を配置する", not _official_bad(P["clusters"], di).is_empty() and not _asset_bad(C, [{"id": "hx_doroage"}]).is_empty())
	var lc: Array = (P["clusters"] as Array).duplicate(true)
	lc.pop_back()
	_neg("B を 1 群減らす（10 群でなくなる）", not _official_bad(lc, items).is_empty())


# ─────────────────────────── 正式構成・snapshot・封存 ───────────────────────────

## 使用者裁定 2026-10-08 の正式構成からの逸脱（空＝OK）
func _official_bad(clusters: Array, items: Array) -> Array:
	var bad: Array = []
	var zc := {}
	for cl: Dictionary in clusters:
		zc[String(cl["zone"])] = int(zc.get(String(cl["zone"]), 0)) + 1
		if String(cl["id"]) in HX.REJECTED_CLUSTERS:
			bad.append("rejected 群 " + String(cl["id"]))
	if clusters.size() != HX.OFFICIAL_CLUSTERS:
		bad.append("群 %d≠%d" % [clusters.size(), HX.OFFICIAL_CLUSTERS])
	for z: String in HX.OFFICIAL_ZONES:
		if int(zc.get(z, 0)) != int(HX.OFFICIAL_ZONES[z]):
			bad.append("%s %d≠%d" % [z, int(zc.get(z, 0)), int(HX.OFFICIAL_ZONES[z])])
	for z in zc:
		if not HX.OFFICIAL_ZONES.has(z):
			bad.append("未知の區 " + str(z))
	for it: Dictionary in items:
		if String(it["id"]) in HX.REJECTED_NEW_IDS:
			bad.append("rejected 資產 " + String(it["id"]))
		if String(it.get("zone", "")) == "C" or String(it.get("cluster", "")) in HX.REJECTED_CLUSTERS:
			bad.append("C の件 %s@%s" % [it["id"], it.get("cluster", "?")])
	return bad


func _snap_yaw_ok(a_deg: float, b_deg: float) -> bool:
	return absf(angle_difference(deg_to_rad(a_deg), deg_to_rad(b_deg))) <= deg_to_rad(0.5)


## 計画の全件＝封存 snapshot（node 名 %03d_<id> で対応）
func _plan_vs_snapshot(items: Array) -> Array:
	if not FileAccess.file_exists(SNAPSHOT):
		return ["no-snapshot"]
	var snap: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SNAPSHOT))
	var by := {}
	for w: Dictionary in snap["items"]:
		by[String(w["name"])] = w
	var bad: Array = []
	if by.size() != items.size():
		bad.append("件数 %d≠%d" % [items.size(), by.size()])
	for i in items.size():
		var it: Dictionary = items[i]
		var nm := "%03d_%s" % [i, it["id"]]
		var w: Dictionary = by.get(nm, {})
		if w.is_empty():
			bad.append(nm + " 無い")
			continue
		var q: Array = w["position"]
		var p2: Vector2 = it["p"]
		if Vector3(p2.x, float(it["y"]), p2.y).distance_to(Vector3(q[0], q[1], q[2])) > 0.01 or not _snap_yaw_ok(rad_to_deg(float(it["yaw"])), float(w["yaw_deg"])):
			bad.append(nm + " 位置／朝向")
		for k in ["id", "zone", "cluster", "who", "why", "anchor"]:
			if String(it[k]) != String(w[k]):
				bad.append("%s %s" % [nm, k])
	return bad


func _live(v: Node3D) -> Array:
	var go := v.get_node_or_null(HX.NODE_NAME) as Node3D
	var out: Array = []
	if go == null:
		return out
	for n in go.find_children("*", "Node3D", true, false):
		if n.has_meta("hu_id"):
			var xf := (n as Node3D).global_transform
			out.append({"node": String(go.get_path_to(n)), "name": String(n.name), "id": String(n.get_meta("hu_id")), "zone": String(n.get_meta("hu_zone")),
				"cluster": String(n.get_meta("hu_cluster")), "anchor": String(n.get_meta("hu_anchor")), "who": String(n.get_meta("hu_who")),
				"why": String(n.get_meta("hu_why")), "position": [snappedf(xf.origin.x, 0.001), snappedf(xf.origin.y, 0.001), snappedf(xf.origin.z, 0.001)],
				"yaw_deg": snappedf(rad_to_deg(xf.basis.get_euler().y), 0.01)})
	return out


func _snapshot(v: Node3D, path: String) -> void:
	var items := _live(v)
	var cl := {}
	var zn := {}
	for it: Dictionary in items:
		cl[it["cluster"]] = int(cl.get(it["cluster"], 0)) + 1
		zn[it["zone"]] = int(zn.get(it["zone"], 0)) + 1
	var out := {"schema": 1, "scope": "P10 R4b Human-Use Expansion Batch 1 A/B FINAL：HumanUseExpansionP10（root 直下・HumanUseP10 の次）の全件；C 水岸 3 群は ART_REJECTED で含まない",
		"art_revision": String((v.get_node(HX.NODE_NAME) as Node).get_meta("art_revision")), "total": items.size(), "clusters": cl, "zones": zn, "items": items}
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "\t") + "\n")
	f.close()
	print("[HUX] snapshot → %s（%d 件、%d cluster）" % [path, items.size(), cl.size()])


func _sealed() -> bool:
	if not FileAccess.file_exists(SEAL):
		return false
	var j = JSON.parse_string(FileAccess.get_file_as_string(SEAL))
	return j is Dictionary and String(j.get("status", "")) == "ART_APPROVED"


func _repo() -> String:
	return (ProjectSettings.globalize_path("res://") + "..").simplify_path() + "/"


func _seal_mismatch(seal: Dictionary) -> Array:
	var bad: Array = []
	for grp: String in ["frozen", "evidence", "art_review_images", "rejected_candidates", "child_seals"]:
		var d: Dictionary = seal.get(grp, {})
		for k: String in d:
			if not FileAccess.file_exists(_repo() + k) or FileAccess.get_sha256(_repo() + k) != String(d[k]):
				bad.append(k)
	return bad


## 場景の全件＝snapshot（node path で対応、位置 ≤ 1 cm・朝向 ≤ 0.5°・id／zone／cluster／anchor／who／why）
func _live_mismatch(v: Node3D, snap: Dictionary) -> Array:
	var bad: Array = []
	var live := {}
	for it: Dictionary in _live(v):
		live[it["node"]] = it
	var want: Array = snap["items"]
	if live.size() != want.size():
		bad.append("件数 %d≠%d" % [live.size(), want.size()])
	for w: Dictionary in want:
		var it: Dictionary = live.get(String(w["node"]), {})
		if it.is_empty():
			bad.append(String(w["node"]) + " 無い")
			continue
		var p: Array = it["position"]
		var q: Array = w["position"]
		if Vector3(p[0], p[1], p[2]).distance_to(Vector3(q[0], q[1], q[2])) > 0.01 or not _snap_yaw_ok(float(it["yaw_deg"]), float(w["yaw_deg"])):
			bad.append(String(w["node"]) + " 位置／朝向")
		for k in ["id", "zone", "cluster", "anchor", "who", "why"]:
			if String(it[k]) != String(w[k]):
				bad.append("%s %s" % [w["node"], k])
	return bad


## snapshot の件＝承認時（r3 審圖）の A/B 件（C を除く）：cluster・id が同じ物の最寄りが 2 cm 以内・朝向 ≤ 0.5°・who／why 同じ、件数一致
func _approved_mismatch(snap_items: Array, r3: Dictionary) -> Array:
	var ab: Array = (r3["items"] as Array).filter(func(it: Dictionary) -> bool: return String(it["zone"]) != "C")
	var bad: Array = []
	if ab.size() != snap_items.size():
		bad.append("件数 r3 A/B %d≠snapshot %d" % [ab.size(), snap_items.size()])
	var used := {}
	for w: Dictionary in snap_items:
		var q: Array = w.get("position", [0.0, 0.0, 0.0])
		var best := -1
		var bd := 1e9
		for i in ab.size():
			var a: Dictionary = ab[i]
			if used.has(i) or String(a["cluster"]) != String(w["cluster"]) or String(a["id"]) != String(w["id"]):
				continue
			var d := Vector3(a["p"][0], a["p"][1], a["p"][2]).distance_to(Vector3(q[0], q[1], q[2]))
			if d < bd:
				bd = d
				best = i
		if best < 0 or bd > 0.02:
			bad.append("%s %s（%.3f m）" % [w["cluster"], w["id"], bd])
			continue
		used[best] = true
		var a2: Dictionary = ab[best]
		if not _snap_yaw_ok(float(a2["yaw_deg"]), float(w["yaw_deg"])) or String(a2["who"]) != String(w["who"]) or String(a2["why"]) != String(w["why"]):
			bad.append("%s %s 朝向／who／why" % [w["cluster"], w["id"]])
	return bad


## R4 封存 HumanUseP10 の 50 件が R4 snapshot と一致
func _r4_bad(v: Node3D) -> Array:
	var snap: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(R4_SNAPSHOT))
	var hu := v.get_node_or_null(HU.NODE_NAME) as Node3D
	var bad: Array = []
	var n_live := 0
	if hu:
		for n in hu.find_children("*", "Node3D", true, false):
			if n.has_meta("hu_id"):
				n_live += 1
	if n_live != (snap["items"] as Array).size():
		bad.append("件数 %d≠%d" % [n_live, (snap["items"] as Array).size()])
	for w: Dictionary in snap["items"]:
		var n := hu.get_node_or_null(String(w["node"])) as Node3D if hu else null
		var q: Array = w["position"]
		if n == null or n.global_position.distance_to(Vector3(q[0], q[1], q[2])) > 0.01 or String(n.get_meta("hu_id", "")) != String(w["id"]):
			bad.append(String(w["node"]))
	return bad


func _seal(v: Node3D) -> int:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(SEAL))
	if not parsed is Dictionary:
		check("seal manifest が読める", false)
		return 2
	var seal: Dictionary = parsed
	var rj: Dictionary = seal.get("rejected", {})
	check("status ART_APPROVED（A 農田・B 住宅、使用者 2026-10-08；agent は美術を承認しない）＋C 水岸 ART_REJECTED の記録（群 %s・理由が裁定文どおり）" % str(rj.get("clusters", [])),
		String(seal.get("status", "")) == "ART_APPROVED" and String(seal.get("approved_by", "")) == "user" and String(rj.get("status", "")) == "ART_REJECTED"
		and String(rj.get("reason", "")) == HX.REJECTED_REASON and Array(rj.get("clusters", [])) == HX.REJECTED_CLUSTERS)
	var bad := _seal_mismatch(seal)
	var n := 0
	for grp: String in ["frozen", "evidence", "art_review_images", "rejected_candidates", "child_seals"]:
		n += (seal.get(grp, {}) as Dictionary).size()
	check("封存 %d 檔雜湊一致（凍結・證據・審圖・rejected candidates・子封存；不符 %d：%s）" % [n, bad.size(), str(bad.slice(0, 4))], bad.is_empty())
	var roots: Array = []
	for c in v.get_children():
		roots.append(String(c.name))
	var names: Array = []
	for c in v.get_node("Props").get_children():
		names.append(String(c.name))
	var ip := roots.find("Props")
	var txt := FileAccess.get_file_as_string(SCENE)
	var go := v.get_node_or_null(HX.NODE_NAME) as Node3D
	check("掛載：root 直下 Props → %s → %s（各 1 個）、Props の子は封存どおり（%s）、%s" % [HU.NODE_NAME, HX.NODE_NAME, " → ".join(names), HX.OUTPUT],
		ip >= 0 and roots.find(HU.NODE_NAME) == ip + 1 and roots.find(HX.NODE_NAME) == ip + 2 and roots.count(HX.NODE_NAME) == 1 and names == PROPS_SEALED
		and txt.count("p10r4b_human_use_exp") == 2 and go != null and go.scene_file_path == HX.OUTPUT and String(go.get_meta("art_revision", "")) == HX.ART_REVISION)
	var snap: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SNAPSHOT))
	var zn: Dictionary = snap["zones"]
	check("snapshot：%d 件・%d cluster（A %d・B %d・C %d 件）、art_revision＝%s" % [int(snap["total"]), (snap["clusters"] as Dictionary).size(), int(zn.get("A", 0)), int(zn.get("B", 0)), int(zn.get("C", 0)), snap["art_revision"]],
		int(snap["total"]) == int(seal["roster"]["total"]) and (snap["clusters"] as Dictionary).size() == HX.OFFICIAL_CLUSTERS and int(zn.get("C", 0)) == 0
		and String(snap["art_revision"]) == HX.ART_REVISION)
	var lb := _live_mismatch(v, snap)
	check("場景の %d 件が snapshot と一致（位置 ≤ 1 cm・朝向 ≤ 0.5°・id／zone／cluster／anchor／who／why；不符 %s）" % [int(snap["total"]), str(lb.slice(0, 4))], lb.is_empty())
	var r3: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_repo() + APPROVED_R3))
	var am := _approved_mismatch(snap["items"], r3)
	check("A/B は承認時（r3 審圖、%s）から美術の変更なし：snapshot の %d 件＝r3 の A/B 件（2 cm・0.5°・who／why）——不符 %s" % [APPROVED_R3, int(snap["total"]), str(am.slice(0, 4))], am.is_empty())
	var cl_names: Array = []
	if go:
		for z in go.get_children():
			for c in z.get_children():
				cl_names.append(String(c.name))
	var rej_nodes := cl_names.filter(func(nm: String) -> bool: return nm in HX.REJECTED_CLUSTERS)
	var live_c := _live(v).filter(func(it: Dictionary) -> bool: return String(it["zone"]) == "C" or String(it["id"]) in HX.REJECTED_NEW_IDS)
	check("C 水岸の除去：場景に rejected 群のノード %s・C の件／hx_doroage %d、ZoneC なし" % [str(rej_nodes), live_c.size()],
		rej_nodes.is_empty() and live_c.is_empty() and go != null and go.get_node_or_null("ZoneC") == null)
	var r4b := _r4_bad(v)
	check("R4 封存 HumanUseP10 不変：50 件が R4 snapshot と位置 ≤ 1 cm・id 一致（不符 %s）" % str(r4b.slice(0, 3)), r4b.is_empty())
	var nb := v.get_node("Population").find_children("*", "AnimatableBody3D", true, false).size()
	check("Population 51 不変（NPC body %d）" % nb, nb == 51)
	var tam := seal.duplicate(true)
	var k0: String = (tam["frozen"] as Dictionary).keys()[0]
	tam["frozen"][k0] = "0".repeat(64)
	check("反向：凍結雜湊を記憶體内で竄改 → 1 件だけ検出（%d）" % (_seal_mismatch(tam).size() - bad.size()), _seal_mismatch(tam).size() == bad.size() + 1)
	var snap2: Dictionary = snap.duplicate(true)
	snap2["items"][0]["position"][0] = float(snap2["items"][0]["position"][0]) + 0.25
	check("反向：snapshot の 1 件を 0.25 m ずらす → 場景と不一致・承認時 r3 とも不一致", not _live_mismatch(v, snap2).is_empty() and not _approved_mismatch(snap2["items"], r3).is_empty())
	var snap3: Dictionary = snap.duplicate(true)
	snap3["items"][1]["who"] = "誰か"
	check("反向：snapshot の 1 件の who を変える → 不一致を検出", not _live_mismatch(v, snap3).is_empty())
	var r3c: Array = (r3["items"] as Array).filter(func(it: Dictionary) -> bool: return String(it["zone"]) == "C")
	var snap4: Dictionary = snap.duplicate(true)
	for it: Dictionary in r3c:
		(snap4["items"] as Array).append({"node": "ZoneC/%s/x_%s" % [it["cluster"], it["id"]], "zone": "C", "cluster": it["cluster"], "id": it["id"],
			"position": it["p"], "yaw_deg": it["yaw_deg"], "who": it["who"], "why": it["why"], "anchor": it["anchor"]})
	check("反向：rejected の C %d 件を snapshot に戻す → 場景と不一致・承認時 A/B とも不一致" % r3c.size(), not _live_mismatch(v, snap4).is_empty() and not _approved_mismatch(snap4["items"], r3).is_empty())
	print("[HUX] 結果：%d 項失敗（seal）" % fails)
	return 0 if fails == 0 else 2


# ─────────────────────────── build／attach／scene ───────────────────────────

func _build(P: Dictionary) -> void:
	var root_n := HX.bake(P)
	HU.own(root_n, root_n)
	var ps := PackedScene.new()
	check("pack overlay", ps.pack(root_n) == OK)
	check("save %s" % HX.OUTPUT, ResourceSaver.save(ps, HX.OUTPUT, ResourceSaver.FLAG_COMPRESS) == OK)
	root_n.free()
	var r := ResourceLoader.load(HX.OUTPUT, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var rb := r.instantiate() as Node3D
	var mi := rb.find_children("*", "MeshInstance3D", true, false)
	var mm := rb.find_children("*", "MultiMeshInstance3D", true, false).size()
	var mk := rb.find_children("*", "Marker3D", true, false).size()
	var n_it := 0
	var meta_ok := true
	for n in rb.find_children("*", "Node3D", true, false):
		if n.has_meta("hu_id"):
			n_it += 1
			for k in ["hu_who", "hu_why", "hu_anchor", "hu_cluster", "hu_zone"]:
				meta_ok = meta_ok and String(n.get_meta(k, "")) != ""
	check("存檔回讀：構件 %d（計画 %d、meta 付き %d）・MeshInstance %d・碰撞 %d・MultiMesh %d・Marker3D %d、art_revision" % [
		int(rb.get_meta("items")), (P["items"] as Array).size(), n_it, mi.size(), int(rb.get_meta("shapes")), mm, mk],
		int(rb.get_meta("items")) == (P["items"] as Array).size() and n_it == int(rb.get_meta("items")) and mi.size() == 2 * n_it and mm == 0 and mk == 0 and meta_ok
		and String(rb.get_meta("art_revision")) == HX.ART_REVISION)
	rb.free()


func _attach() -> int:
	var txt := FileAccess.get_file_as_string(SCENE)
	if not FileAccess.file_exists(HX.OUTPUT):
		push_error("找不到 %s（先 --build）" % HX.OUTPUT)
		return 1
	var line := "[node name=\"%s\" parent=\".\" instance=ExtResource(\"p10r4b_human_use_exp\")]" % HX.NODE_NAME
	if txt.contains(line):
		print("[HUX] attach：已掛 root/%s（不重複、不寫場景）" % HX.NODE_NAME)
		return 0
	var nl := "\r\n" if txt.contains("\r\n") else "\n"
	var after := "[node name=\"%s\" parent=\".\" instance=ExtResource(\"p10r4_human_use\")]" % HU.NODE_NAME
	if not txt.contains(after):
		push_error("找不到 root/%s（R4 封存の掛載）" % HU.NODE_NAME)
		return 1
	var lines := txt.split(nl)
	var out := PackedStringArray(Array(lines))
	var at := out.find(after)
	out.insert(at + 1, "")
	out.insert(at + 2, line)
	var last_ext := -1
	for k in out.size():
		if out[k].begins_with("[ext_resource"):
			last_ext = k
	out.insert(last_ext + 1, "[ext_resource type=\"PackedScene\" path=\"%s\" id=\"p10r4b_human_use_exp\"]" % HX.OUTPUT)
	var f := FileAccess.open(SCENE, FileAccess.WRITE)
	f.store_string(nl.join(out))
	f.close()
	print("[HUX] attach：加 root/%s（HumanUseP10 の次）→ %s（+%d 行）" % [HX.NODE_NAME, SCENE, out.size() - lines.size()])
	return 0


func _scene(v: Node3D) -> void:
	var roots: Array = []
	for c in v.get_children():
		roots.append(String(c.name))
	var names: Array = []
	for c in v.get_node("Props").get_children():
		names.append(String(c.name))
	var go := v.get_node_or_null(HX.NODE_NAME) as Node3D
	var ih := roots.find(HU.NODE_NAME)
	check("場景已掛 root/%s（1 個、%s の次＝%s）、Props の子は封存どおり（%s）" % [HX.NODE_NAME, HU.NODE_NAME, " → ".join(roots.slice(maxi(0, ih - 1), ih + 3)), " → ".join(names)],
		go != null and roots.count(HX.NODE_NAME) == 1 and ih >= 0 and roots.find(HX.NODE_NAME) == ih + 1 and roots.find("Props") == ih - 1 and names == PROPS_SEALED)
	if go == null:
		return
	check("art_revision＝%s、visible、scene_file_path＝%s" % [go.get_meta("art_revision", "?"), HX.OUTPUT],
		String(go.get_meta("art_revision", "")) == HX.ART_REVISION and go.visible and go.scene_file_path == HX.OUTPUT)
	var mi := go.find_children("*", "MeshInstance3D", true, false)
	var mm := go.find_children("*", "MultiMeshInstance3D", true, false).size()
	var mk := go.find_children("*", "Marker3D", true, false).size()
	check("個別ノード：MeshInstance %d（＝2×%d 件）・MultiMesh %d・Marker3D %d" % [mi.size(), int(go.get_meta("items")), mm, mk], mm == 0 and mk == 0 and mi.size() == 2 * int(go.get_meta("items")))
	# R4 の 50 件は封存 snapshot と独立に一致（拡張は R4 を動かさない）
	var r4bad := _r4_bad(v)
	check("R4 封存 HumanUseP10 不変：50 件が R4 snapshot と位置 ≤ 1 cm・id 一致（不符 %s）" % str(r4bad.slice(0, 3)), r4bad.is_empty())
	var oc := _live(v).filter(func(it: Dictionary) -> bool: return String(it["zone"]) == "C" or String(it["id"]) in HX.REJECTED_NEW_IDS or String(it["cluster"]) in HX.REJECTED_CLUSTERS)
	var zc2 := {}
	for it: Dictionary in _live(v):
		zc2[it["cluster"]] = String(it["zone"])
	check("場景の正式構成：群 %d（＝%d）・C の件／rejected 群／hx_doroage %d（＝0）、ZoneC なし" % [zc2.size(), HX.OFFICIAL_CLUSTERS, oc.size()],
		zc2.size() == HX.OFFICIAL_CLUSTERS and oc.is_empty() and go.get_node_or_null("ZoneC") == null)
	var pop: Array = []
	for c in v.get_node("Population").get_children():
		pop.append(String(c.name))
	var nb := v.get_node("Population").find_children("*", "AnimatableBody3D", true, false).size()
	check("Population 不変：子 %s・NPC body %d（＝51）" % [" → ".join(pop), nb], pop == POP_ORDER and nb == 51)
	var shapes := go.find_children("*", "CollisionShape3D", true, false).size()
	check("碰撞：腰より高い件だけ箱 %d（＝meta %d）" % [shapes, int(go.get_meta("shapes"))], shapes == int(go.get_meta("shapes")) and shapes > 0)
	await _placement(v, go)


func _placement(v: Node3D, go: Node3D) -> void:
	for i in 3:
		await physics_frame
	var sp := v.get_world_3d().direct_space_state
	var D := HX.dims_table()
	var body := go.get_node("Collision") as StaticBody3D
	var terr: Array[RID] = []
	for t in v.find_children("TerrainCollision*", "StaticBody3D", true, false):
		terr.append((t as StaticBody3D).get_rid())
	var nodes: Array = []
	for n in go.find_children("*", "Node3D", true, false):
		if n.has_meta("hu_id"):
			nodes.append(n)
	var res := _audit(sp, D, body, terr, nodes, go)
	var vis_only := 0
	for n in nodes:
		if float(D[String(n.get_meta("hu_id"))][4]) < 0.35:
			vis_only += 1
	check("擺放（接地）：%d 件 × 3×3 ray（%d 本）——FLOATING %d %s、最大の埋まり %.3f m（≤ 0.15、%s）；腰より低い %d 件は visual_only" % [
		nodes.size(), int(res["rays"]), (res["float"] as Array).size(), str(res["float"]), float(res["embed"]), res["embed_who"], vis_only],
		(res["float"] as Array).is_empty() and float(res["embed"]) <= 0.15 and int(res["rays"]) == nodes.size() * 9)
	check("擺放（貫通）：碰撞箱 %d を collide_shape（自分・地形を除く）——OBJECT_PENETRATION %d %s" % [int(res["shapes"]), (res["pen"] as Array).size(), str(res["pen"])],
		(res["pen"] as Array).is_empty() and int(res["shapes"]) > 0)
	var n0: Node3D = nodes[0]
	var keep := n0.global_position
	n0.global_position = keep + Vector3(0, 0.3, 0)
	var r1 := _audit(sp, D, body, terr, [n0], go)
	n0.global_position = keep
	check("擺放 反向 float：%s を 0.3 m 持ち上げる → FLOATING（%s）" % [n0.name, str(r1["float"])], (r1["float"] as Array).size() == 1)
	var cs: CollisionShape3D = go.find_children("*_c", "CollisionShape3D", true, false)[0]
	var keep_t := cs.global_transform
	var C := SL.context(v)
	var best: Dictionary = {}
	var bd := 1e9
	for b: Dictionary in C["bld"]:
		var d := (b["o"] as Vector2).distance_to(Vector2(keep_t.origin.x, keep_t.origin.z))
		if d < bd:
			bd = d
			best = b
	var o2: Vector2 = best["o"]
	var by := keep_t.origin.y
	var hit := sp.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(o2.x, 40.0, o2.y), Vector3(o2.x, -20.0, o2.y)))
	if not hit.is_empty():
		by = float(hit.position.y) - 1.0
	cs.global_transform = Transform3D(keep_t.basis, Vector3(o2.x, by, o2.y))
	for i in 2:
		await physics_frame
	var r2 := _audit(sp, D, body, terr, [], go)
	cs.global_transform = keep_t
	check("擺放 反向 clash：碰撞箱 %s を最寄りの建物 %s へ押し込む → OBJECT_PENETRATION（%d）" % [cs.name, best["name"], (r2["pen"] as Array).size()], not (r2["pen"] as Array).is_empty())


func _audit(sp: PhysicsDirectSpaceState3D, D: Dictionary, body: StaticBody3D, terr: Array[RID], nodes: Array, go: Node3D) -> Dictionary:
	var fl: Array = []
	var embed := 0.0
	var embed_who := ""
	var rays := 0
	for n: Node3D in nodes:
		var d: Array = D[String(n.get_meta("hu_id"))]
		var xf := n.global_transform
		var nf := 0
		for i in 3:
			for j in 3:
				var p := xf * Vector3(lerpf(float(d[0]) + 0.08, float(d[3]) - 0.08, i / 2.0), 0.0, lerpf(float(d[2]) + 0.08, float(d[5]) - 0.08, j / 2.0))
				var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 2.0, 0), p - Vector3(0, 3.0, 0))
				q.exclude = [body.get_rid()]
				var h := sp.intersect_ray(q)
				rays += 1
				if h.is_empty():
					nf += 1
					continue
				var gap := p.y - float(h.position.y)
				if gap > 0.08:
					nf += 1
				elif -gap > embed:
					embed = -gap
					embed_who = "%s←%s" % [n.name, str((h.collider as Node).get_path()) if h.collider is Node else "?"]
		if nf * 10 > 4 * 9:
			fl.append("%s %d/9" % [n.name, nf])
	var pen: Array = []
	var nsh := 0
	var ex: Array[RID] = [body.get_rid()]
	ex.append_array(terr)
	for cs in go.find_children("*", "CollisionShape3D", true, false):
		var c := cs as CollisionShape3D
		nsh += 1
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = c.shape
		q.transform = c.global_transform
		q.exclude = ex
		var pts := sp.collide_shape(q, 16)
		var dmax := 0.0
		for k in range(0, pts.size() - 1, 2):
			dmax = maxf(dmax, (pts[k] as Vector3).distance_to(pts[k + 1]))
		if dmax > 0.05:
			var names: Array = []
			for w in sp.intersect_shape(q, 4):
				names.append(str((w["collider"] as Node).get_path()).trim_prefix("/root/") if w["collider"] is Node else "?")
			pen.append("%s %.2f m %s" % [c.name, dmax, str(names)])
	return {"float": fl, "embed": embed, "embed_who": embed_who, "rays": rays, "pen": pen, "shapes": nsh}

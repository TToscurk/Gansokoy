extends SceneTree
## P10 R4 Human-Use / Ambient Life Pilot（root 直下 HumanUseP10、Props の次）gate（回歸 tag HUSE）。
##   godot --headless --path godot --script res://tools/verify_village_v2_human_use.gd -- [--negatives] [--build] [--dump=<json>]
##   godot --headless --path godot --script res://tools/verify_village_v2_human_use.gd -- --attach      （village_v2.tscn の root 直下・Props の次に掛ける；旧 Props/HumanUseP10 は移す）
##   godot --headless --path godot --script res://tools/verify_village_v2_human_use.gd -- --scene       （掛載後の場景）
##     --survey=x,z,w,h[;…]   診断：0.5 m ごとの置ける／置けない理由の地図（設計用）
##     --meadow-cache=<json>  MeadowP9 規劃株のキャッシュ（設計の反復用；gate の本番は付けない＝毎回同 seed で再計算）
##   --build は MultiMesh を含まない（個別ノード）ので headless で可。
##   --snapshot=<json>  掛載済み場景の HumanUseP10 全件（id・pilot・cluster・who・why・anchor・世界位置・朝向）を書き出す（封存用）
##   --seal  封存（data/village_v2_p10r4_seal.json：雜湊＋root 掛載（Props の次）＋Props の子は封存どおり＋場景の 50 件が snapshot と一致＋竄改反向；
##           R4 Human-Use Pilot ART_APPROVED 2026-10-08）。封存中は --build／--attach を拒否（HUSE_ALLOW_REBAKE=1＝使用者承認の再烘焙だけ）。
const HU := preload("res://tools/village_v2_human_use_lib.gd")
const MD := preload("res://tools/village_v2_meadow_lib.gd")
const SL := preload("res://tools/village_v2_street_lib.gd")
const RLib := preload("res://tools/village_v2_riverbank_lib.gd")
const SCENE := "res://maps/village_v2/village_v2.tscn"
const PROPS_SEALED := ["MarketP10", "StreetP10", "MarketWestP10", "EnvironmentP9"]   # R3b scene gate の完全一致
const POP_ORDER := ["PopulationP10", "ActivityP10", "CoreP10", "ActivityCoreP10", "EntranceCueP10", "OuterP10", "ActivityOuterP10"]
const VEG_KEEP := ["GroundcoverP9", "MeadowP9"]
const SEAL := "res://data/village_v2_p10r4_seal.json"
const SNAPSHOT := "res://data/village_v2_p10r4_snapshot.json"
const MAX_ITEMS := 60
const COHESION := 2.5
const SPAN_MAX := 20.0
const REF_DIST := {"field": 6.0, "route": 6.0, "building": 4.5, "water": 6.0, "work_surface": 7.0, "storage": 4.0}
var fails := 0


func check(msg: String, ok: bool) -> void:
	print("[HUSE] %s %s" % ["PASS" if ok else "FAIL", msg])
	if not ok:
		fails += 1


func info(msg: String) -> void:
	print("[HUSE] INFO " + msg)


func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	var args := OS.get_cmdline_user_args()
	if ("--attach" in args or "--build" in args) and _sealed() and OS.get_environment("HUSE_ALLOW_REBAKE") != "1":
		check("P10 R4 封存中（%s）：--build／--attach は拒否（使用者が reopen した時だけ HUSE_ALLOW_REBAKE=1、封存を更新すること）" % SEAL, false)
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
		print("[HUSE] 結果：%d 項失敗（scene）" % fails)
		quit(fails)
		return
	var own := v.get_node_or_null(HU.NODE_NAME)
	if own:
		own.get_parent().remove_child(own)
		own.free()
	root.add_child(v)
	await physics_frame
	var mp := _meadow(v)
	if "--survey" in " ".join(args):
		var C := HU.context(v, mp)
		info("文脈 %d ms" % C["ms"])
		for s: String in args:
			if s.begins_with("--survey="):
				for one in s.trim_prefix("--survey=").split(";"):
					var a := one.split(",")
					var r := Rect2(float(a[0]), float(a[1]), float(a[2]), float(a[3]))
					print("[HUSE] SURVEY %s（. 置ける / R 路 F 店先 B 建物 W 水 w P7 b 橋 H Hero A P8 S 封存 T 幹 E Env P P10 N NPC d 背戸 D 戸口 g 草 / 坂）" % str(r))
					var hdr := "        "
					for i in int(r.size.x / 0.5) + 1:
						hdr += str(int(r.position.x + i * 0.5) % 10) if i % 2 == 0 else " "
					print("[HUSE] " + hdr)
					for row in HU.survey(C, r):
						print("[HUSE] " + row)
		quit(0)
		return
	var P := HU.plan(v, mp)
	_plan_checks(P)
	for s: String in args:
		if s.begins_with("--dump="):
			_dump(P, s.trim_prefix("--dump="))
	if "--negatives" in args:
		_negatives(P)
	if "--build" in args:
		_build(P)
	print("[HUSE] 結果：%d 項失敗" % fails)
	quit(fails)


## MeadowP9 の規劃株：R5-3 封存時の Props（市集・主街・市集西）で同 seed 再計算（EnvironmentP9・HumanUseP10 は不可視にして文脈から外す）
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
	for nm in VEG_KEEP:
		var o := v.get_node_or_null("Vegetation/" + nm)
		if o:
			held.append([o, o.get_parent(), o.get_index()])
			o.get_parent().remove_child(o)
	var hid: Array = []
	for nm in ["Props/EnvironmentP9", HU.NODE_NAME]:
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


# ─────────────────────────── plan gate ───────────────────────────

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


## 依附先の点 ref がその型か
func _ref_ok(C: Dictionary, cl: Dictionary) -> bool:
	var r: Vector2 = cl["ref"]
	match String(cl["anchor"]):
		"field":
			return not is_nan((C["P8"] as RLib.TriSampler).h(r.x, r.y))
		"route":
			return not is_nan((C["R"] as RLib.TriSampler).h(r.x, r.y))
		"water":
			return not is_nan((C["WS"] as RLib.TriSampler).h(r.x, r.y))
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


func _signatures(items: Array, pilot: String) -> Dictionary:
	var sig := {}
	for it: Dictionary in items:
		if String(it["pilot"]) != pilot:
			continue
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
		var x := int(a.get(k, 0))
		var y := int(b.get(k, 0))
		inter += mini(x, y)
		uni += maxi(x, y)
	return float(inter) / maxf(1.0, float(uni))


func _asset_bad(C: Dictionary, items: Array) -> Array:
	var bad: Array = []
	for it: Dictionary in items:
		var id := String(it["id"])
		var pre := id.substr(0, 3)
		if not HU.KIT_OF.has(pre) or not C["D"].has(id):
			bad.append(id + "（kit 外）")
			continue
		if HU.GENERIC_ONLY.has(pre) and not (id in HU.GENERIC_ONLY[pre]):
			bad.append(id + "（Hero 固有の中身）")
		for lod in ["", "_l1"]:
			if not ResourceLoader.exists(HU.mesh_dir(id) + id + lod + ".res"):
				bad.append(id + lod + "（mesh なし）")
		if pre == "hu_" and not (id in HU.NEW_IDS):
			bad.append(id + "（新規の登録外）")
	return bad


func _of(items: Array, cl_id: String) -> Array:
	return items.filter(func(it: Dictionary) -> bool: return String(it["cluster"]) == cl_id)


func _plan_checks(P: Dictionary) -> void:
	var C: Dictionary = P["C"]
	var items: Array = P["items"]
	var clusters: Array = P["clusters"]
	info("文脈 %d ms・計画 %d 件／%d cluster、落とした %d" % [C["ms"], items.size(), clusters.size(), (C["dropped"] as Array).size()])
	for d in C["dropped"]:
		info("  落とした：" + str(d))
	# 1 既存資產優先・新規は缺件だけ
	var kit_j: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/village_v2/humanuse_kit/src/modules_blender.json"))
	var new_ok := true
	var new_txt: Array = []
	for n: String in kit_j["modules"]:
		var m: Dictionary = kit_j["modules"][n]
		if not n.ends_with("_l1"):
			new_txt.append("%s %d△" % [n, int(m["tris"])])
			new_ok = new_ok and int(m["tris"]) <= 600 and (n in HU.NEW_IDS)
		for mt in m["mats"]:
			new_ok = new_ok and String(mt) in ["V2_Wood", "ST_Street"]
	var ids := {}
	var reuse := 0
	for it: Dictionary in items:
		ids[String(it["id"])] = true
		if not String(it["id"]).begins_with("hu_"):
			reuse += 1
	var ab := _asset_bad(C, items)
	check("資產：%d 種 %d 件のうち既存 Kit の重用 %d 件（%.0f %%）、新規 humanuse_kit は缺件 %d 種だけ（%s；LOD0 ≤ 600△・材質 V2_Wood／ST_Street のみ）；Hero 固有の中身・kit 外・mesh 欠け %d %s" % [
		ids.size(), items.size(), reuse, 100.0 * reuse / maxf(1, items.size()), HU.NEW_IDS.size(), "、".join(new_txt), ab.size(), str(ab)],
		ab.is_empty() and new_ok and reuse * 2 > items.size())
	# 2 設計どおり（落とし 0）・範圍
	var pil := {}
	var n_design := 0
	var short: Array = []
	var n_min := 999
	for cl: Dictionary in clusters:
		pil[String(cl["pilot"])] = int(pil.get(String(cl["pilot"]), 0)) + 1
		n_design += int(cl["n_design"])
		n_min = mini(n_min, int(cl["n"]))
		if int(cl["n"]) != int(cl["n_design"]):
			short.append(cl["id"])
	check("設計どおり：%d cluster（A %d・B %d・C %d）、設計 %d 件すべて合法な位置に置けた（落とし %d・欠け cluster %s）" % [
		clusters.size(), pil.get("A", 0), pil.get("B", 0), pil.get("C", 0), n_design, (C["dropped"] as Array).size(), str(short)],
		(C["dropped"] as Array).is_empty() and short.is_empty())
	check("Pilot 構成：A 農田 2–4 cluster（%d）・B 住宅の裏 ≥ 3 戸（%d）・C 水の縁 ≥ 2 cluster（%d）、各 cluster ≥ 3 件（最小 %d）" % [
		pil.get("A", 0), pil.get("B", 0), pil.get("C", 0), n_min],
		int(pil.get("A", 0)) >= 2 and int(pil.get("A", 0)) <= 4 and int(pil.get("B", 0)) >= 3 and int(pil.get("C", 0)) >= 2 and n_min >= 3)
	var out_scope := 0
	for it: Dictionary in items:
		if HU.why(C, it, [it], true) == "scope":
			out_scope += 1
	check("範圍：全 %d 件が 3 Pilot の矩形内（外 %d）、上限 %d 件（全村 batch しない）" % [items.size(), out_scope, MAX_ITEMS], out_scope == 0 and items.size() <= MAX_ITEMS)
	# 3 中型輪郭＋成組（微小 scatter にしない）
	var no_mid: Array = []
	var micro_heavy: Array = []
	var n_micro := 0
	for cl: Dictionary in clusters:
		var mine := _of(items, String(cl["id"]))
		var has_mid := false
		var mc := 0
		for it: Dictionary in mine:
			if _is_mid(C, String(it["id"])):
				has_mid = true
			if _is_micro(C, String(it["id"])):
				mc += 1
		if not has_mid:
			no_mid.append(cl["id"])
		n_micro += mc
		if mc * 100 > 34 * maxi(1, mine.size()):
			micro_heavy.append("%s %d/%d" % [cl["id"], mc, mine.size()])
	check("中型の輪郭：全 cluster に高さ ≥ 0.9 m か長辺 ≥ 1.6 m の核（無い %s）、微小物（< 0.35 m）は cluster ごと ≤ 34 %%（超過 %s）・全體 %d/%d（≤ 15 %%）" % [
		str(no_mid), str(micro_heavy), n_micro, items.size()], no_mid.is_empty() and micro_heavy.is_empty() and n_micro * 100 <= 15 * items.size())
	# 4 誰が・なぜ・何に依附
	var no_story := 0
	for it: Dictionary in items:
		if String(it["who"]).strip_edges() == "" or String(it["why"]).strip_edges() == "" or not (String(it["anchor"]) in HU.ANCHOR_TYPES):
			no_story += 1
	check("「誰が使う？なぜここ？」：全 %d 件に who・why・anchor 型（%s）——欠け %d" % [items.size(), "／".join(HU.ANCHOR_TYPES), no_story], no_story == 0)
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
	check("依附：各 cluster の依附先の点が宣言どおりの型（田＝P8・農道＝路面・建物＝その建物の裏の壁・水＝水面・作業面＝水車／既存の作業物）で、最寄りの件の足元まで型ごとの上限内——%s；違反 %s" % [
		"、".join(ref_txt), str(ref_bad)], ref_bad.is_empty())
	# 5 合法（禁區）・接地
	var bad: Array = []
	var worst := 0.0
	for it: Dictionary in items:
		var w := HU.why(C, it, items)
		if w != "":
			bad.append("%s@%s %s" % [it["id"], it["cluster"], w])
		worst = maxf(worst, HU.relief(C, it))
	check("禁區：路面・店先帯・建物 +%.2f・戸口・背戸の通り道・水 +0.8・P7 構件・橋・Hero／Landmark +0.4・P8 の田／畦／水路 +0.4・封存 overlay 構件・樹幹・EnvironmentP9 +%.1f（錨 +%.1f）・他の P10・NPC（+%.1f／往復路 +%.1f）・MeadowP9 株（AABB +%.1f）・互いの重なり → 違反 %d %s" % [
		HU.BLD_PAD, HU.ENV_PAD, HU.ENV_ANCHOR_PAD, HU.NPC_PAD, HU.PATROL_PAD, HU.MEADOW_PAD, bad.size(), str(bad.slice(0, 6))], bad.is_empty())
	check("接地：足元の起伏 最大 %.3f m（≤ %.2f）、高さ＝足元の見えている最上面の最低点（地形・路面・P4 院子・P8 の地面）" % [worst, HU.RELIEF_MAX], worst <= HU.RELIEF_MAX)
	# 6 MeadowP9・EnvironmentP9 の封存を崩さない
	var gin := 0
	for it: Dictionary in items:
		gin += HU.meadow_in(C, HU.aabb2(C, it).grow(HU.MEADOW_PAD))
	check("MeadowP9 不重烘：規劃株 %d（同 seed 再計算）のうち HU の AABB +%.1f m 内 %d 株（= 0 → meadow の文脈に HU が入っても再計算が封存と一致）" % [
		int(C["meadow_n"]), HU.MEADOW_PAD, gin], gin == 0 and int(C["meadow_n"]) > 100000)
	var env_min := 1e9
	for it: Dictionary in items:
		for a: Vector2 in C["env_anchor"]:
			env_min = minf(env_min, (it["p"] as Vector2).distance_to(a))
	check("EnvironmentP9 不改：HU の足元は Env の構件から ≥ %.1f m（R5-4 の P10 +1.5 m 規則が掛載後も成り立つ）・Env の錨 %d 点から ≥ %.1f m（最近 %.1f m）" % [
		HU.ENV_PAD, (C["env_anchor"] as Array).size(), HU.ENV_ANCHOR_PAD, env_min], env_min >= HU.ENV_ANCHOR_PAD)
	# 7 NPC：増やさない・動かさない・塞がない
	var npc_min := 1e9
	for it: Dictionary in items:
		for t: Vector2 in C["npc"]:
			for q in HU.corners(C, it):
				npc_min = minf(npc_min, q.distance_to(t))
	check("NPC：snapshot の %d 人（R3b 16＋R3d 23＋R3e 12）を変えない、HU の足元の角から立ち位置まで最近 %.2f m（≥ %.1f）・往復路 %d 本 +%.1f、NPC anchors（Marker3D）を足さない" % [
		(C["npc"] as Array).size(), npc_min, HU.NPC_PAD, (C["npc_paths"] as Array).size(), HU.PATROL_PAD], (C["npc"] as Array).size() == 51 and npc_min >= HU.NPC_PAD)
	# 8 成組・孤立なし
	var coh := _cohesion(C, items)
	var span_bad: Array = []
	for cl: Dictionary in clusters:
		var mine := _of(items, String(cl["id"]))
		var r := Rect2(mine[0]["p"], Vector2.ZERO)
		for it: Dictionary in mine:
			r = r.expand(it["p"])
		if r.size.length() > SPAN_MAX:
			span_bad.append("%s %.1f m" % [cl["id"], r.size.length()])
	check("成組：各件は同じ cluster の別の件から足元の縁で ≤ %.1f m（孤立 %s）、cluster の広がり ≤ %.0f m（超過 %s）——空地の真ん中に一つだけ、をしない" % [
		COHESION, str(coh), SPAN_MAX, str(span_bad)], coh.is_empty() and span_bad.is_empty())
	# 9 非均一：家ごとの暮らしの違い・同じ組み合わせの複製なし
	var sB := _signatures(items, "B")
	var jmax := 0.0
	var keys := sB.keys()
	for i in keys.size():
		for j in range(i + 1, keys.size()):
			jmax = maxf(jmax, _jaccard(sB[keys[i]], sB[keys[j]]))
	var rep_bad: Array = []
	for pl in ["A", "B", "C"]:
		var sg := _signatures(items, pl)
		var cnt := {}
		for k in sg:
			for id in sg[k]:
				cnt[id] = int(cnt.get(id, 0)) + 1
		for id in cnt:
			if int(cnt[id]) > 2:
				rep_bad.append("%s:%s×%d" % [pl, id, cnt[id]])
	check("非均一：B の %d 戸の組成の類似度（Jaccard）最大 %.2f（≤ 0.34：同じ桶を各戸に配らない）・一つの Pilot で同じ物が 3 cluster 以上に出ない（%s）" % [
		keys.size(), jmax, str(rep_bad)], jmax <= 0.34 and rep_bad.is_empty() and keys.size() >= 3)
	for cl: Dictionary in clusters:
		info("%s（%s、%s）：%s" % [cl["id"], cl["anchor"], cl["anchor_desc"], "・".join(_of(items, String(cl["id"])).map(func(it: Dictionary) -> String: return String(it["id"])))])


func _dump(P: Dictionary, path: String) -> void:
	var out: Array = []
	for it: Dictionary in P["items"]:
		out.append({"id": it["id"], "pilot": it["pilot"], "cluster": it["cluster"], "anchor": it["anchor"], "who": it["who"], "why": it["why"],
			"p": [snappedf((it["p"] as Vector2).x, 0.01), snappedf(float(it["y"]), 0.01), snappedf((it["p"] as Vector2).y, 0.01)],
			"yaw_deg": snappedf(rad_to_deg(float(it["yaw"])), 0.1)})
	var cls: Array = []
	for c: Dictionary in P["clusters"]:
		cls.append({"id": c["id"], "pilot": c["pilot"], "anchor": c["anchor"], "anchor_desc": c["anchor_desc"], "n": c["n"], "n_design": c["n_design"],
			"center": [snappedf((c["center"] as Vector2).x, 0.01), snappedf((c["center"] as Vector2).y, 0.01)],
			"ref": [snappedf((c["ref"] as Vector2).x, 0.01), snappedf((c["ref"] as Vector2).y, 0.01)]})
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"art_revision": HU.ART_REVISION, "pilots": HU.PILOT_NAME, "items": out, "clusters": cls}, "\t"))
	f.close()
	info("計画 → " + path)


# ─────────────────────────── 反向 ───────────────────────────

func _neg(name: String, caught: bool) -> void:
	check("反向 %s → 偵測" % name, caught)


func _probe(C: Dictionary, items: Array, id: String, p: Vector2) -> String:
	var it := HU.item(C, id, p, Vector2(0, 1), {"pilot": "A", "cluster": "NEG", "anchor": "field", "who": "x", "why": "x"})
	return HU.why(C, it, items, false)


func _negatives(P: Dictionary) -> void:
	var C: Dictionary = P["C"]
	var items: Array = P["items"]
	_neg("P8 の田の中（392, 30）に置く＝p8", _probe(C, items, "sk_box", Vector2(392.0, 30.0)) == "p8")
	_neg("水渠の水面（338.5, -50）に置く＝water", _probe(C, items, "sk_box", Vector2(338.5, -50.0)) == "water")
	_neg("FarmPath_1 の路面（372, -15）に置く＝road", _probe(C, items, "sk_box", Vector2(372.0, -15.0)) == "road")
	var n0: Vector2 = (C["npc"] as Array)[40]
	var wn := _probe(C, items, "sk_box", n0 + Vector2(0.3, 0.0))
	_neg("NPC（R3e）の立ち位置 0.3 m に置く＝npc（%s）" % wn, wn == "npc")
	var stem := Vector2.ZERO
	for k: Vector2i in (C["meadow"] as Dictionary).keys():
		var q := Vector2(k.x * 0.5 + 0.25, k.y * 0.5 + 0.25)
		if (HU.PILOTS["B"] as Rect2).grow(30.0).has_point(q):
			stem = q
			break
	var wm := _probe(C, items, "sk_box", stem)
	_neg("MeadowP9 の株の上（%.1f, %.1f）に置く＝置けない（%s）" % [stem.x, stem.y, wm], wm != "")
	var tmp := C["meadow"] as Dictionary
	var it_m := HU.item(C, "sk_box", Vector2(500.5, 500.5), Vector2(0, 1), {})
	tmp[Vector2i(1001, 1001)] = 1
	var wm2 := HU.meadow_in(C, HU.aabb2(C, it_m).grow(HU.MEADOW_PAD))
	tmp.erase(Vector2i(1001, 1001))
	_neg("足元の AABB +0.4 に株 1 つ＝meadow 計數 %d" % wm2, wm2 == 1)
	if not (C["env_anchor"] as Array).is_empty():
		var e0: Vector2 = (C["env_anchor"] as Array)[0]
		var we := _probe(C, items, "sk_box", e0 + Vector2(1.0, 0.0))
		_neg("EnvironmentP9 の錨 1 m に置く＝置けない（%s）" % we, we != "")
	var b030: Dictionary = (C["bld"] as Array).filter(func(b: Dictionary) -> bool: return String(b["name"]) == "B_P_MKT_030")[0]
	var door := (b030["o"] as Vector2) - (b030["az"] as Vector2) * (float(b030["d"]) * 0.5 + 0.9)
	var wd := _probe(C, items, "sk_box", door)
	_neg("背戸の通り道（MKT_030 の裏戸の前 0.9 m）に置く＝backdoor／building（%s）" % wd, wd in ["backdoor", "building"])
	_neg("Pilot の外（300, 60）に置く＝scope", HU.why(C, HU.item(C, "sk_box", Vector2(300.0, 60.0), Vector2(0, 1), {"pilot": "A"}), items, true) == "scope")
	# 計画レベル（コピーして壊す）
	var iso: Array = items.duplicate(true)
	(iso[1] as Dictionary)["p"] = (iso[1]["p"] as Vector2) + Vector2(12.0, 25.0)
	_neg("1 件を cluster から 28 m 離す＝孤立", not _cohesion(C, iso).is_empty())
	var nos: Array = items.duplicate(true)
	(nos[3] as Dictionary)["who"] = ""
	_neg("who を消す＝誰が使う？が無い", nos.any(func(it: Dictionary) -> bool: return String(it["who"]).strip_edges() == ""))
	var dup: Array = items.duplicate(true)
	var b1 := _of(dup, "B1_maki")
	var b2 := _of(dup, "B2_shigoto")
	for k in mini(b1.size(), b2.size()):
		(b2[k] as Dictionary)["id"] = b1[k]["id"]
	var sB := _signatures(dup, "B")
	var jd := _jaccard(sB["B1_maki"], sB["B2_shigoto"])
	_neg("B2 を B1 と同じ組成にする＝複製（Jaccard %.2f）" % jd, jd > 0.34)
	var ok_mid := false
	for id in ["sk_temari", "sk_temari", "sk_temari", "sk_temari", "sk_temari"]:
		ok_mid = ok_mid or _is_mid(C, id)
	_neg("手毬 5 個だけの cluster＝中型の核なし", not ok_mid and _is_micro(C, "sk_temari"))
	_neg("霧雨店の茸（kr_kinoko）を使う＝Hero 固有の中身", not _asset_bad(C, [{"id": "kr_kinoko"}]).is_empty())
	_neg("存在しない kit の物（xx_foo）＝kit 外", not _asset_bad(C, [{"id": "xx_foo"}]).is_empty())
	_neg("依附先の型を偽る（田の ref を路面へ）", not _ref_ok(C, {"anchor": "field", "ref": Vector2(372.0, -15.0)}))


# ─────────────────────────── build／attach／scene ───────────────────────────

func _build(P: Dictionary) -> void:
	var root_n := HU.bake(P)
	HU.own(root_n, root_n)
	var ps := PackedScene.new()
	check("pack overlay", ps.pack(root_n) == OK)
	check("save %s" % HU.OUTPUT, ResourceSaver.save(ps, HU.OUTPUT, ResourceSaver.FLAG_COMPRESS) == OK)
	root_n.free()
	var r := ResourceLoader.load(HU.OUTPUT, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var rb := r.instantiate() as Node3D
	var mi := rb.find_children("*", "MeshInstance3D", true, false)
	var mm := rb.find_children("*", "MultiMeshInstance3D", true, false).size()
	var mk := rb.find_children("*", "Marker3D", true, false).size()
	var meta_ok := true
	var n_it := 0
	for n in rb.find_children("*", "Node3D", true, false):
		if n.has_meta("hu_id"):
			n_it += 1
			for k in ["hu_who", "hu_why", "hu_anchor", "hu_cluster", "hu_pilot"]:
				meta_ok = meta_ok and String(n.get_meta(k, "")) != ""
	check("存檔回讀：構件 %d（計画 %d、meta 付き %d）・MeshInstance %d（LOD0/LOD1）・碰撞 %d・MultiMesh %d・Marker3D %d・各件の who/why/anchor meta、art_revision" % [
		int(rb.get_meta("items")), (P["items"] as Array).size(), n_it, mi.size(), int(rb.get_meta("shapes")), mm, mk],
		int(rb.get_meta("items")) == (P["items"] as Array).size() and n_it == int(rb.get_meta("items")) and mi.size() == 2 * int(rb.get_meta("items")) and mm == 0 and mk == 0 and meta_ok
		and String(rb.get_meta("art_revision")) == HU.ART_REVISION)
	rb.free()


func _attach() -> int:
	var txt := FileAccess.get_file_as_string(SCENE)
	if not FileAccess.file_exists(HU.OUTPUT):
		push_error("找不到 %s（先 --build）" % HU.OUTPUT)
		return 1
	var nl := "
" if txt.contains("
") else "
"
	var line_props := "[node name=\"%s\" parent=\"Props\" instance=ExtResource(\"p10r4_human_use\")]" % HU.NODE_NAME
	var line_root := "[node name=\"%s\" parent=\".\" instance=ExtResource(\"p10r4_human_use\")]" % HU.NODE_NAME
	if txt.contains(line_root):
		print("[HUSE] attach：已掛 root/%s（不重複、不寫場景）" % HU.NODE_NAME)
		return 0
	if txt.contains(line_props):
		# 旧版（Props 末尾）→ root 直下へ：同じ位置（Props の子の直後）のまま parent だけ変える＝root の子の順は Props の次
		var f0 := FileAccess.open(SCENE, FileAccess.WRITE)
		f0.store_string(txt.replace(line_props, line_root))
		f0.close()
		print("[HUSE] attach：Props/%s → root 直下（Props の次）へ移した" % HU.NODE_NAME)
		return 0
	var lines := txt.split(nl)
	var last_ext := -1
	var last_props := -1
	for k in lines.size():
		if lines[k].begins_with("[ext_resource"):
			last_ext = k
		if lines[k].begins_with("[node ") and lines[k].contains("parent=\"Props\""):
			last_props = k
	if last_props < 0:
		push_error("找不到 Props の子")
		return 1
	var out := PackedStringArray(Array(lines))
	var ins := last_props + 1
	while ins < out.size() and not out[ins].begins_with("["):
		ins += 1
	out.insert(ins, "")
	out.insert(ins, line_root)
	out.insert(last_ext + 1, "[ext_resource type=\"PackedScene\" path=\"%s\" id=\"p10r4_human_use\"]" % HU.OUTPUT)
	var f := FileAccess.open(SCENE, FileAccess.WRITE)
	f.store_string(nl.join(out))
	f.close()
	print("[HUSE] attach：加 root/%s（Props の子の直後＝root の子の順で Props の次）→ %s（+%d 行）" % [HU.NODE_NAME, SCENE, out.size() - lines.size()])
	return 0


func _scene(v: Node3D) -> void:
	var names: Array = []
	for c in v.get_node("Props").get_children():
		names.append(String(c.name))
	var roots: Array = []
	for c in v.get_children():
		roots.append(String(c.name))
	var go := v.get_node_or_null(HU.NODE_NAME) as Node3D
	var ip := roots.find("Props")
	check("場景已掛 root/%s（1 個、root の子で Props の次＝%s）、Props の子は封存どおり（%s；R3b scene gate の完全一致を崩さない）" % [
		HU.NODE_NAME, " → ".join(roots.slice(maxi(0, ip - 1), ip + 3)), " → ".join(names)],
		go != null and roots.count(HU.NODE_NAME) == 1 and ip >= 0 and roots.find(HU.NODE_NAME) == ip + 1 and names == PROPS_SEALED
		and v.get_node_or_null("Props/" + HU.NODE_NAME) == null)
	if go == null:
		return
	check("art_revision＝%s、visible、scene_file_path＝%s" % [go.get_meta("art_revision", "?"), HU.OUTPUT],
		String(go.get_meta("art_revision", "")) == HU.ART_REVISION and go.visible and go.scene_file_path == HU.OUTPUT)
	var mi := go.find_children("*", "MeshInstance3D", true, false)
	var mm := go.find_children("*", "MultiMeshInstance3D", true, false).size()
	var mk := go.find_children("*", "Marker3D", true, false).size()
	var lod_ok := true
	# P10 R4c（使用者 2026-10-09 ART_APPROVED：Straw Geometry Pilot、封存 data/village_v2_p10r4c_seal.json）：PropFixP10 が st_hasa（＋_l1）を
	# st_hasa_v2 に差し替える。差し替え先は PropFixP10 の swaps に登記された 2 つだけ合法（それ以外の kit 外 mesh は従来どおり FAIL）。
	var r4c := {}
	var pf := v.get_node_or_null("PropFixP10")
	if pf != null:
		var sw: Dictionary = pf.get("swaps")
		for k in sw:
			r4c[String((sw[k] as Mesh).resource_path)] = true
	var n_r4c := 0
	for m in mi:
		var path := String((m as MeshInstance3D).mesh.resource_path)
		var kit_ok := path.begins_with("res://assets/village_v2/") and path.contains("/mesh/")
		if not kit_ok and r4c.has(path):
			n_r4c += 1
			kit_ok = true
		lod_ok = lod_ok and kit_ok
	check("個別ノード（選べる）：MeshInstance %d（＝2×%d 件）・MultiMesh %d・NPC anchors（Marker3D）%d、mesh は全部 kit の .res（R4c 登記の st_hasa_v2 差し替え %d）" % [mi.size(), int(go.get_meta("items")), mm, mk, n_r4c],
		mm == 0 and mk == 0 and lod_ok and mi.size() == 2 * int(go.get_meta("items")))
	# 反向（R4c 合法化の後も任意の差し替えは FAIL）：1 件を kit 外の BoxMesh に → 検出
	var m0 := mi[0] as MeshInstance3D
	var keep := m0.mesh
	m0.mesh = BoxMesh.new()
	var p0 := String(m0.mesh.resource_path)
	var neg_ok := not ((p0.begins_with("res://assets/village_v2/") and p0.contains("/mesh/")) or r4c.has(p0))
	m0.mesh = keep
	check("反向：1 件を kit 外の mesh（BoxMesh）に差し替え → 検出（R4c 登記以外は不可）", neg_ok)
	var pil: Array = []
	for p in ["PilotA", "PilotB", "PilotC"]:
		var n := go.get_node_or_null(p)
		pil.append("%s %d cluster" % [p, n.get_child_count() if n else -1])
	check("Pilot→cluster→件の木構造：%s" % "、".join(pil), go.get_node_or_null("PilotA") != null and go.get_node_or_null("PilotB") != null and go.get_node_or_null("PilotC") != null)
	var pop: Array = []
	for c in v.get_node("Population").get_children():
		pop.append(String(c.name))
	check("Population 不変：子 %s（R3b／R3d／R3e 封存の順）" % " → ".join(pop), pop == POP_ORDER)
	var veg_ok := true
	for nm in ["GroundcoverP9", "MeadowP9"]:
		var n := v.get_node_or_null("Vegetation/" + nm) as Node3D
		veg_ok = veg_ok and n != null and n.visible
	var env := v.get_node_or_null("Props/EnvironmentP9") as Node3D
	var p10_ok := true
	for nm in ["MarketP10", "StreetP10", "MarketWestP10"]:
		p10_ok = p10_ok and v.get_node_or_null("Props/" + nm) != null
	check("並行の封存 overlay 仍掛載・visible：GroundcoverP9・MeadowP9・EnvironmentP9・MarketP10・StreetP10・MarketWestP10", veg_ok and env != null and env.visible and p10_ok)
	var shapes := go.find_children("*", "CollisionShape3D", true, false).size()
	check("碰撞：腰より高い件だけ箱 %d（＝meta %d）" % [shapes, int(go.get_meta("shapes"))], shapes == int(go.get_meta("shapes")) and shapes > 0)
	await _placement(v, go)


## 擺放驗證（godot-asset-placement-validation：audit_village_v2_placement.gd の対象外＝Props なので、ここで物理で測る）
##   接地：各件の足元 3×3（内側 0.08）から真下へ ray（自分の碰撞は除外）→ 浮き（足元が支持面より > 0.08 m 上）の点が 40 % を越える件＝FLOATING
##   貫通：各件の碰撞箱を collide_shape（自分・地形は除外）→ 接触の深さ > 0.05 m＝OBJECT_PENETRATION
##   反向：1 件を 0.3 m 持ち上げる → FLOATING を検出／1 件の碰撞箱を最寄りの建物へ押し込む → OBJECT_PENETRATION を検出
func _placement(v: Node3D, go: Node3D) -> void:
	for i in 3:
		await physics_frame
	var sp := v.get_world_3d().direct_space_state
	var D := HU.dims_table()
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
	check("擺放（接地）：%d 件 × 3×3 ray（%d 本）——FLOATING %d %s、最大の埋まり %.3f m（起伏ぶん・意図的、≤ 0.15）；腰より低い %d 件は visual_only（碰撞なし・接地だけ測る）" % [
		nodes.size(), int(res["rays"]), (res["float"] as Array).size(), str(res["float"]), float(res["embed"]), vis_only],
		(res["float"] as Array).is_empty() and float(res["embed"]) <= 0.15 and int(res["rays"]) == nodes.size() * 9)
	check("擺放（貫通）：碰撞箱 %d を collide_shape（自分・地形を除く）——OBJECT_PENETRATION %d %s（建物・P10・P8・河岸・NPC 席などに > 0.05 m 入らない）" % [
		int(res["shapes"]), (res["pen"] as Array).size(), str(res["pen"])], (res["pen"] as Array).is_empty() and int(res["shapes"]) > 0)
	# 反向（メモリ上だけ）：浮かせる・押し込む
	var n0: Node3D = nodes[0]
	var keep := n0.global_position
	n0.global_position = keep + Vector3(0, 0.3, 0)
	var r1 := _audit(sp, D, body, terr, [n0], go)
	n0.global_position = keep
	check("擺放 反向 float：%s を 0.3 m 持ち上げる → FLOATING を検出（%s）" % [n0.name, str(r1["float"])], (r1["float"] as Array).size() == 1)
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
	check("擺放 反向 clash：碰撞箱 %s を最寄りの建物 %s の中へ押し込む → OBJECT_PENETRATION を検出（%d）" % [cs.name, best["name"], (r2["pen"] as Array).size()], not (r2["pen"] as Array).is_empty())


func _audit(sp: PhysicsDirectSpaceState3D, D: Dictionary, body: StaticBody3D, terr: Array[RID], nodes: Array, go: Node3D) -> Dictionary:
	var fl: Array = []
	var embed := 0.0
	var rays := 0
	for n: Node3D in nodes:
		var d: Array = D[String(n.get_meta("hu_id"))]
		var xf := n.global_transform
		var nf := 0
		for i in 3:
			for j in 3:
				var lx := lerpf(float(d[0]) + 0.08, float(d[3]) - 0.08, i / 2.0)
				var lz := lerpf(float(d[2]) + 0.08, float(d[5]) - 0.08, j / 2.0)
				var p := xf * Vector3(lx, 0.0, lz)
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
				else:
					embed = maxf(embed, -gap)
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
			var who := sp.intersect_shape(q, 4)
			var names: Array = []
			for w in who:
				names.append(String((w["collider"] as Node).name) if w["collider"] is Node else "?")
			pen.append("%s %.2f m %s" % [c.name, dmax, str(names)])
	return {"float": fl, "embed": embed, "rays": rays, "pen": pen, "shapes": nsh}


# ─────────────────────────── snapshot／seal ───────────────────────────

func _live(v: Node3D) -> Array:
	var go := v.get_node_or_null(HU.NODE_NAME) as Node3D
	var out: Array = []
	if go == null:
		return out
	for n in go.find_children("*", "Node3D", true, false):
		if n.has_meta("hu_id"):
			var xf := (n as Node3D).global_transform
			out.append({"node": String(go.get_path_to(n)), "id": String(n.get_meta("hu_id")), "pilot": String(n.get_meta("hu_pilot")),
				"cluster": String(n.get_meta("hu_cluster")), "anchor": String(n.get_meta("hu_anchor")), "who": String(n.get_meta("hu_who")),
				"why": String(n.get_meta("hu_why")), "position": [snappedf(xf.origin.x, 0.001), snappedf(xf.origin.y, 0.001), snappedf(xf.origin.z, 0.001)],
				"yaw_deg": snappedf(rad_to_deg(xf.basis.get_euler().y), 0.01)})
	return out


func _snapshot(v: Node3D, path: String) -> void:
	var items := _live(v)
	var cl := {}
	var pil := {}
	for it: Dictionary in items:
		cl[it["cluster"]] = int(cl.get(it["cluster"], 0)) + 1
		pil[it["pilot"]] = int(pil.get(it["pilot"], 0)) + 1
	var out := {"schema": 1, "scope": "P10 R4 Human-Use Pilot：HumanUseP10（root 直下・Props の次）の全件", "art_revision": String((v.get_node(HU.NODE_NAME) as Node).get_meta("art_revision")),
		"total": items.size(), "clusters": cl, "pilots": pil, "items": items}
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "	") + "
")
	f.close()
	print("[HUSE] snapshot → %s（%d 件、%d cluster）" % [path, items.size(), cl.size()])


func _sealed() -> bool:
	if not FileAccess.file_exists(SEAL):
		return false
	var j = JSON.parse_string(FileAccess.get_file_as_string(SEAL))
	return j is Dictionary and String(j.get("status", "")) == "ART_APPROVED"


func _seal_mismatch(seal: Dictionary) -> Array:
	var repo := (ProjectSettings.globalize_path("res://") + "..").simplify_path() + "/"
	var bad: Array = []
	for grp: String in ["frozen", "evidence", "art_review_images", "child_seals"]:
		var d: Dictionary = seal.get(grp, {})
		for k: String in d:
			if not FileAccess.file_exists(repo + k) or FileAccess.get_sha256(repo + k) != String(d[k]):
				bad.append(k)
	return bad


## 場景の全件が snapshot と一致（位置 ≤ 1 cm・朝向 ≤ 0.5°・id／pilot／cluster／anchor／who／why）
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
		if Vector3(p[0], p[1], p[2]).distance_to(Vector3(q[0], q[1], q[2])) > 0.01 or absf(angle_difference(deg_to_rad(float(it["yaw_deg"])), deg_to_rad(float(w["yaw_deg"])))) > deg_to_rad(0.5):
			bad.append(String(w["node"]) + " 位置／朝向")
		for k in ["id", "pilot", "cluster", "anchor", "who", "why"]:
			if String(it[k]) != String(w[k]):
				bad.append("%s %s" % [w["node"], k])
	return bad


func _seal(v: Node3D) -> int:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(SEAL))
	if not parsed is Dictionary:
		check("seal manifest が読める", false)
		return 2
	var seal: Dictionary = parsed
	check("status ART_APPROVED（使用者 2026-10-08；agent は美術を承認しない）", String(seal.get("status", "")) == "ART_APPROVED" and String(seal.get("approved_by", "")) == "user")
	var bad := _seal_mismatch(seal)
	var n := 0
	for grp: String in ["frozen", "evidence", "art_review_images", "child_seals"]:
		n += (seal.get(grp, {}) as Dictionary).size()
	check("封存 %d 檔雜湊一致（凍結・證據・審圖・子封存；不符 %d：%s）" % [n, bad.size(), str(bad.slice(0, 4))], bad.is_empty())
	var roots: Array = []
	for c in v.get_children():
		roots.append(String(c.name))
	var names: Array = []
	for c in v.get_node("Props").get_children():
		names.append(String(c.name))
	var ip := roots.find("Props")
	var txt := FileAccess.get_file_as_string(SCENE)
	check("掛載：root 直下 %s（1 個）＝Props の次（使用者 2026-10-08 承認）、Props の子は封存どおり（%s）、%s" % [HU.NODE_NAME, " → ".join(names), HU.OUTPUT],
		roots.count(HU.NODE_NAME) == 1 and ip >= 0 and roots.find(HU.NODE_NAME) == ip + 1 and names == PROPS_SEALED and txt.count("p10r4_human_use") == 2
		and (v.get_node(HU.NODE_NAME) as Node).scene_file_path == HU.OUTPUT)
	var snap: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SNAPSHOT))
	var pil: Dictionary = snap["pilots"]
	check("snapshot：%d 件・%d cluster（A %d・B %d・C %d 件）、art_revision＝%s" % [int(snap["total"]), (snap["clusters"] as Dictionary).size(), int(pil.get("A", 0)), int(pil.get("B", 0)), int(pil.get("C", 0)), snap["art_revision"]],
		int(snap["total"]) == 50 and (snap["clusters"] as Dictionary).size() == 10 and String(snap["art_revision"]) == HU.ART_REVISION)
	var lb := _live_mismatch(v, snap)
	check("場景の 50 件が snapshot と一致（位置 ≤ 1 cm・朝向 ≤ 0.5°・id／pilot／cluster／anchor／who／why；不符 %s）" % str(lb.slice(0, 4)), lb.is_empty())
	var tam := seal.duplicate(true)
	var k0: String = (tam["frozen"] as Dictionary).keys()[0]
	tam["frozen"][k0] = "0".repeat(64)
	check("反向：凍結雜湊を記憶體内で竄改 → 1 件だけ検出（%d）" % (_seal_mismatch(tam).size() - bad.size()), _seal_mismatch(tam).size() == bad.size() + 1)
	var snap2: Dictionary = snap.duplicate(true)
	snap2["items"][0]["position"][0] = float(snap2["items"][0]["position"][0]) + 0.25
	check("反向：snapshot の 1 件を 0.25 m ずらす → 不一致を検出", not _live_mismatch(v, snap2).is_empty())
	var snap3: Dictionary = snap.duplicate(true)
	snap3["items"][1]["who"] = "誰か"
	check("反向：snapshot の 1 件の who を変える → 不一致を検出", not _live_mismatch(v, snap3).is_empty())
	print("[HUSE] 結果：%d 項失敗（seal）" % fails)
	return 0 if fails == 0 else 2

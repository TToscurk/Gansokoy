extends SceneTree
## 人間之里 V2 P9 R5-4 Existing Asset Environment Pass（全村擴張 x1、Props/EnvironmentP9）：規劃 gate＋反向＋烘焙＋掛載＋場景驗證＋調査。
##   規劃＋gate：Godot --headless --path godot --script res://tools/verify_village_v2_environment.gd
##   調査：      ... -- --survey=x,z,r（ASCII：B 建物・R 路・F 店先帯・W 水・w P7 構件・A 田・S 封存・P P10・T 樹幹・x 地形外・~ 起伏・. 空き）
##               ... -- --dump=<path.json>（錨・event・件の平面図データ）
##   反向：       ... -- --negatives
##   烘焙：       ... -- --build（FAIL 時は存檔しない；MultiMesh を使わない＝headless 可）
##   掛載：       ... -- --attach（Props の末尾へ EnvironmentP9；既にあれば何もしない）
##   場景：       ... -- --scene
##   機位：       ... -- --views=<path.json>
##   封存：       ... -- --seal（R5-4 x2 ART_APPROVED 封存：雜湊・Props 掛載順・反向）；封存中は --build を拒否（ENV_ALLOW_REBAKE=1 は使用者の reopen 時のみ）
## gate は構造の證據であって美術判定ではない（Gate PASS ≠ ART PASS）。各項一行 [ENV] PASS/FAIL、結尾 quit(失敗項數)。

const EL := preload("res://tools/village_v2_environment_lib.gd")
const MD := preload("res://tools/village_v2_meadow_lib.gd")
const RLib := preload("res://tools/village_v2_riverbank_lib.gd")
const GC := preload("res://tools/village_v2_groundcover_lib.gd")
const SCENE := "res://maps/village_v2/village_v2.tscn"
const R5_SEAL := "res://data/village_v2_p9r5_seal.json"
const MEADOW_SEAL := "res://data/village_v2_p9r53_seal.json"
const SEAL := "res://data/village_v2_p9r54_seal.json"
const PROPS_ORDER := ["MarketP10", "StreetP10", "MarketWestP10", "EnvironmentP9"]
## P12 FINAL CLOSURE（使用者 2026-10-12 授權）：P11 R2D の農田水利（farmland_p8.scn）が MeadowP9 規劃の避障入力を変え、
## 同 seed 再計算が封存近級 114105 から漂移。草は再生成しない（封存 meadow_p9.scn 保持）。以下が全部一致する時だけ容認：
## 現計画の株数・株位摘要（同数で位置だけ違う漂移も不可）／上游 farmland_p8.scn・封存 meadow_p9.scn の雜湊。
const P12_MEADOW_DRIFT := {
	"sealed_near": 114105, "count": 114574, "digest": "5d9ef17a69aa96c6cf46628c40546912a771449e0c9400bd7879bd1d553cc53b",
	"upstream": {"res://maps/village_v2/gen/farmland_p8.scn": "eea295d7cf0435144e2df0b2d8f751edd142b5538e0065410fa0317c393d95c2"},
	"baked": {"res://maps/village_v2/gen/meadow_p9.scn": "4fca207ec740ae0b36d8119a68394d6cf5c5afa627850c32c99672e73c428def"},
}


static func _pts_digest(pts: PackedVector2Array) -> String:
	var hc := HashingContext.new()
	hc.start(HashingContext.HASH_SHA256)
	hc.update(pts.to_byte_array())
	return hc.finish().hex_encode()


## 空 Array＝登記どおり
static func _meadow_drift(got: int, dig: String, sealed_near: int, D: Dictionary) -> Array:
	var why: Array = []
	if sealed_near != int(D["sealed_near"]):
		why.append("封存近級")
	if got != int(D["count"]):
		why.append("株数 %d" % got)
	if dig != String(D["digest"]):
		why.append("株位摘要 " + dig)
	for grp in ["upstream", "baked"]:
		for k: String in D[grp]:
			if FileAccess.get_sha256(k) != String(D[grp][k]):
				why.append(grp + " " + k.get_file())
	return why

var fails := 0
var failed_labels: Array = []
var quiet := false


func check(label: String, ok: bool) -> void:
	if not quiet:
		print("[ENV] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		fails += 1
		failed_labels.append(label)


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
	# R5-4 封存後は再烘焙しない（2026-10-05 使用者裁定：x2＝ART_APPROVED、EnvironmentP9 は以後変更しない）
	if "--build" in args and FileAccess.file_exists(SEAL) and OS.get_environment("ENV_ALLOW_REBAKE") != "1":
		check("R5-4 封存中（%s）：--build は拒否（使用者が reopen した時だけ ENV_ALLOW_REBAKE=1、封存を更新すること）" % SEAL, false)
		print("[ENV] 結果：%d 項失敗（build 拒否）" % fails)
		quit(fails)
		return
	var v: Node3D = (load(SCENE) as PackedScene).instantiate()
	if "--scene" in args:
		root.add_child(v)
		await process_frame
		_scene(v)
		print("[ENV] 結果：%d 項失敗（scene）" % fails)
		quit(fails)
		return
	var own := v.get_node_or_null("Props/" + EL.NODE_NAME)
	if own:
		own.get_parent().remove_child(own)
		own.free()
	# MeadowP9（R5-3 封存）の株位は headless では MultiMesh から讀めない → 同じ規劃を同 seed で再計算する（meadow verifier と同じ前處理）
	for nm in ["GroundcoverP9", "MeadowP9"]:
		var o := v.get_node_or_null("Vegetation/" + nm)
		if o:
			o.get_parent().remove_child(o)
			o.free()
	root.add_child(v)
	await physics_frame
	for s: String in args:
		if s.begins_with("--survey="):
			var CC := EL.context(v)
			for one in s.trim_prefix("--survey=").split(";"):
				var a := one.split(",")
				_survey(CC, Vector2(float(a[0]), float(a[1])), float(a[2]))
			quit(0)
			return
	var M := _meadow(v)
	var P := EL.plan(v, M["p"], M["F"])
	P["meadow_n"] = (M["p"] as PackedVector2Array).size()
	P["meadow_digest"] = _pts_digest(M["p"])
	print("[ENV] INFO 規劃 %d ms（距離場 %d ms）：錨 %d・event %d・件 %d；類の候補セル %s；落とした %d" % [P["ms"], P["G"]["ms"], (P["anchors"] as Array).size(),
		(P["events"] as Array).size(), (P["items"] as Array).size(), str(P["counts"]), (P["dropped"] as Array).size()])
	_summary(P)
	for s: String in args:
		if s.begins_with("--views="):
			_views(P, s.trim_prefix("--views="))
			quit(0)
			return
		if s.begins_with("--dump="):
			_dump(P, s.trim_prefix("--dump="))
	if "--negatives" in args:
		quit(_negatives(v, P))
		return
	_checks(P)
	if "--build" in args and fails == 0:
		var r := EL.bake(P)
		EL.own(r, r)
		var ps := PackedScene.new()
		check("pack overlay", ps.pack(r) == OK)
		check("save %s" % EL.OUTPUT, ResourceSaver.save(ps, EL.OUTPUT, ResourceSaver.FLAG_COMPRESS) == OK)
		var rb := (ResourceLoader.load(EL.OUTPUT, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
		var n_mi := rb.find_children("*", "MeshInstance3D", true, false).size()
		check("存檔回讀：構件 %d・MeshInstance %d（LOD0/LOD1）・碰撞 %d、art_revision" % [int(rb.get_meta("items")), n_mi, int(rb.get_meta("shapes"))],
			int(rb.get_meta("items")) == (P["items"] as Array).size() and n_mi == 2 * int(rb.get_meta("items")) and String(rb.get_meta("art_revision")) == EL.ART_REVISION)
		rb.free()
		r.free()
	print("[ENV] 結果：%d 項失敗" % fails)
	quit(fails)


func _meadow(v: Node3D) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var Pm: Dictionary = MD.base_plan(v)
	var MC := MD.context(Pm, v)
	var Fm := MD.fields(Pm, MC)
	var Mm := MD.plan(Pm, MC, Fm)
	print("[ENV] INFO MeadowP9 規劃株を同 seed で再計算 %d ms：%d 株" % [Time.get_ticks_msec() - t0, (Mm["p"] as PackedVector2Array).size()])
	return {"p": Mm["p"], "F": Fm}


func _summary(P: Dictionary) -> void:
	var by := {}
	for ev: Dictionary in P["events"]:
		var k := "%s/%s" % [ev["cls"], ev["type"]]
		by[k] = int(by.get(k, 0)) + 1
	var keys := by.keys()
	keys.sort()
	print("[ENV] INFO event 型：%s" % "、".join(keys.map(func(k: Variant) -> String: return "%s %d" % [k, by[k]])))
	var drops := {}
	for d: String in P["dropped"]:
		var r := d.split(" ")[1] if d.split(" ").size() > 1 else d
		r = r.split(":")[0]
		drops[r] = int(drops.get(r, 0)) + 1
	print("[ENV] INFO 落とした理由：%s" % str(drops))
	var rd := {}
	for d: String in P["dropped"]:
		if d.begins_with("st_shibagaki"):
			var r2 := d.split(" ")[1].split(":")[0] if d.split(" ").size() > 1 else d
			rd[r2] = int(rd.get(r2, 0)) + 1
	print("[ENV] INFO 柴垣の落とした理由：%s" % str(rd))
	var nonmid := {}
	for it: Dictionary in P["items"]:
		var b := EL.box(String(it["id"]))
		var sc: float = it.get("s", 1.0)
		if not ((float(b[2]) * sc >= 0.5 and float(b[2]) * sc <= 6.0) or maxf(float(b[0]), float(b[1])) * 2.0 * sc >= 1.0):
			nonmid[it["id"]] = int(nonmid.get(it["id"], 0)) + 1
	print("[ENV] INFO 中尺度外の件：%s" % str(nonmid))


## event 單位に集める（negatives で件を書き換えても同じ規則で数える）
func _events(items: Array) -> Dictionary:
	var E := {}
	for it: Dictionary in items:
		var t := String(it["tag"])
		if not E.has(t):
			E[t] = {"cls": t.split("/")[0], "type": t.get_slice("_", 1) if t.split("/").size() > 1 else "", "main": [], "sat": [], "iso": []}
		var role := String(it.get("role", "main"))
		(E[t][role] as Array).append(it)
	return E


static func _cen(lst: Array) -> Vector2:
	var c := Vector2.ZERO
	for it: Dictionary in lst:
		c += it["p"]
	return c / maxf(1.0, lst.size())


static func _cv(a: Array) -> float:
	if a.size() < 2:
		return 0.0
	var mu := 0.0
	for x in a:
		mu += float(x)
	mu /= a.size()
	var var_ := 0.0
	for x in a:
		var_ += pow(float(x) - mu, 2.0)
	return sqrt(var_ / a.size()) / maxf(mu, 0.001)


# ─────────────────────────── gate ───────────────────────────

func _checks(P: Dictionary) -> void:
	var C: Dictionary = P["C"]
	var G: Dictionary = P["G"]
	var items: Array = P["items"]
	# 1 既存資產のみ
	var bad_ref: Array = []
	var ids := {}
	for it: Dictionary in items:
		var id := String(it["id"])
		ids[id] = true
		for lod in 2:
			var p := EL.mesh_path(id, lod) if (id.substr(0, 3) in EL.KITS or id in EL.VEG) else "missing"
			if not p.begins_with("res://assets/village_v2/") or not ResourceLoader.exists(p):
				bad_ref.append(p)
	check("既存資產のみ：%d 種 %d 件、全部 res://assets/village_v2/<既存 kit>/mesh の LOD0＋LOD1 を唯讀參照（新規 mesh・舊 kit 0；不正 %d）" % [ids.size(), items.size(), bad_ref.size()], bad_ref.is_empty() and items.size() > 0)
	var off: Array = []
	for it: Dictionary in items:
		if not (String(it["id"]) in EL.R54_IDS):
			off.append(String(it["id"]))
	check("分工：R5-4 語彙のみ（n1 と同じ自然・過渡 %d 種；柴堆・桶・箱・曬衣・商業・作業台・店前・市集は P10）——語彙外 %d %s" % [EL.R54_IDS.size(), off.size(), str(off.slice(0, 4))], off.is_empty())
	var mseal: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MEADOW_SEAL))
	var m_want: int = mseal["counts"]["near_instances"]
	var got: int = P.get("meadow_n", -1)
	var gin := 0
	for it: Dictionary in items:
		gin += EL.grass_in_core(C, it)
	var mdr := _meadow_drift(got, String(P.get("meadow_digest", "")), m_want, P12_MEADOW_DRIFT)
	check("MeadowP9 不重烘：規劃株 %d＝R5-3 封存の近級 %d（同 seed 再計算が封存と一致；不一致時は P12 封存差異登記 %s）、固い物の足元の芯に入る草株 %d（= 0）" % [got, m_want,
		"—" if got == m_want else ("適用" if mdr.is_empty() else "不適用 " + str(mdr)), gin], (got == m_want or mdr.is_empty()) and gin == 0)
	if not quiet and got != m_want and mdr.is_empty():
		var e1 := P12_MEADOW_DRIFT.duplicate(true)
		e1["upstream"][e1["upstream"].keys()[0]] = "0".repeat(64)
		var e2 := P12_MEADOW_DRIFT.duplicate(true)
		e2["baked"][e2["baked"].keys()[0]] = "0".repeat(64)
		var dg := String(P["meadow_digest"])
		check("反向（P12 差異登記）：株数 +1／同数で株位摘要違い／上游雜湊／封存 meadow 雜湊の竄改 → それぞれ不適用",
			not _meadow_drift(got + 1, dg, m_want, P12_MEADOW_DRIFT).is_empty() and not _meadow_drift(got, "0".repeat(64), m_want, P12_MEADOW_DRIFT).is_empty()
			and not _meadow_drift(got, dg, m_want, e1).is_empty() and not _meadow_drift(got, dg, m_want, e2).is_empty())
	# 2 接地（石は意図的に高さの 15–40 % 埋める＝埋まり分は許す）
	var fl := 0
	var sk := 0
	var worst := 0.0
	var sunk := 0
	for it: Dictionary in items:
		if String(it["id"]) in EL.FLAT:
			continue
		var hs: Array = [EL.top_h(C, it["p"])]
		for q: Vector2 in EL.corners(it):
			hs.append(EL.top_h(C, q))
		var y: float = it["y"]
		var h := float(EL.box(String(it["id"]))[2]) * float(it.get("s", 1.0))
		var want := float(it.get("sink", 0.0)) * h
		if want > 0.0:
			sunk += 1
		if y + want - float(hs.min()) > 0.02:
			fl += 1
		var extra := float(hs.max()) - (y + want)
		worst = maxf(worst, extra)
		if extra > 0.25 or float(it.get("sink", 0.0)) > 0.45:
			sk += 1
	check("接地：浮き（> 2 cm）%d・沈み（埋まり分を除き > 0.25 m、埋まり > 45 %%）%d、最大 %.2f m；意図的に埋めた石・杭 %d 件" % [fl, sk, worst, sunk], fl == 0 and sk == 0)
	# 3 禁區
	var bad := {}
	var others: Array = []
	for it: Dictionary in items:
		var r := EL.why(C, it, others)
		others.append(it)
		if r != "":
			bad[r.split(":")[0]] = int(bad.get(r.split(":")[0], 0)) + 1
	check("禁區：路面・店先帯・建物・水（+0.6 m）・P7 構件／橋・田・封存 overlay 構件・P10 の實ノード（+%.1f m）／NPC anchors（+%.1f m）・樹幹・互いの重なり・MeadowP9 株（固い物の芯）→ 違反 %d %s" % [EL.P10_PAD, EL.ANCHOR_PAD, _sum(bad), str(bad)], bad.is_empty())
	# 4 戸口・表側
	var front := 0
	for it: Dictionary in items:
		for b: Dictionary in C["bld"]:
			if (b["o"] as Vector2).distance_to(it["p"]) > 20.0:
				continue
			var d := (it["p"] as Vector2) - (b["o"] as Vector2)
			var lx := d.dot(b["ax"])
			var lz := d.dot(b["az"])
			if absf(lx) < float(b["w"]) * 0.5 + 0.3 and lz > float(b["d"]) * 0.5 and lz < float(b["d"]) * 0.5 + 2.2:
				front += 1
	check("戸口・表側：建物の表（路側）2.2 m 帯に置いた物 %d（裏・側だけを使う）" % front, front == 0)
	var E := _events(items)
	# 5 階層：主 cluster → satellite → 單件 → 留白（固定數にしない）
	var h_ok := true
	var htxt := PackedStringArray()
	for cl: String in EL.CLS:
		var n_ev := 0
		var mains: Array = []
		var sats := {}
		var with_sat := 0
		var iso := 0
		var spread_bad := 0
		var tot_n := 0
		for t: String in E:
			var e: Dictionary = E[t]
			if e["cls"] != cl or (e["main"] as Array).is_empty():
				continue
			n_ev += 1
			mains.append((e["main"] as Array).size())
			var ns := (e["sat"] as Array).size()
			sats[mini(ns, 8)] = true
			if ns > 0:
				with_sat += 1
			iso += (e["iso"] as Array).size()
			tot_n += (e["main"] as Array).size() + ns + (e["iso"] as Array).size()
			var c := _cen(e["main"])
			for it: Dictionary in e["main"]:
				if (it["p"] as Vector2).distance_to(c) > 8.0:
					spread_bad += 1
					break
		var mm := 0.0
		for x in mains:
			mm += float(x)
		mm /= maxf(1.0, mains.size())
		var share := float(with_sat) / maxf(1.0, n_ev)
		var tm := float(tot_n) / maxf(1.0, n_ev)
		# x2：主は 10–25 m で群に読める件數（水邊は据え置き）、event 全體も厚く
		var want_m := 1.8 if cl == "water" else 2.8
		var want_t := 2.5 if cl == "water" else 4.5
		var ok := n_ev >= 4 and mm >= want_m and tm >= want_t and share >= 0.35 and sats.size() >= 3 and iso > 0 and spread_bad == 0
		h_ok = h_ok and ok
		htxt.append("%s event %d・主平均 %.1f 件（≥ %.1f）・event 平均 %.1f 件（≥ %.1f）・satellite あり %.0f %%・satellite 件數 %d 通り・單件 %d・主の散り > 8 m %d" % [cl, n_ev, mm, want_m, tm, want_t, share * 100.0, sats.size(), iso, spread_bad])
	check("階層（主 cluster → satellite → 單件 → 留白）：%s" % "；".join(htxt), h_ok)
	# 6 非展示：同じ組成の繰り返し・型の偏り・倒木＋灌木／杭＋柴垣の固定セット・全部盛り
	var sig_by := {}
	var type_by := {}
	var pos_sig: Array = []
	var log_n := 0
	var log_shrub := 0
	var stake_n := 0
	var stake_shiba := 0
	var allin := 0
	for t: String in E:
		var e: Dictionary = E[t]
		if (e["main"] as Array).is_empty():
			continue
		var idl: Array = (e["main"] as Array).map(func(it: Dictionary) -> String: return String(it["id"]))
		idl.sort()
		var sig := "%s|%s" % [e["cls"], ",".join(idl)]
		var cl: String = e["cls"]
		if not sig_by.has(cl):
			sig_by[cl] = {}
			type_by[cl] = {}
		sig_by[cl][sig] = int(sig_by[cl].get(sig, 0)) + 1
		type_by[cl][e["type"]] = int(type_by[cl].get(e["type"], 0)) + 1
		pos_sig.append([_cen(e["main"]), sig])
		var cats := {}
		for id: String in idl:
			cats[_cat(id)] = true
		if cats.size() >= 4:
			allin += 1
		if "log_a" in idl:
			log_n += 1
			if "shrub_a" in idl:
				log_shrub += 1
		if idl.any(func(x: String) -> bool: return x in EL.STAKE):
			stake_n += 1
			if "st_shibagaki" in idl:
				stake_shiba += 1
	var worst_sig := 0.0
	var worst_type := 0.0
	var stxt := PackedStringArray()
	for cl: String in sig_by:
		var tot := 0
		var mx := 0
		for k: String in sig_by[cl]:
			tot += int(sig_by[cl][k])
			mx = maxi(mx, int(sig_by[cl][k]))
		var mt := 0
		for k: String in type_by[cl]:
			mt = maxi(mt, int(type_by[cl][k]))
		# 小さな類（event < 12）は 3 件までの同組成を許す
		worst_sig = maxf(worst_sig, 0.0 if mx <= 3 else float(mx) / tot)
		worst_type = maxf(worst_type, 0.0 if mt <= 4 else float(mt) / tot)
		stxt.append("%s 組成 %d 通り／%d" % [cl, (sig_by[cl] as Dictionary).size(), tot])
	var twin := 0
	for i in pos_sig.size():
		for j in range(i + 1, pos_sig.size()):
			if pos_sig[i][1] == pos_sig[j][1] and (pos_sig[i][0] as Vector2).distance_to(pos_sig[j][0]) < 40.0:
				twin += 1
	var ls := float(log_shrub) / maxf(1.0, log_n)
	var ss := float(stake_shiba) / maxf(1.0, stake_n)
	check("非展示：同じ組成の最大占有 %.0f %%（≤ 25 %%、3 件までは可）・型の最大占有 %.0f %%（≤ 45 %%、4 件までは可）・40 m 内の同組成 %d 組（≤ %d）・倒木＋灌木 %.0f %%（≤ 50 %%）・杭＋柴垣 %.0f %%（≤ 60 %%）・4 系統以上の全部盛り %d；%s" % [
		worst_sig * 100.0, worst_type * 100.0, twin, int(E.size() * 0.1), ls * 100.0, ss * 100.0, allin, "、".join(stxt)],
		worst_sig <= 0.25 and worst_type <= 0.45 and twin <= int(E.size() * 0.1) and ls <= 0.5 and ss <= 0.6 and allin == 0)
	# 7 間隔：錨は等距にしない／杭・垣の線は不等間隔
	var nn_txt := PackedStringArray()
	var nn_ok := true
	for cl: String in EL.CLS:
		var cs: Array = []
		for t: String in E:
			if E[t]["cls"] == cl and not (E[t]["main"] as Array).is_empty():
				cs.append(_cen(E[t]["main"]))
		# 最近接と第二近接（対になった 2 點の對稱で變動が消えないように）
		var nn: Array = []
		for i in cs.size():
			var ds: Array = []
			for j in cs.size():
				if i != j:
					ds.append((cs[i] as Vector2).distance_to(cs[j]))
			ds.sort()
			nn.append_array(ds.slice(0, 2))
		var cv := _cv(nn)
		nn_ok = nn_ok and cv >= 0.2
		nn_txt.append("%s %.2f" % [cl, cv])
	var lines := {}
	for it: Dictionary in items:
		var lid := String(it.get("line", ""))
		if lid != "":
			if not lines.has(lid):
				lines[lid] = []
			(lines[lid] as Array).append(it["p"])
	var sp: Array = []
	var run_bad := 0
	for lid: String in lines:
		var pts: Array = lines[lid]
		if pts.size() < 2:
			continue
		var dir := ((pts[pts.size() - 1] as Vector2) - (pts[0] as Vector2)).normalized()
		pts.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.dot(dir) < b.dot(dir))
		var run := 0
		var prev := -1.0
		for i in range(1, pts.size()):
			var d := (pts[i] as Vector2).distance_to(pts[i - 1])
			sp.append(d)
			run = run + 1 if prev >= 0.0 and absf(d - prev) < 0.1 else 0
			if run >= 2:
				run_bad += 1
			prev = d
	var lcv := _cv(sp)
	check("間隔：錨の最近接・第二近接距離の變動係數 %s（各 ≥ 0.20、等距にしない）・杭／垣の線 %d 本の間隔 變動係數 %.2f（≥ 0.15）・等間隔の連続 %d" % [", ".join(nn_txt), lines.size(), lcv, run_bad],
		nn_ok and lcv >= 0.15 and run_bad == 0)
	# 8 邊界邏輯：田の縁の杭・垣は等高線に沿う／蘆・菅は水際（≤ 2.6 m）／水邊の石は埋まる／村邊は人工が内・自然が外
	var farm_bad := 0
	var farm_n := 0
	var wet_bad := 0
	var wet_n := 0
	var wrock := 0
	var wrock_sunk := 0
	var art_d: Array = []
	var nat_d: Array = []
	for it: Dictionary in items:
		var id := String(it["id"])
		var cl := String(it.get("cls", ""))
		if cl == "farm" and String(it.get("mode", "")) == "line":
			farm_n += 1
			var g := EL.grad(G, "A", it["p"])
			var face := Vector2(sin(float(it["yaw"])), cos(float(it["yaw"])))
			var dA := EL.gb(G, "A", it["p"])
			if absf(rad_to_deg(face.angle_to(g))) > 30.0 or dA < 0.5 or dA > 2.6:
				farm_bad += 1
		if cl == "water" and id in EL.WETS:
			wet_n += 1
			if EL.gb(G, "W", it["p"]) > 2.6:
				wet_bad += 1
		if cl == "water" and id in EL.ROCKS:
			wrock += 1
			if float(it.get("sink", 0.0)) >= 0.1:
				wrock_sunk += 1
		if cl == "edge":
			if id in ["gk_yotsume", "rb_pile_a", "rb_pile_r"]:
				art_d.append(EL.gb(G, "B", it["p"]))
			elif id in EL.SAPL:
				nat_d.append(EL.gb(G, "B", it["p"]))
	var am := _mean(art_d)
	var nm := _mean(nat_d)
	# 一本だけ立つ杭（3.5 m 内に別の杭・垣がない、または 5 m 内に杭以外の連れがない）＝debug prop
	var lone := 0
	for it: Dictionary in items:
		if not (String(it["id"]) in EL.STAKE):
			continue
		var mate := false
		var comp := false
		for o: Dictionary in items:
			if o == it:
				continue
			var d := (o["p"] as Vector2).distance_to(it["p"])
			if (String(o["id"]) in EL.STAKE or String(o["id"]) in EL.FENCES) and d < 3.5:
				mate = true
			if not (String(o["id"]) in EL.STAKE) and d < 5.0:
				comp = true
		if not (mate and comp):
			lone += 1
	check("邊界邏輯：田の縁の杭・柴垣 %d 件のうち等高線（田から 0.5–2.6 m・向き ±30°）外れ %d・一本だけの杭（debug prop）%d・蘆／菅／花菖蒲 %d 件のうち水際 2.6 m より内陸 %d・水邊の石 %d 件のうち埋まり ≥ 10 %% %d・村邊 人工物の建物距離 %.1f m < 幼樹 %.1f m" % [
		farm_n, farm_bad, lone, wet_n, wet_bad, wrock, wrock_sunk, am, nm], farm_bad == 0 and farm_n > 0 and lone == 0 and wet_bad == 0 and wet_n > 0 and wrock_sunk >= int(ceil(wrock * 0.8)) and am < nm)
	# 9 大留白：各類の候補セルのうち件から 4 m 以內の割合
	var ih := EL.RH.new()
	ih.cs = 4.0
	for it: Dictionary in items:
		ih.add(it["p"], Rect2(it["p"], Vector2.ZERO))
	var cov := {}
	var tot := {}
	var o: Vector2 = G["o"]
	for j in range(1, int(G["nz"]) - 1, 2):
		for i in range(1, int(G["nx"]) - 1, 2):
			var p := o + Vector2(i + 0.5, j + 0.5)
			var cl := EL.klass(C, G, p)
			if cl == "":
				continue
			tot[cl] = int(tot.get(cl, 0)) + 1
			for q: Vector2 in ih.near(p, 4.0):
				if q.distance_to(p) < 4.0:
					cov[cl] = int(cov.get(cl, 0)) + 1
					break
	var ctxt := PackedStringArray()
	var c_ok := true
	for cl: String in EL.CLS:
		var f := float(cov.get(cl, 0)) / maxf(1.0, float(tot.get(cl, 0)))
		c_ok = c_ok and f <= float({"open": 0.38, "water": 0.32}.get(cl, 0.40))
		ctxt.append("%s %.0f %%" % [cl, f * 100.0])
	check("大留白：各類の場所のうち物から 4 m 以內の割合 %s（x2：空地 ≤ 38 %%、水邊 ≤ 32 %%、他 ≤ 40 %%）" % "、".join(ctxt), c_ok)
	# 10 P10 優先
	var near_p10 := 0
	for ev: Dictionary in P["events"]:
		if EL.gb(G, "P", ev["p"]) < 5.0:
			near_p10 += 1
	var shiba_bad := 0
	for it: Dictionary in items:
		if String(it["id"]) == "st_shibagaki" and not EL._shiba_ok(C, it["p"]):
			shiba_bad += 1
	check("P10 優先：build 時に讀んだ P10 occupancy %d 矩形（Props の EnvironmentP9 以外の全子＝市集・主街・市集西・今後の P10、NPC anchors 含む）・P10 の柴垣 %d；錨が P10 から 5 m 未満 %d・P10 の柴垣から 12 m 內の柴垣 %d" % [
		(C["p10"] as Array).size(), (C.get("p10_shiba", []) as Array).size(), near_p10, shiba_bad], near_p10 == 0 and shiba_bad == 0 and (C["p10"] as Array).size() > 0)
	# 11 村邊：村を籬笆で囲わない
	var edge_ev := 0
	var fence_ev: Array = []
	var yot := 0
	var edge_items := 0
	for t: String in E:
		var e: Dictionary = E[t]
		if e["cls"] != "edge":
			continue
		edge_items += (e["main"] as Array).size() + (e["sat"] as Array).size() + (e["iso"] as Array).size()
		if (e["main"] as Array).is_empty():
			continue
		edge_ev += 1
		var has_y := false
		for it: Dictionary in e["main"]:
			if String(it["id"]) == "gk_yotsume":
				has_y = true
				yot += 1
		if has_y:
			fence_ev.append(_cen(e["main"]))
	var fclose := 0
	for i in fence_ev.size():
		for j in range(i + 1, fence_ev.size()):
			if (fence_ev[i] as Vector2).distance_to(fence_ev[j]) < 30.0:
				fclose += 1
	var fshare := float(fence_ev.size()) / maxf(1.0, edge_ev)
	check("村邊：四つ目垣のある event %d / %d（≤ 35 %%）・30 m 內で隣り合う垣 %d・垣の枚數 %d（村邊の件の ≤ 15 %%）" % [fence_ev.size(), edge_ev, fclose, yot],
		fshare <= 0.35 and fclose == 0 and float(yot) <= 0.15 * maxf(1.0, edge_items))
	# 12 中尺度
	var mid := 0
	var micro := 0
	for it: Dictionary in items:
		var b := EL.box(String(it["id"]))
		var s: float = it.get("s", 1.0)
		var h := float(b[2]) * s
		var foot := maxf(float(b[0]), float(b[1])) * 2.0 * s
		if (h >= 0.5 and h <= 6.0) or foot >= 1.0:
			mid += 1
		if h < 0.3 and foot < 0.6:
			micro += 1
	check("中尺度：高さ 0.5–6 m か足元 ≥ 1 m の物 %d / %d（≥ 75 %%）、微小（< 0.3 m かつ < 0.6 m）%d（≤ 15 %%）" % [mid, items.size(), micro],
		float(mid) / maxf(1.0, items.size()) >= 0.75 and float(micro) / maxf(1.0, items.size()) <= 0.15)
	# 13 封存の不變
	var seal: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(R5_SEAL))
	var gk := "godot/maps/village_v2/gen/groundcover_p9.scn"
	check("封存不改：R5 Macro Ground（%s）雜湊＝封存時；本 overlay は別ファイル %s" % [gk.get_file(), EL.OUTPUT.get_file()], FileAccess.get_sha256(GC.OUTPUT) == String(seal["frozen"][gk]))


static func _cat(id: String) -> String:
	if id in EL.ROCKS or id in EL.COB:
		return "rock"
	if id in ["log_a", "snag_a"]:
		return "deadwood"
	if id in EL.SAPL:
		return "tree"
	if id in ["shrub_a"]:
		return "shrub"
	if id in ["sasa_a", "fern_a"]:
		return "under"
	if id in EL.WETS:
		return "wet"
	if id in EL.STAKE or id in ["st_shibagaki", "gk_yotsume"]:
		return "fence"
	return "stone_path"


static func _mean(a: Array) -> float:
	var s := 0.0
	for x in a:
		s += float(x)
	return s / maxf(1.0, a.size())


func _sum(d: Dictionary) -> int:
	var s := 0
	for k in d:
		s += int(d[k])
	return s


# ─────────────────────────── 反向 ───────────────────────────

func _negatives(v: Node3D, P: Dictionary) -> int:
	var C: Dictionary = P["C"]
	var G: Dictionary = P["G"]
	var base: Array = P["items"]
	var bad := 0
	var cases := {"n_road": "禁區", "n_p10": "禁區", "n_p10pad": "禁區", "n_float": "接地", "n_front": "戸口", "n_micro": "中尺度", "n_legacy": "既存資產",
		"n_lifeprop": "分工", "n_grass": "MeadowP9", "n_scatter": "階層", "n_nohier": "階層", "n_showcase": "非展示", "n_logshrub": "非展示",
		"n_equidistant": "間隔", "n_inland_reed": "邊界邏輯", "n_fill": "大留白", "n_fence_ring": "村邊", "n_p10near": "P10 優先", "n_lonestake": "邊界邏輯"}
	for nm: String in cases:
		var items: Array = []
		for it: Dictionary in base:
			items.append(it.duplicate())
		var P2 := P.duplicate()
		var tag0 := String(items[0]["tag"])
		match nm:
			"n_road":
				var ms: PackedVector2Array = C["roads"]["MainStreet"]["pts"]
				items.append(EL.item(C, "sk_box", ms[2], Vector2(0, 1), tag0))
			"n_p10":
				var r0: Rect2 = (C["p10"] as Array)[0]
				items.append(EL.item(C, "sk_box", r0.get_center(), Vector2(0, 1), tag0))
			"n_float":
				for it: Dictionary in items:
					if not (String(it["id"]) in EL.FLAT):
						it["y"] = float(it["y"]) + 0.3
						break
			"n_front":
				var b: Dictionary = (C["bld"] as Array)[10]
				items.append(EL.item(C, "sk_box", (b["o"] as Vector2) + (b["az"] as Vector2) * (float(b["d"]) * 0.5 + 1.0), Vector2(0, 1), tag0))
			"n_micro":
				for it: Dictionary in items:
					it["id"] = "gk_tobi_d"
			"n_legacy":
				items[0]["id"] = "kr_nope_missing"
			"n_lifeprop":
				items[0]["id"] = "sk_woodpile"
			"n_p10pad":
				var r1: Rect2 = (C["p10"] as Array)[0]
				items.append(EL.item(C, "rb_pile_a", Vector2(r1.position.x + EL.P10_PAD - 1.0, r1.get_center().y), Vector2(0, 1), tag0))
			"n_grass":
				var g: Dictionary = C["meadow"]
				var k0: Vector2i = g.keys()[g.size() / 2]
				items.append(EL.item(C, "gk_kei_flat", Vector2(k0.x * 0.5 + 0.25, k0.y * 0.5 + 0.25), Vector2(0, 1), tag0))
			"n_scatter":
				# 一つの主 cluster を 14 m 輪に散らす
				var k := 0
				for it: Dictionary in items:
					if String(it["tag"]) == tag0 and String(it["role"]) == "main":
						it["p"] = (it["p"] as Vector2) + Vector2.from_angle(k * 1.3 + 0.4) * 14.0
						k += 1
			"n_nohier":
				items = items.filter(func(it: Dictionary) -> bool: return String(it["role"]) == "main")
			"n_showcase":
				# 林緣の主 cluster を全部同じ組成（倒木＋景石＋灌木＋羊歯）に
				var seen := {}
				var keep: Array = []
				for it: Dictionary in items:
					if String(it["cls"]) == "forest" and String(it["role"]) == "main":
						if seen.has(it["tag"]):
							continue
						seen[it["tag"]] = true
						var c0: Vector2 = it["p"]
						for e: Array in [["log_a", Vector2.ZERO], ["gk_kei_mid", Vector2(2, 0)], ["shrub_a", Vector2(-2, 1)], ["fern_a", Vector2(0, 2)]]:
							var n2 := (it as Dictionary).duplicate()
							n2["id"] = e[0]
							n2["p"] = c0 + (e[1] as Vector2)
							keep.append(n2)
					else:
						keep.append(it)
				items = keep
			"n_logshrub":
				# 倒木の event に必ず灌木を添える
				for it: Dictionary in items.duplicate():
					if String(it["id"]) == "log_a" and String(it["role"]) == "main":
						var n3 := it.duplicate()
						n3["id"] = "shrub_a"
						n3["p"] = (it["p"] as Vector2) + Vector2(2.2, 0)
						items.append(n3)
			"n_equidistant":
				# 杭・垣の線を 1.5 m 等間隔に
				var lines := {}
				for it: Dictionary in items:
					if String(it.get("line", "")) != "":
						if not lines.has(it["line"]):
							lines[it["line"]] = []
						(lines[it["line"]] as Array).append(it)
				for lid in lines:
					var lst: Array = lines[lid]
					if lst.size() < 2:
						continue
					var p0: Vector2 = lst[0]["p"]
					var dir := ((lst[lst.size() - 1]["p"] as Vector2) - p0).normalized()
					for i in lst.size():
						lst[i]["p"] = p0 + dir * 1.5 * i
			"n_inland_reed":
				for it: Dictionary in items:
					if String(it["cls"]) == "water" and String(it["id"]) in EL.WETS:
						it["p"] = EL.to_band(G, "W", it["p"], 5.0)
						break
			"n_fill":
				# 空地を 3 m 格子で埋める
				var o: Vector2 = G["o"]
				for j in range(1, int(G["nz"]) - 1, 3):
					for i in range(1, int(G["nx"]) - 1, 3):
						var p := o + Vector2(i + 0.5, j + 0.5)
						if EL.klass(C, G, p) == "open":
							var n4 := (items[0] as Dictionary).duplicate()
							n4["p"] = p
							n4["id"] = "shrub_a"
							items.append(n4)
			"n_fence_ring":
				# 村邊の event を全部「四つ目垣」に
				var done := {}
				for it: Dictionary in items:
					if String(it["cls"]) == "edge" and String(it["role"]) == "main" and not done.has(it["tag"]):
						done[it["tag"]] = true
						it["id"] = "gk_yotsume"
			"n_lonestake":
				# 既存の event の 12 m 先に杭を一本だけ（連れなし）
				var b0: Dictionary = items[0]
				var n5 := b0.duplicate()
				n5["id"] = "rb_pile_a"
				n5["p"] = (b0["p"] as Vector2) + Vector2(12.0, 7.0)
				items.append(n5)
			"n_p10near":
				var evs: Array = (P["events"] as Array).duplicate()
				var e0: Dictionary = (evs[0] as Dictionary).duplicate()
				e0["p"] = ((C["p10"] as Array)[0] as Rect2).get_center()
				evs[0] = e0
				P2["events"] = evs
		fails = 0
		failed_labels.clear()
		quiet = true
		P2["items"] = items
		_checks(P2)
		quiet = false
		var hit := failed_labels.any(func(l: String) -> bool: return l.begins_with(String(cases[nm])))
		print("[ENV] %s 反向 %s → 「%s」必須 FAIL（失敗項 %d：%s）" % ["PASS" if hit else "FAIL", nm, cases[nm], failed_labels.size(), " ／ ".join(failed_labels.map(func(l: String) -> String: return l.left(6)))])
		if not hit:
			bad += 1
	print("[ENV] 結果：%d 項失敗（negatives）" % bad)
	return bad


# ─────────────────────────── 封存（R5-4） ───────────────────────────

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
	check("P9 R5-4 封存 %d 檔雜湊一致（凍結 %d、ART_REVIEW 圖 %d、證據 %d；不符 %d：%s）" % [n, seal["frozen"].size(),
		seal["art_review_images"].size(), seal["evidence"].size(), bad.size(), ", ".join(bad.slice(0, 4))], bad.is_empty())
	var txt := FileAccess.get_file_as_string(SCENE)
	var idx: Array = []
	for nm: String in PROPS_ORDER:
		idx.append(txt.find("[node name=\"%s\" parent=\"Props\"" % nm))
	var ord_ok: bool = int(idx[0]) >= 0
	for k in range(1, idx.size()):
		ord_ok = ord_ok and int(idx[k]) > int(idx[k - 1])
	check("village_v2.tscn 掛載 Props/%s（%s、1 個）" % [" → ".join(PROPS_ORDER), EL.OUTPUT], ord_ok and txt.contains(EL.OUTPUT) and txt.count("[node name=\"EnvironmentP9\"") == 1)
	check("art_revision＝封存時（%s）" % seal["art_revision"], EL.ART_REVISION == String(seal["art_revision"]))
	var neg_seal := seal.duplicate(true)
	var k0: String = neg_seal["frozen"].keys()[0]
	neg_seal["frozen"][k0] = "0".repeat(64)
	var nb := _seal_mismatch(neg_seal)
	check("反向：竄改 %s 期望雜湊 → 偵測到 1 筆不符（實際 %d）" % [k0, nb.size() - bad.size()], nb.size() == bad.size() + 1)
	print("[ENV] 結果：%d 項失敗（seal）" % fails)
	return fails


# ─────────────────────────── 平面図データ ───────────────────────────

func _dump(P: Dictionary, path: String) -> void:
	var out := {"items": [], "anchors": []}
	for it: Dictionary in P["items"]:
		(out["items"] as Array).append([String(it["id"]), snappedf((it["p"] as Vector2).x, 0.1), snappedf((it["p"] as Vector2).y, 0.1), String(it["tag"]), String(it.get("role", ""))])
	for a: Dictionary in P["anchors"]:
		(out["anchors"] as Array).append([String(a["cls"]), snappedf((a["p"] as Vector2).x, 0.1), snappedf((a["p"] as Vector2).y, 0.1)])
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	f.close()
	print("[ENV] dump → %s" % path)


# ─────────────────────────── 審圖機位 ───────────────────────────

## 各類 2 event（satellite・單件まで揃った大きいもの、互いに 70 m 以上離す）を、類の「見る側」から近景 7 m／中景 14 m
##   water：陸側から水へ／farm：村側から田へ／forest：開けた側から林へ／edge：村の内側から外へ／open：空き地の内から縁へ
func _views(P: Dictionary, out_path: String) -> void:
	var C: Dictionary = P["C"]
	var G: Dictionary = P["G"]
	var S: RLib.TriSampler = C["S"]
	var E := _events(P["items"])
	var views: Array = []
	for cl: String in ["open", "farm", "edge", "water", "forest"]:
		var cand: Array = []
		for t: String in E:
			var e: Dictionary = E[t]
			if e["cls"] != cl or (e["main"] as Array).is_empty():
				continue
			var all_n: int = (e["main"] as Array).size() + (e["sat"] as Array).size() + (e["iso"] as Array).size()
			cand.append([all_n + 0.5 * (e["sat"] as Array).size(), t])
		cand.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
		var chosen: Array = []
		for c: Array in cand:
			if chosen.size() >= (1 if cl == "water" else 2):
				break
			var cen := _cen(E[c[1]]["main"])
			if chosen.any(func(q: Vector2) -> bool: return q.distance_to(cen) < 70.0):
				continue
			var face := EL.grad(G, EL.FIELD[cl], cen)
			if cl == "edge":
				face = -face
			var vv := _view_pair(C, P["items"], S, cen, face, "%s_%d" % [cl, chosen.size() + 1])
			if vv.size() == 2:
				views.append_array(vv)
				chosen.append(cen)
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(views, " "))
	f.close()
	print("[ENV] 審圖機位 %d → %s" % [views.size(), out_path])


func _view_pair(C: Dictionary, items: Array, S: RLib.TriSampler, cen: Vector2, face: Vector2, nm: String) -> Array:
	var out: Array = []
	for rr: float in [7.0, 14.0]:
		var best: Array = []
		for k in 25:
			var a := (k - 12) * deg_to_rad(10.0)
			var dir := face.rotated(a)
			var stp := cen + dir * rr
			var f := (cen - stp).normalized()
			var back := stp - f * 3.6
			# 實際のカメラ位置（shot_village_v2_props と同じ：肩越し 1.4 m 横）——そこからの視線が建物・樹幹で塞がれないこと
			var cam2 := stp + Vector2(-f.y, f.x) * 1.4 - f * 3.4
			var ok := true
			if EL.bdist(C, stp) < 2.2 or EL.bdist(C, back) < 3.0 or EL.bdist(C, cam2) < 2.5:
				ok = false
			for t4 in range(1, 12):
				var q4 := cam2.lerp(cen, t4 / 12.0)
				if EL.bdist(C, q4) < 0.3:
					ok = false
				for tr: Vector2 in (C["h_trees"] as EL.RH).at(q4):
					if tr.distance_to(q4) < 1.3:
						ok = false
			for q: Vector2 in [stp, back, stp.lerp(back, 0.5)]:
				var c := EL.cell(C, q)
				if not (c in ["", "R", "F"]):
					ok = false
				for t: Vector2 in C["trees"]:
					if t.distance_to(q) < 1.4:
						ok = false
				for it: Dictionary in items:
					if (it["p"] as Vector2).distance_to(q) < 1.6:
						ok = false
			var hs := S.h(stp.x, stp.y)
			if is_nan(hs) or is_nan(S.h(back.x, back.y)) or S.h(back.x, back.y) - hs > 0.8:
				ok = false
			if ok:
				var cam := Vector3(back.x, hs + 2.2, back.y)
				var tgt := Vector3(cen.x, S.h(cen.x, cen.y) + 0.6, cen.y)
				for t2 in range(1, 12):
					var q3 := cam.lerp(tgt, t2 / 12.0)
					var th2 := S.h(q3.x, q3.z)
					if not is_nan(th2) and th2 > q3.y - 0.25:
						ok = false
				for b: Dictionary in C["bld"]:
					if ok and (b["o"] as Vector2).distance_to(stp) < 30.0:
						for t3 in range(1, 10):
							if EL.obb_d(b, back.lerp(cen, t3 / 10.0)) < 0.0:
								ok = false
								break
			if ok and (best.is_empty() or absf(a) < float(best[0])):
				best = [absf(a), stp]
		if best.is_empty():
			print("[ENV] INFO 機位 %s %.0f m：見通しの良い立ち位置なし" % [nm, rr])
			return []
		var s2: Vector2 = best[1]
		out.append(["%s_%s" % [nm, "near" if rr < 10.0 else "mid"], snappedf(s2.x, 0.1), snappedf(s2.y, 0.1), snappedf(cen.x, 0.1), snappedf(cen.y, 0.1), -0.2 if rr < 10.0 else -0.14, 3.6, 1.4])
	return out


# ─────────────────────────── site 調査 ───────────────────────────

func _survey(C: Dictionary, c: Vector2, r: float) -> void:
	print("[ENV] survey (%.1f, %.1f) r %.0f m（1 字＝1 m、上＝−z 北、左＝−x 西）" % [c.x, c.y, r])
	var z := c.y - r
	while z <= c.y + r:
		var line := ""
		var x := c.x - r
		while x <= c.x + r:
			var q := Vector2(x, z)
			var k := EL.cell(C, q)
			if k == "":
				var h0 := EL.top_h(C, q)
				var dh := maxf(absf(EL.top_h(C, q + Vector2(0.5, 0)) - h0), absf(EL.top_h(C, q + Vector2(0, 0.5)) - h0))
				k = "~" if dh > 0.12 else "."
			if q.distance_to(c) < 0.6:
				k = "@"
			line += k
			x += 1.0
		print("[ENV] %7.1f %s" % [z, line])
		z += 1.0


# ─────────────────────────── 掛載・場景 ───────────────────────────

func _attach() -> int:
	var txt := FileAccess.get_file_as_string(SCENE)
	if not FileAccess.file_exists(EL.OUTPUT):
		push_error("找不到 %s（先 --build）" % EL.OUTPUT)
		return 1
	if txt.contains("gen/environment_p9.scn"):
		print("[ENV] attach：已掛 EnvironmentP9（不重複、不寫場景）")
		return 0
	var nl := "\r\n" if txt.contains("\r\n") else "\n"
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
	out.insert(ins, "[node name=\"%s\" parent=\"Props\" instance=ExtResource(\"p9r54_environment\")]" % EL.NODE_NAME)
	out.insert(last_ext + 1, "[ext_resource type=\"PackedScene\" path=\"%s\" id=\"p9r54_environment\"]" % EL.OUTPUT)
	var f := FileAccess.open(SCENE, FileAccess.WRITE)
	f.store_string(nl.join(out))
	f.close()
	print("[ENV] attach：加 Props/%s（Props の末尾）→ %s（+%d 行）" % [EL.NODE_NAME, SCENE, out.size() - lines.size()])
	return 0


func _scene(v: Node3D) -> void:
	var go := v.get_node_or_null("Props/" + EL.NODE_NAME) as Node3D
	var names: Array = []
	for c in v.get_node("Props").get_children():
		names.append(String(c.name))
	check("場景已掛 Props/%s（1 個、Props の子：%s）、P9 Vegetation 掛載不變（MeadowP9 は GroundcoverP9 の後）" % [EL.NODE_NAME, " → ".join(names)],
		go != null and names.count(EL.NODE_NAME) == 1 and v.get_node_or_null("Vegetation/MeadowP9") != null and v.get_node("Vegetation/MeadowP9").get_index() > v.get_node("Vegetation/GroundcoverP9").get_index())
	if go == null:
		return
	check("art_revision＝%s、visible、scene_file_path＝%s" % [go.get_meta("art_revision", "?"), EL.OUTPUT], String(go.get_meta("art_revision", "")) == EL.ART_REVISION and go.visible and go.scene_file_path == EL.OUTPUT)
	var mm := go.find_children("*", "MultiMeshInstance3D", true, false).size()
	var mi := go.find_children("*", "MeshInstance3D", true, false)
	var lod_ok := true
	for g in mi:
		lod_ok = lod_ok and (g as MeshInstance3D).mesh != null and String((g as MeshInstance3D).mesh.resource_path).begins_with("res://assets/village_v2/")
	check("個別ノード：MeshInstance %d（MultiMesh %d）、mesh は全部既存 kit の .res" % [mi.size(), mm], mm == 0 and lod_ok and mi.size() > 0)
	var cls_n: Array = []
	for c in go.get_children():
		if String(c.name) != "Collision":
			cls_n.append("%s %d" % [c.name, c.get_child_count()])
	check("類／event の木構造：%s（5 類とも存在）" % "、".join(cls_n), cls_n.size() == 5)
	for nm in ["MarketP10", "StreetP10", "MarketWestP10"]:
		var n := v.get_node_or_null("Props/" + nm)
		check("並行 P10：Props/%s 仍掛載・visible" % nm, n != null and (n as Node3D).visible)

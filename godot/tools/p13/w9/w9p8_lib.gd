extends RefCounted
## 人間之里 V2 P13 W9 Phase 8（使用者 2026-10-16「Village-Wide Completion Survey」第一批・ART_REVIEW）の環境生成器（source of truth）。
## 全村盤點（docs/art_review/village_v2_p13/wave9/phase8_village_survey/）で選んだ、封存層に触れない 2 区域：
##   A8 稗田邸の西（中橫街の東端～田埂道 FarmPath_1 沿い～大宅の西塀）：
##       辻の地蔵／塀外の稲の置き場（俵・稲叢・荷車・臼）／西塀の足元の植え込み／道の終わりの北の雑木林。
##       稗田阿求の任務路線（中橫街 → 田埂道 → 大宅門）で、長く空いた接近路と白い塀だけの終点に、名家の門前の暮らしと緑の過渡を与える。
##   B8 東北聚落（龍神橋の東・香霖堂への出入口の裏手、RNE 19 棟は W9 で未改修）：
##       各戸の門前の暮らし（W9.FEAT）／宅間の垣・下屋・祠（W9.gap_recipe）／集落の共同井戸／屋根並みの背後の樹冠。
## overlay `EnrichW9P8`（root 直下・EnrichW9P4 の次）→ gen/enrich_w9p8.scn。ビルド：tools/p13/w9/build_w9p8.gd。
## 掛載（village_v2.tscn への 3 行）は共有編輯器の未保存状態が確認できるまで行わない（Phase 8 報告 §10）。検証と審圖は記憶の中で掛けて行う。
## 方針：W9 R1／Phase 3／4 の plan／why（道・建物・戸口・水・田・封存物・NPC 動線・Hero への不侵入、接地）をそのまま使う。
## 新規の資産は無し（承認済み Kit・veg_kit・P3 の樹の再配置のみ）。MultiMesh なし。
const P3 := preload("res://tools/p13/w9/w9p3_lib.gd")
const P4L := preload("res://tools/p13/w9/w9p4_lib.gd")   # _gap_runner_p4（宅間の構件を奥へ平行移動して検査し直す）を再利用
const W9 := preload("res://tools/p13/w9/w9_lib.gd")
const HU := preload("res://tools/village_v2_human_use_lib.gd")

const NODE_NAME := "EnrichW9P8"
const OUTPUT := "res://maps/village_v2/gen/enrich_w9p8.scn"
const SCENE := "res://maps/village_v2/village_v2.tscn"
const AFTER := "EnrichW9P4"
const ART_REVISION := "P13 W9 Phase 8 第一批 r2（ART_REVIEW）：A8 稗田邸の西の参道、B8 東北聚落（香霖堂口）"
## P3.bake は ZONE_NAME（B3／C3）の節点に振り分けるので、計画中は A8→B3・B8→C3 を使い、bake 後に名前を戻す（Phase 4 と同じ扱い）
const ZONE_OF := {"A8": "B3", "B8": "C3"}
const ZONE_NAME := {"A8": "稗田邸の西（中橫街の東端・田埂道・大宅の西塀）", "B8": "東北聚落（龍神橋の東・香霖堂口・RNE）"}
## 腕（SpringArm）の検査線：[名, 折れ線]（verify_w9p8.gd が使う。通行帯＝軸 ±1.2 m）
const ARM_LANES := {
	"A8_cross_end": [Vector2(352.0, -35.2), Vector2(380.0, -36.0)],
	"A8_farmpath": [Vector2(372.0, -33.0), Vector2(372.0, -2.0)],
	"B8_nelane": [Vector2(424.0, -205.0), Vector2(438.0, -216.0), Vector2(456.0, -236.0), Vector2(470.0, -241.0)],
	"B8_nesouth": [Vector2(438.0, -216.0), Vector2(458.0, -208.0), Vector2(474.0, -192.0), Vector2(490.0, -188.0)],
}

## B8 各戸の門前（[feat, side, nth]）。同じ組を 3 戸以上に使わない（verify の sets_ok）
const B_HOUSES := {
	"B_P_RNE_001": [["kame", 1, 0], ["wood", -1, 0]],
	"B_P_RNE_002": [["sudare", 1, 0], ["ueki", -1, 0]],
	"B_P_RNE_003": [["noren_kinari", 0, 0], ["kaki", -1, 0], ["hachi", 1, 0]],
	"B_P_RNE_004": [["tools", -1, 0], ["kago", 1, 0]],
	"B_P_RNE_005": [["asagao", 1, 0], ["wood", -1, 0]],
	"B_P_RNE_010": [["wood", 1, 0], ["hachi", -1, 0]],
	"B_P_RNE_011": [["asagao", -1, 0], ["hachi", 1, 0]],
	"B_P_RNE_012": [["toga", 1, 0], ["wood", -1, 0]],
	"B_P_RNE_013": [["noren_ai", 0, 0], ["ueki", 1, 0]],
	"B_P_RNE_016": [["kago", -1, 0], ["sudare", 1, 0]],
	"B_P_RNE_017": [["tools", 1, 0], ["kaki", -1, 0]],
}
## B8 宅間の recipe（gaps() の幅で選ぶ。幅の狭い宅間は open／shrine だけ）。key の辞書順で決定的に割り当てる
const B_GAP_RECIPES := [["yard", {"gate": 0.5, "kaki": true}], ["shed_wood", {"wall": "a"}], ["fence_gate", {"gate": 0.45, "id": "w9_takegaki"}],
	["shrine", {"id": "w9_jizo"}], ["shed_tool", {"wall": "c"}], ["open", {}], ["fence", {"id": "w9_itabei_b"}], ["yard", {"gate": 0.6}]]
const B_GAP_MAX := 8
const KIDO_SETBACK := 5.5


static func _plant(C: Dictionary, items: Array, id: String, x: float, z: float, s: float, meta: Dictionary, rmax := 1.5) -> Dictionary:
	return P3._plant(C, items, id, x, z, s, meta, rmax)


static func _gr(C: Dictionary, items: Array, id: String, x: float, z: float, face: Vector2, meta: Dictionary, rmax := 0.8) -> Dictionary:
	return P3._ground(C, items, id, x, z, face, meta, rmax)


# ─────────────────────────── A8：稗田邸の西 ───────────────────────────

static func design_A8(_C: Dictionary) -> Array:
	var D: Array = []
	var W := Vector2(-1.0, 0.0)
	D.append({"id": "A8_jizo", "zone": "A8", "desc": "中橫街の東端と田埂道の辻（大宅の西の角）：辻の地蔵と供え花", "center": Vector2(375.8, -30.3), "run": func(C2: Dictionary, items: Array, meta: Dictionary) -> void:
		var m := meta.duplicate()
		m.merge({"who": "辻を通る村人", "why": "大宅の角の辻に立つ地蔵（田と屋敷と道の分かれ目の目印）"}, true)
		_gr(C2, items, "w9_jizo", 375.8, -30.3, Vector2(-0.55, -0.83), m, 0.8)
		var mf := m.duplicate()
		mf.merge({"who": "地蔵に花を供える人", "why": "地蔵の足元の供え花と野の花"}, true)
		_plant(C2, items, "w9_hana_shiro", 374.9, -29.6, 1.0, mf, 0.5)
		_plant(C2, items, "w9_hana_kiiro", 376.7, -29.4, 0.9, mf, 0.5)
		_plant(C2, items, "fern_a", 376.9, -30.9, 0.8, mf, 0.5)})
	D.append({"id": "A8_rice_yard", "zone": "A8", "desc": "西塀の外の稲の置き場：俵の山・稲叢・荷車・臼・背負い籠（田から運んだ稲を大宅へ納める前の置き場。高さ 2 m 未満で塀と屋敷を隠さない）", "center": Vector2(378.6, -20.5), "run": func(C2: Dictionary, items: Array, meta: Dictionary) -> void:
		var m := meta.duplicate()
		m.merge({"who": "稗田家の田を耕す小作の人々", "why": "刈り取った稲を俵にして、大宅の蔵へ納める前に塀の外へ積んでおく"}, true)
		# r2：審圖『散らばった点にしか見えない』→ 荷下ろし（荷車を塀に沿って止め、その脇に俵）と籾摺り（筵・臼・籠）の 2 組に寄せる
		_gr(C2, items, "wk_tawara3", 381.0, -20.8, W, m, 0.6)
		_gr(C2, items, "wk_tawara3", 381.1, -18.6, W.rotated(0.2), m, 0.6)
		_gr(C2, items, "wk_tawara", 379.9, -21.2, W.rotated(-0.4), m, 0.5)
		_gr(C2, items, "mk_kuruma_ni", 378.7, -18.4, Vector2(0.0, 1.0).rotated(-0.06), m, 0.6)
		var mw := m.duplicate()
		mw.merge({"who": "稲を干す小作", "why": "脱穀を待つ稲叢（藁塚）"}, true)
		_gr(C2, items, "st_warazuka", 380.9, -15.2, W, mw, 0.8)
		var mu := m.duplicate()
		mu.merge({"who": "籾を搗く小作", "why": "臼と背負い籠（籾摺りの途中）"}, true)
		_gr(C2, items, "hu_momiboshi", 377.9, -26.6, W.rotated(0.1), mu, 0.5)
		_gr(C2, items, "wk_usu", 379.6, -24.8, W.rotated(0.6), mu, 0.5)
		_gr(C2, items, "hu_seoikago", 378.6, -23.7, W.rotated(-0.9), mu, 0.5)
		_gr(C2, items, "st_kuwa", 380.8, -27.2, W.rotated(1.4), mu, 0.6)})
	D.append({"id": "A8_wall_foot", "zone": "A8", "desc": "大宅の西塀の足元の植え込み：躑躅・低木・笹・羊歯の不揃いな群れと若木 2（白い塀だけの長い面に緑の過渡）", "center": Vector2(382.4, -20.0), "run": func(C2: Dictionary, items: Array, meta: Dictionary) -> void:
		var m := meta.duplicate()
		m.merge({"who": "大宅の庭師", "why": "塀の外の足元に植えた躑躅と、自然に生えた笹・羊歯（塀の白い面を和らげる）"}, true)
		_plant(C2, items, "young_broad_a", 382.4, -28.2, 1.25, m, 1.2)
		P3._clump(C2, items, Vector2(382.6, -30.6), 4, ["tsutsuji_a", "shrub_a", "fern_a"], 0.9, 1.3, 1.0, 81, m, 0.5)
		P3._clump(C2, items, Vector2(382.7, -25.2), 3, ["sasa_a", "fern_a", "tsutsuji_a"], 0.85, 1.2, 0.9, 82, m, 0.5)
		P3._clump(C2, items, Vector2(382.8, -17.4), 3, ["tsutsuji_a", "tsutsuji_a", "shrub_a"], 0.9, 1.25, 1.0, 83, m, 0.5)
		_plant(C2, items, "young_broad_b", 382.3, -12.6, 1.15, m, 1.2)
		P3._clump(C2, items, Vector2(382.6, -14.4), 4, ["shrub_a", "sasa_a", "fern_a", "tsutsuji_a"], 0.85, 1.3, 1.1, 84, m, 0.5)
		_plant(C2, items, "w9_hana_pink", 381.2, -26.8, 1.0, m, 0.5)
		_plant(C2, items, "w9_hana_shiro", 381.4, -13.9, 1.0, m, 0.5)})
	D.append({"id": "A8_north_grove", "zone": "A8", "desc": "中橫街の終点の北（田と大宅の間の空き地）：屋敷林の縁の雑木（高木 3・中木 1）と低木・笹・羊歯・野の花の不規則な林縁", "center": Vector2(375.5, -46.5), "run": func(C2: Dictionary, items: Array, meta: Dictionary) -> void:
		var m := meta.duplicate()
		m.merge({"who": "大宅の屋敷林", "why": "道の終わりに見える屋敷林の縁（田と塀の間の空き地を林の縁にする）"}, true)
		# r2：辻から南を向く TPS（PA2）の相機は道の北 ≈(371.7, 4.4, −44.3) に来て、r1 の若木（369.8, −43.6）の葉の中に入った（審圖）。
		#   相機の届く z −41..−47 の帯には低い物（≤ 1.4 m）だけを残し、高木と若木は z ≤ −49.5 か、相機から 6 m 以上東へ移す
		_plant(C2, items, "konara_a", 372.0, -50.8, 0.60, m, 1.2)
		_plant(C2, items, "enoki_a", 379.4, -45.4, 0.64, m, 2.0)
		_plant(C2, items, "akamatsu_a", 378.6, -51.0, 0.50, m, 1.2)
		_plant(C2, items, "young_broad_b", 368.6, -50.2, 1.20, m, 1.2)
		P3._clump(C2, items, Vector2(374.6, -43.6), 5, ["shrub_a", "sasa_a", "fern_a", "fern_a"], 0.8, 1.15, 1.5, 85, m, 0.6)
		P3._clump(C2, items, Vector2(380.8, -42.6), 4, ["sasa_a", "fern_a", "shrub_a"], 0.9, 1.3, 1.2, 86, m, 0.6)
		P3._clump(C2, items, Vector2(377.8, -48.8), 4, ["fern_a", "sasa_a", "fern_a"], 0.9, 1.25, 1.4, 87, m, 0.6)
		# r2：中層（躑躅・低木）は相機の帯（z −41..−47）の外の林の奥に
		_plant(C2, items, "tsutsuji_a", 380.8, -49.4, 1.15, m, 1.0)
		_plant(C2, items, "shrub_a", 374.4, -49.0, 1.2, m, 1.0)
		_plant(C2, items, "w9_hana_kiiro", 371.6, -42.6, 1.0, m, 0.6)
		_plant(C2, items, "w9_hana_shiro", 377.2, -42.2, 1.1, m, 0.6)
		_plant(C2, items, "w9_hana_higanbana", 382.0, -44.6, 1.0, m, 0.6)})
	return D


# ─────────────────────────── B8：東北聚落 ───────────────────────────

static func design_B8(C: Dictionary) -> Array:
	var D: Array = []
	var names: Array = B_HOUSES.keys()
	names.sort()
	for nm: String in names:
		var b := W9.bld(C, nm)
		if b.is_empty():
			continue
		var feats: Array = B_HOUSES[nm]
		var who: Array = []
		for f: Array in feats:
			who.append("暖簾" if String(f[0]).begins_with("noren_") else String(W9.FEAT[f[0]]["who"]))
		D.append({"id": "BH_" + nm.trim_prefix("B_P_"), "zone": "B8", "desc": "%s（%s・幅 %.1f m）の門前：%s" % [nm, b["type"], b["w"], " ・ ".join(PackedStringArray(who))],
			"center": b["o"], "run": W9._house_runner(b, feats)})
	# 宅間（NELane／NESouth）：幅の大きい順に最大 B_GAP_MAX 個、key の辞書順で recipe を割り当てる
	var gs: Array = []
	for road in ["NELane", "NESouth", "NENorth"]:
		for g: Dictionary in W9.gaps(C, road):
			# r1：001|002 は東北巷の曲がり角をまたいだ 13.6 m の『宅間』（実際は巷の分かれ目）で、垣と若木が路面の縁に乗った → 9 m 超は宅間として扱わない
			if float(g["w"]) >= 1.6 and float(g["w"]) <= 9.0:
				gs.append(g)
	gs.sort_custom(func(p: Dictionary, q: Dictionary) -> bool: return float(p["w"]) > float(q["w"]))
	gs = gs.slice(0, B_GAP_MAX)
	gs.sort_custom(func(p: Dictionary, q: Dictionary) -> bool: return "%s|%s" % [p["a"], p["b"]] < "%s|%s" % [q["a"], q["b"]])
	var si := 0
	for g: Dictionary in gs:
		var spec: Array = (B_GAP_RECIPES[si % B_GAP_RECIPES.size()] as Array).duplicate(true)
		if float(g["w"]) < 2.3 and not (String(spec[0]) in ["open", "shrine"]):
			spec = ["open", {}] if si % 2 == 0 else ["shrine", {"id": "w9_jizo"}]
		si += 1
		# r1：宅間の口の屋根付き木戸（高 2.7 m）が巷の SpringArm を重く縮めた（005|004：25 件）→ Phase 4 と同じ規則で木戸だけを宅間の奥へ（垣の切れ目＝庭の出入口）
		if String(spec[0]) in ["yard", "fence_gate"]:
			(spec[1] as Dictionary).merge({"setback": KIDO_SETBACK, "setback_only": "w9_kido"}, true)
		D.append({"id": "BG_" + String(g["a"]).trim_prefix("B_P_") + "_" + String(g["b"]).trim_prefix("B_P_RNE_"), "zone": "B8",
			"desc": "東北聚落の宅間 %s|%s（幅 %.1f m）：%s" % [g["a"], g["b"], g["w"], spec[0]], "center": g["front"], "run": P4L._gap_runner_p4(g, spec, 60 + si)})
	# r2：r1 は巷の分かれ目（東北南巷の軸から 2.4 m）に置き、井戸の碰撞（高 2.5 m）が SpringArm の重い縮み 116 件を作った → 巷の西の空き地（軸から約 6 m）へ
	D.append({"id": "B8_well", "zone": "B8", "desc": "東北聚落の共同井戸（香霖堂口の北・東北巷の西の空き地）：井戸と手桶・水甕・井戸端の草", "center": Vector2(428.6, -217.4), "run": func(C2: Dictionary, items: Array, meta: Dictionary) -> void:
		var m := meta.duplicate()
		m.merge({"who": "東北聚落の家々", "why": "巷の脇の共同井戸（水汲みと洗い物の場＝集落の中心。橋と香霖堂口から見える）", "kind": "reuse"}, true)
		var it := _gr(C2, items, "st_ido", 428.6, -217.4, Vector2(0.62, 0.78), m, 1.5)
		if it.is_empty():
			return
		var p: Vector2 = it["p"]
		_gr(C2, items, "sk_teoke", p.x + 1.6, p.y + 0.4, Vector2(0.3, 1.0), m, 0.6)
		_gr(C2, items, "mk_kame", p.x - 1.7, p.y - 0.3, Vector2(-1.0, 0.2), m, 0.6)
		var mf := m.duplicate()
		mf.merge({"who": "井戸端", "why": "井戸の周りの湿った足元の羊歯と野の花"}, true)
		_plant(C2, items, "fern_a", p.x + 0.4, p.y - 1.8, 0.9, mf, 0.5)
		_plant(C2, items, "w9_hana_shiro", p.x - 1.2, p.y + 1.5, 1.0, mf, 0.5)})
	D.append({"id": "B8_canopy", "zone": "B8", "desc": "屋根並みの背後の樹冠：龍神橋から見える集落の背景に高さの違う緑（同じ Kit の屋根の連続を破る）", "center": Vector2(470.0, -214.0), "run": func(C2: Dictionary, items: Array, meta: Dictionary) -> void:
		var m := meta.duplicate()
		m.merge({"who": "東北聚落の家々", "why": "家々の裏の庭木と屋敷林（橋の上から見る集落の背景）"}, true)
		_plant(C2, items, "konara_a", 478.0, -218.0, 0.62, m, 3.0)
		_plant(C2, items, "enoki_a", 492.0, -212.0, 0.70, m, 3.0)
		_plant(C2, items, "young_broad_a", 462.5, -217.0, 1.30, m, 2.0)
		_plant(C2, items, "kuromatsu_a", 436.0, -196.0, 0.70, m, 2.5)
		# r2：審圖『幹の長い赤松が一本だけ浮く』→ 樹冠の大きい小楢に。橋から見える集落の西の縁（井戸の奥）に高木 2 を足して屋根並みの背景を作る
		_plant(C2, items, "konara_b", 446.0, -194.0, 0.85, m, 2.5)
		_plant(C2, items, "enoki_a", 425.6, -223.0, 0.70, m, 2.5)
		_plant(C2, items, "konara_b", 432.4, -228.6, 0.80, m, 2.5)
		P3._clump(C2, items, Vector2(427.4, -226.0), 4, ["sasa_a", "fern_a", "shrub_a"], 0.9, 1.3, 1.5, 90, m, 0.6)
		P3._clump(C2, items, Vector2(439.0, -193.5), 5, ["shrub_a", "sasa_a", "fern_a", "tsutsuji_a"], 0.85, 1.3, 1.6, 88, m, 0.6)
		P3._clump(C2, items, Vector2(482.0, -221.5), 4, ["sasa_a", "fern_a", "shrub_a"], 0.9, 1.3, 1.4, 89, m, 0.6)})
	return D


# ─────────────────────────── 計画・烘焙 ───────────────────────────

static func plan(v: Node3D, meadow_pts: PackedVector2Array, zones: Array = ["A8", "B8"]) -> Dictionary:
	P3.register_dims()
	var C := W9.context(v, meadow_pts)
	var n_occ := 0
	# W9 R1／Phase 3／4 の構件（根元の地面物）も占有として扱う
	for ov_name in ["EnrichW9P13", "EnrichW9P3", "EnrichW9P4"]:
		var ov := v.get_node_or_null(ov_name)
		if ov == null:
			continue
		for mi in ov.find_children("*", "MeshInstance3D", true, false):
			var g := mi as MeshInstance3D
			if g.mesh == null or g.visibility_range_begin > 0.001:
				continue
			var r: Rect2 = HU._rect_of(g, v)
			if r.size.x > 12.0 or r.size.y > 12.0:
				continue
			(C["rootp_g"] as HU.Grid).add(r.grow(0.15), r.grow(0.15))
			n_occ += 1
	C["n_r1"] = n_occ
	var items: Array = []
	var clusters: Array = []
	var des: Array = []
	for z: String in zones:
		match z:
			"A8":
				des.append_array(design_A8(C))
			"B8":
				des.append_array(design_B8(C))
	for cl: Dictionary in des:
		var n0 := items.size()
		var cl2 := cl.duplicate()
		cl2["zone"] = ZONE_OF[String(cl["zone"])]
		var meta := W9._cl_meta(cl2)
		(cl["run"] as Callable).call(C, items, meta)
		var got: Array = items.slice(n0)
		clusters.append({"id": String(cl["id"]), "zone": String(cl2["zone"]), "desc": String(cl["desc"]), "center": cl["center"], "n": got.size()})
	return {"C": C, "items": items, "clusters": clusters}


## P3.bake を使い、名前・区域だけ Phase 8 に差し替える（壁に吊る物は建物名 b を覚えさせる＝Phase 4 と同じ）
static func bake(P: Dictionary) -> Node3D:
	var rn := P3.bake(P)
	rn.name = NODE_NAME
	var back := {}
	for k: String in ZONE_OF:
		back[ZONE_OF[k]] = k
	var its: Array = P["items"]
	for zn in rn.get_children():
		for cn in zn.get_children():
			for nd in cn.get_children():
				if nd is Node3D and nd.has_meta("w9_id"):
					var ix := int(String(nd.name).split("_")[0])
					if ix >= 0 and ix < its.size():
						var bb := String((its[ix] as Dictionary).get("b", ""))
						if bb != "":
							nd.set_meta("w9_b", bb)
					var zz := String(nd.get_meta("w9_zone", ""))
					if back.has(zz):
						nd.set_meta("w9_zone", back[zz])
	rn.set_meta("art_revision", ART_REVISION)
	for z: String in ZONE_OF:
		var zn := rn.get_node_or_null("Zone" + String(ZONE_OF[z])) as Node3D
		if zn != null:
			zn.set_meta("zone", ZONE_NAME[z])
			zn.name = "Zone" + z
	return rn

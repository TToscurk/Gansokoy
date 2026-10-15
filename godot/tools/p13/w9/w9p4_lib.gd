extends RefCounted
## 人間之里 V2 P13 W9 Phase 4（使用者 2026-10-15「正常 TPS で一目で分かる場景差異」）の環境生成器（source of truth）。
##   B4 西巷（WestAlley）：宅間の板塀・木戸・下屋・祠・干し柿、各戸の暮らしの痕跡（植木棚・簾・薪・籠…）、棟の背後の樹冠。
##       対象の棟は build_w9p4_arch.py の 024／025／026／012（量体を作り替えた 4 棟）＋ 改造しない 7 戸（FEAT）。
##   C4 中橫街（CrossStreetMid）東寄りの『裏の空き地』2 か所：高木 2＋中木の群れ＋灌木・羊歯・笹・野の花（密度の違う二つの空き地）。
## overlay `EnrichW9P4`（root 直下・EnrichW9P3 の次）→ gen/enrich_w9p4.scn。ビルド／掛載：tools/p13/w9/build_w9p4.gd。
## 方針：W9 R1／Phase 3 の plan／why（道・建物・戸口・水・田・封存物・NPC 動線への不侵入）をそのまま使う。新規の資産は無し（承認済み Kit の再配置のみ）。
const P3 := preload("res://tools/p13/w9/w9p3_lib.gd")
const W9 := preload("res://tools/p13/w9/w9_lib.gd")
const HU := preload("res://tools/village_v2_human_use_lib.gd")

const NODE_NAME := "EnrichW9P4"
const OUTPUT := "res://maps/village_v2/gen/enrich_w9p4.scn"
const SCENE := "res://maps/village_v2/village_v2.tscn"
const AFTER := "EnrichW9P3"
const ART_REVISION := "P13 W9 Phase 4 R1（ART_REVIEW）：B 西巷の生活痕跡・庭木、C 中橫街の裏の空き地"
const ZONE_NAME := {"B3": "西巷 WestAlley（宅間・戸口・庭木）", "C3": "中橫街 CrossStreetMid（裏の空き地の植栽）"}

## 西巷の宅間（key＝"a|b"＝gaps() の a|b。逆順でも引く）。西列：018→009（北へ）、東列：019→026。量体を作り替えた 024｜025｜026｜012 の周りを中心に。
const A_GAPS := {
	"B_P_RSW_024|B_P_RSW_025": ["yard", {"gate": 0.45}],                          # 名主の家の脇の庭：板塀・木戸・植木棚・朝顔・庭木
	"B_P_RSW_025|B_P_RSW_026": ["shed_wood", {"wall": "a"}],                      # 板葺きの家の薪の下屋（025 の側壁に掛ける）
	"B_P_RSW_016|B_P_RSW_015": ["open", {}],                                      # 低い四つ目垣と野の花
	"B_P_RSW_015|B_P_RSW_014": ["fence", {"id": "w9_takegaki"}],                  # 竹垣
	"B_P_RSW_014|B_P_RSW_013": ["yard", {"gate": 0.55, "kaki": true}],            # 干し柿の庭
	"B_P_RSW_013|B_P_RSW_012": ["shed_tool", {"wall": "c"}],                      # 農家の農具の下屋（012 の側壁）
	"B_P_RSW_012|B_P_RSW_011": ["shrine", {"id": "w9_jizo"}],                     # 辻の地蔵
	"B_P_RSW_011|B_P_RSW_010": ["fence_gate", {"gate": 0.5, "id": "w9_takegaki"}],
}
## 各戸の暮らし（改造しない戸＋改造した戸。改造した戸は、戸口の位置を Kit と同じにしてあるので同じ仕組みで置ける）：[feat, side, nth]
const A_HOUSES := {
	"B_P_RSW_010": [["kaki", -1, 0], ["ueki", 1, 0]],
	"B_P_RSW_011": [["asagao", 1, 0], ["wood", -1, 0]],
	"B_P_RSW_013": [["noren_ai", 0, 0], ["sudare", -1, 0]],
	"B_P_RSW_015": [["toga", 1, 0], ["hachi", -1, 0]],
	"B_P_RSW_016": [["kago", 1, 0], ["sudare", -1, 0]],
	"B_P_RSW_022": [["tools", -1, 0], ["kaki", 1, 0]],
	"B_P_RSW_023": [["ueki", -1, 0], ["kame", 1, 0]],
	"B_P_RSW_025": [["wood", -1, 0], ["kago", 1, 0]],
	"B_P_RSW_026": [["ueki", -1, 0], ["hachi", 1, 0]],
	"B_P_RSW_012": [["tools", -1, 0]],                                         # 農家：戸口の左の窓壁に農具（吊柿は新しい軒先と重なるので掛けない・縁側は戸口の右）
}


static func _plant(C: Dictionary, items: Array, id: String, x: float, z: float, s: float, meta: Dictionary, rmax := 1.5) -> Dictionary:
	return P3._plant(C, items, id, x, z, s, meta, rmax)


static func design_B4(C: Dictionary) -> Array:
	var D: Array = []
	# 1) 宅間
	var si := 0
	for g: Dictionary in W9.gaps(C, "WestAlley"):
		var key := "%s|%s" % [g["a"], g["b"]]
		var swap := false
		if not A_GAPS.has(key):
			key = "%s|%s" % [g["b"], g["a"]]
			swap = true
		if not A_GAPS.has(key):
			continue
		si += 1
		var spec: Array = (A_GAPS[key] as Array).duplicate(true)
		if swap and (spec[1] as Dictionary).has("wall"):
			(spec[1] as Dictionary)["wall"] = "c" if String((spec[1] as Dictionary)["wall"]) == "a" else "a"
		D.append({"id": "AG_" + String(g["a"]).trim_prefix("B_P_") + "_" + String(g["b"]).trim_prefix("B_P_RSW_"), "zone": "B3",
			"desc": "西巷の宅間 %s（幅 %.1f m）：%s" % [key, g["w"], spec[0]], "center": g["front"], "run": W9._gap_runner(g, spec, 40 + si)})
	# 2) 各戸の暮らし
	var names: Array = A_HOUSES.keys()
	names.sort()
	for nm: String in names:
		var b := W9.bld(C, nm)
		if b.is_empty():
			continue
		var feats: Array = A_HOUSES[nm]
		var who: Array = []
		for f: Array in feats:
			who.append("暖簾" if String(f[0]).begins_with("noren_") else String(W9.FEAT[f[0]]["who"]))
		D.append({"id": "AH_" + nm.trim_prefix("B_P_"), "zone": "B3", "desc": "%s（%s・幅 %.1f m）の門前：%s" % [nm, b["type"], b["w"], " ・ ".join(PackedStringArray(who))],
			"center": b["o"], "run": W9._house_runner(b, feats)})
	# 3) 棟の背後の樹冠（巷から見上げた屋根の上の緑と高さの変化。東列は 024–026 の裏、西列は 011–013 の裏）
	D.append({"id": "AB_back_east", "zone": "B3", "desc": "東列（024–026）の背後の樹冠：入母屋・低い板葺き・細長い妻入の屋根の上に、高さの違う緑が重なる", "center": Vector2(221.5, -66.0), "run": func(C2: Dictionary, items: Array, meta: Dictionary) -> void:
		var m := meta.duplicate()
		m.merge({"who": "宅地を持つ家々", "why": "東列の家々の裏手に残された庭木（屋根の背後に樹冠が重なり、一続きの屋根並みにならない）"}, true)
		_plant(C2, items, "konara_a", 222.0, -76.5, 0.64, m, 3.0)
		_plant(C2, items, "young_broad_b", 223.5, -66.5, 1.35, m, 2.5)
		_plant(C2, items, "kuromatsu_a", 222.0, -57.5, 0.70, m, 3.0)})
	D.append({"id": "AB_back_west", "zone": "B3", "desc": "西列（011–013）の背後の樹冠：越屋根の寄棟の農家の屋根の上に枝が重なる", "center": Vector2(184.0, -60.0), "run": func(C2: Dictionary, items: Array, meta: Dictionary) -> void:
		var m := meta.duplicate()
		m.merge({"who": "宅地を持つ家々", "why": "西列の家々の裏手の庭木（農家の屋根の背景を緑にする）"}, true)
		_plant(C2, items, "enoki_a", 184.5, -71.5, 0.70, m, 3.0)
		_plant(C2, items, "konara_b", 183.5, -60.5, 0.85, m, 3.0)
		_plant(C2, items, "akamatsu_a", 184.0, -48.5, 0.50, m, 3.0)
		_plant(C2, items, "young_broad_a", 186.0, -38.5, 1.30, m, 2.5)})
	# 4) 名主の家（024）の戸口の脇：袖垣（巷側の前庭帯は樹木を置けない＝庭木は宅間の庭に任せる。W9 の frontage 規則）
	D.append({"id": "AB_024_garden", "zone": "B3", "desc": "名主の家（024）の戸口の脇：袖垣（家格の目印。唐破風の玄関を隠さない）", "center": Vector2(209.2, -77.5), "run": func(C2: Dictionary, items: Array, meta: Dictionary) -> void:
		var m := meta.duplicate()
		m.merge({"who": "名主の家", "why": "玄関の脇の袖垣（家格の目印。巷の側は開けて、戸口の唐破風を見せる）"}, true)
		var b := W9.bld(C2, "B_P_RSW_024")
		if b.is_empty():
			return
		var az: Vector2 = b["az"]
		var mm := m.duplicate()
		mm.merge({"mode": "ground", "meadow_ok": true, "relief_max": 0.45, "kind": "reuse", "on_frontage": true}, true)
		var p4: Vector2 = W9.bw(b, 4.0, float(b["d"]) * 0.5 + 0.45)
		W9.place(C2, items, "gk_sodegaki", p4, az, mm, "ground", 0.4)})
	return D


## C4：中橫街の裏の空き地 2 か所（密度も構えも変える）
static func design_C4(_C: Dictionary) -> Array:
	var D: Array = []
	D.append({"id": "C4_pocket_N", "zone": "C3", "desc": "中橫街の北の裏の空き地（主街の東の列 011–013 の裏と 040 の脇）：高木 2＋中木の群れ＋灌木・羊歯・笹・野の花の不規則な林縁", "center": Vector2(288.5, -37.5), "run": func(C2: Dictionary, items: Array, meta: Dictionary) -> void:
		var m := meta.duplicate()
		m.merge({"who": "裏の空き地を持つ家々", "why": "表通りの裏に残った空き地の木と草（家々の裏口の外。道端の壁の足元を受ける緑）"}, true)
		_plant(C2, items, "konara_a", 288.6, -41.0, 0.62, m, 2.5)
		_plant(C2, items, "enoki_a", 291.6, -34.2, 0.66, m, 2.5)
		_plant(C2, items, "young_broad_a", 285.4, -37.0, 1.30, m, 1.8)
		_plant(C2, items, "young_broad_b", 291.3, -40.8, 1.15, m, 1.8)
		P3._clump(C2, items, Vector2(286.4, -32.6), 6, ["tsutsuji_a", "shrub_a", "tsutsuji_a", "fern_a"], 0.9, 1.35, 1.5, 21, m, 0.5)
		P3._clump(C2, items, Vector2(291.8, -31.4), 5, ["shrub_a", "sasa_a", "fern_a", "shrub_a"], 0.95, 1.4, 1.3, 22, m, 0.5)
		P3._clump(C2, items, Vector2(288.0, -43.2), 6, ["sasa_a", "fern_a", "sasa_a", "young_broad_a"], 0.9, 1.3, 1.6, 23, m, 0.6)
		_plant(C2, items, "w9_hana_shiro", 287.2, -34.6, 1.0, m, 0.6)
		_plant(C2, items, "w9_hana_kiiro", 289.6, -33.2, 1.1, m, 0.6)
		_plant(C2, items, "w9_hana_pink", 286.0, -39.8, 1.0, m, 0.6)
		_plant(C2, items, "w9_hana_shiro", 292.2, -37.4, 0.9, m, 0.6)})
	D.append({"id": "C4_pocket_S", "zone": "C3", "desc": "中橫街の南の角の空き地（主街の東の列 009–010 と 035 の間）：中木 1＋躑躅の低い縁＋羊歯と野の花（北の空き地より小さく、低く、手入れされた縁）", "center": Vector2(274.5, -12.5), "run": func(C2: Dictionary, items: Array, meta: Dictionary) -> void:
		var m := meta.duplicate()
		m.merge({"who": "角の家々", "why": "角地の空き地に残された庭木と植え込み（道の角を柔らかくする）"}, true)
		_plant(C2, items, "young_broad_b", 274.8, -12.2, 1.30, m, 1.8)
		_plant(C2, items, "kuromatsu_a", 277.2, -9.6, 0.72, m, 2.2)
		P3._row(C2, items, ["tsutsuji_a", "shrub_a", "tsutsuji_a"], Vector2(271.2, -16.6), Vector2(277.4, -16.2), 1.4, 0.9, 1.25, 31, m, [[0.55, 0.7]], 0.18, 0.5)
		P3._clump(C2, items, Vector2(275.4, -14.6), 4, ["fern_a", "sasa_a", "fern_a"], 0.9, 1.25, 1.1, 32, m, 0.5)
		_plant(C2, items, "w9_hana_kiiro", 273.2, -15.0, 1.0, m, 0.5)
		_plant(C2, items, "w9_hana_shiro", 277.4, -13.4, 1.1, m, 0.5)})
	return D


# ─────────────────────────── 計画・烘焙 ───────────────────────────

static func plan(v: Node3D, meadow_pts: PackedVector2Array, zones: Array = ["B4", "C4"]) -> Dictionary:
	P3.register_dims()
	var C := W9.context(v, meadow_pts)
	var n_occ := 0
	# W9 R1／Phase 3 の構件（根元の地面物）も占有として扱う
	for ov_name in ["EnrichW9P13", "EnrichW9P3"]:
		var ov := v.get_node_or_null(ov_name)
		if ov == null:
			continue
		for mi in ov.find_children("*", "MeshInstance3D", true, false):
			var g := mi as MeshInstance3D
			if g.mesh == null or g.visibility_range_begin > 0.001:
				continue
			var pn := String(g.get_parent().name)
			var is_plant_item := false
			for pk in ["w9_hana", "shrub_a", "fern_a", "sasa_a", "young_broad", "niwamatsu", "young_sugi"]:
				if pn.contains(pk):
					is_plant_item = true
			if is_plant_item:
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
			"B4":
				des.append_array(design_B4(C))
			"C4":
				des.append_array(design_C4(C))
	for cl: Dictionary in des:
		var n0 := items.size()
		var meta := W9._cl_meta(cl)
		(cl["run"] as Callable).call(C, items, meta)
		var got: Array = items.slice(n0)
		clusters.append({"id": String(cl["id"]), "zone": String(cl["zone"]), "desc": String(cl["desc"]), "center": cl["center"], "n": got.size()})
	return {"C": C, "items": items, "clusters": clusters}


## P3.bake を使い、名前と説明だけ Phase 4 に差し替える
static func bake(P: Dictionary) -> Node3D:
	var rn := P3.bake(P)
	rn.name = NODE_NAME
	# 壁・軒に吊る物（吊柿・簾・暖簾）は b（建物名）を覚えさせる：gate が『その家の床からの高さ』で検査できるように（P3.bake は b を空にする）
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
	rn.set_meta("art_revision", ART_REVISION)
	for z: String in ZONE_NAME:
		var zn := rn.get_node_or_null("Zone" + z) as Node3D
		if zn != null:
			zn.set_meta("zone", ZONE_NAME[z])
			zn.name = "Zone" + ("B4" if z == "B3" else "C4")
	return rn

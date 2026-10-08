## 人間之里 V2 P10 R4b Human-Use Expansion Batch 1（HumanUseExpansionP10＝village_v2 の root 直下、HumanUseP10 の次）。
##   R4 Pilot（封存）の語彙と規則を、まだ生活痕跡のない農田・普通住宅・水岸へ広げる。NPC を消しても「居民が普段何をしているか」読めること。
##   全村を平均に埋めない：農田＝生產と運搬の動線、住宅＝各戶の暮らしの違い、水岸＝水源の用途。核心商業區（市集・主街・市集西）には置かない。
##   封存 R4（village_v2_human_use_lib.gd）の context／why／frame を只讀で使い、追加の禁區を足す：
##     R4 の 50 件（+0.5 m）と R4 Pilot の矩形（+3 m：もう配置した場所）・核心商業區（市場中心 r 45 m＋P10 構件から 4 m）・水面・P7・P8・NPC…（R4 と同じ）。
##   高さ＝見えている最上面（地形・路面・P4 院子・P8 の田・封存 overlay の地面 decal〔Groundcover／Waterside …〕の max）を足元で取り、その最低点に置く。
##   使用者裁定（2026-10-08）：A 農田 5 群・B 住宅 5 群＝ART_APPROVED（A/B FINAL）、C 水岸 3 群＝ART_REJECTED → rejected_c() に記録だけ残し正式出力から除去。
##   R4 Pilot C（封存の水岸）は不変。C の代わりの高い輪郭の道具は足さない（自然の岸を余白として残す）。
const HU := preload("res://tools/village_v2_human_use_lib.gd")
const SL := preload("res://tools/village_v2_street_lib.gd")
const RLib := preload("res://tools/village_v2_riverbank_lib.gd")
const OUTPUT := "res://maps/village_v2/gen/human_use_exp_p10.scn"
const NODE_NAME := "HumanUseExpansionP10"
const AFTER := "HumanUseP10"
const LOD_SWITCH := 34.0
const ART_REVISION := "P10 R4b Human-Use Expansion Batch 1 A/B FINAL（A 農田・B 住宅 ART_APPROVED、C 水岸 ART_REJECTED＝除去）"
const NEW_KIT := "humanuse_exp_kit"
const NEW_PREFIX := "hx_"
const NEW_IDS := ["hx_hatake", "hx_daikon_kake"]
## 缺件として作ったが ART_REJECTED の C 群（XC3 泥上げ）専用だった物：kit に rejected candidate として残し、正式配置では使わない
const REJECTED_NEW_IDS := ["hx_doroage"]
const REJECTED_CLUSTERS := ["XC1_araimono", "XC2_hashi", "XC3_suiro"]
const REJECTED_REASON := "Three iterations failed to establish readable waterside activities. Existing R4 Pilot C already provides sufficient waterside human-use evidence. Additional expansion was removed to preserve natural negative space."
## 正式の Batch 1＝A 農田 5・B 住宅 5・C 水岸擴張 0、計 10 群（使用者 2026-10-08 裁定）
const OFFICIAL_ZONES := {"A": 5, "B": 5, "C": 0}
const OFFICIAL_CLUSTERS := 10
## R4b で使ってよい Hero kit の汎用品（kiri／suzu／mise は中身が店・Hero 固有の物が多いので許可制）
const ALLOW := {"kr_": ["kr_houki", "kr_nawa", "kr_zaimoku", "kr_kuruma", "kr_okeyama", "kr_hakozumi", "kr_ni", "kr_fukuro"],
	"sz_": ["sz_stool", "sz_hachi"], "ms_": ["ms_nuno_kake"]}
## kr_fukuro（麻袋）は汎用の袋として土嚢に使う
const ANCHOR_TYPES := ["building", "work_surface", "water", "field", "route", "storage", "bridge"]
const CORE_CENTER := Vector2(245.0, -40.0)
const CORE_R := 45.0
const P10_COMMERCE_PAD := 4.0
const R4_PAD := 0.5
const R4_ZONE_PAD := 3.0
const GROUP_R := 9.0
const ZONE_NAME := {"A": "農田と農道", "B": "普通住宅"}
const REJECTED_ZONE_NAME := {"C": "水岸と水渠（ART_REJECTED）"}


static func dims_table() -> Dictionary:
	var d := HU.dims_table()
	var f := "res://assets/village_v2/%s/src/modules_blender.json" % NEW_KIT
	if FileAccess.file_exists(f):
		var j: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(f))
		for n: String in j["modules"]:
			if not n.ends_with("_l1"):
				d[n] = j["modules"][n]["dims"]
	return d


static func mesh_dir(id: String) -> String:
	if id.begins_with(NEW_PREFIX):
		return "res://assets/village_v2/%s/mesh/" % NEW_KIT
	return HU.mesh_dir(id)


## 見えている最上面：R4 の top_h（地形・路面・P4 院子・P8）＋封存 overlay の地面 decal
static func top_h(C: Dictionary, p: Vector2) -> float:
	var h := HU.top_h(C, p)
	var g := (C["GD"] as RLib.TriSampler).h(p.x, p.y)
	if not is_nan(g):
		h = maxf(h, g)
	return h


static func context(v: Node3D, meadow_pts: PackedVector2Array) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var C := HU.context(v, meadow_pts)
	C["D"] = dims_table()
	# 封存 overlay の地面 decal（Ground* の LOD0）→ 見えている最上面
	var GD := RLib.TriSampler.new()
	var n_gd := 0
	var veg := v.get_node_or_null("Vegetation")
	if veg:
		for mi in veg.find_children("Ground*", "MeshInstance3D", true, false):
			var g := mi as MeshInstance3D
			if g.mesh != null and g.visibility_range_begin <= 0.001 and g.is_visible_in_tree():
				GD.add(g.mesh.get_faces(), RLib.rel_xf(g, v))
				n_gd += 1
		for gp in veg.find_children("Ground", "Node3D", true, false):
			for mi in gp.find_children("*", "MeshInstance3D", true, false):
				var g := mi as MeshInstance3D
				if g.mesh != null and g.visibility_range_begin <= 0.001 and g.is_visible_in_tree():
					GD.add(g.mesh.get_faces(), RLib.rel_xf(g, v))
					n_gd += 1
	C["GD"] = GD
	C["n_ground_decal"] = n_gd
	# R4 封存の 50 件（+0.5 m）と R4 Pilot の矩形（+3 m）
	var RG := HU.Grid.new()
	var hu := v.get_node_or_null(HU.NODE_NAME)
	var n_r4 := 0
	if hu:
		for mi in hu.find_children("LOD0", "MeshInstance3D", true, false):
			var a := RLib.rel_xf(mi, v) * (mi as MeshInstance3D).get_aabb()
			var r := Rect2(a.position.x, a.position.z, a.size.x, a.size.z).grow(R4_PAD)
			RG.add(r, r)
			n_r4 += 1
	C["r4_g"] = RG
	C["n_r4"] = n_r4
	var zones: Array = []
	for k: String in HU.PILOTS:
		zones.append((HU.PILOTS[k] as Rect2).grow(R4_ZONE_PAD))
	C["r4_zones"] = zones
	# 核心商業區：P10 の市集・主街・市集西の構件（LOD0）から 4 m
	var CG := HU.Grid.new()
	CG.cs = 4.0
	var pr := v.get_node_or_null("Props")
	if pr:
		for nm in ["MarketP10", "StreetP10", "MarketWestP10"]:
			var ov := pr.get_node_or_null(nm)
			if ov == null:
				continue
			for mi in ov.find_children("*", "MeshInstance3D", true, false):
				var g := mi as MeshInstance3D
				if g.mesh != null and g.visibility_range_begin <= 0.001:
					var a := RLib.rel_xf(g, v) * g.get_aabb()
					var r := Rect2(a.position.x, a.position.z, a.size.x, a.size.z).grow(P10_COMMERCE_PAD)
					CG.add(r, r)
	C["commerce_g"] = CG
	C["exp_ms"] = Time.get_ticks_msec() - t0
	return C


static func _hit(G: HU.Grid, q: Vector2) -> bool:
	for r in G.at(q):
		if (r as Rect2).has_point(q):
			return true
	return false


## 置けない理由（"" なら置ける）：R4 の禁區（HU.why、scope は使わない）＋拡張の禁區
static func why(C: Dictionary, it: Dictionary, items: Array) -> String:
	var poly := HU.corners(C, it)
	if it.has("scope") and not (it["scope"] as Rect2).encloses(Rect2(poly[0], Vector2.ZERO).expand(poly[1]).expand(poly[2]).expand(poly[3])):
		return "scope"
	for q in HU.samples(poly, 0.3):
		if q.distance_to(CORE_CENTER) < CORE_R:
			return "core"
		if _hit(C["commerce_g"], q):
			return "commerce"
		if _hit(C["r4_g"], q):
			return "r4"
		for z: Rect2 in C["r4_zones"]:
			if z.has_point(q):
				return "r4zone"
	return HU.why(C, it, items, false)


static func relief(C: Dictionary, it: Dictionary) -> float:
	var hs: Array = [top_h(C, it["p"])]
	for q in HU.corners(C, it):
		hs.append(top_h(C, q))
	return float(hs.max()) - float(hs.min())


static func item(C: Dictionary, id: String, p: Vector2, face: Vector2, meta: Dictionary) -> Dictionary:
	var it := {"id": id, "p": p, "yaw": HU.yaw_to(face), "y": 0.0}
	it.merge(meta, true)
	var hs: Array = [top_h(C, p)]
	for q in HU.corners(C, it):
		hs.append(top_h(C, q))
	it["y"] = hs.min()
	return it


static func place(C: Dictionary, items: Array, id: String, c: Vector2, face: Vector2, meta: Dictionary, rmax := 1.25) -> Dictionary:
	var r := 0.0
	var last := ""
	while r <= rmax + 0.001:
		var n := 1 if r == 0.0 else 16
		for k in n:
			var a := TAU * k / 16.0
			var it := item(C, id, c + Vector2(cos(a), sin(a)) * r, face, meta)
			if relief(C, it) > HU.RELIEF_MAX:
				last = "slope"
				continue
			var w := why(C, it, items)
			if w != "":
				last = w
				continue
			items.append(it)
			return it
		r += 0.25
	(C["dropped"] as Array).append("%s near (%.1f,%.1f) 置けない（最後の理由 %s）[%s]" % [id, c.x, c.y, last, meta.get("cluster", "?")])
	return {}


## 設計（cluster）：R4 と同じ形式。frame＝{"p","face"} か {"bld"}。zone＝A／B／C。
## 正式の配置（A 農田 5・B 住宅 5）。C 水岸は rejected_c()。
static func design() -> Array:
	var D: Array = []
	# ── A 農田と農道（R4 の Pilot A＝Bridge_03 田側は除く）：生產と運搬の動線の節点にだけ置く
	D.append({"id": "XA1_shukka", "zone": "A", "anchor": "route", "ref": Vector2(433.0, 0.0),
		"desc": "FarmPath_2×FarmPath_4 の辻の南西：俵を荷車に積み込む途中の出荷場（台の俵・積みかけの車・車の脇の 3 俵）",
		"frame": {"p": Vector2(433.0, 5.0), "face": Vector2(0, -1)},
		"items": [
			["mk_kuruma_ni", Vector2(2.2, 0.2), 90.0, "この辻の田を持つ農家（大八車）", "俵を積みかけた大八車：辻から村の米屋・蔵へ出す"],
			["wk_tawara3", Vector2(0.65, -0.35), -10.0, "この辻の田を持つ農家", "車の後ろに下ろした次の 3 俵：これから積む"],
			["st_kome_tsumi", Vector2(-0.95, 0.75), 0.0, "この辻の田を持つ農家", "選った俵を台に積んで出荷を待つ（雨の日は菰を掛ける）"],
			["kr_nawa", Vector2(0.75, 1.4), 0.0, "この辻の田を持つ農家", "俵を車に縛る縄（積み終わったら掛ける）"],
		]})
	D.append({"id": "XA2_teire", "zone": "A", "anchor": "route", "ref": Vector2(379.0, 70.0),
		"desc": "FarmPath_1×FarmPath_5 の辻の北東：組の農具置き場と手入れの台——鍬・鋤を掛けた農具掛け 2 架を並べ、その前で柄を削って付け替える作業台",
		"frame": {"p": Vector2(379.5, 65.0), "face": Vector2(0, 1)},
		"items": [
			["st_kuwa", Vector2(-1.15, -0.55), 0.0, "南の田の組", "組で使う鍬・鋤を掛けておく農具掛け（田へ出る前にここで取る）"],
			["st_kuwa", Vector2(0.75, -0.6), 4.0, "南の田の組", "二架目の農具掛け：手入れの済んだ物を掛け戻す"],
			["st_daiku", Vector2(-0.1, 0.95), 0.0, "南の田の組（雨の合間の手入れ）", "馬 2 に板を渡した作業台：折れた鍬の柄を削って付け替える（鋸・墨壺・鉋屑）"],
			["kr_zaimoku", Vector2(2.35, 0.75), 80.0, "南の田の組", "替えの柄にする樫の材"],
			["sz_stool", Vector2(0.75, 1.95), 180.0, "南の田の組", "作業台の前の腰掛け"],
		]})
	D.append({"id": "XA3_hasa", "zone": "A", "anchor": "field", "ref": Vector2(482.0, -8.5),
		"desc": "FarmPath_4 の東、田の北縁：農道に沿った長い稲架の列（3 架）と、風よけの柴垣・藁塚",
		"frame": {"p": Vector2(482.0, -4.2), "face": Vector2(0, 1)},
		"items": [
			["st_hasa", Vector2(-3.75, 0.0), 0.0, "東の田の農家", "刈った稲を農道沿いの稲架に掛けて干す（列の東）"],
			["st_hasa", Vector2(0.0, 0.0), 0.0, "東の田の農家", "稲架の列の中ほど"],
			["st_hasa", Vector2(3.75, 0.0), 0.0, "東の田の農家", "稲架の列の西：一面の田の刈り稲で 3 架"],
			["st_shibagaki", Vector2(0.0, -1.45), 0.0, "東の田の農家", "稲架の田側に立てた柴垣：田から吹く風よけ"],
			["st_warazuka", Vector2(6.3, -0.5), 0.0, "東の田の農家", "去年の藁を積んだ藁塚（縄・草鞋・敷き藁に使う）"],
		]})
	D.append({"id": "XA4_oroshi", "zone": "A", "anchor": "route", "ref": Vector2(339.0, 42.0),
		"desc": "Bridge_04 の田側の橋詰め：村から引いてきた荷を降ろしたところ——空になった大八車と、その後ろに降ろした箱・俵・菰包みの山、田へ背負っていく籠",
		"frame": {"p": Vector2(339.0, 46.9), "face": Vector2(0, -1)},
		"items": [
			["kr_kuruma", Vector2(0.4, 0.25), 90.0, "南の田の農家（村から戻る）", "橋を渡ってきて荷を降ろし終えた大八車（空）"],
			["mk_tsumini", Vector2(-1.85, -0.25), 0.0, "南の田の農家", "車から降ろした荷：種籾の俵・肥料の菰包み・道具の箱・縄"],
			["hu_seoikago", Vector2(-0.55, -1.05), -15.0, "南の田の農家の嫁", "荷の山から田へ背負っていく籠（下ろしたまま）"],
			["kr_ni", Vector2(2.3, -0.6), 20.0, "南の田の農家", "先に降ろした菰包み：あとで車ごと納屋へ"],
		]})
	D.append({"id": "XA5_yasumi", "zone": "A", "anchor": "route", "ref": Vector2(433.0, 70.0),
		"desc": "FarmPath_2×FarmPath_5 の辻の北西：田の合間の一服——藁塚の陰の縁台、下ろした背負い籠と水の手桶",
		"frame": {"p": Vector2(433.0, 65.5), "face": Vector2(0, 1)},
		"items": [
			["st_warazuka", Vector2(0.0, -1.0), 0.0, "北の田の年寄り", "去年の藁を積んだ藁塚：昼の日陰になる"],
			["sk_bench", Vector2(0.15, 0.35), 0.0, "北の田の年寄り", "藁塚の陰に置いた縁台：昼飯と一服"],
			["hu_seoikago", Vector2(-1.45, 0.4), 15.0, "北の田の年寄り", "縁台の脇に下ろした背負い籠"],
			["sk_teoke", Vector2(1.55, 0.55), 0.0, "北の田の年寄り", "水を汲んできた手桶と柄杓"],
		]})
	# ── B 普通住宅（核心商業區から 45 m 以上・R4 の後院以外）：各戶の暮らしは一つ、裏の壁と背戸の脇に寄せる
	D.append({"id": "XB1_some", "zone": "B", "anchor": "building", "bld": "B_P_RSW_048",
		"desc": "B_P_RSW_048（WestBankLane の厨子二階）の裏：染め物の内職——藍の盥・染料の甕・染めた反物を掛けて干す",
		"frame": {"bld": "B_P_RSW_048"},
		"items": [
			["ms_nuno_kake", Vector2(1.7, 2.6), 0.0, "RSW_048 の女房（染め物の内職）", "藍で染めた反物を竿に掛けて干す"],
			["hu_tarai", Vector2(1.55, 1.0), 0.0, "RSW_048 の女房", "藍の液に布を浸ける盥（布が入ったまま）"],
			["mk_kame", Vector2(2.95, 0.6), 0.0, "RSW_048", "藍の染め液を寝かせる甕"],
			["sz_stool", Vector2(0.9, 1.6), 60.0, "RSW_048 の女房", "盥の前の腰掛け"],
		]})
	D.append({"id": "XB2_okeya", "zone": "B", "anchor": "building", "bld": "B_P_RSW_051",
		"desc": "B_P_RSW_051（WestBankLane の平屋）の裏：近所の桶・盥を直す家——軒の陰から日向に出した作業場を挟んで、左に直しを待つ盥、右に直し終えた手桶の山",
		"frame": {"bld": "B_P_RSW_051"},
		"items": [
			["st_okeya", Vector2(-1.9, 2.35), 0.0, "RSW_051 の主（桶の直し）", "緩んだ桶に新しい竹の箍を締める作業場（丸太台・締めかけの桶）：明るい日向で"],
			["kr_okeyama", Vector2(-0.25, 2.05), 0.0, "近所の家々", "直しを頼まれて積んである盥と桶（作業場の右手）"],
			["tk_okeyama", Vector2(-3.75, 1.95), 0.0, "RSW_051 の主", "直し終えて台に積んだ手桶：取りに来るのを待つ"],
			["sk_box", Vector2(-1.85, 3.55), -20.0, "RSW_051 の主", "鉋・鑿・竹割りの道具箱（座る後ろ）"],
		]})
	D.append({"id": "XB3_hatake", "zone": "B", "anchor": "building", "bld": "B_P_RNE_005",
		"desc": "B_P_RNE_005（NELane の平屋）の裏：小さな家庭菜園——背戸の道の両側に畝、外側に柴垣",
		"frame": {"bld": "B_P_RNE_005"},
		"items": [
			["hx_hatake", Vector2(2.15, 2.3), 0.0, "RNE_005 の婆", "背戸の脇の畝：大根・葱・青菜（毎朝ここで摘む）"],
			["hx_hatake", Vector2(-2.2, 2.6), 180.0, "RNE_005 の婆", "道の反対側の畝：冬の漬物用の大根"],
			["st_shibagaki", Vector2(0.0, 4.4), 0.0, "RNE_005", "畑を路地から守る柴垣"],
		]})
	D.append({"id": "XB4_nizukuri", "zone": "B", "anchor": "building", "bld": "B_P_RNE_003",
		"desc": "B_P_RNE_003（NELane の厨子二階）の裏：荷造りの家——箱と俵を積み、半分積んだ荷車（出荷か引っ越し）",
		"frame": {"bld": "B_P_RNE_003"},
		"items": [
			["mk_tsumini", Vector2(-1.9, 1.2), 0.0, "RNE_003 の主", "木箱・俵・菰包みを積んだ荷：明日の朝に出す"],
			["mk_kuruma_ni", Vector2(-1.6, 3.4), 90.0, "RNE_003 の主", "裏に回した大八車：半分積んだところ"],
			["kr_ni", Vector2(1.35, 0.5), 0.0, "RNE_003", "背戸の脇に出した菰包み"],
			["kr_nawa", Vector2(1.1, 1.35), 0.0, "RNE_003", "荷を縛る縄"],
		]})
	D.append({"id": "XB5_tsukemono", "zone": "B", "anchor": "building", "bld": "B_P_RSW_033",
		"desc": "B_P_RSW_033（NWLane の平屋）の裏：冬の漬物づくり——竿に干して萎びさせた大根と、それを漬ける樽を並べた筵",
		"frame": {"bld": "B_P_RSW_033"},
		"items": [
			["hx_daikon_kake", Vector2(1.45, 1.75), 0.0, "RSW_033 の母", "沢庵にする大根を竿に掛けて干す（一週間ほど萎びさせる）"],
			["mk_mushiro_tsuke", Vector2(-1.55, 1.6), 0.0, "RSW_033 の母", "沢庵・菜・梅の樽を筵に並べて漬ける"],
			["sz_stool", Vector2(-0.2, 2.65), -40.0, "RSW_033 の母", "樽の前で座る腰掛け"],
		]})
	return D


## ART_REJECTED（使用者 2026-10-08）の水岸 3 群——rejected candidates として記録だけ残す。正式の design()／plan()／bake() は出力しない
## （gate HUX が「正式の計画に C 群・REJECTED の id・hx_doroage が無い」ことを確認、反向でこの関数を足すと FAIL）。
static func rejected_c() -> Array:
	var D: Array = []
	# ── C 水岸と水渠（r1→r3 の 3 回の反復でも 10–15 m で用途が読めず ART_REJECTED）
	D.append({"id": "XC1_araimono", "zone": "C", "anchor": "water", "ref": Vector2(372.0, -156.0),
		"desc": "北の雁木石段（stair3）の上：採った野菜を洗う所——泥付きの箱と籠 → 石段から汲んだ水の盥 → 洗って水を切る筵",
		"frame": {"p": Vector2(366.0, -156.5), "face": Vector2(1, 0)},
		"items": [
			["mk_mushiro_yasai", Vector2(0.0, -0.5), 0.0, "北の田の農家", "洗った大根・南瓜・茄子を筵に並べて水を切る"],
			["hu_tarai", Vector2(-1.75, 0.85), 0.0, "北の田の農家の嫁", "石段から汲んだ水で泥を落とす盥"],
			["st_kago_tsumi", Vector2(-2.35, -1.25), 90.0, "北の田の農家", "畑から運んできた泥付きの大根・南瓜の箱と籠：これから洗う"],
		]})
	D.append({"id": "XC2_hashi", "zone": "C", "anchor": "bridge", "ref": Vector2(165.5, -8.0),
		"desc": "Bridge_05（西の小川の木橋）の東の橋詰め：橋板の張り替え——馬に板を渡した作業台、新しい橋板の山、外した古い板、桁を見に降りる梯子",
		"frame": {"p": Vector2(168.8, -4.5), "face": Vector2(-1, 0)},
		"items": [
			["st_daiku", Vector2(0.0, 0.0), 0.0, "WestBankLane の大工", "橋板を寸法に切る作業台（馬 2・鋸・墨壺）"],
			["kr_zaimoku", Vector2(-0.2, 1.2), 0.0, "WestBankLane の大工", "張り替える新しい橋板（作業台と橋の間）"],
			["kr_zaimoku", Vector2(0.2, -1.3), 8.0, "WestBankLane の大工", "外した古い橋板：薪にする（作業台の裏）"],
			["tk_ladder", Vector2(-3.05, 0.9), 0.0, "WestBankLane の大工", "橋の下へ降りて桁を見る梯子（岸に寝かせる）"],
			["kr_nawa", Vector2(1.65, 1.0), 0.0, "WestBankLane の大工", "板を吊り下ろす縄"],
		]})
	D.append({"id": "XC3_suiro", "zone": "C", "anchor": "water", "ref": Vector2(318.5, 53.0),
		"desc": "南の水車（WATERWHEEL_3）の下手の東岸：水路の泥上げ——岸に掻き上げた泥と藻の山（鋤を挿したまま）、崩れかけた岸の縁に並べた土嚢、熊手・鋤の掛け、泥を運ぶ手桶",
		"frame": {"p": Vector2(324.4, 53.0), "face": Vector2(-1, 0)},
		"items": [
			["hx_doroage", Vector2(1.6, 1.55), 0.0, "水車を使う家の組", "水車の水路から掻き上げた泥と藻：乾いたら田へ入れる"],
			["kr_fukuro", Vector2(-0.6, 1.95), 90.0, "水車を使う家の組", "崩れかけた岸の縁に並べた土嚢（麻袋）"],
			["kr_ni", Vector2(-2.1, 1.8), 15.0, "水車を使う家の組", "土嚢の続き（菰包み）"],
			["st_kuwa", Vector2(0.2, -0.3), 0.0, "水車を使う家の組", "藻・泥を掻く熊手と鋤を掛けた道具掛け"],
			["tk_okeyama", Vector2(-1.6, -0.1), 0.0, "水車を使う家の組", "掻き出した泥を運ぶ手桶を台に積む"],
		]})
	return D


static func plan(v: Node3D, meadow_pts: PackedVector2Array, des: Array = []) -> Dictionary:
	var C := context(v, meadow_pts)
	var items: Array = []
	var clusters: Array = []
	for cl: Dictionary in (des if not des.is_empty() else design()):
		var fr := HU.frame(C, cl)
		var face: Vector2 = fr[1]
		var along := Vector2(-face.y, face.x)
		var scope := Rect2(fr[0], Vector2.ZERO).grow(GROUP_R)
		var got: Array = []
		for e: Array in cl["items"]:
			var off: Vector2 = e[1]
			var c: Vector2 = (fr[0] as Vector2) + along * off.x + face * off.y
			var f := face.rotated(deg_to_rad(float(e[2])))
			var meta := {"cluster": String(cl["id"]), "zone": String(cl["zone"]), "anchor": String(cl["anchor"]), "anchor_desc": String(cl["desc"]),
				"who": String(e[3]), "why": String(e[4]), "scope": scope}
			var it := place(C, items, String(e[0]), c, f, meta, float(e[5]) if e.size() > 5 else 1.25)
			if not it.is_empty():
				got.append(it)
		clusters.append({"id": String(cl["id"]), "zone": String(cl["zone"]), "anchor": String(cl["anchor"]), "anchor_desc": String(cl["desc"]),
			"ref": fr[2], "bld": String(cl.get("bld", "")), "center": fr[0], "face": face, "n_design": (cl["items"] as Array).size(), "n": got.size(),
			"role": String(cl.get("role", "main"))})
	return {"C": C, "items": items, "clusters": clusters}


## 診断：理由の頭文字の地図（R4 の記号＋ c 核心商業 r R4 件 z R4 Pilot 区）
static func survey(C: Dictionary, r: Rect2, step := 0.5) -> PackedStringArray:
	var out := PackedStringArray()
	var code := {"": ".", "terrain": " ", "road": "R", "frontage": "F", "building": "B", "water": "W", "p7": "w", "bridge": "b", "hero": "H", "p8": "A",
		"sealed": "S", "trunk": "T", "env": "E", "p10": "P", "npc": "N", "backdoor": "d", "door": "D", "meadow": "g", "slope": "/",
		"core": "c", "commerce": "c", "r4": "r", "r4zone": "z"}
	for j in int(r.size.y / step) + 1:
		var z := r.position.y + j * step
		var row := "%7.1f " % z
		for i in int(r.size.x / step) + 1:
			var x := r.position.x + i * step
			var it := item(C, "_probe", Vector2(x, z), Vector2(0, 1), {})
			var w := why(C, it, [])
			if w == "" and relief(C, it) > HU.RELIEF_MAX:
				w = "slope"
			row += String(code.get(w, "?"))
		out.append(row)
	return out


## 住宅候補の順位：町家の裏（out 0.6–3.6、along ±2.4）の置ける割合・NPC／核心からの距離
static func rank_backyards(C: Dictionary) -> Array:
	var out: Array = []
	for b: Dictionary in C["bld"]:
		if String(b["kind"]) != "machiya":
			continue
		var o: Vector2 = b["o"]
		var face: Vector2 = -(b["az"] as Vector2)
		var along := Vector2(-face.y, face.x)
		var c0: Vector2 = o + face * (float(b["d"]) * 0.5)
		if c0.distance_to(CORE_CENTER) < CORE_R + 5.0:
			continue
		var free := 0
		var tot := 0
		for i in range(-4, 5):
			for j in range(1, 7):
				var q := c0 + along * (i * 0.6) + face * (0.3 + j * 0.55)
				var it := item(C, "_probe", q, face, {})
				tot += 1
				if why(C, it, []) == "" and relief(C, it) <= HU.RELIEF_MAX:
					free += 1
		var nd := 1e9
		for t: Vector2 in C["npc"]:
			nd = minf(nd, t.distance_to(c0))
		out.append({"name": b["name"], "o": o, "back": c0, "free": float(free) / tot, "npc_d": nd, "core_d": c0.distance_to(CORE_CENTER), "w": b["w"], "type": b["type"], "kinds": b["kinds"], "road": b["road"]})
	out.sort_custom(func(a: Dictionary, b2: Dictionary) -> bool: return float(a["free"]) > float(b2["free"]))
	return out


# ─────────────────────────── 烘焙 ───────────────────────────

static func bake(P: Dictionary) -> Node3D:
	var C: Dictionary = P["C"]
	var root := Node3D.new()
	root.name = NODE_NAME
	var groups := {}
	for z: String in ZONE_NAME:
		var n := Node3D.new()
		n.name = "Zone" + z
		n.set_meta("zone", ZONE_NAME[z])
		root.add_child(n)
		groups[z] = n
	var cl_nodes := {}
	for cl: Dictionary in P["clusters"]:
		var n := Node3D.new()
		n.name = String(cl["id"])
		n.set_meta("anchor", String(cl["anchor"]))
		n.set_meta("anchor_desc", String(cl["anchor_desc"]))
		n.set_meta("role", String(cl["role"]))
		n.set_meta("ref", cl["ref"])
		var c2: Vector2 = cl["center"]
		n.position = Vector3(c2.x, top_h(C, c2), c2.y)
		(groups[String(cl["zone"])] as Node).add_child(n)
		cl_nodes[String(cl["id"])] = n
	var col := StaticBody3D.new()
	col.name = "Collision"
	root.add_child(col)
	var meshes := {}
	var n_i := 0
	var ns := 0
	for it: Dictionary in P["items"]:
		var id := String(it["id"])
		var parent: Node3D = cl_nodes[String(it["cluster"])]
		var node := Node3D.new()
		node.name = "%03d_%s" % [n_i, id]
		var wxf := Transform3D(Basis(Vector3.UP, float(it["yaw"])), Vector3((it["p"] as Vector2).x, float(it["y"]), (it["p"] as Vector2).y))
		node.transform = parent.transform.affine_inverse() * wxf
		for k in ["who", "why", "anchor", "cluster", "zone"]:
			node.set_meta("hu_" + k, String(it[k]))
		node.set_meta("hu_id", id)
		parent.add_child(node)
		for lod in 2:
			var key := id + ("_l1" if lod == 1 else "")
			if not meshes.has(key):
				meshes[key] = load(mesh_dir(id) + key + ".res")
			var mi := MeshInstance3D.new()
			mi.name = "LOD%d" % lod
			mi.mesh = meshes[key]
			mi.visibility_range_begin = 0.0 if lod == 0 else LOD_SWITCH
			mi.visibility_range_end = LOD_SWITCH if lod == 0 else 200.0
			if lod == 1:
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.add_child(mi)
		var d: Array = C["D"][id]
		if float(d[4]) >= 0.35:
			var bx := BoxShape3D.new()
			bx.size = Vector3(float(d[3]) - float(d[0]), float(d[4]), float(d[5]) - float(d[2]))
			var cs := CollisionShape3D.new()
			cs.name = "%s_c" % node.name
			cs.shape = bx
			var ba := Basis(Vector3.UP, float(it["yaw"]))
			cs.transform = Transform3D(ba, wxf.origin + ba * Vector3((float(d[0]) + float(d[3])) * 0.5, float(d[4]) * 0.5, (float(d[2]) + float(d[5])) * 0.5))
			col.add_child(cs)
			ns += 1
		n_i += 1
	root.set_meta("items", (P["items"] as Array).size())
	root.set_meta("clusters", (P["clusters"] as Array).size())
	root.set_meta("shapes", ns)
	root.set_meta("art_revision", ART_REVISION)
	return root

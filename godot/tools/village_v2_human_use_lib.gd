## 人間之里 V2 P10 R4 Human-Use / Ambient Life Pilot（HumanUseP10＝village_v2 の root 直下、Props の次）。
##   目標：NPC を全部消しても「ここで人が長く暮らし・働き・やり取りしている」と読める痕跡。人口は増やさない・動かさない。
##   3 Pilot（全村には広げない）：A 農田の作業（Bridge_03 の田側＝稲干し場・脱穀／風選・田の入口）／B 住宅の裏（MidLane 南の町家 4 戸の後院）／
##   C 水車の維持（北の水車：羽根板の修理・注油・米搗きの段取り）。
##   置き方：手設計の cluster（誰が・何のために・何に依附して）＋局所探索（平ら・合法な最寄り）。滿地の小物 scatter はしない；
##   中型の輪郭（稲架・唐箕・荷車・干し竿・薪棚・作業台…）を核に 3–7 件で組む。各件に who／why／anchor を持たせ、gate で検査する。
##   禁區：路面・店先帯・建物（+0.25）・戸口・背戸の通り道・水（+0.8）・P7 構件（細密）・橋・P8 の田／畦／水路（+0.4）・封存 overlay の構件・樹幹・
##   EnvironmentP9（+1.6 m、event の錨 +3.2 m：R5-4 の自分の規則が HU 掛載後も成り立つ）・他の P10 構件・NPC（立ち位置 +0.9／往復路 +0.7）・
##   MeadowP9 の株（AABB +0.4 に 0 株：meadow 文脈の再計算が封存と一致し續ける）。
##   生成：verify_village_v2_human_use.gd -- --build（MultiMesh なし → headless で可）。
const SL := preload("res://tools/village_v2_street_lib.gd")
const RLib := preload("res://tools/village_v2_riverbank_lib.gd")
const MD := preload("res://tools/village_v2_meadow_lib.gd")
const GC := preload("res://tools/village_v2_groundcover_lib.gd")
const OUTPUT := "res://maps/village_v2/gen/human_use_p10.scn"
const NODE_NAME := "HumanUseP10"
const PARENT := "."   # root 直下（Props の次）：R3b 封存の scene gate が Props の子を完全一致（Market→Street→MarketWest→Env）で検査するため Props には入れない
const LOD_SWITCH := 34.0
const ART_REVISION := "P10 R4 Human-Use Pilot r4（ART_REVIEW）"
const KIT_OF := {"hu_": "humanuse_kit", "st_": "street_kit", "mk_": "market_kit", "sk_": "school_kit", "tk_": "tower_kit",
	"kr_": "kiri_kit", "sz_": "suzu_kit", "wk_": "waterside_kit", "ms_": "mise_kit"}
## kiri_kit・suzu_kit は Hero（霧雨店・鈴奈庵）固有の中身があるので、汎用の道具だけ（魔法材料・本は不可）
const GENERIC_ONLY := {"kr_": ["kr_houki", "kr_nawa", "kr_zaimoku", "kr_kuruma", "kr_okeyama", "kr_hakozumi", "kr_ni"],
	"sz_": ["sz_stool", "sz_hachi"], "ms_": ["ms_tsuri_kaki", "ms_tsuri_oke"]}
const NEW_IDS := ["hu_senba", "hu_tomi", "hu_momiboshi", "hu_tarai", "hu_makiwari", "hu_seoikago"]
const ANCHOR_TYPES := ["building", "work_surface", "water", "field", "route", "storage"]
## Pilot の範圍（この外には置かない＝全村 batch しない）
const PILOTS := {"A": Rect2(340.0, -36.0, 44.0, 48.0), "B": Rect2(236.0, -84.0, 34.0, 24.0), "C": Rect2(312.0, -66.0, 40.0, 30.0)}
const PILOT_NAME := {"A": "Farmland Human-Use（Bridge_03 田側：稲干し場・脱穀・田の入口）", "B": "Residential Back Alley Life（MidLane 南：町家 4 戸の後院）",
	"C": "Waterside / Working Edge（北の水車：維持・修理・米搗き）"}
const ENV_PAD := 1.6
const ENV_ANCHOR_PAD := 3.2
const P10_PAD := 0.15
const NPC_PAD := 0.9
const PATROL_PAD := 0.7
const MEADOW_PAD := 0.4
const BLD_PAD := 0.25
const RELIEF_MAX := 0.12
const SNAP := ["res://data/village_v2_p10r3d_snapshot.json", "res://data/village_v2_p10r3e_snapshot.json"]

## ─────────────────────────── 設計（cluster） ───────────────────────────
## 各 cluster：pilot・anchor 型（ANCHOR_TYPES）・依附先の説明・ref（依附先の上の 1 点：gate がその型か検査）・frame
##   frame＝{"p": 中心, "face": 使う人の側} か {"bld": 建物名}（＝裏の壁の中央、face＝裏の外向き）。
##   items＝[id, Vector2(along, out), 向きの回転°, who, why, rmax]——along＝face の右手（face.rotated(90°) の逆向き）、out＝face 方向（m）。
##   r2：審圖の自評「物は読めるが展示の列・関係が弱い」→ 作業の立ち位置を囲む小さな塊に詰め、物どうしを向き合わせる（間 0.2–0.8 m）。
static func design() -> Array:
	var D: Array = []
	# ── A 農田：Bridge_03 を渡った田の側（O1・O3・O8 の農家の田）
	D.append({"id": "A1_hasa", "pilot": "A", "anchor": "field", "ref": Vector2(350.5, -21.0),
		"desc": "Bridge_03 田側の畑（P8 block 4）の西の縁：刈り稲を掛ける稲架の列",
		"frame": {"p": Vector2(345.5, -23.6), "face": Vector2(1, 0)},
		"items": [
			["st_hasa", Vector2(2.0, 0.0), 0.0, "O1 の家（田を持つ農家）", "刈った稲を田の脇の稲架に掛けて干す（列の北半分）"],
			["st_hasa", Vector2(-1.95, 0.0), 0.0, "O1 の家", "同じ稲架の列の南半分：一枚の田の刈り稲で 2 架が埋まる"],
			["hu_seoikago", Vector2(0.15, 0.95), 12.0, "O1 の家の嫁", "田から背負ってきた稲束：これから稲架へ掛ける分を下ろした"],
		]})
	D.append({"id": "A2_dakkoku", "pilot": "A", "anchor": "route", "ref": Vector2(352.0, 0.0),
		"desc": "FarmPath_4（田の東西の農道）の北の平地：筵を囲んで扱き・選り・干し、俵に詰めて荷車へ（作業の流れ：稲束→千歯→筵→唐箕→俵→車）",
		"frame": {"p": Vector2(352.0, -4.6), "face": Vector2(0, 1)},
		"items": [
			["hu_momiboshi", Vector2(2.0, -0.05), 2.0, "O1 の家の婆", "扱いた籾を筵に広げ、えぶりで返して干す（筵を 2 組並べた作業の床の西半分）"],
			["hu_momiboshi", Vector2(0.0, 0.05), -3.0, "O1 の家の婆", "筵の床の東半分：唐箕にかける前の籾を干す"],
			["hu_senba", Vector2(3.75, 0.0), -90.0, "O1 の家の主", "筵の床の西の縁で千歯扱き：扱いた籾は筵へ落ちる"],
			["hu_seoikago", Vector2(4.35, 1.3), -20.0, "O1 の家の嫁", "稲架から外して運んできた、これから扱く稲束"],
			["st_warazuka", Vector2(5.0, -1.35), 0.0, "O1 の家", "扱いた後の藁を千歯の後ろに積んだ藁塚"],
			["hu_tomi", Vector2(-1.7, -0.75), 73.0, "O1 の家の主", "筵の床の東の縁で唐箕：干した籾の殻と塵を飛ばし、口を筵へ向ける"],
			["wk_tawara3", Vector2(-2.35, 1.05), 15.0, "O1 の家", "選った籾を詰めた俵：唐箕の口の脇に積む"],
			["kr_kuruma", Vector2(-3.55, -0.05), 0.0, "O1 の家（大八車）", "俵を村の蔵へ運ぶ大八車：俵の隣に梶棒を農道へ向けて停め、積み込みを待つ"],
		]})
	D.append({"id": "A3_taguchi", "pilot": "A", "anchor": "field", "ref": Vector2(380.0, 7.5),
		"desc": "FarmPath_1×FarmPath_4 の辻の南東＝P8 の田の北西の口：田に入る前に道具を取り、刈った物を車に積んで一服する所",
		"frame": {"p": Vector2(378.6, 3.1), "face": Vector2(0, -1)},
		"items": [
			["st_kuwa", Vector2(0.0, 0.0), 0.0, "この田の組（数軒の共同）", "鍬・鋤・熊手を掛け、蓑を吊るす農具掛け：田の口に置いて毎朝取る"],
			["sk_teoke", Vector2(-1.25, 0.35), 0.0, "田で働く人", "水を汲んできた手桶と柄杓：一服の水"],
			["wk_tawara", Vector2(-2.2, -0.25), 25.0, "田で働く人", "腰を下ろす空き俵（休み場）"],
			["kr_nawa", Vector2(-1.0, -0.8), 0.0, "この田の組", "稲束を縛る藁縄の束"],
			["mk_kuruma_ni", Vector2(2.95, 0.1), 90.0, "O3 の家", "田から上げた俵と南瓜・籠を積んだ大八車：辻から村へ出す前"],
		]})
	# ── B 住宅の裏：MidLane の南、町家 4 戸の後院（市集の北、Hero なし）——各戸は背戸の脇の一つの作業の塊
	D.append({"id": "B1_maki", "pilot": "B", "anchor": "building", "bld": "B_P_MKT_030",
		"desc": "B_P_MKT_030（厨子二階の店）の裏：薪をたくさん積む家（堆柴戶）——裏の角の薪棚 2 と、その前の薪割り場",
		"frame": {"bld": "B_P_MKT_030"},
		"items": [
			["sk_woodpile", Vector2(1.6, 0.62), 0.0, "MKT_030 の主（冬の煮炊き・湯）", "割った薪を裏の壁に沿って積む薪棚"],
			["sk_woodpile", Vector2(2.95, 1.95), 90.0, "MKT_030 の主", "二つ目の薪棚を直角に：裏の角が薪置き場"],
			["hu_makiwari", Vector2(1.45, 2.55), -20.0, "MKT_030 の息子", "薪棚の前で玉切りを割る薪割り台（割った薪は棚へ）"],
			["kr_nawa", Vector2(2.75, 3.55), 0.0, "MKT_030 の主", "割った薪を束ねる縄"],
		]})
	D.append({"id": "B2_shigoto", "pilot": "B", "anchor": "building", "bld": "B_P_MKT_029",
		"desc": "B_P_MKT_029（二階の店）の裏：内職をする家（做工戶）——背戸の脇で藁細工、腰掛け・材料の藁塚・品物の箱",
		"frame": {"bld": "B_P_MKT_029"},
		"items": [
			["st_wara", Vector2(-1.75, 1.45), 0.0, "MKT_029 の女房（内職）", "店で売る草鞋を裏庭で編む藁細工の場（草鞋掛けは壁側）"],
			["sz_stool", Vector2(-1.75, 2.4), 180.0, "MKT_029 の女房", "編む人が腰掛ける低い腰掛け（筵を向く）"],
			["st_warazuka", Vector2(-3.4, 1.7), 0.0, "MKT_029 の女房", "農家から買って積んだ藁（草鞋の材料）：作業場の隣の藁塚"],
			["kr_hakozumi", Vector2(-2.85, 0.55), 0.0, "MKT_029 の主", "出来た草鞋と仕入れの品を詰めた箱を裏の壁に積む"],
		]})
	D.append({"id": "B3_kodomo", "pilot": "B", "anchor": "building", "bld": "B_P_MKT_028",
		"desc": "B_P_MKT_028（平屋の住まい）の裏：子供のいる家——背戸の前で洗濯（盥・天水桶・腰掛け）と干し竿、壁際に子供の遊び道具",
		"frame": {"bld": "B_P_MKT_028"},
		"items": [
			["mk_hoshimono", Vector2(-2.2, 2.75), 0.0, "MKT_028 の母", "洗った着物・手拭いと干し大根を盥の後ろの竿に干す（背戸の前は通り道に空ける）"],
			["hu_tarai", Vector2(-1.6, 1.3), 0.0, "MKT_028 の母", "背戸の脇で洗濯の途中の盥（水と洗い物が入ったまま）"],
			["sz_stool", Vector2(-0.85, 1.5), -60.0, "MKT_028 の母", "盥の前で洗う人の腰掛け"],
			["sk_tensui", Vector2(-2.75, 0.5), 0.0, "MKT_028", "雨水を溜める天水桶：洗濯の水"],
			["sk_hoop", Vector2(-3.65, 1.45), 0.0, "MKT_028 の子", "母の洗濯の脇に置きっぱなしの竹の輪回し"],
			["sk_temari", Vector2(-0.75, 2.3), 0.0, "MKT_028 の子", "庭に転がっている手毬"],
			["sk_zori", Vector2(0.85, 0.4), 0.0, "MKT_028 の子", "背戸の踏み石の脇に脱いだ子供の草履"],
		]})
	D.append({"id": "B4_kirei", "pilot": "B", "anchor": "building", "bld": "B_P_RSW_072",
		"desc": "B_P_RSW_072（MidLane の平屋）の裏：きれい好きの隠居の家（乾淨戶）——掃いた庭に箒、水甕、縁台と鉢植え",
		"frame": {"bld": "B_P_RSW_072"},
		"items": [
			["kr_houki", Vector2(-0.95, 0.4), 0.0, "RSW_072 の隠居", "毎朝裏庭を掃く箒を背戸の脇に立て掛ける"],
			["mk_kame", Vector2(-2.3, 0.7), 0.0, "RSW_072", "水甕（大は蓋と柄杓）：井戸から汲んだ水を溜める"],
			["sk_teoke", Vector2(-1.5, 1.2), 0.0, "RSW_072", "水甕に水を運ぶ手桶"],
			["sk_bench", Vector2(1.95, 0.6), 0.0, "RSW_072 の隠居", "夕方に腰掛ける縁台"],
			["sz_hachi", Vector2(3.1, 0.55), 0.0, "RSW_072 の隠居", "縁台の脇に並べた鉢植え（隠居の楽しみ）"],
			["sz_hachi", Vector2(0.8, 0.55), 30.0, "RSW_072 の隠居", "縁台の反対の端にも鉢植え：揃えて並べる"],
		]})
	# ── C 水の縁：北の水車（村側の岸）
	D.append({"id": "C1_shuri", "pilot": "C", "anchor": "work_surface", "ref": Vector2(332.6, -52.0),
		"desc": "北の水車（村側の軸受け）の上手の岸：羽根板の修理と注油——作業台を囲んで替え板・道具箱・縄、岸に梯子",
		"frame": {"p": Vector2(327.0, -55.4), "face": Vector2(1, 0)},
		"items": [
			["st_daiku", Vector2(0.0, -0.3), 0.0, "水車番（村の大工を兼ねる）", "馬に板を渡して欠けた羽根板を削る作業台"],
			["tk_ladder", Vector2(0.6, 2.6), 0.0, "水車番", "軸受けに油をさし、水輪の上の羽根に届く梯子（岸に寝かせる）"],
			["kr_zaimoku", Vector2(-0.1, -1.85), 0.0, "水車番", "替えの羽根板（板材）を作業台の後ろに積む"],
			["sk_box", Vector2(-1.75, -0.9), 20.0, "水車番", "鑿・鉋・油壺を入れた道具箱"],
			["tk_rope", Vector2(1.6, -1.0), 0.0, "水車番", "水輪を止める・板を吊る縄の束"],
		]})
	D.append({"id": "C2_nioki", "pilot": "C", "anchor": "work_surface", "ref": Vector2(326.0, -46.3),
		"desc": "水車の臼（R4-4 の石臼・俵）の西：米を搗きに来た荷の一時置き（車・俵・菰包み・桶が臼の俵に寄り添う）",
		"frame": {"p": Vector2(322.0, -48.4), "face": Vector2(1, 0)},
		"items": [
			["kr_kuruma", Vector2(-0.2, -1.0), 0.0, "米を搗きに来た農家（O5 の連れ）", "俵を運んできた大八車（梶棒を臼の方へ下ろして停める）"],
			["wk_tawara3", Vector2(-2.0, 1.6), 0.0, "米を搗きに来た農家", "臼の脇の俵（R4-4）に足して積んだ、搗く順番を待つ俵"],
			["kr_ni", Vector2(0.9, 1.3), 0.0, "米を搗きに来た農家", "糠と籾殻を入れて持ち帰る菰包み"],
			["kr_okeyama", Vector2(1.6, -0.2), 0.0, "水車番", "搗いた米を受け・水を運ぶ桶と盥（車の脇に置く）"],
		]})
	D.append({"id": "C3_araiba", "pilot": "C", "anchor": "water", "ref": Vector2(334.0, -42.0),
		"desc": "Bridge_03 の北詰め・水渠の岸：洗い物をして干す所（水車番の家の裏）——竿・盥・腰掛け・手桶を岸の上に詰める",
		"frame": {"p": Vector2(326.0, -42.2), "face": Vector2(0, 1)},
		"items": [
			["mk_hoshimono", Vector2(0.0, 0.3), 0.0, "水車番の家", "水渠で洗った布と手拭いを岸の竿に干す"],
			["hu_tarai", Vector2(-2.6, -0.3), 0.0, "水車番の家の娘", "水渠から汲んだ水で洗い物をしている盥"],
			["sz_stool", Vector2(-2.4, 0.65), 180.0, "水車番の家の娘", "盥の前で洗う人の腰掛け"],
			["sk_teoke", Vector2(-3.6, 0.4), 0.0, "水車番の家の娘", "水渠から水を汲む手桶"],
		]})
	return D


static func kit_of(id: String) -> String:
	return KIT_OF[id.substr(0, 3)]


static func mesh_dir(id: String) -> String:
	return "res://assets/village_v2/%s/mesh/" % kit_of(id)


## 足元・高さ（kit の modules_blender.json の dims：[minx, miny, minz, maxx, maxy, maxz]、Godot 座標）
static func dims_table() -> Dictionary:
	var out := {}
	for pre: String in KIT_OF:
		var kit: String = KIT_OF[pre]
		var j: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/village_v2/%s/src/modules_blender.json" % kit))
		for n: String in j["modules"]:
			if not n.ends_with("_l1"):
				out[n] = j["modules"][n]["dims"]
	out["_probe"] = [-0.3, 0.0, -0.3, 0.3, 0.5, 0.3]
	return out


static func yaw_to(d: Vector2) -> float:
	var n := d.normalized()
	return atan2(n.x, n.y)


static func local_to_world(it: Dictionary, l: Vector2) -> Vector2:
	var yaw: float = it["yaw"]
	return (it["p"] as Vector2) + Vector2(cos(yaw), -sin(yaw)) * l.x + Vector2(sin(yaw), cos(yaw)) * l.y


static func corners(C: Dictionary, it: Dictionary) -> PackedVector2Array:
	var d: Array = C["D"][String(it["id"])]
	var out := PackedVector2Array()
	for l: Vector2 in [Vector2(d[0], d[2]), Vector2(d[3], d[2]), Vector2(d[3], d[5]), Vector2(d[0], d[5])]:
		out.append(local_to_world(it, l))
	return out


static func aabb2(C: Dictionary, it: Dictionary) -> Rect2:
	var cs := corners(C, it)
	var r := Rect2(cs[0], Vector2.ZERO)
	for q in cs:
		r = r.expand(q)
	return r


static func height(C: Dictionary, id: String) -> float:
	return float(C["D"][id][4])


static func long_side(C: Dictionary, id: String) -> float:
	var d: Array = C["D"][id]
	return maxf(float(d[3]) - float(d[0]), float(d[5]) - float(d[2]))


static func samples(poly: PackedVector2Array, step := 0.25) -> PackedVector2Array:
	var out := PackedVector2Array()
	var a := poly[0]
	var bx := poly[1] - poly[0]
	var bz := poly[3] - poly[0]
	var nx := maxi(1, int(ceil(bx.length() / step)))
	var nz := maxi(1, int(ceil(bz.length() / step)))
	for i in nx + 1:
		for j in nz + 1:
			out.append(a + bx * (float(i) / nx) + bz * (float(j) / nz))
	return out


## 見えている最上面：地形・路面・P4 院子・P8 の田の地面
static func top_h(C: Dictionary, p: Vector2) -> float:
	var h := SL.top_h(C, p)
	var f := (C["FS"] as RLib.TriSampler).h(p.x, p.y)
	if not is_nan(f):
		h = maxf(h, f)
	return h


# ─────────────────────────── 文脈 ───────────────────────────

class Grid:
	var cs := 1.0
	var cells := {}
	func add(r: Rect2, val) -> void:
		for i in range(floori(r.position.x / cs), floori(r.end.x / cs) + 1):
			for j in range(floori(r.position.y / cs), floori(r.end.y / cs) + 1):
				var k := Vector2i(i, j)
				if not cells.has(k):
					cells[k] = []
				(cells[k] as Array).append(val)
	func at(q: Vector2) -> Array:
		return cells.get(Vector2i(floori(q.x / cs), floori(q.y / cs)), [])


static func _rect_of(g: GeometryInstance3D, v: Node3D) -> Rect2:
	var a := RLib.rel_xf(g, v) * g.get_aabb()
	return Rect2(a.position.x, a.position.z, a.size.x, a.size.z)


## meadow_pts：MeadowP9 の規劃株（同 seed 再計算；呼ぶ側が GroundcoverP9・MeadowP9・EnvironmentP9・HumanUseP10 を外した場景で計算して渡す）
static func context(v: Node3D, meadow_pts: PackedVector2Array) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var C := SL.context(v)
	C["D"] = dims_table()
	C["dropped"] = []
	# P7 河岸構件（細密）：LOD0 の面の高さが地形 +3 cm を越える所＝石・段・杭
	var RBS := RLib.TriSampler.new()
	var rn := v.get_node_or_null("Riverbank")
	if rn:
		for mi in rn.find_children("LOD0", "MeshInstance3D", true, false):
			var g := mi as MeshInstance3D
			if g.mesh != null:
				RBS.add(g.mesh.get_faces(), RLib.rel_xf(g, v))
	C["RBS"] = RBS
	var br: Array = []
	for b in v.get_node("Roads/Bridges").find_children("*", "MeshInstance3D", true, false):
		br.append(_rect_of(b as MeshInstance3D, v).grow(0.6))
	C["bridges"] = br
	# Hero／Landmark（水車・龍神像・鳥居・社寺…）と特別建物 S_*（鈴奈庵・霧雨店…）：LOD0 の AABB +0.4
	var HG := Grid.new()
	var heroes: Array = []
	var lm := v.get_node_or_null("Landmarks")
	if lm:
		heroes.append_array(lm.get_children())
	for b in v.get_node("Districts").find_children("S_*", "", true, false):
		heroes.append(b)
	for h in heroes:
		for mi in (h as Node).find_children("*", "MeshInstance3D", true, false):
			var g := mi as MeshInstance3D
			if g.mesh != null and g.visibility_range_begin <= 0.001:
				var r := _rect_of(g, v)
				HG.cs = 2.0
				HG.add(r.grow(0.4), r.grow(0.4))
	C["hero_g"] = HG
	# P8：田（Plots）・畦（EarthBanks）・水路（Irrigation）・堰や板（ZoneWorks）の LOD0 の面
	var P8 := RLib.TriSampler.new()
	var f8 := v.get_node_or_null("Districts/FarmlandEast/FarmlandP8")
	if f8:
		for grp in ["Plots", "EarthBanks", "Irrigation", "ZoneWorks"]:
			var gn := f8.get_node_or_null(grp)
			if gn == null:
				continue
			for mi in gn.find_children("*", "MeshInstance3D", true, false):
				var g := mi as MeshInstance3D
				if g.mesh != null and g.visibility_range_begin <= 0.001:
					P8.add(g.mesh.get_faces(), RLib.rel_xf(g, v))
	C["P8"] = P8
	# 封存 overlay（Vegetation の R1–R5）：地面（Ground*）は除外（上に載せる）、木は幹（原點 r 0.6）、他は AABB +0.3
	var SG := Grid.new()
	var trunks: Array = []
	for nm: String in GC.SEALED_OVERLAYS + ["ForestP9", "BambooP9"]:
		var ov := v.get_node_or_null("Vegetation/" + nm)
		if ov == null:
			continue
		for mi in ov.find_children("*", "GeometryInstance3D", true, false):
			var g := mi as GeometryInstance3D
			if g is MultiMeshInstance3D or String(g.name).begins_with("Ground") or (g.get_parent() != null and String(g.get_parent().name).begins_with("Ground")):
				continue
			if g is MeshInstance3D and (g as MeshInstance3D).visibility_range_begin > 0.001:
				continue
			var r := _rect_of(g, v)
			if r.size.x > 3.0 or r.size.y > 3.0:
				# 樹冠（幹は原點）：木の Node（LOD の親）の原點
				var o := RLib.rel_xf(g.get_parent() as Node3D if g.get_parent() is Node3D else g, v).origin
				trunks.append(Vector2(o.x, o.z))
				continue
			SG.add(r.grow(0.3), r.grow(0.3))
	C["sealed_g"] = SG
	C["trunks"] = trunks
	# Props：EnvironmentP9（+1.6、event の錨 +3.2）と他の P10（+0.15）
	var EG := Grid.new()
	var PG := Grid.new()
	var env_anchor: Array = []
	var pr := v.get_node_or_null("Props")
	if pr:
		for ch in pr.get_children():
			if String(ch.name) == NODE_NAME:
				continue
			var is_env := String(ch.name) == "EnvironmentP9"
			for mi in ch.find_children("*", "MeshInstance3D", true, false):
				var g := mi as MeshInstance3D
				if g.mesh == null or g.visibility_range_begin > 0.001:
					continue
				var r := _rect_of(g, v)
				if is_env:
					EG.add(r.grow(ENV_PAD), r.grow(ENV_PAD))
				else:
					PG.add(r.grow(P10_PAD), r.grow(P10_PAD))
			if is_env:
				# event（E000_… の Node3D）の錨＝中の件（LOD を持つ Node3D）の重心
				for ev in ch.find_children("E*_*", "Node3D", true, false):
					var acc := Vector2.ZERO
					var n := 0
					for it in ev.get_children():
						if it is Node3D and it.get_node_or_null("LOD0") != null:
							var o := RLib.rel_xf(it as Node3D, v).origin
							acc += Vector2(o.x, o.z)
							n += 1
					if n > 0:
						env_anchor.append(acc / n)
	C["env_g"] = EG
	C["p10_g"] = PG
	C["env_anchor"] = env_anchor
	# NPC：立ち位置・往復路（R3b／R3d／R3e snapshot）＋Population の構件（席・箱・杯…、AABB +0.2）
	var npc: Array = []
	var paths: Array = []
	for f in SNAP:
		var s: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(f))
		for k in ["r3b_baseline", "r3d_added", "outer"]:
			for r: Dictionary in s.get(k, []):
				if r.has("patrol"):
					var pts := PackedVector2Array()
					for q in r["patrol"]["path"]:
						pts.append(Vector2(q[0], q[1]))
					paths.append(pts)
				npc.append(Vector2(float(r["position"][0]), float(r["position"][2])))
	C["npc"] = npc
	C["npc_paths"] = paths
	var NG := Grid.new()
	var pop := v.get_node_or_null("Population")
	if pop:
		for mi in pop.find_children("*", "MeshInstance3D", true, false):
			var g := mi as MeshInstance3D
			if g.mesh == null:
				continue
			var r := _rect_of(g, v)
			if r.size.x < 4.0 and r.size.y < 4.0:
				NG.add(r.grow(0.2), r.grow(0.2))
	C["pop_g"] = NG
	# MeadowP9 の株（0.5 m セル）
	var mg := {}
	for q in meadow_pts:
		var k := Vector2i(floori(q.x * 2.0), floori(q.y * 2.0))
		mg[k] = int(mg.get(k, 0)) + 1
	C["meadow"] = mg
	C["meadow_n"] = meadow_pts.size()
	# 背戸の通り道（裏の壁の中央から外へ 2.0 m・幅 1.2 m）：表＝道路へ向く側（az）
	var back: Array = []
	for b: Dictionary in C["bld"]:
		if String(b["kind"]) != "machiya":
			continue
		var o: Vector2 = b["o"]
		var az: Vector2 = b["az"]
		var ax: Vector2 = b["ax"]
		var c0 := o - az * (float(b["d"]) * 0.5)
		back.append(PackedVector2Array([c0 - ax * 0.6, c0 + ax * 0.6, c0 + ax * 0.6 - az * 2.0, c0 - ax * 0.6 - az * 2.0]))
	C["backdoor"] = back
	C["ms"] = Time.get_ticks_msec() - t0
	return C


static func meadow_in(C: Dictionary, r: Rect2) -> int:
	var g: Dictionary = C["meadow"]
	var n := 0
	for i in range(floori(r.position.x * 2.0), floori(r.end.x * 2.0) + 1):
		for j in range(floori(r.position.y * 2.0), floori(r.end.y * 2.0) + 1):
			n += int(g.get(Vector2i(i, j), 0))
	return n


static func _hit_grid(G: Grid, q: Vector2) -> bool:
	for r in G.at(q):
		if (r as Rect2).has_point(q):
			return true
	return false


## 置けない理由（"" なら置ける）
static func why(C: Dictionary, it: Dictionary, items: Array, check_scope := true) -> String:
	var poly := corners(C, it)
	if check_scope and it.has("pilot") and not (PILOTS[String(it["pilot"])] as Rect2).encloses(Rect2(poly[0], Vector2.ZERO).expand(poly[1]).expand(poly[2]).expand(poly[3])):
		return "scope"
	var S: RLib.TriSampler = C["S"]
	var WS: RLib.TriSampler = C["WS"]
	var RBS: RLib.TriSampler = C["RBS"]
	var P8: RLib.TriSampler = C["P8"]
	for q in samples(poly):
		var sh := S.h(q.x, q.y)
		if is_nan(sh):
			return "terrain"
		if not is_nan((C["R"] as RLib.TriSampler).h(q.x, q.y)):
			return "road"
		if not is_nan((C["F"] as RLib.TriSampler).h(q.x, q.y)):
			return "frontage"
		for b: Dictionary in C["bld"]:
			if (b["o"] as Vector2).distance_to(q) < 14.0 and SL.obb_d(b, q) < BLD_PAD:
				return "building"
		for o in [Vector2.ZERO, Vector2(0.8, 0), Vector2(-0.8, 0), Vector2(0, 0.8), Vector2(0, -0.8)]:
			var p: Vector2 = q + o
			var wh := WS.h(p.x, p.y)
			if not is_nan(wh) and wh > S.h(p.x, p.y) - 0.02:
				return "water"
		var rh := RBS.h(q.x, q.y)
		if not is_nan(rh) and rh > sh + 0.03:
			return "p7"
		if (C["bridges"] as Array).any(func(r: Rect2) -> bool: return r.has_point(q)):
			return "bridge"
		if _hit_grid(C["hero_g"], q):
			return "hero"
		for o in [Vector2.ZERO, Vector2(0.4, 0), Vector2(-0.4, 0), Vector2(0, 0.4), Vector2(0, -0.4)]:
			if not is_nan(P8.h(q.x + o.x, q.y + o.y)):
				return "p8"
		if _hit_grid(C["sealed_g"], q):
			return "sealed"
		for t: Vector2 in C["trunks"]:
			if t.distance_to(q) < 0.6:
				return "trunk"
		if _hit_grid(C["env_g"], q):
			return "env"
		if _hit_grid(C["p10_g"], q):
			return "p10"
		if _hit_grid(C["pop_g"], q):
			return "npc"
		for t: Vector2 in C["npc"]:
			if t.distance_to(q) < NPC_PAD:
				return "npc"
		for pts: PackedVector2Array in C["npc_paths"]:
			for k in range(1, pts.size()):
				if Geometry2D.get_closest_point_to_segment(q, pts[k - 1], pts[k]).distance_to(q) < PATROL_PAD:
					return "npc"
		for a: Vector2 in C["env_anchor"]:
			if a.distance_to(q) < ENV_ANCHOR_PAD:
				return "env"
	for bp: PackedVector2Array in C["backdoor"]:
		if (bp[0] as Vector2).distance_to(it["p"]) < 12.0 and not Geometry2D.intersect_polygons(poly, bp).is_empty():
			return "backdoor"
	for b: Dictionary in C["bld"]:
		if (b["o"] as Vector2).distance_to(it["p"]) < 14.0 and not Geometry2D.intersect_polygons(poly, SL.door_poly(b)).is_empty():
			return "door"
	for m: Dictionary in C["market"]:
		if (m["p"] as Vector2).distance_to(it["p"]) < 8.0 and not Geometry2D.intersect_polygons(poly, SL.MK.corners(m)).is_empty():
			return "p10"
	if meadow_in(C, aabb2(C, it).grow(MEADOW_PAD)) > 0:
		return "meadow"
	for o: Dictionary in items:
		if o == it or (o["p"] as Vector2).distance_to(it["p"]) > 8.0:
			continue
		if not Geometry2D.intersect_polygons(poly, corners(C, o)).is_empty():
			return "overlap:" + String(o["id"])
	return ""


static func relief(C: Dictionary, it: Dictionary) -> float:
	var hs: Array = [top_h(C, it["p"])]
	for q in corners(C, it):
		hs.append(top_h(C, q))
	return float(hs.max()) - float(hs.min())


static func ground(C: Dictionary, it: Dictionary) -> void:
	var hs: Array = [top_h(C, it["p"])]
	for q in corners(C, it):
		hs.append(top_h(C, q))
	it["y"] = hs.min()


static func item(C: Dictionary, id: String, p: Vector2, face: Vector2, meta: Dictionary) -> Dictionary:
	var it := {"id": id, "p": p, "yaw": yaw_to(face), "y": 0.0}
	it.merge(meta, true)
	ground(C, it)
	return it


## 中心 c のまわり（0.25 m 刻みの輪、16 方向）で平ら（起伏 ≤ 0.12）・合法な置き場所を探す
static func place(C: Dictionary, items: Array, id: String, c: Vector2, face: Vector2, meta: Dictionary, rmax := 1.25) -> Dictionary:
	var r := 0.0
	var last := ""
	while r <= rmax + 0.001:
		var n := 1 if r == 0.0 else 16
		for k in n:
			var a := TAU * k / 16.0
			var it := item(C, id, c + Vector2(cos(a), sin(a)) * r, face, meta)
			if relief(C, it) > RELIEF_MAX:
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


## frame → [中心, face, ref]（建物 frame＝裏の壁の中央・裏の外向き・ref＝壁の中央）
static func frame(C: Dictionary, cl: Dictionary) -> Array:
	var fr: Dictionary = cl["frame"]
	if fr.has("bld"):
		for b: Dictionary in C["bld"]:
			if String(b["name"]) == String(fr["bld"]):
				var c0: Vector2 = (b["o"] as Vector2) - (b["az"] as Vector2) * (float(b["d"]) * 0.5)
				return [c0, -(b["az"] as Vector2), c0]
		push_error("建物 %s なし" % fr["bld"])
		return [Vector2.ZERO, Vector2(0, 1), Vector2.ZERO]
	return [fr["p"], (fr["face"] as Vector2).normalized(), cl["ref"]]


## 設計 → 計画
static func plan(v: Node3D, meadow_pts: PackedVector2Array, des: Array = []) -> Dictionary:
	var C := context(v, meadow_pts)
	var items: Array = []
	var clusters: Array = []
	for cl: Dictionary in (des if not des.is_empty() else design()):
		var fr := frame(C, cl)
		var face: Vector2 = fr[1]
		var along := Vector2(-face.y, face.x)
		var got: Array = []
		for e: Array in cl["items"]:
			var off: Vector2 = e[1]
			var c: Vector2 = (fr[0] as Vector2) + along * off.x + face * off.y
			var f := face.rotated(deg_to_rad(float(e[2])))
			var meta := {"cluster": String(cl["id"]), "pilot": String(cl["pilot"]), "anchor": String(cl["anchor"]), "anchor_desc": String(cl["desc"]),
				"who": String(e[3]), "why": String(e[4])}
			var it := place(C, items, String(e[0]), c, f, meta, float(e[5]) if e.size() > 5 else 1.25)
			if not it.is_empty():
				got.append(it)
		clusters.append({"id": String(cl["id"]), "pilot": String(cl["pilot"]), "anchor": String(cl["anchor"]), "anchor_desc": String(cl["desc"]),
			"ref": fr[2], "bld": String(cl.get("bld", "")), "center": fr[0], "face": face, "n_design": (cl["items"] as Array).size(), "n": got.size()})
	return {"C": C, "items": items, "clusters": clusters}


## 診断：矩形を step m ごとに 0.6 m 角の探査物で試し、理由の頭文字で地図にする
static func survey(C: Dictionary, r: Rect2, step := 0.5) -> PackedStringArray:
	var out := PackedStringArray()
	var code := {"": ".", "terrain": " ", "road": "R", "frontage": "F", "building": "B", "water": "W", "p7": "w", "bridge": "b", "p8": "A",
		"sealed": "S", "trunk": "T", "hero": "H", "env": "E", "p10": "P", "npc": "N", "backdoor": "d", "door": "D", "meadow": "g", "slope": "/"}
	var nz := int(r.size.y / step)
	var nx := int(r.size.x / step)
	for j in nz + 1:
		var z := r.position.y + j * step
		var row := "%7.1f " % z
		for i in nx + 1:
			var x := r.position.x + i * step
			var it := item(C, "_probe", Vector2(x, z), Vector2(0, 1), {})
			var w := why(C, it, [], false)
			if w == "" and relief(C, it) > RELIEF_MAX:
				w = "slope"
			if w.begins_with("overlap"):
				w = ""
			row += String(code.get(w, "?"))
		out.append(row)
	return out


# ─────────────────────────── 烘焙 ───────────────────────────

static func bake(P: Dictionary) -> Node3D:
	var C: Dictionary = P["C"]
	var root := Node3D.new()
	root.name = NODE_NAME
	var groups := {}
	for pl: String in PILOTS:
		var n := Node3D.new()
		n.name = "Pilot" + pl
		n.set_meta("pilot", PILOT_NAME[pl])
		root.add_child(n)
		groups[pl] = n
	var cl_nodes := {}
	for cl: Dictionary in P["clusters"]:
		var n := Node3D.new()
		n.name = String(cl["id"])
		n.set_meta("anchor", String(cl["anchor"]))
		n.set_meta("anchor_desc", String(cl["anchor_desc"]))
		var c2: Vector2 = cl["center"]
		n.position = Vector3(c2.x, top_h(C, c2), c2.y)
		(groups[String(cl["pilot"])] as Node).add_child(n)
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
		for k in ["who", "why", "anchor", "cluster", "pilot"]:
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
		# 碰撞：腰より高い物だけ（≥ 0.35 m）、足元の箱
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


static func own(n: Node, owner: Node) -> void:
	for c in n.get_children():
		c.owner = owner
		if c.scene_file_path == "":
			own(c, owner)

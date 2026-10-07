extends RefCounted
## 人間之里 V2 P10 R1b Market West Rework（r2）：市集西通り＝「市集の第二の支街（裏通り）」。
##   r1（空き地に小屋形の店を散らした案、ichi_kit）は使用者裁定「跳蚤市場・園遊會に見える」で不採用 → 空間言語から作り直し。
##   都市の筋書き（表店／裏店）：中橫街の表店（RSW_002–004）は奥行の深い敷地の前半分だけを使っている。その後ろ半分に「裏店」が並び、
##   西小路（WestAlley）から市集（MarketP10、封存・不動）の北西角まで東西に抜ける通り（店の正面どうし 5.6 m）になる。
##   表の中橫街からは路地 3 本で入る：主の口＝RSW_004 と MKT_039 の間（4.5 m、木戸・吊り提灯・道の床）、ほか 3 m・2 m の路地。
##   建物＝P6 町家 Kit（village_v2_machiya_kit_lib.gd の build()）で組む——既存の町と同じ構件・同じ材質の店。
##     北側 6 棟（連続する店列、日の当たる側：日除け幕・陳列が厚い）／南側 4 棟（路地 2 本で 3 塊、日陰側：暖簾・提灯・看板）。
##     主＝辻の角の茶屋（總二階）と通り中ほどの呉服（總二階）、従＝厨子二階の店、静＝平屋の桶屋（仕事場）。
##   店先＝P6 R4 と同じ fr_*（石の帯＋蓋付き側溝＋店前の段）。通りの床＝P7 地面 shader（mode 0、地形と同じ材質）の踏み固め土。
##   陳列・生活物＝承認済み Kit（street_kit・market_kit・P9 R4 Hero Kit）の重用＋新 mise_kit（日除け幕・軒提灯・木戸・吊り提灯）。
##   P3 地塊・P4 建物・P6 Kit・MarketP10・StreetP10・P9 封存 overlay は不動（只讀）。地塊の形は変えない：裏店は REAR_LOTS の後ろ半分だけ。
##   Generator＝source of truth（Editor で動かさない）。overlay＝Props/MarketWestP10（gen/market_west_p10.scn）。
const SL := preload("res://tools/village_v2_street_lib.gd")
const MK := preload("res://tools/village_v2_market_lib.gd")
const RLib := preload("res://tools/village_v2_riverbank_lib.gd")
const ML := preload("res://tools/village_v2_machiya_kit_lib.gd")
const OUTPUT := "res://maps/village_v2/gen/market_west_p10.scn"
const NODE_NAME := "MarketWestP10"
const PARENT := "Props"
const LOD_SWITCH := 36.0
const KITS := {"ms_": "mise_kit", "st_": "street_kit", "mk_": "market_kit", "sk_": "school_kit", "sz_": "suzu_kit", "gd_": "geidon_kit",
	"kr_": "kiri_kit", "tk_": "tower_kit", "wk_": "waterside_kit", "gk_": "garden_kit"}
## 歩ける敷石（延段・飛石）：歩く通り・戸口・到達・碰撞の対象外（上を歩く）
const PAVE_TAG := "pave"
## ── 通り（店の正面＝牆線）
const Z_N := -47.4          # 北側の店の正面（+z 向き）
const Z_S := -41.8          # 南側の店の正面（−z 向き）
const Z_C := -44.6          # 通りの中心
const FR_D := 0.8           # 店先帯（石の帯 0.5＋蓋付き側溝 0.3）
const GUT_W := 0.30
const FR_LIFT := 0.10       # 店先帯の上面＝地形＋0.10（P6 R4 と同じ：路面と揃う）
const FLOOR_LIFT := 0.04    # 通りの床＝地形＋0.04
const OV_EAVE := 0.35
const OV_GABLE := 0.05
const EMBED := 0.3
const DEPTH_MAX := 5.5
const Z_S_BACK := -36.6     # 南側の店の背面（表店 RSW_002–004 の背面 −35.33 から 1.27 m、軒どうし 0.47 m）
## P_RSW_026（北の隣地）の南境界：北側の店は背面の軒先もこの境界から内側（BACK_MARGIN）
const P026_A := Vector2(202.92, -54.24)
const P026_B := Vector2(221.59, -52.0)
const BACK_MARGIN := 0.55
## 裏店を建てる敷地（中橫街の表店の敷地の後ろ半分）。ほかの地塊には入らない
const REAR_LOTS := ["P_RSW_002", "P_RSW_003", "P_RSW_004"]
## 店（建物）。u＝世界 x。door＝戸口（開いた店の間）の世界 x。plan＝P6 Kit の風格計畫（上書き）。trade＝商い
## r3「営業中」：tier＝focal（視覺の主：開いた店の間すべてにばったり床几＋店内の陳列＋覆い、外溢 2、提灯 2、幟）／mid（床几＋店内＋覆い、外溢 1）／
##   quiet（店内の陳列だけ、暖簾は下ろしたまま）／work（仕事場）。goods＝mise_kit の商品。cover＝日除け幕 maku_<色> か蔀 shitomi。noren＝戸口の暖簾を掀げる色
const SHOPS := [
	{"id": "MW_N1", "side": "N", "x0": 202.7, "x1": 207.2, "type": "zushi", "door": 203.7, "trade": "aramono", "corner": "w",
		"tier": "mid", "goods": "zakka", "cover": "shitomi", "noren": "ai",
		"plan": {"theme": "open", "hang": "noren_a", "sign": "side", "sign_key": "kanban", "roof": "offf", "up": "mushi", "fin": 1, "tone": 0, "his_wood": true}},
	{"id": "MW_N2", "side": "N", "x0": 207.5, "x1": 212.9, "type": "nikai", "door": 208.5, "trade": "gofuku",
		"tier": "focal", "goods": "nuno", "cover": "maku_kinari", "noren": "ai",
		"plan": {"theme": "open", "hang": "noren_d", "sign": "roof", "sign_key": "kanban_b", "roof": "std", "up": "win", "fin": 0, "tone": 1, "udatsu": 1}},
	{"id": "MW_N3", "side": "N", "x0": 213.2, "x1": 217.0, "type": "zushi", "door": 214.2, "trade": "seto",
		"tier": "mid", "goods": "seto", "cover": "maku_ai", "noren": "kinari",
		"plan": {"theme": "open", "hang": "noren_b", "sign": "", "sign_key": "kanban", "roof": "low", "up": "mushib", "fin": 2, "tone": 2}},
	{"id": "MW_N4", "side": "N", "x0": 217.3, "x1": 221.6, "type": "zushi", "door": 220.7, "trade": "kanbutsu",
		"tier": "mid", "goods": "kanbutsu", "cover": "shitomi", "noren": "beni",
		"plan": {"theme": "open", "hang": "noren_e", "sign": "side", "sign_key": "kanban_c", "roof": "offb", "up": "plain", "fin": 3, "tone": 0, "his_wood": true}},
	{"id": "MW_N5", "side": "N", "x0": 221.9, "x1": 225.6, "type": "zushi", "door": 224.8, "trade": "kashi",
		"tier": "quiet", "goods": "kashi", "cover": "", "noren": "",
		"plan": {"theme": "bengara", "hang": "noren_e", "sign": "roof", "sign_key": "kanban", "roof": "flat", "up": "mushis", "fin": 4, "tone": 1, "udatsu": 0}},
	{"id": "MW_N6", "side": "N", "x0": 225.9, "x1": 229.3, "type": "zushi", "door": 228.6, "trade": "chaya", "corner": "e",
		"tier": "focal", "goods": "cha", "cover": "maku_beni", "noren": "beni",
		"plan": {"theme": "open", "hang": "noren_c", "sign": "roof", "sign_key": "kanban_c", "roof": "offf2", "up": "mushis", "fin": 0, "tone": 0}},
	{"id": "MW_S1", "side": "S", "x0": 202.7, "x1": 207.2, "type": "zushi", "door": 206.1, "trade": "kome", "corner": "w",
		"tier": "quiet", "goods": "kome", "cover": "", "noren": "",
		"plan": {"theme": "mixed", "hang": "noren_e", "sign": "side", "sign_key": "kanban_b", "roof": "low", "up": "mushis", "fin": 2, "tone": 1}},
	{"id": "MW_S2", "side": "S", "x0": 210.6, "x1": 214.3, "type": "zushi", "door": 213.4, "trade": "yaoya",
		"tier": "mid", "goods": "yasai", "cover": "shitomi", "noren": "kinari",
		"plan": {"theme": "open", "hang": "noren_b", "sign": "", "sign_key": "kanban", "roof": "offb2", "up": "mushi", "fin": 3, "tone": 2, "his_wood": true}},
	{"id": "MW_S3", "side": "S", "x0": 214.6, "x1": 218.3, "type": "hiraya", "door": 215.6, "trade": "okeya",
		"tier": "work", "goods": "", "cover": "", "noren": "",
		"plan": {"theme": "koshib", "hang": "", "sign": "", "sign_key": "kanban", "roof": "std", "up": "", "fin": 1, "tone": 0}},
	{"id": "MW_S4", "side": "S", "x0": 220.7, "x1": 226.5, "type": "nikai", "door": 222.0, "trade": "sakaya", "corner": "e",
		"tier": "focal", "goods": "sake", "cover": "shitomi", "noren": "ai",
		"plan": {"theme": "open", "hang": "noren_a", "sign": "roof", "sign_key": "kanban_b", "roof": "lowoff", "up": "amado", "fin": 4, "tone": 2, "udatsu": 1}},
]
## 外溢（店先帯の外、壁から 0.72–1.42 m）に置く承認済み Kit の物（goods ごと；奥行 ≤ 0.7 m）
const SPILL := {"zakka": ["kr_kago", "kr_houki"], "nuno": ["ms_nuno_kake", "gd_shogi"], "seto": ["sz_dai", "mk_kanban_seto"],
	"kanbutsu": ["gd_taru", "kr_fukuro"], "cha": ["ms_endai_mousen", "mk_kanban_dango"], "yasai": ["kr_kago", "mk_kanban_yasai"],
	"sake": ["gd_taruzumi", "gd_taru"], "kome": ["st_kanban_kome"], "kashi": []}
## 開いた店の間（町家 Kit の店台のある間）・戸口の間
const OPEN_BAYS := ["shop_c", "shop_k"]
const NAKA_Y := 0.72       # 町家 Kit の店台の上面（建物の基準高から）
const SHITOMI_Y := 2.32    # 蔀の蝶番（店先の開口上端 2.25 の上）
const NOREN_Y := 2.22      # 暖簾の竿
const TYPE_EAVE := {"hiraya": 2.9, "zushi": 3.9, "nikai": 5.4}
const TYPE_HIS := {"hiraya": 0.0, "zushi": 2.7, "nikai": 2.9}
## 通りの床（P7 地面 shader mode 0）：通り・辻・市集への連絡・中橫街からの路地（主の口）・路地 2 本
const FLOOR := {
	"street": Rect2(200.9, -46.7, 29.4, 4.2),
	"junction": Rect2(226.6, -52.8, 7.4, 16.0),
	"east": Rect2(230.3, -52.8, 6.95, 2.9),
	"alley": Rect2(226.5, -36.8, 4.3, 13.8),
	"roji1": Rect2(207.45, -42.7, 2.9, 19.7),
	"roji2": Rect2(219.0, -42.7, 1.3, 19.7),
}
## 歩く通り（ここに足元を置かない）：通りの中央 3.0 m・辻から市集への連絡・中橫街の主の口の路地
const LANES := {"street_mid": Rect2(201.0, -45.95, 28.3, 2.8), "crank": Rect2(231.45, -52.6, 2.05, 4.6), "east": Rect2(231.45, -52.6, 5.8, 2.4),
	"alley": Rect2(227.3, -36.6, 2.1, 12.0)}
## 到達性：中橫街（主の口）→ 通りの西の口（西小路）・市集の西の通り・各客の立ち場
const ACCESS_FROM := Vector2(228.6, -23.6)
const ACCESS_TO := [Vector2(201.6, -44.6), Vector2(238.4, -51.5)]
## 視線：中橫街の路地（主の口）から北へ → 突き当たりに茶屋（MW_N6）の店の正面；
##       市集の北西角から斜めに → 木戸の間を抜けて通りの軸（z −44.6）まで建物に当たらない
const SIGHT_ALLEY := [Vector2(228.6, -21.0), Vector2(228.6, -60.0), "MW_N6"]
## 路地 1 から北へ：突き当たり＝呉服（focal）の店の正面
const SIGHT_ROJI := [Vector2(208.9, -21.0), Vector2(208.9, -60.0), "MW_N2"]
## 市集の北西角の視野（扇の頂点と中心方向）
const SIGHT_MARKET := [Vector2(235.2, -51.4), Vector2(226.5, -44.3)]
const SEED := 10021

static var _box := {}
static var _mans := {}


static func kit_dir(prefix: String) -> String:
	return "res://assets/village_v2/%s/" % KITS[prefix]


static func has_kit(prefix: String) -> bool:
	return FileAccess.file_exists(kit_dir(prefix) + "src/modules_blender.json")


static func mesh_dir(id: String) -> String:
	return kit_dir(id.substr(0, 3)) + "mesh/"


## 足元（半幅 x、半奥 z、高さ、奥の中心ずれ z、横の中心ずれ x）——manifest dims から。特別な足元は SPECIAL
const SPECIAL := {
	"mk_bangasa": [0.08, 0.08, 2.4, 0.0, 0.0],      # 番傘：竿だけ（傘の下に人が入る）
	"ms_geya_dango": [1.42, 0.3, 2.42, 0.85, 0.0],  # 茶屋の下屋：売り台＋前柱の帯だけ（屋根の下＝売り手の立ち場）
	"ms_geya_meshi": [1.42, 0.3, 2.42, 0.85, 0.0],
	"ms_battari": [0.85, 0.31, 1.0, 0.34, 0.0],     # ばったり床几：天板 1.7 × 0.62（壁から 0.03–0.65）
}
## 竿・柱だけが地面に触れる物（日除け幕＝前の竹竿 2 本、木戸＝柱 2 本）：局部 (x, z)、半径
const POLES := {"ms_maku": [Vector2(-1.45, 1.35), Vector2(1.45, 1.35)], "ms_kido_26": [Vector2(-1.3, 0.0), Vector2(1.3, 0.0)],
	"ms_kido_37": [Vector2(-1.85, 0.0), Vector2(1.85, 0.0)], "ms_kido_50": [Vector2(-2.5, 0.0), Vector2(2.5, 0.0)]}
const POLE_R := 0.09
## 壁・軒に掛ける物（足元なし；高さ・正面からの距離を検査）
const HUNG := ["ms_noki_chochin_aka", "ms_noki_chochin_shiro", "ms_tsuna_chochin", "ms_tsuri_kaki", "ms_tsuri_waraji", "ms_tsuri_oke", "ms_shitomi",
	"ms_noren_age_ai", "ms_noren_age_beni", "ms_noren_age_kinari"]
## 店内（町家 Kit の開いた店の間の中、店台と奥の棚）に置く物：足元なし、gate は「開いた店の間の中」を検査
const NAKA_TAG := "naka"


static func box(id: String) -> Array:
	if SPECIAL.has(id):
		return SPECIAL[id]
	if id.begins_with("ms_battari_"):
		return SPECIAL["ms_battari"]
	if _box.has(id):
		return _box[id]
	var pre := id.substr(0, 3)
	if not _mans.has(pre):
		_mans[pre] = JSON.parse_string(FileAccess.get_file_as_string(kit_dir(pre) + "src/modules_blender.json"))
	var d: Array = _mans[pre]["modules"][id]["dims"]
	var c: Array = [(float(d[3]) - float(d[0])) * 0.5, (float(d[5]) - float(d[2])) * 0.5, float(d[4]), (float(d[5]) + float(d[2])) * 0.5,
		(float(d[3]) + float(d[0])) * 0.5]
	_box[id] = c
	return c


static func pole_key(id: String) -> String:
	for k: String in POLES:
		if id.begins_with(k):
			return k
	return ""


static func yaw_to(d: Vector2) -> float:
	var n := d.normalized()
	return atan2(n.x, n.y)


static func local_to_world(it: Dictionary, l: Vector2) -> Vector2:
	var yaw: float = it["yaw"]
	var sx: float = float(it.get("sx", 1.0))
	return (it["p"] as Vector2) + Vector2(cos(yaw), -sin(yaw)) * l.x * sx + Vector2(sin(yaw), cos(yaw)) * l.y


static func corners(it: Dictionary) -> PackedVector2Array:
	var b: Array = box(String(it["id"]))
	var out := PackedVector2Array()
	for s in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		out.append(local_to_world(it, Vector2(float(b[4]) + s.x * float(b[0]), float(b[3]) + s.y * float(b[1]))))
	return out


## 足元の多角形：竿物は竿だけ、掛け物はなし、ほかは箱
static func polys(it: Dictionary) -> Array:
	var id := String(it["id"])
	if id in HUNG or String(it.get("tag", "")) == NAKA_TAG:
		return []
	var pk := pole_key(id)
	if pk != "":
		var out: Array = []
		var r := POLE_R
		for l: Vector2 in POLES[pk]:
			var c := local_to_world(it, l)
			out.append(PackedVector2Array([c + Vector2(-r, -r), c + Vector2(r, -r), c + Vector2(r, r), c + Vector2(-r, r)]))
		return out
	return [corners(it)]


# ─────────────────────────── 地面の高さ（地形・店先帯・通りの床） ───────────────────────────

static func p026_z(x: float) -> float:
	var t := (x - P026_A.x) / (P026_B.x - P026_A.x)
	return lerpf(P026_A.y, P026_B.y, t)


## 建物の footprint（世界、Rect2）
static func shop_rect(s: Dictionary) -> Rect2:
	var x0 := float(s["x0"])
	var x1 := float(s["x1"])
	if String(s["side"]) == "N":
		return Rect2(x0, Z_N - float(s["d"]), x1 - x0, float(s["d"]))
	return Rect2(x0, Z_S, x1 - x0, float(s["d"]))


## 店先帯（世界、Rect2）
static func band_rect(s: Dictionary) -> Rect2:
	var x0 := float(s["x0"])
	var x1 := float(s["x1"])
	if String(s["side"]) == "N":
		return Rect2(x0, Z_N, x1 - x0, FR_D)
	return Rect2(x0, Z_S - FR_D, x1 - x0, FR_D)


static func in_floor(p: Vector2) -> bool:
	for k: String in FLOOR:
		if (FLOOR[k] as Rect2).has_point(p):
			return true
	return false


## 見えている最上面：地形・路面・P4 院子地面＋本 overlay の店先帯（＋0.10）・通りの床（＋0.04）
static func ground_h(C: Dictionary, p: Vector2) -> float:
	var h := SL.top_h(C, p)
	for s: Dictionary in C.get("shops", []):
		if (band_rect(s) as Rect2).has_point(p):
			return maxf(h, float(s["band_h"]))
	if in_floor(p) and not (C.get("shops", []) as Array).any(func(s: Dictionary) -> bool: return (shop_rect(s) as Rect2).has_point(p)):
		return h + FLOOR_LIFT
	return h


static func item(C: Dictionary, id: String, p: Vector2, fc: Vector2, tag: String, extra := {}) -> Dictionary:
	var it := {"id": id, "p": p, "yaw": yaw_to(fc), "tag": tag, "y": 0.0}
	it.merge(extra, true)
	if id in HUNG or tag == NAKA_TAG:
		it["y"] = float(extra.get("y", 0.0))
		return it
	var hs: Array = [ground_h(C, p)]
	for poly: PackedVector2Array in polys(it):
		for q: Vector2 in poly:
			hs.append(ground_h(C, q))
	it["y"] = hs.min()
	return it


## 通り座標 → 世界：side N/S、u＝世界 x、v＝牆線から通り側への距離
static func sp(side: String, u: float, v: float) -> Vector2:
	return Vector2(u, Z_N + v) if side == "N" else Vector2(u, Z_S - v)


static func face(side: String) -> Vector2:
	return Vector2(0, 1) if side == "N" else Vector2(0, -1)


# ─────────────────────────── 建物（P6 町家 Kit を合成 rec で組む） ───────────────────────────

static func shop_recs(C: Dictionary) -> Array:
	var out: Array = []
	var S: RLib.TriSampler = C["S"]
	for s0: Dictionary in SHOPS:
		var s: Dictionary = s0.duplicate(true)
		var x0 := float(s["x0"])
		var x1 := float(s["x1"])
		var w := x1 - x0
		var d := DEPTH_MAX
		if String(s["side"]) == "N":
			var zb := -INF
			var x := x0
			while x <= x1 + 0.001:
				if x <= P026_B.x:
					zb = maxf(zb, p026_z(x) + BACK_MARGIN)
				x += 0.25
			if zb > -INF:
				d = minf(d, Z_N - zb)
		else:
			d = Z_S_BACK - Z_S
		d = snappedf(d, 0.01)
		s["d"] = d
		var r := shop_rect(s)
		var lo := INF
		var hi := -INF
		var xx := r.position.x
		while xx <= r.end.x + 0.001:
			var zz := r.position.y
			while zz <= r.end.y + 0.001:
				var h := S.h(xx, zz)
				lo = minf(lo, h)
				hi = maxf(hi, h)
				zz += 0.5
			xx += 0.5
		var typ := String(s["type"])
		var eave := float(TYPE_EAVE[typ])
		var cx := (x0 + x1) * 0.5
		var cz := r.get_center().y
		var n := String(s["side"]) == "N"
		var dlx := float(s["door"]) - cx if n else -(float(s["door"]) - cx)
		s["rec"] = {"id": String(s["id"]), "kind": "machiya", "type": typ, "roof": "hira", "width_m": w, "depth_m": d, "eave_m": eave,
			"ridge_m": eave + 0.45 * d * 0.5, "ground_lo": lo, "base_h": hi, "door_local_x": dlx, "hisashi_m": float(TYPE_HIS[typ]),
			"hisashi_depth_m": 0.45 if float(TYPE_HIS[typ]) > 0.0 else 0.0, "ov_eave_m": OV_EAVE, "ov_gable_m": OV_GABLE, "plinth_m": 0.32,
			"pitch": 0.45, "district": "Market", "road": "MarketWestLane"}
		s["xf"] = Transform3D(Basis(Vector3.UP, 0.0 if n else PI), Vector3(cx, hi, cz))
		s["base_h"] = hi
		s["ground_lo"] = lo
		# 店先帯の上面：帯の牆線・中・外縁の地形の最高＋FR_LIFT（P6 R4 と同じ考え方、建物ごとに一定）
		var br := band_rect(s)
		var bh := -INF
		var bx := br.position.x
		while bx <= br.end.x + 0.001:
			for bz in [br.position.y + 0.02, br.get_center().y, br.end.y - 0.02]:
				bh = maxf(bh, SL.top_h(C, Vector2(bx, bz)))
			bx += 0.5
		s["band_h"] = bh + FR_LIFT
		out.append(s)
	return out


## 店の開間（世界 x、西→東）：[{kind, u0, u1}]——町家 Kit を一度組んで bay_x／bay_kind を読む
static func bays_world(s: Dictionary, lib: Dictionary) -> Array:
	var kit := ML.build(s["rec"], lib, EMBED)
	var xs: Array = kit.get_meta("bay_x")
	var kinds: Array = kit.get_meta("bay_kind")
	kit.free()
	var n := String(s["side"]) == "N"
	var cx := (float(s["x0"]) + float(s["x1"])) * 0.5
	var out: Array = []
	for i in kinds.size():
		var a := cx + float(xs[i]) if n else cx - float(xs[i])
		var b := cx + float(xs[i + 1]) if n else cx - float(xs[i + 1])
		out.append({"kind": String(kinds[i]), "u0": minf(a, b), "u1": maxf(a, b), "i": i})
	out.sort_custom(func(p: Dictionary, q: Dictionary) -> bool: return float(p["u0"]) < float(q["u0"]))
	return out


## P6 Kit の風格計畫：既存の店の計畫を雛形にして上書き（corner は世界の西・東 → 局部 ±x）
static func plan_inject(s: Dictionary) -> void:
	if ML._plan.is_empty():
		ML.plan_for({"id": "B_P_MKT_023"})
	var base: Dictionary = (ML._plan["B_P_MKT_023"] as Dictionary).duplicate(true)
	for k: String in ["corner", "udh", "gyo"]:
		base[k] = []
	base.merge({"hero": false, "district": "Market", "dormer": false, "kemuri": false, "sb": false, "rec": "none", "rec_d": 0.0, "split": false,
		"udatsu": -1, "his_wood": false, "kiri": false, "inuyarai": false, "ridge_low": false, "oni_b": false, "cut": false, "up_period": 0}, true)
	base.merge(s["plan"], true)
	var c := String(s.get("corner", ""))
	if c != "":
		var west := -1.0 if String(s["side"]) == "N" else 1.0
		base["corner"] = [west if c == "w" else -west]
	ML._plan[String(s["id"])] = base


# ─────────────────────────── 規劃 ───────────────────────────

static func plan(v: Node3D) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var C := SL.context(v)
	var shops := shop_recs(C)
	C["shops"] = shops
	for s: Dictionary in shops:
		plan_inject(s)
	var items: Array = []
	var anchors: Array = []
	var lights: Array = []          # 店の灯：開いた店の間の奥（壁線から −0.35、高 1.95）の暖色の灯り
	var add := func(id: String, p: Vector2, fc: Vector2, tag: String, extra := {}) -> Dictionary:
		if not has_kit(id.substr(0, 3)):
			return {}
		var it := item(C, id, p, fc, tag, extra)
		items.append(it)
		return it
	var A := func(id: String, act: String, p: Vector2, fc: Vector2, ref: String) -> void:
		anchors.append({"id": id, "activity": act, "p": p, "yaw": yaw_to(fc), "ref": ref})
	# ── 店先（商いごと；N＝日の当たる側：陳列が厚い・日除け幕、S＝日陰側：暖簾・看板・提灯・吊るし物）。
	#    帯 v 0–0.8＝石の帯；陳列は v ≤ 1.45（北）／1.35（南）、戸口（開いた店の間）の前 ±0.55・1.2 m は空ける（gate W10／W11）
	var bh := func(sid: String) -> float:
		for s: Dictionary in shops:
			if String(s["id"]) == sid:
				return float(s["base_h"])
		return 0.0
	var his := func(sid: String) -> float:
		for s: Dictionary in shops:
			if String(s["id"]) == sid:
				var hm := float(s["rec"]["hisashi_m"])
				return hm if hm > 0.0 else 2.75      # 平屋：軒（2.9）の下
		return 2.7
	var lamp := func(sid: String, sd: String, u: float, col: String) -> void:
		add.call("ms_noki_chochin_" + col, sp(sd, u, 0.0), face(sd), "wall", {"shop": sid, "y": float(bh.call(sid)) + float(his.call(sid)) - 0.3})
	var tsuri := func(sid: String, sd: String, u: float, kind: String) -> void:
		add.call("ms_tsuri_" + kind, sp(sd, u, 0.0), face(sd), "wall", {"shop": sid, "y": float(bh.call(sid)) + float(his.call(sid)) - 0.12})
	var awn := func(sid: String, sd: String, u: float, col: String, sx: float) -> void:
		add.call("ms_maku_" + col, sp(sd, u, 0.0), face(sd), "awn", {"shop": sid, "sx": sx, "sy": (float(his.call(sid)) - 0.2) / 2.5})
	# ── r3「営業中」：開いた店の間ごとに 店内の陳列（店台＋奥の棚）・ばったり床几（店先 0–0.65 m）・覆い（蔀／日除け幕）、戸口の暖簾を掀げる、
	#    外溢（0.72–1.42 m）。tier で主次：focal＞mid＞quiet（店内だけ）。開間は町家 Kit の bay_x／bay_kind（bays_world）から
	var klib := ML.load_lib()
	for s: Dictionary in shops:
		s["bays"] = bays_world(s, klib)
	for s: Dictionary in shops:
		var sid := String(s["id"])
		var sd := String(s["side"])
		var tier := String(s["tier"])
		if tier == "work":
			continue
		var g := String(s["goods"])
		var bays: Array = s["bays"]
		var disp: Array = bays.filter(func(b: Dictionary) -> bool: return String(b["kind"]) in OPEN_BAYS)
		if tier == "quiet":
			disp = disp.slice(0, 1)
		var vmax := 1.42 if sd == "N" else 1.32
		for b: Dictionary in disp:
			var u := (float(b["u0"]) + float(b["u1"])) * 0.5
			var bw := float(b["u1"]) - float(b["u0"])
			add.call("ms_naka_" + g, sp(sd, u, 0.0), face(sd), NAKA_TAG, {"shop": sid, "y": float(s["base_h"]), "sx": minf(bw / 1.8, 1.12)})
			if tier == "quiet":
				continue
			add.call("ms_battari_" + g, sp(sd, u, 0.0), face(sd), "disp", {"shop": sid, "sx": minf((bw - 0.12) / 1.7, 1.12)})
			if String(s["cover"]) == "shitomi":
				add.call("ms_shitomi", sp(sd, u, 0.0), face(sd), "wall", {"shop": sid, "y": float(s["base_h"]) + SHITOMI_Y, "sx": minf(bw / 1.8, 1.12)})
		if tier != "quiet" and String(s["noren"]) != "":
			for b: Dictionary in bays.filter(func(b2: Dictionary) -> bool: return String(b2["kind"]) == "shop_o"):
				var bw := float(b["u1"]) - float(b["u0"])
				var uc := (float(b["u0"]) + float(b["u1"])) * 0.5
				add.call("ms_noren_age_" + String(s["noren"]), sp(sd, uc, 0.0), face(sd), "wall",
					{"shop": sid, "y": float(s["base_h"]) + NOREN_Y, "sx": minf(bw / 1.8, 1.12)})
				add.call("ms_tana_" + g, sp(sd, uc, 0.0), face(sd), NAKA_TAG, {"shop": sid, "y": float(s["base_h"]), "sx": minf(bw / 1.8, 1.12)})
				lights.append({"p": sp(sd, uc, -0.35), "y": float(s["base_h"]) + 1.95, "shop": sid})
				s["noren_up"] = [float(b["u0"]), float(b["u1"])]
		if tier != "quiet":
			for b: Dictionary in disp:
				lights.append({"p": sp(sd, (float(b["u0"]) + float(b["u1"])) * 0.5, -0.35), "y": float(s["base_h"]) + 1.95, "shop": sid})
		if tier != "quiet" and String(s["cover"]).begins_with("maku_") and not disp.is_empty():
			var a0 := float(disp[0]["u0"])
			var a1 := float(disp[disp.size() - 1]["u1"])
			add.call("ms_" + String(s["cover"]), sp(sd, (a0 + a1) * 0.5, 0.0), face(sd), "awn",
				{"shop": sid, "sx": clampf((a1 - a0 + 0.1) / 3.0, 0.6, 1.25), "sy": (float(his.call(sid)) - 0.2) / 2.5})
		# 外溢：開いた店の間の前（0.67 m から＝ばったり床几の先）に、focal 2・mid 1
		var pool: Array = SPILL.get(g, [])
		var nsp := 2 if tier == "focal" else (1 if tier == "mid" else 0)
		var k := 0
		for b: Dictionary in disp:
			if k >= nsp or k >= pool.size():
				break
			var id := String(pool[k])
			var bx: Array = box(id)
			var v0 := 0.67 - (float(bx[3]) - float(bx[1]))
			if v0 + float(bx[3]) + float(bx[1]) > vmax:
				k += 1
				continue
			var u := (float(b["u0"]) + float(b["u1"])) * 0.5 - float(bx[4]) * (1.0 if sd == "N" else -1.0)
			add.call(id, sp(sd, u, v0), face(sd), "disp", {"shop": sid})
			k += 1
	# ── 店ごとの補い（開間の実測 u、bays_world の印字で確認）：提灯は focal 2・mid 1、quiet は小さな陳列か看板ひとつ
	lamp.call("MW_N1", "N", 206.75, "shiro")
	add.call("kr_houki", sp("N", 206.45, 0.45), face("N"), "disp", {"shop": "MW_N1"})
	add.call("kr_kago", sp("N", 206.95, 0.3), face("N"), "disp", {"shop": "MW_N1"})
	lamp.call("MW_N2", "N", 207.7, "aka")
	lamp.call("MW_N2", "N", 212.75, "aka")
	lamp.call("MW_N3", "N", 213.35, "shiro")
	lamp.call("MW_N4", "N", 217.7, "aka")
	add.call("wk_tawara3", sp("N", 217.73, 0.5), face("N"), "disp", {"shop": "MW_N4"})
	add.call("st_hiradai_kashi", sp("N", 222.83, 0.33), face("N"), "disp", {"shop": "MW_N5"})
	lamp.call("MW_N6", "N", 226.0, "aka")
	lamp.call("MW_N6", "N", 229.15, "aka")
	add.call("mk_bangasa", Vector2(231.0, -46.9), face("N"), "disp", {"shop": "MW_N6"})
	add.call("ms_endai_mousen", Vector2(230.6, -46.3), Vector2(0, -1), "disp", {"shop": "MW_N6"})
	add.call("mk_nobori_cha", Vector2(229.55, -47.15), face("N"), "sign", {"shop": "MW_N6"})
	add.call("ms_geya_dango", Vector2(229.3, -51.45), Vector2(1, 0), "disp", {"shop": "MW_N6"})
	add.call("st_kanban_kome", sp("S", 203.15, 0.32), face("S"), "sign", {"shop": "MW_S1"})
	lamp.call("MW_S1", "S", 203.15, "shiro")
	lamp.call("MW_S2", "S", 210.75, "shiro")
	add.call("tk_okeyama", sp("S", 216.75, 0.4), face("S"), "work", {"shop": "MW_S3"})
	add.call("sk_teoke", sp("S", 217.8, 0.35), face("S"), "work", {"shop": "MW_S3"})
	add.call("kr_okeyama", sp("S", 217.75, 0.95), face("S"), "work", {"shop": "MW_S3"})
	tsuri.call("MW_S3", "S", 217.3, "oke")
	lamp.call("MW_S4", "S", 220.85, "aka")
	lamp.call("MW_S4", "S", 226.35, "aka")
	# 酒屋の東の妻（主の口の路地に面する）へ回り込む外溢：樽 2・衝立看板・幟——路地を歩くと「角の先に店がある」
	add.call("gd_taru", Vector2(226.85, -39.3), Vector2(1, 0), "disp", {"shop": "MW_S4"})
	add.call("gd_taru", Vector2(226.85, -38.55), Vector2(1, 0), "disp", {"shop": "MW_S4"})
	add.call("st_kanban_sake", Vector2(226.85, -37.45), Vector2(1, 0), "sign", {"shop": "MW_S4"})
	add.call("st_nobori_sake", Vector2(226.8, -40.45), Vector2(1, 0), "sign", {"shop": "MW_S4"})
	# ── 通りを渡す吊り提灯（N3 と S2 の 2F の壁どうし、3.3 m；綱の長さ＝店の正面どうし 5.6 m）
	for ux: Array in [[205.0, "MW_N1"], [213.75, "MW_N3"], [221.15, "MW_N4"], [226.2, "MW_N6"]]:
		add.call("ms_tsuna_chochin", Vector2(float(ux[0]), Z_C), Vector2(1, 0), "over", {"y": float(bh.call(String(ux[1]))) + 3.3, "sx": (Z_S - Z_N) / 4.4})
	# 路地 1（中橫街 → 呉服の正面）：口と中ほどに吊り提灯（RSW_002 の東壁 206.95 と RSW_003 の西壁 210.85 の間）
	for zr: float in [-25.7, -31.6]:
		add.call("ms_tsuna_chochin", Vector2(208.9, zr), Vector2(0, 1), "over", {"y": SL.top_h(C, Vector2(208.9, zr)) + 3.05, "sx": 3.9 / 4.4})
	add.call("ms_tsuna_chochin", Vector2(208.9, -38.0), Vector2(0, 1), "over", {"y": SL.top_h(C, Vector2(208.9, -38.0)) + 3.05, "sx": 3.4 / 4.4})
	# 路地 1 の口の誘い：RSW_003 の西の側壁の前に八百屋の出店（ばったり床几＋籠＋幟）——口から入ってすぐ「売っている」
	add.call("ms_battari_yasai", Vector2(210.55, -27.2), Vector2(-1, 0), "disp", {"shop": "roji"})
	add.call("kr_kago", Vector2(210.25, -28.7), Vector2(-1, 0), "disp", {"shop": "roji"})
	add.call("mk_nobori_yasai", Vector2(209.8, -25.4), Vector2(0, 1), "sign", {"shop": "roji"})
	# 主の口の路地の 2 本目（RSW_004 の東壁 226.35 と MKT_039 の西壁 230.9 の間）
	add.call("ms_tsuna_chochin", Vector2(228.625, -33.6), Vector2(0, 1), "over", {"y": SL.top_h(C, Vector2(228.6, -33.6)) + 3.05, "sx": 4.55 / 4.4})
	# ── 入口：主の口（中橫街の路地）に木戸「市 この奥」＋吊り提灯、西の口（西小路）に木戸（藍の水引幕）、路地 1 の口に道標
	add.call("ms_kido_37", Vector2(228.6, -24.9), Vector2(0, 1), "entr")
	add.call("ms_tsuna_chochin", Vector2(228.63, -30.2), Vector2(0, 1), "over", {"y": SL.top_h(C, Vector2(228.63, -30.2)) + 3.05, "sx": 4.5 / 4.4})
	add.call("ms_kido_50", Vector2(202.3, Z_C), Vector2(-1, 0), "entr")
	add.call("st_fuda_ichi", Vector2(207.5, -24.75), Vector2(0, 1), "entr")
	# 市集の北西角からの視線：木戸は置かない（r2 で視線を塞いだ）。辻の北東に だんご の置き看板（市集の方を向く）
	add.call("mk_kanban_dango", Vector2(230.4, -47.7), Vector2(0.8, -0.6), "sign", {"shop": "MW_N6"})
	# 主の口の路地に石の延段（木戸の内から辻まで；手入れされた道＝奥に何かある）、路地 1 に飛石
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	for i in 9:
		var z := -25.6 - 1.27 * i
		add.call("gk_nobe_" + ["a", "b", "c"][i % 3], Vector2(228.3 + rng.randf_range(-0.06, 0.06), z), Vector2(sin(rng.randf_range(-0.05, 0.05)), 1.0),
			PAVE_TAG)
	var zt := -25.2
	var k := 0
	while zt > -41.8:
		add.call("gk_tobi_" + ["a", "b", "c", "d"][k % 4], Vector2(208.8 + rng.randf_range(-0.14, 0.14), zt), Vector2(sin(rng.randf() * TAU), cos(rng.randf() * TAU)),
			PAVE_TAG)
		zt -= rng.randf_range(0.86, 1.02)
		k += 1
	# 主の口の路地：MKT_039 の妻壁に一膳飯の下屋＋行灯「めし」（路地を「店の並ぶ道」にする）
	add.call("ms_geya_meshi", Vector2(230.9, -29.6), Vector2(-1, 0), "disp", {"shop": "alley"})
	add.call("st_andon_meshi", Vector2(229.65, -31.5), Vector2(-1, 0), "sign", {"shop": "alley"})
	add.call("mk_nobori_ichi", Vector2(226.75, -25.6), Vector2(0, 1), "sign", {"shop": "alley"})
	add.call("st_hiradai_kashi", Vector2(226.95, -27.9), Vector2(1, 0), "disp", {"shop": "alley"})
	add.call("ms_endai_mousen", Vector2(230.0, -33.0), Vector2(-1, 0), "disp", {"shop": "alley"})
	# 交易・補充の痕跡：辻に届いた荷（木箱・俵・菰包み）
	add.call("mk_tsumini", Vector2(232.9, -44.2), Vector2(-1, 0), "back")
	# ── 後場（北側の店の裏・市集の北西角から見える）：井戸・薪・天水桶・箱・干し棚
	add.call("st_ido", Vector2(226.6, -55.9), Vector2(1, 0), "back")
	add.call("sk_woodpile", Vector2(223.75, -53.45), Vector2(0, -1), "back")
	add.call("sk_tensui", Vector2(229.75, -53.35), Vector2(0, -1), "back")
	add.call("kr_hakozumi", Vector2(228.3, -53.5), Vector2(0, -1), "back")
	add.call("kr_hoshidana", Vector2(223.6, -56.4), Vector2(0, -1), "back")
	add.call("sk_tensui", Vector2(219.75, -38.5), Vector2(1, 0), "back")
	# 下屋（茶屋 だんご・一膳飯 めし）の灯：片流れ屋根の下（売り台の上）
	for it: Dictionary in items:
		if String(it["id"]).begins_with("ms_geya_"):
			lights.append({"p": local_to_world(it, Vector2(0.0, 0.6)), "y": float(it["y"]) + 1.85, "shop": String(it.get("shop", "")), "geya": true})
	# ── NPC activity anchors（R3 用）：店ごとに売り手＋客、仕事・休む・運ぶ・水汲み・行き交う
	for s: Dictionary in shops:
		var sd := String(s["side"])
		var du := float(s["door"])
		var nm := String(s["id"]).to_lower()
		if String(s["trade"]) == "okeya":
			A.call(nm + "_work", "work_craft", sp(sd, 216.75, 1.05), face(sd), s["id"])
			A.call(nm + "_customer", "customer_browse", sp(sd, 217.6, 1.9), -face(sd), s["id"])
			continue
		A.call(nm + "_vendor", "vendor_stand", sp(sd, du, 0.45), face(sd), s["id"])
		var mid := (float(s["x0"]) + float(s["x1"])) * 0.5
		var cu := mid + (0.6 if du < mid else -0.6)
		A.call(nm + "_customer", "customer_browse", sp(sd, cu, 2.0), -face(sd), s["id"])
	A.call("mw_tea_sit_a", "sit_tea", sp("N", 226.4, 1.45), face("N"), "MW_N6")
	A.call("mw_tea_sit_b", "sit_tea", sp("N", 227.6, 1.45), face("N"), "MW_N6")
	A.call("mw_dango_vendor", "vendor_stand", Vector2(229.75, -51.45), Vector2(1, 0), "ms_geya_dango")
	A.call("mw_dango_customer", "customer_buy", Vector2(230.95, -51.9), Vector2(-1, 0), "ms_geya_dango")
	A.call("mw_meshi_vendor", "vendor_stand", Vector2(230.45, -29.6), Vector2(-1, 0), "ms_geya_meshi")
	A.call("mw_meshi_customer", "customer_buy", Vector2(228.9, -29.0), Vector2(1, 0), "ms_geya_meshi")
	A.call("mw_porter_crank", "porter_carry", Vector2(232.0, -49.9), Vector2(0, -1), "")
	A.call("mw_well", "draw_water", Vector2(226.4, -54.5), Vector2(0, -1), "st_ido")
	A.call("mw_walker_a", "walk", Vector2(212.6, -44.5), Vector2(1, 0), "")
	A.call("mw_walker_b", "walk", Vector2(220.0, -44.8), Vector2(-1, 0), "")
	A.call("mw_walker_alley", "walk", Vector2(228.2, -27.0), Vector2(0, -1), "")
	A.call("mw_walker_roji", "walk", Vector2(208.8, -33.0), Vector2(0, -1), "")
	# 床の材質（地形と同じ P7 ground shader の複製を mode 0 で）
	var fm: Material = null
	for mi in v.get_node("Terrain").find_children("*", "MeshInstance3D", true, false):
		var g := mi as MeshInstance3D
		var m: Material = g.material_override if g.material_override != null else (g.mesh.surface_get_material(0) if g.mesh != null and g.mesh.get_surface_count() > 0 else null)
		if m is ShaderMaterial and (m as ShaderMaterial).shader != null and (m as ShaderMaterial).shader.resource_path.ends_with("ground/ground.gdshader"):
			fm = m
			break
	return {"items": items, "anchors": anchors, "lights": lights, "shops": shops, "C": C, "floor_mat": fm, "ms": Time.get_ticks_msec() - t0}


# ─────────────────────────── 通りの床（P7 ground shader mode 0：COLOR＝trodden,gravel,mud,rock；UV＝forest,farm；UV2＝wet,street） ───────────────────────────

const F_STEP := 0.4


static func _nz(p: Vector2, a: float) -> float:
	return 0.5 + 0.35 * sin(p.x * 0.83 * a + p.y * 0.37) * sin(p.y * 0.71 * a - p.x * 0.29) + 0.15 * sin(p.x * 2.3 * a - p.y * 1.9)


## [trodden, gravel, mud, rock, wet, street]
static func floor_w(P: Dictionary, p: Vector2) -> Array:
	var n1 := _nz(p, 1.0)
	var n2 := _nz(p * 2.3 + Vector2(17.0, 5.0), 1.3)
	var roji := (FLOOR["roji1"] as Rect2).has_point(p) or (FLOOR["roji2"] as Rect2).has_point(p)
	# ground.gdshader mode 0 は重みに雑音の擾動（a·(1−a)）を掛け、合計の不足分を草で埋める → 通りの芯は street＝1.0（擾動 0）で草を出さない。
	#   trodden・gravel は高さ混合で斑に出る（合計 > 1 は可、草＝max(1−合計, 0)）。路地は踏み固め土が主で縁に草が少し残る。
	var st := 0.7 if roji else 1.0
	var tr := 0.6 if roji else 0.32 + 0.2 * (n1 - 0.5)
	var gv := 0.06 + 0.1 * maxf(0.0, n2 - 0.6)
	var wet := 0.0
	# 店先帯の外縁（雨落ち・側溝の前）：砂利と湿り
	var db := INF
	for s: Dictionary in P["shops"]:
		var br: Rect2 = band_rect(s)
		var dz := (p.y - br.end.y) if String(s["side"]) == "N" else (br.position.y - p.y)
		if p.x > br.position.x - 0.3 and p.x < br.end.x + 0.3 and dz > -0.2:
			db = minf(db, dz)
	if db < 0.7:
		var k := 1.0 - db / 0.7
		gv += 0.3 * k
		wet += 0.22 * k * n2
	return [clampf(tr, 0.0, 1.0), clampf(gv, 0.0, 1.0), 0.0, 0.0, clampf(wet, 0.0, 1.0), clampf(st, 0.0, 1.0)]


static func floor_ok(P: Dictionary, p: Vector2) -> bool:
	if not in_floor(p):
		return false
	var C: Dictionary = P["C"]
	for s: Dictionary in P["shops"]:
		if (shop_rect(s) as Rect2).grow(-0.05).has_point(p):
			return false
	for b: Dictionary in C["bld"]:
		if (b["o"] as Vector2).distance_to(p) < 12.0 and SL.obb_d(b, p) < -0.05:
			return false
	if is_nan((C["S"] as RLib.TriSampler).h(p.x, p.y)):
		return false
	# 道路（中橫街・西小路）の面の上には重ねない（路面の方が高い）
	if not is_nan((C["R"] as RLib.TriSampler).h(p.x, p.y)):
		return false
	return true


## 床の各格子點から「開いた地面」（床の外で、道路・建物・店先帯でもない所）までの距離（m、BFS）
static func floor_edge_dist(P: Dictionary, bb: Rect2, nx: int, nz: int) -> Dictionary:
	var C: Dictionary = P["C"]
	var inside := {}
	var queue: Array = []
	var dist := {}
	for i in range(-1, nx + 1):
		for j in range(-1, nz + 1):
			var p := bb.position + Vector2(i * F_STEP, j * F_STEP)
			if i >= 0 and j >= 0 and i < nx and j < nz and floor_ok(P, p):
				inside[Vector2i(i, j)] = true
				continue
			var solid := not is_nan((C["R"] as RLib.TriSampler).h(p.x, p.y))
			for s: Dictionary in P["shops"]:
				solid = solid or (shop_rect(s) as Rect2).has_point(p) or (band_rect(s) as Rect2).has_point(p)
			if not solid:
				for b: Dictionary in C["bld"]:
					if (b["o"] as Vector2).distance_to(p) < 12.0 and SL.obb_d(b, p) < 0.35:
						solid = true
						break
			if not solid:
				dist[Vector2i(i, j)] = 0.0
				queue.append(Vector2i(i, j))
	var qi := 0
	while qi < queue.size():
		var c: Vector2i = queue[qi]
		qi += 1
		var dc := float(dist[c])
		if dc > 1.3:
			continue
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if inside.has(n) and not dist.has(n):
				dist[n] = dc + F_STEP
				queue.append(n)
	return dist


static func floor_region(p: Vector2) -> String:
	for k: String in FLOOR:
		if (FLOOR[k] as Rect2).has_point(p):
			return k
	return ""


static func floor_mesh(P: Dictionary, only := "") -> ArrayMesh:
	var C: Dictionary = P["C"]
	var S: RLib.TriSampler = C["S"]
	var bb := Rect2()
	var first := true
	for k: String in FLOOR:
		bb = FLOOR[k] if first else bb.merge(FLOOR[k])
		first = false
	var nx := int(ceil(bb.size.x / F_STEP)) + 1
	var nz := int(ceil(bb.size.y / F_STEP)) + 1
	var idx := {}
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var dist := floor_edge_dist(P, bb, nx, nz)
	for i in nx:
		for j in nz:
			var p := bb.position + Vector2(i * F_STEP, j * F_STEP)
			if not floor_ok(P, p):
				continue
			var w := floor_w(P, p)
			# 開いた地面（床の外・道路でも建物でもない）に向かって 1.2 m で淡出：重み × 0.25→1（殘餘＝草層、地形の草と同じ層）
			var f := clampf(0.25 + 0.75 * float(dist.get(Vector2i(i, j), 99.0)) / 1.2, 0.25, 1.0)
			for k in 4:
				w[k] = float(w[k]) * f
			w[5] = float(w[5]) * f
			idx[Vector2i(i, j)] = verts.size()
			verts.append(Vector3(p.x, SL.top_h(C, p) + FLOOR_LIFT, p.y))
			cols.append(Color(w[0], w[1], w[2], w[3]))
			uv.append(Vector2.ZERO)
			uv2.append(Vector2(w[4], w[5]))
	var ind := PackedInt32Array()
	for i in nx - 1:
		for j in nz - 1:
			var a: Variant = idx.get(Vector2i(i, j))
			var b: Variant = idx.get(Vector2i(i + 1, j))
			var c: Variant = idx.get(Vector2i(i + 1, j + 1))
			var d: Variant = idx.get(Vector2i(i, j + 1))
			var cen := bb.position + Vector2((i + 0.5) * F_STEP, (j + 0.5) * F_STEP)
			if only != "" and floor_region(cen) != only:
				continue
			if a != null and b != null and c != null:
				ind.append_array([a, b, c])
			if a != null and c != null and d != null:
				ind.append_array([a, c, d])
	var nrm := PackedVector3Array()
	nrm.resize(verts.size())
	nrm.fill(Vector3.UP)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = nrm
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_TEX_UV2] = uv2
	arr[Mesh.ARRAY_INDEX] = ind
	var m := ArrayMesh.new()
	if ind.is_empty():
		return m
	# 使われない頂點を落とす（区域ごとの AABB を小さく保つ）
	var used := {}
	for q in ind:
		used[q] = true
	var remap := {}
	var v2 := PackedVector3Array()
	var c2 := PackedColorArray()
	var u1 := PackedVector2Array()
	var u2 := PackedVector2Array()
	for q in range(verts.size()):
		if used.has(q):
			remap[q] = v2.size()
			v2.append(verts[q])
			c2.append(cols[q])
			u1.append(uv[q])
			u2.append(uv2[q])
	var i2 := PackedInt32Array()
	for q in ind:
		i2.append(int(remap[q]))
	var n2 := PackedVector3Array()
	n2.resize(v2.size())
	n2.fill(Vector3.UP)
	arr[Mesh.ARRAY_VERTEX] = v2
	arr[Mesh.ARRAY_NORMAL] = n2
	arr[Mesh.ARRAY_COLOR] = c2
	arr[Mesh.ARRAY_TEX_UV] = u1
	arr[Mesh.ARRAY_TEX_UV2] = u2
	arr[Mesh.ARRAY_INDEX] = i2
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


# ─────────────────────────── 店先帯（P6 R4 の fr_* を同じ作法で：石の帯＋蓋付き側溝＋店前の段） ───────────────────────────

static func frontage(s: Dictionary, kit: Node3D, lib: Dictionary) -> Node3D:
	var fr := Node3D.new()
	fr.name = "Frontage"
	var g0 := Node3D.new()
	g0.name = "LOD0"
	var g1 := Node3D.new()
	g1.name = "LOD1"
	fr.add_child(g0)
	fr.add_child(g1)
	var d := float(s["d"])
	var zw := d * 0.5
	var zc := zw + FR_D
	var h := float(s["band_h"]) - float(s["base_h"])
	var xs: Array = kit.get_meta("bay_x")
	var kinds: Array = kit.get_meta("bay_kind")
	for i in kinds.size():
		var x0 := float(xs[i])
		var x1 := float(xs[i + 1])
		ML._fr_put(g0, lib, "fr_band_ishi", x0, x1, h, h, zw, FR_D - GUT_W, 0)
		ML._fr_put(g0, lib, "fr_gutc_%d_%d" % [int(round(GUT_W * 100)), 3 if x1 - x0 > 1.2 else 2], x0, x1, h, h, zc - GUT_W, 1.0, 0)
		if String(kinds[i]) == "shop_o":
			var r := ML.FL - h
			ML._fr_put(g0, lib, "fr_dan", x0 + 0.03, x1 - 0.03, h + r * 0.45, h + r * 0.45, zw, ML.FR_STEP_D, 0, r * 0.45 + ML.FR_BURY)
		ML._fr_put(g1, lib, "fr_band_ishi", x0, x1, h, h, zw, FR_D - GUT_W, 1)
		ML._fr_put(g1, lib, "fr_gutl_%d" % int(round(GUT_W * 100)), x0, x1, h, h, zc - GUT_W, 1.0, 1)
	return fr


# ─────────────────────────── bake ───────────────────────────

static func bake(P: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = NODE_NAME
	var groups := {}
	for nm: String in ["Buildings", "Floor", "Paving", "Naka", "Stalls", "Signs", "Entrances", "Back", "Anchors"]:
		var n := Node3D.new()
		n.name = nm
		root.add_child(n)
		groups[nm] = n
	var col := StaticBody3D.new()
	col.name = "Collision"
	root.add_child(col)
	var ns := 0
	# ── 建物
	var lib := ML.load_lib()
	for s: Dictionary in P["shops"]:
		var body := Node3D.new()
		body.name = String(s["id"])
		body.transform = s["xf"]
		var rec: Dictionary = s["rec"]
		for k: String in ["width_m", "depth_m", "eave_m", "type", "kind"]:
			body.set_meta(k, rec[k])
		body.set_meta("trade", String(s["trade"]))
		body.set_meta("side", String(s["side"]))
		(groups["Buildings"] as Node).add_child(body)
		var kit := ML.build(rec, lib, EMBED)
		if s.has("noren_up"):
			# 戸口の間（局部 x＝bay_x[door]）に掛かる暖簾 nr_* を外し、mise_kit の掀げた暖簾に替える
			var xs: Array = kit.get_meta("bay_x")
			var kinds: Array = kit.get_meta("bay_kind")
			var di := kinds.find("shop_o")
			for lod_n in kit.get_children():
				for c in lod_n.get_children():
					if String(c.name).begins_with("nr_") and di >= 0 and absf((c as Node3D).position.x - float(xs[di])) < 0.02:
						lod_n.remove_child(c)
						c.free()
			kit.set_meta("noren_lifted", true)
		body.add_child(kit)
		body.add_child(frontage(s, kit, lib))
		var bot := float(rec["ground_lo"]) - EMBED - float(rec["base_h"])
		var bx := BoxShape3D.new()
		bx.size = Vector3(float(rec["width_m"]), float(rec["eave_m"]) - bot, float(rec["depth_m"]))
		var cs := CollisionShape3D.new()
		cs.name = "%s_c" % body.name
		cs.shape = bx
		cs.transform = Transform3D((s["xf"] as Transform3D).basis, (s["xf"] as Transform3D).origin + Vector3(0, (bot + float(rec["eave_m"])) * 0.5, 0))
		col.add_child(cs)
		ns += 1
	# ── 通りの床（区域ごと）
	var fmat: ShaderMaterial = null
	if P["floor_mat"] != null:
		fmat = (P["floor_mat"] as Material).duplicate() as ShaderMaterial
		fmat.set_shader_parameter("mode", 0)
		fmat.set_shader_parameter("use_vertex_weights", true)
	for k: String in FLOOR:
		var fmi := MeshInstance3D.new()
		fmi.name = "Floor_" + k
		fmi.mesh = floor_mesh(P, k)
		fmi.material_override = fmat
		fmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		(groups["Floor"] as Node).add_child(fmi)
	# ── 陳列・看板・入口・後場
	var meshes := {}
	var n_i := 0
	for it: Dictionary in P["items"]:
		var id := String(it["id"])
		var node := Node3D.new()
		node.name = "%03d_%s" % [n_i, id]
		var sx := float(it.get("sx", 1.0))
		var sy := float(it.get("sy", 1.0))
		node.transform = Transform3D(Basis(Vector3.UP, float(it["yaw"])).scaled_local(Vector3(sx, sy, 1.0)),
			Vector3((it["p"] as Vector2).x, float(it["y"]), (it["p"] as Vector2).y))
		node.set_meta("mw_id", id)
		node.set_meta("mw_tag", String(it["tag"]))
		if it.has("shop"):
			node.set_meta("shop", String(it["shop"]))
		var tag := String(it["tag"])
		var grp := String({"disp": "Stalls", "awn": "Stalls", "work": "Stalls", "sign": "Signs", "entr": "Entrances", "back": "Back", "wall": "Signs",
			"over": "Signs", PAVE_TAG: "Paving", NAKA_TAG: "Naka"}.get(tag, "Back"))
		(groups[grp] as Node).add_child(node)
		for lod in 2:
			var key := id + ("_l1" if lod == 1 else "")
			if not meshes.has(key):
				meshes[key] = load(mesh_dir(id) + key + ".res")
			var mi := MeshInstance3D.new()
			mi.name = "LOD%d" % lod
			mi.mesh = meshes[key]
			mi.visibility_range_begin = 0.0 if lod == 0 else LOD_SWITCH
			mi.visibility_range_end = LOD_SWITCH if lod == 0 else 220.0
			if lod == 1:
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.add_child(mi)
		var b: Array = box(id)
		var is_pole := pole_key(id) != "" or id == "mk_bangasa"
		if tag == PAVE_TAG or tag == NAKA_TAG:
			n_i += 1
			continue
		for poly: PackedVector2Array in polys(it):
			var r := Rect2(poly[0], Vector2.ZERO)
			for q in poly:
				r = r.expand(q)
			var bxs := BoxShape3D.new()
			var hh := float(b[2]) * sy
			bxs.size = Vector3(r.size.x, hh, r.size.y) if is_pole else Vector3(float(b[0]) * 2.0 * sx, hh, float(b[1]) * 2.0)
			var cs2 := CollisionShape3D.new()
			cs2.name = "%s_c%d" % [node.name, col.get_child_count()]
			cs2.shape = bxs
			if is_pole:
				cs2.transform = Transform3D(Basis(), Vector3(r.get_center().x, float(it["y"]) + hh * 0.5, r.get_center().y))
			else:
				var ba := Basis(Vector3.UP, float(it["yaw"]))
				cs2.transform = Transform3D(ba, node.transform.origin + ba * Vector3(float(b[4]) * sx, hh * 0.5, float(b[3])))
			col.add_child(cs2)
			ns += 1
		n_i += 1
	var lg := Node3D.new()
	lg.name = "ShopLights"
	root.add_child(lg)
	for i in (P.get("lights", []) as Array).size():
		var L: Dictionary = P["lights"][i]
		var ol := OmniLight3D.new()
		ol.name = "Light_%s_%d" % [L["shop"], i]
		ol.position = Vector3((L["p"] as Vector2).x, float(L["y"]), (L["p"] as Vector2).y)
		ol.light_color = Color(1.0, 0.78, 0.52)
		ol.light_energy = 1.6
		ol.omni_range = 2.7
		ol.omni_attenuation = 1.2
		ol.shadow_enabled = false
		ol.distance_fade_enabled = true
		ol.distance_fade_begin = 40.0
		ol.distance_fade_length = 10.0
		ol.set_meta("shop", String(L["shop"]))
		lg.add_child(ol)
	var C: Dictionary = P["C"]
	for a: Dictionary in P["anchors"]:
		var mk := Marker3D.new()
		mk.name = String(a["id"])
		var p: Vector2 = a["p"]
		mk.transform = Transform3D(Basis(Vector3.UP, float(a["yaw"])), Vector3(p.x, ground_h(C, p), p.y))
		mk.set_meta("activity", String(a["activity"]))
		mk.set_meta("ref", String(a["ref"]))
		mk.add_to_group("npc_activity_anchor", true)
		(groups["Anchors"] as Node).add_child(mk)
	root.set_meta("shops", (P["shops"] as Array).size())
	root.set_meta("items", (P["items"] as Array).size())
	root.set_meta("anchors", (P["anchors"] as Array).size())
	root.set_meta("lights", (P.get("lights", []) as Array).size())
	root.set_meta("shapes", ns)
	root.set_meta("art_revision", "P10 R1b Market West Rework r3 営業中（ART_REVIEW 前）")
	return root


static func own(n: Node, owner: Node) -> void:
	for c in n.get_children():
		c.owner = owner
		if c.scene_file_path == "":
			own(c, owner)

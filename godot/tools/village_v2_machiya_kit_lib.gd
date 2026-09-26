extends RefCounted
## 人間之里 V2 P6 R1／R2／R3：模組化町家 Kit 組裝（新資產；不引用任何舊房屋資產）。
##
## R3 Silhouette / Depth Pass（大輪廓與前後凹凸；不再以顏色／窗型為主）：
##   屋根型 8 種（兩坡勾配 0.45／0.38／0.32 組合 → 棟前後／左右偏移、棟高下降；兩側簷高＝P4，屋根面都在 P4 屋根面之下）、
##   出簷減 0.2（屋簷深度）、庇形式（瓦庇／板庇／2F 退縮用深庇）、小山牆（前坡）、本卯建（屋根端）、煙出し、懸魚；
##   1F 前後凹凸（入口退縮 0.6／0.9、店先退縮 0.45／0.9、格子以外開間退縮 0.35 → 出格子相對突出）、2F セットバック 0.45。
##   權重依街區（district）× 街道（road）不同；角地（側牆臨另一條路／巷 5 m 內）與 Hero／地標周邊 16 m 內提高辨識度
##   （小山牆、本卯建、懸魚、臨街側牆開口）。屋根型分層避同：同側緊鄰 13 m 不同「族」（標準／棟偏前／棟偏後／低棟）、
##   同側 20 m 與對街 28 m 不同型；同側 13 m 內不取同一上層節奏（窓型＋白壁週期＋退縮），小山牆、本卯建不連棟。
##   小山牆／本卯建／棟／煙出し也進 LOD1／2（高處俯視看得到大輪廓）；2F セットバック也進 LOD1／2 外殼。
##   量體（寬深簷高、台基、碰撞）仍 100 % 依 P4；棟只降不升。
##
## R2 Variation Pass：每棟依 id 做決定性「風格計畫」（plan_for）：牆色 5 種（原色＋c1–c4）、瓦色 3 種、1F 立面主題、
##   上層窓型與節奏、暖簾／簾、板庇／瓦庇、袖卯建、屋根／袖看板、霧除け、犬矢来、煙出し、低棟／板鬼、開間分割。
##   同一側相鄰（13 m 內、同朝向）與對街（28 m 內、反朝向）不取同一牆色／立面主題；相鄰不取同一瓦色、窓型、暖簾。
##   量體仍 100 % 依 P4 紀錄（寬深簷脊出簷庇不變），變化只換構件與色變體。
##
## 構件：res://assets/village_v2/machiya_kit/mesh/<構件名>.res（village_v2_machiya_kit_prefab.gd 產生，每構件一檔、全村共用）。
## 輸入：P4 已核准的灰盒紀錄（maps/village_v2/gen/greybox.json 的 machiya；寬、深、簷、脊、出簷、庇、入口、台基）。
## 座標＝P4 灰盒 StaticBody3D 的局部座標：原點＝footprint 中心、y 0＝base（footprint 內最高地面）、+z＝正面（臨路）。
## 尺寸 authority 是 P4：牆面＝Building_Main 外皮（±w/2、±d/2）、簷高＝eave_m、屋面＝P4 屋根面（脊 ridge_m、
## 出簷 ov_eave_m、螻羽出 ov_gable_m、pitch 0.45）、台基＝plinth 0.32 並從 ground_lo−embed 起（與灰盒 Foundation 同）。
## 構件只沿設計好的方向伸縮：開間 x ±12 % 內；屋面／螻羽／妻壁 y、z 同比（勾配不變）；本卯建沿坡 ±10 %；台基與 LOD 外殼單位方塊。
## 碰撞：沿用 P4 灰盒 BoxShape3D（不另建；P4 碰撞已核准）。
##
## apply(body, rec, lib, embed)：把一棟灰盒換成 Kit——灰盒網格逐一 visible＝false（節點保留，P4 gate 讀位置），
##   碰撞不動；body 下加 "Kit"（LOD0／LOD1／LOD2 三組 MeshInstance3D，visibility_range 硬切＋margin）。

const GLib := preload("res://tools/village_v2_greybox_lib.gd")
const PLib := preload("res://tools/village_v2_parcel_lib.gd")
const TLib := preload("res://tools/village_v2_terrain_lib.gd")
const MESH_DIR := "res://assets/village_v2/machiya_kit/mesh/"
const P := 0.45
const FL := 0.32
const HU := 0.53
const RU := 2.12
const SPANS := [1.5, 2.0, 2.5, 3.0, 3.5, 4.0, 4.5, 5.0, 5.5, 6.0, 6.5, 7.0]
const DEPTHS := {"d910": 9.10, "d1001": 10.01, "d1092": 10.92}
const EAVES := {"e29": 2.9, "e39": 3.9, "e54": 5.4}
const LOD_RANGES := [0.0, 40.0, 110.0, 600.0]
const LOD_MARGIN := 4.0
const VERGE_IN := 0.08      # 螻羽中心內縮（袖瓦半徑 0.075）
const ONI_IN := 0.075       # 鬼瓦中心內縮（半厚 0.07）
const EAVE_TRIM := 0.065    # 瓦當／茅負比屋面板多出 ≈0.06 m：屋面水平長內縮，使外緣＝P4 屋根簷緣（不多壓路／鄰地）
const END_TRIM := 0.03      # 屋面瓦列兩端多出 ≈0.025 m：屋面長內縮
const HIS_TRIM := 0.04      # 庇瓦當同理
const GB_MESHES := ["Foundation", "Building_Main", "Roof", "Hisashi", "Door"]
const GREYBOX := "res://maps/village_v2/gen/greybox.json"
const LAYOUT := "res://maps/village_v2/layout_v2.json"

## ── P6 R2 Variation Pass ──
## 1F 立面主題（寬開間依序循環；入口開間另定）
const RES_THEMES := {
	"koshi": ["koshi", "koshi", "mado", "plain"],
	"koshir": ["koshir", "koshir", "plain"],
	"koshib": ["koshib", "amado", "koshib"],
	"amado": ["amado", "koshi", "amado", "plain"],
	"mado": ["mado", "plain", "koshi"],
}
const SHOP_THEMES := {
	"open": ["shop_c", "shop_k"],
	"mixed": ["koshi", "shop_c"],
	"bengara": ["koshir", "shop_k"],
	"lattice": ["koshib", "shop_c", "koshib"],
}
const HANGS := ["noren_a", "noren_b", "noren_c", "noren_d", "noren_e", "sudare", "sudare_b"]
const UP_ZUSHI := ["mushi", "mushib", "mushis", "plain"]
const UP_NIKAI := ["win", "winb", "wins", "amado"]
const KANBAN := ["kanban", "kanban_b", "kanban_c"]
const WALL_PFX := ["f1_", "u_", "bk_", "sd_", "post_", "gb_", "ud_"]
const ROW_R := 13.0       # 同側相鄰
const ACROSS_R := 28.0    # 對街
const KIRI_Y := 2.42      # 霧除け：入口鴨居（2.37）上
const IY_MIN := -0.2      # 犬矢来：正面最低地面（ground_lo − base_h）不低於此才放（底 −0.30 埋入）

## ── P6 R3 Silhouette / Depth Pass ──
## 屋根型：[前坡 p_A, 後坡 p_B]（平入＝街側／背側；妻入＝屋根座標 +c／−c 側）。兩側簷高＝P4 → 棟位置 c_r＝half·(p_A−p_B)/(p_A+p_B)、
## 棟高 H＝簷＋p_A·(half−c_r)；p ≤ 0.45 → 整個屋根面在 P4 屋根面（0.45）之下。
const ROOF_CLS := {
	"std": [0.45, 0.45],      # R2 同（P4 屋根面）
	"low": [0.38, 0.38],      # 緩勾配（棟降 0.07·half）
	"flat": [0.32, 0.32],     # 更緩（棟降 0.13·half）
	"offf": [0.45, 0.38],     # 棟偏前（前坡短陡、後坡長緩）
	"offf2": [0.45, 0.32],
	"offb": [0.38, 0.45],     # 棟偏後（前坡長緩）
	"offb2": [0.32, 0.45],
	"lowoff": [0.32, 0.38],
}
const Y1_OF := {"h27": 2.7, "h29": 2.9}
const POST_W := 0.12
const EAVE_CUT := 0.2       # 出簷減（P4 出簷 0.4／0.45 才減 → 0.2／0.25）
const DM_BACK := 0.7        # 小山牆破風面在前牆線內 0.7（前出 0.3 → 仍在牆線內 0.4）
const DM_HALF := 1.05       # 小山牆半寬（含側出）
const UDH_IN := 0.13        # 本卯建中心離屋根端
const UDH_L := [3.0, 3.5, 4.0, 4.5, 5.0, 5.5, 6.0, 6.5, 7.0, 7.5, 8.0]
const SB_D := 0.45          # 2F セットバック（＝P4 庇出）
const HISX_S := 0.9         # 深庇構件水平長（退 0.45＋出 0.45）
const CORNER_D := 5.0       # 側牆外 0.5 m 點離另一條路／巷邊 < 5 m → 角地
const HERO_R := 16.0        # Hero／地標中心 16 m 內（24 m 會蓋到主街半數 → 辨識度被稀釋）
const ROOF_R := 20.0        # 同側屋根型不重複半徑
## 屋根型「族」：同側緊鄰（ROW_R）不同族——主街審圖：棟偏前／棟偏前2 在眼高下是同一個輪廓
const ROOF_FAM := {"std": "std", "offf": "front", "offf2": "front", "offb": "back", "offb2": "back",
	"low": "low", "flat": "low", "lowoff": "low"}
## 街區權重（屋根型權重；其餘為機率）。rec_*＝1F 凹凸型權重（none／door 入口退縮／shop 店先退縮／koshi 格子以外退縮）
const DIST_W := {
	"Market": {"roof": {"std": 2.0, "offf": 3.0, "offb": 2.0, "low": 1.5, "offb2": 1.0},
		"dormer": 0.2, "udh": 0.4, "sb": 0.35, "cut": 0.2, "kemuri": 0.1,
		"rec_shop": {"none": 2.0, "door": 2.0, "shop": 3.0}, "rec_res": {"none": 2.0, "door": 3.0, "koshi": 2.0}},
	"MixedCommercial": {"roof": {"std": 1.0, "offf": 2.0, "offb": 1.0, "low": 2.0, "lowoff": 1.0, "offf2": 1.0},
		"dormer": 0.35, "udh": 0.25, "sb": 0.25, "cut": 0.3, "kemuri": 0.2,
		"rec_shop": {"none": 2.0, "door": 1.0, "shop": 2.0}, "rec_res": {"none": 2.0, "door": 2.0, "koshi": 2.0}},
	"ResidentialWest": {"roof": {"std": 1.0, "low": 2.0, "flat": 2.0, "offb": 2.0, "offb2": 1.0, "lowoff": 2.0},
		"dormer": 0.12, "udh": 0.1, "sb": 0.2, "cut": 0.4, "kemuri": 0.35,
		"rec_shop": {"none": 1.0, "door": 1.0, "shop": 1.0}, "rec_res": {"none": 2.0, "door": 3.0, "koshi": 3.0}},
	"ResidentialNE": {"roof": {"std": 2.0, "offf": 1.0, "offb2": 2.0, "flat": 1.0, "low": 1.0},
		"dormer": 0.3, "udh": 0.15, "sb": 0.2, "cut": 0.3, "kemuri": 0.4,
		"rec_shop": {"none": 1.0, "door": 1.0, "shop": 1.0}, "rec_res": {"none": 3.0, "door": 2.0, "koshi": 2.0}},
	"SouthGate": {"roof": {"std": 2.0, "offf": 2.0, "low": 1.0},
		"dormer": 0.5, "udh": 0.5, "sb": 0.5, "cut": 0.1, "kemuri": 0.1,
		"rec_shop": {"none": 1.0, "door": 1.0, "shop": 2.0}, "rec_res": {"none": 1.0, "door": 2.0, "koshi": 1.0}},
}
## 街道修正（roof_x＝屋根型權重倍率；其餘加到機率）
const ROAD_MOD := {
	"MainStreet": {"roof_x": {"offf": 1.5, "low": 1.0, "std": 0.5}, "udh": 0.15, "sb": 0.1},
	"HillFootStreet": {"roof_x": {"low": 2.0, "lowoff": 2.0}, "dormer": 0.15},
	"CrossStreetMid": {"roof_x": {"offb": 2.0}, "cut": 0.2},
	"CrossStreetSouth": {"roof_x": {"offb2": 2.0, "std": 1.5}},
	"WestBankLane": {"roof_x": {"flat": 2.0}, "kemuri": 0.1},
	"WestAlley": {"roof_x": {"offb": 2.0, "flat": 1.5}, "dormer": -0.08},
	"NWLane": {"roof_x": {"flat": 2.0, "low": 1.5}},
}
const IDENT_ADD := {"dormer": 0.45, "udh": 0.2}

static var _plan: Dictionary = {}

## 各類型：1F 上緣鍵、上層構件前綴、上層區間
const TYPES := {
	"hiraya": {"h1": "h29", "up": ""},
	"zushi": {"h1": "h27", "up": "27"},
	"nikai": {"h1": "h29", "up": "29"},
}


## 構件快取（名 → Mesh）；同一個 Mesh 資源給所有棟共用
static func load_lib() -> Dictionary:
	var lib := {}
	for f in DirAccess.get_files_at(MESH_DIR):
		if f.ends_with(".res"):
			lib[f.get_basename()] = load(MESH_DIR + f)
	return lib


static func _mesh(lib: Dictionary, name: String) -> Mesh:
	if not lib.has(name):
		push_error("[kit] 構件缺 %s" % name)
		return null
	return lib[name]


static func _nearest_key(tab: Dictionary, v: float) -> String:
	var best := ""
	var bd := INF
	for k: String in tab:
		var d := absf(float(tab[k]) - v)
		if d < bd:
			bd = d
			best = k
	return best


static func _nearest_span(v: float) -> float:
	var best := float(SPANS[0])
	for s: float in SPANS:
		if absf(s - v) < absf(best - v):
			best = s
	return best


## 開間分割：半間數 m（0.91 的倍數）→ 1.82 × m/2（奇數多一個 0.91）；整面同比縮放到 w（±12 % 內取最接近 1）。
## 0.91 開間放在離入口較遠的一端。回傳 {"widths": [1.82|0.91…]（由左到右，左＝−x）, "k": 縮放, "door": 入口開間 index}
static func bays(w: float, door_x: float) -> Dictionary:
	var m := maxi(2, int(round(w / 0.91)))
	var best_m := m
	for mm in [m - 1, m, m + 1]:
		if mm >= 2 and absf(w / (mm * 0.91) - 1.0) < absf(w / (best_m * 0.91) - 1.0):
			best_m = mm
	m = best_m
	var k := w / (m * 0.91)
	var widths: Array = []
	for i in m / 2:
		widths.append(1.82)
	if m % 2 == 1:
		if door_x >= 0.0:
			widths.push_front(0.91)
		else:
			widths.append(0.91)
	# 入口：中心最接近 door_x 的 1.82 開間
	var x := -w * 0.5
	var door := -1
	var bd := INF
	for i in widths.size():
		var bw: float = widths[i] * k
		var c := x + bw * 0.5
		if widths[i] > 1.0 and absf(c - door_x) < bd:
			bd = absf(c - door_x)
			door = i
		x += bw
	return {"widths": widths, "k": k, "door": door}


## 以 id 做決定性變化（同一棟每次組裝結果一樣）
static func _h(id: String, salt: int) -> int:
	# Godot String.hash() 對只差尾數的 id 產生等差序列（步長 33³），% 3 全同、% 5 週期循環——
	# 沿街連號的房子會被系統性指派成同樣式。用 lowbias32 整數 mixer 打散（deterministic）。
	var x := hash(id + ":" + str(salt)) & 0xFFFFFFFF
	x ^= x >> 16
	x = (x * 0x7feb352d) & 0xFFFFFFFF
	x ^= x >> 15
	x = (x * 0x846ca68b) & 0xFFFFFFFF
	x ^= x >> 16
	return x


static func _pick(id: String, salt: int, opts: Array, avoid: Array) -> Variant:
	var n := opts.size()
	var st := _h(id, salt) % n
	for k in n:
		var c: Variant = opts[(st + k) % n]
		if not avoid.has(c):
			return c
	return opts[st]


## R3：加權決定性選擇（避開 avoid；全被避開時不避）
static func _wpick(id: String, salt: int, wts: Dictionary, avoid: Array) -> String:
	var keys: Array = wts.keys()
	keys.sort()
	var cand: Array = []
	for k: String in keys:
		if float(wts[k]) > 0.0 and not avoid.has(k):
			cand.append(k)
	if cand.is_empty():
		for k: String in keys:
			if float(wts[k]) > 0.0:
				cand.append(k)
	var tot := 0.0
	for k: String in cand:
		tot += float(wts[k])
	var r := float(_h(id, salt) % 100000) / 100000.0 * tot
	for k: String in cand:
		r -= float(wts[k])
		if r < 0.0:
			return k
	return String(cand[-1])


static func _chance(id: String, salt: int, p: float) -> bool:
	return float(_h(id, salt) % 10000) < clampf(p, 0.0, 1.0) * 10000.0


## R3：角地——側牆外 0.5 m 的點離另一條路／巷（農路除外）邊緣 < CORNER_D → 回傳該側（局部 ±x）
static func _corner_sides(b: Dictionary, c: Vector2, f: Vector2, nets: Array) -> Array:
	var rx := Vector2(f.y, -f.x)
	var out: Array = []
	for e in [-1.0, 1.0]:
		var p := c + rx * float(e) * (float(b["width_m"]) * 0.5 + 0.5)
		for n: Array in nets:
			if String(n[0]) == String(b["road"]):
				continue
			var pts: PackedVector2Array = n[1]
			var best := INF
			for k in pts.size() - 1:
				best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, pts[k], pts[k + 1])))
			if best - float(n[2]) < CORNER_D:
				out.append(e)
				break
	return out


## R3：街區 × 街道 × 類型 × 辨識度 → 權重
static func _weights(b: Dictionary, ident: bool) -> Dictionary:
	var dw: Dictionary = DIST_W.get(String(b["district"]), DIST_W["ResidentialWest"])
	var rm: Dictionary = ROAD_MOD.get(String(b["road"]), {})
	var rx: Dictionary = rm.get("roof_x", {})
	var typ := String(b["type"])
	var roof := {}
	for k: String in dw["roof"]:
		var v := float(dw["roof"][k]) * float(rx.get(k, 1.0))
		if typ == "hiraya" and k in ["flat", "low", "lowoff"]:
			v *= 2.0
		if typ == "nikai" and k == "flat":
			v = 0.0
		if ident and k in ["std", "offf"]:
			v *= 2.0
		roof[k] = v
	var out := {"roof": roof, "rec_shop": dw["rec_shop"], "rec_res": dw["rec_res"]}
	for k: String in ["dormer", "udh", "sb", "cut", "kemuri"]:
		out[k] = float(dw[k]) + float(rm.get(k, 0.0)) + (float(IDENT_ADD.get(k, 0.0)) if ident else 0.0)
	return out


## 全村風格計畫（依 id 排序貪婪指派；同一份 greybox.json → 永遠同一結果）
static func _build_plan() -> void:
	var G: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GREYBOX))
	var recs: Array = []
	for b: Dictionary in G["buildings"]:
		if String(b["kind"]) == "machiya":
			recs.append(b)
	recs.sort_custom(func(a, b): return String(a["id"]) < String(b["id"]))
	var cen := {}
	var fr := {}
	for b: Dictionary in recs:
		var c := Vector2.ZERO
		for p in b["footprint"]:
			c += Vector2(float(p[0]), float(p[1]))
		cen[b["id"]] = c / float(b["footprint"].size())
		fr[b["id"]] = Vector2(float(b["front_dir"][0]), float(b["front_dir"][1])).normalized()
	var LY: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	var nets: Array = []
	for r: Dictionary in LY["roads"] + LY["lanes"]:
		if String(r.get("class", "")) == "farm":
			continue
		var pts := PackedVector2Array()
		for q in r["pts"]:
			pts.append(Vector2(float(q[0]), float(q[1])))
		nets.append([String(r["name"]), pts, float(r["half_w"])])
	var marks: Array = []
	for lm: Dictionary in LY["landmarks"]:
		if lm.has("at"):
			marks.append(Vector2(float(lm["at"][0]), float(lm["at"][1])))
	for b: Dictionary in recs:
		var id := String(b["id"])
		var row: Array = []
		var acr: Array = []
		var row2: Array = []
		for o: Dictionary in recs:
			var oid := String(o["id"])
			if oid == id or not _plan.has(oid):
				continue
			var dd: float = (cen[id] as Vector2).distance_to(cen[oid])
			var dt: float = (fr[id] as Vector2).dot(fr[oid])
			if dd < ROW_R and dt > 0.7:
				row.append(_plan[oid])
			elif dd < ACROSS_R and dt < -0.7:
				acr.append(_plan[oid])
			if dd < ROOF_R and dt > 0.7:
				row2.append(_plan[oid])
		var shop := float(b.get("hisashi_m", 0.0)) > 0.0
		var typ := String(b["type"])
		var pl := {}
		pl["fin"] = _pick(id, 11, [0, 1, 2, 3, 4], row.map(func(q): return q["fin"]) + acr.map(func(q): return q["fin"]))
		pl["tone"] = _pick(id, 12, [0, 1, 2], row.map(func(q): return q["tone"]))
		var themes: Array = (SHOP_THEMES if shop else RES_THEMES).keys()
		pl["theme"] = _pick(id, 13, themes, row.map(func(q): return q["theme"]) + acr.map(func(q): return q["theme"]))
		var ups: Array = UP_ZUSHI if typ == "zushi" else (UP_NIKAI if typ == "nikai" else [""])
		pl["up"] = _pick(id, 14, ups, row.map(func(q): return q["up"]))
		# R3：上層白壁週期也避開同側相鄰同窓型的週期（窓型＋週期＝上層節奏）
		pl["up_period"] = _pick(id, 15, [0, 2, 3], row.filter(func(q): return q["up"] == pl["up"]).map(func(q): return q["up_period"]))
		pl["hang"] = _pick(id, 16, HANGS, row.map(func(q): return q["hang"]) + acr.map(func(q): return q["hang"]))
		pl["his_wood"] = shop and _h(id, 17) % 10 < 3
		var ud := -1
		if shop and typ != "hiraya" and String(b["roof"]) == "hira" and _h(id, 18) % 100 < 60:
			ud = _h(id, 19) % 3          # 0 左、1 右、2 兩側
		pl["udatsu"] = ud
		var sg := _h(id, 20) % 10
		pl["sign"] = ("roof" if sg < 4 else ("side" if sg < 8 else "")) if shop else ""
		pl["sign_key"] = _pick(id, 21, KANBAN, row.map(func(q): return q["sign_key"]))
		pl["kiri"] = not shop and _h(id, 22) % 2 == 0
		pl["inuyarai"] = not shop and _h(id, 23) % 10 < 4 and float(b["ground_lo"]) - float(b["base_h"]) >= IY_MIN
		pl["ridge_low"] = _h(id, 24) % (2 if typ == "hiraya" else 4) == 0
		pl["oni_b"] = _h(id, 25) % 2 == 0
		pl["split"] = _h(id, 27) % 100 < (35 if shop else 45)   # 半間柱割（店也可；入口開間不拆）
		# ── R3 Silhouette / Depth ──
		var hira := String(b["roof"]) == "hira"
		var corner: Array = _corner_sides(b, cen[id], fr[id], nets)
		var hero := false
		for mk: Vector2 in marks:
			hero = hero or (cen[id] as Vector2).distance_to(mk) < HERO_R
		var ident := not corner.is_empty() or hero
		var W := _weights(b, ident)
		pl["corner"] = corner
		pl["hero"] = hero
		pl["district"] = String(b["district"])
		pl["kemuri"] = typ != "nikai" and _chance(id, 26, float(W["kemuri"]))
		var half := (float(b["depth_m"]) if hira else float(b["width_m"])) * 0.5
		# 屋根型：分層避同——①同側緊鄰（13 m）不同族＋同側 20 m 不同型＋對街不同型 → ②去掉對街 → ③只留緊鄰不同族
		#   → ④只避同側 20 m 同型；取第一個還有候選的層
		var fam_row: Array = row.map(func(q): return ROOF_FAM[q["roof"]])
		var fam_av: Array = []
		for k: String in ROOF_CLS:
			if fam_row.has(ROOF_FAM[k]):
				fam_av.append(k)
		var r2: Array = row2.map(func(q): return q["roof"])
		var ac: Array = acr.map(func(q): return q["roof"])
		var avoid_r: Array = []
		for tier: Array in [fam_av + r2 + ac, fam_av + r2, fam_av, r2]:
			var free := false
			for k: String in W["roof"]:
				free = free or (float(W["roof"][k]) > 0.0 and not tier.has(k))
			if free:
				avoid_r = tier
				break
		pl["roof"] = _wpick(id, 50, W["roof"], avoid_r)
		var ps: Array = ROOF_CLS[pl["roof"]]
		var cr := half * (float(ps[0]) - float(ps[1])) / (float(ps[0]) + float(ps[1]))
		# 本卯建：平入、螻羽出 ≤ 0.1（屋根端≈側牆線）、兩坡水平都 ≥ 2.8 m、棟比 P4 低 ≥ 0.11（合掌塊頂 ≤ P4 屋脊＋0.40）
		var udh: Array = []
		var drop := P * half - float(ps[0]) * (half - cr)          # 棟比 P4 屋脊低多少（std＝0）
		var udh_near := row.any(func(q): return not (q["udh"] as Array).is_empty())
		if hira and float(b["ov_gable_m"]) <= 0.1 and half - absf(cr) >= 2.8 and drop >= 0.11 and not udh_near \
				and _chance(id, 51, float(W["udh"])):
			var m3 := _h(id, 52) % 10
			udh = [-1.0, 1.0] if m3 < 6 else ([-1.0] if m3 < 8 else [1.0])
		pl["udh"] = udh
		pl["cut"] = float(b["ov_eave_m"]) >= 0.4 and _chance(id, 53, float(W["cut"]))
		# 小山牆：平入前坡；破風面後的棟與前坡交點要在棟之前（(c_d−c_r)·p_A ≥ 1.0）；同側 13 m 內已有小山牆則不放
		var dm_near := row.any(func(q): return q["dormer"])
		pl["dormer"] = hira and float(b["width_m"]) >= 4.6 and (half - DM_BACK - cr) * float(ps[0]) >= 1.0 \
			and not dm_near and _chance(id, 54, float(W["dormer"]) * (0.5 if typ == "hiraya" else 1.0))
		var gyo: Array = []
		if not hira and (ident or _chance(id, 55, 0.45)):
			gyo.append(1.0)                                   # 妻入：臨街妻面（屋根座標 +x）
		if hira:
			for e in corner:
				if not udh.has(e):
					gyo.append(e)                             # 平入角地：臨側街的妻面
		pl["gyo"] = gyo
		# 2F セットバック（店・平入・厨子／總二階）；同側 13 m 內上層節奏（窓型／週期／退縮）相同 → 翻轉
		var sb_ok := shop and hira and typ != "hiraya"
		pl["sb"] = sb_ok and _chance(id, 56, float(W["sb"]))
		var usig := "%s/%d/%s" % [pl["up"], int(pl["up_period"]), pl["sb"]]
		if typ != "hiraya" and sb_ok and row.any(func(q): return "%s/%d/%s" % [q["up"], int(q["up_period"]), q["sb"]] == usig):
			pl["sb"] = not pl["sb"]
		if pl["sb"]:
			pl["udatsu"] = -1
			pl["his_wood"] = false
		pl["rec"] = _wpick(id, 57, W["rec_shop"] if shop else W["rec_res"], [])
		match String(pl["rec"]):
			"door":
				pl["rec_d"] = [0.6, 0.9][_h(id, 58) % 2]
			"shop":
				pl["rec_d"] = [0.45, 0.9][_h(id, 58) % 2]
			"koshi":
				pl["rec_d"] = 0.35
			_:
				pl["rec_d"] = 0.0
		_plan[id] = pl


static func plan_for(rec: Dictionary) -> Dictionary:
	if _plan.is_empty():
		_build_plan()
	return _plan.get(String(rec["id"]), {"fin": 0, "tone": 0, "theme": "koshi", "up": "", "up_period": 0, "hang": "noren_a",
		"his_wood": false, "udatsu": -1, "sign": "", "sign_key": "kanban", "kiri": false, "inuyarai": false,
		"ridge_low": false, "oni_b": false, "kemuri": false, "split": false, "corner": [], "hero": false, "district": "",
		"roof": "std", "udh": [], "cut": false, "dormer": false, "gyo": [], "sb": false, "rec": "none", "rec_d": 0.0})


## 牆類構件加色變體後綴
static func _wn(name: String, pl: Dictionary) -> String:
	return name if int(pl["fin"]) == 0 else "%s_c%d" % [name, int(pl["fin"])]


## 屋根類構件加瓦色後綴
static func _rn(name: String, pl: Dictionary) -> String:
	return name if int(pl["tone"]) == 0 else "%s_t%d" % [name, int(pl["tone"])]


static func _front_kinds(rec: Dictionary, B: Dictionary, pl: Dictionary) -> Array:
	var shop := float(rec.get("hisashi_m", 0.0)) > 0.0
	var id := String(rec["id"])
	var widths: Array = B["widths"]
	var out: Array = []
	var cyc: Array = (SHOP_THEMES if shop else RES_THEMES)[pl["theme"]]
	var r0 := _h(id, 1) % cyc.size()
	var wi := 0
	for i in widths.size():
		if i == int(B["door"]):
			out.append("shop_o" if shop else "door")
		elif widths[i] > 1.0:
			out.append(cyc[(wi + r0) % cyc.size()])
			wi += 1
		elif shop:
			out.append("koshi" if _h(id, 3 + i) % 2 == 0 else "plain")
		else:
			out.append(["koshi", "plain", "koshib"][_h(id, 3 + i) % 3])
	return out


## 上層各開間：主窓型；up_period＞0 時每 period 個寬開間換一個白壁（節奏）
static func _upper_kinds(rec: Dictionary, widths: Array, pl: Dictionary) -> Array:
	var id := String(rec["id"])
	var per := int(pl["up_period"])
	var ph := _h(id, 28) % maxi(per, 1)
	var out: Array = []
	var wi := 0
	for i in widths.size():
		if widths[i] > 1.0:
			var alt := per > 0 and wi % per == ph and widths.size() > 2
			out.append("plain" if alt else String(pl["up"]))
			wi += 1
		else:
			out.append("plain")
	return out


static func _mi(parent: Node3D, lib: Dictionary, mod: String, xf: Transform3D, lod: int) -> MeshInstance3D:
	var m := _mesh(lib, mod)
	if m == null:
		return null
	var mi := MeshInstance3D.new()
	mi.name = "%s_%d" % [mod, parent.get_child_count()]
	mi.mesh = m
	mi.transform = xf
	var b := float(LOD_RANGES[lod])
	var e := float(LOD_RANGES[lod + 1])
	mi.visibility_range_begin = b
	mi.visibility_range_begin_margin = LOD_MARGIN if b > 0.0 else 0.0
	mi.visibility_range_end = e
	mi.visibility_range_end_margin = LOD_MARGIN
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	parent.add_child(mi)
	return mi


static func _xf(rot_y: float, pos: Vector3, sc := Vector3.ONE) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, rot_y).scaled_local(sc), pos)


## 一排開間（正面或背面）：front＝true 時在 z＝+d/2 面向 +z、由左（−x）往右；背面 z＝−d/2 轉 180°。
static func _row(g: Node3D, lib: Dictionary, names: Array, widths: Array, k: float, w: float, zf: float, front: bool,
		y := 0.0, rec: Array = []) -> void:
	var x := -w * 0.5
	for i in widths.size():
		var bw: float = widths[i] * k
		if front:
			var r := float(rec[i]) if i < rec.size() else 0.0
			var mi := _mi(g, lib, names[i], _xf(0.0, Vector3(x, y, zf - r), Vector3(k, 1, 1)), 0)
			if mi != null and r > 0.0:
				mi.set_meta("rec", r)
		else:
			_mi(g, lib, names[i], _xf(PI, Vector3(-x, y, zf), Vector3(k, 1, 1)), 0)
		x += bw


## R3 屋根幾何（屋根座標：棟沿 +x；A＝+z 側（平入＝街側）、B＝−z 側）。兩側簷高＝P4 簷高 → 棟位置 cr、棟高 H；
## std 型直接用 P4 ridge_m（與 R2 相同）。ove＝出簷（cut 時減 EAVE_CUT）。
static func roof_geo(rec: Dictionary, pl: Dictionary) -> Dictionary:
	var hira := String(rec["roof"]) == "hira"
	var half := (float(rec["depth_m"]) if hira else float(rec["width_m"])) * 0.5
	var eave := float(rec["eave_m"])
	var cls := String(pl.get("roof", "std"))
	var ps: Array = ROOF_CLS.get(cls, [P, P])
	var pa := float(ps[0])
	var pb := float(ps[1])
	var cr := half * (pa - pb) / (pa + pb)
	var H := float(rec["ridge_m"]) if cls == "std" else eave + pa * (half - cr)
	var ove := float(rec["ov_eave_m"]) - (EAVE_CUT if bool(pl.get("cut", false)) else 0.0)
	return {"pa": pa, "pb": pb, "cr": cr, "H": H, "half": half, "ove": ove, "cls": cls}


static func _psuf(p: float) -> String:
	if absf(p - 0.38) < 0.001:
		return "_p38"
	if absf(p - 0.32) < 0.001:
		return "_p32"
	return ""


static func _nearest_in(arr: Array, v: float) -> float:
	var best := float(arr[0])
	for a: float in arr:
		if absf(a - v) < absf(best - v):
			best = a
	return best


## 屋面、螻羽、棟、鬼瓦、妻壁（屋根座標 F：棟沿 F.x；平入 F＝I，妻入 F＝Ry(−90°)→棟沿 +z）
## R3：兩坡勾配可不同（棟偏移）、出簷可減；本卯建取代該端螻羽／鬼瓦；小山牆（平入前坡）；懸魚。
static func _roof(g: Node3D, lib: Dictionary, rec: Dictionary, F: Basis, wall_len: float, half: float, pl: Dictionary) -> void:
	var R := roof_geo(rec, pl)
	var H := float(R["H"])
	var cr := float(R["cr"])
	var ove := float(R["ove"])
	var eave := float(rec["eave_m"])
	var ovg := float(rec["ov_gable_m"])
	var id := String(rec["id"])
	var FX := Transform3D(F, Vector3.ZERO)
	var L := wall_len + ovg * 2.0
	var Lp := L - END_TRIM * 2.0
	var n := maxi(1, int(round(Lp / HU)))
	var kx := Lp / (n * HU)
	var units: Array = []
	var left := n
	for u in [4, 2, 1]:
		while left >= u:
			units.append(u)
			left -= u
	var udh: Array = pl.get("udh", [])
	for side in [0, 1]:
		var p := float(R["pa"]) if side == 0 else float(R["pb"])
		var sp := (half - cr) if side == 0 else (half + cr)     # 棟 → 牆線水平
		var S := sp + ove - EAVE_TRIM
		var sg := _nearest_span(S)
		var kz := S / sg
		var suf := _psuf(p)
		var sgk := "%d" % int(round(sg * 100))
		var sgn := 1.0 if side == 0 else -1.0
		var x := -Lp * 0.5
		for u: int in units:
			var lx := x if side == 0 else -x
			var loc := Transform3D(Basis(Vector3.UP, PI * side).scaled_local(Vector3(kx, kz, kz)), Vector3(lx, H, cr))
			_mi(g, lib, _rn("rf_%s_%d%s" % [sgk, u, suf], pl), FX * loc, 0)
			x += u * HU * kx
		for e in [-1.0, 1.0]:
			if udh.has(e):
				continue
			# 螻羽（袖瓦半徑 0.075）內縮：外緣＝屋面端（不超出 P4 屋根，出簷 0.05 的鄰棟側不越地塊線）
			var loc := Transform3D(Basis(Vector3.UP, PI * side).scaled_local(Vector3(1, kz, kz)), Vector3(e * (L * 0.5 - VERGE_IN), H, cr))
			_mi(g, lib, _rn("vg_%s%s" % [sgk, suf], pl), FX * loc, 0)
		# 妻壁半片：棟下（z＝cr）到牆線；A 半片 local x→+z、B 半片 local x→−z（兩面，法線朝向不影響）
		var gs := _nearest_span(sp)
		var kg := sp / gs
		for e in [-1.0, 1.0]:
			var loc := Transform3D(Basis(Vector3.UP, -PI * 0.5 * sgn).scaled_local(Vector3(kg, kg, 1)), Vector3(e * wall_len * 0.5, eave, cr))
			_mi(g, lib, _wn("gbh_%d%s" % [int(round(gs * 100)), suf], pl), FX * loc, 0)
	_roof_acc(g, lib, rec, F, wall_len, pl, 0)


## R3 屋根上的輪廓構件（棟、鬼瓦／本卯建、小山牆、煙出し、懸魚）：LOD0 全部；LOD1／2 也放（遠景與高處俯視的
## 大輪廓靠這些——R3a 審圖：40 m 外 LOD1 只有兩片半屋根，R3 屋根變化在高處俯視幾乎看不到）。
static func _roof_acc(g: Node3D, lib: Dictionary, rec: Dictionary, F: Basis, wall_len: float, pl: Dictionary, lod: int) -> void:
	var R := roof_geo(rec, pl)
	var H := float(R["H"])
	var cr := float(R["cr"])
	var half := float(R["half"])
	var ove := float(R["ove"])
	var eave := float(rec["eave_m"])
	var ovg := float(rec["ov_gable_m"])
	var id := String(rec["id"])
	var FX := Transform3D(F, Vector3.ZERO)
	var L := wall_len + ovg * 2.0
	var udh: Array = pl.get("udh", [])
	# 本卯建：沿坡從棟到簷（local x＝下坡、y＝屋面法線）
	for side in [0, 1]:
		var p := float(R["pa"]) if side == 0 else float(R["pb"])
		var sp := (half - cr) if side == 0 else (half + cr)
		var S := sp + ove - EAVE_TRIM
		var sgn := 1.0 if side == 0 else -1.0
		var r := sqrt(1.0 + p * p)
		var dv := Vector3(0, -p, sgn) / r
		var nv := Vector3(0, 1, sgn * p) / r
		for e in udh:
			# 簷端：瓦笠頂（法線上 0.48）隨法線外傾 → 最外點水平＝(Ls＋0.04＋0.48·p)/r；控制在屋面簷緣內 0.03
			var Ls := (S - 0.03) * r - 0.04 - 0.48 * p
			var lq := _nearest_in(UDH_L, Ls)
			var bas := Basis(dv, nv, dv.cross(nv)).scaled_local(Vector3(Ls / lq, 1, 1))
			_mi(g, lib, _wn("udh_%d" % int(round(lq * 100)), pl), FX * Transform3D(bas, Vector3(float(e) * (L * 0.5 - UDH_IN), H, cr)), lod)
	_mi(g, lib, _rn("rg_l" if pl["ridge_low"] else "rg_u", pl), FX * Transform3D(Basis().scaled_local(Vector3((L - 2.0 * ONI_IN) / RU, 1, 1)),
		Vector3(-L * 0.5 + ONI_IN, H, cr)), lod)
	for e in [-1.0, 1.0]:
		if udh.has(e):
			_mi(g, lib, _wn("udk", pl), FX * Transform3D(Basis(), Vector3(e * (L * 0.5 - UDH_IN), H, cr)), lod)
		elif lod == 0:
			_mi(g, lib, _rn("oni_b" if pl["oni_b"] else "oni", pl), FX * Transform3D(Basis(), Vector3(e * (L * 0.5 - ONI_IN), H, cr)), 0)
	# 小山牆（平入前坡）：破風面在前牆線內 DM_BACK
	var dmx := 0.0
	var has_dm := bool(pl.get("dormer", false))
	if has_dm:
		var lim := maxf(0.0, wall_len * 0.5 - DM_HALF - 0.3)
		dmx = clampf(float(_h(id, 59) % 3 - 1) * wall_len * 0.25, -lim, lim)
		var zd := half - DM_BACK
		var yd := H - float(R["pa"]) * (zd - cr)
		var dsuf := _psuf(float(R["pa"]))
		_mi(g, lib, _rn("dmr%s" % (dsuf if dsuf != "" else "_p45"), pl), FX * Transform3D(Basis(), Vector3(dmx, yd, zd)), lod)
		_mi(g, lib, _wn("dmg", pl), FX * Transform3D(Basis(), Vector3(dmx, yd, zd)), lod)
	if pl["kemuri"]:
		var kmx := (1.0 if _h(id, 29) % 2 == 0 else -1.0) * L * 0.2
		if has_dm and absf(kmx - dmx) < DM_HALF + 0.5:
			kmx = -kmx
		_mi(g, lib, _rn("kemu", pl), FX * Transform3D(Basis(), Vector3(kmx, H, cr)), lod)
	# 懸魚（妻面、破風合掌下）：妻三角要夠高
	if lod == 0 and H - eave >= 0.85:
		for e: float in pl.get("gyo", []):
			if udh.has(e):
				continue
			_mi(g, lib, _wn("gyo", pl), FX * Transform3D(Basis(Vector3.UP, e * PI * 0.5), Vector3(e * (L * 0.5 - 0.055), H - 0.12, cr)), 0)


## R3 1F 前後凹凸：每開間退縮深（0＝正面線）
static func _recess(pl: Dictionary, kinds: Array, door: int) -> Array:
	var out: Array = []
	for i in kinds.size():
		out.append(0.0)
	var rd := float(pl.get("rec_d", 0.0))
	match String(pl.get("rec", "none")):
		"door":
			if door >= 0:
				out[door] = rd
		"shop":
			for i in kinds.size():
				if String(kinds[i]) in ["shop_o", "shop_c"]:
					out[i] = rd
		"koshi":
			var nk := 0
			for kd in kinds:
				if String(kd) in ["koshi", "koshir"]:
					nk += 1
			if nk > 0 and nk < kinds.size():
				for i in kinds.size():
					if not String(kinds[i]) in ["koshi", "koshir"]:
						out[i] = rd
			elif door >= 0:
				out[door] = 0.6
	return out


## 組一棟（回傳 "Kit" Node3D；不掛到樹上）
static func build(rec: Dictionary, lib: Dictionary, embed: float) -> Node3D:
	var kit := Node3D.new()
	kit.name = "Kit"
	kit.set_meta("asset_id", "machiya_kit")
	kit.set_meta("phase", "P6")
	var l0 := Node3D.new()
	l0.name = "LOD0"
	var l1 := Node3D.new()
	l1.name = "LOD1"
	var l2 := Node3D.new()
	l2.name = "LOD2"
	for n in [l0, l1, l2]:
		kit.add_child(n)
	var w := float(rec["width_m"])
	var d := float(rec["depth_m"])
	var eave := float(rec["eave_m"])
	var hira := String(rec["roof"]) == "hira"
	var T: Dictionary = TYPES[String(rec["type"])]
	var ek := _nearest_key(EAVES, eave)
	var dk := _nearest_key(DEPTHS, d)
	var bot := float(rec["ground_lo"]) - embed - float(rec["base_h"])
	var pl := plan_for(rec)
	var B := bays(w, float(rec["door_local_x"]))
	var widths: Array = B["widths"]
	var k := float(B["k"])
	# R2：開間分割——住宅一個非入口的 1.82 開間拆成兩個 0.91（柱割節奏；k 不變）
	if pl["split"]:
		var far := -1
		for i in widths.size():
			if i != int(B["door"]) and widths[i] > 1.0 and (far < 0 or absi(i - int(B["door"])) > absi(far - int(B["door"]))):
				far = i
		if far >= 0:
			widths[far] = 0.91
			widths.insert(far, 0.91)
			if int(B["door"]) > far:
				B["door"] = int(B["door"]) + 1
	B["widths"] = widths
	var kinds := _front_kinds(rec, B, pl)
	var ups := _upper_kinds(rec, widths, pl) if T["up"] != "" else []
	var shop := float(rec.get("hisashi_m", 0.0)) > 0.0
	var rec1 := _recess(pl, kinds, int(B["door"]))       # R3：1F 各開間退縮深
	var sb: bool = bool(pl.get("sb", false)) and String(T["up"]) != ""   # R3：2F セットバック
	var zu := d * 0.5 - (SB_D if sb else 0.0)
	# ── LOD0 ──
	_mi(l0, lib, "base", _xf(0.0, Vector3(0, bot, 0), Vector3(w, FL - bot, d)), 0)
	var f1: Array = []
	var up: Array = []
	var bk: Array = []
	var hg: Array = []
	for i in widths.size():
		var wc := "%d" % int(round(widths[i] * 100))
		f1.append(_wn("f1_%s_%s_%s" % [kinds[i], wc, T["h1"]], pl))
		if T["up"] != "":
			up.append(_wn("u_%s_%s_%s" % [ups[i], wc, T["up"]], pl))
		bk.append(_wn("bk_%s_%s_%s" % [("win" if (i % 2 == 1 and widths[i] > 1.0) else "plain"), wc, ek], pl))
		if String(kinds[i]) == "shop_o":
			hg.append("nr_%s_%s" % [pl["hang"], wc])
		elif String(kinds[i]) == "shop_k" and _h(String(rec["id"]), 40 + i) % 2 == 0:
			hg.append("nr_sudare_%s" % wc)
		else:
			hg.append("")
	_row(l0, lib, f1, widths, k, w, d * 0.5, true, 0.0, rec1)
	if not up.is_empty():
		_row(l0, lib, up, widths, k, w, zu, true)
	_row(l0, lib, bk, widths, k, w, -d * 0.5, false)
	var xh := -w * 0.5
	for i in widths.size():
		if hg[i] != "":
			_mi(l0, lib, hg[i], _xf(0.0, Vector3(xh, 0, d * 0.5 - float(rec1[i])), Vector3(k, 1, 1)), 0)
		xh += float(widths[i]) * k
	# R3：1F 退縮段——正面線留柱＋差鴨居、退縮面上方天井、段差兩端袖壁
	var xs: Array = [-w * 0.5]
	for i in widths.size():
		xs.append(float(xs[i]) + float(widths[i]) * k)
	var h1 := String(T["h1"])
	for i in widths.size():
		var r := float(rec1[i])
		if r <= 0.0:
			continue
		var bw := float(widths[i]) * k
		_mi(l0, lib, _wn("fp_%s" % h1, pl), _xf(0.0, Vector3(xs[i], 0, d * 0.5)), 0)
		_mi(l0, lib, _wn("fb_%d_%s" % [int(round(widths[i] * 100)), h1], pl), _xf(0.0, Vector3(xs[i], 0, d * 0.5), Vector3(k, 1, 1)), 0)
		_mi(l0, lib, _wn("sf_%s" % h1, pl), _xf(0.0, Vector3(xs[i], 0, d * 0.5 - 0.06), Vector3(bw / 1.82, 1, r - 0.06)), 0)
		var rl := float(rec1[i - 1]) if i > 0 else 0.0
		var rr := float(rec1[i + 1]) if i + 1 < widths.size() else 0.0
		if r > rl:
			_mi(l0, lib, _wn("rt_%s" % h1, pl), _xf(0.0, Vector3(float(xs[i]) + 0.06, 0, d * 0.5 - rl), Vector3(1, 1, r - rl)), 0)
		if r > rr:
			_mi(l0, lib, _wn("rt_%s" % h1, pl), _xf(0.0, Vector3(float(xs[i + 1]) - 0.012, 0, d * 0.5 - rr), Vector3(1, 1, r - rr)), 0)
	_mi(l0, lib, _wn("post_%s" % ek, pl), _xf(0.0, Vector3(w * 0.5, 0, d * 0.5)), 0)
	_mi(l0, lib, _wn("post_%s" % ek, pl), _xf(PI, Vector3(-w * 0.5, 0, -d * 0.5)), 0)
	if sb:
		# R3：2F セットバック——左前角也留通柱、兩端袖壁、上緣小壁（退縮牆頂到屋根下）
		_mi(l0, lib, _wn("post_%s" % ek, pl), _xf(0.0, Vector3(-w * 0.5 + POST_W, 0, d * 0.5)), 0)
		var hy := float(rec.get("hisashi_m", Y1_OF[h1]))
		for e in [-1.0, 1.0]:
			_mi(l0, lib, _wn("rtu", pl), _xf(0.0, Vector3(e * (w * 0.5 - POST_W - 0.012), hy, d * 0.5), Vector3(1, eave - hy, SB_D)), 0)
		var pa := float(roof_geo(rec, pl)["pa"])
		_mi(l0, lib, _wn("rtu", pl), _xf(PI * 0.5, Vector3(w * 0.5, eave - 0.05, zu), Vector3(1, pa * SB_D + 0.07, w)), 0)
	var kd := d / float(DEPTHS[dk])
	var corner: Array = pl.get("corner", [])
	for e in [-1.0, 1.0]:
		var sdn := ("sdo_%s_%s" if corner.has(e) else "sd_%s_%s") % [dk, ek]
		_mi(l0, lib, _wn(sdn, pl), _xf(e * PI * 0.5, Vector3(e * w * 0.5, 0, 0), Vector3(kd, 1, 1)), 0)
	var F := Basis() if hira else Basis(Vector3.UP, -PI * 0.5)
	_roof(l0, lib, rec, F, w if hira else d, (d if hira else w) * 0.5, pl)
	var his := float(rec.get("hisashi_m", 0.0))
	var hd := float(rec.get("hisashi_depth_m", 0.0))
	# 入口開間中心
	var dxc := -w * 0.5
	for i in int(B["door"]):
		dxc += float(widths[i]) * k
	var door_c := dxc + float(widths[int(B["door"])]) * k * 0.5 if int(B["door"]) >= 0 else 0.0
	if his > 0.0 and hd > 0.2:
		var n := maxi(1, int(round(w / HU)))
		var kx := w / (n * HU)
		var x := -w * 0.5
		var left := n
		var ks := (SB_D + hd - HIS_TRIM) / HISX_S
		for u in [4, 2, 1]:
			while left >= u:
				if sb:
					# R3：深庇（原點＝退縮 2F 牆面，過 1F 牆線時＝P4 庇高）
					_mi(l0, lib, _rn("hisx_%d" % u, pl), _xf(0.0, Vector3(x, his + SB_D * P, zu), Vector3(kx, ks, ks)), 0)
				else:
					var hn := ("hisw_%d" % u) if pl["his_wood"] else _rn("his_%d" % u, pl)
					_mi(l0, lib, hn, _xf(0.0, Vector3(x, his, d * 0.5), Vector3(kx, (hd - HIS_TRIM) / 0.45, (hd - HIS_TRIM) / 0.45)), 0)
				x += u * HU * kx
				left -= u
		# 袖卯建（庇上、牆端內）：總二階右端上層是窓時不放（避開手摺）
		var ud := int(pl["udatsu"])
		if ud >= 0:
			var udn := _wn("ud_%d" % (72 if String(rec["type"]) == "zushi" else 125), pl)
			# 右端被上層窓手摺佔用時改放左端（R2 近景審查：單右側卯建被略過，整棟看不到）
			var r_blk := String(rec["type"]) == "nikai" and not ups.is_empty() and String(ups[-1]) != "plain"
			if r_blk and ud == 1:
				ud = 0
			for e in [-1.0, 1.0]:
				if (ud == 0 and e > 0.0) or (ud == 1 and e < 0.0):
					continue
				if e > 0.0 and r_blk:
					continue
				_mi(l0, lib, udn, _xf(0.0, Vector3(e * (w * 0.5 - 0.13), his, d * 0.5)), 0)
		# 看板（無字）
		if pl["sign"] == "roof":
			var cx := clampf(door_c, -w * 0.5 + 1.0, w * 0.5 - 1.0)
			_mi(l0, lib, "kbr_%s" % pl["sign_key"], _xf(0.0, Vector3(cx, his, d * 0.5)), 0)
		elif pl["sign"] == "side":
			var sx := (w * 0.5 - 0.45) * (-1.0 if door_c > 0.0 else 1.0)
			_mi(l0, lib, "kbs_%s" % pl["sign_key"], _xf(0.0, Vector3(sx, his, d * 0.5)), 0)
	elif not shop:
		if pl["kiri"] and int(B["door"]) >= 0 and float(rec1[int(B["door"])]) <= 0.0:
			var bw := float(widths[int(B["door"])]) * k
			_mi(l0, lib, "kiri", _xf(0.0, Vector3(door_c, KIRI_Y, d * 0.5), Vector3(bw / 2.0, 1, 1)), 0)
		if pl["inuyarai"]:
			var xi := -w * 0.5
			for i in widths.size():
				var bw2 := float(widths[i]) * k
				if String(kinds[i]) in ["plain", "koshib", "mado", "amado"]:
					_mi(l0, lib, "iy_%d" % int(round(widths[i] * 100)), _xf(0.0, Vector3(xi, 0, d * 0.5 - float(rec1[i])), Vector3(k, 1, 1)), 0)
				xi += bw2
	# ── LOD1：台基＋牆體方塊＋立面貼片＋屋根三角柱＋庇板 ──
	# R3：LOD1/2 屋根＝前後兩個半屋根（勾配、棟位置、出簷與 LOD0 同）
	var RG := roof_geo(rec, pl)
	var ovg := float(rec["ov_gable_m"])
	var rl := (w if hira else d) + ovg * 2.0
	var lbox := "l_box" if int(pl["fin"]) == 0 else "l_box_c%d" % int(pl["fin"])
	var lrh := "l_rh" if int(pl["tone"]) == 0 else "l_rh_t%d" % int(pl["tone"])
	var hy1 := float(rec.get("hisashi_m", Y1_OF[h1]))
	for li in [1, 2]:
		var g: Node3D = l1 if li == 1 else l2
		_mi(g, lib, "base", _xf(0.0, Vector3(0, bot, 0), Vector3(w, FL - bot, d)), li)
		if sb:
			# R3：2F セットバック也進 LOD1／2（1F 全深＋2F 退 SB_D）
			_mi(g, lib, lbox, _xf(0.0, Vector3(0, FL, 0), Vector3(w, hy1 - FL, d)), li)
			_mi(g, lib, lbox, _xf(0.0, Vector3(0, hy1, -SB_D * 0.5), Vector3(w, eave - hy1, d - SB_D)), li)
		else:
			_mi(g, lib, lbox, _xf(0.0, Vector3(0, FL, 0), Vector3(w, eave - FL, d)), li)
		_roof_acc(g, lib, rec, F, w if hira else d, pl, li)
		for side in [0, 1]:
			var pp := float(RG["pa"]) if side == 0 else float(RG["pb"])
			var spn := float(RG["half"]) + (-1.0 if side == 0 else 1.0) * float(RG["cr"]) + float(RG["ove"])
			var ee := eave - pp * float(RG["ove"])
			_mi(g, lib, lrh, Transform3D(F, Vector3.ZERO) * _xf(PI * side, Vector3(0, ee, float(RG["cr"])), Vector3(rl, float(RG["H"]) - ee, spn)), li)
	var x1 := -w * 0.5
	for i in widths.size():
		var bw: float = widths[i] * k
		var s := Vector3(bw / 1.82, 1, 1)
		var fk := String(kinds[i])
		var lf := "shop" if fk.begins_with("shop") else (fk if fk in ["koshir", "koshib", "amado"] else "res")
		_mi(l1, lib, "l_f1_%s_%s" % [lf, T["h1"]], _xf(0.0, Vector3(x1, 0, d * 0.5), s), 1)
		if T["up"] != "" and widths[i] > 1.0 and String(ups[i]) != "plain":
			var uk := String(ups[i])
			var lu: String = {"mushi": "l_u_mushi", "mushis": "l_u_mushi", "mushib": "l_u_mushib", "win": "l_u_win", "wins": "l_u_win",
				"winb": "l_u_winb", "amado": "l_u_amado"}[uk]
			_mi(l1, lib, lu, _xf(0.0, Vector3(x1, 0, zu), s), 1)
		x1 += bw
	if his > 0.0 and hd > 0.2:
		if sb:
			_mi(l1, lib, "l_slab", _xf(0.0, Vector3(-w * 0.5, his + SB_D * P, zu), Vector3(w, SB_D + hd, SB_D + hd)), 1)
		else:
			_mi(l1, lib, "l_slab", _xf(0.0, Vector3(-w * 0.5, his, d * 0.5), Vector3(w, hd, hd)), 1)
	kit.set_meta("door_cx", snappedf(door_c, 0.001))
	kit.set_meta("door_w", snappedf(float(widths[int(B["door"])]) * k, 0.001) if int(B["door"]) >= 0 else 0.0)
	kit.set_meta("style", "%s/c%d/t%d/%s" % [pl["theme"], int(pl["fin"]), int(pl["tone"]), pl["up"]])
	# R3 紀錄（gate 依此驗屋根與退縮；皆在 P4 外框內）
	kit.set_meta("roof_cls", String(RG["cls"]))
	kit.set_meta("roof_ps", [float(RG["pa"]), float(RG["pb"])])
	kit.set_meta("roof_cr", snappedf(float(RG["cr"]), 0.0001))
	kit.set_meta("roof_h", snappedf(float(RG["H"]), 0.0001))
	kit.set_meta("roof_ove", float(RG["ove"]))
	kit.set_meta("door_rec", float(rec1[int(B["door"])]) if int(B["door"]) >= 0 else 0.0)
	kit.set_meta("r3", "%s/rec=%s:%.2f/sb=%s/dm=%s/udh=%d/cut=%s/corner=%d/hero=%s" % [RG["cls"], pl["rec"], float(pl["rec_d"]), sb,
		pl["dormer"], (pl["udh"] as Array).size(), pl["cut"], (pl["corner"] as Array).size(), pl["hero"]])
	kit.set_meta("bays", widths.size())
	kit.set_meta("bay_scale", snappedf(k, 0.001))
	# R4 門前帶（frontage）依開間佈置：開間邊界 x、1F 種類、入口開間
	kit.set_meta("bay_x", xs)
	kit.set_meta("bay_kind", kinds)
	kit.set_meta("door_i", int(B["door"]))
	return kit


## 灰盒 → Kit（碰撞沿用灰盒 Shape；灰盒網格逐一隱藏，節點保留）
static func apply(body: Node3D, rec: Dictionary, lib: Dictionary, embed: float) -> Node3D:
	var old := body.get_node_or_null("Kit")
	if old != null:
		return old as Node3D
	for nm: String in GB_MESHES:
		var m := body.get_node_or_null(nm) as MeshInstance3D
		if m != null:
			m.visible = false
	var kit := build(rec, lib, embed)
	body.add_child(kit)
	body.set_meta("kit_asset", "machiya_kit")
	return kit


## 一棟 LOD 三角面數
static func lod_tris(kit: Node3D, lod: int) -> int:
	var t := 0
	for mi: MeshInstance3D in kit.get_node("LOD%d" % lod).get_children():
		for si in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(si)
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			t += (idx.size() if not idx.is_empty() else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return t



# ─────────────────────────── P6 R4 門前／街道過渡（Frontage）───────────────────────────
# 範圍＝牆線（z＝d/2）到路緣（地塊臨路線＋front_gap，P3 本來就留給犬走り＋側溝）；x＝地塊臨路邊兩角。
# 不改 parcel／道路／P4 量體：只在這條帶裡鋪地面構件（視覺專用、不加碰撞；踏段碰撞歸 P11）。
# 高度：每段兩端取帶內地形最高點＋FR_LIFT（≈ 道路面；路面本來就高出兩側地形 0.1 m → 補掉路緣唇），
# 段間線性；帶狀構件往下埋 0.24（底一定在地形下）。門前踏段頂＝帶頂與地板中點（一段 0.11–0.16 m）。
const PARCELS := "res://maps/village_v2/gen/parcels.json"
const FR_LIFT := 0.10
const FR_EDGE := 0.01        # 側溝外緣離路緣
const FR_MIN := 0.3          # 地塊臨路邊比建築多出 ≥ 0.3 m 才自成一段（否則併入端開間）
const FR_INU := 0.45         # 退縮住宅的犬走り（含見切り石 0.08）
const FR_MK := 0.08
const FR_STEP_D := 0.34      # 門前踏段／店前踏段深
const FR_BURY := 0.12        # 踏段底在帶頂下
static var _fr: Dictionary = {}


static func _fr_data() -> Dictionary:
	if _fr.is_empty():
		var PJ: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PARCELS))
		var polys := {}
		var boxes := {}
		var prs := {}
		for r: Dictionary in PJ["parcels"]:
			var pp := TLib.pts(r["footprint"])
			polys[String(r["id"])] = pp
			var bx := Rect2(pp[0], Vector2.ZERO)
			for q in pp:
				bx = bx.expand(q)
			boxes[String(r["id"])] = bx
			prs[String(r["id"])] = r
		var LY: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
		var roads: Array = []
		for r: Dictionary in PLib.network(LY):
			for poly: PackedVector2Array in Geometry2D.offset_polyline(r["pts"], float(r["hw"]), Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND):
				var bx := Rect2(poly[0], Vector2.ZERO)
				for q in poly:
					bx = bx.expand(q)
				roads.append([poly, bx])
		_fr = {"polys": polys, "boxes": boxes, "recs": prs, "roads": roads}
	return _fr


## 這一點落在道路／巷道或別人的地塊裡 → 該段不鋪
static func _fr_blocked(p: Vector2, own: String) -> bool:
	var D := _fr_data()
	for rb: Array in D["roads"]:
		if (rb[1] as Rect2).has_point(p) and Geometry2D.is_point_in_polygon(p, rb[0]):
			return true
	for pid: String in D["polys"]:
		if pid != own and (D["boxes"][pid] as Rect2).has_point(p) and Geometry2D.is_point_in_polygon(p, D["polys"][pid]):
			return true
	return false


## 單位構件放進 [x0,x1]×[z0,z0+dz]，頂面在 x0 高 t0、x1 高 t1（剪切 basis 順坡），y 伸縮 sy
static func _fr_put(g: Node3D, lib: Dictionary, mod: String, x0: float, x1: float, t0: float, t1: float, z0: float,
		dz: float, lod: int, sy := 1.0) -> MeshInstance3D:
	return _mi(g, lib, mod, Transform3D(Basis(Vector3(x1 - x0, t1 - t0, 0), Vector3(0, sy, 0), Vector3(0, 0, dz)),
		Vector3(x0, t0, z0)), lod)


## 灰盒 body 前加門前帶（body 局部座標；h_fn(Vector2 世界 xz) → 地形高）。kit＝已組好的 Kit（開間資訊）。
static func frontage(body: Node3D, rec: Dictionary, lib: Dictionary, kit: Node3D, h_fn: Callable) -> Node3D:
	var old := body.get_node_or_null("Frontage")
	if old != null:
		return old as Node3D
	var D := _fr_data()
	var id := String(rec["id"])
	var pid := String(rec["parcel"])
	var pr: Dictionary = D["recs"][pid]
	var d := float(rec["depth_m"])
	var X := body.transform
	var Xi := X.affine_inverse()
	var fe := GLib.front_edge(pr)
	var pa: Vector3 = Xi * Vector3((fe[0] as Vector2).x, 0, (fe[0] as Vector2).y)
	var pb: Vector3 = Xi * Vector3((fe[1] as Vector2).x, 0, (fe[1] as Vector2).y)
	var zw := d * 0.5
	var zp := (pa.z + pb.z) * 0.5
	var zc := zp + float(pr["clearance"]["front_gap_m"]) - FR_EDGE
	var dz := zc - zw
	var xa := minf(pa.x, pb.x)
	var xb := maxf(pa.x, pb.x)
	var xs: Array = kit.get_meta("bay_x")
	var kinds: Array = kit.get_meta("bay_kind")
	var door := int(kit.get_meta("door_i"))
	var door_c := float(kit.get_meta("door_cx"))
	# 段：開間＋兩側地塊餘邊（< FR_MIN 併入端開間）
	var segs: Array = []
	for i in kinds.size():
		segs.append({"x0": float(xs[i]), "x1": float(xs[i + 1]), "k": String(kinds[i]), "door": i == door})
	if float(xs[0]) - xa >= FR_MIN:
		segs.push_front({"x0": xa, "x1": float(xs[0]), "k": "margin", "door": false})
	else:
		segs[0]["x0"] = minf(xa, float(xs[0]))
	if xb - float(xs[-1]) >= FR_MIN:
		segs.append({"x0": float(xs[-1]), "x1": xb, "k": "margin", "door": false})
	else:
		segs[-1]["x1"] = maxf(xb, float(xs[-1]))
	# 帶頂高（body 局部 y）：邊界 x 處取牆線／中／路緣三點地形最高＋FR_LIFT；段中點若更高就把兩端一起抬
	var hx := func(x: float) -> float:
		var m := -INF
		for z in [zw + 0.02, (zw + zc) * 0.5, zc - 0.02]:
			var wp: Vector3 = X * Vector3(x, 0, z)
			m = maxf(m, float(h_fn.call(Vector2(wp.x, wp.z))))
		return m - X.origin.y + FR_LIFT
	var shop := float(rec.get("hisashi_m", 0.0)) > 0.0
	var deep := dz > 1.0                  # 退縮 0.91 的住宅（前帶 1.39）；否則 0.49
	var road_cls := String(pr.get("road_cls", ""))
	var gw := (0.26 if road_cls == "lane" else 0.36) if deep else 0.30
	var inu: String = ["ishi", "jari", "tataki"][_h(id, 60) % 3] if deep else ("ishi" if shop else "jari")
	var fr := Node3D.new()
	fr.name = "Frontage"
	fr.set_meta("asset_id", "machiya_kit")
	fr.set_meta("phase", "P6 R4")
	var g0 := Node3D.new()
	g0.name = "LOD0"
	var g1 := Node3D.new()
	g1.name = "LOD1"
	fr.add_child(g0)
	fr.add_child(g1)
	var kept: Array = []
	var dropped := 0
	for s: Dictionary in segs:
		var x0 := float(s["x0"])
		var x1 := float(s["x1"])
		var bad := false
		for x in [x0 + 0.05, (x0 + x1) * 0.5, x1 - 0.05]:
			for z in [zw + 0.05, zc - 0.03]:
				var wp: Vector3 = X * Vector3(x, 0, z)
				bad = bad or _fr_blocked(Vector2(wp.x, wp.z), pid)
		if bad:
			dropped += 1
			continue
		kept.append(s)
	# 邊界高：相鄰段共用同一個邊界值（避免段間高低差）；段中點地形若高於兩端內插，把兩端邊界一起抬
	var hb := {}
	for s: Dictionary in kept:
		for key in ["x0", "x1"]:
			var xk := snappedf(float(s[key]), 0.001)
			if not hb.has(xk):
				hb[xk] = float(hx.call(xk))
	var hu := {}
	for s: Dictionary in kept:
		var a := snappedf(float(s["x0"]), 0.001)
		var c := snappedf(float(s["x1"]), 0.001)
		var up := maxf(0.0, float(hx.call((a + c) * 0.5)) - (float(hb[a]) + float(hb[c])) * 0.5)
		hu[a] = maxf(float(hu.get(a, 0.0)), up)
		hu[c] = maxf(float(hu.get(c, 0.0)), up)
	for s: Dictionary in kept:
		var a := snappedf(float(s["x0"]), 0.001)
		var c := snappedf(float(s["x1"]), 0.001)
		s["h0"] = float(hb[a]) + float(hu.get(a, 0.0))
		s["h1"] = float(hb[c]) + float(hu.get(c, 0.0))
	var gut_mod := "fr_guto_%d" % int(round(gw * 100))
	var open_run: Array = []
	for s: Dictionary in kept:
		var x0 := float(s["x0"])
		var x1 := float(s["x1"])
		var h0 := float(s["h0"])
		var h1 := float(s["h1"])
		var k := String(s["k"])
		var covered := shop or (not deep and bool(s["door"]))
		# ── LOD0 ──
		if deep:
			_fr_put(g0, lib, "fr_band_" + inu, x0, x1, h0, h1, zw, FR_INU - FR_MK, 0)
			_fr_put(g0, lib, "fr_mikiri", x0, x1, h0, h1, zw + FR_INU - FR_MK, 1.0, 0)
			_fr_put(g0, lib, "fr_band_tsuchi", x0, x1, h0, h1, zw + FR_INU, dz - FR_INU - gw, 0)
		elif shop:
			_fr_put(g0, lib, "fr_band_ishi", x0, x1, h0, h1, zw, dz - gw, 0)
		else:
			_fr_put(g0, lib, "fr_band_jari", x0, x1, h0, h1, zw, dz - gw - FR_MK, 0)
			_fr_put(g0, lib, "fr_mikiri", x0, x1, h0, h1, zw + dz - gw - FR_MK, 1.0, 0)
		if covered:
			var n := 3 if x1 - x0 > 1.2 else 2
			_fr_put(g0, lib, "fr_gutc_%d_%d" % [int(round(gw * 100)), n], x0, x1, h0, h1, zc - gw, 1.0, 0)
		else:
			_fr_put(g0, lib, gut_mod, x0, x1, h0, h1, zc - gw, 1.0, 0)
		s["open"] = not covered
		# 店前踏段：開放店面開間沿牆（半段高）
		if k == "shop_o":
			var r0 := FL - h0
			var r1 := FL - h1
			_fr_put(g0, lib, "fr_dan", x0 + 0.03, x1 - 0.03, h0 + r0 * 0.45, h1 + r1 * 0.45, zw, FR_STEP_D, 0,
				(r0 + r1) * 0.5 * 0.45 + FR_BURY)
		# ── LOD1：地面帶＋遠景側溝 ──
		_fr_put(g1, lib, "fr_band_tsuchi" if deep else ("fr_band_ishi" if shop else "fr_band_jari"), x0, x1, h0, h1, zw, dz - gw, 1)
		_fr_put(g1, lib, "fr_gutl_%d" % int(round(gw * 100)), x0, x1, h0, h1, zc - gw, 1.0, 1)
	# 開渠端部封口（連續開渠段的兩端）
	for i in kept.size():
		var s: Dictionary = kept[i]
		if not bool(s["open"]):
			continue
		var prev_open := i > 0 and bool(kept[i - 1]["open"]) and is_equal_approx(float(kept[i - 1]["x1"]), float(s["x0"]))
		var next_open := i + 1 < kept.size() and bool(kept[i + 1]["open"]) and is_equal_approx(float(kept[i + 1]["x0"]), float(s["x1"]))
		var cap := "fr_gutk_%d" % int(round(gw * 100))
		# 封口面朝溝內：左端朝 +x（原樣），右端轉 180°
		if not prev_open:
			_mi(g0, lib, cap, Transform3D(Basis.IDENTITY, Vector3(float(s["x0"]), float(s["h0"]), zc - gw)), 0)
		if not next_open:
			_mi(g0, lib, cap, Transform3D(Basis(Vector3.UP, PI), Vector3(float(s["x1"]), float(s["h1"]), zc)), 0)
	# 入口：沓脱石（門前小台階）＋入口前地面＋跨溝
	var ds: Dictionary = {}
	for s: Dictionary in kept:
		if bool(s["door"]):
			ds = s
	var apron := "none"
	if not ds.is_empty() and String(ds["k"]) != "shop_o":
		var x0 := float(ds["x0"])
		var x1 := float(ds["x1"])
		var t := clampf((door_c - x0) / maxf(0.01, x1 - x0), 0.0, 1.0)
		var hc := lerpf(float(ds["h0"]), float(ds["h1"]), t)
		var rise := FL - hc
		var sw := minf(1.2, (x1 - x0) * 0.75)
		_mi(g0, lib, "fr_step", Transform3D(Basis(Vector3(sw, 0, 0), Vector3(0, rise * 0.5 + FR_BURY, 0), Vector3(0, 0, FR_STEP_D)),
			Vector3(door_c, hc + rise * 0.5, zw)), 0)
		if deep:
			var zone := dz - FR_INU - gw
			var z0 := zw + FR_INU
			match _h(id, 61) % 3:
				0:
					apron = "shiki"
					_mi(g0, lib, "fr_shiki", Transform3D(Basis(Vector3.RIGHT, Vector3.UP, Vector3(0, 0, zone / 0.6)), Vector3(door_c, hc + 0.015, z0)), 0)
				1:
					apron = "fumi"
					var st: Array = ["a", "b", "c"]
					for j in 2:
						var sk := String(st[(_h(id, 62) + j) % 3])
						var ang := float(_h(id, 63 + j) % 360) * PI / 180.0
						_mi(g0, lib, "fr_fumi_" + sk, Transform3D(Basis(Vector3.UP, ang), Vector3(door_c + (0.07 if j == 0 else -0.06),
							hc + 0.02, z0 + zone * (0.3 if j == 0 else 0.74))), 0)
				_:
					apron = "tataki"
					_fr_put(g0, lib, "fr_band_tataki", door_c - 0.5, door_c + 0.5, hc + 0.012, hc + 0.012, z0, zone, 0)
			_mi(g0, lib, "fr_hashi_%d" % int(round(gw * 100)), Transform3D(Basis(Vector3(0.8, 0, 0), Vector3.UP, Vector3.BACK),
				Vector3(door_c, hc + 0.006, zc - gw)), 0)
	fr.set_meta("zone", [snappedf(zw, 0.001), snappedf(zc, 0.001)])
	fr.set_meta("gutter", "%s %.2f" % ["covered" if shop else ("open" if deep else "open+door_cover"), gw])
	fr.set_meta("style", "%s/%s/%s" % ["deep" if deep else "shallow", inu, apron])
	fr.set_meta("segs", kept.size())
	fr.set_meta("dropped", dropped)
	body.add_child(fr)
	return fr

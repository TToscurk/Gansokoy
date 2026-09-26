extends RefCounted
## 人間之里 V2 P6 R1／R2：模組化町家 Kit 組裝（新資產；不引用任何舊房屋資產）。
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
## 構件只沿設計好的方向伸縮：開間 x ±12 % 內；屋面／螻羽／妻壁 y、z 同比（pitch 不變）；台基與 LOD 外殼單位方塊。
## 碰撞：沿用 P4 灰盒 BoxShape3D（不另建；P4 碰撞已核准）。
##
## apply(body, rec, lib, embed)：把一棟灰盒換成 Kit——灰盒網格逐一 visible＝false（節點保留，P4 gate 讀位置），
##   碰撞不動；body 下加 "Kit"（LOD0／LOD1／LOD2 三組 MeshInstance3D，visibility_range 硬切＋margin）。

const MESH_DIR := "res://assets/village_v2/machiya_kit/mesh/"
const P := 0.45
const FL := 0.32
const HU := 0.53
const RU := 2.12
const SPANS := [2.0, 2.5, 3.0, 3.5, 4.0, 4.5, 5.0, 5.5, 6.0]
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
	for b: Dictionary in recs:
		var id := String(b["id"])
		var row: Array = []
		var acr: Array = []
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
		var shop := float(b.get("hisashi_m", 0.0)) > 0.0
		var typ := String(b["type"])
		var pl := {}
		pl["fin"] = _pick(id, 11, [0, 1, 2, 3, 4], row.map(func(q): return q["fin"]) + acr.map(func(q): return q["fin"]))
		pl["tone"] = _pick(id, 12, [0, 1, 2], row.map(func(q): return q["tone"]))
		var themes: Array = (SHOP_THEMES if shop else RES_THEMES).keys()
		pl["theme"] = _pick(id, 13, themes, row.map(func(q): return q["theme"]) + acr.map(func(q): return q["theme"]))
		var ups: Array = UP_ZUSHI if typ == "zushi" else (UP_NIKAI if typ == "nikai" else [""])
		pl["up"] = _pick(id, 14, ups, row.map(func(q): return q["up"]))
		pl["up_period"] = [0, 2, 3][_h(id, 15) % 3]
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
		pl["kemuri"] = typ != "nikai" and _h(id, 26) % 5 == 0
		pl["split"] = _h(id, 27) % 100 < (35 if shop else 45)   # 半間柱割（店也可；入口開間不拆）
		_plan[id] = pl


static func plan_for(rec: Dictionary) -> Dictionary:
	if _plan.is_empty():
		_build_plan()
	return _plan.get(String(rec["id"]), {"fin": 0, "tone": 0, "theme": "koshi", "up": "", "up_period": 0, "hang": "noren_a",
		"his_wood": false, "udatsu": -1, "sign": "", "sign_key": "kanban", "kiri": false, "inuyarai": false,
		"ridge_low": false, "oni_b": false, "kemuri": false, "split": false})


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
		y := 0.0) -> void:
	var x := -w * 0.5
	for i in widths.size():
		var bw: float = widths[i] * k
		if front:
			_mi(g, lib, names[i], _xf(0.0, Vector3(x, y, zf), Vector3(k, 1, 1)), 0)
		else:
			_mi(g, lib, names[i], _xf(PI, Vector3(-x, y, zf), Vector3(k, 1, 1)), 0)
		x += bw


## 屋面、螻羽、棟、鬼瓦、妻壁（屋根座標 F：棟沿 F.x；平入 F＝I，妻入 F＝Ry(−90°)→棟沿 +z）
static func _roof(g: Node3D, lib: Dictionary, rec: Dictionary, F: Basis, wall_len: float, half: float, pl: Dictionary) -> void:
	var ridge := float(rec["ridge_m"])
	var eave := float(rec["eave_m"])
	var ove := float(rec["ov_eave_m"])
	var ovg := float(rec["ov_gable_m"])
	var L := wall_len + ovg * 2.0
	var S := half + ove - EAVE_TRIM
	var sg := _nearest_span(S)
	var kz := S / sg
	var Lp := L - END_TRIM * 2.0
	var n := maxi(1, int(round(Lp / HU)))
	var kx := Lp / (n * HU)
	var units: Array = []
	var left := n
	for u in [4, 2, 1]:
		while left >= u:
			units.append(u)
			left -= u
	var sgk := "%d" % int(round(sg * 100))
	for side in [0, 1]:
		var x := -Lp * 0.5
		for u: int in units:
			var ln := u * HU * kx
			var lx := x if side == 0 else -x
			var loc := Transform3D(Basis(Vector3.UP, PI * side).scaled_local(Vector3(kx, kz, kz)), Vector3(lx, ridge, 0))
			_mi(g, lib, _rn("rf_%s_%d" % [sgk, u], pl), Transform3D(F, Vector3.ZERO) * loc, 0)
			x += ln
		for e in [-1.0, 1.0]:
			# 螻羽（袖瓦半徑 0.075）內縮：外緣＝屋面端（不超出 P4 屋根，出簷 0.05 的鄰棟側不越地塊線）
			var loc := Transform3D(Basis(Vector3.UP, PI * side).scaled_local(Vector3(1, kz, kz)), Vector3(e * (L * 0.5 - VERGE_IN), ridge, 0))
			_mi(g, lib, _rn("vg_%s" % sgk, pl), Transform3D(F, Vector3.ZERO) * loc, 0)
	_mi(g, lib, _rn("rg_l" if pl["ridge_low"] else "rg_u", pl), Transform3D(F, Vector3.ZERO) * Transform3D(Basis().scaled_local(Vector3((L - 2.0 * ONI_IN) / RU, 1, 1)),
		Vector3(-L * 0.5 + ONI_IN, ridge, 0)), 0)
	for e in [-1.0, 1.0]:
		_mi(g, lib, _rn("oni_b" if pl["oni_b"] else "oni", pl), Transform3D(F, Vector3.ZERO) * Transform3D(Basis(), Vector3(e * (L * 0.5 - ONI_IN), ridge, 0)), 0)
	if pl["kemuri"]:
		var kmx := (1.0 if _h(String(rec["id"]), 29) % 2 == 0 else -1.0) * L * 0.2
		_mi(g, lib, _rn("kemu", pl), Transform3D(F, Vector3.ZERO) * Transform3D(Basis(), Vector3(kmx, ridge, 0)), 0)
	# 妻壁：牆線上方、簷高起；面向 ±F.x
	var gs := _nearest_span(half)
	var kg := half / gs
	for e in [-1.0, 1.0]:
		var loc := Transform3D(Basis(Vector3.UP, e * PI * 0.5).scaled_local(Vector3(kg, kg, 1)), Vector3(e * wall_len * 0.5, eave, 0))
		_mi(g, lib, _wn("gb_%d" % int(round(gs * 100)), pl), Transform3D(F, Vector3.ZERO) * loc, 0)


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
	var ridge := float(rec["ridge_m"])
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
	_row(l0, lib, f1, widths, k, w, d * 0.5, true)
	if not up.is_empty():
		_row(l0, lib, up, widths, k, w, d * 0.5, true)
	_row(l0, lib, bk, widths, k, w, -d * 0.5, false)
	var xh := -w * 0.5
	for i in widths.size():
		if hg[i] != "":
			_mi(l0, lib, hg[i], _xf(0.0, Vector3(xh, 0, d * 0.5), Vector3(k, 1, 1)), 0)
		xh += float(widths[i]) * k
	_mi(l0, lib, _wn("post_%s" % ek, pl), _xf(0.0, Vector3(w * 0.5, 0, d * 0.5)), 0)
	_mi(l0, lib, _wn("post_%s" % ek, pl), _xf(PI, Vector3(-w * 0.5, 0, -d * 0.5)), 0)
	var kd := d / float(DEPTHS[dk])
	for e in [-1.0, 1.0]:
		_mi(l0, lib, _wn("sd_%s_%s" % [dk, ek], pl), _xf(e * PI * 0.5, Vector3(e * w * 0.5, 0, 0), Vector3(kd, 1, 1)), 0)
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
		for u in [4, 2, 1]:
			while left >= u:
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
		if pl["kiri"] and int(B["door"]) >= 0:
			var bw := float(widths[int(B["door"])]) * k
			_mi(l0, lib, "kiri", _xf(0.0, Vector3(door_c, KIRI_Y, d * 0.5), Vector3(bw / 2.0, 1, 1)), 0)
		if pl["inuyarai"]:
			var xi := -w * 0.5
			for i in widths.size():
				var bw2 := float(widths[i]) * k
				if String(kinds[i]) in ["plain", "koshib", "mado", "amado"]:
					_mi(l0, lib, "iy_%d" % int(round(widths[i] * 100)), _xf(0.0, Vector3(xi, 0, d * 0.5), Vector3(k, 1, 1)), 0)
				xi += bw2
	# ── LOD1：台基＋牆體方塊＋立面貼片＋屋根三角柱＋庇板 ──
	var ee := float(rec["eave_edge_m"])
	var ove := float(rec["ov_eave_m"])
	var ovg := float(rec["ov_gable_m"])
	var span := ((d if hira else w) * 0.5 + ove) * 2.0
	var rl := (w if hira else d) + ovg * 2.0
	var roof_xf := Transform3D(F, Vector3.ZERO) * _xf(0.0, Vector3(0, ee, 0), Vector3(rl, ridge - ee, span))
	var lbox := "l_box" if int(pl["fin"]) == 0 else "l_box_c%d" % int(pl["fin"])
	var lroof := "l_roof" if int(pl["tone"]) == 0 else "l_roof_t%d" % int(pl["tone"])
	for li in [1, 2]:
		var g: Node3D = l1 if li == 1 else l2
		_mi(g, lib, "base", _xf(0.0, Vector3(0, bot, 0), Vector3(w, FL - bot, d)), li)
		_mi(g, lib, lbox, _xf(0.0, Vector3(0, FL, 0), Vector3(w, eave - FL, d)), li)
		_mi(g, lib, lroof, roof_xf, li)
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
			_mi(l1, lib, lu, _xf(0.0, Vector3(x1, 0, d * 0.5), s), 1)
		x1 += bw
	if his > 0.0 and hd > 0.2:
		_mi(l1, lib, "l_slab", _xf(0.0, Vector3(-w * 0.5, his, d * 0.5), Vector3(w, hd, hd)), 1)
	kit.set_meta("door_cx", snappedf(door_c, 0.001))
	kit.set_meta("door_w", snappedf(float(widths[int(B["door"])]) * k, 0.001) if int(B["door"]) >= 0 else 0.0)
	kit.set_meta("style", "%s/c%d/t%d/%s" % [pl["theme"], int(pl["fin"]), int(pl["tone"]), pl["up"]])
	kit.set_meta("bays", widths.size())
	kit.set_meta("bay_scale", snappedf(k, 0.001))
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

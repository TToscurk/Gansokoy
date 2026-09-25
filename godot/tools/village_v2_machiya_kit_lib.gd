extends RefCounted
## 人間之里 V2 P6 R1：模組化町家 Kit 組裝（新資產；不引用任何舊房屋資產）。
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
	return absi(hash(id + ":" + str(salt)))


static func _front_kinds(rec: Dictionary, B: Dictionary) -> Array:
	var shop := float(rec.get("hisashi_m", 0.0)) > 0.0   # P4：庇＝店先（shopfront）才有
	var id := String(rec["id"])
	var widths: Array = B["widths"]
	var out: Array = []
	var res_cycle := ["koshi", "mado", "koshi", "plain"]
	var shop_cycle := ["shop_c", "shop_d", "koshi", "shop_c"]
	var r0 := _h(id, 1) % 4
	for i in widths.size():
		if i == int(B["door"]):
			out.append(("shop_a" if _h(id, 2) % 2 == 0 else "shop_b") if shop else "door")
		elif shop:
			out.append(shop_cycle[(i + r0) % 4])
		else:
			out.append(res_cycle[(i + r0) % 4] if widths[i] > 1.0 else ("koshi" if _h(id, 3 + i) % 2 == 0 else "plain"))
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
static func _roof(g: Node3D, lib: Dictionary, rec: Dictionary, F: Basis, wall_len: float, half: float) -> void:
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
			_mi(g, lib, "rf_%s_%d" % [sgk, u], Transform3D(F, Vector3.ZERO) * loc, 0)
			x += ln
		for e in [-1.0, 1.0]:
			# 螻羽（袖瓦半徑 0.075）內縮：外緣＝屋面端（不超出 P4 屋根，出簷 0.05 的鄰棟側不越地塊線）
			var loc := Transform3D(Basis(Vector3.UP, PI * side).scaled_local(Vector3(1, kz, kz)), Vector3(e * (L * 0.5 - VERGE_IN), ridge, 0))
			_mi(g, lib, "vg_%s" % sgk, Transform3D(F, Vector3.ZERO) * loc, 0)
	_mi(g, lib, "rg_u", Transform3D(F, Vector3.ZERO) * Transform3D(Basis().scaled_local(Vector3((L - 2.0 * ONI_IN) / RU, 1, 1)),
		Vector3(-L * 0.5 + ONI_IN, ridge, 0)), 0)
	for e in [-1.0, 1.0]:
		_mi(g, lib, "oni", Transform3D(F, Vector3.ZERO) * Transform3D(Basis(), Vector3(e * (L * 0.5 - ONI_IN), ridge, 0)), 0)
	# 妻壁：牆線上方、簷高起；面向 ±F.x
	var gs := _nearest_span(half)
	var kg := half / gs
	for e in [-1.0, 1.0]:
		var loc := Transform3D(Basis(Vector3.UP, e * PI * 0.5).scaled_local(Vector3(kg, kg, 1)), Vector3(e * wall_len * 0.5, eave, 0))
		_mi(g, lib, "gb_%d" % int(round(gs * 100)), Transform3D(F, Vector3.ZERO) * loc, 0)


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
	var B := bays(w, float(rec["door_local_x"]))
	var widths: Array = B["widths"]
	var k := float(B["k"])
	var kinds := _front_kinds(rec, B)
	# ── LOD0 ──
	_mi(l0, lib, "base", _xf(0.0, Vector3(0, bot, 0), Vector3(w, FL - bot, d)), 0)
	var f1: Array = []
	var up: Array = []
	var bk: Array = []
	for i in widths.size():
		var wc := "%d" % int(round(widths[i] * 100))
		f1.append("f1_%s_%s_%s" % [kinds[i], wc, T["h1"]])
		if T["up"] != "":
			var uk := ("mushi" if T["up"] == "27" else "win") if widths[i] > 1.0 else "plain"
			up.append("u_%s_%s_%s" % [uk, wc, T["up"]])
		bk.append("bk_%s_%s_%s" % [("win" if (i % 2 == 1 and widths[i] > 1.0) else "plain"), wc, ek])
	_row(l0, lib, f1, widths, k, w, d * 0.5, true)
	if not up.is_empty():
		_row(l0, lib, up, widths, k, w, d * 0.5, true)
	_row(l0, lib, bk, widths, k, w, -d * 0.5, false)
	_mi(l0, lib, "post_%s" % ek, _xf(0.0, Vector3(w * 0.5, 0, d * 0.5)), 0)
	_mi(l0, lib, "post_%s" % ek, _xf(PI, Vector3(-w * 0.5, 0, -d * 0.5)), 0)
	var kd := d / float(DEPTHS[dk])
	for e in [-1.0, 1.0]:
		_mi(l0, lib, "sd_%s_%s" % [dk, ek], _xf(e * PI * 0.5, Vector3(e * w * 0.5, 0, 0), Vector3(kd, 1, 1)), 0)
	var F := Basis() if hira else Basis(Vector3.UP, -PI * 0.5)
	_roof(l0, lib, rec, F, w if hira else d, (d if hira else w) * 0.5)
	var his := float(rec.get("hisashi_m", 0.0))
	var hd := float(rec.get("hisashi_depth_m", 0.0))
	if his > 0.0 and hd > 0.2:
		var n := maxi(1, int(round(w / HU)))
		var kx := w / (n * HU)
		var x := -w * 0.5
		var left := n
		for u in [4, 2, 1]:
			while left >= u:
				_mi(l0, lib, "his_%d" % u, _xf(0.0, Vector3(x, his, d * 0.5), Vector3(kx, (hd - HIS_TRIM) / 0.45, (hd - HIS_TRIM) / 0.45)), 0)
				x += u * HU * kx
				left -= u
	# ── LOD1：台基＋牆體方塊＋立面貼片＋屋根三角柱＋庇板 ──
	var ee := float(rec["eave_edge_m"])
	var ove := float(rec["ov_eave_m"])
	var ovg := float(rec["ov_gable_m"])
	var span := ((d if hira else w) * 0.5 + ove) * 2.0
	var rl := (w if hira else d) + ovg * 2.0
	var roof_xf := Transform3D(F, Vector3.ZERO) * _xf(0.0, Vector3(0, ee, 0), Vector3(rl, ridge - ee, span))
	for li in [1, 2]:
		var g: Node3D = l1 if li == 1 else l2
		_mi(g, lib, "base", _xf(0.0, Vector3(0, bot, 0), Vector3(w, FL - bot, d)), li)
		_mi(g, lib, "l_box", _xf(0.0, Vector3(0, FL, 0), Vector3(w, eave - FL, d)), li)
		_mi(g, lib, "l_roof", roof_xf, li)
	var shop := his > 0.0
	var x1 := -w * 0.5
	for i in widths.size():
		var bw: float = widths[i] * k
		var s := Vector3(bw / 1.82, 1, 1)
		_mi(l1, lib, "l_f1_%s_%s" % [("shop" if shop else "res"), T["h1"]], _xf(0.0, Vector3(x1, 0, d * 0.5), s), 1)
		if T["up"] != "" and widths[i] > 1.0:
			_mi(l1, lib, "l_u_mushi" if T["up"] == "27" else "l_u_win", _xf(0.0, Vector3(x1, 0, d * 0.5), s), 1)
		x1 += bw
	if his > 0.0 and hd > 0.2:
		_mi(l1, lib, "l_slab", _xf(0.0, Vector3(-w * 0.5, his, d * 0.5), Vector3(w, hd, hd)), 1)
	var dxc := -w * 0.5
	for i in int(B["door"]):
		dxc += float(widths[i]) * k
	kit.set_meta("door_cx", snappedf(dxc + float(widths[int(B["door"])]) * k * 0.5, 0.001) if int(B["door"]) >= 0 else 0.0)
	kit.set_meta("door_w", snappedf(float(widths[int(B["door"])]) * k, 0.001) if int(B["door"]) >= 0 else 0.0)
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

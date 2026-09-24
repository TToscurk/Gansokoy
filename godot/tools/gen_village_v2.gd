extends SceneTree
## 人間之里 V2 — 第一輪 blockout 產生器（V2 全面重製計畫 §53 A–C）。
##
##   Godot --headless --path godot --script tools/gen_village_v2.gd
##
## 唯一座標來源：maps/village_v2/layout_v2.json（World Layout，LAYOUT_PROTOTYPE）。
## 產出（可重跑覆寫；改佈局 → 改 JSON → 重跑，不要在編輯器手改本場景）：
##   maps/village_v2/village_v2.tscn   §2 階層。只有地形、水道線、道路線、林冠團塊、
##                                     地標／任務錨點／傳送點 placeholder——無正式資產。
##   maps/village_v2/gen/*.res          地形、水面、道路、林冠網格與地形碰撞
##   data/village_v2.meta.json          開發用 --map=village_v2；正式傳送仍指向 slice（§52）
##   tools/shots/village_v2_fixed_shots.json   ART_REVIEW 固定機位（r1 解算值凍結成絕對座標，每輪同機位；
##                                             tools\capture-godot.cmd -Map village_v2 -Shotlist res://tools/shots/village_v2_fixed_shots.json）
##   tools/shots/village_v2_mainstreet_variant_shots.json   主街寬度 Variant 比較機位（三個 Variant 共用）
##
## 主街寬度 Variant（layout variants.main_street_width；預設＝selected）：
##   Godot --headless --path godot --script tools/gen_village_v2.gd -- --variant=W80
## 只改 MainStreet 路面半寬（連帶路面整地帶與林冠退讓）；場景仍寫到同一個 village_v2.tscn，
## 最後一次產生的 Variant 就是場景現況。
##
## 施工順序照 §1：大地形 → 水系（刻進地形）→ 道路 → 地塊整平 → placeholder。
## 地形分三類（§6）：Natural（丘陵噪訊）／Built（建成區平台＝基準面）／Transition（平台外填挖坡）。
## P1 Terrain：平台外框、填挖坡、參道縱坡的算法在 tools/village_v2_terrain_lib.gd（與驗證共用）；
##   參數在 layout_v2.json 的 terrain（不在 Macro 凍結範圍）。驗收：tools/verify_village_v2_terrain.gd。
## P2 Water：水線以下河床形態（tools/village_v2_water_lib.gd，參數 layout water_form）與貼岸線的網格水面。
##   權限：只改水線以下與岸線縫；水線以上 P1 核准地形由 tools/verify_village_v2_p1_protect.gd 把關。
##   驗收：tools/verify_village_v2_water.gd。
## P3 Roads / Parcels：巷道層（layout lanes，獨立於凍結的 roads，路面貼 P1 平台、不整地）與單棟地塊
##   （layout parcel_rules；算法 tools/village_v2_parcel_lib.gd）。產出 Roads/Alleys/Lanes、Districts/<區>/Parcels、
##   maps/village_v2/gen/parcels.json（§11 地塊紀錄）。驗收：tools/verify_village_v2_parcels.gd。

const Freeze := preload("res://tools/village_v2_freeze.gd")
const TLib := preload("res://tools/village_v2_terrain_lib.gd")
const WLib := preload("res://tools/village_v2_water_lib.gd")
const PLib := preload("res://tools/village_v2_parcel_lib.gd")
const LAYOUT := "res://maps/village_v2/layout_v2.json"
const GEN := "res://maps/village_v2/gen/"
const SCENE := "res://maps/village_v2/village_v2.tscn"
const META := "res://data/village_v2.meta.json"
const EDGES := "res://maps/village_v2/gen/terrain_edges.json"
const PARCELS := "res://maps/village_v2/gen/parcels.json"
const LANE_LIFT := 0.06        # 巷道路面高出 P1 地形（不整地；比道路 +0.10 低，接頭處道路蓋在上面）
const PARCEL_LINE_LIFT := 0.07
const PARCEL_COL := {
	"Market": Color(0.93, 0.62, 0.30), "MixedCommercial": Color(0.55, 0.62, 0.86),
	"ResidentialWest": Color(0.52, 0.74, 0.40), "ResidentialNE": Color(0.36, 0.70, 0.62),
	"MansionEstate": Color(0.86, 0.72, 0.36), "SouthGate": Color(0.80, 0.56, 0.44),
	"landmark": Color(0.86, 0.32, 0.78)}
const SHOT_FILE := "res://tools/shots/village_v2_fixed_shots.json"
const VARIANT_SHOT_FILE := "res://tools/shots/village_v2_mainstreet_variant_shots.json"
const FONT := "res://assets/fonts/NotoSerifTC-VF.ttf"

## 反照率：色盤先照「看起來對」挑色，再統一乘 ALBEDO_K 壓回真實地表反照率（草地／土約 0.15–0.30）。
## 實測（swatch_probe，天象系統 11:00，太陽 1.55、仰角 75°）：
##   反照率 0.25 → Compatibility 輸出 164 / Forward+ 107；0.45 → 240 / 188；≥0.55 在 Compatibility 全白。
## 第一輪直接用挑色值（0.42–0.86）→ 地面 58–70% 像素 >240（過曝、路與地分不開）。
## V1 同光照地面讀值約 100–150。K=0.42 讓主要地表落在 Compatibility ~110–200。
const ALBEDO_K := 0.42
const C_GRASS := Color(0.42 * ALBEDO_K, 0.52 * ALBEDO_K, 0.32 * ALBEDO_K)
const C_BED := Color(0.36 * ALBEDO_K, 0.32 * ALBEDO_K, 0.27 * ALBEDO_K)
const C_ROCK := Color(0.50 * ALBEDO_K, 0.49 * ALBEDO_K, 0.46 * ALBEDO_K)
## 建成區地面＝踩實的土（概念圖町家之間是土／砂地）。分區色只混 30 %：
## 俯視仍分得出區，人眼高度不會把藍灰分區色讀成「缺地形的洞」（r1 p3 審圖）。
const C_BUILT := Color(0.54 * ALBEDO_K, 0.53 * ALBEDO_K, 0.41 * ALBEDO_K)
const C_CANOPY := Color(0.19 * ALBEDO_K * 1.6, 0.32 * ALBEDO_K * 1.6, 0.17 * ALBEDO_K * 1.6)
const ROAD_COL := {
	"main": Color(0.86 * ALBEDO_K, 0.80 * ALBEDO_K, 0.66 * ALBEDO_K),
	"secondary": Color(0.76 * ALBEDO_K, 0.70 * ALBEDO_K, 0.57 * ALBEDO_K),
	"alley": Color(0.68 * ALBEDO_K, 0.62 * ALBEDO_K, 0.52 * ALBEDO_K),
	"farm": Color(0.56 * ALBEDO_K, 0.49 * ALBEDO_K, 0.37 * ALBEDO_K)}
const ROAD_GROUP := {"main": "MainStreet", "secondary": "SecondaryRoads",
	"alley": "Alleys", "farm": "FarmPaths"}

var L: Dictionary
var H: Dictionary
var x0 := 0.0
var z0 := 0.0
var step := 2.0
var nx := 0
var nz := 0
var feather := 10.0
var pad_feather := 5.0
const PAD_BANK_SLOPE := 0.70   # tan(35°)：地塊填挖坡上限
var hg := PackedFloat32Array()   # 最終地形高度（已刻水道）
var hl := PackedFloat32Array()   # 刻水道前的地面
var wbv := PackedFloat32Array()  # 建成區權重
var wfv := PackedFloat32Array()  # 農田權重
var didv := PackedInt32Array()   # 建成區索引
var noise := FastNoiseLite.new()
var noise2 := FastNoiseLite.new()
var font: Font
var vroot: Node3D
var polys := {}
var pbox := {}
var built: Array[String] = []
var pads: Array[Vector4] = []    # x, z, 半徑, 整平高度
var outlines: Array = []         # 建成區平台外框（TLib.built_outlines）
var apron := 3.0                 # 平台在外框外多留的平地（m）
var river_pts := PackedVector2Array()
var river_hw := PackedFloat32Array()
var polish := {}   # terrain.river_bank_polish
var river_cum := PackedFloat32Array()
var river_form := {}   # water_form.MainRiver（P2）
var river_kap := PackedFloat32Array()
var water_stats: Array = []
## 水渠與細渠：{name,label,pts,hw,margin,wdepth,cap,below,cum,lv}
## lv = 沿中心線每 1 m 的水位，取「上游累積最小值」→ 水只會往下游流，不會爬坡。
var channels: Array = []
var roads: Array = []
var bridges: Array = []          # 用來去重：[road_name, Vector2]
var _mats := {}
var _wb := 0.0
var _wf := 0.0
var _did := -1
var variant := ""                # 主街寬度 Variant（空＝layout 的 selected）
var span_errors: Array[String] = []   # 橋長超出 terrain.bridge_spans 容許範圍
var tri_stats := {"quads": 0, "flip": 0, "fan": 0}
var edge_stats := {}


func _init() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("[v2] 讀不到或解析失敗：" + LAYOUT)
		quit(1)
		return
	L = parsed
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--variant="):
			variant = a.substr(10)
	# LAYOUT_FREEZE（2026-09-24）：凍結的 Macro Layout 被改、或要產生非核可主街 Variant → 拒絕產生
	var ferr: String = Freeze.check(L)
	if ferr == "":
		ferr = Freeze.check_variant(L, variant)
	if ferr != "":
		push_error("[v2] " + ferr)
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(GEN))
	_setup()
	_grid()
	vroot = Node3D.new()
	vroot.name = "VillageV2"
	# own_colliders：main.gd 不再對整張圖烤 trimesh，也不套 web 版碰撞箱
	vroot.set_meta("own_colliders", true)
	vroot.set_meta("layout_version", String(L["version"]))
	vroot.set_meta("layout_status", String(L["status"]))
	vroot.set_meta("main_street_variant", variant)
	for g in ["Lighting", "Terrain", "Water", "Roads", "Districts", "Landmarks",
			"QuestAnchors", "Vegetation", "Props", "Collision", "Navigation",
			"Portals", "Debug"]:
		_group(vroot, g)
	_sky()
	for g in ["MainStreet", "SecondaryRoads", "Alleys", "FarmPaths", "Bridges"]:
		_group(vroot.get_node("Roads"), g)
	_group(vroot.get_node("Debug"), "Labels")
	for g in ["Streams", "Waterfalls"]:
		_group(vroot.get_node("Water"), g)
	_terrain()
	_water()
	_roads()
	if not span_errors.is_empty():
		for e in span_errors:
			push_error("[v2] " + e)
		vroot.free()
		quit(3)
		return
	_districts()
	_parcels()
	_forests()
	_landmarks()
	_anchors()
	_portals()
	_debug()
	_own(vroot, vroot)
	var ps := PackedScene.new()
	var err := ps.pack(vroot)
	if err != OK:
		push_error("[v2] pack 失敗 %d" % err)
		quit(1)
		return
	err = ResourceSaver.save(ps, SCENE)
	print("[v2] 存檔 %s → %s" % [SCENE, error_string(err)])
	_write_meta()
	_write_shots()
	_report()
	vroot.free()
	quit()


# ─────────────────────────── 設定 ───────────────────────────

func _setup() -> void:
	var F: Dictionary = L["frame"]
	x0 = float(F["x0"])
	z0 = float(F["z0"])
	step = float(F["grid_step"])
	nx = int(round((float(F["x1"]) - x0) / step)) + 1
	nz = int(round((float(F["z1"]) - z0) / step)) + 1
	H = L["heights"]
	feather = float(H["feather"])
	pad_feather = float(H["pad_feather"])
	var R: Dictionary = L["relief"]
	noise.seed = int(R["seed"])
	noise.frequency = float(R["noise_freq"])
	noise2.seed = int(R["seed"]) + 7
	noise2.frequency = 0.035
	font = load(FONT)
	var D: Dictionary = L["districts"]
	for k in D:
		_add_poly(k, D[k]["poly"])
		if String(D[k]["kind"]) == "built":
			built.append(k)
	outlines = TLib.built_outlines(L)
	apron = TLib.param(L, "platform_apron")
	var FO: Dictionary = L["forests"]
	for k in FO:
		if typeof(FO[k]) == TYPE_DICTIONARY and FO[k].has("poly"):
			_add_poly(k, FO[k]["poly"])
	var W: Dictionary = L["water"]
	river_pts = _pts(W["MainRiver"]["pts"])
	for v in W["MainRiver"]["half_w"]:
		river_hw.append(float(v))
	river_cum = WLib.cum_len(river_pts)
	var WF: Dictionary = L.get("water_form", {})
	river_form = WF.get("MainRiver", {})
	if not river_form.is_empty():
		river_kap = WLib.curvature(river_pts, float(river_form["curv_win"]))
	polish = L.get("terrain", {}).get("river_bank_polish", {})
	if not polish.is_empty():
		print("[v2] 岸坡整修：(%s)→(%s) %s 岸，岸寬 %+.1f ±%.1f m、水線以上坡形指數 %.2f ±%.2f（下限 2）、坡寬下限 %.0f m、岸肩下降 %.2f ±%.2f m（離河中心 %.0f m 內）" % [
			str(polish["from"]), str(polish["to"]), "右" if float(polish["side"]) < 0.0 else "左",
			float(polish["width_bias"]), _amp(polish["width_waves"]), float(polish["shape_k"]), _amp(polish["shape_waves"]),
			float(polish["bank_min_w"]),
			float(polish["top_drop"]), _amp(polish["top_waves"]), float(polish["rim_r"])])
	channels.append({"name": "Canal", "label": String(W["Canal"]["label"]),
		"pts": _pts(W["Canal"]["pts"]), "hw": float(W["Canal"]["half_w"]), "margin": 1.4,
		"wdepth": float(H["canal_water_depth"]), "cap": float(H["canal_max_water"]),
		"below": float(H["canal_depth_below_land"])})
	for s in W["Streams"]:
		channels.append({"name": String(s["name"]), "label": String(s["label"]),
			"pts": _pts(s["pts"]), "hw": float(s["half_w"]), "margin": 1.2,
			"wdepth": float(H["stream_bed_below_land"]) - float(H["stream_water_below_land"]),
			"cap": INF, "below": float(H["stream_water_below_land"])})
	# 主街寬度 Variant：只覆寫指定道路的半寬
	var vroad := ""
	var vhw := 0.0
	var VW: Dictionary = L.get("variants", {}).get("main_street_width", {})
	if not VW.is_empty():
		if variant == "":
			variant = String(VW["selected"])
		if not VW["options"].has(variant):
			push_error("[v2] 沒有這個主街 Variant：%s（可用 %s）" % [variant, VW["options"].keys()])
			quit(1)
			return
		vroad = String(VW["road"])
		vhw = float(VW["options"][variant]["half_w"])
	for r in L["roads"]:
		var rhw := float(r["half_w"])
		if String(r["name"]) == vroad:
			rhw = vhw
		roads.append({"name": String(r["name"]), "cls": String(r["class"]),
			"label": String(r["label"]), "hw": rhw, "pts": _pts(r["pts"])})
	# 地塊整平（§11 Parcel 的最小版）：有 pad 的地標在腳下整出一塊平地
	for lm in L["landmarks"]:
		if lm.get("pad", false):
			var s3: Array = lm["size"]
			var c := Vector2(float(lm["at"][0]), float(lm["at"][1]))
			var r := maxf(float(s3[0]), float(s3[2])) * 0.5 + 1.5
			pads.append(Vector4(c.x, c.y, r, _land(c.x, c.y, false)))
	for ch in channels:
		_channel_prep(ch)
		ch["form"] = WF.get(String(ch["name"]), {})
		if not (ch["form"] as Dictionary).is_empty():
			ch["kap"] = WLib.curvature(ch["pts"], float(ch["form"]["curv_win"]))
	for r in roads:
		_road_prep(r)


func _amp(waves: Array) -> float:
	var s := 0.0
	for wv in waves:
		s += absf(float(wv[1]))
	return s


func _add_poly(name: String, a: Array) -> void:
	var p := _pts(a)
	polys[name] = p
	var r := Rect2(p[0], Vector2.ZERO)
	for v in p:
		r = r.expand(v)
	pbox[name] = r


func _pts(a: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for v in a:
		out.append(Vector2(float(v[0]), float(v[1])))
	return out


# ─────────────────────────── 地形高度 ───────────────────────────

## 自然地形：西丘、北山、東緣、南緣抬升 ＋ 噪訊，再加北丘。
func _natural(x: float, z: float) -> float:
	var R: Dictionary = L["relief"]
	var h := 0.0
	h += float(R["west_h"]) * (1.0 - _ss(0.0, float(R["west_x"]), x))
	h += float(R["north_h"]) * (1.0 - _ss(float(R["north_z0"]), float(R["north_z1"]), z))
	# 東緣只在東北角（北山林）抬升；往南淡出，讓農田平鋪到圖邊、主河從平地出圖（概念圖右緣）
	var ezf: Array = R.get("east_z_fade", [1.0e9, 1.0e9 + 1.0])   # 缺省＝整條東緣都抬升
	h += float(R["east_h"]) * _ss(float(R["east_x0"]), float(R["east_x1"]), x) \
		* (1.0 - _ss(float(ezf[0]), float(ezf[1]), z))
	h += float(R["south_h"]) * _ss(float(R["south_z0"]), float(R["south_z1"]), z)
	h += noise.get_noise_2d(x, z) * float(R["noise_amp"])
	h += _hill_h(x, z)
	return h


## 北丘 macro 輪廓：主丘＋各 lobe（肩／次峰）以 smooth-max 合成，丘與丘之間留鞍部，不是單一圓丘。
func _hill_h(x: float, z: float) -> float:
	var hill: Dictionary = L["hill"]
	var p := Vector2(x, z)
	var h := _lobe(p, hill["center"], float(hill["radius"]), float(hill["height"]))
	var k := float(hill.get("blend_k", 8.0))
	for lb in hill.get("lobes", []):
		h = _smax(h, _lobe(p, lb["center"], float(lb["radius"]), float(lb["height"])), k)
	return h


func _lobe(p: Vector2, c: Array, r: float, hh: float) -> float:
	var d := p.distance_to(Vector2(float(c[0]), float(c[1])))
	return hh * pow(cos(d / r * PI * 0.5), 1.6) if d < r else 0.0


## 多項式 smooth-max：兩丘交界圓順；乘 min(a,b)/k 讓 lobe 外（0）不會多出底噪高度。
func _smax(a: float, b: float, k: float) -> float:
	var hh := maxf(k - absf(a - b), 0.0) / k
	return maxf(a, b) + hh * hh * k * 0.25 * minf(1.0, minf(a, b) / k)


func _in_hill(p: Vector2) -> bool:
	var hill: Dictionary = L["hill"]
	if p.distance_to(Vector2(float(hill["center"][0]), float(hill["center"][1]))) < float(hill["radius"]):
		return true
	for lb in hill.get("lobes", []):
		if p.distance_to(Vector2(float(lb["center"][0]), float(lb["center"][1]))) < float(lb["radius"]):
			return true
	return false


## 地面（未刻水道）：自然地形與整平區（建成、農田、地塊）混合。
## 副作用：_wb／_wf／_did 記錄該點的建成區權重、農田權重、建成區索引。
func _land(x: float, z: float, with_pads := true) -> float:
	var p := Vector2(x, z)
	var nat := _natural(x, z)
	_wb = 0.0
	_wf = 0.0
	_did = -1
	for bi in built.size():
		var w := _pw(built[bi], p, feather)
		if w > _wb:
			_wb = w
			_did = bi
	# 建成區（如農田中的大宅庭園）優先於農田
	_wf = _pw("Farmland", p, feather) * (1.0 - _wb)
	var h := lerpf(nat, TLib.farm_level(L, p), clampf(_wf, 0.0, 1.0))
	# Built Terrain（P1）：建成區平台（分區 closing 聯集＋apron）＝基準面；平台外是填挖坡（Transition），
	# 坡夾不到的地方維持原本的 Natural／農田地面。取代 r3 的「分區內 10 m 羽化」——那會讓村內隨噪訊起伏。
	h = TLib.bank(L, h, TLib.plane(L, z), -TLib.outline_sd(outlines, p) - apron)
	if with_pads:
		# 地塊整平＝平台＋限坡填挖：離平台邊 s 公尺處最多高出／低於平台 s·tan35°。
		# 原本固定 5 m feather：坡上平台（丘腳社寺，自然坡約 31°）挖出 6 m 高、68° 的牆。
		for pd in pads:
			var d := p.distance_to(Vector2(pd.x, pd.y))
			if d <= pd.z:
				h = pd.w
			else:
				var k := (d - pd.z) * PAD_BANK_SLOPE
				if absf(h - pd.w) > k:
					h = pd.w + clampf(h - pd.w, -k, k)
				elif d < pd.z + pad_feather:
					h = lerpf(pd.w, h, _ss(pd.z, pd.z + pad_feather, d))
	return h


## 水道刻進地面。主河固定水位；水渠／細渠用上游累積最小水位。
## 穿過高地時岸坡自動放寬（V 形谷，高出水面每 1 m 放寬 1.8 m），不會切出垂直峽壁。
func _carve(x: float, z: float, h: float) -> float:
	var p := Vector2(x, z)
	var land := h
	var r := _near(river_pts, p)
	var rhw := _hw_interp(river_hw, r)
	var outer := rhw + 6.0 + maxf(0.0, land - 1.0) * 1.8
	# P1 岸坡整修（龍神橋東岸，terrain.river_bank_polish）：水線以下完全照舊；水線以上的坡面
	# 沿河改寬度（dw）、改坡形（k ≤ 1 → 坡頂圓），岸頂在平台外再加淺窪（只降不升）。
	var pk: Array = [0.0, 2.0, 0.0, 0.0, 0.0, 0.0]
	if not polish.is_empty() and r.x < float(polish["rim_r"]) + 1.0:
		var k := int(r.y)
		pk = TLib.bank_polish(polish, signf((river_pts[k + 1] - river_pts[k]).cross(p - river_pts[k])), p)
	var a0 := rhw * 0.45
	var bed := float(H["river_bed"])
	var h0 := h
	if r.x < outer:
		h0 = minf(h, lerpf(bed, land, _ss(a0, outer, r.x)))
	var wgt := float(pk[2])
	var wl := float(H["river_water"])
	if wgt > 0.0 and land > wl:
		# 整修後的岸坡 h1，與原岸坡 h0 依權重混合（兩者皆連續 → 淡入淡出處無縫）。
		# 水線以下完全照舊；水線以上改成 1−(1−v)^p（p ≥ 2）：水線處斜、往上曲率遞減，坡頂是寬圓肩。
		# 坡寬沿河隨 dw 變化，下限 bank_min_w（坡面 ≤ 40°）。
		# 岸肩高低（pk[3]，只降不升、不低於水面 +1.5 m）。固定鏡頭眼高 1.77 m、東岸平台約 1.9–2.0 m：
		# 坡頂幾乎就在視平線上，平面上左右擺動看不出來，只有岸肩高低讀得出起伏。
		# 岸肩在 rim_r（離河中心）前以 smoothstep 接回原地面；rim_r 在驗證的河岸帶（28 m）內，外面的平台不動。
		var yw := clampf((wl - bed) / (land - bed), 0.0, 1.0)
		var uw := 0.5 - sin(asin(1.0 - 2.0 * yw) / 3.0)   # smoothstep 反函數：原岸坡水線位置
		var xw := a0 + (outer - a0) * uw
		var rim := float(polish["rim_r"])
		# 坡頂離 rim 至少 rim_gap，岸肩才有空間降下再接回
		var lw := clampf(outer - xw + float(pk[0]) / wgt, float(polish["bank_min_w"]), rim - float(polish["rim_gap"]) - xw)
		var crest := xw + lw
		# 淺窪深度受回升距離限制：smootherstep 最大曲率 5.77·d/L²，d ≤ 0.02·L² → 曲率 ≤ 0.12 /m，接回處不起肩線
		var top := maxf(land - minf(float(pk[3]), 0.02 * pow(rim - crest, 2.0)), minf(land, wl + float(polish["top_min"])))
		# 岸腳前伸：整條岸坡往河心平移 jut（只伸不縮 → 水線只往河裡走，水面網格邊不外露）。
		# 水線從此不再是一條直線；坡頂同步前移，坡寬不變。
		var jut := float(pk[5])
		var rx := r.x + jut
		var h1 := h
		if rx <= xw:
			h1 = minf(h, lerpf(bed, land, _ss(a0, outer, rx)))
		elif r.x < xw - jut + lw:
			var v := (rx - xw) / lw
			# 坡面鼓凹：sin²(πv) 兩端值與斜率皆 0（水線、坡頂不起折），沿河隨 face_waves 正負交替
			# 鼓起處可能略高過原地面：用 soft min 貼回（硬 min 會在交點留一條折線）
			h1 = TLib.smin(h, wl + (top - wl) * (1.0 - pow(1.0 - v, float(pk[1]))) + float(pk[4]) * pow(sin(PI * v), 2.0) * (top - wl) / 2.8, 0.8)
		elif r.x < rim:
			# 岸肩接回原地面用 smootherstep（兩端二階導數也為 0，接縫不起線）
			var q := clampf((r.x - (crest - jut)) / (rim - (crest - jut)), 0.0, 1.0)
			h1 = minf(h, lerpf(top, land, q * q * q * (q * (q * 6.0 - 15.0) + 10.0)))
		h = lerpf(h0, h1, wgt)
	else:
		h = h0
	# P2 河道形態：只動水線以下（d0 ＝ P1 水深 > 0）；水線附近 blend_d0 內淡入，水線位置不動
	if not river_form.is_empty() and r.x < outer and h < wl:
		var k2 := int(r.y)
		var sg := signf((river_pts[k2 + 1] - river_pts[k2]).cross(p - river_pts[k2]))
		var st := WLib.station(river_cum, r)
		var m := WLib.factor(river_form, WLib.bend(river_form, river_kap, st), sg * r.x / rhw, st, wl - bed, p)
		h = wl - (wl - h) * WLib.blend(river_form, m, wl - h, p)
	for ch in channels:
		var q := _near(ch["pts"], p)
		var hw: float = ch["hw"]
		var base: float = hw + float(ch["margin"])
		if q.x > base + 60.0:
			continue
		var lv := _level(ch, q)
		var o := base + maxf(0.0, land - (lv + 2.0)) * 1.8
		if q.x < o:
			var hc := lerpf(lv - float(ch["wdepth"]), land, _ss(hw * 0.7, o, q.x))
			var F: Dictionary = ch["form"]
			if not F.is_empty() and hc < lv:
				var cp: PackedVector2Array = ch["pts"]
				var k3 := int(q.y)
				var sg := signf((cp[k3 + 1] - cp[k3]).cross(p - cp[k3]))
				var st := WLib.station(ch["cum"], q)
				var m := WLib.factor(F, WLib.bend(F, ch["kap"], st), sg * q.x / hw, st, float(ch["wdepth"]), p)
				hc = lv - (lv - hc) * WLib.blend(F, m, lv - hc, p)
			h = minf(h, hc)
	return h


## 道路整地（§6 Built Terrain 的「道路坡度」）：路面寬＋2 m 內橫向拉平到縱坡，
## 再 3 m 羽化回原地面。路面網格用同一條縱坡 → 地形不會從路面底下刺出來。
func _grade(x: float, z: float, h: float) -> float:
	var p := Vector2(x, z)
	# 地塊 pad 內維持 pad 高度：參道接到山頂社殿 pad 外緣，路面橫向拉平不得把 pad 內緣往下拉
	# （P1 首跑實測：主丘地面 34.17 → 34.08 m）。
	for pd in pads:
		if p.distance_to(Vector2(pd.x, pd.y)) <= pd.z:
			return h
	for r in roads:
		var bb: Rect2 = r["bb"]
		if not bb.has_point(p):
			continue
		var hw: float = r["hw"]
		var q := _near(r["pts"], p)
		if q.x < hw + 5.0:
			h = lerpf(_level(r, q), h, _ss(hw + 2.0, hw + 5.0, q.x))
	return h


## 縱坡：沿中心線每 1 m 取地面高度，±8 m 移動平均（緩坡，不跟著噪訊起伏）。
## 參道（terrain.approach）另外延長到社殿 pad 外緣，縱坡改用 _approach_profile。
func _road_prep(r: Dictionary) -> void:
	var pts: PackedVector2Array = TLib.approach_line(L, r["pts"], String(r["name"]))
	r["pts"] = pts
	var cum := PackedFloat32Array([0.0])
	var bb := Rect2(pts[0], Vector2.ZERO)
	for k in range(1, pts.size()):
		cum.append(cum[k - 1] + pts[k - 1].distance_to(pts[k]))
		bb = bb.expand(pts[k])
	r["cum"] = cum
	r["bb"] = bb.grow(float(r["hw"]) + 6.0)
	var total := cum[cum.size() - 1]
	var raw := PackedFloat32Array()
	for i in int(ceil(total)) + 1:
		var p := _along(pts, cum, minf(float(i), total))
		raw.append(_land(p.x, p.y))
	var prof := PackedFloat32Array()
	prof.resize(raw.size())
	for i in raw.size():
		var s := 0.0
		var n := 0
		for j in range(maxi(0, i - 8), mini(raw.size(), i + 9)):
			s += raw[j]
			n += 1
		prof[i] = s / n
	var A: Dictionary = L.get("terrain", {}).get("approach", {})
	if String(A.get("road", "")) == String(r["name"]):
		prof[prof.size() - 1] = raw[raw.size() - 1]
		_approach_profile(prof, float(A["max_deg"]))
	r["lv"] = prof


## 參道縱坡（P1）：終點釘在社殿 pad 高度；由後往前、再由前往後各掃一次，
## 每公尺升降都不超過 tan(max_deg)。原本 ±8 m 平均跟著丘坡走，接 pad 那段 57.8°（玩家上限 52°）。
func _approach_profile(prof: PackedFloat32Array, max_deg: float) -> void:
	var g := tan(deg_to_rad(max_deg))
	for i in range(prof.size() - 2, -1, -1):
		prof[i] = maxf(prof[i], prof[i + 1] - g)
	for i in range(1, prof.size()):
		prof[i] = maxf(prof[i], prof[i - 1] - g)


func _channel_prep(ch: Dictionary) -> void:
	var pts: PackedVector2Array = ch["pts"]
	var cum := PackedFloat32Array([0.0])
	for k in range(1, pts.size()):
		cum.append(cum[k - 1] + pts[k - 1].distance_to(pts[k]))
	ch["cum"] = cum
	var total := cum[cum.size() - 1]
	var lv := PackedFloat32Array()
	var run: float = ch["cap"]
	for i in int(ceil(total)) + 1:
		var p := _along(pts, cum, minf(float(i), total))
		run = minf(run, _land(p.x, p.y) - float(ch["below"]))
		lv.append(run)
	ch["lv"] = lv


func _along(pts: PackedVector2Array, cum: PackedFloat32Array, s: float) -> Vector2:
	for k in pts.size() - 1:
		if s <= cum[k + 1] or k == pts.size() - 2:
			var seg := maxf(cum[k + 1] - cum[k], 1e-6)
			return pts[k].lerp(pts[k + 1], clampf((s - cum[k]) / seg, 0.0, 1.0))
	return pts[0]


## 水位：r = _near(ch.pts, p) 的 (距離, 段, t)
func _level(ch: Dictionary, r: Vector3) -> float:
	var cum: PackedFloat32Array = ch["cum"]
	var lv: PackedFloat32Array = ch["lv"]
	var k := int(r.y)
	var s := cum[k] + r.z * (cum[k + 1] - cum[k])
	var i := clampi(int(s), 0, lv.size() - 2)
	return lerpf(lv[i], lv[i + 1], clampf(s - i, 0.0, 1.0))


func _grid() -> void:
	var n := nx * nz
	hg.resize(n)
	hl.resize(n)
	wbv.resize(n)
	wfv.resize(n)
	didv.resize(n)
	for j in nz:
		for i in nx:
			var x := x0 + i * step
			var z := z0 + j * step
			var k := j * nx + i
			var h := _land(x, z)
			wbv[k] = _wb
			wfv[k] = _wf
			didv[k] = _did
			h = _grade(x, z, h)
			hl[k] = h
			hg[k] = _carve(x, z, h)
	print("[v2] 高度網格 %d×%d（%.0f m 間距）" % [nx, nz, step])


## 網格雙線性取樣（最終地形）
func _hgrid(x: float, z: float) -> float:
	return _sample(hg, x, z)


## 刻水道前的地面（已整地）
func _hlgrid(x: float, z: float) -> float:
	return _sample(hl, x, z)


## 此點被水道下切（河、水渠、細渠的河床或岸坡）
func _carved(p: Vector2) -> bool:
	return _hlgrid(p.x, p.y) - _hgrid(p.x, p.y) > 0.05


func _sample(arr: PackedFloat32Array, x: float, z: float) -> float:
	var fx := clampf((x - x0) / step, 0.0, nx - 1.001)
	var fz := clampf((z - z0) / step, 0.0, nz - 1.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var a := lerpf(arr[j * nx + i], arr[j * nx + i + 1], tx)
	var b := lerpf(arr[(j + 1) * nx + i], arr[(j + 1) * nx + i + 1], tx)
	return lerpf(a, b, tz)


# ─────────────────────────── 幾何工具 ───────────────────────────

func _ss(e0: float, e1: float, v: float) -> float:
	return smoothstep(e0, e1, v)


## 點到折線：Vector3(距離, 線段索引, 線段參數 t)
func _near(pts: PackedVector2Array, p: Vector2) -> Vector3:
	var best := Vector3(INF, 0, 0)
	for k in pts.size() - 1:
		var a := pts[k]
		var ab := pts[k + 1] - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
		var d := p.distance_to(a + ab * t)
		if d < best.x:
			best = Vector3(d, k, t)
	return best


func _hw_interp(hw: PackedFloat32Array, r: Vector3) -> float:
	return lerpf(hw[int(r.y)], hw[int(r.y) + 1], r.z)


## 多邊形權重：內部且距邊 ≥ f → 1；外部 → 0；邊內 f 公尺羽化。
func _pw(name: String, p: Vector2, f: float) -> float:
	var bb: Rect2 = pbox[name]
	if not bb.grow(1.0).has_point(p):
		return 0.0
	var poly: PackedVector2Array = polys[name]
	if not Geometry2D.is_point_in_polygon(p, poly):
		return 0.0
	var d := INF
	for k in poly.size():
		var a := poly[k]
		var b := poly[(k + 1) % poly.size()]
		d = minf(d, p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)))
	return _ss(0.0, f, d)


func _in_poly(name: String, p: Vector2) -> bool:
	var bb: Rect2 = pbox[name]
	return bb.has_point(p) and Geometry2D.is_point_in_polygon(p, polys[name])


func _dense(pts: PackedVector2Array, maxstep: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in pts.size() - 1:
		var a := pts[k]
		var b := pts[k + 1]
		var n := maxi(1, int(ceil(a.distance_to(b) / maxstep)))
		for s in n:
			out.append(a.lerp(b, float(s) / n))
	out.append(pts[pts.size() - 1])
	return out


## 帶狀網格：沿折線取樣（≤2 m），兩側各 hw；y_fn 有給就用固定水位，否則貼地 + lift。
## ok_fn 回 false 的取樣點斷開（道路在水面上斷開，由橋接上）。
func _ribbon(pts: PackedVector2Array, hw_fn: Callable, y_fn: Callable, ok_fn: Callable,
		lift: float) -> ArrayMesh:
	var dp := _dense(pts, 2.0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var prev_ok := false
	var pl := Vector3()
	var pr := Vector3()
	var tris := 0
	for k in dp.size():
		var p := dp[k]
		var t := (dp[mini(k + 1, dp.size() - 1)] - dp[maxi(k - 1, 0)]).normalized()
		var n := Vector2(-t.y, t.x)
		var hw: float = hw_fn.call(p)
		var a := p + n * hw
		var b := p - n * hw
		var ok: bool = ok_fn.call(p) if ok_fn.is_valid() else true
		var ya := 0.0
		var yb := 0.0
		if y_fn.is_valid():
			ya = y_fn.call(p)
			yb = ya
		else:
			ya = _hgrid(a.x, a.y) + lift
			yb = _hgrid(b.x, b.y) + lift
		var cl := Vector3(a.x, ya, a.y)
		var cr := Vector3(b.x, yb, b.y)
		if ok and prev_ok:
			_tri_up(st, pl, pr, cl)
			_tri_up(st, pr, cr, cl)
			tris += 2
		prev_ok = ok
		pl = cl
		pr = cr
	if tris == 0:
		return null
	return st.commit()


func _tri_up(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	for v in [a, b, c]:
		st.set_normal(Vector3.UP)
		st.add_vertex(v)


# ─────────────────────────── 場景節點工具 ───────────────────────────

func _group(parent: Node, name: String) -> Node3D:
	var n := Node3D.new()
	n.name = name
	parent.add_child(n)
	return n


func _own(n: Node, owner_node: Node) -> void:
	for c in n.get_children():
		c.owner = owner_node
		_own(c, owner_node)


func _save(res: Resource, name: String) -> Resource:
	var path := GEN + name + ".res"
	var err := ResourceSaver.save(res, path)
	if err != OK:
		push_error("[v2] 存 %s 失敗 %s" % [path, error_string(err)])
	res.take_over_path(path)
	return res


func _mat(c: Color, cull_off := false, alpha := false) -> StandardMaterial3D:
	var key := "%s_%s_%s" % [c.to_html(), cull_off, alpha]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.95
	if cull_off:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if alpha:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 0.15
		m.metallic_specular = 0.6
	_mats[key] = m
	return m


func _mi(parent: Node, name: String, mesh: Mesh, mat: Material, shadow := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = mesh
	mi.material_override = mat
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## 名牌一律收進 Debug/Labels（世界座標），審查鏡頭用 "hide": ["Debug"] 一鍵關掉。
## parent 只用來換算位置與命名。
func _label(parent: Node, text: String, pos: Vector3, px: float, size: int,
		vb := 0.0, ve := 0.0, col := Color(1, 1, 1)) -> Label3D:
	var cur: Node = parent
	while cur != null and cur != vroot:
		if cur is Node3D:
			pos = (cur as Node3D).transform * pos
		cur = cur.get_parent()
	var lb := Label3D.new()
	lb.name = "%s_Label" % parent.name
	lb.text = text
	lb.font = font
	lb.font_size = size
	lb.outline_size = int(size / 6.0)
	lb.pixel_size = px
	lb.modulate = col
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.no_depth_test = false
	lb.position = pos
	lb.visibility_range_begin = vb
	lb.visibility_range_end = ve
	vroot.get_node("Debug/Labels").add_child(lb, true)
	return lb


## 方塊（可選碰撞）：size 為公尺，底面貼在 pos.y
func _box(parent: Node, name: String, size: Vector3, pos: Vector3, yaw_deg: float,
		col: Color, collide := true) -> Node3D:
	var holder: Node3D
	if collide:
		holder = StaticBody3D.new()
	else:
		holder = Node3D.new()
	holder.name = name
	holder.position = pos
	holder.rotation.y = deg_to_rad(yaw_deg)
	parent.add_child(holder)
	var bm := BoxMesh.new()
	bm.size = size
	var mi := _mi(holder, "Mesh", bm, _mat(col))
	mi.position.y = size.y * 0.5
	if collide:
		var cs := CollisionShape3D.new()
		cs.name = "Shape"
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		cs.position.y = size.y * 0.5
		holder.add_child(cs)
	return holder


func _c(a: Array) -> Color:
	return Color(float(a[0]), float(a[1]), float(a[2])) * ALBEDO_K


func _k(c: Color) -> Color:
	return Color(c.r * ALBEDO_K, c.g * ALBEDO_K, c.b * ALBEDO_K, c.a)


# ─────────────────────────── 環境 ───────────────────────────

## 天象：重用專案共用的「天象系統」（scripts/sky_system.gd；slice／trail／shrine 同一套），
## 參數照抄 slice（現行人里的外觀），只有陰影距離放大到能涵蓋俯視鏡頭。
## 它在 _ready 自建 太陽／月亮／天空環境；DayNight 依節點名／型別認得它並交出環境，
## main.gd 見圖自帶 WorldEnvironment＋DirectionalLight3D 就讓位。
## 第一輪自建 ProceduralSky＋Filmic＋1.25 太陽：截圖平均灰階 224–239、22–54% 像素 > 240（過曝）。
func _sky() -> void:
	var sky: Node3D = load("res://scripts/sky_system.gd").new()
	sky.name = "天象系統"
	sky.set("時刻", 17.2)
	sky.set("一日長度分鐘", 60.0)
	sky.set("方位角", 20.0)
	sky.set("正午高度", 90.0)
	sky.set("天氣過渡秒數", 30.0)
	sky.set("星星密度", 0.1)
	sky.set("銀河強度", 0.5)
	sky.set("概念圖雲層", load("res://assets/textures/skybox_jinri.png"))
	sky.set("概念圖雲層比例", 0.5)
	sky.set("概念圖雲層方位", -31.0)
	sky.set("概念圖雲層漂移", 0.0)
	sky.set("陰影距離", 160.0)
	vroot.get_node("Lighting").add_child(sky)


# ─────────────────────────── 地形 ───────────────────────────

func _terrain() -> void:
	var n := nx * nz
	var verts := PackedVector3Array()
	var nors := PackedVector3Array()
	var cols := PackedColorArray()
	verts.resize(n)
	nors.resize(n)
	cols.resize(n)
	var D: Dictionary = L["districts"]
	var dcol: Array[Color] = []
	for name in built:
		dcol.append(_c(D[name]["color"]))
	var farm: Dictionary = D["Farmland"]
	var fcol := _c(farm["color"])
	var pd: Dictionary = farm["paddy"]
	var bcol := _c(pd["bund_color"])
	var bund := float(pd["bund"])
	for j in nz:
		for i in nx:
			var k := j * nx + i
			var x := x0 + i * step
			var z := z0 + j * step
			verts[k] = Vector3(x, hg[k], z)
			var hx0 := hg[j * nx + maxi(i - 1, 0)]
			var hx1 := hg[j * nx + mini(i + 1, nx - 1)]
			var hz0 := hg[maxi(j - 1, 0) * nx + i]
			var hz1 := hg[mini(j + 1, nz - 1) * nx + i]
			var nrm := Vector3(hx0 - hx1, 2.0 * step, hz0 - hz1).normalized()
			nors[k] = nrm
			var c := C_GRASS.lerp(C_GRASS.darkened(0.18), noise2.get_noise_2d(x, z) * 0.5 + 0.5)
			if didv[k] >= 0 and wbv[k] > 0.0 and wbv[k] >= wfv[k]:
				# 建成區地面沿分區界羽化（wbv 本身就是 feather 10 m 的 0→1 權重）；
				# r1 以 0.5 門檻硬切，人眼高度把色邊讀成「路旁凹陷／缺地形」。
				c = c.lerp(C_BUILT.lerp(dcol[didv[k]], 0.30), wbv[k])
			elif wfv[k] > 0.5:
				var bx := fposmod(x - float(pd["x0"]), float(pd["dx"]))
				var bz := fposmod(z - float(pd["z0"]), float(pd["dz"]))
				c = bcol if (bx < bund or bz < bund) else fcol
			if hg[k] < hl[k] - 0.3:
				c = C_BED
			elif nrm.y < 0.75:
				c = c.lerp(C_ROCK, 0.75)
			cols[k] = c
	# 依 §2 分四塊：河床／北丘（主丘＋各 lobe）／農田／其餘（同一張高度網格，接縫共用頂點位置）
	var i_main := PackedInt32Array()
	var i_hill := PackedInt32Array()
	var i_farm := PackedInt32Array()
	var i_river := PackedInt32Array()
	# P1：每格依真實地面挑對角線；兩條都差 > FAN_TOL 就在格心加一點拆 4 三角（局部加密），
	# 不整張網格加密。原本固定 b–c 對角線，斜向坡腳在 2 m 網格上走樣成鋸齒（a056297 審圖）。
	for j in nz - 1:
		for i in nx - 1:
			var a := j * nx + i
			var tri := _quad_tris(a, verts, nors, cols)
			var wet := false
			for v in [a, a + 1, a + nx, a + nx + 1]:
				if hg[v] < hl[v] - 0.3:
					wet = true
			if wet:
				i_river.append_array(tri)
			elif _in_hill(Vector2(x0 + (i + 0.5) * step, z0 + (j + 0.5) * step)):
				i_hill.append_array(tri)
			elif (wfv[a] + wfv[a + 1] + wfv[a + nx] + wfv[a + nx + 1]) * 0.25 > 0.5:
				i_farm.append_array(tri)
			else:
				i_main.append_array(tri)
	var faces := PackedVector3Array()
	for idx in [i_main, i_hill, i_farm, i_river]:
		for g in idx:
			faces.append(verts[g])
	print("[v2] 地形三角化：%d 格、換對角線 %d、格心加密 %d（+%d 三角）" % [
		tri_stats["quads"], tri_stats["flip"], tri_stats["fan"], tri_stats["fan"] * 2])
	_edge_kinds()
	var tm := StandardMaterial3D.new()
	tm.vertex_color_use_as_albedo = true
	tm.vertex_color_is_srgb = true
	tm.roughness = 1.0
	var tg := vroot.get_node("Terrain")
	for pair in [["MainTerrain", i_main], ["NorthHill", i_hill],
			["FarmlandTerrain", i_farm], ["RiverTerrain", i_river]]:
		var idx: PackedInt32Array = pair[1]
		if idx.is_empty():
			continue
		var mesh := _sub_mesh(idx, verts, nors, cols)
		_mi(tg, pair[0], _save(mesh, "terrain_" + String(pair[0]).to_lower()), tm)
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	_save(shape, "terrain_col")
	var body := StaticBody3D.new()
	body.name = "TerrainCollision"
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	cs.shape = shape
	body.add_child(cs)
	vroot.get_node("Collision").add_child(body)
	_boundary()


const FAN_TOL := 0.08    # 格心真實高度與兩條對角線中點都差 > 此值 → 格心加點
const TWIST_TOL := 0.02  # 四角近乎共面的格不必判斷


## 一格（左上角索引 a）的三角形索引。可能在 verts／nors／cols 尾端加一個格心頂點。
func _quad_tris(a: int, verts: PackedVector3Array, nors: PackedVector3Array, cols: PackedColorArray) -> PackedInt32Array:
	tri_stats["quads"] += 1
	var b := a + 1
	var c := a + nx
	var d := a + nx + 1
	var bc := PackedInt32Array([a, b, c, b, d, c])
	var twist := absf(hg[a] + hg[d] - hg[b] - hg[c])
	if twist < TWIST_TOL:
		return bc
	var cx := (verts[a].x + verts[d].x) * 0.5
	var cz := (verts[a].z + verts[d].z) * 0.5
	var hc := _carve(cx, cz, _grade(cx, cz, _land(cx, cz)))
	var e_bc := absf((hg[b] + hg[c]) * 0.5 - hc)
	var e_ad := absf((hg[a] + hg[d]) * 0.5 - hc)
	if minf(e_bc, e_ad) > FAN_TOL:
		tri_stats["fan"] += 1
		var e := verts.size()
		verts.append(Vector3(cx, hc, cz))
		nors.append((nors[a] + nors[b] + nors[c] + nors[d]).normalized())
		cols.append((cols[a] + cols[b] + cols[c] + cols[d]) * 0.25)
		return PackedInt32Array([a, b, e, b, d, e, d, c, e, c, a, e])
	if e_ad < e_bc:
		tri_stats["flip"] += 1
		return PackedInt32Array([a, d, c, a, b, d])
	return bc


## 平台邊分類（§6 Transition）：沿平台外框每 2 m 一站，比較「自然接坡」與「夾限後」的地面；
## 差 ≥ retaining_min_h ＝ Retaining edge（高差大，P4 可放擋土），否則 Natural edge（已是平順接坡）。
## 結果寫進 meta.terrain_edges，驗證腳本對 Natural 站量坡度。
func _edge_kinds() -> void:
	var rmin := TLib.param(L, "retaining_min_h")
	var blend_d := TLib.param(L, "platform_blend_max")
	var stations: Array = []
	var ret_m := 0.0
	var nat_m := 0.0
	for poly in outlines:
		for e in poly.size():
			var a: Vector2 = poly[e]
			var b: Vector2 = poly[(e + 1) % poly.size()]
			var seg := a.distance_to(b)
			if seg < 0.01:
				continue
			var tg := (b - a) / seg
			var nrm := Vector2(-tg.y, tg.x)
			if TLib.outline_sd(outlines, (a + b) * 0.5 + nrm * 0.5) > 0.0:
				nrm = -nrm
			var s := 1.0
			while s < seg:
				var o := a + tg * s
				s += 2.0
				var worst := 0.0
				var steep := 0.0
				var prev := TLib.plane(L, o.y)
				for dd in range(1, int(blend_d) + 1):
					var q := o + nrm * (apron + float(dd))
					if TLib.outline_sd(outlines, q) > -apron:
						prev = NAN
						continue
					var nat := _natural(q.x, q.y)
					var wf := _pw("Farmland", q, feather)
					var base := lerpf(nat, TLib.farm_level(L, q), clampf(wf, 0.0, 1.0))
					var pl := TLib.plane(L, q.y)
					var soft := TLib.blend(L, base, pl, float(dd))
					var hb := TLib.bank(L, base, pl, float(dd))
					worst = maxf(worst, absf(soft - hb))
					if not is_nan(prev):
						steep = maxf(steep, rad_to_deg(atan(absf(hb - prev))))
					prev = hb
				# 夾限有作用，或接坡本身就比 blend_deg 陡（高差大、距離不夠，如西肩旁的挖方）＝Retaining
				var kind := "retaining" if (worst >= rmin or steep > TLib.param(L, "blend_deg")) else "natural"
				if kind == "retaining":
					ret_m += 2.0
				else:
					nat_m += 2.0
				stations.append([snappedf(o.x, 0.01), snappedf(o.y, 0.01), snappedf(nrm.x, 0.001), snappedf(nrm.y, 0.001),
					kind, snappedf(worst, 0.01), snappedf(steep, 0.1)])
	edge_stats = {"station_m": 2.0, "apron": apron, "retaining_m": ret_m, "natural_m": nat_m, "stations": stations}
	print("[v2] 平台邊：Natural %.0f m、Retaining %.0f m（夾限差 ≥ %.1f m 或接坡 > %.0f°）" % [nat_m, ret_m, rmin, TLib.param(L, "blend_deg")])


## 世界邊界（P1，§6「世界邊界」）：frame 四邊外側各一道 1 m 厚的牆，y −10…80（地形 −3.2…49 m）。
## 不用 gen_lib.boundary()：那個假設地圖以原點為中心、牆高只到 y 40，V2 的 frame 是 x 0…560、z −340…220。
func _boundary() -> void:
	var F: Dictionary = L["frame"]
	var fx0 := float(F["x0"])
	var fx1 := float(F["x1"])
	var fz0 := float(F["z0"])
	var fz1 := float(F["z1"])
	var cx := (fx0 + fx1) * 0.5
	var cz := (fz0 + fz1) * 0.5
	var w := fx1 - fx0 + 2.0
	var d := fz1 - fz0 + 2.0
	var body := StaticBody3D.new()
	body.name = "Boundary"
	for e in [["N", Vector3(cx, 35.0, fz0 - 0.5), Vector3(w, 90.0, 1.0)],
			["S", Vector3(cx, 35.0, fz1 + 0.5), Vector3(w, 90.0, 1.0)],
			["W", Vector3(fx0 - 0.5, 35.0, cz), Vector3(1.0, 90.0, d)],
			["E", Vector3(fx1 + 0.5, 35.0, cz), Vector3(1.0, 90.0, d)]]:
		var cs := CollisionShape3D.new()
		cs.name = "Wall_" + String(e[0])
		var b := BoxShape3D.new()
		b.size = e[2]
		cs.shape = b
		cs.position = e[1]
		body.add_child(cs)
	vroot.get_node("Collision").add_child(body)


func _sub_mesh(idx: PackedInt32Array, verts: PackedVector3Array, nors: PackedVector3Array,
		cols: PackedColorArray) -> ArrayMesh:
	var remap := PackedInt32Array()
	remap.resize(verts.size())
	remap.fill(-1)
	var v2 := PackedVector3Array()
	var n2 := PackedVector3Array()
	var c2 := PackedColorArray()
	var i2 := PackedInt32Array()
	i2.resize(idx.size())
	for t in idx.size():
		var g := idx[t]
		if remap[g] < 0:
			remap[g] = v2.size()
			v2.append(verts[g])
			n2.append(nors[g])
			c2.append(cols[g])
		i2[t] = remap[g]
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v2
	arr[Mesh.ARRAY_NORMAL] = n2
	arr[Mesh.ARRAY_COLOR] = c2
	arr[Mesh.ARRAY_INDEX] = i2
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


# ─────────────────────────── 水系 ───────────────────────────

func _water() -> void:
	var g := vroot.get_node("Water")
	# P2：水面頂點色＝水深（淺處淡、透；深槽暗、濃），灰模階段讀得出主槽／淺灘。正式水體 shader 在 P13。
	var wm := StandardMaterial3D.new()
	wm.vertex_color_use_as_albedo = true
	wm.vertex_color_is_srgb = true
	wm.cull_mode = BaseMaterial3D.CULL_DISABLED
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.roughness = 0.15
	wm.metallic_specular = 0.6
	var wl := float(H["river_water"])
	# P2：水面改成貼地形網格的水面（取代固定寬度帶狀水面：固定寬 → 低岸處水面邊浮空、端點與匯流口露底）
	var bodies: Array = [{"name": "MainRiver", "pts": river_pts, "ch": {}}]
	for ch in channels:
		bodies.append({"name": String(ch["name"]), "pts": ch["pts"], "ch": ch})
	var meshes := _grid_water(bodies)
	var river := _mi(g, "MainRiver", _save(meshes[0], "water_main_river"), wm, false)
	river.set_meta("label", "主河")
	river.set_meta("water_y", wl)
	_label(river, "主河", Vector3(river_pts[3].x, wl + 18.0, river_pts[3].y), 0.12, 128, 260.0, 1400.0, Color(0.7, 0.9, 1.0))
	for ci in channels.size():
		var ch: Dictionary = channels[ci]
		var cpts: PackedVector2Array = ch["pts"]
		var is_canal: bool = ch["name"] == "Canal"
		var parent: Node = g if is_canal else g.get_node("Streams")
		var wn := _mi(parent, String(ch["name"]), _save(meshes[ci + 1], "water_" + String(ch["name"]).to_lower()), wm, false)
		wn.set_meta("label", ch["label"])
		var lvs: PackedFloat32Array = ch["lv"]
		wn.set_meta("water_y_range", [snappedf(lvs[lvs.size() - 1], 0.01), snappedf(lvs[0], 0.01)])
		if is_canal:
			_label(wn, String(ch["label"]), Vector3(cpts[4].x, 14.0, cpts[4].y), 0.1, 128, 260.0, 1400.0, Color(0.7, 0.9, 1.0))
	var fg := g.get_node("Waterfalls")
	for wf in L["water"]["Waterfalls"]:
		var m := Marker3D.new()
		m.name = String(wf["name"])
		var at := Vector2(float(wf["at"][0]), float(wf["at"][1]))
		m.position = Vector3(at.x, _hgrid(at.x, at.y), at.y)
		m.set_meta("label", wf["label"])
		m.set_meta("src", wf["src"])
		m.set_meta("conf", wf["conf"])
		fg.add_child(m)
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.6
		cyl.bottom_radius = 0.6
		cyl.height = 3.0
		var mk := _mi(m, "Placeholder", cyl, _mat(_k(Color(0.55, 0.80, 1.0))), false)
		mk.position.y = 1.5
		_label(m, "跌水（placeholder）", Vector3(0, 4.5, 0), 0.02, 96, 0.0, 120.0)


const WATER_WET_EPS := 0.03   # 頂點高出水位不到此值也算濕 → 水面外緣一律落在高出水位 ≥ 0.03 m 的岸上（埋進岸下）
const WATER_REACH := 24.0     # 水面最遠到離中心線「半寬＋此值」


## 淺水仍要讀成「水」（藍綠、較透），不能灰到像乾河床（r1 審圖：0.40/0.58/0.56 α0.42 在溪上讀成灰泥）
const WATER_SHALLOW := Color(0.30, 0.56, 0.68, 0.62)
const WATER_DEEP := Color(0.10, 0.27, 0.46, 0.93)


## 水深 → 水面頂點色（0 m 淺藍綠半透明 → 2.2 m 以上深藍不透明）
func _water_col(depth: float) -> Color:
	var c := WATER_SHALLOW.lerp(WATER_DEEP, smoothstep(0.0, 2.2, maxf(depth, 0.0)))
	return _k(c)


func _body_hw(b: Dictionary, r: Vector3) -> float:
	if (b["ch"] as Dictionary).is_empty():
		return _hw_interp(river_hw, r)
	return float(b["ch"]["hw"])


func _body_level(b: Dictionary, r: Vector3) -> float:
	if (b["ch"] as Dictionary).is_empty():
		return float(H["river_water"])
	return _level(b["ch"], r)


## 網格水面（P2）：每個水體在自己的範圍（離岸最近者）內，從中心線附近的濕頂點（地形 < 水位 + WATER_WET_EPS）
## 以 8 鄰接洪水填充；有任一角是濕頂點的 2 m 格整格鋪水面（高度＝各角的水位）。
## → 水面外緣兩端頂點都高出水位，沿格線地形是線性 → 外緣整條埋在岸下（水面稍微伸進岸體下方）；
##   與河道連通、低於水位的地面都有水（不露底）；不連通的窪地不鋪。
## 兩水體相接（水渠取水口）：各自多鋪一格到對方範圍，低的水面邊藏在高的水面下，高的水面邊與低水面的落差＝水門落差。
func _grid_water(bodies: Array) -> Array:
	var n := nx * nz
	var own := PackedInt32Array()
	own.resize(n)
	own.fill(-1)
	var own_e := PackedFloat32Array()
	own_e.resize(n)
	own_e.fill(INF)
	var lvv := PackedFloat32Array()
	lvv.resize(n)
	var core := PackedByteArray()
	core.resize(n)
	for bi in bodies.size():
		var b: Dictionary = bodies[bi]
		var pts: PackedVector2Array = b["pts"]
		var bb := Rect2(pts[0], Vector2.ZERO)
		for q in pts:
			bb = bb.expand(q)
		bb = bb.grow(20.0 + WATER_REACH)
		var i0 := clampi(floori((bb.position.x - x0) / step), 0, nx - 1)
		var i1 := clampi(ceili((bb.end.x - x0) / step), 0, nx - 1)
		var j0 := clampi(floori((bb.position.y - z0) / step), 0, nz - 1)
		var j1 := clampi(ceili((bb.end.y - z0) / step), 0, nz - 1)
		for j in range(j0, j1 + 1):
			for i in range(i0, i1 + 1):
				var k := j * nx + i
				var r := _near(pts, Vector2(x0 + i * step, z0 + j * step))
				var hw := _body_hw(b, r)
				var e := r.x - hw
				if e > WATER_REACH or e >= own_e[k]:
					continue
				own_e[k] = e
				own[k] = bi
				lvv[k] = _body_level(b, r)
				core[k] = 1 if r.x < hw * 0.5 else 0
	var wet := PackedByteArray()
	wet.resize(n)
	var out: Array = []
	for bi in bodies.size():
		var queue: Array[int] = []
		for k in n:
			if own[k] == bi and core[k] == 1 and hg[k] < lvv[k] + WATER_WET_EPS:
				wet[k] = 1
				queue.append(k)
		var qi := 0
		var at_reach := 0
		while qi < queue.size():
			var k: int = queue[qi]
			qi += 1
			if own_e[k] > WATER_REACH - 2.0:
				at_reach += 1
			var i := k % nx
			var j := k / nx
			for dj in range(-1, 2):
				for di in range(-1, 2):
					var ii := i + di
					var jj := j + dj
					if ii < 0 or jj < 0 or ii >= nx or jj >= nz:
						continue
					var kk := jj * nx + ii
					if wet[kk] == 0 and own[kk] == bi and hg[kk] < lvv[kk] + WATER_WET_EPS:
						wet[kk] = 1
						queue.append(kk)
		# 鋪面
		var b: Dictionary = bodies[bi]
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var cells := 0
		var lv_cache := {}
		for j in nz - 1:
			for i in nx - 1:
				var a := j * nx + i
				var cs := [a, a + 1, a + nx, a + nx + 1]
				var any := false
				for c in cs:
					if wet[c] == 1 and own[c] == bi:
						any = true
				if not any:
					continue
				var vs: Array[Vector3] = []
				var cl: Array[Color] = []
				for c in cs:
					var y := lvv[c]
					if own[c] != bi:
						if not lv_cache.has(c):
							lv_cache[c] = _body_level(b, _near(b["pts"], Vector2(x0 + (c % nx) * step, z0 + (c / nx) * step)))
						y = lv_cache[c]
					vs.append(Vector3(x0 + (c % nx) * step, y + 0.001 * float(bi > 0), z0 + (c / nx) * step))
					cl.append(_water_col(y - hg[c]))
				for t in [[0, 1, 2], [1, 3, 2]]:
					for q in t:
						st.set_normal(Vector3.UP)
						st.set_color(cl[q])
						st.add_vertex(vs[q])
				cells += 1
		out.append(st.commit())
		water_stats.append([String(b["name"]), queue.size(), cells, at_reach])
	return out


# ─────────────────────────── 道路與橋 ───────────────────────────

func _roads() -> void:
	for r in roads:
		var cls: String = r["cls"]
		var grp := vroot.get_node("Roads/" + String(ROAD_GROUP[cls]))
		var hw: float = r["hw"]
		var rpts: PackedVector2Array = r["pts"]
		var mesh := _ribbon(rpts, func(_p): return hw,
			func(p): return _level(r, _near(rpts, p)) + 0.1,
			func(p): return not _carved(p), 0.0)
		if mesh == null:
			continue
		var mi := _mi(grp, String(r["name"]), _save(mesh, "road_" + String(r["name"]).to_lower()),
			_mat(ROAD_COL[cls], true), false)
		mi.set_meta("label", r["label"])
		mi.set_meta("width_m", hw * 2.0)
		mi.set_meta("class", cls)
	_lanes()
	_bridges()


## P3 巷道層：路面貼 P1 地形＋LANE_LIFT（不整地，所以 P1 protection 不變）；不跨水（layout 已保證離水 ≥ 5 m）
func _lanes() -> void:
	var grp := _group(vroot.get_node("Roads/Alleys"), "Lanes")
	for r in PLib.lanes(L):
		var hw: float = r["hw"]
		var mesh := _ribbon(r["pts"], func(_p): return hw, Callable(), func(p): return not _carved(p), LANE_LIFT)
		if mesh == null:
			continue
		var mi := _mi(grp, String(r["name"]), _save(mesh, "lane_" + String(r["name"]).to_lower()),
			_mat(ROAD_COL["alley"].darkened(0.06), true), false)
		mi.set_meta("label", r["label"])
		mi.set_meta("width_m", hw * 2.0)
		mi.set_meta("class", "lane")
		mi.set_meta("phase", "P3")


func _bridges() -> void:
	var waters: Array = [["River", river_pts, -1.0, 6.0]]
	for ch in channels:
		waters.append([String(ch["name"]), ch["pts"], float(ch["hw"]), float(ch["margin"])])
	var bg := vroot.get_node("Roads/Bridges")
	for r in roads:
		var rp: PackedVector2Array = r["pts"]
		for w in waters:
			var wp: PackedVector2Array = w[1]
			for a in rp.size() - 1:
				for b in wp.size() - 1:
					var hit = Geometry2D.segment_intersects_segment(rp[a], rp[a + 1], wp[b], wp[b + 1])
					if hit == null:
						continue
					var P: Vector2 = hit
					var dup := false
					for e in bridges:
						if e[0] == r["name"] and (e[1] as Vector2).distance_to(P) < 6.0:
							dup = true
					if dup:
						continue
					bridges.append([r["name"], P])
					var rd := (rp[a + 1] - rp[a]).normalized()
					var wd := (wp[b + 1] - wp[b]).normalized()
					var sinang := absf(rd.cross(wd))
					if sinang < 0.6:
						push_warning("[v2] ⚠ 斜交：%s × %s 夾角 %.0f°（<37°）——道路應正交跨水，改 layout 路線" % [
							r["name"], w[0], rad_to_deg(asin(sinang))])
					# 橋端 = 沿路往兩側走到地面不再被水道下切的地方（再多 1.5 m 壓上路面）
					var e1 := _bridge_end(P, rd)
					var e2 := _bridge_end(P, -rd)
					var h1 := _hgrid(e1.x, e1.y) + 0.05
					var h2 := _hgrid(e2.x, e2.y) + 0.05
					var horiz := e1.distance_to(e2)
					var dh := h1 - h2
					var mid := (e1 + e2) * 0.5
					var width := float(r["hw"]) * 2.0 + 0.8
					var name := "Bridge_%02d_%s_%s" % [bridges.size(), r["name"], w[0]]
					var span := TLib.bridge_span(L, name)
					if span.is_empty():
						span_errors.append("%s 沒有 terrain.bridge_spans.preferred" % name)
					elif horiz < float(span[1]) or horiz > float(span[2]):
						span_errors.append("%s 橋長 %.1f m 超出容許 %.1f–%.1f m（preferred %.1f）——改河岸，不拉長橋" % [
							name, horiz, float(span[1]), float(span[2]), float(span[0])])
					var node := _box(bg, name, Vector3(width, 0.6, sqrt(horiz * horiz + dh * dh)),
						Vector3(mid.x, (h1 + h2) * 0.5 - 0.6, mid.y), rad_to_deg(atan2(rd.x, rd.y)),
						_k(Color(0.52, 0.36, 0.24)))
					# 橋面兩端各落在該端路面高度（+5 cm），不留台階
					node.rotation.x = -atan2(dh, horiz)
					node.set_meta("label", "%s × %s" % [r["label"], w[0]])
					node.set_meta("length_m", snappedf(horiz, 0.1))
					node.set_meta("end_heights", [snappedf(h1, 0.01), snappedf(h2, 0.01)])
					node.set_meta("cross_deg", snappedf(rad_to_deg(asin(sinang)), 1.0))


func _bridge_end(P: Vector2, dir: Vector2) -> Vector2:
	var s := 0.5
	while s < 80.0:
		if not _carved(P + dir * s):
			return P + dir * (s + 1.5)
		s += 0.5
	return P + dir * 80.0


# ─────────────────────────── 分區 ───────────────────────────

func _districts() -> void:
	var D: Dictionary = L["districts"]
	var g := vroot.get_node("Districts")
	for k in D:
		var d: Dictionary = D[k]
		var node_name: String = "FarmlandEast" if k == "Farmland" else k
		var n := _group(g, node_name)
		n.set_meta("label", d["label"])
		n.set_meta("src", d["src"])
		n.set_meta("conf", d["conf"])
		n.set_meta("kind", d["kind"])
		var poly: PackedVector2Array = polys[k]
		var closed := poly.duplicate()
		closed.append(poly[0])
		var om := _ribbon(closed, func(_p): return 0.5, Callable(), Callable(), 0.25)
		# 分區輪廓是除錯用（人眼鏡頭會藏 Debug）：掛在 Debug/DistrictOutlines，不在 Districts 底下
		var dbo := vroot.get_node_or_null("Debug/DistrictOutlines")
		if dbo == null:
			dbo = _group(vroot.get_node("Debug"), "DistrictOutlines")
		_mi(dbo, k, _save(om, "district_" + k.to_lower()), _mat(_c(d["color"]).lightened(0.25), true), false)
		var cen := Vector2.ZERO
		for v in poly:
			cen += v
		cen /= poly.size()
		if d.has("label_at"):   # 形心落在別區或地標上時，layout 指定標籤位置
			cen = Vector2(float(d["label_at"][0]), float(d["label_at"][1]))
		_label(n, d["label"], Vector3(cen.x, _hgrid(cen.x, cen.y) + 30.0, cen.y), 0.16, 128, 260.0, 1400.0)
	var hill: Dictionary = L["hill"]
	var hn := _group(g, "NorthHill")
	hn.set_meta("label", hill["label"])
	hn.set_meta("src", hill["src"])
	var hc := Vector2(float(hill["center"][0]), float(hill["center"][1]))
	# 標在丘頂北側上空：從南看在稜線之上，不擋丘面與參道
	_label(hn, hill["label"], Vector3(hc.x, _hgrid(hc.x, hc.y) + 34.0, hc.y - 30.0), 0.16, 128, 260.0, 1400.0)
	var rv := _group(g, "Riverside")
	rv.set_meta("label", "河岸帶（主河兩岸 6 m 內；尚未分配用途）")


# ─────────────────────────── P3 地塊 ───────────────────────────

func _parcels() -> void:
	var net := PLib.network(L)
	var t0 := Time.get_ticks_msec()
	var res: Dictionary = PLib.parcels(L, net, func(p: Vector2) -> float: return _hgrid(p.x, p.y))
	var byname := {}
	for r in roads:
		byname[r["name"]] = r
	var road_h := func(name: String, p: Vector2) -> float:
		if byname.has(name):
			var rr: Dictionary = byname[name]
			return _level(rr, _near(rr["pts"], p)) + 0.1
		return _hgrid(p.x, p.y) + LANE_LIFT
	var all: Array = []
	for fx in res["fixed"]:
		var fdn := "NorthHill"
		for k in built:
			if Geometry2D.is_point_in_polygon(fx["at"], polys[k]):
				fdn = k
		fx["district"] = fdn
		all.append(fx)
	all.append_array(res["parcels"])
	var all_polys: Array = []
	for pc in all:
		all_polys.append(pc["poly"])
	var recs: Array = []
	var lines := {}   # district → SurfaceTool
	for pc in all:
		var rec := PLib.record(pc, all_polys, net, func(p: Vector2) -> float: return _hgrid(p.x, p.y), road_h)
		recs.append(rec)
		var dn: String = pc["district"]
		var dg := vroot.get_node("Districts/" + dn)
		var pg := dg.get_node_or_null("Parcels")
		if pg == null:
			pg = _group(dg, "Parcels")
		var m := Marker3D.new()
		m.name = String(rec["id"])
		m.position = Vector3(float(rec["center"][0]), float(rec["ground_h"]), float(rec["center"][1]))
		for k in rec:
			if k != "id":
				m.set_meta(k, rec[k])
		pg.add_child(m)
		var key := "landmark" if pc["kind"] == "landmark" else dn
		if not lines.has(key):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			lines[key] = [st, dg]
		_outline(lines[key][0], pc["poly"], 0.35 if pc["kind"] == "machiya" else 0.5)
		if pc["kind"] == "machiya":
			var fa: Vector2 = pc["front_a"]
			var fb: Vector2 = pc["front_b"]
			var dir: Vector2 = pc["dir"]
			_outline(lines[key][0], PackedVector2Array([fa - dir * 0.05, fb - dir * 0.05, fb - dir * 1.2, fa - dir * 1.2]), 0.6)
	for key in lines:
		var st: SurfaceTool = lines[key][0]
		var dg: Node = lines[key][1]
		var mesh := st.commit()
		var lname := "LandmarkParcelLines" if key == "landmark" else "ParcelLines"
		var mi := _mi(dg if key != "landmark" else vroot.get_node("Districts"), lname, _save(mesh, "parcels_" + String(key).to_lower()),
			_mat(_k(PARCEL_COL.get(key, Color(0.8, 0.8, 0.8))), true), false)
		mi.set_meta("phase", "P3")
	var pf := FileAccess.open(PARCELS, FileAccess.WRITE)
	pf.store_string(JSON.stringify({"_note": "P3 地塊紀錄（§11）。由 tools/gen_village_v2.gd 產生，勿手改。",
		"layout_version": L["version"], "stats": res["stats"], "parcels": recs}, "\t") + "\n")
	pf.close()
	var n_m := 0
	for r in recs:
		if r["kind"] == "machiya":
			n_m += 1
	print("[v2] P3 地塊 %d（町家 %d、地標 %d）、%d ms → %s；拒絕 %s" % [recs.size(), n_m, recs.size() - n_m,
		Time.get_ticks_msec() - t0, PARCELS, res["stats"]])


## 地塊外框線（沿地形、每 1.5 m 取樣；四邊各自一條帶，寬 w、朝內）
func _outline(st: SurfaceTool, poly: PackedVector2Array, w: float) -> void:
	var cw := Geometry2D.is_polygon_clockwise(poly)
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var t := (b - a).normalized()
		var n := Vector2(-t.y, t.x) * (-1.0 if cw else 1.0)   # 朝多邊形內
		var cnt := maxi(1, int(ceil(a.distance_to(b) / 1.5)))
		for k in cnt:
			var p0 := a.lerp(b, float(k) / cnt)
			var p1 := a.lerp(b, float(k + 1) / cnt)
			var q0 := p0 + n * w
			var q1 := p1 + n * w
			var v := [p0, p1, q1, q0]
			var y: Array = []
			for p in v:
				y.append(_hgrid(p.x, p.y) + PARCEL_LINE_LIFT)
			var V: Array[Vector3] = []
			for j in 4:
				V.append(Vector3(v[j].x, y[j], v[j].y))
			# 正面朝上（Godot 正面＝從上往下看順時針；x·z 叉積 > 0）。繞錯的面在 cull 關閉時會以背面光照變黑。
			if (v[1] - v[0]).cross(v[2] - v[0]) < 0.0:
				V.reverse()
			_tri_up(st, V[0], V[1], V[2])
			_tri_up(st, V[0], V[2], V[3])


# ─────────────────────────── 林冠團塊 ───────────────────────────

func _forests() -> void:
	var F: Dictionary = L["forests"]
	var cell := maxi(1, int(round(float(F["cell"]) / step)))
	var ch := float(F["canopy_h"])
	var cv := float(F["canopy_var"])
	var names: Array[String] = []
	for k in F:
		if typeof(F[k]) == TYPE_DICTIONARY:
			names.append(k)
	var ncx := (nx - 1) / cell
	var ncz := (nz - 1) / cell
	var own := PackedInt32Array()
	own.resize(ncx * ncz)
	own.fill(-1)
	for cj in ncz:
		for ci in ncx:
			var p := Vector2(x0 + (ci + 0.5) * cell * step, z0 + (cj + 0.5) * cell * step)
			for b in names.size():
				if _in_belt(F[names[b]], names[b], p):
					if _forest_ok(p):
						own[cj * ncx + ci] = b
					break
	# 林緣斜坡：每格離林帶邊緣幾格（BFS）。邊緣角點只有 20% 林冠高，往內每格 +27%，
	# 約 12 m 升到全高（約 52° 的林緣）。第一版四邊直立 13–19 m，審圖時被讀成「地形峭壁」。
	var edist := PackedInt32Array()
	edist.resize(ncx * ncz)
	edist.fill(1 << 20)
	var queue: Array[int] = []
	for cj in ncz:
		for ci in ncx:
			var b0 := own[cj * ncx + ci]
			if b0 < 0:
				continue
			for dd in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
				var ni: int = ci + int(dd[0])
				var nj: int = cj + int(dd[1])
				if ni < 0 or nj < 0 or ni >= ncx or nj >= ncz or own[nj * ncx + ni] != b0:
					edist[cj * ncx + ci] = 0
					queue.append(cj * ncx + ci)
					break
	var qh := 0
	while qh < queue.size():
		var c0 := queue[qh]
		qh += 1
		var ci0 := c0 % ncx
		var cj0 := c0 / ncx
		for dd in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
			var ni: int = ci0 + int(dd[0])
			var nj: int = cj0 + int(dd[1])
			if ni < 0 or nj < 0 or ni >= ncx or nj >= ncz:
				continue
			var c1 := nj * ncx + ni
			if own[c1] == own[c0] and edist[c1] > edist[c0] + 1:
				edist[c1] = edist[c0] + 1
				queue.append(c1)
	var cm := StandardMaterial3D.new()
	cm.vertex_color_use_as_albedo = true
	cm.vertex_color_is_srgb = true
	cm.roughness = 1.0
	cm.cull_mode = BaseMaterial3D.CULL_DISABLED
	var veg := vroot.get_node("Vegetation")
	for b in names.size():
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var count := 0
		for cj in ncz:
			for ci in ncx:
				if own[cj * ncx + ci] != b:
					continue
				count += 1
				var i0 := ci * cell
				var j0 := cj * cell
				var t00 := _canopy_v(i0, j0, ch, cv, _corner_f(ci, cj, b, own, edist, ncx, ncz))
				var t10 := _canopy_v(i0 + cell, j0, ch, cv, _corner_f(ci + 1, cj, b, own, edist, ncx, ncz))
				var t01 := _canopy_v(i0, j0 + cell, ch, cv, _corner_f(ci, cj + 1, b, own, edist, ncx, ncz))
				var t11 := _canopy_v(i0 + cell, j0 + cell, ch, cv, _corner_f(ci + 1, cj + 1, b, own, edist, ncx, ncz))
				var tn := (t01 - t00).cross(t10 - t00).normalized()
				_quad(st, t00, t10, t11, t01, tn if tn.y >= 0.0 else -tn)
				var ctr := (t00 + t11) * 0.5
				# 外緣立面：鄰格不屬同一林帶才封邊
				var nb := [[0, -1, t00, t10], [1, 0, t10, t11], [0, 1, t11, t01], [-1, 0, t01, t00]]
				for e in nb:
					var ni: int = ci + int(e[0])
					var nj: int = cj + int(e[1])
					var same := ni >= 0 and nj >= 0 and ni < ncx and nj < ncz and own[nj * ncx + ni] == b
					if same:
						continue
					var ta: Vector3 = e[2]
					var tb: Vector3 = e[3]
					var ga := Vector3(ta.x, _hgrid(ta.x, ta.z) - 0.4, ta.z)
					var gb := Vector3(tb.x, _hgrid(tb.x, tb.z) - 0.4, tb.z)
					var mid := (ta + tb) * 0.5
					var outn := Vector3(mid.x - ctr.x, 0.0, mid.z - ctr.z).normalized()
					_quad(st, ga, gb, tb, ta, outn)
		if count == 0:
			continue
		var fdef: Dictionary = F[names[b]]
		var mesh := st.commit()
		var mi := _mi(veg, names[b], _save(mesh, "canopy_" + names[b].to_lower()), cm)
		mi.set_meta("label", fdef["label"])
		mi.set_meta("src", fdef["src"])
		mi.set_meta("conf", fdef["conf"])
		mi.set_meta("area_m2", count * cell * cell * step * step)
		mi.set_meta("placeholder", "林冠團塊（不是樹；§53 C 禁止正式種樹）")


func _canopy_v(i: int, j: int, ch: float, cv: float, f := 1.0) -> Vector3:
	var ii := mini(i, nx - 1)
	var jj := mini(j, nz - 1)
	var x := x0 + ii * step
	var z := z0 + jj * step
	var h := hg[jj * nx + ii] + (ch + cv * (noise2.get_noise_2d(x * 1.7, z * 1.7) * 0.5 + 0.5)) * f
	return Vector3(x, h, z)


## 林冠角點 (u, v)（格角座標）的高度係數：碰到林帶外的格 → 林緣 0.2；否則依最近邊緣距離爬升。
func _corner_f(u: int, v: int, b: int, own: PackedInt32Array, edist: PackedInt32Array,
		ncx: int, ncz: int) -> float:
	var d := 1 << 20
	for c in [[u - 1, v - 1], [u, v - 1], [u - 1, v], [u, v]]:
		var ci: int = c[0]
		var cj: int = c[1]
		if ci < 0 or cj < 0 or ci >= ncx or cj >= ncz or own[cj * ncx + ci] != b:
			return 0.2
		d = mini(d, edist[cj * ncx + ci])
	return minf(1.0, 0.2 + 0.27 * float(d + 1))


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	var y := clampf((a.y + c.y) * 0.01, 0.0, 1.0)
	var col := C_CANOPY.lerp(C_CANOPY.lightened(0.25), y) if n.y > 0.5 else C_CANOPY.darkened(0.25)
	for v in [a, b, c, a, c, d]:
		st.set_normal(n)
		st.set_color(col)
		st.add_vertex(v)


func _in_belt(def: Dictionary, name: String, p: Vector2) -> bool:
	if def.has("circle"):
		var c: Array = def["circle"]
		return p.distance_to(Vector2(float(c[0]), float(c[1]))) < float(c[2])
	return _in_poly(name, p)


## 林冠不得侵入：道路（+4 m）、水道、建成區、農田（§ Stop Conditions：森林侵入農田或開放面）、
## 地標地塊與山頂平台。
func _forest_ok(p: Vector2) -> bool:
	for name in built:
		if _pw(name, p, 1.0) > 0.0:
			return false
	if _pw("Farmland", p, 1.0) > 0.0:
		return false
	for r in roads:
		if _near(r["pts"], p).x < float(r["hw"]) + 4.0:
			return false
	var rr := _near(river_pts, p)
	if rr.x < _hw_interp(river_hw, rr) + 8.0:
		return false
	for ch in channels:
		if _near(ch["pts"], p).x < float(ch["hw"]) + 4.0:
			return false
	for pd in pads:
		if p.distance_to(Vector2(pd.x, pd.y)) < pd.z + 6.0:
			return false
	for lm in L["landmarks"]:
		if String(lm["type"]) == "torii" or String(lm["type"]) == "dragon":
			if p.distance_to(Vector2(float(lm["at"][0]), float(lm["at"][1]))) < 12.0:
				return false
	return true


# ─────────────────────────── 地標 placeholder ───────────────────────────

func _landmarks() -> void:
	var g := vroot.get_node("Landmarks")
	for lm in L["landmarks"]:
		var at := Vector2(float(lm["at"][0]), float(lm["at"][1]))
		var gy := _hgrid(at.x, at.y)
		var n := Node3D.new()
		n.name = String(lm["id"])
		n.position = Vector3(at.x, gy, at.y)
		n.set_meta("label", lm["label"])
		n.set_meta("src", lm["src"])
		n.set_meta("conf", lm["conf"])
		n.set_meta("placeholder", true)
		if lm.has("status"):
			n.set_meta("status", lm["status"])
		g.add_child(n)
		var top := 8.0
		match String(lm["type"]):
			"torii":
				top = _torii(n, float(lm["span"]), float(lm["h"]), float(lm.get("yaw", 0.0)))
			"box":
				var s3: Array = lm["size"]
				var size := Vector3(float(s3[0]), float(s3[1]), float(s3[2]))
				if String(lm.get("display", "solid")) == "wire":
					_wire_box(n, size, float(lm.get("yaw", 0.0)), _c(lm["color"]))
				else:
					_box(n, "Block", size, Vector3.ZERO, float(lm.get("yaw", 0.0)), _c(lm["color"]))
				top = size.y
			"dragon":
				var base: Array = lm["base"]
				var bt := float(lm["base_top"])
				# 基座從河床（或地面）起算到 base_top 世界高度
				var bh := bt - gy + 1.0
				var basen := _box(n, "Base", Vector3(float(base[0]), bh, float(base[1])),
					Vector3(0, -1.0, 0), 0.0, _k(Color(0.55, 0.53, 0.50)))
				basen.set_meta("top_y", bt)
				var cyl := CylinderMesh.new()
				cyl.top_radius = float(lm["statue_r"]) * 0.5
				cyl.bottom_radius = float(lm["statue_r"])
				cyl.height = float(lm["statue_h"])
				var st := _mi(n, "Statue", cyl, _mat(_k(Color(0.35, 0.45, 0.42))))
				st.position.y = bt - gy + float(lm["statue_h"]) * 0.5
				top = bt - gy + float(lm["statue_h"])
			"wheel":
				var wr := float(lm["r"])
				var wc := CylinderMesh.new()
				wc.top_radius = wr
				wc.bottom_radius = wr
				wc.height = 0.8
				var wmi := _mi(n, "Wheel", wc, _mat(_k(Color(0.45, 0.32, 0.20))))
				wmi.rotation_degrees = Vector3(0, 0, 90)
				wmi.position.y = wr * 0.6
				top = wr * 1.6
		# 名牌只在遠景（>150 m）出現：人眼視角審的是空間，不是字
		_label(n, "%s\n%s" % [lm["label"], lm["id"]], Vector3(0, top + 3.0, 0), 0.035, 96, 0.0, 300.0,
			Color(1.0, 0.95, 0.75))


## 未定案地標（紫色候補、稗田邸 provisional）：只畫地面 footprint 外框＋量體線框，
## 沒有實面、沒有碰撞 → 不擋主街視線（sightline），也不擋人走。尺寸照 layout size（公尺）。
func _wire_box(parent: Node3D, size: Vector3, yaw_deg: float, col: Color) -> void:
	var yaw := deg_to_rad(yaw_deg)
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var corners := [Vector2(-hx, -hz), Vector2(hx, -hz), Vector2(hx, hz), Vector2(-hx, hz)]
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col.lightened(0.35)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# 量體線框：12 條邊（PRIMITIVE_LINES，1 px，不遮擋）
	var ls := SurfaceTool.new()
	ls.begin(Mesh.PRIMITIVE_LINES)
	for i in 4:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		var ya := _gy_local(parent, a, yaw) + 0.1
		var yb := _gy_local(parent, b, yaw) + 0.1
		for pair in [[ya, yb], [size.y, size.y]]:
			ls.add_vertex(_rot(a, yaw, pair[0]))
			ls.add_vertex(_rot(b, yaw, pair[1]))
		ls.add_vertex(_rot(a, yaw, ya))
		ls.add_vertex(_rot(a, yaw, size.y))
	var wire := _mi(parent, "Wire", ls.commit(), mat, false)
	wire.set_meta("note", "量體線框（未定案地標；不擋視線、無碰撞）")
	# 地面 footprint 外框：0.5 m 寬，貼地 +0.06 m，每 1 m 取樣地面
	var fs := SurfaceTool.new()
	fs.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 4:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		var inward := -(a + b).normalized() * 0.5 if (a + b).length() > 0.0 else Vector2.ZERO
		var n := maxi(1, int(ceil(a.distance_to(b))))
		for s in n:
			var p0 := a.lerp(b, float(s) / n)
			var p1 := a.lerp(b, float(s + 1) / n)
			var q0 := p0 + inward
			var q1 := p1 + inward
			var v := [p0, p1, q1, q0]
			var vv: Array[Vector3] = []
			for w in v:
				vv.append(_rot(w, yaw, _gy_local(parent, w, yaw) + 0.06))
			for t in [0, 1, 2, 0, 2, 3]:
				fs.set_normal(Vector3.UP)
				fs.add_vertex(vv[t])
	var fp := _mi(parent, "Footprint", fs.commit(), mat, false)
	fp.set_meta("footprint_m", [size.x, size.z])
	parent.set_meta("display", "wire")
	parent.set_meta("footprint_m", [size.x, size.z])
	parent.set_meta("height_m", size.y)


## 地標局部座標（未旋轉的 XZ）→ 旋轉後的局部 Vector3
func _rot(p: Vector2, yaw: float, y: float) -> Vector3:
	var r := p.rotated(-yaw)
	return Vector3(r.x, y, r.y)


## 地標局部點的地面高度（相對地標原點 Y）
func _gy_local(parent: Node3D, p: Vector2, yaw: float) -> float:
	var r := p.rotated(-yaw)
	var wx := parent.position.x + r.x
	var wz := parent.position.z + r.y
	return _hgrid(wx, wz) - parent.position.y


## 鳥居 placeholder：兩柱＋笠木＋貫，紅色方塊。回傳頂高。
func _torii(parent: Node3D, span: float, h: float, yaw_deg: float) -> float:
	var t := Node3D.new()
	t.name = "Torii"
	t.rotation.y = deg_to_rad(yaw_deg)
	parent.add_child(t)
	var red := _k(Color(0.78, 0.20, 0.14)) * 1.3   # 朱色保留辨識度
	var pr := maxf(0.35, span * 0.05)
	for sx in [-1.0, 1.0]:
		_box(t, "Pillar_%s" % ("L" if sx < 0 else "R"), Vector3(pr * 2, h, pr * 2),
			Vector3(sx * span * 0.5, 0, 0), 0.0, red)
	_box(t, "Kasagi", Vector3(span * 1.35, pr * 1.6, pr * 2.2), Vector3(0, h, 0), 0.0,
		_k(Color(0.18, 0.16, 0.15)), false)
	_box(t, "Nuki", Vector3(span * 1.1, pr * 1.1, pr * 1.4), Vector3(0, h * 0.78, 0), 0.0, red, false)
	return h + pr * 1.6


# ─────────────────────────── 任務錨點與傳送點 ───────────────────────────

func _anchors() -> void:
	var g := vroot.get_node("QuestAnchors")
	for qa in L["quest_anchors"]:
		var at := Vector2(float(qa["at"][0]), float(qa["at"][1]))
		var m := Marker3D.new()
		m.name = String(qa["id"])
		m.position = Vector3(at.x, _hgrid(at.x, at.y), at.y)
		m.set_meta("label", qa["label"])
		m.set_meta("old_slice", qa["old_slice"])
		if qa.has("status"):
			m.set_meta("status", qa["status"])
		g.add_child(m)
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.25
		cyl.bottom_radius = 0.25
		cyl.height = 2.6
		var pm := StandardMaterial3D.new()
		pm.albedo_color = Color(0.95, 0.25, 0.85)
		pm.emission_enabled = true
		pm.emission = Color(0.95, 0.25, 0.85)
		pm.emission_energy_multiplier = 0.6
		var pole := _mi(m, "Pole", cyl, pm, false)
		pole.position.y = 1.3
		_label(m, "◆ " + String(qa["label"]), Vector3(0, 3.4, 0), 0.012, 96, 0.0, 140.0,
			Color(1.0, 0.7, 0.95))


func _portals() -> void:
	var g := vroot.get_node("Portals")
	for pt in L["portals"]:
		var at := Vector2(float(pt["at"][0]), float(pt["at"][1]))
		var m := Marker3D.new()
		m.name = String(pt["id"])
		m.position = Vector3(at.x, _hgrid(at.x, at.y), at.y)
		m.set_meta("target", pt["target"])
		m.set_meta("label", pt["label"])
		m.set_meta("src", pt["src"])
		m.set_meta("conf", pt["conf"])
		if pt.has("status"):
			m.set_meta("status", pt["status"])
		g.add_child(m)
		var disc := CylinderMesh.new()
		disc.top_radius = 2.5
		disc.bottom_radius = 2.5
		disc.height = 0.12
		var dm := StandardMaterial3D.new()
		dm.albedo_color = Color(0.3, 0.85, 1.0, 0.55)
		dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		dm.emission_enabled = true
		dm.emission = Color(0.3, 0.85, 1.0)
		dm.emission_energy_multiplier = 0.5
		var d := _mi(m, "Disc", disc, dm, false)
		d.position.y = 0.08
		_label(m, "⇄ " + String(pt["label"]), Vector3(0, 3.0, 0), 0.014, 96, 0.0, 160.0,
			Color(0.6, 0.95, 1.0))


func _debug() -> void:
	var g := vroot.get_node("Debug")
	g.set_meta("note", "LAYOUT_PROTOTYPE：只有 placeholder。座標來源 maps/village_v2/layout_v2.json")
	_label(g, "北 N ↑", Vector3(525, 70, -315), 0.3, 128, 300.0, 2000.0)


# ─────────────────────────── 輸出：meta、機位、報告 ───────────────────────────

func _write_meta() -> void:
	var F: Dictionary = L["frame"]
	var portals: Array = []
	for pt in L["portals"]:
		var x := float(pt["at"][0])
		var z := float(pt["at"][1])
		var inward := Vector2(-x, -z).normalized() * 4.0
		portals.append({
			"x": x, "y": snappedf(_hgrid(x, z), 0.01), "z": z,
			"target": pt["target"],
			"arrival_ground_y": snappedf(_hgrid(x + inward.x, z + inward.y), 0.01),
			"arrival_y_offset": 1.2,
			"arrival_yaw": float(pt["arrival_yaw"]),
			"note": "%s（%s，conf=%s）" % [pt["label"], pt["src"], pt["conf"]]})
	var sp: Dictionary = L["spawn"]
	var meta := {
		"_note": "V2 blockout 開發用（--map=village_v2）。由 tools/gen_village_v2.gd 產生，勿手改。正式遊戲的人間之里仍是 slice（計畫 §52）。",
		"id": "village_v2",
		"playSize": [float(F["x1"]) - float(F["x0"]), float(F["z1"]) - float(F["z0"])],
		"spawn": {"x": float(sp["at"][0]), "z": float(sp["at"][1]), "yaw": float(sp["yaw"])},
		"portals": portals}
	var f := FileAccess.open(META, FileAccess.WRITE)
	f.store_string(JSON.stringify(meta, "\t") + "\n")
	f.close()
	print("[v2] meta → ", META)
	# 平台邊分類（Natural／Retaining）：P4 放擋土、驗證量坡度用；不放進 runtime meta。
	var ef := FileAccess.open(EDGES, FileAccess.WRITE)
	ef.store_string(JSON.stringify(edge_stats) + "\n")
	ef.close()
	print("[v2] 平台邊分類 → ", EDGES)


func _write_shots() -> void:
	_shots_out(L["review_shots"], SHOT_FILE)
	var VW: Dictionary = L.get("variants", {}).get("main_street_width", {})
	if VW.has("shots"):
		_shots_out(VW["shots"], VARIANT_SHOT_FILE)


## 機位：abs＝絕對座標（r1 解算值凍結，保證每輪、每個 Variant 同機位）；否則 y 加地面高。
## hide 未指定時：絕對機位不藏、相對（人眼）機位藏 Debug。FOV 用 main.gd 審圖相機預設 75°（垂直）。
func _shots_out(list: Array, path: String) -> void:
	var out: Array = []
	for s in list:
		var c: Array = s["cam"]
		var l: Array = s["look"]
		var cam := Vector3(float(c[0]), float(c[1]), float(c[2]))
		var look := Vector3(float(l[0]), float(l[1]), float(l[2]))
		if not s.get("abs", false):
			cam.y += _hgrid(cam.x, cam.z)
			look.y += _hgrid(look.x, look.z)
		out.append({"name": s["name"],
			"cam": [snappedf(cam.x, 0.01), snappedf(cam.y, 0.01), snappedf(cam.z, 0.01)],
			"look": [snappedf(look.x, 0.01), snappedf(look.y, 0.01), snappedf(look.z, 0.01)],
			"time": s.get("time", 11), "hud": false,
			"hide": s.get("hide", [] if s.get("abs", false) else ["Debug"])})
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "	") + "\n")
	f.close()
	print("[v2] shots → %s（%d 張）" % [path, out.size()])


func _report() -> void:
	var lo := INF
	var hi := -INF
	for v in hg:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	print("[v2] 地形高度 %.2f … %.2f m" % [lo, hi])
	for r in roads:
		if r["name"] == "MainStreet":
			print("[v2] 主街 Variant %s：半寬 %.3f m（全寬 %.2f m）" % [variant, r["hw"], float(r["hw"]) * 2.0])
	var hill: Dictionary = L["hill"]
	var peaks := [["主丘", hill["center"]]]
	for lb in hill.get("lobes", []):
		peaks.append([String(lb["label"]), lb["center"]])
	for pk in peaks:
		var c: Array = pk[1]
		print("[v2] 北丘 %-14s (%.0f, %.0f) 地面 %.2f m" % [pk[0], float(c[0]), float(c[1]), _hgrid(float(c[0]), float(c[1]))])
	var rhw_min := INF
	var rhw_max := -INF
	for v in river_hw:
		rhw_min = minf(rhw_min, v)
		rhw_max = maxf(rhw_max, v)
	print("[v2] 主河 %d 點，全寬 %.1f–%.1f m（寬窄比 %.2f）" % [river_pts.size(), rhw_min * 2.0, rhw_max * 2.0, rhw_max / rhw_min])
	for ws in water_stats:
		print("[v2] 水面 %-10s 濕頂點 %d、水面格 %d（%d 點碰到 %.0f m 範圍上限）" % [ws[0], ws[1], ws[2], ws[3], WATER_REACH])
	var probes := {
		"南門 LANDMARK_SOUTH_GATE": Vector2(234, 100), "主街中段": Vector2(250, 10),
		"主街北端": Vector2(300, -130), "北丘頂": Vector2(262, -215),
		"農田": Vector2(440, 20), "主河中線": Vector2(430, -150), "水渠 G5": Vector2(334, -10),
		"西住宅": Vector2(170, -60), "傳送點 trail": Vector2(224, 172)}
	for k in probes:
		var p: Vector2 = probes[k]
		print("[v2] 高度 %-20s (%.0f, %.0f) = %.2f m" % [k, p.x, p.y, _hgrid(p.x, p.y)])
	print("[v2] 橋 %d 座：" % bridges.size())
	for b in vroot.get_node("Roads/Bridges").get_children():
		var eh: Array = b.get_meta("end_heights")
		print("       %s  長 %.1f m、交角 %.0f°、兩端 %.2f / %.2f m" % [b.name,
			float(b.get_meta("length_m")), float(b.get_meta("cross_deg")), eh[0], eh[1]])
	var tri := 0
	for mi in vroot.find_children("*", "MeshInstance3D", true, false):
		var m: Mesh = (mi as MeshInstance3D).mesh
		if m is ArrayMesh:
			for s in m.get_surface_count():
				var arr := m.surface_get_arrays(s)
				var idx = arr[Mesh.ARRAY_INDEX]
				tri += (idx as PackedInt32Array).size() / 3 if idx != null and (idx as PackedInt32Array).size() > 0 \
					else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	print("[v2] 節點 %d、ArrayMesh 三角面 %d" % [_count(vroot), tri])


func _count(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count(ch)
	return c

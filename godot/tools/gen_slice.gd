# PHASE 1.5 —— 人間之里 Vertical Slice（art benchmark）
#
#   godot --headless --path godot --script tools/gen_slice.gd
#   xvfb-run -a godot --rendering-driver opengl3 --path godot -- --map=slice \
#     --shots=res://tools/shots/slice.json --shotdir=<dir>
#
# ══════════════════════════════════════════════════════════════════════
# 這是什麼、不是什麼
# ══════════════════════════════════════════════════════════════════════
# **是**：一段 8 棟建築的街，用來回答「整體畫面能不能脫離 procedural demo」。
#         獨立的 map（`maps/slice/`），可以來回重生成、重審圖，不動 village。
# **不是**：整村重做。169 棟、六座地標、河流、稗田邸一律沒碰。
#
# ── PHASE 1.6：legacy quarantine ──
# 這個 slice 裡**沒有任何 legacy blockout 建築**。原本用來製造變化的三棟
# （machiya_f_b / b_a / e_a）全部移出：它們是白盒子、屋頂只有一片斜面、
# 高度搶戲但細節不足，站在有軸組有瓦的新版旁邊會直接綁架審圖。
# ⚠ **資產一個都沒刪**，village 的 169 棟照樣在用它們 —— 這裡只是不放。
# 代價寫在報告裡：全場同一份 mesh，天際線因此是平的。那正是 Phase 2
# （Architecture Kit）要解的問題，本輪明令不做。
#
# 為什麼要獨立場景而不是在 village 上改：village 的佈局是 `_block()` 的明表
# （169 棟的 frontage 座標），改一格就要重跑全圖 + 五道閘門，一輪 6 分鐘。
# 這裡 46m 見方、8 棟，一輪 25 秒 —— 審圖要能**反覆**才有意義。
#
# ── 街道構圖的規矩：planned irregularity，不是 random scatter ──
# 所有的變化都寫在 `LOTS` 明表裡，每一筆都有理由（見表上的註解）。
# 沒有一個 `randf()` 決定建築的位置、朝向或退縮 —— 亂數只出現在
# 「同一種雜草的角度」這種層級。
extends SceneTree

const OUT_DIR := "res://maps/slice/"
const MAP_ID := "slice"
const HALF := 46.0
const SEED := 20260807

# 街：沿 x 走，路心 z = 0，路寬 6.0（夯土）。側街沿 z 走，x = +21。
const ROAD_W := 7.2
const SIDE_X := 21.0

var lib = preload("res://tools/gen_lib.gd").new()
var _root: Node3D
var _mods := {}
var _nh: FastNoiseLite
var _rng := RandomNumberGenerator.new()
var _audit: Array[String] = []


# ══════════════════════════════════════════════════════════════════════
# 街廓：8 個地塊。**每一筆的偏移都有理由**
# ══════════════════════════════════════════════════════════════════════
#
# 欄位：kind / x / 退縮 setback（離路緣多遠）/ side（+1 北側、−1 南側）/
#       yaw 微轉（弧度）/ role（決定掛什麼道具）/ why（為什麼這樣擺）
#
# 北側的正面朝 +z（模組正面朝 +z，見 town_modules 的 gbox），所以 yaw=0；
# 南側要轉 PI。「微轉」是 ±0.03 rad（約 1.7°）—— 大到看得出不是尺規排的，
# 小到不會讓相鄰的簷口打架。真實町並みの不整齊就是這個量級：
# 地界是幾百年前分的，房子照地界蓋，所以歪的是**地界**不是房子。
const LOTS := [
	# ── 北側（正面朝街）──
	{"kind": "machiya_f_a", "x": -20.0, "back": 3.4, "side": 1, "yaw": 0.0,
	 "role": "shop", "why": "街西端。最正、當基準"},
	{"kind": "machiya_f_a", "x": -9.8, "back": 3.0, "side": 1, "yaw": 0.028,
	 "role": "shop", "why": "退縮比鄰居少 0.4m —— 店面搶街，這是商業街的常態"},
	# ⚠ 這裡是**巷口**：下一棟往東讓開 2.6m
	{"kind": "machiya_f_a", "x": 2.4, "back": 3.7, "side": 1, "yaw": -0.021,
	 "role": "house", "why": "PHASE 1.6：原本是 legacy machiya_f_b（白盒子）。"
		+ "退縮最多，巷口那側的山牆才露得出來"},
	{"kind": "machiya_f_a", "x": 12.6, "back": 3.1, "side": 1, "yaw": 0.016,
	 "role": "shop", "why": "接近路口，重新往前站"},
	# ── 南側（正面朝街，yaw=PI）──
	{"kind": "machiya_f_a", "x": -15.2, "back": 3.3, "side": -1, "yaw": 0.0,
	 "role": "house", "why": "對街不對齊北側 —— 兩側的節奏錯開，街才不像走廊"},
	{"kind": "machiya_f_a", "x": -4.6, "back": 3.5, "side": -1, "yaw": -0.024,
	 "role": "shop", "why": "對街的店。跟東鄰之間留 2.0m 側巷（服務動線）"},
	{"kind": "machiya_f_a", "x": 7.4, "back": 3.2, "side": -1, "yaw": 0.019,
	 "role": "house", "why": "側巷的另一側"},
	# ── 轉角：**妻入り**（山牆朝街）──
	# ⚠ PHASE 1.6：原本是 legacy machiya_e_a。同一份 mesh 轉 90° 之後，
	# 街上看到的是**山牆＋破風板＋懸魚**而不是格子立面 —— 剪影完全不同。
	# 平入り／妻入り本來就是町家的兩種正統形，這不是偷懶，是免費的變化。
	{"kind": "machiya_f_a", "x": 21.6, "back": -5.4, "side": 1, "yaw": -PI * 0.5,
	 "role": "corner", "why": "轉角棟：妻入り，正面朝側街（−x）"},
	# ── 後排：只供天際線的第二層 ──
	# ⚠ PHASE 1.6：原本是 legacy machiya_b_a（9.4m 白盒子）。它退到後排之後
	# 仍然在天際線上讀成一塊白色量體 —— 規格的判準是「高度搶戲但細節不足」，
	# 它兩條都中。換成兩棟**妻入り的 production 町家**：屋脊垂直街道，
	# 從街上看是兩片山牆疊在前排屋頂後面，深度資訊拿到了、白盒子沒了。
	{"kind": "machiya_f_a", "x": -6.5, "back": 15.8, "side": -1, "yaw": PI * 0.5 + 0.04,
	 "role": "back", "why": "後排・妻入り。只供天際線，不供街景"},
	{"kind": "machiya_f_a", "x": 4.8, "back": 16.6, "side": -1, "yaw": PI * 0.5 - 0.03,
	 "role": "back", "why": "後排第二棟，退得比鄰棟深 0.8m"},
]

# 道具佈局：靠牆、簷下、不對稱。也是明表。
# kind: 掛在建物上的（暖簾／招牌／提灯）用 lot 的 facade 錨點；
#       地面的直接給座標（相對 lot 原點的本地偏移）。
const SHOP_PROPS := [
	{"m": "prop_crate", "dx": -2.9, "dz": 1.35, "yaw": 0.22, "s": 1.0},
	{"m": "prop_crate", "dx": -2.55, "dz": 1.05, "yaw": -0.35, "s": 0.86},
	{"m": "prop_basket", "dx": -3.5, "dz": 1.15, "yaw": 0.9, "s": 1.0},
	{"m": "prop_barrel", "dx": 3.2, "dz": 1.25, "yaw": 0.0, "s": 1.0},
	{"m": "prop_barrel", "dx": 3.62, "dz": 0.95, "yaw": 0.5, "s": 0.9},
]
const HOUSE_PROPS := [
	{"m": "prop_barrel", "dx": 3.05, "dz": 1.05, "yaw": 0.3, "s": 0.78},
	{"m": "prop_basket", "dx": -3.2, "dz": 0.95, "yaw": -0.6, "s": 0.82},
]


func _init() -> void:
	var f := FileAccess.open("res://data/town_modules.json", FileAccess.READ)
	_mods = JSON.parse_string(f.get_as_text())["modules"]
	f.close()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR + "gen"))
	_nh = FastNoiseLite.new()
	_nh.frequency = 0.05
	_nh.seed = 500
	_rng.seed = SEED

	_root = Node3D.new()
	_root.name = "Slice"
	_root.set_meta("own_colliders", true)
	lib.setup(_root, SEED)

	lib.terrain(OUT_DIR, HALF, 181, height_at, mask_at, "stone_flag",
		Color(0.62, 0.90, 0.56), "terrain_path", Color(0.78, 0.70, 0.58))
	lib.boundary(HALF - 2.0)
	_build_ground()
	_build_buildings()
	_build_props()
	_build_node()
	_build_planting()
	_build_people()
	_build_env()

	for line in _audit:
		print(line)
	var packed := PackedScene.new()
	packed.pack(_root)
	print("saved %s.tscn err=%d  節點 %d"
		% [MAP_ID, ResourceSaver.save(packed, OUT_DIR + MAP_ID + ".tscn"),
			_count(_root)])
	_write_meta()
	quit(0)


func _count(n: Node) -> int:
	var t := 1
	for c in n.get_children():
		t += _count(c)
	return t


# ══════════════════════════════════════════════════════════════════════
# 地形：**不是一塊平板**
# ══════════════════════════════════════════════════════════════════════
#
# 規格說「不要讓房子像模型直接放在平面上」。所以地面要有三件事：
#   1. 路是**壓實下陷**的（比兩側低 6~9cm）—— 幾百年走出來的
#   2. 路面有**車轍**：兩條沿 x 的淺溝，離路心 ±1.15m（板車的輪距）
#   3. 建物腳下有**微微墊高**：土在牆邊堆起來，不是切齊
func height_at(x: float, z: float) -> float:
	var h := _nh.get_noise_2d(x * 0.35, z * 0.35) * 0.13
	# 主街：路心下陷
	var dz: float = absf(z) - ROAD_W * 0.5
	var on_road: float = 1.0 - smoothstep(0.0, 2.6, maxf(dz, 0.0))
	# 側街
	var dx2: float = absf(x - SIDE_X) - 2.2
	on_road = maxf(on_road, (1.0 - smoothstep(0.0, 2.2, maxf(dx2, 0.0)))
		* clampf(1.0 - absf(z) / 26.0, 0.0, 1.0))
	h -= on_road * 0.075
	# 車轍：兩條淺溝。⚠ 深度只給 25mm —— 再深就變成排水溝而不是輪痕，
	# 而且玩家走過去會有「踩進坑」的觸感（膠囊會頓一下）。
	for rut in [-1.15, 1.15]:
		var d := absf(z - rut)
		h -= on_road * 0.025 * (1.0 - smoothstep(0.0, 0.34, d))
	# 建物腳下微微墊高：土堆在牆邊
	for L in LOTS:
		var c := _lot_center(L)
		var lx: float = absf(x - c.x) - 5.2
		var lz: float = absf(z - c.y) - 5.0
		h += 0.055 * (1.0 - smoothstep(0.0, 1.7, maxf(maxf(lx, lz), 0.0)))
	return h


func mask_at(x: float, z: float) -> Color:
	# R = 石板　G = 田（不用）　B = 巨觀明暗　A = 夯土
	#
	# ⚠ 規格：「目前大片亮色石板路太搶戲」。所以這裡**反過來**：
	# 主街整條是**夯土**，石板只出現在店門口那幾塊（人真的會踩的地方）。
	# village 的做法是「有店就有石板」鋪成一整片；這裡是「店**門口**才有」。
	var dz: float = absf(z) - ROAD_W * 0.5
	var road: float = 1.0 - smoothstep(0.0, 2.2, maxf(dz, 0.0))
	var dx2: float = absf(x - SIDE_X) - 2.2
	road = maxf(road, (1.0 - smoothstep(0.0, 1.8, maxf(dx2, 0.0)))
		* clampf(1.0 - absf(z) / 26.0, 0.0, 1.0))
	var dirt := road
	# 店門口的敷石：只在 shop 的門前 2.4m 見方
	var stone := 0.0
	for L in LOTS:
		if String(L.role) != "shop":
			continue
		var c := _lot_center(L)
		var fz: float = c.y - float(L.side) * 4.9      # 門面線
		if absf(x - c.x) < 2.6 and absf(z - fz) < 1.5:
			stone = maxf(stone, 1.0 - smoothstep(1.0, 1.5, absf(z - fz)))
	# 井邊也鋪石（打水的地方一定是硬鋪面）
	if Vector2(x - 17.6, z - 0.4).length() < 3.4:
		stone = maxf(stone, 1.0 - smoothstep(2.2, 3.4, Vector2(x - 17.6, z - 0.4).length()))
	dirt = maxf(dirt * (1.0 - stone), 0.0)
	# 屋邊的踏み固め：牆腳一圈也是土（沒有草會長在天天走的地方）
	for L in LOTS:
		var c2 := _lot_center(L)
		# ⚠ 第一版只鋪到牆外 1.5m，實測房子腳下還看得到亮綠草地 —— 房子讀成
		# 「放在草皮上的模型」，正是規格要解的那件事。加寬到 3.4m，而且
		# **貼牆那一圈給滿**（0.95）：天天有人走的地方不會有草。
		var lx: float = absf(x - c2.x) - 5.4
		var lz: float = absf(z - c2.y) - 5.2
		var od: float = maxf(maxf(lx, lz), 0.0)
		dirt = maxf(dirt, 0.95 * (1.0 - smoothstep(0.0, 3.4, od)))
	var macro := clampf(_nh.get_noise_2d(x * 0.22, z * 0.22) * 0.5 + 0.5, 0.0, 1.0)
	return Color(stone, 0.0, macro, clampf(dirt, 0.0, 1.0))


func _lot_center(L: Dictionary) -> Vector2:
	## 地塊原點：模組的正面在原點、量體往背面長。
	## side=+1（北側）→ 正面朝 +z，原點在 z = −back。
	if String(L.role) == "corner":
		return Vector2(float(L.x), float(L.back))
	return Vector2(float(L.x), -float(L.side) * float(L.back))


# ══════════════════════════════════════════════════════════════════════
# 地面層：石溝・路邊石・踏石・牆腳碎石
# ══════════════════════════════════════════════════════════════════════
func _build_ground() -> void:
	var g := lib.add(_root, Node3D.new(), "地面層") as Node3D
	var stone := lib.pbr("slice_kerb", "stone_wall", 0.32, Color(0.80, 0.80, 0.78))
	var dark := lib.pbr("slice_gutter", "stone_wall", 0.36, Color(0.52, 0.53, 0.52))
	var flag := lib.pbr("slice_flag", "stone_flag", 0.30, Color(0.86, 0.85, 0.82))
	# ── 石溝：路兩側各一條。町家的雨水從簷口落下就進這條溝 ──
	var gut: Array[Transform3D] = []
	var gm := BoxMesh.new()
	gm.size = Vector3(1.0, 0.26, 0.34)
	gm.material = dark
	var krb: Array[Transform3D] = []
	var km := BoxMesh.new()
	km.size = Vector3(1.0, 0.22, 0.16)
	km.material = stone
	var x := -HALF + 8.0
	while x < HALF - 8.0:
		for sd in [-1.0, 1.0]:
			var zz: float = sd * (ROAD_W * 0.5 + 0.30)
			var y := height_at(x, zz)
			gut.append(Transform3D(Basis(), Vector3(x, y - 0.05, zz)))
			krb.append(Transform3D(Basis(), Vector3(x, y + 0.02, zz + sd * 0.26)))
		x += 1.0
	_mm(g, "MM_石溝", gm, gut)
	_mm(g, "MM_路邊石", km, krb)
	# ── 踏石：只在幾個「人會踏」的點，不鋪成路 ──
	# ⚠ 這是跟 village 最大的差別。village 是整條街鋪石板；這裡是夯土為主，
	# 石頭只出現在門口、井邊、跨溝的地方 —— 石頭少了，土才讀得出來是土。
	var step: Array[Transform3D] = []
	var sm := BoxMesh.new()
	sm.size = Vector3(0.72, 0.11, 0.62)
	sm.material = flag
	for L in LOTS:
		var c := _lot_center(L)
		var fz: float = c.y - float(L.side) * 4.9
		if String(L.role) == "corner":
			continue
		# 跨石溝的踏石（從門口踏出來到街上）
		for k in 3:
			var px: float = c.x - 1.1 + float(k) * 1.1
			var pz: float = fz - float(L.side) * (0.5 + float(k % 2) * 0.22)
			step.append(Transform3D(
				Basis(Vector3.UP, _rng.randf_range(-0.09, 0.09)),
				Vector3(px, height_at(px, pz) + 0.03, pz)))
	_mm(g, "MM_踏石", sm, step)
	# ── 牆腳碎石（犬走り的簡版）+ 排水點 ──
	var peb: Array[Transform3D] = []
	var pm: Mesh = lib.blob_mesh(41, 0.5, 0.22)
	for L in LOTS:
		var c := _lot_center(L)
		for k in 26:
			var a := TAU * float(k) / 26.0
			var rr := 5.4 + _rng.randf_range(-0.5, 0.5)
			var px: float = c.x + cos(a) * rr
			var pz: float = c.y + sin(a) * rr * 0.92
			var s := _rng.randf_range(0.10, 0.20)
			peb.append(Transform3D(
				Basis(Vector3.UP, _rng.randf_range(0.0, TAU))
					* Basis.from_scale(Vector3(s, s * 0.55, s)),
				Vector3(px, height_at(px, pz) + 0.02, pz)))
	var pmi := MultiMeshInstance3D.new()
	pmi.multimesh = lib.make_multimesh(pm, peb, [], OUT_DIR + "gen/mm_pebble.res")
	pmi.material_override = lib.rock_mat_dry()
	lib.add(g, pmi, "MM_牆腳碎石")
	_audit.append("地面層：石溝 %d 節・路邊石 %d・踏石 %d・牆腳碎石 %d"
		% [gut.size(), krb.size(), step.size(), peb.size()])


func _mm(g: Node3D, name: String, mesh: Mesh, list: Array[Transform3D]) -> void:
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = lib.make_multimesh(mesh, list, [],
		OUT_DIR + "gen/mm_%s.res" % name.trim_prefix("MM_"))
	lib.add(g, mmi, name)


# ══════════════════════════════════════════════════════════════════════
# 建築
# ══════════════════════════════════════════════════════════════════════
func _build_buildings() -> void:
	var g := lib.add(_root, Node3D.new(), "建築") as Node3D
	var body := StaticBody3D.new()
	body.name = "建築碰撞"
	_root.add_child(body)
	body.owner = _root
	var batch := {}
	for i in LOTS.size():
		var L: Dictionary = LOTS[i]
		var c := _lot_center(L)
		var yaw: float = float(L.yaw) + (PI if int(L.side) < 0
			and String(L.role) != "corner" else 0.0)
		var m: Dictionary = _mods[String(L.kind)]
		var y := height_at(c.x, c.y)
		var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(c.x, y, c.y))
		if not batch.has(String(L.kind)):
			batch[String(L.kind)] = [] as Array[Transform3D]
		batch[String(L.kind)].append(xf)
		# 碰撞：牆身 footprint（不含出簷），跟 village 同一條規矩
		var sh := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(float(m.w), float(m.h), float(m.d))
		sh.shape = bx
		sh.transform = Transform3D(Basis(Vector3.UP, yaw),
			Vector3(c.x, y + float(m.h) * 0.5, c.y)
			+ Vector3(sin(yaw), 0, cos(yaw)) * (-float(m.d) * 0.5))
		body.add_child(sh)
		sh.owner = _root
	var names: Array = batch.keys()
	names.sort()
	for k in names:
		# ⚠ 語意材質模組（新版 machiya_f_a）要走 semantic_mesh，
		# legacy 的單 surface 模組走 prop_mesh —— 判斷依據是 surface 數，
		# 跟 gen_town._emit_batches 同一條規則。
		var probe: Array = lib.semantic_mesh(String(_mods[k]["glb"]))
		var mesh: Mesh = probe[0]
		if mesh.get_surface_count() <= 1:
			mesh = lib.prop_mesh(String(_mods[k]["glb"]))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = lib.make_multimesh(mesh, batch[k], [],
			OUT_DIR + "gen/mm_%s.res" % k)
		lib.add(g, mmi, "MM_%s" % k)
	_audit.append("建築 %d 棟 / %d 種模組（新版 machiya_f_a %d 棟、legacy %d 棟）"
		% [LOTS.size(), names.size(),
			batch.get("machiya_f_a", []).size(),
			LOTS.size() - batch.get("machiya_f_a", []).size()])


# ══════════════════════════════════════════════════════════════════════
# 生活道具層
# ══════════════════════════════════════════════════════════════════════
#
# 規格：「不要一次做幾百種 props，重點是讓街道開始有『有人生活』的感覺」。
# 所以只用**既有的** glb（barrel / crate / basket / bench / noren / chochin /
# kanban），缺的幾件（水桶・掃帚・柴堆・盆栽・晾衣・地藏）直接在這裡用
# lib.box/cyl 疊出來 —— 不開新 glb、不開新材質。
func _build_props() -> void:
	var g := lib.add(_root, Node3D.new(), "道具") as Node3D
	var batch := {}
	var put := func(m: String, t: Transform3D) -> void:
		if not batch.has(m):
			batch[m] = [] as Array[Transform3D]
		batch[m].append(t)
	var n_hang := 0
	for L in LOTS:
		var c := _lot_center(L)
		var role := String(L.role)
		var m: Dictionary = _mods[String(L.kind)]
		var sd: float = float(L.side) if role != "corner" else 1.0
		var yaw: float = float(L.yaw) + (PI if int(L.side) < 0 and role != "corner" else 0.0)
		var fwd := Vector3(sin(yaw), 0, cos(yaw))       # 模組正面朝這個方向
		var rgt := Vector3(cos(yaw), 0, -sin(yaw))
		var base := Vector3(c.x, 0, c.y)
		var fz: float = float(m.get("facade", {}).get("beam_z", 1.95))
		# ── 掛的：暖簾（店）／招牌（店）／提灯（店，兩盞）──
		if role == "shop":
			var nk := "prop_noren_a" if int(L.x) % 2 == 0 else "prop_noren_b"
			var dx: float = float(m.get("facade", {}).get("door_x", 0.0))
			var p := base + rgt * dx + fwd * 0.92
			p.y = height_at(p.x, p.z) + fz
			put.call(nk, Transform3D(Basis(Vector3.UP, yaw), p))
			n_hang += 1
			var kp := base + rgt * (dx - 2.5) + fwd * 0.62
			kp.y = height_at(kp.x, kp.z) + fz + 0.42
			put.call("prop_kanban", Transform3D(Basis(Vector3.UP, yaw), kp))
			n_hang += 1
			for s2 in [-1.0, 1.0]:
				var cp: Vector3 = base + rgt * (dx + s2 * 1.55) + fwd * 0.80
				cp.y = height_at(cp.x, cp.z) + fz + 0.30
				put.call("prop_chochin", Transform3D(Basis(Vector3.UP, yaw), cp))
				n_hang += 1
		# ── 地上的：靠牆、簷下 ──
		var table: Array = SHOP_PROPS if role == "shop" else HOUSE_PROPS
		for pr in table:
			var p2 := base + rgt * float(pr.dx) + fwd * float(pr.dz)
			p2.y = height_at(p2.x, p2.z)
			var s3 := float(pr.s)
			put.call(String(pr.m), Transform3D(
				Basis(Vector3.UP, yaw + float(pr.yaw)) * Basis.from_scale(Vector3(s3, s3, s3)),
				p2))
		# ── 手工的小件（不開新 glb）──
		if role == "house":
			_bucket(g, base + rgt * -3.6 + fwd * 1.1, yaw)
			_broom(g, base + rgt * 3.4 + fwd * 0.55, yaw)
			_firewood(g, base + rgt * -4.5 + fwd * -1.2, yaw + 0.1)
			_planter(g, base + rgt * 2.4 + fwd * 1.15, yaw)
			_laundry(g, base + rgt * 0.4 + fwd * -6.2, yaw)
		elif role == "shop":
			_planter(g, base + rgt * -4.2 + fwd * 1.0, yaw)
			_bucket(g, base + rgt * 4.0 + fwd * 0.9, yaw)
	var mods: Array = batch.keys()
	mods.sort()
	var total := 0
	for k in mods:
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = lib.make_multimesh(
			lib.prop_mesh("res://assets/models/%s.glb" % k), batch[k], [],
			OUT_DIR + "gen/mm_%s.res" % k)
		lib.add(g, mmi, "MM_%s" % k)
		total += batch[k].size()
	_audit.append("道具：%d 件 / %d 種既有模組（其中吊掛 %d）+ 手工小件"
		% [total, mods.size(), n_hang])


## ── 手工小件：用既有材質疊出來，不開新 glb ──
func _bucket(g: Node3D, p: Vector3, yaw: float) -> void:
	var w := lib.pbr("slice_wood", "planks", 0.55, Color(0.66, 0.58, 0.48))
	var d := lib.pbr("slice_dark", "dark_wood", 0.45, Color(0.40, 0.42, 0.40))
	var y := height_at(p.x, p.z)
	lib.cyl(g, "水桶", 0.16, 0.14, 0.30, w, Vector3(p.x, y + 0.15, p.z), 10)
	lib.cyl(g, "桶箍", 0.165, 0.165, 0.03, d, Vector3(p.x, y + 0.26, p.z), 10)
	var h := lib.cyl(g, "桶提手", 0.012, 0.012, 0.34, d, Vector3(p.x, y + 0.32, p.z), 5)
	h.rotation = Vector3(0, yaw, PI * 0.5)


func _broom(g: Node3D, p: Vector3, yaw: float) -> void:
	## 掃帚**靠著牆**站 —— 立在空地上會像插在地裡的棍子
	var d := lib.pbr("slice_dark", "dark_wood", 0.45, Color(0.40, 0.42, 0.40))
	var st := lib.pbr("slice_straw", "roof_thatch", 0.5, Color(0.72, 0.62, 0.40))
	var y := height_at(p.x, p.z)
	var pole := lib.cyl(g, "掃帚柄", 0.018, 0.020, 1.35, d, Vector3(p.x, y + 0.66, p.z), 6)
	pole.rotation = Vector3(0.16 * cos(yaw), 0, -0.16 * sin(yaw))
	lib.cyl(g, "掃帚穗", 0.10, 0.05, 0.34, st,
		Vector3(p.x + sin(yaw) * 0.10, y + 0.17, p.z + cos(yaw) * 0.10), 7)


func _firewood(g: Node3D, p: Vector3, yaw: float) -> void:
	## 柴堆：疊三層，每層 4~5 根，上層錯開
	var d := lib.pbr("slice_log", "dark_wood", 0.42, Color(0.48, 0.44, 0.40))
	var y := height_at(p.x, p.z)
	for row in 3:
		var n := 5 - row
		for k in n:
			var off := (float(k) - float(n - 1) * 0.5) * 0.17
			var lg := lib.cyl(g, "柴_%d_%d" % [row, k], 0.075, 0.080, 1.05, d,
				Vector3(p.x + cos(yaw) * off, y + 0.085 + float(row) * 0.16,
					p.z - sin(yaw) * off), 6)
			lg.rotation = Vector3(0, yaw, PI * 0.5)


func _planter(g: Node3D, p: Vector3, _yaw: float) -> void:
	var st := lib.pbr("slice_pot", "arakabe", 0.42, Color(0.60, 0.46, 0.38))
	var y := height_at(p.x, p.z)
	lib.cyl(g, "盆", 0.19, 0.15, 0.24, st, Vector3(p.x, y + 0.12, p.z), 9)
	var leaf := MeshInstance3D.new()
	leaf.mesh = lib.tuft_mesh(9, 0.42, 0.26, Color(0.14, 0.28, 0.12), Color(0.30, 0.50, 0.20))
	leaf.material_override = lib.foliage_vc_mat()
	leaf.position = Vector3(p.x, y + 0.24, p.z)
	lib.add(g, leaf, "盆栽")


func _laundry(g: Node3D, p: Vector3, yaw: float) -> void:
	## 晾衣：兩根竿 + 三塊布。⚠ 掛在**後院**（fwd 的反方向 6.2m），
	## 不是掛在店面上 —— 商業立面上晾衣服是住宅的語彙，位置錯了就穿幫。
	var d := lib.pbr("slice_dark", "dark_wood", 0.45, Color(0.40, 0.42, 0.40))
	var cloth := [lib.pbr("slice_cloth_a", "shoji", 0.30, Color(0.72, 0.76, 0.86)),
		lib.pbr("slice_cloth_b", "shoji", 0.30, Color(0.86, 0.78, 0.66)),
		lib.pbr("slice_cloth_c", "shoji", 0.30, Color(0.66, 0.70, 0.64))]
	var y := height_at(p.x, p.z)
	var rgt := Vector3(cos(yaw), 0, -sin(yaw))
	for s in [-1.0, 1.0]:
		var q: Vector3 = p + rgt * (s * 1.75)
		lib.cyl(g, "衣竿柱_%d" % int(s + 1.0), 0.035, 0.040, 1.75, d,
			Vector3(q.x, y + 0.87, q.z), 6)
	var bar := lib.cyl(g, "衣竿", 0.028, 0.028, 3.5, d, Vector3(p.x, y + 1.70, p.z), 6)
	bar.rotation = Vector3(0, yaw, PI * 0.5)
	for k in 3:
		var off := (float(k) - 1.0) * 0.95
		var q2 := p + rgt * off
		lib.box(g, "衣_%d" % k, Vector3(0.62, 0.72, 0.03), cloth[k],
			Vector3(q2.x, y + 1.32, q2.z)).rotation.y = yaw


# ══════════════════════════════════════════════════════════════════════
# 小型節點：井戶 + 地藏（幻想鄉提示的那 10%）
# ══════════════════════════════════════════════════════════════════════
func _build_node() -> void:
	var g := lib.add(_root, Node3D.new(), "節點") as Node3D
	var stone := lib.pbr("slice_kerb", "stone_wall", 0.32, Color(0.80, 0.80, 0.78))
	var d := lib.pbr("slice_dark", "dark_wood", 0.45, Color(0.40, 0.42, 0.40))
	var kaw := lib.pbr("slice_kawara", "roof_kawara", 0.22, Color(0.78, 0.84, 0.98))
	# ── 井戶 ──
	var wx := 17.6
	var wz := 0.4
	var wy := height_at(wx, wz)
	for k in 12:
		var a := TAU * float(k) / 12.0
		lib.box(g, "井筒_%d" % k, Vector3(0.30, 0.62, 0.22), stone,
			Vector3(wx + cos(a) * 0.72, wy + 0.31, wz + sin(a) * 0.72)).rotation.y = -a
	lib.cyl(g, "井口", 0.60, 0.60, 0.06, d, Vector3(wx, wy + 0.63, wz), 12)
	for s in [-1.0, 1.0]:
		lib.box(g, "井桁柱_%d" % int(s + 1.0), Vector3(0.10, 1.85, 0.10), d,
			Vector3(wx + s * 0.78, wy + 0.92, wz))
	lib.box(g, "井桁梁", Vector3(1.86, 0.11, 0.11), d, Vector3(wx, wy + 1.80, wz))
	for s2 in [-1.0, 1.0]:
		var r := lib.box(g, "井屋根_%d" % int(s2 + 1.0), Vector3(2.20, 0.09, 0.86), kaw,
			Vector3(wx, wy + 2.02, wz + s2 * 0.36))
		r.rotation.x = s2 * -0.44
	var rope := lib.cyl(g, "釣瓶繩", 0.012, 0.012, 1.0, d, Vector3(wx, wy + 1.26, wz), 5)
	rope.rotation = Vector3(0, 0, 0)
	_bucket(g, Vector3(wx + 1.15, 0, wz - 0.9), 0.6)
	# ── 地藏（路口的小神龕）+ 護符 + 一株不尋常的植物 ──
	# 規格：90% 傳統聚落 / 10% 幻想鄉提示。所以只有**這一組**，而且藏在
	# 路口的角落，不放在街心 —— 幻想鄉的怪東西是路過才注意到的，不是展示品。
	var jx := 20.6
	var jz := -6.2
	var jy := height_at(jx, jz)
	lib.box(g, "地藏台座", Vector3(0.72, 0.26, 0.62), stone, Vector3(jx, jy + 0.13, jz))
	lib.cyl(g, "地藏身", 0.17, 0.20, 0.58, stone, Vector3(jx, jy + 0.55, jz), 10)
	lib.cyl(g, "地藏頭", 0.155, 0.155, 0.26, stone, Vector3(jx, jy + 0.95, jz), 10)
	# 前掛（紅圍兜）—— 地藏一眼認得出來就是靠這塊布
	lib.box(g, "地藏前掛", Vector3(0.32, 0.30, 0.04),
		lib.pbr("slice_bib", "shoji", 0.30, Color(0.86, 0.34, 0.30)),
		Vector3(jx, jy + 0.62, jz - 0.19))
	for s3 in [-1.0, 1.0]:
		var rf := lib.box(g, "祠屋根_%d" % int(s3 + 1.0), Vector3(1.05, 0.07, 0.52), kaw,
			Vector3(jx, jy + 1.30, jz + s3 * 0.21))
		rf.rotation.x = s3 * -0.50
	for s4 in [-1.0, 1.0]:
		lib.box(g, "祠柱_%d" % int(s4 + 1.0), Vector3(0.08, 1.22, 0.08), d,
			Vector3(jx + s4 * 0.44, jy + 0.61, jz + 0.20))
	# 護符：貼在祠柱上的一張紙
	lib.box(g, "護符", Vector3(0.09, 0.24, 0.012),
		lib.pbr("slice_ofuda", "shoji", 0.30, Color(0.98, 0.96, 0.88)),
		Vector3(jx - 0.44, jy + 0.92, jz + 0.145))
	# 奇怪的告示（村的公告板 —— 上面寫什麼看不清，但它就是有）
	var bx := 15.4
	var bz := -4.6
	var by := height_at(bx, bz)
	for s5 in [-1.0, 1.0]:
		lib.box(g, "高札柱_%d" % int(s5 + 1.0), Vector3(0.09, 1.55, 0.09), d,
			Vector3(bx + s5 * 0.52, by + 0.78, bz))
	lib.box(g, "高札板", Vector3(1.26, 0.72, 0.05),
		lib.pbr("slice_board", "planks", 0.5, Color(0.70, 0.62, 0.50)),
		Vector3(bx, by + 1.18, bz))
	lib.box(g, "高札屋根", Vector3(1.44, 0.06, 0.30), kaw, Vector3(bx, by + 1.60, bz))
	_audit.append("節點：井戶（井桁＋屋根＋釣瓶）・地藏祠（前掛＋護符）・高札")


func _build_planting() -> void:
	var g := lib.add(_root, Node3D.new(), "植栽") as Node3D
	# 牆腳的草與雜草：**只長在人不走的地方**（建物之間的縫、牆角、溝邊）
	var tuft := lib.tuft_mesh(7, 0.30, 0.22, Color(0.16, 0.30, 0.12), Color(0.34, 0.54, 0.22))
	var weed := lib.tuft_mesh(5, 0.44, 0.16, Color(0.20, 0.28, 0.12), Color(0.44, 0.52, 0.24))
	var a: Array[Transform3D] = []
	var b: Array[Transform3D] = []
	var tries := 0
	while (a.size() + b.size()) < 260 and tries < 4000:
		tries += 1
		var x := _rng.randf_range(-HALF + 6.0, HALF - 6.0)
		var z := _rng.randf_range(-24.0, 24.0)
		var m := mask_at(x, z)
		if m.a > 0.25 or m.r > 0.15:            # 踩實的土／石板上不長草
			continue
		var near := false
		for L in LOTS:
			var c := _lot_center(L)
			if absf(x - c.x) < 4.4 and absf(z - c.y) < 4.2:
				near = true
				break
		if near:
			continue
		var s := _rng.randf_range(0.7, 1.3)
		var t := Transform3D(Basis(Vector3.UP, _rng.randf_range(0.0, TAU))
			* Basis.from_scale(Vector3(s, s, s)), Vector3(x, height_at(x, z), z))
		if _rng.randf() < 0.3:
			b.append(t)
		else:
			a.append(t)
	for pair in [["MM_草", tuft, a], ["MM_雜草", weed, b]]:
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = lib.make_multimesh(pair[1], pair[2], [],
			OUT_DIR + "gen/mm_%s.res" % String(pair[0]).trim_prefix("MM_"))
		mmi.material_override = lib.foliage_vc_mat()
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
		lib.add(g, mmi, String(pair[0]))
	# 兩棵樹：一棵在井邊（提供樹蔭與垂直線）、一棵在巷底
	for spec in [[16.2, 4.6, "tree_round_a", 0.9], [-4.2, -13.5, "tree_round_c", 0.72]]:
		var t2 := MeshInstance3D.new()
		t2.mesh = lib.tree_mesh("res://assets/models/%s.glb" % String(spec[2]))
		t2.position = Vector3(float(spec[0]), height_at(float(spec[0]), float(spec[1])),
			float(spec[1]))
		t2.scale = Vector3.ONE * float(spec[3])
		t2.rotation.y = _rng.randf_range(0.0, TAU)
		lib.add(g, t2, "樹_%s" % String(spec[2]))
	_audit.append("植栽：草 %d・雜草 %d・樹 2（只長在沒踩實的地方）" % [a.size(), b.size()])


func _build_people() -> void:
	## 三個村民 —— 驗收問題 5：「放東方角色進去是否自然」。
	## 尺度參考也靠他們：房子好不好看很主觀，但「門比人高多少」是客觀的。
	var g := lib.add(_root, Node3D.new(), "村民") as Node3D
	for spec in [[-6.4, 1.2, "villager_a", 2.1], [15.9, -1.4, "villager_b", -0.7],
			[3.1, 2.6, "villager_c", 1.2]]:
		var x := float(spec[0])
		var z := float(spec[1])
		var v := MeshInstance3D.new()
		v.mesh = lib.prop_mesh("res://assets/models/%s.glb" % String(spec[2]))
		v.position = Vector3(x, height_at(x, z), z)
		v.rotation.y = float(spec[3])
		lib.add(g, v, String(spec[2]))
	_audit.append("村民 3 人（尺度參考 + 驗收問題 5）")


func _build_env() -> void:
	## 簡單自然日光。⚠ 規格明令：不要用 cinematic lighting／霧／DOF 掩蓋問題。
	## 所以這裡**沒有**霧、沒有 glow、沒有 SSAO 以外的後製。
	var e := WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	var pm := ProceduralSkyMaterial.new()
	pm.sky_top_color = Color(0.42, 0.55, 0.76)
	pm.sky_horizon_color = Color(0.72, 0.76, 0.80)
	pm.ground_bottom_color = Color(0.32, 0.32, 0.30)
	pm.ground_horizon_color = Color(0.62, 0.62, 0.58)
	pm.sun_angle_max = 8.0
	sky.sky_material = pm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 3.0
	e.environment = env
	lib.add(_root, e, "WorldEnvironment")
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-48.0), deg_to_rad(-126.0), 0.0)
	sun.light_energy = 1.15
	sun.light_color = Color(1.0, 0.97, 0.92)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	lib.add(_root, sun, "Sun")


func _write_meta() -> void:
	var meta := {
		"id": MAP_ID,
		"note": "PHASE 1.5 vertical slice（art benchmark）。8 棟建築、一條主街、"
			+ "兩條巷、一個井戶節點。獨立於 village，改這裡不影響 169 棟。",
		"playSize": [HALF * 2.0, HALF * 2.0],
		"safe": true,
		"colliders": [],
		"connections": [],
		"portals": [],
	}
	var f := FileAccess.open("res://data/%s.meta.json" % MAP_ID, FileAccess.WRITE)
	f.store_string(JSON.stringify(meta, " ", false))
	f.close()
	print("wrote data/%s.meta.json" % MAP_ID)

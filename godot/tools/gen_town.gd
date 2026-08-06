# 人間之里 街區重設計・參數化產生器（第一階段：寬橋核心區）
#
#   godot --headless --path godot --script tools/gen_town.gd
#
# 分工（開工前定案）：Blender 只做模組（make_town.py → machiya_*.glb /
# bridge_main.glb + data/town_modules.json 尺寸表）；**佈局邏輯全在這裡**，
# 資料驅動、MultiMesh 批次實例 —— 第一步就 MultiMesh，不重蹈稗田邸
# 「單一 mesh 事後拆」的回頭路。
#
# ── 水系優先 ──
# RIVER_SPINE 是整個城鎮的結構脊椎（先定河，街區跟著水走）。這條線是
# **全鎮提案**（村座標，跟 gen_village.gd 同一空間）；本輪只在寬橋核心區
# 蓋出第一個街區群給使用者驗收，其餘街區等驗收後批量。
#
# 取代的舊決策（記錄在 gen_village.gd 的註解裡，使用者 2026-08-05 看過
# 空拍幻想鄉參考後明確推翻）：
#   ・「水道直直的就好不要轉彎」→ 改為蜿蜒河道作為城鎮脊椎
#   ・12m 主路：舊決策「主街 8m、11m 像機場跑道」是對**南北向本通**說的
#     （兩側只有 4~6m 的房子，路寬撐不起來）。新的 12m 軸是**過河的東西向
#     主路**：有 9~10m 的後排町家壓著、有 12m 寬的橋收束，路寬有東西扛。
#     南北本通維持 8m 不動。
#
# 輸出：res://maps/townlab/townlab.tscn（獨立試驗場景，不碰 village.tscn）
#       + data/townlab.instances.json（Blender 端 fallback 預覽用的擺位表）
# 整合進 village.tscn 是批量階段的事 —— 先讓使用者看核心區。
extends SceneTree

const OUT_DIR := "res://maps/townlab/"
const MODULES := "res://data/town_modules.json"
const SEED := 20260805

# ── 全鎮河道提案（村座標：-z=北，跟 gen_village.gd 同空間）──
# 北端出圖處 x≈108（接未來的河畔道→湖，mapRegistry 的 lake connection 鉤子
# 保留）；南端 x≈64 出圖。轉折避開既有地標街區（x=26 那排的東緣在 47，
# 河最貼近時岸線離它 ≥8m）。主橋在 (66,30) —— 12m 東西主路過河處。
const RIVER_SPINE := [
	Vector2(108, -300), Vector2(96, -236), Vector2(74, -168), Vector2(86, -108),
	Vector2(64, -50), Vector2(62, -6), Vector2(66, 30), Vector2(78, 72),
	Vector2(64, 120), Vector2(56, 168), Vector2(72, 224), Vector2(64, 300),
]
const RIVER_HALF := 7.0
const RIVER_DEPTH := 2.5
const BRIDGE_POS := Vector2(66, 30)

# 12m 東西主路（升級版橫町）。南北本通維持 8m（既有決策不動）。
const MAIN_EW_Z := 30.0
const MAIN_EW_W := 12.0

# 核心區試驗場範圍（地形只鋪這一塊）
const LAB_C := Vector2(66, 30)
const LAB_HALF := 64.0

var lib = preload("res://tools/gen_lib.gd").new()
var _root: Node3D
var _mods := {}                # town_modules.json 的模組表
var _batch := {}               # 模組名 → Array[Transform3D]（MultiMesh 批次）
var _audit: Array[String] = []
var _dump := []                # Blender fallback 預覽用


func _init() -> void:
	var f := FileAccess.open(MODULES, FileAccess.READ)
	if f == null:
		push_error("讀不到 %s —— 先跑 make_town.py" % MODULES)
		quit(1)
		return
	_mods = JSON.parse_string(f.get_as_text())["modules"]
	f.close()

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR + "gen"))
	_root = Node3D.new()
	_root.name = "TownLab"
	_root.set_meta("own_colliders", true)   # 不要讓 main.gd 套 village 的舊碰撞
	lib.setup(_root, SEED)

	_build_terrain()
	_build_river()
	_build_bridge()
	_build_blocks()
	_assert_no_overlap()
	_emit_batches()
	_build_env()
	lib.boundary(LAB_HALF + 30.0)

	for line in _audit:
		print(line)

	var packed := PackedScene.new()
	packed.pack(_root)
	var err := ResourceSaver.save(packed, OUT_DIR + "townlab.tscn")
	print("saved townlab.tscn err=", err)
	_write_dump()
	quit()


# ── 河道幾何 ──

func _spline(ctrl: Array, per_seg: int) -> PackedVector2Array:
	## Catmull-Rom（跟 make_hieda.py 的 _spline 同款）——控制點少、曲線滑。
	var out := PackedVector2Array()
	for i in ctrl.size() - 1:
		var p0: Vector2 = ctrl[max(i - 1, 0)]
		var p1: Vector2 = ctrl[i]
		var p2: Vector2 = ctrl[i + 1]
		var p3: Vector2 = ctrl[min(i + 2, ctrl.size() - 1)]
		for k in per_seg:
			var t := float(k) / per_seg
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t
				+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t
				+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t))
	out.append(ctrl[ctrl.size() - 1])
	return out


var _river_pts := PackedVector2Array()

func _river_lab_pts() -> PackedVector2Array:
	## 試驗場範圍內的河段（含一點越界，讓水在圖緣外收尾）
	if _river_pts.is_empty():
		_river_pts = _spline(RIVER_SPINE, 14)
	var out := PackedVector2Array()
	for p in _river_pts:
		if abs(p.x - LAB_C.x) < LAB_HALF + 24.0 and abs(p.y - LAB_C.y) < LAB_HALF + 24.0:
			out.append(p)
	return out


func river_tangent(at: Vector2) -> Vector2:
	## 河道在最近點的切線（單位向量）。街區「對水角度」靠它。
	if _river_pts.is_empty():
		_river_pts = _spline(RIVER_SPINE, 14)
	var bi := 0
	var bd := 1e18
	for i in _river_pts.size():
		var d := _river_pts[i].distance_squared_to(at)
		if d < bd:
			bd = d
			bi = i
	var a := _river_pts[max(bi - 1, 0)]
	var b := _river_pts[min(bi + 1, _river_pts.size() - 1)]
	return (b - a).normalized()


# ── 地形（試驗場小patch：平地 + 河道下切 + 路面遮罩）──

func _height_at(x: float, z: float) -> float:
	var h: float = lib.river_carve(_river_lab_pts(), RIVER_HALF, RIVER_DEPTH, x, z)
	var d: float = lib.poly_dist(_river_lab_pts(), x, z)
	# 下切影響半徑收斂：river_carve 的緩坡拖到 2.2×half=15.4m，房子的基石
	# 會浮在坡上、主路在橋前先陷 0.77m 再爬上橋台。岸外 1.2m 起 2.8m 內
	# 收到 0 —— 岸還有軟肩，但路和街區站在平地上。
	if d > RIVER_HALF + 1.2:
		h *= clampf(1.0 - (d - (RIVER_HALF + 1.2)) / 2.8, 0.0, 1.0)
	# 12m 主路廊道拉平（水道開口除外）：橋的兩端要平接橋台，
	# 不是先下坡再撞上 0.26m 的橋緣。
	if absf(z - MAIN_EW_Z) < 7.5 and d > RIVER_HALF + 0.6:
		h *= clampf((absf(z - MAIN_EW_Z) - 6.0) / 1.5, 0.0, 1.0)
	return h


func _mask_at(x: float, z: float) -> Color:
	var path := 0.0
	# 12m 東西主路
	var dz: float = abs(z - MAIN_EW_Z) - MAIN_EW_W * 0.5
	path = maxf(path, clampf(1.0 - maxf(dz, 0.0) / 0.9, 0.0, 1.0))
	# （南北巷這輪不畫：上一版畫在 x=36/100，正好從 12 棟房子底下穿過 ——
	# 巷子要等批量階段跟街區一起排，不是先畫線再擺房。）
	# 河畔道（沿岸 3.2m —— 街區讓出來的濱水步道）
	var dr: float = lib.poly_dist(_river_lab_pts(), x, z) - (RIVER_HALF + 1.2)
	if dr > 0.0 and dr < 3.2:
		path = maxf(path, 0.7)
	return Color(path, 0.0, 0.0, 0.0)


func _build_terrain() -> void:
	# lib.terrain 自己掛進 root（回傳值只拿來設位置）。
	# 地形以原點建、整塊平移到 LAB_C —— height/mask fn 對應把座標移回世界。
	var t := lib.terrain(OUT_DIR, LAB_HALF, 129,
		func(x: float, z: float) -> float:
			return _height_at(x + LAB_C.x, z + LAB_C.y),
		func(x: float, z: float) -> Color:
			return _mask_at(x + LAB_C.x, z + LAB_C.y))
	t.position = Vector3(LAB_C.x, 0.0, LAB_C.y)


func _build_river() -> void:
	var pts := _river_lab_pts()
	# river_water 自己掛進 root；bank_y_fn 是 (x, z) 兩參數
	lib.river_water(OUT_DIR, pts, RIVER_HALF * 0.86, RIVER_DEPTH * 0.35,
		func(_x: float, _z: float) -> float: return 0.0)
	# 石積護岸：沿線兩側的低擋牆（頂 +0.30、埋到 -1.3）。
	# 參考空拍：市中心段的河是**砌石岸**，不是自然土坡 —— 這是「城鎮裡的河」
	# 跟「野外的河」的分別。
	var g := lib.add(_root, Node3D.new(), "護岸")
	for i in range(0, pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var tan := (b - a)
		var len := tan.length()
		if len < 0.01:
			continue
		tan /= len
		var nrm := Vector2(-tan.y, tan.x)
		for sd in [-1.0, 1.0]:
			var off: Vector2 = nrm * sd * (RIVER_HALF + 0.25)
			var mid: Vector2 = (a + b) * 0.5 + off
			# 橋位讓開（橋台自己接岸）
			if abs(mid.x - BRIDGE_POS.x) < 7.5 and abs(mid.y - BRIDGE_POS.y) < 7.5:
				continue
			var bx := lib.box(g, "岸_%d_%d" % [i, int(sd)],
				Vector3(0.55, 1.6, len + 0.25), lib.flat_mat("岸石", Color(0.42, 0.42, 0.40), 0.95),
				Vector3(mid.x, -0.50, mid.y))
			bx.rotation.y = atan2(tan.x, tan.y)


func _build_bridge() -> void:
	# 12m 半拱木橋。模組沿 Blender x → Godot x：橋面東西走向，正好跨過
	# 在這裡南北流的河。**朝向跟太陽是配過的**：daynight 的影子永遠往 -z
	# 半空擺 ±40°，南側欄杆的鏤空欄影整天都掃在橋面上（規格點）。
	var mesh: Mesh = lib.prop_mesh(String(_mods["bridge_main"]["glb"]))
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = Vector3(BRIDGE_POS.x, 0.02, BRIDGE_POS.y)
	lib.add(_root, mi, "主橋")
	_dump.append(["bridge_main", BRIDGE_POS.x, 0.02, BRIDGE_POS.y, 0.0])
	_audit.append("主橋 @ (%.0f, %.0f)  跨 22m×寬 12m  拱 +1.5  欄杆 1.15（模組值）"
		% [BRIDGE_POS.x, BRIDGE_POS.y])


# ── 複合街區產生器（本輪真正的交付物）──
#
# 參數：
#   frontage  {a: Vector2, b: Vector2}    臨街線（前排沿它擺，法線朝街）
#   rows      [{kinds, setback, jog: [lo, hi]}, {kinds, gap: [lo, hi], ...}]
#             jog = 鄰棟前後錯位範圍（規格 1~2m —— 打破直線）
#   wrap      "L" / "U" / ""              端部轉 90° 包角（打破格狀）
#   river_end true                        靠河那端最後一棟改成對河道切線
#
# 前排沿臨街線排；後排在前排背後 gap 處、橫向錯半個面寬（屋脊互相錯開，
# 天際線才有進退）。鄰棟錯位 jog 由亂數逐棟累進 —— 這是「打破格線」的
# 最小機制：排的方向仍然順著街／河，但沒有兩棟真正對齊。

func _house(kind: String, pos: Vector2, face_dir: Vector2) -> void:
	## face_dir = 正面朝向（朝街的單位向量）。模組正面在 Godot 朝 +z（yaw 0）。
	var yaw := atan2(face_dir.x, face_dir.y)
	var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(pos.x, 0.0, pos.y))
	if not _batch.has(kind):
		_batch[kind] = []
	_batch[kind].append(xf)
	_dump.append([kind, pos.x, 0.0, pos.y, yaw])


func _block(seed_i: int, cfg: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_i
	var a: Vector2 = cfg["frontage"]["a"]
	var b: Vector2 = cfg["frontage"]["b"]
	var along := (b - a).normalized()
	var into: Vector2 = cfg.get("into", Vector2(-along.y, along.x))  # 街的反向＝進深方向
	var face := -into                       # 正面朝街
	var span := a.distance_to(b)
	var rows: Array = cfg["rows"]
	var name: String = cfg.get("name", "block")

	# ── 角落預留 ──
	# 包角棟／河畔棟不是「事後硬塞」：先把端部的地讓出來，前排排到預留線
	# 就停。第一版沒有預留，包角棟全數跟排屋穿插 0.5~6.2m（審查用 OBB
	# 逐對量出來的）—— 位置對不對不能用看的，要留給 _assert_no_overlap()。
	var wrap: String = cfg.get("wrap", "")
	var wrap_kind: String = cfg.get("wrap_kind", "machiya_f_a")
	var reserve_a := 0.0
	var reserve_b := 0.0
	if wrap == "U" or (wrap == "L" and cfg.get("wrap_end", "b") == "a"):
		reserve_a = float(_mods[wrap_kind]["d"]) + 1.6
	if wrap == "U" or (wrap == "L" and cfg.get("wrap_end", "b") == "b"):
		reserve_b = float(_mods[wrap_kind]["d"]) + 1.6
	var river_reserve := 0.0
	if cfg.get("river_end", false):
		# 河畔棟固定吃 b 端的角。牠的**屋身**朝街區內伸（面朝河），
		# 佔掉的是 fd（含出簷進深）—— 用面寬算會少留 ~2.5m，後排尾棟
		# 就撞上來（審查抓到的 1.01m 穿插正是這個）。而且**每一排**都要讓，
		# 不只前排。
		river_reserve = float(_mods[cfg.get("river_kind", "machiya_f_b")]["fd"]) + 2.6
		reserve_b = maxf(reserve_b, river_reserve)

	var front_depth := 0.0
	var row_i := 0
	for row in rows:
		var kinds: Array = row["kinds"]
		var jog: Array = row.get("jog", [1.0, 2.0])
		var base_set: float = row.get("setback", 0.8)
		if row_i > 0:
			base_set = front_depth + rng.randf_range(row["gap"][0], row["gap"][1])
		var lateral: float = row.get("lateral", 0.0)
		var s: float = row.get("start", 0.6) + lateral
		if row_i == 0:
			s += reserve_a                  # 角落讓給包角棟
		var gap_after: int = row.get("gap_after", -1)
		var set_prev := base_set
		var deepest := base_set
		var hn := 0
		while true:
			var kind: String = kinds[(hn + seed_i) % kinds.size()]
			var m: Dictionary = _mods[kind]
			var w: float = m["w"]
			var limit: float = span - 0.4 - (reserve_b if row_i == 0 else river_reserve)
			if s + w > limit:
				break
			# 鄰棟前後錯位：規格 1~2m。第一棟取 base，之後每棟相對前一棟
			# 錯 ±rr(1,2) —— 夾回 [base, base+2.2] 免得整排漂走。
			var setb := base_set
			if hn > 0:
				var d := rng.randf_range(jog[0], jog[1]) * (1.0 if hn % 2 == 1 else -1.0)
				setb = clampf(set_prev + d, base_set, base_set + 2.2)
				_audit.append("  %s 排%d 棟%d 錯位 %.2f m" % [name, row_i, hn, absf(setb - set_prev)])
			set_prev = setb
			var center: Vector2 = a + along * (s + w * 0.5) + into * setb
			_house(kind, center, face)
			_audit.append("%s 排%d 棟%d %s @(%.1f,%.1f) 高 %.2f" %
				[name, row_i, hn, kind, center.x, center.y, m["h"]])
			deepest = maxf(deepest, setb + m["d"] + 1.0)
			# 鄰棟間隔 ≥1.9m：兩側出簷各 0.85，1.7 以下**屋簷互相穿插**、
			# 同模組鄰棟的簷還同高共面（老病）。1.9~3.0 → 簷距 0.2~1.3。
			s += w + rng.randf_range(1.9, 3.0)
			# 看河／看天缺口：指定棟數之後空一格（東南低開區的規格點——
			# 「不只是矮，還要開」。缺口寬 ≈ 一棟小屋 + 餘量）
			if hn == gap_after:
				var gw := rng.randf_range(6.5, 8.0)
				s += gw
				_audit.append("  %s 排%d 在棟%d 後留 %.1fm 視線缺口" % [name, row_i, hn, gw])
			hn += 1
		front_depth = deepest
		row_i += 1

	# 包角（L / ㄇ）：端部一棟轉 90° 佔進預留的角 —— 打破「矩形排排站」。
	# 幾何：正面線貼齊端點外側、屋身伸進預留段；橫向帶 [setback, setback+w]
	# 與後排（setback+d+gap 起）在進深軸上不相交 —— 不重疊由建構保證，
	# 再由 _assert_no_overlap() 複核。
	if wrap != "":
		var ends: Array = []
		if wrap == "U":
			ends = [[a, -1.0], [b, 1.0]]
		else:
			ends = [[b, 1.0]] if cfg.get("wrap_end", "b") == "b" else [[a, -1.0]]
		for epair in ends:
			var e: Vector2 = epair[0]
			var sgn: float = epair[1]
			if sgn > 0 and cfg.get("river_end", false):
				continue                    # b 端讓給河畔棟（一個角只放一棟）
			var m: Dictionary = _mods[wrap_kind]
			var setb0: float = rows[0].get("setback", 0.8)
			var pos: Vector2 = e + along * sgn * 0.3 + into * (setb0 + float(m["w"]) * 0.5)
			_house(wrap_kind, pos, along * sgn)
			_audit.append("%s 包角(%s) %s @(%.1f,%.1f) 面朝%s" %
				[name, wrap, wrap_kind, pos.x, pos.y, "端外" if sgn > 0 else "端外(反)"])

	# 靠河端：一棟正對**河畔道**的（街區跟著水彎 —— 水系優先的具體形）。
	# ⚠ 從**河道最近點**起算，不是從錨點起算 —— 第一版寫 anchor+offset，
	# 錨點本身離河 4.7~9.1m，房子被推到離河 16~21m 還壓進後排。
	if cfg.get("river_end", false):
		var kind: String = cfg.get("river_kind", "machiya_f_b")
		var e2: Vector2 = cfg["river_anchor"]
		var rp := _nearest_river_pt(e2)
		var t := river_tangent(rp)
		var n := Vector2(-t.y, t.x)
		if n.dot(e2 - rp) < 0.0:
			n = -n                          # 法線朝街區那側（離河）
		# 正面線在 岸(7)+護岸帶(1.2)+河畔道(3.2)+0.5 ≈ 11.9m 處，面朝河
		var pos2: Vector2 = rp + n * (RIVER_HALF + 4.9)
		_house(kind, pos2, -n)
		_audit.append("%s 河畔棟 %s @(%.1f,%.1f) 正面離河道中心 %.1fm、對切線 %.1f°" %
			[name, kind, pos2.x, pos2.y, pos2.distance_to(rp), rad_to_deg(atan2(t.x, t.y))])


func _nearest_river_pt(at: Vector2) -> Vector2:
	if _river_pts.is_empty():
		_river_pts = _spline(RIVER_SPINE, 14)
	var best := _river_pts[0]
	var bd := 1e18
	for p in _river_pts:
		var d := p.distance_squared_to(at)
		if d < bd:
			bd = d
			best = p
	return best


func _build_blocks() -> void:
	var rd := MAIN_EW_W * 0.5               # 主路半寬 6
	# ── 橋西（過橋前）：標準階梯天際線 —— 前排 4.5~5.5 臨街、後排 9~10 在後 ──
	_block(101, {
		"name": "西北",
		"frontage": {"a": Vector2(10, MAIN_EW_Z - rd - 1.2), "b": Vector2(52, MAIN_EW_Z - rd - 1.2)},
		"into": Vector2(0, -1),
		"rows": [
			{"kinds": ["machiya_f_a", "machiya_f_b"], "setback": 0.8},
			{"kinds": ["machiya_b_a", "machiya_b_b"], "gap": [2.6, 4.0], "lateral": 3.8},
		],
		"wrap": "L", "wrap_end": "a",
		"river_end": true, "river_anchor": Vector2(56, 12), "river_kind": "machiya_f_a",
	})
	_block(102, {
		"name": "西南",
		"frontage": {"a": Vector2(10, MAIN_EW_Z + rd + 1.2), "b": Vector2(50, MAIN_EW_Z + rd + 1.2)},
		"into": Vector2(0, 1),
		"rows": [
			{"kinds": ["machiya_f_b", "machiya_f_a"], "setback": 0.8},
			{"kinds": ["machiya_b_b", "machiya_b_a"], "gap": [2.8, 4.2], "lateral": 4.6},
		],
		"wrap": "U",
		"river_end": true, "river_anchor": Vector2(64, 52), "river_kind": "machiya_f_b",
	})
	# ── 橋東：過橋後的不對稱（規格點）──
	# 左（北）＝高壓：**後排模組直接臨街**，9~10m 的量體貼著路肩壓下來
	_block(103, {
		"name": "東北・高壓",
		"frontage": {"a": Vector2(82, MAIN_EW_Z - rd - 0.6), "b": Vector2(126, MAIN_EW_Z - rd - 0.6)},
		"into": Vector2(0, -1),
		"rows": [
			{"kinds": ["machiya_b_a", "machiya_b_b"], "setback": 0.4, "jog": [1.0, 1.8]},
			{"kinds": ["machiya_f_a", "machiya_f_b"], "gap": [2.6, 3.6], "lateral": 4.2},
		],
		"wrap": "L",
	})
	# 右（南）＝低開：前排／村緣模組、退距拉大、中段留一個看河的缺口
	_block(104, {
		"name": "東南・低開",
		"frontage": {"a": Vector2(84, MAIN_EW_Z + rd + 2.6), "b": Vector2(126, MAIN_EW_Z + rd + 2.6)},
		"into": Vector2(0, 1),
		"rows": [
			{"kinds": ["machiya_e_a", "machiya_f_a", "machiya_e_a"], "setback": 2.2, "jog": [1.2, 2.0], "gap_after": 1},
		],
	})
	# 東北牆面 z = 23.4 - 0.4(退距)，路肩 z = 24 → 實際牆到路肩 1.0m
	_audit.append("不對稱驗證：東北臨街=後排模組(9.4/9.9m 牆離路肩 1.0m)；"
		+ "東南臨街=村緣/前排(3.5/4.8m 退 2.2m+ 且留視線缺口)")


func _assert_no_overlap() -> void:
	## 逐對 OBB（SAT）檢查所有町家的**含出簷 footprint** —— 位置對不對
	## 不能用看的。這一輪的兩個 blocker（包角棟、河畔棟穿插）都是審查
	## 這樣量出來的，所以把檢查放進產生器本身，之後批量也一直有效。
	var rects: Array = []
	for e in _dump:
		if not String(e[0]).begins_with("machiya"):
			continue
		var m: Dictionary = _mods[e[0]]
		var yaw: float = e[4]
		var fwd := Vector2(sin(yaw), cos(yaw))      # 正面朝向（xz 平面）
		var side := Vector2(fwd.y, -fwd.x)
		var hw: float = float(m["fw"]) * 0.5
		var fd: float = float(m["fd"])
		# 模組原點在正面中心，屋身往背面延伸：中心 = 原點 - fwd*(fd/2 - 0.85)
		var c := Vector2(e[1], e[3]) - fwd * (fd * 0.5 - 0.85)
		rects.append([c, side, fwd, hw, fd * 0.5, e[0]])
	var bad := 0
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			var pen := _obb_pen(rects[i], rects[j])
			if pen > 0.05:
				bad += 1
				push_error("重疊：%s#%d × %s#%d 穿插 %.2fm" %
					[rects[i][5], i, rects[j][5], j, pen])
	if bad == 0:
		_audit.append("重疊檢查：%d 棟兩兩比對（含出簷）—— 0 穿插 ✓" % rects.size())
	else:
		_audit.append("⚠ 重疊檢查：%d 對穿插 —— 佈局有 bug，看上面的 push_error" % bad)


func _obb_pen(ra: Array, rb: Array) -> float:
	## SAT：回傳最小穿透深度（<=0 = 分離）。軸取兩個矩形的四個邊法線。
	var pen := 1e18
	for r in [ra, rb]:
		for k in [1, 2]:
			var axis: Vector2 = r[k]
			var ca: float = Vector2(ra[0]).dot(axis)
			var cb: float = Vector2(rb[0]).dot(axis)
			var ea: float = absf(Vector2(ra[1]).dot(axis)) * ra[3] + absf(Vector2(ra[2]).dot(axis)) * ra[4]
			var eb: float = absf(Vector2(rb[1]).dot(axis)) * rb[3] + absf(Vector2(rb[2]).dot(axis)) * rb[4]
			var ov := ea + eb - absf(ca - cb)
			if ov <= 0.0:
				return 0.0
			pen = minf(pen, ov)
	return pen


func _emit_batches() -> void:
	var g := lib.add(_root, Node3D.new(), "町家")
	var total := 0
	var names := _batch.keys()
	names.sort()
	for kind in names:
		var list: Array = _batch[kind]
		var mesh: Mesh = lib.prop_mesh(String(_mods[kind]["glb"]))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = lib.make_multimesh(mesh, list, [],
			OUT_DIR + "gen/mm_%s.res" % kind)
		lib.add(g, mmi, "MM_%s" % kind)
		total += list.size()
	_audit.append("町家 %d 棟 / %d 種模組（%d draw call）" % [total, names.size(), names.size()])


func _build_env() -> void:
	# 跟 gen_kourindou 同一組確認過的環境參數（SDFGI 關、ACES、微霧）
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.sky = sky
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.82
	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.glow_hdr_threshold = 1.25
	env.ssao_enabled = true
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.55
	env.fog_enabled = true
	env.fog_density = 0.0016
	var we := WorldEnvironment.new()
	we.environment = env
	lib.add(_root, we, "WorldEnvironment")


func _write_dump() -> void:
	# Blender 端 fallback 預覽用（座標已是 Godot 空間；yaw 繞 +y）
	var out := {"note": "townlab 擺位表（gen_town.gd 產出，僅供預覽比對）",
		"river": [], "instances": _dump}
	for p in _river_lab_pts():
		out["river"].append([snappedf(p.x, 0.01), snappedf(p.y, 0.01)])
	var f := FileAccess.open("res://data/townlab.instances.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out, " "))
	f.close()
	print("wrote data/townlab.instances.json（%d 實例）" % _dump.size())

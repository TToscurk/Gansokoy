# 地圖體檢 —— 自動抓幾何錯誤（ADR-003）
#
#   godot --headless --path godot --script tools/check_map.gd -- village
#   godot --headless --path godot --script tools/check_map.gd -- all
#
# 為什麼要有這支：使用者回報的 bug 裡，有五個是「用眼睛看才發現」的幾何
# 錯誤 —— 建築離地、樹穿建築、物件壓街、水面在河床下、生物錯位。
# 這些全部可以自動檢查。產生器跑完就接這支，有紅字就不算完成。
#
# 做法：載入 .tscn，抓 Terrain 的 mesh 當高度場（不重算 height_at ——
# 體檢要驗「場景實際長怎樣」，不是驗「產生器以為長怎樣」，否則
# 產生器的 bug 會同時騙過自己與體檢）。
extends SceneTree

const TOL_FLOAT := 0.55        # 建物底面允許離地多少
const TOL_SINK := 2.5          # 允許陷進地裡多少（基石本來就會埋）
const TOL_WATER := 0.15        # 水面允許低於地面多少
const WATER_BAD_FRAC := 0.06   # 超過這個比例的水面點被埋才算問題（邊緣點會壓到岸）

## 建物「該貼地」的構件命名。屋頂／簷／瓦不列入 —— 它們本來就在半空中，
## 拿它們量離地會得到 200 多筆假訊息。
const GROUND_PARTS := ["基石", "屋身", "塀", "基壇", "土台", "石垣"]
## 明確排除：塀瓦 含「塀」但它是牆頂的蓋瓦，本來就懸在半空
const NOT_GROUND := ["瓦", "屋根", "簷", "庇"]

var _cell := 4.0
var _gmin := {}                # Vector2i -> 該格地形最低點
var _gmax := {}                # Vector2i -> 該格地形最高點
var _issues := []
var _parts := []       # 個別貼地構件（跨水檢查用）

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var maps: Array = []
	if args.is_empty() or args[0] == "all":
		maps = ["village", "trail", "kourindou"]
	else:
		maps = [args[0]]
	var total := 0
	for m in maps:
		total += _check(String(m))
	print("\n══ 體檢完成：%d 個問題 ══" % total)
	quit(1 if total > 0 else 0)

func _check(map_id: String) -> int:
	_issues.clear()
	_gmin.clear()
	_gmax.clear()
	_parts.clear()
	var path := "res://maps/%s/%s.tscn" % [map_id, map_id]
	if not ResourceLoader.exists(path):
		print("[%s] 沒有原生場景，跳過（還在用 blockout 底稿）" % map_id)
		return 0
	print("\n──── 體檢：%s ────" % map_id)
	var packed: PackedScene = load(path)
	var root := packed.instantiate()

	if not _build_height_field(root):
		print("  ✗ 找不到 Terrain 的 mesh，無法體檢")
		root.free()
		return 1

	var buildings: Array = []      # [{aabb, name}] 一棟 = 一個群組，不是一片牆
	var scatters: Array = []       # MultiMeshInstance3D
	var waters: Array = []
	_collect(root, buildings, scatters, waters)
	print("  掃到 %d 棟建物、%d 個構件、%d 組散佈、%d 片水面" % [buildings.size(), _parts.size(), scatters.size(), waters.size()])

	_check_floating(buildings)
	_check_building_overlap(buildings)
	_check_scatter_overlap(scatters, buildings)
	_check_water(waters)
	_check_water_on_road(waters, root)
	_check_props_grounded(root)
	_check_building_over_water(_parts, waters)
	_check_fauna(root, waters)

	for s in _issues:
		print("  ✗ ", s)
	if _issues.is_empty():
		print("  ✓ 沒有發現幾何問題")
	root.free()
	return _issues.size()

## 世界矩陣 —— 自己往上乘。
## 不能用 global_transform：這支是 SceneTree script，`_init` 執行時 root
## 視窗還沒進樹，instantiate 出來的節點永遠 is_inside_tree() == false，
## global_transform 會靜靜回傳單位矩陣 → 所有 AABB 塌到原點 →
## 體檢報「2600 棵樹全長在同一棟建物裡」這種假訊息。
func _world_xf(n: Node) -> Transform3D:
	var t := Transform3D()
	var cur: Node = n
	while cur != null and cur is Node3D:
		t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t

## 從 Terrain 的 mesh 建高度場（每格記最低與最高）。
## 兩個都要：建物要跟「footprint 最低點」比（產生器就是這樣擺的），
## 水面要跟「河床最低點」比（拿最高點會量到岸）。
func _build_height_field(root: Node) -> bool:
	var terr := root.find_child("Terrain", true, false)
	if terr == null or not (terr is MeshInstance3D):
		return false
	var mesh: Mesh = (terr as MeshInstance3D).mesh
	if mesh == null or mesh.get_surface_count() == 0:
		return false
	var arr := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var txf := _world_xf(terr)
	for v in verts:
		var w: Vector3 = txf * v
		var c := Vector2i(int(floor(w.x / _cell)), int(floor(w.z / _cell)))
		if not _gmin.has(c):
			_gmin[c] = w.y
			_gmax[c] = w.y
		else:
			if _gmin[c] > w.y:
				_gmin[c] = w.y
			if _gmax[c] < w.y:
				_gmax[c] = w.y
	return _gmin.size() > 0

## 一塊水平範圍內的「地面基準高度」。
## 取第 15 百分位而不是絕對最低點：大院子裡可能有池塘或水溝，
## 一格池底就會讓整棟宅子被誤判成離地 1.7m。
## 不外擴取樣範圍 —— 格子本身就有 4m 寬，再 padding 會把旁邊的斜坡算進來。
func _ground_min_box(x0: float, z0: float, x1: float, z1: float) -> float:
	var vals: Array[float] = []
	for i in range(int(floor(x0 / _cell)), int(floor(x1 / _cell)) + 1):
		for j in range(int(floor(z0 / _cell)), int(floor(z1 / _cell)) + 1):
			var c := Vector2i(i, j)
			if _gmin.has(c):
				vals.append(_gmin[c])
	if vals.is_empty():
		return -INF
	vals.sort()
	return vals[mini(int(float(vals.size()) * 0.15), vals.size() - 1)]

## 單點地形最低點（水面用：要跟河床比，不是跟岸比）
func _ground_min_at(x: float, z: float) -> float:
	var c := Vector2i(int(floor(x / _cell)), int(floor(z / _cell)))
	return _gmin[c] if _gmin.has(c) else -INF

func _is_ground_part(nm: String) -> bool:
	for bad in NOT_GROUND:
		if nm.contains(bad):
			return false
	for good in GROUND_PARTS:
		if nm.contains(good):
			return true
	return false

## 一棟建物 = 一個群組節點（長屋_0 / 塀_2_1 / 蔵）。
## v1 把每片 mesh 當一棟，於是「牆頂蓋瓦離地 1.6m」被報成 227 筆離地。
func _collect(n: Node, buildings: Array, scatters: Array, waters: Array) -> void:
	if n is MultiMeshInstance3D:
		var mn := String(n.name)
		# 護岸／堤是地景，跟群組分支的豁免同一條規則
		if mn.contains("護岸") or mn.contains("堤"):
			return
		# ⚠ MM_machiya_* 是**建物**不是散佈物。以前一律丟進 scatters →
		# 人間之里的 169 棟町家全部隱形，buildings 為空時「建物互卡」與
		# 「建物跨水」直接 return —— 體檢綠燈但什麼都沒驗。
		# 逐實例解 buffer（不能用 get_instance_transform：headless 的
		# dummy 渲染器一律回單位矩陣，本檔下面的散佈檢查踩過同一個坑）。
		if mn.begins_with("MM_machiya"):
			_collect_mm_buildings(n, buildings)
			return
		scatters.append(n)
		return
	if n is MeshInstance3D:
		var mat = (n as MeshInstance3D).material_override
		if mat is ShaderMaterial and (mat as ShaderMaterial).shader != null \
				and String((mat as ShaderMaterial).shader.resource_path).contains("water"):
			waters.append(n)
		return
	# 這個節點是不是一棟建物的群組？看它有沒有直接掛著貼地構件
	var box := AABB()
	var got := false
	for c in n.get_children():
		if c is MeshInstance3D and _is_ground_part(String(c.name)):
			var wb: AABB = _world_xf(c) * (c as MeshInstance3D).get_aabb()
			box = wb if not got else box.merge(wb)
			got = true
	# 護岸／堤是**地景**不是建物。加了「石垣」當貼地構件之後，
	# 水路護岸整條被當成一棟建物，岸邊的荷與蘆葦就全被判成「長在建物裡」。
	var is_terrainish := String(n.name).contains("護岸") or String(n.name).contains("堤")
	if got and not is_terrainish:
		buildings.append({ "name": _path_of(n), "aabb": box })
		# 個別構件也留一份：跨水檢查要**逐片牆**比。
		# 拿整棟的外框去比，稗田邸院子裡的庭池會被誤報成「牆擋住水」。
		for c2 in n.get_children():
			if c2 is MeshInstance3D and _is_ground_part(String(c2.name)):
				_parts.append({
					"name": "%s/%s" % [_path_of(n), c2.name],
					"aabb": _world_xf(c2) * (c2 as MeshInstance3D).get_aabb(),
				})
	for c in n.get_children():
		_collect(c, buildings, scatters, waters)

## MultiMesh 町家 → 逐實例建物。
## 建物範圍用**牆身 footprint**（w×d，不含出簷）—— 出簷本來就允許互相
## 探出去，「建物互卡」與「跨水」都該量牆。模組尺寸讀 town_modules.json
## （實測自 glb 的那份）；實例 transform 讀場景的 buffer —— 被驗的是場景。
var _mods_cache = null

func _collect_mm_buildings(mmi: MultiMeshInstance3D, buildings: Array) -> void:
	if _mods_cache == null:
		var f := FileAccess.open("res://data/town_modules.json", FileAccess.READ)
		_mods_cache = JSON.parse_string(f.get_as_text())["modules"] if f else {}
		if f:
			f.close()
	var kind := String(mmi.name).trim_prefix("MM_")
	var mm: MultiMesh = mmi.multimesh
	if mm == null or mm.instance_count == 0:
		return
	var buf := mm.buffer
	var stride := 16 if mm.use_colors else 12
	if buf.size() < mm.instance_count * stride:
		_issues.append("%s 的 MultiMesh buffer 長度不對" % mmi.name)
		return
	# 牆身局部箱（Godot 局部：正面朝 +z、原點在正面地面中心）
	var md: Dictionary = _mods_cache.get(kind, {})
	var w: float = md.get("w", 8.0)
	var d: float = md.get("d", 8.0)
	var h: float = md.get("h", 5.0)
	var corners_l := [
		Vector3(-w / 2, 0, -d), Vector3(w / 2, 0, -d),
		Vector3(-w / 2, 0, 0), Vector3(w / 2, 0, 0),
		Vector3(-w / 2, h, -d), Vector3(w / 2, h, 0),
	]
	var pxf := _world_xf(mmi)
	for i in mm.instance_count:
		var b := i * stride
		var t := Transform3D(
			Vector3(buf[b + 0], buf[b + 4], buf[b + 8]),
			Vector3(buf[b + 1], buf[b + 5], buf[b + 9]),
			Vector3(buf[b + 2], buf[b + 6], buf[b + 10]),
			Vector3(buf[b + 3], buf[b + 7], buf[b + 11]))
		var xf := pxf * t
		var box := AABB(xf * corners_l[0], Vector3.ZERO)
		for ci in range(1, corners_l.size()):
			box = box.expand(xf * corners_l[ci])
		# 斜排的建物（河畔列 yaw −112°）用 AABB 會外擴出假面積 ——
		# 兩棟實際沒碰到的町家被報「互卡 4.4㎡」。多存一份 2D OBB，
		# 互卡與點在建物內的判定優先用它。
		var c3: Vector3 = xf * Vector3(0.0, 0.0, -d / 2)
		var entry := { "name": "%s#%d" % [kind, i], "aabb": box, "obb": {
			"c": Vector2(c3.x, c3.z),
			"ax": Vector2(xf.basis.x.x, xf.basis.x.z).normalized(),
			"az": Vector2(xf.basis.z.x, xf.basis.z.z).normalized(),
			"hx": w / 2, "hz": d / 2 } }
		buildings.append(entry)
		_parts.append(entry)


## 建物的 2D OBB —— 有存 obb（MultiMesh 實例）就用，沒有的（群組建物，
## 都是正交擺放）拿 AABB 當軸對齊 OBB。
func _obb_of_entry(b: Dictionary) -> Dictionary:
	if b.has("obb"):
		return b.obb
	var box: AABB = b.aabb
	return { "c": Vector2(box.position.x + box.size.x / 2, box.position.z + box.size.z / 2),
		"ax": Vector2(1, 0), "az": Vector2(0, 1),
		"hx": box.size.x / 2, "hz": box.size.z / 2 }

## SAT：兩個 2D OBB 的穿深（0 = 沒碰到）
func _obb_pen(a: Dictionary, b: Dictionary) -> float:
	var dv: Vector2 = b.c - a.c
	var pen := INF
	for ax in [a.ax, a.az, b.ax, b.az]:
		var ra: float = a.hx * absf((ax as Vector2).dot(a.ax)) + a.hz * absf((ax as Vector2).dot(a.az))
		var rb: float = b.hx * absf((ax as Vector2).dot(b.ax)) + b.hz * absf((ax as Vector2).dot(b.az))
		var p: float = ra + rb - absf(dv.dot(ax))
		if p <= 0.0:
			return 0.0
		pen = minf(pen, p)
	return pen

## 點在建物的水平範圍內？呼叫端已用 AABB 粗篩過，這裡只補斜排建物的精判
func _pt_in_entry(b: Dictionary, x: float, z: float) -> bool:
	if not b.has("obb"):
		return true
	var o: Dictionary = b.obb
	var dv := Vector2(x, z) - (o.c as Vector2)
	return absf(dv.dot(o.ax)) < o.hx and absf(dv.dot(o.az)) < o.hz

func _path_of(n: Node) -> String:
	var parts := [String(n.name)]
	var p := n.get_parent()
	var depth := 0
	while p != null and depth < 2:
		parts.push_front(String(p.name))
		p = p.get_parent()
		depth += 1
	return "/".join(parts)

## 建物離地 / 陷太深
func _check_floating(buildings: Array) -> void:
	var floats := 0
	var sinks := 0
	var worst_f := 0.0
	var worst_s := 0.0
	for b in buildings:
		var box: AABB = b.aabb
		var c := box.get_center()
		# 跟 footprint 的最低點比 —— 產生器就是把建物擺在最低點、
		# 基石往下加深高差。拿中心點的高度比會在斜坡上全部誤判。
		var g := _ground_min_box(box.position.x, box.position.z,
			box.position.x + box.size.x, box.position.z + box.size.z)
		if g == -INF:
			continue
		var gap := box.position.y - g
		if gap > TOL_FLOAT:
			floats += 1
			worst_f = maxf(worst_f, gap)
			if floats <= 6:
				_issues.append("建物離地 %.2fm：%s @ (%.0f, %.0f)" % [gap, b.name, c.x, c.z])
		elif gap < -TOL_SINK:
			sinks += 1
			worst_s = maxf(worst_s, -gap)
			if sinks <= 4:
				_issues.append("建物陷入地面 %.2fm：%s @ (%.0f, %.0f)" % [-gap, b.name, c.x, c.z])
	if floats > 6:
		_issues.append("…另有 %d 棟建物離地（最嚴重 %.2fm）" % [floats - 6, worst_f])
	if sinks > 4:
		_issues.append("…另有 %d 棟建物陷入地面（最嚴重 %.2fm）" % [sinks - 4, worst_s])

## 建物互相卡住 —— 使用者要求：「建築物卡住其他建築」也要算進體檢。
## 只比貼地構件（基石／屋身／塀）的水平範圍；屋簷本來就會互相探出去。
func _check_building_overlap(buildings: Array) -> void:
	var grid := {}
	var hits := 0
	var worst := 0.0
	for i in buildings.size():
		var box: AABB = buildings[i].aabb
		var keys: Array[Vector2i] = []
		for ii in range(int(floor(box.position.x / 12.0)), int(floor((box.position.x + box.size.x) / 12.0)) + 1):
			for jj in range(int(floor(box.position.z / 12.0)), int(floor((box.position.z + box.size.z) / 12.0)) + 1):
				keys.append(Vector2i(ii, jj))
		var seen := {}
		for k in keys:
			if not grid.has(k):
				grid[k] = []
			for j in grid[k]:
				if seen.has(j):
					continue
				seen[j] = true
				var ob: AABB = buildings[j].aabb
				# 水平重疊面積（只看 XZ）
				var ox := minf(box.position.x + box.size.x, ob.position.x + ob.size.x) - maxf(box.position.x, ob.position.x)
				var oz := minf(box.position.z + box.size.z, ob.position.z + ob.size.z) - maxf(box.position.z, ob.position.z)
				if ox <= 0.35 or oz <= 0.35:
					continue
				# 上下疊在一起才算「卡住」；差 3m 以上視為不同層（例：橋跨過牆）
				if absf(box.position.y - ob.position.y) > 3.0:
					continue
				# 有一方是斜排建物（MultiMesh 實例）→ AABB 是外擴的假框，
				# 改用 OBB SAT 精判；兩方都正交才走原本的面積判定。
				if buildings[i].has("obb") or buildings[j].has("obb"):
					var pen := _obb_pen(_obb_of_entry(buildings[i]), _obb_of_entry(buildings[j]))
					if pen <= 0.35:
						continue
					hits += 1
					worst = maxf(worst, pen)
					if hits <= 5:
						_issues.append("建物互相卡住（穿深 %.2fm）：%s ↔ %s @ (%.0f, %.0f)"
							% [pen, buildings[i].name, buildings[j].name,
								box.get_center().x, box.get_center().z])
					continue
				var area := ox * oz
				if area < 1.2:
					continue
				hits += 1
				worst = maxf(worst, area)
				if hits <= 5:
					_issues.append("建物互相卡住 %.1f㎡：%s ↔ %s @ (%.0f, %.0f)"
						% [area, buildings[i].name, buildings[j].name,
							box.get_center().x, box.get_center().z])
		for k2 in keys:
			grid[k2].append(i)
	if hits > 5:
		_issues.append("…另有 %d 組建物互相卡住（最嚴重 %.1f）" % [hits - 5, worst])

## 散佈物（樹、草、岩石）跟建物重疊 —— 「樹長在建築裡」
func _check_scatter_overlap(scatters: Array, buildings: Array) -> void:
	if buildings.is_empty():
		return
	# 建物用空間索引，否則 2600 棵樹 × 上千棟是 O(n²)
	var bgrid := {}
	for i in buildings.size():
		var box: AABB = buildings[i].aabb
		for ii in range(int(floor(box.position.x / 16.0)), int(floor((box.position.x + box.size.x) / 16.0)) + 1):
			for jj in range(int(floor(box.position.z / 16.0)), int(floor((box.position.z + box.size.z) / 16.0)) + 1):
				var k := Vector2i(ii, jj)
				if not bgrid.has(k):
					bgrid[k] = []
				bgrid[k].append(i)

	for mmi in scatters:
		var nm := String(mmi.name)
		# 草與睡蓮貼地，穿模不影響觀感；只驗有體積的（樹、岩石）
		# 睡蓮／蘆葦在水上，不會跟建物打架；稻米在田裡。其餘（含草）都要驗 ——
		# 使用者：「不要有東西擋住或放在同一層」，草從屋內長出來一樣詭異。
		if nm.contains("睡蓮") or nm.contains("Rice") or nm.contains("Reed"):
			continue
		var mm: MultiMesh = (mmi as MultiMeshInstance3D).multimesh
		if mm == null or mm.instance_count == 0:
			continue
		var xf: Transform3D = _world_xf(mmi)
		# ⚠ 不能用 mm.get_instance_transform()：--headless 走的是 dummy 渲染器，
		# MultiMesh 的 transform 存在 RenderingServer 那邊，讀回來一律是單位矩陣。
		# 這支體檢因此**默默地綠燈了好幾個版本** —— 所有實例都被當成在原點，
		# 而原點剛好沒有建物，所以「沒發現問題」。直接解 buffer 才是真資料。
		var buf := mm.buffer
		var stride := 16 if mm.use_colors else 12
		if buf.size() < mm.instance_count * stride:
			_issues.append("%s 的 MultiMesh buffer 長度不對，跳過檢查" % nm)
			continue
		var hit := 0
		var first := ""
		for i in mm.instance_count:
			var b := i * stride
			var o: Vector3 = xf * Vector3(buf[b + 3], buf[b + 7], buf[b + 11])
			var k := Vector2i(int(floor(o.x / 16.0)), int(floor(o.z / 16.0)))
			if not bgrid.has(k):
				continue
			for bi in bgrid[k]:
				var box: AABB = buildings[bi].aabb
				# 只比水平範圍：樹幹落在建物平面內就是穿模
				if o.x > box.position.x and o.x < box.position.x + box.size.x \
						and o.z > box.position.z and o.z < box.position.z + box.size.z \
						and _pt_in_entry(buildings[bi], o.x, o.z):
					hit += 1
					if hit == 1:
						first = "例：(%.0f, %.0f) ← %s" % [o.x, o.z, buildings[bi].name]
					break
		if hit > 0:
			_issues.append("%s 有 %d 個實例長在建物裡，%s" % [nm, hit, first])

## 生物錯位 —— 這支檔頭從第一版就寫著要驗，但**一直沒有實作**。
## 而這正是舊圖出過的 bug：v8 只寫 meta、位置留給執行期算，編輯器不跑
## _process，九隻鴨全部疊在世界原點（＝本通正中央），使用者回報「鴨子在路上」。
## 存檔位置是唯一能被靜態驗的東西，所以就驗它：
##   ・鴨（swim_kind 0）要**浮在水面上**（±0.35m）
##   ・鯉（swim_kind 1）要在水面**以下**（0.05~1.2m）
##   ・鷺鷥要站在水面**以上**（不能泡在水裡），而且要靠得到水（30m 內）
const FAUNA_XY_TOL := 3.0      # 找水面時允許的水平誤差（水面是有限寬的帶狀網格）

func _check_fauna(root: Node, waters: Array) -> void:
	var beasts := []
	_collect_fauna(root, beasts)
	if beasts.is_empty():
		return
	# 水面高度場：把所有水面網格的頂點灑進 2m 的格子裡
	var wgrid := {}
	for w in waters:
		var mi := w as MeshInstance3D
		if mi.mesh == null or mi.mesh.get_surface_count() == 0:
			continue
		var verts: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var xf := _world_xf(mi)
		for i in verts.size():
			var p: Vector3 = xf * verts[i]
			var c := Vector2i(int(floor(p.x / 2.0)), int(floor(p.z / 2.0)))
			if not wgrid.has(c) or p.y > wgrid[c]:
				wgrid[c] = p.y
	var water_at := func(x: float, z: float, rad: int) -> Variant:
		var best = null
		var c0 := Vector2i(int(floor(x / 2.0)), int(floor(z / 2.0)))
		for di in range(-rad, rad + 1):
			for dj in range(-rad, rad + 1):
				var c := Vector2i(c0.x + di, c0.y + dj)
				if wgrid.has(c) and (best == null or float(wgrid[c]) > float(best)):
					best = wgrid[c]
		return best
	var bad_swim := 0
	var bad_heron := 0
	var worst := ""
	for b in beasts:
		var n: Node3D = b[0]
		var kind: int = b[1]
		var p: Vector3 = _world_xf(n).origin
		var wy = water_at.call(p.x, p.z, int(ceil(FAUNA_XY_TOL / 2.0)))
		if wy == null:
			# 完全找不到水面 —— 這隻不在任何水體上（舊 bug 的樣子）
			if kind == 2:
				continue                       # 鷺鷥可以站在離水面格子稍遠的岸上
			bad_swim += 1
			if worst == "":
				worst = "%s 附近 %.0fm 內沒有水面 @ (%.0f, %.0f)" % [n.name, FAUNA_XY_TOL, p.x, p.z]
			continue
		var d: float = p.y - float(wy)
		match kind:
			0:                                  # 鴨：浮在水面
				if absf(d) > 0.35:
					bad_swim += 1
					if worst == "":
						worst = "%s 離水面 %+.2fm @ (%.0f, %.0f)" % [n.name, d, p.x, p.z]
			1:                                  # 鯉：水面下
				if d > -0.05 or d < -1.2:
					bad_swim += 1
					if worst == "":
						worst = "%s 離水面 %+.2fm（該在水下 0.05~1.2m）@ (%.0f, %.0f)" % [n.name, d, p.x, p.z]
			2:                                  # 鷺鷥：站在水面以上
				if d < -0.05:
					bad_heron += 1
					if worst == "":
						worst = "%s 泡在水裡 %.2fm @ (%.0f, %.0f)" % [n.name, -d, p.x, p.z]
	if bad_swim > 0:
		_issues.append("水生生物位置錯誤 %d 隻（%s）" % [bad_swim, worst])
	if bad_heron > 0:
		_issues.append("鷺鷥站在水裡 %d 隻（%s）" % [bad_heron, worst])

func _collect_fauna(n: Node, out: Array) -> void:
	if n is Node3D:
		if n.has_meta("swim_kind"):
			out.append([n, int(n.get_meta("swim_kind"))])
		elif String(n.name).begins_with("鷺鷥"):
			out.append([n, 2])
	for c in n.get_children():
		_collect_fauna(c, out)

## 水體溢到平地／路面 —— 使用者回報「池塘在路上」。
##
## 判定方式踩過一次坑：一開始拿「周圍地面的**中位數**」比，結果碗狀的池塘
## 全部被報 —— 碗底比水面低是正常的，水面當然高過中位數。
## 正解是比**岸緣**（周圍地形的 95 百分位）：水躺在窪地裡時一定低於岸緣，
## 只有鋪到平地上時才會超過。
func _check_water_on_road(waters: Array, _root: Node) -> void:
	for w in waters:
		var mi := w as MeshInstance3D
		var mesh: Mesh = mi.mesh
		if mesh == null or mesh.get_surface_count() == 0:
			continue
		var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		if verts.is_empty():
			continue
		var xf := _world_xf(mi)
		var n := 0
		var high := 0
		var worst := 0.0
		var wx := 0.0
		var wz := 0.0
		var step := maxi(1, verts.size() / 2500)
		for i in range(0, verts.size(), step):
			var p: Vector3 = xf * verts[i]
			var vals: Array[float] = []
			for di in range(-4, 5):
				for dj in range(-4, 5):
					var c := Vector2i(int(floor(p.x / _cell)) + di, int(floor(p.z / _cell)) + dj)
					if _gmax.has(c):
						vals.append(_gmax[c])
			if vals.size() < 20:
				continue
			vals.sort()
			var rim: float = vals[int(float(vals.size()) * 0.95)]
			n += 1
			var d := p.y - rim
			if d > 0.05:
				high += 1
				if d > worst:
					worst = d
					wx = p.x
					wz = p.z
		if n == 0:
			continue
		var frac := float(high) / float(n)
		if frac > 0.12:
			_issues.append("水面有 %.0f%% 高過岸緣（溢到平地／路面上）：%s 最高 %.2fm @ (%.0f, %.0f)"
				% [frac * 100.0, mi.name, worst, wx, wz])

## 建物／土塀橫跨水面 —— 使用者回報「水道被牆壁擋住了」。
## 產生器那邊只測了牆的**中心點**離水多遠，但一道 42m 長的牆中心在遠處、
## 身體照樣橫跨水路。這裡直接比幾何：水面頂點落在建物的水平範圍內就是壓到。
func _check_building_over_water(buildings: Array, waters: Array) -> void:
	if buildings.is_empty() or waters.is_empty():
		return
	var bgrid := {}
	for i in buildings.size():
		var box: AABB = buildings[i].aabb
		for ii in range(int(floor(box.position.x / 10.0)), int(floor((box.position.x + box.size.x) / 10.0)) + 1):
			for jj in range(int(floor(box.position.z / 10.0)), int(floor((box.position.z + box.size.z) / 10.0)) + 1):
				var k := Vector2i(ii, jj)
				if not bgrid.has(k):
					bgrid[k] = []
				bgrid[k].append(i)
	var hits := {}
	for w in waters:
		var mi := w as MeshInstance3D
		var mesh: Mesh = mi.mesh
		if mesh == null or mesh.get_surface_count() == 0:
			continue
		var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var xf := _world_xf(mi)
		var step := maxi(1, verts.size() / 4000)
		for i in range(0, verts.size(), step):
			var p: Vector3 = xf * verts[i]
			var k := Vector2i(int(floor(p.x / 10.0)), int(floor(p.z / 10.0)))
			if not bgrid.has(k):
				continue
			for bi in bgrid[k]:
				var box: AABB = buildings[bi].aabb
				if p.x > box.position.x and p.x < box.position.x + box.size.x \
						and p.z > box.position.z and p.z < box.position.z + box.size.z \
						and _pt_in_entry(buildings[bi], p.x, p.z):
					# 橋是應該跨過水的 —— 只抓牆與屋身
					var nm: String = buildings[bi].name
					# 只放行橋 —— 石垣護岸本來就在水面外側，它若壓到水
					# 就是真的砌錯地方（v11 的護岸一路砌進大河）
					if nm.contains("橋"):
						continue
					if not hits.has(nm):
						hits[nm] = Vector2(p.x, p.z)
	var n := 0
	for nm in hits:
		n += 1
		if n <= 5:
			var q: Vector2 = hits[nm]
			_issues.append("建物橫跨水面（水被擋住）：%s @ (%.0f, %.0f)" % [nm, q.x, q.y])
	if n > 5:
		_issues.append("…另有 %d 棟建物壓在水面上" % (n - 5))

## 道具浮空 / 埋進地裡 —— 使用者回報「雜物在空中」。
## 掃 Clutter / Props / FloorDecor 這幾組群組節點，比它們的底面與地形。
func _check_props_grounded(root: Node) -> void:
	for gname in ["Clutter", "Props", "FloorDecor", "Lamps"]:
		var grp := root.find_child(gname, true, false)
		if grp == null:
			continue
		var floats := 0
		var worst := 0.0
		var wname := ""
		var wpos := Vector3.ZERO
		for c in grp.get_children():
			if not (c is Node3D):
				continue
			var box := AABB()
			var got := false
			var stack: Array[Node] = [c]
			while stack.size() > 0:
				var n2: Node = stack.pop_back()
				for gc in n2.get_children():
					stack.push_back(gc)
				if n2 is MeshInstance3D:
					var wb: AABB = _world_xf(n2) * (n2 as MeshInstance3D).get_aabb()
					box = wb if not got else box.merge(wb)
					got = true
			if not got:
				continue
			var g := _ground_min_box(box.position.x, box.position.z,
				box.position.x + box.size.x, box.position.z + box.size.z)
			if g == -INF:
				continue
			var gap := box.position.y - g
			if gap > 0.6:
				floats += 1
				if gap > worst:
					worst = gap
					wname = String(c.name)
					wpos = box.get_center()
		if floats > 0:
			_issues.append("%s 有 %d 件離地（最嚴重 %.2fm：%s @ %.0f, %.0f）"
				% [gname, floats, worst, wname, wpos.x, wpos.z])

## 水面高度 —— 「水是隱形的」（水面沉到河床底下）
## v1 拿 AABB 中心點量，河是彎的、中心點根本不在河上，於是報假訊息。
## 改成取樣水面 mesh 的頂點，逐點跟該處河床比。
func _check_water(waters: Array) -> void:
	for w in waters:
		var mi := w as MeshInstance3D
		var mesh: Mesh = mi.mesh
		if mesh == null or mesh.get_surface_count() == 0:
			continue
		var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		if verts.is_empty():
			continue
		var xf := _world_xf(mi)
		var n := 0
		var bad := 0
		var worst := 0.0
		var wx := 0.0
		var wz := 0.0
		var step := maxi(1, verts.size() / 4000)
		for i in range(0, verts.size(), step):
			var p: Vector3 = xf * verts[i]
			var g := _ground_min_at(p.x, p.z)
			if g == -INF:
				continue
			n += 1
			var d := g - p.y
			if d > TOL_WATER:
				bad += 1
				if d > worst:
					worst = d
					wx = p.x
					wz = p.z
		if n == 0:
			continue
		var frac := float(bad) / float(n)
		if frac > WATER_BAD_FRAC:
			_issues.append("水面有 %.0f%% 埋在地面下（最深 %.2fm @ %.0f, %.0f）：%s"
				% [frac * 100.0, worst, wx, wz, mi.name])

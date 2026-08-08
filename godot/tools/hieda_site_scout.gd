# 稗田邸完整版落點偵查 —— 人間之里邊界有沒有 95×107 的淨空
#
#   godot --headless --path godot --script tools/hieda_site_scout.gd
#
# 執行前偵查（改善書 §1.1），**不動任何東西**，只量。量的是成品：
# 載入 village.tscn 把每一件內容的世界 AABB 打進 2m 佔用網格，再掃出
# 淨空矩形 —— 不是拿產生器的變數猜。
#
# 排除在「佔用」之外的東西（它們不是障礙）：
#   Terrain / Boundary / Vista*（圖外遠景）/ 草層 / 水生植物 / 水面本身
# 河與水面另外記一層：河不是「不能蓋」，是「不能壓在上面」，要單獨量距離。
extends SceneTree

const CELL := 2.0
const HALF := 300.0               # gen_town 的 HALF
const EDGE := 6.0                 # 圖緣 Boundary 牆內縮
const NEED_W := 95.3              # 完整版擺位表跨度（實測）
const NEED_D := 107.0
const BUFFER := 5.0               # 四周緩衝（改善書 §2.4／§4 的疏林帶）

var _occ := {}                    # Vector2i -> 來源名（建物／地標／橋／護岸…）
var _water := {}                  # Vector2i -> true（河面）
var _tree := {}                   # Vector2i -> true（樹：可清，另計）
var _n := {"occ": 0, "water": 0, "tree": 0}
var _towers: Array[Vector2] = []


func _init() -> void:
	_asset_extents()
	var root: Node3D = (load("res://maps/village/village.tscn") as PackedScene).instantiate()
	_scan(root, "")
	print("\n佔用格 %d／水面格 %d／樹格 %d（格 %.0fm）"
		% [_occ.size(), _water.size(), _tree.size(), CELL])
	_report_landmarks(root)
	_probe_candidates()
	_scan_sites()
	quit(0)


## 完整版的本地包絡（實測）：擺位表 x −50.1..45.2、z −76.1..30.9；
## blockout 本體 x −36.8..38.8、z −70.0..40.5（外參道端點 +40.5 比植栽還前）
## → 併起來 x −50.1..45.2、z −76.1..40.5，即 95.3 × 116.6
const LOC_X0 := -50.1
const LOC_X1 := 45.2
const LOC_Z0 := -76.1
const LOC_Z1 := 40.5

## 候選原點（＝完整版自己的座標原點要放在村圖的哪一點）
const CANDS := [
	{"n": "A′ 原地擴張・外參道接上 z=−135 橫街（建議）", "x": -78.0, "z": -178.0},
	{"n": "E 更西、完全不碰街網", "x": -215.0, "z": -150.0},
]

func _probe_candidates() -> void:
	print("\n── 候選落點實測（框 = 完整版包絡 %.1f×%.1f + 緩衝 %.0fm）──"
		% [LOC_X1 - LOC_X0, LOC_Z1 - LOC_Z0, BUFFER])
	for c in CANDS:
		var ox: float = float(c.x)
		var oz: float = float(c.z)
		var x0: float = ox + LOC_X0 - BUFFER
		var x1: float = ox + LOC_X1 + BUFFER
		var z0: float = oz + LOC_Z0 - BUFFER
		var z1: float = oz + LOC_Z1 + BUFFER
		var occ := 0
		var wat := 0
		var tre := 0
		var hits := {}
		for i in range(int(floor(x0 / CELL)), int(ceil(x1 / CELL)) + 1):
			for j in range(int(floor(z0 / CELL)), int(ceil(z1 / CELL)) + 1):
				var k := Vector2i(i, j)
				if _occ.has(k):
					occ += 1
					hits[_occ[k]] = int(hits.get(_occ[k], 0)) + 1
				if _water.has(k):
					wat += 1
				if _tree.has(k):
					tre += 1
		var cx := (x0 + x1) * 0.5
		var cz := (z0 + z1) * 0.5
		var dn := _dist_to_content(cx, cz, x1 - x0, z1 - z0)
		print("\n  %s　原點 (%.0f, %.0f)" % [c.n, ox, oz])
		print("    框 x %.0f..%.0f　z %.0f..%.0f（%.0f×%.0f）"
			% [x0, x1, z0, z1, x1 - x0, z1 - z0])
		print("    框內：佔用格 %d　水面格 %d　樹格 %d" % [occ, wat, tre])
		if occ > 0:
			var names: Array = hits.keys()
			names.sort()
			print("    ⚠ 撞到：%s" % ", ".join(names.slice(0, 6)))
		print("    框外緣離既有內容 %.1fm／離河 %.1fm／離地標塔 %.1fm"
			% [dn[0], dn[1], dn[2]])
		print("    表門位置（本地 z=+34）→ 世界 (%.0f, %.0f)；北門在 (0, −168)，相距 %.0fm"
			% [ox, oz + 34.0, Vector2(ox, oz + 34.0).distance_to(Vector2(0, -168))])


# ── 完整版資產到底多大 ──
func _asset_extents() -> void:
	print("── 完整版資產實測 ──")
	for path in ["res://assets/models/hieda_blockout.glb",
			"res://assets/models/hieda_main.glb"]:
		var ps: PackedScene = load(path)
		if ps == null:
			print("  ✗ 載不到 %s" % path)
			continue
		var n: Node = ps.instantiate()
		var box := AABB()
		var got := false
		var stack: Array[Node] = [n]
		while stack.size() > 0:
			var c: Node = stack.pop_back()
			for g in c.get_children():
				stack.push_back(g)
			if c is MeshInstance3D:
				var wb: AABB = _xf(c as Node3D, n) * (c as MeshInstance3D).get_aabb()
				box = wb if not got else box.merge(wb)
				got = true
		print("  %s　%.1f × %.1f m（高 %.1f）　x %.1f..%.1f  z %.1f..%.1f"
			% [path.get_file(), box.size.x, box.size.z, box.size.y,
				box.position.x, box.position.x + box.size.x,
				box.position.z, box.position.z + box.size.z])
		n.queue_free()
	# 植栽擺位表（blockout 之外的 136 實例）
	var txt := FileAccess.get_file_as_string("res://data/hieda_garden.instances.json")
	var man: Dictionary = JSON.parse_string(txt)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var cnt := 0
	for k in man["modules"]:
		for t in man["modules"][k]["xforms"]:
			cnt += 1
			lo.x = minf(lo.x, float(t[0])); lo.y = minf(lo.y, float(t[2]))
			hi.x = maxf(hi.x, float(t[0])); hi.y = maxf(hi.y, float(t[2]))
	print("  植栽擺位表　%.1f × %.1f m（%d 實例）　x %.1f..%.1f  z %.1f..%.1f"
		% [hi.x - lo.x, hi.y - lo.y, cnt, lo.x, hi.x, lo.y, hi.y])


func _xf(n: Node3D, stop: Node) -> Transform3D:
	var t := n.transform
	var p: Node = n.get_parent()
	while p != null and p != stop:
		t = (p as Node3D).transform * t
		p = p.get_parent()
	return t


# ── 掃 village.tscn 建佔用網格 ──
func _scan(n: Node, path: String) -> void:
	var nm := String(n.name)
	var full := path + "/" + nm
	# 圖外遠景／地形／邊界牆／草：不是障礙
	if nm.begins_with("Vista") or nm == "Terrain" or nm == "Boundary" \
			or nm in ["Shrubs", "Ferns", "GrassTall", "GrassFlower", "Reeds", "WaterPlants"]:
		return
	# ⚠ 現有的村版稗田邸（含它的庭池）**不算障礙** —— 它正是要被取代的對象。
	# 不排除的話每個「原地擴張」候選都會報成撞到自己。
	if nm == "稗田邸" or nm == "庭池":
		return
	var kind := "occ"
	if nm == "River":
		kind = "water"
	elif full.contains("花樹") or nm.begins_with("MM_tree") or nm.contains("樹叢"):
		kind = "tree"
	if n is MultiMeshInstance3D:
		_mark_mm(n as MultiMeshInstance3D, kind, _tag(full))
	elif n is MeshInstance3D:
		_mark(_world(n as MeshInstance3D) * (n as MeshInstance3D).get_aabb(), kind, _tag(full))
	for c in n.get_children():
		_scan(c, full)


func _world(n: Node3D) -> Transform3D:
	var t := n.transform
	var p: Node = n.get_parent()
	while p is Node3D:
		t = (p as Node3D).transform * t
		p = p.get_parent()
	return t


## 路徑取前兩層當標籤（/Sato/町家 → 町家），撞到誰才報得出名字
func _tag(full: String) -> String:
	var parts := full.split("/", false)
	return parts[1] if parts.size() > 1 else full


func _mark_mm(mmi: MultiMeshInstance3D, kind: String, tag: String) -> void:
	var mm: MultiMesh = mmi.multimesh
	if mm == null or mm.instance_count == 0:
		return
	var ab: AABB = mm.mesh.get_aabb() if mm.mesh != null else AABB()
	var r := maxf(ab.size.x, ab.size.z) * 0.5
	var buf := mm.buffer
	var stride := 16 if mm.use_colors else 12
	var base := _world(mmi)
	for i in mm.instance_count:
		var o := i * stride
		if o + 11 >= buf.size():
			break
		var p: Vector3 = base * Vector3(buf[o + 3], buf[o + 7], buf[o + 11])
		var s := maxf(absf(buf[o]), absf(buf[o + 2]))
		_mark(AABB(Vector3(p.x - r * s, 0, p.z - r * s),
			Vector3(r * s * 2.0, 1, r * s * 2.0)), kind)


func _mark(b: AABB, kind: String, tag := "?") -> void:
	var d: Dictionary = _occ if kind == "occ" else (_water if kind == "water" else _tree)
	for i in range(int(floor(b.position.x / CELL)), int(ceil((b.position.x + b.size.x) / CELL)) + 1):
		for j in range(int(floor(b.position.z / CELL)), int(ceil((b.position.z + b.size.z) / CELL)) + 1):
			d[Vector2i(i, j)] = tag
	_n[kind] += 1


func _report_landmarks(root: Node) -> void:
	print("\n── 地標塔／地標中心（找落點時要避開）──")
	for g in ["地標塔", "地標佔位"]:
		var node := root.find_child(g, true, false)
		if node == null:
			continue
		for c in node.get_children():
			var box := AABB()
			var got := false
			var stack: Array[Node] = [c]
			while stack.size() > 0:
				var q: Node = stack.pop_back()
				for k in q.get_children():
					stack.push_back(k)
				if q is MeshInstance3D:
					var wb: AABB = _world(q as Node3D) * (q as MeshInstance3D).get_aabb()
					box = wb if not got else box.merge(wb)
					got = true
			if got:
				_towers.append(Vector2(box.get_center().x, box.get_center().z))
				print("  %-10s 中心 (%.0f, %.0f)　跨度 %.0f×%.0f"
					% [c.name, box.get_center().x, box.get_center().z, box.size.x, box.size.z])


# ── 掃淨空矩形 ──
# 需要 (NEED_W + 2*BUFFER) × (NEED_D + 2*BUFFER)，四個朝向都試
# （完整版是南北向長 107、東西向寬 95；轉 90° 也算數）
func _scan_sites() -> void:
	var lim := HALF - EDGE
	for rot in [false, true]:
		var w: float = (NEED_D if rot else NEED_W) + BUFFER * 2.0
		var d: float = (NEED_W if rot else NEED_D) + BUFFER * 2.0
		print("\n── 淨空掃描：需要 %.0f × %.0f m%s ──"
			% [w, d, "（轉 90°）" if rot else ""])
		var cw := int(ceil(w / CELL))
		var cd := int(ceil(d / CELL))
		var best := []
		var lo := int(-lim / CELL)
		var hi := int(lim / CELL)
		for i in range(lo, hi - cw + 1, 2):
			for j in range(lo, hi - cd + 1, 2):
				var occ := 0
				var wat := 0
				var tre := 0
				for a in range(i, i + cw):
					for b in range(j, j + cd):
						var k := Vector2i(a, b)
						if _occ.has(k):
							occ += 1
						if _water.has(k):
							wat += 1
						if _tree.has(k):
							tre += 1
					if occ > 0 or wat > 0:
						break
				if occ == 0 and wat == 0:
					var cx := (float(i) + float(cw) * 0.5) * CELL
					var cz := (float(j) + float(cd) * 0.5) * CELL
					best.append([cx, cz, tre])
		if best.is_empty():
			print("  ✗ 全圖找不到完全淨空的框")
			_edge_relax(w, d)
			continue
		# 挑「離圖心最遠」的幾個（邊界優先），順便報樹格數
		# 「邊界」不是「圖角」：要的是**貼著村子的外緣**，不是荒野正中央。
		# 所以排序看的是「離最近的既有內容多遠」—— 越小越貼村，0 是不可能
		# （框內淨空），太大就變成孤零零蓋在野外。
		var scored := []
		for e in best:
			var dn := _dist_to_content(float(e[0]), float(e[1]), w, d)
			scored.append([e[0], e[1], e[2], dn[0], dn[1], dn[2]])
		scored.sort_custom(func(a, b): return a[3] < b[3])
		print("  ✓ 找到 %d 個淨空框。**最貼村緣**的 8 個（框外緣離既有內容的距離）："
			% best.size())
		print("    　中心座標　　　離內容　離河　離地標塔　框內樹格")
		for k2 in mini(8, scored.size()):
			var e = scored[k2]
			print("    (%6.0f, %6.0f)　%6.1fm　%6.1fm　%7.1fm　%4d"
				% [e[0], e[1], e[3], e[4], e[5], e[2]])


## 框（中心 cx,cz，尺寸 w×d）外緣到最近的 [既有內容, 河面, 地標塔] 的距離
func _dist_to_content(cx: float, cz: float, w: float, d: float) -> Array:
	var best := [INF, INF, INF]
	var hw := w * 0.5
	var hd := d * 0.5
	for src in [[_occ, 0], [_water, 1]]:
		var dict: Dictionary = src[0]
		var slot: int = src[1]
		for k in dict:
			var px: float = float(k.x) * CELL
			var pz: float = float(k.y) * CELL
			var dx: float = maxf(absf(px - cx) - hw, 0.0)
			var dz: float = maxf(absf(pz - cz) - hd, 0.0)
			var dd := sqrt(dx * dx + dz * dz)
			if dd < best[slot]:
				best[slot] = dd
	for t in _towers:
		var dx2: float = maxf(absf(t.x - cx) - hw, 0.0)
		var dz2: float = maxf(absf(t.y - cz) - hd, 0.0)
		best[2] = minf(best[2], sqrt(dx2 * dx2 + dz2 * dz2))
	return best


## 完全淨空找不到時：放寬成「只擋建物、河可繞」，回報最少的水面格
func _edge_relax(w: float, d: float) -> void:
	var lim := HALF - EDGE
	var cw := int(ceil(w / CELL))
	var cd := int(ceil(d / CELL))
	var best := []
	for i in range(int(-lim / CELL), int(lim / CELL) - cw + 1, 2):
		for j in range(int(-lim / CELL), int(lim / CELL) - cd + 1, 2):
			var occ := 0
			var wat := 0
			for a in range(i, i + cw):
				for b in range(j, j + cd):
					var k := Vector2i(a, b)
					if _occ.has(k):
						occ += 1
					if _water.has(k):
						wat += 1
				if occ > 0:
					break
			if occ == 0:
				best.append([(float(i) + float(cw) * 0.5) * CELL,
					(float(j) + float(cd) * 0.5) * CELL, wat])
	if best.is_empty():
		print("  ✗ 連「只擋建物」都找不到")
		return
	best.sort_custom(func(a, b): return a[2] < b[2])
	print("  放寬成「只擋建物、河另計」→ %d 個候選，水面格最少的 6 個：" % best.size())
	for k2 in mini(6, best.size()):
		var e = best[k2]
		print("    中心 (%6.0f, %6.0f)　框內水面格 %d（%.0f㎡）"
			% [e[0], e[1], e[2], float(e[2]) * CELL * CELL])

# 稗田邸完整版邊界安置 —— 量成品
#
#   godot --headless --path godot --script tools/hieda_boundary_check.gd
#
# 改善書 §6 的第五道閘門。前四道（lm_ghost／check_map／walk_test／portal_test）
# 驗的是「有沒有壞」，這支驗的是「搬對地方了沒」：footprint 座標、離河距離、
# 離地標塔距離、緩衝疏林環帶寬度。
#
# 一律從存好的 village.tscn 讀，不看產生器的變數 —— 產生器算錯的話，
# 拿它自己的常數去比只會兩邊一起錯（這是這個專案的搬遷驗收規矩）。
extends SceneTree

const RES_C := Vector2(-80.5, -195.8)     # 保留區中心（gen_town 的 LANDMARKS）
const RES_W := 97.0
const RES_D := 118.5
const NEED_W := 95.3                       # 完整版實測包絡
const NEED_D := 116.6
const RIVER_MIN := 20.0                    # 離河最少要留多少（§2：無重疊即可）
const TOWER_MIN := 25.0                    # 離地標塔最少（§5：不搶焦）
const GROVE_LO := 3.0                      # 緩衝環帶內緣（§4）
const GROVE_HI := 9.0                      # 緩衝環帶外緣

var _fail := 0
var _root: Node3D


func _init() -> void:
	_root = (load("res://maps/village/village.tscn") as PackedScene).instantiate()
	_check_footprint()
	_check_content()
	_check_river()
	_check_towers()
	_check_grove()
	_check_approach()
	print("\n══ 邊界安置檢查：%d 項不符 ══" % _fail)
	quit(1 if _fail > 0 else 0)


func _ok(cond: bool, label: String, got := "") -> void:
	if cond:
		print("  ✓ %s%s" % [label, ("　" + got) if got != "" else ""])
	else:
		print("  ✗ %s　實測 %s" % [label, got])
		_fail += 1


func _world(n: Node3D) -> Transform3D:
	var t := n.transform
	var p: Node = n.get_parent()
	while p is Node3D:
		t = (p as Node3D).transform * t
		p = p.get_parent()
	return t


## 一棵子樹的世界 AABB（含 MultiMesh 的逐實例）
func _subtree_box(root: Node) -> AABB:
	var box := AABB()
	var got := false
	var stack: Array[Node] = [root]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.push_back(c)
		if n is MultiMeshInstance3D:
			var mm: MultiMesh = (n as MultiMeshInstance3D).multimesh
			if mm == null or mm.instance_count == 0 or mm.mesh == null:
				continue
			var ab: AABB = mm.mesh.get_aabb()
			var base := _world(n as Node3D)
			var buf := mm.buffer
			var stride := 16 if mm.use_colors else 12
			for i in mm.instance_count:
				var o := i * stride
				if o + 11 >= buf.size():
					break
				var xf := Transform3D(
					Vector3(buf[o], buf[o + 4], buf[o + 8]),
					Vector3(buf[o + 1], buf[o + 5], buf[o + 9]),
					Vector3(buf[o + 2], buf[o + 6], buf[o + 10]),
					Vector3(buf[o + 3], buf[o + 7], buf[o + 11]))
				var wb: AABB = (base * xf) * ab
				box = wb if not got else box.merge(wb)
				got = true
		elif n is MeshInstance3D:
			var wb2: AABB = _world(n as Node3D) * (n as MeshInstance3D).get_aabb()
			box = wb2 if not got else box.merge(wb2)
			got = true
	return box


func _est() -> Node:
	return _root.find_child("稗田邸", true, false)


# ── 1. footprint 落在保留區內、而且保留區沒有虛胖 ──
func _check_footprint() -> void:
	print("\n── footprint ──")
	var est := _est()
	if est == null:
		_ok(false, "地標佔位/稗田邸 存在", "缺件")
		return
	var b := _subtree_box(est)
	print("  實測跨度 %.1f × %.1f m　中心 (%.1f, %.1f)　高 %.1f"
		% [b.size.x, b.size.z, b.get_center().x, b.get_center().z, b.size.y])
	_ok(b.size.x >= NEED_W - 1.0 and b.size.z >= NEED_D - 1.0,
		"完整版整組都在（不是又縮了一次）：跨度 ≥ %.1f×%.1f" % [NEED_W, NEED_D],
		"%.1f×%.1f" % [b.size.x, b.size.z])
	var over := maxf(
		maxf(RES_C.x - RES_W * 0.5 - b.position.x, b.position.x + b.size.x - RES_C.x - RES_W * 0.5),
		maxf(RES_C.y - RES_D * 0.5 - b.position.z, b.position.z + b.size.z - RES_C.y - RES_D * 0.5))
	_ok(over <= 0.0, "沒有外溢保留區 %.1f×%.1f" % [RES_W, RES_D], "最大外溢 %.2fm" % over)
	var slack := minf(RES_W - b.size.x, RES_D - b.size.z)
	_ok(slack < 6.0, "保留區沒有虛胖（餘裕 < 6m；虛胖會白白把町家推開）",
		"最小餘裕 %.2fm" % slack)


# ── 2. 搬進來的是**完整版**：blockout 本體 + 136 植栽實例 ──
func _check_content() -> void:
	print("\n── 內容 ──")
	var est := _est()
	if est == null:
		return
	var body := est.find_child("本體", true, false) as MeshInstance3D
	_ok(body != null, "blockout 本體節點存在")
	if body != null:
		var m: Mesh = body.mesh
		var tris := 0
		for s in m.get_surface_count():
			var arr := m.surface_get_arrays(s)
			var ic := 0
			if arr[Mesh.ARRAY_INDEX] != null:
				ic = (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size()
			tris += ic / 3
		_ok(tris > 22000, "blockout 面數 ≈22,600（縮小版只有這個的零頭）", "%d 面" % tris)
		_ok(body.has_meta("needs_trimesh"),
			"掛了 needs_trimesh —— blockout 沒有自己的碰撞，全靠執行期 trimesh")
		# ⚠ 材質掛在 **mesh 的 surface** 上（lib.prop_mesh 是這樣設的），
		# 不是 material_override —— 第一版的檢查看錯地方，報「無材質」。
		var mat: Material = body.material_override
		if mat == null and m.get_surface_count() > 0:
			mat = m.surface_get_material(0)
		var sm := mat as StandardMaterial3D
		_ok(sm != null and sm.cull_mode == BaseMaterial3D.CULL_DISABLED,
			"材質關掉背面剔除（Blender 雙面／Godot 剔背面 —— 不關的話整條參道消失）",
			"cull_mode=%s" % (str(sm.cull_mode) if sm != null else "無材質"))
	var total := 0
	var mods := 0
	var stack: Array[Node] = [est]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.push_back(c)
		if n is MultiMeshInstance3D and String(n.name).begins_with("MM_hieda"):
			mods += 1
			total += (n as MultiMeshInstance3D).multimesh.instance_count
	_ok(total == 136 and mods == 10, "植栽 136 實例 / 10 種模組（擺位表原封不動）",
		"%d 實例 / %d 模組" % [total, mods])


# ── 3. 河（§2）──
func _check_river() -> void:
	print("\n── 河 ──")
	var riv := _root.find_child("River", true, false) as MeshInstance3D
	if riv == null:
		_ok(false, "River 存在", "缺件")
		return
	var b := _subtree_box(_est())
	var best := INF
	var arr := (riv.mesh as ArrayMesh).surface_get_arrays(0)
	var xf := _world(riv)
	for v in (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array):
		var p: Vector3 = xf * v
		var dx: float = maxf(maxf(b.position.x - p.x, p.x - b.position.x - b.size.x), 0.0)
		var dz: float = maxf(maxf(b.position.z - p.z, p.z - b.position.z - b.size.z), 0.0)
		best = minf(best, sqrt(dx * dx + dz * dz))
	_ok(best >= RIVER_MIN,
		"庭院與河面不重疊、且留 ≥%.0fm（§2「無重疊」分支：河道維持原路徑）" % RIVER_MIN,
		"最近 %.1fm" % best)


# ── 4. 地標塔（§5）──
func _check_towers() -> void:
	print("\n── 地標塔視覺平衡 ──")
	var g := _root.find_child("地標塔", true, false)
	if g == null:
		_ok(false, "地標塔 存在", "缺件")
		return
	var b := _subtree_box(_est())
	for t in g.get_children():
		var tb := _subtree_box(t)
		var c := tb.get_center()
		var dx: float = maxf(maxf(b.position.x - c.x, c.x - b.position.x - b.size.x), 0.0)
		var dz: float = maxf(maxf(b.position.z - c.z, c.z - b.position.z - b.size.z), 0.0)
		var d := sqrt(dx * dx + dz * dz)
		_ok(d >= TOWER_MIN, "%s 離庭院外緣 ≥%.0fm" % [t.name, TOWER_MIN], "%.1fm" % d)


# ── 5. 緩衝疏林（§4）──
func _check_grove() -> void:
	print("\n── 緩衝疏林 ──")
	var g := _root.find_child("稗田邸緩衝林", true, false)
	if g == null:
		_ok(false, "稗田邸緩衝林 存在", "缺件")
		return
	var n := 0
	var bad := 0
	var lo := INF
	var hi := -INF
	for c in g.get_children():
		var mm: MultiMesh = (c as MultiMeshInstance3D).multimesh
		var buf := mm.buffer
		var stride := 16 if mm.use_colors else 12
		for i in mm.instance_count:
			var o := i * stride
			n += 1
			var x: float = buf[o + 3]
			var z: float = buf[o + 11]
			var out: float = maxf(absf(x - RES_C.x) - RES_W * 0.5,
				absf(z - RES_C.y) - RES_D * 0.5)
			lo = minf(lo, out)
			hi = maxf(hi, out)
			if out < GROVE_LO - 0.5 or out > GROVE_HI + 0.5:
				bad += 1
	_ok(n >= 30, "環帶上有樹（≥30 株）", "%d 株" % n)
	_ok(bad == 0, "全部落在保留區外緣 %.0f~%.0fm 的環帶上（不進院子、不撒滿田）"
		% [GROVE_LO, GROVE_HI], "%d 株出界（實測 %.1f~%.1fm）" % [bad, lo, hi])


# ── 6. 動線（§3）：庭院自己的外參道要接到街上 ──
func _check_approach() -> void:
	print("\n── 動線 ──")
	var b := _subtree_box(_est())
	# z=−135 橫街，寬 5.0 → 北緣 −137.5
	var street_edge := -137.5
	var gap: float = b.position.z + b.size.z - street_edge
	_ok(absf(gap) <= 3.0,
		"外參道端點接上 z=−135 橫街的北緣（不用另拉引道）",
		"庭院南緣 %.1f，街緣 %.1f，差 %.1fm" % [b.position.z + b.size.z, street_edge, gap])
	var meta: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/village.meta.json"))
	var found := false
	for p in meta.get("portals", []):
		if p.get("target") == "hieda1f":
			found = true
			var inside: bool = absf(float(p.x) - RES_C.x) < RES_W * 0.5 \
				and absf(float(p.z) - RES_C.y) < RES_D * 0.5
			_ok(inside, "室內 portal 落在庭院內（唐破風石階前）",
				"(%.2f, %.2f)" % [float(p.x), float(p.z)])
	_ok(found, "village.meta 有指向 hieda1f 的 portal")

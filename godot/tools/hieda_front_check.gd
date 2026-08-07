# 稗田邸前庭 —— 定案規格逐項對照
#
#   godot --headless --path godot --script tools/hieda_front_check.gd
#
# 這一輪把村院的前庭從「舊 gen_village 的築地塀＋藥醫門」換成使用者逐輪驗收
# 過的定案版（assets/blender/make_hieda.py 的格子塀／棟門／狛犬／石燈籠／
# 飛石參道）。搬遷驗收的規矩是**量成品、不量產生器參數** —— 產生器自己
# 算錯的話，拿產生器的變數去比只會兩邊一起錯。所以這支從存好的
# village.tscn 讀節點，跟 make_hieda.py 的明表逐項比。
#
# 座標換算（獨立版 Blender Z-up → 村院 Godot Y-up）：
#     村本地 x = blender x + AXIS
#     村本地 z = −blender y − 12.5
# 院落中心 (−78, −164)，中軸 x = −5（本地）。
extends SceneTree

const CX := -78.0                # 院落中心（世界）
const CZ := -164.0
const AXIS := -5.0               # 前庭中軸（本地）
const TOL := 0.02                # 位置／尺寸容差（m）
const TOL_A := 0.01              # 角度容差（rad）

var _fail := 0
var _root: Node3D


func _init() -> void:
	var packed: PackedScene = load("res://maps/village/village.tscn")
	_root = packed.instantiate()
	var est := _root.find_child("稗田邸", true, false)
	if est == null:
		print("✗ 找不到 地標佔位/稗田邸")
		quit(1)
		return
	var y0: float = est.position.y
	print("院落群組原點 y = %.3f（＝院子地面；舊版是池水面，整座宅子沉 0.55m）" % y0)

	_check_removed(est)
	_check_komainu(est)
	_check_lantern(est)
	_check_pine(est)
	_check_gate(est)
	_check_wall(est)
	_check_apron(est)
	_check_sando(est)
	_check_karahafu(est)
	print("\n══ 前庭定案規格對照：%d 項不符 ══" % _fail)
	quit(1 if _fail > 0 else 0)


func _ok(cond: bool, label: String, got := "") -> void:
	if cond:
		print("  ✓ %s%s" % [label, ("　" + got) if got != "" else ""])
	else:
		print("  ✗ %s　實測 %s" % [label, got])
		_fail += 1


func _near(a: float, b: float, tol := TOL) -> bool:
	return absf(a - b) <= tol


## 節點自己的 AABB（含 scale/rotation）換算到院落本地座標
func _box(n: Node3D) -> AABB:
	var mi := n as MeshInstance3D
	var ab: AABB = mi.get_aabb()
	var xf: Transform3D = mi.transform
	var p: Node = mi.get_parent()
	while p != null and p != _root and not (p is Node3D and String(p.name) == "稗田邸"):
		xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf * ab


func _find(est: Node, nm: String) -> Node3D:
	return est.find_child(nm, true, false) as Node3D


# ── 1. 舊版前庭真的拆乾淨了嗎（不是疊上去而已）──
func _check_removed(est: Node) -> void:
	print("\n── 舊築地塀／藥醫門殘留 ──")
	var stale := ["腰石垣", "築地塀", "定規筋", "門樑"]
	var left := []
	var stack: Array[Node] = [est]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.push_back(c)
		for s in stale:
			if String(n.name).begins_with(s):
				left.append(String(n.name))
	_ok(left.is_empty(), "舊件已全數移除（腰石垣／築地塀／定規筋／門樑）",
		"還剩 %d 個：%s" % [left.size(), ", ".join(left.slice(0, 5))])


# ── 2. 狛犬：嚴格左右對稱、+18%、從門往內 1/3 ──
func _check_komainu(est: Node) -> void:
	print("\n── 狛犬（嚴格對稱・放大 18%）──")
	var a := _find(est, "狛犬_0")
	var b := _find(est, "狛犬_2")
	if a == null or b == null:
		_ok(false, "狛犬一對存在", "缺件")
		return
	# 明表：x = AXIS ∓ 4.7、z = +14.0、scale 1.18、yaw = ∓1.0
	_ok(_near(a.position.x, AXIS - 4.7) and _near(b.position.x, AXIS + 4.7),
		"x = 中軸 ∓4.7", "%.2f / %.2f" % [a.position.x, b.position.x])
	_ok(_near(a.position.z, 14.0) and _near(b.position.z, 14.0),
		"z = +14.0（前庭深 22.6 的 1/3）", "%.2f / %.2f" % [a.position.z, b.position.z])
	# 對稱：兩隻離中軸等距、同高、同縮放、旋轉互為相反
	_ok(_near(absf(a.position.x - AXIS), absf(b.position.x - AXIS), 0.001)
		and _near(a.position.y, b.position.y, 0.001),
		"左右嚴格對稱（離軸等距、同高）")
	_ok(_near(a.scale.x, 1.18, 0.001) and _near(b.scale.x, 1.18, 0.001),
		"縮放 1.18", "%.3f / %.3f" % [a.scale.x, b.scale.x])
	_ok(_near(a.rotation.y, 1.0, TOL_A) and _near(b.rotation.y, -1.0, TOL_A),
		"yaw ±1.0（斜對中線、偏向來人）", "%.3f / %.3f" % [a.rotation.y, b.rotation.y])
	var h: float = _box(a).size.y
	_ok(_near(h, 3.25, 0.12), "實高 ≈3.25m（門柱 3.30，同一個視覺量級）",
		"%.2fm" % h)


# ── 3. 石燈籠：刻意不對稱（明表寫死，不用迴圈鏡射）──
func _check_lantern(est: Node) -> void:
	print("\n── 門前石燈籠（刻意不對稱）──")
	# 明表：右 (6.50, 14.70) rot 0.26 sc 1.06｜左 (−7.40, 16.40) rot −0.62 sc 0.98
	for spec in [[2, 6.50, 14.70, 0.26, 1.06], [0, -7.40, 16.40, -0.62, 0.98]]:
		var n := _find(est, "門前燈籠_%d" % int(spec[0]))
		if n == null:
			_ok(false, "門前燈籠_%d 存在" % int(spec[0]), "缺件")
			continue
		_ok(_near(n.position.x, AXIS + float(spec[1])) and _near(n.position.z, float(spec[2]))
			and _near(n.rotation.y, float(spec[3]), TOL_A)
			and _near(n.scale.x, float(spec[4]), 0.001),
			"燈籠 (%.2f, %.2f) rot %.2f sc %.2f" % [spec[1], spec[2], spec[3], spec[4]],
			"(%.2f, %.2f) rot %.2f sc %.2f"
				% [n.position.x - AXIS, n.position.z, n.rotation.y, n.scale.x])
	var r := _find(est, "門前燈籠_2")
	var l := _find(est, "門前燈籠_0")
	if r != null and l != null:
		# 疏密對比：右側燈籠緊挨狛犬、左側退遠 —— 兩側不可以等距
		var dr: float = Vector2(r.position.x - (AXIS + 4.7), r.position.z - 14.0).length()
		var dl: float = Vector2(l.position.x - (AXIS - 4.7), l.position.z - 14.0).length()
		_ok(absf(dr - dl) > 1.2, "兩側離狛犬的距離**不等**（疏密對比）",
			"右 %.2fm / 左 %.2fm" % [dr, dl])


# ── 4. 門前松：同樣是明表，不鏡射 ──
func _check_pine(est: Node) -> void:
	print("\n── 門前松（刻意不對稱）──")
	# ⚠ 比的是**縮放係數**不是絕對樹高。定案表寫的是 7.6m / 8.8m，但那是拿
	# make_hieda.py 的 `TREE_H0 = 8.0`（宣告的模組樹高）換算出來的係數
	# 0.95 / 1.10；hieda_pine_a.glb 實測只有 6.92m 高，所以獨立版自己長出來
	# 的門前松也是 6.6 / 7.6m，不是表上那兩個數。村院照抄係數＝跟定案版
	# 逐位元組同一棵樹；改抄絕對高度反而會跟獨立版對不上。
	# （TREE_H0 對不上實測資產是獨立版那邊的帳，記在誠實清單，不在這一輪動。）
	for spec in [[2, 9.90, 18.10, 0.9, 7.6 / 8.0], [0, -9.50, 18.40, 2.4, 8.8 / 8.0]]:
		var n := _find(est, "門前松_%d" % int(spec[0]))
		if n == null:
			_ok(false, "門前松_%d 存在" % int(spec[0]), "缺件")
			continue
		_ok(_near(n.position.x, AXIS + float(spec[1])) and _near(n.position.z, float(spec[2]))
			and _near(n.rotation.y, float(spec[3]), TOL_A),
			"松 (%.2f, %.2f) rot %.1f" % [spec[1], spec[2], spec[3]],
			"(%.2f, %.2f) rot %.2f" % [n.position.x - AXIS, n.position.z, n.rotation.y])
		_ok(_near(n.scale.x, float(spec[4]), 0.001),
			"縮放 %.3f（＝定案表的 %.1f / TREE_H0 8.0）" % [float(spec[4]), float(spec[4]) * 8.0],
			"%.3f　實高 %.2fm" % [n.scale.x, _box(n).size.y])


# ── 5. 棟門：柱高 3.30、柱厚 1.10、門洞半寬 3.6 ──
func _check_gate(est: Node) -> void:
	print("\n── 表門（棟門）──")
	var a := _find(est, "門柱_0")
	var b := _find(est, "門柱_2")
	if a == null or b == null:
		_ok(false, "門柱一對存在", "缺件")
		return
	var ba := _box(a)
	var bb := _box(b)
	_ok(_near(ba.position.x + ba.size.x, AXIS - 3.6) or _near(bb.position.x, AXIS + 3.6),
		"門洞半寬 3.60（6m 參道穿得過）",
		"內緣 %.2f / %.2f" % [ba.position.x + ba.size.x - AXIS, bb.position.x - AXIS])
	_ok(_near(ba.size.x, 0.70) and _near(ba.size.z, 1.10),
		"門柱斷面 0.70×1.10（厚過牆身 0.86 才露得出來）",
		"%.2f×%.2f" % [ba.size.x, ba.size.z])
	var top: float = ba.position.y + ba.size.y
	_ok(_near(top, 3.30, 0.05), "柱頂 3.30（收 8% 讓狛犬對得上量級）", "%.2f" % top)
	var beam := _find(est, "冠木")
	if beam != null:
		_ok(_near(_box(beam).size.x, 8.6, 0.05), "冠木跨距 8.60",
			"%.2f" % _box(beam).size.x)


# ── 6. 格子塀六層：石垣 0.72 → 漆喰 2.30 → 格子帶 3.10 → 冠木 → 瓦頂 3.50 ──
func _check_wall(est: Node) -> void:
	print("\n── 格子塀分層 ──")
	var st := _find(est, "石垣_南東")
	var pl := _find(est, "漆喰壁_南東")
	var la := _find(est, "格子底_南東")
	var kn := _find(est, "冠木_南東")
	var rg := _find(est, "棟瓦_南東")
	if st == null or pl == null or la == null:
		_ok(false, "格子塀分層構件存在", "缺件")
		return
	var bs := _box(st)
	_ok(_near(bs.position.y + bs.size.y, 0.72, 0.03), "腰石垣頂 0.72", "%.3f" % (bs.position.y + bs.size.y))
	_ok(_near(bs.size.z, 2.0 * 0.79, 0.03), "石垣腳寬 2×0.79（勾配下緣）", "%.3f" % bs.size.z)
	var bp := _box(pl)
	_ok(_near(bp.position.y, 0.72, 0.03) and _near(bp.position.y + bp.size.y, 2.30, 0.03),
		"白漆喰 0.72 → 2.30", "%.2f → %.2f" % [bp.position.y, bp.position.y + bp.size.y])
	_ok(_near(bp.size.z, 0.86, 0.02), "牆身厚 0.86", "%.3f" % bp.size.z)
	var bl := _box(la)
	_ok(_near(bl.position.y, 2.30, 0.03) and _near(bl.position.y + bl.size.y, 3.10, 0.03),
		"格子帶 2.30 → 3.10", "%.2f → %.2f" % [bl.position.y, bl.position.y + bl.size.y])
	_ok(_near(bl.size.z, 0.80, 0.02), "格子底板厚 0.80（比牆身薄，格柵才凸得出來）",
		"%.3f" % bl.size.z)
	if kn != null:
		_ok(_near(_box(kn).size.z, 1.00, 0.02), "冠木厚 1.00（壓在格子帶上出簷）",
			"%.3f" % _box(kn).size.z)
	if rg != null:
		var br := _box(rg)
		_ok(_near(br.position.y, 3.56, 0.05), "棟瓦底 3.56（瓦頂 3.50 上）", "%.2f" % br.position.y)
	# 格柵：MultiMesh，量間距與凸出量
	var mm := _find(est, "MM_格子") as MultiMeshInstance3D
	if mm == null:
		_ok(false, "MM_格子 存在", "缺件")
		return
	var m: MultiMesh = mm.multimesh
	var bm := m.mesh as BoxMesh
	_ok(_near(bm.size.x, 0.14) and _near(bm.size.z, 0.94),
		"格柵斷面 0.14×0.94（比底板 0.80 厚 → 兩側各凸 0.07）",
		"%.2f×%.2f" % [bm.size.x, bm.size.z])
	# 相鄰兩支的間距（同一段牆上）
	var xs: Array[float] = []
	var buf := m.buffer
	var stride := 16 if m.use_colors else 12
	for i in m.instance_count:
		var o := i * stride
		var px: float = buf[o + 3]
		var pz: float = buf[o + 11]
		if absf(pz - 21.5) < 0.01 and px > AXIS + 4.3:      # 南東段
			xs.append(px)
	xs.sort()
	var gaps := 0
	var bad := 0
	for i in range(1, xs.size()):
		gaps += 1
		if not _near(xs[i] - xs[i - 1], 0.42, 0.03):
			bad += 1
	_ok(gaps > 10 and bad == 0, "格柵間距 0.42（南東段 %d 支）" % xs.size(),
		"%d/%d 支間距不符" % [bad, gaps])


# ── 7. 犬走り：兩階碎石帶；貼牆那條的 albedo 必須 ≤0.15（比草地暗）──
func _check_apron(est: Node) -> void:
	print("\n── 犬走り＋接觸陰影 ──")
	var dk := _find(est, "犬走り_南東_00")
	var gv := _find(est, "犬走り_南東_01")
	if dk == null or gv == null:
		_ok(false, "犬走り兩階存在", "缺件")
		return
	_ok(_near(_box(dk).size.z, 0.34, 0.02), "接觸陰影帶寬 0.34", "%.3f" % _box(dk).size.z)
	_ok(_near(_box(gv).size.z, 1.00, 0.02), "外圈碎石帶寬 1.00", "%.3f" % _box(gv).size.z)
	var mat := ((dk as MeshInstance3D).mesh as BoxMesh).material as StandardMaterial3D
	var alb: float = mat.albedo_color.get_luminance() if mat != null else -1.0
	_ok(alb >= 0.0 and alb <= 0.155,
		"接觸陰影 albedo ≤0.15（草地 0.22；第一版 0.285 比草還亮，讀成混凝土路緣）",
		"%.3f" % alb)
	# 轉角不共面：南東段的犬走り從門柱外緣起，東段的往內縮同一個量
	var e := _find(est, "犬走り_東_01")
	if e != null:
		var be := _box(e)
		var bg := _box(gv)
		var overlap: bool = be.position.x < bg.position.x + bg.size.x \
			and bg.position.x < be.position.x + be.size.x \
			and be.position.z < bg.position.z + bg.size.z \
			and bg.position.z < be.position.z + be.size.z
		_ok(not overlap, "轉角兩道犬走り接齊、不共面重疊（重疊會互相擋光算成全黑）")


# ── 8. 參道：邊界筆直、固定目地、從門一路連到石階不斷開 ──
func _check_sando(est: Node) -> void:
	print("\n── 切石參道 ──")
	var slabs := []
	var stack: Array[Node] = [est]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.push_back(c)
		if n is MeshInstance3D and String(n.name).begins_with("參道石_"):
			slabs.append(n)
	if slabs.is_empty():
		_ok(false, "參道石板存在", "缺件")
		return
	var lo := INF
	var hi := -INF
	var xlo := INF
	var xhi := -INF
	for s in slabs:
		var b := _box(s)
		lo = minf(lo, b.position.z)
		hi = maxf(hi, b.position.z + b.size.z)
		xlo = minf(xlo, b.position.x)
		xhi = maxf(xhi, b.position.x + b.size.x)
	_ok(_near(xhi - xlo, 6.0, 0.15), "參道寬 6.00", "%.2f" % (xhi - xlo))
	_ok(_near((xlo + xhi) * 0.5, AXIS, 0.05), "參道置中於中軸", "%.2f" % ((xlo + xhi) * 0.5))
	_ok(lo < 0.6 and hi > 21.5, "從門線（+21.5）連到石階腳下（+0.35）不斷開",
		"z %.2f → %.2f" % [lo, hi])
	# 邊界筆直：所有石板的最外緣 x 只有兩個值（不是亂數侵蝕的鋸齒邊）
	var edge_bad := 0
	for s in slabs:
		var b := _box(s)
		if b.position.x < xlo + 0.01 and not _near(b.position.x, xlo, 0.01):
			edge_bad += 1
	_ok(edge_bad == 0, "邊界筆直（不是「與草地不規則交錯侵蝕」的野徑）")
	_ok(slabs.size() % 5 == 0, "橫向 5 塊（奇數 → 中軸上不會有連續的縱向目地）",
		"%d 塊" % slabs.size())


# ── 9. 唐破風玄関前廊（村版新增；主屋其餘部分不動）──
func _check_karahafu(est: Node) -> void:
	print("\n── 唐破風玄関前廊 ──")
	var roof := _find(est, "玄関屋面")
	var bd := _find(est, "玄関破風板")
	if roof == null or bd == null:
		_ok(false, "玄関屋面／破風板存在", "缺件")
		return
	var br := _box(roof)
	_ok(_near(br.size.x, 2.0 * 3.85, 0.1), "簷口半寬 3.85（牆面 3.35 → 外張）",
		"%.2f" % (br.size.x * 0.5))
	_ok(_near(br.position.y + br.size.y, 4.45, 0.08),
		"棟頂 4.45（上有裳階簷口 4.5 壓著，下有腰壁 1.76）",
		"%.2f" % (br.position.y + br.size.y))
	_ok(br.position.z + br.size.z > -0.70 and br.position.z + br.size.z < -0.55,
		"簷口伸出主屋正面 3.35m", "z=%.2f" % (br.position.z + br.size.z))
	# 五段石階：每階等高、頂階＝縁側面高 0.90
	var hs: Array[float] = []
	for i in 5:
		var s := _find(est, "玄関階_%d" % i)
		if s != null:
			var b := _box(s)
			hs.append(b.position.y + b.size.y)
	_ok(hs.size() == 5, "五段石階", "%d 段" % hs.size())
	if hs.size() == 5:
		hs.sort()
		_ok(_near(hs[4], 0.90, 0.03), "頂階＝縁側面高 0.90", "%.3f" % hs[4])
		var even := true
		for i in range(1, 5):
			if not _near(hs[i] - hs[i - 1], 0.18, 0.01):
				even = false
		_ok(even, "每階等高 0.18")
	# 高欄在玄関這一段要開口 —— 不開口就是做了一座走不上去的階梯
	var r0 := _find(est, "高欄_0")
	var r1 := _find(est, "高欄_1")
	if r0 != null and r1 != null:
		var b0 := _box(r0)
		var b1 := _box(r1)
		var gap: float = b1.position.x - (b0.position.x + b0.size.x)
		_ok(_near(gap, 5.8, 0.05), "高欄在玄関開口 5.80（＝2×2.9）", "%.2f" % gap)

extends SceneTree
## arch_spatial_lib.gd 單元測試（headless，合成資料，不讀正式場景）：
##   Phase 5 道路排列（弧形道路＝曲線局部切線、三種模式、侵入、退縮、立面線、Landmark 主軸）
##   Phase 7 節點比對（缺節點、多節點、縮放、負縮放遺失、無 CPU 資料、worst() 不把 UNKNOWN 當 PASS）
## godot --headless --path godot --script res://tools/test_arch_spatial_lib.gd   → 失敗 exit 1
const ARCH := preload("res://tools/arch_spatial_lib.gd")

var n_ok := 0
var n_bad := 0
var R := 50.0
var HW := 3.0


func _check(label: String, got: Variant, want: Variant, detail := "") -> void:
	var ok: bool = got == want
	if ok:
		n_ok += 1
	else:
		n_bad += 1
	print("%s %s: got %s want %s %s" % ["ok " if ok else "BAD", label, str(got), str(want), detail])


func _arc_lines() -> Array:
	var pts := PackedVector2Array()
	for k in 61:
		var a := deg_to_rad(3.0 * k)
		pts.append(Vector2(cos(a), sin(a)) * R)
	return [{"name": "Arc", "class": "main", "half_w": HW, "pts": pts},
		{"name": "Far", "class": "lane", "half_w": 1.0, "pts": PackedVector2Array([Vector2(500, 500), Vector2(520, 500)])}]


## 弧外側的建築：phi＝弧上角度，sb＝退縮（腳印到路緣），yaw_off＝正面相對「朝路」的偏轉，front_phi＝拿哪個角度的朝向
func _bld(phi_deg: float, sb := 2.0, yaw_off := 0.0, front_phi := NAN, w := 8.0, d := 6.0) -> Dictionary:
	var phi := deg_to_rad(phi_deg)
	var u := Vector2(cos(phi), sin(phi))
	var c := u * (R + HW + sb + d * 0.5)
	var fp := deg_to_rad(front_phi) if not is_nan(front_phi) else phi
	var front := (-Vector2(cos(fp), sin(fp))).rotated(deg_to_rad(yaw_off))
	var side := Vector2(-front.y, front.x)
	var poly := PackedVector2Array()
	for s in [[1, 1], [1, -1], [-1, -1], [-1, 1]]:
		poly.append(c + front * (d * 0.5 * s[0]) + side * (w * 0.5 * s[1]))
	return {"center": c, "front": front, "entrance": c + front * (d * 0.5), "poly": poly}


func _st(rows: Array, rid: String) -> String:
	for r: Dictionary in rows:
		if r["rule_id"] == rid:
			return r["status"]
	return "NONE"


func _row_of(rows: Array, rid: String) -> Dictionary:
	for r: Dictionary in rows:
		if r["rule_id"] == rid:
			return r
	return {}


func _initialize() -> void:
	var L := _arc_lines()
	# ── Structured
	var b := _bld(50.0)
	var rows := ARCH.road_alignment("t", L, b, {"mode": "structured", "setback": 2.0})
	_check("弧形路 structured 正對路 facing", _st(rows, "layout:facing"), "PASS", str(_row_of(rows, "layout:facing")["actual"]))
	_check("structured 入口", _st(rows, "layout:entrance_road"), "PASS")
	_check("structured 退縮 2.0 m", _st(rows, "layout:setback"), "PASS", str(_row_of(rows, "layout:setback")["actual"]))
	_check("structured 不侵路", _st(rows, "layout:road_intrusion"), "PASS")
	var b2 := _bld(50.0, 2.0, 0.0, 90.0)  # 用 90° 處的朝向放在 50° 處：直線段判斷會過、局部切線要抓到
	rows = ARCH.road_alignment("t", L, b2, {"mode": "structured"})
	_check("弧上別處的朝向（差 40°）structured FAIL", _st(rows, "layout:facing"), "FAIL", str(_row_of(rows, "layout:facing")["actual"]))
	_check("  修正建議給 yaw", _row_of(rows, "layout:facing")["fix"] != null, true, str(_row_of(rows, "layout:facing")["fix"]))
	rows = ARCH.road_alignment("t", L, _bld(50.0, 2.0, 180.0), {"mode": "structured"})
	_check("背對道路 → 入口 FAIL", _st(rows, "layout:entrance_road"), "FAIL", _row_of(rows, "layout:entrance_road")["suggestion"])
	rows = ARCH.road_alignment("t", L, _bld(50.0, -1.5), {"mode": "organic"})
	_check("腳印伸進路面 1.5 m → 侵入 FAIL（任何模式）", _st(rows, "layout:road_intrusion"), "FAIL",
		str(_row_of(rows, "layout:road_intrusion")["actual"]))
	rows = ARCH.road_alignment("t", L, _bld(50.0, 3.2), {"mode": "structured", "setback": 2.0})
	_check("退縮 3.2 vs 指定 2.0 → FAIL＋修正量", [_st(rows, "layout:setback"), _row_of(rows, "layout:setback")["fix"] != null], ["FAIL", true],
		str(_row_of(rows, "layout:setback")["actual"]))
	var nbs: Array = []
	for k in [[30.0, 2.0], [40.0, 2.1], [60.0, 1.9], [70.0, 2.0]]:
		nbs.append({"name": "nb%d" % int(k[0]), "poly": _bld(k[0], k[1])["poly"]})
	var b3 := _bld(50.0, 2.0)
	b3["neighbors"] = nbs
	rows = ARCH.road_alignment("t", L, b3, {"mode": "structured"})
	_check("立面線對齊鄰棟（中位 2.0）", _st(rows, "layout:facade_line"), "PASS", str(_row_of(rows, "layout:facade_line")["actual"]))
	var b4 := _bld(50.0, 3.5)
	b4["neighbors"] = nbs
	rows = ARCH.road_alignment("t", L, b4, {"mode": "structured"})
	_check("立面退後 1.5 m → FAIL", _st(rows, "layout:facade_line"), "FAIL", str(_row_of(rows, "layout:facade_line")["actual"]))
	rows = ARCH.road_alignment("t", L, _bld(50.0), {"mode": "structured"})
	_check("沒有鄰棟 → 立面線 UNKNOWN（不當 PASS）", _st(rows, "layout:facade_line"), "UNKNOWN")
	# ── Organic
	rows = ARCH.road_alignment("t", L, _bld(50.0, 2.0, 30.0), {"mode": "organic"})
	_check("organic 偏 30° → PASS", _st(rows, "layout:facing"), "PASS")
	rows = ARCH.road_alignment("t", L, _bld(50.0, 2.0, 60.0), {"mode": "organic"})
	_check("organic 偏 60° → WARN", _st(rows, "layout:facing"), "WARN")
	rows = ARCH.road_alignment("t", L, _bld(50.0, 2.0, 120.0), {"mode": "organic"})
	_check("organic 偏 120°（朝向軟約束）→ WARN 不是 FAIL", _st(rows, "layout:facing"), "WARN")
	rows = ARCH.road_alignment("t", L, _bld(50.0, 20.0), {"mode": "organic"})
	_check("organic 入口離路 20 m → FAIL", _st(rows, "layout:entrance_road"), "FAIL", _row_of(rows, "layout:entrance_road")["suggestion"])
	_check("organic 不檢查立面線", _st(rows, "layout:facade_line"), "NONE")
	# ── Landmark
	var lm := _bld(50.0, 10.0, 45.0)
	var tgt: Vector2 = (lm["center"] as Vector2) + (lm["front"] as Vector2) * 40.0
	rows = ARCH.road_alignment("t", L, lm, {"mode": "landmark", "axis_target": tgt})
	_check("landmark 主軸對準目標（正面不朝路也可）", _st(rows, "layout:landmark_axis"), "PASS")
	_check("landmark 不要求朝路（記錄）", _st(rows, "layout:facing"), "PASS", _row_of(rows, "layout:facing")["suggestion"])
	var off_t: Vector2 = (lm["center"] as Vector2) + (lm["front"] as Vector2).rotated(deg_to_rad(20.0)) * 40.0
	rows = ARCH.road_alignment("t", L, lm, {"mode": "landmark", "axis_target": off_t})
	_check("landmark 主軸偏 20° → FAIL", _st(rows, "layout:landmark_axis"), "FAIL", str(_row_of(rows, "layout:landmark_axis")["actual"]))
	rows = ARCH.road_alignment("t", L, lm, {"mode": "landmark"})
	_check("landmark 沒給主軸參考 → UNKNOWN", _st(rows, "layout:landmark_axis"), "UNKNOWN")
	_check("沒有道路資料 → UNKNOWN", _st(ARCH.road_alignment("t", [], b, {"mode": "organic"}), "layout:roads"), "UNKNOWN")
	# ── Phase 7 節點比對
	var ref := {"a": {"lo": Vector3(-1, 0, -1), "hi": Vector3(1, 2, 1), "xform": Transform3D.IDENTITY},
		"m": {"lo": Vector3(0, 0, 0), "hi": Vector3(1, 1, 1), "xform": Transform3D(Basis.from_scale(Vector3(-1, 1, 1)), Vector3.ZERO)}}
	var got := {"a": {"lo": Vector3(-1, 0, -1), "hi": Vector3(1, 2, 1), "xform": Transform3D.IDENTITY, "cpu_data": true},
		"m": {"lo": Vector3(0, 0, 0), "hi": Vector3(1, 1, 1), "xform": Transform3D(Basis.from_scale(Vector3(-1, 1, 1)), Vector3.ZERO), "cpu_data": true}}
	var cr := ARCH.compare_nodes("t", ref, got, "c")
	_check("一致 → 全 PASS", ARCH.summarize(cr)["PASS"], 2)
	var g2 := got.duplicate(true)
	g2.erase("m")
	g2["extra"] = got["a"]
	cr = ARCH.compare_nodes("t", ref, g2, "c")
	_check("缺節點 FAIL、多節點 WARN", [_st(cr, "c:m"), _st(cr, "c:extra")], ["FAIL", "WARN"])
	var g3 := got.duplicate(true)
	g3["a"]["xform"] = Transform3D(Basis.from_scale(Vector3(1.01, 1, 1)), Vector3.ZERO)
	g3["a"]["hi"] = Vector3(1.01, 2, 1)
	g3["m"]["xform"] = Transform3D.IDENTITY
	cr = ARCH.compare_nodes("t", ref, g3, "c")
	_check("縮放差 1% → FAIL", _st(cr, "c:a"), "FAIL", _row_of(cr, "c:a")["suggestion"])
	_check("負縮放遺失 → FAIL", _st(cr, "c:m"), "FAIL", _row_of(cr, "c:m")["suggestion"])
	var g4 := got.duplicate(true)
	g4["a"]["cpu_data"] = false
	cr = ARCH.compare_nodes("t", ref, g4, "c")
	_check("讀不到頂點 → UNKNOWN", _st(cr, "c:a"), "UNKNOWN")
	_check("worst(PASS+UNKNOWN) = UNKNOWN（不當 PASS）", ARCH.worst(cr), "UNKNOWN")
	var g5 := got.duplicate(true)
	g5["a"]["xform"] = Transform3D(Basis(Vector3.UP, deg_to_rad(0.2)), Vector3.ZERO)
	cr = ARCH.compare_nodes("t", ref, g5, "c")
	_check("旋轉差 0.2° → FAIL（atan2 精度）", _st(cr, "c:a"), "FAIL", str(_row_of(cr, "c:a")["actual"]))
	print("[ARCH-LIB-TEST] %d/%d ok" % [n_ok, n_ok + n_bad])
	quit(1 if n_bad else 0)

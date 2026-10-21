extends RefCounted
## 建築空間驗證：Godot 端共用庫（與 tools/blender/arch_spatial.py 同一份報告欄位）。
## 只放 Godot 才量得到的東西：GLB 原始資料 vs 匯入結果（Phase 7）、道路排列（Phase 5）。
## 幾何核心（接觸／穿插／支撐）在 Blender 端，不在這裡重寫。
## 用法：const ARCH := preload("res://tools/arch_spatial_lib.gd")；全部是 static func。

const TOOL := "arch_spatial_godot/1.0"


## 統一結果列（欄位同 Python 端 _row）。status：PASS / WARN / FAIL / UNKNOWN。
static func row(rule_id: String, type: String, building_id: String, object_ids: Array, status: String,
		expected: Variant, actual: Variant, deviation: Variant, tolerance: Variant, method: String,
		suggestion := "", evidence := {}, priority := "hard", fix: Variant = null) -> Dictionary:
	if status == "FAIL" and priority == "soft":
		status = "WARN"
	return {"rule_id": rule_id, "type": type, "building_id": building_id, "object_ids": object_ids,
		"status": status, "priority": priority, "severity": "high" if priority == "hard" else "low",
		"expected": expected, "actual": actual, "deviation": deviation, "tolerance": tolerance,
		"method": method, "suggestion": suggestion, "evidence": evidence, "fix": fix}


static func summarize(rows: Array) -> Dictionary:
	var s := {"PASS": 0, "WARN": 0, "FAIL": 0, "UNKNOWN": 0}
	for r: Dictionary in rows:
		s[r["status"]] = int(s.get(r["status"], 0)) + 1
	return s


## 多列合成一個快速通道檢查項：最差狀態勝出（UNKNOWN 不算 PASS：有 UNKNOWN 且沒有 FAIL → UNKNOWN）。
static func worst(rows: Array) -> String:
	var rank := {"FAIL": 3, "UNKNOWN": 2, "WARN": 1, "PASS": 0}
	var w := "PASS"
	for r: Dictionary in rows:
		if int(rank[r["status"]]) > int(rank[w]):
			w = r["status"]
	return w


# ───────────────────────── Phase 7：GLB 原始資料 vs 匯入結果 ─────────────────────────

## GLB 直接讀（GLTFDocument，CPU 端 ImporterMesh，headless 也可靠）。
## 回傳 {node_name: {original_name, index, xform, lo, hi, verts}}；node_name＝GLTFDocument 指派的唯一節點名
## （Godot 匯入器用同一套命名，所以能和匯入後的節點一對一對應）。
static func gltf_mesh_nodes(path: String) -> Dictionary:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var err := doc.append_from_file(path, st)
	if err != OK:
		return {"_error": "GLTFDocument 讀取失敗 err=%d" % err}
	var nodes: Array = st.get_nodes()
	var meshes: Array = st.get_meshes()
	var out := {}
	for i in nodes.size():
		var n: GLTFNode = nodes[i]
		if n.mesh < 0:
			continue
		var xf := Transform3D.IDENTITY
		var k := i
		while k >= 0:
			xf = (nodes[k] as GLTFNode).xform * xf
			k = (nodes[k] as GLTFNode).parent
		var im: ImporterMesh = (meshes[n.mesh] as GLTFMesh).mesh
		var lo := Vector3(INF, INF, INF)
		var hi := -lo
		var cnt := 0
		for s in im.get_surface_count():
			var verts: PackedVector3Array = im.get_surface_arrays(s)[Mesh.ARRAY_VERTEX]
			cnt += verts.size()
			for v in verts:
				var w := xf * v
				lo = lo.min(w)
				hi = hi.max(w)
		var nm := String(n.resource_name) if String(n.resource_name) != "" else n.original_name
		out[nm] = {"original_name": n.original_name, "index": i, "xform": xf, "lo": lo, "hi": hi, "verts": cnt}
	return out


## 匯入後的實例：每個 MeshInstance3D 相對 root 的 Transform 與「緊」AABB（頂點）。
## headless（dummy RenderingServer）讀不到網格頂點 → cpu_data=false，比對時回 UNKNOWN，不當 PASS。
static func scene_mesh_nodes(root: Node3D) -> Dictionary:
	var out := {}
	var list: Array = root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		list.append(root)
	for mi: MeshInstance3D in list:
		var xf := rel_xform(mi, root)
		var lo := Vector3(INF, INF, INF)
		var hi := -lo
		var faces := mi.mesh.get_faces() if mi.mesh else PackedVector3Array()
		for v in faces:
			var w := xf * v
			lo = lo.min(w)
			hi = hi.max(w)
		out[String(mi.name)] = {"path": String(root.get_path_to(mi)), "xform": xf, "lo": lo, "hi": hi,
			"cpu_data": faces.size() > 0}
	return out


static func rel_xform(n: Node3D, anc: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != anc:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


## Transform 拆解：每軸縮放（欄長）、行列式、旋轉（正交化；負縮放先翻一軸再取四元數）。
static func decompose(xf: Transform3D) -> Dictionary:
	var b := xf.basis
	var sc := Vector3(b.x.length(), b.y.length(), b.z.length())
	var det := b.determinant()
	var ob := b.orthonormalized()
	if det < 0.0:
		ob = Basis(-ob.x, ob.y, ob.z)
	return {"origin": xf.origin, "scale": sc, "det": det, "quat": ob.get_rotation_quaternion()}


static func _v(v: Vector3) -> Array:
	return [snappedf(v.x, 0.000001), snappedf(v.y, 0.000001), snappedf(v.z, 0.000001)]


## 逐節點比對 ref（期望）與 got（實得）。ref 缺節點 → FAIL MISSING_NODE（絕不因缺資料判 PASS）；
## got 多出節點 → WARN EXTRA_NODE。容差：位置／AABB 公尺（× max(1, 尺寸)）、旋轉度、縮放相對值。
static func compare_nodes(bid: String, ref: Dictionary, got: Dictionary, label: String,
		tol_pos := 0.001, tol_rot := 0.05, tol_scale := 0.0005, check_xform := true) -> Array:
	var rows: Array = []
	for nm: String in ref.keys():
		if nm.begins_with("_"):
			continue
		var r: Dictionary = ref[nm]
		var rid := "%s:%s" % [label, nm]
		if not got.has(nm):
			rows.append(row(rid, "IMPORT_CONSISTENCY", bid, [nm], "FAIL", "node present", "missing", null, null,
				label, "匯入結果找不到節點 %s（改名、被合併或被匯入設定丟掉）" % nm))
			continue
		var g: Dictionary = got[nm]
		if g.has("cpu_data") and not g["cpu_data"]:
			rows.append(row(rid, "IMPORT_CONSISTENCY", bid, [nm], "UNKNOWN", "mesh vertices", "no CPU mesh data",
				null, null, label, "讀不到頂點（headless 的 dummy RenderingServer）；需在有畫面的行程比對"))
			continue
		var size := maxf(1.0, ((r["hi"] as Vector3) - (r["lo"] as Vector3)).length())
		var tp := tol_pos * size
		var d_lo := ((g["lo"] as Vector3) - (r["lo"] as Vector3))
		var d_hi := ((g["hi"] as Vector3) - (r["hi"] as Vector3))
		var dev_aabb := maxf(absf(d_lo.x), maxf(absf(d_lo.y), maxf(absf(d_lo.z), maxf(absf(d_hi.x), maxf(absf(d_hi.y), absf(d_hi.z))))))
		var issues: Array = []
		var actual := {"aabb_dev_m": snappedf(dev_aabb, 0.000001)}
		if dev_aabb > tp:
			var rs := (r["hi"] as Vector3) - (r["lo"] as Vector3)
			var gs := (g["hi"] as Vector3) - (g["lo"] as Vector3)
			issues.append("幾何範圍差 %.4f m（尺寸 %s → %s）" % [dev_aabb, str(_v(rs)), str(_v(gs))])
			actual["size_ref"] = _v(rs)
			actual["size_got"] = _v(gs)
		if check_xform and r.has("xform") and g.has("xform"):
			var a := decompose(r["xform"])
			var b := decompose(g["xform"])
			var dp := ((a["origin"] as Vector3) - (b["origin"] as Vector3)).length()
			var sa: Vector3 = a["scale"]
			var sb: Vector3 = b["scale"]
			var ds := 0.0
			for ax in 3:
				ds = maxf(ds, absf(sa[ax] - sb[ax]) / maxf(absf(sa[ax]), 1e-9))
			var qd: Quaternion = (a["quat"] as Quaternion).inverse() * (b["quat"] as Quaternion)
			var dr := rad_to_deg(2.0 * atan2(Vector3(qd.x, qd.y, qd.z).length(), absf(qd.w)))  # atan2：小角度不受 acos 精度限制
			actual.merge({"origin_dev_m": snappedf(dp, 0.000001), "scale_dev_rel": snappedf(ds, 0.000001),
				"rot_dev_deg": snappedf(dr, 0.0001), "det_ref": snappedf(a["det"], 0.0001), "det_got": snappedf(b["det"], 0.0001)})
			if dp > tp:
				issues.append("原點差 %.4f m" % dp)
			if ds > tol_scale:
				issues.append("縮放差 %.3f%%（%s → %s）" % [ds * 100.0, str(_v(sa)), str(_v(sb))])
			if dr > tol_rot:
				issues.append("旋轉差 %.3f°" % dr)
			if signf(a["det"]) != signf(b["det"]):
				issues.append("負縮放（鏡像）遺失：det %.3f → %.3f" % [a["det"], b["det"]])
		rows.append(row(rid, "IMPORT_CONSISTENCY", bid, [nm], "FAIL" if not issues.is_empty() else "PASS",
			{"tol_pos_m": tp, "tol_rot_deg": tol_rot, "tol_scale_rel": tol_scale}, actual, dev_aabb, tp, label,
			"；".join(issues)))
	for nm: String in got.keys():
		if not ref.has(nm):
			rows.append(row("%s:%s" % [label, nm], "IMPORT_CONSISTENCY", bid, [nm], "WARN", "absent", "extra node",
				null, null, label, "匯入結果多出參考資料沒有的網格節點 %s" % nm, {}, "soft"))
	return rows


## Blender 端 arch_check.py --godot-expect 產出的 JSON → 與 gltf_mesh_nodes 同形狀（座標已換成 Godot）。
static func load_expect(path: String) -> Dictionary:
	var txt := FileAccess.get_file_as_string(path)
	var d: Variant = JSON.parse_string(txt)
	if not (d is Dictionary):
		return {"_error": "讀不到 expect JSON %s" % path}
	var out := {}
	var nodes: Dictionary = d.get("nodes", d)
	for nm: String in nodes.keys():
		if nm.begins_with("_"):
			continue
		var e: Dictionary = nodes[nm]
		var rec := {"lo": Vector3(e["min"][0], e["min"][1], e["min"][2]), "hi": Vector3(e["max"][0], e["max"][1], e["max"][2])}
		if e.has("xform"):
			var m: Array = e["xform"]  # 4x4 row-major（Godot 座標）
			rec["xform"] = Transform3D(Basis(Vector3(m[0][0], m[1][0], m[2][0]), Vector3(m[0][1], m[1][1], m[2][1]),
				Vector3(m[0][2], m[1][2], m[2][2])), Vector3(m[0][3], m[1][3], m[2][3]))
		out[nm.validate_node_name()] = rec
	if d.has("front_node"):
		out["_front_node"] = String(d["front_node"]).validate_node_name()
	return out


## 正面檢查：front_node 的中心必須在模型中心的 +Z 側（模型局部；快速通道約定正面＝+Z）。
static func front_check(bid: String, nodes: Dictionary, front_node: String, label: String) -> Dictionary:
	if not nodes.has(front_node):
		return row(label + ":front", "FRONT_AXIS", bid, [front_node], "FAIL", "front marker present", "missing", null, null,
			label, "正面標記節點 %s 不存在" % front_node)
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for nm: String in nodes.keys():
		if nm.begins_with("_") or nm == front_node:
			continue
		lo = lo.min(nodes[nm]["lo"])
		hi = hi.max(nodes[nm]["hi"])
	var c := (lo + hi) * 0.5
	var m: Vector3 = ((nodes[front_node]["lo"] as Vector3) + (nodes[front_node]["hi"] as Vector3)) * 0.5
	var d := m - c
	var flat := Vector2(d.x, d.z)
	var ang := rad_to_deg(absf(Vector2(0, 1).angle_to(flat))) if flat.length() > 1e-6 else 180.0
	var ok := ang <= 45.0
	return row(label + ":front", "FRONT_AXIS", bid, [front_node], "PASS" if ok else "FAIL", "marker on +Z side (≤45°)",
		{"angle_from_+Z_deg": snappedf(ang, 0.01)}, ang, 45.0, label,
		"" if ok else "正面標記不在 +Z 側（偏 %.1f°）：模型正面方向和快速通道約定（+Z）不一致" % ang)


# ───────────────────────── Phase 5：建築與道路排列 ─────────────────────────
## 參考線＝layout 的道路／巷道中心線（設計權威，凍結）；畫出來的路面蛇行被夾在原路寬內，所以「中心線＋half_w」包得住路面。
## 曲線道路：最近點的「局部切線」＝沿線 ±window 公尺兩點的方向（不是單一線段方向），彎道處才不會判錯。

const MODE_RULES := {
	# facing_pass／facing_warn：正面與「朝路法線」夾角（度）；facing_hard=false → 超過也只記 WARN
	"structured": {"facing_pass": 10.0, "facing_warn": 20.0, "facing_hard": true, "entrance_max": 6.0, "facade_tol": 1.0},
	"organic": {"facing_pass": 35.0, "facing_warn": 90.0, "facing_hard": false, "entrance_max": 15.0, "facade_tol": -1.0},
	"landmark": {"facing_pass": -1.0, "facing_warn": -1.0, "facing_hard": false, "entrance_max": -1.0, "facade_tol": -1.0,
		"axis_pass": 5.0, "axis_warn": 15.0, "axis_offset": 1.0},
}


static func road_lines(layout_path: String, include_lanes := true) -> Array:
	var txt := FileAccess.get_file_as_string(layout_path)
	var L: Variant = JSON.parse_string(txt)
	if not (L is Dictionary):
		return []
	var out: Array = []
	var groups: Array = [L.get("roads", [])]
	if include_lanes:
		groups.append(L.get("lanes", []))
	for g: Array in groups:
		for r: Dictionary in g:
			var pts := PackedVector2Array()
			for q in r["pts"]:
				pts.append(Vector2(float(q[0]), float(q[1])))
			out.append({"name": String(r["name"]), "class": String(r.get("class", "lane")), "half_w": float(r["half_w"]),
				"pts": pts})
	return out


## 折線最近點：回傳 {dist, q, s, seg}
static func _nearest_on(pts: PackedVector2Array, p: Vector2) -> Dictionary:
	var best := {"dist": INF}
	var s0 := 0.0
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var ab := b - a
		var L := ab.length()
		if L < 1e-6:
			continue
		var t := clampf((p - a).dot(ab) / (L * L), 0.0, 1.0)
		var q := a + ab * t
		var d := p.distance_to(q)
		if d < float(best["dist"]):
			best = {"dist": d, "q": q, "s": s0 + t * L, "seg": i}
		s0 += L
	return best


static func _point_at(pts: PackedVector2Array, s: float) -> Vector2:
	var s0 := 0.0
	for i in pts.size() - 1:
		var L := pts[i].distance_to(pts[i + 1])
		if s <= s0 + L or i == pts.size() - 2:
			return pts[i].lerp(pts[i + 1], clampf((s - s0) / maxf(L, 1e-6), 0.0, 1.0))
		s0 += L
	return pts[pts.size() - 1]


static func polyline_length(pts: PackedVector2Array) -> float:
	var s := 0.0
	for i in pts.size() - 1:
		s += pts[i].distance_to(pts[i + 1])
	return s


## 最近道路（所有線中最近）＋局部切線與「從 p 指向路」的法線。
static func nearest_road(lines: Array, p: Vector2, window := 6.0, only := "") -> Dictionary:
	var best := {}
	for ln: Dictionary in lines:
		if only != "" and ln["name"] != only:
			continue
		var nr := _nearest_on(ln["pts"], p)
		if nr.is_empty() or float(nr["dist"]) == INF:
			continue
		var edge := float(nr["dist"]) - float(ln["half_w"])
		if best.is_empty() or edge < float(best["edge_dist"]):
			var total := polyline_length(ln["pts"])
			var s := float(nr["s"])
			var t := (_point_at(ln["pts"], minf(total, s + window)) - _point_at(ln["pts"], maxf(0.0, s - window))).normalized()
			var n := Vector2(-t.y, t.x)
			if n.dot((nr["q"] as Vector2) - p) < 0.0:
				n = -n
			best = {"name": ln["name"], "class": ln["class"], "half_w": ln["half_w"], "dist": nr["dist"], "edge_dist": edge,
				"q": nr["q"], "s": s, "tangent": t, "normal_to_road": n, "length": total}
	return best


static func _angle(a: Vector2, b: Vector2) -> float:
	return rad_to_deg(absf(a.angle_to(b)))


## 腳印多邊形（XZ）沿邊每 step 取樣 → 對所有道路的最小「到路緣」距離（負值＝侵入路面）。
static func road_intrusion(lines: Array, poly: PackedVector2Array, step := 1.0) -> Dictionary:
	var worst := {"edge_dist": INF}
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var n := maxi(1, int(a.distance_to(b) / step))
		for k in n + 1:
			var p := a.lerp(b, float(k) / n)
			var nr := nearest_road(lines, p, 1.0)
			if not nr.is_empty() and float(nr["edge_dist"]) < float(worst["edge_dist"]):
				worst = nr.duplicate()
				worst["at"] = p
	return worst


## 腳印多邊形到某條路的路緣距離（最近的角點／邊點），用來量退縮與立面對齊。
static func setback(lines: Array, poly: PackedVector2Array, road: String) -> float:
	var m := INF
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var n := maxi(1, int(a.distance_to(b) / 0.5))
		for k in n + 1:
			var nr := nearest_road(lines, a.lerp(b, float(k) / n), 1.0, road)
			if not nr.is_empty():
				m = minf(m, float(nr["edge_dist"]))
	return m


## 第 4 項檢查：建築與道路排列。b = {center, front, entrance, poly, neighbors:[{name, poly}]}（全部 XZ、世界座標）。
## opts：mode、setback（structured 的指定退縮 m）、setback_tol、axis_target（Vector2，landmark）、sando（道路名，landmark）。
static func road_alignment(bid: String, lines: Array, b: Dictionary, opts: Dictionary) -> Array:
	var rows: Array = []
	var mode := String(opts.get("mode", "organic"))
	if not MODE_RULES.has(mode):
		return [row("layout:mode", "ROAD_ALIGNMENT", bid, [], "UNKNOWN", "structured|organic|landmark", mode, null, null,
			"-", "未知排列模式 %s" % mode)]
	var R: Dictionary = MODE_RULES[mode]
	if lines.is_empty():
		return [row("layout:roads", "ROAD_ALIGNMENT", bid, [], "UNKNOWN", "road centerlines", "none", null, null,
			"layout", "沒有道路參考線（layout 讀不到），無法判斷排列")]
	var front: Vector2 = (b["front"] as Vector2).normalized()
	var center: Vector2 = b["center"]
	var ent: Vector2 = b["entrance"]
	# 1) 侵入路面（所有模式）
	var intr := road_intrusion(lines, b["poly"])
	var ie := float(intr.get("edge_dist", INF))
	rows.append(row("layout:road_intrusion", "ROAD_ALIGNMENT", bid, [String(intr.get("name", ""))],
		"FAIL" if ie < -0.05 else "PASS", "footprint outside road (edge_dist ≥ -0.05 m)",
		{"min_edge_dist_m": snappedf(ie, 0.01), "road": intr.get("name", "")}, minf(0.0, ie), 0.05, "footprint_edge_samples→nearest_centerline",
		"" if ie >= -0.05 else "腳印伸進 %s 路面 %.2f m" % [intr.get("name", ""), -ie], {},
		"hard", null if ie >= -0.05 else {"translate_xz": ARCH_v2(-(intr["normal_to_road"] as Vector2) * (-ie + 0.1))}))
	# 2) 入口→最近道路
	var nr := nearest_road(lines, ent, float(opts.get("window", 6.0)))
	var ev := {"road": nr.get("name"), "road_class": nr.get("class"), "entrance_edge_dist_m": snappedf(float(nr["edge_dist"]), 0.01),
		"local_tangent": ARCH_v2(nr["tangent"]), "nearest_s_m": snappedf(float(nr["s"]), 0.1)}
	if mode != "landmark":
		var emax := float(R["entrance_max"])
		var ed := float(nr["edge_dist"])
		var ahead := front.dot((nr["q"] as Vector2) - ent)
		var st := "PASS"
		var msg := ""
		if ed > emax:
			st = "FAIL"
			msg = "入口離最近道路 %s 路緣 %.1f m > %.1f m" % [nr["name"], ed, emax]
		elif ahead < 0.0 and ed > 0.5:
			st = "FAIL"
			msg = "最近道路 %s 在入口背後（正面朝外）" % nr["name"]
		rows.append(row("layout:entrance_road", "ROAD_ALIGNMENT", bid, [String(nr["name"])], st,
			"entrance→road edge ≤ %.1f m, road ahead" % emax, ev, maxf(0.0, ed - emax), emax,
			"nearest_centerline(local_tangent ±%.0f m)" % float(opts.get("window", 6.0)), msg))
		# 3) 正面朝路（局部法線）
		var ang := _angle(front, nr["normal_to_road"])
		var st2 := "PASS" if ang <= float(R["facing_pass"]) else ("WARN" if ang <= float(R["facing_warn"]) else "FAIL")
		if st2 == "FAIL" and not bool(R["facing_hard"]):
			st2 = "WARN"
		var want := atan2((nr["normal_to_road"] as Vector2).x, (nr["normal_to_road"] as Vector2).y)
		rows.append(row("layout:facing", "ROAD_ALIGNMENT", bid, [String(nr["name"])], st2,
			"front vs road normal ≤ %.0f°（%s）" % [float(R["facing_pass"]), mode], {"angle_deg": snappedf(ang, 0.1)},
			ang, R["facing_pass"], "front·local_road_normal",
			"" if st2 == "PASS" else "正面與 %s 局部法線差 %.1f°" % [nr["name"], ang], {},
			"hard" if bool(R["facing_hard"]) else "soft",
			null if st2 == "PASS" else {"yaw_deg": snappedf(rad_to_deg(want), 0.1)}))
	# 4) Structured：指定退縮、立面對齊鄰棟、間距
	if mode == "structured":
		var sb := setback(lines, b["poly"], nr["name"])
		if opts.has("setback"):
			var tgt := float(opts["setback"])
			var tol := float(opts.get("setback_tol", 0.5))
			var dv := absf(sb - tgt)
			rows.append(row("layout:setback", "ROAD_ALIGNMENT", bid, [String(nr["name"])], "PASS" if dv <= tol else "FAIL",
				"setback %.2f ± %.2f m" % [tgt, tol], {"setback_m": snappedf(sb, 0.01)}, dv, tol, "footprint→road_edge",
				"" if dv <= tol else "退縮 %.2f m，指定 %.2f m" % [sb, tgt], {}, "hard",
				null if dv <= tol else {"translate_xz": ARCH_v2(-(nr["normal_to_road"] as Vector2) * (tgt - sb))}))
		var nb: Array = []
		for n: Dictionary in b.get("neighbors", []):
			var nn := nearest_road(lines, _centroid(n["poly"]), 6.0)
			if nn.is_empty() or nn["name"] != nr["name"]:
				continue
			# 同一側：鄰棟到路的法線方向一致
			if (nn["normal_to_road"] as Vector2).dot(nr["normal_to_road"]) < 0.5:
				continue
			nb.append({"name": n["name"], "setback": setback(lines, n["poly"], nr["name"]), "poly": n["poly"]})
		if nb.size() >= 2:
			var sbs: Array = nb.map(func(x): return float(x["setback"]))
			sbs.sort()
			var med := float(sbs[sbs.size() / 2])
			var dv2 := absf(sb - med)
			var ftol := float(R["facade_tol"])
			rows.append(row("layout:facade_line", "ROAD_ALIGNMENT", bid, nb.map(func(x): return x["name"]),
				"PASS" if dv2 <= ftol else "FAIL", "facade within %.1f m of neighbours' median setback" % ftol,
				{"setback_m": snappedf(sb, 0.01), "neighbours_median_m": snappedf(med, 0.01), "neighbours": nb.size()},
				dv2, ftol, "footprint→road_edge vs same-side neighbours",
				"" if dv2 <= ftol else "立面比同側鄰棟中位退縮差 %.2f m" % dv2, {}, "hard",
				null if dv2 <= ftol else {"translate_xz": ARCH_v2(-(nr["normal_to_road"] as Vector2) * (med - sb))}))
			var gaps: Array = []
			for x: Dictionary in nb:
				gaps.append(snappedf(poly_distance(b["poly"], x["poly"]), 0.01))
			gaps.sort()
			rows.append(row("layout:spacing", "ROAD_ALIGNMENT", bid, nb.map(func(x): return x["name"]),
				"WARN" if float(gaps[0]) < 0.3 else "PASS", "gap to same-side neighbours ≥ 0.3 m", {"gaps_m": gaps.slice(0, 4)},
				null, 0.3, "footprint polygon distance", "" if float(gaps[0]) >= 0.3 else "與鄰棟間距 %.2f m" % gaps[0], {}, "soft"))
		else:
			rows.append(row("layout:facade_line", "ROAD_ALIGNMENT", bid, [], "UNKNOWN", "≥2 same-side neighbours",
				{"neighbours": nb.size()}, null, null, "-", "同側鄰棟不足 2 棟，無法判斷立面對齊（不當 PASS）", {}, "soft"))
	# 5) Landmark：主軸對參道／目標點
	if mode == "landmark":
		var tgt_v: Variant = opts.get("axis_target")
		var sando := String(opts.get("sando", ""))
		var ax_t := Vector2.ZERO
		var have := false
		var ref_name := ""
		if sando != "":
			for ln: Dictionary in lines:
				if ln["name"] == sando:
					var pts: PackedVector2Array = ln["pts"]
					var e0 := pts[0]
					var e1 := pts[pts.size() - 1]
					ax_t = e0 if e0.distance_to(center) < e1.distance_to(center) else e1
					have = true
					ref_name = sando
		elif tgt_v is Vector2:
			ax_t = tgt_v
			have = true
			ref_name = "axis_target"
		if not have:
			rows.append(row("layout:landmark_axis", "ROAD_ALIGNMENT", bid, [], "UNKNOWN", "axis target or sando road",
				null, null, null, "-", "Landmark 模式需要 --axis-target=x,z 或 --sando=<道路名>（不猜主軸）"))
		else:
			var d := ax_t - center
			var ang := _angle(front, d)
			var off := absf(front.cross(d))
			var st3 := "PASS" if ang <= float(R["axis_pass"]) and off <= float(R["axis_offset"]) else (
				"WARN" if ang <= float(R["axis_warn"]) else "FAIL")
			rows.append(row("layout:landmark_axis", "ROAD_ALIGNMENT", bid, [ref_name], st3,
				"main axis → %s ≤ %.0f°, offset ≤ %.1f m" % [ref_name, float(R["axis_pass"]), float(R["axis_offset"])],
				{"angle_deg": snappedf(ang, 0.1), "axis_offset_m": snappedf(off, 0.01), "target": ARCH_v2(ax_t)}, ang,
				R["axis_pass"], "front vs (target − centre)",
				"" if st3 == "PASS" else "主軸偏 %.1f°、軸線偏移 %.2f m" % [ang, off], {}, "hard",
				null if st3 == "PASS" else {"yaw_deg": snappedf(rad_to_deg(atan2(d.x, d.y)), 0.1)}))
			if sando != "":
				var sn := nearest_road(lines, ent, 6.0, sando)
				var ed2 := float(sn.get("edge_dist", INF))
				rows.append(row("layout:sando_entrance", "ROAD_ALIGNMENT", bid, [sando], "PASS" if ed2 <= 3.0 else "FAIL",
					"entrance within 3 m of sando edge", {"edge_dist_m": snappedf(ed2, 0.01)}, maxf(0.0, ed2 - 3.0), 3.0,
					"nearest_centerline", "" if ed2 <= 3.0 else "入口離參道 %s %.1f m" % [sando, ed2]))
		rows.append(row("layout:facing", "ROAD_ALIGNMENT", bid, [String(nr["name"])], "PASS",
			"not required (landmark)", {"angle_to_nearest_road_normal_deg": snappedf(_angle(front, nr["normal_to_road"]), 0.1)},
			null, null, "info", "Landmark 不要求正面平行／垂直於附近道路（只記錄）", ev, "soft"))
	return rows


static func ARCH_v2(v: Vector2) -> Array:
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001)]


static func _centroid(poly: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for p in poly:
		c += p
	return c / maxf(1, poly.size())


static func poly_distance(a: PackedVector2Array, b: PackedVector2Array) -> float:
	if Geometry2D.intersect_polygons(a, b).size() > 0:
		return 0.0
	var m := INF
	for poly_pair in [[a, b], [b, a]]:
		var p: PackedVector2Array = poly_pair[0]
		var q: PackedVector2Array = poly_pair[1]
		for v in p:
			for i in q.size():
				var c := Geometry2D.get_closest_point_to_segment(v, q[i], q[(i + 1) % q.size()])
				m = minf(m, v.distance_to(c))
	return m


## 節點的 XZ 腳印：所有啟用中 CollisionShape3D 的局部框角點 → 世界 → 凸包（保留 yaw，不用世界 AABB）。
static func footprint_xz(n: Node3D) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var shapes: Array = n.find_children("*", "CollisionShape3D", true, false)
	for cs: CollisionShape3D in shapes:
		if cs.disabled or cs.shape == null:
			continue
		var bb := cs.shape.get_debug_mesh().get_aabb()
		for x in [bb.position.x, bb.end.x]:
			for z in [bb.position.z, bb.end.z]:
				var w := cs.global_transform * Vector3(x, bb.position.y, z)
				pts.append(Vector2(w.x, w.z))
	if pts.size() < 3:
		return PackedVector2Array()
	return Geometry2D.convex_hull(pts)

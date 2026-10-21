extends SceneTree
## 博麗神社 r3 擺放驗證（接地／穿插／石階側坡／樹木避讓／計數）。
##   godot --headless --path godot --script res://tools/shrine_v2/verify_placement.gd
## 讀 maps/shrine_v2/shrine_v2.tscn 的實際節點變換與網格頂點（不看 layout 常數），地面高度一律用 S2.height_at()
## （＝地形網格實際高度）。輸出 [PV] 行，最後 [PV] failures=N；exit code = failures。
## 判定門檻寫在各檢查旁；「資訊」行不計入 failures。

const S2 := preload("res://tools/shrine_v2/s2lib.gd")
const SCENE := "res://maps/shrine_v2/shrine_v2.tscn"

var failures := 0
var sroot: Node
var L: Dictionary


func check(label: String, ok: bool, detail := "") -> void:
	if not ok:
		failures += 1
	print("[PV] %s %s%s" % ["PASS" if ok else "FAIL", label, ("  — " + detail) if detail != "" else ""])


func info(msg: String) -> void:
	print("[PV] INFO ", msg)


func _init() -> void:
	_run.call_deferred()


func _meshes(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.find_children("*", "MeshInstance3D", true, false):
		out.append(c)
	return out


# 節點底部接觸：取該節點所有（非碰撞）網格的世界座標頂點，找最低點 ±tol 內的頂點，量它們與地面的高差。
func base_contact(n: Node3D, tol := 0.05) -> Dictionary:
	var verts: PackedVector3Array = PackedVector3Array()
	for mi: MeshInstance3D in _meshes(n):
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var xf := mi.global_transform
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var vv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			for v in vv:
				verts.append(xf * v)
	if verts.is_empty():
		return {}
	var lo := INF
	var hi := -INF
	for v in verts:
		lo = minf(lo, v.y)
		hi = maxf(hi, v.y)
	var gaps: Array = []
	for v in verts:
		if v.y <= lo + tol:
			gaps.append(v.y - S2.height_at(v.x, v.z))
	var gmax := -INF
	var gmin := INF
	var gsum := 0.0
	for g in gaps:
		gmax = maxf(gmax, g)
		gmin = minf(gmin, g)
		gsum += g
	return {"n": gaps.size(), "gap_max": gmax, "gap_min": gmin, "gap_mean": gsum / maxf(gaps.size(), 1), "y_lo": lo, "y_hi": hi}


func world_aabb(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi: MeshInstance3D in _meshes(n):
		if mi.mesh == null:
			continue
		var a := mi.global_transform * mi.mesh.get_aabb()
		out = a if first else out.merge(a)
		first = false
	return out


func _run() -> void:
	L = S2.load_layout()
	S2.load_height()
	var ps := load(SCENE) as PackedScene
	sroot = ps.instantiate()
	root.add_child(sroot)
	await process_frame

	# ── 1. 建築與境內物件接地 ──
	print("[PV] ── 1. 接地（最低 5 cm 內的頂點 vs 地形面；gap>0＝懸空、<0＝埋入）──")
	var targets := []
	var bg := sroot.get_node("建築")
	for c in bg.get_children():
		targets.append(c)
	var cg := sroot.get_node("境內物件")
	for c in cg.get_children():
		var nm := String(c.name)
		if nm.begins_with("燈籠") or nm.begins_with("狛犬") or nm == "陰陽玉台石":
			targets.append(c)
	for c in targets:
		if not (c is Node3D):
			continue
		var r := base_contact(c as Node3D)
		if r.is_empty():
			continue
		var nm := String(c.name)
		var ok: bool = r.gap_max < 0.12 and r.gap_min > -0.45
		# 拜殿／倉庫座落在平台，底面整片貼地；鳥居柱腳、燈籠只有數點落地
		check("接地 %-8s" % nm, ok, "底部頂點 %d 個，gap %.3f..%.3f（均 %.3f）m，底高 y=%.2f" % [r.n, r.gap_min, r.gap_max, r.gap_mean, r.y_lo])

	# ── 2. 實際尺寸（公尺）──
	print("[PV] ── 2. 世界尺寸（AABB，公尺）──")
	for nm in ["拜殿", "博麗鳥居", "手水舍", "倉庫", "賽錢箱"]:
		var n := bg.get_node_or_null(nm) as Node3D
		if n != null:
			var a := world_aabb(n)
			info("%-6s 寬 %.2f × 深 %.2f × 高 %.2f m；中心 (%.1f, %.1f)" % [nm, a.size.x, a.size.z, a.size.y, a.get_center().x, a.get_center().z])
	var tor := bg.get_node_or_null("博麗鳥居") as Node3D
	if tor != null:
		# 柱距＝最低頂點群的 x 範圍
		var verts_x: Array = []
		for mi: MeshInstance3D in tor.find_children("*", "MeshInstance3D", true, false):
			var xf := mi.global_transform
			var arr := mi.mesh.surface_get_arrays(0)
			var vv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var ymin := INF
			for v in vv:
				ymin = minf(ymin, (xf * v).y)
			for v in vv:
				var w := xf * v
				if w.y < ymin + 0.3:
					verts_x.append(w.x)
		if verts_x.size() > 0:
			var xs := PackedFloat64Array(verts_x)
			var mn := INF
			var mx := -INF
			for x in xs:
				mn = minf(mn, x)
				mx = maxf(mx, x)
			info("鳥居柱腳外緣 x = %.2f .. %.2f（外寬 %.2f m）" % [mn, mx, mx - mn])

	# ── 3. 石階：踏面與兩側坡 ──
	print("[PV] ── 3. 石階（踏石頂 vs 側坡地形）──")
	var gts := sroot.get_node("參道石階/踏石")
	var worst_wall := 0.0
	var best_up := 0.0
	var n_wall := 0
	var rows := 0
	for c in gts.get_children():
		var nm := String(c.name)
		if not nm.begins_with("踏石_") or not nm.ends_with("_L"):
			continue
		var mi := c as MeshInstance3D
		var top := (mi.global_transform * mi.mesh.get_aabb()).end.y
		var zc := mi.global_position.z
		rows += 1
		# 側坡：袖石外緣 x=±2.05 ~ ±3.2 的地形高 − 踏面高（<0＝地形比踏面低＝露出側牆；>0＝石階切進坡內）
		for sx in [-1.0, 1.0]:
			for off in [2.1, 2.6, 3.2]:
				var d: float = S2.height_at(sx * off, zc) - top
				worst_wall = maxf(worst_wall, -d)
				best_up = maxf(best_up, d)
				if -d > 0.55:
					n_wall += 1
	info("踏石 %d 列；側坡最低處比踏面低 %.2f m（>0.55 m 的取樣點 %d 個＝露出的側牆）；石階切進坡內最深 %.2f m" % [rows, worst_wall, n_wall, best_up])
	check("石階側牆不超過 0.55 m（無巨大垂直石牆）", n_wall == 0, "超標取樣點 %d；最大露出 %.2f m" % [n_wall, worst_wall])
	# 填塊底 vs 地形：中軸線上，填塊底面不得高於地形（不然踏石下露縫）
	var gf := sroot.get_node("參道石階/填塊")
	var fgap_max := -INF
	for c in gf.get_children():
		var fb := c as MeshInstance3D
		var bot := fb.global_position.y - 0.35
		var zc := fb.global_position.z
		for dx in [-1.4, 0.0, 1.4]:
			fgap_max = maxf(fgap_max, bot - S2.height_at(dx, zc))
	check("石階填塊底面不懸空（≤ 0.08 m）", fgap_max <= 0.08, "最大 %.3f m" % fgap_max)

	# ── 4. 樹木避讓 ──
	print("[PV] ── 4. 樹木 ──")
	var trees := sroot.get_node("樹木").get_children()
	var fps: Dictionary = {}
	for k in L["place"].keys():
		fps[k] = L["place"][k]
	var lay: Dictionary = L
	var bad_blds := []
	var bad_stair := 0
	var bad_pond := 0
	var bad_path := 0
	var crown_hits := []
	var pathg := sroot.get_node("鋪石")
	var path_pts: Array = []
	for c in pathg.get_children():
		path_pts.append(Vector2((c as Node3D).global_position.x, (c as Node3D).global_position.z))
	var bn := {}
	for nm in ["拜殿", "博麗鳥居", "手水舍", "倉庫"]:
		var n := bg.get_node_or_null(nm) as Node3D
		if n != null:
			bn[nm] = world_aabb(n)
	var pond: Dictionary = L["pond"]
	var th := deg_to_rad(float(pond["rot_deg"]))
	for t in trees:
		var tn := t as Node3D
		var p := tn.global_position
		for nm in bn.keys():
			var a: AABB = bn[nm]
			# 樹幹落點在建築 AABB 內（含 0.8 m 邊）
			if p.x > a.position.x - 0.8 and p.x < a.end.x + 0.8 and p.z > a.position.z - 0.8 and p.z < a.end.z + 0.8:
				bad_blds.append("%s@%s" % [tn.name, nm])
		if absf(p.x) < 3.0 and p.z > 3.0 and p.z < 34.5:
			bad_stair += 1
		var dx := p.x - float(pond["cx"])
		var dz := p.z - float(pond["cz"])
		var u := (dx * cos(th) + dz * sin(th)) / float(pond["rx"])
		var v := (-dx * sin(th) + dz * cos(th)) / float(pond["rz"])
		if sqrt(u * u + v * v) < 1.15:
			bad_pond += 1
		for q in path_pts:
			if q.distance_to(Vector2(p.x, p.z)) < 0.9:
				bad_path += 1
				break
		# 樹冠（網格世界 AABB）水平投影與建築 AABB 相交，且高度重疊 → 冠切屋面
		var ta := world_aabb(tn)
		for nm in bn.keys():
			var a: AABB = bn[nm]
			var cx := ta.get_center().x
			var cz := ta.get_center().z
			var cr := 0.5 * minf(ta.size.x, ta.size.z) * 0.8   # 冠半徑取 AABB 的 80%（冠不是方的）
			var nx := clampf(cx, a.position.x, a.end.x)
			var nz := clampf(cz, a.position.z, a.end.z)
			if Vector2(cx - nx, cz - nz).length() < cr and ta.end.y > a.position.y + a.size.y * 0.5 and ta.position.y < a.end.y:
				crown_hits.append("%s→%s" % [tn.name, nm])
	check("樹幹不在建築腳印內", bad_blds.is_empty(), "%d：%s" % [bad_blds.size(), str(bad_blds.slice(0, 4))])
	check("石階廊內無樹幹", bad_stair == 0, "%d 棵" % bad_stair)
	check("池水範圍內無樹幹", bad_pond == 0, "%d 棵" % bad_pond)
	check("石板上無樹幹", bad_path == 0, "%d 棵" % bad_path)
	check("樹冠不切入建築（樹冠半徑≈AABB 的 80%）", crown_hits.size() == 0, "%d：%s" % [crown_hits.size(), str(crown_hits.slice(0, 6))])
	var cnt := {}
	for t in trees:
		var id := String(t.name).rsplit("_", true, 1)[0]
		cnt[id] = int(cnt.get(id, 0)) + 1
	info("樹種數量 %s" % str(cnt))
	# 禁用樹源
	var banned := 0
	for t in trees:
		var f := String((t as Node3D).scene_file_path)
		if f.find("landscape") >= 0 or f.find("資產glb") >= 0 or f.find("_tripo") >= 0:
			banned += 1
	check("樹皆為 veg_kit（無 D:/資產glb 來源）", banned == 0, "違規 %d 棵" % banned)

	# ── 5. 岩石、石板落地 ──
	print("[PV] ── 5. 岩石與鋪石 ──")
	var rg := sroot.get_node("岩石")
	var rock_bad := 0
	var rock_lines := []
	for c in rg.get_children():
		var r := base_contact(c as Node3D, 0.12)
		if r.is_empty():
			continue
		if r.gap_max > 0.10:
			rock_bad += 1
			rock_lines.append("%s gap %.2f" % [c.name, r.gap_max])
	check("岩石底部不懸空（≤ 0.10 m）", rock_bad == 0, "%d/%d：%s" % [rock_bad, rg.get_child_count(), str(rock_lines.slice(0, 4))])
	var flo := 0
	var floline := []
	for c in pathg.get_children():
		var r := base_contact(c as Node3D, 0.03)
		if r.is_empty():
			continue
		if r.gap_max > 0.12:
			flo += 1
			floline.append("%s %.2f" % [c.name, r.gap_max])
	check("鋪石底面不懸空（≤ 0.12 m）", flo == 0, "%d/%d：%s" % [flo, pathg.get_child_count(), str(floline.slice(0, 4))])
	# 鋪石頂面不被地形蓋住：腳印 9 點（內縮 10%）的地面高度不得高過石頂 2 cm 以上
	var bury_bad := 0
	var bury_line := []
	var bury_max := 0.0
	for c in pathg.get_children():
		var wa2 := world_aabb(c as Node3D)
		var top_y := wa2.end.y
		var worst := -INF
		for ox in [-0.9, 0.0, 0.9]:
			for oz in [-0.9, 0.0, 0.9]:
				var px: float = wa2.get_center().x + float(ox) * wa2.size.x * 0.5
				var pz: float = wa2.get_center().z + float(oz) * wa2.size.z * 0.5
				worst = maxf(worst, S2.height_at(px, pz) - top_y)
		bury_max = maxf(bury_max, worst)
		if worst > 0.02:
			bury_bad += 1
			bury_line.append("%s %.3f" % [c.name, worst])
	check("鋪石頂面不被地形蓋住（≤ 2 cm）", bury_bad == 0, "%d/%d：%s；最大 %.3f m" % [bury_bad, pathg.get_child_count(), str(bury_line.slice(0, 4)), bury_max])

	# ── 6. 池塘 ──
	print("[PV] ── 6. 池塘 ──")
	var water := sroot.get_node_or_null("池塘水面") as MeshInstance3D
	if water != null:
		var wa := world_aabb(water)
		var level := wa.position.y + wa.size.y * 0.5
		# 水面三角形內的地形：是否有地形高過水面（水面被土蓋住）／岸線坡度
		var arr := water.mesh.surface_get_arrays(0)
		var vv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var above := 0
		var deep := 0.0
		var edge_slope := []
		for v in vv:
			var gh := S2.height_at(v.x, v.z)
			if gh > level + 0.02:
				above += 1
			deep = maxf(deep, level - gh)
		info("水面頂點 %d 個；水位 y=%.2f；最深 %.2f m；高於水面的地形頂點 %d" % [vv.size(), level, deep, above])
		# 岸線：沿 24 條放射線，找地形與水位的交點，量交點處坡度（不應近乎水平）
		var cx := float(pond["cx"])
		var cz := float(pond["cz"])
		var n_flat := 0
		var slopes := []
		for k in 24:
			var a := TAU * k / 24.0
			var dir := Vector2(cos(a), sin(a))
			var prev := S2.height_at(cx, cz) - level
			var found := false
			var r := 0.2
			while r < 16.0:
				var px := cx + dir.x * r
				var pz := cz + dir.y * r
				var cur := S2.height_at(px, pz) - level
				if prev < 0.0 and cur >= 0.0:
					var sl := (cur - prev) / 0.1
					slopes.append(sl)
					if sl < 0.12:
						n_flat += 1
					found = true
					break
				prev = cur
				r += 0.1
			if not found:
				slopes.append(-1.0)
		var lines := []
		for s in slopes:
			lines.append("%.2f" % s)
		info("24 向岸線交點坡度（m/m；-1＝未穿越水位）%s" % [", ".join(lines)])
		check("岸線交點坡度 ≥ 0.12（不是水平淺灘）", n_flat == 0, "水平岸線方向 %d/24" % n_flat)
		check("池水範圍內地形不高於水面（水面不被土蓋住）", above <= 3, "高於水面的水面頂點 %d" % above)

	# ── 7. 計數 ──
	print("[PV] ── 7. 場景計數 ──")
	var n_nodes := 0
	var n_mi := 0
	var tris := 0
	var uniq := {}
	var stack: Array[Node] = [sroot]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		n_nodes += 1
		for c in n.get_children():
			stack.push_back(c)
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null and (n as Node3D).is_visible_in_tree():
			n_mi += 1
			var m := (n as MeshInstance3D).mesh
			uniq[m.get_instance_id()] = true
			for s in m.get_surface_count():
				var arr := m.surface_get_arrays(s)
				var idx = arr[Mesh.ARRAY_INDEX]
				tris += (idx.size() if idx != null else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	info("節點 %d；可見 MeshInstance3D %d（獨立 mesh %d）；全部實例三角面（含 LOD0 全量、未剔除）%.2f M" % [n_nodes, n_mi, uniq.size(), tris / 1.0e6])
	print("[PV] failures=%d" % failures)
	quit(failures)

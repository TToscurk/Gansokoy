extends SceneTree
## P10 R6b Shrine Approach Pilot gate（回歸 tag SAN）。使用者 2026-10-09 D6（端景 Pilot、MXC_018 不動不刪）／D7（視覺石段＋斜坡碰撞）。
##   plan＋反向（headless，含物理射線）：Godot --headless --path . --script res://tools/verify_village_v2_shrine_approach.gd
##   build（headless 可）：… -- --build
##   attach：… -- --attach        （village_v2.tscn 加 root/ShrineApproachP10，WaterLifeP10 之後）
##   scene（非 headless）：… -- --scene
## plan：
##   1 石段：段數 ≥ 80；蹴上 0.12–0.20、踏面 0.25–0.45（古い社の男坂相當）；緩坡石疊坡度 < 16°
##   2 地形不蓋踏面：每段踏面頂 ≥ 段內 P1 地形最高（容差 0.01）
##   3 斜坡碰撞 vs 踏面：段內每點 |碰撞面 − 踏面| ≤ 半個蹴上 + 0.03（腳底不浮不陷超過半段）
##   4 斜坡碰撞連續：起終點與 P1 地形差 ≤ 0.03、最大坡度 ≤ 38°（玩家 floor_max 52°）
##   5 寬度：石段＋袖石半寬 ≤ 參道半寬 2.5；穿過二の鳥居處 ≤ 柱內淨半寬 1.89 − 0.05
##   6 一の鳥居：柱台離丘腳街／主街中心線 ≥ 半寬 + 0.3；柱台不撞既有碰撞體；在主街第 5 段軸心延長線左右 ≤ 6 m（端景）
##   7 石燈籠：坐在坂に据えた水平基壇（頂＝四角最高＋0.06、底＝最低 −0.15、高 ≤ 1.0）、不撞既有碰撞體、沿路間隔 16–24 m（20 m ±1.5 找平地）
##   8 NPC：Population 的 NPC 不在石段範圍內、離鳥居柱台 ≥ 1.2 m；巡回 NPC 的 path_xz 不貼鳥居柱、不橫切石段（D7 NPC 通行；不搬 NPC）
const LIB := preload("res://tools/village_v2_shrine_approach_lib.gd")
const SCENE := "res://maps/village_v2/village_v2.tscn"
const EXT_ID := "p10r6b_shrine_approach"
const AFTER_NODE := "[node name=\"WaterLifeP10\" parent=\".\" instance=ExtResource(\"p10r5b_water_life\")]"
var fails := 0
var quiet := false
var V: Node3D
var excl: Array[RID] = []


func _ok(c: bool, msg: String) -> bool:
	if not quiet:
		print("[SAN] ", "PASS " if c else "FAIL ", msg)
	if not c:
		fails += 1
	return c


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if "--attach" in args:
		quit(_attach())
		return
	V = (load(SCENE) as PackedScene).instantiate()
	root.add_child(V)
	await process_frame
	await physics_frame
	await physics_frame
	if "--scene" in args:
		await _scene()
		print("[SAN] 結果：%d 項失敗" % fails)
		quit(fails)
		return
	var old := V.get_node_or_null(LIB.NODE_NAME)
	if old:
		for b in old.find_children("*", "CollisionObject3D", true, false):
			excl.append((b as CollisionObject3D).get_rid())
		if old is CollisionObject3D:
			excl.append((old as CollisionObject3D).get_rid())
	var cl := LIB.centerline()
	var H := LIB.ramp_profile(V, cl)
	var st := LIB.steps(cl, H)
	var rp := LIB.ramp_points(st, H)
	print("[SAN] plan 中心線 %.1f m、石段 %d（step %d／slab %d）、斜坡點 %d" % [cl.size() * 0.05, st.size(), st.filter(func(a): return a["kind"] == "step").size(), st.filter(func(a): return a["kind"] == "slab").size(), rp.size()])
	var cfg := {"tread_dy": 0.0, "ramp_dy": 0.0, "riser_mul": 1.0, "torii_s": LIB.TORII1_S, "step_w": LIB.STEP_W, "lantern_dy": 0.0}
	_gates(cl, H, st, rp, cfg)
	if "--build" in args:
		_build(cl, H)
	else:
		_negatives(cl, H, st, rp)
	print("[SAN] 結果：%d 項失敗" % fails)
	quit(fails)


func _ray_y(p: Vector2) -> float:
	var sp := V.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 80.0, p.y), Vector3(p.x, -30.0, p.y))
	q.exclude = excl
	var h := sp.intersect_ray(q)
	return NAN if h.is_empty() else float(h["position"].y)


func _hits(xf: Transform3D, size: Vector3, skip_terrain := true) -> Array:
	var sp := V.get_world_3d().direct_space_state
	var bs := BoxShape3D.new()
	bs.size = size
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = bs
	q.transform = xf
	q.exclude = excl
	var out := []
	for r in sp.intersect_shape(q, 16):
		var nm := String(V.get_path_to(r["collider"])) if r["collider"] is Node and V.is_ancestor_of(r["collider"]) else str(r["collider"])
		if skip_terrain and nm.contains("TerrainCollision"):
			continue
		out.append(nm)
	return out


static func _seg_d(p: Vector2, pts: Array) -> float:
	var best := INF
	for i in pts.size() - 1:
		var a := Vector2(pts[i][0], pts[i][1])
		var b := Vector2(pts[i + 1][0], pts[i + 1][1])
		var t := clampf((p - a).dot(b - a) / (b - a).length_squared(), 0.0, 1.0)
		best = minf(best, p.distance_to(a.lerp(b, t)))
	return best


func _ramp_at(rp: Array, k: int, dy: float) -> float:
	for i in rp.size() - 1:
		var ka := int(rp[i][0])
		var kb := int(rp[i + 1][0])
		if k >= ka and k <= kb and kb > ka:
			return lerpf(float(rp[i][1]), float(rp[i + 1][1]), float(k - ka) / float(kb - ka)) + dy
	return NAN


func _gates(cl: PackedVector2Array, H: PackedFloat32Array, st: Array, rp: Array, cfg: Dictionary) -> void:
	# 1 石段尺寸
	var nstep := 0
	var rmin := INF
	var rmax := 0.0
	var tmin := INF
	var tmax := 0.0
	var slab_bad := 0
	var prev_y := NAN
	var y0_ref := float(st[0]["y0"]) if not st.is_empty() else 0.0
	for a: Dictionary in st:
		var y := y0_ref + (float(a["y0"]) - y0_ref) * float(cfg["riser_mul"])
		if String(a["kind"]) == "step":
			nstep += 1
			var tr := (int(a["k1"]) - int(a["k0"])) * 0.05
			tmin = minf(tmin, tr)
			tmax = maxf(tmax, tr)
			if not is_nan(prev_y):
				var r := y - prev_y
				rmin = minf(rmin, r)
				rmax = maxf(rmax, r)
			prev_y = y
		else:
			var sl := rad_to_deg(atan2(float(a["y1"]) - float(a["y0"]), (int(a["k1"]) - int(a["k0"])) * 0.05))
			if sl >= LIB.SLOPE_MIN_DEG + 2.0:
				slab_bad += 1
			prev_y = NAN
	_ok(nstep >= 80 and rmin >= LIB.RISER[0] - 0.005 and rmax <= LIB.RISER[1] + 0.005 and tmin >= LIB.TREAD[0] - 0.001 and tmax <= LIB.TREAD[1] + 0.001 and slab_bad == 0,
		"石段 %d 段：蹴上 %.3f–%.3f m（%.2f–%.2f）、踏面 %.2f–%.2f m（%.2f–%.2f）、緩坡石疊超坡 %d" % [nstep, rmin, rmax, LIB.RISER[0], LIB.RISER[1], tmin, tmax, LIB.TREAD[0], LIB.TREAD[1], slab_bad])
	# 2 地形不蓋踏面
	var buried := 0
	for a: Dictionary in st:
		if String(a["kind"]) != "step":
			continue
		var hm := -INF
		for k in range(int(a["k0"]), int(a["k1"]) + 1):
			hm = maxf(hm, H[k])
		if float(a["y0"]) + float(cfg["tread_dy"]) < hm - 0.01:
			buried += 1
	_ok(buried == 0, "踏面全在 P1 地形之上（被地形蓋住的段 %d）" % buried)
	# 3 斜坡碰撞 vs 踏面
	var dev := 0.0
	var dev_bad := 0
	var rr := float(LIB.RISER[1])
	for a: Dictionary in st:
		if String(a["kind"]) != "step":
			continue
		for k in range(int(a["k0"]), int(a["k1"]) + 1):
			var rc := _ramp_at(rp, k, float(cfg["ramp_dy"]))
			if is_nan(rc):
				continue
			var d := absf(rc - (float(a["y0"]) + float(cfg["tread_dy"])))
			dev = maxf(dev, d)
			if d > rr * 0.5 + 0.03:
				dev_bad += 1
	_ok(dev_bad == 0, "斜坡碰撞與踏面最大差 %.3f m（≤ 半蹴上 %.3f + 0.03）" % [dev, rr * 0.5])
	# 4 斜坡碰撞連續
	var k_a := int(rp[0][0])
	var k_b := int(rp[rp.size() - 1][0])
	var e0 := absf(float(rp[0][1]) + float(cfg["ramp_dy"]) - H[k_a])
	var e1 := absf(float(rp[rp.size() - 1][1]) + float(cfg["ramp_dy"]) - H[k_b])
	var smax := 0.0
	for i in rp.size() - 1:
		var dk := int(rp[i + 1][0]) - int(rp[i][0])
		if dk > 0:
			smax = maxf(smax, rad_to_deg(atan2(absf(float(rp[i + 1][1]) - float(rp[i][1])), dk * 0.05)))
	_ok(e0 <= 0.03 and e1 <= 0.03 and smax <= 38.0, "斜坡碰撞：起點／終點與地形差 %.3f／%.3f m、最大坡度 %.1f°" % [e0, e1, smax])
	# 5 寬度
	var half := float(cfg["step_w"]) * 0.5 + LIB.CURB_W
	var kt := 0
	var bd := INF
	for k in cl.size():
		var d := cl[k].distance_to(LIB.HILL_TORII)
		if d < bd:
			bd = d
			kt = k
	var covered := false
	for a: Dictionary in st:
		if kt >= int(a["k0"]) - 20 and kt <= int(a["k1"]) + 20:
			covered = true
	_ok(half <= LIB.SANDO_HW and (not covered or half <= 1.89 - 0.05), "石段＋袖石半寬 %.2f m（參道 %.1f；二の鳥居柱內淨半寬 1.89%s）" % [half, LIB.SANDO_HW, "，石段穿過鳥居" if covered else ""])
	# 6 一の鳥居
	var txf := LIB.torii1_xf(cl, H, float(cfg["torii_s"]))
	var lat := txf.basis.x.normalized()
	var bad6 := []
	for sd in [-1.0, 1.0]:
		var pc: Vector3 = txf.origin + lat * 2.25 * float(sd)
		var p2: Vector2 = Vector2(pc.x, pc.z)
		for rn in LIB.OTHER_ROADS:
			var d := _seg_d(p2, LIB.OTHER_ROADS[rn])
			if d < float(LIB.OTHER_HW[rn]) + 0.36 + 0.3:
				bad6.append("柱 %+d 離 %s %.2f m" % [int(sd), rn, d])
		var hh := _hits(Transform3D(txf.basis, pc + Vector3(0, 0.6, 0)), Vector3(0.72, 1.0, 0.72))
		if not hh.is_empty():
			bad6.append("柱 %+d 撞 %s" % [int(sd), str(hh)])
	var ms := LIB.OTHER_ROADS["MainStreet"]
	var a5 := Vector2(ms[1][0], ms[1][1])
	var b5 := Vector2(ms[2][0], ms[2][1])
	var dir5 := (b5 - a5).normalized()
	var to_t := Vector2(txf.origin.x, txf.origin.z) - b5
	var axis_lat := absf(to_t.dot(Vector2(-dir5.y, dir5.x)))
	_ok(bad6.is_empty() and axis_lat <= 6.0, "一の鳥居（s %.1f m）：柱台離丘腳街／主街 ≥ 半寬 + 0.66、不撞既有碰撞、離主街軸心延長線 %.2f m（≤ 6）%s" % [float(cfg["torii_s"]), axis_lat, "" if bad6.is_empty() else " ✗ " + str(bad6)])
	# 7 石燈籠
	var ls := LIB.lantern_specs(cl, H, st, V.get_world_3d().direct_space_state)
	var bad7 := []
	var ss := []
	for l: Dictionary in ls:
		var p: Vector2 = l["p"]
		var g2 := LIB.lantern_ground(V.get_world_3d().direct_space_state, p)
		var gmin := float(g2[0])
		var gmax := float(g2[1])
		var top := gmax + LIB.PLINTH_UP + float(cfg["lantern_dy"])
		var g := gmax
		# 基壇：頂＝四角最高＋0.06（不浮空）、底＝四角最低 −0.15（埋入）、高 ≤ 0.9 m；燈籠坐在基壇頂
		if gmin == INF or top - (gmax + LIB.PLINTH_UP) > 0.001 or (gmax + LIB.PLINTH_UP) - (gmin - 0.15) > 1.0:
			bad7.append("基壇 頂 %.2f／四角 %.2f–%.2f" % [top, gmin, gmax])
		var hh := _hits(Transform3D(Basis(), Vector3(p.x, g + 1.0, p.y)), Vector3(0.6, 1.6, 0.6))
		if not hh.is_empty():
			bad7.append("撞 %s" % str(hh))
		ss.append(float(l["s"]))
	var gaps_ok := true
	for i in range(2, ss.size(), 2):
		var gp := float(ss[i]) - float(ss[i - 2])
		if gp < 16.0 or gp > 24.0:
			gaps_ok = false
	_ok(ls.size() >= 4 and bad7.is_empty() and gaps_ok, "石燈籠 %d 基（%d 對）：坐在水平基壇（高 ≤ 1.0 m）、不撞、間隔 16–24 m（約 20 m 節奏，±1.5 m 找平地）%s" % [ls.size(), ls.size() / 2, "" if bad7.is_empty() else " ✗ " + str(bad7.slice(0, 4))])
	# 8 NPC
	var bad8 := []
	var n_patrol := 0
	var pop := V.get_node_or_null("Population")
	if pop:
		for b in pop.find_children("*", "AnimatableBody3D", true, false):
			var np := Vector2((b as Node3D).global_position.x, (b as Node3D).global_position.z)
			for sd in [-1.0, 1.0]:
				var pc: Vector3 = txf.origin + lat * 2.25 * float(sd)
				if np.distance_to(Vector2(pc.x, pc.z)) < 1.2:
					bad8.append("%s 貼鳥居柱" % b.name)
			var kk := 0
			var dd := INF
			for k in range(0, cl.size(), 4):
				var d := cl[k].distance_to(np)
				if d < dd:
					dd = d
					kk = k
			if dd <= half + 0.3:
				for a: Dictionary in st:
					if kk >= int(a["k0"]) and kk <= int(a["k1"]):
						bad8.append("%s 在石段上" % b.name)
						break
			# 巡回 NPC：path_xz の各区間が一の鳥居柱台から ≥ 1.2 m、石段中心線から ≥ 半寬＋0.3（巡回路を横切らない）
			if "path_xz" in b:
				var px: PackedVector2Array = b.get("path_xz")
				if px.size() >= 2:
					n_patrol += 1
					for i2 in px.size() - 1:
						for sd in [-1.0, 1.0]:
							var pc2: Vector3 = txf.origin + lat * 2.25 * float(sd)
							var q2 := Geometry2D.get_closest_point_to_segment(Vector2(pc2.x, pc2.z), px[i2], px[i2 + 1])
							if q2.distance_to(Vector2(pc2.x, pc2.z)) < 1.2:
								bad8.append("%s 巡回路貼鳥居柱" % b.name)
						for a: Dictionary in st:
							for k in range(int(a["k0"]), int(a["k1"]) + 1, 10):
								var q3 := Geometry2D.get_closest_point_to_segment(cl[k], px[i2], px[i2 + 1])
								if q3.distance_to(cl[k]) < half + 0.3:
									bad8.append("%s 巡回路橫切石段" % b.name)
									break
	_ok(bad8.is_empty() and n_patrol > 0, "NPC：初期位置不在石段、離鳥居柱 ≥ 1.2 m；巡回 %d 條的路徑不貼鳥居柱、不橫切石段（NPC 不搬）%s" % [n_patrol, "" if bad8.is_empty() else " ✗ " + str(bad8)])


func _negatives(cl: PackedVector2Array, H: PackedFloat32Array, st: Array, rp: Array) -> void:
	print("[SAN] 永久反向（每案必須讓 gate 失敗）")
	var base := {"tread_dy": 0.0, "ramp_dy": 0.0, "riser_mul": 1.0, "torii_s": LIB.TORII1_S, "step_w": LIB.STEP_W, "lantern_dy": 0.0}
	var cases := []
	var c1 := base.duplicate()
	c1["riser_mul"] = 1.5
	cases.append(["N1 蹴上 ×1.5（0.25 m 級，不是參道石段）", c1])
	var c2 := base.duplicate()
	c2["tread_dy"] = -0.12
	cases.append(["N2 踏面壓低 0.12 m（被地形蓋住）", c2])
	var c3 := base.duplicate()
	c3["ramp_dy"] = 0.30
	cases.append(["N3 斜坡碰撞抬高 0.30 m（腳浮在踏面上）", c3])
	var c4 := base.duplicate()
	c4["torii_s"] = 1.0
	cases.append(["N4 一の鳥居立在路口（柱台壓丘腳街）", c4])
	var c5 := base.duplicate()
	c5["step_w"] = 4.6
	cases.append(["N5 石段寬 4.6 m（超出參道、擠二の鳥居）", c5])
	var c6 := base.duplicate()
	c6["lantern_dy"] = 0.4
	cases.append(["N6 石燈籠浮空 0.4 m", c6])
	var neg_fail := 0
	for c in cases:
		var f0 := fails
		quiet = true
		_gates(cl, H, st, rp, c[1])
		quiet = false
		var tripped := fails > f0
		fails = f0
		print("[SAN]   %s：%s" % [c[0], "PASS（gate 正確失敗）" if tripped else "FAIL（gate 沒抓到）"])
		if not tripped:
			neg_fail += 1
	_ok(neg_fail == 0, "反向 %d/%d" % [cases.size() - neg_fail, cases.size()])


func _build(cl: PackedVector2Array, H: PackedFloat32Array) -> void:
	if fails > 0:
		_ok(false, "plan gate 未過，不 build")
		return
	var n := LIB.build(V, cl, H)
	for c in n.find_children("*", "", true, false):
		if c.owner == null:
			c.owner = n
	var ps := PackedScene.new()
	_ok(ps.pack(n) == OK, "pack")
	_ok(ResourceSaver.save(ps, LIB.OUTPUT) == OK, "save %s" % LIB.OUTPUT)
	var rb := (ResourceLoader.load(LIB.OUTPUT, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	_ok(rb.get_node_or_null("StoneSteps") != null and rb.get_node_or_null("IchiNoTorii") != null and rb.get_node_or_null("RampCollision/Ramp") != null, "回讀：石段／一の鳥居／斜坡碰撞")
	print("[SAN] build {\"steps\":%d,\"lanterns\":%d,\"cut_s\":%s,\"output_sha256\":\"%s\"}" % [int(rb.get_node("StoneSteps").get_meta("steps", 0)), rb.get_node("Lanterns").get_child_count(), str(rb.get("cut_s")), FileAccess.get_sha256(LIB.OUTPUT)])
	rb.free()
	n.free()


func _scene() -> void:
	var nodes := V.find_children(LIB.NODE_NAME, "", false, false)
	_ok(nodes.size() == 1, "root/%s 掛載 1 個（實得 %d）" % [LIB.NODE_NAME, nodes.size()])
	if nodes.is_empty():
		return
	var n := nodes[0] as Node3D
	var wl := V.get_node_or_null("WaterLifeP10")
	_ok(wl != null and wl.get_index() == n.get_index() - 1, "順序：WaterLifeP10 之後（index %d）" % n.get_index())
	for i in 4:
		await process_frame
	await physics_frame
	var rib := V.get_node(LIB.RIBBON) as MeshInstance3D
	var m := rib.material_override as ShaderMaterial
	var cs: Vector2 = n.get("cut_s")
	_ok(bool(n.get("swapped")) and m != null and m.shader.resource_path.ends_with("ground_p10_pilot.gdshader") and (m.get_shader_parameter("cut_s") as Vector2).is_equal_approx(cs) and cs.y > cs.x,
		"參道 ribbon 換 pilot shader、石段範圍挖洞 cut_s %s、cut_hw %.2f" % [str(cs), float(n.get("cut_hw"))])
	# 斜坡碰撞實測：踏面中點往下打，第一擊＝RampCollision
	var cl := LIB.centerline()
	var sp := V.get_world_3d().direct_space_state
	var hit_ok := 0
	var hit_bad := 0
	for k in range(int(LIB.TORII1_S / 0.05) + 900, cl.size() - 60, 40):
		var q := PhysicsRayQueryParameters3D.create(Vector3(cl[k].x, 80.0, cl[k].y), Vector3(cl[k].x, -20.0, cl[k].y))
		var h := sp.intersect_ray(q)
		if h.is_empty():
			continue
		var path := String(V.get_path_to(h["collider"]))
		if path.begins_with(LIB.NODE_NAME + "/RampCollision") or path.contains("TerrainCollision"):
			hit_ok += 1
		else:
			hit_bad += 1
	_ok(hit_ok > 10 and hit_bad == 0, "參道中心線往下射線：斜坡碰撞／地形 %d、其他 %d" % [hit_ok, hit_bad])
	n.set("enabled", false)
	var all_off := true
	for c in n.find_children("*", "CollisionShape3D", true, false):
		if not (c as CollisionShape3D).disabled:
			all_off = false
	_ok(not bool(n.get("swapped")) and rib.material_override != m and all_off, "enabled=false → ribbon 還原、碰撞全停")
	n.set("enabled", true)
	_ok(bool(n.get("swapped")), "enabled=true → 重新套用")


func _attach() -> int:
	var txt := FileAccess.get_file_as_string(SCENE)
	if not FileAccess.file_exists(LIB.OUTPUT):
		push_error("找不到 %s（先 --build）" % LIB.OUTPUT)
		return 1
	var line := "[node name=\"%s\" parent=\".\" instance=ExtResource(\"%s\")]" % [LIB.NODE_NAME, EXT_ID]
	if txt.contains(line):
		print("[SAN] attach：已掛（不重複、不寫場景）")
		return 0
	var nl := "\r\n" if txt.contains("\r\n") else "\n"
	var lines := txt.split(nl)
	var out := PackedStringArray(Array(lines))
	var at := out.find(AFTER_NODE)
	if at < 0:
		push_error("找不到 root/WaterLifeP10")
		return 1
	if at + 1 < out.size() and out[at + 1].strip_edges() != "":
		push_error("WaterLifeP10 節點後面不是空行，拒絕文字插入")
		return 1
	out.insert(at + 1, "")
	out.insert(at + 2, line)
	var last_ext := -1
	for k in out.size():
		if out[k].begins_with("[ext_resource"):
			last_ext = k
	out.insert(last_ext + 1, "[ext_resource type=\"PackedScene\" path=\"%s\" id=\"%s\"]" % [LIB.OUTPUT, EXT_ID])
	var f := FileAccess.open(SCENE, FileAccess.WRITE)
	f.store_string(nl.join(out))
	f.close()
	print("[SAN] attach：加 root/%s（WaterLifeP10 之後）→ %s（+%d 行）" % [LIB.NODE_NAME, SCENE, out.size() - lines.size()])
	return 0

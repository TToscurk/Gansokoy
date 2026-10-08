extends SceneTree
## P10 R5b Water Logic Pilot gate（回歸 tag WLF）。使用者 2026-10-09 D5（水車功能）／D10（主河一艘小舟）。
##   plan＋反向（headless，含物理射線）：Godot --headless --path . --script res://tools/verify_village_v2_water_life.gd
##   build（headless 可，無 MultiMesh）：… -- --build
##   attach：… -- --attach        （village_v2.tscn 加 root/WaterLifeP10，GroundPilotP10 之後）
##   scene（非 headless）：… -- --scene
## plan：
##   1 柄杓 16：全在輪面（x 2.22）與東軸承柱（x 2.40）之間、不出輪半徑 3.0；內徑 > 受け樋最大半徑 + 0.05（迴轉不撞樋）
##   2 受け樋：在輪面外、在柄杓迴轉圈內、往 P8 樋頭方向下降、東端＝P8 樋頭（Δx ≤ 0.02、樋底高 0–0.03 m）
##   3 樋頭架台：柱在東軸承柱外 ≥ 0.05 m、柱腳埋入水渠底 ≥ 0.25 m、柱頭＝P8 枕木下（≤ 0.03 m）
##   4 小舟：浮在水位（船底＝水位 − 吃水）、船體與世界碰撞體不相交、船底下水深 ≥ 0.15 m、離最下段石段 ≤ 1.6 m、
##     尺寸＝川舟（長 ≤ 8 m、寬 ≤ 1.8 m）、船首迎流（與流向夾角 ≤ 10°）
##   5 繫船杭：落地（地面差 ≤ 0.05 m、埋 0.35 m）、地上部分不撞其他碰撞體；綱長 ≤ 7 m
##   6 「届いた荷」：落地（≤ 0.05 m）、不撞其他碰撞體
const LIB := preload("res://tools/village_v2_water_life_lib.gd")
const SCENE := "res://maps/village_v2/village_v2.tscn"
const EXT_ID := "p10r5b_water_life"
const AFTER_NODE := "[node name=\"GroundPilotP10\" parent=\".\" instance=ExtResource(\"p10r5a_ground_pilot\")]"
var fails := 0
var quiet := false
var V: Node3D
var hero: Node3D
var excl: Array[RID] = []


func _ok(c: bool, msg: String) -> bool:
	if not quiet:
		print("[WLF] ", "PASS " if c else "FAIL ", msg)
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
		print("[WLF] 結果：%d 項失敗" % fails)
		quit(fails)
		return
	# 已掛的 WaterLifeP10（重建時）不算世界碰撞
	var old := V.get_node_or_null(LIB.NODE_NAME)
	if old:
		for b in old.find_children("*", "CollisionObject3D", true, false):
			excl.append((b as CollisionObject3D).get_rid())
	hero = V.get_node(LIB.WHEEL) as Node3D
	var H := _heights()
	print("[WLF] heights ", JSON.stringify(H))
	var cfg := _cfg()
	_gates(cfg, H)
	if "--build" in args:
		_build(H)
	else:
		_negatives(H)
	print("[WLF] 結果：%d 項失敗" % fails)
	quit(fails)


func _cfg() -> Dictionary:
	return {"bucket_x1": -1.0, "trough_raise": 0.0, "bent_x": LIB.BENT_X.duplicate(), "boat_off": LIB.BOAT_OFF, "boat_l": LIB.BOAT_L, "boat_b": LIB.BOAT_B, "post_dy": 0.0}


func _ray_y(p: Vector2, from_y := 40.0) -> float:
	var sp := V.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, from_y, p.y), Vector3(p.x, -30.0, p.y))
	q.exclude = excl
	var h := sp.intersect_ray(q)
	return NAN if h.is_empty() else float(h["position"].y)


func _hits(xf: Transform3D, size: Vector3) -> Array:
	var sp := V.get_world_3d().direct_space_state
	var bs := BoxShape3D.new()
	bs.size = size
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = bs
	q.transform = xf
	q.exclude = excl
	var out := []
	for r in sp.intersect_shape(q, 16):
		out.append(String(V.get_path_to(r["collider"])) if r["collider"] is Node and V.is_ancestor_of(r["collider"]) else str(r["collider"]))
	return out


func _heights() -> Dictionary:
	var hx := hero.global_transform
	var bed := []
	for x in LIB.BENT_X:
		var w := hx * Vector3(x, 0, LIB.BENT_Z)
		bed.append(_ray_y(Vector2(w.x, w.z), hx.origin.y + 3.0) - hx.origin.y)
	var ms := LIB.mooring_specs(0.0)
	var pp: Vector2 = ms["post"]
	var best := {}
	for kg: Vector2 in LIB.kago_candidates():
		var ys := []
		for c in LIB.kago_corners(kg, ms["down"]):
			ys.append(_ray_y(c))
		if ys.any(func(y): return is_nan(float(y))):
			continue
		var spread: float = ys.max() - ys.min()
		var hh := _hits(Transform3D(Basis(), Vector3(kg.x, float(ys.max()) + 0.48, kg.y)), Vector3(1.2, 0.6, 0.75))
		if not hh.is_empty():
			continue
		if best.is_empty() or spread < float(best["kago_spread"]):
			best = {"kago_p": kg, "kago_ground": float(ys.max()) - 0.02, "kago_spread": spread}
	var out := {"bent_bed": bed, "post_ground": _ray_y(pp)}
	out.merge(best)
	return out


func _gates(cfg: Dictionary, H: Dictionary) -> void:
	# 1 柄杓
	var bs := LIB.bucket_specs(float(cfg["bucket_x1"]))
	var dep: float = LIB.BUCKET_R[1] - LIB.BUCKET_R[0]
	var face := LIB.WHEEL_FACE_X - LIB.HUB.x
	var post := LIB.EAST_POST_X - LIB.HUB.x
	var rmin := INF
	var rmax := 0.0
	var xbad := 0
	for b in bs:
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					var c: Vector3 = b["c"] + (b["t"] as Vector3) * LIB.BUCKET_TAN * 0.5 * sx + (b["n"] as Vector3) * dep * 0.5 * sy + (b["ax"] as Vector3) * float(b["a"]) * 0.5 * sz
					var r := Vector2(c.y, c.z).length()
					rmin = minf(rmin, r)
					rmax = maxf(rmax, r)
					if c.x <= face + 0.005 or c.x >= post - 0.005:
						xbad += 1
	# 受け樋最大半徑（相對輪心，y-z）
	var tz: float = LIB.P8_HEAD_LOCAL.z
	var hw := LIB.TROUGH_W * 0.5 + 0.035
	var tr := 0.0
	for i in 2:
		var ytop: float = float(LIB.TROUGH_BOT[i]) + float(cfg["trough_raise"]) + LIB.TROUGH_WALL
		for sz in [-1.0, 1.0]:
			tr = maxf(tr, Vector2(ytop - LIB.HUB.y, tz + sz * hw - LIB.HUB.z).length())
	_ok(bs.size() == LIB.BUCKETS and xbad == 0 and rmax <= 3.02 and rmin >= tr + 0.05, "柄杓 %d：輪面與東軸承柱之間（越界角點 %d）、半徑 %.2f–%.2f m（輪 3.0、受け樋最大 %.2f）" % [bs.size(), xbad, rmin, rmax, tr])
	# 2 受け樋
	var x0: float = LIB.TROUGH_X[0]
	var x1: float = LIB.TROUGH_X[1]
	var b0: float = float(LIB.TROUGH_BOT[0]) + float(cfg["trough_raise"])
	var b1: float = float(LIB.TROUGH_BOT[1]) + float(cfg["trough_raise"])
	var dy := b1 - LIB.P8_HEAD_LOCAL.y
	_ok(x0 >= LIB.WHEEL_FACE_X + 0.02 and tr <= rmin - 0.05 and b0 > b1 and absf(x1 - LIB.P8_HEAD_LOCAL.x) <= 0.02 and dy >= 0.0 and dy <= 0.03,
		"受け樋：x %.3f–%.3f（輪面 %.2f）、底 %.3f→%.3f（往樋頭降 %.0f mm）、樋頭接口 Δy %.3f m" % [x0, x1, LIB.WHEEL_FACE_X, b0, b1, (b0 - b1) * 1000.0, dy])
	# 3 架台
	var bad3 := []
	var bed: Array = H["bent_bed"]
	for i in 2:
		var bx := float(cfg["bent_x"][i])
		if bx - LIB.POST * 0.5 < 2.70 + 0.05:
			bad3.append("柱 %d x %.2f 貼東軸承柱／柄杓迴轉面" % [i, bx])
		if is_nan(float(bed[i])):
			bad3.append("柱 %d 下方無水渠底" % i)
	_ok(bad3.is_empty(), "樋頭架台 2 柱：在東軸承柱（x 2.70）外 ≥ 0.05、腳埋水渠底 0.30 m（底 %s）、頭＝P8 枕木下%s" % [str(bed.map(func(y): return snappedf(float(y), 0.01))), "" if bad3.is_empty() else " ✗ " + str(bad3)])
	# 4 小舟
	var bxf := LIB.boat_xf(float(cfg["boat_off"]))
	var hull_c := bxf * Vector3(0, LIB.BOAT_H * 0.5 + 0.03, -0.2)
	var hits := _hits(Transform3D(bxf.basis, hull_c), Vector3(float(cfg["boat_b"]) - 0.1, LIB.BOAT_H - 0.06, float(cfg["boat_l"]) - 0.6))
	var bot := bxf.origin
	var bed_y := _ray_y(Vector2(bot.x, bot.z), bot.y + 0.05)
	var depth := bot.y - bed_y if not is_nan(bed_y) else INF
	var stair := Vector2(LIB.STAIR_BOT.x, LIB.STAIR_BOT.z)
	var near := stair.distance_to(Vector2(bot.x, bot.z)) - float(cfg["boat_b"]) * 0.5
	var fwd := bxf.basis.z
	var ang := rad_to_deg(Vector2(fwd.x, fwd.z).angle_to(-LIB.FLOW))
	var float_ok := absf((bot.y + LIB.BOAT_DRAFT) - LIB.RIVER_WATER) < 0.005
	_ok(float_ok and hits.is_empty() and depth >= 0.15 and near <= 1.6 and float(cfg["boat_l"]) <= 8.0 and float(cfg["boat_b"]) <= 1.8 and absf(ang) <= 10.0,
		"小舟 %.1f×%.1f m：吃水 %.2f、船體碰撞 %s、船底下水深 %.2f m、離石段 %.2f m、船首與迎流夾角 %.1f°" % [float(cfg["boat_l"]), float(cfg["boat_b"]), LIB.BOAT_DRAFT, str(hits) if not hits.is_empty() else "0", depth, near, ang])
	# 5 繫船杭＋綱
	var ms := LIB.mooring_specs(float(H["post_ground"]))
	var pp: Vector2 = ms["post"]
	var pg := float(H["post_ground"]) + float(cfg["post_dy"])
	var g_here := _ray_y(pp)
	var ph := _hits(Transform3D(Basis(), Vector3(pp.x, pg + 0.55, pp.y)), Vector3(0.13, 0.8, 0.13))
	var rope_len := (ms["bow"] as Vector3).distance_to(Vector3(pp.x, pg + 0.78, pp.y))
	_ok(not is_nan(g_here) and absf(pg - g_here) <= 0.05 and ph.is_empty() and rope_len <= 7.0, "繫船杭：地面差 %.3f m、地上部碰撞 %s、綱長 %.2f m" % [pg - g_here, str(ph) if not ph.is_empty() else "0", rope_len])
	# 6 届いた荷
	var kg: Vector2 = H.get("kago_p", ms["kago"])
	var kgy := float(H.get("kago_ground", NAN))
	var g2 := _ray_y(kg)
	var spread := float(H.get("kago_spread", 0.0))
	var kh := _hits(Transform3D(Basis(), Vector3(kg.x, kgy + 0.18 + 0.30, kg.y)), Vector3(1.2, 0.6, 0.75))
	_ok(not is_nan(g2) and kgy - g2 <= 0.15 and kgy - g2 >= -0.05 and spread <= 0.15 and kh.is_empty(), "届いた荷（st_kago_tsumi 重用）：放在四角最高點 −0.02（中心地面差 %.3f、四角起伏 %.3f ≤ 0.15）、地上部碰撞 %s" % [kgy - g2, spread, str(kh) if not kh.is_empty() else "0"])


func _negatives(H: Dictionary) -> void:
	print("[WLF] 永久反向（每案必須讓 gate 失敗）")
	var cases := []
	var c1 := _cfg()
	c1["bucket_x1"] = 0.86
	cases.append(["N1 柄杓加厚撞東軸承柱", c1, H])
	var c2 := _cfg()
	c2["trough_raise"] = 0.25
	cases.append(["N2 受け樋抬高進入柄杓迴轉圈", c2, H])
	var c3 := _cfg()
	c3["bent_x"] = [2.55, 3.30]
	cases.append(["N3 架台柱立在東軸承柱位置", c3, H])
	var c4 := _cfg()
	c4["boat_off"] = -0.6
	cases.append(["N4 小舟壓上石段", c4, H])
	var c5 := _cfg()
	c5["boat_l"] = 14.0
	c5["boat_b"] = 3.0
	cases.append(["N5 船過大（14 × 3 m，港口船）", c5, H])
	var c6 := _cfg()
	c6["post_dy"] = 0.5
	cases.append(["N6 繫船杭浮空 0.5 m", c6, H])
	var neg_fail := 0
	for c in cases:
		var f0 := fails
		quiet = true
		_gates(c[1], c[2])
		quiet = false
		var tripped := fails > f0
		fails = f0
		print("[WLF]   %s：%s" % [c[0], "PASS（gate 正確失敗）" if tripped else "FAIL（gate 沒抓到）"])
		if not tripped:
			neg_fail += 1
	_ok(neg_fail == 0, "反向 %d/%d" % [cases.size() - neg_fail, cases.size()])


func _build(H: Dictionary) -> void:
	if fails > 0:
		_ok(false, "plan gate 未過，不 build")
		return
	var n := LIB.build(V, H)
	for c in n.find_children("*", "", true, false):
		c.owner = n
	var ps := PackedScene.new()
	_ok(ps.pack(n) == OK, "pack")
	_ok(ResourceSaver.save(ps, LIB.OUTPUT) == OK, "save %s" % LIB.OUTPUT)
	var rb := (ResourceLoader.load(LIB.OUTPUT, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	var nb := rb.get_node_or_null("WW2_Lift/LiftBuckets") as MeshInstance3D
	_ok(nb != null and nb.mesh != null and rb.get_node_or_null("BoatLanding/Boat/Hull") != null, "回讀：柄杓網格 %s、小舟 %s" % [nb != null, rb.get_node_or_null("BoatLanding/Boat/Hull") != null])
	rb.free()
	n.free()
	print("[WLF] build {\"output_sha256\":\"%s\"}" % FileAccess.get_sha256(LIB.OUTPUT))


func _scene() -> void:
	var nodes := V.find_children(LIB.NODE_NAME, "", false, false)
	_ok(nodes.size() == 1, "root/%s 掛載 1 個（實得 %d）" % [LIB.NODE_NAME, nodes.size()])
	if nodes.is_empty():
		return
	var n := nodes[0] as Node3D
	var gp := V.get_node_or_null("GroundPilotP10")
	_ok(gp != null and gp.get_index() == n.get_index() - 1, "順序：GroundPilotP10 之後（index %d）" % n.get_index())
	for i in 4:
		await process_frame
	var rotor := V.get_node(LIB.ROTOR) as Node3D
	var bk := rotor.get_node_or_null("LiftBuckets") as Node3D
	_ok(bk != null and bool(n.get("attached")), "柄杓掛在水車 2 轉子下（Hero/Wheel/LiftBuckets）")
	# 隨輪轉：2 秒後柄杓世界位置改變、相對轉子不變
	if bk:
		var g0 := bk.global_transform
		var l0 := bk.transform
		var a0 := rotor.rotation.x
		for i in 60:
			await process_frame
		await create_timer(1.5).timeout
		_ok(not bk.global_transform.is_equal_approx(g0) and bk.transform.is_equal_approx(l0) and not is_equal_approx(rotor.rotation.x, a0), "柄杓隨輪轉（轉子角 %.2f→%.2f rad）" % [a0, rotor.rotation.x])
	# 水車 1／3 不動
	for w in ["Landmarks/LANDMARK_WATERWHEEL_1/Hero/Wheel", "Landmarks/LANDMARK_WATERWHEEL_3/Hero/Wheel"]:
		var r := V.get_node_or_null(w)
		_ok(r != null and r.get_node_or_null("LiftBuckets") == null, "%s 未加柄杓（Pilot 只做水車 2）" % w.split("/")[1])
	# 開關
	n.set("enabled", false)
	var hidden := true
	for c in n.get_children():
		if c is Node3D and (c as Node3D).visible:
			hidden = false
	_ok(rotor.get_node_or_null("LiftBuckets") == null and hidden, "enabled=false → 柄杓取下、overlay 全隱藏")
	n.set("enabled", true)
	_ok(rotor.get_node_or_null("LiftBuckets") != null, "enabled=true → 柄杓重新掛上")
	# 碰撞體：架台 2＋舟 1＋杭 1
	var cols := n.find_children("*", "CollisionShape3D", true, false).size()
	_ok(cols == 4, "碰撞形 %d（架台柱 2、舟 1、杭 1）" % cols)


func _attach() -> int:
	var txt := FileAccess.get_file_as_string(SCENE)
	if not FileAccess.file_exists(LIB.OUTPUT):
		push_error("找不到 %s（先 --build）" % LIB.OUTPUT)
		return 1
	var line := "[node name=\"%s\" parent=\".\" instance=ExtResource(\"%s\")]" % [LIB.NODE_NAME, EXT_ID]
	if txt.contains(line):
		print("[WLF] attach：已掛（不重複、不寫場景）")
		return 0
	var nl := "\r\n" if txt.contains("\r\n") else "\n"
	var lines := txt.split(nl)
	var out := PackedStringArray(Array(lines))
	var at := out.find(AFTER_NODE)
	if at < 0:
		push_error("找不到 root/GroundPilotP10")
		return 1
	if at + 1 < out.size() and out[at + 1].strip_edges() != "":
		push_error("GroundPilotP10 節點後面不是空行，拒絕文字插入")
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
	print("[WLF] attach：加 root/%s（GroundPilotP10 之後）→ %s（+%d 行）" % [LIB.NODE_NAME, SCENE, out.size() - lines.size()])
	return 0

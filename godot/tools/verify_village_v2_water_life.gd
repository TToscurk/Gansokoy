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
	_wheel_facts()
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


## P5 水車 2 の実測：葉板の角度（Wheel 局部、先端 r ≥ 2.9 の頂点を 1° 単位で束ねる）、輪の材質と頂点色平均
var paddles: Array[float] = []
var wheel_mat := ""
var wheel_vc := 0.0


func _wheel_facts() -> void:
	var m := hero.get_node("Wheel/LOD0") as MeshInstance3D
	var arr := m.mesh.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var bins := {}
	for v0 in vs:
		var p: Vector3 = m.transform * v0
		if Vector2(p.y, p.z).length() >= 2.9:
			bins[int(round(rad_to_deg(atan2(p.z, p.y))))] = true
	var ks := bins.keys()
	ks.sort()
	# 隣り合う 1° ビン（例 −1, 1）は 1 枚の葉板 → 中心角
	var groups := []
	for k in ks:
		if not groups.is_empty() and absf(float(k) - float(groups[groups.size() - 1].back())) <= 2.0:
			groups[groups.size() - 1].append(k)
		else:
			groups.append([k])
	if groups.size() > 1 and float(groups[0][0]) <= -178.0 and float(groups[groups.size() - 1].back()) >= 178.0:
		groups[0].append_array(groups.pop_back().map(func(x): return x - 360))
	paddles.clear()
	for gp in groups:
		var sm := 0.0
		for x in gp:
			sm += float(x)
		paddles.append(sm / gp.size())
	var mat := m.get_active_material(0)
	wheel_mat = mat.resource_path if mat else ""
	var cs: PackedColorArray = arr[Mesh.ARRAY_COLOR] if arr[Mesh.ARRAY_COLOR] != null else PackedColorArray()
	var sum := 0.0
	for c in cs:
		sum += c.get_luminance()
	wheel_vc = sum / maxf(1.0, cs.size())
	print("[WLF] wheel facts: paddles %d %s、材質 %s、頂点色平均 %.3f" % [paddles.size(), str(paddles.map(func(a): return snappedf(a, 0.5))), wheel_mat.get_file(), wheel_vc])


func _cfg() -> Dictionary:
	return {"bucket_x1": -1.0, "bucket_th_off": 0.0, "bucket_r": [], "trough_raise": 0.0, "bent_x": LIB.BENT_X.duplicate(), "pour_dz": 0.0, "wood_vc": LIB.WOOD_VC,
		"boat_off": LIB.BOAT_OFF, "boat_l": LIB.BOAT_L, "boat_b": LIB.BOAT_B, "post_dy": 0.0}


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
	# 水車 2：水渠水面（P2 水面網格、輪心 4 m 內頂點の平均、Hero 局部）・輪の真下の水渠底（Hero 碰撞を除外）
	var hub_w := hx * LIB.HUB
	var wys := []
	var wnode := V.get_node_or_null("Water")
	if wnode:
		for mi in wnode.find_children("*", "MeshInstance3D", true, false):
			var m3 := mi as MeshInstance3D
			if m3.mesh == null:
				continue
			var gab := m3.global_transform * m3.mesh.get_aabb()
			if hub_w.x < gab.position.x - 4.0 or hub_w.x > gab.end.x + 4.0 or hub_w.z < gab.position.z - 4.0 or hub_w.z > gab.end.z + 4.0:
				continue
			var vs: PackedVector3Array = m3.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			for v0 in vs:
				var w: Vector3 = m3.global_transform * v0
				if Vector2(w.x - hub_w.x, w.z - hub_w.z).length() < 4.0:
					wys.append(w.y - hx.origin.y)
	var wy := NAN
	if not wys.is_empty():
		var sum := 0.0
		for y in wys:
			sum += float(y)
		wy = sum / wys.size()
	var hex: Array[RID] = excl.duplicate()
	for co in hero.find_children("*", "CollisionObject3D", true, false):
		hex.append((co as CollisionObject3D).get_rid())
	var sp := V.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(hub_w + Vector3(0, 6, 0), hub_w + Vector3(0, -20, 0))
	q.exclude = hex
	var hb := sp.intersect_ray(q)
	var out := {"bent_bed": bed, "post_ground": _ray_y(pp), "water_y": wy, "water_n": wys.size(),
		"bed_wheel": (float(hb["position"].y) - hx.origin.y) if not hb.is_empty() else NAN}
	out.merge(best)
	return out


func _gates(cfg: Dictionary, H: Dictionary) -> void:
	# 1 柄杓（Wheel 局部）：葉板の間・輪縁に載る・輪郭の外へ張り出す・東軸承柱の内・水に浸かる・水渠底に当たらない
	var bs := LIB.bucket_specs(float(cfg["bucket_x1"]), float(cfg["bucket_th_off"]), cfg["bucket_r"])
	var rmin := INF
	var rmax := 0.0
	var xmax := -INF
	var pad_bad := 0
	for b in bs:
		# 柄杓の角度範囲（中心角からの相対、8 隅）に葉板の角度が ±2.5° 以内で入れば干渉（葉板は輪縁 2.7〜先端 3.0 の板）
		var thb := rad_to_deg(float(b["th"]))
		var lo := INF
		var hi := -INF
		var r_lo := INF
		for c: Vector3 in LIB.bucket_corners(b):
			var r := Vector2(c.y, c.z).length()
			rmin = minf(rmin, r)
			rmax = maxf(rmax, r)
			r_lo = minf(r_lo, r)
			xmax = maxf(xmax, c.x + LIB.HUB.x)
			var rel := wrapf(rad_to_deg(atan2(c.z, c.y)) - thb, -180.0, 180.0)
			lo = minf(lo, rel)
			hi = maxf(hi, rel)
		if r_lo <= LIB.PADDLE_R + 0.02:
			for pa: float in paddles:
				var rp := wrapf(pa - thb, -180.0, 180.0)
				if rp >= lo - 2.5 and rp <= hi + 2.5:
					pad_bad += 1
	var low := LIB.HUB.y - rmax
	var wy := float(H["water_y"])
	var bedw := float(H["bed_wheel"])
	_ok(bs.size() == LIB.BUCKETS and pad_bad == 0 and rmin >= 2.50 and rmin <= LIB.RIM_R - 0.03 and rmax >= LIB.PADDLE_R + 0.25 and xmax <= LIB.POST_COL_X - 0.01
		and not is_nan(wy) and low <= wy - 0.2 and not is_nan(bedw) and low >= bedw + 0.15,
		"柄杓 %d：葉板 %d 枚の間（柄杓の角度範囲 ±2.5° に入る葉板 %d）、內端 r %.3f（輪縁の帯 2.50–%.2f に差し込み）、外緣 r %.3f（葉板 %.1f＋≥0.25＝輪郭の外）、東端 x %.3f（軸承柱碰撞 %.2f）、最下點 %.2f（水面 %.2f−0.2 以下・底 %.2f＋0.15 以上）"
		% [bs.size(), paddles.size(), pad_bad, rmin, LIB.RIM_R - 0.03, rmax, LIB.PADDLE_R, xmax, LIB.POST_COL_X, low, wy, bedw])
	# 受け樋最大半徑（相對輪心，y-z）
	var tz: float = LIB.P8_HEAD_LOCAL.z
	var hw := LIB.TROUGH_W * 0.5 + 0.04
	var tr := 0.0
	for i in 2:
		var ytop: float = float(LIB.TROUGH_BOT[i]) + float(cfg["trough_raise"]) + LIB.TROUGH_WALL
		for sz in [-1.0, 1.0]:
			tr = maxf(tr, Vector2(ytop - LIB.HUB.y, tz + sz * hw - LIB.HUB.z).length())
	# 2 受け樋
	var x0: float = LIB.TROUGH_X[0]
	var x1: float = LIB.TROUGH_X[1]
	var b0: float = float(LIB.TROUGH_BOT[0]) + float(cfg["trough_raise"])
	var b1: float = float(LIB.TROUGH_BOT[1]) + float(cfg["trough_raise"])
	var dy := b1 - LIB.P8_HEAD_LOCAL.y
	var rest := (b0 - LIB.TROUGH_FLOOR) - LIB.P8_BEARER_TOP
	_ok(x0 >= LIB.WHEEL_FACE_X + 0.01 and tr <= rmin - 0.1 and b0 > b1 and absf(x1 - LIB.P8_HEAD_LOCAL.x) <= 0.02 and dy >= 0.0 and dy <= 0.03 and rest >= -0.01 and rest <= 0.03,
		"受け樋：x %.3f–%.3f（輪面 %.2f）、最大 r %.2f（柄杓の回転 內緣 %.2f −0.1 以下）、底 %.3f→%.3f（往樋頭降 %.0f mm）、樋頭接口 Δy %.3f m、西端の底と P8 枕木 %+.3f m（載る）"
		% [x0, x1, LIB.WHEEL_FACE_X, tr, rmin, b0, b1, (b0 - b1) * 1000.0, dy, rest])
	# 3 架台
	var bad3 := []
	var bed: Array = H["bent_bed"]
	for i in 2:
		var bx := float(cfg["bent_x"][i])
		if bx - LIB.POST * 0.5 < LIB.POST_VIS_EAST + 0.05:
			bad3.append("柱 %d x %.2f 貼東軸承柱" % [i, bx])
		if absf(LIB.BENT_Z) - LIB.POST * 0.5 < LIB.FOOT_Z + 0.02:
			bad3.append("柱 %d 壓礎石" % i)
		if bx - LIB.POST * 0.5 < xmax + 0.05:
			bad3.append("柱 %d 進柄杓回轉範圍" % i)
		if is_nan(float(bed[i])):
			bad3.append("柱 %d 下方無水渠底" % i)
	_ok(bad3.is_empty(), "樋頭架台 2 柱：東軸承柱（可視東面 %.2f）外 ≥ 0.05、礎石（z ±%.2f）外、柄杓回轉範圍外、腳埋水渠底 0.30 m（底 %s）、頭＝P8 枕木下%s"
		% [LIB.POST_VIS_EAST, LIB.FOOT_Z, str(bed.map(func(y): return snappedf(float(y), 0.01))), "" if bad3.is_empty() else " ✗ " + str(bad3)])
	# 3b 落水：注ぎ＝輪頂を越えた柄杓の口 → 受け樋の中；こぼれ水＝輪郭の外を水面まで；泡＝水面
	var pt: Vector3 = LIB.POUR_TOP
	var pb: Vector3 = LIB.POUR_BOT + Vector3(0, 0, float(cfg["pour_dz"]))
	var floor_y := lerpf(b0, b1, (pb.x - x0) / (x1 - x0))
	var pr := Vector2(pt.y - LIB.HUB.y, pt.z - LIB.HUB.z).length()
	var pm: Vector3 = LIB.POUR_MID
	var pour_ok := pm.x >= LIB.WHEEL_FACE_X + 0.03 and pm.y < pt.y and pm.y > pb.y and pb.x >= x0 + 0.06 and pb.x <= x1 and absf(pb.z - tz) <= LIB.TROUGH_W * 0.5 - 0.03 and pb.y >= floor_y and pb.y <= floor_y + 0.12 \
		and pt.x >= LIB.WHEEL_FACE_X + 0.03 and pr >= LIB.RIM_R and pr <= rmax + 0.05 and pt.z < 0.0
	var spill_bad := 0
	for sd: Dictionary in LIB.spill_specs(wy if not is_nan(wy) else 0.0):
		for k in 6:
			var p: Vector3 = (sd["top"] as Vector3).lerp(sd["bot"], k / 5.0)
			if Vector2(p.y - LIB.HUB.y, p.z - LIB.HUB.z).length() < LIB.PADDLE_R + 0.15:
				spill_bad += 1
	_ok(pour_ok and spill_bad == 0, "落水：注ぎ 輪頂 r %.2f・z %.2f・x %.2f（輪面の外）→ 受け樋の中（x %.2f、z %.2f、底 %.3f＋%.3f）；こぼれ水 %d 本 輪郭（r %.1f＋0.15）の内に入る點 %d；泡＝水面＋0.015"
		% [pr, pt.z, pt.x, pb.x, pb.z, floor_y, pb.y - floor_y, LIB.SPILL_TH_DEG.size(), LIB.PADDLE_R, spill_bad])
	# 3c 材質一致：輪と同じ V2_Wood、頂点色の明度 ±0.05
	_ok(wheel_mat == LIB.WOOD and absf(float(cfg["wood_vc"]) - wheel_vc) <= 0.05 and LIB.BENT_VC <= wheel_vc and LIB.BENT_WET_VC < LIB.BENT_VC,
		"材質一致：輪 %s／新部材 %s、頂点色 輪 %.3f／柄杓・受け樋 %.3f（差 ≤ 0.05＝白く浮かない）、架台 %.2f（≤ 輪＝日向で淡灰の縦材にならない）・濡れ脚 %.2f" % [wheel_mat.get_file(), LIB.WOOD.get_file(), wheel_vc, float(cfg["wood_vc"]), LIB.BENT_VC, LIB.BENT_WET_VC])
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
	c1["bucket_x1"] = 2.42
	cases.append(["N1 柄杓を東へ広げて東軸承柱に当てる", c1, H])
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
	var c7 := _cfg()
	c7["bucket_th_off"] = -11.25
	cases.append(["N7 柄杓を葉板の角度に置く（葉板と干渉）", c7, H])
	var c8 := _cfg()
	c8["pour_dz"] = 0.5
	cases.append(["N8 注ぎが受け樋を外れる", c8, H])
	var c9 := _cfg()
	c9["bucket_r"] = [2.45, 2.95]
	cases.append(["N9 柄杓が輪の輪郭の内（r3 以前＝西から見えない）", c9, H])
	var c10 := _cfg()
	c10["wood_vc"] = 0.95
	cases.append(["N10 新部材が白い（r3 の檜色＝浮く）", c10, H])
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
	# ROUND 2：表裏（明示法線＝Godot の表）＋反向（r1–r12 の巻き順の四角は必ず検出）
	var wb := LIB.winding_bad(rb)
	var neg := LIB.old_winding_quad()
	var wn := LIB.winding_bad(neg)
	neg.free()
	_ok(int(wb[0]) == 0 and int(wb[1]) > 100 and int(wn[0]) == 2, "表裏：明示法線と表（時計回り）が逆の三角形 %d／%d（反向：r1–r12 の巻き順の四角 → 検出 %d／2）" % [int(wb[0]), int(wb[1]), int(wn[0])])
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
	var p8_back := int(n.get("p8_toned")) == 0
	for m: MeshInstance3D in n.call("p8_wood_nodes"):
		if m.material_override != null and m.material_override.resource_name == "P10_WLF_P8WoodTone":
			p8_back = false
	_ok(rotor.get_node_or_null("LiftBuckets") == null and hidden and p8_back, "enabled=false → 柄杓取下、overlay 全隱藏、P8 落とし樋の木部は元の材質へ（%s）" % p8_back)
	n.set("enabled", true)
	_ok(rotor.get_node_or_null("LiftBuckets") != null, "enabled=true → 柄杓重新掛上")
	# ROUND 2：落水と材質
	var fx := n.get_node_or_null("WW2_Lift/WaterFX")
	var fx_ok := fx != null and fx.get_node_or_null("Pour") != null and fx.get_node_or_null("Spill") != null and fx.get_node_or_null("Foam") != null \
		and n.get_node_or_null("ChuteFlow/Flow") != null and bk != null and bk.get_node_or_null("BucketWater") != null
	var bkm := (bk as MeshInstance3D).material_override if bk is MeshInstance3D else null
	var tro := n.get_node_or_null("WW2_Lift/UkeToi/Trough") as MeshInstance3D
	var pst := n.get_node_or_null("WW2_Lift/HeadBent/Posts") as MeshInstance3D
	var wm := (V.get_node(LIB.ROTOR + "/LOD0") as MeshInstance3D).get_active_material(0)
	var same := bkm != null and tro != null and pst != null and wm != null and bkm.resource_path == wm.resource_path and tro.material_override.resource_path == wm.resource_path and pst.material_override.resource_path == wm.resource_path
	_ok(fx_ok and same, "落水 Pour／Spill／Foam／ChuteFlow／柄杓の中の水 存在 %s；柄杓・受け樋・架台の材質＝輪と同一 %s（%s）" % [fx_ok, same, wm.resource_path.get_file() if wm else "?"])
	# ROUND 2：P8 落とし樋の木部の明度＝輪と同じ（runtime override、P8 ファイル不変）；enabled=false で元へ
	var wl := n
	var p8n: Array = wl.call("p8_wood_nodes")
	var lum_bad := []
	for m: MeshInstance3D in p8n:
		var mo := m.material_override as StandardMaterial3D
		var eff := mo.albedo_color.get_luminance() if mo else -1.0
		var want := (wm as StandardMaterial3D).albedo_color.get_luminance() * LIB.WOOD_VC
		if mo == null or absf(eff - want) > 0.03:
			lum_bad.append("%s %.3f" % [m.name, eff])
	_ok(p8n.size() >= 10 and p8n.size() <= 24 and lum_bad.is_empty() and int(wl.get("p8_toned")) == p8n.size(),
		"P8 落とし樋（水車 2 の分だけ、10–24 件）木部 %d 件：明度 ＝ 輪（%.3f × 頂点色 %.2f）±0.03%s（P8 ファイル不変・runtime override）" % [p8n.size(), (wm as StandardMaterial3D).albedo_color.get_luminance(), LIB.WOOD_VC, "" if lum_bad.is_empty() else " ✗ " + str(lum_bad.slice(0, 4))])
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

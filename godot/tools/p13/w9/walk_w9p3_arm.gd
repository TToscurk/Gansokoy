extends "res://tools/p13/w6/w6_base.gd"
## P13 W9 Phase 3 R2：真玩家の短い歩行で SpringArm の実測（get_hit_length）を 1 フレームずつ残す。唯読・場景ファイルは書かない。
##   godot --path . --script res://tools/p13/w9/walk_w9p3_arm.gd -- <outdir/> <tag> [--disable=EnrichW9P3,ArchW9R2P13] [--inject-r1-posts] [--baseline=<OFF の *_arm.json>]
## 使用者（2026-10-15）：「075 の前で、新しい柴棚柱が SpringArm の実際の臂長を 2.75 m → 1.54 m に縮めた。同じ路線を重走して、
##   角色の可視性と SpringArm の表現が新しい柴棚柱のせいで顕著に悪化しないこと」。
## 正式 main.tscn → ReviewStart → village_v2（実際の玩家制御器・TPS 相機・SpringArm）。Input.action_press("move_forward") と制御器自身の snap_yaw だけで歩く。
## 各フレームで arm.get_hit_length()（実際の臂長）と、その臂の ray（起点＝arm.global_position・向き＝arm の +Z・mask＝arm.collision_mask・玩家を除外）が
## 当たった碰撞体の持ち主（overlay 名／建物 ID）を記録する。--baseline を渡すと同じフレーム番号どうしの臂長の差（OFF − ON）を出す。
## --inject-r1-posts：R1（bce7cf4）の庇柱 3 本を（メモリ内だけで）戻す＝この計測が R1 の問題を検出できることの反向案例。
const W9 := preload("res://tools/p13/w9/w9_lib.gd")
const P3 := preload("res://tools/p13/w9/w9p3_lib.gd")
const SL := preload("res://tools/village_v2_street_lib.gd")
const L := preload("res://tools/p13/w9/w9r2_lib.gd")

const STALL_FRAMES := 30
const TIMEOUT_MS := 30000
const BLOCK_SPEED := 0.3
const WORSE := 0.30
const R1_POSTS := [[-3.3655, 6.53], [-1.94775, 6.53], [-0.53, 6.53]]
const NEG_OWNER := "NEG/R1_posts"

var _tag := ""
var _arm: SpringArm3D
var _space: PhysicsDirectSpaceState3D
var _legs: Array = []
var _base := {}
var _fails := 0
var _passes := 0


func _owner_of(col: Node) -> String:
	if col.name.begins_with("_neg_post"):
		return NEG_OWNER
	var seg := String(vil.get_path_to(col)).split("/")
	if seg.size() >= 2 and (seg[0] == "ArchW9R2P13" or seg[0] == "EnrichW9P3"):
		return "%s/%s" % [seg[0], seg[1]]
	return "(base)"


func _arm_owner() -> String:
	var o := _arm.global_position
	var d := _arm.global_transform.basis.z
	var to := o + d * (_arm.spring_length + 0.5)
	var r := _space.intersect_ray(PhysicsRayQueryParameters3D.create(o, to, _arm.collision_mask, [player.get_rid()]))
	if r.is_empty():
		return ""
	return _owner_of(r["collider"] as Node)


## 停止位置が OFF と変わるのが設計の脚（薪の積みの碰撞で ON は手前で止まる）は、フレーム対フレームでなく『最小の臂長』で比べる
const MIN_ONLY := ["B_shed_under_roof_to_wood"]


func _walk(name: String, kind: String, pts: Array) -> void:
	var p0: Vector2 = pts[0]
	await _tpw(p0, ((pts[1] as Vector2) - p0).normalized())
	await _frames(4)
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	Input.action_press("move_forward")
	var n := 0
	var run := 0
	var wi := 1
	var prev := player.global_position
	var t0 := Time.get_ticks_msec()
	var stop := ""
	var hits: Array = []
	var owners: Array = []
	var xs: Array = []
	while true:
		await physics_frame
		n += 1
		var pp := player.global_position
		var q := Vector2(pp.x, pp.z)
		var goal: Vector2 = pts[wi]
		var dv := goal - q
		var d := dv.length()
		if d > 0.05:
			player.call("snap_yaw", atan2(-dv.x / d, -dv.y / d))
		if n % 8 == 1:
			_fix_camera()
		var sp := Vector2(pp.x - prev.x, pp.z - prev.z).length() / dt
		run = run + 1 if (n > 6 and sp < BLOCK_SPEED) else 0
		prev = pp
		var hl := _arm.get_hit_length()
		hits.append(snappedf(hl, 0.001))
		xs.append([snappedf(pp.x, 0.01), snappedf(pp.z, 0.01)])
		owners.append(_arm_owner() if hl < _arm.spring_length - 0.05 or hl < 2.5 else "")
		if kind == "reach" and d <= 0.4:
			if wi == pts.size() - 1:
				stop = "reached"
				break
			wi += 1
		if run >= STALL_FRAMES:
			stop = "stalled"
			break
		if Time.get_ticks_msec() - t0 > TIMEOUT_MS:
			stop = "timeout"
			break
	Input.action_release("move_forward")
	var mn := 1.0e9
	var mn_at := Vector2.ZERO
	var sum := 0.0
	for i in hits.size():
		sum += float(hits[i])
		if float(hits[i]) < mn:
			mn = float(hits[i])
			mn_at = Vector2((xs[i] as Array)[0], (xs[i] as Array)[1])
	var by_owner := {}
	for i in hits.size():
		var ow: String = owners[i]
		if ow != "" and float(hits[i]) < 2.4:
			by_owner[ow] = int(by_owner.get(ow, 0)) + 1
	var row := {"leg": name, "kind": kind, "stop": stop, "frames": n, "min_hit": snappedf(mn, 0.001), "min_at": [snappedf(mn_at.x, 0.01), snappedf(mn_at.y, 0.01)],
		"mean_hit": snappedf(sum / float(maxi(hits.size(), 1)), 0.001), "short_owner_frames": by_owner, "hit": hits, "pos": xs,
		"end": (xs[xs.size() - 1] if xs.size() > 0 else [0, 0])}
	var msg := "min %.2f m @(%.1f,%.1f)・平均 %.2f m・臂が 2.4 m 未満のフレームの当たり先 %s" % [mn, mn_at.x, mn_at.y, float(row["mean_hit"]), str(by_owner)]
	if _base.has(name) and name in MIN_ONLY:
		var bmin: float = float((_base[name] as Dictionary)["min_hit"])
		row["vs_off"] = {"mode": "min_only", "off_min": bmin, "on_min": snappedf(mn, 0.001), "worst_loss": snappedf(maxf(bmin - mn, 0.0), 0.001), "n_worse": 0 if bmin - mn < WORSE else 1}
		msg += " ｜OFF 比（最小の臂長のみ）OFF %.2f m → ON %.2f m（差 %.2f m）" % [bmin, mn, bmin - mn]
	elif _base.has(name):
		var bh: Array = (_base[name] as Dictionary)["hit"]
		var m := mini(bh.size(), hits.size())
		var worst := 0.0
		var nbad := 0
		var worst_i := 0
		for i in m:
			var loss: float = float(bh[i]) - float(hits[i])
			if loss > worst:
				worst = loss
				worst_i = i
			if loss >= WORSE:
				nbad += 1
		row["vs_off"] = {"frames_compared": m, "worst_loss": snappedf(worst, 0.001), "worst_at": (xs[worst_i] if m > 0 else [0, 0]), "n_worse": nbad}
		msg += " ｜OFF 比 最悪の縮み %.2f m @(%.1f,%.1f)・≥ %.2f m 縮んだフレーム %d／%d" % [worst, float((xs[worst_i] as Array)[0]), float((xs[worst_i] as Array)[1]), WORSE, nbad, m]
	_legs.append(row)
	print("[W9ARM] LEG %-26s %s stop=%s frames=%d %s" % [name, kind, stop, n, msg])


func _chk(cond: bool, msg: String) -> void:
	if cond:
		_passes += 1
		print("[W9ARM] PASS ", msg)
	else:
		_fails += 1
		print("[W9ARM] FAIL ", msg)


func _find(name: String) -> Dictionary:
	for r: Dictionary in _legs:
		if String(r["leg"]) == name:
			return r
	return {}


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0]
	_tag = args[1]
	var disables: Array = []
	var inject := false
	for a: String in args:
		if a.begins_with("--disable="):
			disables.append_array(a.trim_prefix("--disable=").split(",", false))
		elif a == "--inject-r1-posts":
			inject = true
		elif a.begins_with("--baseline="):
			var bj: Variant = JSON.parse_string(FileAccess.get_file_as_string(a.trim_prefix("--baseline=")))
			if bj is Dictionary:
				for r: Dictionary in (bj as Dictionary)["legs"]:
					_base[String(r["leg"])] = r
			print("[W9ARM] baseline 脚 %d 本" % _base.size())
	DirAccess.make_dir_recursive_absolute(out)
	await _boot()
	for dn: String in disables:
		var dnode := vil.get_node_or_null(NodePath(dn))
		if dnode != null:
			if "enabled" in dnode:
				dnode.set("enabled", false)
			else:
				vil.remove_child(dnode)
				dnode.queue_free()
			print("[W9ARM] disabled ", dn)
	await _frames(8)
	_arm = player.get_node("Pivot/SpringArm3D") as SpringArm3D
	_space = player.get_world_3d().direct_space_state
	P3.register_dims()
	var C := W9.context(vil, PackedVector2Array())
	var b71 := W9.bld(C, "B_P_RSW_071")
	if inject:
		var body := vil.get_node_or_null("Districts/ResidentialWest/Buildings/B_P_RSW_071") as Node3D
		for pi in R1_POSTS.size():
			var pz: Array = R1_POSTS[pi]
			var sb := StaticBody3D.new()
			sb.name = "_neg_post%d" % pi
			sb.collision_layer = int((body as CollisionObject3D).collision_layer)
			sb.collision_mask = int((body as CollisionObject3D).collision_mask)
			var cs := CollisionShape3D.new()
			var bx := BoxShape3D.new()
			var half := maxf(0.14 / 2.0 + L.POST_PAD, 0.125)
			bx.size = Vector3(2.0 * half, 2.478, 2.0 * half)
			cs.shape = bx
			sb.add_child(cs)
			vil.add_child(sb)
			sb.global_transform = Transform3D(body.global_transform.basis, body.global_transform * Vector3(float(pz[0]), 1.239, float(pz[1])))
		await _frames(6)
		print("[W9ARM] R1 の庇柱 3 本をメモリ内に戻した（反向案例）")
	print("[W9ARM] tag=%s spring_length(設定)=%.2f  arm.margin=%.2f  mask=%d" % [_tag, _arm.spring_length, _arm.margin, _arm.collision_mask])
	# 脚：075 の戸口へ（bT3 の状況＝相機が 071 の柴棚の方へ引かれる）／巷を東へ・西へ／071 自身の戸口／元の庇柱の列を横切る
	var b75 := W9.bld(C, "B_P_RSW_075")
	var dp75 := SL.door_poly(b75)
	var dc75 := (dp75[0] + dp75[1] + dp75[2] + dp75[3]) * 0.25
	await _walk("B_door_RSW_075", "door", [dc75 + (b75["az"] as Vector2) * 3.0, dc75 - (b75["az"] as Vector2) * 0.6])
	await _walk("B_lane_east", "reach", [P3.lane(-14.0, 0.0), P3.lane(16.0, 0.0)])
	await _walk("B_lane_west", "reach", [P3.lane(16.0, 0.4), P3.lane(-14.0, 0.4)])
	var dp71 := SL.door_poly(b71)
	var dc71 := (dp71[0] + dp71[1] + dp71[2] + dp71[3]) * 0.25
	await _walk("B_door_RSW_071", "door", [dc71 + (b71["az"] as Vector2) * 3.0, dc71 - (b71["az"] as Vector2) * 0.6])
	var f71: Vector2 = b71["az"]
	var x71 := Vector2(f71.y, -f71.x)
	var o71: Vector2 = b71["o"]
	var lw := func(lx: float, lz: float) -> Vector2: return o71 + x71 * lx + f71 * lz
	# 元の庇柱（局部 x −3.3655／−1.94775・z 6.53）の線そのものを東へ歩く（終点 x −1.75＝右端 −1.45 は切り株の箱 −1.33 の手前）
	await _walk("B_shed_post_line", "reach", [lw.call(-4.6, 6.53), lw.call(-1.75, 6.53)])
	# 元の中柱の線（局部 x −1.94775）で壁へ：壁際の薪の積みの前で止まる（R1 では中柱 z 6.53 の手前 1.96 m で止まった）
	await _walk("B_shed_under_roof_to_wood", "door", [lw.call(-1.94775, 9.0), lw.call(-1.94775, 5.0)])
	# ── 判定
	var n071 := 0
	for r: Dictionary in _legs:
		var so: Dictionary = r["short_owner_frames"]
		for k: String in so:
			if k.contains("B_P_RSW_071"):
				n071 += int(so[k])
	var nneg := 0
	for r: Dictionary in _legs:
		nneg += int((r["short_owner_frames"] as Dictionary).get(NEG_OWNER, 0))
	var worst_all := 0.0
	var worst_leg := ""
	for r: Dictionary in _legs:
		if r.has("vs_off") and float((r["vs_off"] as Dictionary)["worst_loss"]) > worst_all:
			worst_all = float((r["vs_off"] as Dictionary)["worst_loss"])
			worst_leg = String(r["leg"])
	var is_off := not disables.is_empty()
	var wood: Dictionary = _find("B_shed_under_roof_to_wood")
	var wood_short := 0.0
	if not wood.is_empty():
		var we: Array = wood["end"]
		wood_short = Vector2(float(we[0]), float(we[1])).distance_to(lw.call(-1.94775, 5.0) as Vector2)
	var line: Dictionary = _find("B_shed_post_line")
	if is_off:
		print("[W9ARM] OFF（overlay を外した基準の走り）：判定なし・記録のみ")
	elif inject:
		_chk(nneg >= 1, "反向：R1 の庇柱を戻すと、臂が柱に当たったフレームが %d 個ある（≥ 1）" % nneg)
		_chk(worst_all >= 1.0, "反向：OFF 比の最悪の縮み %.2f m（%s）≥ 1.00 m＝この計測は R1 の問題（−1.21 m 級）を検出できる" % [worst_all, worst_leg])
		_chk(String(line.get("stop", "")) != "reached", "反向：R1 の庇柱を戻すと、庇柱の線（局部 z＝6.53）を歩けず止まる（stop=%s）" % str(line.get("stop", "")))
		_chk(wood_short >= 1.8, "反向：R1 の庇柱を戻すと、中柱の線で壁へ向かうと柱の手前（目標の %.2f m 手前≥ 1.80）で止まる＝柱の碰撞が効いている" % wood_short)
	else:
		_chk(n071 == 0, "071（B_P_RSW_071）の overlay に臂が当たったフレーム 0（実際 %d）" % n071)
		_chk(String(line.get("stop", "")) == "reached", "元の庇柱の線（局部 z＝6.53）を最後まで歩ける＝可視の柱が無い（stop=%s）" % str(line.get("stop", "")))
		_chk(absf(wood_short - 1.14) <= 0.14, "中柱の線で壁へ向かうと薪の積みの前で止まる（目標の %.2f m 手前・期待 1.14 ±0.14＝箱の前面＋半径 0.30）" % wood_short)
		var d75: Dictionary = _find("B_door_RSW_075")
		if d75.has("vs_off"):
			_chk(float((d75["vs_off"] as Dictionary)["worst_loss"]) <= 0.10, "075 の戸口へ歩く間の最悪の縮み（OFF 比）%.3f m ≤ 0.10（R1：1.21 m）" % float((d75["vs_off"] as Dictionary)["worst_loss"]))
		for r: Dictionary in _legs:
			if r.has("vs_off") and String(r["leg"]) in ["B_door_RSW_075", "B_door_RSW_071", "B_shed_post_line", "B_shed_under_roof_to_wood"]:
				_chk(int((r["vs_off"] as Dictionary)["n_worse"]) == 0, "%s：OFF より 0.30 m 以上縮んだフレーム 0（実際 %d）" % [r["leg"], int((r["vs_off"] as Dictionary)["n_worse"])])
	var f := FileAccess.open(out + _tag + "_arm.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"tag": _tag, "inject_r1_posts": inject, "spring_length": _arm.spring_length, "legs": _legs, "fails": _fails}, "\t") + "\n")
	f.close()
	print("[W9ARM] PASS %d  FAIL %d" % [_passes, _fails])
	print("[W9ARM] 結果：%d 項失敗" % _fails)
	quit(1 if _fails > 0 else 0)

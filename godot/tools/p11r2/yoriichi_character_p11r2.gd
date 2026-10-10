extends "res://characters/yoriichi/yoriichi_character.gd"
## P11 R2 候補 A — Auto-Step Controller（**検証用の候補・未統合**）。
## 本檔は yoriichi_character.gd（他 session 所有）を変更せず、_try_step_up だけを override して挙動を検証するためのもの。
## 統合は docs/art_review/village_v2_p11/r2/patches/A_yoriichi_character_step.patch を所有者が適用する（本檔と同じ内容）。
##
## 変更点（使用者 P11 R2「將可跨高度設為 0.35 m／僅在有效接地狀態下允許跨步／阻止同一動作造成重複、累積抬升」）：
##   ① step_height 0.6 → 0.35（patch では @export の既定値。検証 harness は差し替え後に 0.35 を設定）
##   ② 有効接地＝足元中心の真下の地面 g：足元中心から真下 step_height＋0.5 m 以内に面が無ければ跨がない（空中・何も無い所の上）。
##      is_on_floor() は要求しない（46° の縁に押し付けられて一瞬 off-floor でも足が地面にあれば跨げる＝原版の意図を保持）。
##   ③ 障害物の高さ：最初に当たった点の 5 cm 奥を真上から測り、上面が g＋step_height を超えるなら跨がない
##      （0.51 m の長凳に 0.35 m の跨ぎで縁にだけ乗り上げる、を最初から起こさない）。
##   ④ 累積の上限：跨いだ後の足の高さは g＋step_height 以下。g は「足元中心の真下」なので、膠囊の丸い底が縁に乗った状態
##      （足元中心の真下はまだ低い地面）から次の幀にもう一段、の連続抬升ができない。本物の段差（各段 ≤ step_height）は一段ずつ上れる。
## 原版からの差分は ②③④ だけ（持ち上げ・前進・着地の掃引は原版のまま）。

## 検証用：直近の跨ぎ判定の結果（診断ツールが読む）
var step_dbg := ""


func _try_step_up(delta: float) -> void:
	if step_height <= 0.0:
		step_dbg = "no_height"
		return
	var h := Vector3(velocity.x, 0.0, velocity.z)
	if h.length_squared() < 0.01:
		step_dbg = "no_hvel"
		return
	var space := get_world_3d().direct_space_state
	# ② 足元中心の真下の地面 g
	var o := global_transform.origin
	var gq := PhysicsRayQueryParameters3D.create(o + Vector3(0, 0.05, 0), o - Vector3(0, step_height + 0.5, 0), collision_mask)
	gq.exclude = [get_rid()]
	var gh := space.intersect_ray(gq)
	if gh.is_empty():
		step_dbg = "no_ground"
		return
	var g := float((gh["position"] as Vector3).y)
	var motion := h * delta
	var par := PhysicsTestMotionParameters3D.new()
	var res := PhysicsTestMotionResult3D.new()
	par.from = global_transform
	par.motion = motion
	# Not blocked → nothing to step over.
	if not PhysicsServer3D.body_test_motion(get_rid(), par, res):
		step_dbg = "not_blocked"
		return
	# ③ 障害物の上面（当たった点の 5 cm 奥を真上から）が g＋step_height を超えるなら跨がない
	var cp := res.get_collision_point()
	var probe := Vector3(cp.x, 0.0, cp.z) + h.normalized() * 0.05
	var tq := PhysicsRayQueryParameters3D.create(Vector3(probe.x, g + step_height + 0.3, probe.z), Vector3(probe.x, g - 0.1, probe.z), collision_mask)
	tq.exclude = [get_rid()]
	var th := space.intersect_ray(tq)
	if not th.is_empty() and float((th["position"] as Vector3).y) > g + step_height + 0.01:
		step_dbg = "too_tall %.2f" % (float((th["position"] as Vector3).y) - g)
		return
	# ここから下は原版と同じ（持ち上げた姿勢の空き → 前進 → 着地）
	var up := Vector3(0.0, step_height, 0.0)
	var raised := global_transform.translated(up)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _capsule_shape()
	if q.shape == null:
		step_dbg = "no_shape"
		return
	q.transform = raised * _capsule_local()
	q.collision_mask = collision_mask
	q.exclude = [get_rid()]
	if not space.intersect_shape(q, 1).is_empty():
		step_dbg = "ceiling"
		return
	par.from = raised
	par.motion = motion
	PhysicsServer3D.body_test_motion(get_rid(), par, res)
	var fwd: Vector3 = res.get_travel()
	if fwd.length() < motion.length() * 0.5:
		step_dbg = "walled"
		return
	var lifted_by: float = step_height
	par.from = raised.translated(fwd)
	par.motion = Vector3(0.0, -lifted_by, 0.0)
	if not PhysicsServer3D.body_test_motion(get_rid(), par, res):
		step_dbg = "no_land"
		return
	var landed := raised.translated(fwd).translated(res.get_travel())
	var foot := landed.origin
	var rq := PhysicsRayQueryParameters3D.create(foot + Vector3(0, 0.3, 0), foot + Vector3(0, -0.3, 0), collision_mask)
	rq.exclude = [get_rid()]
	var rh := space.intersect_ray(rq)
	var land_n: Vector3 = rh["normal"] if not rh.is_empty() else res.get_collision_normal()
	if land_n.angle_to(Vector3.UP) > floor_max_angle:
		step_dbg = "steep_land"
		return
	var rise: float = lifted_by - res.get_travel().length()
	if rise <= 0.02:
		step_dbg = "rise_small"
		return
	# ④ 累積の上限：跨いだ後の足の高さ ≤ g＋step_height
	if o.y + rise - g > step_height + 0.01:
		step_dbg = "over_ground %.2f" % (o.y + rise - g)
		return
	step_dbg = "STEP %.2f" % rise
	global_position.y += rise

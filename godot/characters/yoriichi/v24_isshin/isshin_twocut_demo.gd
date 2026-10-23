extends "res://characters/yoriichi/v24_isshin/isshin_iai_demo.gd"
## 葦名流二連斬候選（獨立候選；不改正式 Player／跑酷／共用資產；已結案的居合斬設定不動）：
## 居合構 → K／J／左鍵＝二連斬（c1400 居合型 a100_003010）：拔刀逆袈裟上撩 → 袈裟斬回 → 殘心 → 血振 → 納刀 → 回居合構。
## 沿用居合候選的鞘中刀／手上刀切換、刀身判定（實際半徑、切入 5 cm、掃掠）、火花與 Hit Stop；逐格刀可見度 anims/isshin_twocut_sword.json。
## 自動導覽：godot --path godot --write-movie out.avi --fixed-fps 60 res://characters/yoriichi/v24_isshin/isshin_twocut_demo.tscn -- --tour [--cam=third|side] [--dist=1.8]
## 調參：--twocut_cfg='{"min_dist": 0.8, "aim_offset": 0}'
var twocut_track: Dictionary = {}

func _ready() -> void:
	super._ready()
	combat.iai_key = "twocut"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--twocut_cfg="):
			combat.shot_override["twocut"] = JSON.parse_string(a.substr(13))
	twocut_track = JSON.parse_string(FileAccess.get_file_as_string("res://characters/yoriichi/v24_isshin/anims/isshin_twocut_sword.json"))
	_apply_sword_vis()

func _apply_sword_vis() -> void:
	var mode := "sheathed"
	var clip := 10.0
	var key: String = combat.shot_key
	var track: Dictionary = twocut_track if key == "twocut" else iai_track
	if combat.state == combat.S.SHOT and (key == "twocut" or key == "iai") and not track.is_empty():
		var frames: Array = track["frames"]
		var f := clampi(int(round(combat.shot_t * float(track["fps"]))), 0, frames.size() - 1)
		mode = str(frames[f]["mode"])
		clip = float(frames[f]["clip_y"])
	elif not combat.iai_mode:
		mode = "hand"
	sword.visible = mode == "hand"
	sword_sheathed.visible = mode == "sheathed"
	for sm in hand_mats:
		(sm as ShaderMaterial).set_shader_parameter("clip_y", clip if mode == "hand" else 10.0)
	if tour and tour_t >= TOUR_START_DELAY and key == "twocut" and combat.state == combat.S.SHOT:
		var hs := sword.global_transform
		var ss := sword_sheathed.global_transform
		vis_log.append({"t": snappedf(tour_t - TOUR_START_DELAY, 0.0001), "shot_t": snappedf(combat.shot_t, 0.0001), "mode": mode, "clip_y": clip,
			"hitstop": combat.hitstop_left, "gap_mm": snappedf(hs.origin.distance_to(ss.origin) * 1000.0, 0.1),
			"ang_deg": snappedf(rad_to_deg(hs.basis.orthonormalized().get_rotation_quaternion().angle_to(ss.basis.orthonormalized().get_rotation_quaternion())), 0.1),
			"probe": _contact_probe()})

## 判定同居合候選（掃掠＋切入 5 cm），只改火花位置：放在「這一幀（停格畫面上看到的刀）刀身從護手往刀尖走、第一次碰到木樁表面的那一點」
## ＝刀刃切進木樁的入口（一定在手那一側、看得見）。掃掠是在上一幀→這一幀之間判到的，若這一幀刀已穿過木樁就用判到的那個中間位置。
func _hit_test() -> Dictionary:
	var hit := super._hit_test()
	if hit.is_empty():
		return hit
	var m := sword.global_transform
	var entry := _blade_entry(m * GUARD_LOCAL, m * TIP_LOCAL)
	if entry.is_empty() and _blade_prev.size() == 2:
		var w := float(hit.get("sub", 1.0))
		entry = _blade_entry((_blade_prev[0] as Vector3).lerp(m * GUARD_LOCAL, w), (_blade_prev[1] as Vector3).lerp(m * TIP_LOCAL, w))
	if not entry.is_empty():
		hit["pos"] = entry["p"]
		hit["entry_u"] = entry["u"]
	return hit

## 判到命中的那一幀，動畫還會再前進一格才進入停格；停格畫面上的刀＝下一格的刀。所以火花延到下一幀開頭（停格中、刀已凍結）
## 才依畫面上的刀重算入口位置再生成（晚 1 幀＝16.7 ms，仍在 3 幀停格內）。
var _pending_spark: Variant = null

func _spark(p: Vector3) -> void:
	_pending_spark = p

func _process(delta: float) -> void:
	if _pending_spark != null:
		var m := sword.global_transform
		var e := _blade_entry(m * GUARD_LOCAL, m * TIP_LOCAL)
		var p: Vector3 = e["p"] if not e.is_empty() else _pending_spark
		_pending_spark = null
		spark_log.append({"t": snappedf(tour_t - TOUR_START_DELAY, 0.0001), "pos": [snappedf(p.x, 0.001), snappedf(p.y, 0.001), snappedf(p.z, 0.001)], "on_frozen_blade": not e.is_empty()})
		super._spark(p)
	super._process(delta)

var spark_log: Array = []

func _finish_tour() -> void:
	if slashlog_path != "":
		var f := FileAccess.open(slashlog_path.get_basename() + "_spark.json", FileAccess.WRITE)
		f.store_string(JSON.stringify(spark_log))
		f.close()
	super._finish_tour()

func _dummy_r(y: float) -> float:
	if y > 1.6:
		return sqrt(maxf(0.0, 0.04 - pow(y - 1.75, 2.0)))
	return 0.26 - 0.025 * clampf(y, 0.0, 1.6)

func _blade_entry(a: Vector3, b: Vector3) -> Dictionary:
	var prev_out := -1.0
	for i in range(0, 65):
		var u := float(i) / 64.0
		var p := a.lerp(b, u)
		var inside := Vector2(p.x - enemy_pos.x, p.z - enemy_pos.z).length() < _dummy_r(p.y) and p.y > 0.05
		if inside and prev_out >= 0.0:
			return {"p": a.lerp(b, (u + prev_out) * 0.5), "u": u}
		if not inside:
			prev_out = u
	return {}

## 側面相機：每次出招時定一次、整招固定；垂直於「角色→木樁」連線、站在連線右手側再往正面轉 30°
var _tc_side_set := false
var _tc_side_locked := false

func _update_cam(snap: bool) -> void:
	var args := OS.get_cmdline_user_args()
	if not args.has("--cam=side"):
		super._update_cam(snap)
		return
	var firing := combat.state == combat.S.SHOT and combat.shot_key == "twocut"
	if not _tc_side_set or (firing and not _tc_side_locked):
		_tc_side_set = true
		_tc_side_locked = firing
		var to := enemy_pos - actor.global_position
		to.y = 0.0
		var yaw := atan2(to.x, to.z)
		var dir := Vector3(sin(yaw), 0, cos(yaw))
		var right := Vector3(-cos(yaw), 0, sin(yaw))
		var midp := enemy_pos - dir * 0.7 + Vector3(0, 1.05, 0)
		var cdir := right.rotated(Vector3.UP, -deg_to_rad(30.0))
		cam.global_position = midp + cdir * 4.3 + Vector3(0, 0.45, 0)
		cam.look_at(midp, Vector3.UP)
	if not firing:
		_tc_side_locked = false

func _build_tour() -> void:
	var dist := enemy_dist
	var ang := 0.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--enemy_ang="):
			ang = float(a.substr(12))
	var E := {"enemy": [ang, dist, 0.01]}
	_s(1.2, "葦名流二連斬：居合構（刀在鞘）", Vector2.ZERO, E)
	_s(3.6, "拔刀上撩 → 袈裟斬回 → 殘心 → 血振 → 納刀", Vector2.ZERO, {"attack": 0.3})
	_s(0.8, "居合構", Vector2.ZERO, E)
	_s(3.6, "再一次", Vector2.ZERO, {"attack": 0.2})
	_s(0.8, "居合構", Vector2.ZERO, {"enemy": [0.0, dist + 1.8, 0.01]})
	_s(3.6, "距離不夠＝空揮，仍完整納刀", Vector2.ZERO, {"attack": 0.2})
	_s(0.8, "居合構")

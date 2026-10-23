extends "res://characters/yoriichi/v24_isshin/isshin_twocut_demo.gd"
## 前衝突刺候選（獨立候選；不改正式 Player／跑酷／共用資產；居合斬、二連斬設定不動）：
## 一般架勢（刀在手上）→ K／J／左鍵＝前衝突刺（c1400 a000「剣客 守り／攻めタイプ」a000_003014，雙手）。
## 沿用居合／二連斬候選的刀身判定（實際半徑、切入 5 cm、掃掠）、停在命中那一格的 Hit Stop、刀刃入口火花。
## 自動導覽：godot --path godot --write-movie out.avi --fixed-fps 60 res://characters/yoriichi/v24_isshin/isshin_thrust_demo.tscn -- --tour [--cam=third|side] [--dist=3.0]
## 調參：--thrust_cfg='{"min_dist": 1.2}'

func _ready() -> void:
	super._ready()
	combat.set_iai_mode(false)
	combat.attack_key = "thrust"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--thrust_cfg="):
			combat.shot_override["thrust"] = JSON.parse_string(a.substr(13))
	_apply_sword_vis()

func _apply_sword_vis() -> void:
	super._apply_sword_vis()
	if tour and tour_t >= TOUR_START_DELAY and combat.shot_key == "thrust" and combat.state == combat.S.SHOT:
		vis_log.append({"t": snappedf(tour_t - TOUR_START_DELAY, 0.0001), "shot_t": snappedf(combat.shot_t, 0.0001), "mode": "hand",
			"hitstop": combat.hitstop_left, "label": cur_label, "probe": _contact_probe()})

## 側面相機：每次出招時定一次、整招固定；垂直於「角色→木樁」連線、站在連線右手側再往正面轉 25°（突刺是直線，側面最看得清刺入深度）
var _th_side_set := false
var _th_side_locked := false

func _update_cam(snap: bool) -> void:
	var args := OS.get_cmdline_user_args()
	if not args.has("--cam=side"):
		super._update_cam(snap)
		return
	var firing := combat.state == combat.S.SHOT and combat.shot_key == "thrust"
	if not _th_side_set or (firing and not _th_side_locked):
		_th_side_set = true
		_th_side_locked = firing
		var to := enemy_pos - actor.global_position
		to.y = 0.0
		var yaw := atan2(to.x, to.z)
		var dir := Vector3(sin(yaw), 0, cos(yaw))
		var right := Vector3(-cos(yaw), 0, sin(yaw))
		var midp := enemy_pos - dir * maxf(1.0, to.length() * 0.5) + Vector3(0, 1.0, 0)
		var cdir := right.rotated(Vector3.UP, -deg_to_rad(25.0))
		cam.global_position = midp + cdir * 4.8 + Vector3(0, 0.45, 0)
		cam.look_at(midp, Vector3.UP)
	if not firing:
		_th_side_locked = false

func _build_tour() -> void:
	var dist := enemy_dist
	var E := {"enemy": [0.0, dist, 0.01]}
	_s(1.0, "主城劍客前衝突刺：一般架勢（刀在手上）", Vector2.ZERO, E)
	_s(2.0, "前衝突刺 → 命中 → 收勢", Vector2.ZERO, {"attack": 0.2})
	_s(0.8, "一般架勢", Vector2.ZERO, E)
	_s(1.6, "突刺 → 1.33 s 起可移動", Vector2.ZERO, {"attack": 0.2})
	_s(1.2, "移動取消：左移", Vector2(-1, 0))
	_s(0.6, "停步", Vector2.ZERO, E)
	_s(1.5, "突刺 → 0.70 s 起可閃避", Vector2.ZERO, {"attack": 0.2, "dodge": 1.0, "hold": 1.1, "side": 1.0})
	_s(1.2, "閃避後", Vector2.ZERO, {"enemy": [0.0, dist + 2.0, 0.01]})
	_s(2.0, "距離不夠＝空刺", Vector2.ZERO, {"attack": 0.2})
	_s(0.8, "一般架勢")

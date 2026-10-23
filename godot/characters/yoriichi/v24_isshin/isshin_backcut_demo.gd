extends "res://characters/yoriichi/v24_isshin/isshin_thrust_demo.gd"
## 退步縱斬候選（獨立候選；不改正式 Player／跑酷／共用資產；居合斬、二連斬、突刺設定不動）：
## 一般架勢（刀在手上）→ K／J／左鍵＝退步縱斬（c1400 a000「剣客 守り／攻めタイプ」a000_003009，雙手）：舉刀過頂 → 邊後退邊劈下。
## 沿用候選的刀身判定（實際半徑、切入 5 cm、掃掠）、停在命中那一格的 Hit Stop、刀刃入口火花。
## 自動導覽：godot --path godot --write-movie out.avi --fixed-fps 60 res://characters/yoriichi/v24_isshin/isshin_backcut_demo.tscn -- --tour [--cam=third|side] [--dist=1.4]
## 調參：--backcut_cfg='{"travel_scale": 0.93}'

func _ready() -> void:
	super._ready()
	combat.attack_key = "backcut"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--backcut_cfg="):
			combat.shot_override["backcut"] = JSON.parse_string(a.substr(14))

func _apply_sword_vis() -> void:
	super._apply_sword_vis()
	if tour and tour_t >= TOUR_START_DELAY and combat.shot_key == "backcut" and combat.state == combat.S.SHOT:
		vis_log.append({"t": snappedf(tour_t - TOUR_START_DELAY, 0.0001), "shot_t": snappedf(combat.shot_t, 0.0001), "mode": "hand",
			"hitstop": combat.hitstop_left, "label": cur_label, "probe": _contact_probe()})

## 側面相機：每次出招時定一次、整招固定；垂直於「角色→木樁」連線、站在連線右手側再往正面轉 20°；畫面中心放在角色與木樁中間偏後（要看得到後退）
var _bc_side_set := false
var _bc_side_locked := false

func _update_cam(snap: bool) -> void:
	var args := OS.get_cmdline_user_args()
	if not args.has("--cam=side"):
		super._update_cam(snap)
		return
	var firing := combat.state == combat.S.SHOT and combat.shot_key == "backcut"
	if not _bc_side_set or (firing and not _bc_side_locked):
		_bc_side_set = true
		_bc_side_locked = firing
		var to := enemy_pos - actor.global_position
		to.y = 0.0
		var yaw := atan2(to.x, to.z)
		var dir := Vector3(sin(yaw), 0, cos(yaw))
		var right := Vector3(-cos(yaw), 0, sin(yaw))
		var midp := actor.global_position + dir * (to.length() * 0.5 - 0.9) + Vector3(0, 1.0, 0)
		var cdir := right.rotated(Vector3.UP, -deg_to_rad(20.0))
		cam.global_position = midp + cdir * 5.0 + Vector3(0, 0.5, 0)
		cam.look_at(midp, Vector3.UP)
	if not firing:
		_bc_side_locked = false

func _build_tour() -> void:
	var dist := enemy_dist
	var E := {"enemy": [0.0, dist, 0.01]}
	_s(1.0, "主城劍客退步縱斬：一般架勢（敵人逼近）", Vector2.ZERO, E)
	_s(2.3, "舉刀過頂 → 邊退邊劈 → 命中 → 收勢", Vector2.ZERO, {"attack": 0.2})
	_s(0.8, "一般架勢（敵人再逼近）", Vector2.ZERO, E)
	_s(1.7, "退步縱斬 → 1.40 s 起可移動", Vector2.ZERO, {"attack": 0.2})
	_s(1.2, "移動取消：右移", Vector2(1, 0))
	_s(0.6, "停步", Vector2.ZERO, E)
	_s(1.6, "退步縱斬 → 1.00 s 起可閃避", Vector2.ZERO, {"attack": 0.2, "dodge": 1.3, "hold": 1.4, "side": -1.0})
	_s(1.2, "閃避後", Vector2.ZERO, {"enemy": [0.0, dist + 1.6, 0.01]})
	_s(2.3, "距離太遠＝空劈", Vector2.ZERO, {"attack": 0.2})
	_s(0.8, "一般架勢")

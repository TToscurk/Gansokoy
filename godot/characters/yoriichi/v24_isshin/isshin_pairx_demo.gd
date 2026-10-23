extends "res://characters/yoriichi/v24_isshin/isshin_thrust_demo.gd"
## 雙手交叉二連斬候選（獨立候選；不改正式 Player／跑酷／共用資產；居合斬、二連斬、突刺設定不動）：
## 一般架勢（刀在手上）→ K／J／左鍵＝雙手交叉二連斬（c1400 a000「剣客」a000_003072 → 橋接 → a000_003056）：左上→右下、刀回頭頂、右上→左下。
## 沿用候選的刀身判定（實際半徑、切入 5 cm、掃掠）、停在命中那一格的 Hit Stop、刀刃入口火花。
## 自動導覽：godot --path godot --write-movie out.avi --fixed-fps 60 res://characters/yoriichi/v24_isshin/isshin_pairx_demo.tscn -- --tour [--cam=third|side] [--dist=3.0]
## 調參：--pairx_cfg='{"min_dist": 1.2}'

func _ready() -> void:
	super._ready()
	combat.attack_key = "pairx"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--pairx_cfg="):
			combat.shot_override["pairx"] = JSON.parse_string(a.substr(12))

## 判定（只在這個候選覆寫）：條件同其他候選（只算刀身 u ≥ 0.25、木樁實際半徑、切入 5 cm），但幀間掃掠改成「刀的整個變換」插值
## （護手位置線性、刀的旋轉 slerp），而不是刀尖與護手各自直線插值。這招第二刀很快，30 fps 時一幀刀轉約 70°，直線插值的弦會
## 從木樁外面繞過去（30 fps 第二刀漏判）。範圍不變。
var _xf_prev := Transform3D()
var _xf_last := Transform3D()
var _xf_ok := false

func _process(delta: float) -> void:
	_xf_prev = _xf_last
	super._process(delta)
	if sword:
		_xf_ok = _xf_last != Transform3D()
		_xf_last = sword.global_transform

func _hit_test() -> Dictionary:
	if sword == null:
		return {}
	var cur := sword.global_transform
	var prev := _xf_prev if _xf_prev != Transform3D() else cur
	for k in range(1, 5):
		var w := float(k) / 4.0
		var xf := prev.interpolate_with(cur, w)
		var a := xf * GUARD_LOCAL
		var b := xf * TIP_LOCAL
		var best := 0.0
		var hit := {}
		for i in range(4, 17):
			var u := float(i) / 16.0
			var p := a.lerp(b, u)
			var hv := Vector2(p.x - enemy_pos.x, p.z - enemy_pos.z)
			var r := _dummy_r(p.y)
			var depth := r - hv.length()
			if p.y > 0.05 and p.y < 1.95 and depth > maxf(best, HIT_MIN_DEPTH):
				best = depth
				var n := hv.normalized() if hv.length() > 1e-3 else Vector2(0, -1)
				var dv := tip_v.normalized() if tip_v.length() > 0.5 else Vector3.DOWN
				hit = {"pos": Vector3(enemy_pos.x + n.x * r, p.y, enemy_pos.z + n.y * r), "dir": dv, "tip_speed": tip_speed, "blade_u": u, "depth": depth, "sub": w}
		if not hit.is_empty():
			return hit
	return {}

func _apply_sword_vis() -> void:
	super._apply_sword_vis()
	if tour and tour_t >= TOUR_START_DELAY and combat.shot_key == "pairx" and combat.state == combat.S.SHOT:
		vis_log.append({"t": snappedf(tour_t - TOUR_START_DELAY, 0.0001), "shot_t": snappedf(combat.shot_t, 0.0001), "mode": "hand",
			"hitstop": combat.hitstop_left, "label": cur_label, "probe": _contact_probe()})

## 側面相機：每次出招時定一次、整招固定；垂直於「角色→木樁」連線、站在連線右手側再往正面轉 20°；畫面中心放在角色與木樁中間
var _bc_side_set := false
var _bc_side_locked := false

func _update_cam(snap: bool) -> void:
	var args := OS.get_cmdline_user_args()
	if not args.has("--cam=side"):
		super._update_cam(snap)
		return
	var firing := combat.state == combat.S.SHOT and combat.shot_key == "pairx"
	if not _bc_side_set or (firing and not _bc_side_locked):
		_bc_side_set = true
		_bc_side_locked = firing
		var to := enemy_pos - actor.global_position
		to.y = 0.0
		var yaw := atan2(to.x, to.z)
		var dir := Vector3(sin(yaw), 0, cos(yaw))
		var right := Vector3(-cos(yaw), 0, sin(yaw))
		var midp := actor.global_position + dir * (to.length() * 0.5) + Vector3(0, 1.0, 0)
		var cdir := right.rotated(Vector3.UP, -deg_to_rad(20.0))
		cam.global_position = midp + cdir * 5.0 + Vector3(0, 0.5, 0)
		cam.look_at(midp, Vector3.UP)
	if not firing:
		_bc_side_locked = false

func _build_tour() -> void:
	var dist := enemy_dist
	var E := {"enemy": [0.0, dist, 0.01]}
	_s(1.0, "主城劍客雙手交叉二連斬：一般架勢", Vector2.ZERO, E)
	_s(3.0, "左上→右下 → 刀回頭頂 → 右上→左下 → 收勢", Vector2.ZERO, {"attack": 0.2})
	_s(0.8, "一般架勢", Vector2.ZERO, E)
	_s(2.1, "二連斬 → 1.85 s 起可移動", Vector2.ZERO, {"attack": 0.2})
	_s(1.2, "移動取消：左移", Vector2(-1, 0))
	_s(0.6, "停步", Vector2.ZERO, E)
	_s(2.1, "二連斬 → 1.42 s 起可閃避", Vector2.ZERO, {"attack": 0.2, "dodge": 1.85, "hold": 1.95, "side": 1.0})
	_s(1.2, "閃避後", Vector2.ZERO, {"enemy": [0.0, dist + 3.5, 0.01]})
	_s(3.0, "距離不夠＝兩刀都空", Vector2.ZERO, {"attack": 0.2})
	_s(0.8, "一般架勢")

extends "res://characters/yoriichi/player_camera_adapter.gd"
## P11 R2 候補 B — Third-Person Camera（**検証用の候補・未統合**）。
## player_camera_adapter.gd（Yoriichi 相機 session 所有）を変更せず、_process だけを override して検証する。
## 統合は docs/art_review/village_v2_p11/r2/patches/B_player_camera_adapter_slope_pitch.patch を所有者が適用する（本檔と同じ内容）。
##
## 変更点（使用者 P11 R2「在斜坡下行測試相機的動態俯仰調整，不得直接永久鎖定 pitch，也不得停用正常的相機碰撞」
##   「確認玩家不會被地形遮蔽，窄巷不會出現劇烈鏡頭跳動」）：
##   ① 下り坂の俯仰バイアス：足元中心の真下の面の傾き α ≥ SLOPE_MIN_DEG の下り坂を SLOPE_MIN_TIME 秒以上移動中は、実効 pitch を
##      −atan(tan α − SLOPE_LINE_K)（30° の參道で ≈ −0.43、上限 SLOPE_PITCH_MAX）まで “加算の偏り” で下げる。
##      頭→相機の線が背後の斜面より上を通る俯角（腕 8.5 m・頭 1.65 m からの幾何）。坂を降りきっても SLOPE_HOLD 秒は保持
##      （坂の下で背後の斜面に相機が潜らない）、その後・停止・上り坂では SLOPE_EASE で 0 へ戻る。
##      使用者の _target_pitch（マウス）は変えない＝自由に動かせる；すでに十分下を向いていれば偏りは 0（pitch を永久に固定しない）。
##      ※ 使用者指定の試験値 −0.35 固定（初版）は 30° の參道で相機が斜面すれすれに座り、頭が斜面に隠れる幀が 0.1 → 3.2 % に増えた
##        （docs/art_review/village_v2_p11/r2/cam_candB_fixed035/）。
##   ② 腕の長さ：縮む（壁・屋根・坂に当たる）時は SpringArm3D のまま即時（相機碰撞は止めない）、伸び戻る時だけ ARM_EXTEND m/s で
##      なめらかに（窄巷で建物を抜けた瞬間に 4–6 m 跳ね返るのを防ぐ）。
##   ※ v3（接触法線・即時）は段の縁や壁際の STUCK で −0.42 まで誤反応した（walk_candAB_Bv3/）→ v4：足元の面の法線＋0.3 s 持続。

const SLOPE_MIN_DEG := 18.0
const SLOPE_LINE_K := 0.12       # tan β = tan α − K（K ≈ 頭の高さ／腕の長さ − 余裕）
const SLOPE_PITCH_MAX := -0.6    # rad
const SLOPE_HOLD := 1.0          # s
const SLOPE_MIN_TIME := 0.3      # s（この時間続いた下り坂だけ）
const SLOPE_EASE := 0.9          # rad/s
const ARM_EXTEND := 6.0          # m/s

var _slope_bias := 0.0
var _slope_pitch := 0.0          # 直近の下り坂で要った実効 pitch（0＝なし）
var _slope_hold := 0.0
var _slope_time := 0.0
var _arm_eff := -1.0


func _slope_bias_target(delta: float) -> float:
	var b := _body as CharacterBody3D
	if b == null:
		return 0.0
	var hv := Vector2(b.velocity.x, b.velocity.z)
	var moving := hv.length() > 0.5
	var want := 0.0
	if b.is_on_floor() and moving:
		# 坂の判定は足元中心の真下の面の法線（縁・壁際の接触法線では反応しない）
		var o := b.global_position
		var rq := PhysicsRayQueryParameters3D.create(o + Vector3(0, 0.3, 0), o - Vector3(0, 0.6, 0), b.collision_mask)
		rq.exclude = [b.get_rid()]
		var h := b.get_world_3d().direct_space_state.intersect_ray(rq)
		if not h.is_empty():
			var n: Vector3 = h["normal"]
			var a := n.angle_to(Vector3.UP)
			var down := Vector2(n.x, n.z)
			if rad_to_deg(a) >= SLOPE_MIN_DEG and down.length() > 0.01 and hv.normalized().dot(down.normalized()) > 0.5:
				want = maxf(-atan(maxf(0.0, tan(a) - SLOPE_LINE_K)), SLOPE_PITCH_MAX)
	# 一瞬の傾き（段の縁・踏石）では反応しない：SLOPE_MIN_TIME 秒続いた下り坂だけ
	_slope_time = _slope_time + delta if want < 0.0 else 0.0
	if want < 0.0 and _slope_time >= SLOPE_MIN_TIME:
		_slope_pitch = want
		_slope_hold = SLOPE_HOLD
	elif moving and _slope_hold > 0.0:
		_slope_hold -= delta
	else:
		_slope_hold = 0.0
		_slope_pitch = 0.0
	if _slope_pitch >= 0.0:
		return 0.0
	return minf(0.0, _slope_pitch - _current_pitch)


func _process(delta: float) -> void:
	super(delta)
	if pivot == null:
		return
	# ① 下り坂の俯仰バイアス
	_slope_bias = move_toward(_slope_bias, _slope_bias_target(delta), SLOPE_EASE * delta)
	pivot.rotation = Vector3(clampf(_current_pitch + _slope_bias, pitch_min, pitch_max), _current_yaw, 0.0)
	# ② 腕：縮むのは即時、伸びるのはなめらかに
	if arm != null:
		var hit := arm.get_hit_length()
		if _arm_eff < 0.0:
			_arm_eff = _current_distance
		if hit < _arm_eff - 0.01:
			_arm_eff = hit
		else:
			_arm_eff = move_toward(_arm_eff, _current_distance, ARM_EXTEND * delta)
		arm.spring_length = minf(_current_distance, _arm_eff + 0.05)


## 検証用（診断ツールが読む）
func slope_bias() -> float:
	return _slope_bias

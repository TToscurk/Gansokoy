extends AnimatableBody3D
## 人間之里 NPC の簡易行動（P10 R3b Population Pilot）。crowd AI・navigation・schedule ではない。
##   idle   ：その場で Idle（向きは generator が決めた yaw＝攤位／話し相手）
##   patrol ：A↔B の短い往復。端で Idle を wait_min〜wait_max 秒、向きを滑らかに変えてから Walk。
##            高さは generator が焼いた path_y（0.25 m 毎、見えている最上面）を線形補間＝runtime の raycast なし。
##            歩く速さ＝clip の足の接地速度（walk_speed）×speed_scale → 足が滑らない。
##            玩家（group "player"）が進行方向 0.9 m 以内にいる間は立ち止まる（避讓システムではない、ぶつからないだけ）。
## 見た目は子の NPC（characters/npc/<id>/<id>.tscn＝封存 NPC Asset Library）。ここは封存外。
## 玩家の SpringArm3D はこの body を除外する（カメラが NPC に当たって縮まない）。玩家側の場景は変更しない。

@export_enum("idle", "patrol") var mode := "idle"
@export var path_xz := PackedVector2Array()
@export var path_y := PackedFloat32Array()
@export var walk_speed := 1.4
@export var wait_min := 2.0
@export var wait_max := 5.0
@export var seed_i := 0
## 開始時の状態（審圖の再現用）：0..1 は path 上の位置、負なら端で待つ。
@export var start_u := -1.0

var _npc: Node
var _rng := RandomNumberGenerator.new()
var _u := 0.0          # path 上の距離（m）
var _dir := 1          # +1＝A→B、-1＝B→A
var _wait := 0.0
var _walking := false
var _len := 0.0
var _cum := PackedFloat32Array()
var _yaw_goal := 0.0


func _ready() -> void:
	_npc = get_node_or_null("NPC")
	_rng.seed = seed_i
	sync_to_physics = false
	for sa in _scene_arms(get_tree()):
		(sa as SpringArm3D).add_excluded_object(get_rid())
	get_tree().node_added.connect(_on_node_added)
	if mode != "patrol" or path_xz.size() < 2:
		set_physics_process(false)
		return
	_cum.resize(path_xz.size())
	_cum[0] = 0.0
	for i in range(1, path_xz.size()):
		_cum[i] = _cum[i - 1] + path_xz[i].distance_to(path_xz[i - 1])
	_len = _cum[_cum.size() - 1]
	if start_u >= 0.0:
		_u = clampf(start_u, 0.0, 1.0) * _len
		_walking = true
		_dir = 1 if _rng.randf() < 0.5 else -1
	else:
		_u = 0.0
		_wait = _rng.randf_range(wait_min, wait_max) * 0.5
	_place(true)
	_anim(&"walk" if _walking else &"idle")


func _on_node_added(n: Node) -> void:
	if n is SpringArm3D:
		(n as SpringArm3D).add_excluded_object(get_rid())
		# 同じ frame の後続の actor が使う走査結果にも足す（frame 内キャッシュを陳腐化させない）
		if _arms_frame == Engine.get_process_frames():
			_arms_cache.append(n)


## P12 Wave 1：SpringArm3D の全樹走査は 1 process frame に 1 回だけ。
## 村の読込で 51 体が同じ frame に _ready → 以前は 87k 節点の root.find_children を 51 回（≈ 2.35 s）。
## 同じ frame 内で後から足された SpringArm3D は、先に _ready した actor の _on_node_added が上でキャッシュへ追加する。
static var _arms_cache: Array = []
static var _arms_frame := -1


static func _scene_arms(tree: SceneTree) -> Array:
	var f := Engine.get_process_frames()
	if f != _arms_frame:
		_arms_cache = tree.root.find_children("*", "SpringArm3D", true, false)
		_arms_frame = f
	var out: Array = []
	for a in _arms_cache:
		if is_instance_valid(a) and (a as Node).is_inside_tree():
			out.append(a)
	return out


func _anim(c: StringName) -> void:
	if _npc != null and _npc.get("animation") != c:
		_npc.call("play_clip", c, -1.0)


func _sample(u: float) -> Vector3:
	var i := 1
	while i < _cum.size() - 1 and _cum[i] < u:
		i += 1
	var seg := maxf(_cum[i] - _cum[i - 1], 1e-4)
	var t := clampf((u - _cum[i - 1]) / seg, 0.0, 1.0)
	var p := path_xz[i - 1].lerp(path_xz[i], t)
	# path_y は 0.25 m 毎（u に対して等間隔）
	var fy := u / 0.25
	var k := clampi(floori(fy), 0, path_y.size() - 2)
	var k2 := k + 1
	var span := minf(0.25, _len - k * 0.25)
	var y := lerpf(path_y[k], path_y[k2], clampf((u - k * 0.25) / maxf(span, 1e-6), 0.0, 1.0))
	return Vector3(p.x, y, p.y)


func _place(snap_yaw: bool) -> void:
	var p := _sample(_u)
	var ahead := _sample(clampf(_u + 0.3 * _dir, 0.0, _len)) - p
	if ahead.length_squared() > 1e-6:
		_yaw_goal = atan2(ahead.x, ahead.z)   # NPC の正面＝+Z
	global_position = p
	if snap_yaw:
		rotation.y = _yaw_goal


## P11 R2B TASK04：rotate_toward は角度の値を線形に寄せるので、±π を跨ぐ目標だと
## 遠回り（最大ほぼ 1 周）する。最短弧（angle_difference）で寄せる。
const TURN_RATE := 2.6


static func _turn(from: float, to: float, step: float) -> float:
	var d := angle_difference(from, to)
	return wrapf(from + clampf(d, -step, step), -PI, PI)


func _blocked() -> bool:
	var pl := get_tree().get_first_node_in_group("player") as Node3D
	if pl == null:
		return false
	var d := pl.global_position - global_position
	d.y = 0.0
	if d.length() > 0.9:
		return false
	var fwd := Vector3(sin(rotation.y), 0.0, cos(rotation.y))
	return d.normalized().dot(fwd) > 0.3


func _physics_process(dt: float) -> void:
	if not _walking:
		# P11 R2B TASK04：折返は最短弧で、足踏み（walk clip）しながら振り向く。Idle のまま独楽のように回らない。
		if absf(angle_difference(rotation.y, _yaw_goal)) > 0.12:
			_anim(&"walk")
			rotation.y = _turn(rotation.y, _yaw_goal, TURN_RATE * dt)
			return
		_anim(&"idle")
		_wait -= dt
		if _wait <= 0.0:
			_walking = true
			_anim(&"walk")
		return
	if _blocked():
		_anim(&"idle")
		return
	_anim(&"walk")
	var sp := walk_speed * float(_npc.get("speed_scale") if _npc != null else 1.0)
	# 向きが目標から大きくずれている間は進まない（その場で振り向く）
	var dy := absf(angle_difference(rotation.y, _yaw_goal))
	_u = clampf(_u + sp * dt * _dir * (0.0 if dy > 1.2 else 1.0), 0.0, _len)
	_place(false)
	rotation.y = _turn(rotation.y, _yaw_goal, 4.0 * dt)
	if (_dir > 0 and _u >= _len) or (_dir < 0 and _u <= 0.0):
		_dir = -_dir
		_walking = false
		_wait = _rng.randf_range(wait_min, wait_max)
		_anim(&"idle")
		# 端で振り返る向き
		var p := _sample(_u)
		var back := _sample(clampf(_u + 0.3 * _dir, 0.0, _len)) - p
		if back.length_squared() > 1e-6:
			_yaw_goal = atan2(back.x, back.z)

extends Node3D
class_name Kedama
## 毛玉 —— 東方裡最基本的小妖怪。程序化造型：一顆毛球 + 兩顆眼睛，
## 沒有外部資產。做成通用小妖怪，逃跑妖怪與受傷妖怪都用它。
##
## 行為只有三種，由 mode 決定：
##   IDLE     原地飄浮呼吸
##   FLEE     看到玩家就往 flee_dir 跑，跑出 flee_distance 後消失（MQ03 不要追）
##   WOUNDED  縮在地上發抖，不動（受傷妖怪事件；離開由劇情腳本呼叫 flee_away()）
##
## 不認識任務、不認識對話；只發訊號。

enum Mode { IDLE, FLEE, WOUNDED }

signal fled          # 逃離完成（已消失）
signal noticed_player

@export var mode: Mode = Mode.IDLE
@export var radius := 0.32
@export var body_color := Color(0.93, 0.93, 0.95)
@export var eye_color := Color(0.12, 0.10, 0.14)
## 毛的根數與長度
@export var fur_count := 42
@export var fur_length := 0.14
## 飄浮高度（毛玉是飄的，不是站的）
@export var hover_height := 0.55
@export var bob_amount := 0.06
@export var bob_speed := 1.8

@export_group("Flee")
## 玩家進入這個距離就開始逃
@export var notice_range := 7.0
@export var flee_speed := 6.5
## 逃這麼遠就消失
@export var flee_distance := 18.0
## 逃跑方向（世界座標、水平）。留零則背對玩家跑
@export var flee_dir := Vector3.ZERO

@export_group("Wounded")
## 發抖幅度
@export var tremble := 0.025

var _t := 0.0
var _noticed := false
var _fled_dist := 0.0
var _base_y := 0.0
var _body: MeshInstance3D = null
var _target: Node3D = null


func _ready() -> void:
	add_to_group("kedama")
	_build()
	_base_y = position.y


func _build() -> void:
	# 本體
	_body = MeshInstance3D.new()
	_body.name = "Body"
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 20
	sm.rings = 12
	_body.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = body_color
	mat.roughness = 0.95
	_body.material_override = mat
	_body.position.y = hover_height
	add_child(_body)

	# 毛：細圓柱從球面往外長，帶隨機角度
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260908
	var fur_mat := StandardMaterial3D.new()
	fur_mat.albedo_color = body_color.darkened(0.08)
	fur_mat.roughness = 1.0
	for i in fur_count:
		var f := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.004
		cm.bottom_radius = 0.016
		cm.height = fur_length * rng.randf_range(0.7, 1.3)
		cm.radial_segments = 5
		f.mesh = cm
		f.material_override = fur_mat
		# 均勻分佈在球面上（黃金螺旋）
		var phi := acos(1.0 - 2.0 * (float(i) + 0.5) / float(fur_count))
		var theta := PI * (1.0 + sqrt(5.0)) * float(i)
		var dir := Vector3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))
		# 圓柱 +y 對齊 dir，再稍微歪一點
		f.position = dir * radius
		var up := Vector3.UP
		var axis := up.cross(dir)
		if axis.length() > 0.001:
			f.basis = Basis(axis.normalized(), up.angle_to(dir))
		f.rotate_object_local(Vector3.RIGHT, rng.randf_range(-0.35, 0.35))
		f.position += dir * cm.height * 0.5
		_body.add_child(f)

	# 眼睛：兩顆黑珠，在正面（+z）
	for sx in [-1.0, 1.0]:
		var e := MeshInstance3D.new()
		var em := SphereMesh.new()
		em.radius = radius * 0.16
		em.height = em.radius * 2.0
		em.radial_segments = 10
		em.rings = 6
		e.mesh = em
		var emat := StandardMaterial3D.new()
		emat.albedo_color = eye_color
		emat.roughness = 0.3
		e.material_override = emat
		var ed := Vector3(sx * 0.32, 0.18, 0.92).normalized()
		e.position = ed * radius * 0.96
		_body.add_child(e)


func _process(delta: float) -> void:
	_t += delta
	if _target == null:
		var ps := get_tree().get_nodes_in_group("player")
		if ps.size() > 0:
			_target = ps[0]
	match mode:
		Mode.IDLE:
			_body.position.y = hover_height + sin(_t * bob_speed) * bob_amount
		Mode.WOUNDED:
			# 縮在地上、細微發抖
			_body.position.y = radius * 0.85 + sin(_t * 23.0) * tremble
			_body.position.x = sin(_t * 31.0) * tremble * 0.6
			# 縮小一點，看起來蜷著
			_body.scale = Vector3.ONE * 0.88
			if _target != null:
				var to := _target.global_position - global_position
				to.y = 0.0
				if to.length() > 0.01:
					# 面向玩家（害怕地盯著）
					var want := atan2(to.x, to.z)
					rotation.y = lerp_angle(rotation.y, want, 4.0 * delta)
		Mode.FLEE:
			_body.position.y = hover_height + sin(_t * bob_speed * 2.5) * bob_amount * 1.5
			if not _noticed:
				if _target != null and global_position.distance_to(_target.global_position) <= notice_range:
					_noticed = true
					noticed_player.emit()
					if flee_dir.length() < 0.01:
						var away := global_position - _target.global_position
						away.y = 0.0
						flee_dir = away.normalized() if away.length() > 0.01 else Vector3.FORWARD
				return
			var step: Vector3 = flee_dir.normalized() * flee_speed * delta
			position += step
			_fled_dist += step.length()
			# 面向逃跑方向
			var want := atan2(flee_dir.x, flee_dir.z)
			rotation.y = lerp_angle(rotation.y, want, 8.0 * delta)
			if _fled_dist >= flee_distance:
				fled.emit()
				queue_free()


## 劇情呼叫：受傷妖怪被放走 → 慢慢退後再逃
func flee_away(dir: Vector3 = Vector3.ZERO) -> void:
	if dir.length() > 0.01:
		flee_dir = dir
	elif _target != null:
		var away := global_position - _target.global_position
		away.y = 0.0
		flee_dir = away.normalized() if away.length() > 0.01 else Vector3.FORWARD
	mode = Mode.FLEE
	_noticed = true
	_fled_dist = 0.0
	_body.scale = Vector3.ONE

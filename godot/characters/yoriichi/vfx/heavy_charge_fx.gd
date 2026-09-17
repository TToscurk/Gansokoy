extends Node3D
class_name HeavyChargeFX
## RMB 長按蓄力（拔刀斬）的刀身特效。掛在 Sword_Hand 下、由 yoriichi_character 持有，
## 一次建好、重複用（start / set_progress / flash_ready / stop），不每次生成銷毀。
##
## 三層各自一個職責、各自可關（滑桿拉到 0 = 該層關掉）：
##   1. 刀身升溫 —— 刀材質 emission 由琥珀走到白熱，能量隨蓄力比例升。
##      ⚠ GLB 的 material.004 是共用資源，必須 duplicate 成 surface override，收招時還原 null。
##   2. 內聚火星 —— 以刀身中段為球心，火星從外圍被「吸」向刀身（radial_velocity 負值）。
##      這是「刀在聚光」，不是噴火：方向與 spawn_form_ignite（往外噴）刻意相反。
##   3. 暖光 —— 刀根一盞 OmniLight，能量隨比例升。只負責照角色，不當火焰形狀用。
## 滿蓄瞬間 flash_ready()：一次短白金閃光 ＋ 沿刀身一次火星噴流（重用 CombatVFX.spawn_form_ignite）。
##
## 視覺層級：蓄力 < 型起手 < 忍殺 —— 持續 3 秒的東西必須比一瞬間的爆發更收斂，
## 否則整段蓄力都在 bloom 裡，落刀那一下反而沒份量。

const CombatVFX = preload("res://characters/yoriichi/vfx/combat_vfx.gd")

@export_group("Blade Heat")
## 刀身 emission 最大能量（滿蓄時）。專案 glow_hdr_threshold 1.05~1.25：只有最後一段才進 bloom。0 = 關。
## 1.6 實拍滿蓄時手＋柄一起過曝；1.2 讓刀身白熱、手還看得見輪廓。
@export_range(0.0, 4.0, 0.05) var emission_max := 1.2
@export var emission_color_start := Color(1.000, 0.616, 0.110)   # 琥珀
@export var emission_color_end := Color(1.000, 0.984, 0.910)     # 白熱

@export_group("Pull Sparks")
## 火星數量。0 = 關。（28 顆實拍看不出「往刀身收」，48 顆才讀得出方向）
@export_range(0, 96, 1) var spark_amount := 48
## 火星出生半徑（公尺，以刀身中段為球心）。
@export_range(0.1, 2.0, 0.05) var spark_radius := 1.1
## 火星被吸向刀身的速度（m/s）。壽命 = 半徑 ÷ 速度，火星剛好在刀身上熄滅。
@export_range(0.2, 6.0, 0.1) var spark_pull_speed := 2.2

@export_group("Warm Light")
## 刀根暖光最大能量（滿蓄時）。0 = 關。
@export_range(0.0, 4.0, 0.05) var light_energy_max := 1.2
@export_range(0.5, 6.0, 0.1) var light_range := 2.6

@export_group("Timing")
## stop(false) 的淡出秒數。0 = 立即。
@export_range(0.0, 1.0, 0.01) var fade_out_time := 0.18

## 刀模型（由 character 指定；null = 沒有升溫層）。
var sword_mesh: MeshInstance3D = null
## Sword_Hand 局部座標：刀根 0.1、刀尖 1.05 → 中段 0.55。
var blade_mid := Vector3(0, 0.55, 0)

var _mat: StandardMaterial3D = null
var _prev_override: Material = null
var _sparks: GPUParticles3D = null
var _light: OmniLight3D = null
var _progress := 0.0
var _active := false
var _fade_left := -1.0
var _fade_from := 0.0


func _ready() -> void:
	visible = false
	position = blade_mid

	_light = OmniLight3D.new()
	_light.name = "ChargeLight"
	_light.light_color = emission_color_start
	_light.light_energy = 0.0
	_light.omni_range = light_range
	_light.omni_attenuation = 1.4
	_light.shadow_enabled = false
	# 放在刀身中段（節點原點），不是刀根：實拍燈在刀根時手＋柄過曝成一塊白。
	_light.position = Vector3.ZERO
	add_child(_light)

	_sparks = GPUParticles3D.new()
	_sparks.name = "PullSparks"
	_sparks.emitting = false
	_sparks.one_shot = false
	_sparks.local_coords = true          # 跟著手走：火星是被刀吸住的，不是留在原地
	_sparks.amount = maxi(spark_amount, 1)
	_sparks.lifetime = spark_radius / maxf(spark_pull_speed, 0.05)
	_sparks.explosiveness = 0.0
	_sparks.randomness = 0.6
	_sparks.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
	pm.emission_sphere_radius = spark_radius
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.0
	# 負徑向速度 = 往 velocity_pivot（此節點原點 = 刀身中段）收。
	pm.velocity_pivot = Vector3.ZERO
	pm.radial_velocity_min = -spark_pull_speed * 1.15
	pm.radial_velocity_max = -spark_pull_speed * 0.85
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.5
	pm.scale_max = 0.9
	var g := Gradient.new()
	g.set_color(0, Color(CombatVFX.C_CRIMSON.r, CombatVFX.C_CRIMSON.g, CombatVFX.C_CRIMSON.b, 0.0))
	g.add_point(0.25, CombatVFX.C_AMBER)
	g.add_point(0.75, CombatVFX.C_GOLD)
	g.add_point(0.94, CombatVFX.C_CORE)
	g.set_color(1, Color(CombatVFX.C_CORE.r, CombatVFX.C_CORE.g, CombatVFX.C_CORE.b, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	_sparks.process_material = pm

	var quad := QuadMesh.new()
	quad.size = Vector2(0.035, 0.26)   # 拉長：短 streak 讀成散點，看不出往刀身收
	quad.material = CombatVFX._make_draw_mat(CombatVFX._get_streak_texture(), false, true)
	_sparks.draw_pass_1 = quad
	add_child(_sparks)


func is_active() -> bool:
	return _active


func progress() -> float:
	return _progress


## 開始蓄力：掛上刀材質 override、火星開始內聚。
func start() -> void:
	_fade_left = -1.0
	_active = true
	_progress = 0.0
	visible = true
	if sword_mesh != null and _mat == null and emission_max > 0.0:
		_prev_override = sword_mesh.get_surface_override_material(0)
		var src := sword_mesh.get_active_material(0)
		if src is StandardMaterial3D:
			_mat = (src as StandardMaterial3D).duplicate()
			_mat.emission_enabled = true
			sword_mesh.set_surface_override_material(0, _mat)
	if _sparks != null and spark_amount > 0:
		if _sparks.amount != spark_amount:
			_sparks.amount = spark_amount   # 只在滑桿改過時重配 GPU buffer
		_sparks.restart()
		_sparks.emitting = true
	_apply(0.0)


## 蓄力比例 0~1。
func set_progress(t: float) -> void:
	if not _active:
		return
	_progress = clampf(t, 0.0, 1.0)
	_apply(_progress)


## 滿蓄的一瞬：短白金閃光 ＋ 沿刀身一次火星噴流。
func flash_ready(origin: Vector3, blade_dir: Vector3, owner_node: Node) -> void:
	if not is_inside_tree():
		return
	CombatVFX._flash_light(get_tree().root, origin + Vector3(0, 0.3, 0), Color(1.0, 0.92, 0.72), 3.2, 3.0, 0.12)
	CombatVFX.spawn_form_ignite(owner_node, origin, blade_dir)


## 結束。immediate = 同幀清乾淨（受擊／死亡／換場）；否則依 fade_out_time 淡出。
func stop(immediate: bool = false) -> void:
	if not _active and _fade_left < 0.0:
		return
	_active = false
	if _sparks != null:
		_sparks.emitting = false
	if immediate or fade_out_time <= 0.0:
		_clear()
		return
	_fade_from = _progress
	_fade_left = fade_out_time


func _process(delta: float) -> void:
	if _fade_left < 0.0:
		return
	_fade_left -= delta
	if _fade_left <= 0.0:
		_clear()
		return
	_apply(_fade_from * (_fade_left / maxf(fade_out_time, 0.001)))


func _apply(t: float) -> void:
	var col := emission_color_start.lerp(emission_color_end, t)
	if _mat != null:
		_mat.emission = col
		# 前段緩、後段陡：最後 0.5 s 才真的白熱，讀得出「快滿了」。
		_mat.emission_energy_multiplier = emission_max * (t * t)
	if _light != null:
		_light.light_color = col
		_light.light_energy = light_energy_max * t
		_light.omni_range = light_range


func _clear() -> void:
	_fade_left = -1.0
	_progress = 0.0
	visible = false
	if _light != null:
		_light.light_energy = 0.0
	if _sparks != null:
		_sparks.emitting = false
	if sword_mesh != null and _mat != null:
		sword_mesh.set_surface_override_material(0, _prev_override)
	_prev_override = null
	_mat = null


## 衝刺速度線：top_level 節點放在世界座標、每幀跟著角色位置走（_process），方向直接用世界向量 ——
## 掛在角色下會被 CharacterBody3D 的 yaw（鎖定時 root 也會轉）再轉一次，方向就歪了。
## 粒子留在經過的路上、往衝刺反方向掃，讀成「人衝過去、光線留在後面」。發射 dash_time 秒後自動停、燒完自刪。
static func spawn_dash_streaks(owner_node: Node3D, dash_dir: Vector3, dash_time: float) -> void:
	if owner_node == null or not owner_node.is_inside_tree():
		return
	var dir := dash_dir.normalized() if dash_dir.length_squared() > 0.0001 else Vector3.FORWARD
	var p := _DashFollow.new()
	p.follow = owner_node
	p.name = "IaiDashStreaks"
	p.top_level = true
	p.local_coords = false
	p.one_shot = false
	p.emitting = false
	p.amount = 40
	p.lifetime = 0.22
	p.explosiveness = 0.0
	p.randomness = 0.4
	p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.35, 0.55, 0.35)
	pm.direction = -dir
	pm.spread = 10.0
	pm.initial_velocity_min = 5.0
	pm.initial_velocity_max = 9.0
	pm.gravity = Vector3.ZERO
	pm.damping_min = 6.0
	pm.damping_max = 10.0
	pm.scale_min = 0.8
	pm.scale_max = 1.4
	var g := Gradient.new()
	g.set_color(0, CombatVFX.C_CORE)
	g.add_point(0.35, CombatVFX.C_GOLD)
	g.add_point(0.8, Color(CombatVFX.C_AMBER.r, CombatVFX.C_AMBER.g, CombatVFX.C_AMBER.b, 0.5))
	g.set_color(1, Color(CombatVFX.C_CRIMSON.r, CombatVFX.C_CRIMSON.g, CombatVFX.C_CRIMSON.b, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.03, 0.55)
	quad.material = CombatVFX._make_draw_mat(CombatVFX._get_streak_texture(), true, true)
	p.draw_pass_1 = quad
	owner_node.add_child(p)
	p.global_transform = Transform3D(Basis.IDENTITY, owner_node.global_position + Vector3(0, 1.0, 0))
	p.restart()
	p.emitting = true
	var tree := owner_node.get_tree()
	tree.create_timer(maxf(dash_time, 0.05)).timeout.connect(func() -> void:
		if is_instance_valid(p):
			p.emitting = false)
	tree.create_timer(maxf(dash_time, 0.05) + p.lifetime + 0.2).timeout.connect(func() -> void:
		if is_instance_valid(p):
			p.queue_free())


## 速度線發射器跟著角色位置（不跟旋轉）。
class _DashFollow extends GPUParticles3D:
	var follow: Node3D = null
	func _process(_delta: float) -> void:
		if follow != null and is_instance_valid(follow):
			global_position = follow.global_position + Vector3(0, 1.0, 0)

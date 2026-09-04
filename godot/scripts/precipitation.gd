@tool
class_name 降水效果
extends Node3D
## Rain and snow that follow the camera.
##
## Why camera-following rather than a world-sized emitter: covering the whole
## 500 m village in raindrops would need hundreds of thousands of particles for
## a handful that are ever on screen. Instead a modest volume rides above the
## camera — the player is always at the centre of the storm, which is also how
## it feels in reality.
##
## Two separate emitters rather than one recoloured system: rain is fast,
## stretched and nearly vertical; snow is slow, round and drifts sideways.
## Trying to blend one into the other gives fast snow or floaty rain.
##
## Intensity is driven from 天象系統 so weather stays in one place; this node
## only renders what it is told.

## 0 = 無，1 = 最大。由天象系統設定，也可手動測試。
@export_range(0.0, 1.0, 0.01) var 強度: float = 0.0:
	set(v):
		# 天象系統 pushes this every frame while a weather lerp converges.
		# Only a real change may dirty us: _apply() rebuilds the particle
		# material, mesh and shader material, and doing that per frame was
		# ~600 ms of _process (probe_process_cost 2026-09-03).
		if is_equal_approx(強度, v):
			return
		強度 = v
		_dirty = true

enum 種類 { 雨, 雪 }

@export var 降水種類: 種類 = 種類.雨:
	set(v):
		if 降水種類 == v:
			return
		降水種類 = v
		_dirty = true

## 覆蓋半徑（公尺）。太小會看到邊界，太大會浪費粒子。
@export_range(4.0, 40.0, 1.0) var 覆蓋半徑: float = 14.0:
	set(v):
		覆蓋半徑 = v
		_dirty = true

## 最大粒子數（強度 1.0 時）。
@export_range(100, 4000, 50) var 最大粒子數: int = 1400:
	set(v):
		最大粒子數 = v
		_dirty = true

## 風的水平方向與強度。雪受風影響遠大於雨。
@export var 風: Vector3 = Vector3(1.2, 0.0, 0.4):
	set(v):
		風 = v
		_dirty = true

## 自動跟隨目前相機。關掉的話這個節點自己就是中心。
@export var 跟隨相機: bool = true

var _rain: GPUParticles3D
var _snow: GPUParticles3D
var _dirty := true


func _ready() -> void:
	_build()
	_dirty = true
	set_process(true)


func _process(_delta: float) -> void:
	if 跟隨相機:
		var cam := get_viewport().get_camera_3d()
		if cam:
			# Sit above and slightly ahead of the camera so particles are
			# already falling when they enter view rather than popping in.
			var fwd := -cam.global_transform.basis.z
			global_position = cam.global_position \
				+ Vector3(fwd.x, 0, fwd.z).normalized() * 覆蓋半徑 * 0.25 \
				+ Vector3.UP * 覆蓋半徑 * 0.55
	if _dirty:
		_apply()
		_dirty = false


func _build() -> void:
	_rain = get_node_or_null("雨") as GPUParticles3D
	if _rain == null:
		_rain = GPUParticles3D.new()
		_rain.name = "雨"
		add_child(_rain)
		if Engine.is_editor_hint() and owner:
			_rain.owner = owner

	_snow = get_node_or_null("雪") as GPUParticles3D
	if _snow == null:
		_snow = GPUParticles3D.new()
		_snow.name = "雪"
		add_child(_snow)
		if Engine.is_editor_hint() and owner:
			_snow.owner = owner


func _apply() -> void:
	if _rain == null:
		_build()

	var r := 覆蓋半徑
	var h := r * 1.1

	# Both systems get an explicit AABB. Without it Godot culls the emitter as
	# soon as its origin leaves the frustum and the precipitation blinks out.
	var box := AABB(Vector3(-r, -h, -r), Vector3(r * 2.0, h * 2.0, r * 2.0))

	# ── 雨 ──
	_rain.visible = 降水種類 == 種類.雨 and 強度 > 0.01
	_rain.emitting = _rain.visible
	if _rain.visible:
		_rain.amount = maxi(1, int(最大粒子數 * 強度))
		_rain.lifetime = 1.1
		_rain.local_coords = false
		_rain.visibility_aabb = box
		# Preprocess so the volume is already full of rain the instant weather
		# turns, instead of raining from an empty sky for a second.
		_rain.preprocess = 1.0
		_rain.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH

		var m := ParticleProcessMaterial.new()
		m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		m.emission_box_extents = Vector3(r, 0.5, r)
		m.direction = Vector3(0, -1, 0)
		m.spread = 2.0
		m.initial_velocity_min = 13.0
		m.initial_velocity_max = 18.0
		m.gravity = Vector3(0, -22.0, 0) + 風 * 1.5
		m.scale_min = 0.7
		m.scale_max = 1.3
		_rain.process_material = m

		# A stretched quad, not a sphere: a raindrop at speed reads as a streak.
		var quad := QuadMesh.new()
		quad.size = Vector2(0.012, 0.42)
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.78, 0.85, 0.95, 0.42)
		# Y-billboard keeps the streak vertical while still facing the camera;
		# full billboard would spin the streaks as the player turns.
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
		mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		mat.no_depth_test = false
		quad.material = mat
		_rain.draw_pass_1 = quad

	# ── 雪 ──
	_snow.visible = 降水種類 == 種類.雪 and 強度 > 0.01
	_snow.emitting = _snow.visible
	if _snow.visible:
		_snow.amount = maxi(1, int(最大粒子數 * 0.55 * 強度))
		_snow.lifetime = 7.0
		_snow.local_coords = false
		_snow.visibility_aabb = box
		_snow.preprocess = 5.0
		_snow.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH

		var m2 := ParticleProcessMaterial.new()
		m2.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		m2.emission_box_extents = Vector3(r, 0.5, r)
		m2.direction = Vector3(0, -1, 0)
		m2.spread = 22.0
		m2.initial_velocity_min = 0.7
		m2.initial_velocity_max = 1.9
		m2.gravity = Vector3(0, -1.1, 0) + 風 * 0.8
		m2.scale_min = 0.5
		m2.scale_max = 1.5
		# Turbulence gives the drifting, tumbling path that separates snow from
		# slow rain. Desktop-only cost, which this project is.
		m2.turbulence_enabled = true
		m2.turbulence_noise_strength = 0.9
		m2.turbulence_noise_scale = 2.2
		m2.turbulence_influence_min = 0.15
		m2.turbulence_influence_max = 0.45
		_snow.process_material = m2

		var q2 := QuadMesh.new()
		q2.size = Vector2(0.05, 0.05)
		var mat2 := StandardMaterial3D.new()
		mat2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat2.albedo_color = Color(1, 1, 1, 0.85)
		mat2.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		mat2.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		q2.material = mat2
		_snow.draw_pass_1 = q2

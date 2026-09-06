extends Node3D
class_name SunDragon
## 玖ノ型 日暈龍・頭舞 finisher effect.
## Blender-authored geometry (assets/vfx/sun_dragon.glb) driven by a procedural
## flame shader: the body sweeps in tail-to-head, then burns away.

const SCENE := preload("res://assets/vfx/sun_dragon.glb")
const SHADER := preload("res://characters/yoriichi/vfx/sun_dragon.gdshader")
const SND_FIRE := preload("res://assets/audio/sfx/dragon_fire_loop.wav")
const SND_WIND := preload("res://assets/audio/sfx/dragon_wind_loop.wav")

## Seconds for the dragon to sweep fully into existence.
@export var reveal_time := 0.55
## Seconds it lingers at full body before dissolving.
@export var hold_time := 0.35
## Seconds to burn away, tail first.
@export var burn_time := 0.60
@export var flame_color := Color(1.0, 0.28, 0.02)
@export var intensity := 1.6
## 龍頭追向的節點（通常是刀尖）；未設定時維持出招方向。
@export var track_node: Node3D
## 龍頭轉向速度（度／秒）；越低越沉穩。
@export_range(30.0, 1080.0, 10.0) var track_turn_speed := 320.0
@export_range(-40.0, 40.0, 0.5) var fire_volume_db := -6.0
@export_range(-40.0, 40.0, 0.5) var wind_volume_db := -4.0

var _reveal := 0.0
var _burn := 0.0
var _elapsed := 0.0
var _materials: Array[ShaderMaterial] = []
var _light: OmniLight3D
var _follow: Node3D
var _follow_offset := Vector3.ZERO
var _fire: AudioStreamPlayer3D
var _wind: AudioStreamPlayer3D
var _yaw := 0.0


static func spawn(host: Node, xform: Transform3D) -> SunDragon:
	if host == null or not host.is_inside_tree():
		return null
	var d := SunDragon.new()
	d.name = "SunDragon"
	d.top_level = true
	if host is Node3D:
		# The body circles the actor, so it must follow him instead of the spawn point.
		d._follow = host
		d._follow_offset = (host as Node3D).global_position - xform.origin
	host.get_tree().root.add_child(d)
	d.global_transform = xform
	return d


func _ready() -> void:
	var model := SCENE.instantiate()
	add_child(model)
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Never culled mid-swing by its authored (static) AABB.
		mi.extra_cull_margin = 6.0
		for s in mi.mesh.get_surface_count():
			var mat := ShaderMaterial.new()
			mat.shader = SHADER
			mat.render_priority = 1
			mi.set_surface_override_material(s, mat)
			_materials.append(mat)

	# The finisher lights its own surroundings; a bright body with no bounce reads as a decal.
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.55, 0.18)
	_light.omni_range = 12.0
	_light.light_energy = 0.0
	_light.position = Vector3(0, 1.2, 0)
	add_child(_light)

	# 火在燒與風在吹：兩層獨立循環，隨招式生滅。
	_fire = _make_loop(SND_FIRE, fire_volume_db, 18.0)
	_wind = _make_loop(SND_WIND, wind_volume_db, 24.0)
	_yaw = rotation.y
	_push()


## 建一個循環播放的 3D 音源；WAV 匯入預設不循環，這裡明確設定。
func _make_loop(stream: AudioStream, volume_db: float, distance: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	var s := stream
	if s is AudioStreamWAV:
		s = (s as AudioStreamWAV).duplicate()
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = s.data.size() / 2
	p.stream = s
	p.volume_db = volume_db
	p.max_distance = distance
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.position = Vector3(0, 1.0, 0)
	add_child(p)
	p.play()
	return p


func get_reveal() -> float:
	return _reveal


func get_burn() -> float:
	return _burn


func _push() -> void:
	for mat in _materials:
		mat.set_shader_parameter("reveal", _reveal)
		mat.set_shader_parameter("burn", _burn)
		mat.set_shader_parameter("flame_color", flame_color)
		mat.set_shader_parameter("intensity", intensity)


## Follow in the physics step so the body stays centred on a moving actor
## instead of trailing a frame behind his CharacterBody3D motion.
func _physics_process(delta: float) -> void:
	if is_instance_valid(_follow) and _follow.is_inside_tree():
		global_position = _follow.global_position - _follow_offset
	_track_head(delta)


## 龍頭（模型 +X）追向刀尖的水平方位，用角速度上限避免瞬間彈動。
func _track_head(delta: float) -> void:
	if not is_instance_valid(track_node) or not track_node.is_inside_tree():
		return
	var to_blade := track_node.global_position - global_position
	to_blade.y = 0.0
	if to_blade.length_squared() < 0.0004:
		return
	var target := atan2(to_blade.z, to_blade.x)
	var step := deg_to_rad(track_turn_speed) * delta
	_yaw += clampf(wrapf(target - _yaw, -PI, PI), -step, step)
	# 只轉水平方位，龍身保持水平，不會翻倒。
	global_transform.basis = Basis(Vector3.UP, -_yaw).scaled(Vector3.ONE * scale.x)


func _process(delta: float) -> void:
	# A load hitch on the first frame must not skip the sweep-in; clamp to ~3 frames.
	_elapsed += minf(delta, 0.05)
	_reveal = clampf(_elapsed / maxf(reveal_time, 0.0001), 0.0, 1.0)
	var burn_start := reveal_time + hold_time
	_burn = clampf((_elapsed - burn_start) / maxf(burn_time, 0.0001), 0.0, 1.0)
	if _light != null:
		# Bright while the body sweeps in, fading out as it burns away.
		_light.light_energy = 6.0 * _reveal * (1.0 - _burn)
	_push()
	if _burn >= 1.0:
		queue_free()

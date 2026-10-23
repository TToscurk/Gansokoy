extends Node3D
## 傳送點地面光印（美術依據：docs/reference/傳送點美術/幻想鄉神社傳送點設計提案.png）。
##  - 嵌在地面的圓形石盤＋櫻花紋＋結界同心環（Decal 投影，貼合石板／土／草的起伏）
##  - 玩家接近時緩慢點亮（約 1.6 s），花瓣與光粒向上飄
##  - 夜間（DayNight.is_night）增亮，確保辨識
##  - 色系依所在地：神社＝櫻粉、獸道＝青藍、人里與其他＝金黃
## main.gd 的 _spawn_portals 把它以 "GlowGate" 之名掛在 Portal_* Area3D 下（verify_*portal* 依名字找）。
## 節點原點＝傳送點地面高（Area3D 中心往下 1 m）。

const TEX_STONE := preload("res://assets/portal/seal_stone.png")
const TEX_CORE := preload("res://assets/portal/seal_core.png")
const TEX_GLYPH := preload("res://assets/portal/seal_glyph.png")
const TEX_PETAL := preload("res://assets/portal/petal.png")
const TEX_MOTE := preload("res://assets/portal/mote.png")

const PALETTES := {
	"shrine": {"glow": Color(1.0, 0.50, 0.74), "petal": Color(1.0, 0.80, 0.90), "stone_mix": 0.85},
	"trail": {"glow": Color(0.32, 0.68, 1.0), "petal": Color(0.72, 0.90, 1.0), "stone_mix": 0.55},
	"village": {"glow": Color(1.0, 0.68, 0.28), "petal": Color(1.0, 0.86, 0.56), "stone_mix": 0.80},
}

@export_enum("shrine", "trail", "village") var palette := "village"
## 光印直徑（m）。觸發區半徑 1.6 m；石盤略大一圈。
@export var diameter := 3.8
## 遠處待機亮度（0..1）與完全點亮的距離
@export var idle_level := 0.30
@export var near_dist := 2.5
@export var far_dist := 10.0
## 點亮／熄滅速度（每秒變化量；0.6 ≒ 1.6 s 由待機到全亮）
@export var fade_rate := 0.6
@export var night_gain := 1.5

var level := 0.0          # 目前亮度 0..1（測試可讀）
var _core: Decal
var _glyph: Decal
var _stone: Decal
var _light: OmniLight3D
var _petals: GPUParticles3D
var _motes: GPUParticles3D
var _player: Node3D


static func palette_for_map(map_id: String) -> String:
	if map_id.begins_with("shrine"):
		return "shrine"
	if map_id == "trail" or map_id == "beast_path":
		return "trail"
	return "village"


func _ready() -> void:
	var pal: Dictionary = PALETTES.get(palette, PALETTES["village"])
	var glow: Color = pal["glow"]
	var size := Vector3(diameter, 1.2, diameter)
	_stone = _decal("Stone", size * Vector3(1, 1, 1), TEX_STONE, null, Color.WHITE, float(pal["stone_mix"]))
	_core = _decal("Core", size * Vector3(0.98, 1, 0.98), TEX_CORE, TEX_CORE, glow.lerp(Color.WHITE, 0.25), 0.0)
	_glyph = _decal("Glyph", size * Vector3(0.98, 1, 0.98), TEX_GLYPH, TEX_GLYPH, glow, 0.0)

	_light = OmniLight3D.new()
	_light.name = "Glow"
	_light.position.y = 0.45
	_light.light_color = glow
	_light.omni_range = 3.4
	_light.omni_attenuation = 1.6
	_light.shadow_enabled = false
	_light.light_specular = 0.0
	add_child(_light)

	_petals = _particles("Petals", 24, 4.8, TEX_PETAL, pal["petal"], Vector2(0.08, 0.12), false,
		1.25, 0.75, Vector2(0.18, 0.42))
	_motes = _particles("Motes", 34, 3.2, TEX_MOTE, glow.lerp(Color.WHITE, 0.35), Vector2(0.025, 0.05), true,
		1.45, 0.15, Vector2(0.25, 0.7))
	level = idle_level
	_apply(level, 1.0)


func _decal(nm: String, size: Vector3, albedo: Texture2D, emission: Texture2D, mod: Color, albedo_mix: float) -> Decal:
	var d := Decal.new()
	d.name = nm
	d.size = size
	d.texture_albedo = albedo
	if emission != null:
		d.texture_emission = emission
	d.modulate = mod
	d.albedo_mix = albedo_mix
	d.upper_fade = 0.25
	d.lower_fade = 0.25
	d.normal_fade = 0.45        # 只投在朝上的面：不染到站在上面的角色腳脛
	add_child(d)
	return d


func _particles(nm: String, amount: int, life: float, tex: Texture2D, col: Color, scale_range: Vector2,
		additive: bool, ring_r: float, ring_inner: float, vel: Vector2) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = nm
	p.amount = amount
	p.lifetime = life
	p.preprocess = life
	p.randomness = 0.6
	p.visibility_aabb = AABB(Vector3(-2.2, -0.3, -2.2), Vector3(4.4, 4.0, 4.4))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_radius = ring_r
	pm.emission_ring_inner_radius = ring_inner
	pm.emission_ring_height = 0.05
	pm.direction = Vector3.UP
	pm.spread = 22.0
	pm.initial_velocity_min = vel.x
	pm.initial_velocity_max = vel.y
	pm.gravity = Vector3(0.0, 0.02, 0.0)
	pm.damping_min = 0.05
	pm.damping_max = 0.15
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -70.0
	pm.angular_velocity_max = 70.0
	pm.scale_min = 0.7
	pm.scale_max = 1.3
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.35
	pm.turbulence_noise_scale = 2.5
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.15
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.18, 0.7, 1.0])
	grad.colors = PackedColorArray([Color(col, 0.0), Color(col, 0.9), Color(col, 0.6), Color(col, 0.0)])
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	var s := (scale_range.x + scale_range.y) * 0.5
	q.size = Vector2(s, s * (1.25 if not additive else 1.0))
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = tex
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	q.material = m
	p.draw_pass_1 = q
	add_child(p)
	return p


func _night_factor() -> float:
	var dn := get_node_or_null("/root/DayNight")
	if dn == null:
		return 0.0
	var h := float(dn.get("hour"))
	# 18:00→19:30 漸亮、05:00→06:30 漸暗
	if h >= 19.5 or h < 5.0:
		return 1.0
	if h >= 18.0:
		return (h - 18.0) / 1.5
	if h < 6.5:
		return 1.0 - (h - 5.0) / 1.5
	return 0.0


func _process(dt: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	var near := 0.0
	if _player != null:
		var d := Vector2(_player.global_position.x - global_position.x,
			_player.global_position.z - global_position.z).length()
		near = clampf(inverse_lerp(far_dist, near_dist, d), 0.0, 1.0)
	var target := lerpf(idle_level, 1.0, near)
	level = move_toward(level, target, fade_rate * dt)
	_apply(level, lerpf(1.0, night_gain, _night_factor()))
	_glyph.rotation.y += dt * 0.05


func _apply(lv: float, gain: float) -> void:
	_core.emission_energy = 1.5 * lv * gain
	_glyph.emission_energy = 1.1 * lv * gain
	_light.light_energy = 0.55 * lv * gain
	_petals.amount_ratio = clampf((lv - idle_level) / maxf(0.01, 1.0 - idle_level), 0.0, 1.0) * 0.85 + 0.15
	_motes.amount_ratio = 0.35 + 0.65 * lv

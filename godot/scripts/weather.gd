extends Node
## 天氣系統（autoload：Weather）—— 全地圖統一。
## 目前一種天氣：雨（GPUParticles3D 跟著玩家走）。F3 切換測試。
## 之後加雪/花瓣就是多一組 particles + 對 set_weather 加 case。

var _rain: GPUParticles3D = null
var current := "clear"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_F3:
		set_weather("rain" if current == "clear" else "clear")

func set_weather(kind: String) -> void:
	current = kind
	if kind == "rain":
		if _rain == null:
			_rain = _make_rain()
			get_tree().root.get_node("Main").add_child(_rain)
		_rain.emitting = true
	elif _rain:
		_rain.emitting = false

func _process(_delta: float) -> void:
	if _rain and _rain.emitting:
		var player := get_tree().root.get_node_or_null("Main/Player") as Node3D
		if player:
			_rain.global_position = player.global_position + Vector3(0, 14, 0)

func _make_rain() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Rain"
	p.amount = 2600
	p.lifetime = 1.1
	p.visibility_aabb = AABB(Vector3(-30, -20, -30), Vector3(60, 40, 60))
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(26, 1, 26)
	mat.direction = Vector3(0, -1, 0)
	mat.initial_velocity_min = 16.0
	mat.initial_velocity_max = 20.0
	mat.gravity = Vector3(0, -22, 0)
	p.process_material = mat
	var quad := QuadMesh.new()
	quad.size = Vector2(0.025, 0.5)
	var qmat := StandardMaterial3D.new()
	qmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qmat.albedo_color = Color(0.75, 0.82, 0.95, 0.35)
	qmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qmat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	quad.material = qmat
	p.draw_pass_1 = quad
	return p

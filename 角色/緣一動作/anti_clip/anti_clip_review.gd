extends Node3D

const SHOT_DIR := "D:/神社/shrine-yoriichi/角色/haori_work/anti_clipping/shots/"
const VARIANTS := [
	["O_original", preload("res://yoriichi_character_v21.tscn")],
	["A_2cm", preload("res://anti_clip/character_2cm.tscn")],
	["B_3cm", preload("res://anti_clip/character_3cm.tscn")],
	["C_4cm", preload("res://anti_clip/character_4cm.tscn")],
]

var _character: CharacterBody3D
var _camera: Camera3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	sun.light_energy = 1.2
	add_child(sun)
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.55, 0.65, 0.8)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.7, 0.7, 0.75)
	environment_node.environment = environment
	add_child(environment_node)
	var floor_body := StaticBody3D.new()
	floor_body.position = Vector3(0, -0.1, 0)
	add_child(floor_body)
	var floor_collision := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(80, 0.2, 80)
	floor_collision.shape = floor_shape
	floor_body.add_child(floor_collision)
	var floor_mesh := MeshInstance3D.new()
	var floor_box := BoxMesh.new()
	floor_box.size = Vector3(80, 0.2, 80)
	floor_mesh.mesh = floor_box
	floor_body.add_child(floor_mesh)
	_camera = Camera3D.new()
	_camera.current = true
	add_child(_camera)
	_run_review.call_deferred()


func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


func _release_movement() -> void:
	for code in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_SHIFT, KEY_Q]:
		_key(code, false)


func _yaw() -> float:
	var player := _character.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	return player.get_parent().rotation.y


func _shot(variant: String, action: String, yaw_offset := 0.0, distance := 2.7, height := 1.5, focus := 0.95) -> void:
	var yaw := _yaw() + yaw_offset
	var forward := Vector3(sin(yaw), 0, cos(yaw))
	_camera.global_position = _character.global_position + forward * distance + Vector3(0, height, 0)
	_camera.look_at(_character.global_position + Vector3(0, focus, 0))
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := SHOT_DIR + variant + "__" + action + ".png"
	get_viewport().get_texture().get_image().save_png(path)
	print("ANTI_SHOT ", variant, " ", action)


func _run_variant(label: String, packed: PackedScene) -> void:
	_release_movement()
	_character = packed.instantiate() as CharacterBody3D
	_character.position = Vector3(0, 0.5, 0)
	add_child(_character)
	await get_tree().create_timer(1.0).timeout
	await _shot(label, "idle_front")
	await _shot(label, "idle_side", PI * 0.5)

	_key(KEY_W, true)
	await get_tree().create_timer(1.0).timeout
	await _shot(label, "walk_front")
	await _shot(label, "walk_hem", 0.0, 1.55, 0.72, 0.62)

	_key(KEY_SHIFT, true)
	await get_tree().create_timer(0.9).timeout
	await _shot(label, "run_side", PI * 0.5)
	await _shot(label, "run_hem", 0.0, 1.55, 0.72, 0.62)
	await _shot(label, "run_sleeve_close", -PI * 0.28, 1.5, 1.42, 1.20)

	_key(KEY_W, false)
	_key(KEY_D, true)
	await get_tree().create_timer(0.35).timeout
	_key(KEY_D, false)
	_key(KEY_A, true)
	await get_tree().create_timer(0.35).timeout
	await _shot(label, "turn180_front")
	await _shot(label, "turn180_side", PI * 0.5)
	await _shot(label, "turn180_sleeve_close", -PI * 0.28, 1.5, 1.42, 1.20)

	_release_movement()
	await get_tree().create_timer(0.6).timeout
	_key(KEY_Q, true)
	await get_tree().process_frame
	_key(KEY_Q, false)
	await get_tree().create_timer(0.55).timeout
	await _shot(label, "draw_mid_close", -PI * 0.30, 1.45, 1.48, 1.24)
	await get_tree().create_timer(0.35).timeout
	await _shot(label, "draw_high_close", -PI * 0.30, 1.45, 1.48, 1.24)

	_release_movement()
	_character.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_character = null


func _run_review() -> void:
	for variant in VARIANTS:
		await _run_variant(variant[0], variant[1])
	print("ANTI_CLIP_REVIEW_DONE")
	get_tree().quit()

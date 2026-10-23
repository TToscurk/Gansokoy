extends Node3D
## 緣一 V2.4（衣髮彈簧骨）在人間之里（village_v2.tscn）裡走路的檢視場景。獨立於正式 Player / main.gd，F6 執行。
## 操作：WASD 移動、Q/E 轉相機、Shift 跑、R 切換彈簧骨、1..4 切換出生點。
## 自動：命令列 `-- --auto --auto-shots[=<spawn>]`：沿面向方向走，輸出截圖到 user://v24_village_shots/。

const VILLAGE := preload("res://maps/village_v2/village_v2.tscn")
const MODEL := preload("res://characters/yoriichi/v24/yoriichi_v24.glb")
const SPAWNS := {
	"main_street": [Vector2(241.0, 44.0), Vector2(262.0, -20.0)],
	"hieda": [Vector2(0, 0), Vector2(0, 0)],
}
@export var walk_speed := 1.55
@export var run_speed := 4.0
var _body: CharacterBody3D
var _rig: YoriichiV24Rig
var _cam: Camera3D
var _yaw := 0.0
var _auto := false
var _shots := false
var _t := 0.0
var _label: Label
var _spawn_name := "main_street"
var _shot_i := 0
var _ready_t := -1.0

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_auto = "--auto" in args
	for a in args:
		if a.begins_with("--auto-shots"):
			_shots = true
			if a.contains("="): _spawn_name = a.get_slice("=", 1)
		if a.begins_with("--spawn="): _spawn_name = a.get_slice("=", 1)
	add_child(VILLAGE.instantiate())
	_body = CharacterBody3D.new(); _body.name = "V24Body"
	var cs := CollisionShape3D.new(); var cap := CapsuleShape3D.new(); cap.radius = 0.3; cap.height = 1.7
	cs.shape = cap; cs.position.y = 0.85; _body.add_child(cs)
	_body.floor_max_angle = 0.9076; _body.floor_snap_length = 0.4
	add_child(_body)
	_rig = YoriichiV24Rig.new(); _rig.name = "Rig"
	_rig.add_child(MODEL.instantiate())
	_body.add_child(_rig)
	_cam = Camera3D.new(); _cam.fov = 60; _cam.far = 600.0
	add_child(_cam); _cam.current = true
	var cl := CanvasLayer.new(); add_child(cl)
	_label = Label.new(); _label.position = Vector2(16, 10); _label.add_theme_font_size_override("font_size", 20)
	_label.add_theme_color_override("font_outline_color", Color.BLACK); _label.add_theme_constant_override("outline_size", 6)
	cl.add_child(_label)
	_place(_spawn_name)

func _place(nm: String) -> void:
	_spawn_name = nm
	var sp: Array = SPAWNS.get(nm, SPAWNS["main_street"])
	var at: Vector2 = sp[0]; var look: Vector2 = sp[1]
	await get_tree().physics_frame
	await get_tree().physics_frame
	var q := PhysicsRayQueryParameters3D.create(Vector3(at.x, 60.0, at.y), Vector3(at.x, -20.0, at.y))
	q.exclude = [_body.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var y: float = (hit["position"] as Vector3).y + 0.05 if not hit.is_empty() else 40.0
	_body.global_position = Vector3(at.x, y, at.y); _body.velocity = Vector3.ZERO
	var d := look - at
	_yaw = atan2(-d.x, -d.y) if d.length() > 0.01 else 0.0
	_body.rotation.y = atan2(d.x, d.y) if d.length() > 0.01 else 0.0
	_ready_t = _t

func _unhandled_key_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo and ev.physical_keycode == KEY_R:
		_rig.springs_enabled = not _rig.springs_enabled

func _physics_process(delta: float) -> void:
	_t += delta
	if _ready_t < 0.0: return
	var dir := Vector3.ZERO
	var spd := walk_speed
	if _auto:
		var d := _body.transform.basis.z
		d.y = 0.0
		if _t - _ready_t > 1.5: dir = d.normalized()
	else:
		var v := Vector2.ZERO
		if Input.is_physical_key_pressed(KEY_W): v.y -= 1
		if Input.is_physical_key_pressed(KEY_S): v.y += 1
		if Input.is_physical_key_pressed(KEY_A): v.x -= 1
		if Input.is_physical_key_pressed(KEY_D): v.x += 1
		if Input.is_physical_key_pressed(KEY_Q): _yaw += delta * 1.8
		if Input.is_physical_key_pressed(KEY_E): _yaw -= delta * 1.8
		if Input.is_physical_key_pressed(KEY_SHIFT): spd = run_speed
		if v != Vector2.ZERO:
			v = v.normalized(); dir = Vector3(v.x, 0, v.y).rotated(Vector3.UP, _yaw)
	if dir.length() > 0.01:
		_body.velocity.x = dir.x * spd; _body.velocity.z = dir.z * spd
		_body.rotation.y = lerp_angle(_body.rotation.y, atan2(dir.x, dir.z), clampf(delta * 10.0, 0.0, 1.0))
		_rig.play_motion(_rig.walk_motion)
	else:
		_body.velocity.x = move_toward(_body.velocity.x, 0.0, 20.0 * delta); _body.velocity.z = move_toward(_body.velocity.z, 0.0, 20.0 * delta)
		_rig.play_motion("idle")
	if not _body.is_on_floor(): _body.velocity.y -= 18.0 * delta
	else: _body.velocity.y = -1.0
	_body.move_and_slide()

func _process(_delta: float) -> void:
	if _ready_t < 0.0: return
	var focus := _body.global_position + Vector3(0, 1.1, 0)
	var back := Vector3(0, 0, 1).rotated(Vector3.UP, _yaw) * 3.6
	if _auto: back = (-_body.transform.basis.z * -1.0 * 0.0) + Vector3(1.6, 0.0, 0.0).rotated(Vector3.UP, _body.rotation.y) + (-_body.transform.basis.z) * 3.4
	_cam.global_position = focus + back + Vector3(0, 0.7, 0)
	_cam.look_at(focus, Vector3.UP)
	_label.text = "V2.4 緣一 @ 人間之里  彈簧骨 %s  [WASD 移動 Shift 跑 Q/E 相機 R 彈簧骨]  (%.1f, %.1f, %.1f)" % [("ON" if _rig.springs_enabled else "OFF"), _body.global_position.x, _body.global_position.y, _body.global_position.z]
	if _shots: _auto_shots()

func _auto_shots() -> void:
	var times := [0.8, 2.6, 3.2, 3.8, 4.4, 5.0, 6.5, 8.0]
	var tt := _t - _ready_t
	if _shot_i < times.size() and tt >= times[_shot_i]:
		DirAccess.make_dir_recursive_absolute("user://v24_village_shots")
		get_viewport().get_texture().get_image().save_png("user://v24_village_shots/shot_%02d.png" % _shot_i)
		_shot_i += 1
	if _shot_i >= times.size():
		print("V24_VILLAGE_SHOTS_DONE ", ProjectSettings.globalize_path("user://v24_village_shots"), " end pos ", _body.global_position)
		get_tree().quit()

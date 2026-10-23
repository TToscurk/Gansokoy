extends Node3D
## 緣一 V2.4 衣髮骨架 走路測試（F6 執行 yoriichi_v24_walk_test.tscn）。獨立場景，不引用 Player / 村落。
## 操作：WASD 移動（走路動作）、Q/E 轉相機、R 切換彈簧骨 ON/OFF、H 切換羽織顯示。
## 自動示範（給截圖／驗證）：命令列 `-- --auto`；`--auto-shots` 另存畫面到 user://v24_shots/。

const MODEL_SCENE := preload("res://characters/yoriichi/v24/yoriichi_v24.glb")
## 模型已在資產中烘成 1.7 m 高（舊 Meshy 玩家同高），遊戲內縮放保持 1.0（Godot 彈簧骨碰撞體在縮放骨架下行為不可靠）。
@export var target_height_m := 1.7
@export var model_height_m := 1.7
@export var walk_speed := 1.5

var _root: Node3D
var _rig: YoriichiV24Rig
var _cam: Camera3D
var _cam_yaw := 0.0
var _auto := false
var _shots := false
var _t := 0.0
var _label: Label

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_auto = "--auto" in args
	_shots = "--auto-shots" in args
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.65, 0.78)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.85, 0.88, 1.0)
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	add_child(sun)
	var floor_ := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(40, 40)
	floor_.mesh = pm
	var m := StandardMaterial3D.new(); m.albedo_color = Color(0.32, 0.36, 0.30); m.roughness = 0.95
	floor_.material_override = m
	add_child(floor_)
	_root = Node3D.new(); _root.name = "Actor"
	_root.scale = Vector3.ONE * (target_height_m / model_height_m)
	add_child(_root)
	_rig = YoriichiV24Rig.new()
	if OS.get_environment("RIG_TX") != "": _rig.torso_collider_extra = float(OS.get_environment("RIG_TX"))
	if OS.get_environment("RIG_SR") != "": _rig.sleeve_joint_radius = float(OS.get_environment("RIG_SR"))
	if OS.get_environment("RIG_ON") == "0": _rig.springs_enabled = false
	_rig.name = "Rig"
	_rig.add_child(MODEL_SCENE.instantiate())   # 先掛模型，再進場景樹，Rig._ready 才找得到骨架
	_root.add_child(_rig)
	_cam = Camera3D.new(); _cam.fov = 50
	add_child(_cam)
	_cam.current = true
	var cl := CanvasLayer.new(); add_child(cl)
	_label = Label.new(); _label.position = Vector2(16, 12)
	_label.add_theme_font_size_override("font_size", 22)
	cl.add_child(_label)
	_update_camera()

func _unhandled_key_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		match ev.physical_keycode:
			KEY_R: _rig.springs_enabled = not _rig.springs_enabled
			KEY_H: _rig.set_haori_visible(not _rig.find_child("羽織", true, false).visible)

func _process(delta: float) -> void:
	_t += delta
	var dir := Vector3.ZERO
	if _auto:
		# 自動示範：2 秒站、之後沿圓弧走
		if _t > 2.0:
			var a := (_t - 2.0) * 0.5
			dir = Vector3(sin(a), 0, cos(a))
	else:
		var v := Vector2.ZERO
		if Input.is_physical_key_pressed(KEY_W): v.y -= 1
		if Input.is_physical_key_pressed(KEY_S): v.y += 1
		if Input.is_physical_key_pressed(KEY_A): v.x -= 1
		if Input.is_physical_key_pressed(KEY_D): v.x += 1
		if Input.is_physical_key_pressed(KEY_Q): _cam_yaw += delta * 1.8
		if Input.is_physical_key_pressed(KEY_E): _cam_yaw -= delta * 1.8
		if v != Vector2.ZERO:
			v = v.normalized()
			dir = Vector3(v.x, 0, v.y).rotated(Vector3.UP, _cam_yaw)
	if dir.length() > 0.01:
		dir = dir.normalized()
		_root.position += dir * walk_speed * delta
		var target := atan2(dir.x, dir.z)
		_root.rotation.y = lerp_angle(_root.rotation.y, target, clampf(delta * 10.0, 0.0, 1.0))
		_rig.play_motion(_rig.walk_motion)
	else:
		_rig.play_motion("idle")
	_update_camera()
	_label.text = "V2.4 衣髮骨架  彈簧骨：%s   [WASD 移動 / Q E 轉相機 / R 彈簧骨 / H 羽織]" % ("ON" if _rig.springs_enabled else "OFF")
	if _shots:
		_auto_shots()

var _shot_i := 0
func _auto_shots() -> void:
	var times := [3.0, 3.25, 3.5, 3.75, 4.0, 4.25]
	if _shot_i < times.size() and _t >= times[_shot_i]:
		var img := get_viewport().get_texture().get_image()
		DirAccess.make_dir_recursive_absolute("user://v24_shots")
		img.save_png("user://v24_shots/shot_%02d.png" % _shot_i)
		_shot_i += 1
	if _shot_i >= times.size():
		print("V24_SHOTS_DONE ", ProjectSettings.globalize_path("user://v24_shots"))
		get_tree().quit()

func _update_camera() -> void:
	var focus := _root.position + Vector3(0, target_height_m * 0.55, 0)
	var offset := Vector3(0, 0.35, 3.0).rotated(Vector3.UP, _cam_yaw)
	if _auto:
		offset = Vector3(0.0, 0.3, 3.0) if "--front" in OS.get_cmdline_user_args() else Vector3(1.6, 0.5, 2.6)
	_cam.position = focus + offset
	_cam.look_at(focus, Vector3.UP)

extends Node3D
## 緣一 × 一心「拿刀走路」移動展示（動作來自《隻狼》一心 a000_405000／405001／405002／405003／405010／400000 的重定向；
## 研究／試看用，未接正式 Player）。
## 操作：W 前進　S 後退　A/D 左右橫移　Shift+W 快走　Q/E 轉身　右鍵拖曳轉相機　滾輪縮放　F 彈簧骨　R 重設　H 隱藏說明　Esc 離開
## 自動拍照：godot --path godot res://characters/yoriichi/v24_isshin/isshin_move_demo.tscn -- --auto --out=D:/某資料夾
##           --hand（握刀近景）　--dbg（指骨小球）
## 移動速度＝各動作站立腳的實測接觸速度（measure_isshin_clips.gd），不滑步。
const ANIM_DIR := "res://characters/yoriichi/v24_isshin/anims/"
const SPEED_FWD := 0.49       # m/s 前走
const SPEED_RUN := 0.976      # m/s 快走（405010，實測接觸速度；原動作其實是 2 倍步頻的快走，不是騰空跑）
const SPEED_BACK := 0.443
const SPEED_SIDE_L := 0.419
const SPEED_SIDE_R := 0.447
const TURN_SPEED := 1.75      # rad/s
const BLEND_RATE := 3.5       # 混合位置每秒變化量

@onready var actor: Node3D = $Actor
@onready var rig: YoriichiV24Rig = $Actor/BodyVisual
var ap: AnimationPlayer
var sk: Skeleton3D
var tree: AnimationTree
var cam: Camera3D
var hud: Label
var cam_yaw := -0.55
var cam_pitch := 0.14
var cam_dist := 3.1
var cam_target := Vector3(0, 0.9, 0)
var in_place := false
var auto := false
var hand_only := false
var dbg := false
var slip_only := false
var out_dir := ""
var auto_input := Vector2.ZERO
var auto_label := ""
var yaw_off := 0.0              # 斜向移動時身體相對 actor 的偏航
var bp := Vector2.ZERO          # 混合位置：x=橫移(+右)，y=前後(+前；2=跑)
var _drag := false
var _dbg_nodes := {}

func _ready() -> void:
	_build_world()
	ap = rig.anim_player
	sk = rig.skeleton
	var lib := ap.get_animation_library("")
	for n in ["isshin_idle", "isshin_walk", "isshin_back", "isshin_strafe_l", "isshin_strafe_r", "isshin_run"]:
		var a: Animation = load(ANIM_DIR + n + ".res")
		a.loop_mode = Animation.LOOP_LINEAR
		lib.add_animation(n, a)
	_build_tree()
	for a in OS.get_cmdline_user_args():
		if a == "--auto":
			auto = true
		elif a.begins_with("--out="):
			out_dir = a.substr(6)
		elif a == "--dbg":
			dbg = true
		elif a == "--hand":
			auto = true
			hand_only = true
		elif a == "--slip":
			auto = true
			slip_only = true
	_update_cam(true)
	if dbg:
		_make_dbg()
	if auto:
		in_place = true
		if slip_only:
			in_place = false
			_slip_run()
		elif hand_only:
			_hand_run()
		else:
			_auto_run()

func _build_tree() -> void:
	tree = AnimationTree.new()
	tree.name = "IsshinTree"
	rig.add_child(tree)
	tree.anim_player = tree.get_path_to(ap)
	tree.root_node = tree.get_path_to(rig)
	var bs := AnimationNodeBlendSpace2D.new()
	bs.min_space = Vector2(-1, -1)
	bs.max_space = Vector2(1, 2)
	bs.blend_mode = AnimationNodeBlendSpace2D.BLEND_MODE_INTERPOLATED
	bs.sync = true
	var pts := {"isshin_idle": Vector2(0, 0), "isshin_walk": Vector2(0, 1), "isshin_back": Vector2(0, -1),
		"isshin_strafe_l": Vector2(-1, 0), "isshin_strafe_r": Vector2(1, 0), "isshin_run": Vector2(0, 2)}
	for n in pts:
		var an := AnimationNodeAnimation.new()
		an.animation = n
		bs.add_blend_point(an, pts[n])
	tree.tree_root = bs
	tree.active = true

func _build_world() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.36, 0.5, 0.72)
	psm.sky_horizon_color = Color(0.72, 0.78, 0.86)
	psm.ground_horizon_color = Color(0.55, 0.57, 0.6)
	psm.ground_bottom_color = Color(0.25, 0.27, 0.3)
	sky.sky_material = psm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, 38, 0)
	sun.shadow_enabled = true
	sun.light_energy = 1.25
	add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(160, 160)
	floor_mi.mesh = pm
	var sh := Shader.new()
	sh.code = """shader_type spatial;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = wpos.xz;
	vec2 g = abs(fract(p - 0.5) - 0.5) / fwidth(p);
	float line = 1.0 - clamp(min(g.x, g.y), 0.0, 1.0);
	vec2 g5 = abs(fract(p / 5.0 - 0.5) - 0.5) / fwidth(p / 5.0);
	float line5 = 1.0 - clamp(min(g5.x, g5.y), 0.0, 1.0);
	ALBEDO = mix(vec3(0.34, 0.37, 0.36), vec3(0.16, 0.17, 0.17), max(line * 0.6, line5));
	ROUGHNESS = 0.95;
}"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	floor_mi.material_override = mat
	add_child(floor_mi)
	cam = Camera3D.new()
	cam.fov = 38
	cam.near = 0.05
	cam.far = 300
	add_child(cam)
	cam.current = true
	var cl := CanvasLayer.new()
	add_child(cl)
	hud = Label.new()
	hud.position = Vector2(14, 10)
	hud.add_theme_color_override("font_color", Color(1, 0.96, 0.82))
	hud.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	hud.add_theme_constant_override("outline_size", 5)
	cl.add_child(hud)

func _raw_input() -> Vector2:
	if auto:
		return auto_input
	var x := float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A))
	var y := float(Input.is_key_pressed(KEY_W)) - float(Input.is_key_pressed(KEY_S))
	if y > 0.0 and x == 0.0 and Input.is_key_pressed(KEY_SHIFT):
		y = 2.0
	return Vector2(x, y)

## 輸入 → [混合位置, 身體偏航]。四個正方向直接用對應動作；斜向（同時按前後＋左右）改成
## 「用前走／後退動作，身體轉向移動方向」，因為前走和橫移是兩種不同的腿部動作，混在一起站立腳會漂（實測 0.34 m/s）。
func _cmd(v: Vector2) -> Array:
	if v.y > 1.5:
		return [Vector2(0, 2), 0.0]
	if v.x != 0.0 and v.y != 0.0:
		var yaw := atan2(-v.x, v.y) if v.y > 0.0 else atan2(v.x, -v.y)
		return [Vector2(0, signf(v.y)), yaw]
	return [v, 0.0]

func _local_velocity() -> Vector3:
	# 動畫混合位置 → 角色局部速度（角色朝 +Z；角色的右手邊 = 局部 -X）
	var vz := 0.0
	if bp.y >= 0.0:
		vz = bp.y * SPEED_FWD if bp.y <= 1.0 else lerpf(SPEED_FWD, SPEED_RUN, bp.y - 1.0)
	else:
		vz = bp.y * SPEED_BACK
	var vs := bp.x * (SPEED_SIDE_R if bp.x > 0.0 else SPEED_SIDE_L)
	return Basis(Vector3.UP, yaw_off) * Vector3(-vs, 0.0, vz)

func _process(delta: float) -> void:
	if ap == null:
		return
	var turn := 0.0
	if not auto:
		turn = float(Input.is_key_pressed(KEY_Q)) - float(Input.is_key_pressed(KEY_E))
	actor.rotate_y(turn * TURN_SPEED * delta)
	var cmd := _cmd(_raw_input())
	bp = bp.move_toward(cmd[0], BLEND_RATE * delta)
	yaw_off = lerp_angle(yaw_off, cmd[1], 1.0 - exp(-9.0 * delta))
	rig.rotation.y = yaw_off
	tree.set("parameters/blend_position", bp)
	if not in_place:
		actor.global_position += actor.global_basis * _local_velocity() * delta
	_update_cam(false)
	_update_dbg()
	var spd := _local_velocity().length()
	if auto:
		hud.text = auto_label
	else:
		hud.text = "緣一 × 一心拿刀走路（重定向）\n混合位置 (%.2f, %.2f)　速度 %.2f m/s\nW 前進　S 後退　A/D 橫移　Shift+W 快走　Q/E 轉身　右鍵拖曳／滾輪 相機　F 彈簧骨 %s　R 重設　Esc 離開" % [
			bp.x, bp.y, spd, "開" if rig.springs_enabled else "關"]

func _update_cam(snap: bool) -> void:
	var tgt := actor.global_position + cam_target
	if snap or auto:
		cam.global_position = tgt + _orbit()
	else:
		cam.global_position = cam.global_position.lerp(tgt + _orbit(), 1.0 - exp(-12.0 * get_process_delta_time()))
	cam.look_at(tgt, Vector3.UP)

func _orbit() -> Vector3:
	# 角色朝 +Z；yaw=0 → 相機在角色正前方；yaw<0 → 角色右側（-X）
	var a := cam_yaw + actor.rotation.y
	return Vector3(sin(a) * cos(cam_pitch), sin(cam_pitch), cos(a) * cos(cam_pitch)) * cam_dist

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_drag = mb.pressed
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			cam_dist = maxf(0.8, cam_dist - 0.2)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cam_dist = minf(9.0, cam_dist + 0.2)
	elif e is InputEventMouseMotion and _drag:
		var mm := e as InputEventMouseMotion
		cam_yaw -= mm.relative.x * 0.006
		cam_pitch = clampf(cam_pitch + mm.relative.y * 0.004, -0.2, 1.1)
	elif e is InputEventKey:
		var k := e as InputEventKey
		if k.pressed and not k.echo:
			match k.keycode:
				KEY_F: rig.springs_enabled = not rig.springs_enabled
				KEY_H: hud.visible = not hud.visible
				KEY_R:
					actor.position = Vector3.ZERO
					actor.rotation = Vector3.ZERO
					cam_yaw = -0.55
					cam_pitch = 0.14
					cam_dist = 3.1
				KEY_ESCAPE: get_tree().quit()

# ---------------------------------------------------------------- 自動拍照
func _shot(name_: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name_ + ".png"))

func _view(yaw: float, pitch: float, dist: float, target := Vector3(0, 0.9, 0)) -> void:
	cam_yaw = yaw
	cam_pitch = pitch
	cam_dist = dist
	cam_target = target
	_update_cam(true)

func _state(label: String, v: Vector2, settle := 1.3) -> void:
	auto_label = label
	auto_input = v
	await get_tree().create_timer(settle).timeout

func _auto_run() -> void:
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path("user://isshin_shots")
	DirAccess.make_dir_recursive_absolute(out_dir)
	await get_tree().create_timer(1.2).timeout
	var states := [
		["idle 待機", Vector2(0, 0)], ["forward 前走", Vector2(0, 1)], ["back 後退", Vector2(0, -1)],
		["strafe left 左移", Vector2(-1, 0)], ["strafe right 右移", Vector2(1, 0)], ["brisk 快走", Vector2(0, 2)],
		["fwd+left 左前", Vector2(-1, 1)], ["fwd+right 右前", Vector2(1, 1)],
	]
	var views := {"q34": [-0.78, 0.14, 3.4], "front": [0.0, 0.1, 3.6]}
	var idx := 0
	for s in states:
		await _state(s[0], s[1])
		for v in views:
			_view(views[v][0], views[v][1], views[v][2])
			for i in 3:
				await get_tree().create_timer(0.17).timeout
				await _shot("s%d_%s_%d" % [idx, v, i])
		idx += 1
	# 導覽 GIF：q34，每狀態 1.0 s、12 fps
	DirAccess.make_dir_recursive_absolute(out_dir.path_join("gif"))
	_view(-0.78, 0.14, 3.4)
	var n := 0
	for s in states:
		auto_label = s[0]
		auto_input = s[1]
		await get_tree().create_timer(0.35).timeout
		for i in 9:
			await get_tree().create_timer(1.0 / 12.0).timeout
			await _shot("gif/f%03d" % n)
			n += 1
	print("AUTO_DONE ", out_dir)
	get_tree().quit()

func _hand_run() -> void:
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path("user://isshin_shots")
	DirAccess.make_dir_recursive_absolute(out_dir)
	await get_tree().create_timer(1.0).timeout
	await _state("hand", Vector2(0, 1), 0.9)
	var angles := {"front": [0.0, 0.22], "fr45": [-0.8, 0.25], "outer": [-PI / 2.0, 0.15], "back45": [-2.4, 0.25], "back": [PI, 0.2], "fl45": [0.8, 0.25], "top": [-0.6, 1.25]}
	for k in angles:
		for i in 2:
			var hp: Vector3 = sk.global_transform * sk.get_bone_global_pose(sk.find_bone("mixamorig_RightHand")).origin
			_view(angles[k][0], angles[k][1], 0.5, hp - actor.global_position)
			await get_tree().create_timer(0.55).timeout
			await _shot("hand_%s_%d" % [k, i])
	print("AUTO_DONE ", out_dir)
	get_tree().quit()

func _make_dbg() -> void:
	var cols := {"Thumb": Color(1, 0.1, 0.9), "Index": Color(0.1, 0.9, 1), "Middle": Color(0.2, 1, 0.2), "Ring": Color(1, 0.8, 0.1), "Pinky": Color(1, 0.4, 0.1)}
	var names := ["mixamorig_RightHand"]
	for f in cols:
		for j in 4:
			names.append("mixamorig_RightHand%s%d" % [f, j + 1])
	for n in names:
		var mi := MeshInstance3D.new()
		var sp := SphereMesh.new()
		sp.radius = 0.0045
		sp.height = 0.009
		sp.radial_segments = 8
		sp.rings = 4
		mi.mesh = sp
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.no_depth_test = true
		m.render_priority = 100
		var col := Color.WHITE
		for f in cols:
			if n.contains(f):
				col = cols[f]
		m.albedo_color = col
		mi.material_override = m
		add_child(mi)
		_dbg_nodes[n] = mi

func _update_dbg() -> void:
	if not dbg or sk == null:
		return
	for n in _dbg_nodes:
		var i := sk.find_bone(n)
		if i >= 0:
			_dbg_nodes[n].global_position = sk.global_transform * sk.get_bone_global_pose(i).origin

## 真實移動下量腳滑：角色依 _local_velocity 位移，統計「站立腳」的世界水平速度（理想 0）。
func _slip_run() -> void:
	await get_tree().create_timer(0.8).timeout
	var states := [["forward", Vector2(0, 1)], ["back", Vector2(0, -1)], ["strafe L", Vector2(-1, 0)], ["strafe R", Vector2(1, 0)],
		["brisk", Vector2(0, 2)], ["fwd+L", Vector2(-1, 1)], ["fwd+R", Vector2(1, 1)], ["back+L", Vector2(-1, -1)]]
	for s in states:
		auto_label = s[0]
		auto_input = s[1]
		await get_tree().create_timer(1.6).timeout
		var recs := {"mixamorig_LeftFoot": [], "mixamorig_RightFoot": []}
		var t_end := Time.get_ticks_msec() + 4800
		var start := actor.global_position
		var t0 := Time.get_ticks_msec()
		var last := {}
		while Time.get_ticks_msec() < t_end:
			await get_tree().process_frame
			for b in recs:
				var p: Vector3 = sk.global_transform * sk.get_bone_global_pose(sk.find_bone(b)).origin
				recs[b].append([Time.get_ticks_msec() / 1000.0, p])
		var speeds := []
		for b in recs:
			var ymin := 9.0
			for r in recs[b]:
				ymin = minf(ymin, r[1].y)
			for i in range(1, recs[b].size()):
				var a: Array = recs[b][i - 1]
				var c: Array = recs[b][i]
				if c[1].y < ymin + 0.02 and a[1].y < ymin + 0.02 and c[0] > a[0]:
					var d: Vector3 = c[1] - a[1]
					d.y = 0.0
					speeds.append(d.length() / (c[0] - a[0]))
		speeds.sort()
		var moved := (actor.global_position - start).length() / ((Time.get_ticks_msec() - t0) / 1000.0)
		print("SLIP %-9s body_speed=%.3f m/s  stance_foot_world_speed median=%.3f p90=%.3f (n=%d)" % [s[0], moved, speeds[speeds.size() / 2] if speeds.size() else -1.0, speeds[int(speeds.size() * 0.9)] if speeds.size() else -1.0, speeds.size()])
	print("AUTO_DONE slip")
	get_tree().quit()

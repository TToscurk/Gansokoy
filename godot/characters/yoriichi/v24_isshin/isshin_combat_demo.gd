extends Node3D
## 緣一 × 一心「戰鬥警戒步行」原型演示（獨立候選；不修改正式 Player、不碰跑酷）。
## 操作：W/S 前進／後退　A/D 左右橫移（繞敵）　Shift+W 快走　Space 閃避（A/D 決定左右）
##       方向鍵 左右：把敵人繞著你轉（測試原地轉身）　O：敵人自動繞圈　Q/E：轉相機　F 彈簧骨　H 隱藏說明　R 重設　Esc 離開
## 自動導覽（錄影）：godot --path godot --write-movie out.avi --fixed-fps 60 --resolution 1280x720 res://characters/yoriichi/v24_isshin/isshin_combat_demo.tscn -- --tour [--log=D:/x/log]
const Loco = preload("res://characters/yoriichi/v24_isshin/combat_locomotion.gd")
const SwordGeo = preload("res://tools/motion_capture/sword_geometry.gd")   # 刀尖／柄／鍔由網格頂點實測（--log 附加欄位用）
const TOUR_START_DELAY := 1.0

@onready var actor: Node3D = $Actor
@onready var rig: YoriichiV24Rig = $Actor/BodyVisual
var combat: Loco
var sk: Skeleton3D
var cam: Camera3D
var hud: Label
var enemy: Node3D
var enemy_pos := Vector3(0, 0, 6.0)   # 敵人固定在世界座標；玩家橫移就自然繞著它轉
var orbit_speed := 0.0
var cam_side := 0.0
var cam_yaw_extra := 0.0
var hud_on := true
# 導覽
var tour := false
var tour_t := 0.0
var tour_ix := -1
var tour_steps: Array = []
var tour_meta: Array = []
var tour_input := Vector2.ZERO
var tour_dodge_at := -1.0
var tour_attack_at := -1.0
var attack_fired := true
var tour_attack2_at := -1.0     # 導覽：同一段裡的第二次攻擊鍵（連段輸入）
var attack2_fired := true
var tour_attack3_at := -1.0
var attack3_fired := true
var tour_dodge_side := 0.0
var tour_step_t0 := 0.0
var tour_hold := -1.0
var log_path := ""
var log_rows: PackedFloat32Array = PackedFloat32Array()
var log_cols: Array = []
var log_bones: Array = []
var log_n := 0
var log_extra_cols: Array = []      # 附加在骨骼之後的欄位（舊欄位位置不變）
var _log_geo := {}
var _log_mi: MeshInstance3D
var _log_prev_tip: Variant = null
var cur_label := ""
var dodge_fired := false

func _ready() -> void:
	_build_world()
	sk = rig.skeleton
	combat = Loco.new()
	combat.name = "CombatLocomotion"
	add_child(combat)
	_pre_setup()
	combat.setup(actor, rig, not OS.get_cmdline_user_args().has("--no-clothfix"))
	for a in OS.get_cmdline_user_args():
		if a == "--tour":
			tour = true
		elif a.begins_with("--log="):
			log_path = a.substr(6)
		elif a == "--no-iklock":
			combat.foot_lock_on = false
		elif a.begins_with("--diag="):
			combat.diag_mode = a.substr(7)
	_place_enemy()
	_update_cam(true)
	if tour:
		_build_tour()
		if log_path != "":
			_init_log()
		sk.skeleton_updated.connect(_on_pre_draw)

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
	pm.size = Vector2(200, 200)
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
	# 敵人（木樁）：只是鎖定目標的標記
	enemy = Node3D.new()
	enemy.name = "EnemyDummy"
	var body := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.22
	cm.bottom_radius = 0.26
	cm.height = 1.6
	body.mesh = cm
	body.position = Vector3(0, 0.8, 0)
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.62, 0.16, 0.12)
	body.material_override = bm
	enemy.add_child(body)
	var head := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.2
	sm.height = 0.4
	head.mesh = sm
	head.position = Vector3(0, 1.75, 0)
	head.material_override = bm
	enemy.add_child(head)
	add_child(enemy)
	cam = Camera3D.new()
	cam.fov = 42
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
	hud.add_theme_constant_override("outline_size", 6)
	hud.add_theme_font_size_override("font_size", 28)
	cl.add_child(hud)

func _place_enemy() -> void:
	enemy.global_position = enemy_pos

func _enemy_rel(rel_rad: float, dist: float) -> Vector3:
	var yw := actor.rotation.y + rel_rad
	var p := actor.global_position
	return Vector3(p.x + sin(yw) * dist, 0.0, p.z + cos(yw) * dist)

func _move_input() -> Vector2:
	if tour:
		return tour_input
	var x := float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A))
	var y := float(Input.is_key_pressed(KEY_W)) - float(Input.is_key_pressed(KEY_S))
	if y > 0.0 and x == 0.0 and Input.is_key_pressed(KEY_SHIFT):
		y = 2.0
	return Vector2(x, y)

func _process(delta: float) -> void:
	var dodge := false
	var attack := false
	if tour:
		_tour_step(delta)
		if tour_attack_at >= 0.0 and not attack_fired and tour_t >= tour_attack_at:
			attack = true
			attack_fired = true
		elif tour_attack2_at >= 0.0 and not attack2_fired and tour_t >= tour_attack2_at:
			attack = true
			attack2_fired = true
		elif tour_attack3_at >= 0.0 and not attack3_fired and tour_t >= tour_attack3_at:
			attack = true
			attack3_fired = true
		if tour_dodge_at >= 0.0 and not dodge_fired and tour_t >= tour_dodge_at:
			dodge = true
			dodge_fired = true
	else:
		dodge = Input.is_key_pressed(KEY_SPACE) and not _space_held
		_space_held = Input.is_key_pressed(KEY_SPACE)
		var atk_now := Input.is_key_pressed(KEY_J) or Input.is_key_pressed(KEY_K) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		attack = atk_now and not _atk_held
		_atk_held = atk_now
		var ex := float(Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_LEFT))
		var rel := enemy_pos - actor.global_position
		var rr := rel.rotated(Vector3.UP, -(ex * 1.2 + orbit_speed) * delta)    # 繞玩家轉動（←/→、O）
		enemy_pos = actor.global_position + rr
		cam_yaw_extra += (float(Input.is_key_pressed(KEY_E)) - float(Input.is_key_pressed(KEY_Q))) * 1.4 * delta
	_place_enemy()
	var io := _filter_input(delta, dodge, attack)
	combat.step(delta, _move_input(), io[0], enemy.global_position, tour_dodge_side if tour else 0.0, io[1])
	_after_step(delta)
	_update_cam(false)
	var spd := Vector2(combat.body_velocity.x, combat.body_velocity.z).length()
	var sword_note := ""
	if tour:
		hud.text = cur_label
	else:
		hud.text = "緣一 × 一心 戰鬥警戒步行原型（獨立候選）\n狀態 %s　g=%.2f　速度 %.2f m/s\nW/S/A/D 移動　Shift+W 快走　Space 閃避　←/→ 繞敵　O 敵人繞圈　Q/E 相機　F 彈簧骨　H 說明　R 重設　Esc 離開" % [combat.label, combat.g, spd]
	hud.visible = hud_on

var _space_held := false
var _atk_held := false

## R9 掛點（基底什麼都不做）：setup() 前登記額外招式／衝刺動作；每幀出招前整理輸入（緩衝、跳躍、技能）；出招後檢查輸入是否被吃掉
func _pre_setup() -> void:
	pass

func _filter_input(_delta: float, dodge: bool, attack: bool) -> Array:
	return [dodge, attack]

func _after_step(_delta: float) -> void:
	pass

var cam_yaw := 0.0

func _update_cam(snap: bool) -> void:
	# 第三人稱：相機在角色身後（跟隨角色朝向、帶延遲），略偏右肩；轉身時不會因為敵人瞬間換邊而整個鏡頭翻過去
	var pp := actor.global_position
	if snap:
		cam_yaw = actor.rotation.y
	else:
		cam_yaw = lerp_angle(cam_yaw, actor.rotation.y, 1.0 - exp(-2.6 * get_process_delta_time()))
	var yw := cam_yaw + cam_yaw_extra
	var dir := Vector3(sin(yw), 0.0, cos(yw))
	var right := dir.cross(Vector3.UP)
	var want := pp - dir * 4.4 + Vector3(0, 2.1, 0) + right * 0.9
	var look := pp + dir * 1.8 + Vector3(0, 1.05, 0)
	if snap:
		cam.global_position = want
	else:
		cam.global_position = cam.global_position.lerp(want, 1.0 - exp(-8.0 * get_process_delta_time()))
	cam.look_at(look, Vector3.UP)

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey:
		var k := e as InputEventKey
		if k.pressed and not k.echo:
			match k.keycode:
				KEY_F: rig.springs_enabled = not rig.springs_enabled
				KEY_H: hud_on = not hud_on
				KEY_O: orbit_speed = 0.0 if absf(orbit_speed) > 0.01 else 0.45
				KEY_R:
					actor.position = Vector3.ZERO
					actor.rotation = Vector3.ZERO
					enemy_pos = Vector3(0, 0, 6.0)
					orbit_speed = 0.0
					combat.g = 0.0
				KEY_ESCAPE: get_tree().quit()

# ---------------------------------------------------------------- 導覽
func _s(d: float, label: String, mv := Vector2.ZERO, extra := {}) -> void:
	var st := {"d": d, "label": label, "mv": mv}
	st.merge(extra)
	tour_steps.append(st)

func _build_tour() -> void:
	var E := {"enemy": [0.0, 5.0, 0.01]}
	_s(2.0, "idle 待機", Vector2.ZERO, E)
	_s(3.6, "forward 前進", Vector2(0, 1))
	_s(1.8, "stop 停步")
	_s(3.6, "back 後退", Vector2(0, -1), E)
	_s(1.6, "stop 停步")
	_s(3.2, "strafe left 左移（繞敵）", Vector2(-1, 0))
	_s(1.4, "stop 停步")
	_s(3.2, "strafe right 右移（繞敵）", Vector2(1, 0), E)
	_s(1.4, "stop 停步")
	_s(1.6, "reverse 反向：前進", Vector2(0, 1))
	_s(2.0, "reverse 反向：立刻改按後退（先煞停再後退）", Vector2(0, -1))
	_s(1.4, "stop 停步")
	_s(1.6, "reverse 反向：左移", Vector2(-1, 0), E)
	_s(2.0, "reverse 反向：立刻改按右移", Vector2(1, 0))
	_s(1.4, "stop 停步")
	_s(2.8, "diagonal fwd+left 左前（仍面向敵人）", Vector2(-1, 1))
	_s(1.0, "stop")
	_s(2.8, "diagonal fwd+right 右前", Vector2(1, 1), E)
	_s(1.0, "stop")
	_s(2.8, "diagonal back+left 左後", Vector2(-1, -1))
	_s(1.0, "stop")
	_s(2.8, "diagonal back+right 右後", Vector2(1, -1), E)
	_s(1.2, "stop")
	_s(2.6, "brisk 快走", Vector2(0, 2))
	_s(1.6, "stop 停步", Vector2.ZERO, E)
	_s(0.5, "tap W 短按起步", Vector2(0, 1))
	_s(1.0, "stop")
	_s(0.5, "tap W", Vector2(0, 1))
	_s(1.0, "stop")
	_s(0.5, "tap A", Vector2(-1, 0))
	_s(1.2, "stop", Vector2.ZERO, E)
	_s(3.0, "enemy jumps to the left → turn 90 左轉身", Vector2.ZERO, {"enemy": [95.0, 5.0, 0.2]})
	_s(1.6, "hold")
	_s(3.4, "enemy jumps behind → turn 180 轉身", Vector2.ZERO, {"enemy": [170.0, 5.0, 0.2]})
	_s(1.6, "hold")
	_s(3.0, "enemy jumps to the right → turn 90 右轉身", Vector2.ZERO, {"enemy": [-95.0, 5.0, 0.2]})
	_s(1.6, "hold")
	_s(3.4, "enemy jumps behind (right) → turn 180 轉身", Vector2.ZERO, {"enemy": [-170.0, 5.0, 0.2]})
	_s(1.6, "hold")
	_s(5.0, "circle strafe 繞敵橫移（敵人固定，距離 2.5 m）", Vector2(1, 0), {"enemy": [0.0, 2.5, 0.3]})
	_s(1.4, "stop")
	_s(1.4, "dodge left 閃避（左）", Vector2(-1, 0), {"dodge": 0.1, "hold": 0.25, "side": -1.0, "enemy": [0.0, 5.0, 0.01]})
	_s(1.4, "idle")
	_s(1.4, "dodge right 閃避（右）", Vector2(1, 0), {"dodge": 0.1, "hold": 0.25, "side": 1.0})
	_s(1.4, "idle")
	_s(1.8, "walk then dodge 前進中閃避（左）", Vector2(0, 1), {"dodge": 1.2, "hold": 1.3, "side": -1.0})
	_s(1.6, "idle")
	_s(2.0, "idle end")

var _enemy_move_t := 0.0
var _enemy_from := Vector3.ZERO
var _enemy_to := Vector3.ZERO
var _enemy_dur := 0.0

func _tour_step(delta: float) -> void:
	tour_t += delta
	var t := tour_t - TOUR_START_DELAY
	if t < 0.0:
		return
	# 找目前段落
	var acc := 0.0
	var ix := -1
	for i in tour_steps.size():
		if t < acc + tour_steps[i]["d"]:
			ix = i
			break
		acc += tour_steps[i]["d"]
	if ix < 0:
		if tour_ix != -2:
			tour_ix = -2
			_finish_tour()
		return
	if ix != tour_ix:
		tour_ix = ix
		var st: Dictionary = tour_steps[ix]
		cur_label = st["label"]
		tour_input = st["mv"]
		tour_step_t0 = tour_t
		tour_hold = float(st.get("hold", -1.0))
		tour_dodge_side = float(st.get("side", 0.0))
		dodge_fired = not st.has("dodge")
		attack_fired = not st.has("attack")
		tour_attack_at = tour_t + float(st.get("attack", -1.0)) if st.has("attack") else -1.0
		attack2_fired = not st.has("attack2")
		tour_attack2_at = tour_t + float(st.get("attack2", -1.0)) if st.has("attack2") else -1.0
		attack3_fired = not st.has("attack3")
		tour_attack3_at = tour_t + float(st.get("attack3", -1.0)) if st.has("attack3") else -1.0
		tour_dodge_at = tour_t + float(st.get("dodge", -1.0)) if st.has("dodge") else -1.0
		if st.has("enemy"):
			var e: Array = st["enemy"]          # [相對朝向（度）, 距離（m）, 移動秒數]
			_enemy_from = enemy_pos
			_enemy_to = _enemy_rel(deg_to_rad(float(e[0])), float(e[1]))
			_enemy_move_t = 0.0
			_enemy_dur = maxf(float(e[2]), 0.001)
		else:
			_enemy_dur = 0.0
		tour_meta.append({"i": ix, "label": cur_label, "t0": tour_t, "t1": tour_t + float(st["d"]), "mv": [st["mv"].x, st["mv"].y]})
	if tour_hold >= 0.0 and tour_t - tour_step_t0 > tour_hold:
		tour_input = Vector2.ZERO
	if _enemy_dur > 0.0 and _enemy_move_t < _enemy_dur:
		_enemy_move_t += delta
		enemy_pos = _enemy_from.lerp(_enemy_to, smoothstep(0.0, 1.0, clampf(_enemy_move_t / _enemy_dur, 0.0, 1.0)))

func _finish_tour() -> void:
	if log_path != "":
		_save_log()
	print("TOUR_DONE t=", tour_t)
	get_tree().quit()

# ---------------------------------------------------------------- 逐幀記錄（腳滑／布料／刀鞘分析用）
func _init_log() -> void:
	var chains: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://characters/yoriichi/v24/chains.json"))
	log_bones = ["Hips", "Spine", "Spine1", "Spine2", "Neck", "Head", "LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase", "RightUpLeg", "RightLeg", "RightFoot", "RightToeBase", "LeftArm", "LeftForeArm", "LeftHand", "RightArm", "RightForeArm", "RightHand"]
	var bone_names: Array = []
	for b in log_bones:
		bone_names.append("mixamorig_" + b)
	for c in chains["chains"]:
		for bb in c["bones_game"]:
			bone_names.append(bb)
	log_bones = bone_names
	log_cols = ["t", "state", "g", "actor_x", "actor_z", "actor_yaw", "enemy_x", "enemy_z", "seg", "sheath_x", "sheath_y", "sheath_z", "sheath_ax", "sheath_ay", "sheath_az", "tip_x", "tip_y", "tip_z"]
	var swn := rig.find_child("Sword_Hand", true, false) as Node3D
	if swn:
		_log_mi = SwordGeo.find_mesh(swn)
		_log_geo = SwordGeo.analyze(swn)
	if _log_mi and _log_geo.get("ok", false):
		log_extra_cols = ["hilt_x", "hilt_y", "hilt_z", "guard_x", "guard_y", "guard_z", "blade_tip_x", "blade_tip_y", "blade_tip_z",
			"blade_tip_vx", "blade_tip_vy", "blade_tip_vz", "blade_dir_x", "blade_dir_y", "blade_dir_z"]

func _on_pre_draw() -> void:
	if log_path == "" or tour_t < TOUR_START_DELAY:
		return
	var sheath := rig.find_child("Sheath", true, false) as Node3D
	var sword := rig.find_child("Sword_Hand", true, false) as Node3D
	var row := PackedFloat32Array()
	row.append(tour_t - TOUR_START_DELAY)
	row.append(float(combat.state))
	row.append(combat.g)
	row.append(actor.global_position.x)
	row.append(actor.global_position.z)
	row.append(actor.rotation.y)
	row.append(enemy.global_position.x)
	row.append(enemy.global_position.z)
	row.append(float(max(tour_ix, 0)))
	var sp := sheath.global_position if sheath else Vector3.ZERO
	var sa := sheath.global_basis.y if sheath else Vector3.ZERO
	row.append_array(PackedFloat32Array([sp.x, sp.y, sp.z, sa.x, sa.y, sa.z]))
	# 舊欄位 tip_x/y/z＝Sword_Hand 原點（刀網格 y=0：柄上、鍔中心下方約 7 cm（世界）），**不是刀尖**；為相容保留原值，真刀尖見附加欄位 blade_tip_*
	var tip := sword.global_transform * Vector3(0, 0, 0) if sword else Vector3.ZERO
	row.append_array(PackedFloat32Array([tip.x, tip.y, tip.z]))
	for n in log_bones:
		var i := sk.find_bone(n)
		var p := sk.global_transform * sk.get_bone_global_pose(i).origin if i >= 0 else Vector3.ZERO
		row.append_array(PackedFloat32Array([p.x, p.y, p.z]))
	if not log_extra_cols.is_empty():
		var w := SwordGeo.world(_log_geo, _log_mi)
		var bt: Vector3 = w["tip"]
		var dtl := get_process_delta_time()
		var vel: Vector3 = (bt - (_log_prev_tip as Vector3)) / dtl if _log_prev_tip is Vector3 and dtl > 0.0 else Vector3(NAN, NAN, NAN)
		_log_prev_tip = bt
		var hv: Vector3 = w["hilt"]
		var gv: Vector3 = w["guard"]
		var dv: Vector3 = w["dir"]
		row.append_array(PackedFloat32Array([hv.x, hv.y, hv.z, gv.x, gv.y, gv.z, bt.x, bt.y, bt.z, vel.x, vel.y, vel.z, dv.x, dv.y, dv.z]))
	log_rows.append_array(row)
	log_n += 1

func _save_log() -> void:
	DirAccess.make_dir_recursive_absolute(log_path.get_base_dir())
	var f := FileAccess.open(log_path + ".bin", FileAccess.WRITE)
	f.store_buffer(log_rows.to_byte_array())
	f.close()
	var meta := {"cols": log_cols, "bones": log_bones, "rows": log_n, "width": log_cols.size() + log_bones.size() * 3 + log_extra_cols.size(), "segments": tour_meta, "start_delay": TOUR_START_DELAY,
		"extra_cols": log_extra_cols, "extra_offset": log_cols.size() + log_bones.size() * 3,
		"col_notes": {"tip_x/tip_y/tip_z": "DEPRECATED name: value is the Sword_Hand node origin (mesh y=0: on the grip, ~7 cm in world below the tsuba centre), NOT the blade tip; kept unchanged for compatibility",
			"hilt_*": "world; centroid of tsuka vertices (sword_geometry.gd)", "guard_*": "world; centroid of the widest 2 cm cross-section (tsuba)",
			"blade_tip_*": "world; mesh vertex extremum along the blade axis", "blade_tip_v*": "world m/s; difference of blade_tip between consecutive rows / process delta (first row NaN)",
			"blade_dir_*": "world unit vector guard->tip (chord of the curved blade)", "bones": "world positions, offset len(cols)"},
		"blade_geometry": {"tip_local": SwordGeo._v(_log_geo["tip_local"]), "guard_local": SwordGeo._v(_log_geo["guard_local"]), "hilt_local": SwordGeo._v(_log_geo["hilt_local"]), "method": _log_geo["method"]} if _log_geo.get("ok", false) else {}}
	var m := FileAccess.open(log_path + ".json", FileAccess.WRITE)
	m.store_string(JSON.stringify(meta))
	m.close()

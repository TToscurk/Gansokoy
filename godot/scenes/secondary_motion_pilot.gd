extends Node3D
## Wind V2 Phase F 試驗場：WindSecondaryMotion 用在狼 rig（assets/enemies/wolf/wolf_pounce.glb 的實例，
## 不動正式 enemy_wolf／戰鬥檔案）。WIND_V2_REVIEW。
##   Wolf_Still：原地 Idle，只吃風（尾巴與鬃毛順風偏、陣風時延遲擺動、風停回彈）
##   Wolf_Runner：繞半徑 5 m 圓跑（Run 動畫）——相對空氣（迎面風）＋轉向向心加速度讓尾巴往後、往外甩
## 鍵：F9 風面板（1–4 preset、G 陣風）、R 切換奔跑。

const WOLF := "res://assets/enemies/wolf/wolf_pounce.glb"
const PROFILE := "res://data/wind/secondary/wolf.tres"
const MOTION := preload("res://scripts/wind/secondary_motion.gd")

var runner: Node3D
var still: Node3D
var running := true
var _ang := 0.0
const R := 5.0
const CENTER := Vector3(3.0, 0.0, -1.0)
const SPEED := 5.5


func _ready() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	g.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.32, 0.36, 0.24)
	g.material_override = gm
	add_child(g)
	still = spawn_wolf("Wolf_Still", Vector3(-3.0, 0, 1.0), "Wolf_Idle", true)
	runner = spawn_wolf("Wolf_Runner", CENTER + Vector3(R, 0, 0), "Wolf_Run", true)
	var cam := Camera3D.new()
	cam.name = "PILOT_camera"
	cam.position = Vector3(0.5, 3.2, 11.5)
	cam.fov = 55.0
	add_child(cam)
	cam.look_at(Vector3(0.5, 0.6, -0.5), Vector3.UP)
	cam.current = true
	var w := get_node_or_null("/root/Wind")
	if w:
		w.set_focus(Vector3.ZERO, true)


## 生成一隻狼；with_motion＝是否掛 WindSecondaryMotion（驗證工具用 false 做「純動畫」對照組）
func spawn_wolf(nm: String, pos: Vector3, anim: String, with_motion: bool) -> Node3D:
	var root := Node3D.new()
	root.name = nm
	root.position = pos
	add_child(root)
	var inst: Node = (load(WOLF) as PackedScene).instantiate()
	var sk := inst.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	# Wind 會自動替狼 rig 接 WindSecondaryMotion；試驗場自己接（或明確不接＝對照組），所以先排除
	sk.set_meta("wind_secondary_off", true)
	root.add_child(inst)
	if with_motion:
		var m: SkeletonModifier3D = MOTION.new()
		m.name = "WindSecondaryMotion"
		m.set("profile", load(PROFILE))
		sk.add_child(m)
		m.set("body_path", m.get_path_to(root))
		m.call("_rebuild")
	var ap := inst.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var a := ap.get_animation(anim)
	if a:
		a.loop_mode = Animation.LOOP_LINEAR
	ap.play(anim)
	return root


func _physics_process(delta: float) -> void:
	if runner == null or not running:
		return
	_ang += SPEED / R * delta
	var p := CENTER + Vector3(cos(_ang), 0, sin(_ang)) * R
	var v := Vector3(-sin(_ang), 0, cos(_ang))
	runner.position = p
	runner.rotation.y = atan2(v.x, v.z)


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and (e as InputEventKey).physical_keycode == KEY_R:
		running = not running

# 角色打樣場 —— 把角色排成一列站好，用來看造型與材質。
#
#   godot --headless --path godot --script tools/gen_charpreview.gd
#   godot --path godot -- --map=charpreview --shot=/tmp/c.png --shot-cam=...
#
# 為什麼需要這張圖：角色一放進村子就會被 npc.gd 帶著走，截圖抓不到；
# 而且街景的光照與背景會干擾判斷。這張是中性背景 + 固定站位。
extends SceneTree

const Lib = preload("res://tools/gen_lib.gd")
const OUT_DIR := "res://maps/charpreview/"
const CHARS := ["villager_a", "villager_b", "villager_c"]

var lib: Lib

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR + "gen"))
	var root := Node3D.new()
	root.name = "CharPreview"
	root.set_meta("own_colliders", true)
	lib = Lib.new()
	lib.setup(root, 1)

	# 中性地面：淺灰石板，不要有花紋搶戲
	var ground := lib.box(root, "Terrain", Vector3(40, 0.4, 40),
		lib.pbr("preview_ground", "cobble", 0.12, Color(0.72, 0.72, 0.70)), Vector3(0, -0.2, 0))
	ground.name = "Terrain"

	# 對照物：一個 1.7m 的柱子，一眼看出角色多高
	lib.box(root, "身高尺_1m7", Vector3(0.12, 1.7, 0.12),
		lib.flat_mat("ruler", Color(0.85, 0.25, 0.25), 0.8), Vector3(1.5, 0.85, 0))
	for i in 17:                                    # 每 10cm 一格
		lib.box(root, "刻度_%d" % i, Vector3(0.2, 0.012, 0.14),
			lib.flat_mat("ruler_tick", Color(0.98, 0.98, 0.98), 0.8),
			Vector3(1.5, 0.1 + float(i) * 0.1, 0))

	for i in CHARS.size():
		var v := lib.char_scene("res://assets/models/%s.glb" % CHARS[i])
		lib.add(root, v, CHARS[i])
		lib.own_all(v)
		# 排在 x=3 一帶：玩家膠囊生在原點，站位要閃開它
		v.position = Vector3(2.4 + float(i) * 1.1, 0, 0)
		# 模型朝 +X；繞 Y 轉 +90° 把 +X 轉到 -Z（面向鏡頭）
		v.rotation.y = PI * 0.5

	# 側面各放一隻，看剪影
	for i in CHARS.size():
		var v2 := lib.char_scene("res://assets/models/%s.glb" % CHARS[i])
		lib.add(root, v2, CHARS[i] + "_側")
		lib.own_all(v2)
		v2.position = Vector3(2.4 + float(i) * 1.1, 0, 1.6)   # 側面（維持朝 +X）

	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.42, 0.55, 0.75)
	sky_mat.sky_horizon_color = Color(0.78, 0.80, 0.80)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.9
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.sdfgi_enabled = false
	var we := WorldEnvironment.new()
	we.environment = env
	lib.add(root, we, "WorldEnvironment")

	var scene := PackedScene.new()
	scene.pack(root)
	var err := ResourceSaver.save(scene, OUT_DIR + "charpreview.tscn")
	print("saved charpreview.tscn err=", err)
	quit(0 if err == OK else 1)

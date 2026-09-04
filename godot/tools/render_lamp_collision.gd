extends SceneTree
## 把路燈的碰撞圓柱畫成可見網格，和實際路燈一起拍照。
##
##   Godot --path godot --script tools/render_lamp_collision.gd
##   （需要渲染，不可 --headless）
##
## 為什麼要這支：碰撞形狀在遊戲裡看不見，「對不對齊」只能靠數字。數字說
## 偏差 0.000 m，但使用者要的是眼睛能確認。這支從 lamp_collision.scn 讀出
## 每個 CylinderShape3D，用同樣的半徑/高度/位置生一個半透明紅色圓柱疊上去。
## 對齊的話紅圓柱會正好套在燈桿上；沒對齊就會像之前那樣浮在旁邊 1.4 m。

const OUT_DIR := "D:/lamp_shots"


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var packed := ResourceLoader.load("res://scenes/main.tscn", "PackedScene") as PackedScene
	var main := packed.instantiate()
	root.add_child(main)
	await process_frame
	main.load_map("slice", "")
	main.player.visible = false
	for i in 10:
		await process_frame

	# 天象：固定正午，讓碰撞體看得清楚（預設 16:56 斜陽會把一半壓進陰影）
	var sky: Node = main.map_root.get_node_or_null("天象系統")
	if sky != null:
		sky.set("一日長度分鐘", 0.0)
		sky.call("設定時刻", 11.0)
		for i in 4:
			await process_frame

	# 讀碰撞、生可見圓柱
	var lamps: Node = main.map_root.get_node_or_null("路燈碰撞")
	if lamps == null:
		print("[SHOT] ✗ 場景裡沒有「路燈碰撞」節點")
		quit(1)
		return

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.15, 0.15, 0.42)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = false

	var shown := 0
	for body in lamps.get_children():
		if not (body is StaticBody3D):
			continue
		var cs := body.get_child(0) as CollisionShape3D
		var cyl := cs.shape as CylinderShape3D
		if cyl == null:
			continue
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = cyl.radius
		cm.bottom_radius = cyl.radius
		cm.height = cyl.height
		cm.radial_segments = 20
		mi.mesh = cm
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.global_position = (body as StaticBody3D).global_position
		main.map_root.add_child(mi)
		shown += 1
	print("[SHOT] 疊上 %d 個紅色碰撞圓柱" % shown)

	var cam := Camera3D.new()
	cam.fov = 60.0
	cam.far = 4000.0
	root.add_child(cam)
	cam.current = true

	# 三組鏡位：都對著實際有路燈的位置
	var shots := [
		{"n": "01_路燈00_側面", "pos": Vector3(225.0, 3.5, -96.3), "look": Vector3(231.4, 2.3, -96.3)},
		{"n": "02_路燈00_斜角", "pos": Vector3(226.5, 6.0, -102.0), "look": Vector3(231.4, 2.3, -96.3)},
		{"n": "03_主街兩排燈", "pos": Vector3(235.0, 4.0, -110.0), "look": Vector3(235.0, 3.0, -60.0)},
		{"n": "04_北端路燈02_03", "pos": Vector3(236.0, 4.0, 74.0), "look": Vector3(236.0, 3.0, 92.0)},
	]
	for s in shots:
		cam.global_position = s["pos"]
		cam.look_at(s["look"], Vector3.UP)
		for i in 12:
			await process_frame
		var path := "%s/%s.png" % [OUT_DIR, s["n"]]
		get_root().get_texture().get_image().save_png(path)
		print("[SHOT] → %s" % path)

	print("[SHOT] done")
	quit(0)

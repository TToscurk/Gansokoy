extends SceneTree
## 收刀態參考照：玩家 Idle 站著（SHEATHED），側／後 3/4 各一張——
## 居合蓄力姿勢的地面真相（刀柄、鞘在身體哪裡）。
## 執行（要視窗）：godot --path godot -s res://tools/capture_iai_ref.gd --audio-driver Dummy

func _init():
	_run.call_deferred()

func _run():
	var vp := SubViewport.new()
	vp.size = Vector2i(1000, 700)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.18, 0.2, 0.24)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.76, 0.8)
	env_node.environment = env
	vp.add_child(env_node)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 45, 0)
	vp.add_child(sun)
	var cam := Camera3D.new()
	vp.add_child(cam)
	var ps := load("res://characters/yoriichi/player_yoriichi.tscn") as PackedScene
	var player := ps.instantiate() as CharacterBody3D
	vp.add_child(player)
	player.input_locked = true   # 不讀輸入，保持收刀站姿
	var floor_body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(50, 1, 50)
	col.shape = box
	col.position.y = -0.5
	floor_body.add_child(col)
	vp.add_child(floor_body)
	var display := TextureRect.new()
	display.texture = vp.get_texture()
	display.size = Vector2(1000, 700)
	root.add_child(display)
	var out := ProjectSettings.globalize_path("res://../artifacts/iai_ref")
	DirAccess.make_dir_recursive_absolute(out)
	for i in 25:
		await physics_frame
		await process_frame
	print("[IAI_REF] sword_state=", player.sword_state, " (0=SHEATHED)")
	var shots := {"side": Vector3(2.6, 1.15, 0.0), "rear34": Vector3(1.9, 1.5, -1.9), "front34": Vector3(-1.9, 1.4, 1.9)}
	for k in shots:
		cam.position = shots[k]
		cam.look_at(Vector3(0, 1.0, 0))
		cam.current = true
		for i in 3:
			await process_frame
		var img := vp.get_texture().get_image()
		img.save_png(out + "/sheathed_%s.png" % k)
		print("[IAI_REF] saved sheathed_%s.png" % k)
	quit(0)

extends SceneTree
## 山犬化光死亡實機拍照：Wolf_Death 動畫 + 溶解 shader + 光點粒子。
##   Godot --headless 拍不到 shader/粒子，必須開視窗跑：
##   Godot.exe --path godot --script tools/capture_wolf_death.gd
##
## 拍 12 張：死亡當下到全消（0.0–4.6 s），另加一張斜角。
## 輸出到 D:/神社/shrine/_review/wolf_death/

const OUT := "D:/神社/shrine/_review/wolf_death/"
const WOLF := "res://characters/combat/enemy_wolf.tscn"
const WolfDissolveFX = preload("res://characters/combat/wolf_dissolve_fx.gd")


func _init() -> void:
	_run.call_deferred()


func _wait(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame


func _shoot(cam: Camera3D, path: String) -> void:
	await _wait(2)
	root.get_viewport().get_texture().get_image().save_png(path)
	print("[DEATH] %s" % path)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var world := Node3D.new()
	root.add_child(world)

	# 暗一點的環境，光點才看得出來
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.05, 0.06, 0.09)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.35, 0.4, 0.5)
	e.ambient_light_energy = 0.6
	e.glow_enabled = true
	e.glow_intensity = 0.55
	e.glow_bloom = 0.12
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	world.add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, 38, 0)
	sun.light_energy = 1.6
	world.add_child(sun)

	var floor_body := StaticBody3D.new()
	var fc := CollisionShape3D.new()
	var fb := BoxShape3D.new()
	fb.size = Vector3(60, 1, 60)
	fc.shape = fb
	fc.position = Vector3(0, -0.5, 0)
	floor_body.add_child(fc)
	var fm := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.16, 0.17, 0.15)
	pm.material = gm
	fm.mesh = pm
	floor_body.add_child(fm)
	world.add_child(floor_body)

	var wolf: CharacterBody3D = (load(WOLF) as PackedScene).instantiate()
	world.add_child(wolf)
	wolf.dodge_enabled = false
	await _wait(20)

	var cam := Camera3D.new()
	cam.fov = 46.0
	cam.position = Vector3(0.15, 1.15, 3.6)
	world.add_child(cam)
	cam.look_at(Vector3(0, 1.0, 0), Vector3.UP)
	cam.current = true
	await _wait(6)

	# 開拍前的活體對照
	await _shoot(cam, OUT + "00_alive.png")

	# 崩軀幹 → 忍殺 → 死亡
	wolf.posture.apply_damage(0.0, 999.0)
	await _wait(4)
	var ok: bool = wolf.execute_deathblow()
	print("[DEATH] deathblow=%s state=%d" % [ok, wolf.state])

	# 依 dissolve_t（動畫真實秒數）取樣，不是牆鐘時間 ——
	# 截圖存檔本身耗時，牆鐘標籤會與動畫進度對不上。
	var marks := [0.0, 0.4, 0.8, 1.2, 1.6, 2.0, 2.4, 2.8, 3.1, 3.4, 3.7, 4.0, 4.6, 5.2]
	var idx := 0
	print("[DEATH] fps=%d" % int(Engine.get_frames_per_second()))
	while idx < marks.size():
		if not is_instance_valid(wolf):
			print("[DEATH] 狼已移除 於 mark=%.1f" % float(marks[idx]))
			break
		var dt: float = wolf._dissolve_t
		if dt + 0.001 < float(marks[idx]):
			await physics_frame
			await process_frame
			continue
		var sk := _skel(wolf)
		var y := 0.0 if sk == null else (sk.global_transform * sk.get_bone_global_pose(0).origin).y
		cam.position = Vector3(0.15, clampf(y + 0.45, 1.15, 3.2), 3.6)
		cam.look_at(Vector3(0, clampf(y + 0.35, 1.0, 3.1), 0), Vector3.UP)
		var dv: float = float(WolfDissolveFX.sample(dt).get("dissolve", 0.0))
		print("[DEATH] mark=%.1f dissolve_t=%.2f dissolve=%.3f rootY=%.3f" % [float(marks[idx]), dt, dv, y])
		await _shoot(cam, OUT + "%02d_d%.1fs.png" % [idx + 1, float(marks[idx])])
		idx += 1

	print("[DEATH] done")
	quit(0)


func _skel(n: Node) -> Skeleton3D:
	var st: Array[Node] = [n]
	while st.size() > 0:
		var c: Node = st.pop_back()
		for k in c.get_children():
			st.push_back(k)
		if c is Skeleton3D:
			return c as Skeleton3D
	return null

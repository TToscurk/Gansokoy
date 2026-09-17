extends SceneTree
## 把 assets/landscape/ 每棵樹的「底部 1/3」單獨拍成特寫，供使用者點名哪些底部不乾淨。
##   Godot --path godot --script tools/shot_tree_bottoms.gd
## 檔名用 ASCII（capture 流程對 CJK 檔名不友善）。

const OUT := "D:/神社/shrine/_review/tree_bottoms/"
const LS := "res://assets/landscape/"
const LIST := [
	["普通樹.glb", "futsuu"],
	["大衫.glb", "sugi1"],
	["2大衫.glb", "sugi2"],
	["針葉樹1.glb", "conifer1"],
	["針葉樹2glb.glb", "conifer2"],
	["針葉林樹3.glb", "conifer3"],
	["針葉林樹4.glb", "conifer4"],
	["盆樹.glb", "bonsai"],
	["櫻花樹.glb", "sakura"],
	["楓樹.glb", "momiji"],
	["松樹.glb", "matsu"],
	["鎮守之杜.glb", "chinju"],
	["竹垣.glb", "takegaki"],
]


func _init() -> void:
	_run.call_deferred()


func _wait(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	root.size = Vector2i(640, 640)
	var world := Node3D.new()
	root.add_child(world)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.62, 0.66, 0.72)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.9, 0.9, 0.95)
	e.ambient_light_energy = 1.5
	env.environment = e
	world.add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-35.0), deg_to_rad(40.0), 0.0)
	sun.light_energy = 1.1
	world.add_child(sun)

	# 參考地面：一片灰白平面在 y=0，讓「樹底與地面接合」看得出來
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40.0, 40.0)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.72, 0.70, 0.66)
	ground.material_override = gm
	world.add_child(ground)

	var cam := Camera3D.new()
	world.add_child(cam)
	cam.current = true

	for row in LIST:
		var file: String = row[0]
		var slug: String = row[1]
		var p: String = LS + file
		if not ResourceLoader.exists(p):
			print("MISSING %s" % file)
			continue
		var inst: Node3D = (load(p) as PackedScene).instantiate()
		world.add_child(inst)
		await _wait(4)

		var acc := AABB()
		var has := false
		var st: Array = [inst]
		while not st.is_empty():
			var n: Node = st.pop_back()
			st.append_array(n.get_children())
			if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
				var mi := n as MeshInstance3D
				var b: AABB = mi.global_transform * mi.mesh.get_aabb()
				acc = acc.merge(b) if has else b
				has = true
		if not has:
			print("NOMESH %s" % file)
			inst.queue_free()
			continue

		var h: float = maxf(acc.size.y, 0.01)
		var ctr: Vector3 = acc.position + acc.size * 0.5
		# 底部特寫：對準最低 18% 高度處，水平視角略微俯視
		var focus := Vector3(ctr.x, acc.position.y + h * 0.10, ctr.z)
		var dist: float = maxf(acc.size.x, acc.size.z) * 1.6 + h * 0.30
		cam.global_position = focus + Vector3(0.0, h * 0.10, dist)
		cam.look_at(focus, Vector3.UP)
		await _wait(8)
		root.get_viewport().get_texture().get_image().save_png(OUT + slug + "_bottom.png")

		# 同時拍一張全株，方便對照
		cam.global_position = ctr + Vector3(0.0, h * 0.12, h * 1.9)
		cam.look_at(ctr, Vector3.UP)
		await _wait(8)
		root.get_viewport().get_texture().get_image().save_png(OUT + slug + "_full.png")

		print("SHOT %-12s %-10s h=%.2f ymin=%.3f" % [file, slug, h, acc.position.y])
		inst.queue_free()
		await _wait(3)
	print("DONE -> %s" % OUT)
	quit(0)

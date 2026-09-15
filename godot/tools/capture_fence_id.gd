extends SceneTree
## 拍「小河的竹垣」候選，供使用者指認要刪哪一組。
## A：slice 實際場景，運河邊的 Fence_Wood.gltf 木栅欄（EastBankDressing/fence_*）
## B：prototypes/waterway_art_review.tscn 裡的真竹垣.glb（take_fence.gd）
##
## B 是實驗場景、本身沒有光照，單獨載入會全黑——所以載入後自己補一盞
## DirectionalLight3D 與環境，否則拍出來judge不了。

func _init() -> void:
	_run.call_deferred()

func _wait(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame

func _shoot(host: Node, cam: Camera3D, pos: Vector3, look: Vector3, path: String) -> void:
	cam.global_position = pos
	cam.look_at(look, Vector3.UP)
	await _wait(8)
	host.get_viewport().get_texture().get_image().save_png(path)
	print("[F] %s" % path)

## 補光：實驗場景沒有 WorldEnvironment / 太陽時用
func _add_light(host: Node) -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, -35.0, 0.0)
	sun.light_energy = 1.3
	host.add_child(sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	host.add_child(we)

func _run() -> void:
	var d := "D:/神社/shrine/_review/fence_id/"
	DirAccess.make_dir_recursive_absolute(d)

	# ---- A：slice 運河邊木栅欄，x=303.3、z -23.9..44
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _wait(3)
	main.load_map("slice", "trail")
	await _wait(90)
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.current = true
	# 貼近單支，正面平視——看清楚板材形式
	await _shoot(main, cam, Vector3(301.5, 1.5, -23.9), Vector3(303.3, 1.2, -23.9),
		d + "A1_close.png")
	# 沿排斜看，整排的節奏
	await _shoot(main, cam, Vector3(300.5, 2.2, -28.0), Vector3(303.3, 1.0, 0.0),
		d + "A2_along.png")
	# 拉遠帶運河，交代它在小河哪一側
	await _shoot(main, cam, Vector3(295.0, 6.0, -10.0), Vector3(305.0, 0.5, 5.0),
		d + "A3_context.png")
	main.free()
	await _wait(5)

	# ---- B：prototypes 的真竹垣，x=-5.85、z -72..84
	var proto_path := "res://maps/slice/prototypes/waterway_art_review.tscn"
	if ResourceLoader.exists(proto_path):
		var proto = load(proto_path).instantiate()
		root.add_child(proto)
		_add_light(proto)
		await _wait(30)
		var cam2 := Camera3D.new()
		proto.add_child(cam2)
		cam2.current = true
		await _shoot(proto, cam2, Vector3(-7.6, 3.6, -20.0), Vector3(-5.85, 3.4, -20.0),
			d + "B1_close.png")
		await _shoot(proto, cam2, Vector3(-7.4, 4.2, -34.0), Vector3(-5.85, 3.2, 0.0),
			d + "B2_along.png")
		await _shoot(proto, cam2, Vector3(-14.0, 6.5, -12.0), Vector3(-4.0, 2.0, 4.0),
			d + "B3_context.png")
	else:
		print("[F] 找不到 %s" % proto_path)
	quit(0)

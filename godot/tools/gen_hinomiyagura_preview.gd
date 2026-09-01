extends SceneTree
## 火見櫓單體預覽：中性場景，用於資產本身的外觀審查（不進 slice）。
## 依 blender-asset-production 的「新資產先跑單模型預覽」原則。

func _init() -> void:
	var root: Node3D = Node3D.new()
	root.name = "hinomiyagura"

	# 中性地面
	var ground: MeshInstance3D = MeshInstance3D.new()
	ground.name = "Ground"
	var pm: PlaneMesh = PlaneMesh.new()
	pm.size = Vector2(60, 60)
	ground.mesh = pm
	var gm: StandardMaterial3D = StandardMaterial3D.new()
	gm.albedo_color = Color(0.42, 0.42, 0.40)
	gm.roughness = 1.0
	ground.material_override = gm
	root.add_child(ground)
	ground.owner = root

	# 資產：縮放到 15m，底面貼地
	var scn: PackedScene = load("res://assets/landmark/火見櫓.glb")
	var t: Node3D = scn.instantiate() as Node3D
	t.name = "火見櫓"
	var bb: AABB = _local_bbox(t)
	var s: float = 15.0 / maxf(bb.size.y, 0.001)
	t.scale = Vector3(s, s, s)
	var c: Vector3 = bb.position + bb.size * 0.5
	t.position = Vector3(-c.x * s, -bb.position.y * s, -c.z * s)
	root.add_child(t)
	t.owner = root

	# 比例尺：1.7m 人形柱 + 5m 高的町家量體，放在塔旁
	var human: MeshInstance3D = MeshInstance3D.new()
	human.name = "ScaleHuman_1m7"
	var cm: CylinderMesh = CylinderMesh.new()
	cm.top_radius = 0.22
	cm.bottom_radius = 0.22
	cm.height = 1.7
	human.mesh = cm
	human.position = Vector3(5.0, 0.85, 3.0)
	var hm: StandardMaterial3D = StandardMaterial3D.new()
	hm.albedo_color = Color(0.85, 0.25, 0.25)
	human.material_override = hm
	root.add_child(human)
	human.owner = root

	var house: MeshInstance3D = MeshInstance3D.new()
	house.name = "ScaleHouse_5m"
	var bm2: BoxMesh = BoxMesh.new()
	bm2.size = Vector3(8, 5, 6)
	house.mesh = bm2
	house.position = Vector3(-12.0, 2.5, 0.0)
	var hm2: StandardMaterial3D = StandardMaterial3D.new()
	hm2.albedo_color = Color(0.55, 0.52, 0.50)
	house.material_override = hm2
	root.add_child(house)
	house.owner = root

	# 中性打光
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-42, -55, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	root.add_child(sun)
	sun.owner = root

	var env: WorldEnvironment = WorldEnvironment.new()
	env.name = "WorldEnvironment"
	var e: Environment = Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.62, 0.66, 0.70)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.58, 0.62)
	e.ambient_light_energy = 0.55
	env.environment = e
	root.add_child(env)
	env.owner = root

	var packed: PackedScene = PackedScene.new()
	packed.pack(root)
	var err: int = ResourceSaver.save(packed, "res://maps/hinomiyagura/hinomiyagura.tscn")
	print("SAVE %s  scale=%.4f  高=%.2fm  底=%.2f x %.2f" % [
		"OK" if err == OK else "FAIL %d" % err, s, bb.size.y * s, bb.size.x * s, bb.size.z * s])
	quit()

func _local_bbox(n: Node3D) -> AABB:
	var acc: AABB = AABB()
	var has: bool = false
	var stack: Array = [[n, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var pair: Array = stack.pop_back()
		var node: Node = pair[0]
		var xf: Transform3D = pair[1]
		if node is Node3D:
			xf = xf * (node as Node3D).transform
		if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
			var a: AABB = xf * (node as MeshInstance3D).mesh.get_aabb()
			if has:
				acc = acc.merge(a)
			else:
				acc = a
				has = true
		for c in node.get_children():
			stack.push_back([c, xf])
	return acc

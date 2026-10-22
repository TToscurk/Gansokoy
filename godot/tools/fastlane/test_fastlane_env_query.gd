extends SceneTree
## 快速通道環境查詢（place_building.gd 的 _is_env／_blocked／_ray_env）單元測試，headless、合成世界、約 1 秒。
## 2026-10-22 noka_b：阿求袖子模擬的 WorldBoundaryShape3D（layer 20 無限平面）擋住外圍膠囊 23/23 點與全部鏡位。
##   godot --headless --path godot --script res://tools/fastlane/test_fastlane_env_query.gd
const PB := preload("res://tools/fastlane/place_building.gd")

var bad := 0
var n := 0


func _init() -> void:
	_run.call_deferred()


func _ok(label: String, got: Variant, want: Variant) -> void:
	n += 1
	var ok: bool = got == want
	if not ok:
		bad += 1
	print("%s [ENVQ] %s: got %s want %s" % ["ok " if ok else "BAD", label, got, want])


func _body(cls: String, shape: Shape3D, pos: Vector3, layer: int) -> CollisionObject3D:
	var b: CollisionObject3D = ClassDB.instantiate(cls)
	b.collision_layer = layer
	var cs := CollisionShape3D.new()
	cs.shape = shape
	b.add_child(cs)
	b.position = pos
	root.add_child(b)
	return b


func _run() -> void:
	var wall_shape := BoxShape3D.new()
	wall_shape.size = Vector3(2, 3, 0.2)
	var wall := _body("StaticBody3D", wall_shape, Vector3(5, 1.5, 0), 1)
	_body("AnimatableBody3D", WorldBoundaryShape3D.new(), Vector3(0, 1.69, 0), 1 << 19)   # 袖子模擬地板
	var npc_shape := CapsuleShape3D.new()
	var npc := _body("AnimatableBody3D", npc_shape, Vector3(-5, 1, 0), 1)                 # NPC 身體（魔理沙型）
	_body("CharacterBody3D", npc_shape, Vector3(-5, 1, 5), 1)
	for i in 3:
		await physics_frame
	var space := root.get_world_3d().direct_space_state
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.7
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.transform = Transform3D(Basis.IDENTITY, Vector3(0, 0.97, 0))
	_ok("對照：不過濾時膠囊確實撞到 layer 20 無限平面", space.intersect_shape(q, 4).size() > 0, true)
	_ok("空地膠囊：layer 20 無限平面不擋", PB._blocked(space, q), false)
	q.transform = Transform3D(Basis.IDENTITY, Vector3(5, 0.97, 0))
	_ok("layer 1 靜態牆要擋", PB._blocked(space, q), true)
	q.transform = Transform3D(Basis.IDENTITY, Vector3(-5, 0.97, 0))
	_ok("NPC 身體（AnimatableBody3D）不擋", PB._blocked(space, q), false)
	q.transform = Transform3D(Basis.IDENTITY, Vector3(-5, 0.97, 5))
	_ok("NPC 身體（CharacterBody3D）不擋", PB._blocked(space, q), false)
	var raw := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0, 5, 0), Vector3(0, -1, 0)))
	_ok("對照：不過濾時垂直射線打到無限平面", raw.is_empty(), false)
	_ok("鏡位射線：穿過無限平面不算遮擋", PB._ray_env(space, Vector3(0, 5, 0), Vector3(0, -1, 0), [] as Array[RID]).is_empty(), true)
	_ok("鏡位射線：穿過 NPC 不算遮擋", PB._ray_env(space, Vector3(-5, 1, -5), Vector3(-5, 1, 2), [] as Array[RID]).is_empty(), true)
	var hw := PB._ray_env(space, Vector3(5, 1.5, -5), Vector3(5, 1.5, 5), [] as Array[RID])
	_ok("鏡位射線：牆要擋", hw.get("collider") == wall, true)
	_ok("_is_env：靜態牆是環境、NPC 不是", [PB._is_env(wall), PB._is_env(npc)], [true, false])
	print("[ENVQ] %d/%d ok" % [n - bad, n])
	quit(bad)

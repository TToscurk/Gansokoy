extends SceneTree
## 毛玉實機體檢：載入真的 trail，逼毛玉逃跑，每幀量它離地多高。
##
##   Godot --headless --path godot --script tools/verify_kedama.gd
##
## 為什麼要有這支：靜態算地形落差只能證明「舊做法會沉」，
## 不能證明新做法真的貼地。這裡量的是跑起來之後的實際 y。

var fails := 0
var main: Node
var space: PhysicsDirectSpaceState3D


func _init() -> void:
	_run.call_deferred()


func check(label: String, ok: bool) -> void:
	if not ok:
		fails += 1
	print("[KEDAMA] %s %s" % ["PASS" if ok else "FAIL", label])


func _s(n: int) -> void:
	for i in n:
		await physics_frame


func _gy(x: float, z: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 90.0, z), Vector3(x, -40.0, z))
	q.collision_mask = 0xFFFFFFFF
	var hit := space.intersect_ray(q)
	return hit.position.y if hit.has("position") else -INF


func _run() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _s(4)
	main.load_map("trail", "")
	await _s(90)
	space = main.get_viewport().world_3d.direct_space_state
	var player: Node3D = main.player

	var all := main.get_tree().get_nodes_in_group("kedama")
	check("毛玉已生成（%d 隻）" % all.size(), all.size() >= 4)

	# ── 1. 擺放時就要貼地 ──
	var worst_place := 0.0
	var worst_name := ""
	for k in all:
		var n := k as Node3D
		var g := _gy(n.global_position.x, n.global_position.z)
		if g == -INF:
			continue
		var d: float = absf(n.global_position.y - g)
		if d > worst_place:
			worst_place = d
			worst_name = str(n.get_parent().name)
	check("初始擺放全部貼地（最大偏差 %.2f m @ %s）" % [worst_place, worst_name], worst_place < 0.35)

	# ── 2. 逃跑全程貼地 ──
	# 把玩家丟到逃跑毛玉群旁邊觸發逃跑
	player.global_position = Vector3(2.6, _gy(2.6, -74.0) + 1.0, -74.0)
	await _s(20)
	var fleeing := []
	for k in main.get_tree().get_nodes_in_group("kedama"):
		if int(k.get("mode")) == 1 and bool(k.get("_noticed")):
			fleeing.append(k)
	check("靠近後毛玉起跑（%d 隻）" % fleeing.size(), fleeing.size() >= 2)

	var worst_run := 0.0
	var worst_at := ""
	var samples := 0
	for f in 150:
		await physics_frame
		for k in fleeing:
			if not is_instance_valid(k):
				continue
			var n := k as Node3D
			var g := _gy(n.global_position.x, n.global_position.z)
			if g == -INF:
				continue
			var d: float = n.global_position.y - g
			samples += 1
			if absf(d) > absf(worst_run):
				worst_run = d
				worst_at = "%s @ (%.1f, %.1f)" % [n.name, n.global_position.x, n.global_position.z]
	check("逃跑全程貼地（%d 次取樣，最大偏差 %+.2f m %s）" % [samples, worst_run, worst_at],
		absf(worst_run) < 0.3)

	# ── 3. 最後真的消失 ──
	await _s(200)
	var left := 0
	for k in main.get_tree().get_nodes_in_group("kedama"):
		if int(k.get("mode")) == 1:
			left += 1
	check("逃跑毛玉全部消失（剩 %d）" % left, left == 0)

	# ── 4. 果實有留下 ──
	check("逃光後留下果實", main.map_root.find_child("DroppedFruit", true, false) != null)

	print("[KEDAMA] failures=%d" % fails)
	quit(1 if fails > 0 else 0)

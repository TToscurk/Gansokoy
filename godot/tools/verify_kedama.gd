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
	# 2026-09-17：逃跑群刪除後，獸道只剩受傷毛玉一隻。
	check("毛玉已生成（%d 隻）" % all.size(), all.size() == 1)

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
	# 2026-09-17：逃跑毛玉群（果實那一格）已刪除。獸道只剩受傷毛玉，
	# 它的「逃走」由 WoundedYokaiEvent 選『靠近』後呼叫 flee_away() 觸發，
	# 這裡直接呼叫來驗同一條貼地路徑。
	var wounded: Node3D = null
	for k in all:
		if int(k.get("mode")) == 2:
			wounded = k as Node3D
	check("場上有受傷毛玉", wounded != null)
	if wounded == null:
		print("[KEDAMA] failures=%d" % fails)
		quit(1)
		return
	wounded.call("flee_away")
	await _s(4)
	check("呼叫 flee_away 後轉成逃跑", int(wounded.get("mode")) == 1)

	var worst_run := 0.0
	var worst_at := ""
	var samples := 0
	for f in 150:
		await physics_frame
		if not is_instance_valid(wounded):
			break
		var g := _gy(wounded.global_position.x, wounded.global_position.z)
		if g == -INF:
			continue
		var d: float = wounded.global_position.y - g
		samples += 1
		if absf(d) > absf(worst_run):
			worst_run = d
			worst_at = "(%.1f, %.1f)" % [wounded.global_position.x, wounded.global_position.z]
	check("逃跑全程貼地（%d 次取樣，最大偏差 %+.2f m %s）" % [samples, worst_run, worst_at],
		absf(worst_run) < 0.3)

	# ── 3. 最後真的消失 ──
	await _s(200)
	var left := 0
	for k in main.get_tree().get_nodes_in_group("kedama"):
		if int(k.get("mode")) == 1:
			left += 1
	check("逃跑毛玉全部消失（剩 %d）" % left, left == 0)

	print("[KEDAMA] failures=%d" % fails)
	quit(1 if fails > 0 else 0)

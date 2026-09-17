extends SceneTree
## 精簡後獸道任務流程回歸測試。
## Godot --headless --path godot --script tools/verify_quest_flow.gd

var fails := 0

func _init() -> void:
	_run.call_deferred()

func check(label: String, ok: bool) -> void:
	print("[QFLOW] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok: fails += 1

func step(n: int = 6) -> void:
	for i in n: await process_frame

func _mk_world() -> Array:
	var world := Node3D.new()
	root.add_child(world)
	world.add_child((load("res://maps/trail/trail_interactions.tscn") as PackedScene).instantiate())
	var player := CharacterBody3D.new()
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.7
	collision.shape = capsule
	player.add_child(collision)
	player.add_to_group("player")
	world.add_child(player)
	return [world, player]

func _run() -> void:
	var qm: Node = root.get_node("/root/QuestManager")
	var sf: Node = root.get_node("/root/StoryFlags")
	var dm: Node = root.get_node("/root/DialogueManager")

	# A. MQ00 直接接山犬；山犬打完直接接毛玉。
	qm.call("reset"); sf.call("reset")
	qm.call("start_quest", "MQ00")
	qm.call("report_event", "REACH", "trail_leave_clearing")
	check("A1 MQ00 完成後直接開啟 MQ02", qm.call("is_completed", "MQ00") and qm.call("is_active", "MQ02"))
	check("A2 已刪除的 MQ01 不會出現在進度", not (qm.get("_progress") as Dictionary).has("MQ01"))
	qm.call("report_event", "DEFEAT", "trail_wolf")
	check("A3 擊退山犬即完成 MQ02", qm.call("is_completed", "MQ02"))
	check("A4 不必踩痕跡，直接續行 MQ03", qm.call("is_active", "MQ03"))

	# B. 受傷妖怪早到仍可在稍後補算。
	qm.call("reset"); sf.call("reset")
	var b := _mk_world()
	var world_b: Node3D = b[0]
	var player_b: CharacterBody3D = b[1]
	await step(4)
	qm.call("start_quest", "MQ02")
	var auto_advance := func(_s: String, _p: Texture2D, _t: String, choices: PackedStringArray) -> void:
		dm.call_deferred("advance", 0) if choices.size() > 0 else dm.call_deferred("advance")
	dm.connect("line_shown", auto_advance)
	player_b.global_position = Vector3(-1.54, 8.8, -90.74)
	await step(40)
	check("B1 受傷妖怪事件已演出", sf.call("get_flag", "wounded_yokai_played"))
	check("B2 早到沒有跳過 MQ02", qm.call("is_active", "MQ02"))
	# 2026-09-17：MQ03 的果實那一格已刪，只剩 trail_wounded_yokai。
	# 受傷妖怪的事件是在 MQ02 還沒完成時就發生的（早到）→ 進 _pending，
	# 擊退山犬完成 MQ02、鏈到 MQ03 之後應該被自動補算掉。
	qm.call("report_event", "DEFEAT", "trail_wolf")
	await step(10)
	check("B3 早到事件補算後完成 MQ03", qm.call("is_completed", "MQ03"))
	check("B4 任務鏈進入 MQ04", qm.call("is_active", "MQ04"))
	dm.disconnect("line_shown", auto_advance)
	world_b.queue_free(); await step(4)

	# C. 神社抵達與靈夢初見合併成 MQ04。
	qm.call("reset"); sf.call("reset")
	var c := _mk_world()
	var world_c: Node3D = c[0]
	world_c.add_child((load("res://maps/shrine/shrine_interactions.tscn") as PackedScene).instantiate())
	await step(6)
	qm.call("start_quest", "MQ04")
	var haiden: Node = world_c.find_child("拜殿拜訪", true, false)
	check("C1 MQ04 時拜殿可互動", not String(haiden.call("prompt_text")).is_empty())
	qm.call("report_event", "REACH", "hakurei_shrine_approach")
	check("C2 抵達後仍等待完整初見", qm.call("is_active", "MQ04"))
	var seen: Array = []
	var watch := func(s: String, _p: Texture2D, t: String, choices: PackedStringArray) -> void:
		seen.append("%s:%s" % [s, t])
		dm.call_deferred("advance", 0) if choices.size() > 0 else dm.call_deferred("advance")
	dm.connect("line_shown", watch)
	haiden.call("interact")
	await step(100)
	check("C3 靈夢初見確實演出", seen.size() > 0 and String(seen[0]).contains("你誰"))
	check("C4 一場對話完成 MQ04", qm.call("is_completed", "MQ04"))
	check("C5 不產生 MQ05／MQ06，直接進 MQ07", qm.call("is_active", "MQ07") and not (qm.get("_progress") as Dictionary).has("MQ05") and not (qm.get("_progress") as Dictionary).has("MQ06"))
	dm.disconnect("line_shown", watch)
	world_c.queue_free(); await step(4)

	# D. 重複早到與壞輸入不能污染流程。
	qm.call("reset"); sf.call("reset")
	qm.call("report_event", "REACH", "trail_leave_clearing")
	qm.call("report_event", "REACH", "trail_leave_clearing")
	qm.call("start_quest", "MQ00")
	check("D1 重複早到只補算一次", qm.call("is_completed", "MQ00") and qm.call("is_active", "MQ02"))
	qm.call("report_event", "DEFEAT", "trail_wolf", -3)
	check("D2 負 amount 不得推進", qm.call("is_active", "MQ02"))
	qm.call("report_event", 99, "nonsense")
	qm.call("report_event", "REACH", "no_such_target_anywhere")
	check("D3 未知事件不污染 pending", (qm.get("_pending") as Dictionary).is_empty())

	print("[QFLOW] failures=%d" % fails)
	quit(1 if fails > 0 else 0)

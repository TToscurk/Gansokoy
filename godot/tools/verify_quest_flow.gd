extends SceneTree
## 任務流程回歸測試 —— 專測「玩家不照劇本走」的情況。
##   Godot --headless --path godot --script tools/verify_quest_flow.gd
##
## 為什麼要有這一支：verify_story_slice.gd 是照著劇本順序走的happy path，
## 它抓不到亂序、對話中斷、回訪這三類打結。以下每一條都對應一個實際修掉的 bug：
##   A 亂序：先撞到後段事件（once_flag 燒掉）→ 任務推進到該目標時必須補算
##   B 中斷：對話進行中踏入 auto_trigger 區 → 獨白不得被吃掉
##   C 回訪：靈夢 repeat 分支必須照樣回報 TALK，否則 MQ05/MQ06 永久卡死
##   D 連鎖：report_event 內完成任務會動到 _progress，不得在迭代中爆掉

var fails := 0


func _init() -> void:
	_run.call_deferred()


func check(label: String, ok: bool) -> void:
	print("[QFLOW] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		fails += 1


func step(n: int = 6) -> void:
	for i in n:
		await process_frame


func _mk_world() -> Array:
	var world := Node3D.new()
	root.add_child(world)
	world.add_child((load("res://maps/trail/trail_interactions.tscn") as PackedScene).instantiate())
	var p := CharacterBody3D.new()
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.7
	cs.shape = cap
	p.add_child(cs)
	p.add_to_group("player")
	world.add_child(p)
	return [world, p]


func _run() -> void:
	var qm: Node = root.get_node("/root/QuestManager")
	var sf: Node = root.get_node("/root/StoryFlags")
	var dm: Node = root.get_node("/root/DialogueManager")

	# ── A. 亂序：受傷妖怪先被撞到，任務還停在 MQ02 ──
	qm.call("reset")
	sf.call("reset")
	var a := _mk_world()
	var world_a: Node3D = a[0]
	var pa: CharacterBody3D = a[1]
	await step(4)
	qm.call("start_quest", "MQ02")
	var auto_adv := func(_s: String, _p: Texture2D, _t: String, ch: PackedStringArray) -> void:
		if ch.size() > 0:
			dm.call_deferred("advance", 0)
		else:
			dm.call_deferred("advance")
	dm.connect("line_shown", auto_adv)
	# 座標：2026-09-15 r3 路線重排後的實測錨點（tools/probe_trail_anchors.gd）
	pa.global_position = Vector3(-1.54, 8.8, -90.74)
	await step(40)
	check("A1 受傷妖怪事件已演出（once_flag 立起）", sf.call("get_flag", "wounded_yokai_played"))
	check("A2 此時任務仍在 MQ02（事件早到，無人接收）", qm.call("is_active", "MQ02"))
	# ⚠ 2026-09-15：山犬戰鬥取消，MQ02 改成 REACH 獵食者痕跡（非戰鬥）。
	#   回合制戰鬥做好之後，這裡換回 DEFEAT / trail_wolf。
	qm.call("report_event", "REACH", "trail_predator_sign")
	await step(10)
	check("A3 看過痕跡進入 MQ03", qm.call("is_active", "MQ03"))
	qm.call("report_event", "REACH", "trail_fleeing_yokai")
	await step(10)
	check("A4 早到的受傷妖怪事件被補算 → MQ03 完成", qm.call("is_completed", "MQ03"))
	check("A5 任務鏈續行至 MQ04", qm.call("is_active", "MQ04"))
	dm.disconnect("line_shown", auto_adv)
	world_a.queue_free()
	await step(4)

	# ── B. 中斷：對話中踏入 auto_trigger 區，獨白不得被吃掉 ──
	qm.call("reset")
	sf.call("reset")
	var b := _mk_world()
	var world_b: Node3D = b[0]
	var pb: CharacterBody3D = b[1]
	await step(4)
	qm.call("start_quest", "MQ01")
	dm.call("start", "yoriichi_wake")
	pb.global_position = Vector3(-6.03, 7.4, -49.74)
	await step(12)
	check("B1 對話中不插隊（獨白尚未播）", not sf.call("get_flag", "sensed_presence_played"))
	while dm.call("is_active"):
		dm.call("advance")
		await step(2)
	await step(30)
	check("B2 前段對話結束後補播獨白", sf.call("get_flag", "sensed_presence_played"))
	while dm.call("is_active"):
		dm.call("advance")
		await step(2)
	await step(20)
	check("B3 補播的獨白照樣推進任務（MQ01→MQ02）", qm.call("is_active", "MQ02"))
	world_b.queue_free()
	await step(4)

	# ── C. 回訪：met_reimu 已立時走 repeat 分支，仍須能完成 MQ05/MQ06 ──
	qm.call("reset")
	sf.call("reset")
	sf.call("set_flag", "met_reimu", true)
	qm.call("start_quest", "MQ05")
	dm.call("start", "reimu_hakurei_shrine")
	var guard := 0
	while dm.call("is_active") and guard < 40:
		dm.call("advance")
		guard += 1
	check("C1 回訪對話能完成 MQ05", qm.call("is_completed", "MQ05"))
	check("C2 回訪對話能完成 MQ06", qm.call("is_completed", "MQ06"))
	check("C3 推進到 MQ07 人間之里", qm.call("is_active", "MQ07"))

	# ── D. 連鎖：一次事件連續完成多關不得出錯 ──
	qm.call("reset")
	sf.call("reset")
	qm.call("start_quest", "MQ00")
	qm.call("report_event", "REACH", "trail_leave_clearing")
	check("D1 MQ00 完成並連鎖開啟 MQ01", qm.call("is_completed", "MQ00") and qm.call("is_active", "MQ01"))
	qm.call("report_event", "REACH", "trail_presence")
	check("D2 MQ01 完成、旗標立起", qm.call("is_completed", "MQ01") and sf.call("get_flag", "sensed_presence"))
	check("D3 追蹤中的任務為 MQ02", qm.call("get_active_quest") == "MQ02")

	# ── E. 早到事件不得重複計算 ──
	qm.call("reset")
	sf.call("reset")
	qm.call("report_event", "REACH", "trail_leave_clearing")
	qm.call("report_event", "REACH", "trail_leave_clearing")
	qm.call("start_quest", "MQ00")
	check("E1 早到事件補算後 MQ00 完成", qm.call("is_completed", "MQ00"))
	check("E2 沒有把後續任務一起吃掉（MQ01 仍在進行）", qm.call("is_active", "MQ01"))

	# ── F. 輸入衛生：壞掉的事件不得污染進度或 _pending ──
	qm.call("reset")
	sf.call("reset")
	qm.call("start_quest", "MQ05")
	qm.call("report_event", "TALK", "reimu_hakurei_shrine", -3)
	check("F1 負的 amount 不得倒扣進度", qm.call("get_objective_progress", "MQ05") == 0)
	qm.call("report_event", "TALK", "reimu_hakurei_shrine", 0)
	check("F2 amount=0 不推進也不吞掉任務", qm.call("is_active", "MQ05"))
	qm.call("report_event", 99, "nonsense")
	qm.call("report_event", "REACH", "no_such_target_anywhere")
	check("F3 未知型別與無主 target 不留在 _pending", (qm.get("_pending") as Dictionary).is_empty())

	# ── G. quest_id 正規化：大小寫不得建出兩份進度 ──
	qm.call("reset")
	sf.call("reset")
	check("G1 start_quest(MQ00) 成功", qm.call("start_quest", "MQ00"))
	check("G2 start_quest(mq00) 必須被擋（同一個任務）", not qm.call("start_quest", "mq00"))
	check("G3 _progress 只有一筆", (qm.get("_progress") as Dictionary).size() == 1)

	# ── H. _tracked 不得卡在已完成的任務 ──
	# MQ01 的 next 是 MQ02；先讓 MQ02 完成，再完成 MQ01 → 鏈斷。
	qm.call("reset")
	sf.call("reset")
	qm.call("start_quest", "MQ01")
	qm.call("start_quest", "MQ02")
	qm.call("report_event", "REACH", "trail_predator_sign")   # MQ02 完成 → 連鎖 MQ03
	qm.call("report_event", "REACH", "trail_presence")        # MQ01 完成，next(MQ02) 已完成
	var tracked: String = qm.get("_tracked")
	check("H1 _tracked 必須指向 active 任務或空", tracked.is_empty() or qm.call("is_active", tracked))
	check("H2 get_active_quest 仍回傳 active 任務", qm.call("is_active", qm.call("get_active_quest")))

	# ── I. _pending 不得無限累積（回頭重踩／重複對話）──
	qm.call("reset")
	sf.call("reset")
	qm.call("start_quest", "MQ00")
	qm.call("report_event", "REACH", "trail_leave_clearing")   # MQ00 完成 → MQ01
	for i in 5:
		qm.call("report_event", "REACH", "trail_leave_clearing")   # 回頭重踩已完成的區
	check("I1 已用過的 REACH 事件不得留在 _pending", (qm.get("_pending") as Dictionary).is_empty())
	# 尚未走到的目標仍要存，但有上限（不得累積成 5）
	for i in 5:
		qm.call("report_event", "REACH", "hakurei_shrine_approach")
	var pend: Dictionary = qm.get("_pending")
	check("I2 未來用得到的事件仍存下來", pend.size() == 1)
	check("I3 存量受 required_amount 上限約束", int(pend.values()[0]) == 1)

	# ── J. 序章核心對話不得被提前燒掉（拜殿 require_quest）──
	qm.call("reset")
	sf.call("reset")
	var j := _mk_world()
	var world_j: Node3D = j[0]
	world_j.add_child((load("res://maps/shrine/shrine_interactions.tscn") as PackedScene).instantiate())
	await step(6)
	qm.call("start_quest", "MQ00")
	var haiden: Node = world_j.find_child("拜殿拜訪", true, false)
	check("J1 MQ05 之前拜殿不顯示提示", String(haiden.call("prompt_text")).is_empty())
	haiden.call("interact")
	await step(4)
	check("J2 MQ05 之前按 E 不起靈夢對話", not dm.call("is_active"))
	check("J3 met_reimu 未被提前立起", not sf.call("get_flag", "met_reimu"))
	# 推進到 MQ05：玩家此時就站在拜殿區內，前置解除必須讓提示補亮
	for t in ["trail_leave_clearing", "trail_presence", "trail_predator_sign",
			"trail_fleeing_yokai", "trail_wounded_yokai", "hakurei_shrine_approach"]:
		qm.call("report_event", "REACH", t)
	await step(6)
	check("J4 推進到 MQ05（不得被早到事件跳過）", qm.call("is_active", "MQ05"))
	check("J5 前置解除後拜殿提示補亮", not String(haiden.call("prompt_text")).is_empty())
	# ⚠ 監聽要在 interact() **之前**接上：start() 會同步發出第一句 line_shown，
	#   之後才連的話永遠收不到開頭那句，看不出走的是哪條分支。
	# ⚠ 用 Array 收，不要用 bool 旗標：GDScript 的 lambda 對區域變數是**傳值捕獲**，
	#   在 lambda 內寫 `saw_first = true` 改到的是副本，外面永遠讀到 false。
	var seen: Array = []
	var watch := func(s: String, _p: Texture2D, t: String, ch: PackedStringArray) -> void:
		seen.append("%s:%s" % [s, t])
		if ch.size() > 0:
			dm.call_deferred("advance", 0)
		else:
			dm.call_deferred("advance")
	dm.connect("line_shown", watch)
	haiden.call("interact")
	await step(90)
	check("J6 此時按 E 起得了靈夢對話", seen.size() > 0)
	check("J7 走的是 first_* 初見分支（序章核心對話還在）",
		seen.size() > 0 and String(seen[0]).contains("你誰"))
	check("J8 對話後推進到 MQ07", qm.call("is_active", "MQ07"))
	dm.disconnect("line_shown", watch)
	world_j.queue_free()
	await step(4)

	# ── K. 受傷妖怪已演過時，重踩仍要補回報（否則 MQ03 死鎖）──
	qm.call("reset")
	sf.call("reset")
	sf.call("set_flag", "wounded_yokai_played", true)
	var k := _mk_world()
	var world_k: Node3D = k[0]
	var pk: CharacterBody3D = k[1]
	await step(6)
	qm.call("start_quest", "MQ03")
	qm.call("report_event", "REACH", "trail_fleeing_yokai")
	await step(4)
	pk.global_position = Vector3(-1.54, 11.6, -90.74)
	await step(30)
	check("K1 演過的受傷妖怪區重踩仍完成 MQ03", qm.call("is_completed", "MQ03"))
	check("K2 任務鏈續行至 MQ04", qm.call("is_active", "MQ04"))
	world_k.queue_free()
	await step(4)

	print("[QFLOW] failures=%d" % fails)
	quit(1 if fails > 0 else 0)

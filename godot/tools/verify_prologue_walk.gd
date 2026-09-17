extends SceneTree
## 序章**走位**回歸測試 —— 專抓「測試靠傳送、真玩家靠走」才會露出來的錯。
##   Godot --headless --path godot --script tools/verify_prologue_walk.gd
##
## 為什麼要另開一支：verify_story_slice.gd 用 _teleport() 移動玩家。傳送會
##   1) 繞過 input_locked（測不出「對話中被打」）；
##   2) 讓玩家「停在」某個位置，於是「區域啟用時人還在不在裡面」永遠成立。
##   2026-09-16 使用者實玩回報的兩個問題，就是這兩點掩蓋掉的：
##     A 還在對話框，狼就攻擊了
##     B 三隻毛玉往右邊逃 → 走過去才有對話（該事件點已於 2026-09-17 刪除，B 段停用）
##
## 這支只走真的 main.tscn、只用走的（Input.action_*），不傳送玩家。

const TICK := 6

var fails := 0
var _main: Node
var _dm: Node
var _player: Node
var _t := 0


func _init() -> void:
	_run.call_deferred()


func check(label: String, ok: bool) -> void:
	print("[PWALK] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		fails += 1


func _wait(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame


func _line() -> String:
	if not _dm.call("is_active"):
		return ""
	var nodes: Dictionary = _dm.get("_nodes")
	var cur := String(_dm.get("_current"))
	return String((nodes[cur] as Dictionary).get("text", "")) if nodes.has(cur) else ""


func _accept() -> void:
	var ev := InputEventAction.new()
	ev.action = "ui_accept"
	ev.pressed = true
	Input.parse_input_event(ev)
	await _wait(2)
	ev.pressed = false
	Input.parse_input_event(ev)
	await _wait(2)


func _drain() -> void:
	var n := 0
	while _dm.call("is_active") and n < 120:
		await _accept()
		n += 1


func _nearest_enemy() -> Array:
	var best := -1.0
	var st := "-"
	for e in get_root().get_tree().get_nodes_in_group("enemies"):
		var d: float = (e as Node3D).global_position.distance_to((_player as Node3D).global_position)
		if best < 0.0 or d < best:
			best = d
			st = str(e.get("state"))
	return [best, st]


func _run() -> void:
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	await _wait(6)
	_dm = root.get_node("/root/DialogueManager")
	_player = _main.get_node("Player")
	var sf: Node = root.get_node("/root/StoryFlags")

	# ── 開場：淡入 → 醒來獨白（用等真實條件，不用固定幀數）──
	var w := 0
	while not _dm.call("is_active") and w < 900:
		await _wait(6)
		w += 6
	check("W1 開場醒來獨白起得來（第 %d 幀）" % w, _dm.call("is_active"))
	var p0: Vector3 = (_player as Node3D).global_position
	Input.action_press("move_back")
	await _wait(30)
	Input.action_release("move_back")
	check("W2 對話期間玩家被鎖住不能走（位移 %.3f m）" % (
		(_player as Node3D).global_position.distance_to(p0)),
		(_player as Node3D).global_position.distance_to(p0) < 0.05)
	await _drain()

	# ══ A. 走進山犬遭遇：狼不得在對話框還開著時貼上來 ══
	print("[PWALK] ── A：往北走進遭遇區 ──")
	var spawn_dist := -1.0
	var min_dist_in_dialogue := INF
	var attacked_in_dialogue := false
	var entered_z := 0.0
	Input.action_press("move_back")
	var f := 0
	while f < 900 and spawn_dist < 0.0:
		await _wait(TICK)
		f += TICK
		_t += TICK
		var e := _nearest_enemy()
		if int(e[0] * 100.0) >= 0:
			spawn_dist = float(e[0])
			entered_z = (_player as Node3D).global_position.z
	Input.action_release("move_back")
	check("A1 狼生成時距離玩家 ≥ 8 m（實測 %.2f m，修正前 1.25 m）" % spawn_dist,
		spawn_dist >= 8.0)
	print("[PWALK]   生成：玩家 z=%.2f，距離 %.2f m，對話框=「%s」" % [entered_z, spawn_dist, _line()])

	# 對話框開著期間：狼應該是 IDLE、不會靠近
	for i in 20:
		await _wait(TICK)
		_t += TICK
		var e := _nearest_enemy()
		if _dm.call("is_active"):
			min_dist_in_dialogue = minf(min_dist_in_dialogue, float(e[0]))
			if float(e[0]) < 2.5:
				attacked_in_dialogue = true

	check("A2 開場獨白播放中（狼還站著）", _dm.call("is_active"))
	check("A3 對話框開著時狼沒有靠近（最近 %.2f m）" % min_dist_in_dialogue,
		min_dist_in_dialogue >= 5.0)
	check("A4 **對話框還開著時狼不得貼身**（< 2.5 m）", not attacked_in_dialogue)

	# 讀完台詞 → 這時才該開打
	await _drain()
	var after_arm := INF
	for i in 20:
		await _wait(TICK)
		_t += TICK
		var e := _nearest_enemy()
		after_arm = minf(after_arm, float(e[0]))
	check("A5 讀完台詞後狼才開始接近（%.2f m < %.2f m）" % [after_arm, min_dist_in_dialogue],
		after_arm < min_dist_in_dialogue)

	# 收掉狼，免得干擾 B（走真的清場路徑，順便驗戰後流程不炸）
	var enc: Node = _main.find_child("山犬遭遇", true, false)
	if enc != null:
		enc.call("force_clear")
	await _wait(120)
	await _drain()
	print("[PWALK]   清場後場上敵人 = %d" % get_root().get_tree().get_nodes_in_group("enemies").size())

	# ═ B. （已移除）走過毛玉現場：果實獨白 ══
	#  2026-09-17 使用者裁定刪掉果實那一格（獸道事件點過密），
	#  z=-78 的逃跑毛玉群與果實獨白區都不存在了，本段無標的可驗。
	#  「區域啟用時玩家已在裡面要補觸發」這個機制本身仍在
	#  world_interaction._set_enabled，未來有新的延後啟用區時再補一支。

	print("[PWALK] ══ 走位回歸結束：%d 項失敗 ══" % fails)
	quit(1 if fails > 0 else 0)
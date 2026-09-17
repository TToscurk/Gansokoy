extends SceneTree
## 序章節奏探針 —— 用**真實玩法**（InputMap 動作走、對話逐句按掉）走一次獸道，
## 回答兩個症狀：
##   1 開場：還在對話框時山犬是不是已經撲上來了？
##   2 毛玉：是不是先看到三隻逃走，之後才有獨白？（該事件點已於 2026-09-17 刪除，本段停用）
##
##   Godot --path godot --script tools/probe_prologue_timing.gd
##   （不用 headless：要看得到畫面才知道方向對不對；輸出全部走 stdout）
##
## 為什麼不用 verify_story_slice.gd：那支是**傳送點到點**，跳過了「走過去」這段距離，
##   而使用者回報的兩個問題都正好發生在那段距離裡（遭遇區到醒來點 4.2 m、
##   毛玉察覺半徑 7–8.6 m 對比果實區半徑 3 m）。

const MAP := "trail"

var _main: Node
var _dm: Node
var _qm: Node
var _sf: Node
var _player: Node
var _f := 0
var _hit_log: Array = []


func _init() -> void:
	_run.call_deferred()


func _wait(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame
		_f += 1


func _dlg() -> String:
	if not _dm.call("is_active"):
		return "-"
	return String(_dm.get("_dialogue_id"))


func _drain() -> void:
	var n := 0
	while _dm.call("is_active") and n < 300:
		_dm.call("advance", 0)
		n += 1
		await _wait(2)


func _pos() -> Vector3:
	return (_player as Node3D).global_position


func _wolves() -> Array:
	return get_nodes_in_group("enemies")


func _on_hit(_data: Variant) -> void:
	_hit_log.append("幀 %d：受到攻擊（對話=%s，玩家 %s）" % [_f, _dlg(), str(_pos())])


func _run() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	await _wait(4)
	_dm = root.get_node("/root/DialogueManager")
	_qm = root.get_node("/root/QuestManager")
	_sf = root.get_node("/root/StoryFlags")

	_main.load_map(MAP, "")
	# load_map 會卡住主執行緒（實測約 9 秒），淡入在那之後才跑
	await _wait(30)
	_player = _main.get_node_or_null("Player")
	if _player == null:
		print("[PROBE] 找不到 Player")
		quit(1)
		return
	_player.connect("player_was_hit", _on_hit)

	print("[PROBE] ═ A. 開場 ═")
	print("[PROBE] 落點 %s  input_locked=%s" % [str(_pos()), str(_player.get("input_locked"))])

	# 等開場淡入結束、醒來獨白出生
	var w := 0
	while not _dm.call("is_active") and w < 2400:
		await _wait(10)
		w += 10
	print("[PROBE] 醒來獨白於第 %d 幀出生（id=%s）；此時敵人數=%d" % [_f, _dlg(), _wolves().size()])
	print("[PROBE] 獨白剛起時玩家 %s、input_locked=%s" % [str(_pos()), str(_player.get("input_locked"))])

	# 獨白期間：按著前進 30 幀，看鎖定到底有沒有作用
	Input.action_press("move_forward")
	await _wait(30)
	print("[PROBE] 獨白期間按前進 30 幀後：%s（位移 %.2f m）" % [
		str(_pos()), _pos().distance_to(Vector3(-13.78, 5.19, -26.82))])
	Input.action_release("move_forward")
	await _drain()
	print("[PROBE] 獨白結束於第 %d 幀；敵人數=%d" % [_f, _wolves().size()])

	# ── B. 走北：房間大小決定一切 ──
	print("[PROBE] ══ B. 走出空地（按 move_forward 真的走）══")
	Input.action_press("move_forward")
	await _wait(20)
	var dz := _pos().z - (-26.82)
	if dz > 0.0:
		Input.action_release("move_forward")
		Input.action_press("move_back")
		print("[PROBE] move_forward 往 +z（南）走，改按 move_back 往北")
	var enemies_seen := false
	var intro_seen := ""
	var guard := 0
	while guard < 900:
		guard += 1
		await _wait(5)
		var ws := _wolves()
		if ws.size() > 0 and not enemies_seen:
			enemies_seen = true
			var wolf: Node3D = ws[0]
			print("[PROBE] 山犬生成於第 %d ：玩家 %s、狼 %s、相距 %.2f m、對話=%s" % [
				_f, str(_pos()), str(wolf.global_position),
				_pos().distance_to(wolf.global_position), _dlg()])
		if _dlg() != "-" and _dlg() != intro_seen and intro_seen == "":
			intro_seen = _dlg()
			print("[PROBE] 遭遇獨白起於第 %d ：id=%s、此時狼距玩家 %.2f m" % [
				_f, intro_seen, _dist_to_first_wolf()])
		# 每 10 個取樣印一次狀態
		if guard % 2 == 0:
			print("[PROBE]   幀%4d 玩家z=%7.2f 對話=%-22s 狼=%d 狼距=%.2f 狼態=%s" % [
				_f, _pos().z, _dlg(), ws.size(),
				_dist_to_first_wolf(), _wolf_state()])
		if _hit_log.size() > 0:
			break
		if _pos().z < -44.0:
			break
	Input.action_release("move_forward")
	Input.action_release("move_back")
	print("[PROBE] 走北段結束於第 %d 幀，玩家 %s" % [_f, str(_pos())])
	for h in _hit_log:
		print("[PROBE] ⚠ %s" % h)
	if _hit_log.is_empty():
		print("[PROBE] 這一段沒有被打到")

	# ── C. 毛玉：察覺距離 vs 獨白區 ──
	print("[PROBE] ══ C. 毛玉 ══")
	for enc in get_nodes_in_group("combat_encounter"):
		if enc.has_method("force_clear"):
			enc.call("force_clear")
	await _wait(60)
	await _drain()
	# 2026-09-17：原本這一段往北走去探「毛玉逃跑 vs 果實獨白差幾公尺」，
	# 果實那一格已整條刪除（獸道事件點過密），無標的可探，本段停用。
	# 山犬那一題（症狀 1）在上面已經量完。

	print("[PROBE] 結束")
	quit(0)


func _dist_to_first_wolf() -> float:
	var ws := _wolves()
	if ws.is_empty():
		return -1.0
	return _pos().distance_to((ws[0] as Node3D).global_position)


func _wolf_state() -> String:
	var ws := _wolves()
	if ws.is_empty():
		return "-"
	return str(ws[0].get("_state"))


func _count_fleeing() -> int:
	var n := 0
	for k in get_nodes_in_group("kedama"):
		if int(k.get("mode")) == 1 and bool(k.get("_noticed")):
			n += 1
	return n
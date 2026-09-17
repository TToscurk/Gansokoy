extends SceneTree
## 序章開場流程探針 —— 兩件事的實證時間軸。
##   Godot --headless --path godot --script tools/probe_prologue_flow.gd
##
## 使用者回報（2026-09-16）：
##   1. 「還在對話框，狼就攻擊了」
##   2. 「到了毛玉那邊會先看到 3 個毛玉往右邊離開，然後再深入才有對話」
##
## 走**真的 main.tscn**（autoload 活著、真的淡入、真的 Area3D、真的敵人 AI），
## 逐幀記錄對話框狀態／玩家位置／輸入鎖／敵人狀態／毛玉逃了沒。
##
## ⚠ 兩個踩過的坑：
##   - 這張圖的 move_forward 是**往南**（+z），往北要用 move_back。第一版走反了。
##   - 傳送會繞過 input_locked；要驗「對話中被打」只能用走的。
##   - 傳送到別張互動區裡會被上一個獨白鎖住，動彈不得；每段開頭先清對話。

const TICK := 6

var _main: Node
var _dm: Node
var _player: Node
var _t := 0
var _wolf_near_strike := false
var _strike_line := ""


func _init() -> void:
	_run.call_deferred()


func _wait(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame


func _line() -> String:
	if not _dm.call("is_active"):
		return ""
	var nodes: Dictionary = _dm.get("_nodes")
	var cur := String(_dm.get("_current"))
	return String((nodes[cur] as Dictionary).get("text", "")) if nodes.has(cur) else "?"


func _sample(tag: String) -> void:
	var enemies := get_root().get_tree().get_nodes_in_group("enemies")
	var near := -1.0
	var st := "-"
	for e in enemies:
		var d: float = (e as Node3D).global_position.distance_to((_player as Node3D).global_position)
		if near < 0.0 or d < near:
			near = d
			st = str(e.get("state"))
	print("[PF] %-8s t=%4d dlg=%-5s「%s」 locked=%-5s z=%7.2f 敵=%d 最近=%5.2fm %s" % [
		tag, _t, str(_dm.call("is_active")), _line(), str(_player.get("input_locked")),
		(_player as Node3D).global_position.z, enemies.size(), near, st])


func _drain() -> void:
	var n := 0
	while _dm.call("is_active") and n < 80:
		await _press_accept()
		n += 1


func _press_accept() -> void:
	var ev := InputEventAction.new()
	ev.action = "ui_accept"
	ev.pressed = true
	Input.parse_input_event(ev)
	await _wait(2)
	ev.pressed = false
	Input.parse_input_event(ev)
	await _wait(2)


func _run() -> void:
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	await _wait(6)
	_dm = root.get_node("/root/DialogueManager")
	_player = _main.get_node("Player")

	var w := 0
	while not _dm.call("is_active") and w < 900:
		await _wait(6)
		w += 6
		_t += 6
	print("[PF] ── 醒來獨白第 %d 幀起來 ──" % _t)
	_sample("獨白中")
	var p0: Vector3 = (_player as Node3D).global_position
	Input.action_press("move_back")
	await _wait(30)
	Input.action_release("move_back")
	print("[PF] 獨白期間按前進 30 位移 = %.3f m（0 = 被鎖住）" % (
		(_player as Node3D).global_position.distance_to(p0)))
	await _drain()
	_t += 10
	print("[PF] ─ 獨白結束 ──")
	_sample("獨白後")

	# ── A. 往北走進「山犬遭遇」（z -49.03..-31.03）──
	print("[PF] ─ A. 往北走（遭遇區南緣 z=-31.03）──")
	var mq: Node = root.get_node("/root/QuestManager")
	var first_hit_dlg := "（還沒進攻擊距離）"
	var entered_at := 0.0
	Input.action_press("move_back")
	var f := 0
	while f < 900:
		await _wait(TICK)
		f += TICK
		_t += TICK
		var enemies := get_root().get_tree().get_nodes_in_group("enemies")
		if enemies.size() > 0 and entered_at == 0.0:
			entered_at = (_player as Node3D).global_position.z
			print("[PF] 狼生成：玩家 z=%.2f，狼距離 %.2f m，對話框=%s「%s」" % [
				entered_at,
				(enemies[0] as Node3D).global_position.distance_to((_player as Node3D).global_position),
				str(_dm.call("is_active")), _line()])
		for e in enemies:
			var d: float = (e as Node3D).global_position.distance_to((_player as Node3D).global_position)
			if d < 2.5 and not _wolf_near_strike:
				_wolf_near_strike = true
				_strike_line = _line()
				print("[PF] ★狼進入 2.5 m：玩家 z=%.2f，對話框=%s「%s」，locked=%s" % [
					(_player as Node3D).global_position.z, str(_dm.call("is_active")),
					_strike_line, str(_player.get("input_locked"))])
		if f % 60 == 0:
			_sample("A走")
	Input.action_release("move_back")
	print("[PF] A 結論：狼貼身時對話框開著 = %s（當時台詞「%s」）" % [str(_wolf_near_strike), _strike_line])
	print("[PF] A 任務：MQ00=%s MQ01=%s MQ02=%s" % [
		str(mq.call("is_completed", "MQ00")), str(mq.call("is_active", "MQ01")),
		str(mq.call("is_active", "MQ02"))])

	# ── B.（已移除）毛玉：看到逃跑 vs 聽到獨白 ──
	# 2026-09-17：逃跑妖怪群／果實獨白（z=-78）已整條刪除，無標的可探。

	print("[PF] ══ 探針結束 ══")
	quit(0)
extends SceneTree
## 實機存讀檔驗證 —— 真的載 main.tscn、真的存檔、真的重開讀回來。
## 這一支跟 verify_save_load.gd 的差別：那支只測 API，這支測 main.gd 的接線
## （load_requested → load_map → 擺玩家的順序、開場流程不得蓋掉存檔位置）。
##
## 兩階段，靠 user:// 的暫存檔傳遞期望值：
##   --  --savephase=write   載 main、走到某處、存檔、記下期望值
##   --  --savephase=verify  重新載 main + --continue、比對實際落點

const EXPECT := "user://_savetest_expect.json"


func _init() -> void:
	_run.call_deferred()


func step(n: int = 6) -> void:
	for i in n:
		await process_frame


func _phase() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--savephase="):
			return a.substr(12)
	return ""


func _run() -> void:
	var phase := _phase()
	# ⚠ --script 會取代主場景，main.tscn 不會自己載進來。手動實例化，
	#   這樣 main.gd 的 _ready（含 --continue 讀檔流程）才會真的跑。
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	# 等 main 的 _ready 跑完、圖載好、玩家落地
	await step(150)
	var qm: Node = root.get_node("/root/QuestManager")
	var sf: Node = root.get_node("/root/StoryFlags")
	var sm: Node = root.get_node("/root/SaveManager")
	var player: Node3D = main.get("player")

	if phase == "write":
		# 推進劇情到一個有內容的狀態，並把玩家挪到一個明確的座標。
		# ⚠ 挪位置**之前**先把劇情設好：屋台附近有 auto_trigger 區，
		#   先挪再設的話會被獨白推進任務，期望值就跟存檔內容不一致。
		var here := Vector3(3.80, 7.30, -71.60)     # 夜雀屋台附近，實測錨點
		player.global_position = here
		player.set("velocity", Vector3.ZERO)
		if player.has_method("snap_yaw"):
			player.call("snap_yaw", 2.0)
		await step(30)
		# 世界事件演完之後才設任務狀態，確保存下去的就是我們要驗的
		qm.call("reset")
		sf.call("reset")
		qm.call("start_quest", "MQ03")
		sf.call("set_flag", "woke_in_trail", true)
		sf.call("set_flag", "spared_wounded_yokai", true)
		await step(4)
		var yaw: float = player.call("current_yaw") if player.has_method("current_yaw") \
			else player.rotation.y
		var ok: bool = sm.call("save_game", 0, main.get("current_id"),
			player.global_position, yaw)
		print("[LIVE] write: saved=%s map=%s pos=%v yaw=%.3f quest=%s" % [
			ok, main.get("current_id"), player.global_position, yaw,
			qm.call("get_active_quest")])
		var f := FileAccess.open(EXPECT, FileAccess.WRITE)
		f.store_string(JSON.stringify({
			"map": main.get("current_id"),
			"x": player.global_position.x, "y": player.global_position.y,
			"z": player.global_position.z,
			"yaw": yaw,
			"quest": qm.call("get_active_quest"),
			"objective": (qm.call("get_current_objective", qm.call("get_active_quest")) as Object).get("target_id"),
			"flags": sf.call("serialize").keys(),
		}))
		f.close()
		quit(0)
		return

	# ── verify：main 已經帶 --continue 跑過讀檔流程 ──
	var exp: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(EXPECT))
	var fails := 0
	var want_pos := Vector3(float(exp.x), float(exp.y), float(exp.z))
	var got_pos: Vector3 = player.global_position
	var drift := Vector2(got_pos.x - want_pos.x, got_pos.z - want_pos.z).length()
	var got_yaw: float = player.call("current_yaw") if player.has_method("current_yaw") \
		else player.rotation.y
	var yaw_err := absf(wrapf(got_yaw - float(exp.get("yaw", 0.0)), -PI, PI))

	var checks := [
		["L1 地圖還原", String(main.get("current_id")) == String(exp.map),
			"%s vs %s" % [main.get("current_id"), exp.map]],
		["L2 水平落點誤差 < 1 m（不得被出生點／傳送點蓋掉）", drift < 1.0,
			"drift=%.3f m  got=%v want=%v" % [drift, got_pos, want_pos]],
		["L3 沒掉到地底（y 誤差 < 3 m）", absf(got_pos.y - want_pos.y) < 3.0,
			"y got=%.2f want=%.2f" % [got_pos.y, want_pos.y]],
		["L4 任務還原", String(qm.call("get_active_quest")) == String(exp.quest),
			"%s vs %s" % [qm.call("get_active_quest"), exp.quest]],
		["L5 目標還原（不是從第一目標重來）",
			(qm.call("get_current_objective", qm.call("get_active_quest")) as Object).get("target_id") == String(exp.objective),
			str((qm.call("get_current_objective", qm.call("get_active_quest")) as Object).get("target_id"))],
		["L6 旗標還原", (sf.call("serialize") as Dictionary).size() == (exp.flags as Array).size(),
			"%d vs %d" % [(sf.call("serialize") as Dictionary).size(), (exp.flags as Array).size()]],
		["L6b 朝向還原（誤差 < 0.1 rad）", yaw_err < 0.1,
			"got=%.3f want=%.3f err=%.3f rad" % [got_yaw, float(exp.get("yaw", 0.0)), yaw_err]],
		["L7 讀檔後玩家沒被鎖住（開場獨白不得復播）", not bool(player.get("input_locked")),
			"input_locked=%s" % player.get("input_locked")],
		["L8 開場黑幕沒有復播", main.get_node_or_null("OpeningFade") == null, ""],
		["L9 醒來獨白沒有復播（woke_in_trail 仍為真且無對話）",
			sf.call("get_flag", "woke_in_trail") and not root.get_node("/root/DialogueManager").call("is_active"), ""],
		# ⚠ 這一條在找一個真的很容易犯的錯：若 StoryFlags.deserialize 發 flag_changed，
		#   存檔裡的 spared_wounded_yokai 會讓 WoundedYokaiEvent 誤以為玩家剛剛
		#   選了「靠近」→ 重播毛玉逃走的演出、並重複回報任務事件。
		#   （實測確認：手動 set_flag 該旗標就會讓 MQ03 在玩家 20 m 外自己完成。）
		["L10 存檔裡的選擇旗標不得重播演出（毛玉沒有憑空逃走）",
			sf.call("get_flag", "spared_wounded_yokai") \
			and _wounded_intact(main), _wounded_state(main)],
	]
	for c in checks:
		print("[LIVE] %s %s%s" % ["PASS" if c[1] else "FAIL", c[0],
			"" if String(c[2]).is_empty() else "   (%s)" % c[2]])
		if not c[1]:
			fails += 1
	print("[LIVE] failures=%d" % fails)
	DirAccess.remove_absolute(EXPECT)
	quit(1 if fails > 0 else 0)


## 受傷妖怪那一幕是否**還沒被演過**（_started 為 false）。
## 讀檔時若旗標重放，這裡會變 true —— 等於毛玉在玩家沒到場的情況下逃走了。
func _wounded_intact(main: Node) -> bool:
	var we := main.find_child("受傷妖怪", true, false)
	if we == null:
		return true          # 這張圖沒有這個節點就不算失敗
	return not bool(we.get("_started"))


func _wounded_state(main: Node) -> String:
	var we := main.find_child("受傷妖怪", true, false)
	if we == null:
		return "(圖上沒有受傷妖怪節點)"
	return "_started=%s" % we.get("_started")

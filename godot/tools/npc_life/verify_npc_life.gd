extends SceneTree
## NPC Living World 驗收（docs/NPC自主生活系統.md §十二 測試 A–G）
## godot --headless --path godot -s res://tools/npc_life/verify_npc_life.gd -- --map=village_v2 [--cases=ACBDEF|G] [--ts=4] [--long=300]
##   走正式 main.tscn（玩家、碰撞、對話系統都在），用 director 的事件紀錄＋實際位置／朝向／動作名判定。
##   A 載入後自動開始生活事件（錯開）  B 主動社交（雙方到位、面對、輪流說完）  C 環境互動（走到站位、面向、跪地動作、物件消失、離開）
##   D 事件鏈（甲的事件結果改變乙的目的地）  E 玩家介入（暫停／續做、打斷交談、劇情凍結、威脅）
##   F 全 HERO 三類事件覆蓋（資料＋實跑）  G 長時間加速運作不卡死
## 任何 FAIL → exit 1。

var main: Node
var dir: Node
var player: Node3D
var cases := "ACBDEF"
var ts_run := 4.0
var long_secs := 300.0
var results: Array = []
var log_all: Array = []
var t0 := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--cases="): cases = a.substr(8)
		if a.begins_with("--ts="): ts_run = float(a.substr(5))
		if a.begins_with("--long="): long_secs = float(a.substr(7))
	t0 = Time.get_ticks_msec()
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	_run.call_deferred()


func _run() -> void:
	# 等 director 就緒
	var ok := await _wait(func(): return _find_dir() != null and bool(dir.get("_ready_done")), 90.0)
	if not ok:
		_check("SETUP", "director 就緒", false, "90 s 內找不到 NpcLife director")
		_finish()
		return
	player = root.get_tree().get_first_node_in_group("player") as Node3D
	dir.connect("event_state", func(h, e, s, i): log_all.append([float(dir.get("clock")), Time.get_ticks_msec(), h, e, s, i]))
	print("[VERIFY] 載入 %.1f s，heroes=%s" % [(Time.get_ticks_msec() - t0) / 1000.0, dir.get("heroes").keys()])
	_disable_dialogue_input()
	if cases.contains("A"): await case_a()
	dir.set("time_scale", ts_run)
	if cases.contains("C"): await case_c()
	if cases.contains("B"): await case_b()
	if cases.contains("D"): await case_d()
	if cases.contains("E"): await case_e()
	if cases.contains("F"): await case_f()
	if cases.contains("G"): await case_g()
	_finish()


# ─────────────────────────── A：載入 ───────────────────────────

func case_a() -> void:
	dir.set("time_scale", 1.0)
	_park_player(Vector3(224, 0.3, 160))
	await _sleep(22.0)
	var started := {}
	var traveling := {}
	for r in log_all:
		if r[4] == "Reserved" and not started.has(r[2]): started[r[2]] = r[1]
		if r[4] in ["Traveling", "Interacting"]: traveling[r[2]] = true
	var times: Array = started.values()
	times.sort()
	var spread: float = (times[-1] - times[0]) / 1000.0 if times.size() > 1 else 0.0
	_check("A", "載入 22 s 內 ≥4 名 HERO 自行開始事件", started.size() >= 4, "開始=%s" % [started.keys()])
	_check("A", "≥3 名已在移動或互動（不是站在出生點）", traveling.size() >= 3, "移動/互動=%s" % [traveling.keys()])
	_check("A", "啟動錯開（首末間隔 ≥ 1.5 s）", spread >= 1.5, "間隔 %.2f s" % spread)
	var dup := false
	for h in dir.get("heroes"):
		var a: Node3D = dir.get("heroes")[h]
		if a.global_position.distance_to(player.global_position) < 2.0:
			dup = true
	_check("A", "沒有 HERO 生成在玩家身上", not dup, "")


# ─────────────────────────── C：環境互動 ───────────────────────────

func case_c() -> void:
	var m: Node3D = _hero("marisa")
	var obj := "mushroom_1"
	var od: Dictionary = dir.get("objects")[obj]
	_park_player(_v3(od.def.stand) + Vector3(9, 0, -6))
	var forced: bool = await _force("marisa", "marisa_mushroom", "", obj)
	_check("C", "魔理沙排入採蘑菇", forced, "")
	if not forced:
		return
	var mark := _last_reserved("marisa")
	var seen_clips := {}
	var inter_pos := Vector3.INF
	var inter_yaw_err := INF
	var done := false
	var end_c := Time.get_ticks_msec() + 150000
	while Time.get_ticks_msec() < end_c:
		await physics_frame
		seen_clips[String(m.get_node("NPC").get("player").current_animation)] = true
		for k in range(mark, log_all.size()):
			var r: Array = log_all[k]
			if r[2] == "marisa" and r[3] == "marisa_mushroom" and r[4] == "Interacting" and inter_pos == Vector3.INF:
				inter_pos = m.global_position
				var f := _v3(od.def.face) - m.global_position
				inter_yaw_err = absf(angle_difference(m.rotation.y, atan2(f.x, f.z)))
			if r[2] == "marisa" and r[3] == "marisa_mushroom" and r[4] in ["Completed", "Failed", "Interrupted"]:
				done = true
				_check("C", "事件結束狀態＝Completed", r[4] == "Completed", "%s %s" % [r[4], r[5]])
		if done:
			break
	var stand := _v3(od.def.stand)
	_check("C", "走到互動站位（≤0.35 m）", inter_pos != Vector3.INF and _xz(inter_pos).distance_to(_xz(stand)) <= 0.35, "站位誤差 %.3f m" % (_xz(inter_pos).distance_to(_xz(stand)) if inter_pos != Vector3.INF else -1.0))
	_check("C", "面向蘑菇（≤0.3 rad）", inter_yaw_err <= 0.3, "%.3f rad" % inter_yaw_err)
	_check("C", "播放跪地採集動作（kneel_down→kneel_idle→kneel_up）", seen_clips.has("kneel_down") and seen_clips.has("kneel_idle") and seen_clips.has("kneel_up"), "看到 %s" % [seen_clips.keys()])
	var node: Node3D = od.node
	_check("C", "蘑菇被採走（節點隱藏）", node != null and not node.visible, "")
	var p0 := m.global_position
	await _wait(func(): return _xz(m.global_position).distance_to(_xz(p0)) > 1.0, 40.0)
	_check("C", "完成後起身離開（移動 > 1 m）", _xz(m.global_position).distance_to(_xz(p0)) > 1.0, "移動 %.2f m" % _xz(m.global_position).distance_to(_xz(p0)))


# ─────────────────────────── B：主動社交 ───────────────────────────

func case_b() -> void:
	var m: Node3D = _hero("marisa")
	var k: Node3D = _hero("keine")
	_park_player((m.global_position + k.global_position) * 0.5 + Vector3(14, 0, 0))
	var ok: bool = await _force("marisa", "marisa_chat", "keine")
	var mark := _last_reserved("marisa")
	_check("B", "魔理沙主動去找慧音（排入）", ok, "")
	if not ok:
		return
	var talk_dist := -1.0
	var face_a := INF
	var face_b := INF
	var max_d := 0.0
	var end_state := ""
	var talking := false
	var end_b := Time.get_ticks_msec() + 220000
	while Time.get_ticks_msec() < end_b and end_state == "":
		await physics_frame
		if not talking:
			for i in range(mark, log_all.size()):
				var r: Array = log_all[i]
				if r[4] == "SESSION_TALK" and r[2] == "marisa":
					talking = true
					talk_dist = float(r[5].get("dist", -1))
		if talking:
			max_d = maxf(max_d, _xz(m.global_position).distance_to(_xz(k.global_position)))
			if face_a == INF and _count_log(mark, "", "SAY") >= 1:
				face_a = _face_err(m, k)
				face_b = _face_err(k, m)
		for i in range(mark, log_all.size()):
			var r: Array = log_all[i]
			if r[2] == "marisa" and r[4] in ["SESSION_COMPLETED", "SESSION_INTERRUPTED", "SESSION_FAILED"] and String(r[5].get("with", "")) == "keine":
				end_state = r[4]
	var says: Array = []
	for i in range(mark, log_all.size()):
		var r: Array = log_all[i]
		if r[4] == "SAY" and r[2] in ["marisa", "keine"]:
			says.append(r)
	_check("B", "雙方到位才開始（距離 ≤ 1.8 m）", talk_dist > 0.0 and talk_dist <= 1.8, "開講距離 %.2f m" % talk_dist)
	_check("B", "雙方互相面對（≤0.5 rad）", face_a <= 0.5 and face_b <= 0.5, "魔理沙 %.2f／慧音 %.2f rad" % [face_a, face_b])
	var spk := {}
	for r in says: spk[r[2]] = true
	_check("B", "雙方都有說話（輪流）", spk.size() == 2 and says.size() >= 3, "台詞 %d 句，說話者 %s" % [says.size(), spk.keys()])
	_check("B", "交談全程距離 ≤ 2.2 m（沒有人中途走掉）", max_d <= 2.2, "最大 %.2f m" % max_d)
	_check("B", "交談正常結束", end_state == "SESSION_COMPLETED", end_state)
	await _sleep(8.0)
	# 這一對的交談已不在；兩人之後各自排了新事件（別人再來找她們聊天是正常生活，不算卡住）
	var still := false
	for s in dir.get("sessions"):
		if (s.a == "marisa" and s.b == "keine") or (s.a == "keine" and s.b == "marisa"):
			still = true
	var moved_m := false
	var moved_k := false
	for i in range(mark, log_all.size()):
		var r: Array = log_all[i]
		if r[4] == "Reserved" and r[2] == "marisa" and i > _last_session_end(mark): moved_m = true
		if r[4] == "Reserved" and r[2] == "keine" and i > _last_session_end(mark): moved_k = true
		if r[4] == "RESUMED" and r[2] == "keine": moved_k = true
	_check("B", "結束後兩人回到各自生活（不卡在 session）", not still and moved_m and moved_k, "%s / %s" % [m.call("life_state"), k.call("life_state")])


# ─────────────────────────── D：事件鏈 ───────────────────────────

func case_d() -> void:
	var k: Node3D = _hero("keine")
	var m: Node3D = _hero("marisa")
	# 1) 世界出現異狀（毛玉）。測試用生活時鐘加速，但走路是實速——TTL 拉長，免得慧音跨村走到一半事件就過期
	dir.call("_spawn_kedama", {"fact": "anomaly_south_forest", "ttl": 4000})
	dir.call("set_world", "anomaly_south_forest", 4000.0, "verify")   # 若世界觸發已先生出毛玉，也把 TTL 拉長
	_check("D", "村口林邊出現毛玉（世界事實 anomaly_south_forest）", bool(dir.call("has_world", "anomaly_south_forest")), "")
	_park_player(Vector3(226, 0.3, 175))
	# 魔理沙若正走在遠途約談（社交事件不可打斷）就先讓她改做附近的事，否則後面「指定通報魔理沙」排不進去
	var mst := String(m.call("life_state"))
	if mst == "session" or mst == "plan:marisa_chat":
		dir.call("force_event", "marisa", "marisa_herb")
	# 2) 慧音巡視時親眼看到（知覺），不是直接灌資料
	var mark := log_all.size()
	await _force("keine", "keine_patrol")
	var learned: bool = await _wait(func(): return bool(dir.call("hero_knows", "keine", "anomaly_south_forest")), 160.0)
	_check("D", "慧音巡視途中看見毛玉（知覺學到）", learned, "")
	if not learned:
		return
	# 3) 慧音放下巡視、去通報魔理沙（為了可重現指定對象；自然運作時依關係挑 marisa/reimu/akyuu）
	var m_goal_before := _plan_goal(m)
	var m_event_before := String(m.call("current_event"))
	# 慧音學到後會自己（priority 7）挑人通報；若自然選了魔理沙就直接用，否則指定魔理沙（可重現）
	var natural: bool = await _wait(func(): return _reserved_with("keine", "keine_report_anomaly", "marisa"), 3.0)
	var ok := natural
	if not natural:
		ok = await _force("keine", "keine_report_anomaly", "marisa")
	_check("D", "慧音的反應事件：去通報魔理沙", ok, "自然選擇" if natural else "指定對象")
	var told: bool = await _wait(func(): return bool(dir.call("hero_knows", "marisa", "anomaly_south_forest")), 200.0)
	_check("D", "交談結果：魔理沙得知森林異狀（傳聞傳遞）", told, "")
	if not told:
		return
	# 4) 魔理沙改變計畫，前往森林調查
	var went: bool = await _wait(func(): return String(m.call("current_event")) == "marisa_investigate", 30.0)
	var goal_after := _plan_goal(m)
	var spot := _v3(dir.get("objects")["anomaly_spot"].def.stand)
	_check("D", "魔理沙下一個事件改為調查（marisa_investigate）", went, "之前=%s 之後=%s" % [m_event_before, m.call("current_event")])
	_check("D", "魔理沙目的地改變（→ 林邊異狀點）", goal_after != Vector3.INF and _xz(goal_after).distance_to(_xz(spot)) < 0.5 and (m_goal_before == Vector3.INF or _xz(m_goal_before).distance_to(_xz(spot)) > 2.0), "之前 %s → 之後 %s" % [_xz(m_goal_before) if m_goal_before != Vector3.INF else "無", _xz(goal_after)])
	# 5) 抵達調查、毛玉逃走、異狀解除
	var resolved: bool = await _wait(func(): return bool(dir.call("has_world", "anomaly_resolved")), 220.0)
	_check("D", "魔理沙抵達調查 → 毛玉逃走 → anomaly_resolved", resolved, "魔理沙位置 %s" % _xz(m.global_position))
	var at_spot := false
	for i in range(mark, log_all.size()):
		var r: Array = log_all[i]
		if r[2] == "marisa" and r[3] == "marisa_investigate" and r[4] == "Interacting":
			at_spot = _xz(spot).distance_to(r[5].pos) < 0.5
	_check("D", "調查時確實站在林邊異狀點", at_spot, "")
	_check("D", "異狀解除後世界事實清除（恢復日常）", not bool(dir.call("has_world", "anomaly_south_forest")), "")


# ─────────────────────────── E：玩家介入 ───────────────────────────

func case_e() -> void:
	# E1 走路中被搭話 → 暫停、轉向玩家 → 玩家離開 → 續做完成
	var r: Node3D = _hero("reimu")
	var objs: Dictionary = dir.get("objects")
	var far_obj := "stall_ame" if r.global_position.distance_to(_v3(objs["stall_ame"].def.stand)) > r.global_position.distance_to(_v3(objs["hokora"].def.stand)) else "hokora"
	var far_ev := "reimu_market" if far_obj == "stall_ame" else "reimu_hokora"
	_park_player(r.global_position + Vector3(20, 0, 0))
	await _force("reimu", far_ev, "", far_obj)
	var mark_e1 := _last_reserved("reimu")
	await _wait(func(): return String(r.get("_step").get("op", "")) == "goto" and r.get("_path").size() > 1, 30.0)
	await _sleep(2.0)
	var ahead := r.global_position + Vector3(sin(r.rotation.y), 0, cos(r.rotation.y)) * 2.2
	var mark := log_all.size()
	_park_player(ahead)
	var paused: bool = await _wait(func(): return _has_log(mark, "reimu", "PAUSED"), 4.0)
	await _sleep(3.0)
	_check("E", "E1 靈夢走路中被玩家攔下 → 暫停事件", paused, "事件 %s" % far_ev)
	_check("E", "E1 轉向玩家（≤0.45 rad）", _face_err(r, player) <= 0.45, "%.2f rad" % _face_err(r, player))
	var bub := r.get("_bubble") as Label3D
	var pc: Dictionary = dir.get("defs")["reimu"].player_chat
	var ok_line := false
	for k in pc:
		for ln in pc[k]:
			if bub.text.find(String(ln)) >= 0: ok_line = true
	_check("E", "E1 頭頂有對玩家的回應台詞", bub.visible and ok_line, bub.text)
	_park_player(r.global_position + Vector3(25, 0, 10))
	var resumed: bool = await _wait(func(): return _has_log(mark, "reimu", "RESUMED"), 5.0)
	_check("E", "E1 玩家離開 → 續做原事件", resumed, "")
	var fin: bool = await _wait(func(): return _has_log(mark_e1, "reimu", "Completed", far_ev) or _has_log(mark_e1, "reimu", "Failed", far_ev) or _has_log(mark_e1, "reimu", "Interrupted", far_ev), 200.0)
	_check("E", "E1 原事件仍走完（Completed，沒有卡死）", fin and _has_log(mark_e1, "reimu", "Completed", far_ev), "")
	# E2 雙人交談中玩家插入 → 暫停 → 停留 6 s 散場 → 兩人都恢復（挑當下能聊的一對）
	var pairs := [["marisa", "keine", "marisa_chat"], ["marisa", "kosuzu", "marisa_chat"], ["reimu", "kosuzu", "reimu_chat"], ["keine", "kosuzu", "keine_chat"], ["reimu", "marisa", "reimu_chat"]]
	var m: Node3D
	var k: Node3D
	var talking := false
	var ia := ""
	# 當下每一對都可能在忙（世界觸發的反應事件、別的交談）：最多重試 90 s
	var t_try := Time.get_ticks_msec()
	while not talking and Time.get_ticks_msec() - t_try < 90000:
		for pr in pairs:
			m = _hero(pr[0])
			k = _hero(pr[1])
			_park_player(m.global_position + Vector3(15, 0, 0))
			if not bool(dir.call("force_event", pr[0], pr[2], pr[1])):
				continue
			ia = pr[0]
			mark = _last_reserved(pr[0])
			talking = await _wait(func(): return _has_log(mark, ia, "SESSION_TALK"), 150.0)
			if talking:
				break
		if not talking:
			await _sleep(3.0)
	_check("E", "E2 交談開始", talking, "%s↔%s" % [m.name, k.name])
	if talking:
		await _sleep(2.5)
		_park_player((m.global_position + k.global_position) * 0.5 + (k.global_position - m.global_position).normalized().rotated(Vector3.UP, PI / 2) * 1.6)
		await _sleep(3.0)
		var n_say := _count_log(mark, "", "SAY")
		await _sleep(2.0)
		_check("E", "E2 玩家靠近 → 交談暫停（2 s 內沒有新台詞）", _count_log(mark, "", "SAY") == n_say, "")
		var broke: bool = await _wait(func(): return _has_log(mark, ia, "SESSION_INTERRUPTED"), 10.0)
		_check("E", "E2 玩家停留 → 交談中止（Interrupted）並釋放雙方", broke and dir.call("session_of", m.get("hero_id")).is_empty() and dir.call("session_of", k.get("hero_id")).is_empty(), "")
		_park_player(m.global_position + Vector3(30, 0, 0))
		var both: bool = await _wait(func(): return String(m.call("life_state")).begins_with("plan:") and String(k.call("life_state")).begins_with("plan:"), 45.0)
		_check("E", "E2 兩人之後各自恢復生活事件", both, "%s / %s" % [m.call("life_state"), k.call("life_state")])
	# E3 劇情對話進行中：附近 HERO 凍結；對話結束後恢復
	var z: Node3D = _hero("kosuzu")
	_park_player(z.global_position + Vector3(6, 0, 0))
	await _force("kosuzu", "kosuzu_arrange")
	await _sleep(1.0)
	var dm := root.get_node("/root/DialogueManager")
	var started: bool = dm.call("start", "kosuzu_suzunaan")
	var p0 := z.global_position
	await _sleep(3.0)
	_check("E", "E3 劇情對話中附近 HERO 凍結（3 s 位移 < 0.05 m）", started and z.global_position.distance_to(p0) < 0.05 and bool(z.get("_frozen")), "started=%s 位移 %.3f" % [started, z.global_position.distance_to(p0)])
	for i in 60:
		if not bool(dm.call("is_active")): break
		dm.call("advance", 0)
		await _sleep(0.2)
	await _sleep(1.0)
	_check("E", "E3 對話結束後解除凍結", not bool(z.get("_frozen")), "")
	# E4 敵人靠近：中止事件、面向威脅；威脅消失後恢復
	_park_player(z.global_position + Vector3(30, 0, 0))
	mark = log_all.size()
	var foe := Node3D.new()
	foe.name = "VerifyThreat"
	foe.add_to_group("enemies")
	main.add_child(foe)
	foe.global_position = z.global_position + Vector3(6, 0, 0)
	var alarm: bool = await _wait(func(): return _has_log(mark, "kosuzu", "ALARM"), 3.0)
	_check("E", "E4 敵人靠近 → HERO 中止事件並警戒", alarm, "")
	foe.queue_free()
	var back: bool = await _wait(func(): return _has_log(mark, "kosuzu", "ALARM_CLEAR"), 10.0)
	var replan: bool = await _wait(func(): return String(z.call("life_state")).begins_with("plan:"), 25.0)
	_check("E", "E4 威脅消失 → 恢復生活事件", back and replan, String(z.call("life_state")))


# ─────────────────────────── F：全 HERO 覆蓋 ───────────────────────────

func case_f() -> void:
	var defs: Dictionary = dir.get("defs")
	for h in defs:
		var cat := {"personal": [], "social_env": [], "reaction": []}
		for ev in defs[h].get("events", []):
			var react: bool = ev.has("need_know") or ev.has("need_world")
			if react:
				cat.reaction.append(ev.id)
			elif String(ev.kind) == "social" or (String(ev.kind) == "object"):
				cat.social_env.append(ev.id)
			if not react and String(ev.kind) in ["object", "place", "route", "home"]:
				cat.personal.append(ev.id)
		_check("F", "%s 資料：三類事件齊備" % h, cat.personal.size() > 0 and cat.social_env.size() > 0 and cat.reaction.size() > 0, "個人 %s｜社交/環境 %s｜反應 %s" % [cat.personal, cat.social_env, cat.reaction])
	# 實跑：本次 run 裡每名 HERO 真正進入互動／交談的事件
	var ran := _ran_events()
	for h in defs:
		var need := 3 - (ran.get(h, {}) as Dictionary).size()
		if need > 0:
			for ev in defs[h].get("events", []):
				if need <= 0: break
				if (ran.get(h, {}) as Dictionary).has(ev.id) or String(ev.kind) == "home" and defs[h].get("events").size() > 4:
					continue
				_prepare_conditions(h, ev)
				var mark := log_all.size()
				_park_player(_hero(h).global_position + Vector3(25, 0, 0))
				if await _force(h, ev.id):
					var hit: bool = await _wait(func(): return _has_log(mark, h, "Interacting", ev.id) or _has_log(mark, h, "SESSION_TALK") or _has_log(mark, h, "VANISH", ev.id), 150.0)
					if hit: need -= 1
		ran = _ran_events()
		_check("F", "%s 實跑：≥3 種事件真的進入互動／交談" % h, (ran.get(h, {}) as Dictionary).size() >= 3, "%s" % [(ran.get(h, {}) as Dictionary).keys()])


func _prepare_conditions(h: String, ev: Dictionary) -> void:
	for f in ev.get("need_world", []):
		if f == "anomaly_south_forest":
			dir.call("_spawn_kedama", {"fact": f, "ttl": 900})
		else:
			dir.call("set_world", f, 900.0, "verify")
	for f in ev.get("need_know", []):
		dir.call("learn", h, f)


func _ran_events() -> Dictionary:
	var out := {}
	for r in log_all:
		if r[4] in ["Interacting", "VANISH"] or (r[4] == "SESSION_TALK"):
			if not out.has(r[2]): out[r[2]] = {}
			var e: String = r[3]
			if r[4] == "SESSION_TALK":
				e = "social:" + String(r[3])
			out[r[2]][e] = true
	return out


# ─────────────────────────── G：長時間 ───────────────────────────

func case_g() -> void:
	dir.set("time_scale", 10.0)
	_park_player(Vector3(240, 0.6, 30))
	var mark := log_all.size()
	var last_change := {}
	var last_state := {}
	var worst_idle := {}
	var worst_at := {}
	var t := 0.0
	var chaos_t := 30.0
	var phys: Array = []
	while t < long_secs:
		await _sleep(1.0)
		t += 1.0
		phys.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		for h in dir.get("heroes"):
			var a: Node = dir.get("heroes")[h]
			var st := "%s|%d|%s" % [a.call("life_state"), int(a.get("_si")), _xz((a as Node3D).global_position)]
			if last_state.get(h, "") != st:
				last_state[h] = st
				last_change[h] = t
			var idle := t - float(last_change.get(h, t))
			if idle > float(worst_idle.get(h, 0.0)):
				worst_idle[h] = idle
				worst_at[h] = "%s，生活時鐘 %.0f" % [st, float(dir.get("clock"))]
		# 混亂注入：交談對象被叫走、預約物件失效
		chaos_t -= 1.0
		if chaos_t <= 0.0:
			chaos_t = 45.0
			await _chaos()
	var comp := {}
	var fail := {}
	var intr := {}
	for i in range(mark, log_all.size()):
		var r: Array = log_all[i]
		if r[4] == "Completed": comp[r[2]] = int(comp.get(r[2], 0)) + 1
		if r[4] == "Failed": fail[r[2]] = int(fail.get(r[2], 0)) + 1
		if r[4] == "Interrupted": intr[r[2]] = int(intr.get(r[2], 0)) + 1
	for h in dir.get("heroes"):
		var hid_ok: bool = String(dir.get("heroes")[h].call("life_state")) == "hidden"
		var ended := int(comp.get(h, 0)) + int(fail.get(h, 0)) + int(intr.get(h, 0))
		_check("G", "%s 長跑：事件持續循環（結束 ≥3 件、完成 ≥2 件）" % h, (ended >= 3 and int(comp.get(h, 0)) >= 2) or hid_ok, "完成 %d／失敗 %d／中斷 %d（含混亂注入）" % [comp.get(h, 0), fail.get(h, 0), intr.get(h, 0)])
		_check("G", "%s 長跑：狀態停滯 < 90 s（不卡死）" % h, float(worst_idle.get(h, 0.0)) < 90.0 or hid_ok, "最長停滯 %.0f s（%s）" % [worst_idle.get(h, 0.0), worst_at.get(h, "")])
	# 預約一致性：被預約的物件，預約者一定正在做那件事
	var bad := []
	for oid in dir.get("objects"):
		var o: Dictionary = dir.get("objects")[oid]
		var by := String(o.reserved_by)
		if by != "":
			var p: Dictionary = dir.get("heroes")[by].get("_plan")
			if p.is_empty() or String(p.get("object", "")) != oid:
				bad.append("%s←%s" % [oid, by])
	_check("G", "預約一致（沒有殘留的物件預約）", bad.is_empty(), str(bad))
	var orphan := 0
	for s in dir.get("sessions"):
		if s.state == "talk" and float(s.t) > 200.0: orphan += 1
	_check("G", "沒有殘留的交談 session", orphan == 0, "")
	phys.sort()
	var ps: Dictionary = dir.get("path_stats")
	print("[VERIFY] G 效能：physics 幀 p50 %.2f ms／p95 %.2f ms；尋路 %d 次，平均 %.2f ms，最大 %.2f ms" % [phys[phys.size() / 2], phys[int(phys.size() * 0.95)], ps.n, ps.total_ms / maxf(ps.n, 1), ps.max_ms])
	_check("G", "尋路在背景執行緒、單次計算 ≤ 80 ms（主執行緒不等）", float(ps.max_ms) <= 80.0, "最大 %.2f ms" % ps.max_ms)


func _chaos() -> void:
	var hs: Array = dir.get("heroes").keys()
	hs.shuffle()
	# 1) 發起交談後立刻把對象叫去做別的 → 發起者必須失敗並恢復
	var a: String = hs[0]
	var b: String = hs[1]
	var mark := log_all.size()
	var ev_id := ""
	for ev in dir.get("defs")[a].get("events", []):
		if String(ev.kind) == "social" and not ev.has("need_know") and not ev.has("need_world"):
			ev_id = ev.id
	if ev_id != "" and await _force(a, ev_id, b):
		await _sleep(0.5)
		# 兩人本來就站在一起時，加速時鐘下交談可能已經講完：那就沒有「被叫走」可測
		if (dir.call("session_of", a) as Dictionary).is_empty():
			print("[VERIFY] 混亂注入略過：%s 與 %s 的交談在注入前已結束" % [a, b])
			return
		var pulled := false
		for ev in dir.get("defs")[b].get("events", []):
			if String(ev.kind) in ["object", "place", "route"] and not ev.has("need_world") and not ev.has("need_know"):
				if bool(dir.call("force_event", b, ev.id)):
					pulled = true
					break
		if not pulled:
			print("[VERIFY] 混亂注入略過：%s 當下沒有可改做的事件" % b)
			return
		var rec: bool = await _wait(func(): return _has_log(mark, a, "Failed") or _has_log(mark, a, "Interrupted") or _has_log(mark, a, "SESSION_FAILED") or _has_log(mark, a, "SESSION_INTERRUPTED"), 10.0)
		_check("G", "混亂：%s 找 %s 時對方被叫走 → 發起者釋放" % [a, b], rec, "")
	# 2) 某個被預約的物件突然失效 → 預約者失敗並釋放
	for oid in dir.get("objects"):
		var o: Dictionary = dir.get("objects")[oid]
		if String(o.reserved_by) != "":
			var by := String(o.reserved_by)
			mark = log_all.size()
			o.enabled = false
			var rel: bool = await _wait(func(): return String(o.reserved_by) == "", 6.0)
			_check("G", "混亂：%s 使用中的 %s 失效 → 釋放" % [by, oid], rel, "")
			o.enabled = true
			break


# ─────────────────────────── 工具 ───────────────────────────

func _find_dir() -> Node:
	if dir == null:
		dir = root.get_tree().get_first_node_in_group("npc_life_director")
	return dir


func _hero(id: String) -> Node3D:
	return dir.get("heroes").get(id)


func _force(h: String, ev: String, partner := "", obj := "") -> bool:
	for i in 40:
		if bool(dir.call("force_event", h, ev, partner, obj)):
			return true
		await _sleep(1.5)
	return false


func _plan_goal(a: Node) -> Vector3:
	var p: Dictionary = a.get("_plan")
	if p.is_empty():
		return Vector3.INF
	for st in p.get("steps", []):
		if String(st.op) == "goto":
			return st.to
	return Vector3.INF


func _park_player(p: Vector3) -> void:
	if player == null:
		return
	var y: float = dir.call("ground_y", Vector2(p.x, p.z), p.y)
	player.global_position = Vector3(p.x, y + 0.05, p.z)
	if "velocity" in player:
		player.set("velocity", Vector3.ZERO)


func _disable_dialogue_input() -> void:
	for n in main.find_children("*", "", true, false):
		if n.get_script() != null and String(n.get_script().resource_path).find("dialogue") >= 0 and n.has_method("_unhandled_input"):
			n.set_process_unhandled_input(false)


func _last_session_end(from: int) -> int:
	for i in range(from, log_all.size()):
		var r: Array = log_all[i]
		if r[2] == "marisa" and r[4] == "SESSION_COMPLETED":
			return i
	return from


func _reserved_with(h: String, ev: String, partner: String) -> bool:
	for i in range(log_all.size() - 1, -1, -1):
		var r: Array = log_all[i]
		if r[2] == h and r[3] == ev and r[4] == "Reserved":
			return String(r[5].get("partner", "")) == partner
	return false


## 最近一次 force 之後的起點（該 HERO 最後一筆 Reserved），避免把被 force 打斷的舊事件算進來
func _last_reserved(h: String) -> int:
	for i in range(log_all.size() - 1, -1, -1):
		if log_all[i][2] == h and log_all[i][4] == "Reserved":
			return i
	return log_all.size()


func _has_log(from: int, h: String, state: String, ev := "") -> bool:
	for i in range(from, log_all.size()):
		var r: Array = log_all[i]
		if (h == "" or r[2] == h) and r[4] == state and (ev == "" or r[3] == ev):
			return true
	return false


func _count_log(from: int, h: String, state: String) -> int:
	var n := 0
	for i in range(from, log_all.size()):
		var r: Array = log_all[i]
		if (h == "" or r[2] == h) and r[4] == state:
			n += 1
	return n


func _face_err(a: Node3D, b: Node3D) -> float:
	var d := b.global_position - a.global_position
	return absf(angle_difference(a.rotation.y, atan2(d.x, d.z)))


## 逾時一律用實際經過時間（headless 的 process 幀率不固定，不能用幀數換算秒數）
func _wait(cond: Callable, timeout: float) -> bool:
	var end := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await physics_frame
	return bool(cond.call())


func _sleep(s: float) -> void:
	var end := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < end:
		await physics_frame


func _check(c: String, name: String, ok: bool, detail: String) -> void:
	results.append([c, name, ok, detail])
	print("[%s] %s %s — %s" % ["PASS" if ok else "FAIL", c, name, detail])


func _finish() -> void:
	var fails := results.filter(func(r): return not r[2])
	print("[VERIFY] 總計 %d 項，FAIL %d，耗時 %.0f s" % [results.size(), fails.size(), (Time.get_ticks_msec() - t0) / 1000.0])
	var counts := {}
	for r in log_all:
		counts[r[4]] = int(counts.get(r[4], 0)) + 1
	print("[VERIFY] 事件狀態計數 %s" % JSON.stringify(counts))
	quit(1 if fails.size() > 0 else 0)


func _v3(a: Array) -> Vector3:
	return Vector3(float(a[0]), dir.call("ground_y", Vector2(float(a[0]), float(a[1])), 0.0), float(a[1]))


static func _xz(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z)

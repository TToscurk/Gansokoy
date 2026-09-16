extends SceneTree
## MQ08／MQ09（人間之里 批次 A）回歸測試。
##   Godot --headless --path godot --script tools/verify_village_arc.gd
##
## 這一批是**純資料**（quests / dialogue / interactions / waypoints），沒有新程式。
## 所以驗的是四件容易無聲壞掉的事：
##   P 資料完整性：next_quest_id 指得到、每個 objective 的 target_id 都在
##     waypoints.json 裡（導航與地圖都讀那張表，缺一筆就沒有指引）。
##   D 對話完整性：每個 next／start 節點存在、speaker 在 portraits.json 有名字。
##   G 閘門：MQ08 之前守衛必須完全沉默（不得讓玩家繞過任務鏈先跟慧音對完話）。
##   R 流程：村門 → 寺子屋 → 慧音，兩條序章分支都要能完成 MQ09；
##     對話中途放棄後回訪仍要能完成（reimu repeat 分支的同一課）。

const QUEST_DIR := "res://data/quests/"
const DIALOGUE_DIR := "res://data/dialogue/"
const WAYPOINTS := "res://data/waypoints.json"
const PORTRAITS := "res://data/portraits.json"

## 批次 A／B 新增、且被互動區引用的對話檔
const NEW_DIALOGUES := [
	"village_gatekeeper", "keine_temple_school",
	"kosuzu_suzunaan", "akyuu_hieda", "keine_verdict", "miyoi_kujiratei",
]

var fails := 0


func _init() -> void:
	_run.call_deferred()


func check(label: String, ok: bool) -> void:
	print("[VARC] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		fails += 1


func step(n: int = 6) -> void:
	for i in n:
		await process_frame


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return v if v is Dictionary else {}


func _mk_world() -> Array:
	var world := Node3D.new()
	root.add_child(world)
	world.add_child((load("res://maps/slice/slice_interactions.tscn") as PackedScene).instantiate())
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


## 一路自動 advance 到對話結束（含選項一律選第一項）
func _drive(dm: Node, guard: int = 120) -> void:
	var n := 0
	while dm.call("is_active") and n < guard:
		dm.call("advance", 0)
		n += 1
		await step(1)


func _run() -> void:
	var qm: Node = root.get_node("/root/QuestManager")
	var sf: Node = root.get_node("/root/StoryFlags")
	var dm: Node = root.get_node("/root/DialogueManager")

	_wp = _read_json(WAYPOINTS).get("targets", {})
	_portraits = _read_json(PORTRAITS)

	# ── P. 資料完整性：所有任務的 target_id 都要在 waypoints.json 裡 ──
	var dir := DirAccess.open(QUEST_DIR)
	var quest_ids: Array = []
	var all_targets: Array = []
	var bad_next: Array = []
	for f in dir.get_files():
		if not f.ends_with(".tres"):
			continue
		var q := load(QUEST_DIR + f) as QuestData
		if q == null:
			continue
		quest_ids.append(q.id)
		for o in q.objectives:
			if o == null or o.target_id.is_empty():
				bad_next.append("空目標 @%s" % q.id)
				continue
			all_targets.append(o.target_id)
			if not _wp.has(o.target_id):
				bad_next.append("%s 的 %s 不在 waypoints.json" % [q.id, o.target_id])
		if not q.next_quest_id.is_empty() and not ResourceLoader.exists(QUEST_DIR + q.next_quest_id.to_lower() + ".tres"):
			bad_next.append("%s → %s 找不到定義" % [q.id, q.next_quest_id])
	check("P1 所有 objective target_id 都在 waypoints.json，且鏈不斷", bad_next.is_empty())
	if not bad_next.is_empty():
		for b in bad_next:
			print("[VARC]   ✗ %s" % b)
	check("P2 任務數含新增的 MQ08／MQ09", quest_ids.has("MQ08") and quest_ids.has("MQ09"))

	# ── P3. 導航真的解析得出來（資料存在 ≠ 執行期查得到）──
	#  WaypointResolver 只查「目前 active 任務的當前目標」那一筆，
	#  所以這裡照真實路徑走一次：起 MQ02 → resolve。
	var nav: Node = root.get_node_or_null("/root/WaypointResolver")
	if nav == null:
		check("P3 WaypointResolver autoload 存在", false)
	else:
		qm.call("reset")
		qm.call("start_quest", "MQ02")
		var r: Dictionary = nav.call("resolve", "trail", [])
		check("P3 MQ02 山犬目標導航解析得出座標（trail_wolf 已進表）",
			not r.is_empty() and (r["pos"] as Vector2).distance_to(Vector2(-14.08, -40.03)) < 0.01)
		if not r.is_empty():
			print("[VARC]   導航：%s %s" % [str(r.get("pos")), str(r.get("label"))])
		qm.call("reset")

	# ── D. 對話完整性 ─
	var d_bad: Array = []
	for d in NEW_DIALOGUES:
		var data := _read_json(DIALOGUE_DIR + d + ".json")
		if data.is_empty():
			d_bad.append("%s 讀不到" % d)
			continue
		var nodes: Dictionary = data.get("nodes", {})
		var starts: Array = []
		var st: Variant = data.get("start")
		if st is String:
			starts.append(st)
		elif st is Array:
			for e in st:
				starts.append(String((e as Dictionary).get("node", "")))
		for s in starts:
			if not nodes.has(s):
				d_bad.append("%s 的 start 節點 %s 不存在" % [d, s])
		for nid in nodes:
			var n: Dictionary = nodes[nid]
			var nx: Variant = n.get("next")
			if nx != null and not String(nx).is_empty() and not nodes.has(String(nx)):
				d_bad.append("%s/%s → next %s 不存在" % [d, nid, nx])
			for c in n.get("choices", []):
				var cn: Variant = (c as Dictionary).get("next")
				if cn != null and not String(cn).is_empty() and not nodes.has(String(cn)):
					d_bad.append("%s/%s 選項 → %s 不存在" % [d, nid, cn])
			var sp := String(n.get("speaker", ""))
			if not sp.is_empty() and not _portraits.has(sp):
				d_bad.append("%s/%s speaker %s 不在 portraits.json" % [d, nid, sp])
			if n.has("quest_event"):
				var ev: Dictionary = n["quest_event"]
				if not all_targets.has(String(ev.get("target", ""))):
					d_bad.append("%s/%s quest_event target %s 不是任何任務的目標" % [d, nid, ev.get("target", "")])
	check("D1 新增對話的節點／speaker／quest_event 全部對得上", d_bad.is_empty())
	if not d_bad.is_empty():
		for b in d_bad:
			print("[VARC]   ✗ %s" % b)

	# ── G. 閘門：MQ08 之前守衛必須沉默 ──
	qm.call("reset")
	sf.call("reset")
	var w := _mk_world()
	var world: Node3D = w[0]
	var player: CharacterBody3D = w[1]
	await step(4)
	qm.call("start_quest", "MQ00")
	var guard: Node = world.find_child("村門守衛", true, false)
	var school: Node = world.find_child("寺子屋慧音", true, false)
	var arrive: Node = world.find_child("寺子屋抵達", true, false)
	check("G1 互動區節點都在（守衛／抵達／慧音）", guard != null and school != null and arrive != null)
	if guard == null:
		print("[VARC] 找不到互動區節點，後續流程無法驗")
		quit(1)
		return
	player.global_position = Vector3(240, 2.5, 92)
	await step(6)
	check("G2 MQ08 之前守衛不顯示提示", String(guard.call("prompt_text")).is_empty())
	guard.call("interact")
	await step(4)
	check("G3 MQ08 之前按 E 不起對話", not dm.call("is_active"))
	player.global_position = Vector3(315, 2.5, 46)
	await step(6)
	check("G4 MQ09 之前慧音不顯示提示", String(school.call("prompt_text")).is_empty())

	# ── R1. 村門：進 MQ08 → 對話 → 目標 1 完成、目標切到 REACH ──
	#  G 段落為了驗慧音的閘門，把玩家放進了寺子屋抵達區 —— Area3D 的 body_entered
	#   是物理步尾端才送的，站在區裡 reset() 之後才收到訊號的話，那筆早到事件會
	#   又存回 _pending，R4 就變成「守衛一開口任務就自己完成」。
	#   所以：先把人移開、等訊號落地，再清狀態。
	player.global_position = Vector3(240, 2.5, 92)
	await step(10)
	qm.call("reset")
	sf.call("reset")
	qm.call("start_quest", "MQ07")
	qm.call("report_event", "REACH", "human_village_gate")
	await step(4)
	check("R1 村門抵達完成 MQ07 並連鎖 MQ08", qm.call("is_completed", "MQ07") and qm.call("is_active", "MQ08"))
	player.global_position = Vector3(240, 2.5, 92)
	await step(6)
	check("R2 進 MQ08 後守衛提示亮起", not String(guard.call("prompt_text")).is_empty())
	guard.call("interact")
	await step(4)
	check("R3 按 E 起守衛對話", dm.call("is_active"))
	await _drive(dm)
	check("R4 對話完成守衛目標，MQ08 仍在（等 REACH）", qm.call("is_active", "MQ08"))
	check("R5 目標已切到第 2 格（寺子屋）", _obj_index(qm, "MQ08") == 1)

	# ── R2. 寺子屋抵達 → MQ08 完成、met_gatekeeper、MQ09 接手 ──
	player.global_position = Vector3(315, 2.5, 50)
	await step(10)
	check("R6 抵達寺子屋使 MQ08 完成", qm.call("is_completed", "MQ08"))
	check("R7 met_gatekeeper 旗標立起", sf.call("get_flag", "met_gatekeeper"))
	check("R8 任務鏈續行至 MQ09", qm.call("is_active", "MQ09"))

	# ─ R3. 慧音：spared 分支完成 MQ09 ──
	sf.call("set_flag", "spared_wounded_yokai", true)
	player.global_position = Vector3(315, 2.5, 46)
	await step(6)
	check("R9 進 MQ09 後慧音提示亮起", not String(school.call("prompt_text")).is_empty())
	school.call("interact")
	await step(4)
	await _drive(dm)
	check("R10 spared 分支完成 MQ09", qm.call("is_completed", "MQ09"))
	check("R11 met_keine 旗標立起", sf.call("get_flag", "met_keine"))
	check("R12 spared 分支立 keine_trusts_yoriichi", sf.call("get_flag", "keine_trusts_yoriichi"))

	# ── R4. left 分支：同樣完成，但旗標不同 ──
	qm.call("reset")
	sf.call("reset")
	qm.call("start_quest", "MQ09")
	sf.call("set_flag", "left_wounded_yokai", true)
	school.call("interact")
	await step(4)
	await _drive(dm)
	check("R13 left 分支同樣完成 MQ09", qm.call("is_completed", "MQ09"))
	check("R14 left 分支立 keine_watches_yoriichi（不是 trusts）",
		sf.call("get_flag", "keine_watches_yoriichi") and not sf.call("get_flag", "keine_trusts_yoriichi"))

	# ── R5. 對話中途放棄後回訪仍要能完成（reimu repeat 的同一課）──
	qm.call("reset")
	sf.call("reset")
	qm.call("start_quest", "MQ08")
	guard.call("interact")
	await step(4)
	dm.call("advance")            # 只讀一句就「放棄」
	check("R15 中途放棄時守衛目標尚未完成", _obj_index(qm, "MQ08") == 0)
	await _drive(dm)
	player.global_position = Vector3(240, 2.5, 92)
	await step(6)
	guard.call("interact")
	await step(4)
	await _drive(dm)
	check("R16 回訪（repeat 分支）仍完成守衛目標", _obj_index(qm, "MQ08") == 1)

	# ── R6. 已完成後回訪：不得重複完成、不得橫生枝節 ──
	qm.call("reset")
	sf.call("reset")
	qm.call("start_quest", "MQ09")
	sf.call("set_flag", "met_keine", true)
	var before: int = (qm.get("_progress") as Dictionary).size()
	school.call("interact")
	await step(4)
	await _drive(dm)
	check("R17 已完成後回訪只連鎖下一關，不重複完成原任務",
		(qm.get("_progress") as Dictionary).size() == before + 1
		and qm.call("is_completed", "MQ09") and qm.call("is_active", "MQ10")
		and (qm.get("_pending") as Dictionary).is_empty())

	# ── R7. 早到事件：玩家先晃到寺子屋，再回頭找守衛 ──
	#  寺子屋抵達區沒有前置閘（玩家本來就可能到處亂走），所以他可能在任務還沒
	#  推進到那一格之前就踩過。QuestManager 的 _pending 會把事件存下來，等目標
	#  成為當前目標時補算 —— 這條驗的就是那個補算真的作用在這一條鏈上。
	qm.call("reset")
	sf.call("reset")
	player.global_position = Vector3(315, 2.5, 47)
	await step(10)
	check("R18 沒有任務在跑時走過寺子屋，不留任何 active 進度",
		(qm.get("_progress") as Dictionary).is_empty())
	check("R19 早到事件被存進 pending（將來用得到才存）",
		(qm.get("_pending") as Dictionary).size() == 1)
	player.global_position = Vector3(240, 2.5, 92)
	await step(8)
	qm.call("start_quest", "MQ07")
	qm.call("report_event", "REACH", "human_village_gate")
	await step(4)
	guard.call("interact")
	await step(4)
	await _drive(dm)
	check("R20 守衛指路後，早到的寺子屋事件直接補算 → MQ08 完成",
		qm.call("is_completed", "MQ08") and sf.call("get_flag", "met_gatekeeper"))
	check("R21 補算後仍續行 MQ09", qm.call("is_active", "MQ09"))

	# ══ S. 批次 B：MQ10–MQ12（人里段後半）══
	var kosuzu: Node = world.find_child("鈴奈庵小鈴", true, false)
	var akyuu: Node = world.find_child("稗田邸阿求", true, false)
	var verdict: Node = world.find_child("寺子屋慧音裁定", true, false)
	var inn: Node = world.find_child("鯢吞亭美宵", true, false)
	check("S1 批次 B 的四個互動區節點都在", kosuzu != null and akyuu != null
		and verdict != null and inn != null)
	if kosuzu == null or inn == null:
		print("[VARC] 找不到批次 B 互動區，S 段無法驗")
		quit(1)
		return

	# ─ S2. 閘門：MQ10 之前三個跑腿點都要沉默 ──
	qm.call("reset")
	sf.call("reset")
	player.global_position = Vector3(236, 2.5, -68)
	await step(6)
	check("S2 MQ10 之前鈴奈庵沉默", String(kosuzu.call("prompt_text")).is_empty())
	player.global_position = Vector3(233, 2.5, -122)
	await step(6)
	check("S3 MQ10 之前稗田邸沉默", String(akyuu.call("prompt_text")).is_empty())
	player.global_position = Vector3(213, 2.5, -82)
	await step(6)
	check("S4 MQ12 之前鯢吞亭沉默", String(inn.call("prompt_text")).is_empty())

	# ── S5. MQ09 完成 → 連鎖 MQ10 ─
	qm.call("start_quest", "MQ09")
	qm.call("report_event", "TALK", "keine_first")
	await step(4)
	check("S5 MQ09 完成後連鎖 MQ10（next 已填）",
		qm.call("is_completed", "MQ09") and qm.call("is_active", "MQ10"))

	# ─ S6. 第一格：小鈴（還書）──
	player.global_position = Vector3(236, 2.5, -68)
	await step(6)
	check("S6 MQ10 第一格時鈴奈庵提示亮起", not String(kosuzu.call("prompt_text")).is_empty())
	kosuzu.call("interact")
	await step(4)
	check("S7 按 E 起小鈴對話", dm.call("is_active"))
	await _drive(dm)
	check("S8 小鈴完成第一格，MQ10 仍在（等阿求）",
		qm.call("is_active", "MQ10") and _obj_index(qm, "MQ10") == 1)

	# ── S9. 第二站：阿求當面查冊；不再拆成 MQ11 要玩家原地再按一次 ──
	player.global_position = Vector3(233, 2.5, -122)
	await step(6)
	check("S9 MQ10 時稗田邸提示亮起", not String(akyuu.call("prompt_text")).is_empty())
	_lines.clear()
	dm.connect("line_shown", _record_line)
	akyuu.call("interact")
	await step(4)
	await _drive(dm)
	dm.disconnect("line_shown", _record_line)
	check("S10 阿求對話同時完成查冊與『查無此人』劇情",
		" ".join(_lines).contains("你什麼都沒有") and sf.call("get_flag", "name_not_in_record"))
	check("S11 兩場有角色的會面後完成 MQ10", qm.call("is_completed", "MQ10"))
	check("S12 三顆完成旗標都立起", sf.call("get_flag", "did_keine_errands")
		and sf.call("get_flag", "met_kosuzu") and sf.call("get_flag", "met_akyuu"))
	check("S13 跳過多餘 MQ11，直接連鎖至 MQ12", qm.call("is_active", "MQ12")
		and not qm.call("is_active", "MQ11"))

	# ── S17. MQ12 裁定（信任分支）→ 美宵 ──
	sf.call("set_flag", "keine_trusts_yoriichi", true)
	player.global_position = Vector3(315, 2.5, 47)
	await step(6)
	check("S17 MQ12 時寺子屋（裁定區）亮、MQ09 用的那區退場",
		not String(verdict.call("prompt_text")).is_empty() and String(school.call("prompt_text")).is_empty())
	_lines.clear()
	dm.connect("line_shown", _record_line)
	verdict.call("interact")
	await step(4)
	await _drive(dm)
	dm.disconnect("line_shown", _record_line)
	check("S18 信任分支完成裁定那格", _obj_index(qm, "MQ12") == 1)
	check("S19 信任分支不得出現觀察期的台詞", not " ".join(_lines).contains("別讓我後悔"))

	player.global_position = Vector3(213, 2.5, -82)
	await step(6)
	check("S20 MQ12 第二格時鯢吞亭亮起", not String(inn.call("prompt_text")).is_empty())
	_lines.clear()
	dm.connect("line_shown", _record_line)
	inn.call("interact")
	await step(4)
	await _drive(dm)
	dm.disconnect("line_shown", _record_line)
	check("S21 美宵完成 MQ12", qm.call("is_completed", "MQ12"))
	check("S22 落腳旗標立起（人里段完成）",
		sf.call("get_flag", "has_village_lodging") and sf.call("get_flag", "village_arc_done"))
	check("S23 信任分支的美宵不提『刀放樓下』", not " ".join(_lines).contains("刀放樓下"))

	# ── S24. 反向：觀察分支也要住得下來，且台詞不同 ──
	qm.call("reset")
	sf.call("reset")
	qm.call("start_quest", "MQ12")
	sf.call("set_flag", "keine_watches_yoriichi", true)
	player.global_position = Vector3(315, 2.5, 47)
	await step(6)
	_lines.clear()
	dm.connect("line_shown", _record_line)
	verdict.call("interact")
	await step(4)
	await _drive(dm)
	dm.disconnect("line_shown", _record_line)
	check("S24 觀察分支同樣完成裁定那格", _obj_index(qm, "MQ12") == 1)
	check("S25 觀察分支出現『別讓我後悔』", " ".join(_lines).contains("別讓我後悔"))
	player.global_position = Vector3(213, 2.5, -82)
	await step(6)
	_lines.clear()
	dm.connect("line_shown", _record_line)
	inn.call("interact")
	await step(4)
	await _drive(dm)
	dm.disconnect("line_shown", _record_line)
	check("S26 觀察分支的美宵也收人（台詞含『刀放樓下』）",
		qm.call("is_completed", "MQ12") and " ".join(_lines).contains("刀放樓下"))

	# ── S27. 早到：先見過阿求，再做小鈴那一站 ──
	qm.call("reset")
	sf.call("reset")
	qm.call("start_quest", "MQ10")
	qm.call("report_event", "TALK", "akyuu_record")
	check("S27 第二站事件早到時 MQ10 不得跳過第一站",
		qm.call("is_active", "MQ10") and _obj_index(qm, "MQ10") == 0)
	check("S28 早到的阿求事件存成 pending", (qm.get("_pending") as Dictionary).size() == 1)
	player.global_position = Vector3(236, 2.5, -68)
	await step(6)
	kosuzu.call("interact")
	await step(4)
	await _drive(dm)
	check("S29 小鈴完成後補算阿求事件，直接完成 MQ10", qm.call("is_completed", "MQ10")
		and qm.call("is_active", "MQ12"))

	print("[VARC] ══ 批次 A＋B（MQ08–MQ12）驗證結束：%d 項失敗 ══" % fails)
	quit(1 if fails > 0 else 0)


var _wp := {}
var _portraits := {}
## 對話逐句紀錄（驗分支台詞用）—— 用成員函式而不是 lambda：
## GDScript 的 lambda 對區域變數是傳值捕獲，寫 _lines = [] 只會改到副本。
var _lines: Array = []


func _record_line(_speaker: String, _portrait: Texture2D, text: String, _choices: PackedStringArray) -> void:
	_lines.append(text)


func _obj_index(qm: Node, qid: String) -> int:
	var p: Dictionary = qm.get("_progress").get(qid.to_upper(), {})
	return int(p.get("objective_index", -1))
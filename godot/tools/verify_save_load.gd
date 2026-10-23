extends SceneTree
## 存讀檔回歸測試 —— Godot --headless --path godot --script tools/verify_save_load.gd
##
## 為什麼要有這一支：存檔是「使用者可編輯的檔案」＋「跨版本要活著」的組合，
## 兩者都不能靠人工點測。以下每一條都對應一個真實會壞的情況：
##   A 往返   存了再讀，旗標／任務／pending 必須一模一樣
##   B 壞檔   半截 JSON、非物件、少 version → 不得崩，要退到 .bak
##   C 竄改   手改欄位（負進度、越界索引、不存在的任務）不得汙染狀態
##   D 改版   任務定義變短／任務被刪 → 舊檔要能降級讀，不留推不動的任務
##   E 隔離   deserialize 不得發 signal（否則場景重建中會誤觸發演出）
##   F 版本   沒有 version 的檔一律當壞檔；未來版本照讀不擋

var fails := 0
var qm: Node
var sf: Node
var sm: Node
var inv: Node


func _init() -> void:
	_run.call_deferred()


func check(label: String, ok: bool) -> void:
	print("[SAVE] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		fails += 1


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _run() -> void:
	qm = root.get_node("/root/QuestManager")
	sf = root.get_node("/root/StoryFlags")
	sm = root.get_node("/root/SaveManager")
	inv = root.get_node("/root/InventoryManager")
	var slot := 2                     # 用最後一槽，不動玩家的快速槽
	sm.call("delete_save", slot)

	# ── A. 往返 ──
	qm.call("reset"); sf.call("reset"); inv.call("reset")
	qm.call("start_quest", "MQ03")
	sf.call("set_flag", "woke_in_trail", true)
	sf.call("set_flag", "spared_wounded_yokai", true)
	inv.call("add_item", "kujiratei_room_key", 1)
	qm.call("report_event", "REACH", "hakurei_shrine_approach")  # 早到事件 → pending
	var want_flags: Dictionary = sf.call("serialize")
	var want_quests: Dictionary = qm.call("serialize")
	var want_inventory: Dictionary = inv.call("serialize")
	var pos := Vector3(-1.54, 8.8, -90.74)
	check("A1 存檔成功", sm.call("save_game", slot, "trail", pos, 1.25))
	check("A2 檔案存在", sm.call("has_save", slot))
	# 洗掉記憶體狀態，確認真的是從檔案讀回來的
	qm.call("reset"); sf.call("reset"); inv.call("reset")
	check("A3 洗掉後確實是空的", sf.call("serialize").is_empty() \
		and (qm.get("_progress") as Dictionary).is_empty() \
		and (inv.call("serialize") as Dictionary).is_empty())
	var got_map := ""
	var got_pos := Vector3.ZERO
	var got_yaw := 0.0
	var seen: Array = []
	var on_load := func(m: String, p: Vector3, y: float) -> void:
		seen.append([m, p, y])
	sm.connect("load_requested", on_load)
	check("A4 讀檔成功", sm.call("load_game", slot))
	sm.disconnect("load_requested", on_load)
	check("A5 發出 load_requested 且帶對的地圖／座標／朝向", seen.size() == 1 \
		and String(seen[0][0]) == "trail" \
		and (seen[0][1] as Vector3).distance_to(pos) < 0.001 \
		and absf(float(seen[0][2]) - 1.25) < 0.001)
	check("A6 旗標完全還原", sf.call("serialize") == want_flags)
	check("A7 任務進度完全還原", qm.call("serialize") == want_quests)
	check("A7b 背包完全還原", inv.call("serialize") == want_inventory)
	# MQ03 只剩「受傷妖怪」一格（果實那一格已於 2026-09-17 刪除）。
	check("A8 MQ03 仍停在受傷妖怪那一格（不是從頭來）",
		qm.call("is_active", "MQ03") \
		and (qm.call("get_current_objective", "MQ03") as Object).get("target_id") == "trail_wounded_yokai")
	check("A9 未消化的早到事件也還原", (qm.get("_pending") as Dictionary).has("0|hakurei_shrine_approach"))

	# ── B. 壞檔 → 退到 .bak ──
	# 上一步的 save 已經留了一份主檔；再存一次讓 .bak 生出來，然後毀掉主檔。
	sm.call("save_game", slot, "trail", pos, 1.25)
	check("B1 .bak 已產生", FileAccess.file_exists(sm.call("backup_path", slot)))
	_write(sm.call("slot_path", slot), '{"version":1,"map":"tra')     # 半截 JSON
	qm.call("reset"); sf.call("reset")
	check("B2 主檔壞掉仍讀得起來（退到備份）", sm.call("load_game", slot))
	check("B3 退備份後旗標正確", sf.call("serialize") == want_flags)
	# 主檔與備份都壞
	_write(sm.call("slot_path", slot), "не json")
	_write(sm.call("backup_path", slot), "{]")
	check("B4 兩個檔都壞時安靜失敗（不崩）", not sm.call("load_game", slot))

	# ── C. 竄改 ──
	qm.call("reset"); sf.call("reset")
	_write(sm.call("slot_path", slot), JSON.stringify({
		"version": 1, "map": "trail", "pos": {"x": 0, "y": 0, "z": 0}, "yaw": 0,
		"flags": {"woke_in_trail": true, "bogus_flag": false},
		"quests": {"progress": {
			"MQ03": {"objective_index": 0, "current": -99, "state": 1},
			"MQ99_NOT_REAL": {"objective_index": 0, "current": 1, "state": 1},
			"MQ00": {"objective_index": 77, "current": 5, "state": 1},
		}, "tracked": "MQ99_NOT_REAL", "pending": {"0|nonsense": 999, "99|bad": 5}},
	}))
	DirAccess.remove_absolute(sm.call("backup_path", slot))
	check("C1 竄改過的檔仍讀得起來", sm.call("load_game", slot))
	check("C2 負進度被夾回 0", qm.call("get_objective_progress", "MQ03") == 0)
	check("C3 不存在的任務被丟棄", not qm.call("is_active", "MQ99_NOT_REAL") \
		and not qm.call("is_completed", "MQ99_NOT_REAL"))
	check("C4 越界索引不留成推不動的 active",
		not (qm.call("is_active", "MQ00") and qm.call("get_current_objective", "MQ00") == null))
	check("C5 tracked 指向不存在的任務時改指 active",
		qm.call("get_active_quest") == "" or qm.call("is_active", qm.call("get_active_quest")))
	check("C6 無主／壞型別的 pending 不收", (qm.get("_pending") as Dictionary).is_empty())
	check("C7 值為 false 的旗標不還原成真", not sf.call("get_flag", "bogus_flag"))

	# ── D. 改版：ACTIVE 但索引已超過現行目標數 ──
	qm.call("reset"); sf.call("reset")
	var mq03: Resource = qm.call("load_definition", "MQ03")
	var n_obj: int = mq03.get("objectives").size()
	qm.call("deserialize", {"progress": {
		"MQ03": {"objective_index": n_obj + 3, "current": 0, "state": 1},
	}, "tracked": "MQ03", "pending": {}})
	check("D1 索引越界的 active 轉成已完成（不留死任務）", qm.call("is_completed", "MQ03"))
	check("D2 不再是 active", not qm.call("is_active", "MQ03"))
	check("D3 tracked 不指向已完成任務",
		String(qm.get("_tracked")).is_empty() or qm.call("is_active", qm.get("_tracked")))

	# ── E. deserialize 不得發 signal ──
	qm.call("reset"); sf.call("reset")
	var emitted: Array = []
	var c1 := func(_a: Variant = null) -> void: emitted.append("quest_started")
	var c2 := func(_a: Variant = null) -> void: emitted.append("quest_completed")
	var c3 := func(_a: Variant, _b: Variant, _c: Variant, _d: Variant) -> void:
		emitted.append("objective_updated")
	var c4 := func(_a: Variant, _b: Variant) -> void: emitted.append("flag_changed")
	qm.connect("quest_started", c1)
	qm.connect("quest_completed", c2)
	qm.connect("objective_updated", c3)
	sf.connect("flag_changed", c4)
	qm.call("deserialize", want_quests)
	sf.call("deserialize", want_flags)
	qm.disconnect("quest_started", c1)
	qm.disconnect("quest_completed", c2)
	qm.disconnect("objective_updated", c3)
	sf.disconnect("flag_changed", c4)
	check("E1 還原過程完全不發 signal（避免半成品狀態誤觸發）", emitted.is_empty())
	check("E2 但資料確實進去了", qm.call("is_active", "MQ03") and sf.call("get_flag", "woke_in_trail"))

	# ── F. 版本欄位 ──
	_write(sm.call("slot_path", slot), JSON.stringify({"map": "trail", "flags": {}}))
	DirAccess.remove_absolute(sm.call("backup_path", slot))
	check("F1 沒有 version 的檔當壞檔拒收", not sm.call("load_game", slot))
	_write(sm.call("slot_path", slot), JSON.stringify({
		"version": 999, "map": "trail", "pos": {"x": 1, "y": 2, "z": 3}, "yaw": 0,
		"flags": {"woke_in_trail": true}, "quests": {"progress": {}, "tracked": "", "pending": {}},
	}))
	check("F2 未來版本照讀不擋", sm.call("load_game", slot))
	check("F3 slot_info 回摘要", (sm.call("slot_info", slot) as Dictionary).has("saved_at"))

	# ── G. v1 → v2 背包遷移 ──
	_write(sm.call("slot_path", slot), JSON.stringify({
		"version": 1, "map": "slice", "pos": {"x": 0, "y": 0, "z": 0}, "yaw": 0,
		"flags": {"met_keine": true}, "quests": {"progress": {}, "tracked": "", "pending": {}},
	}))
	inv.call("reset")
	check("G1 v1 慧音已交書的存檔可升級", sm.call("load_game", slot) \
		and inv.call("has_item", "terakoya_book"))
	_write(sm.call("slot_path", slot), JSON.stringify({
		"version": 1, "map": "slice", "pos": {"x": 0, "y": 0, "z": 0}, "yaw": 0,
		"flags": {"met_keine": true, "met_kosuzu": true, "has_village_lodging": true},
		"quests": {"progress": {}, "tracked": "", "pending": {}},
	}))
	check("G2 已還書且已住宿的舊檔只補客房鑰匙", sm.call("load_game", slot) \
		and not inv.call("has_item", "terakoya_book") \
		and inv.call("has_item", "kujiratei_room_key"))
	sm.call("delete_save", slot)
	check("F4 delete_save 清掉主檔與備份", not sm.call("has_save", slot))
	check("F5 沒有存檔時 slot_info 回空字典", (sm.call("slot_info", slot) as Dictionary).is_empty())

	print("[SAVE] failures=%d" % fails)
	quit(1 if fails > 0 else 0)

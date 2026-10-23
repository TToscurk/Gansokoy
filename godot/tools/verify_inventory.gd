extends SceneTree
## 任務道具系統回歸測試。
## Godot --headless --path godot --script tools/verify_inventory.gd

var fails := 0


func _init() -> void:
	_run.call_deferred()


func check(label: String, ok: bool) -> void:
	print("[ITEM] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		fails += 1


func _run() -> void:
	var inv := root.get_node_or_null("/root/InventoryManager")
	check("A1 InventoryManager autoload 存在", inv != null)
	if inv == null:
		print("[ITEM] failures=%d" % fails)
		quit(1)
		return
	inv.call("reset")
	var overflow: int = inv.call("add_item", "terakoya_book", 1)
	check("A2 可用 id 加入任務道具", overflow == 0 and inv.call("count_item", "terakoya_book") == 1)
	check("A3 唯一道具不會超過堆疊上限", inv.call("add_item", "terakoya_book", 2) == 2 \
		and inv.call("count_item", "terakoya_book") == 1)
	check("A4 數量不足時不會部分扣除", not inv.call("remove_item", "terakoya_book", 2) \
		and inv.call("count_item", "terakoya_book") == 1)
	check("A5 可完整移除道具", inv.call("remove_item", "terakoya_book", 1) \
		and not inv.call("has_item", "terakoya_book"))
	check("A6 未知 id 不會進入背包", inv.call("add_item", "not_real", 3) == 3 \
		and not inv.call("has_item", "not_real"))

	# ── B. 任務完成獎勵 ──
	var qm := root.get_node("/root/QuestManager")
	qm.call("reset")
	inv.call("reset")
	check("B1 MQ09 可啟動", qm.call("start_quest", "MQ09"))
	qm.call("complete_quest", "MQ09")
	check("B2 完成 MQ09 取得慧音借書", inv.call("has_item", "terakoya_book"))
	# 重複完成（例如回呼 complete_quest）不得再發一次獎勵
	qm.call("complete_quest", "MQ09")
	check("B3 重複完成 MQ09 不會拿到第二本", inv.call("count_item", "terakoya_book") == 1)
	var rewards: Array = (qm.call("load_definition", "MQ09") as Object).get("rewards")
	check("B4 MQ09 獎勵指向存在的道具", rewards.size() == 1 \
		and inv.call("definition", String(rewards[0].get("item_id"))) != null)

	# ── C. 對話中的交付與取得 ──
	var sf := root.get_node("/root/StoryFlags")
	var dm := root.get_node("/root/DialogueManager")
	sf.call("reset")
	check("C1 可開始小鈴初見對話", dm.call("start", "kosuzu_suzunaan"))
	for i in 20:
		dm.call("advance")
	check("C2 小鈴收書時從背包移除", not inv.call("has_item", "terakoya_book"))
	sf.call("reset")
	check("C3 可開始美宵住宿對話", dm.call("start", "miyoi_kujiratei"))
	for i in 15:
		dm.call("advance")
	check("C4 美宵交付客房鑰匙", inv.call("has_item", "kujiratei_room_key"))
	# 沒有書的狀態下去還書（例如存檔只剩一半流程）不得弄壞對話
	sf.call("reset")
	check("C5 沒有書時仍可開始小鈴對話", dm.call("start", "kosuzu_suzunaan"))
	for i in 3:
		dm.call("advance")
	check("C6 沒書去還書不會中斷對話", dm.call("is_active"))

	# ── D. 玩家可見的道具袋與取得提示 ──
	var ui_scene := load("res://ui/inventory/inventory_ui.tscn") as PackedScene
	var toast_scene := load("res://ui/inventory/item_toast.tscn") as PackedScene
	check("D1 道具袋與提示場景可載入", ui_scene != null and toast_scene != null)
	if ui_scene != null and toast_scene != null:
		var ui := ui_scene.instantiate()
		var toast := toast_scene.instantiate()
		root.add_child(ui)
		root.add_child(toast)
		await process_frame
		ui.call("_set_open", true)
		check("D2 道具袋可開啟並列出持有物", ui.visible \
			and ui.get_node("Dim/Panel/Margin/Layout/Items").get_child_count() == 1)
		inv.call("reset")
		inv.call("add_item", "terakoya_book", 1)
		await process_frame
		check("D3 取得道具時顯示提示", toast.get_node("Panel").visible \
			and "慧音借出的書" in String(toast.get_node("Panel/Label").text))
		ui.queue_free()
		toast.queue_free()
	print("[ITEM] failures=%d" % fails)
	quit(1 if fails > 0 else 0)

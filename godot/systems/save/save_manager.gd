extends Node
## SaveManager —— 存檔（autoload）。
##
## 檔案：user://save_<slot>.json（slot 0..2）＋ 同名 .bak。
## 存的是**純資料**：劇情旗標、任務進度、玩家所在圖與座標。
## 不存節點、不存 Resource、不存世界物件狀態 —— 世界由 res:// 的場景重建，
## 「已經發生過的事」全部由 StoryFlags 的旗標代表。
##
## 依賴方向：SaveManager → QuestManager / StoryFlags（往下呼叫 serialize/deserialize）。
## 本節點不認識 main、不 get_node 世界物件；載入後由 main 監聽 load_requested 重建場景。
##
## ⚠ 為什麼要有版本號：任務定義（data/quests/*.tres）與旗標名都會隨開發變動。
##   沒有 version 欄位的話，改一次任務內容就得叫使用者砍掉存檔重來。
##   現在的規則是「讀得懂就讀，讀不懂的欄位用預設值」，並在 _migrate() 留升級點。

signal game_saved(slot: int)
signal game_loaded(slot: int)
## 載入完成、資料已就位，但世界還沒重建 —— main 監聽這個訊號切圖、擺玩家。
signal load_requested(map_id: String, position: Vector3, yaw: float)

const SAVE_VERSION := 2
const SLOT_COUNT := 3
const SAVE_PREFIX := "user://save_"


func slot_path(slot: int) -> String:
	return "%s%d.json" % [SAVE_PREFIX, slot]


func backup_path(slot: int) -> String:
	return "%s%d.json.bak" % [SAVE_PREFIX, slot]


func has_save(slot: int) -> bool:
	return FileAccess.file_exists(slot_path(slot)) or FileAccess.file_exists(backup_path(slot))


## 存檔。map_id / pos / yaw 由呼叫端（main）提供 —— SaveManager 不去翻場景樹。
## 回傳是否成功。
func save_game(slot: int, map_id: String, pos: Vector3, yaw: float) -> bool:
	if slot < 0 or slot >= SLOT_COUNT:
		push_error("[Save] 槽位超出範圍：%d" % slot)
		return false
	var dn: Node = get_node_or_null("/root/DayNight")
	var cur_hour: float = float(dn.get("hour")) if dn != null else 6.5
	var cur_day: int = int(dn.get("day")) if dn != null else 1
	var data := {
		"version": SAVE_VERSION,
		"saved_at": Time.get_datetime_string_from_system(true),
		"map": map_id,
		# ⚠ Vector3 不能直接進 JSON（會變成字串，讀回來是垃圾）。拆成三個數字。
		"pos": {"x": pos.x, "y": pos.y, "z": pos.z},
		"yaw": yaw,
		"day": cur_day,
		"hour": cur_hour,
		"flags": StoryFlags.serialize(),
		"quests": QuestManager.serialize(),
		"inventory": InventoryManager.serialize(),
	}
	var txt := JSON.stringify(data, "  ")
	# ⚠ 先備份再覆寫：寫到一半當掉會讓主檔變成半截 JSON，
	#   沒有 .bak 的話玩家的進度就直接沒了。
	var path := slot_path(slot)
	if FileAccess.file_exists(path):
		DirAccess.copy_absolute(path, backup_path(slot))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("[Save] 寫不進 %s（err=%d）" % [path, FileAccess.get_open_error()])
		return false
	f.store_string(txt)
	f.close()
	game_saved.emit(slot)
	print("[Save] 已存到槽 %d（%s / %s）" % [slot, map_id, data["saved_at"]])
	return true


## 讀檔並把資料灌進 StoryFlags / QuestManager，然後發 load_requested 讓 main 重建世界。
## 主檔壞掉時自動退回 .bak。回傳是否成功。
func load_game(slot: int) -> bool:
	var data := _read_slot(slot_path(slot))
	if data.is_empty():
		data = _read_slot(backup_path(slot))
		if not data.is_empty():
			push_warning("[Save] 槽 %d 主檔壞了，改用備份" % slot)
	if data.is_empty():
		push_warning("[Save] 槽 %d 沒有可用的存檔" % slot)
		return false
	data = _migrate(data)
	StoryFlags.deserialize(data.get("flags", {}))
	QuestManager.deserialize(data.get("quests", {}))
	InventoryManager.deserialize(data.get("inventory", {}))
	var dn: Node = get_node_or_null("/root/DayNight")
	if dn != null:
		if data.has("day"):
			dn.set("day", int(data["day"]))
		if data.has("hour") and dn.has_method("set_hour"):
			dn.set_hour(float(data["hour"]))
	var p: Dictionary = data.get("pos", {})
	var pos := Vector3(float(p.get("x", 0.0)), float(p.get("y", 0.0)), float(p.get("z", 0.0)))
	var map_id := String(data.get("map", ""))
	game_loaded.emit(slot)
	load_requested.emit(map_id, pos, float(data.get("yaw", 0.0)))
	print("[Save] 已讀取槽 %d（%s）" % [slot, map_id])
	return true


## 槽位摘要，給存讀檔 UI 用。沒有存檔就回空字典。
func slot_info(slot: int) -> Dictionary:
	var data := _read_slot(slot_path(slot))
	if data.is_empty():
		data = _read_slot(backup_path(slot))
	if data.is_empty():
		return {}
	var quests: Dictionary = data.get("quests", {})
	var tracked := String(quests.get("tracked", ""))
	var title := tracked
	var q := QuestManager.load_definition(tracked) if not tracked.is_empty() else null
	if q != null:
		title = q.title
	return {
		"slot": slot,
		"saved_at": String(data.get("saved_at", "")),
		"map": String(data.get("map", "")),
		"quest": title,
		"version": int(data.get("version", 0)),
	}


func delete_save(slot: int) -> void:
	for p in [slot_path(slot), backup_path(slot)]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


## 讀一個檔並驗基本形狀。壞檔回空字典（呼叫端負責退到 .bak）。
##
## ⚠ 存檔是使用者可編輯的純文字。JSON.parse_string 對壞資料回 null，
##   不檢查就直接當 Dictionary 用會在載入時整個崩掉。
func _read_slot(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var txt := FileAccess.get_file_as_string(path)
	if txt.is_empty():
		return {}
	var v: Variant = JSON.parse_string(txt)
	if not (v is Dictionary):
		push_warning("[Save] %s 不是合法的 JSON 物件" % path)
		return {}
	var d: Dictionary = v
	if not d.has("version"):
		push_warning("[Save] %s 沒有 version 欄位，當成壞檔" % path)
		return {}
	return d


## 舊版存檔逐版升級。v1 沒有背包，依已發生的劇情補回玩家當下應持有的任務道具。
func _migrate(data: Dictionary) -> Dictionary:
	var v := int(data.get("version", 0))
	if v == SAVE_VERSION:
		return data
	if v > SAVE_VERSION:
		# 未來版本的檔：欄位可能多出來，但 get(…, 預設值) 讀得下去，照讀不擋。
		push_warning("[Save] 存檔版本 %d 比本體 %d 新，嘗試照讀" % [v, SAVE_VERSION])
		return data
	push_warning("[Save] 升級存檔 v%d → v%d" % [v, SAVE_VERSION])
	if v < 2:
		var flags: Dictionary = data.get("flags", {})
		var inventory := {}
		# MQ09 完成後慧音已交書；見過小鈴表示書已還掉。
		if bool(flags.get("met_keine", false)) and not bool(flags.get("met_kosuzu", false)):
			inventory["terakoya_book"] = 1
		if bool(flags.get("has_village_lodging", false)):
			inventory["kujiratei_room_key"] = 1
		data["inventory"] = inventory
	data["version"] = SAVE_VERSION
	return data

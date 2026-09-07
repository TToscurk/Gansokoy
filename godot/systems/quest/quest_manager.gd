extends Node
## QuestManager —— 任務進度（autoload）。
##
## 定義 = res://data/quests/<id>.tres（QuestData）；進度只存在這裡：
##   _progress[quest_id] = { "objective_index": int, "current": int, "state": State }
## 事件入口只有 report_event()；沒有對應的 active quest 就安靜忽略。
## 不 get_node 世界物件；只往下呼叫 StoryFlags。

signal quest_started(quest_id: String)
signal objective_updated(quest_id: String, objective_index: int, current: int, required: int)
signal quest_completed(quest_id: String)
signal tracked_quest_changed(quest_id: String)

enum State { INACTIVE, ACTIVE, COMPLETED }

const QUEST_DIR := "res://data/quests/"

var _progress: Dictionary = {}
var _tracked: String = ""
var _defs: Dictionary = {}       # id → QuestData（快取）


func load_definition(quest_id: String) -> QuestData:
	if _defs.has(quest_id):
		return _defs[quest_id]
	var path := QUEST_DIR + quest_id.to_lower() + ".tres"
	if not ResourceLoader.exists(path):
		push_warning("[Quest] 找不到任務定義 %s" % path)
		return null
	var q := load(path) as QuestData
	if q != null:
		_defs[quest_id] = q
	return q


func start_quest(quest_id: String) -> bool:
	if is_active(quest_id) or is_completed(quest_id):
		return false
	var q := load_definition(quest_id)
	if q == null:
		return false
	_progress[quest_id] = {"objective_index": 0, "current": 0, "state": State.ACTIVE}
	quest_started.emit(quest_id)
	if _tracked.is_empty() or not is_active(_tracked):
		_set_tracked(quest_id)
	var obj := get_current_objective(quest_id)
	if obj != null:
		objective_updated.emit(quest_id, 0, 0, obj.required_amount)
	return true


## 統一事件入口。type 用 QuestObjective.Type 的名字（"REACH"/"TALK"…）或列舉值。
func report_event(event_type: Variant, target_id: String, amount: int = 1) -> void:
	var t := _to_type(event_type)
	if t < 0:
		return
	for quest_id in _progress.keys():
		if _progress[quest_id]["state"] != State.ACTIVE:
			continue
		var obj := get_current_objective(quest_id)
		if obj == null or obj.type != t or obj.target_id != target_id:
			continue
		var p: Dictionary = _progress[quest_id]
		if p["current"] >= obj.required_amount:
			continue          # 已滿，不重複計
		p["current"] = mini(p["current"] + amount, obj.required_amount)
		objective_updated.emit(quest_id, p["objective_index"], p["current"], obj.required_amount)
		if p["current"] >= obj.required_amount:
			advance_objective(quest_id)


func advance_objective(quest_id: String) -> void:
	if not is_active(quest_id):
		return
	var q := load_definition(quest_id)
	var p: Dictionary = _progress[quest_id]
	p["objective_index"] += 1
	p["current"] = 0
	if p["objective_index"] >= q.objectives.size():
		complete_quest(quest_id)
	else:
		var obj: QuestObjective = q.objectives[p["objective_index"]]
		objective_updated.emit(quest_id, p["objective_index"], 0, obj.required_amount)


func complete_quest(quest_id: String) -> void:
	if not is_active(quest_id):
		return
	var q := load_definition(quest_id)
	_progress[quest_id]["state"] = State.COMPLETED
	for f in q.complete_flags:
		StoryFlags.set_flag(String(f), true)
	quest_completed.emit(quest_id)
	if not q.next_quest_id.is_empty():
		start_quest(q.next_quest_id)
	elif _tracked == quest_id:
		_set_tracked("")


func is_active(quest_id: String) -> bool:
	return _progress.has(quest_id) and _progress[quest_id]["state"] == State.ACTIVE


func is_completed(quest_id: String) -> bool:
	return _progress.has(quest_id) and _progress[quest_id]["state"] == State.COMPLETED


func get_active_quest() -> String:
	if is_active(_tracked):
		return _tracked
	for id in _progress.keys():
		if is_active(id):
			return id
	return ""


func get_current_objective(quest_id: String) -> QuestObjective:
	if not is_active(quest_id):
		return null
	var q := load_definition(quest_id)
	var i: int = _progress[quest_id]["objective_index"]
	if q == null or i >= q.objectives.size():
		return null
	return q.objectives[i]


func get_objective_progress(quest_id: String) -> int:
	return int(_progress.get(quest_id, {}).get("current", 0))


func _set_tracked(quest_id: String) -> void:
	_tracked = quest_id
	tracked_quest_changed.emit(quest_id)


func _to_type(v: Variant) -> int:
	if v is int:
		return int(v)
	var s := String(v).to_upper()
	if QuestObjective.Type.has(s):
		return QuestObjective.Type[s]
	push_warning("[Quest] 未知事件型別 %s" % s)
	return -1


## 測試用
func reset() -> void:
	_progress.clear()
	_tracked = ""

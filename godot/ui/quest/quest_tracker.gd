extends CanvasLayer
## 右上角極簡任務追蹤：**只留一行當前目標**。
##
## 2026-09-22 使用者裁定「常駐提示太擠、同一件事講兩次」：
##   - 標題不再常駐（目標本身已經說明要做什麼；目的地由指路浮標的距離表示）。
##   - 任務開始／完成各用中央橫幅報一次名字（停留 2.6 秒後淡出），報完就收掉。
##   - 對話中整塊隱藏 —— 對話框已經佔了畫面下半，不需要任務文字搶注意力。
## 只監聽 QuestManager 與 DialogueManager 的 signal，不認識世界。
## 外觀（掛紙、御札燃燒、滑入展開）全在 GensokyoQuestTracker。

@onready var _tracker: GensokyoQuestTracker = $Tracker

## 橫幅停留秒數（含淡出前的靜止時間）
@export var banner_hold := 2.6:
	set(v):
		banner_hold = v
		if is_node_ready():
			_tracker.banner_hold = v

var _in_dialogue := false


func _ready() -> void:
	_tracker.banner_hold = banner_hold
	QuestManager.quest_started.connect(_on_started)
	QuestManager.objective_updated.connect(func(_id: String, _i: int, _c: int, _r: int) -> void: _refresh())
	QuestManager.tracked_quest_changed.connect(func(_id: String) -> void: _refresh())
	QuestManager.quest_completed.connect(_on_completed)
	DialogueManager.dialogue_started.connect(func(_id: String) -> void:
		_in_dialogue = true
		_refresh())
	DialogueManager.dialogue_ended.connect(func(_id: String) -> void:
		_in_dialogue = false
		_refresh())
	_refresh()


func _refresh() -> void:
	if _in_dialogue:
		_tracker.hide_objective()
		return
	var id := QuestManager.get_active_quest()
	if id.is_empty():
		_tracker.hide_objective()
		return
	var obj := QuestManager.get_current_objective(id)
	if obj == null:
		_tracker.hide_objective()
		return
	var prog := ""
	if obj.required_amount > 1:
		prog = "  %d / %d" % [QuestManager.get_objective_progress(id), obj.required_amount]
	_tracker.show_objective(obj.description + prog, _is_main(id))


## 主線 = MQ 開頭（data/quests/mqNN.tres）；其他視為支線（墨灰）。
static func _is_main(id: String) -> bool:
	return id.to_upper().begins_with("MQ")


func _on_started(id: String) -> void:
	_tracker.announce("new", _title_of(id))


func _on_completed(id: String) -> void:
	_tracker.announce("done", _title_of(id))


func _title_of(id: String) -> String:
	var q := QuestManager.load_definition(id)
	return q.title if q != null else id

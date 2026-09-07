extends CanvasLayer
## 右上角極簡任務追蹤：標題 + 當前目標。完成時「──── 任務完成 ────」淡出。
## 只監聽 QuestManager signal。

@onready var _title: Label = $Box/Title
@onready var _objective: Label = $Box/Objective
@onready var _done: Label = $Done

var _tween: Tween = null


func _ready() -> void:
	$Box.visible = false
	_done.visible = false
	QuestManager.quest_started.connect(func(_id: String) -> void: _refresh())
	QuestManager.objective_updated.connect(func(_id: String, _i: int, _c: int, _r: int) -> void: _refresh())
	QuestManager.tracked_quest_changed.connect(func(_id: String) -> void: _refresh())
	QuestManager.quest_completed.connect(_on_completed)
	_refresh()


func _refresh() -> void:
	var id := QuestManager.get_active_quest()
	if id.is_empty():
		$Box.visible = false
		return
	var q := QuestManager.load_definition(id)
	var obj := QuestManager.get_current_objective(id)
	_title.text = q.title if q != null else id
	if obj != null:
		var prog := ""
		if obj.required_amount > 1:
			prog = "  %d / %d" % [QuestManager.get_objective_progress(id), obj.required_amount]
		_objective.text = obj.description + prog
	else:
		_objective.text = ""
	$Box.visible = true


func _on_completed(id: String) -> void:
	var q := QuestManager.load_definition(id)
	_done.text = "──── 任務完成 ────\n%s" % (q.title if q != null else id)
	_done.modulate.a = 1.0
	_done.visible = true
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_interval(2.0)
	_tween.tween_property(_done, "modulate:a", 0.0, 1.2)
	_tween.tween_callback(func() -> void: _done.visible = false)

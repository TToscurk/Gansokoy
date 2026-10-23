extends CanvasLayer
## 冥想選單 —— 只負責「選一個時長」與上下鍵，**不碰時間**。
## 選好 emit chosen(索引)，取消 emit cancelled；換算與快轉在
## systems/time/meditation_controller.gd。

signal chosen(index: int)
signal cancelled

@onready var _list: VBoxContainer = $Panel/VBox/List
@onready var _clock: Label = $Panel/VBox/Clock

var _idx := 0
var _buttons: Array[Button] = []


func _ready() -> void:
	visible = false
	# 全螢幕面板互斥（存檔選單靠這個群組判斷「別的面板開著就別搶 Esc」）
	add_to_group("modal_ui")


func is_open() -> bool:
	return visible


## entries: [{ "text": "三十分鐘", "detail": "15:50（+30 分）" }, …]
func open(entries: Array, now_text: String) -> void:
	for c in _list.get_children():
		c.queue_free()
	_buttons.clear()
	_clock.text = now_text
	for i in entries.size():
		var e: Dictionary = entries[i]
		var b := Button.new()
		b.text = "%s　→　%s" % [String(e.get("text", "")), String(e.get("detail", ""))]
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 18)
		b.pressed.connect(func() -> void: _choose(i))
		_list.add_child(b)
		_buttons.append(b)
	_idx = 0
	_highlight()
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_up") or event.is_action_pressed("move_forward"):
		_idx = wrapi(_idx - 1, 0, _buttons.size())
		_highlight()
	elif event.is_action_pressed("ui_down") or event.is_action_pressed("move_back"):
		_idx = wrapi(_idx + 1, 0, _buttons.size())
		_highlight()
	elif event.is_action_pressed("ui_accept") or event.is_action_pressed("interact"):
		_choose(_idx)
	# 再按一次冥想鍵＝取消（開關同鍵，跟地圖／背包一致）
	elif event.is_action_pressed("ui_cancel") or event.is_action_pressed("meditate"):
		visible = false
		cancelled.emit()
	else:
		return
	get_viewport().set_input_as_handled()


func _choose(index: int) -> void:
	if index < 0 or index >= _buttons.size():
		return
	visible = false
	chosen.emit(index)


func _highlight() -> void:
	for i in _buttons.size():
		_buttons[i].modulate = Color(1, 0.9, 0.6) if i == _idx else Color(1, 1, 1)

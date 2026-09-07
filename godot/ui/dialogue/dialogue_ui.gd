extends CanvasLayer
## 立繪對話 UI。監聽 DialogueManager 的 signal；不知道任務或世界。
## 背景暗化 = 半透明 ColorRect 蓋在 3D 上，不切場景。
## 逐句：Enter/Space/E/滑鼠左鍵 推進；有選項時 ↑↓ + Enter 或點選。

@export var dim_alpha := 0.45
@export var typewriter_cps := 40.0     # 0 = 直接全顯示

@onready var _dim: ColorRect = $Dim
@onready var _portrait: TextureRect = $Portrait
@onready var _name: Label = $Panel/VBox/Name
@onready var _text: RichTextLabel = $Panel/VBox/Text
@onready var _choices: VBoxContainer = $Panel/VBox/Choices
@onready var _next_hint: Label = $Panel/VBox/NextHint

var _choice_idx := 0
var _typing := false


func _ready() -> void:
	visible = false
	_dim.color.a = dim_alpha
	DialogueManager.dialogue_started.connect(_on_started)
	DialogueManager.line_shown.connect(_on_line)
	DialogueManager.dialogue_ended.connect(_on_ended)


func _on_started(_id: String) -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_ended(_id: String) -> void:
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_line(speaker: String, portrait: Texture2D, text: String, choices: PackedStringArray) -> void:
	_name.text = speaker
	_portrait.texture = portrait
	_portrait.visible = portrait != null
	_text.text = text
	for c in _choices.get_children():
		c.queue_free()
	_choice_idx = 0
	for i in choices.size():
		var b := Button.new()
		b.text = choices[i]
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func() -> void: DialogueManager.advance(i))
		_choices.add_child(b)
	_choices.visible = choices.size() > 0
	_next_hint.visible = choices.size() == 0
	_highlight_choice()
	if typewriter_cps > 0.0:
		_text.visible_ratio = 0.0
		_typing = true
	else:
		_text.visible_ratio = 1.0
		_typing = false


func _process(delta: float) -> void:
	if not visible or not _typing:
		return
	var total := maxf(float(_text.get_total_character_count()), 1.0)
	_text.visible_ratio = minf(_text.visible_ratio + typewriter_cps * delta / total, 1.0)
	if _text.visible_ratio >= 1.0:
		_typing = false


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	var confirm: bool = event.is_action_pressed("ui_accept") or event.is_action_pressed("interact") \
		or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
	if _choices.visible:
		if event.is_action_pressed("ui_up") or event.is_action_pressed("move_forward"):
			_choice_idx = wrapi(_choice_idx - 1, 0, _choices.get_child_count())
			_highlight_choice()
		elif event.is_action_pressed("ui_down") or event.is_action_pressed("move_back"):
			_choice_idx = wrapi(_choice_idx + 1, 0, _choices.get_child_count())
			_highlight_choice()
		elif event.is_action_pressed("ui_accept") or event.is_action_pressed("interact"):
			DialogueManager.advance(_choice_idx)
		else:
			return
		get_viewport().set_input_as_handled()
		return
	if confirm:
		get_viewport().set_input_as_handled()
		if _typing:
			_text.visible_ratio = 1.0
			_typing = false
		else:
			DialogueManager.advance()


func _highlight_choice() -> void:
	for i in _choices.get_child_count():
		var b := _choices.get_child(i) as Button
		b.modulate = Color(1, 0.9, 0.6) if i == _choice_idx else Color(1, 1, 1)

extends CanvasLayer
## 立繪對話 UI。監聽 DialogueManager 的 signal；不知道任務或世界。
## 外觀全在 ui/gensokyo/（GensokyoDialogueBox）；這支只管推進、選項、打字機。
## 背景暗化 = 半透明墨色 ColorRect 蓋在 3D 上（規格：降低亮度 10–15%），不切場景。
## 逐句：Enter/Space/E/滑鼠左鍵 推進；有選項時 ↑↓ + Enter 或點選。

## 背景暗化；規格 Important Dialogue = 10–15%。
@export_range(0.0, 0.6, 0.01) var dim_alpha := 0.13
@export var typewriter_cps := 40.0     # 0 = 直接全顯示

@onready var _dim: ColorRect = $Dim
@onready var _portrait: TextureRect = $Portrait
@onready var _box: GensokyoDialogueBox = $Box
@onready var _text: RichTextLabel = $Box/Panel/VBox/Text
@onready var _choices: VBoxContainer = $Box/Panel/VBox/Choices
@onready var _next_hint: Label = $Box/Panel/VBox/NextHint

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
	_box.play_enter()
	var st := GensokyoStyle.current()
	_dim.color.a = 0.0
	create_tween().tween_property(_dim, "color:a", dim_alpha, st.dur(st.dialogue_reveal_duration))


func _on_ended(_id: String) -> void:
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## 立繪路徑 …/reimu_smile.png → "smile"（名牌小飾用；取不到就 normal）。
static func _portrait_key(tex: Texture2D) -> String:
	if tex == null:
		return "normal"
	var base := tex.resource_path.get_file().get_basename()
	var cut := base.rfind("_")
	return base.substr(cut + 1) if cut >= 0 else "normal"


func _on_line(speaker: String, portrait: Texture2D, text: String, choices: PackedStringArray) -> void:
	_box.set_speaker(speaker, _portrait_key(portrait))
	_portrait.texture = portrait
	_portrait.visible = portrait != null
	_text.text = text
	for c in _choices.get_children():
		c.queue_free()
	_choice_idx = 0
	for i in choices.size():
		var b := GensokyoButton.new()
		b.text = choices[i]
		b.pressed.connect(func() -> void: DialogueManager.advance(i))
		b.mouse_entered.connect(func() -> void:
			_choice_idx = i
			_highlight_choice())
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
	if not visible:
		return
	if _typing:
		var total := maxf(float(_text.get_total_character_count()), 1.0)
		_text.visible_ratio = minf(_text.visible_ratio + typewriter_cps * delta / total, 1.0)
		if _text.visible_ratio >= 1.0:
			_typing = false
	if _next_hint.visible:
		# 慢呼吸，不閃爍
		_next_hint.modulate.a = 0.45 + 0.35 * sin(Time.get_ticks_msec() * 0.0035)


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
		var b := _choices.get_child(i) as GensokyoButton
		if b != null:
			b.selected = i == _choice_idx

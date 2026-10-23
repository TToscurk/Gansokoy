@tool
extends Control
class_name GensokyoDialogueBox
## 對話框元件（規格 DialogueBox）：
##   anchor bottom_center、寬 0.62 viewport、min_height 180、和紙 0.92–0.94、
##   不規則墨框（3px、irregularity 0.55）、名牌壓框（offset_x 48）、左楓葉＋繩結／右紙垂。
## 本節點鋪滿畫面（不吃滑鼠），自己算 Panel 位置；Panel 隨文字長高，不是固定大方框。
## 只負責外觀與版面；推進／選項邏輯留在 ui/dialogue/dialogue_ui.gd。

@export_range(0.3, 0.95, 0.01) var width_ratio := 0.62:
	set(v):
		width_ratio = v
		_queue_layout()
@export var min_height := 180.0:
	set(v):
		min_height = v
		_queue_layout()
@export var bottom_margin := 38.0:
	set(v):
		bottom_margin = v
		_queue_layout()
@export var nameplate_offset_x := 48.0:
	set(v):
		nameplate_offset_x = v
		_queue_layout()
@export var speaker_size := 28.0
@export var dialogue_size := 25.0

@onready var panel: GensokyoPanel = $Panel
@onready var vbox: VBoxContainer = $Panel/VBox
@onready var text: RichTextLabel = $Panel/VBox/Text
@onready var choices: VBoxContainer = $Panel/VBox/Choices
@onready var next_hint: Label = $Panel/VBox/NextHint
@onready var nameplate: GensokyoNameplate = $Nameplate
@onready var ornament: GensokyoOrnament = $Ornament

var _layout_queued := false
var _enter_tw: Tween = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	panel.minimum_size_changed.connect(_queue_layout)
	vbox.minimum_size_changed.connect(_queue_layout)
	text.minimum_size_changed.connect(_queue_layout)
	get_viewport().size_changed.connect(_on_viewport_resized)
	resized.connect(_queue_layout)
	_apply_scale()
	_layout()


func _on_viewport_resized() -> void:
	_apply_scale()
	_queue_layout()


## 字級、邊距依 GensokyoStyle（解析度 × ui_scale × font_scale）。
func _apply_scale() -> void:
	var st := GensokyoStyle.current()
	var k := st.scale_for(self)
	text.add_theme_font_size_override("normal_font_size", st.font_px(self, dialogue_size))
	text.add_theme_font_size_override("bold_font_size", st.font_px(self, dialogue_size))
	text.add_theme_constant_override("line_separation", int(round(dialogue_size * 0.35 * k * st.font_scale)))
	next_hint.add_theme_font_size_override("font_size", st.font_px(self, 15))
	panel.add_theme_constant_override("margin_left", int(52 * k))
	panel.add_theme_constant_override("margin_right", int(46 * k))
	panel.add_theme_constant_override("margin_top", int(40 * k))   # 名牌壓進來的空間
	panel.add_theme_constant_override("margin_bottom", int(20 * k))
	vbox.add_theme_constant_override("separation", int(8 * k))
	choices.add_theme_constant_override("separation", int(2 * k))
	nameplate._relayout()
	ornament.queue_redraw()


func _queue_layout() -> void:
	if _layout_queued or not is_inside_tree():
		return
	_layout_queued = true
	_layout.call_deferred()


func _layout() -> void:
	_layout_queued = false
	if panel == null:
		return
	var st := GensokyoStyle.current()
	var k := st.scale_for(self)
	var vp := size if size.x > 1.0 else get_viewport_rect().size
	var w := vp.x * width_ratio
	# 先定寬，文字依寬換行後才知道要多高
	panel.size = Vector2(w, panel.size.y)
	var need := panel.get_combined_minimum_size().y
	var h := maxf(min_height * k, need)
	panel.position = Vector2((vp.x - w) * 0.5, vp.y - bottom_margin * k - h)
	panel.size = Vector2(w, h)
	nameplate.position = panel.position + Vector2(nameplate_offset_x * k, -nameplate.size.y * 0.52)
	ornament.position = panel.position
	ornament.size = panel.size


## 換行 / 換說話者。portrait_key：smile / serious / … 只改名牌小飾。
func set_speaker(speaker: String, portrait_key: String) -> void:
	var changed := nameplate.speaker != speaker
	nameplate.speaker = speaker
	nameplate.visible = not speaker.is_empty()
	nameplate.emotion = GensokyoNameplate.emotion_from_portrait(portrait_key)
	_queue_layout()
	if changed and is_visible_in_tree():
		var st := GensokyoStyle.current()
		nameplate.modulate.a = 0.0
		var tw := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(nameplate, "modulate:a", 1.0, st.dur())


## 對話開啟：墨水暈開（0.22 s）＋整體淡入、微幅上滑。
func play_enter() -> void:
	var st := GensokyoStyle.current()
	var k := st.scale_for(self)
	_layout()
	if _enter_tw != null:
		_enter_tw.kill()
	panel.ink_reveal()
	modulate.a = 0.0
	var y0 := position.y
	position.y = y0 + 8.0 * k
	_enter_tw = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_enter_tw.tween_property(self, "modulate:a", 1.0, st.dur(st.dialogue_reveal_duration))
	_enter_tw.parallel().tween_property(self, "position:y", y0, st.dur(st.dialogue_reveal_duration))

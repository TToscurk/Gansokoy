@tool
extends Button
class_name GensokyoButton
## 紙片按鈕：沒有矩形底框。
##   平時：只有字＋左側一截淡墨筆觸。
##   hover／selected：淡朱紅內暈 + 紙張浮起 2px + 左側小日輪緩慢呼吸（不是霓虹發光）。
## 對話選項、選單都用它；外觀全從 GensokyoStyle 取。

@export var selected := false:
	set(v):
		if selected == v:
			return
		selected = v
		_animate_lift()
		queue_redraw()
## 字級基準（1080p）；實際依 GensokyoStyle 縮放。
@export var base_font_size := 23.0:
	set(v):
		base_font_size = v
		_apply_scale()
@export var seed := 5.0

var _lift := 0.0
var _hover := false
var _t := 0.0
var _tw: Tween = null


func _init() -> void:
	flat = false
	focus_mode = Control.FOCUS_NONE
	alignment = HORIZONTAL_ALIGNMENT_LEFT


func _ready() -> void:
	if theme_type_variation == &"":
		theme_type_variation = &"GensokyoChoice"
	mouse_entered.connect(func() -> void:
		_hover = true
		_animate_lift())
	mouse_exited.connect(func() -> void:
		_hover = false
		_animate_lift())
	_apply_scale()


func _apply_scale() -> void:
	if not is_inside_tree():
		return
	var st := GensokyoStyle.current()
	add_theme_font_size_override("font_size", st.font_px(self, base_font_size))


func _active() -> bool:
	return selected or _hover


func _animate_lift() -> void:
	if not is_inside_tree():
		return
	var st := GensokyoStyle.current()
	if _tw != null:
		_tw.kill()
	_tw = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tw.tween_property(self, "_lift", 1.0 if _active() else 0.0, st.dur())
	_tw.parallel().tween_method(func(_v: float) -> void: queue_redraw(), 0.0, 1.0, st.dur())
	# 字色：選中＝暗朱
	if _active():
		add_theme_color_override("font_color", st.accent(st.dark_vermilion))
	else:
		remove_theme_color_override("font_color")


func _process(delta: float) -> void:
	if _lift > 0.01:
		_t += delta * GensokyoStyle.current().animation_speed
		queue_redraw()


func _draw() -> void:
	var st := GensokyoStyle.current()
	var k := st.scale_for(self)
	var h := size.y
	var lift := _lift * 2.0 * k
	# 紙張浮起：內容往上 lift，底下留一條極淡的影
	if _lift > 0.01:
		var glow := Color(st.dark_vermilion, 0.10 * _lift * st.accent_red_strength)
		var r := Rect2(Vector2(18.0 * k, 2.0 * k - lift), Vector2(size.x - 18.0 * k, h - 4.0 * k))
		GensokyoInk.stroke(self, r, glow, seed, 2.0 * k, 1.0, 0.2, 0.7)
		draw_line(Vector2(22.0 * k, h - 1.0 * k), Vector2(size.x * 0.7, h - 0.5 * k), Color(st.ink_black, 0.10 * _lift), 1.0)
	# 左側記號：平時淡墨點，選中時小日輪呼吸
	var c := Vector2(14.0 * k, h * 0.5 - lift)
	if _lift > 0.01:
		var breath := 0.5 + 0.5 * sin(_t * 2.2)
		GensokyoInk.sun(self, c, 4.2 * k, st.accent(st.sun_accent), Color(st.accent(st.dark_vermilion), 0.85 * _lift), breath * _lift, 10)
	else:
		draw_circle(c, 2.4 * k, Color(st.ink_grey, 0.7))


func _notification(what: int) -> void:
	# 不能接 THEME_CHANGED：add_theme_*_override 本身會發 THEME_CHANGED → 無限遞迴。
	if what == NOTIFICATION_ENTER_TREE:
		_apply_scale()

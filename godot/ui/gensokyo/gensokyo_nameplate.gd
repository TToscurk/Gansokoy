@tool
extends Control
class_name GensokyoNameplate
## 說話者名牌：漆器底的斜切木牌，壓在對話框上緣（overlap_border）。
## 左端一小截日之呼吸紅；emotion 只輕微改變右端的小飾（不改整個框）。

enum Emotion { NORMAL, SMILE, SERIOUS, SAD, SURPRISED, ANNOYED }

@export var speaker := "":
	set(v):
		speaker = v
		_relayout()
@export var emotion: Emotion = Emotion.NORMAL:
	set(v):
		emotion = v
		queue_redraw()
@export var seed := 3.0

var _label: Label = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_label = Label.new()
	_label.theme_type_variation = &"GensokyoSpeaker"
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	_relayout()


static func emotion_from_portrait(key: String) -> Emotion:
	match key:
		"smile":
			return Emotion.SMILE
		"serious":
			return Emotion.SERIOUS
		"sad", "scared":
			return Emotion.SAD
		"surprised", "confused":
			return Emotion.SURPRISED
		"annoyed":
			return Emotion.ANNOYED
	return Emotion.NORMAL


func _relayout() -> void:
	if _label == null:
		return
	var st := GensokyoStyle.current()
	var k := st.scale_for(self)
	_label.text = speaker
	_label.add_theme_font_size_override("font_size", st.font_px(self, 28))
	var tw := _label.get_minimum_size()
	var pad_l := 26.0 * k
	var pad_r := 38.0 * k
	custom_minimum_size = Vector2(tw.x + pad_l + pad_r, maxf(tw.y + 10.0 * k, 46.0 * k))
	size = custom_minimum_size
	_label.position = Vector2(pad_l, (size.y - tw.y) * 0.5 - 1.0 * k)
	_label.size = tw
	queue_redraw()


func _draw() -> void:
	if speaker.is_empty():
		return
	var st := GensokyoStyle.current()
	var k := st.scale_for(self)
	var w := size.x
	var h := size.y
	var sl := h * 0.32   # 斜切
	# 漆牌：左下、右上斜切（不對稱）
	var body := PackedVector2Array([
		Vector2(0, 0), Vector2(w - sl, 0), Vector2(w, h * 0.5), Vector2(w - sl * 0.6, h),
		Vector2(sl * 0.5, h)])
	draw_colored_polygon(body, Color(st.lacquer, 0.96))
	# 漆面的一條高光（舊金，極淡）
	draw_line(Vector2(sl * 0.4, 2.0 * k), Vector2(w - sl * 1.1, 2.0 * k), Color(st.old_gold, 0.35), 1.0, true)
	# 底緣暗金細線（只到 70%）
	draw_line(Vector2(sl * 0.5, h - 1.0), Vector2(w * 0.7, h - 1.0), Color(st.old_gold, 0.55), 1.2 * k, true)
	# 日之呼吸紅：左端一截筆觸
	var red := st.accent(st.sun_accent)
	var bar := Rect2(Vector2(5.0 * k, h * 0.22), Vector2(7.0 * k, h * 0.56))
	draw_colored_polygon(PackedVector2Array([
		bar.position + Vector2(1.5 * k, 0), bar.position + Vector2(bar.size.x, 1.0 * k),
		bar.end - Vector2(0.5 * k, 0), bar.position + Vector2(0, bar.size.y - 2.0 * k)]), red)
	# 情緒小飾：右端（只改這一點）
	var c := Vector2(w - sl * 0.95, h * 0.5)
	var r := 4.5 * k
	match emotion:
		Emotion.SMILE:
			GensokyoInk.maple(self, c, r * 1.5, 0.3, st.accent(st.dark_vermilion))
		Emotion.SERIOUS:
			draw_line(c + Vector2(-r, 0), c + Vector2(r, 0), st.old_gold, 1.6 * k, true)
		Emotion.SAD:
			draw_circle(c + Vector2(0, r * 0.3), r * 0.55, Color(st.spirit_blue, 0.85))
			draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.45, r * 0.1), c + Vector2(0, -r * 0.9), c + Vector2(r * 0.45, r * 0.1)]), Color(st.spirit_blue, 0.85))
		Emotion.SURPRISED:
			GensokyoInk.enso(self, c, r, 1.4 * k, st.old_gold, seed, 1.0, 0.25)
		Emotion.ANNOYED:
			draw_line(c + Vector2(-r, -r * 0.6), c + Vector2(r, r * 0.6), st.accent(st.dark_vermilion), 1.8 * k, true)
			draw_line(c + Vector2(-r, r * 0.6), c + Vector2(r, -r * 0.6), st.accent(st.dark_vermilion), 1.8 * k, true)
		_:
			draw_circle(c, r * 0.45, Color(st.old_gold, 0.8))

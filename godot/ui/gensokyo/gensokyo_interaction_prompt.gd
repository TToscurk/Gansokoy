extends Label
class_name GensokyoInteractionPrompt
## 互動提示（規格：極低存在感，只有 Key Icon + Action Text，不要大型 Panel）。
##
## 刻意仍是 Label：main.gd 與驗證腳本只認 .text / .visible，介面不變。
## Label 本身的字設成透明，改由子節點畫「墨框鍵帽 + 動作字」；
## 文字格式沿用 world_interaction.prompt_text()：
##   "[E] 拜訪"  或  "博麗神社\n[E] 拜訪"（第一行 = 地名，小字淡墨）。

@export var base_font_size := 21.0
@export var key_size := 26.0

var _last := "<unset>"
var _col: VBoxContainer
var _row: HBoxContainer
var _key: Control
var _key_text := ""
var _action: Label
var _place: Label
var _tw: Tween = null


func _ready() -> void:
	theme = GensokyoStyle.theme()
	add_theme_color_override("font_color", Color(0, 0, 0, 0))
	add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	add_theme_color_override("font_outline_color", Color(0, 0, 0, 0))
	add_theme_constant_override("outline_size", 0)
	clip_text = false
	# 地名一行 + 「鍵帽 動作」一行，用容器疊，不手算 y（手算時地名會壓到鍵帽上）
	_col = VBoxContainer.new()
	_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_col.alignment = BoxContainer.ALIGNMENT_END
	add_child(_col)
	_place = Label.new()
	_place.theme_type_variation = &"GensokyoHudText"
	_place.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_col.add_child(_place)
	_row = HBoxContainer.new()
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_col.add_child(_row)
	_key = Control.new()
	_key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_key.draw.connect(_draw_key)
	_row.add_child(_key)
	_action = Label.new()
	_action.theme_type_variation = &"GensokyoPrompt"
	_action.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_child(_action)
	visibility_changed.connect(_on_visibility)
	get_viewport().size_changed.connect(func() -> void: _rebuild(true))
	_rebuild(true)


func _process(_delta: float) -> void:
	if visible and text != _last:
		_rebuild(false)


static func parse(t: String) -> Dictionary:
	var lines := t.strip_edges().split("\n")
	var last := lines[lines.size() - 1].strip_edges() if lines.size() > 0 else ""
	var place := "\n".join(lines.slice(0, lines.size() - 1)).strip_edges() if lines.size() > 1 else ""
	var key := ""
	var action := last
	var re := RegEx.create_from_string("^\\[([^\\]]+)\\]\\s*(.*)$")
	var m := re.search(last)
	if m != null:
		key = m.get_string(1)
		action = m.get_string(2)
	else:
		var re2 := RegEx.create_from_string("^([A-Za-z0-9])\\s*[：:]\\s*(.*)$")
		var m2 := re2.search(last)
		if m2 != null:
			key = m2.get_string(1)
			action = m2.get_string(2)
	return {"place": place, "key": key, "action": action}


func _rebuild(force: bool) -> void:
	if _row == null or (not force and text == _last):
		return
	_last = text
	var st := GensokyoStyle.current()
	var k := st.scale_for(self)
	var p := parse(text)
	_key_text = String(p.key)
	_place.text = String(p.place)
	_place.visible = not _place.text.is_empty()
	_place.add_theme_font_size_override("font_size", st.font_px(self, 15))
	_place.modulate.a = 0.75
	_action.text = String(p.action)
	_action.add_theme_font_size_override("font_size", st.font_px(self, base_font_size))
	_key.visible = not _key_text.is_empty()
	_key.custom_minimum_size = Vector2(key_size, key_size) * k * st.font_scale
	_row.add_theme_constant_override("separation", int(10 * k))
	_col.add_theme_constant_override("separation", int(2 * k))
	_col.size = Vector2.ZERO
	var cs := _col.get_combined_minimum_size()
	_col.size = cs
	# 底邊對齊 Label 底邊、水平置中；多出的高度往上長
	_col.position = Vector2((size.x - cs.x) * 0.5, size.y - cs.y)
	_key.queue_redraw()
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _row != null:
		_rebuild(true)


func _draw() -> void:
	if _row == null or not visible:
		return
	# 讀字用的淡墨暈（不是面板）：一條低透明筆觸墊在字下
	var st := GensokyoStyle.current()
	var k := st.scale_for(self)
	var rp := _col.position + _row.position
	var r := Rect2(rp + Vector2(-14.0 * k, _row.size.y * 0.12), Vector2(_row.size.x + 34.0 * k, _row.size.y * 0.8))
	GensokyoInk.stroke(self, r, Color(st.ink_black, st.hud_background * 0.42), 4.2, 3.0 * k, 1.0, 0.5, 0.95)


func _draw_key() -> void:
	var st := GensokyoStyle.current()
	var s := _key.size
	var r := Rect2(Vector2(1, 1), s - Vector2(2, 2))
	GensokyoInk.keycap(_key, r, st.ink_black, Color(st.washi_ivory, 0.94), 2.0)
	var font := get_theme_default_font()
	var fs := int(s.y * 0.62)
	var tw := font.get_string_size(_key_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	_key.draw_string(font, Vector2((s.x - tw.x) * 0.5, s.y * 0.5 + fs * 0.36), _key_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, st.text_ink)


func _on_visibility() -> void:
	if not visible:
		return
	_rebuild(true)
	var st := GensokyoStyle.current()
	if _tw != null:
		_tw.kill()
	modulate.a = 0.0
	_col.position.y += 4.0
	_tw = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tw.tween_property(self, "modulate:a", 1.0, st.dur())
	_tw.parallel().tween_property(_col, "position:y", _col.position.y - 4.0, st.dur())

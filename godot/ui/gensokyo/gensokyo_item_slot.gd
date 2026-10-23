@tool
extends Control
class_name GensokyoItemSlot
## 快捷列的一格。形狀三選一（規格 HOTBAR：御札、木牌、刀鍔構成 Slot）：
##   OFUDA 直式御札（紙）  WOOD 木牌（繪馬形）  TSUBA 刀鍔（圓）
## selected：淡朱紅內光 + 紙張浮起 2px + 小型日輪呼吸（不是 Neon Glow）。
## cooldown 0..1：墨從上往下退（冷卻中）；locked：整格墨灰。

enum Shape { OFUDA, WOOD, TSUBA }

@export var shape: Shape = Shape.OFUDA:
	set(v):
		shape = v
		queue_redraw()
@export var key_label := "C":
	set(v):
		key_label = v
		queue_redraw()
## 格內主字（一到兩字，直書）。
@export var glyph := "日":
	set(v):
		glyph = v
		queue_redraw()
@export var tip := "":
	set(v):
		tip = v
		tooltip_text = v
@export var selected := false:
	set(v):
		if selected == v:
			return
		selected = v
		_tween_lift()
@export_range(0.0, 1.0, 0.01) var cooldown := 0.0:
	set(v):
		cooldown = v
		queue_redraw()
@export var locked := false:
	set(v):
		locked = v
		queue_redraw()
@export var seed := 1.0

var _lift := 0.0
var _t := 0.0
var _tw: Tween = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS


func _ready() -> void:
	tooltip_text = tip


func _make_custom_tooltip(for_text: String) -> Object:
	return GensokyoTooltip.make(for_text)


func _tween_lift() -> void:
	if not is_inside_tree():
		_lift = 1.0 if selected else 0.0
		return
	if _tw != null:
		_tw.kill()
	_tw = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tw.tween_property(self, "_lift", 1.0 if selected else 0.0, GensokyoStyle.current().dur())


func _process(delta: float) -> void:
	_t += delta * GensokyoStyle.current().animation_speed
	if _lift > 0.001 or _tw != null and _tw.is_running():
		queue_redraw()


func _draw() -> void:
	var st := GensokyoStyle.current()
	var k := st.scale_for(self)
	var lift := _lift * 2.0 * k
	var s := size
	var c := s * 0.5 - Vector2(0, lift)
	var dim := 0.45 if locked else 1.0
	# 浮起的影
	if _lift > 0.01:
		draw_set_transform(Vector2(0, 2.0 * k), 0, Vector2.ONE)
		_shape_poly(s, Color(st.ink_black, 0.25 * _lift))
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	draw_set_transform(Vector2(0, -lift), 0, Vector2.ONE)
	match shape:
		Shape.OFUDA:
			_shape_poly(s, Color(st.washi_ivory, 0.9 * dim))
			# 御札：上緣朱色一截（紅不過 10%）
			draw_rect(Rect2(Vector2(s.x * 0.18, s.y * 0.07), Vector2(s.x * 0.64, s.y * 0.06)), st.accent(st.dark_vermilion) * Color(1, 1, 1, dim))
			draw_line(Vector2(s.x * 0.12, s.y * 0.03), Vector2(s.x * 0.12, s.y * 0.97), Color(st.ink_black, 0.35), 1.0)
		Shape.WOOD:
			_shape_poly(s, Color("#5A3E2B") * Color(1, 1, 1, 0.92 * dim))
			for g in 3:
				var y := s.y * (0.35 + 0.18 * g)
				draw_line(Vector2(s.x * 0.12, y), Vector2(s.x * 0.88, y + 1.0 * k), Color("#3C2819", 0.55), 1.0, true)
			draw_circle(Vector2(s.x * 0.5, s.y * 0.13), 2.0 * k, Color(st.old_gold, 0.8))
		Shape.TSUBA:
			GensokyoInk.tsuba(self, s * 0.5, minf(s.x, s.y) * 0.46, Color("#2A2522") * Color(1, 1, 1, 0.95 * dim), Color(st.ink_black, 0.0))
			draw_arc(s * 0.5, minf(s.x, s.y) * 0.44, 0, TAU, 40, Color(st.old_gold, 0.55 * dim), 1.2 * k, true)
	# 墨框：手繪、不對稱
	_shape_outline(s, Color(st.ink_black, 0.85 * dim), k)
	# 淡朱紅內光（selected）
	if _lift > 0.01:
		var br := 0.55 + 0.45 * sin(_t * 2.0)
		for g in 3:
			_shape_outline_inset(s, Color(st.dark_vermilion, 0.16 * _lift * (3 - g) / 3.0 * st.accent_red_strength), k, (2.0 + g * 2.0) * k)
		GensokyoInk.sun(self, Vector2(s.x - 6.0 * k, 6.0 * k), 3.6 * k, st.accent(st.sun_accent),
			Color(st.accent(st.dark_vermilion), 0.85 * _lift), br * _lift, 10)
	# 主字（直書）
	var font := get_theme_default_font()
	var dark_face := shape != Shape.OFUDA
	var ink := st.washi_ivory if dark_face else st.text_ink
	if locked:
		ink = st.ink_grey
	var fs := int(minf(s.x * 0.5, s.y * 0.30))
	var chars := glyph.split("")
	var total_h := fs * chars.size()
	var y0 := (s.y - total_h) * 0.5 + fs * 0.86
	for i in chars.size():
		var gw := font.get_string_size(chars[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2((s.x - gw) * 0.5, y0 + fs * i), chars[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
	# 冷卻：墨由上往下退
	if cooldown > 0.001:
		draw_rect(Rect2(Vector2(1, 1), Vector2(s.x - 2, (s.y - 2) * cooldown)), Color(st.ink_black, 0.55))
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	# 鍵位：格子左下，極小鍵帽
	var kr := Rect2(Vector2(-4.0 * k, s.y - 11.0 * k), Vector2(15.0, 15.0) * k)
	GensokyoInk.keycap(self, kr, Color(st.ink_black, 0.9), Color(st.washi_ivory, 0.92), seed)
	var kfs := int(11 * k)
	var kw := font.get_string_size(key_label, HORIZONTAL_ALIGNMENT_LEFT, -1, kfs).x
	draw_string(font, Vector2(kr.position.x + (kr.size.x - kw) * 0.5, kr.position.y + kr.size.y * 0.5 + kfs * 0.36),
		key_label, HORIZONTAL_ALIGNMENT_LEFT, -1, kfs, st.text_ink)


func _shape_points(s: Vector2, inset := 0.0) -> PackedVector2Array:
	match shape:
		Shape.WOOD:
			# 繪馬形：五角（上方屋頂）
			return PackedVector2Array([
				Vector2(inset, s.y * 0.2 + inset * 0.5), Vector2(s.x * 0.5, inset), Vector2(s.x - inset, s.y * 0.2 + inset * 0.5),
				Vector2(s.x - inset, s.y - inset), Vector2(inset, s.y - inset)])
		Shape.TSUBA:
			var pts := PackedVector2Array()
			var r := minf(s.x, s.y) * 0.46 - inset
			for i in 40:
				var a := TAU * i / 40.0
				pts.append(s * 0.5 + Vector2(cos(a), sin(a)) * r * (0.88 + 0.12 * absf(cos(2.0 * a))))
			return pts
	# 御札：略不規則的直長方
	return PackedVector2Array([
		Vector2(inset + 1.0, inset), Vector2(s.x - inset, inset + 1.5), Vector2(s.x - inset - 0.5, s.y - inset),
		Vector2(inset, s.y - inset - 1.0)])


func _shape_poly(s: Vector2, col: Color) -> void:
	draw_colored_polygon(_shape_points(s), col)


func _shape_outline(s: Vector2, col: Color, k: float) -> void:
	var pts := _shape_points(s)
	var n := pts.size()
	for i in n:
		# 右、下邊粗，左、上邊細（筆壓）
		var a := pts[i]
		var b := pts[(i + 1) % n]
		var w := 1.1 if (b - a).x > 0.0 and absf((b - a).y) < absf((b - a).x) else 1.9
		draw_line(a, b, col, w * k, true)


func _shape_outline_inset(s: Vector2, col: Color, k: float, inset: float) -> void:
	var pts := _shape_points(s, inset)
	pts.append(pts[0])
	draw_polyline(pts, col, 2.0 * k, true)

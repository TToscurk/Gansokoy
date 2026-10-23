@tool
extends Control
class_name GensokyoOrnament
## 面板角落的稀疏裝飾（規格 decoration_density 0.20–0.30）：
##   左下：紅楓 ＋ 細繩結（掛在紙外）   右上：紙垂（御幣白紙）
## 左右刻意不對稱。數量由 GensokyoStyle.ornament_density 決定，0 = 全不畫。

@export var left_maple := true
@export var left_cord := true
@export var right_shide := true
@export var seed := 11.0
## 對話框在 Important 時可以換一片彼岸花（目前沒有資料欄位，保留開關）。
@export var higanbana := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var st := GensokyoStyle.current()
	var dens := st.ornament_density
	if dens <= 0.01:
		return
	var k := st.scale_for(self)
	var w := size.x
	var h := size.y
	# 右上：細注連繩斜掛過紙角，垂一條紙垂（密度高才兩條）—— 神社元素只佔一角
	if right_shide and dens >= 0.1:
		var x := w - 70.0 * k
		var y := -2.0 * k
		draw_line(Vector2(x - 30.0 * k, y - 3.0 * k), Vector2(w + 6.0 * k, y + 12.0 * k), Color(st.ink_black, 0.8), 2.4 * k, true)
		GensokyoInk.shide(self, Vector2(x - 2.0 * k, y + 1.0 * k), 46.0 * k, 16.0 * k, Color("#F7F3EA"), Color(st.ink_black, 0.45))
		if dens >= 0.35:
			GensokyoInk.shide(self, Vector2(x + 30.0 * k, y + 8.0 * k), 34.0 * k, 13.0 * k, Color("#F7F3EA"), Color(st.ink_black, 0.4))
	# 左下：楓葉壓在紙角上，繩結從紙角垂下一小段（不飄在紙外）
	if left_cord and dens >= 0.15:
		GensokyoInk.cord(self, Vector2(34.0 * k, h - 3.0 * k), 34.0 * k, st.accent(st.dark_vermilion), st.old_gold, seed)
	if left_maple and dens >= 0.2:
		GensokyoInk.maple(self, Vector2(14.0 * k, h - 14.0 * k), 14.0 * k, -0.55, st.accent(st.dark_vermilion))
		if dens >= 0.5:
			GensokyoInk.maple(self, Vector2(40.0 * k, h - 6.0 * k), 9.0 * k, 0.9, Color(st.accent(st.sun_accent), 0.85))
	if higanbana:
		_higanbana(Vector2(w - 20.0 * k, h - 6.0 * k), 12.0 * k, st.accent(st.dark_vermilion))


func _higanbana(c: Vector2, r: float, col: Color) -> void:
	# 彼岸花：六條反捲細瓣 + 長蕊
	for i in 6:
		var a := -PI * 0.5 + (i - 2.5) * 0.42
		var d := Vector2(cos(a), sin(a))
		var tip := c + d * r
		var ctrl := c + d * r * 0.6 + Vector2(-d.y, d.x) * r * 0.25
		draw_polyline(PackedVector2Array([c, ctrl, tip]), col, 1.6, true)
		draw_line(c, c + d * r * 1.5, Color(col, 0.7), 0.8, true)

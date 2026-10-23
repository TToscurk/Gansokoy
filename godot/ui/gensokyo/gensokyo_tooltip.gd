extends PanelContainer
class_name GensokyoTooltip
## 提示框：墨底、2px 角、暗金細線（UITheme_Gensokyo 的 TooltipPanel）。
## 用法：Control._make_custom_tooltip(t) 回傳 GensokyoTooltip.make(t)。
## 第一行可當標題（暗金），其餘內文象牙白。


static func make(text: String) -> GensokyoTooltip:
	var tt := GensokyoTooltip.new()
	tt.theme = GensokyoStyle.theme()
	var st := GensokyoStyle.current()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	tt.add_child(vb)
	var lines := text.split("\n", false, 1)
	var head := Label.new()
	head.text = lines[0] if lines.size() > 0 else ""
	head.add_theme_color_override("font_color", st.old_gold.lightened(0.15))
	head.add_theme_constant_override("outline_size", 0)
	head.add_theme_font_size_override("font_size", 17)
	vb.add_child(head)
	if lines.size() > 1:
		var body := Label.new()
		body.text = lines[1]
		body.add_theme_color_override("font_color", st.washi_ivory)
		body.add_theme_constant_override("outline_size", 0)
		body.add_theme_font_size_override("font_size", 15)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.custom_minimum_size.x = 220
		vb.add_child(body)
	return tt


func _ready() -> void:
	add_theme_stylebox_override("panel", GensokyoStyle.theme().get_stylebox("panel", "TooltipPanel"))

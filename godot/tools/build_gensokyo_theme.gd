extends SceneTree
## 產生 res://ui/gensokyo/UITheme_Gensokyo.tres（從 GensokyoStyle 取色）。
##   <godot_console.exe> --headless --path godot --script res://tools/build_gensokyo_theme.gd
## 改色／改字重：改 gensokyo_style.tres 或這支，再跑一次。不要手改 .tres。
##
## 字型：Noto Serif TC（OFL，assets/fonts/）—— 明朝體有筆鋒，繁中＋假名全覆蓋。
## 字級是 1080p 基準；各元件在執行期依 GensokyoStyle.scale_for() 覆寫實際大小。

const FONT_PATH := "res://assets/fonts/NotoSerifTC-VF.ttf"
const OUT := "res://ui/gensokyo/UITheme_Gensokyo.tres"


func _init() -> void:
	var st: GensokyoStyle = load("res://ui/gensokyo/gensokyo_style.tres")
	var base: FontFile = load(FONT_PATH)
	if base == null:
		push_error("讀不到字型 %s（先跑一次 --import）" % FONT_PATH)
		quit(1)
		return

	var t := Theme.new()
	var body := _weight(base, 500)
	var strong := _weight(base, 700)
	var light := _weight(base, 400)
	t.default_font = body
	t.default_font_size = 22

	# --- 基底 Label：畫面上的字（HUD 類）一律象牙白＋墨描邊 -------------------
	t.set_color("font_color", "Label", st.washi_ivory)
	t.set_color("font_outline_color", "Label", Color(st.ink_black, 0.85))
	t.set_constant("outline_size", "Label", 4)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0))

	# --- 對話 ---------------------------------------------------------------
	_variation(t, "GensokyoSpeaker", "Label")
	t.set_font("font", "GensokyoSpeaker", strong)
	t.set_font_size("font_size", "GensokyoSpeaker", 28)
	t.set_color("font_color", "GensokyoSpeaker", st.washi_ivory)
	t.set_color("font_outline_color", "GensokyoSpeaker", Color(0, 0, 0, 0))
	t.set_constant("outline_size", "GensokyoSpeaker", 0)

	_variation(t, "GensokyoDialogueText", "RichTextLabel")
	t.set_font("normal_font", "GensokyoDialogueText", body)
	t.set_font("bold_font", "GensokyoDialogueText", strong)
	t.set_font_size("normal_font_size", "GensokyoDialogueText", 25)
	t.set_font_size("bold_font_size", "GensokyoDialogueText", 25)
	t.set_color("default_color", "GensokyoDialogueText", st.text_ink)
	t.set_constant("line_separation", "GensokyoDialogueText", 9)   # 25 px × 0.35 ≈ 1.35 行距
	t.set_constant("outline_size", "GensokyoDialogueText", 0)

	_variation(t, "GensokyoChoice", "Button")
	for s in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		var sb := StyleBoxEmpty.new()
		sb.content_margin_left = 34.0
		sb.content_margin_right = 12.0
		sb.content_margin_top = 4.0
		sb.content_margin_bottom = 4.0
		t.set_stylebox(s, "GensokyoChoice", sb)
	t.set_font("font", "GensokyoChoice", body)
	t.set_font_size("font_size", "GensokyoChoice", 23)
	t.set_color("font_color", "GensokyoChoice", st.text_ink.lerp(st.washi_ivory, 0.25))
	t.set_color("font_hover_color", "GensokyoChoice", st.dark_vermilion)
	t.set_color("font_pressed_color", "GensokyoChoice", st.dark_vermilion.darkened(0.2))
	t.set_color("font_focus_color", "GensokyoChoice", st.dark_vermilion)
	t.set_color("font_hover_pressed_color", "GensokyoChoice", st.dark_vermilion)

	_variation(t, "GensokyoHint", "Label")
	t.set_font("font", "GensokyoHint", light)
	t.set_font_size("font_size", "GensokyoHint", 15)
	t.set_color("font_color", "GensokyoHint", st.ink_grey)
	t.set_constant("outline_size", "GensokyoHint", 0)

	# --- 任務 ---------------------------------------------------------------
	_variation(t, "GensokyoQuestText", "Label")
	t.set_font("font", "GensokyoQuestText", body)
	t.set_font_size("font_size", "GensokyoQuestText", 18)
	t.set_color("font_color", "GensokyoQuestText", st.text_ink)
	t.set_constant("outline_size", "GensokyoQuestText", 0)
	t.set_constant("line_spacing", "GensokyoQuestText", 4)

	_variation(t, "GensokyoBannerHead", "Label")
	t.set_font("font", "GensokyoBannerHead", light)
	t.set_font_size("font_size", "GensokyoBannerHead", 16)
	t.set_color("font_color", "GensokyoBannerHead", st.dark_vermilion)
	t.set_constant("outline_size", "GensokyoBannerHead", 0)

	_variation(t, "GensokyoBannerTitle", "Label")
	t.set_font("font", "GensokyoBannerTitle", strong)
	t.set_font_size("font_size", "GensokyoBannerTitle", 30)
	t.set_color("font_color", "GensokyoBannerTitle", st.text_ink)
	t.set_constant("outline_size", "GensokyoBannerTitle", 0)

	# --- HUD／提示 -----------------------------------------------------------
	_variation(t, "GensokyoHudText", "Label")
	t.set_font("font", "GensokyoHudText", strong)
	t.set_font_size("font_size", "GensokyoHudText", 15)
	t.set_color("font_color", "GensokyoHudText", st.washi_ivory)
	t.set_color("font_outline_color", "GensokyoHudText", Color(st.ink_black, 0.9))
	t.set_constant("outline_size", "GensokyoHudText", 4)

	_variation(t, "GensokyoPrompt", "Label")
	t.set_font("font", "GensokyoPrompt", body)
	t.set_font_size("font_size", "GensokyoPrompt", 22)
	t.set_color("font_color", "GensokyoPrompt", st.washi_ivory)
	t.set_color("font_outline_color", "GensokyoPrompt", Color(st.ink_black, 0.85))
	t.set_constant("outline_size", "GensokyoPrompt", 5)

	# --- Button（GensokyoButton 自繪底，這裡只管字）---------------------------
	for s in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		var sb := StyleBoxEmpty.new()
		sb.content_margin_left = 22.0
		sb.content_margin_right = 22.0
		sb.content_margin_top = 8.0
		sb.content_margin_bottom = 8.0
		t.set_stylebox(s, "Button", sb)
	t.set_color("font_color", "Button", st.text_ink)
	t.set_color("font_hover_color", "Button", st.dark_vermilion)
	t.set_color("font_pressed_color", "Button", st.dark_vermilion.darkened(0.2))
	t.set_color("font_focus_color", "Button", st.text_ink)
	t.set_color("font_disabled_color", "Button", st.ink_grey)

	# --- Tooltip：墨底、2px 角、暗金細線（不是發光框）-------------------------
	var tip := StyleBoxFlat.new()
	tip.bg_color = Color(st.ink_black, 0.92)
	tip.border_color = Color(st.old_gold, 0.55)
	tip.border_width_bottom = 1
	tip.border_width_left = 2
	tip.corner_radius_top_left = 2
	tip.corner_radius_top_right = 2
	tip.corner_radius_bottom_left = 2
	tip.corner_radius_bottom_right = 2
	tip.content_margin_left = 12.0
	tip.content_margin_right = 14.0
	tip.content_margin_top = 6.0
	tip.content_margin_bottom = 7.0
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", st.washi_ivory)
	t.set_font_size("font_size", "TooltipLabel", 17)

	var err := ResourceSaver.save(t, OUT)
	print("[THEME] 寫出 %s err=%d" % [OUT, err])
	quit(err)


func _weight(base: FontFile, w: int) -> FontVariation:
	var fv := FontVariation.new()
	fv.base_font = base
	fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): w}
	return fv


func _variation(t: Theme, name: String, base_type: String) -> void:
	t.add_type(name)
	t.set_type_variation(name, base_type)

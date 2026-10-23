extends Resource
class_name GensokyoStyle
## 「幻想鄉 × 緣一」UI 統一參數。所有 Gensokyo* 元件只從這裡取色、取尺寸、取速度。
## 實例 = res://ui/gensokyo/gensokyo_style.tres（改這一份，全部元件跟著變）。
##
## 紅色是辨識色不是主色：accent 相關面積由各元件控制在 10–15% 以下。

const STYLE_PATH := "res://ui/gensokyo/gensokyo_style.tres"
const THEME_PATH := "res://ui/gensokyo/UITheme_Gensokyo.tres"

@export_group("Global")
## 整體 UI 縮放（乘在自動解析度縮放上）。
@export_range(0.5, 2.0, 0.05) var ui_scale := 1.0
## 以 1080p 為基準，依視窗高度自動縮放（2560x1440 → 1.33）。
@export var auto_resolution_scale := true
## 只縮字（在 ui_scale 之上）。
@export_range(0.6, 1.6, 0.05) var font_scale := 1.0
## 動畫速度倍率；2 = 快一倍。
@export_range(0.25, 3.0, 0.05) var animation_speed := 1.0

@export_group("Material")
## 面板底（和紙）不透明度的全域倍率；各元件另有自己的基準值。
@export_range(0.0, 1.0, 0.01) var panel_opacity := 1.0
## 和紙纖維／紙紋強度。
@export_range(0.0, 2.0, 0.05) var paper_texture_strength := 1.0
## 墨框濃度。
@export_range(0.0, 2.0, 0.05) var ink_edge_strength := 1.0
## 朱色點綴強度（0 = 全部改墨色）。
@export_range(0.0, 1.5, 0.05) var accent_red_strength := 1.0
## 裝飾密度 0..1（楓葉、繩結、紙垂、日輪）。0.25 = 規格值「稀疏」。
@export_range(0.0, 1.0, 0.05) var ornament_density := 0.25

@export_group("Palette")
@export var ink_black := Color("#171310")
@export var washi_ivory := Color("#E8DFCC")
@export var dark_vermilion := Color("#A72E2E")
@export var old_gold := Color("#B58A4A")
@export var sun_accent := Color("#D85A38")
@export var spirit_blue := Color("#A7C9D4")
## 和紙上的正文墨色（比 ink_black 暖一點，長時間閱讀不刺眼）。
@export var text_ink := Color("#2A211B")
## 漆器（名牌底）。
@export var lacquer := Color("#1E1714")
## 支線／次要資訊用的墨灰。
@export var ink_grey := Color("#6E655B")

@export_group("Opacity (spec)")
@export_range(0.0, 1.0, 0.01) var hud_background := 0.55
@export_range(0.0, 1.0, 0.01) var dialogue_background := 0.92
@export_range(0.0, 1.0, 0.01) var quest_background := 0.86

@export_group("Motion (spec)")
## 基本時長（秒）；實際 = base / animation_speed。
@export_range(0.05, 1.0, 0.01) var base_duration := 0.18
@export_range(0.05, 1.0, 0.01) var dialogue_reveal_duration := 0.22

static var _cached: GensokyoStyle = null
static var _theme: Theme = null


static func current() -> GensokyoStyle:
	if _cached == null:
		_cached = load(STYLE_PATH) as GensokyoStyle
		if _cached == null:
			_cached = GensokyoStyle.new()
	return _cached


static func theme() -> Theme:
	if _theme == null:
		_theme = load(THEME_PATH) as Theme
	return _theme


## 解析度 × ui_scale。node 必須在樹上。
func scale_for(node: Node) -> float:
	var s := ui_scale
	if auto_resolution_scale and node != null and node.is_inside_tree():
		var h := node.get_viewport().get_visible_rect().size.y
		s *= clampf(h / 1080.0, 0.75, 2.0)
	return s


func font_px(node: Node, base: float) -> int:
	return int(round(base * scale_for(node) * font_scale))


func dur(base: float = -1.0) -> float:
	return (base_duration if base < 0.0 else base) / maxf(animation_speed, 0.01)


## 朱色依 accent_red_strength 往墨色退。
func accent(c: Color) -> Color:
	var k := clampf(accent_red_strength, 0.0, 1.0)
	return ink_black.lerp(c, k)

@tool
extends MarginContainer
class_name GensokyoPanel
## 所有「紙」的共同底：和紙＋不規則毛筆墨框（gensokyo_paper.gdshader）。
## 子節點照 MarginContainer 排版；底紙畫在自己的 _draw，墨框可溢出矩形 bleed px。
##
## 每個用到它的元件應給不同 seed 與 border_sides —— 規格禁止「所有框同一套 NinePatch」。
## reveal（墨水暈開）與 burn（御札燃燒）給 Tween 驅動。

const SHADER := preload("res://ui/gensokyo/gensokyo_paper.gdshader")

enum Tone { WASHI, INK, LACQUER }

## 紙色：和紙（對話／任務）、墨（HUD 底暈）、漆（名牌）。
@export var tone: Tone = Tone.WASHI:
	set(v):
		tone = v
		_sync()
## 基準不透明度（乘上 GensokyoStyle.panel_opacity）。
@export_range(0.0, 1.0, 0.01) var base_opacity := 0.92:
	set(v):
		base_opacity = v
		_sync()
@export var seed := 0.0:
	set(v):
		seed = v
		_sync()
@export_range(0.5, 12.0, 0.1) var border_px := 3.0:
	set(v):
		border_px = v
		_sync()
@export_range(0.0, 1.5, 0.01) var irregularity := 0.55:
	set(v):
		irregularity = v
		_sync()
## 上、右、下、左 各邊墨線權重；不對稱是預設。
@export var border_sides := Vector4(1.0, 0.3, 0.85, 0.5):
	set(v):
		border_sides = v
		_sync()
@export_range(0.0, 1.0, 0.01) var taper := 0.6:
	set(v):
		taper = v
		_sync()
## 朱色筆段：-1 無、0 上、1 右、2 下、3 左。
@export_range(-1, 3) var accent_edge := 2:
	set(v):
		accent_edge = v
		_sync()
@export var accent_span := Vector2(0.80, 0.95):
	set(v):
		accent_span = v
		_sync()
@export_range(0.0, 40.0, 0.5) var soft_edge := 1.2:
	set(v):
		soft_edge = v
		_sync()
@export_range(0.0, 40.0, 0.5) var bleed := 14.0:
	set(v):
		bleed = v
		queue_redraw()
		_sync()
@export_range(0.0, 1.0, 0.01) var reveal := 1.0:
	set(v):
		reveal = v
		_sync_anim()
@export_range(0.0, 1.0, 0.01) var burn := 0.0:
	set(v):
		burn = v
		_sync_anim()
@export var reveal_origin := Vector2(0.08, 0.5):
	set(v):
		reveal_origin = v
		_sync_anim()

static var _white: Texture2D = null
var _mat: ShaderMaterial = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	material = _mat
	resized.connect(_sync)
	_sync()
	_sync_anim()


static func _white_tex() -> Texture2D:
	if _white == null:
		var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_white = ImageTexture.create_from_image(img)
	return _white


func _draw() -> void:
	var r := Rect2(Vector2(-bleed, -bleed), size + Vector2(bleed, bleed) * 2.0)
	draw_texture_rect(_white_tex(), r, false)


func _paper_color(st: GensokyoStyle) -> Color:
	match tone:
		Tone.INK:
			return st.ink_black
		Tone.LACQUER:
			return st.lacquer
	return st.washi_ivory


func _sync() -> void:
	if _mat == null:
		return
	var st := GensokyoStyle.current()
	var total := size + Vector2(bleed, bleed) * 2.0
	_mat.set_shader_parameter("rect_size", total)
	_mat.set_shader_parameter("bleed", bleed)
	_mat.set_shader_parameter("paper_color", _paper_color(st))
	var ink := st.ink_black
	if tone != Tone.WASHI:
		ink = st.old_gold.darkened(0.35)   # 深底上的框用暗金，才看得到
	_mat.set_shader_parameter("ink_color", ink)
	_mat.set_shader_parameter("accent_color", st.dark_vermilion)
	_mat.set_shader_parameter("ember_color", st.sun_accent)
	_mat.set_shader_parameter("opacity", base_opacity * st.panel_opacity)
	_mat.set_shader_parameter("paper_strength", st.paper_texture_strength * (0.5 if tone != Tone.WASHI else 1.0))
	_mat.set_shader_parameter("ink_strength", st.ink_edge_strength)
	_mat.set_shader_parameter("accent_strength", st.accent_red_strength)
	_mat.set_shader_parameter("border_px", border_px * st.scale_for(self) if is_inside_tree() else border_px)
	_mat.set_shader_parameter("irregularity", irregularity)
	_mat.set_shader_parameter("border_sides", border_sides)
	_mat.set_shader_parameter("taper", taper)
	_mat.set_shader_parameter("accent_edge", accent_edge)
	_mat.set_shader_parameter("accent_span", accent_span)
	_mat.set_shader_parameter("soft_edge", soft_edge)
	_mat.set_shader_parameter("seed", seed)
	queue_redraw()


func _sync_anim() -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("reveal", reveal)
	_mat.set_shader_parameter("burn", burn)
	_mat.set_shader_parameter("reveal_origin", reveal_origin)


## 墨水暈開出現。回傳 Tween（呼叫端可 await finished）。
func ink_reveal(duration := -1.0) -> Tween:
	var st := GensokyoStyle.current()
	var d := st.dur(st.dialogue_reveal_duration if duration < 0.0 else duration)
	reveal = 0.0
	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(self, "reveal", 1.0, d)
	return tw


## 御札燃燒 → 灰燼 → 消失。
func burn_away(duration := 1.1) -> Tween:
	var st := GensokyoStyle.current()
	burn = 0.0
	var tw := create_tween()
	tw.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
	tw.tween_property(self, "burn", 1.0, duration / maxf(st.animation_speed, 0.01))
	return tw

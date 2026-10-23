@tool
extends Control
class_name GensokyoQuestTracker
## 任務資訊區（規格 QUEST UI）：不是 RPG Quest Box，是右上角一張小掛紙。
##   - 掛紙：細繩從畫面頂端垂下，一張窄和紙，左側 ◆ 標記（主線暖金／支線墨灰）。
##   - 非更新狀態：停留 hold_time 後退到 idle_alpha（存在感降低），紙底幾乎消失只剩字。
##   - 新任務：紙條由右側滑入並展開；任務完成：御札淡淡燃燒 → 灰燼 → 消失。
## 外部只呼叫 show_objective / hide_objective / announce；不認識 QuestManager。

signal announce_finished

@export var width := 340.0
@export var top_margin := 70.0
@export var right_margin := 34.0
## 更新後保持醒目的秒數，之後退到 idle。
@export var hold_time := 4.0
@export_range(0.0, 1.0, 0.01) var idle_alpha := 0.62
@export var banner_hold := 2.6

@onready var paper: GensokyoPanel = $Paper
@onready var objective: Label = $Paper/Row/Objective
@onready var marker: Control = $Paper/Row/Marker
@onready var banner: GensokyoPanel = $Banner
@onready var banner_head: Label = $Banner/VBox/Head
@onready var banner_title: Label = $Banner/VBox/Title

var is_main := true
var _presence := 1.0      # 1 = 剛更新；idle_alpha = 平時
var _presence_tw: Tween = null
var _banner_tw: Tween = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	marker.draw.connect(_draw_marker)
	paper.visible = false
	banner.visible = false
	get_viewport().size_changed.connect(_layout)
	paper.minimum_size_changed.connect(_layout.call_deferred)
	banner.minimum_size_changed.connect(_layout.call_deferred)
	_apply_scale()
	_layout()


func _apply_scale() -> void:
	var st := GensokyoStyle.current()
	var k := st.scale_for(self)
	objective.add_theme_font_size_override("font_size", st.font_px(self, 18))
	objective.custom_minimum_size.x = (width - 60.0) * k
	marker.custom_minimum_size = Vector2(18, 18) * k
	paper.add_theme_constant_override("margin_left", int(16 * k))
	paper.add_theme_constant_override("margin_right", int(20 * k))
	paper.add_theme_constant_override("margin_top", int(10 * k))
	paper.add_theme_constant_override("margin_bottom", int(11 * k))
	banner_head.add_theme_font_size_override("font_size", st.font_px(self, 16))
	banner_title.add_theme_font_size_override("font_size", st.font_px(self, 30))
	banner.add_theme_constant_override("margin_left", int(46 * k))
	banner.add_theme_constant_override("margin_right", int(58 * k))
	banner.add_theme_constant_override("margin_top", int(12 * k))
	banner.add_theme_constant_override("margin_bottom", int(16 * k))


func _layout() -> void:
	if paper == null:
		return
	_apply_scale()
	var st := GensokyoStyle.current()
	var k := st.scale_for(self)
	var vp := get_viewport_rect().size
	paper.size = Vector2(0, 0)
	var ps := paper.get_combined_minimum_size()
	paper.size = ps
	paper.position = Vector2(vp.x - right_margin * k - ps.x, top_margin * k)
	paper.pivot_offset = Vector2(ps.x, 0)
	banner.size = Vector2(0, 0)
	var bs := banner.get_combined_minimum_size()
	banner.size = bs
	# 上方 1/5，不擋角色（角色在畫面中央偏下）
	banner.position = Vector2((vp.x - bs.x) * 0.5, vp.y * 0.16)
	banner.pivot_offset = bs * 0.5
	queue_redraw()


## 掛繩：從畫面頂端垂到紙的右上（畫在自己身上，紙外）。
func _draw() -> void:
	if not paper.visible or paper.modulate.a < 0.02:
		return
	var st := GensokyoStyle.current()
	var k := st.scale_for(self)
	var a := paper.modulate.a
	var x := paper.position.x + paper.size.x - 26.0 * k
	var col := Color(st.accent(st.dark_vermilion), 0.75 * a)
	draw_line(Vector2(x, 0), Vector2(x + 1.0 * k, paper.position.y + 2.0 * k), col, 1.4 * k, true)
	draw_circle(Vector2(x + 1.0 * k, paper.position.y + 1.0 * k), 2.6 * k, Color(st.old_gold, 0.9 * a))


func _draw_marker() -> void:
	var st := GensokyoStyle.current()
	var s := marker.size
	var c := s * 0.5
	var r := minf(s.x, s.y) * 0.34
	var col := st.old_gold if is_main else st.ink_grey
	var pts := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.8, 0), c + Vector2(0, r), c + Vector2(-r * 0.8, 0)])
	marker.draw_colored_polygon(pts, col)
	if is_main:
		marker.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r * 0.45), c + Vector2(r * 0.35, 0), c + Vector2(0, r * 0.45), c + Vector2(-r * 0.35, 0)]),
			st.accent(st.dark_vermilion))


func show_objective(text: String, main_quest: bool) -> void:
	var changed := text != objective.text or not paper.visible or main_quest != is_main
	is_main = main_quest
	objective.text = text
	objective.add_theme_color_override("font_color", GensokyoStyle.current().text_ink if main_quest else GensokyoStyle.current().ink_grey.darkened(0.2))
	marker.queue_redraw()
	var was_hidden := not paper.visible
	paper.visible = true
	_layout()
	if was_hidden:
		paper.ink_reveal(0.25)
	if changed:
		_bump_presence()


func hide_objective() -> void:
	paper.visible = false
	queue_redraw()


## kind: "new" / "done"
## 橫幅排隊播：完成任務會在同一幀串起下一關（QuestManager.complete_quest → start_quest），
## 不排隊的話「新的委託」會把「委託完成」的燃燒動畫當場砍掉。
var _queue: Array = []


func announce(kind: String, title: String) -> void:
	if banner.visible and _banner_tw != null and _banner_tw.is_valid() and _banner_tw.is_running():
		_queue.append([kind, title])
		return
	_play_banner(kind, title)


func _play_banner(kind: String, title: String) -> void:
	var st := GensokyoStyle.current()
	var k := st.scale_for(self)
	banner_head.text = "── 新的委託 ──" if kind == "new" else "── 委託完成 ──"
	banner_title.text = title
	banner.burn = 0.0
	banner.reveal = 1.0
	banner.visible = true
	banner.modulate.a = 1.0
	_layout()
	if _banner_tw != null:
		_banner_tw.kill()
	var slide := st.dur(0.30)
	_banner_tw = create_tween()
	if kind == "new":
		# 紙張由側邊滑入並展開
		var x1 := banner.position.x
		banner.position.x = x1 + 90.0 * k
		banner.scale = Vector2(0.15, 1.0)
		banner.modulate.a = 0.0
		_banner_tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		_banner_tw.tween_property(banner, "position:x", x1, slide)
		_banner_tw.parallel().tween_property(banner, "scale:x", 1.0, slide)
		_banner_tw.parallel().tween_property(banner, "modulate:a", 1.0, slide * 0.6)
		_banner_tw.tween_interval(banner_hold)
		_banner_tw.tween_property(banner, "modulate:a", 0.0, st.dur(0.5))
	else:
		# 御札：靜靜出現，停留後由下往上燃燒成灰
		banner.scale = Vector2.ONE
		banner.modulate.a = 0.0
		_banner_tw.tween_property(banner, "modulate:a", 1.0, st.dur(0.25))
		_banner_tw.tween_interval(banner_hold * 0.8)
		_banner_tw.tween_property(banner, "burn", 1.0, 1.2 / maxf(st.animation_speed, 0.01)).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
		_banner_tw.parallel().tween_property(banner_head, "modulate:a", 0.0, 0.6)
		_banner_tw.parallel().tween_property(banner_title, "modulate:a", 0.0, 0.9)
	_banner_tw.tween_callback(func() -> void:
		banner.visible = false
		banner_head.modulate.a = 1.0
		banner_title.modulate.a = 1.0
		announce_finished.emit()
		if not _queue.is_empty():
			var nx: Array = _queue.pop_front()
			_play_banner(nx[0], nx[1]))


func is_banner_visible() -> bool:
	return banner.visible


func banner_text() -> String:
	return banner_head.text + "\n" + banner_title.text


## 更新 → 醒目 → hold_time 後退到 idle（字留著，紙底變淡）。
func _bump_presence() -> void:
	var st := GensokyoStyle.current()
	if _presence_tw != null:
		_presence_tw.kill()
	_presence_tw = create_tween()
	_presence_tw.tween_method(_set_presence, _presence, 1.0, st.dur())
	_presence_tw.tween_interval(hold_time)
	_presence_tw.tween_method(_set_presence, 1.0, idle_alpha, st.dur(0.9))


func _set_presence(v: float) -> void:
	_presence = v
	var st := GensokyoStyle.current()
	paper.modulate.a = v
	# 紙底比字退得更多：idle 時只剩一層薄紙
	var t := inverse_lerp(idle_alpha, 1.0, v)
	paper.base_opacity = lerpf(st.quest_background * 0.45, st.quest_background, clampf(t, 0.0, 1.0))
	queue_redraw()

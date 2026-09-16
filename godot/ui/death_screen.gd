extends CanvasLayer
class_name DeathScreen
## 死亡演出（隻狼式）：倒地 → 畫面壓暗 → 大字「死」浮現 → 全黑 → 重生 → 淡入。
##
## 純程式繪製（同 combat_hud / form_menu 的做法，不依賴貼圖）。由 CombatRuntime
## 在玩家 `player_died` 時掛起；重生本身由 `respawn_requested` 交給 main.gd
## （它才知道地圖與出生點）。時間軸全部 @export，實測秒數見 verify_death_screen.gd。

signal respawn_requested
signal finished

## 倒地後多久開始壓暗（讓 Dead 動畫先播一段）。
@export var hold_before_dim := 1.2
## 壓暗到 dim_alpha 的時間。
@export var dim_time := 0.8
## 壓暗的黑幕不透明度（不全黑，倒地的人還看得到）。
@export_range(0.0, 1.0, 0.05) var dim_alpha := 0.55
## 「死」字淡入時間。
@export var kanji_fade_in := 0.6
## 「死」字停留時間。
@export var kanji_hold := 1.4
## 全黑（含字一起淡掉）時間。
@export var black_time := 0.9
## 全黑後多久發 respawn_requested（讓 main 有時間搬人）。
@export var black_hold := 0.4
## 重生後淡入時間。
@export var fade_in_time := 1.0
## 字的大小（像素，依視窗高度比例）。
@export_range(0.1, 0.8, 0.05) var kanji_height_ratio := 0.42
@export var kanji_color := Color(0.78, 0.08, 0.08)
@export var kanji_text := "死"
## 音效（tools/synth_sfx.py 合成）：「死」字浮現時的太鼓＋低鳴；重生淡入時的吸氣。
## 用 load：檔案缺席就靜音，不擋演出。
@export var kanji_sound: AudioStream = null
@export var respawn_sound: AudioStream = null
@export var sound_bus: StringName = &"Master"

var _black: ColorRect = null
var _kanji: Label = null
var _running := false
var _sfx: AudioStreamPlayer = null


func _ready() -> void:
	layer = 60   # 蓋在對話（1）、開場黑幕（50）之上
	if kanji_sound == null and ResourceLoader.exists("res://assets/audio/sfx/death_kanji.wav"):
		kanji_sound = load("res://assets/audio/sfx/death_kanji.wav")
	if respawn_sound == null and ResourceLoader.exists("res://assets/audio/sfx/respawn_breath.wav"):
		respawn_sound = load("res://assets/audio/sfx/respawn_breath.wav")
	_sfx = AudioStreamPlayer.new()
	_sfx.name = "Sfx"
	_sfx.bus = sound_bus
	add_child(_sfx)
	_black = ColorRect.new()
	_black.name = "Black"
	_black.color = Color(0, 0, 0, 0)
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_black)
	_kanji = Label.new()
	_kanji.name = "Kanji"
	_kanji.text = kanji_text
	_kanji.set_anchors_preset(Control.PRESET_FULL_RECT)
	_kanji.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_kanji.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_kanji.modulate = Color(kanji_color, 0.0)
	_kanji.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_kanji_size()
	get_viewport().size_changed.connect(_apply_kanji_size)
	add_child(_kanji)


func _apply_kanji_size() -> void:
	var h: float = get_viewport().get_visible_rect().size.y
	_kanji.add_theme_font_size_override("font_size", int(h * kanji_height_ratio))


func is_running() -> bool:
	return _running


## 整段演出。await 得到，結束時 finished。
func play() -> void:
	if _running:
		return
	_running = true
	_black.mouse_filter = Control.MOUSE_FILTER_STOP   # 黑幕期間吃掉輸入
	var t := create_tween()
	t.tween_interval(hold_before_dim)
	t.tween_property(_black, "color:a", dim_alpha, dim_time).set_trans(Tween.TRANS_SINE)
	t.tween_callback(func() -> void: _play_sound(kanji_sound, 0.0))
	t.tween_property(_kanji, "modulate:a", 1.0, kanji_fade_in).set_trans(Tween.TRANS_SINE)
	t.tween_interval(kanji_hold)
	t.set_parallel(true)
	t.tween_property(_black, "color:a", 1.0, black_time).set_trans(Tween.TRANS_SINE)
	t.tween_property(_kanji, "modulate:a", 0.0, black_time).set_trans(Tween.TRANS_SINE)
	t.set_parallel(false)
	t.tween_interval(black_hold)
	t.tween_callback(func() -> void: respawn_requested.emit())
	# 重生那一幀給 main 搬人；再淡入
	t.tween_interval(0.05)
	t.tween_callback(func() -> void: _play_sound(respawn_sound, -4.0))
	t.tween_property(_black, "color:a", 0.0, fade_in_time).set_trans(Tween.TRANS_SINE)
	t.tween_callback(func() -> void:
		_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_running = false
		finished.emit())
	await t.finished


func _play_sound(stream: AudioStream, volume_db: float) -> void:
	if stream == null or _sfx == null:
		return
	_sfx.stream = stream
	_sfx.volume_db = volume_db
	_sfx.play()


## 測試／跳關用。
func total_time() -> float:
	return hold_before_dim + dim_time + kanji_fade_in + kanji_hold + black_time + black_hold + 0.05 + fade_in_time

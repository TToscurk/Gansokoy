extends CanvasLayer
class_name TravelLoading
## 換圖載入幕：傳送一受理就蓋黑幕＋目的地名＋進度條，載完才淡出。
##
## 為什麼需要：獸道→人間之里在 F5 實測整段 ≈10 s 主執行緒卡死
## （load 5.5 s＋instantiate 2.0 s＋效能裁剪 1.8 s＋首幀 0.8 s），
## 畫面停在獸道、按鍵沒反應，看起來就是「載不進去」。
##
## 不認識地圖、不管暫停 —— 由 main.gd 的 _travel() 驅動。
## 整棵樹暫停時也要動：process_mode = ALWAYS，tween 用 TWEEN_PAUSE_PROCESS。

## 黑幕淡入秒數（很短：傳送受理後要立刻有反應）
@export var fade_in := 0.15
## 載完淡出秒數
@export var fade_out := 0.45

var _rect: ColorRect = null
var _title: Label = null
var _status: Label = null
var _bar: ProgressBar = null


func _ready() -> void:
	# 蓋在所有 UI（對話 layer 1、開場 50）之上
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect = ColorRect.new()
	_rect.name = "Black"
	_rect.color = Color(0, 0, 0, 0)
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_rect)

	_title = Label.new()
	_title.name = "Title"
	_title.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 34)
	_title.add_theme_color_override("font_color", Color(1.0, 0.94, 0.82))
	_rect.add_child(_title)

	_status = Label.new()
	_status.name = "Status"
	_status.anchor_left = 0.0
	_status.anchor_right = 1.0
	_status.anchor_top = 0.56
	_status.anchor_bottom = 0.61
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 18)
	_status.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	_status.text = "載入中…"
	_rect.add_child(_status)

	_bar = ProgressBar.new()
	_bar.name = "Progress"
	_bar.anchor_left = 0.35
	_bar.anchor_right = 0.65
	_bar.anchor_top = 0.63
	_bar.anchor_bottom = 0.645
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.step = 0.0
	_bar.show_percentage = false
	_rect.add_child(_bar)
	_set_children_alpha(0.0)


func set_title(text: String) -> void:
	_title.text = text


func set_status(text: String) -> void:
	_status.text = text


func set_progress(p: float) -> void:
	_bar.value = clampf(p, 0.0, 1.0)


## 淡入黑幕；await 回來時畫面已全黑。
func cover() -> void:
	var t := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	t.tween_method(_set_alpha, 0.0, 1.0, fade_in)
	await t.finished


## 淡出並自我釋放。
func reveal() -> void:
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	t.tween_method(_set_alpha, 1.0, 0.0, fade_out)
	await t.finished
	queue_free()


func _set_alpha(a: float) -> void:
	_rect.color.a = a
	_set_children_alpha(a)


func _set_children_alpha(a: float) -> void:
	for c in _rect.get_children():
		(c as CanvasItem).modulate.a = a

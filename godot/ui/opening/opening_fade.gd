extends CanvasLayer
class_name OpeningFade
## 序章開場：黑畫面 → 停留 → 淡入 → 才起獨白。
##
## 設計文件：「黑畫面。風。蟲。遠處鳥叫。不是音樂先上。畫面亮起。」
## 在畫面還是黑的時候就跳對話框，玩家會覺得遊戲壞了。
##
## 只在「首次啟動、落在 START_MAP、沒有 woke_in_trail 旗標」時演。
## 之後 --map= 跳圖、傳送回獸道都不演。
##
## 不認識任務、不認識對話 —— 淡入完成發 signal，由 main 接去起獨白。

signal fade_finished

## 黑畫面停留（讓環境音先上）
@export var hold_black := 1.4
## 淡入秒數
@export var fade_in := 2.2
## 淡入曲線：先慢後快，像眼睛慢慢張開
@export var ease_curve: Tween.EaseType = Tween.EASE_IN

var _rect: ColorRect = null
var _done := false


func _ready() -> void:
	# 蓋在對話 UI 之上（DialogueUI 在 layer 1）；淡入時對話框不該先露出來
	layer = 50
	_rect = ColorRect.new()
	_rect.name = "Black"
	_rect.color = Color.BLACK
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	# 黑幕期間吃掉輸入：不要讓玩家在黑畫面裡跑掉
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_rect)


func play() -> void:
	if _done:
		return
	_done = true
	var t := create_tween()
	t.tween_interval(hold_black)
	t.tween_property(_rect, "color:a", 0.0, fade_in) \
		.set_trans(Tween.TRANS_SINE).set_ease(ease_curve)
	t.tween_callback(func() -> void:
		_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fade_finished.emit()
		queue_free())


## 測試／跳圖用：立即拿掉黑幕
func skip() -> void:
	_done = true
	if _rect != null:
		_rect.color.a = 0.0
		_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_finished.emit()
	queue_free()

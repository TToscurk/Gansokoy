extends Control
## 玩家血量／軀幹槽的程式繪製。左下角，血在上、軀幹在下。

@export var bar_width := 320.0
@export var health_height := 14.0
@export var posture_height := 10.0
@export var gap := 8.0

var _hud: Node = null


func _ready() -> void:
	_hud = get_parent().get_parent()


func _draw() -> void:
	if _hud == null:
		return

	# --- 血量：分節，容易讀出還剩幾下 ---------------------------------
	var seg: int = maxi(_hud.health_segments, 1)
	var seg_gap := 3.0
	var seg_w: float = (bar_width - seg_gap * (seg - 1)) / seg
	var filled: float = _hud.player_health_ratio * seg
	for i in seg:
		var x: float = i * (seg_w + seg_gap)
		var rect := Rect2(x, 0.0, seg_w, health_height)
		draw_rect(rect, Color(0, 0, 0, 0.55))
		var f: float = clampf(filled - i, 0.0, 1.0)
		if f > 0.0:
			var col := Color(0.82, 0.16, 0.16) if _hud.player_health_ratio > 0.3 else Color(1.0, 0.3, 0.25)
			draw_rect(Rect2(x, 0.0, seg_w * f, health_height), col)
		draw_rect(rect, Color(0, 0, 0, 0.85), false, 1.0)

	# --- 軀幹：中央往兩側長 -------------------------------------------
	var y := health_height + gap
	var mid := bar_width * 0.5
	draw_rect(Rect2(0.0, y, bar_width, posture_height), Color(0, 0, 0, 0.55))
	var half: float = _hud.player_posture_ratio * mid
	if half > 0.0:
		var col: Color = _hud.posture_colour(_hud.player_posture_ratio)
		col.a = _hud._pulse_alpha(_hud.player_posture_ratio)
		draw_rect(Rect2(mid - half, y, half * 2.0, posture_height), col)
	draw_rect(Rect2(0.0, y, bar_width, posture_height), Color(0, 0, 0, 0.85), false, 1.0)
	# 中線刻度，讓「往兩側長」讀得出來。
	draw_line(Vector2(mid, y - 2.0), Vector2(mid, y + posture_height + 2.0), Color(1, 1, 1, 0.35), 1.0)

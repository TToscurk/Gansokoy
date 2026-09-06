extends Control
## 敵人軀幹／血量槽的程式繪製。畫面上方中央，軀幹在上（隻狼把軀幹放主位）。

@export var bar_width := 420.0
@export var posture_height := 12.0
@export var health_height := 6.0
@export var gap := 5.0

var _hud: Node = null


func _ready() -> void:
	_hud = get_parent().get_parent().get_parent()


func _draw() -> void:
	if _hud == null:
		return

	var mid := bar_width * 0.5

	# --- 軀幹（主角色）：中央往兩側 -----------------------------------
	draw_rect(Rect2(0.0, 0.0, bar_width, posture_height), Color(0, 0, 0, 0.6))
	var half: float = _hud.enemy_posture_ratio * mid
	if half > 0.0:
		var col: Color = _hud.posture_colour(_hud.enemy_posture_ratio)
		col.a = _hud._pulse_alpha(_hud.enemy_posture_ratio)
		draw_rect(Rect2(mid - half, 0.0, half * 2.0, posture_height), col)
	draw_rect(Rect2(0.0, 0.0, bar_width, posture_height), Color(0, 0, 0, 0.9), false, 1.0)
	draw_line(Vector2(mid, -2.0), Vector2(mid, posture_height + 2.0), Color(1, 1, 1, 0.35), 1.0)

	# --- 血量（次要）：細條，由左往右 ---------------------------------
	var y := posture_height + gap
	draw_rect(Rect2(0.0, y, bar_width, health_height), Color(0, 0, 0, 0.6))
	if _hud.enemy_health_ratio > 0.0:
		draw_rect(Rect2(0.0, y, bar_width * _hud.enemy_health_ratio, health_height), Color(0.78, 0.18, 0.18))
	draw_rect(Rect2(0.0, y, bar_width, health_height), Color(0, 0, 0, 0.9), false, 1.0)

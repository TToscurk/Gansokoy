extends CanvasLayer
## M 鍵：全螢幕地圖（程式繪製，無貼圖）。畫目前圖的路徑、地標、玩家、目標。
## 開啟時鎖玩家（借 input_locked），滑鼠釋放；再按 M 或 Esc 關。

var _main: Node = null
@onready var _canvas: Control = $Canvas
@onready var _title: Label = $Canvas/Title


func _ready() -> void:
	_main = get_parent()
	visible = false
	_canvas.draw.connect(_draw_map)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("map_toggle"):
		if not visible and DialogueManager.is_active():
			return
		_set_open(not visible)
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed("ui_cancel"):
		_set_open(false)
		get_viewport().set_input_as_handled()


func _set_open(open: bool) -> void:
	visible = open
	_main.player.set("input_locked", open)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED
	if open:
		var info: Dictionary = WaypointResolver.map_info(String(_main.current_id))
		_title.text = String(info.get("name", _main.current_id))
		_canvas.queue_redraw()


func _process(_d: float) -> void:
	if visible:
		_canvas.queue_redraw()


func _draw_map() -> void:
	var info: Dictionary = WaypointResolver.map_info(String(_main.current_id))
	if info.is_empty():
		_canvas.draw_string(ThemeDB.fallback_font, Vector2(40, 80), "（本圖尚無地圖資料）", HORIZONTAL_ALIGNMENT_LEFT, -1, 22)
		return
	var hx := float(info.get("half_x", 100))
	var hz := float(info.get("half_z", 100))
	var size := _canvas.size
	var pad := 90.0
	var scale := minf((size.x - pad * 2.0) / (hx * 2.0), (size.y - pad * 2.0) / (hz * 2.0))
	var centre := size * 0.5
	var to_screen := func(x: float, z: float) -> Vector2:
		return centre + Vector2(x, z) * scale      # 北(-z) 在上
	# 底
	var rect := Rect2(to_screen.call(-hx, -hz), Vector2(hx * 2.0, hz * 2.0) * scale)
	_canvas.draw_rect(rect, Color(0.10, 0.12, 0.10, 0.92))
	_canvas.draw_rect(rect, Color(0.85, 0.75, 0.5, 0.8), false, 2.0)
	# 格線每 50 m
	var g := 50.0
	var gx := -floorf(hx / g) * g
	while gx <= hx:
		_canvas.draw_line(to_screen.call(gx, -hz), to_screen.call(gx, hz), Color(1, 1, 1, 0.06))
		gx += g
	var gz := -floorf(hz / g) * g
	while gz <= hz:
		_canvas.draw_line(to_screen.call(-hx, gz), to_screen.call(hx, gz), Color(1, 1, 1, 0.06))
		gz += g
	# 路徑
	var path: Array = info.get("path", [])
	for i in range(path.size() - 1):
		_canvas.draw_line(to_screen.call(path[i][0], path[i][1]), to_screen.call(path[i + 1][0], path[i + 1][1]),
			Color(0.75, 0.65, 0.45, 0.9), 3.0)
	# 地標
	var font := ThemeDB.fallback_font
	for lm in info.get("landmarks", []):
		var p: Vector2 = to_screen.call(float(lm.x), float(lm.z))
		_canvas.draw_circle(p, 4.0, Color(0.9, 0.9, 0.85))
		_canvas.draw_string(font, p + Vector2(8, 5), String(lm.label), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.9, 0.9, 0.85))
	# 目標
	var t: Dictionary = WaypointResolver.resolve(String(_main.current_id), _main.current_portals())
	if not t.is_empty():
		var tp: Vector2 = to_screen.call(t.pos.x, t.pos.y)
		_canvas.draw_circle(tp, 9.0, Color(1, 0.85, 0.45, 0.35))
		_canvas.draw_circle(tp, 5.0, Color(1, 0.85, 0.45))
		# 標籤放目標左側，避開右側的地標名
		var tl := String(t.label)
		var w := font.get_string_size(tl, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		_canvas.draw_string(font, tp + Vector2(-w - 14, 6), tl, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 0.9, 0.6))
	# 玩家（帶朝向）
	var pl: Node3D = _main.player
	var pp: Vector2 = to_screen.call(pl.global_position.x, pl.global_position.z)
	var fwd: Vector2
	var visual: Node3D = pl.get_node_or_null("BodyVisual")
	if visual != null:
		var yaw := visual.global_rotation.y
		fwd = Vector2(sin(yaw), cos(yaw))
	else:
		var yaw := pl.rotation.y
		fwd = Vector2(-sin(yaw), -cos(yaw))       # 模型朝 -z 為前
	var tri := PackedVector2Array([pp + fwd * 12.0, pp + fwd.rotated(2.5) * 8.0, pp + fwd.rotated(-2.5) * 8.0])
	_canvas.draw_colored_polygon(tri, Color(0.45, 0.85, 1.0))
	# 指北
	_canvas.draw_string(font, Vector2(rect.position.x, rect.position.y - 10), "N ↑", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.9, 0.9, 0.85))
	_canvas.draw_string(font, Vector2(rect.position.x, rect.end.y + 26), "%.0f × %.0f m　[M] 關閉" % [hx * 2, hz * 2], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.7, 0.7, 0.7))

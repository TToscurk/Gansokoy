extends PanelContainer
## Wind 除錯面板（F9；只在 debug build 建立）。對應 docs 的「Wind Debug Preview」概念圖：
##   四個滑桿（風力強度／主風向／陣風強度／局部風力差異）＋ preset ＋ 陣風 ＋ 熱圖 ＋「複製測試參數」。
## 預覽區不是示意圖：20 根草莖畫在焦點（相機）周圍 ±18 m 的真實世界位置，彎曲量與方向即時取自
## Wind.sample_field()——和植被 shader 同一個場，所以看得到局部差異與陣風前緣掃過。
##
## 滑桿＝寫回 Wind（不另存一份狀態）：強度／方向 → set_wind（手動覆寫；按「自動」回到 preset 排程），
## 陣風 → set_gust_amplitude，局部差異 → set_local_variation。

const W := 380
const PREVIEW_H := 120
const COLS := 10
const ROWS := 2
const SPAN_M := 18.0

var wind: Node
var _sl := {}
var _val := {}
var _unit := {}
var _syncing := false
var _status: Label
var _preview: Control
var _copied_t := 0.0


func setup(w: Node) -> void:
	wind = w
	name = "WindDebugPanel"
	custom_minimum_size = Vector2(W, 0)
	# 右上角：左上角留給各場景自己的 HUD（pilot、審圖工具）
	anchor_left = 1.0
	anchor_right = 1.0
	offset_left = -W - 16
	offset_right = -16
	offset_top = 16
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.09, 0.10, 0.96)
	sb.border_color = Color(0.32, 0.32, 0.34)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(14)
	add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	add_child(v)

	var head := HBoxContainer.new()
	var title := Label.new()
	title.text = "Wind Debug Preview"
	title.add_theme_font_size_override("font_size", 17)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var badge := Label.new()
	badge.text = "即時風場  [F9]"
	badge.add_theme_font_size_override("font_size", 12)
	badge.add_theme_color_override("font_color", Color(0.7, 0.72, 0.75))
	head.add_child(badge)
	v.add_child(head)

	_preview = Control.new()
	_preview.custom_minimum_size = Vector2(W - 28, PREVIEW_H)
	_preview.draw.connect(_draw_preview)
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_preview)
	var cap := Label.new()
	cap.text = "焦點周圍 ±18 m 的真實取樣：彎曲＝當地強度、傾向＝當地風向（螢幕左右）。"
	cap.add_theme_font_size_override("font_size", 12)
	cap.add_theme_color_override("font_color", Color(0.6, 0.62, 0.65))
	cap.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(cap)

	_add_slider(v, "strength", "風力強度", 0.0, 150.0, 1.0, "%")
	_add_slider(v, "direction", "主風向", 0.0, 360.0, 1.0, "°")
	_add_slider(v, "gust", "陣風強度", 0.0, 100.0, 1.0, "%")
	_add_slider(v, "local", "局部風力差異", 0.0, 100.0, 1.0, "%")

	var row1 := HBoxContainer.new()
	for pair in [["calm", 0], ["breeze", 1], ["moderate", 2], ["gust", 3]]:
		var b := Button.new()
		b.text = String(pair[0])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var idx: int = pair[1]
		b.pressed.connect(func() -> void:
			wind.set_preset(idx)
			wind.set_gust_amplitude(-1.0)
			_sync_from_wind())
		row1.add_child(b)
	v.add_child(row1)
	var row2 := HBoxContainer.new()
	_btn(row2, "陣風", func() -> void: wind.trigger_gust())
	_btn(row2, "自動", func() -> void:
		wind.clear_override()
		_sync_from_wind())
	_btn(row2, "開／關", func() -> void: wind.toggle_enabled())
	_btn(row2, "熱圖", func() -> void: wind.set_debug_view(0 if int(wind.get_debug_view()) == 1 else 1))
	v.add_child(row2)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 13)
	_status.add_theme_color_override("font_color", Color(0.85, 0.9, 0.8))
	v.add_child(_status)

	var row3 := HBoxContainer.new()
	var copy := Button.new()
	copy.text = "⧉  複製測試參數"
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.pressed.connect(_copy_params)
	row3.add_child(copy)
	var paste := Button.new()
	paste.text = "貼上套用"
	paste.pressed.connect(_paste_params)
	row3.add_child(paste)
	v.add_child(row3)
	_sync_from_wind()
	wind.preset_changed.connect(func(_n: String) -> void: _sync_from_wind())


func _btn(parent: Control, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	parent.add_child(b)


func _add_slider(parent: Control, key: String, label: String, lo: float, hi: float, step: float, unit: String) -> void:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	var val := Label.new()
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.custom_minimum_size = Vector2(60, 0)
	h.add_child(val)
	parent.add_child(h)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.focus_mode = Control.FOCUS_NONE
	s.value_changed.connect(func(x: float) -> void:
		val.text = "%d%s" % [int(round(x)), unit]
		if not _syncing:
			_apply(key, x))
	parent.add_child(s)
	_sl[key] = s
	_val[key] = val
	_unit[key] = unit


## 滑桿 → Wind
func _apply(key: String, x: float) -> void:
	match key:
		"strength":
			wind.set_wind(float(_sl["direction"].value), x / 100.0)
		"direction":
			wind.set_wind(x, float(_sl["strength"].value) / 100.0)
		"gust":
			wind.set_gust_amplitude(x / 100.0)
		"local":
			wind.set_local_variation(x / 50.0)


## Wind → 滑桿（換 preset／自動／貼上之後）。局部差異：50 %＝設計值 ×1。
func _sync_from_wind() -> void:
	_syncing = true
	var p: Dictionary = wind.get_params()
	_sl["strength"].value = float(p["strength"]) * 100.0
	_sl["direction"].value = float(p["direction_deg"])
	_sl["gust"].value = float(p["gust_amplitude"]) * 100.0
	_sl["local"].value = float(p["local_variation"]) * 50.0
	_refresh_labels()
	_syncing = false


## value_changed 只在值有變時才發；同步後一律重寫數值文字（避免初值等於預設時讀數空白）。
func _refresh_labels() -> void:
	for k in _sl:
		(_val[k] as Label).text = "%d%s" % [int(round((_sl[k] as HSlider).value)), _unit[k]]


func _copy_params() -> void:
	var txt := JSON.stringify(wind.get_params())
	DisplayServer.clipboard_set(txt)
	print("[Wind] 測試參數已複製：", txt)
	_copied_t = 2.0


func _paste_params() -> void:
	var d: Variant = JSON.parse_string(DisplayServer.clipboard_get())
	if d is Dictionary:
		wind.apply_params(d)
		_sync_from_wind()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_copied_t = maxf(0.0, _copied_t - delta)
	var st: Dictionary = wind.get_wind()
	var f: Dictionary = wind.sample_field(st["focus"])
	_status.text = "%s%s  %s  base %.2f  gust %.2f  eff %.2f\n焦點 %.0f° ・ %.2f（%.1f m/s）  陣風事件 %d  植被 %d  熱圖 %s%s" % [
		String(st["preset"]).to_upper(), "" if bool(st["enabled"]) else "（關）",
		"手動" if wind.is_manual() else "自動",
		float(st["strength"]), float(st["gust"]), float(st["effective"]),
		wrapf(rad_to_deg(float(f["angle"])), 0.0, 360.0), float(f["strength"]), float(f["speed"]),
		int(st["events"]), int(wind.call("_veg_total")),
		"開" if int(wind.get_debug_view()) == 1 else "關",
		"   ✓ 已複製" if _copied_t > 0.0 else ""]
	if not wind.is_manual() and not _is_dragging():
		_follow_live(st)
	_preview.queue_redraw()


## 自動模式時滑桿跟著風場走（看得到排程轉向與 lull），拖曳中不搶。
func _follow_live(st: Dictionary) -> void:
	_syncing = true
	_sl["strength"].value = float(st["strength"]) * 100.0
	_sl["direction"].value = wrapf(float(st["direction_deg"]), 0.0, 360.0)
	_refresh_labels()
	_syncing = false


func _is_dragging() -> bool:
	return Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)


## 預覽：20 根草莖，世界位置＝焦點 + 相機右方 x（±18 m）× 前方兩列（6 m／14 m）。
func _draw_preview() -> void:
	var c := _preview
	var sz := c.size
	c.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.05, 0.05, 0.06, 1.0))
	var st: Dictionary = wind.get_wind()
	var focus: Vector3 = st["focus"]
	var right := Vector3.RIGHT
	var fwd := Vector3.FORWARD
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		right = cam.global_transform.basis.x
		right.y = 0.0
		right = right.normalized()
		fwd = Vector3(-right.z, 0.0, right.x) * -1.0
	for r in ROWS:
		var y := sz.y * (0.46 + 0.42 * r)
		var depth := 6.0 + 8.0 * (1 - r)
		for i in COLS:
			var t := (float(i) + 0.5) / COLS
			var x := sz.x * (0.04 + 0.80 * t)
			var wp := focus + right * lerpf(-SPAN_M, SPAN_M, t) + fwd * depth
			var f: Dictionary = wind.sample_field(wp, 0.5)
			var a := float(f["angle"])
			var wv := Vector3(cos(a), 0.0, sin(a))
			var side := wv.dot(right)
			var s := clampf(float(f["strength"]) / 1.6, 0.0, 1.0)
			var lean := side * s * 1.25
			var h := 34.0 - 8.0 * r
			var tip := Vector2(x + sin(lean) * h, y - cos(lean) * h)
			var mid := Vector2(x + sin(lean * 0.45) * h * 0.55, y - cos(lean * 0.45) * h * 0.55)
			var col := Color(0.36, 0.5, 0.3).lerp(Color(0.62, 0.8, 0.45), s)
			c.draw_polyline(PackedVector2Array([Vector2(x, y), mid, tip]), col, 4.0, true)
			c.draw_circle(Vector2(x, y), 3.0, Color(0.55, 0.45, 0.32))
	# 羅盤：全域風向（相對相機）＋強度
	var ctr := Vector2(sz.x - 26, 24)
	c.draw_arc(ctr, 18, 0, TAU, 32, Color(0.4, 0.4, 0.42), 1.5, true)
	var ga := deg_to_rad(float(st["direction_deg"]))
	var gv := Vector3(cos(ga), 0.0, sin(ga))
	var dir2 := Vector2(gv.dot(right), -gv.dot(fwd)).normalized()
	c.draw_line(ctr, ctr + dir2 * 16.0, Color(0.95, 0.85, 0.4), 3.0, true)

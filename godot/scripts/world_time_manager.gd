extends Node
## WorldTimeManager —— 全域世界時間系統代理與外觀（Facade）
## 提供與 DayNight 完全同步的介面，支援日、時、分、7 大時段、多原因時間鎖定與事件推進。

signal hour_changed(hour: float)
signal time_advanced(day: int, hour: int, minute: int)
signal period_changed(new_period: int, old_period: int)

var _dn: Node = null


func _ready() -> void:
	_dn = get_node_or_null("/root/DayNight")
	if _dn != null:
		if _dn.has_signal("hour_changed"):
			_dn.hour_changed.connect(func(h: float) -> void: hour_changed.emit(h))
		if _dn.has_signal("time_advanced"):
			_dn.time_advanced.connect(func(d: int, h: int, m: int) -> void: time_advanced.emit(d, h, m))
		if _dn.has_signal("period_changed"):
			_dn.period_changed.connect(func(np: int, op: int) -> void: period_changed.emit(np, op))


var day: int:
	get:
		var dn := _get_dn()
		return int(dn.get("day")) if dn != null else 1
	set(v):
		var dn := _get_dn()
		if dn != null: dn.set("day", v)

var hour: float:
	get:
		var dn := _get_dn()
		return float(dn.get("hour")) if dn != null else 6.5
	set(v):
		var dn := _get_dn()
		if dn != null: dn.call("set_hour", v)

var minute: int:
	get:
		var dn := _get_dn()
		return int(dn.get("minute")) if dn != null else 30

var hour_int: int:
	get:
		var dn := _get_dn()
		return int(dn.get("hour_int")) if dn != null else 6

var flowing: bool:
	get:
		var dn := _get_dn()
		return bool(dn.get("flowing")) if dn != null else true
	set(v):
		var dn := _get_dn()
		if dn != null: dn.set("flowing", v)

var pause_reasons: Array[String]:
	get:
		var dn := _get_dn()
		return dn.get("pause_reasons") as Array[String] if dn != null else []

## 時間流速倍率（1.0 = 正常）。冥想等「快轉」只動這一個數字 ——
## 不動 day_seconds（那是「一天多長」，由各圖天象系統的「一日長度分鐘」決定，
## 兩者混用會讓換圖把玩家的快轉倍率一起換掉）。
var time_scale: float:
	get:
		var dn := _get_dn()
		return float(dn.get("time_scale")) if dn != null else 1.0
	set(v):
		var dn := _get_dn()
		if dn != null: dn.set("time_scale", maxf(v, 0.0))

## 現實幾秒 = 遊戲一天。用來把「流速倍率」換算成「現實 1 秒走幾分」。
var day_seconds: float:
	get:
		var dn := _get_dn()
		return float(dn.get("day_seconds")) if dn != null else 3600.0

## 絕對時間（遊戲分鐘，第 1 日 00:00 = 0）。
## 跨日目標（23:00 冥想到隔天 06:00）拿這個比，比 hour 會永遠不成立。
var total_minutes: int:
	get:
		var dn := _get_dn()
		return int(dn.get("total_minutes")) if dn != null else 390


func _get_dn() -> Node:
	if _dn == null and is_inside_tree():
		_dn = get_node_or_null("/root/DayNight")
	return _dn


func lock_time(reason: String) -> void:
	var dn := _get_dn()
	if dn != null and dn.has_method("lock_time"):
		dn.lock_time(reason)


func unlock_time(reason: String) -> void:
	var dn := _get_dn()
	if dn != null and dn.has_method("unlock_time"):
		dn.unlock_time(reason)


func is_time_paused() -> bool:
	var dn := _get_dn()
	if dn != null and dn.has_method("is_time_paused"):
		return dn.is_time_paused()
	return false


func advance_minutes(amount: int) -> void:
	var dn := _get_dn()
	if dn != null and dn.has_method("advance_minutes"):
		dn.advance_minutes(amount)


func advance_time(hours: float) -> void:
	var dn := _get_dn()
	if dn != null and dn.has_method("advance_time"):
		dn.advance_time(hours)


func set_hour(h: float) -> void:
	var dn := _get_dn()
	if dn != null and dn.has_method("set_hour"):
		dn.set_hour(h)


func get_period() -> int:
	var dn := _get_dn()
	if dn != null and dn.has_method("get_period"):
		return dn.get_period()
	return 0


func get_period_name(p: Variant = null) -> String:
	var dn := _get_dn()
	if dn != null and dn.has_method("get_period_name"):
		return dn.get_period_name(p)
	return ""


func is_night() -> bool:
	var dn := _get_dn()
	if dn != null and dn.has_method("is_night"):
		return dn.is_night()
	return false


func clock_text() -> String:
	var dn := _get_dn()
	if dn != null and dn.has_method("clock_text"):
		return dn.clock_text()
	return "06:30"


## 從現在到「下一個 h 點」還差幾分鐘（1 ~ 1440）。已經在該時刻回 1440。
func minutes_until_hour(h: float) -> int:
	var dn := _get_dn()
	if dn != null and dn.has_method("minutes_until_hour"):
		return dn.minutes_until_hour(h)
	return 0


## 今天什麼天氣（全域）。⚠ 每張圖的天象系統另有自己的天氣，那要問圖裡的節點。
func weather_id() -> String:
	var w := get_node_or_null("/root/Weather")
	return String(w.get("current")) if w != null else "clear"

extends Node
class_name WorldEventManager
## 世界事件系統管理器（ADR-018 / RPG 系統第 13 模組）
## 統一管理地圖時間段事件、天氣條件、任務前置與機率擲骰。

signal event_triggered(event_id: String)

var _events: Dictionary = {}
var _triggered_history: Dictionary = {}


func register_event(id: String, def: Dictionary) -> void:
	_events[id] = def


func evaluate_events(map_id: String, hour: float, weather: String = "") -> Array[String]:
	var triggered: Array[String] = []
	for id in _events:
		var ev: Dictionary = _events[id]
		if String(ev.get("map", "")) != "" and String(ev.get("map", "")) != map_id:
			continue
		var start_h: float = float(ev.get("start_hour", 0.0))
		var end_h: float = float(ev.get("end_hour", 24.0))
		var in_time := false
		if start_h <= end_h:
			in_time = hour >= start_h and hour <= end_h
		else:
			# 跨午夜（如 19.5 到 05.0）
			in_time = hour >= start_h or hour <= end_h
		if not in_time:
			continue
		if bool(ev.get("one_shot", false)) and _triggered_history.has(id):
			continue
		var req_weather := String(ev.get("weather", ""))
		if not req_weather.is_empty() and not weather.is_empty():
			if req_weather != weather:
				continue
		var req_quest := String(ev.get("quest_requirement", ""))
		if not req_quest.is_empty():
			if has_node("/root/QuestManager"):
				var qm: Node = get_node("/root/QuestManager")
				if not qm.call("is_quest_active", req_quest) and not qm.call("is_quest_completed", req_quest):
					continue
		var req_flag := String(ev.get("flag_requirement", ""))
		if not req_flag.is_empty():
			if has_node("/root/StoryFlags"):
				var sf: Node = get_node("/root/StoryFlags")
				if not sf.call("get_flag", req_flag):
					continue
		var prob: float = float(ev.get("probability", 1.0))
		if randf() <= prob:
			_triggered_history[id] = true
			triggered.append(id)
			event_triggered.emit(id)
	return triggered


func is_event_triggered(id: String) -> bool:
	return _triggered_history.has(id)


func reset_event(id: String) -> void:
	_triggered_history.erase(id)

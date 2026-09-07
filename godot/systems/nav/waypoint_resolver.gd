extends Node
## WaypointResolver —— 把「目前任務目標」翻成「這張圖上該走去哪」。
## 資料：data/waypoints.json。跨圖時回傳通往目標圖的傳送點座標。
## 純查表，不畫東西；nav UI 與地圖 UI 共用。

const PATH := "res://data/waypoints.json"

var _data: Dictionary = {}


func _ready() -> void:
	if FileAccess.file_exists(PATH):
		var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if v is Dictionary:
			_data = v


func map_info(map_id: String) -> Dictionary:
	return _data.get("maps", {}).get(map_id, {})


## 回傳 {"pos": Vector2(x,z), "label": String, "via_portal": bool} 或空字典。
## portals：目前圖的 meta.portals（[{x,z,target}]），跨圖時用來找出口。
func resolve(current_map: String, portals: Array) -> Dictionary:
	var qid: String = QuestManager.get_active_quest()
	if qid.is_empty():
		return {}
	var obj: QuestObjective = QuestManager.get_current_objective(qid)
	if obj == null:
		return {}
	var t: Dictionary = _data.get("targets", {}).get(obj.target_id, {})
	if t.is_empty():
		return {}
	var target_map := String(t.get("map", current_map))
	if target_map == current_map:
		return {"pos": Vector2(float(t.x), float(t.z)), "label": String(t.get("label", obj.description)), "via_portal": false}
	# 跨圖：找直接通往 target_map 的傳送點；沒有就找任何傳送點（先離開這張圖）
	var best: Dictionary = {}
	for p in portals:
		if String(p.get("target", "")) == target_map:
			best = p
			break
	if best.is_empty() and portals.size() > 0:
		best = portals[0]
	if best.is_empty():
		return {}
	return {"pos": Vector2(float(best.x), float(best.z)),
		"label": "前往 %s" % _map_name(target_map), "via_portal": true}


func _map_name(map_id: String) -> String:
	return String(map_info(map_id).get("name", map_id))

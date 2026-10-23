extends Node3D
## 獸道夜雀屋台（NightSparrowStall）日夜隱現與天氣香氣事件控制器。
## - 白天（05:00 ~ 19:30）：隱藏夜雀屋台與桌椅，process_mode 設為 PROCESS_MODE_DISABLED 關閉碰撞與運算。
## - 夜晚（19:30 ~ 05:00）：顯現夜雀屋台，process_mode 設為 PROCESS_MODE_INHERIT。
## - 清晨（05:00）：若屋台在玩家視野（Camera3D 視錐）內，等待玩家轉開視線後才自然消失；不在視野則立即消失。
## - 進入夜晚：單次擲骰判定是否聞到烤八目鰻焦香（依天氣機率：晴45%、雲55%、雨75%/30%、霧85%、雪0%）。

const MORNING_HOUR := 5.0
const NIGHT_HOUR := 19.5

var _dn: Node = null
var _was_night := false
var _checked_tonight := false
var _pending_vanish := false


func _ready() -> void:
	_dn = get_node_or_null("/root/DayNight")
	if _dn != null and not Engine.is_editor_hint():
		_dn.hour_changed.connect(_on_hour_changed)
		var cur_hour: float = float(_dn.get("hour"))
		_was_night = _is_night_time(cur_hour)
		if _was_night:
			_appear_stall()
			_checked_tonight = true
		else:
			_vanish_stall()
	else:
		_vanish_stall()


func _process(_delta: float) -> void:
	if _pending_vanish:
		if not _is_in_camera_frustum():
			_pending_vanish = false
			_vanish_stall()


func _is_night_time(h: float) -> bool:
	return h >= NIGHT_HOUR or h < MORNING_HOUR


func _is_in_camera_frustum() -> bool:
	var viewport := get_viewport()
	if viewport == null:
		return false
	var cam := viewport.get_camera_3d()
	if cam == null:
		return false
	# 檢測屋台中心座標是否在鏡頭視錐內
	return cam.is_position_in_frustum(global_position)


func _appear_stall() -> void:
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	_pending_vanish = false


func _vanish_stall() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED


func _on_hour_changed(h: float) -> void:
	var night := _is_night_time(h)

	# 白天轉夜晚（在獸道待到晚上）
	if night and not _was_night:
		_was_night = true
		_appear_stall()
		if not _checked_tonight:
			_checked_tonight = true
			_evaluate_night_aroma_event()
	elif not night and _was_night:
		# 05:00 清晨：檢查玩家是否正在看著屋台
		_was_night = false
		_checked_tonight = false
		if _is_in_camera_frustum():
			_pending_vanish = true
		else:
			_vanish_stall()


func _evaluate_night_aroma_event() -> void:
	var chance := _get_weather_chance()
	var roll := randf()
	if roll <= chance:
		# 稍作延遲讓夜色與燈籠光先顯現，營造林間氛圍
		await get_tree().create_timer(1.5).timeout
		if has_node("/root/DialogueManager"):
			var dm: Node = get_node("/root/DialogueManager")
			if not dm.call("is_active"):
				dm.call("start", "trail_night_aroma")
		if has_node("/root/StoryFlags"):
			var sf: Node = get_node("/root/StoryFlags")
			sf.call("set_flag", "trail_aroma_noticed", true)


func _get_weather_chance() -> float:
	var tree := get_tree()
	if tree != null:
		var scene: Node = tree.current_scene if tree.current_scene != null else tree.root
		if scene != null:
			var sky := scene.find_child("天象系統", true, false)
			if sky != null and sky.get("天氣") != null:
				var w = sky.get("天氣")
				match int(w):
					0: return 0.45   # 晴朗：45%
					1: return 0.55   # 多雲：55%
					2: return 0.50   # 陰天：50%
					3: return 0.75   # 雨天：75%（小雨散發特殊焦香）
					4: return 0.85   # 起霧：85%（白霧迷濛氣味凝聚）
					5: return 0.00   # 雪天：0%（寒冬收攤）
	# 退回通用 Weather 判定
	if has_node("/root/Weather"):
		var wnode: Node = get_node("/root/Weather")
		var cur: String = String(wnode.get("current"))
		if cur == "rain":
			return 0.75
		elif cur == "fog":
			return 0.85
		elif cur == "snow":
			return 0.00
	return 0.50

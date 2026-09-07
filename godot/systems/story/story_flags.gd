extends Node
## StoryFlags —— 劇情旗標（autoload）。只存 bool；不做存檔。
##
## 依賴方向：WorldInteraction → DialogueManager → QuestManager → StoryFlags。
## 本節點不認識任何上層。

signal flag_changed(flag: String, value: bool)

var _flags: Dictionary = {}


func set_flag(flag: String, value: bool = true) -> void:
	if _flags.get(flag, false) == value:
		return
	_flags[flag] = value
	flag_changed.emit(flag, value)


func get_flag(flag: String) -> bool:
	return bool(_flags.get(flag, false))


func has_flag(flag: String) -> bool:
	return get_flag(flag)


## 條件式：字串 = 旗標為真；{"not": f}；{"all": [...]}；{"any": [...]}；null/空 = 真。
func check(cond: Variant) -> bool:
	if cond == null:
		return true
	if cond is String:
		return String(cond).is_empty() or get_flag(cond)
	if cond is Array:
		for c in cond:
			if not check(c):
				return false
		return true
	if cond is Dictionary:
		var d: Dictionary = cond
		if d.has("not"):
			return not check(d["not"])
		if d.has("all"):
			return check(d["all"])
		if d.has("any"):
			for c in d["any"]:
				if check(c):
					return true
			return false
	push_warning("[StoryFlags] 看不懂的條件：%s" % str(cond))
	return false


func all_flags() -> Dictionary:
	return _flags.duplicate()


## 測試用：清空
func reset() -> void:
	_flags.clear()

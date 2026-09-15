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


## ── 存檔 ──
## 只吐純資料（String → bool）。SaveManager 負責寫檔，本節點不碰檔案系統。
func serialize() -> Dictionary:
	var out := {}
	for k in _flags:
		if bool(_flags[k]):
			out[String(k)] = true          # 只存為真的旗標；false 等同不存在
	return out


## 從存檔還原。**不發 flag_changed** —— 還原時世界物件都還沒建好（或正要重建），
## 逐一發訊號會讓監聽者（WorldInteraction 的前置閘、受傷妖怪事件）在半成品
## 狀態下誤觸發演出。載入完成後由 SaveManager 統一重建場景。
func deserialize(data: Dictionary) -> void:
	_flags.clear()
	for k in data:
		if bool(data[k]):
			_flags[String(k)] = true


## 測試用：清空
func reset() -> void:
	_flags.clear()

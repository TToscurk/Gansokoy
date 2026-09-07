extends Node
## DialogueManager —— 對話流程（autoload）。
##
## 資料：res://data/dialogue/<dialogue_id>.json
##   { "start": "node_id" | [ {"if": cond, "node": id}, ... ],
##     "nodes": { id: { speaker, portrait, text, choices:[{text,next}], next,
##                      set_flags:[...], quest_event:{type,target} , "if": cond } } }
## 立繪：res://data/portraits.json  { character_id: { name, portraits: {state: path} } }
##
## 只發 signal；UI 與玩家鎖定由監聽者處理。往下只呼叫 QuestManager / StoryFlags。

signal dialogue_started(dialogue_id: String)
signal line_shown(speaker_name: String, portrait: Texture2D, text: String, choices: PackedStringArray)
signal dialogue_ended(dialogue_id: String)

const DIALOGUE_DIR := "res://data/dialogue/"
const PORTRAITS_PATH := "res://data/portraits.json"

var _portraits: Dictionary = {}
var _dialogue_id := ""
var _nodes: Dictionary = {}
var _current := ""
var _choices_next: Array = []


func _ready() -> void:
	_portraits = _load_json(PORTRAITS_PATH)


func is_active() -> bool:
	return not _dialogue_id.is_empty()


func start(dialogue_id: String) -> bool:
	if is_active():
		return false
	var data := _load_json(DIALOGUE_DIR + dialogue_id + ".json")
	if data.is_empty() or not data.has("nodes"):
		push_warning("[Dialogue] 讀不到對話 %s" % dialogue_id)
		return false
	_nodes = data["nodes"]
	var first := _resolve_start(data.get("start"))
	if first.is_empty():
		push_warning("[Dialogue] %s 沒有符合條件的起點" % dialogue_id)
		return false
	_dialogue_id = dialogue_id
	dialogue_started.emit(dialogue_id)
	_show(first)
	return true


## 沒有選項時：前進到 next；有選項時：index 選哪個。
func advance(choice_index: int = -1) -> void:
	if not is_active():
		return
	var next: Variant = null
	if _choices_next.size() > 0:
		if choice_index < 0 or choice_index >= _choices_next.size():
			return
		next = _choices_next[choice_index]
	else:
		next = _nodes[_current].get("next")
	if next == null or String(next).is_empty():
		_end()
	else:
		_show(String(next))


func _show(node_id: String) -> void:
	if not _nodes.has(node_id):
		push_warning("[Dialogue] 沒有節點 %s" % node_id)
		_end()
		return
	var n: Dictionary = _nodes[node_id]
	# 條件不成立就跳過到 next
	if not StoryFlags.check(n.get("if")):
		var nx: Variant = n.get("next")
		if nx == null:
			_end()
		else:
			_show(String(nx))
		return
	_current = node_id
	# 副作用：先於顯示，這樣同一節點的 text 能反映結果也無妨
	for f in n.get("set_flags", []):
		StoryFlags.set_flag(String(f), true)
	if n.has("quest_event"):
		var ev: Dictionary = n["quest_event"]
		QuestManager.report_event(ev.get("type", ""), String(ev.get("target", "")), int(ev.get("amount", 1)))
	_choices_next.clear()
	var labels := PackedStringArray()
	for c in n.get("choices", []):
		if not StoryFlags.check(c.get("if")):
			continue
		labels.append(String(c.get("text", "…")))
		_choices_next.append(c.get("next"))
	var speaker_id := String(n.get("speaker", ""))
	line_shown.emit(_speaker_name(speaker_id), _portrait(speaker_id, String(n.get("portrait", "normal"))),
		String(n.get("text", "")), labels)


func _end() -> void:
	var id := _dialogue_id
	_dialogue_id = ""
	_nodes = {}
	_current = ""
	_choices_next.clear()
	dialogue_ended.emit(id)


func _resolve_start(start: Variant) -> String:
	if start is String:
		return start
	if start is Array:
		for e in start:
			if e is Dictionary and StoryFlags.check(e.get("if")):
				return String(e.get("node", ""))
	return ""


func _speaker_name(character_id: String) -> String:
	var c: Dictionary = _portraits.get(character_id, {})
	return String(c.get("name", character_id))


func _portrait(character_id: String, state: String) -> Texture2D:
	var c: Dictionary = _portraits.get(character_id, {})
	var table: Dictionary = c.get("portraits", {})
	var path := String(table.get(state, table.get("normal", "")))
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return v if v is Dictionary else {}

extends Area3D
class_name WorldInteraction
## WorldInteraction —— 掛在建築／門口／神社的通用互動區。
##
## 玩家（group "player"）進入 → prompt_changed("[E] 拜訪")；離開 → prompt_changed("")。
## 在區內按 interact → 起對話（dialogue_id）並／或回報任務事件。
## 不認識 UI、不認識 main；提示字由 main.gd 依 group "world_interaction" 接線。

signal prompt_changed(text: String)
signal interacted(interaction_id: String)

@export var interaction_id := ""
@export var interaction_label := "拜訪"
## 顯示在提示上方的地點名（可空）
@export var place_name := ""
@export var dialogue_id := ""
## 沒對話時直接回報任務事件；有對話則交給對話節點的 quest_event
@export_enum("NONE", "REACH", "INTERACT", "TALK", "DEFEAT") var quest_event_type := "NONE"
@export var quest_target_id := ""
@export var enabled := true
## 進區即自動觸發（獨白／事件），不需按 E；prompt 不顯示
@export var auto_trigger := false
## 設了就只觸發一次：觸發後立 flag，flag 為真時整個互動區停用
@export var once_flag := ""
## 設了就「這個旗標為真時整區停用」——劇情推進後就不該再演的台詞用。
## 例：見過靈夢後，人里口的「先去山上看看」獨白已經過時。
@export var skip_flag := ""

var _player_inside := false


func _ready() -> void:
	add_to_group("world_interaction")
	monitoring = true
	body_entered.connect(_on_enter)
	body_exited.connect(_on_exit)


func _on_enter(body: Node3D) -> void:
	if not _is_player(body):
		return
	_player_inside = true
	if _suppressed():
		return
	if auto_trigger:
		if enabled and not DialogueManager.is_active():
			interact()
		return
	_refresh_prompt()
	# REACH 型：進區即回報（QuestManager 自己防重複）
	if quest_event_type == "REACH" and enabled:
		QuestManager.report_event("REACH", quest_target_id)


func _on_exit(body: Node3D) -> void:
	if not _is_player(body):
		return
	_player_inside = false
	prompt_changed.emit("")


func _unhandled_input(event: InputEvent) -> void:
	if not _player_inside or not enabled or _suppressed():
		return
	if DialogueManager.is_active():
		return
	if event.is_action_pressed("interact") and not event.is_echo():
		get_viewport().set_input_as_handled()
		interact()


func interact() -> void:
	interacted.emit(interaction_id)
	if not once_flag.is_empty():
		StoryFlags.set_flag(once_flag, true)
	if not dialogue_id.is_empty():
		DialogueManager.start(dialogue_id)
	elif quest_event_type != "NONE" and quest_event_type != "REACH":
		QuestManager.report_event(quest_event_type, quest_target_id)


func prompt_text() -> String:
	if not enabled or auto_trigger or _suppressed():
		return ""
	# 按 E 沒有任何後果的互動區不得顯示提示。REACH 型是「進區即完成」，
	# 按鍵完全不參與；先前它們照樣印出「[E] 拜訪」，玩家按了什麼也沒發生。
	if not _has_interact_payload():
		return ""
	var head := "" if place_name.is_empty() else place_name + "\n"
	return "%s[E] %s" % [head, interaction_label]


## 按 E 是否真的會做事：起對話，或回報非 REACH 的任務事件。
func _has_interact_payload() -> bool:
	if not dialogue_id.is_empty():
		return true
	return quest_event_type != "NONE" and quest_event_type != "REACH"


## 這一區現在該不該完全沉默（已觸發過，或劇情已推進過去）。
func _suppressed() -> bool:
	if not once_flag.is_empty() and StoryFlags.get_flag(once_flag):
		return true
	if not skip_flag.is_empty() and StoryFlags.get_flag(skip_flag):
		return true
	return false


func _refresh_prompt() -> void:
	prompt_changed.emit(prompt_text() if _player_inside else "")


func _is_player(body: Node) -> bool:
	return body.is_in_group("player")

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
@export var enabled := true: set = _set_enabled
## 進區即自動觸發（獨白／事件），不需按 E；prompt 不顯示
@export var auto_trigger := false
## 設了就只觸發一次：觸發後立 flag，flag 為真時整個互動區停用
@export var once_flag := ""
## 設了就「這個旗標為真時整區停用」——劇情推進後就不該再演的台詞用。
## 例：見過靈夢後，人里口的「先去山上看看」獨白已經過時。
@export var skip_flag := ""
## 設了就「這個旗標為真**之前**整區停用」——劇情順序保護。
##
## ⚠ 為什麼需要：獸道北端的傳送點沒有任何前置條件，玩家在 MQ00 階段就能走到
##   博麗神社按 E 跟靈夢把 first_* 全段演完。met_reimu 一立，之後 MQ04
##   可能被早到事件瞬間補完，玩家回頭找靈夢只剩 repeat 兩句 —— 序章核心對話
##   （「先看妖怪要做什麼」與受傷毛玉的回照）就這樣永久消失，而且玩家不會知道。
@export var require_flag := ""
## 設了就「這個任務尚未開始之前整區停用」（active 或已完成都算達成）。
## 比 require_flag 直接：劇情順序本來就是任務鏈定義的，不必另立一個旗標。
## 例：拜殿的靈夢對話設 "MQ04" —— 序章走到「山上的巫女」才談得起來。
@export var require_quest := ""

var _player_inside := false
## 正在等目前這段對話結束、好補播自己的 auto_trigger 獨白
var _waiting_for_dialogue := false


func _ready() -> void:
	add_to_group("world_interaction")
	monitoring = true
	body_entered.connect(_on_enter)
	body_exited.connect(_on_exit)
	# ⚠ require_flag / require_quest 解除的那一刻，玩家**可能已經站在區內**。
	#   Area3D 的 body_entered 只在跨越邊界那一幀發出，所以跟 _set_enabled 一樣
	#   需要主動重判一次，否則前置一解除這區就永遠不會再發動。
	if not require_flag.is_empty() or not require_quest.is_empty():
		var sf := _story_flags()
		if sf != null:
			sf.flag_changed.connect(_on_gate_changed)
		var qm := _quest_mgr()
		if qm != null:
			qm.quest_started.connect(_on_gate_changed)
			qm.quest_completed.connect(_on_gate_changed)


## 前置條件可能剛剛解除 —— 玩家站在區內就補發動（或至少把提示字亮出來）。
func _on_gate_changed(_a: Variant = null, _b: Variant = null) -> void:
	if not _player_inside or not enabled or _suppressed():
		return
	if auto_trigger:
		_try_auto_trigger()
	elif quest_event_type == "REACH":
		var qm := _quest_mgr()
		if qm != null:
			qm.report_event("REACH", quest_target_id)
	else:
		_refresh_prompt()


func _on_enter(body: Node3D) -> void:
	if not _is_player(body):
		return
	_player_inside = true
	if _suppressed():
		return
	if auto_trigger:
		if enabled:
			_try_auto_trigger()
		return
	_refresh_prompt()
	# REACH 型：進區即回報（QuestManager 自己防重複）
	if quest_event_type == "REACH" and enabled:
		var qm := _quest_mgr()
		if qm != null:
			qm.report_event("REACH", quest_target_id)


## auto_trigger 的實際發動。對話中不能插隊，但**不得就此丟掉**——
## 玩家常在前一段獨白還沒讀完就走進下一區，之前那一幕會永遠消失
## （once_flag 沒立、事件沒回報，回頭再走也不會重播）。
## 這裡改成：對話中就等它結束，玩家若還站在區內就補播。
func _try_auto_trigger() -> void:
	if _suppressed():
		return
	var dm := _dialogue_mgr()
	if dm == null or not dm.is_active():
		interact()
		return
	if _waiting_for_dialogue:
		return
	_waiting_for_dialogue = true
	dm.dialogue_ended.connect(_on_dialogue_ended_retry, CONNECT_ONE_SHOT)


func _on_dialogue_ended_retry(_id: String) -> void:
	_waiting_for_dialogue = false
	# 玩家已經離開這一區就不補了——他人都走了還硬跳獨白更怪。
	if not _player_inside or not enabled or _suppressed():
		return
	# 同一幀可能又有別的對話接著起，交給 call_deferred 再判一次。
	call_deferred("_try_auto_trigger")


## enabled 由 false 翻成 true 時，**玩家可能已經站在區內**。
##
## ⚠ Area3D 的 body_entered 只在「跨越邊界的那一幀」發出；區域是後來才啟用的，
##   站在裡面的人不會再觸發一次。歷史案例（該事件點已於 2026-09-17 移除）：
##   MQ03 的果實獨白區是在毛玉逃光後才 enabled 的，但玩家本來就站在群旁邊，
##   → 獨白不播、旗標不立、任務永久卡住。
##   （測試裡看起來像「站位沒站好」，實際是任何正常玩法都會踩到。）
##   任何「先關著、事件發生後才開」的互動區都靠這段補觸發。
func _set_enabled(v: bool) -> void:
	var was := enabled
	enabled = v
	if not v or was == v or not is_inside_tree() or not _player_inside:
		return
	if _suppressed():
		return
	if auto_trigger:
		_try_auto_trigger()
	elif quest_event_type == "REACH":
		var qm := _quest_mgr()
		if qm != null:
			qm.report_event("REACH", quest_target_id)
	else:
		_refresh_prompt()


func _on_exit(body: Node3D) -> void:
	if not _is_player(body):
		return
	_player_inside = false
	prompt_changed.emit("")


func _unhandled_input(event: InputEvent) -> void:
	if not _player_inside or not enabled or _suppressed():
		return
	var dm := _dialogue_mgr()
	if dm != null and dm.is_active():
		return
	if event.is_action_pressed("interact") and not event.is_echo():
		get_viewport().set_input_as_handled()
		interact()


func interact() -> void:
	# ⚠ 守衛放在這裡，不是只放在 _unhandled_input。這個方法是公開的——劇情腳本、
	#   _set_enabled、auto_trigger 補播都會直接呼叫它。少了這一行，前置條件
	#   （require_quest / require_flag）就只擋得住按鍵，擋不住程式路徑。
	if not enabled or _suppressed():
		return
	interacted.emit(interaction_id)
	var sf := _story_flags()
	if not once_flag.is_empty() and sf != null:
		sf.set_flag(once_flag, true)
	if not dialogue_id.is_empty():
		var dm := _dialogue_mgr()
		if dm != null:
			dm.start(dialogue_id)
	elif quest_event_type != "NONE" and quest_event_type != "REACH":
		var qm := _quest_mgr()
		if qm != null:
			qm.report_event(quest_event_type, quest_target_id)


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


## 這一區現在該不該完全沉默（前置未達、已觸發過，或劇情已推進過去）。
func _suppressed() -> bool:
	var sf := _story_flags()
	var qm := _quest_mgr()
	if not require_flag.is_empty():
		if sf == null or not sf.get_flag(require_flag):
			return true
	if not require_quest.is_empty():
		if qm == null or not (qm.is_active(require_quest) or qm.is_completed(require_quest)):
			return true
	if not once_flag.is_empty() and sf != null and sf.get_flag(once_flag):
		return true
	if not skip_flag.is_empty() and sf != null and sf.get_flag(skip_flag):
		return true
	return false


func _refresh_prompt() -> void:
	prompt_changed.emit(prompt_text() if _player_inside else "")


func _is_player(body: Node) -> bool:
	return body.is_in_group("player")


func _story_flags() -> Node:
	return get_tree().root.get_node_or_null("StoryFlags") if is_inside_tree() else null


func _quest_mgr() -> Node:
	return get_tree().root.get_node_or_null("QuestManager") if is_inside_tree() else null


func _dialogue_mgr() -> Node:
	return get_tree().root.get_node_or_null("DialogueManager") if is_inside_tree() else null

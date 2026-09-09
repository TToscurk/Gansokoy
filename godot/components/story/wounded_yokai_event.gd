extends Area3D
class_name WoundedYokaiEvent
## 受傷妖怪事件 —— 序章的唯一選擇（靠近／離開）。
##
## 這一幕是緣一角色弧線的起點。設計文件：
## 「如果前面玩家什麼都沒遇到，靈夢那句『妖怪不代表它該死』會很像作者硬塞設定。」
##
## 流程：
##   踏入 → 播「別過來……」對話（含選項）
##   選「靠近」 → 緣一收刀 → 毛玉慢慢退後、逃走 → 「……它在害怕我。」
##   選「離開」 → 毛玉留在原地，之後路過會逃
##
## 對話系統只管文字與旗標；「收刀」「毛玉逃走」這兩個世界演出由本節點監聽旗標執行。
## 不改 DialogueManager —— 它不該認識毛玉。

@export var kedama_scene: PackedScene
## 毛玉相對本節點的位置
@export var kedama_offset := Vector3(2.0, 0.0, -3.0)
@export var dialogue_id := "yoriichi_wounded_yokai"
@export var once_flag := "wounded_yokai_played"
## 選靠近時立的旗標（由對話 set_flags）；本節點監聽它來演收刀與逃走
@export var approach_flag := "spared_wounded_yokai"
## 選離開時立的旗標
@export var leave_flag := "left_wounded_yokai"
## 完成後回報的任務事件
@export var quest_target_id := "trail_wounded_yokai"

var _kedama: Node3D = null
var _started := false


func _ready() -> void:
	add_to_group("story_event")
	monitoring = true
	body_entered.connect(_on_enter)
	StoryFlags.flag_changed.connect(_on_flag)
	# 毛玉先擺好：玩家遠遠就看得到它縮在那裡
	if kedama_scene != null and not StoryFlags.get_flag(once_flag):
		_kedama = kedama_scene.instantiate()
		get_parent().call_deferred("add_child", _kedama)
		call_deferred("_place_kedama")


func _place_kedama() -> void:
	if _kedama == null:
		return
	_kedama.global_position = global_position + kedama_offset
	_kedama.set("mode", 2)   # Kedama.Mode.WOUNDED


func _on_enter(body: Node3D) -> void:
	if _started or not body.is_in_group("player"):
		return
	if StoryFlags.get_flag(once_flag):
		return
	_started = true
	StoryFlags.set_flag(once_flag, true)
	if not DialogueManager.is_active():
		DialogueManager.start(dialogue_id)


func _on_flag(flag: String, value: bool) -> void:
	if not value:
		return
	if flag == approach_flag:
		_do_approach()
	elif flag == leave_flag:
		_do_leave()


## 靠近：緣一收刀 → 毛玉退後逃走
func _do_approach() -> void:
	var ps := get_tree().get_nodes_in_group("player")
	if ps.size() > 0:
		var p: Node = ps[0]
		# 刀在手上才收；沒拔就不動作
		if p.get("sword_state") == 2 and p.has_method("request_sword_toggle"):   # DRAWN
			p.request_sword_toggle()
	if _kedama != null and is_instance_valid(_kedama):
		# 先讓對話把「我不會傷你」講完，再退後。用 timer 而不是等 dialogue_ended，
		# 因為對話結束時玩家已經看到「它在害怕我」，那時毛玉應該已經在跑了。
		var t := create_tween()
		t.tween_interval(2.2)
		t.tween_callback(func() -> void:
			if is_instance_valid(_kedama):
				_kedama.call("flee_away"))
	_finish()


## 離開：毛玉留著，之後路過會嚇跑（轉成 FLEE 模式）
func _do_leave() -> void:
	if _kedama != null and is_instance_valid(_kedama):
		_kedama.set("mode", 1)   # Kedama.Mode.FLEE
		_kedama.set("_noticed", false)
	_finish()


func _finish() -> void:
	if not quest_target_id.is_empty():
		QuestManager.report_event("REACH", quest_target_id)

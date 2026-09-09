extends Area3D
class_name CombatEncounter
## 戰鬥遭遇區 —— 玩家踏入即生成敵人，全滅後回報任務事件。
##
## 為什麼敵人不是預先擺在場上：預擺的敵人會在玩家還沒接到任務時就開始追人，
## 而且離開再回來時狀態不對。這裡採「進區才生、清空才算完成」。
##
## 依賴方向：CombatEncounter → QuestManager / StoryFlags / DialogueManager。
## 不認識 main、不認識玩家的內部實作 —— 只用 group "player" 找目標。

signal encounter_started
signal enemy_died(remaining: int)
signal encounter_cleared

## 敵人場景（EnemyWolf 等，需有 died 訊號與 take_hit()）
@export var enemy_scene: PackedScene
## 生成點（相對本節點的局部座標）。留空則在本節點原點生一隻。
@export var spawn_offsets: Array[Vector3] = []
## 生成時從這個高度往下射線找地面，避免浮空或埋地
@export var ground_probe_height := 20.0

@export_group("Quest")
## 全滅後回報的任務事件（DEFEAT）
@export var quest_target_id := ""
## 全滅後立起的劇情旗標
@export var clear_flag := ""
## 這個旗標為真時整區停用（已打過就不再生）
@export var skip_flag := ""

@export_group("Dialogue")
## 遭遇開始時播（例：「……妖怪。」）
@export var intro_dialogue := ""
## 全滅後播（例：戰後停頓「和鬼……不同。」）
@export var clear_dialogue := ""
## 全滅到播對話之間的停頓秒數。
## 設計要求：怪死了不要馬上跳任務完成，先讓音樂降下來、給一個沉默。
@export var clear_delay := 1.6

var _spawned: Array = []
var _alive := 0
var _started := false
var _cleared := false


func _ready() -> void:
	add_to_group("combat_encounter")
	monitoring = true
	body_entered.connect(_on_body_entered)


func _suppressed() -> bool:
	return not skip_flag.is_empty() and StoryFlags.get_flag(skip_flag)


func _on_body_entered(body: Node3D) -> void:
	if _started or _suppressed():
		return
	if not body.is_in_group("player"):
		return
	_begin()


func _begin() -> void:
	_started = true
	if enemy_scene == null:
		push_warning("[遭遇] %s 沒有指定 enemy_scene" % name)
		return
	var offsets := spawn_offsets
	if offsets.is_empty():
		offsets = [Vector3.ZERO] as Array[Vector3]
	var players := get_tree().get_nodes_in_group("player")
	var player: Node3D = players[0] if players.size() > 0 else null
	for off in offsets:
		var e: Node3D = enemy_scene.instantiate()
		# 掛在本區的父節點下，而不是本區底下 —— Area3D 的 monitoring
		# 會把生在裡面的敵人也當成進入事件來源，徒增噪音。
		get_parent().add_child(e)
		var world_pos := global_position + off
		e.global_position = Vector3(world_pos.x, _ground_y(world_pos), world_pos.z)
		if player != null and "target" in e:
			e.set("target", player)
		if e.has_signal("died"):
			e.died.connect(_on_enemy_died)
		_spawned.append(e)
		_alive += 1
	encounter_started.emit()
	if not intro_dialogue.is_empty() and not DialogueManager.is_active():
		DialogueManager.start(intro_dialogue)


## 生成點的地面高度。射線排除邊界牆（40 m 高的隱形擋牆會被誤認成地面）。
func _ground_y(p: Vector3) -> float:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(
		Vector3(p.x, p.y + ground_probe_height, p.z),
		Vector3(p.x, p.y - ground_probe_height, p.z))
	var ex: Array[RID] = []
	for k in 6:
		q.exclude = ex
		var hit := space.intersect_ray(q)
		if not hit.has("position"):
			return p.y
		var col: Object = hit.get("collider")
		var nm := String(col.name) if col else ""
		if not (nm.contains("Boundary") or nm.contains("邊界") or nm.contains("boundary")):
			return float(hit.position.y) + 0.1
		ex.append(hit.rid)
	return p.y


func _on_enemy_died() -> void:
	_alive = maxi(0, _alive - 1)
	enemy_died.emit(_alive)
	if _alive > 0 or _cleared:
		return
	_cleared = true
	# 停頓：怪死了不要馬上 Quest Complete。先給一個沉默，再播戰後獨白。
	var t := create_tween()
	t.tween_interval(clear_delay)
	t.tween_callback(_finish)


func _finish() -> void:
	if not clear_flag.is_empty():
		StoryFlags.set_flag(clear_flag, true)
	if not clear_dialogue.is_empty() and not DialogueManager.is_active():
		DialogueManager.start(clear_dialogue)
	elif not quest_target_id.is_empty():
		# 沒有戰後對話時直接回報；有對話的話由對話節點的 quest_event 回報，
		# 這樣「任務完成」會出現在玩家讀完台詞之後，而不是打完的瞬間。
		QuestManager.report_event("DEFEAT", quest_target_id)
	encounter_cleared.emit()


## 測試用：直接把場上敵人清掉
func force_clear() -> void:
	for e in _spawned:
		if is_instance_valid(e) and e.has_method("execute_deathblow"):
			if e.get("posture") != null:
				e.posture.apply_damage(9999.0, 0.0)

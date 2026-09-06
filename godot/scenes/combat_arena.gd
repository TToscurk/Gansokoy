extends Node3D
## 隻狼式戰鬥場：把玩家、敵人、HUD 接成一場真的能打的戰鬥。
##
## 這個節點只做「接線」——所有規則都在 posture.gd / enemy_samurai.gd /
## yoriichi_character.gd / combat_hud.gd 裡，這裡不重複實作任何戰鬥邏輯。

@export var enemy_scene: PackedScene = preload("res://characters/combat/enemy_samurai.tscn")

var _player: Node = null
var _hud: Node = null
var _bound: Array[Node] = []


func _ready() -> void:
	_player = get_node_or_null("Player")
	_hud = get_node_or_null("CombatHUD")
	if _player == null or _hud == null:
		return

	_player.add_to_group("player")

	# 玩家數值 → HUD
	if _player.posture != null:
		_player.posture.health_changed.connect(_hud.set_player_health)
		_player.posture.posture_changed.connect(_hud.set_player_posture)
		_hud.set_player_health(_player.posture.health, _player.posture.max_health)
		_hud.set_player_posture(_player.posture.posture, _player.posture.max_posture)

	# 彈刀成功 → HUD 閃光（玩家判斷「彈到了沒」的唯一即時回饋）
	if _player.has_signal("player_was_hit"):
		_player.player_was_hit.connect(_on_player_was_hit)
	if _player.has_signal("lock_target_changed"):
		_player.lock_target_changed.connect(_on_lock_target_changed)

	for e in _find_enemies():
		_bind_enemy(e)


## 以腳本路徑辨識敵人，而不是節點名或 class_name（class_name 需重匯才註冊）。
func _find_enemies() -> Array[Node]:
	var out: Array[Node] = []
	for n in find_children("*", "CharacterBody3D", true, false):
		var s: Variant = n.get_script()
		if s != null and String(s.resource_path).ends_with("enemy_samurai.gd"):
			out.append(n)
	return out


func _bind_enemy(e: Node) -> void:
	if e in _bound:
		return
	_bound.append(e)
	e.target = _player
	e.attack_windup.connect(_on_enemy_windup.bind(e))
	e.attack_struck.connect(_on_enemy_struck.bind(e))
	e.became_vulnerable.connect(_on_enemy_vulnerable.bind(e))
	e.died.connect(_on_enemy_died.bind(e))
	e.posture_changed.connect(_on_enemy_numbers_changed.bind(e))
	e.health_changed.connect(_on_enemy_numbers_changed.bind(e))


func _on_player_was_hit(info: Dictionary) -> void:
	if String(info.get("result", "")) == "deflect":
		_hud.flash_deflect()


func _on_lock_target_changed(t: Node3D) -> void:
	if t == null:
		_hud.hide_enemy()
		_hud.hide_perilous()
		return
	var p = t.get("posture")
	if p == null:
		return
	_hud.show_enemy(_enemy_name(t), p.health, p.max_health, p.posture, p.max_posture)
	if t.has_method("can_deathblow") and t.can_deathblow():
		_hud.show_deathblow()


func _enemy_name(e: Node) -> String:
	var s: Variant = e.get_script()
	if s != null and String(s.resource_path).ends_with("enemy_samurai.gd"):
		return "侍"
	return String(e.name)


## 只有被鎖定的敵人才更新 HUD，避免多敵時數值互相蓋掉。
func _is_shown(e: Node) -> bool:
	return _player != null and _player.lock_target == e


func _on_enemy_numbers_changed(_a: float, _b: float, e: Node) -> void:
	if not _is_shown(e):
		return
	var p = e.get("posture")
	if p != null:
		_hud.update_enemy(p.health, p.max_health, p.posture, p.max_posture)


func _on_enemy_windup(perilous: bool, e: Node) -> void:
	if perilous and _is_shown(e):
		_hud.show_perilous()


func _on_enemy_struck(_damage: float, e: Node) -> void:
	if _is_shown(e):
		_hud.hide_perilous()


func _on_enemy_vulnerable(e: Node) -> void:
	if _is_shown(e):
		_hud.show_deathblow()


func _on_enemy_died(e: Node) -> void:
	if _is_shown(e):
		_hud.hide_deathblow()
		_hud.hide_enemy()
	if _player != null and _player.lock_target == e:
		_player.set_lock_target(null)

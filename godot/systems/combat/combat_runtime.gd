extends Node
class_name CombatRuntime
## 把戰鬥系統接進主世界 —— HUD、型選單、玩家數值、場上敵人。
##
## 為什麼是程式掛而不是寫進 main.tscn：
##   使用者常開著 Godot 編輯器手拖 transform 而不存檔。agent 寫 .tscn 會
##   互相覆蓋。這一層純 .gd，載入時自己生 HUD 與選單，不動任何場景檔。
##
## 這個節點只做接線 —— 規則全在 posture.gd / yoriichi_character.gd /
## enemy_*.gd / combat_hud.gd / form_menu.gd 裡，這裡不重複實作戰鬥邏輯。
## 對照 scenes/combat_arena.gd（測試場的同等接線），行為刻意保持一致。

const FormMenuScript = preload("res://ui/form_menu.gd")
const HUD_SCENE := "res://ui/combat_hud.tscn"

## 型選單的按鍵。project.godot 由使用者管理，agent 不寫入 ——
## 這個 action 在執行期註冊，缺了就自己補。
##
## ⚠ 不可用 Tab：project.godot 裡 Tab 已經綁給 lock_on（鎖定敵人），
##   兩個 action 綁同一顆鍵會同時觸發（實測：按 Tab 開選單的同時也切了鎖定）。
##   C 鍵目前未被任何 action 使用（實測 project.godot 的 [input] 全表）。
const FORM_MENU_ACTION := "form_menu"
const FORM_MENU_KEY := KEY_C

var hud: Node = null
var menu: Node = null

var _player: Node = null
var _bound: Array[Node] = []


func _ready() -> void:
	name = "CombatRuntime"
	add_to_group("combat_runtime")
	_ensure_form_menu_action()


## Tab 開型選單。註冊在 InputMap（執行期），不改 project.godot。
func _ensure_form_menu_action() -> void:
	if InputMap.has_action(FORM_MENU_ACTION):
		return
	InputMap.add_action(FORM_MENU_ACTION)
	var ev := InputEventKey.new()
	ev.physical_keycode = FORM_MENU_KEY
	InputMap.action_add_event(FORM_MENU_ACTION, ev)


## 由 main.gd 呼叫：接上玩家，生出 HUD 與型選單。
func bind_player(p: Node) -> void:
	if p == null or _player == p:
		return
	_player = p
	if not _player.is_in_group("player"):
		_player.add_to_group("player")

	_spawn_hud()
	_spawn_menu()
	_bind_player_signals()
	# 起始隱藏：探索時畫面要乾淨，第一次交手才浮出來。
	_hud_alpha = 0.0
	_apply_hud_alpha()


func _spawn_hud() -> void:
	if hud != null:
		return
	var scene: PackedScene = load(HUD_SCENE)
	if scene == null:
		push_warning("[戰鬥] 找不到 combat_hud.tscn，HUD 不會顯示")
		return
	hud = scene.instantiate()
	add_child(hud)


func _spawn_menu() -> void:
	if menu != null:
		return
	menu = FormMenuScript.new()
	menu.name = "FormMenu"
	add_child(menu)
	menu.bind_player(_player)
	menu.menu_opened.connect(_on_menu_opened)
	menu.menu_closed.connect(_on_menu_closed)


func _bind_player_signals() -> void:
	var p: Variant = _player.get("posture")
	if p != null and hud != null:
		p.health_changed.connect(hud.set_player_health)
		p.posture_changed.connect(hud.set_player_posture)
		hud.set_player_health(p.health, p.max_health)
		hud.set_player_posture(p.posture, p.max_posture)
	if _player.has_signal("player_was_hit"):
		_player.player_was_hit.connect(_on_player_was_hit)
	if _player.has_signal("lock_target_changed"):
		_player.lock_target_changed.connect(_on_lock_target_changed)
	if _player.has_signal("breath_changed") and hud != null and hud.has_method("set_player_breath"):
		_player.breath_changed.connect(hud.set_player_breath)
		# 呼吸會漲代表打中了／彈到了 —— 那就是交手。
		_player.breath_changed.connect(func(_c: float, _m: float) -> void: mark_combat())
		hud.set_player_breath(float(_player.get("sun_breath_gauge")), float(_player.get("sun_breath_max")))


func _unhandled_input(event: InputEvent) -> void:
	if menu == null or _player == null:
		return
	if event.is_action_pressed(FORM_MENU_ACTION):
		# 選單自己處理「開著時再按 C = 關」，這裡只負責開。
		if not menu.open:
			menu.toggle()
			get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
# HUD 自動顯隱：探索時完全不顯示，進入戰鬥才浮出來
#
# 使用者要求：「沒有戰鬥的時候血量之類的 UI 隱藏」「不要太多提示」。
# 判定「在戰鬥中」的條件（任一成立）：
#   * 附近有活著的敵人（in_combat_range 內）
#   * 剛受過傷 / 剛出過手（combat_linger 秒內）
#   * 型選單開著
# 三者皆不成立 → 淡出。拔刀本身**不算**戰鬥：緣一可以只是握著刀走路。
# ---------------------------------------------------------------------------

## 多近算「捲入戰鬥」。
@export var in_combat_range := 18.0
## 最後一次交手後，HUD 還留在畫面上的秒數。
@export var combat_linger := 5.0
## HUD 淡入／淡出時間。
@export var hud_fade_time := 0.35

var _combat_timer := 0.0
var _hud_shown := false
var _hud_alpha := 0.0


## 交手了：重置留存計時（受擊、命中、鎖定都算）。
func mark_combat() -> void:
	_combat_timer = combat_linger


func _process(delta: float) -> void:
	if hud == null or _player == null:
		return
	_combat_timer = maxf(_combat_timer - delta, 0.0)
	var want: bool = _combat_timer > 0.0 or _enemy_near() \
		or (menu != null and menu.open)
	if want != _hud_shown:
		_hud_shown = want
	var target: float = 1.0 if _hud_shown else 0.0
	if not is_equal_approx(_hud_alpha, target):
		var step: float = delta / maxf(hud_fade_time, 0.001)
		_hud_alpha = move_toward(_hud_alpha, target, step)
		_apply_hud_alpha()


func _apply_hud_alpha() -> void:
	var root: Control = hud.get_node_or_null("Root")
	if root != null:
		root.modulate.a = _hud_alpha
		root.visible = _hud_alpha > 0.01


## 附近有沒有活著的敵人。敵人數量在本專案是個位數，每幀掃不成問題。
func _enemy_near() -> bool:
	if not (_player is Node3D):
		return false
	var me: Vector3 = (_player as Node3D).global_position
	for n in get_tree().get_nodes_in_group("enemies"):
		if not (n is Node3D) or not is_instance_valid(n):
			continue
		var p: Variant = n.get("posture")
		if p != null and p.is_dead():
			continue
		if me.distance_to((n as Node3D).global_position) <= in_combat_range:
			return true
	return false


## 選單開著時鎖住玩家輸入，否則 WASD 會同時移動角色與移動游標。
func _on_menu_opened() -> void:
	if _player != null:
		_player.set("input_locked", true)


func _on_menu_closed() -> void:
	if _player != null:
		_player.set("input_locked", false)


# ---------------------------------------------------------------------------
# 敵人：進場時自動接線（CombatEncounter 是執行期生怪，不能只在 _ready 掃一次）
# ---------------------------------------------------------------------------

## 由 main.gd 在載圖後呼叫，也可在敵人生成後再呼叫一次。
func rescan_enemies() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		_bind_enemy(e)


func _bind_enemy(e: Node) -> void:
	if e == null or not is_instance_valid(e) or e in _bound:
		return
	_bound.append(e)
	if _player != null and "target" in e:
		e.set("target", _player)
	if e.has_signal("attack_windup"):
		e.attack_windup.connect(_on_enemy_windup.bind(e))
	if e.has_signal("attack_struck"):
		e.attack_struck.connect(_on_enemy_struck.bind(e))
	if e.has_signal("became_vulnerable"):
		e.became_vulnerable.connect(_on_enemy_vulnerable.bind(e))
	if e.has_signal("died"):
		e.died.connect(_on_enemy_died.bind(e))
	if e.has_signal("posture_changed"):
		e.posture_changed.connect(_on_enemy_numbers_changed.bind(e))
	if e.has_signal("health_changed"):
		e.health_changed.connect(_on_enemy_numbers_changed.bind(e))


## 只有被鎖定的敵人才更新 HUD，避免多敵時數值互相蓋掉。
func _is_shown(e: Node) -> bool:
	return _player != null and _player.get("lock_target") == e


func _on_player_was_hit(info: Dictionary) -> void:
	mark_combat()
	if hud != null and String(info.get("result", "")) == "deflect":
		hud.flash_deflect()


func _on_lock_target_changed(t: Node3D) -> void:
	if t != null:
		mark_combat()
	if hud == null:
		return
	if t == null:
		hud.hide_enemy()
		hud.hide_perilous()
		return
	var p: Variant = t.get("posture")
	if p == null:
		return
	hud.show_enemy(_enemy_name(t), p.health, p.max_health, p.posture, p.max_posture)
	if t.has_method("can_deathblow") and t.can_deathblow():
		hud.show_deathblow()


func _enemy_name(e: Node) -> String:
	var s: Variant = e.get_script()
	if s == null:
		return String(e.name)
	var path := String(s.resource_path)
	if path.ends_with("enemy_samurai.gd"):
		return "侍"
	if path.ends_with("enemy_wolf.gd"):
		return "山犬"
	return String(e.name)


func _on_enemy_numbers_changed(_a: float, _b: float, e: Node) -> void:
	mark_combat()
	if hud == null or not _is_shown(e):
		return
	var p: Variant = e.get("posture")
	if p != null:
		hud.update_enemy(p.health, p.max_health, p.posture, p.max_posture)


func _on_enemy_windup(perilous: bool, e: Node) -> void:
	mark_combat()
	if hud != null and perilous and _is_shown(e):
		hud.show_perilous()


func _on_enemy_struck(_damage: float, e: Node) -> void:
	if hud != null and _is_shown(e):
		hud.hide_perilous()


func _on_enemy_vulnerable(e: Node) -> void:
	if hud != null and _is_shown(e):
		hud.show_deathblow()


func _on_enemy_died(e: Node) -> void:
	if hud != null and _is_shown(e):
		hud.hide_deathblow()
		hud.hide_enemy()
	if _player != null and _player.get("lock_target") == e:
		_player.set_lock_target(null)
	_bound.erase(e)

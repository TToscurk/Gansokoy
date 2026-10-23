extends Control
class_name GensokyoHotbar
## 快捷列（右下）：只放玩家**真的按得出來**的招，不放假格子。
##   Q 刀（刀鍔）   R 玖ノ型 日暈龍（御札）   C 拾參ノ型（御札，呼吸滿才亮）
## 底下一把極淡的刀鞘剪影當基座。數值唯讀自 group "player"（不改任何遊戲邏輯）。
## 隨 CombatHUD 一起自動顯隱（探索時整組 HUD 淡出）。

const SLOTS := [
	{key = "Q", glyph = "刀", shape = GensokyoItemSlot.Shape.TSUBA, tip = "拔刀／納刀\n刀收在鞘裡時，其他招式都不會出手。"},
	{key = "R", glyph = "日暈", shape = GensokyoItemSlot.Shape.OFUDA, tip = "玖ノ型　日暈龍・頭舞\n連續迴旋；再按一次可銜接。"},
	{key = "C", glyph = "拾參", shape = GensokyoItemSlot.Shape.OFUDA, tip = "拾參ノ型\n日之呼吸滿時，十二型連放。"},
]

@export var slot_size := Vector2(46, 64)
@export var slot_gap := 14.0

var _slots: Array[GensokyoItemSlot] = []
var _player: Node = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for d in SLOTS:
		var s := GensokyoItemSlot.new()
		s.key_label = d.key
		s.glyph = d.glyph
		s.shape = d.shape
		s.tip = d.tip
		s.seed = float(_slots.size()) * 3.3 + 1.0
		add_child(s)
		_slots.append(s)
	get_viewport().size_changed.connect(_layout)
	_layout()


func _layout() -> void:
	var st := GensokyoStyle.current()
	var k := st.scale_for(self)
	var ss := slot_size * k
	var gap := slot_gap * k
	var total := ss.x * _slots.size() + gap * (_slots.size() - 1)
	custom_minimum_size = Vector2(total + 60.0 * k, ss.y + 26.0 * k)
	size = custom_minimum_size
	# 錨在右下：自己算位置（解析度縮放後尺寸會變，offset 不可靠）
	var parent_size := (get_parent() as Control).size if get_parent() is Control else get_viewport_rect().size
	position = parent_size - size - Vector2(40.0, 30.0) * k
	for i in _slots.size():
		var s := _slots[i]
		if s.shape == GensokyoItemSlot.Shape.TSUBA:
			s.size = Vector2(ss.y, ss.y) * 0.82
			s.position = Vector2(i * (ss.x + gap) - (s.size.x - ss.x) * 0.5, (ss.y - s.size.y) * 0.5)
		else:
			s.size = ss
			s.position = Vector2(i * (ss.x + gap), 0)
	queue_redraw()


func _draw() -> void:
	var st := GensokyoStyle.current()
	var k := st.scale_for(self)
	# 刀鞘剪影基座：非常淡
	GensokyoInk.katana(self, Vector2(-26.0 * k, slot_size.y * k + 12.0 * k), size.x + 20.0 * k, 5.0 * k, Color(st.ink_black, st.hud_background * 0.6))


func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		if _player == null:
			return
	var sword: int = int(_player.get("sword_state")) if _player.get("sword_state") != null else 0
	var drawn := sword == 2           # SwordState.DRAWN
	var gauge := float(_player.get("sun_breath_gauge")) if _player.get("sun_breath_gauge") != null else 0.0
	var cost := float(_player.get("form13_gauge_cost")) if _player.get("form13_gauge_cost") != null else 100.0
	var unlocked := bool(_player.get("form13_unlocked")) if _player.get("form13_unlocked") != null else false
	# Q：刀出鞘 = 亮
	_slots[0].selected = drawn
	# R：刀出鞘才用得出來
	_slots[1].locked = not drawn
	_slots[1].selected = false
	# C：呼吸量當「冷卻」顯示（墨退到哪 = 還差多少），滿了才亮
	var ready := drawn and (unlocked or gauge >= cost)
	_slots[2].cooldown = 0.0 if unlocked else clampf(1.0 - gauge / maxf(cost, 0.001), 0.0, 1.0)
	_slots[2].locked = not drawn
	_slots[2].selected = ready


func slot_states() -> Array:
	var out := []
	for s in _slots:
		out.append({key = s.key_label, selected = s.selected, locked = s.locked, cooldown = s.cooldown})
	return out

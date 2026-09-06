extends CanvasLayer
class_name CombatHUD
## 隻狼風戰鬥 HUD。全部用程式繪製，不依賴任何貼圖資產（避免美術債）。
##
## 可讀性規則（照抄隻狼真正有效的做法）：
##   * 軀幹槽由**中央往兩側**長，一眼看出離爆還有多遠。
##   * 軀幹越滿顏色越燙：白 → 橙 → 紅，並加快脈動。
##   * 血量分節顯示，比連續條更容易讀出「還剩幾下會死」。
##   * 彈刀成功時軀幹槽閃白 —— 這是玩家判斷「我彈到了沒」的唯一即時回饋。

const PERILOUS_GLYPH := "危"

var player_health_ratio := 1.0
var player_posture_ratio := 0.0
var enemy_health_ratio := 1.0
var enemy_posture_ratio := 0.0
## 彈刀閃光強度，1 → 0 自動衰減。
var deflect_flash := 0.0

@export var health_segments := 5
@export var deflect_flash_decay := 4.0
## 軀幹開始警示／進入危險的門檻。
@export_range(0.0, 1.0, 0.05) var posture_warn_at := 0.7
@export_range(0.0, 1.0, 0.05) var posture_danger_at := 0.9

var _pulse := 0.0
var _enemy_root: Control = null
var _perilous: Label = null
var _deathblow: Control = null
var _player_bars: Control = null
var _enemy_bars: Control = null
var _enemy_name: Label = null


func _ready() -> void:
	_enemy_root = get_node_or_null("Root/EnemyPanel")
	_enemy_bars = get_node_or_null("Root/EnemyPanel/Bars")
	_enemy_name = get_node_or_null("Root/EnemyPanel/Name")
	_perilous = get_node_or_null("Root/Perilous")
	_deathblow = get_node_or_null("Root/Deathblow")
	_player_bars = get_node_or_null("Root/PlayerBars")

	if _enemy_root:
		_enemy_root.visible = false
	if _perilous:
		_perilous.visible = false
		_perilous.text = PERILOUS_GLYPH
	if _deathblow:
		_deathblow.visible = false


func _process(delta: float) -> void:
	_pulse += delta * (2.0 + player_posture_ratio * 6.0)
	if deflect_flash > 0.0:
		deflect_flash = maxf(deflect_flash - delta * deflect_flash_decay, 0.0)
	if _perilous and _perilous.visible:
		# 危字脈動，讓它在混戰中抓得住眼睛。
		var a: float = 0.7 + 0.3 * sin(_pulse * 4.0)
		_perilous.modulate = Color(1.0, 0.25, 0.2, a)
	if _player_bars:
		_player_bars.queue_redraw()
	if _enemy_bars and _enemy_root and _enemy_root.visible:
		_enemy_bars.queue_redraw()


# ---------------------------------------------------------------------------
# 數值輸入
# ---------------------------------------------------------------------------

func set_player_health(current: float, maximum: float) -> void:
	player_health_ratio = clampf(current / maxf(maximum, 0.001), 0.0, 1.0)


func set_player_posture(current: float, maximum: float) -> void:
	player_posture_ratio = clampf(current / maxf(maximum, 0.001), 0.0, 1.0)


func show_enemy(display_name: String, health: float, max_health: float, posture: float, max_posture: float) -> void:
	enemy_health_ratio = clampf(health / maxf(max_health, 0.001), 0.0, 1.0)
	enemy_posture_ratio = clampf(posture / maxf(max_posture, 0.001), 0.0, 1.0)
	if _enemy_name:
		_enemy_name.text = display_name
	if _enemy_root:
		_enemy_root.visible = true


func update_enemy(health: float, max_health: float, posture: float, max_posture: float) -> void:
	enemy_health_ratio = clampf(health / maxf(max_health, 0.001), 0.0, 1.0)
	enemy_posture_ratio = clampf(posture / maxf(max_posture, 0.001), 0.0, 1.0)


func hide_enemy() -> void:
	if _enemy_root:
		_enemy_root.visible = false
	hide_deathblow()


func is_enemy_visible() -> bool:
	return _enemy_root != null and _enemy_root.visible


func show_perilous() -> void:
	if _perilous:
		_perilous.visible = true


func hide_perilous() -> void:
	if _perilous:
		_perilous.visible = false


func is_perilous_visible() -> bool:
	return _perilous != null and _perilous.visible


func perilous_text() -> String:
	return _perilous.text if _perilous else ""


func show_deathblow() -> void:
	if _deathblow:
		_deathblow.visible = true


func hide_deathblow() -> void:
	if _deathblow:
		_deathblow.visible = false


func is_deathblow_visible() -> bool:
	return _deathblow != null and _deathblow.visible


func flash_deflect() -> void:
	deflect_flash = 1.0


# ---------------------------------------------------------------------------
# 顏色規則
# ---------------------------------------------------------------------------

## 軀幹槽顏色：越滿越燙。彈刀閃光疊在最上層。
func posture_colour(ratio: float) -> Color:
	var c: Color
	if ratio >= posture_danger_at:
		c = Color(1.0, 0.22, 0.12)
	elif ratio >= posture_warn_at:
		var t := (ratio - posture_warn_at) / maxf(posture_danger_at - posture_warn_at, 0.001)
		c = Color(1.0, 0.72, 0.28).lerp(Color(1.0, 0.22, 0.12), t)
	else:
		var t := ratio / maxf(posture_warn_at, 0.001)
		c = Color(0.88, 0.88, 0.82).lerp(Color(1.0, 0.72, 0.28), t)
	if deflect_flash > 0.0:
		c = c.lerp(Color(1, 1, 1), deflect_flash)
	return c


func _pulse_alpha(ratio: float) -> float:
	if ratio < posture_warn_at:
		return 1.0
	var speed: float = 6.0 if ratio >= posture_danger_at else 3.5
	return 0.72 + 0.28 * sin(_pulse * speed)

extends CanvasLayer
## 指路：目標在畫面內 → 目標點上方浮標＋距離；在畫面外 → 螢幕邊緣箭頭。
## 讀 WaypointResolver；不知道任務細節。對話中隱藏。

@export var edge_margin := 48.0
@export var marker_height := 1.6      # 浮標離地高

var _target: Dictionary = {}
var _main: Node = null
var _refresh_t := 0.0


func _ready() -> void:
	_main = get_parent()
	$Marker.visible = false
	$Arrow.visible = false
	QuestManager.objective_updated.connect(func(_a, _b, _c, _d) -> void: _refresh())
	QuestManager.quest_started.connect(func(_a) -> void: _refresh())
	QuestManager.quest_completed.connect(func(_a) -> void: _refresh())
	_refresh()


func _refresh() -> void:
	if _main == null or not _main.has_method("current_portals"):
		_target = {}
		return
	_target = WaypointResolver.resolve(String(_main.current_id), _main.current_portals())


func _process(delta: float) -> void:
	_refresh_t += delta
	if _refresh_t > 1.0:      # 換圖後 current_id 變了也要跟上
		_refresh_t = 0.0
		_refresh()
	var cam := get_viewport().get_camera_3d()
	var map_open: bool = _main.has_node("WorldMap") and _main.get_node("WorldMap").visible
	if _target.is_empty() or cam == null or DialogueManager.is_active() or map_open:
		$Marker.visible = false
		$Arrow.visible = false
		return
	var player: Node3D = _main.player
	var pos2: Vector2 = _target["pos"]
	# 目標高度：用玩家高度近似（差距對浮標影響小；避免每幀射線）
	var world := Vector3(pos2.x, player.global_position.y + marker_height, pos2.y)
	var dist := Vector2(player.global_position.x, player.global_position.z).distance_to(pos2)
	var label := "%s  %d m" % [_target["label"], int(dist)]
	var vp := get_viewport().get_visible_rect().size
	var behind := cam.is_position_behind(world)
	var sp := cam.unproject_position(world)
	var on_screen := not behind and sp.x > 0 and sp.x < vp.x and sp.y > 0 and sp.y < vp.y
	if on_screen and dist > 3.0:
		$Marker.visible = true
		$Arrow.visible = false
		$Marker.position = sp - $Marker.size * 0.5
		$Marker/Label.text = label
	elif dist > 3.0:
		$Marker.visible = false
		$Arrow.visible = true
		# 用玩家→目標的水平方向相對相機 yaw 算螢幕邊緣角度
		var to := Vector2(pos2.x - player.global_position.x, pos2.y - player.global_position.z)
		var cam_fwd := -cam.global_transform.basis.z
		var fwd := Vector2(cam_fwd.x, cam_fwd.z)
		var ang := fwd.angle_to(to)      # 左負右正（Godot 2D y 向下，需翻）
		var centre := vp * 0.5
		var dir := Vector2(sin(ang), -cos(ang))
		var half := centre - Vector2(edge_margin, edge_margin)
		var k := minf(absf(half.x / maxf(absf(dir.x), 0.001)), absf(half.y / maxf(absf(dir.y), 0.001)))
		$Arrow.position = centre + dir * k - $Arrow.size * 0.5
		$Arrow.rotation = dir.angle() + PI * 0.5
		$Arrow/Label.rotation = -$Arrow.rotation
		$Arrow/Label.text = label
	else:
		$Marker.visible = false
		$Arrow.visible = false

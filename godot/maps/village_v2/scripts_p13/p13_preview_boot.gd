extends Node
## P13 W1B 開発用プレビュー起動（正式 main.tscn／main.gd は変更しない）。
##   エディタ：このシーン res://maps/village_v2/p13_preview.tscn を開いて F6（Run Current Scene）
##   命令列：Godot --path godot res://maps/village_v2/p13_preview.tscn
## 動作：main.tscn を current_scene として起動 → 人間之里 V2 を載せる → 主街の審圖站位へ → ArchPilotP13 overlay を村の根に追加。
## P13 W2 で主街 39 棟・農家は正式場景へ統合済み（ArchPilotP13 overlay は退役、もう掛けない）。
## 操作：F7＝主街 → MKT_010 前 → MKT_006 前 → 農家 A1／A2 → 主街 の順に瞬間移動。
## 碰撞・NPC・道路・農田は変更しない（overlay は見た目だけ、農家預覽は碰撞なし）。
const STOPS := [
	["主街（北望）", Vector2(241.0, 44.0), Vector2(262.0, -20.0)],
	["MKT_010 蔵造住居の前", Vector2(262.4, -13.2), Vector2(269.1, -10.9)],
	["MKT_006 竹籠工房の前", Vector2(253.6, 11.4), Vector2(260.2, 14.3)],
	["農家 A1／A2（FarmPath_5）", Vector2(334.0, 69.0), Vector2(319.0, 79.0)],
]

var main: Node
var stop := 0


func _ready() -> void:
	_boot.call_deferred()


func _boot() -> void:
	var sf := get_node_or_null("/root/StoryFlags")
	if sf:
		sf.set_flag("woke_in_trail", true)
		sf.set_flag("met_reimu", true)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(main)
	get_tree().current_scene = main
	for i in 30:
		await get_tree().process_frame
	if String(main.get("current_id")) != "village_v2":
		main.call("load_map", "village_v2", "")
		for i in 60:
			await get_tree().process_frame
	var mr: Node3D = main.get("map_root")
	for nm in ["Debug", "Portals", "QuestAnchors"]:
		var n := mr.get_node_or_null(nm) as Node3D
		if n:
			n.visible = false
	var dn := get_node_or_null("/root/DayNight")
	if dn:
		dn.call("set_hour", 10.0)
		dn.set("flowing", false)
	await _go(0)
	print("[P13 preview] 起動完了：F7＝次の站位（正式場景）")


func _go(i: int) -> void:
	stop = i % STOPS.size()
	var s: Array = STOPS[stop]
	var player: CharacterBody3D = main.get("player")
	await get_tree().physics_frame
	var at: Vector2 = s[1]
	var q := PhysicsRayQueryParameters3D.create(Vector3(at.x, 60.0, at.y), Vector3(at.x, -20.0, at.y))
	q.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	player.velocity = Vector3.ZERO
	player.global_position = Vector3(at.x, (hit["position"] as Vector3).y + 0.05 if not hit.is_empty() else 2.0, at.y)
	var look: Vector2 = s[2]
	var yaw := atan2(-(look.x - at.x), -(look.y - at.y))
	if player.has_method("snap_yaw"):
		player.call("snap_yaw", yaw)
	print("[P13 preview] 站位：%s" % s[0])


func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed and not e.echo):
		return
	match (e as InputEventKey).physical_keycode:
		KEY_F7:
			_go(stop + 1)

extends SceneTree
## 人里段立繪實機截圖（ART_REVIEW 用）：慧音／小鈴／阿求／美宵各一張對話畫面。
##   Godot --headless --path godot --script tools/_shot_village_portraits.gd
##
## ⚠ --script 模式下 autoload 在 _init 當下尚未就緒，必須 call_deferred。
## ⚠ 跑之前把 DialogueUI 的 _unhandled_input 關掉：桌面上任何一次點擊都會推進對話。
const OUT := "D:/神社/shrine/work/shots/portraits_village/"

var _main: Node
var _dm: Node
var _qm: Node
var _sf: Node


func _init() -> void:
	_run.call_deferred()


func _settle(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame


func _shot(name: String) -> void:
	# 打字機沒跑完就存圖會拍到半句
	await _settle(40)
	DirAccess.make_dir_recursive_absolute(OUT)
	root.get_viewport().get_texture().get_image().save_png(OUT + name + ".png")
	print("[SHOT] ", name)


## 推進到含指定字串的那一句就停（停在該句的畫面上）
func _drive_till(needle: String, guard: int = 60) -> String:
	var seen := ""
	for i in guard:
		if not _dm.call("is_active"):
			break
		if seen.contains(needle):
			break
		_dm.call("advance")
		await _settle(3)
		seen = _last_line
	return _last_line


var _last_line := ""


func _on_line(_speaker: String, _p: Texture2D, text: String, _c: PackedStringArray) -> void:
	_last_line = text


func _drain() -> void:
	for i in 80:
		if not _dm.call("is_active"):
			break
		_dm.call("advance")
		await _settle(2)


func _go(x: float, z: float) -> void:
	var player: CharacterBody3D = _main.player
	player.velocity = Vector3.ZERO
	player.global_position = Vector3(x, 2.5, z)
	await _settle(12)


func _talk(node_name: String, shot: String, needle: String) -> void:
	var node: Node = _main.find_child(node_name, true, false)
	if node == null:
		print("[SHOT] 找不到互動區 ", node_name)
		return
	node.call("interact")
	await _settle(20)
	if not _dm.call("is_active"):
		print("[SHOT] %s 沒起對話（prompt=「%s」）" % [node_name, String(node.call("prompt_text"))])
		return
	await _drive_till(needle)
	await _shot(shot)
	await _drain()


func _run() -> void:
	_dm = root.get_node("/root/DialogueManager")
	_qm = root.get_node("/root/QuestManager")
	_sf = root.get_node("/root/StoryFlags")
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	await _settle(6)
	# 桌面誤點會推進對話，關掉 UI 的輸入處理
	var ui := root.find_child("DialogueUI", true, false)
	if ui != null:
		ui.set_process_unhandled_input(false)
	var day := root.get_node_or_null("/root/DayNight")
	if day != null:
		day.set("flowing", false)
		day.call("set_hour", 11.0)
	_dm.connect("line_shown", _on_line)
	await _settle(30)
	await _drain()

	_main.load_map("slice", "trail")
	await _settle(60)

	# MQ09 慧音（信任線）
	_qm.call("reset")
	_sf.call("reset")
	_sf.call("set_flag", "spared_wounded_yokai", true)
	_qm.call("start_quest", "MQ09")
	await _go(315, 47)
	await _talk("寺子屋慧音", "v1_keine", "半人半獸")

	# MQ10 小鈴
	await _go(236, -68)
	await _talk("鈴奈庵小鈴", "v2_kosuzu", "本居小鈴")

	# MQ10 阿求
	await _go(233, -122)
	await _talk("稗田邸阿求", "v3_akyuu", "稗田阿求")

	# MQ12 慧音裁定 → 美宵
	await _go(315, 47)
	await _talk("寺子屋慧音裁定", "v4_keine_verdict", "願意先信任你")
	await _go(213, -82)
	await _talk("鯢吞亭美宵", "v5_miyoi", "奧野田美宵")

	print("[SHOT] 完成。MQ12=%s 落腳=%s" % [
		str(_qm.call("is_completed", "MQ12")), str(_sf.call("get_flag", "has_village_lodging"))])
	quit(0)

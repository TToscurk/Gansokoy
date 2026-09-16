extends SceneTree
## 立面探針 —— 任務互動區「站在建築的哪一面」不能靠猜，用畫面看。
##   Godot --rendering-method gl_compatibility --path godot --script tools/probe_village_facades.gd
##
## 每筆候選：把玩家放到預定站位，相機從預定位置看向建築，存一張 PNG。
## 判讀重點：站的那一面是不是正面（有入口、暖簾、門牌），或其實是後牆／側牆。
##   BFS 只證明「走得到」，證明不了「那是門」。
##
## ⚠ 開場獨白（OpeningFade → yoriichi_wake）會在開機後十幾秒自己起，對話框
##   會蓋進截圖裡；先等它出現再讀完（與 capture_village_arc.gd 同一課）。

const OUT := "D:/神社/shrine/shots2/village_facades_20260916/"

## name / 玩家站位 (x,z) / 相機位置 / 注視點
## 第二輪：鈴奈庵與火見櫓用高角度斜視重拍 —— 第一輪的相機埋在街屋（machiya）裡，
##   只拍到屋頂與牆的背面。街屋離店面只有 2.6 m，平視一定被吃掉。
const SPOTS := [
	{ "name": "01b_suzunaan_highSE", "stand": Vector2(236.0, -68.0), "cam": Vector3(255.0, 13.0, -47.0), "look": Vector3(227.0, 3.0, -68.0) },
	{ "name": "02b_suzunaan_highSW", "stand": Vector2(227.0, -58.0), "cam": Vector3(203.0, 13.0, -45.0), "look": Vector3(227.0, 3.0, -68.0) },
	{ "name": "05b_firewatch_highSE", "stand": Vector2(251.0, -69.0), "cam": Vector3(266.0, 12.0, -55.0), "look": Vector3(243.0, 6.0, -69.0) },
	{ "name": "06b_firewatch_highW", "stand": Vector2(236.0, -69.0), "cam": Vector3(222.0, 11.0, -80.0), "look": Vector3(243.0, 6.0, -69.0) },
]

var _main: Node
var _dm: Node


func _init() -> void:
	_run.call_deferred()


func _wait(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	await _wait(4)
	_dm = root.get_node("/root/DialogueManager")
	# 對話 UI 不吃取證期間的雜訊輸入
	for n in _main.find_children("*", "CanvasLayer", true, false):
		var sc = n.get_script()
		if sc != null and String(sc.resource_path).ends_with("dialogue_ui.gd"):
			n.set_process_unhandled_input(false)

	_main.load_map("slice", "trail")
	await _wait(120)
	var player = _main.get_node_or_null("Player")
	print("[FACADE] 落點 %s" % str(player.global_position))

	# 等開場獨白出生再讀完，否則對話框會留在截圖上（實測約 12.7 s 才起）
	var waited := 0
	while not _dm.call("is_active") and waited < 1800:
		await _wait(10)
		waited += 10
	while _dm.call("is_active"):
		_dm.call("advance", 0)
		await _wait(2)
	print("[FACADE] 開場獨白已讀完（等 %d 幀）" % waited)

	var cam := Camera3D.new()
	_main.add_child(cam)
	cam.fov = 60.0
	cam.current = true

	for s in SPOTS:
		var stand: Vector2 = s.stand
		player.global_position = Vector3(stand.x, 2.5, stand.y)
		cam.global_position = s.cam
		cam.look_at(s.look, Vector3.UP)
		await _wait(40)
		var p: Vector3 = player.global_position
		var path: String = OUT + String(s.name) + ".png"
		_main.get_viewport().get_texture().get_image().save_png(path)
		print("[FACADE] %-20s 站 %.2f,%.2f,%.2f on_floor=%s → %s" % [
			String(s.name), p.x, p.y, p.z, str(player.is_on_floor()), path])

	quit(0)
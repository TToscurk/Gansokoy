extends SceneTree
## 批次 B（MQ10–MQ12）實機取證 —— 提示字與對話框的畫面。
##   Godot --rendering-method gl_compatibility --path godot --script tools/capture_village_arc_b.gd
##
## 與 capture_village_arc.gd（批次 A）同一套規矩：用遊戲自己的視角、不擺自製相機
## （火見櫓那一張例外，見下），並且：
##   1. 開場獨白（OpeningFade → yoriichi_wake）要等它出生再讀完，否則後面每次
##      advance 都在推它。
##   2. 對話 UI 的 unhandled input 停掉，免得桌面上一個雜訊點擊把對話跳掉。
##
## 任務狀態用 API 直接擺（不是照劇本走一遍）：這裡要驗的是**畫面**，
## 劇本順序由 tools/verify_village_arc.gd 的 S 段負責。

const OUT := "D:/神社/shrine/shots2/village_arc_batchB_20260916/"

var _main: Node
var _dm: Node
var _qm: Node
var _sf: Node


func _init() -> void:
	_run.call_deferred()


func _wait(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame


func _line() -> String:
	if not _dm.call("is_active"):
		return "（沒有對話）"
	var nodes: Dictionary = _dm.get("_nodes")
	var cur: String = String(_dm.get("_current"))
	if not nodes.has(cur):
		return ""
	var n: Dictionary = nodes[cur]
	return "%s：%s" % [String(n.get("speaker", "")), String(n.get("text", ""))]


func _shoot(tag: String) -> void:
	await _wait(24)      # 等打字機把這一句打完
	var path := OUT + tag + ".png"
	_main.get_viewport().get_texture().get_image().save_png(path)
	print("[SHOT] %s  ← %s" % [path, _line()])


func _go(x: float, z: float, frames: int = 30) -> void:
	var p = _main.get_node_or_null("Player")
	p.global_position = Vector3(x, 2.5, z)
	await _wait(frames)


func _drive_till(needle: String, max_steps: int = 30) -> String:
	var last := ""
	for i in max_steps:
		if not _dm.call("is_active"):
			break
		_dm.call("advance", 0)
		await _wait(4)
		last = _line()
		if last.contains(needle):
			return last
	return last


func _drain() -> void:
	var n := 0
	while _dm.call("is_active") and n < 200:
		_dm.call("advance", 0)
		n += 1
		await _wait(2)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	await _wait(4)
	_dm = root.get_node("/root/DialogueManager")
	_qm = root.get_node("/root/QuestManager")
	_sf = root.get_node("/root/StoryFlags")
	for n in _main.find_children("*", "CanvasLayer", true, false):
		var sc = n.get_script()
		if sc != null and String(sc.resource_path).ends_with("dialogue_ui.gd"):
			n.set_process_unhandled_input(false)

	_main.load_map("slice", "trail")
	await _wait(120)

	# 等開場獨白出生再讀完（實測約 12.7 s：load_map 擋掉約 9 秒才輪到淡入）
	var waited := 0
	while not _dm.call("is_active") and waited < 1800:
		await _wait(10)
		waited += 10
	await _drain()
	print("[SHOT] 開場獨白已讀完（等 %d ）" % waited)

	# ── 1. MQ10 第一格：鈴奈庵小鈴 ─
	_qm.call("start_quest", "MQ10")
	await _go(236, -68)
	print("[SHOT] 鈴奈庵 prompt=「%s」" % String(_main.find_child("鈴奈庵小鈴", true, false).call("prompt_text")))
	await _shoot("b01_suzunaan_prompt")
	_main.find_child("鈴奈庵小鈴", true, false).call("interact")
	await _wait(40)
	await _shoot("b02_kosuzu_sword_line")
	await _drain()

	# ── 2. MQ10 第二格：稗田邸阿求（記錄）──
	await _go(233, -122)
	var akyuu = _main.find_child("稗田邸阿求", true, false)
	print("[SHOT] 稗田邸 prompt=「%s」" % String(akyuu.call("prompt_text")))
	await _shoot("b03_hieda_prompt")
	akyuu.call("interact")
	await _wait(40)
	await _shoot("b04_akyuu_record")
	await _drain()

	# ── 3. MQ10 第三格：火見櫓（自製相機取景：玩家相機看不到「站在塔下」）──
	#  ⚠ 用完一定要收掉並把玩家相機還原 —— 第一版忘了還原，後面 6 張全部用塔的
	#   視角拍（台詞對、取景錯），看起來像所有對話都發生在火見櫓下。
	var player_cam := _find_player_camera()
	var cam := Camera3D.new()
	_main.add_child(cam)
	cam.global_position = Vector3(258, 9.0, -56)
	cam.look_at(Vector3(244, 5.0, -70), Vector3.UP)
	cam.current = true
	await _go(248, -70)
	print("[SHOT] 火見櫓 → MQ10 完成=%s" % str(_qm.call("is_completed", "MQ10")))
	await _shoot("b05_firewatch_reach")
	cam.queue_free()
	if player_cam != null:
		player_cam.current = true
	await _wait(10)

	# ── 4. MQ11：同一地點換成「結果」區 ──
	await _go(233, -122)
	var akyuu2 = _main.find_child("稗田邸阿求結果", true, false)
	print("[SHOT] MQ11 稗田邸 prompt=「%s」" % String(akyuu2.call("prompt_text")))
	akyuu2.call("interact")
	await _wait(40)
	await _shoot("b06_akyuu_no_record")
	await _drain()

	# ── 5. MQ12：慧音的裁定（信任分支）──
	_sf.call("set_flag", "keine_trusts_yoriichi", true)
	await _go(315, 47)
	var verdict = _main.find_child("寺子屋慧音裁定", true, false)
	print("[SHOT] 寺子屋 prompt=「%s」" % String(verdict.call("prompt_text")))
	await _shoot("b07_keine_verdict_prompt")
	verdict.call("interact")
	await _wait(40)
	await _shoot("b08_keine_verdict_open")
	print("[SHOT] 裁定關鍵句：%s" % await _drive_till("我願意先信任你"))
	await _shoot("b09_keine_marmot_line")
	await _drain()

	# ── 6. MQ12 第二格：鯢吞亭美宵 ──
	await _go(213, -82)
	var inn = _main.find_child("鯢吞亭美宵", true, false)
	print("[SHOT] 鯢吞亭 prompt=「%s」" % String(inn.call("prompt_text")))
	await _shoot("b10_inn_prompt")
	inn.call("interact")
	await _wait(40)
	print("[SHOT] 美宵關鍵句：%s" % await _drive_till("客房的鑰匙"))
	await _shoot("b11_inn_key_line")
	await _drain()
	print("[SHOT] 收尾：MQ12 完成=%s 落腳=%s" % [
		str(_qm.call("is_completed", "MQ12")), str(_sf.call("get_flag", "has_village_lodging"))])
	await _shoot("b12_after_inn")

	quit(0)


func _find_player_camera() -> Camera3D:
	var p = _main.get_node_or_null("Player")
	if p == null:
		return null
	for n in p.find_children("*", "Camera3D", true, false):
		return n as Camera3D
	return null

extends SceneTree
## R7 P5 候選試玩：沿用既有 combat_arena 與其 HUD，只在執行期換上 R7K 候選 Player。不寫任何場景／資源／存檔。
##   godot --path godot -s res://tools/yoriichi_r7/play_r7_p5.gd
## 包含：十三型循環（C 按住）、REF01 圓舞右鍵旋身斬、新普通跳躍（Running Jump，預設 mx）、F1–F12 單招。
const ARENA := preload("res://scenes/combat_arena.tscn")
const CANDIDATE := preload("res://characters/yoriichi/player_yoriichi_r7k.tscn")
## F1..F12 → REF01..REF12（招式 ID 依 R7 控制器對照）
const FKEYS := {KEY_F1: 1, KEY_F2: 2, KEY_F3: 3, KEY_F4: 11, KEY_F5: 10, KEY_F6: 4,
	KEY_F7: 8, KEY_F8: 6, KEY_F9: 5, KEY_F10: 7, KEY_F11: 9, KEY_F12: 12}

class ReviewKeys extends Node:
	var player: CharacterBody3D
	var label: Label
	var last := ""

	func _unhandled_input(event: InputEvent) -> void:
		if not event is InputEventKey or not event.pressed or event.echo:
			return
		if FKEYS.has(event.keycode):
			var id: int = FKEYS[event.keycode]
			var ok: bool = player.execute_form(id, true)
			last = "F%d → 招式 %d %s" % [event.keycode - KEY_F1 + 1, id, "發動" if ok else "被拒（忙碌中／狀態不合）"]
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_B:
			player.set("sun_breath_gauge", float(player.get("sun_breath_max")))
			last = "呼吸補滿"
			get_viewport().set_input_as_handled()

	func _process(_delta: float) -> void:
		var f: int = player.active_form
		var ref := ""
		var forms = player.get("R7_FORMS")
		if f != 0 and forms is Dictionary and forms.has(f):
			ref = str(forms[f].get("ref", ""))
		label.text = ("R7 P5 候選試玩｜ART_REVIEW｜不影響正式主遊戲\n"
			+ "WASD 移動｜Shift 長按衝刺、短按閃避｜Space 跳（新 Running Jump）｜Q 拔刀\n"
			+ "左鍵 輕斬｜右鍵 重斬（圓舞中按＝旋身斬分支）｜F 防禦｜C 按住＝十三型循環，放開收招\n"
			+ "F1–F12＝日之呼吸 REF01–REF12 單招｜B 補滿呼吸\n"
			+ "著地：%s｜型：%s %s｜十三型：%s 第 %s 圈｜呼吸：%.0f\n%s") % [
			"是" if player.is_on_floor() else "否", str(f), ref,
			"進行中" if bool(player.get("_r7c_running")) else "—", str(player.get("r7c_lap")),
			float(player.get("sun_breath_gauge")), last]

func _initialize() -> void:
	_boot.call_deferred()

func _boot() -> void:
	var arena := ARENA.instantiate()
	var original := arena.get_node("Player") as Node3D
	var spawn := original.transform
	arena.remove_child(original)
	original.free()
	var player := CANDIDATE.instantiate() as CharacterBody3D
	player.name = "Player"
	player.transform = spawn
	# 只限這個試玩實例：熟練度全開、十三型解鎖，不改存檔或正式預設值。
	player.set("sun_mastery", 100)
	player.set("form13_unlocked", true)
	player.set("form13_key_enabled", true)
	arena.add_child(player)
	root.add_child(arena)
	var layer := CanvasLayer.new()
	layer.layer = 100
	var label := Label.new()
	label.position = Vector2(18, 16)
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	layer.add_child(label)
	root.add_child(layer)
	var keys := ReviewKeys.new()
	keys.player = player
	keys.label = label
	root.add_child(keys)
	await process_frame
	player.set("sun_breath_gauge", float(player.get("sun_breath_max")))
	player.request_draw()
	print("P5_PLAY_READY candidate=player_yoriichi_r7k jump=", player.get("r7_jump_variant"), " ref09=", player.get("r7_ref09_variant"))

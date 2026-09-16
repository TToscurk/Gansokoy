extends SceneTree
## HUD 自動顯隱 ＋ 型選單按鍵：實機接線驗證。
##
## 執行：
##   godot --headless --path godot -s tools/verify_hud_autohide.gd
##
## 驗三件使用者要求的事：
##   1. 型選單的鍵不再和 lock_on 撞（原本兩個都是 Tab）
##   2. 探索時 HUD 完全不顯示
##   3. 交手後 HUD 浮出，停手數秒後自己收掉

var _pass := 0
var _fail := 0


func check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		_pass += 1
		print("  [OK] ", label, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", label, ("  " + detail) if detail != "" else "")


func _initialize() -> void:
	print("=== HUD 自動顯隱 / 選單按鍵 ===")
	var scene: PackedScene = load("res://scenes/main.tscn")
	var main: Node = scene.instantiate()
	get_root().add_child(main)
	for i in 15:
		await process_frame

	var combat: Node = main.get("combat")
	var player: Node = main.get("player")
	check("CombatRuntime 存在", combat != null)
	if combat == null:
		print("=== %d passed, %d failed ===" % [_pass, _fail])
		quit(1)
		return

	# --- 1. 型選單已移除（FF7R 式，2026-09-16 裁定）---
	print("-- 按鍵 --")
	check("form_menu 未註冊", not InputMap.has_action("form_menu"))

	# --- 2. 探索時隱藏 ---
	print("-- 探索時 --")
	for i in 40:
		await process_frame
	var root: Control = combat.hud.get_node_or_null("Root")
	check("HUD 節點存在", root != null)
	if root != null:
		check("探索時 HUD 透明度為 0",
			root.modulate.a < 0.02, "alpha=%.3f" % root.modulate.a)
		check("探索時 HUD 不可見", not root.visible)

	# --- 3. 交手後浮出 ---
	print("-- 交手後 --")
	combat.mark_combat()
	# 淡入是以真實 delta 推進（hud_fade_time 0.35 s）；headless 幀率不固定
	# （實測 40 幀只走到 α 0.86），所以等「可觀測的完成條件」而不是猜幀數。
	var fade_frames := 0
	var fade_t0 := Time.get_ticks_msec()
	while root != null and root.modulate.a < 0.99 and Time.get_ticks_msec() - fade_t0 < 2000:
		await process_frame
		fade_frames += 1
	if root != null:
		check("交手後 HUD 浮出", root.modulate.a > 0.9,
			"alpha=%.3f（%d 幀 / %d ms）" % [root.modulate.a, fade_frames, Time.get_ticks_msec() - fade_t0])
		check("交手後 HUD 可見", root.visible)

	# --- 4. 停手後自己收掉 ---
	print("-- 停手後 --")
	# combat_linger 預設 5 s；用大 delta 推快一點不現實，直接把計時歸零。
	combat._combat_timer = 0.0
	for i in 60:
		await process_frame
	if root != null:
		check("停手後 HUD 淡出",
			root.modulate.a < 0.02, "alpha=%.3f" % root.modulate.a)

	print("=== %d passed, %d failed ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _keys_of(action: String) -> Array[int]:
	var out: Array[int] = []
	if not InputMap.has_action(action):
		return out
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			var k := e as InputEventKey
			out.append(k.physical_keycode if k.physical_keycode != 0 else k.keycode)
	return out


func _names(keys: Array) -> String:
	var parts: Array[String] = []
	for k in keys:
		parts.append(OS.get_keycode_string(int(k)))
	return str(parts)

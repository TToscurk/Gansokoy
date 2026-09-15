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

	# --- 1. 按鍵不撞 ---
	print("-- 按鍵 --")
	check("form_menu 已註冊", InputMap.has_action("form_menu"))
	var menu_keys: Array[int] = _keys_of("form_menu")
	var lock_keys: Array[int] = _keys_of("lock_on")
	print("     form_menu = %s、lock_on = %s" % [
		_names(menu_keys), _names(lock_keys)])
	var clash: Array[int] = []
	for k in menu_keys:
		if lock_keys.has(k):
			clash.append(k)
	check("型選單不與 lock_on 撞鍵", clash.is_empty(), _names(clash))

	# 全表掃一次，確認沒和任何其他 action 撞
	var all_clash: Array[String] = []
	for a in InputMap.get_actions():
		if String(a) == "form_menu" or String(a).begins_with("ui_"):
			continue
		for k in _keys_of(String(a)):
			if menu_keys.has(k):
				all_clash.append(String(a))
				break
	check("型選單不與任何既有 action 撞鍵", all_clash.is_empty(), str(all_clash))

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
	for i in 40:
		await process_frame
	if root != null:
		check("交手後 HUD 浮出", root.modulate.a > 0.9, "alpha=%.3f" % root.modulate.a)
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

	# --- 5. 提示密度 ---
	print("-- 提示 --")
	var hint: Label = combat.menu.get_node_or_null("Root/Panel/Hint")
	if hint != null:
		print("     選單提示文字 = 「%s」" % hint.text)
		check("選單提示夠精簡（≤ 16 字）", hint.text.length() <= 16,
			"%d 字" % hint.text.length())

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

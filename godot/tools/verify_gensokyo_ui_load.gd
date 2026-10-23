extends SceneTree
## 載入所有 Gensokyo 元件與改過的 UI 場景，確認能 parse / instantiate（無頭）。
func _init() -> void:
	_run.call_deferred()   # autoload 在 _init 當下尚未就緒


func _run() -> void:
	var fails := 0
	for p in ["res://ui/gensokyo/gensokyo_style.gd", "res://ui/gensokyo/gensokyo_ink.gd", "res://ui/gensokyo/gensokyo_panel.gd",
			"res://ui/gensokyo/gensokyo_nameplate.gd", "res://ui/gensokyo/gensokyo_button.gd", "res://ui/gensokyo/gensokyo_ornament.gd",
			"res://ui/gensokyo/gensokyo_dialogue_box.gd", "res://ui/gensokyo/gensokyo_quest_tracker.gd",
			"res://ui/gensokyo/gensokyo_interaction_prompt.gd", "res://ui/gensokyo/gensokyo_item_slot.gd",
			"res://ui/gensokyo/gensokyo_tooltip.gd", "res://ui/gensokyo/gensokyo_hotbar.gd", "res://ui/player_bars.gd",
			"res://ui/dialogue/dialogue_ui.gd", "res://ui/quest/quest_tracker.gd"]:
		var s: Script = load(p)
		var ok := s != null and s.can_instantiate()
		print("[LOAD] %s %s" % ["OK  " if ok else "FAIL", p])
		if not ok:
			fails += 1
	for p in ["res://ui/gensokyo/UITheme_Gensokyo.tres", "res://ui/gensokyo/gensokyo_style.tres", "res://ui/dialogue/dialogue_ui.tscn",
			"res://ui/quest/quest_tracker.tscn", "res://ui/combat_hud.tscn", "res://ui/gensokyo/gensokyo_dialogue_box.tscn"]:
		var r: Resource = load(p)
		print("[LOAD] %s %s" % ["OK  " if r != null else "FAIL", p])
		if r == null:
			fails += 1
	print("[LOAD] failures=%d" % fails)
	quit(fails)

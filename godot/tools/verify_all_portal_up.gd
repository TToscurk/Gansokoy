extends SceneTree
## 每張已建置地圖的每個出口：真實 overlap、可見元件、實際 ↑ 換圖。
var main: Node
var failures := 0
var results: Array = []
var source_id := "shrine"
const OUT := "D:/神社/shrine/_review/portal_glow/"

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):
			source_id = arg.substr(6)
	_run.call_deferred()

func frames(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame

func check(label: String, ok: bool) -> void:
	results.append({"check": label, "ok": ok})
	print("[ALL_UP] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await frames(5)
	var player: CharacterBody3D = main.player
	player.set_physics_process(false)
	check("loaded " + source_id, main.current_id == source_id)
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/%s.meta.json" % source_id))
	var count := 0
	for p in meta.get("portals", []):
		if main.current_id != source_id:
			main.load_map(source_id, "")
			await frames(4)
		var target := str(p.get("target", "")) if p.get("target") != null else ""
		var area: Area3D = main.map_root.get_node("Portal_" + ("保留" if target.is_empty() else target))
		player.global_position = area.global_position
		player.velocity = Vector3.ZERO
		main.portal_cooldown = 0.0
		await frames(5)
		check("stationary " + target, main.current_id == source_id)
		check("overlap " + target, area.overlaps_body(player))
		if target.is_empty():
			check("reserved has no glow", not area.has_node("GlowGate"))
		else:
			count += 1
			check("glow + prompt " + target, area.has_node("GlowGate") and area.has_node("PortalPrompt"))
			check("prompt visible " + target, area.get_node("PortalPrompt").visible)
		var event := InputEventKey.new()
		event.keycode = KEY_UP
		event.pressed = true
		Input.parse_input_event(event)
		await frames(5)
		event = InputEventKey.new()
		event.keycode = KEY_UP
		event.pressed = false
		Input.parse_input_event(event)
		check("up transition " + target, main.current_id == (source_id if target.is_empty() else target))
	var f := FileAccess.open(OUT + source_id + ".json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"map":source_id,"portals":count,"failures":failures,"results":results}, "  "))
	f.close()
	print("[ALL_UP] map=%s portals=%d failures=%d" % [source_id,count,failures])
	quit(failures)

extends SceneTree

var failures := 0

func _init() -> void:
	_run.call_deferred()

func check(label: String, ok: bool) -> void:
	print("[SUN_VFX] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1

func _run() -> void:
	var scene := load("res://characters/yoriichi/player_yoriichi.tscn") as PackedScene
	var player = scene.instantiate()
	root.add_child(player)
	await process_frame
	check("trail uses flame shader", player._sword_trail.material_override is ShaderMaterial)
	check("audio component attached", player.get_node_or_null("CharacterAudio") != null)
	player.sword_state = 2
	player.request_heavy_cut()
	var audio = player.get_node_or_null("CharacterAudio")
	if audio != null:
		check("audio playback triggered by attack", audio.get("events_played") > 0)
	var trail = player._sword_trail
	trail.stop_trail()
	for i in 40:
		trail._process(0.016667)
	check("expired trail has no geometry", trail.mesh.get_surface_count() == 0)
	print("[SUN_VFX] failures=%d" % failures)
	player.free()
	quit(failures)

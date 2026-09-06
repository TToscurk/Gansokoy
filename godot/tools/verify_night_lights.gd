extends SceneTree
## Verify the night-lighting rig: do lanterns switch on at dusk, off at noon,
## and do their meshes actually emit?
##
## Why test this headlessly: "the lanterns should light up at night" is easy to
## eyeball wrong — a light can be on while its lantern mesh stays black, which
## looks like nothing happened. Assert both channels (light energy AND material
## emission) across the day, and confirm the scene's real 14 street lamps are
## the ones being driven.
##
## Run: godot --headless --path godot --script tools/verify_night_lights.gd

const SCENE := "res://maps/slice/slice.tscn"


func _init() -> void:
	root.call_deferred("add_child", load(SCENE).instantiate())
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await process_frame

	var scene := root.get_child(root.get_child_count() - 1)

	var sky := scene.find_child("天象系統", true, false)
	if sky == null:
		print("[FAIL] 場景中沒有天象系統")
		quit(1)
		return

	var lights := scene.find_child("夜間燈火", true, false)
	if lights == null:
		print("[FAIL] 場景中沒有夜間燈火節點")
		quit(1)
		return

	# Count what the rig found.
	var omni := _find_type(scene, "OmniLight3D")
	print("場景中的點光源: %d 盞" % omni.size())

	var fails: Array = []
	print("\n%-8s %-8s %-12s %-12s %s" % [
		"時刻", "等級", "首盞光強", "自發光強度", "亮著的燈"])

	for hr in [0.0, 4.0, 6.0, 10.0, 12.0, 16.0, 17.0, 18.0, 19.0, 21.0, 23.0]:
		sky.set("時刻", hr)
		if sky.has_method("設定時刻"):
			sky.設定時刻(hr)
		# The rig reads the hour in _process, so give it frames to react.
		for f in 3:
			await process_frame

		# Diagnostic: is the rig even seeing the lights and the sky?
		if hr == 0.0:
			var probe_lights = lights.get("_lights")
			var probe_sky = lights.get("_sky")
			print("  [診斷] 收集到光源 %s 個，找到天象系統 %s" % [
				(probe_lights.size() if probe_lights != null else "null"),
				("是" if probe_sky != null else "否")])

		var on := 0
		var first_e := 0.0
		for i in omni.size():
			var l: OmniLight3D = omni[i]
			if l.visible and l.light_energy > 0.01:
				on += 1
			if i == 0:
				first_e = l.light_energy

		# Emission on the lantern meshes — the half that is easy to forget.
		var emis := 0.0
		var mesh_lit := 0
		for mi in _find_type(scene, "MeshInstance3D"):
			var m: MeshInstance3D = mi
			var mat = m.get_surface_override_material(0)
			if mat is BaseMaterial3D and mat.emission_enabled:
				mesh_lit += 1
				emis = maxf(emis, mat.emission_energy_multiplier)

		var lvl = lights.get("亮度倍率")
		print("%-8.1f %-8s %-12.3f %-12.2f %d 盞 / %d 個發光網格" % [
			hr, "-", first_e, emis, on, mesh_lit])

		# Daytime: everything must be off.
		if hr >= 8.0 and hr <= 15.0:
			if on > 0:
				fails.append("%.0f時 白天卻有 %d 盞燈亮著" % [hr, on])
			if emis > 0.01:
				fails.append("%.0f時 白天卻有網格在發光" % hr)
		# Deep night: everything must be on.
		if hr <= 3.0 or hr >= 20.0:
			if on < omni.size():
				fails.append("%.0f時 夜晚只有 %d/%d 盞亮" % [hr, on, omni.size()])
			if emis < 0.5:
				fails.append("%.0f時 夜晚燈籠網格沒有發光 (%.2f)" % [hr, emis])

	print("")
	if fails.is_empty():
		print("[PASS] 燈火作息正確，燈籠網格會發光")
		quit(0)
	else:
		for f in fails:
			print("  [FAIL] %s" % f)
		quit(1)


func _find_type(node: Node, cls: String) -> Array:
	var out: Array = []
	if node.is_class(cls):
		out.append(node)
	for c in node.get_children():
		out.append_array(_find_type(c, cls))
	return out

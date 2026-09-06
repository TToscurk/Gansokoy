extends SceneTree
## Night-lantern verification shot: load slice via main.tscn at a fixed 時刻,
## park the camera on the whale lantern (鯢吞亭) and on a bank stone lantern,
## report what lights exist near them, and save PNGs for Human Art Review.
##
## Run WINDOWED:  godot --path godot --script tools/render_night_lanterns.gd -- --hour=20.5

var _main: Node


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var hour := 20.5
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--hour="):
			hour = float(a.substr(7))
	var packed := ResourceLoader.load("res://scenes/main.tscn", "PackedScene") as PackedScene
	_main = packed.instantiate()
	root.add_child(_main)
	await process_frame
	_main.load_map("slice", "")
	for i in 5:
		await process_frame
	var map: Node = _main.map_root
	var sky := map.get_node_or_null("天象系統")
	sky.set("一日長度分鐘", 0.0)
	sky.set("時刻", hour)
	_main.player.visible = false

	var out_dir := "res://work/shots/night_lanterns"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var shots := [
		["kujira", Vector3(258.0, 3.5, -10.0), Vector3(265.5, 2.0, -5.5)],
		["ishidoro", Vector3(0, 0, 0), Vector3(0, 0, 0)],
		["street", Vector3(235.0, 2.0, -5.0), Vector3(235.0, 3.0, 60.0)],
	]
	var lant := map.get_node_or_null("EastBankDressing/lantern_02/StoneLantern_009")
	if lant != null:
		var c: Vector3 = (lant as MeshInstance3D).global_transform * (lant as MeshInstance3D).get_aabb().get_center()
		shots[1][1] = c + Vector3(-4.0, 1.5, 3.0)
		shots[1][2] = c

	# Report lights near each lantern
	var nl := map.get_node_or_null("夜間燈火")
	for path in ["鯢吞亭/Meshy_Kujira Lantern_mesh_node", "EastBankDressing/lantern_02/StoneLantern_009", "霧雨店/Meshy_Glowing Kanji Lantern_mesh_node"]:
		var mi := map.get_node_or_null(path) as MeshInstance3D
		if mi == null:
			print("[night] %s 不存在" % path)
			continue
		var fill := mi.get_node_or_null("補光") as OmniLight3D
		var mat := mi.get_surface_override_material(0) as BaseMaterial3D
		print("[night] %-52s 補光=%s%s  自發光=%s" % [
			path.substr(-52),
			"有" if fill else "無",
			(" range %.1f energy %.2f vis %s" % [fill.omni_range, fill.light_energy, fill.visible]) if fill else "",
			("on E=%.2f" % mat.emission_energy_multiplier) if mat and mat.emission_enabled else "off"])

	var cam := Camera3D.new()
	cam.fov = 60.0
	root.add_child(cam)
	cam.current = true
	for s in shots:
		cam.global_position = s[1]
		cam.look_at(s[2], Vector3.UP)
		for i in 12:
			await process_frame
		var img := root.get_texture().get_image()
		var p := "%s/%s_h%02d.png" % [out_dir, s[0], int(hour)]
		img.save_png(ProjectSettings.globalize_path(p))
		print("[night] 存 %s" % p)
	print("done")
	quit(0)

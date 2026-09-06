extends SceneTree
## Brightness baseline: measure 稗田邸's interiors against scenes the user has
## already accepted (slice street, shrine grounds), so "太暗" is a number and
## not my opinion.

func _init() -> void:
	_run.call_deferred()

func _wait(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame

func _measure(main: Node, cam: Camera3D, p: Vector3) -> Dictionary:
	var sum_mean := 0.0
	var worst_black := 0.0
	var darkest := 1.0
	for i in 4:
		var ang := TAU * float(i) / 4.0
		cam.global_position = p + Vector3(0, 1.6, 0)
		cam.look_at(p + Vector3(sin(ang), 0.0, cos(ang)) * 8.0 + Vector3(0, 1.3, 0), Vector3.UP)
		await _wait(8)
		var img: Image = main.get_viewport().get_texture().get_image()
		var w := img.get_width()
		var h := img.get_height()
		var total := 0.0
		var black := 0
		var n := 0
		for y in range(60, h, 4):
			for x in range(0, w, 4):
				var c := img.get_pixel(x, y)
				var l: float = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
				total += l
				if l < 0.02:
					black += 1
				n += 1
		var m: float = total / maxf(n, 1)
		sum_mean += m
		darkest = minf(darkest, m)
		worst_black = maxf(worst_black, float(black) / maxf(n, 1))
	return {"mean": sum_mean / 4.0, "darkest": darkest, "black": worst_black}

func _run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _wait(3)
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.current = true
	cam.fov = 75.0

	# 使用者已接受的室外場景 = 基準。
	for spec in [["slice", "trail"], ["shrine", ""], ["hieda1f", "slice"],
			["hieda2f", "hieda1f"], ["hieda3f", "hieda2f"]]:
		main.load_map(spec[0], spec[1])
		await _wait(70)
		var player = main.get_node_or_null("Player")
		player.visible = false
		var r: Dictionary = await _measure(main, cam, player.global_position)
		print("[BASE] %-9s mean=%.4f  darkest_view=%.4f  worst_black=%.1f%%"
			% [spec[0], r.mean, r.darkest, float(r.black) * 100.0])
	quit(0)

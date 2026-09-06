extends SceneTree
## 概念圖雲層晴天濃度 滑桿的全行程驗證：0.0 / 0.25 / 0.5 / 0.85 / 1.0 各拍一張，
## 並量測天空區域的亮度變化，確認端點（尤其 0）真的有作用。
##
##   Godot --headless --path godot --script tools/verify_cloud_slider.gd
##   （需要渲染，不要加 --headless；此腳本自行開窗）
##
## 為什麼要量端點：使用者會自己拉滑桿，一個「拉到 0 沒反應」的控制項比沒有
## 這個控制項更糟——他會以為整個功能壞了。

const VALUES := [0.0, 0.25, 0.5, 0.85, 1.0]
const OUT_DIR := "D:/cloud_slider"


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var packed := ResourceLoader.load("res://scenes/main.tscn", "PackedScene") as PackedScene
	var main := packed.instantiate()
	root.add_child(main)
	await process_frame
	main.load_map("slice", "")
	main.player.visible = false
	for i in 10:
		await process_frame

	var sky_node: Node = main.map_root.get_node_or_null("天象系統")
	if sky_node == null:
		print("[CLOUD] 找不到天象系統")
		quit(1)
		return

	# 朝天空的固定機位，兩次取樣之間唯一的變數就是滑桿。
	var cam := Camera3D.new()
	cam.fov = 72.0
	cam.far = 4000.0
	root.add_child(cam)
	cam.global_position = Vector3(235, 20, 0)
	cam.look_at(Vector3(235, 60, 90), Vector3.UP)
	cam.current = true

	print("[CLOUD] %8s %12s %12s %12s" % ["濃度", "天空平均亮度", "標準差", "與前一格差"])
	var prev := -1.0
	for v in VALUES:
		sky_node.set("概念圖雲層晴天濃度", v)
		for i in 12:
			await process_frame
		var img := get_root().get_texture().get_image()
		img.save_png("%s/base_%.2f.png" % [OUT_DIR, v])

		# 只量畫面上半（天空），避免地景把差異稀釋掉。
		var mean := 0.0
		var sq := 0.0
		var n := 0
		var h := img.get_height() / 3
		var y := 0
		while y < h:
			var x := 0
			while x < img.get_width():
				var c := img.get_pixel(x, y)
				var l := c.get_luminance()
				mean += l
				sq += l * l
				n += 1
				x += 4
			y += 4
		mean /= maxf(n, 1)
		var sd := sqrt(maxf(sq / maxf(n, 1) - mean * mean, 0.0))
		var delta := 0.0 if prev < 0.0 else absf(mean - prev)
		print("[CLOUD] %8.2f %12.4f %12.4f %12.4f%s" % [
			v, mean, sd, delta,
			"" if prev < 0.0 else ("   ← 與前一格無差異！" if delta < 0.0005 else "")])
		prev = mean

	print("[CLOUD] 圖存於 %s" % OUT_DIR)
	print("[CLOUD] done")
	quit(0)

extends SceneTree
## Cel-shading 驗收機位：主街街景，改前／改後同機位對比（美術規格 §1.4）。
##
##   Godot --path godot --script tools/render_cel_review.gd -- <tag>
##
## ⚠ 時刻必須由 `--hour=` 命令列旗標固定，不能在腳本裡設。
## DayNight autoload（scripts/daynight.gd）有自己的 `hour := 15.7` 與
## `flowing := true`，每幀在 _process 覆寫；天象系統的「設定時刻()」會被它蓋掉。
## 第一版沒帶旗標，設了 11:00 卻拍到 15:43 的斜陽——半個畫面壓在陰影裡，
## 正是看不出光影分層的時刻。`--hour=` 會同時把 flowing 關掉。
##
## 用法（時刻由 main.tscn 這一層吃旗標，所以要走 main 而非 SceneTree 腳本）：
##   Godot --path godot -- --hour=11 --shot-cam=235,1.7,-10,235,3,60 --shot=<png>
## 本腳本保留給需要多機位連拍的情境，並自行帶入旗標值。

const OUT_ROOT := "res://../docs/art_review/cel"


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var tag := "shot"
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			tag = a

	var dir := ProjectSettings.globalize_path("res://") + "../docs/art_review/cel"
	DirAccess.make_dir_recursive_absolute(dir)

	var packed := ResourceLoader.load("res://scenes/main.tscn", "PackedScene") as PackedScene
	var main := packed.instantiate()
	root.add_child(main)
	await process_frame
	main.load_map("slice", "")
	main.player.visible = false
	for i in 10:
		await process_frame

	# 固定時刻：設定時刻() 會觸發 _apply()，直接 set 欄位不會。
	var sky: Node = main.map_root.get_node_or_null("天象系統")
	if sky != null:
		sky.set("一日長度分鐘", 0.0)
		sky.call("設定時刻", 11.0)
		for i in 6:
			await process_frame

	var cam := Camera3D.new()
	cam.fov = 72.0
	cam.far = 4000.0
	root.add_child(cam)
	cam.current = true

	# 主街：玩家眼高 1.7 m，沿街往北看
	for s in [
			{"n": "主街街景", "pos": Vector3(235.0, 1.7, -10.0), "look": Vector3(235.0, 3.0, 60.0)},
			{"n": "主街背光", "pos": Vector3(235.0, 1.7, 40.0), "look": Vector3(235.0, 3.0, -30.0)},
		]:
		cam.global_position = s["pos"]
		cam.look_at(s["look"], Vector3.UP)
		for i in 14:
			await process_frame
		var path := "%s/%s_%s.png" % [dir, tag, s["n"]]
		get_root().get_texture().get_image().save_png(path)
		print("[CEL] → %s" % path)

	print("[CEL] done")
	quit(0)

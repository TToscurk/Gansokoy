extends SceneTree
## Cel-shading 分層強度比較：同機位、同時刻，只換色彩校正漸層。
##
##   Godot --path godot --script tools/render_cel_variants.gd -- --hour=11
##   （需要渲染，不可 --headless）
##
## 漸層在**執行期**注入 Environment，不寫進 slice.tscn——比較階段不該碰
## 使用者手調的 27 MB 場景。選定之後才會有一次明確的套用動作。
##
## 時刻由 --hour= 決定（DayNight autoload 吃這個旗標，天象系統現在讀它）。
## 不帶旗標會拿到 DayNight 預設的 15.7 斜陽，那不是這輪要比的光。

const OUT_DIR := "res://../docs/art_review/cel"
const RAMP_DIR := "res://assets/materials/cel"
const VARIANTS := ["（無）", "2階_硬", "3階_硬", "3階_柔", "4階_柔"]

## 主街：玩家眼高、沿街往北，與 bench_slice.gd 的「主街街道」同機位。
const CAM_POS := Vector3(235.0, 1.7, -10.0)
const CAM_LOOK := Vector3(235.0, 3.0, 60.0)


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var dir := ProjectSettings.globalize_path("res://") + "../docs/art_review/cel"
	DirAccess.make_dir_recursive_absolute(dir)

	var packed := ResourceLoader.load("res://scenes/main.tscn", "PackedScene") as PackedScene
	var main := packed.instantiate()
	root.add_child(main)
	await process_frame
	main.load_map("slice", "")
	main.player.visible = false
	for i in 12:
		await process_frame

	var dn: Node = root.get_node_or_null("/root/DayNight")
	var hour: float = dn.get("hour") if dn != null else -1.0
	print("[VAR] 時刻 = %.2f（由 --hour= 決定；沒帶旗標會是預設 15.7）" % hour)

	# 圖自帶的 WorldEnvironment（天象系統/天空環境），不是 main 的那個——
	# main 的已經在 load_map 時讓位了。
	var we := _find_env(main.map_root)
	if we == null:
		print("[VAR] ✗ 找不到圖的 WorldEnvironment")
		quit(1)
		return
	var env: Environment = we.environment
	print("[VAR] 目標環境節點：%s" % we.name)

	var cam := Camera3D.new()
	cam.fov = 72.0
	cam.far = 4000.0
	root.add_child(cam)
	cam.global_position = CAM_POS
	cam.look_at(CAM_LOOK, Vector3.UP)
	cam.current = true

	for v in VARIANTS:
		if v == "（無）":
			env.adjustment_color_correction = null
		else:
			var p := "%s/cel_ramp_%s.tres" % [RAMP_DIR, v]
			var tex := ResourceLoader.load(p) as Texture
			if tex == null:
				print("[VAR] ✗ 載不到 %s" % p)
				continue
			env.adjustment_color_correction = tex
		env.adjustment_enabled = true

		for i in 14:
			await process_frame
		var path := "%s/cel_%02dh_%s.png" % [dir, int(hour), v]
		get_root().get_texture().get_image().save_png(path)
		print("[VAR] → %s" % path)

	print("[VAR] done")
	quit(0)


func _find_env(n: Node) -> WorldEnvironment:
	if n is WorldEnvironment and (n as WorldEnvironment).environment != null:
		return n as WorldEnvironment
	for c in n.get_children():
		var f := _find_env(c)
		if f != null:
			return f
	return null

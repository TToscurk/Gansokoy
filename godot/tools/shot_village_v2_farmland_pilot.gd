extends SceneTree
## P8 pilot review captures: 1.7 m eye / oblique / top-down from fixed cameras
## on the saved, integrated village scene. Read-only; nothing is saved.
## Usage: Godot --path godot --script res://tools/shot_village_v2_farmland_pilot.gd -- --tag=after [--hour=10]
##   診斷用：--only=top（只拍一個鏡位）、--hide=Irrigation/DrainWater,...（藏 FarmlandP8 下的節點，同曝光比對）
const SCENE := "res://maps/village_v2/village_v2.tscn"
const OUT_DIR := "res://../docs/art_review/village_v2_p8_farmland/"
# Fixed review cameras (world). Eye stands on the SW outer bund crest (+1.7 m).
const SHOTS := [
	["eye_1p7", Vector3(380.85, 1.95, 14.0), Vector3(398.0, 0.0, 27.0), 70.0],
	["oblique", Vector3(360.0, 30.0, 78.0), Vector3(404.0, 0.0, 34.0), 50.0],
	["top", Vector3(404.0, 78.0, 34.0), Vector3(404.0, 0.0, 34.0), 50.0],
]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var tag := "after"
	var hour := -1.0
	var only := ""
	var hide: PackedStringArray = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tag="):
			tag = a.substr(6)
		elif a.begins_with("--hour="):
			hour = float(a.substr(7))
		elif a.begins_with("--only="):
			only = a.substr(7)
		elif a.begins_with("--hide="):
			hide = a.substr(7).split(",")
	var village: Node3D = (load(SCENE) as PackedScene).instantiate()
	# 審圖固定時刻（不存檔）：--script 下沒有 DayNight autoload，天象系統會自己走時鐘
	var sky := village.get_node_or_null("Lighting/天象系統")
	if sky and hour >= 0.0:
		sky.set("一日長度分鐘", 0.0)
		sky.set("時刻", hour)
	root.add_child(village)
	var debug := village.get_node_or_null("Debug")
	if debug:
		debug.visible = false
	var fp := village.find_child("FarmlandP8", true, false)
	for h in hide:
		var hn := fp.get_node_or_null(h) as Node3D if fp else null
		if hn:
			hn.visible = false
		else:
			print("[FARM_SHOT] hide: missing ", h)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.current = true
	for i in 30:
		await process_frame
	for s: Array in SHOTS:
		if only != "" and s[0] != only:
			continue
		cam.fov = s[3]
		cam.global_position = s[1]
		var up := Vector3.FORWARD if s[0] == "top" else Vector3.UP
		cam.look_at(s[2], up)
		for i in 12:
			await process_frame
		await RenderingServer.frame_post_draw
		var path := ProjectSettings.globalize_path(OUT_DIR + "pilot_%s_%s.png" % [tag, s[0]]).simplify_path()
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var err := root.get_texture().get_image().save_png(path)
		print("[FARM_SHOT] %s %s -> %s" % [s[0], error_string(err), path])
		# 本鏡位實際繪製三角面：整景 vs 藏掉 pilot 的差＝pilot 在此視角的渲染成本
		var farm := village.find_child("FarmlandP8", true, false) as Node3D
		if farm:
			var on := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
			farm.visible = false
			for i in 4:
				await process_frame
			await RenderingServer.frame_post_draw
			var off := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
			farm.visible = true
			for i in 4:
				await process_frame
			print("[FARM_TRIS] %s frame=%d pilot=%d" % [s[0], on, on - off])
	quit(0)

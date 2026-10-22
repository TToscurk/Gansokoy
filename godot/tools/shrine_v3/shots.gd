extends SceneTree
## 博麗神社 v3 審圖截圖（非 headless）：
##   godot --path godot --resolution 1600x900 --script res://tools/shrine_v3/shots.gd -- --shots=res://tools/shrine_v3/shots_terrain.json --out=<絕對路徑資料夾>
## shots JSON：[{name, pos:[x,z,dy], at:[x,z,dy], fov}]；dy＝相對近景地面高（S3.height_at），abs_y 給定時用絕對高度。
## 可加 --scene=res://... --time=<時刻> --only=name1,name2 --frames=N

const S3 := preload("res://tools/shrine_v3/s3lib.gd")

var cam: Camera3D
var map: Node


func _init() -> void:
	_run.call_deferred()


func _arg(k: String, d: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + k + "="):
			return a.substr(k.length() + 3)
	return d


func _p(v: Array) -> Vector3:
	var x := float(v[0])
	var z := float(v[1])
	if v.size() >= 4 and String(v[3]) == "abs":
		return Vector3(x, float(v[2]), z)
	return Vector3(x, S3.height_at(x, z) + float(v[2]), z)


func _run() -> void:
	var scene_path := _arg("scene", "res://maps/shrine_v3/shrine_v3.tscn")
	var shots: Array = JSON.parse_string(FileAccess.get_file_as_string(_arg("shots", "res://tools/shrine_v3/shots_terrain.json")))
	var out := _arg("out", ProjectSettings.globalize_path("user://shrine_v3_shots"))
	var only := _arg("only", "")
	var frames := int(_arg("frames", "24"))
	DirAccess.make_dir_recursive_absolute(out)
	map = (load(scene_path) as PackedScene).instantiate()
	root.add_child(map)
	var sky := map.get_node_or_null("天象系統")
	var t := _arg("time", "")
	if sky != null and t != "":
		sky.set("時刻", float(t))
	cam = Camera3D.new()
	cam.far = 20000.0
	cam.near = 0.1
	root.add_child(cam)
	cam.current = true
	for i in 30:
		await process_frame
	for s in shots:
		var nm := String(s["name"])
		if only != "" and not (nm in only.split(",")):
			continue
		var p := _p(s["pos"])
		var a := _p(s["at"])
		cam.fov = float(s.get("fov", 60.0))
		cam.global_position = p
		cam.look_at(a, Vector3.UP)
		for i in frames:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_viewport().get_texture().get_image()
		var fp := out.path_join(nm + ".png")
		img.save_png(fp)
		print("[SHOT] %s pos=%s at=%s -> %s" % [nm, p, a, fp])
	quit()

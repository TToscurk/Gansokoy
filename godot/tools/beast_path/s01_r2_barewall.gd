extends "res://tools/beast_path/s01_r2_shots.gd"
## S01 R2 谷壁「裸露面」量測（診斷，不進產物）：同一組 R2 審圖鏡位，把 S01 地形換成不受光的哨兵材質——
##   洋紅＝坡度 > 41°（1−N.y > 0.25）而且不在土袋裡（CUSTOM0.a；R1 沒有土袋）＝畫面上的裸露灰褐坡；黑＝其他地形。
## 樹、岩、林下、道具照常渲染（照常遮擋）。之後 evidence/scripts/barewall.py 算洋紅的覆蓋率與最大連通塊。
##   godot --path godot --script res://tools/beast_path/s01_r2_barewall.gd -- --map=beast_path --out=<dir> --only=w30_back,...
## 這只是幾何＋遮擋的量測（不是美術判斷）：它回答「從同一鏡位看，裸露的陡坡在畫面上連成多大一片」。

const SENTINEL := """
shader_type spatial;
render_mode unshaded, fog_disabled, cull_back;
varying vec3 wn;
varying float soil;
void vertex() { wn = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz; soil = 1.0 - CUSTOM0.a; }
void fragment() {
	float steep = 1.0 - normalize(wn).y;
	ALBEDO = (steep > 0.25 && soil < 0.5) ? vec3(1.0, 0.0, 1.0) : vec3(0.0);
}
"""


func _go() -> void:
	var out := ""
	var only: PackedStringArray = []
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		elif a.begins_with("--only="):
			only = a.trim_prefix("--only=").split(",")
	DirAccess.make_dir_recursive_absolute(out)
	lib = BP.new()
	lib.setup(true, true)
	get_root().size = Vector2i(1600, 900)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	while true:
		await physics_frame
		player = main.get("player")
		if player and String(main.get("current_id")) == "beast_path" and player.is_on_floor():
			break
	adapter = player.get_node("CameraAdapter")
	adapter.set_process_unhandled_input(false)
	player.set_process_unhandled_input(false)
	var dn := root.get_node_or_null("DayNight")
	if dn != null:
		dn.set("flowing", false)
		dn.call("set_hour", 10.0)
	# S01 地形網格：mesh 路徑是 s01_terrain.res 的 MeshInstance3D
	var terr: Array[MeshInstance3D] = []
	for n in main.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh != null and mi.mesh.resource_path.ends_with("s01_terrain.res"):
			terr.append(mi)
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SENTINEL
	sm.shader = sh
	print("[bare] S01 地形網格 %d 個" % terr.size())
	var gp_cam: Camera3D = player.get_viewport().get_camera_3d()
	var free_cam := Camera3D.new()
	free_cam.fov = 62.0
	free_cam.far = 900.0
	root.add_child(free_cam)
	for v: Dictionary in _views():
		var nm := String(v["name"])
		if not only.is_empty() and not only.has(nm):
			continue
		_hide_hud()
		if v.has("free"):
			var fr: Dictionary = v["free"]
			var cm: Array = fr["cam"]
			var lk: Array = fr["look"]
			free_cam.global_position = Vector3(float(cm[0]), lib.h_at(float(cm[0]), float(cm[2])) + float(fr.get("cam_above", 2.0)), float(cm[2]))
			free_cam.look_at(Vector3(float(lk[0]), lib.h_at(float(lk[0]), float(lk[2])) + float(fr.get("look_above", 1.0)), float(lk[2])))
			free_cam.make_current()
			player.visible = false
		else:
			await _put(Vector2(float(v["at"][0]), float(v["at"][1])), -deg_to_rad(float(v["face"])), float(v.get("pitch", -0.18)), float(v.get("dist", 8.5)))
			if gp_cam != null:
				gp_cam.make_current()
			player.visible = true
		for mi2: MeshInstance3D in terr:
			mi2.material_override = sm
		for i in 40:
			await process_frame
		get_root().get_texture().get_image().save_png("%s/%s__bare.png" % [out, nm])
		for mi3: MeshInstance3D in terr:
			mi3.material_override = null
		print("  ✓ %s" % nm)
	quit(0)

extends SceneTree
## P10 NPC Asset Library 審圖撮影（再現可能・非 headless・Forward+）：studio ブースに NPC を並べて撮る。village_v2 は読まない。
##   godot --path . --script res://tools/shot_npc_library.gd -- <shots.json> <outdir/>
## shots.json の各要素：
##   {"name": "...", "size": [w, h]（可選）, "silhouette": false, "ruler": false, "labels": false,
##    "npcs": [{"id": "kozo_m01", "x": 0.0, "z": 0.0, "yaw": 0, "clip_res": "res://…res"（可選：無ければ tscn の idle、tscn も無ければ rest）,
##              "anim": "idle"|"walk"（tscn 使用時）, "t": 0.0}],
##    "seq": {"times": [0, 0.3, …]}（可選：各時点で連続撮影 <name>_NN.png）,
##    "cam": {"type": "look", "eye": [x,y,z], "at": [x,y,z], "fov": 30} | {"type": "ortho", "center": [x,y,z], "size": 2.2, "dir": [0,0,1]}}

var studio: Array[Node] = []
var ruler: Array[Node] = []


func _scene_for(id: String) -> Node3D:
	var tscn := "res://characters/npc/%s/%s.tscn" % [id, id]
	if ResourceLoader.exists(tscn):
		return (load(tscn) as PackedScene).instantiate()
	var w := Node3D.new()   # tscn 前（動作未取り込み）：glb だけ
	w.name = id
	w.add_child((load("res://characters/npc/%s/%s.glb" % [id, id]) as PackedScene).instantiate())
	return w


func _apply_clip(n: Node3D, d: Dictionary) -> AnimationPlayer:
	var model := n.get_child(0) as Node3D
	var ap := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if d.has("clip_res"):
		if ap == null:
			ap = AnimationPlayer.new()
			ap.name = "AnimationPlayer"
			model.add_child(ap)
			ap.root_node = NodePath("../Armature")
		var lib := AnimationLibrary.new()
		lib.add_animation(&"c", load(d["clip_res"]))
		if ap.has_animation_library(&"shot"):
			ap.remove_animation_library(&"shot")
		ap.add_animation_library(&"shot", lib)
		ap.play(&"shot/c")
	elif ap != null and n.has_method("play_clip"):
		n.call("play_clip", StringName(d.get("anim", "idle")), float(d.get("t", 0.0)))
	if ap != null and ap.current_animation != "":
		ap.seek(fmod(float(d.get("t", 0.0)), ap.current_animation_length), true)
		ap.speed_scale = 0.0
	return ap


func _env(sil: bool) -> void:
	for x in studio:
		x.queue_free()
	studio.clear()
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(1, 1, 1) if sil else Color(0.46, 0.46, 0.45)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.8, 0.84)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR if sil else Environment.TONE_MAPPER_FILMIC
	we.environment = env
	studio.append(we)
	if not sil:
		var sun := DirectionalLight3D.new()
		sun.light_energy = 1.25
		sun.light_color = Color(1.0, 0.96, 0.9)
		sun.shadow_enabled = true
		sun.rotation_degrees = Vector3(-38, 30, 0)
		studio.append(sun)
		var fill := DirectionalLight3D.new()
		fill.light_energy = 0.35
		fill.rotation_degrees = Vector3(-20, -150, 0)
		studio.append(fill)
		var floor_mi := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(30, 12)
		floor_mi.mesh = pm
		var fm := StandardMaterial3D.new()
		fm.albedo_color = Color(0.5, 0.5, 0.49)
		floor_mi.material_override = fm
		studio.append(floor_mi)
	for x in studio:
		root.add_child(x)


func _box(size: Vector3, pos: Vector3, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	mi.material_override = m
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _label(txt: String, pos: Vector3, px: int, col: Color) -> Label3D:
	var l := Label3D.new()
	l.text = txt
	l.font_size = px
	l.pixel_size = 0.0022
	l.modulate = col
	l.outline_size = 0
	l.position = pos
	l.no_depth_test = true
	l.shaded = false
	return l


func _ruler(x0: float, x1: float, sil: bool) -> void:
	for x in ruler:
		x.queue_free()
	ruler.clear()
	var ink := Color(0.15, 0.15, 0.15) if sil else Color(0.08, 0.08, 0.08)
	var faint := Color(0.55, 0.55, 0.55) if sil else Color(0.32, 0.32, 0.31)
	for xr in [x0 - 0.45, x1 + 0.45]:
		ruler.append(_box(Vector3(0.025, 2.0, 0.025), Vector3(xr, 1.0, -0.5), ink))
		for i in 21:
			var h := i * 0.1
			var major := i % 5 == 0
			ruler.append(_box(Vector3(0.16 if major else 0.08, 0.006, 0.01), Vector3(xr, h, -0.49), ink))
			if major or i >= 14:
				ruler.append(_label("%.1f m" % h, Vector3(xr + (-0.27 if xr < x0 else 0.27), h, -0.48), 34 if major else 26, ink))
	for h in [1.5, 1.6, 1.7, 1.8]:
		ruler.append(_box(Vector3(x1 - x0 + 0.9, 0.004, 0.004), Vector3((x0 + x1) / 2, h, -0.52), faint))
	for x in ruler:
		root.add_child(x)


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var shots: Array = JSON.parse_string(FileAccess.get_file_as_string(a[0]))
	var outdir: String = a[1]
	var cam := Camera3D.new()
	cam.near = 0.05
	cam.far = 200.0
	root.add_child(cam)
	cam.make_current()
	var cur_sil := -1
	for s: Dictionary in shots:
		var sz: Array = s.get("size", [1152, 648])
		DisplayServer.window_set_size(Vector2i(int(sz[0]), int(sz[1])))
		root.size = Vector2i(int(sz[0]), int(sz[1]))
		var sil: bool = s.get("silhouette", false)
		if int(sil) != cur_sil:
			_env(sil)
			cur_sil = int(sil)
		var made: Array[Node3D] = []
		var aps: Array = []
		var xs: Array[float] = []
		for d: Dictionary in s["npcs"]:
			var n := _scene_for(d["id"])
			n.set("frozen", true)
			n.set("start_time", float(d.get("t", 0.0)))
			root.add_child(n)
			await process_frame   # npc_visual._ready（AnimationPlayer 生成）を待つ
			n.position = Vector3(float(d.get("x", 0.0)), 0.0, float(d.get("z", 0.0)))
			n.rotation = Vector3(0, deg_to_rad(float(d.get("yaw", 0.0))), 0)
			aps.append(_apply_clip(n, d))
			made.append(n)
			xs.append(float(d.get("x", 0.0)))
			if sil:
				var bm := StandardMaterial3D.new()
				bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				bm.albedo_color = Color(0, 0, 0)
				for mi in n.find_children("*", "MeshInstance3D", true, false):
					(mi as MeshInstance3D).material_override = bm
			if s.get("labels", false):
				var lb := _label(String(d.get("label", d["id"])), Vector3(0, -0.09, 0.3), 30, Color(0.1, 0.1, 0.1))
				n.add_child(lb)
		if s.get("ruler", false):
			_ruler(xs.min(), xs.max(), sil)
		var c: Dictionary = s["cam"]
		if c["type"] == "ortho":
			cam.projection = Camera3D.PROJECTION_ORTHOGONAL
			cam.size = float(c["size"])
			var ce := Vector3(c["center"][0], c["center"][1], c["center"][2])
			var dr := Vector3(c.get("dir", [0, 0, 1])[0], c.get("dir", [0, 0, 1])[1], c.get("dir", [0, 0, 1])[2]).normalized()
			cam.global_position = ce + dr * 20.0
			cam.look_at(ce, Vector3.UP)
		else:
			cam.projection = Camera3D.PROJECTION_PERSPECTIVE
			cam.fov = float(c.get("fov", 30.0))
			cam.global_position = Vector3(c["eye"][0], c["eye"][1], c["eye"][2])
			cam.look_at(Vector3(c["at"][0], c["at"][1], c["at"][2]), Vector3.UP)
		for i in 8:
			await process_frame
		var times: Array = s["seq"]["times"] if s.has("seq") else [null]
		for k in times.size():
			if times[k] != null:
				for j in made.size():
					var ap := aps[j] as AnimationPlayer
					if ap != null and ap.current_animation != "":
						var d2: Dictionary = s["npcs"][j]
						ap.seek(fmod(float(d2.get("t", 0.0)) + float(times[k]), ap.current_animation_length), true)
			for i in 4:
				await process_frame
			await RenderingServer.frame_post_draw
			var fn := outdir + ("%s_%02d.png" % [s["name"], k] if times[k] != null else "%s.png" % s["name"])
			root.get_texture().get_image().save_png(fn)
		print("SHOT %s npcs %d frames %d" % [s["name"], made.size(), times.size()])
		for n in made:
			n.queue_free()
		await process_frame
	quit(0)

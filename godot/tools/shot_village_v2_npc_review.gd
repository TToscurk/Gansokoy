extends SceneTree
## P10 R3a NPC Prototype 審圖撮影（ART_REVIEW 用・再現可能）：非 headless・Forward+。
##   godot --path . --script res://tools/shot_village_v2_npc_review.gd -- <shots.json> <outdir/>
## shots.json の各要素：
##   {"name": "...", "mode": "studio"|"village", "hour": 10.0,
##    "npc":  {"pos": [x, z], "y": 可選（無ければ地形へ raycast）, "face": [dx, dz], "yaw": studio 用（度）, "anim": "idle", "t": 2.0},
##    "yori": {"pos": [x, z], "face": [dx, dz]}   ← 緣一＝yoriichi_body.fbx＋idle_grounded（正式資產は読むだけ）
##    "cam":  {"type": "tps", "player": [x, z], "target": [x, z], "dist": 8.5, "pitch": -0.18}   ← 遊戲の SpringArm（樞軸 1.70 m・肩 0.40/0.10・FOV 75・壁で縮む）
##         | {"type": "look", "eye": [x, h, z], "at": [x, h, z], "fov": 40}                      ← village では h＝足元の地表からの高さ
##   }
## studio：灰色背景・太陽＋補助光の中性ブース（原点に立たせる）。village と同じ実行で混ぜない。

const NPC_SCENE := "res://characters/npc/chonin_m01/chonin_m01.tscn"
const YORI_SCENE := "res://characters/yoriichi/yoriichi_body.fbx"
const YORI_IDLE := "res://characters/yoriichi/animations/yoriichi_idle_grounded.res"

var v: Node3D
var sp: PhysicsDirectSpaceState3D


func _ground(p: Vector2) -> float:
	if sp == null:
		return 0.0
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 60.0, p.y), Vector3(p.x, -20.0, p.y))
	var ex: Array[RID] = []
	for k in 16:
		q.exclude = ex
		var hit := sp.intersect_ray(q)
		if hit.is_empty():
			break
		if String((hit.collider as Node).name).begins_with("TerrainCollision"):
			return hit.position.y
		ex.append(hit.rid)
	return 0.0


func _place(n: Node3D, d: Dictionary) -> float:
	var p := Vector2(d["pos"][0], d["pos"][1])
	var y: float = float(d["y"]) if d.has("y") else _ground(p)
	var f := Vector2(d.get("face", [0, 1])[0], d.get("face", [0, 1])[1]).normalized()
	n.global_position = Vector3(p.x, y, p.y)
	n.rotation = Vector3(0, atan2(f.x, f.y), 0)   # モデルの正面＝+Z
	return y


func _yoriichi() -> Node3D:
	var y: Node3D = (load(YORI_SCENE) as PackedScene).instantiate()
	root.add_child(y)
	var ap := y.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var lib := AnimationLibrary.new()
	lib.add_animation(&"idle_grounded", load(YORI_IDLE))
	ap.add_animation_library(&"npcshot", lib)
	ap.play(&"npcshot/idle_grounded")
	ap.seek(0.5, true)
	ap.speed_scale = 0.0
	return y


func _studio() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.46, 0.46, 0.45)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.8, 0.84)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.25
	sun.light_color = Color(1.0, 0.96, 0.9)
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-38, 30, 0)
	root.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.35
	fill.rotation_degrees = Vector3(-20, -150, 0)
	root.add_child(fill)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(8, 8)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.5, 0.5, 0.49)
	floor_mi.material_override = fm
	root.add_child(floor_mi)


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var shots: Array = JSON.parse_string(FileAccess.get_file_as_string(a[0]))
	var outdir: String = a[1]
	var cam := Camera3D.new()
	cam.near = 0.05
	cam.far = 900.0
	root.add_child(cam)
	cam.make_current()
	var studio_ready := false
	for s: Dictionary in shots:
		var mode: String = s.get("mode", "village")
		if mode == "village" and v == null:
			v = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
			root.add_child(v)
			for nm in ["Debug", "Portals", "QuestAnchors"]:
				if v.has_node(nm):
					v.get_node(nm).visible = false
			for n in v.get_node("Districts").find_children("*ParcelLines*", "", true, false):
				n.visible = false
			await process_frame
			sp = v.get_world_3d().direct_space_state
			for i in 20:
				await process_frame
		if mode == "studio" and not studio_ready:
			_studio()
			studio_ready = true
		for c in root.get_children():
			if c.has_method("set_hour"):
				c.set_hour(float(s.get("hour", 10.0)))
		var made: Array[Node] = []
		var npc_y := 0.0
		if s.has("npc"):
			var npc: Node3D = (load(NPC_SCENE) as PackedScene).instantiate()
			npc.set("frozen", true)
			npc.set("start_time", float(s["npc"].get("t", 2.0)))
			npc.set("animation", StringName(s["npc"].get("anim", "idle")))
			root.add_child(npc)
			await process_frame   # SceneTree._init 中は _ready が次フレームまで遅れる（AnimationPlayer はそこで作られる）
			if s["npc"].has("clip_res"):   # 候選 clip（共通 library に一時追加して再生）
				var ap0 := npc.find_child("AnimationPlayer", true, false) as AnimationPlayer
				var cn := StringName(String(s["npc"]["clip_res"]).get_file().get_basename())
				ap0.get_animation_library(&"").add_animation(cn, load(s["npc"]["clip_res"]))
				npc.call("play_clip", cn, float(s["npc"].get("t", 2.0)))
			if mode == "studio":
				npc.global_position = Vector3(s["npc"]["pos"][0], 0, s["npc"]["pos"][1])
				npc.rotation = Vector3(0, deg_to_rad(float(s["npc"].get("yaw", 0.0))), 0)
			else:
				npc_y = _place(npc, s["npc"])
			made.append(npc)
		if s.has("yori"):
			var yo := _yoriichi()
			if mode == "studio":
				yo.global_position = Vector3(s["yori"]["pos"][0], 0, s["yori"]["pos"][1])
			else:
				_place(yo, s["yori"])
			made.append(yo)
		var c: Dictionary = s["cam"]
		if c["type"] == "tps":
			var pp := Vector2(c["player"][0], c["player"][1])
			var tt := Vector2(c["target"][0], c["target"][1])
			var gy := _ground(pp)
			var f := (tt - pp).normalized()
			var yaw := atan2(-f.x, -f.y)   # Godot：-Z が前
			var pitch := float(c.get("pitch", -0.18))
			var b := Basis.from_euler(Vector3(pitch, yaw, 0))
			var piv := Vector3(pp.x, gy + 1.70, pp.y)
			var dist := float(c.get("dist", 8.5))
			if sp != null:
				var hit := sp.intersect_ray(PhysicsRayQueryParameters3D.create(piv, piv + b * Vector3(0.0, 0.0, dist)))
				if not hit.is_empty():
					dist = maxf(0.6, piv.distance_to(hit.position) - 0.2)
			cam.fov = 75.0
			cam.global_transform = Transform3D(b, piv + b * Vector3(0.40, 0.10, dist))
			print("SHOTCAM %s arm %.2f" % [s["name"], dist])
		else:
			var e := Vector3(c["eye"][0], c["eye"][1], c["eye"][2])
			var t := Vector3(c["at"][0], c["at"][1], c["at"][2])
			if mode == "village":
				e.y += _ground(Vector2(e.x, e.z))
				t.y += npc_y
			cam.fov = float(c.get("fov", 40.0))
			cam.global_transform = Transform3D(Basis(), e).looking_at(t, Vector3.UP)
		for i in 14:
			await process_frame
		if s.has("seq") and s.has("npc"):
			# 連続撮影：clip を t 秒へ、move があれば NPC を from→to へ speed m/s で進める（in-place の歩行を実際に歩かせる）
			var npc2: Node3D = made[0]
			var ap2 := npc2.find_child("AnimationPlayer", true, false) as AnimationPlayer
			var mv: Dictionary = s["seq"].get("move", {})
			for k in (s["seq"]["times"] as Array).size():
				var tt2 := float(s["seq"]["times"][k])
				ap2.seek(fmod(float(s["npc"].get("t", 0.0)) + tt2, ap2.current_animation_length), true)
				if not mv.is_empty():
					var a2 := Vector2(mv["from"][0], mv["from"][1])
					var b2 := Vector2(mv["to"][0], mv["to"][1])
					var p2 := a2 + (b2 - a2).normalized() * float(mv["speed"]) * tt2
					npc2.global_position = Vector3(p2.x, _ground(p2), p2.y)
					npc2.rotation = Vector3(0, atan2((b2 - a2).x, (b2 - a2).y), 0)
				for i in 6:
					await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(outdir + "%s_%02d.png" % [s["name"], k])
			print("SHOT %s seq %d" % [s["name"], (s["seq"]["times"] as Array).size()])
			for n in made:
				n.queue_free()
			await process_frame
			continue
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(outdir + String(s["name"]) + ".png")
		print("SHOT %s npc_y %.2f" % [s["name"], npc_y])
		for n in made:
			n.queue_free()
		await process_frame
	quit()

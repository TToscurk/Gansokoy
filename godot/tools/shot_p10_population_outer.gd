extends SceneTree
## P10 R3e Outer Village 審圖撮影（R3d の撮影ツールと同じ手順）。route 鏡位は AFTER のみ・見えている住人の数を記録。
## （以下 R3d の説明）P10 R3d 審圖撮影：非 headless Forward+、最新 village_v2、10:00、1920×1080、正式 Player instance（審圖鏡位の TPS 再現）。
## 靜止鏡位は全員の animation phase を固定し、同じ鏡位で AFTER（R3b＋R3c＋R3d）／BEFORE（R3d の CoreP10 と ActivityCoreP10 だけ非表示＝承認済み baseline）。
## walk 鏡位は実際の入力・衝突で歩いて 6 枚（R3d 有効）。
## 使い方：godot --path godot --script res://tools/shot_p10_population_outer.gd -- <outdir/> [--only=<view 名>]
const VG := preload("res://tools/verify_village_v2_population.gd")
const CL := preload("res://tools/village_v2_population_outer_lib.gd")
const CAPTURE_SIZE := Vector2i(1920, 1080)
const VIEWS := "res://tools/shot_village_v2_population_outer_views.json"
var v: Node3D
var player: CharacterBody3D
var cam: Camera3D
var helper: SceneTree
var sp: PhysicsDirectSpaceState3D
var outdir: String


func _initialize() -> void:
	run.call_deferred()


func camera_at(vw: Dictionary) -> void:
	var d: Dictionary = vw.duplicate(true)
	var dx := float(vw.target[0]) - float(vw.player[0])
	var dz := float(vw.target[1]) - float(vw.player[1])
	d.player = [player.global_position.x, player.global_position.z]
	d.target = [player.global_position.x + dx, player.global_position.z + dz]
	cam.global_transform = helper._tps(v, sp, d)


func snap(name: String) -> int:
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if root.size != CAPTURE_SIZE or image.get_size() != CAPTURE_SIZE or absf(cam.get_camera_projection().determinant()) <= 1e-8:
		push_error("[OUTERSHOT] Invalid capture viewport: window %s, image %s" % [root.size, image.get_size()])
		return 2
	var err := image.save_png(outdir + name + ".png")
	if err != OK:
		push_error("[OUTERSHOT] PNG save failed: %s (%s)" % [name, err])
		return 3
	print("[OUTERSHOT] ", name, " size ", image.get_size(), " player ", player.global_position, " cam ", cam.global_position)
	return OK


## 見えている住人（視錐台・60 m 以内・頭への視線が遮られない）の数
func visible_count(actors: Array) -> int:
	var ex: Array[RID] = []
	for b in actors:
		ex.append((b as CollisionObject3D).get_rid())
	var n := 0
	for b in actors:
		if not (b as Node3D).is_visible_in_tree():
			continue
		var head := (b as Node3D).global_position + Vector3(0, 1.4, 0)
		if not cam.is_position_in_frustum(head) or cam.global_position.distance_to(head) > 60.0:
			continue
		var q := PhysicsRayQueryParameters3D.create(cam.global_position, head)
		q.exclude = ex
		if sp.intersect_ray(q).is_empty():
			n += 1
	return n


func freeze(actors: Array, on: bool) -> void:
	for b in actors:
		var npc: Node = b.get_node("NPC")
		(npc.find_child("AnimationPlayer", true, false) as AnimationPlayer).speed_scale = 0.0 if on else float(npc.get("speed_scale"))


func run() -> void:
	root.borderless = true
	root.position = Vector2i.ZERO
	root.size = CAPTURE_SIZE
	for i in 8:
		await process_frame
	if root.size != CAPTURE_SIZE:
		push_error("[OUTERSHOT] Cannot lock 1920x1080 viewport: %s" % root.size)
		quit(2)
		return
	var args := OS.get_cmdline_user_args()
	outdir = args[0]
	var only := ""
	for a in args:
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=")
	DirAccess.make_dir_recursive_absolute(outdir)
	v = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	root.add_child(v)
	for nm in ["Debug", "Portals", "QuestAnchors"]:
		if v.has_node(nm):
			v.get_node(nm).visible = false
	for n in v.get_node("Districts").find_children("*ParcelLines*", "", true, false):
		n.visible = false
	for i in 20:
		await process_frame
	sp = v.get_world_3d().direct_space_state
	for c in root.get_children():
		if c.has_method("set_hour"):
			c.set_hour(10.0)
			c.set_process(false)
	helper = VG.new()
	player = (load("res://characters/yoriichi/player_yoriichi.tscn") as PackedScene).instantiate()
	player.add_to_group("player")
	root.add_child(player)
	player.set_physics_process(false)
	var yaw := Node3D.new()
	root.add_child(yaw)
	player.set("input_yaw_node", yaw)
	cam = Camera3D.new()
	cam.fov = 75.0
	cam.near = 0.05
	cam.far = 900.0
	root.add_child(cam)
	cam.make_current()
	var core := v.get_node("Population/" + CL.NODE_NAME) as Node3D
	var act := v.get_node("Population/" + CL.ACT_NODE)
	for i in 4:
		await process_frame
	var actors := v.get_node("Population").find_children("*", "AnimatableBody3D", true, false)
	var views: Array = JSON.parse_string(FileAccess.get_file_as_string(VIEWS))
	var counts := {}
	for vw: Dictionary in views:
		if only != "" and String(vw.name) != only:
			continue
		for b in actors:
			b.set_physics_process(false)
		var p := Vector2(vw.player[0], vw.player[1])
		player.global_position = Vector3(p.x, VG._ground(sp, p) + 0.03, p.y)
		player.velocity = Vector3.ZERO
		var f := (Vector2(vw.target[0], vw.target[1]) - p).normalized()
		yaw.rotation.y = atan2(-f.x, -f.y)
		player.rotation.y = yaw.rotation.y
		camera_at(vw)
		if vw.has("motion"):
			# 動態走訪：玩家が実際の入力で口へ歩き、住人は通常どおり動く（相位凍結なし）。fps 枚/秒で seconds 秒。
			if only == "" or only != String(vw.name):
				continue
			for b in actors:
				b.set_physics_process(String(b.get("mode")) == "patrol")
			freeze(actors, false)
			player.set_physics_process(true)
			Input.action_press("move_forward")
			var mo: Dictionary = vw["motion"]
			var nf := int(float(mo["seconds"]) * float(mo["fps"]))
			var step := int(60.0 / float(mo["fps"]))
			for k in nf:
				for j in step:
					await physics_frame
					camera_at(vw)
				if k == int(nf * 0.45):
					Input.action_release("move_forward")
				var em: int = await snap("%s_%02d" % [vw.name, k])
				if em != OK:
					helper.free()
					quit(em)
					return
			Input.action_release("move_forward")
			player.set_physics_process(false)
			continue
		if vw.has("walk"):
			for b in actors:
				b.set_physics_process(String(b.get("mode")) == "patrol")
			player.set_physics_process(true)
			Input.action_press("move_forward")
			var start := player.global_position
			for k in 6:
				for j in 36:
					await physics_frame
					camera_at(vw)
				var e0: int = await snap("5_walk_through_%02d" % k)
				if e0 != OK:
					Input.action_release("move_forward")
					helper.free()
					quit(e0)
					return
			Input.action_release("move_forward")
			player.set_physics_process(false)
			print("[OUTERWALK] travelled ", start.distance_to(player.global_position))
		elif vw.has("route"):
			freeze(actors, true)
			var vc := visible_count(actors)
			counts[String(vw.name)] = vc
			var er: int = await snap(String(vw.name))
			if er != OK:
				helper.free()
				quit(er)
				return
			freeze(actors, false)
		else:
			freeze(actors, true)
			core.visible = true
			act.call("set_enabled", true)
			freeze(actors, true)
			var e1: int = await snap(String(vw.name) + "_after")
			if e1 != OK:
				helper.free()
				quit(e1)
				return
			core.visible = false
			act.call("set_enabled", false)
			var e2: int = await snap(String(vw.name) + "_before")
			if e2 != OK:
				helper.free()
				quit(e2)
				return
			core.visible = true
			act.call("set_enabled", true)
			freeze(actors, false)
	if not counts.is_empty():
		var f := FileAccess.open(outdir + "route_counts.json", FileAccess.WRITE)
		f.store_string(JSON.stringify(counts, " "))
		f.close()
		print("[OUTERSHOT] route counts ", counts)
	helper.free()
	quit(0)

extends SceneTree
## P11 R2D-Fix 短距離實走＋NPC／道路／伏越し水理（非 headless、正式 main.tscn、玩家實際 CharacterBody3D 輸入）。
##   godot --path . --resolution 1280x720 --script res://tools/p11r2d/walk_branches.gd -- --no-review
## 段：伏越し 3 か所の道路上を沿って通過、FarmPath_5 西端（T0 の脇）、N0 土渠を直角に横断（低い堤 0.2 m 級）、T0 木槽脇。
## 判定：抵達・橫偏 < 0.6 m・足元と地面の差 ≤ 0.30 m（乗り上げ／落ち込み）・停止 2 秒以上 0。
const ZL := preload("res://tools/village_v2_farmland_zone.gd")
const FARM := "Districts/FarmlandEast/FarmlandP8"
const LEGS := [
	["N0 伏越し FarmPath_4 上を通過", Vector2(353.0, 0.0), Vector2(368.0, 0.0)],
	["N0 伏越し CrossStreetMid 上を通過", Vector2(350.0, -34.7), Vector2(368.0, -35.4)],
	["T0 伏越し CrossStreetSouth 上を通過", Vector2(326.0, 42.5), Vector2(344.0, 41.4)],
	["T0 脇 FarmPath_5 西端へ", Vector2(344.0, 70.0), Vector2(331.5, 70.0)],
	["N0 土渠を直角に横断", Vector2(360.5, -18.0), Vector2(367.5, -18.0)],
	["T0 接合部（木槽→土渠）の脇", Vector2(333.5, 51.0), Vector2(329.0, 57.5)],
]
var main: Node
var player: CharacterBody3D
var fails := 0

func _init() -> void:
	_run.call_deferred()

func _ground(x: float, z: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 30.0, z), Vector3(x, -30.0, z))
	q.exclude = [player.get_rid()]
	var r := player.get_world_3d().direct_space_state.intersect_ray(q)
	return NAN if r.is_empty() else (r["position"] as Vector3).y

func _chk(label: String, ok: bool, detail: String) -> void:
	print("[BWALK] %s %s：%s" % ["PASS" if ok else "FAIL", label, detail])
	if not ok:
		fails += 1

func _leg(label: String, a: Vector2, b: Vector2) -> void:
	var d0 := b - a
	player.global_position = Vector3(a.x, _ground(a.x, a.y) + 0.05, a.y)
	player.velocity = Vector3.ZERO
	player.snap_yaw(atan2(-d0.x, -d0.y))
	for i in 20:
		await physics_frame
	Input.action_press("move_forward")
	var dir := d0.normalized()
	var dev := 0.0
	var gap := 0.0
	var arrived := false
	var still := 0
	var max_still := 0
	var last := player.global_position
	for f in 60 * 20:
		var p := Vector2(player.global_position.x, player.global_position.z)
		if (b - p).length() < 0.8:
			arrived = true
			break
		if f % 6 == 0:
			var d := b - p
			player.snap_yaw(atan2(-d.x, -d.y))
		await physics_frame
		var rel := p - a
		dev = maxf(dev, absf(rel.x * dir.y - rel.y * dir.x))
		if player.is_on_floor():
			var g := _ground(player.global_position.x, player.global_position.z)
			if not is_nan(g):
				gap = maxf(gap, absf(player.global_position.y - g))
		if player.global_position.distance_to(last) < 0.004:
			still += 1
			max_still = maxi(max_still, still)
		else:
			still = 0
		last = player.global_position
	Input.action_release("move_forward")
	for i in 10:
		await physics_frame
	_chk(label, arrived and dev < 0.6 and gap <= 0.30 and max_still < 120,
		"抵達=%s 橫偏 %.2f m 足元−地面 最大 %.2f m 停止 %d 幀 終点 %s" % [arrived, dev, gap, max_still, player.global_position.snappedf(0.01)])

func _terrain(x: float, z: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 30.0, z), Vector3(x, -30.0, z))
	var ex: Array[RID] = [player.get_rid()]
	for i in 12:
		q.exclude = ex
		var r := player.get_world_3d().direct_space_state.intersect_ray(q)
		if r.is_empty():
			return NAN
		if String((r["collider"] as Node).name).begins_with("TerrainCollision"):
			return (r["position"] as Vector3).y
		ex.append(r["rid"])
	return NAN

func _run() -> void:
	var flags := root.get_node("/root/StoryFlags")
	flags.set_flag("woke_in_trail", true)
	flags.set_flag("met_reimu", true)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	for i in 60:
		await process_frame
	main.load_map("village_v2", "")
	for i in 90:
		await process_frame
	player = main.player
	player.set("input_locked", false)
	for cl in root.find_children("*", "CanvasLayer", true, false):
		(cl as CanvasLayer).visible = false
	var v: Node = main.map_root
	# 1) 實走
	for lg in LEGS:
		await _leg(lg[0], lg[1], lg[2])
	# 2) NPC：巡回 path と待機位置が支線の碰撞形（Br*）から 0.5 m 以内に入らない
	var zw := v.get_node(FARM + "/Irrigation/ZoneWater")
	var shapes: Array = []
	for c in zw.get_children():
		if String(c.name).begins_with("Br"):
			shapes.append(c)
	var sp := player.get_world_3d().direct_space_state
	var npc_bad := []
	var n_patrol := 0
	var n_idle := 0
	var probe := SphereShape3D.new()
	probe.radius = 0.5
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = probe
	var zw_rid := (zw as CollisionObject3D).get_rid()
	for b in v.get_node("Population").find_children("*", "AnimatableBody3D", true, false):
		var pts: Array = []
		if String(b.get("mode")) == "patrol":
			n_patrol += 1
			var px: PackedVector2Array = b.get("path_xz")
			for k in px.size() - 1:
				for t in 11:
					pts.append(px[k].lerp(px[k + 1], t / 10.0))
		else:
			n_idle += 1
			pts.append(Vector2((b as Node3D).global_position.x, (b as Node3D).global_position.z))
		for p2: Vector2 in pts:
			q.transform = Transform3D(Basis(), Vector3(p2.x, _ground(p2.x, p2.y) + 0.6, p2.y))
			for h in sp.intersect_shape(q, 8):
				if h["rid"] == zw_rid:
					var sh: Node = zw.shape_owner_get_owner(zw.shape_find_owner(h["shape"]))
					if String(sh.name).begins_with("Br"):
						npc_bad.append("%s→%s" % [b.name, sh.name])
						break
	_chk("NPC 通路（巡回 %d・待機 %d）が新支線の碰撞から 0.5 m 以内" % [n_patrol, n_idle], npc_bad.is_empty(), str(npc_bad.slice(0, 4)) if not npc_bad.is_empty() else "0 件")
	# 3) 道路面：支線の碰撞形の 5×5 取樣点と可見網格頂点が道路 ribbon に入らない
	var tris: Array = []
	for mi: MeshInstance3D in v.get_node("Roads").find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or String(v.get_path_to(mi)).begins_with("Roads/Bridges"):
			continue
		var f := mi.mesh.get_faces()
		for t in range(0, f.size(), 3):
			var a3 := mi.global_transform * f[t]
			var b3 := mi.global_transform * f[t + 1]
			var c3 := mi.global_transform * f[t + 2]
			tris.append([Vector2(a3.x, a3.z), Vector2(b3.x, b3.z), Vector2(c3.x, c3.z)])
	var on_road := func(p2: Vector2) -> bool:
		for t in tris:
			if Geometry2D.point_is_inside_triangle(p2, t[0], t[1], t[2]):
				return true
		return false
	var rhit := 0
	for s in shapes:
		var bx := ((s as CollisionShape3D).shape as BoxShape3D).size
		for i in 5:
			for j in 5:
				var w := (s as Node3D).global_transform * Vector3((i / 4.0 - 0.5) * bx.x, 0, (j / 4.0 - 0.5) * bx.z)
				if on_road.call(Vector2(w.x, w.z)):
					rhit += 1
	var vhit := 0
	for mi: MeshInstance3D in v.get_node(FARM + "/ZoneWorks/ZoneIrrigation/Branches").find_children("*", "MeshInstance3D", true, false):
		for si in mi.mesh.get_surface_count():
			for p3: Vector3 in mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]:
				var w := mi.global_transform * p3
				if on_road.call(Vector2(w.x, w.z)):
					vhit += 1
	_chk("道路面に支線の碰撞／可見網格が入らない", rhit == 0 and vhit == 0, "碰撞取樣 %d・頂点 %d" % [rhit, vhit])
	# 4) 伏越し水理（幾何で言えることだけ）
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/village_v2_p8_blocks.json"))
	for br: Dictionary in ZL.branch_specs():
		for r: Dictionary in br["runs"]:
			if r["kind"] != "siphon":
				continue
			var line: PackedVector2Array = r["line"]
			var w: PackedFloat32Array = r["w"]
			var mid := line[0].lerp(line[1], 0.5)
			var ry := _ground(mid.x, mid.y)     # 道路中央：最上面（路面）
			var g0 := _terrain(line[0].x, line[0].y)
			var g1 := _terrain(line[1].x, line[1].y)
			var pipe_top := ry - ZL.PIPE_COVER
			var ok := w[0] > w[1] and w[1] > g1 and w[0] > g0
			_chk("%s 伏越し %s→%s" % [br["id"], line[0], line[1]], ok,
				"入口水面 %.3f（桝地形 %.3f）→ 出口水面 %.3f（桝地形 %.3f）水頭差 %.3f m、管長≈%.1f m、路面 %.3f・管頂（覆土 %.2f）%.3f ＜ 水面 → 滿管＝伏越し；管徑・糙率・流量 未設定＝流量充足は未驗證" % [
					w[0], g0, w[1], g1, w[0] - w[1], line[0].distance_to(line[1]), ry, ZL.PIPE_COVER, pipe_top])
	print("[BWALK] result: %d failed" % fails)
	quit(1 if fails > 0 else 0)

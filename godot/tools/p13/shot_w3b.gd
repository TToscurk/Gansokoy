extends SceneTree
## P13 W3B：土渠（N0／T0）の撮影ハーネス。非 headless、Forward+、10:00、正式 main.tscn → village_v2（場景ファイルは書かない）。
##   godot --path . --script res://tools/p13/shot_w3b.gd -- <outdir/> <mode> [set]
##   mode：orig＝Wave 3 以前（CanalSampleP13 があれば enabled=false）／sample＝W3 の樣本のまま／formal＝現行（overlay 無し）／
##         exp＝実験（現行の生成器 branch_art を記憶體内で回して Branches を差し替える。再烘焙なしで見た目を反復確認するため。場景ファイルは書かない）／
##         old＝W3B 以前の Branches（.godot/w3b_backup/farmland_p8_before.scn のもの）を記憶體内で戻す（正式重烘後に Before を撮るため。場景ファイルは書かない）
##         ※ sample（W3 の樣本 overlay）は退役済み（git e50c84c で復元可）。orig は「今の farmland_p8.scn のまま」＝正式重烘後は After と同じ
##   set ：scout（俯瞰で位置確認）／tps（N0・T0 の TPS）／high（農田高視角）／seam（接合・外縁の近景）／all
const OVR := "CanalSampleP13"
const FLib := preload("res://tools/village_v2_farmland_lib.gd")
const ZLib := preload("res://tools/village_v2_farmland_zone.gd")
const Visual := preload("res://tools/village_v2_farmland_visual.gd")
const ZI := "Districts/FarmlandEast/FarmlandP8/ZoneWorks/ZoneIrrigation"

var main: Node
var player: CharacterBody3D
var mr: Node3D
var out := ""
var mode := "formal"


func _init() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await _frames(14)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + name + ".png")
	print("SHOT ", name)


func _terrain_h(x: float, z: float) -> float:
	var tc := mr.get_node("Collision/TerrainCollision") as CollisionObject3D
	var sp := player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 60, z), Vector3(x, -30, z))
	q.collide_with_bodies = true
	var ex: Array[RID] = [player.get_rid()]
	for i in 12:
		q.exclude = ex
		var hit := sp.intersect_ray(q)
		if hit.is_empty():
			return NAN
		if hit.rid == tc.get_rid():
			return float(hit.position.y)
		ex.append(hit.rid)
	return NAN


## 撮影の再現性：実機の使用者のマウスが Godot の窓に入ると（Input.mouse_mode＝CAPTURED）カメラの pitch が動き、同鏡位でなくなる
## （n0scan で pitch が上限 +31.5° に張り付いた）。マウス捕捉を外し、既定の pitch −0.18 rad へ固定する。
func _fix_camera() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var ad := player.get_node_or_null("CameraAdapter")
	if ad:
		ad.set("_target_pitch", -0.18)
		ad.set("_current_pitch", -0.18)
		ad.set("_slope_bias", 0.0)


func _place(at: Vector2, look: Vector2) -> void:
	_fix_camera()
	player.velocity = Vector3.ZERO
	var h := _terrain_h(at.x, at.y)
	player.global_position = Vector3(at.x, (h if not is_nan(h) else 0.5) + 0.05, at.y)
	player.call("snap_yaw", atan2(-(look.x - at.x), -(look.y - at.y)))
	await _frames(45)


func _tps(name: String, at: Vector2, look: Vector2, masks := false) -> void:
	await _place(at, look)
	var pc := player.find_child("Camera3D", true, false) as Camera3D
	if pc:
		var pg := player.global_position
		print("[W3B] %s player(%.1f,%.2f,%.1f) camera 距離 %.2f m・地面上 %.2f m・pitch %.1f°" % [name, pg.x, pg.y, pg.z, pc.global_position.distance_to(pg + Vector3(0, 1.4, 0)),
			pc.global_position.y - _terrain_h(pc.global_position.x, pc.global_position.z), rad_to_deg(pc.global_rotation.x)])
	if masks:
		await _shot_masks(name)
	else:
		await _shot(name)


var _cam: Camera3D


## exp：現行の生成器（ZLib.branch_art）で Branches を記憶體内に再生成し、封存の Branches と差し替える（_merge まで生成器と同じ）
func _swap_branches() -> void:
	var zi := mr.get_node(ZI)
	var old := zi.get_node("Branches") as Node3D
	old.visible = false
	Visual._load_materials()
	Visual._noise = FastNoiseLite.new()
	Visual._noise.seed = 8108
	Visual._noise.frequency = 0.35
	var P: Dictionary = FLib.plan()
	var nb := Node3D.new()
	nb.name = "BranchesExp"
	zi.add_child(nb)
	var rng := RandomNumberGenerator.new()
	rng.seed = 60601
	ZLib.branch_art(nb, P["zone"], Visual._wood_mat(), Visual._stone_mat(), Visual._ground_mat(), Visual._flow_mat(0.8, Color(0.36, 0.36, 0.3), 0.7), Visual._flow_mat(0.6, Color(0.16, 0.16, 0.13), 0.12), rng)
	for sub: Node in nb.get_children():
		ZLib._merge(sub as Node3D, 180.0, true)
	print("[W3B] exp: Branches 再生成 → ", nb.find_children("*", "MeshInstance3D", true, false).size(), " メッシュ")


## 分類：earth（ground shader）／water（p8_paddy_water）／struct（木・石）
func _kind(mi: MeshInstance3D) -> String:
	var m := mi.material_override
	if m is ShaderMaterial:
		var sp := String((m as ShaderMaterial).shader.resource_path)
		if sp.ends_with("ground.gdshader"):
			return "earth"
		if sp.ends_with("p8_paddy_water.gdshader"):
			return "water"
	return "struct"


func _branch_meshes() -> Array:
	var zi := mr.get_node(ZI)
	var root_b: Node = zi.get_node("BranchesExp") if zi.has_node("BranchesExp") else (zi.get_node("BranchesOld") if zi.has_node("BranchesOld") else zi.get_node("Branches"))
	return root_b.find_children("*", "MeshInstance3D", true, false)


var _mag: StandardMaterial3D


## 数値用：通常画像に加え、earth／water／struct の各メッシュを不透明マゼンタ（unshaded）に差し替えた画像。
## 差し替えた構件の可視画素＝マゼンタ画素（時間で動く水面があっても厳密なマスクになる）。
func _shot_masks(name: String) -> void:
	if _mag == null:
		_mag = StandardMaterial3D.new()
		_mag.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mag.albedo_color = Color(1, 0, 1)
	await _shot(name)
	var meshes := _branch_meshes()
	for k in ["earth", "water", "struct"]:
		var keep := {}
		for mi: MeshInstance3D in meshes:
			if _kind(mi) == k:
				keep[mi] = mi.material_override
				mi.material_override = _mag
		await _shot("%s__m_%s" % [name, k])
		for mi: MeshInstance3D in keep:
			mi.material_override = keep[mi]


## old：W3B 以前の Branches を記憶體内で戻す
func _swap_old_branches() -> void:
	var zi := mr.get_node(ZI)
	var cur := zi.get_node("Branches") as Node3D
	var old_scene := ResourceLoader.load("res://.godot/w3b_backup/farmland_p8_before.scn", "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var inst := old_scene.instantiate()
	var ob := inst.get_node("ZoneWorks/ZoneIrrigation/Branches") as Node3D
	ob.get_parent().remove_child(ob)
	inst.free()
	ob.name = "BranchesOld"
	cur.visible = false
	zi.add_child(ob)
	print("[W3B] old: W3B 以前の Branches を戻した（メッシュ ", ob.find_children("*", "MeshInstance3D", true, false).size(), "）")


func _free_begin() -> void:
	_cam = Camera3D.new()
	_cam.far = 900.0
	_cam.fov = 55.0
	root.add_child(_cam)
	_cam.make_current()
	player.visible = false


func _free(name: String, pos: Vector3, target: Vector3, fov := 55.0, masks := false) -> void:
	_cam.fov = fov
	_cam.global_transform = Transform3D(Basis(), pos).looking_at(target, Vector3.UP if absf((target - pos).normalized().y) < 0.98 else Vector3(0, 0, -1))
	if masks:
		await _shot_masks(name)
	else:
		await _shot(name)


func _free_end() -> void:
	player.visible = true
	_cam.queue_free()
	await _frames(2)
	var pc := player.find_child("Camera3D", true, false) as Camera3D
	if pc:
		pc.make_current()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0]
	mode = args[1] if args.size() > 1 else "formal"
	var sets: PackedStringArray = (args[2] if args.size() > 2 else "all").split(",")
	DirAccess.make_dir_recursive_absolute(out)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	var sf := root.get_node_or_null("/root/StoryFlags")
	if sf:
		sf.set_flag("woke_in_trail", true)
		sf.set_flag("met_reimu", true)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(60)
	main.call("load_map", "village_v2", "")
	await _frames(90)
	player = main.get("player")
	mr = main.get("map_root")
	for nm in ["Debug", "Portals", "QuestAnchors"]:
		var nd := mr.get_node_or_null(nm) as Node3D
		if nd:
			nd.visible = false
	for cl in root.find_children("*", "CanvasLayer", true, false):
		(cl as CanvasLayer).visible = false
	var dn := root.get_node_or_null("/root/DayNight")
	if dn:
		dn.call("set_hour", 10.0)
		dn.set("flowing", false)
	var ov := mr.get_node_or_null(OVR)
	if ov != null:
		ov.set("enabled", mode == "sample")
		await _frames(4)
	print("[W3B] mode=%s overlay=%s" % [mode, "あり enabled=%s" % ov.get("enabled") if ov else "なし"])
	if mode == "exp":
		_swap_branches()
		await _frames(6)
	if mode == "old":
		_swap_old_branches()
		await _frames(6)
	if "scout" in sets or "all" in sets:
		await _free_begin()
		await _free("scout_T0_top", Vector3(333.0, 70.0, 42.0), Vector3(333.0, 0.0, 42.0), 60.0)
		await _free("scout_N0_top", Vector3(358.0, 60.0, -22.0), Vector3(358.0, 0.0, -22.0), 60.0)
		await _free_end()
	if "tps" in sets or "all" in sets:
		# T0 下流（W3 と同鏡位）
		await _tps("T0_down_tps", Vector2(336.5, 66.0), Vector2(327.0, 57.0), true)
		# T0 上流（伏越し手前の土渠）：東側から南西を見る
		await _tps("T0_up_tps", Vector2(340.5, 14.0), Vector2(336.0, 25.0), true)
		# N0（x=364 直線区間）：西側の畦から北を見る
		await _tps("N0_tps", Vector2(359.0, -26.0), Vector2(364.0, -16.0), true)
	var seam_filter := ""
	for st in sets:
		if st.begins_with("seam:"):
			seam_filter = st.substr(5)
	if "seam" in sets or seam_filter != "":
		var P: Dictionary = FLib.plan()
		var J: Array = []
		for br: Dictionary in P["zone"]["branches"]:
			var ri := 0
			for r: Dictionary in br["runs"]:
				var line: PackedVector2Array = r["line"]
				if r["kind"] == "siphon":
					for k in 2:
						var c: Vector2 = line[k]
						J.append({"n": "%s_r%d_siphon%d" % [br["id"], ri, k], "c": c, "d": (line[1] - line[0]).normalized() * (1.0 if k == 0 else 1.0)})
				else:
					for sp: Array in ZLib.branch_spans(r):
						for e in 2:
							var s: float = float(sp[1]) if e == 0 else float(sp[2])
							var at: Array = FLib.at_s(line, s)
							J.append({"n": "%s_r%d_%s_%s%d" % [br["id"], ri, sp[0], "s" if e == 0 else "e", int(s)], "c": at[0], "d": at[1]})
				ri += 1
		if seam_filter != "":
			J = J.filter(func(j: Dictionary) -> bool: return String(j["n"]).contains(seam_filter))
		print("[W3B] seam joints: %d" % J.size())
		await _free_begin()
		for j: Dictionary in J:
			var c: Vector2 = j["c"]
			var d: Vector2 = j["d"]
			var n := Vector2(-d.y, d.x)
			var gy := ZLib.ground_h(c)
			var tgt := Vector3(c.x, gy + 0.2, c.y)
			var p1 := c - d * 2.4 + n * 1.5
			var p2 := c + d * 2.2 - n * 1.2
			await _free("seam_%s_eye" % j["n"], Vector3(p1.x, ZLib.ground_h(p1) + 1.1, p1.y), tgt, 55.0)
			await _free("seam_%s_low" % j["n"], Vector3(p2.x, ZLib.ground_h(p2) + 0.45, p2.y), tgt, 55.0)
			await _free("seam_%s_top" % j["n"], Vector3(c.x, gy + 3.2, c.y), Vector3(c.x, gy, c.y), 38.0)
		await _free_end()
	if "glare" in sets:
		# 水面の白い高光：N0／T0 の代表点で 8 方位×2 高さ（0.5 m・1.5 m）から水面を見る。水面マスクの輝度分布を数値で比べる
		await _free_begin()
		var spots := {"T0_up": Vector2(336.0, 21.0), "T0_trough": Vector2(328.0, 63.6), "T0_down": Vector2(329.3, 71.0), "N0": Vector2(364.0, -16.0)}
		for key: String in spots:
			var c: Vector2 = spots[key]
			var gy := ZLib.ground_h(c)
			for ai in 8:
				var a := TAU * ai / 8.0
				for hh: float in [0.5, 1.5]:
					var pos := Vector3(c.x + cos(a) * 3.2, gy + hh, c.y + sin(a) * 3.2)
					pos.y = maxf(pos.y, ZLib.ground_h(Vector2(pos.x, pos.z)) + hh)
					await _free("glare_%s_a%d_h%d" % [key, ai, int(hh * 10)], pos, Vector3(c.x, gy + 0.35, c.y), 55.0, true)
		await _free_end()
	if "n0scan" in sets:
		var cands := [Vector2(358.0, -13.0), Vector2(358.0, -19.0), Vector2(355.5, -16.0), Vector2(370.0, -14.0), Vector2(372.0, -19.0), Vector2(368.5, -28.0), Vector2(364.0, -4.0), Vector2(357.0, -8.0),
			Vector2(366.0, -33.0), Vector2(362.0, -36.0), Vector2(359.0, -26.0), Vector2(369.5, -22.0)]
		for i in cands.size():
			var a: Vector2 = cands[i]
			await _tps("n0scan_%02d" % i, a, Vector2(364.0, -16.0 if i != 8 and i != 9 else -27.0))
	if "high" in sets or "all" in sets:
		await _free_begin()
		await _free("high_farm", Vector3(385.0, 46.0, 14.0), Vector3(346.0, 0.0, 20.0), 62.0, true)
		await _free_end()
	print("[DONE]")
	quit(0)

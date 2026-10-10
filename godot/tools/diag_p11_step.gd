extends SceneTree
const P11R2Swap := preload("res://tools/p11r2/p11r2_swap.gd")
## P11 R1 診斷（非 headless、場景・封存・玩家ファイルは不変）：玩家 step_height の比較。
## step_height はメモリ上だけ上書き（yoriichi_character.gd の @export、ファイル不変）。各 step 値で同じ短い実走を行い、
## 「構件への乗り上がり（足元の最初の当たりが構件で地形より 0.2 m 以上）」と「本来通れるべき段差（石段・踏石・橋端・門）で止まらないか」を量る。
##   godot --path godot --script res://tools/diag_p11_step.gd -- --review=kirisame [--steps=0.6,0.45,0.4] [--out=<json>]

const CASES := [
	# [名前, 種別, start, goal]  種別 prop＝構件の乗り上がり帯（止まる・回り込むのが正しい）／pass＝通れるべき
	["kit_B_P_MKT_003", "prop", "kit", "B_P_MKT_003"],
	["kit_B_P_MKT_008", "prop", "kit", "B_P_MKT_008"],
	["walk_x2_MKT_003", "prop", Vector2(244.0, 34.1), Vector2(248.0, 35.5)],
	["walk_s3_endai", "prop", Vector2(232.9, -47.2), Vector2(228.4, -45.4)],
	["mw_endai_062", "prop", Vector2(233.6, -46.3), Vector2(228.0, -45.9)],
	["hu_stool_048", "prop", Vector2(328.3, -39.4), Vector2(328.3, -44.6)],
	["sando_steps_up", "pass", Vector2(290.0, -166.0), Vector2(280.5, -189.0)],
	["sando_steps_down", "pass", Vector2(280.5, -189.0), Vector2(290.0, -166.0)],
	["terakoya_stepstone", "pass", Vector2(201.0, 24.1), Vector2(196.4, 24.0)],
	["hieda_gate", "pass", Vector2(398.0, -3.5), Vector2(398.0, -15.0)],
	["bridge02_end", "pass", Vector2(372.0, -183.0), Vector2(378.0, -212.0)],
	["bridge05", "pass", Vector2(176.5, -14.5), Vector2(161.0, -12.0)],
	["farm_bund_N2", "pass", Vector2(372.0, 22.0), Vector2(392.0, 22.0)],
	["riverbank_stair_dragon", "pass", Vector2(392.0, -200.0), Vector2(388.0, -214.0)],
	# P11 R2：P8 ZONE の支渠跨渠板 S2（候補 A の初版で止まった所）
	["plank_S2", "pass", Vector2(474.4, 19.3), Vector2(468.0, 19.2)],
	# P11 R2：縁沿いの横移動（R1 の walk_step035 で 0.35 でも乗り上がった経路の再現）＝膠囊が箱の長辺に 0.12 m 食い込む線を端から端まで
	["graze_046_bench_L", "prop", "graze", "046_sk_bench_c", -1.0],
	["graze_046_bench_R", "prop", "graze", "046_sk_bench_c", 1.0],
	["graze_046_bench_L_deep", "prop", "graze", "046_sk_bench_c", -1.0, 0.25],
	["graze_046_bench_R_deep", "prop", "graze", "046_sk_bench_c", 1.0, 0.25],
	["graze_062_endai_L", "prop", "graze", "062_ms_endai_mousen_c39", -1.0],
	["graze_062_endai_R", "prop", "graze", "062_ms_endai_mousen_c39", 1.0],
	["graze_062_endai_L_deep", "prop", "graze", "062_ms_endai_mousen_c39", -1.0, 0.25],
	["graze_007_bench_L", "prop", "graze", "007_sk_bench_c", -1.0],
	["graze_007_bench_R", "prop", "graze", "007_sk_bench_c", 1.0],
	["graze_048_stool_L", "prop", "graze", "048_sz_stool_c", -1.0],
	# P11 R2：跳躍は従来どおり使える（長凳・縁台に跳び乗れる＝jump は lifted_on が出るのが正しい）
	["jump_046_bench", "jump", Vector2(244.0, 34.1), Vector2(246.87, 35.58), 1.3],
	["jump_062_endai", "jump", Vector2(232.9, -47.2), Vector2(230.6, -46.31), 1.7],
]
const PROP_PREFIX := ["Props/", "HumanUseP10", "HumanUseExpansionP10", "Vegetation/", "WaterLifeP10", "PropFixP10"]

var main: Node
var player: CharacterBody3D
var adapter: Node
var vil: Node3D
var trid := RID()
var under_at_max := ""


func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	var steps := [0.6, 0.45, 0.4]
	var out := ""
	var only := ""
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=")
		if a.begins_with("--steps="):
			steps = Array(a.trim_prefix("--steps=").split(",")).map(func(x): return float(x))
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	# P11 R2：--candidate=A|B|C（候補スクリプトをメモリ上で差し替え、ファイル不変；tools/p11r2/p11r2_swap.gd）
	var _cand := P11R2Swap.parse(OS.get_cmdline_user_args())
	if _cand != "":
		print("[P11R2] candidate ", P11R2Swap.apply(main, _cand))
	root.add_child(main)
	current_scene = main
	var t0 := Time.get_ticks_msec()
	while true:
		await physics_frame
		player = main.get("player")
		vil = main.get("map_root") as Node3D
		if player and vil and String(main.get("current_id")) == "village_v2" and player.is_on_floor():
			break
		if Time.get_ticks_msec() - t0 > 120000:
			quit(2)
			return
	for i in 30:
		await physics_frame
	adapter = player.get_node("CameraAdapter")
	adapter.set_process_unhandled_input(false)
	player.set_process_unhandled_input(false)
	for cl in root.find_children("*", "CanvasLayer", true, false):
		(cl as CanvasLayer).visible = false
	trid = (vil.get_node("Collision/TerrainCollision") as CollisionObject3D).get_rid()
	# --ground-boxes：診斷用（メモリ上だけ）乗り上がり帯の構件 BoxShape3D の下面を地形まで下げる（上面は不変）。
	#   仮説「箱の下に 0.03–0.10 m の隙間があると、膠囊の下の球が箱の下縁を床として押し上げられる」の検証。
	if "--ground-boxes" in OS.get_cmdline_user_args():
		var nb := 0
		for co in vil.find_children("*", "StaticBody3D", true, false):
			var path := String(vil.get_path_to(co))
			var ok := false
			for pre: String in PROP_PREFIX:
				if path.begins_with(pre):
					ok = true
			if not ok:
				continue
			for cs in co.get_children():
				if not (cs is CollisionShape3D) or not ((cs as CollisionShape3D).shape is BoxShape3D):
					continue
				var c3 := cs as CollisionShape3D
				var bx := (c3.shape as BoxShape3D).duplicate() as BoxShape3D
				var xf := c3.global_transform
				var top := xf.origin.y + bx.size.y * 0.5
				var bot := xf.origin.y - bx.size.y * 0.5
				var ty := _terrain_y(xf.origin.x, xf.origin.z)
				if is_nan(ty) or top - ty > 0.6 or top - ty < 0.25 or bot - ty <= 0.005:
					continue
				bx.size.y = top - ty
				c3.shape = bx
				c3.global_position = Vector3(xf.origin.x, ty + bx.size.y * 0.5, xf.origin.z)
				nb += 1
		print("[STEP] --ground-boxes：下面を地形へ下げた箱 %d" % nb)
		for i in 3:
			await physics_frame
	var R := {"default_step_height": player.get("step_height"), "runs": []}
	for st: float in steps:
		player.set("step_height", st)
		for c: Array in CASES:
			if only != "" and not String(c[0]).contains(only):
				continue
			var r := await _case(c)
			r["step_height"] = st
			R["runs"].append(r)
			print("[STEP] step %.2f %-24s %s 到達=%s 終点→目標 %.2f m 地形上最大 %.2f m 構件へ乗った %s 終了時 地形上 %s 足元 %s ｜最高時の足元 %s" % [st, c[0], c[1], r.get("arrived"), r.get("end_dist", -1.0), r.get("max_above_terrain", -1.0), str(r.get("lifted_on")), str(r.get("final_above_terrain")), r.get("final_on", ""), r.get("under_at_max", "")])
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		f.store_string(JSON.stringify(R, "\t") + "\n")
		f.close()
	quit(0)


func _top_above_terrain(p: Vector3) -> float:
	var ty := _terrain_y(p.x, p.z)
	if is_nan(ty):
		return 0.0
	var rq := PhysicsRayQueryParameters3D.create(Vector3(p.x, ty + 6.0, p.z), Vector3(p.x, ty - 1.0, p.z), player.collision_mask)
	rq.exclude = [player.get_rid()]
	var r := player.get_world_3d().direct_space_state.intersect_ray(rq)
	return float((r["position"] as Vector3).y) - ty if not r.is_empty() else 0.0


func _find_shape(nm: String) -> CollisionShape3D:
	for cs in vil.find_children("*", "CollisionShape3D", true, false):
		var n := String(cs.name)
		if (n == nm or (nm.length() <= 4 and n.begins_with(nm + "_"))) and (cs as CollisionShape3D).shape is BoxShape3D:
			return cs as CollisionShape3D
	return null


func _terrain_y(x: float, z: float) -> float:
	var sp := player.get_world_3d().direct_space_state
	var ex: Array[RID] = [player.get_rid()]
	for i in 16:
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, 80.0, z), Vector3(x, -40.0, z))
		q.exclude = ex
		var h := sp.intersect_ray(q)
		if h.is_empty():
			return NAN
		if h["rid"] == trid:
			return float((h["position"] as Vector3).y)
		ex.append(h["rid"])
	return NAN


func _place(q: Vector2, yaw: float) -> void:
	var sp := player.get_world_3d().direct_space_state
	var ty := _terrain_y(q.x, q.y)
	var rq := PhysicsRayQueryParameters3D.create(Vector3(q.x, ty + 6.0, q.y), Vector3(q.x, -40.0, q.y), player.collision_mask)
	rq.exclude = [player.get_rid()]
	var r := sp.intersect_ray(rq)
	player.velocity = Vector3.ZERO
	player.global_position = Vector3(q.x, (float((r["position"] as Vector3).y) if not r.is_empty() else ty) + 0.1, q.y)
	adapter.set("_target_yaw", yaw)
	adapter.set("_current_yaw", yaw)
	for i in 20:
		await physics_frame


func _case(c: Array) -> Dictionary:
	var a: Vector2
	var b: Vector2
	var jump_at := -1.0
	if c[1] == "jump":
		jump_at = float(c[4])
	if c[2] is String and String(c[2]) == "graze":
		var cs := _find_shape(String(c[3]))
		if cs == null:
			return {"case": c[0], "kind": c[1], "error": "shape not found"}
		var bx := cs.shape as BoxShape3D
		var gx := cs.global_transform
		var ax := gx.basis.x.normalized()
		var az := gx.basis.z.normalized()
		var sx := bx.size.x * absf(gx.basis.x.length())
		var sz := bx.size.z * absf(gx.basis.z.length())
		var lng := ax if sx >= sz else az
		var sht := az if sx >= sz else ax
		var hl := maxf(sx, sz) * 0.5
		var hs := minf(sx, sz) * 0.5
		var ovl := float(c[5]) if c.size() > 5 else 0.12
		var o := gx.origin + sht * float(c[4]) * (hs + 0.3 - ovl)
		# 始点・終点が他の構件の上（屋台の屋根など）にならないよう、延長を 2.0 → 0.4 m まで縮める
		var ext_a := 2.0
		while ext_a > 0.4 and _top_above_terrain(o - lng * (hl + ext_a)) > 0.6:
			ext_a -= 0.2
		var ext_b := 2.0
		while ext_b > 0.4 and _top_above_terrain(o + lng * (hl + ext_b)) > 0.6:
			ext_b -= 0.2
		var a3 := o - lng * (hl + ext_a)
		var b3 := o + lng * (hl + ext_b)
		a = Vector2(a3.x, a3.z)
		b = Vector2(b3.x, b3.z)
	elif c[2] is String and String(c[2]) == "kit":
		var bp := vil.find_child(String(c[3]), true, false) as Node3D
		var xf := bp.global_transform
		var d := float(bp.get_meta("depth_m", 10.0))
		var s := xf * Vector3(0.9, 0, d * 0.5 + 3.0)
		var g := xf * Vector3(0.9, 0, 0)
		a = Vector2(s.x, s.z)
		b = Vector2(g.x, g.z)
	else:
		a = c[2]
		b = c[3]
	var dir := (b - a).normalized()
	await _place(a, atan2(-dir.x, -dir.y))
	var maxab := 0.0
	under_at_max = ""
	var lifted := []
	var t0 := Time.get_ticks_msec()
	var arrived := false
	var hist: Array = []
	var f := 0
	while Time.get_ticks_msec() - t0 < 9000:
		var p := Vector2(player.global_position.x, player.global_position.z)
		if p.distance_to(b) < 0.6:
			arrived = true
			break
		var dd := b - p
		adapter.set("_target_yaw", atan2(-dd.x, -dd.y))
		Input.action_press("move_forward")
		if "--trace" in OS.get_cmdline_user_args() and f % 3 == 0:
			var tp := player.global_position
			var tq := PhysicsRayQueryParameters3D.create(tp + Vector3(0, 0.2, 0), tp + Vector3(0, -0.8, 0), player.collision_mask)
			tq.exclude = [player.get_rid()]
			var th := player.get_world_3d().direct_space_state.intersect_ray(tq)
			print("[TRACE] f%d pos %s floor %s v %.2f dbg %s under %s gap %s ang %s" % [f, str(tp), player.is_on_floor(), Vector2(player.velocity.x, player.velocity.z).length(), str(player.get("step_dbg")),
				String((th["collider"] as Node).name) if not th.is_empty() else "-", str(snappedf(tp.y - (th["position"] as Vector3).y, 0.001)) if not th.is_empty() else "-",
				str(snappedf(rad_to_deg((th["normal"] as Vector3).angle_to(Vector3.UP)), 0.1)) if not th.is_empty() else "-"])
		if jump_at > 0.0 and p.distance_to(b) < jump_at and player.is_on_floor():
			player.call("request_jump")
			jump_at = -1.0
		await physics_frame
		f += 1
		if f % 6 == 0:
			var pp := player.global_position
			var ty := _terrain_y(pp.x, pp.z)
			if not is_nan(ty) and pp.y - ty > maxab:
				maxab = pp.y - ty
				var sp0 := player.get_world_3d().direct_space_state
				var q0 := PhysicsRayQueryParameters3D.create(pp + Vector3(0, 0.25, 0), pp + Vector3(0, -0.8, 0), player.collision_mask)
				q0.exclude = [player.get_rid()]
				var h0 := sp0.intersect_ray(q0)
				if not h0.is_empty():
					var co0 := h0["collider"] as CollisionObject3D
					under_at_max = "%s/%s y %.2f" % [String(vil.get_path_to(co0)), String(co0.shape_owner_get_owner(co0.shape_find_owner(int(h0["shape"]))).name), (h0["position"] as Vector3).y]
			if player.is_on_floor():
				var sp := player.get_world_3d().direct_space_state
				var q := PhysicsRayQueryParameters3D.create(pp + Vector3(0, 0.25, 0), pp + Vector3(0, -0.6, 0), player.collision_mask)
				q.exclude = [player.get_rid()]
				var h := sp.intersect_ray(q)
				if not h.is_empty() and h["collider"] is Node and not is_nan(ty) and pp.y - ty > 0.2:
					var path := String(vil.get_path_to(h["collider"] as Node))
					for pre: String in PROP_PREFIX:
						if path.begins_with(pre):
							var co := h["collider"] as CollisionObject3D
							var nm := String(co.shape_owner_get_owner(co.shape_find_owner(int(h["shape"]))).name)
							if not (nm in lifted):
								lifted.append(nm)
		hist.append(p)
		if hist.size() > 120:
			hist.pop_front()
			if (hist[-1] as Vector2).distance_to(hist[0]) < 0.15:
				break
	Input.action_release("move_forward")
	# 静止まで（空中なら着地するまで、最大 3 s）
	for i in 180:
		await physics_frame
		if i > 20 and player.is_on_floor():
			break
	for i in 10:
		await physics_frame
	var e := Vector2(player.global_position.x, player.global_position.z)
	# 終了時（静止後）の足元：構件の上に立っているか
	var fp := player.global_position
	var fty := _terrain_y(fp.x, fp.z)
	var final_on := ""
	var spf := player.get_world_3d().direct_space_state
	var qf := PhysicsRayQueryParameters3D.create(fp + Vector3(0, 0.25, 0), fp + Vector3(0, -0.8, 0), player.collision_mask)
	qf.exclude = [player.get_rid()]
	var hf := spf.intersect_ray(qf)
	if not hf.is_empty() and (hf["collider"] as Node) != null:
		final_on = String(vil.get_path_to(hf["collider"] as Node))
	return {"case": c[0], "kind": c[1], "start": [a.x, a.y], "goal": [b.x, b.y], "arrived": arrived, "end": [snappedf(e.x, 0.01), snappedf(e.y, 0.01)],
		"end_dist": snappedf(e.distance_to(b), 0.01), "max_above_terrain": snappedf(maxab, 0.01), "lifted_on": lifted, "under_at_max": under_at_max,
		"final_above_terrain": snappedf(fp.y - fty, 0.01) if not is_nan(fty) else null, "final_on": final_on}

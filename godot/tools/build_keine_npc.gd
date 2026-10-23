extends SceneTree
## 慧音（characters/keine）放進人間之里：霧雨店前主街一段往復（patrol）。
##   godot --headless --path . --script res://tools/build_keine_npc.gd
## 輸出 maps/village_v2/keine_npc.tscn（village_v2 的 Population/KeineNPC 實例化它）。
## 走法＝scripts/npc_population_actor.gd（同其他 NPC）；歩速＝walk clip 的足接地速度（同 village_v2_population_lib.walk_speed 量法）；
## path_y＝0.25 m 毎の射線高度（同 generator 規格）。最後回讀檢查：0.25 m 毎の膠囊淨空、段差 ≤ 0.10 m。

## 其他角色（魔理莎等）同一支：godot --headless --path . --script res://tools/build_keine_npc.gd -- --npc=res://characters/marisa/marisa.tscn
##   --out=res://maps/village_v2/marisa_npc.tscn --name=MarisaNPC --actor=M1_marisa --model=marisa --zone=main_street --path=237.4,61,237.4,56
##   [--height=1.65] [--seed=130015] [--wait=6,12] [--art="…"]；沒給的參數＝慧音的原值。
var KEINE := "res://characters/keine/keine.tscn"
var ACTOR := "res://scripts/npc_population_actor.gd"
var OUT := "res://maps/village_v2/keine_npc.tscn"
var PATH := [Vector2(235.5, 70.0), Vector2(235.5, 62.0)]
var HEIGHT := 1.70
var RADIUS := 0.22
var TOP_NAME := "KeineNPC"
var ACTOR_NAME := "K1_keine"
var MODEL := "keine"
var ZONE := "main_street"
var SEED_I := 170018
var WAIT_MIN := 8.0
var WAIT_MAX := 16.0
var ART := "Keine NPC r1 ART_REVIEW（2026-10-18）"


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--npc="): KEINE = a.substr(6)
		elif a.begins_with("--out="): OUT = a.substr(6)
		elif a.begins_with("--name="): TOP_NAME = a.substr(7)
		elif a.begins_with("--actor="): ACTOR_NAME = a.substr(8)
		elif a.begins_with("--model="): MODEL = a.substr(8)
		elif a.begins_with("--zone="): ZONE = a.substr(7)
		elif a.begins_with("--height="): HEIGHT = float(a.substr(9))
		elif a.begins_with("--seed="): SEED_I = int(a.substr(7))
		elif a.begins_with("--art="): ART = a.substr(6)
		elif a.begins_with("--wait="):
			var w := a.substr(7).split(",")
			WAIT_MIN = float(w[0]); WAIT_MAX = float(w[1])
		elif a.begins_with("--path="):          # x1,z1,x2,z2[,x3,z3…]：折線也可（actor 以 0.25 m 弧長取 path_y）
			var q := a.substr(7).split(",")
			PATH = []
			for qi in range(0, q.size() - 1, 2):
				PATH.append(Vector2(float(q[qi]), float(q[qi + 1])))
		elif a.begins_with("--actor-script="): ACTOR = a.substr(15)
		elif a.begins_with("--radius="): RADIUS = float(a.substr(9))
	var v: Node3D = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	# 既有的自己也有碰撞膠囊：量路線前拿掉，否則射線打到她頭頂
	var old := v.get_node_or_null("Population/" + TOP_NAME)
	if old != null:
		old.get_parent().remove_child(old)
		old.free()
	root.add_child(v)
	for i in 4:
		await physics_frame
	var ss := v.get_world_3d().direct_space_state
	# 阿求的袖子地板（WorldBoundary，圖層 20，y=1.692）會把全圖的射線擋在 1.692：量地面／淨空時排除圖層 20
	var mask := 0xFFFFFFFF & ~(1 << 19)
	# 1 歩速
	var spd: Dictionary = _walk_speed(v)
	print("[KEINE] walk foot speed L %.3f R %.3f → %.3f m/s (clip %.2fs)" % [spd.left, spd.right, spd.speed, spd.len])
	# 2 path_y
	var a: Vector2 = PATH[0]
	var b: Vector2 = PATH[1]
	var L := 0.0
	for pi in range(1, PATH.size()):
		L += PATH[pi].distance_to(PATH[pi - 1])
	var ys := PackedFloat32Array()
	var j := 0
	while j * 0.25 <= L + 1e-4:
		var p := _poly(minf(j * 0.25, L))
		var rq := PhysicsRayQueryParameters3D.create(Vector3(p.x, 40, p.y), Vector3(p.x, -20, p.y))
		rq.collision_mask = mask
		var h := ss.intersect_ray(rq)
		ys.append(float(h.position.y) if not h.is_empty() else NAN)
		j += 1
	# 3 場景
	var top := Node3D.new()
	top.name = TOP_NAME
	top.set_meta("art_revision", ART)
	var act := AnimatableBody3D.new()
	act.name = ACTOR_NAME
	act.set_script(load(ACTOR))
	var dir := (b - a).normalized()
	act.transform = Transform3D(Basis(Vector3.UP, atan2(dir.x, dir.y)), Vector3(a.x, ys[0], a.y))
	act.sync_to_physics = false
	act.set("mode", "patrol")
	act.set("path_xz", PackedVector2Array(PATH))
	act.set("path_y", ys)
	act.set("walk_speed", snappedf(spd.speed, 0.001))
	act.set("wait_min", WAIT_MIN)
	act.set("wait_max", WAIT_MAX)
	act.set("seed_i", SEED_I)
	act.set_meta("model", MODEL)
	act.set_meta("zone", ZONE)
	top.add_child(act)
	act.owner = top
	var col := CollisionShape3D.new()
	col.name = "Body"
	var cap := CapsuleShape3D.new()
	cap.radius = RADIUS
	cap.height = HEIGHT - 0.1
	col.shape = cap
	col.position = Vector3(0, (HEIGHT - 0.1) * 0.5, 0)
	act.add_child(col)
	col.owner = top
	var npc: Node = (load(KEINE) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	npc.name = "NPC"
	act.add_child(npc)
	npc.owner = top
	var ps := PackedScene.new()
	var err := ps.pack(top)
	err = max(err, ResourceSaver.save(ps, OUT))
	print("[KEINE] saved %s err %d len %.2f m pts %d y %.3f..%.3f" % [OUT, err, L, ys.size(), _min(ys), _max(ys)])
	# 4 回讀檢查
	var fails := 0
	var step := 0.0
	var blocked := []
	var capq := CapsuleShape3D.new()
	capq.radius = RADIUS
	capq.height = HEIGHT - 0.1
	for k in ys.size():
		if is_nan(ys[k]):
			fails += 1
			continue
		if k > 0:
			step = maxf(step, absf(ys[k] - ys[k - 1]))
		var p := _poly(minf(k * 0.25, L))
		var sq := PhysicsShapeQueryParameters3D.new()
		sq.shape = capq
		sq.collision_mask = mask
		sq.transform = Transform3D(Basis(), Vector3(p.x, ys[k] + (HEIGHT - 0.1) * 0.5 + 0.06, p.y))
		if ss.intersect_shape(sq, 4).size() > 0:
			blocked.append("%.2f m" % (k * 0.25))
	# 5 與其他 NPC 路線的最近距離（< 2.0 m 者列出）
	var near := []
	for o in v.find_children("*", "AnimatableBody3D", true, false):
		if o.name == ACTOR_NAME or not o.get_script() or o.get("path_xz") == null:
			continue
		var pxz: PackedVector2Array = o.get("path_xz")
		var best := INF
		for k in range(0, ys.size(), 2):
			var mp := _poly(minf(k * 0.25, L))
			if pxz.size() >= 2:
				for si in range(1, pxz.size()):
					var cp := Geometry2D.get_closest_point_to_segment(mp, pxz[si - 1], pxz[si])
					best = minf(best, mp.distance_to(cp))
			else:
				var gp: Vector3 = (o as Node3D).global_position
				best = minf(best, mp.distance_to(Vector2(gp.x, gp.z)))
		if best < 2.0:
			near.append("%s %.2f m" % [o.get_path().get_concatenated_names().substr(0, 60), best])
	print("[KEINE] 其他 NPC 路線最近距離 < 2.0 m: ", near)
	var ok: bool = fails == 0 and blocked.is_empty() and step <= 0.10 and err == OK and spd.speed > 0.6
	print("[KEINE] %s ray-miss %d blocked %s max step %.3f m speed %.3f" % ["PASS" if ok else "FAIL", fails, str(blocked), step, spd.speed])
	quit(0 if ok else 1)


func _poly(u: float) -> Vector2:
	var acc := 0.0
	for i in range(1, PATH.size()):
		var seg: float = PATH[i].distance_to(PATH[i - 1])
		if u <= acc + seg or i == PATH.size() - 1:
			return PATH[i - 1].lerp(PATH[i], clampf((u - acc) / maxf(seg, 1e-6), 0.0, 1.0))
		acc += seg
	return PATH[PATH.size() - 1]


func _walk_speed(v: Node3D) -> Dictionary:
	var npc: Node3D = (load(KEINE) as PackedScene).instantiate()
	npc.set("frozen", true)
	npc.set("animation", &"walk")
	npc.set("start_time", 0.0)
	v.add_child(npc)
	var ap := npc.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var sk := npc.find_child("GeneralSkeleton", true, false) as Skeleton3D
	var L := ap.current_animation_length
	var meds := []
	for bn in ["LeftFoot", "RightFoot"]:
		var bi := sk.find_bone(bn)
		var ys := []
		var zs := []
		var N := 120
		for k in N:
			ap.seek(L * k / N, true)
			var p := sk.global_transform * sk.get_bone_global_pose(bi).origin
			ys.append(p.y)
			zs.append(p.z)
		var ymin: float = ys.min()
		var sp := []
		for k in N:
			var k2 := (k + 1) % N
			if ys[k] < ymin + 0.02 and ys[k2] < ymin + 0.02:
				sp.append(-(zs[k2] - zs[k]) / (L / N))
		sp.sort()
		meds.append(float(sp[sp.size() / 2]) if sp.size() > 0 else 0.0)
	v.remove_child(npc)
	npc.free()
	return {"speed": 0.5 * (float(meds[0]) + float(meds[1])), "left": meds[0], "right": meds[1], "len": L}


func _min(a: PackedFloat32Array) -> float:
	var m := INF
	for x in a:
		m = minf(m, x)
	return m


func _max(a: PackedFloat32Array) -> float:
	var m := -INF
	for x in a:
		m = maxf(m, x)
	return m

extends Node3D
## 小鈴雙袖 SoftBody3D（Jolt Physics）元件。掛在 kosuzu.tscn 的 Model 旁邊。
## - 袖子是 SoftBody3D（世界空間），上緣跟上臂、肩縫跟肩膀（kosuzu_sleeve_*.glb 頂點色 R＝上臂、B＝肩）。
## - 碰撞代理（只給袖子用的圖層）：袴每 3 cm 一層凸包（跟 Hips/Spine/Spine1）＋大腿、上臂、前臂、手膠囊。
## - 會接手 AnimationPlayer 的推進（MANUAL，於本節點的物理步內先推進動作、再更新代理），讓代理與釘點和同一格的骨架一致。
## - 生成時先以 T-pose 靜置 settle_time，再於 blend_in_time 內漸入動作（袖網格是 T-pose 建的，直接跳進 idle 會甩飛）。
## 已知限制（實測 2026-10-19）：SoftBody 無自碰撞，袖袋前後片會互穿（約 40–50% 三角形），pressure 會讓袖子吹成氣球，勿用。
## 共用：阿求（akyuu.tscn）也用這支，data_prefix 指到 res://characters/akyuu/akyuu；頂點色 G＝前臂（小鈴的袖子 G 全 0，不受影響）。
## 骨名先找 mixamorig 原名，找不到再找 retarget 後的 GeneralSkeleton 名（阿求走 Godot retarget）。

const HUMANOID := {"UpLeg": "UpperLeg", "Leg": "LowerLeg", "Arm": "UpperArm", "ForeArm": "LowerArm",
	"Spine1": "Chest", "Spine2": "UpperChest", "HandMiddle2": "MiddleIntermediate"}

## 資料前綴：<prefix>_colliders.json、<prefix>_sleeve_L.glb／_R.glb
@export var data_prefix := "res://characters/kosuzu/kosuzu"
@export var stiffness := 0.8
@export_range(5, 30) var precision := 10
@export var mass := 0.2
@export var damping := 0.05
@export var settle_time := 0.5
@export var blend_in_time := 1.5
## 袖子碰撞代理專用的物理圖層（1–32）。袖子只碰這一層，不碰地形、玩家、其他 NPC。
@export_range(1, 32) var proxy_layer := 20
## 地板碰撞（角色腳底高度的無限平面，跟著角色根節點）：正座、跪姿時袖子垂到地上不會穿地。小鈴預設關。
@export var floor_collision := false
@export var model_path := NodePath("../Model")

var skel: Skeleton3D
var player: AnimationPlayer
var _sim: Node3D
var _bodies := []          # [AnimatableBody3D, bone]
var _caps := []            # [AnimatableBody3D, bone_a, bone_b]
var _att := {}             # 名稱 -> [Node3D, bone]
var _floor: AnimatableBody3D
var _blend := {}           # 混合釘點："side:r,g,b" -> [Node3D, [[bone, w, rest_inv], ...]]
var _sleeves := {}         # "L"/"R" -> SoftBody3D
var _rest := {}
var _t := 0.0
var _built := false


func _ready() -> void:
	var model := get_node_or_null(model_path)
	if model == null:
		push_error("KosuzuSleeves：找不到 Model"); return
	skel = model.find_children("*", "Skeleton3D", true, false)[0]
	process_physics_priority = -1000
	_build.call_deferred()


## AnimationPlayer：小鈴的在 glb 裡；阿求的由 npc_visual 在父節點 _ready 建立（比本節點晚），所以延到 _build 才找。
func _find_player() -> void:
	if player == null:
		var ps := get_node(model_path).find_children("*", "AnimationPlayer", true, false)
		if ps.is_empty():
			push_error("KosuzuSleeves：找不到 AnimationPlayer"); return
		player = ps[0]
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL


func _bone(n: String) -> int:
	for c in [n, n.replace(":", "_"), n.split(":")[-1]]:
		var i := skel.find_bone(c)
		if i >= 0: return i
	var b: String = n.split(":")[-1]
	for side in ["Left", "Right"]:
		if b.begins_with(side) and HUMANOID.has(b.trim_prefix(side)):
			b = side + HUMANOID[b.trim_prefix(side)]
	if HUMANOID.has(b): b = HUMANOID[b]
	var j := skel.find_bone(b)
	if j >= 0: return j
	push_error("KosuzuSleeves：找不到骨頭 " + n); return -1


func _bw(i: int) -> Transform3D:
	var g := skel.global_transform * skel.get_bone_global_pose(i)
	return Transform3D(g.basis.orthonormalized(), g.origin)


func _build() -> void:
	_find_player()
	for i in skel.get_bone_count(): _rest[i] = skel.get_bone_rest(i)
	skel.reset_bone_poses()
	var M := skel.global_transform                       # glb 空間 → 世界
	var sc := M.basis.get_scale().x
	_sim = Node3D.new(); _sim.name = "SleeveSim"; _sim.top_level = true; add_child(_sim)
	_sim.global_transform = Transform3D.IDENTITY
	var bit := 1 << (proxy_layer - 1)
	var cj = JSON.parse_string(FileAccess.get_file_as_string(data_prefix + "_colliders.json"))
	for sd in cj.slabs:
		var bi := _bone(sd.bone); var inv := _bw(bi).affine_inverse()
		var pv := PackedVector3Array()
		for q in sd.pts_blender: pv.append(inv * (M * Vector3(q[0], q[2], -q[1])))
		var sh := ConvexPolygonShape3D.new(); sh.points = pv
		_bodies.append([_body("Slab%.2f" % sd.z, sh, bit), bi])
	for c in cj.capsules:
		var sh := CapsuleShape3D.new(); sh.radius = float(c.r) * sc; sh.height = 0.1
		_caps.append([_body("Cap_" + str(c.name), sh, bit), _bone(c.a), _bone(c.b)])
	for n in ["LeftArm", "RightArm", "LeftShoulder", "RightShoulder", "LeftForeArm", "RightForeArm"]:
		var nd := Node3D.new(); nd.name = "Att_" + n; _sim.add_child(nd); _att[n] = [nd, _bone("mixamorig:" + n)]
	if floor_collision:
		var wb := WorldBoundaryShape3D.new()
		_floor = _body("Floor", wb, bit)
	_update_proxies()
	for side in ["L", "R"]:
		var src: Node = (load(data_prefix + "_sleeve_%s.glb" % side) as PackedScene).instantiate()
		var mi: MeshInstance3D = src.find_children("*", "MeshInstance3D", true, false)[0]
		var arr := mi.mesh.surface_get_arrays(0)
		var V: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		for i in V.size(): V[i] = M * V[i]
		arr[Mesh.ARRAY_VERTEX] = V
		var N = arr[Mesh.ARRAY_NORMAL]
		if N is PackedVector3Array:
			var nb := M.basis.orthonormalized()
			for i in N.size(): N[i] = nb * N[i]
			arr[Mesh.ARRAY_NORMAL] = N
		var am := ArrayMesh.new(); am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var mat := mi.mesh.surface_get_material(0)
		if mat:
			var m2: Material = mat.duplicate()
			if m2 is BaseMaterial3D: (m2 as BaseMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
			am.surface_set_material(0, m2)
		src.free()
		var sb := SoftBody3D.new(); sb.name = "Sleeve" + side; sb.mesh = am
		sb.simulation_precision = precision; sb.total_mass = mass; sb.linear_stiffness = stiffness
		sb.damping_coefficient = damping; sb.collision_layer = 0; sb.collision_mask = bit
		_sim.add_child(sb)
		var C: PackedColorArray = arr[Mesh.ARRAY_COLOR]
		var sn := "Left" if side == "L" else "Right"
		var buckets := {}          # 混合釘點：key -> [顏色, 頂點索引...]
		for i in V.size():
			var a := ""
			var c := C[i]
			if c.r + c.g + c.b < 0.5: continue
			if c.r > 0.99: a = sn + "Arm"
			elif c.g > 0.99: a = sn + "ForeArm"
			elif c.b > 0.99: a = sn + "Shoulder"
			elif c.r > 0.5 and c.g < 0.01 and c.b < 0.01: a = sn + "Arm"   # 小鈴：二值色
			if a != "":
				sb.set_point_pinned(i, true, sb.get_path_to(_att[a][0]))
			else:
				var key := "%s:%.1f,%.1f,%.1f" % [sn, snappedf(c.r, 0.1), snappedf(c.g, 0.1), snappedf(c.b, 0.1)]
				if not buckets.has(key): buckets[key] = [c]
				buckets[key].append(i)
		for key in buckets:
			var b: Array = buckets[key]
			var pivot := Vector3.ZERO
			for k in range(1, b.size()): pivot += V[b[k]]
			pivot /= float(b.size() - 1)
			var nd := _blend_node(sn, b[0], key, pivot)
			for k in range(1, b.size()): sb.set_point_pinned(b[k], true, sb.get_path_to(nd))
		_sleeves[side] = sb
	_built = true


## 混合釘點（阿求）：頂點色＝蒙皮權重（R 上臂、G 前臂、B 肩），量化到 0.1 共用一個節點，每格依權重混合骨頭變換。
## 節點原點放在該組頂點的靜止重心（pivot）：旋轉混合的誤差與「點到節點原點的距離」成正比，放在世界原點會差到數十公分。
func _blend_node(sn: String, c: Color, key: String, pivot: Vector3) -> Node3D:
	var w := Vector3(snappedf(c.r, 0.1), snappedf(c.g, 0.1), snappedf(c.b, 0.1))
	if not _blend.has(key):
		var nd := Node3D.new(); nd.name = "Blend_" + key.replace(":", "_").replace(",", "_").replace(".", "")
		_sim.add_child(nd)
		var parts := []
		var s := w.x + w.y + w.z
		for pr in [[sn + "Arm", w.x], [sn + "ForeArm", w.y], [sn + "Shoulder", w.z]]:
			if pr[1] > 0.0:
				var bi: int = _att[pr[0]][1]
				parts.append([bi, pr[1] / s, _bw(bi).affine_inverse()])
		_blend[key] = [nd, parts, pivot]
		nd.global_transform = _blend_xf(parts, pivot)
	return _blend[key][0]


## 各骨「目前／靜止」變換的旋轉 nlerp；原點＝pivot 經各骨變換後的加權位置（避免線性混合矩陣的塌縮）。
func _blend_xf(parts: Array, pivot: Vector3) -> Transform3D:
	var q := Quaternion(0, 0, 0, 0)
	var t := Vector3.ZERO
	var q0 := Quaternion.IDENTITY
	for k in parts.size():
		var m: Transform3D = _bw(parts[k][0]) * (parts[k][2] as Transform3D)
		var qi := m.basis.get_rotation_quaternion()
		if k == 0: q0 = qi
		elif q0.dot(qi) < 0.0: qi = -qi
		q += qi * float(parts[k][1])
		t += (m * pivot) * float(parts[k][1])
	return Transform3D(Basis(q.normalized()), t)


func _body(nm: String, sh: Shape3D, bit: int) -> AnimatableBody3D:
	var ab := AnimatableBody3D.new(); ab.name = nm; ab.collision_layer = bit; ab.collision_mask = 0; ab.sync_to_physics = true
	var cs := CollisionShape3D.new(); cs.shape = sh; ab.add_child(cs); _sim.add_child(ab)
	return ab


func _update_proxies() -> void:
	for b in _bodies: (b[0] as AnimatableBody3D).global_transform = _bw(b[1])
	for c in _caps:
		var a := _bw(c[1]).origin; var bb := _bw(c[2]).origin
		var sh: CapsuleShape3D = (c[0].get_child(0) as CollisionShape3D).shape
		sh.height = maxf(a.distance_to(bb) + 2.0 * sh.radius, 2.0 * sh.radius + 0.001)
		var y := (bb - a).normalized(); var x := y.cross(Vector3.FORWARD)
		if x.length() < 0.1: x = y.cross(Vector3.RIGHT)
		x = x.normalized()
		(c[0] as AnimatableBody3D).global_transform = Transform3D(Basis(x, y, x.cross(y)), (a + bb) * 0.5)
	for n in _att: (_att[n][0] as Node3D).global_transform = _bw(_att[n][1])
	if _floor:
		var r := get_parent() as Node3D
		_floor.global_transform = Transform3D(Basis.IDENTITY, Vector3(0, r.global_position.y if r else 0.0, 0))
	for k in _blend: (_blend[k][0] as Node3D).global_transform = _blend_xf(_blend[k][1], _blend[k][2])


func _physics_process(dt: float) -> void:
	if not _built: return
	_t += dt
	if _t > settle_time:
		player.advance(dt)
	var k := clampf((_t - settle_time) / maxf(blend_in_time, 0.001), 0.0, 1.0)
	if k < 1.0:
		for i in skel.get_bone_count():
			var r: Transform3D = _rest[i]
			skel.set_bone_pose_rotation(i, r.basis.get_rotation_quaternion().slerp(skel.get_bone_pose_rotation(i), k))
			skel.set_bone_pose_position(i, r.origin.lerp(skel.get_bone_pose_position(i), k))
	_update_proxies()


## 角色被瞬移（傳送、讀檔）後呼叫：重建袖子，避免布料被拉成長條。
func reset_sleeves() -> void:
	if _sim: _sim.queue_free()
	_bodies.clear(); _caps.clear(); _att.clear(); _blend.clear(); _sleeves.clear(); _built = false; _t = 0.0
	_build.call_deferred()


func get_sleeve(side: String) -> SoftBody3D:
	return _sleeves.get(side)

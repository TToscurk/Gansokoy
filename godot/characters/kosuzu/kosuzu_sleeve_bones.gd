extends Node3D
## 小鈴雙袖：多骨鏈擺動（SpringBoneSimulator3D），取代 Jolt SoftBody（kosuzu_sleeves.gd）。2026-10-21。
## 資料：kosuzu.glb 內 Sleeve_L0..2_1..3／Sleeve_R0..2_1..3（每袖 3 條鏈 × 3 節，鏈根掛上臂／過肘那條掛前臂；
##       權重只看沿臂位置與臂軸下方深度，前後兩片吃同一組權重 → 袖袋不會自己互穿）。
##       kosuzu_sleeve_chains.json（各鏈關節 Blender 世界座標）、kosuzu_colliders.json（衣身每 3 cm 一層外殼點＋腿／手臂膠囊）。
## 垂放：袖骨是 T-pose 建的（往下垂）。手臂放下後「垂直於手臂」會變成「往身體裡」，所以在彈簧之前（SleeveDrape）
##       把每條鏈的根繞「它掛的手臂骨」轉，讓袖袋朝「往下＋往後」（垂直於該骨的平面內最接近者），彈簧以它為目標，再由重力把袋尾往下拉。
##       實測（2026-10-21）：stiffness 3／gravity 0.2 → 袖袋水平往後像板子；改成「鏈根直接轉向正下方」→ 袖面與手臂共線被壓扁、
##       自交 13.7%。只照上臂下放角轉（第一版）托腮時前臂那條會翹成翅膀 → 改成每條鏈依自己的骨轉。

@export var data_prefix := "res://characters/kosuzu/kosuzu"
@export var springs_enabled := true:
	set(v):
		springs_enabled = v
		if _sim: _sim.active = v
## 回彈力（越大越貼著目標形狀）。
@export_range(0.0, 20.0) var stiffness := 1.2
## 阻尼（0～1）。
@export_range(0.0, 1.0) var drag := 0.45
## 重力（越大越往下垂）。
@export_range(0.0, 5.0) var gravity := 0.8
## 末節比根部軟多少（stiffness 沿鏈降到 stiffness × tip_softness）。
@export_range(0.1, 1.0) var tip_softness := 0.5
## 關節碰撞半徑（公尺，末節；根部 ×0.15，免得被自己的手臂膠囊推開）。
@export_range(0.0, 0.1) var joint_radius := 0.03
## 垂放：鏈根繞自己掛的手臂骨轉向「往下＋往後」的強度（0＝不轉，手臂放下後袖袋會往身體裡塞）。
@export_range(0.0, 1.0) var drape := 1.0
## 垂放目標的往後比例（相對往下 1）。
@export_range(0.0, 2.0) var drape_back := 0.6
## 垂放目標的往外（離開身體側面）比例：手臂垂下時袖袋朝「後＋外」，不貼著腰側／背後的帶結（T25）。只在該骨垂著時生效（前臂抬起不給）。0＝舊行為。
@export_range(0.0, 2.0) var drape_out := 0.0
## 衣身碰撞球半徑（公尺）與每圈方位數。
@export_range(0.0, 0.2) var body_sphere_r := 0.07
@export_range(4, 32) var body_dirs := 12
## 衣身碰撞只取這個高度（Blender 座標，袖袋最低約 0.49）以上的層，且每 slab_step 層取一層（效能：16 方位全取 307 個碰撞體 ≈1.3 ms／格）。
@export var body_min_z := 0.42
@export_range(1, 4) var slab_step := 2
## 上臂姿勢修正層（characters/npc/_shared/arm_space_correction.gd）：手垂著貼身體時最多往外張幾度。0＝不加。
@export_range(0.0, 30.0) var arm_correction_deg := 0.0
@export var model_path := NodePath("../Model")

var skel: Skeleton3D
var _sim: SpringBoneSimulator3D
var _drape: SleeveDrape
var _arm_fix: SkeletonModifier3D
var _chains := []   # [{side, bones:[idx], parent}]


class SleeveDrape extends SkeletonModifier3D:
	var strength := 1.0
	var back_k := 0.6
	var roots := []          # [root_idx, side]
	var chest := -1
	var up0 := Vector3.UP
	var back0 := Vector3.BACK
	var left0 := Vector3.RIGHT
	var out_k := 0.0
	var chest_rest_inv := Basis()

	## 每條鏈繞「自己掛的那根手臂骨」的軸轉，讓袖袋方向在垂直於該骨的平面上最接近「往下＋往後」。
	## 手臂水平時≈往下稍往後；手臂垂下時＝往後（再由重力往下拉）；前臂舉起（托腮）時＝往下。
	func _process_modification() -> void:
		var sk := get_skeleton()
		if sk == null or strength <= 0.0:
			return
		var cr := sk.get_bone_global_pose(chest).basis.orthonormalized() * chest_rest_inv
		var base := -(cr * up0) + (cr * back0) * back_k
		for r in roots:
			var bi: int = r[0]
			var par := sk.get_bone_parent(bi)
			var pgt := sk.get_bone_global_pose(par)
			var pg := pgt.basis.orthonormalized()
			var a := (pg * Vector3.UP).normalized()                   # 手臂骨軸（骨頭朝 +Y）
			# 往外只在「掛的那根骨垂著」時給（說話／托腮前臂抬起時不給，免得袖袋往外翹）
			var ok := out_k * smoothstep(0.5, 0.9, -a.dot((cr * up0).normalized()))
			var tgt := (base + (cr * left0) * (ok if r[1] == "L" else -ok)).normalized()
			var g := pg * sk.get_bone_pose(bi).basis.orthonormalized()
			var d0 := (g * Vector3.UP).normalized()
			var p0 := d0 - a * d0.dot(a); var pt := tgt - a * tgt.dot(a)
			if p0.length() < 1e-4 or pt.length() < 1e-4:
				continue
			var th := p0.signed_angle_to(pt, a) * strength
			var ng := Basis(a, th) * g
			sk.set_bone_pose_rotation(bi, (pg.inverse() * ng).get_rotation_quaternion())


func _ready() -> void:
	var model := get_node_or_null(model_path)
	if model == null:
		push_error("KosuzuSleeveBones：找不到 Model"); return
	skel = model.find_children("*", "Skeleton3D", true, false)[0]
	_build()


func _v(q: Array) -> Vector3:
	return Vector3(q[0], q[2], -q[1])     # Blender 世界 → glb／骨架空間


func _build() -> void:
	var sc := skel.global_transform.basis.get_scale().x
	var cj = JSON.parse_string(FileAccess.get_file_as_string(data_prefix + "_colliders.json"))
	var sj = JSON.parse_string(FileAccess.get_file_as_string(data_prefix + "_sleeve_chains.json"))
	# 上臂姿勢修正層（第一個修改器：動畫 → 上臂修正 → 袖子垂放 → 彈簧）
	if arm_correction_deg > 0.0:
		_arm_fix = (load("res://characters/npc/_shared/arm_space_correction.gd") as GDScript).new()
		_arm_fix.name = "ArmSpaceCorrection"; _arm_fix.set("max_deg", arm_correction_deg)
		skel.add_child(_arm_fix)
	# 垂放修改器（排在彈簧前）
	_drape = SleeveDrape.new(); _drape.name = "SleeveDrape"; _drape.strength = drape; _drape.back_k = drape_back
	skel.add_child(_drape)
	var hips := skel.find_bone("mixamorig_Hips"); var head := skel.find_bone("mixamorig_Head")
	var la := skel.find_bone("mixamorig_LeftArm"); var ra := skel.find_bone("mixamorig_RightArm")
	var up := (skel.get_bone_global_rest(head).origin - skel.get_bone_global_rest(hips).origin).normalized()
	var left := skel.get_bone_global_rest(la).origin - skel.get_bone_global_rest(ra).origin
	left = (left - up * left.dot(up)).normalized()
	_drape.up0 = up; _drape.back0 = -left.cross(up); _drape.left0 = left; _drape.out_k = drape_out
	_drape.chest = skel.find_bone("mixamorig_Spine2")
	_drape.chest_rest_inv = skel.get_bone_global_rest(_drape.chest).basis.orthonormalized().inverse()
	# 彈簧
	_sim = SpringBoneSimulator3D.new(); _sim.name = "Spring_Sleeves"
	skel.add_child(_sim)
	var paths: Array[NodePath] = []
	# 衣身：每層外殼取 body_dirs 個方位的最外點，碰撞球貼在外表面內側
	var si := -1
	for sd in cj.slabs:
		if float(sd.z) < body_min_z: continue
		si += 1
		if si % slab_step != 0: continue
		var bi := skel.find_bone(String(sd.bone).replace(":", "_"))
		var pts := []
		var cen := Vector3.ZERO
		for q in sd.pts_blender:
			var p := _v(q); pts.append(p); cen += p
		cen /= maxf(pts.size(), 1)
		var bg := skel.get_bone_global_rest(bi)
		for k in body_dirs:
			var ang := TAU * k / body_dirs
			var dir := Vector3(cos(ang), 0, sin(ang))
			var best := -1.0; var bp := Vector3.ZERO
			for p: Vector3 in pts:
				var d := p - cen; d.y = 0
				if d.length() < 1e-5 or d.normalized().dot(dir) < cos(PI / body_dirs * 1.5): continue
				if d.length() > best: best = d.length(); bp = p
			if best < 0.0: continue
			var r_sk := body_sphere_r / sc
			var c := bp - dir * minf(r_sk, best * 0.8)
			var s := SpringBoneCollisionSphere3D.new(); s.name = "COL_Body_%.2f_%02d" % [float(sd.z), k]
			s.radius = body_sphere_r
			_sim.add_child(s); s.bone = bi
			s.position_offset = bg.affine_inverse() * c
			paths.append(NodePath(s.name))
	# 腿、手臂、手膠囊（膠囊沿骨 +Y）
	for c in cj.capsules:
		var a := skel.find_bone(String(c.a).replace(":", "_")); var b := skel.find_bone(String(c.b).replace(":", "_"))
		if a < 0 or b < 0: continue
		var L := skel.get_bone_global_rest(a).origin.distance_to(skel.get_bone_global_rest(b).origin)
		var cap := SpringBoneCollisionCapsule3D.new(); cap.name = "COL_" + str(c.name)
		cap.radius = float(c.r) * sc; cap.mid_height = L * sc
		_sim.add_child(cap); cap.bone = a
		cap.position_offset = Vector3(0, L * 0.5, 0)
		paths.append(NodePath(cap.name))
	# 鏈
	_sim.setting_count = sj.chains.size()
	for i in sj.chains.size():
		var ch: Dictionary = sj.chains[i]
		var j: Array = ch.joints_blender
		var ids := []
		for bn in ch.bones: ids.append(skel.find_bone(bn))
		var side := "L" if String(ch.chain).begins_with("Sleeve_L") else "R"
		_chains.append({"side": side, "bones": ids})
		_drape.roots.append([ids[0], side])
		_sim.set_root_bone(i, ids[0])
		_sim.set_end_bone(i, ids[-1])
		_sim.set_extend_end_bone(i, true)
		_sim.set_end_bone_direction(i, SkeletonModifier3D.BONE_DIRECTION_PLUS_Y)
		_sim.set_end_bone_length(i, _v(j[-2]).distance_to(_v(j[-1])) * sc)
		_sim.set_radius(i, joint_radius)
		var rc := Curve.new(); rc.add_point(Vector2(0, 0.15)); rc.add_point(Vector2(1, 1.0))
		_sim.set_radius_damping_curve(i, rc)
		_sim.set_stiffness(i, stiffness)
		var sc2 := Curve.new(); sc2.add_point(Vector2(0, 1)); sc2.add_point(Vector2(1, tip_softness))
		_sim.set_stiffness_damping_curve(i, sc2)
		_sim.set_drag(i, drag)
		_sim.set_gravity(i, gravity)
		_sim.set_enable_all_child_collisions(i, false)
		_sim.set_collision_count(i, paths.size())
		for k in paths.size(): _sim.set_collision_path(i, k, paths[k])
	_sim.active = springs_enabled
	_sim.reset()


## 瞬移後呼叫：彈簧歸位
func reset_sleeves() -> void:
	if _sim: _sim.reset()


func get_simulator() -> SpringBoneSimulator3D:
	return _sim

extends Node
## Haori v2.1 runtime 組裝：在 Haori Skeleton3D 下依序掛
## [0] anchor modifier（haori_v21_anchor.gd）→ [1] SpringBoneSimulator3D（9 條鏈＋碰撞）。
## Body / Haori Skeleton3D 與 sim 的 scale 都必須是 (1,1,1)，啟動時檢查。

const AnchorScript := preload("res://haori_v21_anchor.gd")

# chain: [root, end, stiffness, drag, gravity, radius, s_curve_tip, g_curve_root, colliders]
const CHAINS := [
	["Haori_SleeveBag_L_01", "Haori_SleeveBag_L_03", 1.9, 0.60, 1.0, 0.05, 0.5, 0.5, ["Col_Torso","Col_UpArm_L","Col_ForeArm_L"]],
	["Haori_SleeveBag_R_01", "Haori_SleeveBag_R_03", 1.9, 0.60, 1.0, 0.05, 0.5, 0.5, ["Col_Torso","Col_UpArm_R","Col_ForeArm_R"]],
	["Haori_SleeveCuff_L_01", "Haori_SleeveCuff_L_02", 2.2, 0.45, 0.7, 0.05, 0.6, 0.7, ["Col_UpArm_L","Col_ForeArm_L"]],
	["Haori_SleeveCuff_R_01", "Haori_SleeveCuff_R_02", 2.2, 0.45, 0.7, 0.05, 0.6, 0.7, ["Col_UpArm_R","Col_ForeArm_R"]],
	["Haori_Front_L_01", "Haori_Front_L_03", 3.2, 0.50, 1.4, 0.06, 0.75, 0.8, ["Col_Hips","Col_Thigh_L","Col_Thigh_R"]],
	["Haori_Front_R_01", "Haori_Front_R_03", 3.2, 0.50, 1.4, 0.06, 0.75, 0.8, ["Col_Hips","Col_Thigh_L","Col_Thigh_R"]],
	["Haori_Side_L_01", "Haori_Side_L_02", 3.4, 0.50, 1.2, 0.06, 0.8, 0.85, ["Col_Hips","Col_Thigh_L"]],
	["Haori_Side_R_01", "Haori_Side_R_02", 3.4, 0.50, 1.2, 0.06, 0.8, 0.85, ["Col_Hips","Col_Thigh_R"]],
	["Haori_Back_01", "Haori_Back_03", 3.0, 0.50, 1.3, 0.07, 0.75, 0.8, ["Col_Hips","Col_Thigh_L","Col_Thigh_R"]],
]

# name: [haori_bone, radius, height, offset_y]
const COLLIDERS := {
	"Col_Torso":     ["Haori_Root", 0.13, 0.38, -0.09],
	"Col_UpArm_L":   ["Haori_SleeveUpper_L", 0.062, 0.26, 0.11],
	"Col_UpArm_R":   ["Haori_SleeveUpper_R", 0.062, 0.26, 0.11],
	"Col_ForeArm_L": ["Haori_Col_ForeArm_L", 0.05, 0.24, 0.12],
	"Col_ForeArm_R": ["Haori_Col_ForeArm_R", 0.05, 0.24, 0.12],
	"Col_Hips":      ["Haori_Waist", 0.12, 0.22, 0.06],
	"Col_Thigh_L":   ["Haori_Col_Thigh_L", 0.072, 0.36, 0.18],
	"Col_Thigh_R":   ["Haori_Col_Thigh_R", 0.072, 0.36, 0.18],
}

func _ready() -> void:
	var chr := get_parent()
	var body_skel: Skeleton3D
	var haori_skel: Skeleton3D
	for s in chr.find_children("*", "Skeleton3D", true, false):
		var sk := s as Skeleton3D
		if sk.find_bone("Haori_Root") != -1:
			haori_skel = sk
		elif sk.find_bone("Hips") != -1:
			body_skel = sk
	assert(body_skel and haori_skel)
	print("SCALECHECK body=", body_skel.scale, " haori=", haori_skel.scale)

	var anchor := AnchorScript.new()
	anchor.name = "HaoriAnchor"
	haori_skel.add_child(anchor)
	haori_skel.move_child(anchor, 0)
	anchor.setup(body_skel)

	var sim := SpringBoneSimulator3D.new()
	sim.name = "HaoriSpring"
	haori_skel.add_child(sim)          # child index 1，排在 anchor 之後
	print("MODIFIER ORDER: ", haori_skel.get_children().map(func(c): return c.name))

	for cname in COLLIDERS:
		var cfg: Array = COLLIDERS[cname]
		var c := SpringBoneCollisionCapsule3D.new()
		c.name = cname
		sim.add_child(c)
		c.bone_name = cfg[0]
		c.radius = cfg[1]
		c.height = cfg[2]
		c.position_offset = Vector3(0, cfg[3], 0)

	sim.setting_count = CHAINS.size()
	var joints := 0
	for i in CHAINS.size():
		var ch: Array = CHAINS[i]
		sim.set_root_bone_name(i, ch[0])
		sim.set_end_bone_name(i, ch[1])
		sim.set_extend_end_bone(i, true)
		sim.set_end_bone_length(i, 0.10)
		sim.set_stiffness(i, ch[2])
		sim.set_drag(i, ch[3])
		sim.set_gravity(i, ch[4])
		sim.set_gravity_direction(i, Vector3(0, -1, 0))
		sim.set_radius(i, ch[5])
		var sc := Curve.new()
		sc.add_point(Vector2(0, 1.0)); sc.add_point(Vector2(1, ch[6]))
		sim.set_stiffness_damping_curve(i, sc)
		var gc := Curve.new()
		gc.add_point(Vector2(0, ch[7])); gc.add_point(Vector2(1, 1.0))
		sim.set_gravity_damping_curve(i, gc)
		sim.set_enable_all_child_collisions(i, false)
		var cols: Array = ch[8]
		sim.set_collision_count(i, cols.size())
		for j in cols.size():
			sim.set_collision_path(i, j, sim.get_path_to(sim.get_node(NodePath(cols[j]))))
		joints += 3
	print("SPRING v21: ", sim.setting_count, " chains, sim.scale=", sim.scale,
		" colliders=", COLLIDERS.size())

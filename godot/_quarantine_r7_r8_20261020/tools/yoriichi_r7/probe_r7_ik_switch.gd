extends SceneTree
## P3.1 一次性量測：空中型起手／收尾時，IK 權重與刀插槽切換是否造成「渲染姿勢」跳位。
## 在 Skeleton3D.skeleton_updated（modifier 之後＝實際渲染姿勢）記錄刀尖／刀根、右手骨的玩家局部位置。
##   godot --headless --fixed-fps 60 --path godot -s res://tools/yoriichi_r7/probe_r7_ik_switch.gd -- [form_id]
const PLAYER := "res://characters/yoriichi/player_yoriichi_r7k.tscn"
var _p: CharacterBody3D
var _sk: Skeleton3D
var _rows: Array = []
var _t := 0.0

func _initialize() -> void:
	call_deferred("_run")

func _box(pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	body.position = pos
	root.add_child(body)

func _on_skel() -> void:
	var inv := (_p.get("_visual") as Node3D).global_transform.affine_inverse()
	var tip: Node3D = _p.get("_blade_tip")
	var sh: Node3D = _p.get("_sword_hand")
	var h := _sk.find_bone("mixamorig_RightHand")
	var hand := _sk.global_transform * _sk.get_bone_global_pose(h)
	var ik = _p.get("_r62_ik")
	_rows.append({"t": snappedf(_t, 0.001), "el": snappedf(float(_p.get("_action_elapsed")), 0.001),
		"w": snappedf(ik.right_weight, 0.001) if ik != null else -1.0, "phase": _p.get("r7_air_phase"),
		"full": _p.get("_tree").get("parameters/full/internal_active"),
		"tip": inv * tip.global_position, "base": inv * sh.global_position, "hand": inv * hand.origin})

func _run() -> void:
	for act in InputMap.get_actions():
		InputMap.action_erase_events(act)
	var args := OS.get_cmdline_user_args()
	var fid := int(args[0]) if args.size() > 0 else 10
	_box(Vector3(0, -0.5, 0), Vector3(100, 1, 100))
	_p = (load(PLAYER) as PackedScene).instantiate()
	_p.set("r7_vfx_enabled", false)
	_p.set("sun_mastery", 100)
	_p.set("sun_breath_gauge", 100.0)
	root.add_child(_p)
	await process_frame
	_p.set_process_unhandled_input(false)
	_sk = _p.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	_sk.skeleton_updated.connect(_on_skel)
	_p.call("request_draw")
	var fired := false
	while _t < 5.0:
		await physics_frame
		_t += 1.0 / 60.0
		if not fired and _t >= 2.0:
			fired = bool(_p.call("execute_form", fid, true))
	var worst := {"tip": [0.0, 0.0], "base": [0.0, 0.0], "hand": [0.0, 0.0]}
	var near: Array = []
	for i in range(1, _rows.size()):
		var a: Dictionary = _rows[i - 1]
		var b: Dictionary = _rows[i]
		if b.t < 1.9:
			continue
		var switch: bool = absf(float(a.w) - float(b.w)) > 0.05 or a.full != b.full or a.phase != b.phase
		for k in ["tip", "base", "hand"]:
			var d := ((b[k] as Vector3) - (a[k] as Vector3)).length()
			if switch and d > float(worst[k][0]):
				worst[k] = [snappedf(d * 1000.0, 0.1), b.t]
		if switch:
			near.append([b.t, b.el, a.w, b.w, a.full, b.full, b.phase,
				snappedf(((b.tip as Vector3) - (a.tip as Vector3)).length() * 1000.0, 0.1),
				snappedf(((b.base as Vector3) - (a.base as Vector3)).length() * 1000.0, 0.1)])
	print("R7_IK_SWITCH form=%d fired=%s worst_mm_at_switch=%s" % [fid, fired, JSON.stringify(worst)])
	for n in near:
		print("  switch t=%s el=%s w %s->%s full %s->%s phase=%s d_tip_mm=%s d_base_mm=%s" % n)
	quit()

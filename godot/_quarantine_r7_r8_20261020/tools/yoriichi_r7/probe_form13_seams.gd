extends SceneTree
## R7 P4 接縫連續性量測（唯讀，只輸出量測，不是長期 gate）。跑一圈十三型（REF01→REF12→REF01），
## 在 Skeleton3D.skeleton_updated（骨架＋握刀 IK 都更新後）取刀根／刀尖世界位置，逐格記錄。
##   R7C_SEAM_FIX=0|1 godot --headless --fixed-fps 60 --path godot -s res://tools/yoriichi_r7/probe_form13_seams.gd -- <tag>
## 輸出 user://r7p4_seams_rt_<tag>.json
const PLAYER := "res://characters/yoriichi/player_yoriichi_r7k.tscn"
var _p: CharacterBody3D
var _rows: Array = []
var _frame := 0
var _tip: Node3D
var _base: Node3D


func _initialize() -> void:
	call_deferred("_run")


func _on_sk() -> void:
	if _p == null or not bool(_p.call("r7c_running")):
		return
	var forms: Dictionary = _p.get("R7_FORMS")
	var f: int = _p.get("active_form")
	var ik = _p.get("_r62_ik")
	_rows.append({"f": _frame, "ref": String(forms[f].ref) if forms.has(f) else "", "anim": str(_p.get("_active_attack_name")),
		"af": snappedf(float(_p.get("_action_elapsed")) * 60.0, 0.01),
		"tip": _v(_tip.global_position), "base": _v(_base.global_position), "pos": _v(_p.global_position),
		"ikr": snappedf(float(ik.get("right_weight")), 0.01) if ik != null else -1.0,
		"ikl": snappedf(float(ik.get("_lw")), 0.01) if ik != null else -1.0,
		"grp": int(_p.get("r7_hit_group")), "floor": _p.is_on_floor()})


func _v(v: Vector3) -> Array:
	return [snappedf(v.x, 0.0001), snappedf(v.y, 0.0001), snappedf(v.z, 0.0001)]


func _run() -> void:
	var tag := "run"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		tag = args[0]
	for act in InputMap.get_actions():
		InputMap.action_erase_events(act)
	var w := Node3D.new()
	root.add_child(w)
	var g := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(200, 1, 200)
	cs.shape = bx
	g.add_child(cs)
	g.position = Vector3(0, -0.5, 0)
	w.add_child(g)
	_p = (load(PLAYER) as PackedScene).instantiate()
	_p.set("r7_vfx_enabled", false)
	_p.set("sun_mastery", 100)
	_p.set("sun_breath_gauge", 100.0)
	_p.set("form13_unlocked", true)
	w.add_child(_p)
	for i in 12:
		await physics_frame
	_p.call("request_draw")
	for i in 100:
		await physics_frame
	var sk: Skeleton3D = (_p.get("_visual") as Node).find_children("*", "Skeleton3D", true, false)[0]
	_tip = _p.get("_blade_tip")
	_base = _p.get("_blade_base")
	sk.skeleton_updated.connect(_on_sk)
	_p.set("r7c_hold_to_continue", false)
	var ok := bool(_p.call("start_form13"))
	var starts := 0
	for i in 60 * 30:
		await physics_frame
		_frame += 1
		var n := 0
		for e in _p.get("r7c_log"):
			if e.ev == "start":
				n += 1
		if n >= 13:
			_p.call("r7c_request_stop")
		if not bool(_p.call("r7c_running")):
			break
		starts = n
	var fo := FileAccess.open("user://r7p4_seams_rt_%s.json" % tag, FileAccess.WRITE)
	fo.store_string(JSON.stringify({"seam_fix": _p.get("r7c_seam_fix"), "started": ok, "log": _p.get("r7c_log"), "rows": _rows}))
	fo.close()
	print("R7C_SEAM_PROBE tag=", tag, " fix=", _p.get("r7c_seam_fix"), " rows=", _rows.size(), " starts=", starts)
	quit(0)

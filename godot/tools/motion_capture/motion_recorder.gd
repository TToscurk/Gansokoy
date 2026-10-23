extends Node
## MotionRecorder（godot_motion.v1）：逐格真值記錄元件。**只讀**——不改任何戰鬥／動畫／輸入狀態。
## 由 record_harness.gd 掛到測試場景；也可手動 add_child 後呼叫 configure()。
##
## 取樣時機＝RenderingServer.frame_pre_draw（該格所有 _process、AnimationTree、Skeleton 修改器都跑完、送去繪製之前），
## 所以記到的姿勢＝這一格畫面上的姿勢。同步標記在本節點 _process（process_priority 最大＝最後跑）設定為同一個 id。
## 輸出（out_dir）：meta.json、frames.jsonl（一格一行）、events.jsonl。座標系見 tools/video_intel/SCHEMA.md。
const SCHEMA := "godot_motion.v1"
const SwordGeo = preload("res://tools/motion_capture/sword_geometry.gd")
const MAIN_BONES := ["Hips", "Spine", "Spine1", "Spine2", "Neck", "Head", "LeftArm", "LeftForeArm", "LeftHand", "RightArm", "RightForeArm", "RightHand",
	"LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase", "RightUpLeg", "RightLeg", "RightFoot", "RightToeBase"]
const SECONDARY_PREFIX := ["Haori_", "Hair_", "Cuff_", "Sleeve"]
const FOOT_LIFT_M := 0.03          # 與 foot_lock_modifier.gd 同門檻：腳趾離校正高度 < 3 cm
const FOOT_SPEED := 0.7            # 且水平速度 < 0.7 m/s 才算著地
const FROZEN_EPS_M := 0.0005       # 主骨（角色本地座標）一格內最大位移 < 0.5 mm＝姿勢凍結
const MARKER_BITS := 32            # 4 位同步樣式 1011 + 24 位 id + 4 位檢查碼
const MARKER_CELL := 12
const MARKER_COLS := 16

var target: Node
var out_dir := ""
var marker_enabled := true
var proj_points: Array = []        # 投影驗證用的固定世界點（harness 放的不受深度遮擋小球）
var proj_tip_marker := false
var extra_meta := {}

var sk: Skeleton3D
var actor: Node3D
var combat: Object
var tree: AnimationTree
var sword: Node3D
var sword_mi: MeshInstance3D
var sword_geo := {}
var sheathed: Node3D
var _main_idx: Array = []
var _main_names: Array = []
var _sec_idx: Array = []
var _f_frames: FileAccess
var _f_events: FileAccess
var _id := -1                      # 這一格的同步 id（_process 設定，pre_draw 寫入）
var _written_id := -1
var _proc_calls := 0
var _pf_last := -1
var _rows := 0
var _dup_pre_draw := 0
var _last_phys := 0
var _phys_frames_in_proc := 0
var _prev := {}
var _toe_ref := {}
var _calib_frames := 0
var _cells: Array = []
var _marker_rect := Rect2()
var _order: Array = []             # 本格內各回呼的時間戳（判斷 AnimationTree 在控制器之前或之後算）
var _hit_queue: Array = []
var _unavail := {}
var _t0_usec := 0
var _finished := false
var _last_hs := 0
var _last_frozen := false
var _last_scale := {}

func configure(p_target: Node, p_out: String) -> void:
	target = p_target
	out_dir = p_out

func _ready() -> void:
	process_priority = 1 << 30
	process_physics_priority = 1 << 30
	_t0_usec = Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(out_dir)
	_f_frames = FileAccess.open(out_dir.path_join("frames.jsonl"), FileAccess.WRITE)
	_f_events = FileAccess.open(out_dir.path_join("events.jsonl"), FileAccess.WRITE)
	_discover()
	if marker_enabled:
		_build_marker()
	RenderingServer.frame_pre_draw.connect(_on_pre_draw)
	_write_meta(false)

# ------------------------------------------------------------------ 探索（找不到就記 unavailable，不猜）
func _discover() -> void:
	sk = target.get("sk") as Skeleton3D if "sk" in target else null
	if sk == null:
		var l := target.find_children("*", "Skeleton3D", true, false)
		sk = l[0] as Skeleton3D if l.size() > 0 else null
	actor = target.get("actor") as Node3D if "actor" in target else null
	combat = target.get("combat") if "combat" in target else null
	if combat != null and "tree" in combat:
		tree = combat.get("tree") as AnimationTree
	if tree == null:
		var t := target.find_children("*", "AnimationTree", true, false)
		tree = t[0] as AnimationTree if t.size() > 0 else null
	sword = target.find_child("Sword_Hand", true, false) as Node3D
	sheathed = target.find_child("Sword_Sheathed", true, false) as Node3D
	if sk == null:
		_unavail["skeleton"] = "no Skeleton3D found"
	else:
		for b in MAIN_BONES:
			var i := sk.find_bone("mixamorig_" + b)
			if i < 0:
				i = sk.find_bone(b)
			if i >= 0:
				_main_idx.append(i)
				_main_names.append(sk.get_bone_name(i))
			else:
				_unavail["bone:" + b] = "bone not in skeleton"
		for i in sk.get_bone_count():
			var n := sk.get_bone_name(i)
			for pfx in SECONDARY_PREFIX:
				if n.begins_with(pfx):
					_sec_idx.append(i)
					break
		sk.skeleton_updated.connect(func() -> void: _order.append(["skeleton_updated", Time.get_ticks_usec()]))
	if actor == null:
		_unavail["actor"] = "target has no 'actor' Node3D"
	if combat == null:
		_unavail["controller"] = "target has no 'combat' controller; shot/hitstop fields null"
	else:
		for sig in ["hit_landed", "shot_finished", "swing_started"]:
			if combat.has_signal(sig):
				combat.connect(sig, _on_combat_signal.bind(sig))
	if tree != null and tree.has_signal("mixer_updated"):
		tree.mixer_updated.connect(func() -> void: _order.append(["mixer_updated", Time.get_ticks_usec()]))
	if sword == null:
		_unavail["sword"] = "no Sword_Hand node"
	else:
		sword_mi = SwordGeo.find_mesh(sword)
		sword_geo = SwordGeo.analyze(sword)
		if not sword_geo.get("ok", false):
			_unavail["blade_geometry"] = sword_geo.get("reason", "?")

func _on_combat_signal(a = null, b = null, c = null, sig := "") -> void:
	# 信號參數個數不同（hit_landed 1、swing_started 1、shot_finished 3）；bind 的 sig 永遠在最後
	var args := [a, b, c].filter(func(x) -> bool: return x != null)
	if sig == "" and args.size() > 0 and args[-1] is String:
		sig = args.pop_back()
	# 信號可能在本格 recorder._process 之前觸發（被測場景的 _process 先跑）：那時 _id 還是上一格，要用「本格將拿到的 id」
	var eid := _id if Engine.get_process_frames() == _pf_last else _proc_calls
	var ev := {"kind": sig, "id": eid, "process_frame": Engine.get_process_frames(), "frame_drawn": Engine.get_frames_drawn(), "t_usec": Time.get_ticks_usec() - _t0_usec}
	if sig == "hit_landed" and args.size() > 0 and args[0] is Dictionary:
		ev["info"] = _jsonable(args[0])
	elif sig == "shot_finished":
		ev["info"] = {"key": args[0] if args.size() > 0 else null, "t": args[1] if args.size() > 1 else null, "cancelled": args[2] if args.size() > 2 else null}
	elif sig == "swing_started":
		ev["info"] = {"idx": args[0] if args.size() > 0 else null}
	_hit_queue.append(ev)

# ------------------------------------------------------------------ 同步標記
func _build_marker() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 128
	cl.name = "MotionRecorderSyncMarker"
	add_child(cl)
	var vs := get_viewport().get_visible_rect().size
	var rows := int(ceil(float(MARKER_BITS) / MARKER_COLS))
	var size := Vector2(MARKER_COLS * MARKER_CELL, rows * MARKER_CELL)
	var origin := Vector2(6, vs.y - size.y - 6)
	var bg := ColorRect.new()
	bg.color = Color(0.5, 0.5, 0.5)
	bg.position = origin - Vector2(3, 3)
	bg.size = size + Vector2(6, 6)
	cl.add_child(bg)
	for i in MARKER_BITS:
		var r := ColorRect.new()
		r.position = origin + Vector2((i % MARKER_COLS) * MARKER_CELL, (i / MARKER_COLS) * MARKER_CELL)
		r.size = Vector2(MARKER_CELL, MARKER_CELL)
		r.color = Color.BLACK
		cl.add_child(r)
		_cells.append(r)
	_marker_rect = Rect2(origin, size)

static func marker_bits(id: int) -> Array:
	var bits := [1, 0, 1, 1]
	for k in range(23, -1, -1):
		bits.append((id >> k) & 1)
	var chk := 0
	for k in 6:
		chk ^= (id >> (4 * k)) & 15
	for k in range(3, -1, -1):
		bits.append((chk >> k) & 1)
	return bits

func _process(_delta: float) -> void:
	_proc_calls += 1
	_id = _proc_calls - 1
	_pf_last = Engine.get_process_frames()
	_order.append(["recorder_process_last", Time.get_ticks_usec()])
	if marker_enabled:
		var bits := marker_bits(_id)
		for i in MARKER_BITS:
			(_cells[i] as ColorRect).color = Color.WHITE if bits[i] == 1 else Color.BLACK

func _physics_process(_delta: float) -> void:
	_phys_frames_in_proc += 1

func note_harness_process() -> void:
	_order.append(["harness_process_first", Time.get_ticks_usec()])

# ------------------------------------------------------------------ 每格取樣
func _on_pre_draw() -> void:
	if _finished or _id < 0:
		return
	if _id == _written_id:
		_dup_pre_draw += 1          # 同一個 _process 之後畫了兩次（不應發生）——記下來，不重寫
		return
	_written_id = _id
	_order.append(["pre_draw", Time.get_ticks_usec()])
	var vp := get_viewport()
	var cam := vp.get_camera_3d()
	var row := {"id": _id, "frame_drawn": Engine.get_frames_drawn(), "process_frame": Engine.get_process_frames(),
		"physics_frame": Engine.get_physics_frames(), "physics_steps_since_prev": _phys_frames_in_proc,
		"t_usec": Time.get_ticks_usec() - _t0_usec, "delta": get_process_delta_time(), "physics_delta": get_physics_process_delta_time(),
		"time_scale": Engine.time_scale}
	_phys_frames_in_proc = 0
	var order := []
	for o in _order:
		order.append([o[0], int(o[1]) - _t0_usec])
	row["order"] = order
	_order.clear()
	row["viewport"] = {"size": [vp.size.x, vp.size.y], "visible_rect": [vp.get_visible_rect().size.x, vp.get_visible_rect().size.y]}
	row["camera"] = _cam_row(cam, vp)
	var root_xf := actor.global_transform if actor else Transform3D.IDENTITY
	row["actor"] = {"pos_w": _v(root_xf.origin), "quat_w": _q(root_xf.basis), "yaw_rad": actor.rotation.y if actor else null} if actor else null
	var cur := {}
	if sk:
		var sxf := sk.global_transform
		var bp := []
		var bq := []
		var loc := []
		var inv := root_xf.affine_inverse()
		for i in _main_idx:
			var g := sxf * sk.get_bone_global_pose(i)
			bp.append(_v(g.origin))
			bq.append(_q(g.basis))
			loc.append(inv * g.origin)
		var sec := []
		for i in _sec_idx:
			sec.append(inv * (sxf * sk.get_bone_global_pose(i).origin))
		cur["main_local"] = loc
		cur["sec_local"] = sec
		row["skeleton_xform_w"] = _xf(sxf)
		row["bones_p_w"] = bp
		row["bones_q_w"] = bq
		row["main_delta_max_m"] = _max_delta(loc, _prev.get("main_local", []))
		row["secondary_delta_max_m"] = _max_delta(sec, _prev.get("sec_local", []))
		row["feet"] = _feet(sxf, cur)
	row["sword"] = _sword_row(cam, cur)
	row["controller"] = _ctrl_row()
	row["anim"] = _anim_row()
	var en: Variant = target.get("enemy") if "enemy" in target else null
	row["others"] = {"enemy_pos_w": _v((en as Node3D).global_position), "enemy_child0_local": _v(((en as Node3D).get_child(0) as Node3D).position) if (en as Node3D).get_child_count() > 0 else null} if en is Node3D else null
	# 凍結判定：三件事分開記
	var hs_active := false
	var ctrl: Dictionary = row["controller"] if row["controller"] is Dictionary else {}
	if ctrl.get("hitstop_left") != null:
		hs_active = int(ctrl["hitstop_left"]) > 0
	var ts0 := false
	var an: Dictionary = row["anim"]
	if an.get("attack_time_scale") != null and ctrl.get("is_attack") == true:
		ts0 = float(an["attack_time_scale"]) == 0.0
	elif an.get("shot_time_scale") != null and ctrl.get("state_name") == "SHOT":
		ts0 = float(an["shot_time_scale"]) == 0.0
	var shot_same: Variant = null
	if ctrl.get("shot_t") != null and _prev.has("shot_t"):
		shot_same = absf(float(ctrl["shot_t"]) - float(_prev["shot_t"])) < 1e-7
	var pose_frozen: Variant = null
	if row.get("main_delta_max_m") != null:
		pose_frozen = float(row["main_delta_max_m"]) < FROZEN_EPS_M
	row["freeze"] = {"hitstop_counter_active": hs_active, "anim_time_scale_zero": ts0, "shot_t_unchanged": shot_same,
		"main_pose_frozen": pose_frozen, "rule_pose_frozen": "main bones actor-local max displacement < %.4f m" % FROZEN_EPS_M}
	# 事件
	var evs := _hit_queue.duplicate()
	_hit_queue.clear()
	var hl := int(ctrl.get("hitstop_left", 0)) if ctrl.get("hitstop_left") != null else 0
	if hl > 0 and _last_hs == 0:
		evs.append({"kind": "hitstop_counter_start", "id": _id, "hitstop_left": hl})
	elif hl == 0 and _last_hs > 0:
		evs.append({"kind": "hitstop_counter_end", "id": _id})
	_last_hs = hl
	var fz: bool = pose_frozen == true
	if fz != _last_frozen:
		evs.append({"kind": "pose_frozen_start" if fz else "pose_frozen_end", "id": _id})
	_last_frozen = fz
	for k in ["attack_time_scale", "shot_time_scale"]:
		if an.get(k) != null and _last_scale.get(k) != null and float(an[k]) != float(_last_scale[k]):
			evs.append({"kind": "anim_speed_change", "id": _id, "param": k, "from": _last_scale[k], "to": an[k]})
		_last_scale[k] = an.get(k)
	if _prev.has("time_scale") and float(_prev["time_scale"]) != Engine.time_scale:
		evs.append({"kind": "engine_time_scale_change", "id": _id, "from": _prev["time_scale"], "to": Engine.time_scale})
	row["events"] = evs
	for e in evs:
		_f_events.store_line(JSON.stringify(e, "", true, true))
	_f_frames.store_line(JSON.stringify(row, "", true, true))
	_rows += 1
	if _rows % 60 == 0:
		_f_frames.flush()
		_f_events.flush()
		_write_meta(false)
	cur["shot_t"] = ctrl.get("shot_t")
	cur["time_scale"] = Engine.time_scale
	_prev = cur

func _cam_row(cam: Camera3D, vp: Viewport) -> Variant:
	if cam == null:
		return null
	var xf := cam.global_transform
	var vs := vp.get_visible_rect().size
	var r := {"path": str(cam.get_path()), "pos_w": _v(xf.origin), "basis_w": _basis(xf.basis), "quat_w": _q(xf.basis),
		"projection_type": cam.projection, "fov_deg": cam.fov, "keep_aspect": cam.keep_aspect, "near": cam.near, "far": cam.far,
		"h_offset": cam.h_offset, "v_offset": cam.v_offset, "size": cam.size}
	var p := cam.get_camera_projection()
	r["projection_cols"] = [_v4(p.x), _v4(p.y), _v4(p.z), _v4(p.w)]
	var view := xf.affine_inverse()
	r["view_xform"] = _xf(view)
	r["viewport_px"] = [vs.x, vs.y]
	return r

func _sword_row(cam: Camera3D, cur: Dictionary) -> Variant:
	if sword == null:
		return null
	var dt := get_process_delta_time()
	var r := {"visible_in_tree": sword.is_visible_in_tree(), "node_origin_w": _v(sword.global_position)}
	if sword_mi and sword_geo.get("ok", false):
		var w := SwordGeo.world(sword_geo, sword_mi)
		var tip: Vector3 = w["tip"]
		r["blade_tip_w"] = _v(tip)
		r["guard_w"] = _v(w["guard"])
		r["hilt_w"] = _v(w["hilt"])
		r["pommel_w"] = _v(w["pommel"])
		r["blade_dir_w"] = _v(w["dir"])
		r["blade_len_m"] = w["blade_len"]
		var pt: Variant = _prev.get("tip_w")
		if pt is Vector3 and dt > 0.0:
			var vel: Vector3 = (tip - (pt as Vector3)) / dt
			r["blade_tip_vel_w"] = _v(vel)
			r["blade_tip_speed"] = vel.length()
		else:
			r["blade_tip_vel_w"] = null
			r["blade_tip_speed"] = null
		r["velocity_rule"] = "(blade_tip_w[this frame] - blade_tip_w[previous recorded frame]) / delta"
		cur["tip_w"] = tip
		if cam:
			r["blade_tip_px_godot"] = _v2(cam.unproject_position(tip)) if not cam.is_position_behind(tip) else null
			r["hilt_px_godot"] = _v2(cam.unproject_position(w["hilt"])) if not cam.is_position_behind(w["hilt"]) else null
	if sheathed:
		r["sheathed_visible_in_tree"] = sheathed.is_visible_in_tree()
	return r

func _ctrl_row() -> Variant:
	if combat == null:
		return null
	var st: Variant = combat.get("state")
	var names := ["IDLE", "MOVE", "SHOT"]
	var key := str(combat.get("shot_key")) if "shot_key" in combat else ""
	var is_attack: Variant = null
	if combat.has_method("_cfg") and key != "" and int(st) == 2:
		is_attack = bool((combat.call("_cfg", key) as Dictionary).get("attack", false))
	return {"state": st, "state_name": names[int(st)] if st != null and int(st) < names.size() else null,
		"shot_key": key, "shot_t": combat.get("shot_t"), "hitstop_left": combat.get("hitstop_left"), "hitstop_total": combat.get("hitstop_total"),
		"hitstop_frames_cfg": combat.get("hitstop_frames"), "atk_w": combat.get("atk_w"), "label": combat.get("label"), "is_attack": is_attack,
		"body_velocity_local": _v(combat.get("body_velocity")) if combat.get("body_velocity") is Vector3 else null}

func _anim_row() -> Dictionary:
	var r := {"tree_active": tree.active if tree else null}
	if tree:
		var a: Variant = tree.get("parameters/asts/scale")
		var s: Variant = tree.get("parameters/sts/scale")
		r["attack_time_scale"] = a
		r["shot_time_scale"] = s
		r["callback_mode_process"] = tree.callback_mode_process
	return r

func _feet(sxf: Transform3D, cur: Dictionary) -> Dictionary:
	var out := {}
	var dt := get_process_delta_time()
	for side in ["Left", "Right"]:
		var ti := sk.find_bone("mixamorig_%sToeBase" % side)
		var ai := sk.find_bone("mixamorig_%sFoot" % side)
		if ti < 0 or ai < 0:
			out[side] = null
			continue
		var toe := sxf * sk.get_bone_global_pose(ti).origin
		var ank := sxf * sk.get_bone_global_pose(ai).origin
		var pk: String = "toe_" + side
		var pv: Variant = _prev.get(pk)
		var hs: Variant = null
		if pv is Vector3 and dt > 0.0:
			hs = Vector2(toe.x - (pv as Vector3).x, toe.z - (pv as Vector3).z).length() / dt
		cur[pk] = toe
		if _calib_frames < 10:
			_toe_ref[side] = minf(float(_toe_ref.get(side, 1e9)), toe.y)
		var ref: float = _toe_ref.get(side, toe.y)
		var contact: Variant = null
		if hs != null and _calib_frames >= 10:
			contact = (toe.y - ref) < FOOT_LIFT_M and float(hs) < FOOT_SPEED
		out[side] = {"toe_w": _v(toe), "ankle_w": _v(ank), "toe_height_above_ref_m": toe.y - ref, "toe_horiz_speed": hs, "contact": contact}
	_calib_frames += 1
	out["rule"] = "kinematic heuristic (not physics): toe_y - min(toe_y over first 10 frames) < %.2f m AND toe horizontal speed < %.1f m/s" % [FOOT_LIFT_M, FOOT_SPEED]
	return out

func _max_delta(a: Array, b: Array) -> Variant:
	if a.is_empty() or b.size() != a.size():
		return null
	var m := 0.0
	for i in a.size():
		m = maxf(m, (a[i] as Vector3).distance_to(b[i] as Vector3))
	return m

# ------------------------------------------------------------------ meta / 結束
func _write_meta(final: bool) -> void:
	var vp := get_viewport()
	var m := {"schema": SCHEMA, "final": final, "rows": _rows, "process_calls": _proc_calls, "duplicate_pre_draw": _dup_pre_draw,
		"target_scene": target.scene_file_path if target else "", "godot_version": Engine.get_version_info(),
		"cmdline": OS.get_cmdline_args(), "user_args": OS.get_cmdline_user_args(),
		"movie_writer_path": Engine.get_write_movie_path(),
		"physics_ticks_per_second": Engine.physics_ticks_per_second, "max_fps": Engine.max_fps,
		"window_size": [get_window().size.x, get_window().size.y], "viewport_size": [vp.size.x, vp.size.y],
		"marker": {"enabled": marker_enabled, "rect_px": [_marker_rect.position.x, _marker_rect.position.y, _marker_rect.size.x, _marker_rect.size.y],
			"cell_px": MARKER_CELL, "cols": MARKER_COLS, "bits": MARKER_BITS, "layout": "bits[0:4]=1011 sync, bits[4:28]=id (24-bit, MSB first), bits[28:32]=xor of the six id nibbles; row-major, white=1",
			"value": "recorder id set in MotionRecorder._process (runs last in the frame); frames.jsonl row with the same id is sampled at frame_pre_draw of that frame"},
		"main_bones": _main_names, "secondary_bone_count": _sec_idx.size(),
		"blade_geometry": _jsonable(sword_geo), "legacy_tip_local_in_demos": [0.0, 1.085, 0.0],
		"proj_points_w": proj_points.map(func(p): return _v(p)), "proj_tip_marker": proj_tip_marker,
		"coordinate_frames": {"*_w": "Godot world space, metres, +Y up", "*_local": "actor root local space", "bones_*_w": "world space (skeleton global transform x bone global pose)",
			"projection_cols": "Camera3D.get_camera_projection() columns (Godot clip space; ndc y up)", "view_xform": "camera.global_transform.affine_inverse() basis cols + origin",
			"*_px_godot": "Camera3D.unproject_position (pixels, origin top-left, viewport size)"},
		"unavailable": _unavail}
	m.merge(extra_meta)
	var f := FileAccess.open(out_dir.path_join("meta.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(m, " "))
	f.close()

func finish() -> void:
	if _finished:
		return
	_finished = true
	_f_frames.flush()
	_f_events.flush()
	_write_meta(true)
	_f_frames.close()
	_f_events.close()

func _exit_tree() -> void:
	finish()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		finish()

# ------------------------------------------------------------------ 序列化小工具
static func _v(v: Vector3) -> Array:
	return [v.x, v.y, v.z]

static func _v2(v: Vector2) -> Array:
	return [v.x, v.y]

static func _v4(v: Vector4) -> Array:
	return [v.x, v.y, v.z, v.w]

static func _q(b: Basis) -> Array:
	var q := b.orthonormalized().get_rotation_quaternion()
	return [q.x, q.y, q.z, q.w]

static func _basis(b: Basis) -> Array:
	return [_v(b.x), _v(b.y), _v(b.z)]

static func _xf(t: Transform3D) -> Array:
	return [_v(t.basis.x), _v(t.basis.y), _v(t.basis.z), _v(t.origin)]

static func _jsonable(x: Variant) -> Variant:
	if x is Vector3:
		return _v(x)
	if x is Vector2:
		return _v2(x)
	if x is Dictionary:
		var d := {}
		for k in x:
			d[str(k)] = _jsonable(x[k])
		return d
	if x is Array:
		return (x as Array).map(func(e): return _jsonable(e))
	if x is float and (is_nan(x) or is_inf(x)):
		return null
	return x

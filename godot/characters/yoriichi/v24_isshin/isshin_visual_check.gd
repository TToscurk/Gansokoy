extends "res://characters/yoriichi/v24_isshin/isshin_slash_demo.gd"
## 衣物／腳步視覺檢查（v24_isshin 獨立候選；不改 Player／跑酷／共用骨架）。
## 三個同步面板：正面／左側（刀鞘側）／背後；相機以場景起點的朝向為基準，只跟隨角色平移（轉身時鏡頭不轉，才看得出身體怎麼轉）。
## 起步、停步、反向、轉身開始時，在兩腳踝正下方的地面放標記，並畫標記→腳踝的連線與公分數，直接看見滑步。
## 用法：godot --path godot --write-movie out.avi --fixed-fps 60 res://characters/yoriichi/v24_isshin/isshin_visual_check.tscn -- --tour [--log=P] [--poselog=P] [--slipjson=P]
##      [--springs=off] [--sleeve-springs=off] [--sleeve-col=off] [--hem-col=off] [--stop-at=秒]
var CAM_DIST := 2.3
var cam_off := Vector3.ZERO
const CAM_FOV := 36.0
const MARK_LIFE := 3.0

var panels: Array = []
var cam_ref_yaw := 0.0
var cam_yaw_s := 0.0
var cam_focus := Vector3.ZERO
var last_seg := -99
var markers: Array = []
var slip_events: Array = []
var prev_g := 0.0
var prev_stopping := false
var prev_state := 0
var prev_label := ""
var pose_rows := PackedFloat32Array()
var pose_n := 0
var fl_rows := PackedFloat32Array()
var pose_path := ""
var slip_json := ""
var stop_at := -1.0
var finished := false
var shot_list: Array = []      # [{t, focus(skeleton space), name}]
var shot_dir := ""
var shot_busy := false
var xray_meshes: Array = []

func _ready() -> void:
	super._ready()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--poselog="):
			pose_path = a.substr(10)
		elif a.begins_with("--slipjson="):
			slip_json = a.substr(11)
		elif a.begins_with("--stop-at="):
			stop_at = float(a.substr(10))
		elif a.begins_with("--shotdir="):
			shot_dir = a.substr(10)
		elif a.begins_with("--shots="):
			for item in a.substr(8).split(";"):
				var f := item.split(",")
				if f.size() >= 5:
					shot_list.append({"t": float(f[0]), "focus": Vector3(float(f[1]), float(f[2]), float(f[3])), "name": f[4]})
		elif a.begins_with("--winsize="):
			var wh := a.substr(10).split("x")
			get_window().size = Vector2i(int(wh[0]), int(wh[1]))
		elif a == "--springs=off":
			rig.springs_enabled = false
		elif a == "--sleeve-springs=off":
			_sim("sleeve").active = false
		elif a == "--sleeve-col-torso=off":
			_sleeve_filter_cols(["Hips", "Spine", "Spine1", "Spine2"], "")
		elif a.begins_with("--sleeve-col-chain=off:"):
			_sleeve_filter_cols(["Hips", "Spine", "Spine1", "Spine2", "Neck", "Head"], a.substr(23))
		elif a.begins_with("--sleeve-stiff="):
			var sm := _sim("sleeve")
			for i in sm.setting_count:
				sm.set_stiffness(i, float(a.substr(15)))
			sm.reset()
		elif a.begins_with("--cam-off="):
			var co := a.substr(10).split(",")
			cam_off = Vector3(float(co[0]), float(co[1]), float(co[2]))
		elif a.begins_with("--cam-dist="):
			CAM_DIST = float(a.substr(11))
		elif a.begins_with("--hem-leg="):
			var rr := a.substr(10).split(",")
			_set_hem_leg(float(rr[0]), float(rr[1]))
		elif a.begins_with("--torso-extra="):
			_set_torso_extra(float(a.substr(14)))
		elif a == "--sleeve-col=off":
			_no_col("sleeve")
		elif a == "--hem-col=off":
			_no_col("hem")
	shot_list.sort_custom(func(a, b): return float(a["t"]) < float(b["t"]))
	_build_panels()
	cam.current = false
	sk.skeleton_updated.connect(_check_update)
	cam_ref_yaw = actor.rotation.y
	cam_yaw_s = cam_ref_yaw
	cam_focus = actor.global_position + Vector3(0, 0.62, 0) + cam_off
	_update_cam(true)

func _sim(kind: String) -> SpringBoneSimulator3D:
	return sk.get_node("Spring_" + kind) as SpringBoneSimulator3D

## 只改這個候選場景實例的袖鏈碰撞膠囊（軀幹膠囊的額外半徑）；不改共用的 yoriichi_v24_rig.gd。
func _set_torso_extra(extra: float) -> void:
	var cols: Array = (JSON.parse_string(FileAccess.get_file_as_string("res://characters/yoriichi/v24/colliders.json")) as Dictionary)["colliders"]
	var s := _sim("sleeve")
	for d in cols:
		var cap := s.get_node_or_null("COL_" + str(d["name"])) as SpringBoneCollisionCapsule3D
		if cap and bool(d.get("torso", false)):
			cap.radius = float(d["radius_m"]) + extra
			cap.mid_height = maxf(0.0, float(d["height_m"]) - 2.0 * float(d["radius_m"]))
	s.reset()

## 只改這個候選實例的下襬碰撞膠囊：大腿／小腿半徑放大到袴的實際表面半徑（實測袴中位半徑 大腿 0.117／小腿 0.151 m，原膠囊 0.080／0.058 m）。
func _set_hem_leg(thigh_r: float, shin_r: float) -> void:
	var cols: Array = (JSON.parse_string(FileAccess.get_file_as_string("res://characters/yoriichi/v24/colliders.json")) as Dictionary)["colliders"]
	var s := _sim("hem")
	for d in cols:
		var nm := str(d["name"])
		var cap := s.get_node_or_null("COL_" + nm) as SpringBoneCollisionCapsule3D
		if cap == null or not nm.contains("Leg"):
			continue
		cap.radius = shin_r if (nm == "LeftLeg" or nm == "RightLeg") else thigh_r
		cap.mid_height = maxf(0.0, float(d["height_m"]) - 2.0 * float(d["radius_m"]))
	s.reset()

## 袖鏈碰撞過濾：names 為要拿掉的碰撞膠囊名（COL_ 後綴）；chain_key 非空時只作用在名稱含該字串的鏈（例如 "_Dn"），否則作用在全部袖鏈。
func _sleeve_filter_cols(names: Array, chain_key: String) -> void:
	var s := _sim("sleeve")
	for i in s.setting_count:
		if chain_key != "" and not str(s.get_root_bone_name(i)).contains(chain_key):
			continue
		var keep: Array = []
		for k in s.get_collision_count(i):
			var path := str(s.get_collision_path(i, k))
			var nm := path.replace("COL_", "")
			if chain_key == "":
				if not (nm in names):
					keep.append(path)
			# chain_key 模式：該鏈的碰撞全部拿掉
		s.set_collision_count(i, keep.size())
		for k in keep.size():
			s.set_collision_path(i, k, NodePath(keep[k]))
	s.reset()

func _no_col(kind: String) -> void:
	var s := _sim(kind)
	for i in s.setting_count:
		s.set_collision_count(i, 0)
	s.reset()

# ---------------------------------------------------------------- 面板
func _build_panels() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 0
	add_child(cl)
	var hb := HBoxContainer.new()
	hb.set_anchors_preset(Control.PRESET_FULL_RECT)
	hb.add_theme_constant_override("separation", 4)
	cl.add_child(hb)
	var titles := ["正面 FRONT", "左側（刀鞘側）LEFT", "背後 BACK"]
	for i in 3:
		var c := SubViewportContainer.new()
		c.stretch = true
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
		hb.add_child(c)
		var vp := SubViewport.new()
		vp.msaa_3d = Viewport.MSAA_2X
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		c.add_child(vp)
		var cm := Camera3D.new()
		cm.fov = CAM_FOV
		cm.near = 0.05
		cm.far = 100.0
		vp.add_child(cm)
		cm.current = true
		var lb := Label.new()
		lb.text = titles[i]
		lb.position = Vector2(10, 52)
		lb.add_theme_font_size_override("font_size", 22)
		lb.add_theme_color_override("font_color", Color(1, 1, 0.8))
		lb.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		lb.add_theme_constant_override("outline_size", 5)
		c.add_child(lb)
		panels.append({"cam": cm, "vp": vp})

func _update_cam(snap: bool) -> void:
	if panels.is_empty():
		return
	var dt := get_process_delta_time()
	if snap:
		cam_yaw_s = cam_ref_yaw
		cam_focus = actor.global_position + Vector3(0, 0.62, 0) + cam_off
	else:
		cam_yaw_s = lerp_angle(cam_yaw_s, cam_ref_yaw, 1.0 - exp(-3.0 * dt))
		cam_focus = cam_focus.lerp(actor.global_position + Vector3(0, 0.62, 0) + cam_off, 1.0 - exp(-14.0 * dt))
	var dir := Vector3(sin(cam_yaw_s), 0.0, cos(cam_yaw_s))
	var left := Vector3(cos(cam_yaw_s), 0.0, -sin(cam_yaw_s))
	var offs := [dir, left, -dir]
	for i in 3:
		var cm: Camera3D = panels[i]["cam"]
		cm.global_position = cam_focus + offs[i] * CAM_DIST + Vector3(0, 0.12, 0)
		cm.look_at(cam_focus, Vector3.UP)

func _tour_step(delta: float) -> void:
	super._tour_step(delta)
	if not shot_list.is_empty() and not shot_busy and tour_t - TOUR_START_DELAY >= float(shot_list[0]["t"]):
		var sh: Dictionary = shot_list.pop_front()
		_take_shots(sh)
	if tour_ix != last_seg and tour_ix >= 0:
		last_seg = tour_ix
		cam_ref_yaw = actor.rotation.y
	if stop_at > 0.0 and tour_t >= stop_at and not finished:
		_finish_tour()

# ---------------------------------------------------------------- 滑步標記
func _ankle_ground(n: String) -> Vector3:
	var i := sk.find_bone("mixamorig_" + n)
	var p := sk.global_transform * sk.get_bone_global_pose(i).origin
	return Vector3(p.x, 0.006, p.z)

func _spawn_markers(kind: String) -> void:
	for foot in ["LeftFoot", "RightFoot"]:
		var base := _ankle_ground(foot)
		var col := Color(0.1, 0.9, 1.0) if foot == "LeftFoot" else Color(1.0, 0.55, 0.1)
		var root := Node3D.new()
		add_child(root)
		root.global_position = base
		var disc := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.03
		cyl.bottom_radius = 0.03
		cyl.height = 0.006
		disc.mesh = cyl
		var mt := StandardMaterial3D.new()
		mt.albedo_color = col
		mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		disc.material_override = mt
		root.add_child(disc)
		var line := MeshInstance3D.new()
		var bx := BoxMesh.new()
		bx.size = Vector3(1, 0.006, 0.014)
		line.mesh = bx
		line.material_override = mt
		add_child(line)
		var lab := Label3D.new()
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lab.no_depth_test = true
		lab.font_size = 64
		lab.pixel_size = 0.0011
		lab.modulate = col
		lab.outline_size = 14
		add_child(lab)
		markers.append({"root": root, "line": line, "lab": lab, "foot": foot, "kind": kind, "base": base, "t0": tour_t, "max": 0.0, "cur": 0.0, "path": 0.0, "prev": base})

func _is_frozen(m: Dictionary) -> bool:
	var k := str(m["kind"])
	var age := tour_t - float(m["t0"])
	if k == "start":
		return combat.g >= 0.999 or age > 0.8
	if k == "stop" or k == "reverse":
		return combat.g <= 0.001 or (k == "stop" and not combat.stopping and age > 0.05) or age > 1.4
	return combat.state != 2 and age > 0.1        # turn

func _update_markers() -> void:
	var keep: Array = []
	for m in markers:
		var age := tour_t - float(m["t0"])
		var base: Vector3 = m["base"]
		if not m.get("frozen", false):
			var p := _ankle_ground(m["foot"])
			var d := Vector2(p.x - base.x, p.z - base.z).length()
			m["cur"] = d
			m["max"] = maxf(float(m["max"]), d)
			m["path"] += Vector2(p.x - (m["prev"] as Vector3).x, p.z - (m["prev"] as Vector3).z).length()
			m["prev"] = p
			if _is_frozen(m):
				m["frozen"] = true
		var q: Vector3 = m["prev"]
		var line: MeshInstance3D = m["line"]
		var mid := (q + base) * 0.5
		var dd := Vector2(q.x - base.x, q.z - base.z).length()
		line.global_position = mid
		line.global_basis = Basis(Vector3.UP, atan2(-(q.z - base.z), q.x - base.x)) * Basis.from_scale(Vector3(maxf(dd, 0.002), 1, 1))
		var lab: Label3D = m["lab"]
		lab.global_position = q + Vector3(0, 0.14 if m["foot"] == "LeftFoot" else 0.27, 0)
		var partner_max := -1.0
		for o in markers:
			if o != m and o["kind"] == m["kind"] and absf(float(o["t0"]) - float(m["t0"])) < 0.001:
				partner_max = float(o["max"])
		var tag := "" if partner_max < 0.0 else ("滑 " if float(m["max"]) <= partner_max else "步 ")
		lab.text = "%s%.0f cm" % [tag, float(m["max"]) * 100.0]
		if age > MARK_LIFE:
			slip_events.append({"kind": m["kind"], "foot": m["foot"], "t": float(m["t0"]) - TOUR_START_DELAY, "max_displacement_cm": snappedf(float(m["max"]) * 100.0, 0.1), "path_cm": snappedf(float(m["path"]) * 100.0, 0.1)})
			(m["root"] as Node).queue_free()
			line.queue_free()
			lab.queue_free()
		else:
			keep.append(m)
	markers = keep

func _check_update() -> void:
	if finished:
		return
	var g := combat.g
	var st := combat.state
	if prev_g <= 0.001 and g > 0.001 and st == 1:
		_spawn_markers("start")
	if combat.stopping and not prev_stopping:
		_spawn_markers("stop")
	if combat.label == "reverse" and prev_label != "reverse":
		_spawn_markers("reverse")
	if st == 2 and prev_state != 2 and str(combat.shot_key).begins_with("turn"):
		_spawn_markers(str(combat.shot_key))
	prev_g = g
	prev_stopping = combat.stopping
	prev_state = st
	prev_label = combat.label
	_update_markers()
	if pose_path != "" and tour_t >= TOUR_START_DELAY:
		var row := PackedFloat32Array()
		row.resize(sk.get_bone_count() * 12)
		var k := 0
		for i in sk.get_bone_count():
			var t := sk.get_bone_global_pose(i)
			var b := t.basis
			row[k] = b.x.x; row[k + 1] = b.y.x; row[k + 2] = b.z.x; row[k + 3] = t.origin.x
			row[k + 4] = b.x.y; row[k + 5] = b.y.y; row[k + 6] = b.z.y; row[k + 7] = t.origin.y
			row[k + 8] = b.x.z; row[k + 9] = b.y.z; row[k + 10] = b.z.z; row[k + 11] = t.origin.z
			k += 12
		pose_rows.append_array(row)
		pose_n += 1
		var li: Dictionary = combat.foot_lock.last_info
		for sd in ["Left", "Right"]:
			var e: Dictionary = li.get(sd, {})
			fl_rows.append_array(PackedFloat32Array([float(e.get("w", -1.0)), float(e.get("err_cm", 0.0)), float(e.get("spd", 0.0)), float(e.get("h_cm", 0.0))]))

func _build_tour() -> void:
	if OS.get_cmdline_user_args().has("--slash-tour"):
		super._build_tour()
		return
	var E := {"enemy": [0.0, 5.0, 0.01]}
	if OS.get_cmdline_user_args().has("--short"):      # 21 s 快測：前進→停→後退→停（袖口彈跳處）→左右閃避
		_s(2.0, "idle 待機", Vector2.ZERO, E)
		_s(3.6, "forward 前進", Vector2(0, 1))
		_s(1.8, "stop 停步")
		_s(3.6, "back 後退", Vector2(0, -1), E)
		_s(2.2, "stop 後退停步（袖口）")
		_s(1.5, "dodge left 閃避（左）", Vector2(-1, 0), {"dodge": 0.1, "hold": 0.25, "side": -1.0, "enemy": [0.0, 5.0, 0.01]})
		_s(1.6, "idle")
		_s(1.5, "dodge right 閃避（右）", Vector2(1, 0), {"dodge": 0.1, "hold": 0.25, "side": 1.0})
		_s(2.0, "idle end")
		return
	_s(2.0, "idle 待機", Vector2.ZERO, E)
	_s(3.6, "forward 前進", Vector2(0, 1))
	_s(1.8, "stop 停步")
	_s(3.6, "back 後退", Vector2(0, -1), E)
	_s(2.2, "stop 後退停步（左袖口彈跳處）")
	_s(2.6, "strafe left 左移", Vector2(-1, 0))
	_s(1.8, "stop 停步")
	_s(2.6, "strafe right 右移", Vector2(1, 0), E)
	_s(1.8, "stop 停步")
	_s(2.4, "diagonal fwd+left 左前", Vector2(-1, 1))
	_s(1.6, "stop 停步", Vector2.ZERO, E)
	_s(3.0, "enemy to the left → turn 90 左轉身", Vector2.ZERO, {"enemy": [95.0, 5.0, 0.2]})
	_s(1.4, "hold")
	_s(3.4, "enemy behind → turn 180 轉身", Vector2.ZERO, {"enemy": [170.0, 5.0, 0.2]})
	_s(1.4, "hold")
	_s(3.0, "enemy to the right → turn 90 右轉身", Vector2.ZERO, {"enemy": [-95.0, 5.0, 0.2]})
	_s(1.4, "hold")
	_s(1.5, "dodge left 閃避（左）", Vector2(-1, 0), {"dodge": 0.1, "hold": 0.25, "side": -1.0, "enemy": [0.0, 5.0, 0.01]})
	_s(1.6, "idle")
	_s(1.5, "dodge right 閃避（右）", Vector2(1, 0), {"dodge": 0.1, "hold": 0.25, "side": 1.0})
	_s(2.0, "idle end")

func _finish_tour() -> void:
	if finished:
		return
	finished = true
	for m in markers:
		slip_events.append({"kind": m["kind"], "foot": m["foot"], "t": float(m["t0"]) - TOUR_START_DELAY, "max_displacement_cm": snappedf(float(m["max"]) * 100.0, 0.1), "path_cm": snappedf(float(m["path"]) * 100.0, 0.1)})
	if slip_json != "":
		DirAccess.make_dir_recursive_absolute(slip_json.get_base_dir())
		var f := FileAccess.open(slip_json, FileAccess.WRITE)
		f.store_string(JSON.stringify({"events": slip_events, "segments": tour_meta}))
		f.close()
	if pose_path != "":
		DirAccess.make_dir_recursive_absolute(pose_path.get_base_dir())
		var f2 := FileAccess.open(pose_path + ".bin", FileAccess.WRITE)
		f2.store_buffer(pose_rows.to_byte_array())
		f2.close()
		var names := []
		for i in sk.get_bone_count():
			names.append(sk.get_bone_name(i))
		var ff := FileAccess.open(pose_path + ".fl.bin", FileAccess.WRITE)
		ff.store_buffer(fl_rows.to_byte_array())
		ff.close()
		var f3 := FileAccess.open(pose_path + ".json", FileAccess.WRITE)
		f3.store_string(JSON.stringify({"frames": pose_n, "bones": names, "start_delay": TOUR_START_DELAY, "fps": 60}))
		f3.close()
	super._finish_tour()

## 特寫截圖：四個方向（前／左／後／右）×（一般／袴半透明 X 光），距離 1.0 m，FOV 34°，只含 3D（不含 HUD）。
func _take_shots(sh: Dictionary) -> void:
	shot_busy = true
	get_tree().paused = true      # 凍結模擬：八張圖是同一瞬間
	DirAccess.make_dir_recursive_absolute(shot_dir)
	var focus: Vector3 = sk.global_transform * (sh["focus"] as Vector3)
	var yw := actor.rotation.y
	var dirs := {"front": Vector3(sin(yw), 0, cos(yw)), "left": Vector3(cos(yw), 0, -sin(yw)), "back": -Vector3(sin(yw), 0, cos(yw)), "right": -Vector3(cos(yw), 0, -sin(yw))}
	var hak := rig.find_child("袴", true, false) as GeometryInstance3D
	for xray in [false, true]:
		if hak:
			hak.transparency = 0.7 if xray else 0.0
		for view in dirs:
			var vp := SubViewport.new()
			vp.size = Vector2i(800, 800)
			vp.msaa_3d = Viewport.MSAA_4X
			vp.render_target_update_mode = SubViewport.UPDATE_ONCE
			add_child(vp)
			var cm := Camera3D.new()
			cm.fov = 34.0
			cm.near = 0.03
			vp.add_child(cm)
			cm.current = true
			cm.global_position = focus + (dirs[view] as Vector3) * 1.0
			cm.look_at(focus, Vector3.UP)
			await RenderingServer.frame_post_draw
			vp.get_texture().get_image().save_png("%s/%s_%s_%s.png" % [shot_dir, sh["name"], view, "xray" if xray else "normal"])
			vp.queue_free()
	if hak:
		hak.transparency = 0.0
	# 純色遮擋量測：A = 羽織紅／袴藍／身體綠／其他深灰（全不打光、雙面）；B = 只留羽織。比較 B 的輪廓有多少在 A 裡被蓋住。
	var meshes := sk.find_children("*", "MeshInstance3D", false, false)
	var hid: Array = []
	for m in markers:
		for k in ["root", "line", "lab"]:
			var n3 := m[k] as Node3D
			hid.append([n3, n3.visible])
			n3.visible = false
	for n in ["Sword_Hand", "Sheath"]:
		var nd := rig.find_child(n, true, false) as Node3D
		if nd:
			hid.append([nd, nd.visible])
			nd.visible = false
	var cols := {"羽織": Color(1, 0, 0), "袴": Color(0, 0, 1), "身體": Color(0, 1, 0)}
	for pass_name in ["flatA", "flatB"]:
		for mi in meshes:
			var mm := mi as MeshInstance3D
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			mat.albedo_color = cols.get(str(mm.name), Color(0.25, 0.25, 0.25))
			mm.material_override = mat
			mm.visible = (pass_name == "flatA") or (str(mm.name) == "羽織")
		for view in dirs:
			var vp2 := SubViewport.new()
			vp2.size = Vector2i(800, 800)
			vp2.msaa_3d = Viewport.MSAA_DISABLED
			vp2.render_target_update_mode = SubViewport.UPDATE_ONCE
			add_child(vp2)
			var cm2 := Camera3D.new()
			cm2.fov = 34.0
			cm2.near = 0.03
			vp2.add_child(cm2)
			cm2.current = true
			cm2.global_position = focus + (dirs[view] as Vector3) * 1.0
			cm2.look_at(focus, Vector3.UP)
			await RenderingServer.frame_post_draw
			vp2.get_texture().get_image().save_png("%s/%s_%s_%s.png" % [shot_dir, sh["name"], view, pass_name])
			vp2.queue_free()
	for mi in meshes:
		var mm2 := mi as MeshInstance3D
		mm2.material_override = null
		mm2.visible = true
	for h in hid:
		(h[0] as Node3D).visible = h[1]
	get_tree().paused = false
	shot_busy = false

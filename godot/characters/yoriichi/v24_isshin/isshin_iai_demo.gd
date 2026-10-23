extends "res://characters/yoriichi/v24_isshin/isshin_slash_demo.gd"
## 葦名流居合候選（獨立候選；不改正式 Player／跑酷／共用資產）：居合構（刀在鞘）→ K／J／左鍵＝拔刀橫斬 → 命中 → 納刀 → 回居合構。
## 動作：c1400「剣客_居合」a100_003021（佐瀬甚助／水生氏成共用），拔刀與納刀已改成刀身經過緣一自己的鞘口（notes/build_iai.py）。
## 刀的顯示：鞘中刀＝正式 R6.2 場景 Sword_Sheathed 的 transform（只讀）＋同一支 sword_hilt_only 著色器；手上的刀在出鞘／入鞘途中
## 用同一個著色器把「還在鞘裡的那段刀身」藏起來（clip_y＝刀柄＋已出鞘長度），逐格資料在 anims/isshin_iai_sword.json。
## 自動導覽：godot --path godot --write-movie out.avi --fixed-fps 60 res://characters/yoriichi/v24_isshin/isshin_iai_demo.tscn -- --tour [--dist=2.3]
const HILT_SHADER := preload("res://characters/yoriichi/sheath_v2/sword_hilt_only.gdshader")
const HILT_SCRIPT := preload("res://characters/yoriichi/sheath_v2/sword_hilt_only.gd")
const SWORD_GLB := preload("res://characters/yoriichi/yoriichi_sword.glb")
const R62 := "res://characters/yoriichi/player_yoriichi_r62.tscn"

var sword_sheathed: Node3D
var hand_mats: Array = []
var iai_track: Dictionary = {}
var vis_log: Array = []

func _ready() -> void:
	super._ready()
	combat.set_iai_mode(true)
	# 調參用：--iai_cfg='{"aim_offset": -25, "min_dist": 0.6}'（JSON，覆寫 SHOTS["iai"] 的部分欄位）
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--iai_cfg="):
			combat.shot_override["iai"] = JSON.parse_string(a.substr(10))
	# 鞘中刀：transform 取自正式 R6.2 場景（只讀 SceneState，不實例化、不修改）
	var t_ss := Transform3D.IDENTITY
	var st := (load(R62) as PackedScene).get_state()
	for i in st.get_node_count():
		if st.get_node_name(i) == "Sword_Sheathed":
			for j in st.get_node_property_count(i):
				if st.get_node_property_name(i, j) == "transform":
					t_ss = st.get_node_property_value(i, j)
	var sheath := rig.find_child("Sheath", true, false) as Node3D
	sword_sheathed = SWORD_GLB.instantiate() as Node3D
	sword_sheathed.name = "Sword_Sheathed"
	sword_sheathed.set_script(HILT_SCRIPT)
	sheath.get_parent().add_child(sword_sheathed)
	sword_sheathed.transform = t_ss
	if "sway_gain" in sheath:
		sheath.set("sway_gain", 0.0)          # 居合中鞘不甩（拔刀／納刀的鞘口位置以靜止的鞘為準）
	# 手上的刀：同一支著色器，clip_y 由逐格資料驅動
	for mi in sword.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var src := m.get_active_material(0) as StandardMaterial3D
		var sm := ShaderMaterial.new()
		sm.shader = HILT_SHADER
		sm.set_shader_parameter("clip_y", 10.0)
		if src != null:
			sm.set_shader_parameter("albedo_tex", src.albedo_texture)
			sm.set_shader_parameter("albedo_color", src.albedo_color)
			sm.set_shader_parameter("normal_tex", src.normal_texture)
			sm.set_shader_parameter("use_normal", src.normal_enabled and src.normal_texture != null)
			sm.set_shader_parameter("orm_tex", src.roughness_texture)
			sm.set_shader_parameter("roughness", src.roughness)
			sm.set_shader_parameter("metallic", src.metallic)
		m.material_override = sm
		hand_mats.append(sm)
	iai_track = JSON.parse_string(FileAccess.get_file_as_string("res://characters/yoriichi/v24_isshin/anims/isshin_iai_sword.json"))
	_apply_sword_vis()

func _process(delta: float) -> void:
	# 漏判測試用：--enemy_drift=vx,vz（m/s，世界座標）＝出招期間木樁小幅移動（停格中不動）
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--enemy_drift=") and combat.state == combat.S.SHOT and combat.hitstop_left == 0:
			var v := a.substr(14).split(",")
			enemy_pos += Vector3(float(v[0]), 0.0, float(v[1])) * delta
	# 判定時「這一幀」的刀＝上一幀骨架更新後的姿勢；「上一幀」＝再前一幀（_process 結尾記下）
	_blade_prev = _blade_last
	super._process(delta)
	if sword:
		_blade_last = [sword.global_transform * GUARD_LOCAL, sword.global_transform * TIP_LOCAL]
	_apply_sword_vis()

## 命中判定（只在居合候選內覆寫）：用木樁網格的實際半徑（圓柱底 0.26／頂 0.22，頭球 0.20），只算刀身（u ≥ 0.25，不含刀柄、護手、
## 握刀的手），且要切進表面 HIT_MIN_DEPTH；回傳的位置＝最深那一點徑向投到木樁表面（刀刃切進木樁的地方），火花就放在那裡。
const HIT_MIN_DEPTH := 0.05     # 刀刃要切進木樁表面至少 5 cm 才算命中（停格那一格看得到刀在木樁裡，而不是刀尖剛擦到）

func _hit_test() -> Dictionary:
	if OS.get_cmdline_user_args().has("--legacy_hit"):      # 比較用：v1 的判定（半徑 0.30、從護手算起）
		return super._hit_test()
	if sword == null:
		return {}
	var m := sword.global_transform
	var a1 := m * GUARD_LOCAL
	var b1 := m * TIP_LOCAL
	# 掃掠：上一幀到這一幀之間再補 3 個中間位置（低幀率時刀一幀走 20–30 cm，只檢查幀上的位置會漏掉）；範圍本身不變
	var a0: Vector3 = _blade_prev[0] if _blade_prev.size() == 2 else a1
	var b0: Vector3 = _blade_prev[1] if _blade_prev.size() == 2 else b1
	var best := 0.0
	var hit := {}
	for k in range(1, 5):
		var w := float(k) / 4.0
		var a := a0.lerp(a1, w)
		var b := b0.lerp(b1, w)
		for i in range(4, 17):
			var u := float(i) / 16.0
			var p := a.lerp(b, u)
			var hv := Vector2(p.x - enemy_pos.x, p.z - enemy_pos.z)
			var r := 0.26 - 0.025 * clampf(p.y, 0.0, 1.6)
			if p.y > 1.6:
				r = sqrt(maxf(0.0, 0.04 - pow(p.y - 1.75, 2.0)))
			var depth := r - hv.length()
			if p.y > 0.05 and p.y < 1.95 and depth > maxf(best, HIT_MIN_DEPTH):
				best = depth
				var n := hv.normalized() if hv.length() > 1e-3 else Vector2(0, -1)
				var surf := Vector3(enemy_pos.x + n.x * r, p.y, enemy_pos.z + n.y * r)
				var dv := tip_v.normalized() if tip_v.length() > 0.5 else Vector3.DOWN
				hit = {"pos": surf, "dir": dv, "tip_speed": tip_speed, "blade_u": u, "depth": depth, "sub": w}
		if not hit.is_empty():
			break                # 取最早切入的那個中間位置
	return hit

var _blade_prev: Array = []     # 上一次判定時的刀（護手、刀尖）世界座標
var _blade_last: Array = []

func _on_hit(info: Dictionary) -> void:
	super._on_hit(info)
	var last: Dictionary = slash_hits[slash_hits.size() - 1]
	last["blade_u"] = info.get("blade_u", -1.0)
	last["depth"] = info.get("depth", -1.0)
	last["probe"] = _contact_probe()

## 火花：沿用同一個效果，只把最大尺寸從直徑約 1.0 m 縮到 0.5 m（原本會整團蓋住刀身與手）
func _spark(p: Vector3) -> void:
	if OS.get_cmdline_user_args().has("--legacy_hit"):
		super._spark(p)
		return
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.09
	sm.height = 0.18
	mi.mesh = sm
	var mt := StandardMaterial3D.new()
	mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mt.albedo_color = Color(1.0, 0.85, 0.5)
	mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mt.no_depth_test = false
	mi.material_override = mt
	add_child(mi)
	mi.global_position = p
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(2.8, 2.8, 2.8), 0.15)
	tw.tween_property(mt, "albedo_color:a", 0.0, 0.15)
	tw.chain().tween_callback(mi.queue_free)

func _apply_sword_vis() -> void:
	var mode := "sheathed"
	var clip := 10.0
	if combat.state == combat.S.SHOT and combat.shot_key == "iai" and not iai_track.is_empty():
		var frames: Array = iai_track["frames"]
		var f := clampi(int(round(combat.shot_t * float(iai_track["fps"]))), 0, frames.size() - 1)
		mode = str(frames[f]["mode"])
		clip = float(frames[f]["clip_y"])
	elif not combat.iai_mode:
		mode = "hand"
	sword.visible = mode == "hand"
	sword_sheathed.visible = mode == "sheathed"
	for sm in hand_mats:
		(sm as ShaderMaterial).set_shader_parameter("clip_y", clip if mode == "hand" else 10.0)
	if tour and tour_t >= TOUR_START_DELAY and combat.shot_key == "iai" and combat.state == combat.S.SHOT:
		var hs := sword.global_transform
		var ss := sword_sheathed.global_transform
		vis_log.append({"t": snappedf(tour_t - TOUR_START_DELAY, 0.0001), "shot_t": snappedf(combat.shot_t, 0.0001), "mode": mode, "clip_y": clip,
			"gap_mm": snappedf(hs.origin.distance_to(ss.origin) * 1000.0, 0.1),
			"ang_deg": snappedf(rad_to_deg(hs.basis.orthonormalized().get_rotation_quaternion().angle_to(ss.basis.orthonormalized().get_rotation_quaternion())), 0.1),
			"probe": _contact_probe()})

## 命中檢查用：世界座標的護手／刀尖／右手／木樁中心，以及刀身上每 1/16 段離木樁軸的水平距離（m）
func _contact_probe() -> Dictionary:
	var m := sword.global_transform
	var g := m * GUARD_LOCAL
	var tp := m * TIP_LOCAL
	var gsk := sk.global_transform
	var rh := gsk * sk.get_bone_global_pose(sk.find_bone("mixamorig_RightHand")).origin
	var rf := gsk * sk.get_bone_global_pose(sk.find_bone("mixamorig_RightForeArm")).origin
	var lh := gsk * sk.get_bone_global_pose(sk.find_bone("mixamorig_LeftHand")).origin
	var ds: Array = []
	for i in 17:
		var p := g.lerp(tp, float(i) / 16.0)
		ds.append(snappedf(Vector2(p.x - enemy_pos.x, p.z - enemy_pos.z).length(), 0.001))
	var v3 := func(v: Vector3) -> Array: return [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)]
	return {"guard": v3.call(g), "tip": v3.call(tp), "rhand": v3.call(rh), "relbow": v3.call(rf), "lhand": v3.call(lh), "lhand_d": snappedf(Vector2(lh.x - enemy_pos.x, lh.z - enemy_pos.z).length(), 0.001), "dummy": v3.call(enemy_pos),
		"actor": v3.call(actor.global_position), "rhand_d": snappedf(Vector2(rh.x - enemy_pos.x, rh.z - enemy_pos.z).length(), 0.001),
		"blade_d": ds, "cam": v3.call(cam.global_position)}

## 相機：居合在左腰拔刀，背後偏右肩的相機會被身體擋住 → 改從左前斜側看（角色與木樁都在畫面內）
var _side_cam_set := false
var _side_locked := false

func _update_cam(snap: bool) -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--cam=third"):           # 遊戲用的第三人稱（身後偏右肩）
		super._update_cam(snap)
		return
	if args.has("--cam=side"):
		# 側面：每次出招時定一次、整招固定。方向＝垂直於「命中瞬間角色→木樁」連線（出招時的連線往右轉約 24°：aim_offset 讓身體
		# 先轉向左前、再沿身體方向前衝），站在連線右手側（刀在角色右側），角色與木樁在畫面上左右分開、不互相前後遮擋
		var firing := combat.state == combat.S.SHOT and combat.shot_key == "iai"
		if not _side_cam_set or (firing and not _side_locked):
			_side_cam_set = true
			_side_locked = firing
			var a0 := actor.global_position
			var to := enemy_pos - a0
			to.y = 0.0
			var yaw := atan2(to.x, to.z) - deg_to_rad(24.0)
			var dir := Vector3(sin(yaw), 0, cos(yaw))
			var right := Vector3(-cos(yaw), 0, sin(yaw))
			var midp := enemy_pos - dir * 0.45 + Vector3(0, 0.95, 0)
			var rot := deg_to_rad(30.0)     # 預設往正面轉 30°：刀進木樁、兩手與木樁之間看得到空隙（四個角度比較後選的）
			for a in args:
				if a.begins_with("--side_rot="):
					rot = deg_to_rad(float(a.substr(11)))     # + ＝相機往角色正面方向轉
			var cdir := right.rotated(Vector3.UP, -rot)
			cam.global_position = midp + cdir * 4.0 + Vector3(0, 0.55, 0)
			cam.look_at(midp, Vector3.UP)
		if not firing:
			_side_locked = false
		return
	var pp := actor.global_position
	var fwd := Vector3(sin(actor.rotation.y), 0.0, cos(actor.rotation.y))
	var left := Vector3.UP.cross(fwd).normalized()      # actor +X＝角色左手邊
	var mid := pp + fwd * 0.9 + Vector3(0, 1.0, 0)
	var want := mid + (left * 3.6 + fwd * 0.6) + Vector3(0, 0.5, 0)
	if OS.get_cmdline_user_args().has("--closecam"):        # 檢查用：左腰拔刀特寫
		mid = pp + fwd * 0.2 + Vector3(0, 0.95, 0)
		want = mid + left * 1.7 + fwd * 0.9 + Vector3(0, 0.25, 0)
	if OS.get_cmdline_user_args().has("--frontcam"):        # 檢查用：正前偏左上看腰間（拔刀／納刀）
		mid = pp + Vector3(0, 0.95, 0) + left * 0.15
		want = pp + fwd * 1.5 + left * 0.9 + Vector3(0, 1.6, 0)
	if snap or OS.get_cmdline_user_args().has("--frontcam"):
		cam.global_position = want
	else:
		cam.global_position = cam.global_position.lerp(want, 1.0 - exp(-6.0 * get_process_delta_time()))
	cam.look_at(mid, Vector3.UP)

func _build_tour() -> void:
	var dist := enemy_dist
	var ang := 0.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--enemy_ang="):         # 漏判測試用：木樁偏離正前方的角度（度）
			ang = float(a.substr(12))
	var E := {"enemy": [ang, dist, 0.01]}
	_s(1.2, "葦名流居合：居合構（刀在鞘）", Vector2.ZERO, E)
	_s(2.6, "拔刀橫斬 → 命中 → 納刀", Vector2.ZERO, {"attack": 0.3})
	_s(0.8, "居合構", Vector2.ZERO, E)
	_s(2.6, "再一次（拔刀 0.10 s 出鞘，判定 0.23–0.33 s）", Vector2.ZERO, {"attack": 0.2})
	_s(0.8, "居合構", Vector2.ZERO, {"enemy": [0.0, dist + 1.6, 0.01]})
	_s(2.6, "距離不夠＝空揮，仍完整納刀", Vector2.ZERO, {"attack": 0.2})
	_s(0.8, "居合構")

func _finish_tour() -> void:
	if slashlog_path != "":
		var f := FileAccess.open(slashlog_path.get_basename() + "_vis.json", FileAccess.WRITE)
		f.store_string(JSON.stringify(vis_log))
		f.close()
	super._finish_tour()

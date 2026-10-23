extends "res://characters/yoriichi/v24_isshin/r10/r10_combat_demo.gd"
## 緣一 R11 試玩：日之呼吸・貳ノ型 碧羅天 實戰化（候選 ART_REVIEW；R10 場景與資料原樣保留，正式 Player／跑酷／正式場景不動）。
## 一、碧羅天改用 R11 動作（anims/isshin_sun_hekira_r11.res）：一心 c5400 a000_003031 時間重配，刀由身體轉動帶出一個完整的圓
##     （前下→頭頂→背後→左側→袈裟斬過正面到右下→右後方），雙手、著地。資料：r11/sun_breathing_r11.json（notes/r11/gen_r11_data.py）。
##     火焰＝R9-C3 L1 系統（C2 流焰＋C1 命中爆燃），沿 R11 實測刀路重建的 r9c/enbu_vfx_HK11.glb。
## 二、輸入緩衝：命中停格期間緩衝不老化（停格吃掉的時間不算進 0.20 s 緩衝窗；接招仍依動畫進度 shot_t 判斷）。
## 三、位移碰撞：角色每幀的位移（走路、出招根位移、前衝）經一個膠囊 CharacterBody3D（半徑 0.3 m）對牆面層掃掠，
##     撞牆就沿牆滑、不穿過去；木樁不在這一層（最小距離另由招式控制）。場景放了一面試驗牆（世界 x=-5、z=4）。
const R11_DIR := "res://characters/yoriichi/v24_isshin/r11/"
const WALL_LAYER := 1 << 4
var r11_buffer_hitstop_freeze := true
var _proxy: CharacterBody3D
var _last_pos := Vector3.INF
var col_log: Array = []
var frame_log: Array = []
var _flog := false
var _wall_spec := ""

func _pre_setup() -> void:
	super._pre_setup()
	combat.smooth_stance = true
	sun = JSON.parse_string(FileAccess.get_file_as_string(R11_DIR + "sun_breathing_r11.json"))
	skills = sun["skills"]
	skill_order = sun.get("order", skills.keys())
	cur_skill = "sun_hekiraten" if skills.has("sun_hekiraten") else str(skill_order[0])
	for k in skills:
		combat.extra_shots[k] = _clean(skills[k]["shot"])

func _build_world() -> void:                    # （基底 _ready 先建世界、後 _pre_setup，所以命令列在這裡讀）
	for a in OS.get_cmdline_user_args():
		if a == "--r11log":
			_flog = true
		elif a.begins_with("--wall="):          # 測試用：--wall=前方距離（m），在角色起點正前方放一面牆
			_wall_spec = a.substr(7)
		elif a == "--no-buffer-freeze":
			r11_buffer_hitstop_freeze = false
	super._build_world()
	_add_wall(Vector3(-5.0, 0.0, 4.0), 0.0, Vector3(4.0, 2.2, 0.25))
	if _wall_spec != "":
		_add_wall(Vector3(0.0, 0.0, float(_wall_spec) + 0.125), 0.0, Vector3(6.0, 2.2, 0.25))
	_proxy = CharacterBody3D.new()
	_proxy.name = "MoveProxy"
	_proxy.collision_layer = 0
	_proxy.collision_mask = WALL_LAYER
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.7
	cs.shape = cap
	cs.position = Vector3(0, 0.85, 0)
	_proxy.add_child(cs)
	add_child(_proxy)

func _add_wall(pos: Vector3, yaw: float, size: Vector3) -> void:
	var sb := StaticBody3D.new()
	sb.name = "R11Wall"
	sb.collision_layer = WALL_LAYER
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = size
	cs.shape = bx
	cs.position = Vector3(0, size.y * 0.5, 0)
	sb.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = cs.position
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.33, 0.24)
	mi.material_override = mat
	sb.add_child(mi)
	sb.position = pos
	sb.rotation.y = yaw
	add_child(sb)

## 碧羅天收勢低身側身，取消接普通劍術時交叉淡入加長到 0.16 s（預設 0.08 s 時髖部 0.08 s 內抬 0.3 m）
func _router(ctx: String) -> String:
	var from := combat.shot_key if combat.state == combat.S.SHOT else ""
	var k := super._router(ctx)
	if ctx == "cancel" and from == "sun_hekiraten" and k != "":
		combat.fire_opts["fade_in"] = 0.16
	return k

## 刀在鞘中按呼吸＝先拔刀再出招：拔刀結束時待機姿勢還在由居合構淡回持刀（0.2 s），技能淡入改 0.2 s 跟著走（0.08 s 時髖部一格 4 m/s）
func _fire_pending() -> void:
	if skills.has(pending_key) or skills.has(_my_pending):
		combat.fire_opts["fade_in"] = 0.2
	super._fire_pending()

## 停格中緩衝不老化：基底每幀 now += delta，停格這幾幀把各緩衝時間戳一起往後推
func _filter_input(delta: float, dodge: bool, attack: bool) -> Array:
	if r11_buffer_hitstop_freeze and combat.hitstop_left > 0:
		for k in buf:
			if float(buf[k]) > -9.0:
				buf[k] = float(buf[k]) + delta
	return super._filter_input(delta, dodge, attack)

## 位移碰撞：這一幀控制器給的水平位移，經膠囊對牆面層掃掠（沿牆滑動，最多 3 次）
func _after_step(delta: float) -> void:
	super._after_step(delta)
	if _proxy == null:
		return
	var p := actor.global_position
	if _last_pos == Vector3.INF:
		_last_pos = p
	var want := Vector3(p.x - _last_pos.x, 0.0, p.z - _last_pos.z)
	_proxy.global_position = Vector3(_last_pos.x, p.y, _last_pos.z)
	var m := want
	var hit := false
	for _i in 3:
		if m.length() < 1e-6:
			break
		var c := _proxy.move_and_collide(m)
		if c == null:
			break
		hit = true
		m = c.get_remainder().slide(c.get_normal())
	if hit:
		var np := Vector3(_proxy.global_position.x, p.y, _proxy.global_position.z)
		if tour and slashlog_path != "":
			col_log.append({"t": snappedf(tour_t - TOUR_START_DELAY, 0.001), "shot": combat.shot_key if combat.state == combat.S.SHOT else "", "want": [snappedf(want.x, 0.0001), snappedf(want.z, 0.0001)], "got": [snappedf(np.x - _last_pos.x, 0.0001), snappedf(np.z - _last_pos.z, 0.0001)], "pos": [snappedf(np.x, 0.001), snappedf(np.z, 0.001)]})
		actor.global_position = np
	_last_pos = actor.global_position
	if _flog and tour:
		var sk := actor.get_node("BodyVisual/緣一_fbx/Armature/Skeleton3D") as Skeleton3D
		var rec := {"t": snappedf(tour_t - TOUR_START_DELAY, 0.0001), "dt": snappedf(delta, 0.0001), "st": combat.state, "shot": combat.shot_key if combat.state == combat.S.SHOT else "", "shot_t": snappedf(combat.shot_t, 0.0001), "hs": combat.hitstop_left,
			"pos": [snappedf(actor.global_position.x, 0.0001), snappedf(actor.global_position.z, 0.0001)], "yaw": snappedf(actor.rotation.y, 0.0001), "ws": wstate(), "weapon": weapon, "label": cur_label}
		_bone_rec(rec)                       # 先記一次（若這一幀骨架之後才更新，skeleton_updated 會覆寫成同一幀的姿勢）
		rec["_pending"] = true
		rec["enemy"] = [snappedf(enemy.global_position.x, 0.001), snappedf(enemy.global_position.z, 0.001)]
		rec["hp"] = dummy_hp
		rec["atk_w"] = snappedf(combat.atk_w, 0.001)
		rec["oneshot"] = bool(combat.tree.get("parameters/shot/active"))
		rec["g"] = snappedf(combat.g, 0.001)
		rec["iai"] = combat.iai_mode
		frame_log.append(rec)

## 導覽段 g＝秒：這段開始後幾秒按 G（拔刀／納刀；測試用）
var _g_at := -1.0
func _tour_step(delta: float) -> void:
	var prev := tour_ix
	super._tour_step(delta)
	if tour_ix != prev and tour_ix >= 0 and tour_ix < tour_steps.size() and tour_steps[tour_ix].has("g"):
		_g_at = tour_t + float(tour_steps[tour_ix]["g"])
	if _g_at >= 0.0 and tour_t >= _g_at and combat.state != combat.S.SHOT:
		_g_at = -1.0
		pending_key = ""
		combat._fire("draw" if weapon == "sheathed" else "noto", 0.0)

## 骨架姿勢與角色位置要取同一幀：在 skeleton_updated（動畫＋修改器都套用完）時重記骨頭與刀
func _bone_rec(rec: Dictionary) -> void:
	var skl := actor.get_node("BodyVisual/緣一_fbx/Armature/Skeleton3D") as Skeleton3D
	for b in ["mixamorig_Hips", "mixamorig_LeftToeBase", "mixamorig_RightToeBase", "mixamorig_Head"]:
		var gp := skl.global_transform * skl.get_bone_global_pose(skl.find_bone(b)).origin
		rec[b.replace("mixamorig_", "")] = [snappedf(gp.x, 0.0001), snappedf(gp.y, 0.0001), snappedf(gp.z, 0.0001)]
	var sx := sword.global_transform
	var tip := sx * TIP_LOCAL
	var grd := sx * GUARD_LOCAL
	rec["tip"] = [snappedf(tip.x, 0.0001), snappedf(tip.y, 0.0001), snappedf(tip.z, 0.0001)]
	rec["guard"] = [snappedf(grd.x, 0.0001), snappedf(grd.y, 0.0001), snappedf(grd.z, 0.0001)]
	rec["pos_at_pose"] = [snappedf(actor.global_position.x, 0.0001), snappedf(actor.global_position.z, 0.0001)]

func _on_skel_updated_r11() -> void:
	if _flog and not frame_log.is_empty() and frame_log[-1].get("_pending", false):
		_bone_rec(frame_log[-1])
		frame_log[-1].erase("_pending")
		frame_log[-1]["late"] = true

func _ready() -> void:
	super._ready()
	if _flog:
		sk.skeleton_updated.connect(_on_skel_updated_r11)

func _finish_tour() -> void:
	if slashlog_path != "":
		var f := FileAccess.open(slashlog_path.get_basename() + "_r11.json", FileAccess.WRITE)
		f.store_string(JSON.stringify({"col": col_log, "frames": frame_log}))
		f.close()
	super._finish_tour()

func _hud_text() -> String:
	return super._hud_text().replace("緣一 R10 綜合戰鬥試玩", "緣一 R11 碧羅天試玩")

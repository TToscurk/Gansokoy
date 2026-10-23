extends "res://characters/yoriichi/v24_isshin/isshin_combat_demo.gd"
## 緣一 × 一心 斬擊原型（獨立候選；不改正式 Player／跑酷／共用資產）：第一刀 TAE 3038 縱斬；第一刀途中再按＝接 TAE 3071 橫斬（兩刀連段）。
## 操作：J 或滑鼠左鍵＝斬擊（第一刀開始後 0.10～0.70 s 內再按＝接第二刀）；其餘同戰鬥警戒步行（W/S/A/D、Shift+W、Space、←/→、O、Q/E、F、R、Esc）。
## 自動導覽（錄影）：godot --path godot --write-movie out.avi --fixed-fps 60 res://characters/yoriichi/v24_isshin/isshin_slash_demo.tscn -- --tour [--slashlog=P.json] [--dist=2.4] [--hitstop=3|5] [--no-audio]
const TIP_LOCAL := Vector3(0, 1.085, 0)       # Sword_Hand 本地座標：刀尖（刀模型 AABB y −0.38…1.085，Sword_Hand 縮放 0.68）
const GUARD_LOCAL := Vector3(0, 0.0, 0)
const DUMMY_RADIUS := 0.30
const REACT_T := 0.55
const PUSH_M := 0.15          # 受擊瞬間的視覺推移（之後回位）；實際位移由 KNOCK_M 擊退負責
const KNOCK_M := [0.0, 0.6, 0.45]   # 擊退（依第幾刀）：縱斬原地受擊；橫斬擊退 0.6 m、第三刀 0.45 m（沿「角色→木樁」方向，0.12 s 內滑到並停在新位置）（研究文件第 5 層：擊退約 0.5 m），讓下一刀的前衝有空間
const TILT_DEG := 20.0

var sword: Node3D
var audio: CharacterAudio
var dummy_t := -1.0
var dummy_dir := Vector3.FORWARD
var enemy_dist := 2.4
var _hitstop_arg := -1
var tip_prev := Vector3.ZERO
var tip_v := Vector3.ZERO
var tip_speed := 0.0
var slog: Array = []
var slash_hits: Array = []
var slashlog_path := ""
var enemy_kids: Array = []
var use_audio := true
var knock_t := -1.0
var knock_from := Vector3.ZERO
var knock_to := Vector3.ZERO
var dummy_hp := 10            # 木樁血量（每次命中扣 1；用來確認停格中不會重複扣血）
## R9：共用刀身命中判定（blade_hit_judge.gd）。所有候選場景預設都用它（命中結果不因場景而不同）；
## --judge=scene＝改回各場景自己的舊判定（回歸比較用）。
const BladeJudge = preload("res://characters/yoriichi/v24_isshin/blade_hit_judge.gd")
var judge = BladeJudge.new()
var judge_mode := "shared"

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dist="):
			enemy_dist = float(a.substr(7))
		elif a.begins_with("--slashlog="):
			slashlog_path = a.substr(11)
		elif a == "--no-audio":
			use_audio = false
		elif a.begins_with("--hitstop="):
			_hitstop_arg = int(a.substr(10))
	enemy_pos = Vector3(0, 0, enemy_dist)
	super._ready()
	enemy_pos = Vector3(0, 0, enemy_dist)
	sword = rig.find_child("Sword_Hand", true, false) as Node3D
	if use_audio:
		audio = CharacterAudio.new()
		audio.name = "CharacterAudio"
		add_child(audio)
	for c in enemy.get_children():
		enemy_kids.append([c, (c as Node3D).position])
	if OS.get_cmdline_user_args().has("--no-grip") and combat.grip:
		combat.grip.ik.queue_free()
		combat.grip.queue_free()
		combat.grip = null
	if OS.get_cmdline_user_args().has("--judge=scene"):
		judge_mode = "scene"
	combat.hit_test = _shared_hit_test if judge_mode == "shared" else _hit_test
	if _hitstop_arg >= 0:
		combat.hitstop_frames = _hitstop_arg
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mindist="):
			combat.attack_min_dist = float(a.substr(10))
	combat.swing_started.connect(_on_swing)
	combat.hit_landed.connect(_on_hit)
	sk.skeleton_updated.connect(_slash_update)

func _hit_test() -> Dictionary:
	if sword == null:
		return {}
	var m := sword.global_transform
	var a := m * GUARD_LOCAL
	var b := m * TIP_LOCAL
	for i in 17:
		var p := a.lerp(b, float(i) / 16.0)
		var h := Vector2(p.x - enemy_pos.x, p.z - enemy_pos.z).length()
		if h < DUMMY_RADIUS and p.y > 0.05 and p.y < 1.85:
			var dv := tip_v.normalized() if tip_v.length() > 0.5 else Vector3.DOWN
			return {"pos": p, "dir": dv, "tip_speed": tip_speed}
	return {}

func _shared_hit_test() -> Dictionary:
	if sword == null:
		return {}
	var cfg: Dictionary = combat._cfg(combat.shot_key)
	return judge.test(sword.global_transform, enemy_pos, combat.shot_t, get_process_delta_time(), cfg.get("strikes", []), tip_v, tip_speed)

func _on_swing(_idx: int) -> void:
	if audio:
		audio.play_heavy_swing()

func _on_hit(info: Dictionary) -> void:
	if audio:
		audio.play_hit(true)
	var d: Vector3 = info["dir"]
	d.y = 0.0
	dummy_dir = d.normalized() if d.length() > 0.05 else (enemy_pos - actor.global_position).normalized()
	dummy_t = 0.0
	dummy_hp -= 1
	var kd := enemy_pos - actor.global_position
	kd.y = 0.0
	var km: float = KNOCK_M[mini(int(info.get("strike", 0)), KNOCK_M.size() - 1)]
	if kd.length() > 0.01 and km > 0.0:
		knock_from = enemy_pos
		knock_to = enemy_pos + kd.normalized() * km
		knock_t = 0.0
	var a_to := enemy_pos - actor.global_position
	a_to.y = 0.0
	slash_hits.append({"t": tour_t - TOUR_START_DELAY, "pos": [info["pos"].x, info["pos"].y, info["pos"].z], "tip_speed": info["tip_speed"], "shot_t": info["shot_t"],
		"strike": info.get("strike", 0), "key": info.get("key", ""), "hp_after": dummy_hp, "dist": a_to.length(), "label": cur_label})
	_spark(info["pos"])

func _spark(p: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.18
	sm.height = 0.36
	mi.mesh = sm
	var mt := StandardMaterial3D.new()
	mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mt.albedo_color = Color(1.0, 0.85, 0.5)
	mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mt
	add_child(mi)
	mi.global_position = p
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(2.8, 2.8, 2.8), 0.15)
	tw.tween_property(mt, "albedo_color:a", 0.0, 0.15)
	tw.chain().tween_callback(mi.queue_free)

func _process(delta: float) -> void:
	if knock_t >= 0.0 and combat.hitstop_left == 0:
		knock_t += delta
		var kk := clampf(knock_t / 0.12, 0.0, 1.0)
		enemy_pos = knock_from.lerp(knock_to, 1.0 - pow(1.0 - kk, 3.0))
		if kk >= 1.0:
			knock_t = -1.0
	judge.begin_frame()
	super._process(delta)
	if sword:
		judge.end_frame(sword.global_transform)
	# 受擊假人：沿攻擊方向被推開並後仰，再回正；命中停格期間凍結（與攻擊方同一時鐘）
	if dummy_t >= 0.0 and combat.hitstop_left == 0:
		dummy_t += delta
	var off := Vector3.ZERO
	var tilt := 0.0
	if dummy_t >= 0.0:
		var t := dummy_t
		var k := 0.0
		if t < 0.18:
			k = 1.0 - pow(1.0 - t / 0.18, 2.0)
		elif t < REACT_T:
			k = 1.0 - smoothstep(0.18, REACT_T, t)
		else:
			dummy_t = -1.0
		off = dummy_dir * PUSH_M * k
		tilt = deg_to_rad(TILT_DEG) * k
	for kid in enemy_kids:
		(kid[0] as Node3D).position = (kid[1] as Vector3) + off
	var axis := dummy_dir.cross(Vector3.UP)
	enemy.basis = Basis(axis.normalized(), -tilt) if axis.length() > 0.01 and tilt != 0.0 else Basis.IDENTITY

func _slash_update() -> void:
	if sword == null:
		return
	var tip := sword.global_transform * TIP_LOCAL
	var dt := 1.0 / 60.0
	tip_v = (tip - tip_prev) / dt
	tip_speed = tip_v.length()
	tip_prev = tip
	if not tour or tour_t < TOUR_START_DELAY:
		return
	var guard := sword.global_transform * GUARD_LOCAL
	var inv := actor.global_transform.affine_inverse()
	var tl := inv * tip
	var gl := inv * guard
	var ik = combat.grip.ik if combat.grip else null
	# 左手離柄量測：左手骨（腕）與「刀 × left_rel」握位的距離（mm）；左臂伸直比＝肩→腕距離 ÷ 上臂＋前臂長
	var lh_err := -1.0
	var l_reach := -1.0
	if ik:
		var lt: Transform3D = sword.global_transform * (ik.left_rel as Transform3D)
		var gsk := sk.global_transform
		var lh := gsk * sk.get_bone_global_pose(sk.find_bone("mixamorig_LeftHand")).origin
		var la := gsk * sk.get_bone_global_pose(sk.find_bone("mixamorig_LeftArm")).origin
		var lf := gsk * sk.get_bone_global_pose(sk.find_bone("mixamorig_LeftForeArm")).origin
		lh_err = lh.distance_to(lt.origin) * 1000.0
		l_reach = la.distance_to(lh) / (la.distance_to(lf) + lf.distance_to(lh))
	slog.append({"t": snappedf(tour_t - TOUR_START_DELAY, 0.0001), "state": combat.state, "shot_t": snappedf(combat.shot_t, 0.0001), "hitstop": combat.hitstop_left,
		"tip_speed": snappedf(tip_speed, 0.01), "tip_l": [snappedf(tl.x, 0.001), snappedf(tl.y, 0.001), snappedf(tl.z, 0.001)], "guard_l": [snappedf(gl.x, 0.001), snappedf(gl.y, 0.001), snappedf(gl.z, 0.001)],
		"actor": [snappedf(actor.global_position.x, 0.001), snappedf(actor.global_position.z, 0.001), snappedf(actor.rotation.y, 0.0001)],
		"grip_w": snappedf(combat.grip.cur, 0.001) if combat.grip else 0.0,
		"grip_err_mm_deg": [snappedf(ik.last_err[0], 0.01), snappedf(ik.last_err[1], 0.01)] if ik else [0, 0],
		"left_w": snappedf(ik.last_left_weight, 0.001) if ik else 0.0,
		"dummy": [snappedf(enemy_pos.x, 0.001), snappedf(enemy_pos.z, 0.001)], "label": cur_label, "key": combat.shot_key, "hp": dummy_hp, "clamp": snappedf(combat.clamp_total, 0.0001), "atk_w": snappedf(combat.atk_w, 0.001), "lh_err_mm": snappedf(lh_err, 0.1), "l_reach": snappedf(l_reach, 0.001),
		"dummy_off": [snappedf(enemy.get_child(0).position.x, 0.001), snappedf(enemy.get_child(0).position.z, 0.001)]})

func _build_tour() -> void:
	var dist := enemy_dist
	var E := {"enemy": [0.0, dist, 0.01]}
	_s(0.8, "待機", Vector2.ZERO, E.merged({"third": "slash_vhx"}))	# 木樁每次命中被擊退 0.4 m
	_s(5.3, "① 一心三刀：縱斬 → 橫斬 → 袈裟斬（一心 3031）→ 收勢", Vector2.ZERO, {"attack": 0.15, "attack2": 0.45, "attack3": 1.55})
	_s(0.8, "待機", Vector2.ZERO, E.merged({"third": "slash_vhg"}))
	_s(3.2, "② 融合：縱斬 → 橫斬（一心）→ 上步唐竹斬（弦一郎 3001）→ 收勢", Vector2.ZERO, {"attack": 0.15, "attack2": 0.45, "attack3": 1.55})
	_s(0.8, "待機", Vector2.ZERO, E)
	_s(2.55, "③ 融合三刀，斬完立即移動", Vector2.ZERO, {"attack": 0.15, "attack2": 0.45, "attack3": 1.55})
	_s(1.6, "③ 恢復戰鬥移動：左移", Vector2(-1, 0))
	_s(1.2, "停步")

func _tour_step(delta: float) -> void:
	var prev := tour_ix
	super._tour_step(delta)
	if tour_ix != prev and tour_ix >= 0 and (tour_steps[tour_ix] as Dictionary).has("third"):
		combat.third_key = str(tour_steps[tour_ix]["third"])

func _finish_tour() -> void:
	if slashlog_path != "":
		DirAccess.make_dir_recursive_absolute(slashlog_path.get_base_dir())
		var f := FileAccess.open(slashlog_path, FileAccess.WRITE)
		f.store_string(JSON.stringify({"rows": slog, "hits": slash_hits, "hitstop_frames_total": combat.hitstop_total, "hitstop_frames": combat.hitstop_frames,
			"segments": tour_meta, "dist": enemy_dist, "combo_switch_t": combat.combo_switch_t, "clamp_total_m": combat.clamp_total,
			"fit_log": combat.fit_log, "cancel_log": combat.cancel_log,
			"field_notes": {"tip_speed/tip_l/hits[].tip_speed": "point Sword_Hand*TIP_LOCAL(0,1.085,0): a fixed offset on the blade axis, NOT the mesh tip (true tip is ~6 cm away in world, see tools/motion_capture/sword_geometry.gd); values unchanged for compatibility",
				"guard_l": "Sword_Hand origin (mesh y=0: on the grip, ~7 cm in world below the tsuba centre), not the guard",
				"hitstop": "combat.hitstop_left sampled after combat.step(): with freeze_hit_frame the hit frame is frozen and already counted, so rows with hitstop>0 = hitstop_frames-1 per hit; hitstop_frames_total counts every frozen frame"}}))
		f.close()
	super._finish_tour()

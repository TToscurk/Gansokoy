extends SceneTree
# 視窗模式驗證（SkeletonModifier3D 在 --headless 不跑）：
#   godot --path . --resolution 960x720 -s res://tools/verify_yoriichi_v2.gd
# 1) 每支 IP 動畫各播兩次：sim on / off，於 modification_processed 讀末端骨（唯一看得到 SpringBone 結果的時點）
# 2) 指標：末端位移（證明 sim 在跑）、最大偏移（不爆）、骨長守恆、進入腿碰撞膠囊深度
# 3) Root Motion：RM 版累積 root motion × motion_scale 與 Blender 實測比對
# 4) 截圖到 work/yoriichi_mixamo/renders/godot_*.png
const SCENE := "res://characters/yoriichi/v2/yoriichi_v2_test.tscn"
const SHOT_DIR := "D:/神社/shrine/work/yoriichi_mixamo/renders/"
var CLIPS := ["GS_Idle_IP", "GS_TurnL90_IP", "GS_Run_IP", "GS_DownwardSlash_IP", "GS_ComboSlash_IP", "TH_Combo_IP"]
const SHOTS := {"GS_Idle_IP": [1.0], "GS_TurnL90_IP": [0.3, 0.5, 0.7], "GS_Run_IP": [0.2, 0.45], "GS_DownwardSlash_IP": [0.3, 0.7, 0.95], "GS_ComboSlash_IP": [0.85, 1.6, 2.2, 2.7], "TH_Combo_IP": [0.7, 1.0, 1.5, 2.3]}

var skel: Skeleton3D
var sim: SpringBoneSimulator3D
var hsim: SpringBoneSimulator3D
var hends := []
var ap: AnimationPlayer
var ends := []          # [bone_idx, parent_idx, name]
var rec := []           # 每次 modification_processed 的樣本
var recording := false
var force_off := false
var hair_off := false
var tag := "v4"

func _init() -> void:
	var sc: Node = (load(SCENE) as PackedScene).instantiate()
	sc.set_script(null)
	var clip_lb: Label = sc.get_node_or_null("ClipLabel")
	if clip_lb: clip_lb.text = ""            # 測試場景的自動輪播腳本關掉，由本腳本逐支播
	get_root().add_child(sc)
	skel = sc.find_child("GeneralSkeleton", true, false)
	sim = skel.get_node("HaoriSpring")
	hsim = skel.get_node_or_null("HairSpring")
	for bi in skel.get_bone_count():
		var bn := skel.get_bone_name(bi)
		if bn.begins_with("hair_") and not bn.contains("_root"):
			hends.append([bi, skel.get_bone_parent(bi), bn])
	for e in hends:
		ends.append(e)
	if hsim:
		print("VERIFY HAIRSIM settings ", hsim.get_setting_count(), " joints ", range(hsim.get_setting_count()).map(func(q): return hsim.get_joint_count(q)),
			" roots ", range(hsim.get_setting_count()).map(func(q): return hsim.get_root_bone_name(q)), " hairbones ", hends.map(func(e): return e[2]))
	ap = sc.find_children("*", "AnimationPlayer", true, false)[0]
	for k in ["back_C", "back_L", "back_R", "side_L", "side_R", "front_L", "front_R"]:
		for j in [1, 2, 3]:
			var nm := "haori_%s_%02d" % [k, j]
			ends.append([skel.find_bone(nm), skel.get_bone_parent(skel.find_bone(nm)), nm])
	for s in ["L", "R"]:
		for j in [1, 2]:
			var nm := "haori_sleeve_%02d.%s" % [j, s]
			ends.append([skel.find_bone(nm), skel.get_bone_parent(skel.find_bone(nm)), nm])
	var variant := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "as_built"
	print("VERIFY variant ", variant)
	force_off = variant == "nosim"
	hair_off = variant == "nohair"
	# 參數覆寫：-- <tag> '{"front":{"k":3,"d":0.8,"r":[0.05,0.08]}, "back":{...}}'（區名前綴比對 root bone）
	if OS.get_cmdline_user_args().size() > 1:
		var ov: Dictionary = JSON.parse_string(OS.get_cmdline_user_args()[1])
		for si in sim.get_setting_count():
			var rb := String(sim.get_root_bone_name(si))
			for key in ov:
				if rb.begins_with("haori_" + str(key)):
					var o: Dictionary = ov[key]
					if o.has("k"): sim.set_stiffness(si, o.k)
					if o.has("d"): sim.set_drag(si, o.d)
					if o.has("g"): sim.set_gravity(si, o.g)
					if o.has("r"):
						sim.set_radius(si, o.r[1])
						var c := Curve.new(); c.add_point(Vector2(0, o.r[0] / o.r[1])); c.add_point(Vector2(1, 1)); sim.set_radius_damping_curve(si, c)
					if o.has("kc"):
						var c2 := Curve.new(); c2.add_point(Vector2(0, o.kc[0])); c2.add_point(Vector2(1, o.kc[1])); sim.set_stiffness_damping_curve(si, c2)
		# 頭髮覆寫：key 以 "hair_" 開頭（"hair_" 全部、"hair_ponytail"、"hair_side" …），另 "hcol":{名:半徑}
		if hsim:
			for si in hsim.get_setting_count():
				var rb2 := String(hsim.get_root_bone_name(si))
				for key in ov:
					if str(key).begins_with("hair_") and rb2.begins_with(str(key)):
						var o: Dictionary = ov[key]
						if o.has("k"): hsim.set_stiffness(si, o.k)
						if o.has("d"): hsim.set_drag(si, o.d)
						if o.has("g"): hsim.set_gravity(si, o.g)
						if o.has("r"): hsim.set_radius(si, o.r)
						if o.has("kc"):
							var c3 := Curve.new(); c3.add_point(Vector2(0, o.kc[0])); c3.add_point(Vector2(1, o.kc[1])); hsim.set_stiffness_damping_curve(si, c3)
						if o.has("dc"):
							var c4 := Curve.new(); c4.add_point(Vector2(0, o.dc[0])); c4.add_point(Vector2(1, o.dc[1])); hsim.set_drag_damping_curve(si, c4)
			if ov.has("hcol"):
				for c5 in hsim.get_children():
					var k5 := String(c5.name).replace("Col_", "")
					if ov.hcol.has(k5):
						(c5 as SpringBoneCollisionCapsule3D).radius = ov.hcol[k5]
	if variant != "as_built": tag = "v4" + variant
	for c in sim.get_children():
		var cc: SpringBoneCollisionCapsule3D = c
		if variant == "nocol":
			cc.radius = 0.0001
		elif variant == "long" and (cc.name.contains("Thigh") or cc.name.contains("Calf")):
			var L := cc.height - 2.0 * cc.radius
			cc.position_offset = Vector3.ZERO
			cc.height = 2.0 * L + 2.0 * cc.radius       # 以骨頭為中心、往兩端各延伸一整節 → 覆蓋整條腿
		elif variant == "big":
			cc.radius *= 1.6
		elif variant.begins_with("longbig") and (cc.name.contains("Thigh") or cc.name.contains("Calf")):
			var k := float(variant.substr(7)) if variant.length() > 7 else 1.4
			var L2 := cc.height - 2.0 * cc.radius
			cc.position_offset = Vector3.ZERO
			cc.radius *= k
			cc.height = 2.0 * L2 + 2.0 * cc.radius
	sim.reset()
	# 取樣必須接在「最後一個」modifier：HairSpring 在 HaoriSpring 之後處理；接 HaoriSpring 會讀不到頭髮結果
	if hsim and not hair_off and not force_off:
		hsim.modification_processed.connect(_on_mod)
	else:
		sim.modification_processed.connect(_on_mod)
	_run.call_deferred()

func _on_mod() -> void:
	if not recording:
		return
	var smp := {"t": ap.current_animation_position}
	for e in ends:
		smp[e[2]] = skel.get_bone_global_pose(e[0]).origin
		smp[e[2] + "_p"] = skel.get_bone_global_pose(e[1]).origin
	for pn in ["clothcol_head", "clothcol_neck", "clothcol_upperback", "clothcol_shoulder.L", "clothcol_shoulder.R"]:
		var pbi := skel.find_bone(pn)
		if pbi >= 0:
			smp[pn] = skel.get_bone_global_pose(pbi)
	for side in ["Left", "Right"]:
		smp[side + "UL"] = skel.get_bone_global_pose(skel.find_bone(side + "UpperLeg")).origin
		smp[side + "LL"] = skel.get_bone_global_pose(skel.find_bone(side + "LowerLeg")).origin
		smp[side + "FT"] = skel.get_bone_global_pose(skel.find_bone(side + "Foot")).origin
	rec.append(smp)

func _play(clip: String, active: bool) -> Array:
	sim.active = active and not force_off
	if hsim: hsim.active = active and not force_off and not hair_off
	if hsim: hsim.reset()
	sim.reset()
	ap.play(clip)
	ap.seek(0.0, true)
	for i in 5:
		await process_frame
	rec = []
	recording = true
	var shots: Array = SHOTS.get(clip, []) if active else []
	var si := 0
	if not active:
		# sim off 時 modification_processed 不發 → 改在 process_frame 讀（此時無 modifier，讀到的就是動畫姿勢）
		while ap.is_playing() and ap.current_animation == clip and rec.size() < 400 and not (clip.begins_with("GS_Idle") and ap.current_animation_position > 1.95):
			await process_frame
			var smp := {"t": ap.current_animation_position}
			for e in ends:
				smp[e[2]] = skel.get_bone_global_pose(e[0]).origin
				smp[e[2] + "_p"] = skel.get_bone_global_pose(e[1]).origin
			rec.append(smp)
	else:
		while ap.is_playing() and ap.current_animation == clip and rec.size() < 400 and not (clip.begins_with("GS_Idle") and ap.current_animation_position > 1.95):
			await process_frame
			if si < shots.size() and ap.current_animation_position >= shots[si]:
				await RenderingServer.frame_post_draw
				var img := get_root().get_viewport().get_texture().get_image()
				img.save_png(SHOT_DIR + tag + "_%s_%03d.png" % [clip, int(shots[si] * 30)])
				si += 1
	recording = false
	return rec.duplicate()

func _seg_d(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
	return p.distance_to(a + ab * t)

func _near(arr: Array, t: float) -> Dictionary:
	var best: Dictionary = arr[0]
	for s in arr:
		if absf(s.t - t) < absf(best.t - t):
			best = s
	return best

func _run() -> void:
	for i in 10:
		await process_frame
	print("VERIFY sim settings ", sim.get_setting_count(), " joints ", range(sim.get_setting_count()).map(func(i): return sim.get_joint_count(i)),
		" colliders ", range(sim.get_setting_count()).map(func(i): return sim.get_collision_count(i)))
	for c in sim.get_children():
		var cc: SpringBoneCollisionCapsule3D = c
		var bi := skel.find_bone(cc.bone_name)
		var bw := skel.global_transform * skel.get_bone_global_pose(bi)
		print("VERIFY collider ", cc.name, " bone ", cc.bone_name, " idx ", bi, " col_pos ", cc.global_position, " bone_pos ", bw.origin,
			" col_up ", cc.global_basis.y, " bone_y ", bw.basis.y.normalized(), " r ", cc.radius, " h ", cc.height)
	for si in sim.get_setting_count():
		var js := []
		for j in sim.get_joint_count(si):
			js.append([snappedf(sim.get_joint_stiffness(si, j), 0.01), snappedf(sim.get_joint_drag(si, j), 0.01), snappedf(sim.get_joint_radius(si, j), 0.001)])
		print("VERIFY joints ", sim.get_root_bone_name(si), " [k,d,r] ", js)
	# rest 骨長
	var rest_len := {}
	for e in ends:
		rest_len[e[2]] = skel.get_bone_global_rest(e[0]).origin.distance_to(skel.get_bone_global_rest(e[1]).origin)
	for clip in CLIPS:
		var off: Array = await _play(clip, false)
		var on: Array = await _play(clip, true)
		var max_dev := 0.0
		var dev_by := {}
		var len_err := 0.0
		var leg_in := 0.0
		var leg_in_off := 0.0
		var nan := 0
		var pen_by := {}
		for s in on:
			var b: Dictionary = _near(off, s.t)
			for e in ends:
				var nm: String = e[2]
				var p: Vector3 = s[nm]
				if not p.is_finite():
					nan += 1
					continue
				var d := p.distance_to(b[nm])
				max_dev = maxf(max_dev, d)
				dev_by[nm] = maxf(dev_by.get(nm, 0.0), d)
				len_err = maxf(len_err, absf(p.distance_to(s[nm + "_p"]) - rest_len[nm]))
				if not nm.contains("sleeve") and not nm.begins_with("hair_"):
					for side in ["Left", "Right"]:
						var dd := _seg_d(p, s[side + "UL"], s[side + "LL"])
						leg_in = maxf(leg_in, 0.08 - dd)   # 0.08 = 實測大腿網格半徑
						if 0.08 - dd > 0.0:
							pen_by[nm] = maxf(pen_by.get(nm, 0.0), 0.08 - dd)
						var pb: Vector3 = b[nm]
						# off 基線用同一時點 on 的腿位置（腿不受 sim 影響）
						leg_in_off = maxf(leg_in_off, 0.08 - _seg_d(pb, s[side + "UL"], s[side + "LL"]))
		# 頭髮：各鏈末端最大延遲（on vs off）＋ 髮骨節點最深進入頭部/上背代理（膠囊）深度
		var hdev := {}
		var hpen := {}
		var hpen_who := {}
		for s2 in on:
			var b2: Dictionary = _near(off, s2.t)
			for e in hends:
				var nm2: String = e[2]
				if not (s2.has(nm2) and b2.has(nm2)):
					continue
				var p2: Vector3 = s2[nm2]
				var ch2 := nm2.substr(0, nm2.rfind("_"))
				if nm2.ends_with(".L") or nm2.ends_with(".R"):
					ch2 += nm2.substr(nm2.length() - 2)
				hdev[ch2] = maxf(hdev.get(ch2, 0.0), p2.distance_to(b2[nm2]))
				for pc in [["clothcol_head", 0.105, 0.26], ["clothcol_upperback", 0.15, 0.40], ["clothcol_neck", 0.065, 0.16]]:
					if not s2.has(pc[0]):
						continue
					var T: Transform3D = s2[pc[0]]
					var hl: float = pc[2] * 0.5 - pc[1]
					var d2 := _seg_d(p2, T.origin - T.basis.y.normalized() * hl, T.origin + T.basis.y.normalized() * hl)
					var pen2: float = pc[1] - d2
					if pen2 > 0.0:
						var key: String = str(pc[0]).replace("clothcol_", "")
						if pen2 > hpen.get(key, 0.0):
							hpen[key] = pen2
							hpen[key + "@"] = 0.0
							hpen.erase(key + "@")
							hpen_who[key] = nm2
		print("VERIFY HAIR ", clip, " tip_lag_cm ", hdev.keys().map(func(k): return [k.replace("hair_", ""), snappedf(hdev[k] * 100, 0.1)]),
			" node_inside_proxy_cm ", hpen.keys().map(func(k): return [k, snappedf(hpen[k] * 100, 0.1), hpen_who.get(k, "")]))
		var chains := {}
		for k in dev_by:
			chains[k.replace("haori_", "")] = snappedf(dev_by[k] * 100.0, 0.1)
		print("VERIFY ", clip, " samples on/off ", on.size(), "/", off.size(), " max_dev_cm ", snappedf(max_dev * 100, 0.1),
			" per_chain_cm ", chains, " bone_len_err_mm ", snappedf(len_err * 1000, 0.1), " nan ", nan,
			" thigh_penetration_cm sim_on ", snappedf(maxf(leg_in, 0) * 100, 0.1), " sim_off ", snappedf(maxf(leg_in_off, 0) * 100, 0.1),
			" pen_by_bone_cm ", pen_by.keys().map(func(k): return [k.replace("haori_", ""), snappedf(pen_by[k] * 100, 0.1)]))
	# Root motion
	for clip in [] if OS.get_cmdline_user_args().size() > 0 else ["GS_ComboSlash_RM", "TH_Combo_RM"]:
		ap.root_motion_track = NodePath("%GeneralSkeleton:Root")
		ap.play(clip); ap.seek(0.0, true)
		var acc := Vector3.ZERO
		await process_frame
		while ap.is_playing() and ap.current_animation == clip:
			await process_frame
			acc += ap.get_root_motion_position()
		print("VERIFY root motion ", clip, " accumulated (m, 已含 motion_scale ", snappedf(skel.motion_scale, 0.001), ") ", acc)
	ap.root_motion_track = NodePath("")
	print("VERIFY done")
	quit()

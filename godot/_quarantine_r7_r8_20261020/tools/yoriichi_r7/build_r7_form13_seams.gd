extends SceneTree
## R7 P4 十三型「循環專用」接縫派生（新檔，不覆寫原十二型 .res／json）。
## 問題：十二型的首尾格分屬兩種構（K1 低刀尖／K2-K3 喉高刀尖），6 對相鄰接縫（REF01→02、02→03、03→04、06→07、08→09、10→11）
## 在接點與下一型首格的刀尖差 0.73–0.81 m，原本只靠 0.16 s 交叉淡化回中段構再起刀。
## 作法：上一型在隨揮仍在走的格 fa 交出；下一型複製一份，上半身（脊椎→手）旋轉軌加「起點＝上一型 fa 姿勢、
## 在 N 格內 smoothstep 衰減到 0」的偏移 → 派生 clip 第 0 格＝上一型出口姿勢，第 N 格起與原 clip 逐位元相同。
## 時長、metadata（命中窗、root、空中 marker、cancel）完全不變；N 一律在第一個命中窗／起跳蹲／evade 之前結束。
## 骨盆與腿不動（蹬地、承重、root 基準照原 clip）；腳的差異仍由 full_sel 交叉淡化承接。
##   godot --headless --path godot -s res://tools/yoriichi_r7/build_r7_form13_seams.gd -- probe   （只量，不寫檔）
##   godot --headless --path godot -s res://tools/yoriichi_r7/build_r7_form13_seams.gd -- save
const PLAYER := "res://characters/yoriichi/player_yoriichi_r7k.tscn"
const OUT_DIR := "res://characters/yoriichi/v24/anims_r7/form13/"
## [上一型 anim, 接出格 fa, 下一型 anim 清單（主版＋近距版）, 衰減格 N]
const SEAMS := [
	["R7_Sun01_Enbu", 24, ["R7_Sun02_Hekira"], 14],
	["R7_Sun02_Hekira", 37, ["R7_Sun03_Retsujitsu"], 8],
	# REF03→04 試過 fa=39／N=6：runtime 交接格刀尖折返，退回原接法（不派生）
	["R7_Sun06_Shakkotsu", 78, ["R7_Sun07_Youkatotsu", "R7_Sun07_YoukatotsuNear"], 10],
	["R7_Sun08_HirinKagerou", 35, ["R7_Sun09_ShayouTenshinMX"], 10],
	["R7_Sun10_KikiOnkou", 74, ["R7_Sun11_NichirinDragon", "R7_Sun11_NichirinDragonNear"], 12],
]
const WARP_PREFIX := ["Spine", "Neck", "Head", "LeftShoulder", "RightShoulder", "LeftArm", "RightArm", "LeftForeArm",
	"RightForeArm", "LeftHand", "RightHand"]

var _anim: AnimationPlayer
var _sk: Skeleton3D
var _vis: Node3D
var _tip: Node3D
var _base: Node3D


func _initialize() -> void:
	call_deferred("_run")


static func seam_out_name(prev: String, nxt: String) -> String:
	return "R7C_%s_from_%s" % [nxt.trim_prefix("R7_"), prev.trim_prefix("R7_").get_slice("_", 0)]


static func _bone_of(path: NodePath) -> String:
	return str(path).get_slice(":", 1).trim_prefix("mixamorig_")


static func _warp_bone(bn: String) -> bool:
	for p in WARP_PREFIX:
		if bn == p or (bn.begins_with(p) and not bn.begins_with(p + "Thumb") and not bn.begins_with(p + "Index")
				and not bn.begins_with(p + "Middle") and not bn.begins_with(p + "Ring") and not bn.begins_with(p + "Pinky")):
			if bn.begins_with("LeftHand") or bn.begins_with("RightHand"):
				return bn == "LeftHand" or bn == "RightHand"
			return true
	return false


func derive(prev: Animation, fa: int, nxt: Animation, n: int) -> Animation:
	var o: Animation = nxt.duplicate(true)
	for m in nxt.get_meta_list():
		o.set_meta(m, nxt.get_meta(m))
	var t_exit := minf(fa / 30.0, prev.length)
	for ti in o.get_track_count():
		if o.track_get_type(ti) != Animation.TYPE_ROTATION_3D:
			continue
		var path := o.track_get_path(ti)
		if not _warp_bone(_bone_of(path)):
			continue
		var pi := prev.find_track(path, Animation.TYPE_ROTATION_3D)
		if pi < 0:
			continue
		var q_prev := prev.rotation_track_interpolate(pi, t_exit).normalized()
		var q_next0 := nxt.rotation_track_interpolate(ti, 0.0).normalized()
		if _bone_of(path) == "Spine":
			# 骨盆不動（腿／蹬地照原 clip）→ 脊椎根補上兩 clip 的骨盆朝向差，讓胸以上的「骨架空間」姿勢等於上一型出口
			var hp := str(path).get_slice(":", 0) + ":mixamorig_Hips"
			var hi_p := prev.find_track(NodePath(hp), Animation.TYPE_ROTATION_3D)
			var hi_n := nxt.find_track(NodePath(hp), Animation.TYPE_ROTATION_3D)
			if hi_p >= 0 and hi_n >= 0:
				var hq_p := prev.rotation_track_interpolate(hi_p, t_exit).normalized()
				var hq_n := nxt.rotation_track_interpolate(hi_n, 0.0).normalized()
				q_prev = (hq_n.inverse() * hq_p * q_prev).normalized()
		var delta := (q_prev * q_next0.inverse()).normalized()
		if delta.w < 0.0:
			delta = -delta   # 短路徑
		for k in o.track_get_key_count(ti):
			var t := o.track_get_key_time(ti, k)
			var f := t * 30.0
			if f >= float(n):
				break
			var u := f / float(n)
			var w := 1.0 - u * u * (3.0 - 2.0 * u)
			var dq := Quaternion.IDENTITY.slerp(delta, w)
			o.track_set_key_value(ti, k, (dq * (o.track_get_key_value(ti, k) as Quaternion)).normalized())
	o.set_meta("r7c_seam_from", prev.resource_name if prev.resource_name != "" else "")
	o.set_meta("r7c_seam_fa", fa)
	o.set_meta("r7c_seam_decay", n)
	return o


func _sample(aname: String, f: float) -> Dictionary:
	_anim.play(aname)
	_anim.speed_scale = 0.0
	_anim.seek(f / 30.0, true)
	return {}


func _read() -> Dictionary:
	var inv := _vis.global_transform.affine_inverse()
	var lh := inv * (_sk.global_transform * _sk.get_bone_global_pose(_sk.find_bone("mixamorig_LeftHand")).origin)
	var rh := inv * (_sk.global_transform * _sk.get_bone_global_pose(_sk.find_bone("mixamorig_RightHand")).origin)
	var rb := (inv * (_sk.global_transform * _sk.get_bone_global_pose(_sk.find_bone("mixamorig_RightHand")))).basis.orthonormalized()
	return {"tip": inv * _tip.global_position, "base": inv * _base.global_position, "lh": lh, "rh": rh, "rel": rb.inverse() * (lh - rh)}


func _pose(aname: String, f: float) -> Dictionary:
	_sample(aname, f)
	await process_frame
	await process_frame
	return _read()


func _run() -> void:
	var mode := "probe"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		mode = args[0]
	var w := Node3D.new()
	root.add_child(w)
	var p: CharacterBody3D = (load(PLAYER) as PackedScene).instantiate()
	p.set("r7_vfx_enabled", false)
	w.add_child(p)
	p.set_physics_process(false)
	await process_frame
	(p.get("_tree") as AnimationTree).active = false
	_anim = p.get("_anim")
	_vis = p.get("_visual")
	_sk = _vis.find_children("*", "Skeleton3D", true, false)[0]
	_tip = p.get("_blade_tip")
	_base = p.get("_blade_base")
	var lib: AnimationLibrary = _anim.get_animation_library(_anim.get_animation_library_list()[0])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var report := []
	for s in SEAMS:
		var prev: Animation = _anim.get_animation(s[0])
		var fa: int = s[1]
		var n: int = s[3]
		var ex := await _pose(s[0], fa)
		for nm in s[2]:
			var nxt: Animation = _anim.get_animation(nm)
			var der := derive(prev, fa, nxt, n)
			var on := seam_out_name(s[0], nm)
			if lib.has_animation(on):
				lib.remove_animation(on)
			lib.add_animation(on, der)
			var rows := []
			var orig := []
			for f in n + 4:
				rows.append(await _pose(on, f))
				orig.append(await _pose(nm, f))
			var old0: Dictionary = orig[0]
			var gap_old: float = (ex.tip as Vector3).distance_to(old0.tip)
			var gap_new: float = (ex.tip as Vector3).distance_to(rows[0].tip)
			var gap_base: float = (ex.base as Vector3).distance_to(rows[0].base)
			var mstep := 0.0
			var ostep := 0.0
			var grip_d := 0.0
			for f in range(1, rows.size()):
				mstep = maxf(mstep, (rows[f].tip as Vector3).distance_to(rows[f - 1].tip))
				ostep = maxf(ostep, (orig[f].tip as Vector3).distance_to(orig[f - 1].tip))
			# 握把：左手在右手座標中的位置，派生 clip 應落在「出口值→原值」之間；量與線性插值的最大偏離
			for f in rows.size():
				var u := minf(float(f) / float(n), 1.0)
				var sm := u * u * (3.0 - 2.0 * u)
				var want: Vector3 = (ex.rel as Vector3).lerp(orig[f].rel, sm)
				grip_d = maxf(grip_d, (rows[f].rel as Vector3).distance_to(want))
			var identical_after := (rows[n + 1].tip as Vector3).distance_to(orig[n + 1].tip)
			var r := {"seam": "%s@%d -> %s" % [s[0], fa, nm], "out": on, "tip_gap_old_f0": snappedf(gap_old, 0.001),
				"tip_gap_new": snappedf(gap_new, 0.001), "base_gap_new": snappedf(gap_base, 0.001),
				"max_tip_step_derived": snappedf(mstep, 0.001), "max_tip_step_orig": snappedf(ostep, 0.001),
				"grip_rel_dev_max": snappedf(grip_d, 0.001), "tip_diff_after_N": snappedf(identical_after, 0.0001)}
			print(JSON.stringify(r))
			report.append(r)
			if mode == "save":
				var path := OUT_DIR + on.to_snake_case() + ".res"
				der.resource_name = on
				var err := ResourceSaver.save(der, path)
				print("SAVE ", path, " err=", err)
	var fo := FileAccess.open("user://r7p4_seams_build_%s.json" % mode, FileAccess.WRITE)
	fo.store_string(JSON.stringify(report, " "))
	fo.close()
	quit(0)

extends SceneTree
## P10 R3a NPC Prototype（普通町人・男 chonin_m01；使用者の Tripo モデル）技術 gate——「壊れていない」ことだけを証明する（美術判定ではない）。
##   godot --headless --path . --script res://tools/verify_npc_prototype.gd                 gate 9 項
##   godot --headless --path . --script res://tools/verify_npc_prototype.gd -- --negatives  反向 4 案（各案で狙った項目が FAIL）
## 真の FAIL は exit code ≠ 0。反向は「狙った項目が落ちる」なら PASS。

const SCENE := "res://characters/npc/chonin_m01/chonin_m01.tscn"
const PARTS := ["NPC_Head", "NPC_Hair", "NPC_Upper", "NPC_Lower", "NPC_Feet"]
const HUMANOID := ["Root", "Hips", "Spine", "Chest", "UpperChest", "Neck", "Head",
	"LeftShoulder", "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand",
	"LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "LeftToes", "RightUpperLeg", "RightLowerLeg", "RightFoot", "RightToes",
	"LeftIndexProximal", "RightIndexProximal", "LeftThumbProximal", "RightThumbProximal"]
const MATS := ["m_skin.tres", "m_cloth.tres", "m_hair.tres"]
const H_MIN := 1.65
const H_MAX := 1.70
## 使用者規格の LOD0 目安は 25k–60k。Tripo 原型は 10,220 三角（分割・地毛込み 10,904）——下限は「原型から欠けていない」ことの確認に使う。
const TRI_MIN := 10000
const TRI_MAX := 60000

var fails := 0


func check(label: String, ok: bool) -> bool:
	print("[NPC] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		fails += 1
	return ok


func _c(label: String, ok: bool, quiet: bool) -> bool:
	return ok if quiet else check(label, ok)


func run(w: Node3D, quiet := false) -> PackedStringArray:
	var bad := PackedStringArray()
	var sk := w.find_child("GeneralSkeleton", true, false) as Skeleton3D
	var mis: Array = w.find_children("NPC_*", "MeshInstance3D", true, false)
	var names := mis.map(func(m: Node) -> String: return String(m.name))
	var parts_ok := sk != null and mis.size() == PARTS.size() and PARTS.all(func(p: String) -> bool: return p in names) \
		and mis.all(func(m: MeshInstance3D) -> bool: return m.skin != null and m.get_node_or_null(m.skeleton) == sk)
	if not _c("部位 5（Head／Hair／Upper／Lower／Feet）が同じ GeneralSkeleton に skin（%s）" % str(names), parts_ok, quiet):
		bad.append("parts")
	var miss := []
	for b in HUMANOID:
		if sk == null or sk.find_bone(b) < 0:
			miss.append(b)
	if not _c("骨格＝SkeletonProfileHumanoid 名（Root・体幹・四肢・指 %d 本確認、全 %d 骨、欠 %s）" % [HUMANOID.size(), sk.get_bone_count() if sk else 0, str(miss)], miss.is_empty(), quiet):
		bad.append("bones")
	var ap := w.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var clips := ap.get_animation_list() if ap else PackedStringArray()
	var loop_ok := ap != null and clips.size() == 2 and "idle" in clips and "walk" in clips \
		and ap.get_animation("idle").loop_mode == Animation.LOOP_LINEAR and ap.get_animation("walk").loop_mode == Animation.LOOP_LINEAR
	if not _c("clip は共通 library の idle・walk の 2 本だけ・両方ループ（%s）" % str(clips), loop_ok, quiet):
		bad.append("clips")
	var tris := 0
	var mats := {}
	var albedo := {}
	var emis := false
	for m: MeshInstance3D in mis:
		var am := m.mesh as ArrayMesh
		for i in am.get_surface_count():
			tris += am.surface_get_array_index_len(i) / 3
			var mt := am.surface_get_material(i) as StandardMaterial3D
			mats[mt.resource_path.get_file() if mt else "null"] = true
			if mt:
				albedo[mt.albedo_texture.resource_path if mt.albedo_texture else "none"] = true
				emis = emis or mt.emission_enabled
	if not _c("三角 %d（%d–%d）" % [tris, TRI_MIN, TRI_MAX], tris >= TRI_MIN and tris <= TRI_MAX, quiet):
		bad.append("tris")
	var mat_ok := mats.size() == 3 and mats.keys().all(func(k: String) -> bool: return k in MATS) and albedo.size() == 1 and not emis
	if not _c("材質＝外部 m_skin／m_cloth／m_hair の 3 つ・albedo atlas 1 枚・emission なし（%s）" % str(mats.keys()), mat_ok, quiet):
		bad.append("materials")
	var top := -INF
	var bottom := INF
	for m: MeshInstance3D in mis:
		var ab: AABB = m.global_transform * m.get_aabb()
		top = maxf(top, ab.end.y)
		bottom = minf(bottom, ab.position.y)
	if not _c("身長（rest、髪の頂点まで）%.3f m（%.2f–%.2f）・足裏 %.3f" % [top - bottom, H_MIN, H_MAX, bottom], top - bottom >= H_MIN and top - bottom <= H_MAX and absf(bottom) < 0.01, quiet):
		bad.append("height")
	var g_err := 0.0
	var stretch := -INF
	var shrink := INF
	if sk != null and loop_ok:
		var rest := {}
		for b in ["LeftFoot", "RightFoot", "LeftToes", "RightToes", "Head"]:
			rest[b] = sk.get_bone_global_rest(sk.find_bone(b)).origin.y
		ap.speed_scale = 0.0
		for c in ["idle", "walk"]:
			ap.play(c)
			var t := 0.0
			while t < ap.get_animation(c).length:
				ap.seek(t, true)
				var lo := INF
				for b in ["LeftFoot", "RightFoot", "LeftToes", "RightToes"]:
					lo = minf(lo, sk.get_bone_global_pose(sk.find_bone(b)).origin.y - float(rest[b]))
				g_err = maxf(g_err, absf(lo))
				var hy := sk.get_bone_global_pose(sk.find_bone("Head")).origin.y - float(rest["Head"])
				stretch = maxf(stretch, hy)
				shrink = minf(shrink, hy)
				t += 0.25
	if not _c("idle／walk 全フレーム接地：最も低い足骨の rest 差 最大 %.3f m（≤ 0.015）" % g_err, loop_ok and g_err <= 0.015, quiet):
		bad.append("ground")
	if not _c("首・胴が伸びない：Head 骨の rest 差 %.3f〜%.3f m（−0.08〜+0.03）" % [shrink, stretch], loop_ok and stretch <= 0.03 and shrink >= -0.08, quiet):
		bad.append("stretch")
	return bad


func _fresh() -> Node3D:
	var w: Node3D = (load(SCENE) as PackedScene).instantiate()
	w.set("frozen", true)
	w.set("start_time", 0.0)
	root.add_child(w)
	return w


## clip を書き換える反向用：library の clip を複製に差し替えてから返す
func _own_clip(w: Node3D, clip: String) -> Animation:
	var ap := w.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var lib := ap.get_animation_library(&"")
	var an := lib.get_animation(clip).duplicate(true) as Animation
	lib.add_animation(clip, an)
	return an


func _init() -> void:
	if "--negatives" in OS.get_cmdline_user_args():
		var cases := {
			"part_missing": ["parts", func(w: Node3D) -> void: w.find_child("NPC_Hair", true, false).free()],
			"scaled_110": ["height", func(w: Node3D) -> void: w.scale = Vector3.ONE * 1.1],
			"neck_stretch": ["stretch", func(w: Node3D) -> void:
				var sk := w.find_child("GeneralSkeleton", true, false) as Skeleton3D
				for c in ["idle", "walk"]:
					var an := _own_clip(w, c)
					var tr := an.add_track(Animation.TYPE_POSITION_3D)
					an.track_set_path(tr, NodePath("%GeneralSkeleton:Neck"))
					an.position_track_insert_key(tr, 0.0, sk.get_bone_rest(sk.find_bone("Neck")).origin + Vector3(0, 0.15, 0))],
			"float_10cm": ["ground", func(w: Node3D) -> void:
				var sk := w.find_child("GeneralSkeleton", true, false) as Skeleton3D
				var an := _own_clip(w, "walk")
				var tr := an.find_track(NodePath("%GeneralSkeleton:Hips"), Animation.TYPE_POSITION_3D)
				for k in an.track_get_key_count(tr):
					an.track_set_key_value(tr, k, (an.track_get_key_value(tr, k) as Vector3) + Vector3(0, 0.1 / sk.motion_scale, 0))],
		}
		for nm: String in cases:
			var w := _fresh()
			await process_frame
			(cases[nm][1] as Callable).call(w)
			await process_frame
			var bad := run(w, true)
			check("反向 %s → 「%s」が FAIL（落ちた項目 %s）" % [nm, cases[nm][0], str(bad)], cases[nm][0] in bad)
			w.queue_free()
			await process_frame
		print("[NPC] 結果：%d 項失敗（negatives）" % fails)
		quit(fails)
		return
	var w := _fresh()
	await process_frame
	run(w)
	var w2: Node3D = (load(SCENE) as PackedScene).instantiate()
	root.add_child(w2)
	await process_frame
	var ap := w2.find_child("AnimationPlayer", true, false) as AnimationPlayer
	check("chonin_m01.tscn（npc_visual.gd）が既定で idle を再生", ap != null and ap.current_animation == "idle" and ap.is_playing())
	print("[NPC] 結果：%d 項失敗" % fails)
	quit(fails)

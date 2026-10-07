extends SceneTree
## P10 R3a NPC：retarget 後の clip を NPC 骨格上で「接地」させた共通 clip を書き出す（再現可能）。
##   godot --headless --path . --script res://tools/build_npc_anim_grounded.gd -- [--dir=res://…] [--clips=a,b,…]
## 入力＝import が save_to_file した <dir>/<clip>.res（GeneralSkeleton＝SkeletonProfileHumanoid のトラック）。
## 各 Hips 位置キーで、最も低い足骨（足首・つま先）が rest の高さに来るよう Hips の高さだけ補正（位置トラックは motion_scale で正規化済み）。
## 出力＝<dir>/<clip>_grounded.res（npc_visual.gd が使う）。
## 2026-10-05：動作は Mixamo のみ（使用者指示）。Mixamo に NPC 本体（Tripo rig）を上傳して書き出した FBX＝同じ骨格。

const NPC := "res://characters/npc/chonin_m01/chonin_m01.tscn"
const FEET := ["LeftFoot", "RightFoot", "LeftToes", "RightToes"]
const DEFAULT_DIR := "res://characters/npc/_shared/anim/mixamo"
const DEFAULT_CLIPS := ["idle_weightshift_a030", "idle_breathing_s0_a030", "idle_neutral_a030",
	"walk_standard_a030", "walk_malestandard_a030", "walk_hurried_a030"]


func _init() -> void:
	var dir := DEFAULT_DIR
	var clips: Array = DEFAULT_CLIPS
	var npc_path := NPC
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dir="):
			dir = a.trim_prefix("--dir=")
		elif a.begins_with("--clips="):
			clips = Array(a.trim_prefix("--clips=").split(","))
		elif a.begins_with("--npc="):   # P10 NPC Asset Library：各 NPC の glb（自分の骨格で接地を測る）
			npc_path = a.trim_prefix("--npc=")
	var w: Node3D = (load(npc_path) as PackedScene).instantiate()
	w.set("frozen", true)
	root.add_child(w)
	await process_frame
	var sk := w.find_child("GeneralSkeleton", true, false) as Skeleton3D
	var ap := w.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap == null:   # glb 単体（動作なし）：npc_visual.gd と同じ掛け方
		ap = AnimationPlayer.new()
		w.add_child(ap)
		ap.root_node = NodePath("../Armature")
	var rest := {}
	for b in FEET:
		rest[b] = sk.get_bone_global_rest(sk.find_bone(b)).origin.y
	var fails := 0
	var lib := AnimationLibrary.new()   # library は 1 回だけ追加し、clip ごとに別名で入れる
	ap.add_animation_library(&"tmp", lib)
	for c: String in clips:
		var src: Animation = load("%s/%s.res" % [dir, c])
		var an := src.duplicate(true) as Animation
		var tr := an.find_track(NodePath("%GeneralSkeleton:Hips"), Animation.TYPE_POSITION_3D)
		if tr < 0:
			print("[NPCANIM] FAIL %s：Hips 位置トラックが無い" % c)
			fails += 1
			continue
		lib.add_animation(StringName(c), an)
		ap.play(StringName("tmp/" + c))
		ap.speed_scale = 0.0
		var before := [INF, -INF]
		var fix := {}
		for k in an.track_get_key_count(tr):
			ap.seek(an.track_get_key_time(tr, k), true)
			var lo := INF
			for b in FEET:
				lo = minf(lo, sk.get_bone_global_pose(sk.find_bone(b)).origin.y - float(rest[b]))
			before[0] = minf(before[0], lo)
			before[1] = maxf(before[1], lo)
			fix[k] = lo
		for k: int in fix:
			var v: Vector3 = an.track_get_key_value(tr, k)
			an.track_set_key_value(tr, k, v - Vector3(0, float(fix[k]) / sk.motion_scale, 0))
		var after := [INF, -INF]
		for k in an.track_get_key_count(tr):
			ap.seek(an.track_get_key_time(tr, k), true)
			var lo := INF
			for b in FEET:
				lo = minf(lo, sk.get_bone_global_pose(sk.find_bone(b)).origin.y - float(rest[b]))
			after[0] = minf(after[0], lo)
			after[1] = maxf(after[1], lo)
		an.resource_name = c
		an.loop_mode = Animation.LOOP_LINEAR
		var out := "%s/%s_grounded.res" % [dir, c]
		var err := ResourceSaver.save(an, out)
		var ok: bool = err == OK and absf(after[0]) < 0.005 and absf(after[1]) < 0.005
		if not ok:
			fails += 1
		print("[NPCANIM] %s %s len %.2fs keys %d 接地誤差 before %.3f〜%.3f → after %.4f〜%.4f m → %s" % ["PASS" if ok else "FAIL", c, an.length, an.track_get_key_count(tr), before[0], before[1], after[0], after[1], out])
	quit(fails)

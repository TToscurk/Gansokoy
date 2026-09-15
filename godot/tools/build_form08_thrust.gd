extends SceneTree
## 捌ノ型 陽華突：Blender GLB → Godot .res 動畫。
##
## 執行：
##   godot --headless --path godot -s tools/build_form08_thrust.gd
##
## 沿用 build_spin_slash.gd 建立的同一條管線（憲法第 1 條：重用優先，
## 不另開平行 pipeline）。差別只在來源是自製 GLB 而非 Meshy 匯出，
## 因此**不需要**那支腳本的公分→公尺換算與 X90 校正 ——
## 本 GLB 由 make_form08_thrust.py 產生，已經是 Godot 慣例的 y-up 公尺制。
##
## 本腳本做的事：
##   1. 讀 GLB 的 Form08_Thrust 軌
##   2. 軌路徑改寫成 "Armature/Skeleton3D:<骨名>"（對上 player_yoriichi.tscn）
##   3. **Hips 水平凍結到 FBX rest** —— 位移一律由 GDScript 驅動（專案紅線）
##   4. 存成 .res

const GLB := "res://characters/yoriichi/anim_src/form08_thrust.glb"
const FBX := "res://characters/yoriichi/yoriichi_body.fbx"
const OUT := "res://characters/yoriichi/animations/yoriichi_form08_thrust.res"
const SRC_ANIM := "Form08_Thrust"


func _init() -> void:
	var ps_glb := load(GLB) as PackedScene
	if ps_glb == null:
		push_error("[捌型] 載不到 GLB：" + GLB)
		quit(1)
		return
	var inst_glb := ps_glb.instantiate()
	var aps := inst_glb.find_children("*", "AnimationPlayer", true, false)
	if aps.is_empty():
		push_error("[捌型] GLB 裡沒有 AnimationPlayer")
		quit(1)
		return
	var ap: AnimationPlayer = aps[0]

	# 動畫名由匯入器決定，不寫死 —— 先找精確名，再退回「含 Form08 的那個」。
	var src: Animation = null
	if ap.has_animation(SRC_ANIM):
		src = ap.get_animation(SRC_ANIM)
	else:
		for n in ap.get_animation_list():
			if String(n).contains("Form08") or String(n).contains("Thrust"):
				src = ap.get_animation(n)
				print("[捌型] 用動畫 '%s'" % n)
				break
	if src == null:
		push_error("[捌型] GLB 裡找不到 Form08 動畫，實際有：%s" % str(ap.get_animation_list()))
		quit(1)
		return

	var ps_fbx := load(FBX) as PackedScene
	var inst_fbx := ps_fbx.instantiate()
	var skel: Skeleton3D = inst_fbx.find_children("*", "Skeleton3D", true, false)[0]
	var hips_rest := skel.get_bone_rest(skel.find_bone("Hips"))

	var out_anim := Animation.new()
	out_anim.length = src.length
	out_anim.loop_mode = Animation.LOOP_NONE

	var n_pos := 0
	var n_rot := 0
	var skipped: Array[String] = []

	for t in src.get_track_count():
		var path := String(src.track_get_path(t))
		var bone := path.get_slice(":", 1) if path.contains(":") else path.get_file()
		var ttype := src.track_get_type(t)
		# 只搬骨架動得到的骨頭；GLB 若帶多餘節點軌一律丟掉。
		if skel.find_bone(bone) < 0:
			if not skipped.has(bone):
				skipped.append(bone)
			continue
		var new_path := "Armature/Skeleton3D:" + bone

		if ttype == Animation.TYPE_POSITION_3D:
			# ⚠ 只有 Hips 保留位移，而且**只保留垂直**。
			#   水平必須凍結在 FBX rest：專案所有位移由 CharacterBody3D 驅動，
			#   動畫帶水平 root motion 會與程式位移疊加打架。
			if bone != "Hips":
				continue
			var nt := out_anim.add_track(Animation.TYPE_POSITION_3D)
			out_anim.track_set_path(nt, new_path)
			out_anim.track_set_interpolation_type(nt, src.track_get_interpolation_type(t))
			# ⚠ 垂直要**重新錨定到 FBX rest**，不能照搬 GLB 的絕對值：
			#   兩邊的骨架基準不同（實測 GLB Hips Z ≈ 5.73、FBX rest ≈ 0.99），
			#   直接搬會讓角色浮在 4.7 m 高空。做法與既有 build_spin_slash.gd
			#   一致：取 GLB 首幀當 0 點，只把「相對起伏」疊到 FBX rest 上。
			var base_z: float = 0.0
			if src.track_get_key_count(t) > 0:
				var first: Vector3 = src.track_get_key_value(t, 0)
				base_z = first.z
			for k in src.track_get_key_count(t):
				var time := src.track_get_key_time(t, k)
				var v: Vector3 = src.track_get_key_value(t, k)
				# 本 rig 的 Hips position：Z 是垂直軸（README 記載、偵察實證）。
				out_anim.track_insert_key(nt, time, Vector3(
					hips_rest.origin.x,
					hips_rest.origin.y,
					hips_rest.origin.z + (v.z - base_z)))
			n_pos += 1

		elif ttype == Animation.TYPE_ROTATION_3D:
			var nt := out_anim.add_track(Animation.TYPE_ROTATION_3D)
			out_anim.track_set_path(nt, new_path)
			out_anim.track_set_interpolation_type(nt, src.track_get_interpolation_type(t))
			for k in src.track_get_key_count(t):
				out_anim.track_insert_key(nt, src.track_get_key_time(t, k),
					src.track_get_key_value(t, k))
			n_rot += 1

	var err := ResourceSaver.save(out_anim, OUT)
	print("[捌型] 位置軌 %d、旋轉軌 %d、總長 %.3f s" % [n_pos, n_rot, out_anim.length])
	if not skipped.is_empty():
		print("[捌型] 略過非骨架軌：%s" % str(skipped))
	print("[捌型] 存檔 %s（狀態 %d）" % [OUT, err])

	inst_glb.free()
	inst_fbx.free()
	quit(0 if err == OK else 1)

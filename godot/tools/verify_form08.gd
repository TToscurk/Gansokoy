extends SceneTree
## 捌ノ型 陽華突：在 Godot 端的接線驗證。
##
## 執行：
##   godot --headless --path godot -s tools/verify_form08.gd
##
## Blender 那邊量的是動作本身；這支量的是「接進遊戲後成不成立」：
##   1. .res 真的載得進來，軌路徑對得上 Skeleton3D
##   2. 24 骨全部有軌（少骨會導致該部位停在 rest，看起來像癱瘓）
##   3. Hips 水平真的被凍結（專案紅線：位移由程式驅動）
##   4. 型表登記成 READY、AnimationPlayer 裡註冊得到
##   5. execute_form(8) 真的發得動，扣呼吸、起冷卻

const SunBreathing = preload("res://characters/yoriichi/sun_breathing.gd")
const RES := "res://characters/yoriichi/animations/yoriichi_form08_thrust.res"

var _pass := 0
var _fail := 0


func check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		_pass += 1
		print("  [OK] ", label, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", label, ("  " + detail) if detail != "" else "")


func _initialize() -> void:
	print("=== 捌ノ型 陽華突 接線驗證 ===")
	_test_resource()
	await process_frame
	await _test_in_character()
	print("=== %d passed, %d failed ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _test_resource() -> void:
	print("-- .res 本體 --")
	var anim: Animation = load(RES)
	check(".res 載入成功", anim != null)
	if anim == null:
		return
	check("長度 1.25 s", is_equal_approx(anim.length, 1.25), "%.3f s" % anim.length)
	check("不循環", anim.loop_mode == Animation.LOOP_NONE)

	var rot_bones: Array[String] = []
	var pos_bones: Array[String] = []
	var bad_paths: Array[String] = []
	for t in anim.get_track_count():
		var p := String(anim.track_get_path(t))
		if not p.begins_with("Armature/Skeleton3D:"):
			bad_paths.append(p)
			continue
		var bone := p.get_slice(":", 1)
		if anim.track_get_type(t) == Animation.TYPE_ROTATION_3D:
			rot_bones.append(bone)
		elif anim.track_get_type(t) == Animation.TYPE_POSITION_3D:
			pos_bones.append(bone)
	check("軌路徑全部指向 Skeleton3D", bad_paths.is_empty(), str(bad_paths))
	check("旋轉軌覆蓋 23 骨", rot_bones.size() == 23, "%d 骨" % rot_bones.size())
	check("只有 Hips 有位置軌", pos_bones == ["Hips"], str(pos_bones))

	# --- Hips 水平凍結（專案紅線）---
	for t in anim.get_track_count():
		if anim.track_get_type(t) != Animation.TYPE_POSITION_3D:
			continue
		var xs: Array[float] = []
		var ys: Array[float] = []
		var zs: Array[float] = []
		for k in anim.track_get_key_count(t):
			var v: Vector3 = anim.track_get_key_value(t, k)
			xs.append(v.x); ys.append(v.y); zs.append(v.z)
		var dx: float = xs.max() - xs.min()
		var dy: float = ys.max() - ys.min()
		var dz: float = zs.max() - zs.min()
		check("Hips 水平 X 凍結", is_zero_approx(dx), "跨度 %.6f" % dx)
		check("Hips 水平 Y 凍結", is_zero_approx(dy), "跨度 %.6f" % dy)
		# ⚠ 不能只驗「有起伏」：初版因 Blender 端多乘 100，跨度 1.4584 m
		#   （髖部飛到 4.7 m 高）照樣通過。必須驗**合理範圍**。
		check("Hips 垂直起伏在合理範圍（1~8 cm）",
			dz > 0.008 and dz < 0.08, "跨度 %.4f m" % dz)
		var z_rest := 0.9895   # FBX Hips rest Z（probe_yoriichi_rig 實測）
		check("Hips 垂直絕對值貼近 rest（沒有整體飄移）",
			absf(zs.min() - z_rest) < 0.08,
			"最低 %.4f vs rest %.4f" % [zs.min(), z_rest])


func _test_in_character() -> void:
	print("-- 角色端 --")
	var def: Dictionary = SunBreathing.FORMS[8]
	check("型表登記 READY", String(def.status) == "READY", String(def.status))
	check("型表指到 Attack_Thrust", String(def.anim) == "Attack_Thrust", String(def.anim))

	var scene: PackedScene = load("res://characters/yoriichi/player_yoriichi.tscn")
	var player: Node = scene.instantiate()
	get_root().add_child(player)
	await process_frame
	await process_frame

	var ap: AnimationPlayer = player.find_children("*", "AnimationPlayer", true, false)[0]
	check("AnimationPlayer 註冊得到 Attack_Thrust",
		ap.has_animation("Attack_Thrust"),
		str(ap.get_animation_list()).substr(0, 120))

	if ap.has_animation("Attack_Thrust"):
		var a := ap.get_animation("Attack_Thrust")
		check("註冊進去的長度一致", is_equal_approx(a.length, 1.25), "%.3f s" % a.length)

	# --- 發招 ---
	player.sun_mastery = 3          # 捌型 required_mastery = 3
	player.sun_breath_gauge = player.sun_breath_max
	player.sword_state = 2          # DRAWN
	player.action_state = 0         # FREE
	# ⚠ 無頭測試沒有地板，捌型 allowed_airborne = false 會被正當擋下。
	check("空中被擋（著地限定生效）",
		player.form_block_reason(8) == "airborne", player.form_block_reason(8))

	print("=== 驗證完成（發招需要地板，實機再驗）===")

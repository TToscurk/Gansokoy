extends SceneTree
## 反應動畫組：Blender GLB → Godot .res（五支：架勢／格擋受衝／彈刀／受擊／軀幹爆）。
##
## 執行：
##   godot --headless --path godot -s tools/build_react_clips.gd
##
## 沿用 build_form08_thrust.gd 的同一條管線（憲法第 1 條），差別只有：
##   * 一個 GLB 五個動作，跑一個 JOBS 表
##   * Hips 垂直**錨到 Idle_Grounded 首幀（0.9475）**而不是 FBX rest（0.9895）——
##     這幾支的首尾幀就是 Idle 姿，與 loco 層 Idle 混合時髖高必須一致，
##     否則 OneShot 淡入淡出會看到 4 cm 的上下彈。
##     （Idle_Grounded key0 z = 0.947505，headless 實測；Blender 端量到 0.9475 一致。）
##   * upper 層用的三支（Guard/Block/Deflect）Hips 位置軌照樣寫入 —— upper OneShot
##     的 bone filter 不含 Hips，這條軌在遊戲裡不會生效，留著是為了 .res 可獨立檢查。

## 兩個來源：架勢／格擋／彈刀 = Blender MCP 手調（IK 對刀柄、react_lib.py，
## 匯出 react_mcp.glb）；受擊／軀幹爆 = make_react_clips.py 姿勢表（react_clips.glb）。
const GLB := "res://characters/yoriichi/anim_src/react_clips.glb"
const GLB_MCP := "res://characters/yoriichi/anim_src/react_mcp.glb"
const FBX := "res://characters/yoriichi/yoriichi_body.fbx"
const GLB_FORMS := "res://characters/yoriichi/anim_src/form_clips.glb"
const GLB_IAI := "res://characters/yoriichi/anim_src/iai_clips.glb"
const IDLE_HIPS_Z := 0.947505
const JOBS := [
	{"src": "Guard_Hold",   "out": "res://characters/yoriichi/animations/yoriichi_guard_hold.res",   "loop": false, "glb": GLB_MCP},
	{"src": "Block_Impact", "out": "res://characters/yoriichi/animations/yoriichi_block_impact.res", "loop": false, "glb": GLB_MCP},
	{"src": "Deflect",      "out": "res://characters/yoriichi/animations/yoriichi_deflect.res",      "loop": false, "glb": GLB_MCP},
	{"src": "Hit_React",    "out": "res://characters/yoriichi/animations/yoriichi_hit_react.res",    "loop": false},
	{"src": "Stagger",      "out": "res://characters/yoriichi/animations/yoriichi_stagger.res",      "loop": false},
	# 日之呼吸缺件四型（tools/blender/make_form_clips.py，同一條姿勢表管線）
	{"src": "Form05_Turn",  "out": "res://characters/yoriichi/animations/yoriichi_form05_turn.res",  "loop": false, "glb": GLB_FORMS},
	{"src": "Form06_Wheel", "out": "res://characters/yoriichi/animations/yoriichi_form06_wheel.res", "loop": false, "glb": GLB_FORMS},
	{"src": "Form11_Halo",  "out": "res://characters/yoriichi/animations/yoriichi_form11_halo.res",  "loop": false, "glb": GLB_FORMS},
	{"src": "Form12_Dance", "out": "res://characters/yoriichi/animations/yoriichi_form12_dance.res",  "loop": false, "glb": GLB_FORMS},
	# 居合（RMB 蓄力）：Iai_Stance f0 Idle→f8 kamae→f32 循環；引擎用 custom timeline 只循環 f8 起。
	#   ⚠ anchor_first：Hips 錨到「Idle 端」而不是固定錨末鍵 —— Stance 末鍵是 kamae（蹲低 12 cm），
	#   錨末鍵會把蹲姿抬回 Idle 高度、f0 反而高出 12 cm。Slash 末鍵就是 Idle，照舊錨末。
	{"src": "Iai_Stance",   "out": "res://characters/yoriichi/animations/yoriichi_iai_stance.res",    "loop": false, "glb": GLB_IAI, "anchor_first": true},
	{"src": "Iai_Slash",    "out": "res://characters/yoriichi/animations/yoriichi_iai_slash.res",     "loop": false, "glb": GLB_IAI},
	# 拔刀斬預備跑步（Iai_Run）：純循環、原地、全身（蹲姿）。
	#   ⚠ 這支沒有 Idle 端點幀可錨（整支都是蹲姿跑），錨任何一鍵都會把蹲姿抬到 Idle 高度 →
	#   用 hips_ref 直接指定「Idle 姿的 GLB y」當基準（實測 Iai_Stance f0 = 101.28969，
	#   對照它的 kamae 蹲姿 y 101.17353 = 沉腰 11.6 cm）。蹲姿深度因此原樣保留。
	{"src": "Iai_Run",      "out": "res://characters/yoriichi/animations/yoriichi_iai_run.res",      "loop": true,  "glb": GLB_IAI, "hips_ref": 101.28969},
]


var _players := {}
var _insts: Array = []
var _hips_fix := {}


## Hips 根骨校正。Blender 端 FBX 匯入把 Armature 物件轉了 X−90°（骨架 Z-up），
## export_yup 匯 GLB 時該物件旋轉被烘進根骨 Hips 的旋轉鍵；Godot 端 FBX 匯入則把同一個
## X−90° 留在 Skeleton 的父節點上（實測 skeleton parent euler (−90, 0, 0)），骨頭鍵不含它。
## 所以 GLB 的 Hips 鍵要先乘掉 X+90° 才能放進 FBX 骨架。
## 實測：Idle_Grounded（Meshy 管線）Hips f0 euler (59.0, −23.8, −29.7)、
##       未校正的 Stagger／Guard_Hold（Idle 姿）(−28.1, −13.6, −2.4) —— 差的就是這一軸。
## 這也是 build_spin_slash.gd 對 Meshy GLB 做的 rot_x90（憲法第 1 條：同一套校正，不另發明）。
func _hips_fix_for(glb: String, _skel_fbx: Skeleton3D, _fbx_hips_rest: Transform3D) -> Quaternion:
	if _hips_fix.has(glb):
		return _hips_fix[glb]
	var q := Quaternion(Vector3(1, 0, 0), PI / 2.0)
	_hips_fix[glb] = q
	return q


func _player_for(glb: String) -> AnimationPlayer:
	if _players.has(glb):
		return _players[glb]
	var ps_glb := load(glb) as PackedScene
	if ps_glb == null:
		push_error("[反應] 載不到 GLB：" + glb)
		return null
	var inst_glb := ps_glb.instantiate()
	_insts.append(inst_glb)
	var aps := inst_glb.find_children("*", "AnimationPlayer", true, false)
	if aps.is_empty():
		push_error("[反應] GLB 裡沒有 AnimationPlayer：" + glb)
		return null
	print("[反應] %s 動畫：%s" % [glb.get_file(), str((aps[0] as AnimationPlayer).get_animation_list())])
	_players[glb] = aps[0]
	return aps[0]


func _init() -> void:

	var ps_fbx := load(FBX) as PackedScene
	var inst_fbx := ps_fbx.instantiate()
	var skel: Skeleton3D = inst_fbx.find_children("*", "Skeleton3D", true, false)[0]
	var hips_rest := skel.get_bone_rest(skel.find_bone("Hips"))
	# ⚠ Hips 是根骨：GLB（export_yup，根骨自帶 Y-up）與 FBX（Armature 節點 X-90 ＋ 骨架 Z-up）
	#   的 Hips 局部旋轉差一個 90°。子骨的 parent 都是同一根 Hips，鍵直接照抄沒問題；
	#   Hips 自己的旋轉鍵不校正 = 整個人躺下（實測：Stagger 腳趾離地 0.84 m、頭在髖後 0.32 m）。
	#   校正 = X+90°（見 _hips_fix_for；驗收：verify_react_anims 比對 Hips f0 與 Idle_Grounded）。
	_hips_fix = {}

	var failed := 0
	for job in JOBS:
		var ap := _player_for(String(job.get("glb", GLB)))
		if ap == null:
			failed += 1
			continue
		var src: Animation = null
		for n in ap.get_animation_list():
			if String(n) == String(job.src) or String(n).ends_with("/" + String(job.src)):
				src = ap.get_animation(n)
				break
		if src == null:
			push_error("[反應] GLB 缺 %s" % job.src)
			failed += 1
			continue
		var out_anim := Animation.new()
		out_anim.length = src.length
		out_anim.loop_mode = Animation.LOOP_LINEAR if job.loop else Animation.LOOP_NONE
		var n_pos := 0
		var n_rot := 0
		var skipped: Array[String] = []
		for t in src.get_track_count():
			var path := String(src.track_get_path(t))
			var bone := path.get_slice(":", 1) if path.contains(":") else path.get_file()
			var ttype := src.track_get_type(t)
			if skel.find_bone(bone) < 0:
				if not skipped.has(bone):
					skipped.append(bone)
				continue
			var new_path := "Armature/Skeleton3D:" + bone
			if ttype == Animation.TYPE_POSITION_3D:
				if bone != "Hips":
					continue
				var nt := out_anim.add_track(Animation.TYPE_POSITION_3D)
				out_anim.track_set_path(nt, new_path)
				out_anim.track_set_interpolation_type(nt, src.track_get_interpolation_type(t))
				# ⚠ GLB 是 glTF Y-up：Hips 位置軌的**垂直在 y**（x/z 全程常數）。
				#   之前讀 v.z（常數）→ 每支 clip 的髖部沉降全部被丟掉，Stagger 的
				#   「膝軟髖沉 12 cm」在遊戲裡從沒發生：膝彎了、髖沒沉、腳懸空。
				#   實測 form_clips.glb：y 跨度 = Blender 端 hips_z 設定值（公尺），x/z 跨度 0。
				#   基準取**最後一個 key**：匯出器把時間軸滑掉了約 1 幀（Form05 首 key 已在 −1.3 cm），
				#   末幀才是乾淨的 Idle 髖高 —— 淡回 loco 那一刻要對齊 0.9475，起手差 1 cm 被 fadein 吃掉。
				var base_y: float = 0.0
				if job.has("hips_ref"):
					# 明確給基準：純循環 clip 沒有 Idle 端點幀可錨（見 Iai_Run 的註解）
					base_y = float(job.get("hips_ref"))
				elif src.track_get_key_count(t) > 0:
					var anchor_key: int = 0 if bool(job.get("anchor_first", false)) else src.track_get_key_count(t) - 1
					var anchor_v: Vector3 = src.track_get_key_value(t, anchor_key)
					base_y = anchor_v.y
				for k in src.track_get_key_count(t):
					var v: Vector3 = src.track_get_key_value(t, k)
					out_anim.track_insert_key(nt, src.track_get_key_time(t, k), Vector3(
						hips_rest.origin.x, hips_rest.origin.y, IDLE_HIPS_Z + (v.y - base_y)))
				n_pos += 1
			elif ttype == Animation.TYPE_ROTATION_3D:
				var nt := out_anim.add_track(Animation.TYPE_ROTATION_3D)
				out_anim.track_set_path(nt, new_path)
				out_anim.track_set_interpolation_type(nt, src.track_get_interpolation_type(t))
				var fix: Quaternion = _hips_fix_for(String(job.get("glb", GLB)), skel, hips_rest) if bone == "Hips" else Quaternion.IDENTITY
				for k in src.track_get_key_count(t):
					var q: Quaternion = src.track_get_key_value(t, k)
					out_anim.track_insert_key(nt, src.track_get_key_time(t, k), (fix * q).normalized())
				n_rot += 1
		var err := ResourceSaver.save(out_anim, job.out)
		print("[反應] %s：位置軌 %d、旋轉軌 %d、%.3f s、loop=%s → %s（%d）" % [
			job.src, n_pos, n_rot, out_anim.length, str(job.loop), String(job.out).get_file(), err])
		if not skipped.is_empty():
			print("       略過非骨架軌：%s" % str(skipped))
		if err != OK:
			failed += 1

	for i in _insts:
		i.free()
	inst_fbx.free()
	quit(0 if failed == 0 else 1)

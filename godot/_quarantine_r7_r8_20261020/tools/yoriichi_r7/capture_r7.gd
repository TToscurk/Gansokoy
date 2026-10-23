extends SceneTree
## R7 第一階段展示擷取（複製自 tools/yoriichi_r62/capture_r62.gd；原檔不動；輸出 user://r7_moves/）。
## R6.2 擷取（複製自 tools/yoriichi_r61/capture_r61.gd；R6.1 原檔不動；輸出 user://r62_moves/）。需 rendering，不可 --headless。
## 與 R6.1 版差別：骨架 dump 改在 Skeleton3D.skeleton_updated 記錄（＝所有 SkeletonModifier3D（R6.2 握刀 IK、SpringBone）之後的最終
## 姿勢；Godot 4.3+ 在蒙皮後會把骨架還原成動畫姿勢，_process 讀到的是未修改的姿勢），並記錄 R6.2 IK 狀態。
## R6.1 驗收（複製自 tools/yoriichi_r6/capture_r6.gd；原檔不動；輸出 user://r61_moves/）。需 rendering，不可 --headless：
##   godot --path . --resolution 1280x720 --fixed-fps 30 -s tools/yoriichi_r6/capture_r6.gd -- 測項,逗號 [player.tscn] [輸出子資料夾]
## 鏡頭 dict 加："bone"（追骨頭近拍）、"dir"（角色本地方向，+Z=角色前方）、"dump"（逐格存全骨架 global pose → <測項>/poses.json）。
## 事件加：[t, "rig", 屬性, 值] 設 BodyVisual（YoriichiV24Rig）屬性，例如 springs_enabled。
## R5 測項逐格記錄 r5 狀態（clip 格、手上刀可見、刀身露出、hitbox monitoring）到 log.json。
## 測項 cam 參數 video=true 時每幀存圖（--fixed-fps 30 → 每張 = 1/30 s 遊戲時間）供合成 MP4。
## 原始說明：
##   godot --path . --resolution 1280x720 -s tools/v24_anim/capture_v24_moves.gd [-- 只跑的測項,逗號分隔]
## 自建測試場（地面、1.5 m 木箱、2.4 m 平台、6 m 高牆、5 m 高台），以 InputEventAction 模擬按鍵，
## 每個測項從固定位置開始，依時間點截圖（追身 3/4 鏡頭）並記錄狀態到 user://v24_moves/log.json。

var OUT := "user://r7_moves_v2/"
var _player_path := "res://characters/yoriichi/player_yoriichi.tscn"
var _vframe := 0
var _p: CharacterBody3D
var _cam: Camera3D
var _log := {}
var _tests: Array = []
var _ti := -1
var _t := 0.0
var _events: Array = []
var _shots_pending: Array = []
var _shot_wait := 0
var _cam_side := 1.0
var _only: PackedStringArray = []
var _fix_anchor := Vector3.INF
var _fix_dir := Vector3.FORWARD
var _dummy: Node3D = null
var _wolf_dumped := {}
var _wolf_live := false
var _evade_on_windup := 0
var _evaded := false
var _windup_t0 := -1.0
var _evade_delay := 0.0
var _hit_results: Array = []
var _tps_yaw := 1.0e9
var _grip_aim := Vector3.INF
var _grip_yaw := 1.0e9


func _on_player_hit(info: Dictionary) -> void:
	_hit_results.append([snappedf(_t, 0.01), str(info.get("result", "?")), snappedf(float(info.get("damage", 0.0)), 0.1)])


## 山犬可見模型（CPU 蒙皮後的世界頂點，抽樣）＋ Hurtbox 膠囊端點，給離線比對刀身接觸
func _wolf_snapshot() -> Dictionary:
	var pts := []
	for m in _dummy.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree() or mi.name == "Tell":
			continue
		var sk := mi.get_node_or_null(mi.skeleton) as Skeleton3D
		var skin: Skin = mi.skin
		for si in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(si)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var bones = arr[Mesh.ARRAY_BONES]
			var wts = arr[Mesh.ARRAY_WEIGHTS]
			var mats := []
			if sk != null and skin != null:
				for bi in skin.get_bind_count():
					var bidx := skin.get_bind_bone(bi)
					if bidx < 0:
						bidx = sk.find_bone(skin.get_bind_name(bi))
					mats.append(sk.global_transform * sk.get_bone_global_pose(bidx) * skin.get_bind_pose(bi))
			var step := maxi(1, vs.size() / 3000)
			var i := 0
			while i < vs.size():
				var v: Vector3 = vs[i]
				var wpos := Vector3.ZERO
				if not mats.is_empty() and bones != null and bones.size() >= (i + 1) * 4:
					var acc := Vector3.ZERO
					var ws := 0.0
					for k in 4:
						var w: float = wts[i * 4 + k]
						if w > 0.0:
							acc += w * ((mats[bones[i * 4 + k]] as Transform3D) * v)
							ws += w
					wpos = acc / maxf(ws, 1e-6)
				else:
					wpos = mi.global_transform * v
				pts.append([snappedf(wpos.x, 0.001), snappedf(wpos.y, 0.001), snappedf(wpos.z, 0.001)])
				i += step
	var hs := _dummy.get_node("Hurtbox/HurtShape") as CollisionShape3D
	var cap := hs.shape as CapsuleShape3D
	var ax := (hs.global_transform.basis.y).normalized() * (cap.height * 0.5 - cap.radius)
	var c := hs.global_position
	return {"pts": pts, "hurt": [[c.x - ax.x, c.y - ax.y, c.z - ax.z], [c.x + ax.x, c.y + ax.y, c.z + ax.z], cap.radius]}
var _hits_taken := 0

func _box(pos: Vector3, size: Vector3, col: Color) -> void:
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	b.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	mi.material_override = m
	b.add_child(mi)
	b.position = pos + Vector3(0, size.y * 0.5, 0)
	root.add_child(b)

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_only = args[0].split(",")
	if args.size() > 1 and args[1] != "":
		_player_path = args[1]
	if args.size() > 2:
		OUT = "user://r7_moves_v2/" + args[2] + "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	# 擷取期間忽略實體鍵鼠（測項只用 InputEventAction／action_press 驅動；桌面上其他程式的點擊不得觸發攻擊）
	for act in InputMap.get_actions():
		InputMap.action_erase_events(act)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.62, 0.68, 0.74)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.8, 0.8, 0.82)
	e.ambient_light_energy = 1.3
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 35, 0)
	sun.shadow_enabled = true
	root.add_child(sun)
	_box(Vector3(0, -1, 0), Vector3(200, 1, 200), Color(0.45, 0.42, 0.36))
	_box(Vector3(0, 0, -13.5), Vector3(4, 1.5, 3), Color(0.55, 0.4, 0.25))      # 木箱 1.5 m（攀上）
	_box(Vector3(8, 0, -13.5), Vector3(4, 2.4, 3), Color(0.5, 0.5, 0.55))      # 平台 2.4 m（蹬牆跑）
	_box(Vector3(-9, 0, 0), Vector3(1, 6, 10), Color(0.6, 0.58, 0.5))          # 高牆 6 m（踩牆跳）
	_box(Vector3(16, 0, 10), Vector3(4, 5, 4), Color(0.5, 0.45, 0.4))          # 高台 5 m（落地翻滾）
	_p = (load(_player_path) as PackedScene).instantiate()
	if _p.get("r7_vfx_enabled") != null and OS.get_environment("R7_CAP_VFX") != "1":
		_p.set("r7_vfx_enabled", false)      # R7 展示：關閉刀光與蓄力火焰（R7_CAP_VFX=1 → 保留既有刀光／火花，十三型 TPS 主片用）
	if OS.get_environment("R62_NOIK") == "1" and _p.get("r62_grip_ik_enabled") != null:
		_p.set("r62_grip_ik_enabled", false)      # A/B：同一 R6.2 場景關掉握刀 IK
	root.add_child(_p)
	_cam = Camera3D.new()
	_cam.fov = 50
	root.add_child(_cam)
	_cam.make_current()
	_tests = [
		["akesa_rside", Vector3(-55, 0, 10), PI, 4.4, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [101, true]]], [], 1, {"fixed": [-1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "video": true, "vstart": 2.0, "notrail": true}],
		["a02_rside", Vector3(-55, 0, 10), PI, 4.4, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [2, true]]], [], 1, {"fixed": [-1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "video": true, "vstart": 2.0, "notrail": true}],
		["a02_side", Vector3(-55, 0, -100), PI, 4.4, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [2, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "video": true, "vstart": 2.0, "notrail": true}],
		["a02_front", Vector3(-55, 0, -93), PI, 4.4, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [2, true]]], [], 1, {"fixed": [0.0, 0.08, 1.0], "dist": 3.6, "h": 1.0, "video": true, "vstart": 2.0, "notrail": true}],
		["a02_high", Vector3(-55, 0, -86), PI, 4.4, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [2, true]]], [], 1, {"fixed": [0.35, 0.85, 0.75], "dist": 3.8, "h": 1.0, "video": true, "vstart": 2.0, "notrail": true}],
		["a04_side", Vector3(-55, 0, -79), PI, 4.0, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [11, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "video": true, "vstart": 2.0, "notrail": true}],
		["a04_front", Vector3(-55, 0, -72), PI, 4.0, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [11, true]]], [], 1, {"fixed": [0.0, 0.08, 1.0], "dist": 3.6, "h": 1.0, "video": true, "vstart": 2.0, "notrail": true}],
		["a04_high", Vector3(-55, 0, -65), PI, 4.0, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [11, true]]], [], 1, {"fixed": [0.05, 1.0, 0.3], "dist": 4.6, "h": 0.5, "video": true, "vstart": 2.0, "notrail": true}],
		["akesa_side", Vector3(-55, 0, -58), PI, 4.2, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [101, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "video": true, "vstart": 2.0, "notrail": true}],
		["akesa_front", Vector3(-55, 0, -51), PI, 4.2, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [101, true]]], [], 1, {"fixed": [0.0, 0.08, 1.0], "dist": 3.6, "h": 1.0, "video": true, "vstart": 2.0, "notrail": true}],
		["akesa_high", Vector3(-55, 0, -44), PI, 4.2, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [101, true]]], [], 1, {"fixed": [0.35, 0.85, 0.75], "dist": 3.8, "h": 1.0, "video": true, "vstart": 2.0, "notrail": true}],
		["akesa_hit", Vector3(-55, 0, -37), PI, 4.2, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [101, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "video": true, "vstart": 2.0, "notrail": true, "dummy": 1.5}],
		["a02_hit", Vector3(-55, 0, -30), PI, 4.4, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [2, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "video": true, "vstart": 2.0, "notrail": true, "dummy": 1.4}],
		["a04_wall", Vector3(-55, 0, -23), PI, 4.0, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [11, true]]], [], 1, {"fixed": [0.05, 1.0, 0.3], "dist": 4.6, "h": 0.5, "video": true, "vstart": 2.0, "notrail": true, "wall_left": 0.6}],
		["a04_face", Vector3(-55, 0, -16), PI, 4.0, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [11, true]]], [], 1, {"fixed": [0.05, 1.0, 0.3], "dist": 4.6, "h": 0.5, "video": true, "vstart": 2.0, "notrail": true, "dummy": 2.0}],
		["k_stand_side", Vector3(-45, 0, -80), PI, 5.2, [[1.8, "call", "request_draw"]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.0, "h": 1.0, "video": true, "vstart": 0.4, "notrail": true, "dump": true}],
		["k_stand_rside", Vector3(-45, 0, -80), PI, 5.2, [[1.8, "call", "request_draw"]], [], 1, {"fixed": [-1.0, 0.0, 0.35], "dist": 3.0, "h": 1.0, "video": true, "vstart": 0.4, "notrail": true, "dump": true}],
		["k_stand_front", Vector3(-45, 0, -80), PI, 5.2, [[1.8, "call", "request_draw"]], [], 1, {"fixed": [0.0, 0.08, 1.0], "dist": 3.0, "h": 1.0, "video": true, "vstart": 0.4, "notrail": true}],
		["k_stand_tps", Vector3(-45, 0, -80), PI, 5.2, [[1.8, "call", "request_draw"]], [], 1, {"fixed": [0.30, 0.38, -1.0], "dist": 3.6, "h": 1.35, "video": true, "vstart": 0.4, "notrail": true}],
		["k_sheathe_side", Vector3(-45, 0, -80), PI, 5.0, [[0.1, "call", "request_draw"], [2.4, "call", "request_sword_toggle"]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.0, "h": 1.0, "video": true, "vstart": 1.8, "notrail": true, "dump": true}],
		["k_sheathe_front", Vector3(-45, 0, -80), PI, 5.0, [[0.1, "call", "request_draw"], [2.4, "call", "request_sword_toggle"]], [], 1, {"fixed": [0.0, 0.08, 1.0], "dist": 3.0, "h": 1.0, "video": true, "vstart": 1.8, "notrail": true}],
		["k_close_draw", Vector3(-45, 0, -80), PI, 4.4, [[1.8, "call", "request_draw"]], [], 1, {"fixed": [0.60, 0.08, 0.80], "dist": 1.15, "h": 1.04, "video": true, "vstart": 1.2, "notrail": true}],
		["k_close_sheathe", Vector3(-45, 0, -80), PI, 5.0, [[0.1, "call", "request_draw"], [2.4, "call", "request_sword_toggle"]], [], 1, {"fixed": [0.60, 0.08, 0.80], "dist": 1.15, "h": 1.04, "video": true, "vstart": 1.8, "notrail": true}],
		["k_close_chudan_r", Vector3(-45, 0, -80), PI, 4.4, [[1.8, "call", "request_draw"]], [], 1, {"fixed": [-0.72, 0.06, 0.70], "dist": 1.30, "h": 1.12, "video": true, "vstart": 1.2, "notrail": true}],
		# R7 P5 普通跳躍對照（R7_JUMP_VARIANT=r61|mx 由環境變數切換；同鏡頭、原速、無特效；輸入由程式呼叫 request_jump／action_press）
		["j5_idle_side", Vector3(-96, 0, 40), PI, 4.6, [[2.6, "call", "request_jump"]], [], 1, {"fixed": [1.0, 0.0, 0.25], "dist": 5.4, "h": 1.75, "video": true, "vstart": 2.2, "notrail": true}],
		["j5_move_side", Vector3(-96, 0, 60), PI, 5.0, [[2.0, "hold", "move_forward"], [2.7, "call", "request_jump"], [3.8, "release", "move_forward"]], [], 1, {"fixed": [1.0, 0.0, 0.0], "fixed_at": [-96.0, 56.6], "dist": 7.4, "h": 1.6, "video": true, "vstart": 2.2, "notrail": true}],
		["j5_tps", Vector3(-96, 0, 85), PI, 7.2, [[1.6, "hold", "move_forward"], [2.4, "call", "request_jump"], [3.9, "release", "move_forward"], [5.0, "call", "request_jump"]], [], 1, {"tps": true, "dist": 4.6, "h": 1.7, "video": true, "vstart": 1.4, "notrail": true}],
		# R7K v3 診斷（羽織隱藏，只供查左手／鞘口／刀尖對位；不作正式美術圖）
		["k_diag_draw", Vector3(-45, 0, -80), PI, 4.4, [[1.8, "call", "request_draw"]], [], 1, {"bone": "mixamorig_Hips", "dir": [0.75, 0.05, 0.65], "dist": 1.15, "video": true, "vstart": 1.2, "notrail": true, "hide": ["羽織"]}],
		["k_diag_noto", Vector3(-45, 0, -80), PI, 5.0, [[0.1, "call", "request_draw"], [2.4, "call", "request_sword_toggle"]], [], 1, {"bone": "mixamorig_Hips", "dir": [0.75, 0.05, 0.65], "dist": 1.15, "video": true, "vstart": 1.8, "notrail": true, "hide": ["羽織"]}],
		["k_walk_side", Vector3(-45, 0, -60), PI, 9.4, [[0.2, "call", "request_draw"], [1.2, "call", "toggle_lock_on"], [2.0, "hold", "walk"], [2.0, "hold", "move_forward"], [3.4, "release", "move_forward"], [3.9, "hold", "move_back"], [5.3, "release", "move_back"], [5.8, "hold", "move_left"], [7.0, "release", "move_left"], [7.5, "hold", "move_right"], [8.7, "release", "move_right"], [8.7, "release", "walk"]], [], 1, {"bone": "mixamorig_Hips", "dir": [1.0, 0.05, 0.10], "dist": 3.4, "video": true, "vstart": 1.6, "notrail": true, "dummy": 6.0}],
		["k_walk_front", Vector3(-45, 0, -60), PI, 9.4, [[0.2, "call", "request_draw"], [1.2, "call", "toggle_lock_on"], [2.0, "hold", "walk"], [2.0, "hold", "move_forward"], [3.4, "release", "move_forward"], [3.9, "hold", "move_back"], [5.3, "release", "move_back"], [5.8, "hold", "move_left"], [7.0, "release", "move_left"], [7.5, "hold", "move_right"], [8.7, "release", "move_right"], [8.7, "release", "walk"]], [], 1, {"bone": "mixamorig_Hips", "dir": [0.10, 0.05, 1.0], "dist": 3.4, "video": true, "vstart": 1.6, "notrail": true, "dummy": 6.0}],
		["h03_front_on", Vector3(40, 0, -90), PI, 4.2, [[0.2, "call", "request_draw"], [0.3, "callv", "r7_set_blade_sweep", [true]], [2.2, "callv", "execute_form", [3, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "dummy": [0.00, 1.20]}],
		["h03_front_off", Vector3(55, 0, -90), PI, 4.2, [[0.2, "call", "request_draw"], [0.3, "callv", "r7_set_blade_sweep", [false]], [2.2, "callv", "execute_form", [3, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "dummy": [0.00, 1.20]}],
		["h03_right_on", Vector3(40, 0, -84), PI, 4.2, [[0.2, "call", "request_draw"], [0.3, "callv", "r7_set_blade_sweep", [true]], [2.2, "callv", "execute_form", [3, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "dummy": [1.00, 0.00]}],
		["h03_right_off", Vector3(55, 0, -84), PI, 4.2, [[0.2, "call", "request_draw"], [0.3, "callv", "r7_set_blade_sweep", [false]], [2.2, "callv", "execute_form", [3, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "dummy": [1.00, 0.00]}],
		["h03_left_on", Vector3(40, 0, -78), PI, 4.2, [[0.2, "call", "request_draw"], [0.3, "callv", "r7_set_blade_sweep", [true]], [2.2, "callv", "execute_form", [3, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "dummy": [-1.10, 0.80]}],
		["h03_left_off", Vector3(55, 0, -78), PI, 4.2, [[0.2, "call", "request_draw"], [0.3, "callv", "r7_set_blade_sweep", [false]], [2.2, "callv", "execute_form", [3, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "dummy": [-1.10, 0.80]}],
		["h03_oldonly_on", Vector3(40, 0, -72), PI, 4.2, [[0.2, "call", "request_draw"], [0.3, "callv", "r7_set_blade_sweep", [true]], [2.2, "callv", "execute_form", [3, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "dummy": [-1.20, 0.40]}],
		["h03_oldonly_off", Vector3(55, 0, -72), PI, 4.2, [[0.2, "call", "request_draw"], [0.3, "callv", "r7_set_blade_sweep", [false]], [2.2, "callv", "execute_form", [3, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "dummy": [-1.20, 0.40]}],
		["h03_bladeonly_on", Vector3(40, 0, -66), PI, 4.2, [[0.2, "call", "request_draw"], [0.3, "callv", "r7_set_blade_sweep", [true]], [2.2, "callv", "execute_form", [3, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "dummy": [-1.00, 1.30]}],
		["h03_bladeonly_off", Vector3(55, 0, -66), PI, 4.2, [[0.2, "call", "request_draw"], [0.3, "callv", "r7_set_blade_sweep", [false]], [2.2, "callv", "execute_form", [3, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "dummy": [-1.00, 1.30]}],
		["h03_miss_on", Vector3(40, 0, -60), PI, 4.2, [[0.2, "call", "request_draw"], [0.3, "callv", "r7_set_blade_sweep", [true]], [2.2, "callv", "execute_form", [3, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "dummy": [0.00, 1.90]}],
		["h03_miss_off", Vector3(55, 0, -60), PI, 4.2, [[0.2, "call", "request_draw"], [0.3, "callv", "r7_set_blade_sweep", [false]], [2.2, "callv", "execute_form", [3, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "dummy": [0.00, 1.90]}],
		["h08_front_on", Vector3(40, 0, -54), PI, 4.2, [[0.2, "call", "request_draw"], [0.3, "callv", "r7_set_blade_sweep", [true]], [2.2, "callv", "execute_form", [6, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "dummy": [0.00, 1.40]}],
		["h08_front_off", Vector3(55, 0, -54), PI, 4.2, [[0.2, "call", "request_draw"], [0.3, "callv", "r7_set_blade_sweep", [false]], [2.2, "callv", "execute_form", [6, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "dummy": [0.00, 1.40]}],
		["h08_right_on", Vector3(40, 0, -48), PI, 4.2, [[0.2, "call", "request_draw"], [0.3, "callv", "r7_set_blade_sweep", [true]], [2.2, "callv", "execute_form", [6, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "dummy": [0.35, 1.30]}],
		["h08_right_off", Vector3(55, 0, -48), PI, 4.2, [[0.2, "call", "request_draw"], [0.3, "callv", "r7_set_blade_sweep", [false]], [2.2, "callv", "execute_form", [6, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "dummy": [0.35, 1.30]}],
		["h08_left_on", Vector3(40, 0, -42), PI, 4.2, [[0.2, "call", "request_draw"], [0.3, "callv", "r7_set_blade_sweep", [true]], [2.2, "callv", "execute_form", [6, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "dummy": [-0.90, 1.00]}],
		["h08_left_off", Vector3(55, 0, -42), PI, 4.2, [[0.2, "call", "request_draw"], [0.3, "callv", "r7_set_blade_sweep", [false]], [2.2, "callv", "execute_form", [6, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "dummy": [-0.90, 1.00]}],
		["h08_oldonly_on", Vector3(40, 0, -36), PI, 4.2, [[0.2, "call", "request_draw"], [0.3, "callv", "r7_set_blade_sweep", [true]], [2.2, "callv", "execute_form", [6, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "dummy": [0.60, 1.00]}],
		["h08_oldonly_off", Vector3(55, 0, -36), PI, 4.2, [[0.2, "call", "request_draw"], [0.3, "callv", "r7_set_blade_sweep", [false]], [2.2, "callv", "execute_form", [6, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "dummy": [0.60, 1.00]}],
		["h08_rightout_on", Vector3(40, 0, -30), PI, 4.2, [[0.2, "call", "request_draw"], [0.3, "callv", "r7_set_blade_sweep", [true]], [2.2, "callv", "execute_form", [6, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "dummy": [0.90, 1.00]}],
		["h08_rightout_off", Vector3(55, 0, -30), PI, 4.2, [[0.2, "call", "request_draw"], [0.3, "callv", "r7_set_blade_sweep", [false]], [2.2, "callv", "execute_form", [6, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "dummy": [0.90, 1.00]}],
		["h08_miss_on", Vector3(40, 0, -24), PI, 4.2, [[0.2, "call", "request_draw"], [0.3, "callv", "r7_set_blade_sweep", [true]], [2.2, "callv", "execute_form", [6, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "dummy": [0.00, 2.00]}],
		["h08_miss_off", Vector3(55, 0, -24), PI, 4.2, [[0.2, "call", "request_draw"], [0.3, "callv", "r7_set_blade_sweep", [false]], [2.2, "callv", "execute_form", [6, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "dummy": [0.00, 2.00]}],
		["h11_front_on", Vector3(40, 0, -18), PI, 5.0, [[0.2, "call", "request_draw"], [0.3, "callv", "r7_set_blade_sweep", [true]], [2.2, "callv", "execute_form", [9, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "dummy": [0.00, 1.60]}],
		["h11_front_off", Vector3(55, 0, -18), PI, 5.0, [[0.2, "call", "request_draw"], [0.3, "callv", "r7_set_blade_sweep", [false]], [2.2, "callv", "execute_form", [9, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "dummy": [0.00, 1.60]}],
		["h11_right_on", Vector3(40, 0, -12), PI, 5.0, [[0.2, "call", "request_draw"], [0.3, "callv", "r7_set_blade_sweep", [true]], [2.2, "callv", "execute_form", [9, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "dummy": [1.00, 1.30]}],
		["h11_right_off", Vector3(55, 0, -12), PI, 5.0, [[0.2, "call", "request_draw"], [0.3, "callv", "r7_set_blade_sweep", [false]], [2.2, "callv", "execute_form", [9, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "dummy": [1.00, 1.30]}],
		["h11_left_on", Vector3(40, 0, -6), PI, 5.0, [[0.2, "call", "request_draw"], [0.3, "callv", "r7_set_blade_sweep", [true]], [2.2, "callv", "execute_form", [9, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "dummy": [-0.90, 1.40]}],
		["h11_left_off", Vector3(55, 0, -6), PI, 5.0, [[0.2, "call", "request_draw"], [0.3, "callv", "r7_set_blade_sweep", [false]], [2.2, "callv", "execute_form", [9, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "dummy": [-0.90, 1.40]}],
		["h11_oldonly_on", Vector3(40, 0, 0), PI, 5.0, [[0.2, "call", "request_draw"], [0.3, "callv", "r7_set_blade_sweep", [true]], [2.2, "callv", "execute_form", [9, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "dummy": [0.90, 0.80]}],
		["h11_oldonly_off", Vector3(55, 0, 0), PI, 5.0, [[0.2, "call", "request_draw"], [0.3, "callv", "r7_set_blade_sweep", [false]], [2.2, "callv", "execute_form", [9, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "dummy": [0.90, 0.80]}],
		["h11_bladeonly_on", Vector3(40, 0, 6), PI, 5.0, [[0.2, "call", "request_draw"], [0.3, "callv", "r7_set_blade_sweep", [true]], [2.2, "callv", "execute_form", [9, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "dummy": [1.00, 2.20]}],
		["h11_bladeonly_off", Vector3(55, 0, 6), PI, 5.0, [[0.2, "call", "request_draw"], [0.3, "callv", "r7_set_blade_sweep", [false]], [2.2, "callv", "execute_form", [9, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "dummy": [1.00, 2.20]}],
		["h11_miss_on", Vector3(40, 0, 12), PI, 5.0, [[0.2, "call", "request_draw"], [0.3, "callv", "r7_set_blade_sweep", [true]], [2.2, "callv", "execute_form", [9, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "dummy": [0.00, 2.80]}],
		["h11_miss_off", Vector3(55, 0, 12), PI, 5.0, [[0.2, "call", "request_draw"], [0.3, "callv", "r7_set_blade_sweep", [false]], [2.2, "callv", "execute_form", [9, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "dummy": [0.00, 2.80]}],
		["h11_close_on", Vector3(85, 0, -60), PI, 5.0, [[0.2, "call", "request_draw"], [0.3, "callv", "r7_set_blade_sweep", [true]], [2.2, "callv", "execute_form", [9, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "dummy": [0.0, 1.4]}],
		["h11_close_off", Vector3(85, 0, -50), PI, 5.0, [[0.2, "call", "request_draw"], [0.3, "callv", "r7_set_blade_sweep", [false]], [2.2, "callv", "execute_form", [9, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "dummy": [0.0, 1.4]}],
		["h11_c1a_on", Vector3(85, 0, -40), PI, 5.0, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [9, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "dummy": [0.00, 1.00]}],
		["h11_c1b_on", Vector3(85, 0, -34), PI, 5.0, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [9, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "dummy": [-0.35, 1.00]}],
		["h11_c1c_on", Vector3(85, 0, -28), PI, 5.0, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [9, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "dummy": [0.30, 1.10]}],
		["h11_c1d_on", Vector3(85, 0, -22), PI, 5.0, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [9, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "dummy": [-0.20, 0.85]}],
		["h03_oldonly2_on", Vector3(85, 0, -16), PI, 4.2, [[0.2, "call", "request_draw"], [0.3, "callv", "r7_set_blade_sweep", [true]], [2.2, "callv", "execute_form", [3, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "dummy": [-1.3, 0.6]}],
		["h03_oldonly2_off", Vector3(85, 0, -10), PI, 4.2, [[0.2, "call", "request_draw"], [0.3, "callv", "r7_set_blade_sweep", [false]], [2.2, "callv", "execute_form", [3, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "dummy": [-1.3, 0.6]}],
		["h03_oldonly3_on", Vector3(85, 0, 2), PI, 4.2, [[0.2, "call", "request_draw"], [0.3, "callv", "r7_set_blade_sweep", [true]], [2.2, "callv", "execute_form", [3, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "dummy": [-0.85, 0.15]}],
		["h03_oldonly3_off", Vector3(85, 0, 5), PI, 4.2, [[0.2, "call", "request_draw"], [0.3, "callv", "r7_set_blade_sweep", [false]], [2.2, "callv", "execute_form", [3, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "dummy": [-0.85, 0.15]}],
		["h03_oldonly4_on", Vector3(85, 0, 8), PI, 4.2, [[0.2, "call", "request_draw"], [0.3, "callv", "r7_set_blade_sweep", [true]], [2.2, "callv", "execute_form", [3, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "dummy": [-0.95, 0.35]}],
		["h03_oldonly4_off", Vector3(85, 0, 11), PI, 4.2, [[0.2, "call", "request_draw"], [0.3, "callv", "r7_set_blade_sweep", [false]], [2.2, "callv", "execute_form", [3, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "dummy": [-0.95, 0.35]}],
		["h11_c1b_on2", Vector3(85, 0, 20), PI, 5.0, [[0.2, "call", "request_draw"], [0.3, "callv", "r7_set_blade_sweep", [true]], [2.2, "callv", "execute_form", [9, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "dummy": [-0.35, 1.0]}],
		["h11_c1b_off2", Vector3(85, 0, 26), PI, 5.0, [[0.2, "call", "request_draw"], [0.3, "callv", "r7_set_blade_sweep", [false]], [2.2, "callv", "execute_form", [9, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "dummy": [-0.35, 1.0]}],
		["h01_d100", Vector3(85, 0, 30), PI, 4.2, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [1, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "dummy": [0.0, 1.00]}],
		["h01_d110", Vector3(85, 0, 36), PI, 4.2, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [1, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "dummy": [0.0, 1.10]}],
		["h01_d120", Vector3(85, 0, 42), PI, 4.2, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [1, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "dummy": [0.0, 1.20]}],
		["h01_d90", Vector3(85, 0, 48), PI, 4.2, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [1, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "dummy": [0.0, 0.90]}],
		["h01_d130_off", Vector3(85, 0, 54), PI, 4.2, [[0.2, "call", "request_draw"], [0.3, "callv", "r7_set_blade_sweep", [false]], [2.2, "callv", "execute_form", [1, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "dummy": [0.0, 1.3]}],
		["h01_d130_on", Vector3(85, 0, 60), PI, 4.2, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [1, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "dummy": [0.0, 1.3]}],
		["w03_front", Vector3(25, 0, -80), PI, 4.2, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [3, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "wolf": [0.00, 1.40, 0]}],
		["w03_left", Vector3(25, 0, -72), PI, 4.2, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [3, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "wolf": [-1.00, 0.60, 90]}],
		["w03_right", Vector3(25, 0, -64), PI, 4.2, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [3, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "wolf": [1.00, 0.20, 90]}],
		["w08_front", Vector3(25, 0, -56), PI, 4.2, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [6, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "wolf": [0.00, 1.50, 0]}],
		["w08_left", Vector3(25, 0, -48), PI, 4.2, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [6, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "wolf": [-0.80, 1.00, 90]}],
		["w08_right", Vector3(25, 0, -40), PI, 4.2, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [6, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "wolf": [0.50, 1.20, 90]}],
		["w11_front", Vector3(25, 0, -32), PI, 5.0, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [9, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "wolf": [0.00, 1.80, 0]}],
		["w11_left", Vector3(25, 0, -24), PI, 5.0, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [9, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "wolf": [-0.90, 1.40, 90]}],
		["w11_right", Vector3(25, 0, -16), PI, 5.0, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [9, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "wolf": [1.00, 1.30, 90]}],
		["w11_close", Vector3(25, 0, -8), PI, 5.0, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [9, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "wolf": [-0.35, 1.10, 0]}],
		["w11_trans", Vector3(25, 0, 0), PI, 5.0, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [9, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "wolf": [0.90, 0.80, 0]}],
		["w11_int", Vector3(25, 0, 8), PI, 5.0, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [9, true]], [2.62, "hit"]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "wolf": [-0.35, 1.1, 0]}],
		["v03_sf", Vector3(10, 0, -80), PI, 4.2, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [3, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "wolf": [0.00, 1.45, 90]}],
		["v03_hf", Vector3(10, 0, -72), PI, 4.2, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [3, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "wolf": [0.00, 2.00, 0]}],
		["v03_l", Vector3(10, 0, -64), PI, 4.2, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [3, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "wolf": [-1.30, 0.70, 90]}],
		["v03_r", Vector3(10, 0, -56), PI, 4.2, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [3, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "wolf": [1.20, 0.50, 90]}],
		["v08_sf", Vector3(10, 0, -48), PI, 4.2, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [6, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "wolf": [0.00, 1.45, 90]}],
		["v08_hf", Vector3(10, 0, -40), PI, 4.2, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [6, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "wolf": [0.00, 2.00, 0]}],
		["v08_l", Vector3(10, 0, -32), PI, 4.2, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [6, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "wolf": [-1.30, 0.70, 90]}],
		["v08_r", Vector3(10, 0, -24), PI, 4.2, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [6, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "wolf": [1.20, 0.50, 90]}],
		["v11_sf", Vector3(10, 0, -16), PI, 5.0, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [9, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "wolf": [0.00, 1.45, 90]}],
		["v11_hf", Vector3(10, 0, -8), PI, 5.0, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [9, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "wolf": [0.00, 2.00, 0]}],
		["v11_l", Vector3(10, 0, 0), PI, 5.0, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [9, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "wolf": [-1.30, 0.70, 90]}],
		["v11_r", Vector3(10, 0, 8), PI, 5.0, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [9, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "wolf": [1.20, 0.50, 90]}],
		["v11_close", Vector3(10, 0, 16), PI, 5.0, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [9, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "wolf": [0.00, 1.20, 90]}],
		["v11_int", Vector3(10, 0, 24), PI, 5.0, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [9, true]], [2.62, "hit"]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "wolf": [0.00, 1.20, 90]}],
		["v11_trans", Vector3(10, 0, 32), PI, 5.0, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [9, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "wolf": [1.10, 0.90, 90]}],
		["b02", Vector3(-30, 0, -90), PI, 4.4, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [2, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "video": true, "vstart": 2.0, "notrail": true}],
		["b02_front", Vector3(-30, 0, -82), PI, 4.4, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [2, true]]], [], 1, {"fixed": [0.12, 0.05, 1.0], "dist": 3.6, "h": 1.0, "video": true, "vstart": 2.0, "notrail": true}],
		["b02_high", Vector3(-30, 0, -74), PI, 4.4, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [2, true]]], [], 1, {"fixed": [0.35, 0.85, 0.75], "dist": 3.8, "h": 1.0, "video": true, "vstart": 2.0, "notrail": true}],
		["b04", Vector3(-30, 0, -66), PI, 4.0, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [11, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "video": true, "vstart": 2.0, "notrail": true}],
		["b04_front", Vector3(-30, 0, -58), PI, 4.0, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [11, true]]], [], 1, {"fixed": [0.12, 0.05, 1.0], "dist": 3.6, "h": 1.0, "video": true, "vstart": 2.0, "notrail": true}],
		["b04_top", Vector3(-30, 0, -50), PI, 4.0, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [11, true]]], [], 1, {"fixed": [0.05, 1.0, 0.3], "dist": 4.6, "h": 0.5, "video": true, "vstart": 2.0, "notrail": true}],
		["b02_hit", Vector3(-30, 0, -42), PI, 4.4, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [2, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "video": true, "vstart": 2.0, "notrail": true, "dummy": 1.3}],
		["b02_hit_r", Vector3(-30, 0, -34), PI, 4.4, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [2, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "dummy": [0.5, 1.1]}],
		["v02_sf", Vector3(-30, 0, -26), PI, 4.4, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [2, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "wolf": [0.0, 1.45, 90]}],
		["v02_hf", Vector3(-30, 0, -18), PI, 4.4, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [2, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "wolf": [0.0, 2.0, 0]}],
		["b04_nodmg", Vector3(-30, 0, -10), PI, 4.0, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [11, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "dummy": [-0.6, 0.8]}],
		["b04_wall", Vector3(-30, 0, -2), PI, 4.0, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [11, true]]], [], 1, {"fixed": [0.05, 1.0, 0.3], "dist": 4.6, "h": 0.5, "video": true, "vstart": 2.0, "notrail": true, "wall_left": 0.6}],
		["b04_face", Vector3(-30, 0, 6), PI, 4.0, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [11, true]]], [], 1, {"fixed": [0.05, 1.0, 0.3], "dist": 4.6, "h": 0.5, "video": true, "vstart": 2.0, "notrail": true, "dummy": 2.0}],
		["b04_wolf", Vector3(-30, 0, 14), PI, 8.0, [[0.2, "call", "request_draw"]], [], 1, {"fixed": [0.05, 1.0, 0.3], "dist": 6.0, "h": 0.5, "video": true, "vstart": 0.5, "notrail": true, "wolf": [0.0, 4.5, 0], "wolf_live": true, "evade_on_windup": 11, "evade_delay": 0.85}],
		["b04_wolf_noevade", Vector3(-30, 0, 22), PI, 8.0, [[0.2, "call", "request_draw"]], [], 1, {"fixed": [0.05, 1.0, 0.3], "dist": 6.0, "h": 0.5, "notrail": true, "wolf": [0.0, 4.5, 0], "wolf_live": true, "wolf_lunge_only": true}],
		["c02_dodge", Vector3(-30, 0, 30), PI, 4.4, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [2, true]], [2.77, "call", "request_dodge"], [3.01, "call", "request_dodge"]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "video": true, "vstart": 2.0, "notrail": true}],
		["c04_dodge", Vector3(-30, 0, 38), PI, 4.0, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [11, true]], [2.54, "call", "request_dodge"], [2.85, "call", "request_dodge"]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true}],
		["v11_int2", Vector3(-30, 0, 46), PI, 5.0, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [9, true]], [2.95, "hit"]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "wolf": [0.0, 1.2, 90]}],
		["b04_wolf_iframe", Vector3(-30, 0, 60), PI, 8.0, [[0.2, "call", "request_draw"]], [], 1, {"fixed": [0.05, 1.0, 0.3], "dist": 6.0, "h": 0.5, "video": true, "vstart": 0.5, "notrail": true, "wolf": [0.0, 4.5, 0], "wolf_live": true, "wolf_lunge_only": true, "evade_on_windup": 11, "evade_delay": 1.08}],
		["c04_dodge2", Vector3(-30, 0, 70), PI, 4.0, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [11, true]], [2.80, "call", "request_dodge"], [2.93, "call", "request_dodge"]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true}],
		["b04_wallface", Vector3(-30, 0, 80), PI, 4.0, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [11, true]]], [], 1, {"fixed": [0.05, 1.0, 0.3], "dist": 4.6, "h": 0.5, "video": true, "vstart": 2.0, "notrail": true, "wall_left": 0.6, "dummy": [-0.6, 1.6]}],
		["h11_int_mid", Vector3(70, 0, 18), PI, 5.0, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [9, true]], [2.49, "hit"]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "dummy": [-0.35, 1.0]}],
		["h11_int_after1", Vector3(70, 0, 24), PI, 5.0, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [9, true]], [2.62, "hit"]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "dummy": [-0.35, 1.0]}],
		["b03", Vector3(-82, 0, -60), PI, 4.2, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [3, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "video": true, "vstart": 2.0, "notrail": true}],
		["b03_front", Vector3(-82, 0, -50), PI, 4.2, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [3, true]]], [], 1, {"fixed": [0.12, 0.05, 1.0], "dist": 3.4, "h": 1.1, "video": true, "vstart": 2.0, "notrail": true}],
		["b08", Vector3(-82, 0, -40), PI, 4.2, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [6, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "video": true, "vstart": 2.0, "notrail": true}],
		["b08_front", Vector3(-82, 0, -30), PI, 4.2, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [6, true]]], [], 1, {"fixed": [0.12, 0.05, 1.0], "dist": 3.4, "h": 1.1, "video": true, "vstart": 2.0, "notrail": true}],
		["b11", Vector3(-82, 0, -20), PI, 5.0, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [9, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "video": true, "vstart": 2.0, "notrail": true}],
		["b11_front", Vector3(-82, 0, -10), PI, 5.0, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [9, true]]], [], 1, {"fixed": [0.12, 0.05, 1.0], "dist": 4.6, "h": 0.95, "video": true, "vstart": 2.0, "notrail": true}],
		["b03_high", Vector3(-82, 0, 60), PI, 4.2, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [3, true]]], [], 1, {"fixed": [0.35, 0.85, 0.75], "dist": 3.6, "h": 1.0, "video": true, "vstart": 2.0, "notrail": true}],
		["b08_high", Vector3(-82, 0, 70), PI, 4.2, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [6, true]]], [], 1, {"fixed": [0.35, 0.85, 0.75], "dist": 3.6, "h": 1.0, "video": true, "vstart": 2.0, "notrail": true}],
		["b03_hit", Vector3(-82, 0, -60), PI, 4.2, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [3, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "video": true, "vstart": 2.0, "notrail": true, "dummy": 1.5}],
		["b08_hit", Vector3(-82, 0, -50), PI, 4.2, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [6, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "video": true, "vstart": 2.0, "notrail": true, "dummy": 1.6}],
		["b11_hit", Vector3(-82, 0, -40), PI, 5.0, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [9, true]]], [], 1, {"fixed": [1.0, 0.0, 0.2], "dist": 4.0, "h": 1.0, "video": true, "vstart": 2.0, "notrail": true, "dummy": 1.9}],
		["b11_hit_close", Vector3(-82, 0, 50), PI, 5.0, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [9, true]]], [], 1, {"fixed": [1.0, 0.0, 0.2], "dist": 4.0, "h": 1.0, "video": true, "vstart": 2.0, "notrail": true, "dummy": 1.4}],
		["b11_int", Vector3(-82, 0, -30), PI, 5.0, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [9, true]], [2.75, "hit"], [3.8, "tap", "attack_light"]], [], 1, {"fixed": [1.0, 0.0, 0.2], "dist": 4.0, "h": 1.0, "video": true, "vstart": 2.0, "notrail": true, "dummy": 1.9}],
		["b_branch08", Vector3(-82, 0, -20), PI, 4.6, [[0.2, "call", "request_draw"], [2.4, "tap", "attack_light"], [2.5, "tap", "attack_heavy"]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "video": true, "vstart": 2.2, "notrail": true}],
		["c03_dodge", Vector3(-82, 0, 60), PI, 4.2, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [3, true]], [2.68, "call", "request_dodge"], [2.80, "call", "request_dodge"]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "video": true, "vstart": 2.0, "notrail": true}],
		["c08_guard", Vector3(-82, 0, 70), PI, 4.2, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [6, true]], [2.575, "call", "begin_guard"], [2.725, "call", "begin_guard"], [3.6, "call", "end_guard"]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "video": true, "vstart": 2.0, "notrail": true}],
		["f_chain03", Vector3(-82, 0, 80), PI, 4.6, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [3, true]], [2.45, "tap", "attack_heavy"], [2.85, "tap", "attack_heavy"]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true}],
		["c12_dodge", Vector3(-82, 0, -10), PI, 4.6, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [12, true]], [2.75, "call", "request_dodge"], [3.135, "call", "request_dodge"]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "video": true, "vstart": 2.0, "notrail": true}],
		["c07_guard", Vector3(-82, 0, 0), PI, 4.2, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [8, true]], [2.43, "call", "begin_guard"], [2.69, "call", "begin_guard"], [3.6, "call", "end_guard"]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "video": true, "vstart": 2.0, "notrail": true}],
		["c01_dodge", Vector3(-82, 0, 10), PI, 4.2, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [1, true]], [2.56, "call", "request_dodge"], [2.74, "call", "request_dodge"]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true}],
		["c11_dodge_mid", Vector3(-82, 0, 20), PI, 5.0, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [9, true]], [3.20, "call", "request_dodge"], [3.40, "call", "request_dodge"]], [], 1, {"fixed": [1.0, 0.0, 0.2], "dist": 4.0, "h": 1.0, "video": true, "vstart": 2.0, "notrail": true}],
		["s_sprint07_follow", Vector3(-82, 0, 30), PI, 4.6, [[0.2, "call", "request_draw"], [2.0, "hold", "sprint"], [2.0, "hold", "move_forward"], [3.0, "tap", "attack_heavy"], [3.05, "release", "move_forward"], [3.05, "release", "sprint"]], [], 1, {"bone": "mixamorig_Hips", "dir": [1.0, 0.05, 0.15], "dist": 3.4, "video": true, "vstart": 2.5, "notrail": true, "dummy": 9.4}],
		["s07_wall_mid", Vector3(-82, 0, 40), PI, 4.0, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [8, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "video": true, "vstart": 2.0, "notrail": true, "wall": 0.9}],
		["s07_near", Vector3(-90, 0, -60), PI, 4.0, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [8, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "video": true, "vstart": 2.0, "notrail": true, "dummy": 1.0}],
		["s07_long", Vector3(-90, 0, -50), PI, 4.0, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [8, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "notrail": true, "dummy": 2.3}],
		["s07_wall", Vector3(-90, 0, -40), PI, 4.0, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [8, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "video": true, "vstart": 2.0, "notrail": true, "wall": 0.9}],
		["s07_wall_close", Vector3(-90, 0, -70), PI, 4.0, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [8, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "video": true, "vstart": 2.0, "notrail": true, "wall": 0.55}],
		["s07_free", Vector3(-90, 0, -30), PI, 4.0, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [8, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "video": true, "vstart": 2.0, "notrail": true}],
		["s_sprint07_hit", Vector3(-90, 0, -20), PI, 5.0, [[0.2, "call", "request_draw"], [2.0, "hold", "sprint"], [2.0, "hold", "move_forward"], [3.0, "tap", "attack_heavy"], [3.05, "release", "move_forward"], [3.05, "release", "sprint"]], [], 1, {"fixed": [1.0, 0.0, 0.0], "dist": 4.6, "h": 1.0, "video": true, "vstart": 2.6, "notrail": true, "dummy": 9.4}],
		["s01", Vector3(-60, 0, -60), PI, 4.2, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [1, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.2, "h": 1.0, "video": true, "vstart": 2.0, "notrail": true}],
		["s01_front", Vector3(-60, 0, -50), PI, 4.2, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [1, true]]], [], 1, {"fixed": [0.12, 0.05, 1.0], "dist": 3.2, "h": 1.1, "video": true, "vstart": 2.0, "notrail": true}],
		["s07", Vector3(-60, 0, -40), PI, 4.2, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [8, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.2, "h": 1.0, "video": true, "vstart": 2.0, "notrail": true}],
		["s07_front", Vector3(-60, 0, -30), PI, 4.2, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [8, true]]], [], 1, {"fixed": [0.45, 0.05, 1.0], "dist": 3.2, "h": 1.1, "video": true, "vstart": 2.0, "notrail": true}],
		["s12", Vector3(-60, 0, -20), PI, 4.2, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [12, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.2, "h": 1.0, "video": true, "vstart": 2.0, "notrail": true}],
		["s12_front", Vector3(-60, 0, -10), PI, 4.2, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [12, true]]], [], 1, {"fixed": [0.45, 0.05, 1.0], "dist": 3.2, "h": 1.1, "video": true, "vstart": 2.0, "notrail": true}],
		["s01_hit", Vector3(-75, 0, -60), PI, 4.0, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [1, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.2, "h": 1.0, "video": true, "vstart": 2.0, "notrail": true, "dummy": 1.3}],
		["s07_hit", Vector3(-75, 0, -50), PI, 4.0, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [8, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.2, "h": 1.0, "video": true, "vstart": 2.0, "notrail": true, "dummy": 1.75}],
		["s12_hit", Vector3(-75, 0, -40), PI, 4.0, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [12, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.2, "h": 1.0, "video": true, "vstart": 2.0, "notrail": true, "dummy": 1.3}],
		["s_whiff", Vector3(-75, 0, -30), PI, 8.0, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [1, true]], [4.0, "callv", "execute_form", [8, true]], [5.8, "callv", "execute_form", [12, true]]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.2, "h": 1.0, "notrail": true, "dummy": 3.6}],
		["s_branch12", Vector3(-75, 0, -20), PI, 5.0, [[0.2, "call", "request_draw"], [2.4, "tap", "attack_light"], [2.6, "tap", "attack_light"], [2.85, "tap", "attack_light"], [3.0, "tap", "attack_heavy"]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.2, "h": 1.0, "video": true, "vstart": 2.2, "notrail": true}],
		["s_sprint07", Vector3(-75, 0, -10), PI, 5.0, [[0.2, "call", "request_draw"], [2.0, "hold", "sprint"], [2.0, "hold", "move_forward"], [3.0, "tap", "attack_heavy"], [3.05, "release", "move_forward"], [3.05, "release", "sprint"]], [], 1, {"back": true, "dist": 4.0, "h": 1.0, "video": true, "vstart": 2.0, "notrail": true}],
		["s_int12", Vector3(-75, 0, 0), PI, 4.6, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [12, true]], [2.6, "hit"], [3.6, "tap", "attack_light"]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.2, "h": 1.0, "video": true, "vstart": 2.0, "notrail": true, "dummy": 1.3}],
		["s_follow01", Vector3(-75, 0, 10), PI, 4.6, [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [1, true]], [2.35, "tap", "attack_light"]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.2, "h": 1.0, "video": true, "vstart": 2.0, "notrail": true}],
		["d_mouth", Vector3(15, 0, 0), PI, 3.4, [[0.8, "tap", "attack_light"]], [], 1,
			{"bone": "mixamorig_Hips", "dir": [-0.45, -0.1, 1.0], "dist": 0.9, "video": true, "vstart": 0.6, "notrail": true, "hide": ["羽織"]}],
		["d_sleeve", Vector3(15, 0, 20), PI, 4.6, [[0.2, "call", "request_draw"], [2.4, "tap", "attack_light"], [2.6, "tap", "attack_light"], [2.85, "tap", "attack_light"]], [], 1,
			{"bone": "mixamorig_RightForeArm", "dir": [0.6, 0.3, 0.75], "dist": 0.9, "video": true, "vstart": 2.2, "notrail": true}],
		["d_twohand", Vector3(15, 0, 40), PI, 4.0, [[0.2, "call", "request_draw"], [2.4, "tap", "attack_heavy"]], [], 1,
			{"bone": "mixamorig_LeftHand", "dir": [-0.5, 0.2, 0.85], "dist": 0.6, "video": true, "vstart": 2.2, "notrail": true}],
		["v3_int_qd_early", Vector3(90, 0, 30), PI, 4.0, [[0.8, "tap", "attack_light"], [1.28, "hit"], [2.6, "tap", "attack_light"]], [], 1,
			{"fixed": [1.0, 0.0, 0.35], "dist": 3.0, "h": 1.0, "video": true, "vstart": 0.6, "notrail": true}],
		["d_grip_a", Vector3(15, 0, -50), PI, 3.2, [[0.2, "call", "request_draw"]], [], 1,
			{"bone": "mixamorig_RightHand", "dir": [0.9, 0.2, 0.4], "dist": 0.45, "video": true, "vstart": 2.4, "notrail": true, "hide": ["羽織"]}],
		["d_grip_b", Vector3(15, 0, -40), PI, 3.2, [[0.2, "call", "request_draw"]], [], 1,
			{"bone": "mixamorig_RightHand", "dir": [-0.2, -0.6, 0.8], "dist": 0.45, "video": true, "vstart": 2.4, "notrail": true, "hide": ["羽織"]}],
		["d_grip_c", Vector3(15, 0, -30), PI, 3.2, [[0.2, "call", "request_draw"]], [], 1,
			{"bone": "mixamorig_RightHand", "dir": [0.3, 0.9, 0.3], "dist": 0.45, "video": true, "vstart": 2.4, "notrail": true, "hide": ["羽織"]}],
		["d_grip_d", Vector3(15, 0, -20), PI, 3.2, [[0.2, "call", "request_draw"]], [], 1,
			{"bone": "mixamorig_RightHand", "dir": [-0.9, 0.1, -0.4], "dist": 0.45, "video": true, "vstart": 2.4, "notrail": true, "hide": ["羽織"]}],
		# R7 P1 v2 驗收（刀光／火焰／煙塵／速度線關閉）。[名稱, 起點, yaw, 長度, 事件, 截圖, 鏡頭側, 鏡頭]
		["v2_combo", Vector3(30, 0, -50), PI, 4.6, [[0.2, "call", "request_draw"], [2.4, "tap", "attack_light"], [2.6, "tap", "attack_light"], [2.85, "tap", "attack_light"]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.0, "h": 1.0, "video": true, "vstart": 2.2, "notrail": true}],
		["v2_combo_front", Vector3(30, 0, -30), PI, 4.6, [[0.2, "call", "request_draw"], [2.4, "tap", "attack_light"], [2.6, "tap", "attack_light"], [2.85, "tap", "attack_light"]], [], 1, {"fixed": [0.45, 0.05, 1.0], "dist": 3.0, "h": 1.1, "video": true, "vstart": 2.2, "notrail": true}],
		["v2_combo_early", Vector3(30, 0, -10), PI, 4.4, [[0.2, "call", "request_draw"], [2.4, "tap", "attack_light"], [2.45, "tap", "attack_light"], [2.5, "tap", "attack_light"]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.0, "h": 1.0, "notrail": true}],
		["v2_combo_late", Vector3(30, 0, 10), PI, 4.4, [[0.2, "call", "request_draw"], [2.4, "tap", "attack_light"], [3.2, "tap", "attack_light"]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.0, "h": 1.0, "notrail": true}],
		["v2_combo_stop", Vector3(30, 0, 30), PI, 4.4, [[0.2, "call", "request_draw"], [2.4, "tap", "attack_light"]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.0, "h": 1.0, "notrail": true}],
		["v2_heavy", Vector3(45, 0, -50), PI, 4.0, [[0.2, "call", "request_draw"], [2.4, "tap", "attack_heavy"]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.0, "h": 1.0, "video": true, "vstart": 2.2, "notrail": true}],
		["v2_charge", Vector3(45, 0, -30), PI, 6.6, [[0.2, "call", "request_draw"], [2.4, "press", "attack_heavy"], [4.9, "unpress", "attack_heavy"]], [], 1,
			{"bone": "mixamorig_Hips", "dir": [1.0, 0.05, 0.35], "dist": 3.0, "video": true, "vstart": 2.2, "notrail": true, "dummy": 3.4}],
		["v2_charge_near", Vector3(45, 0, -10), PI, 6.6, [[0.2, "call", "request_draw"], [2.4, "press", "attack_heavy"], [4.9, "unpress", "attack_heavy"]], [], 1,
			{"fixed": [1.0, 0.0, 0.35], "dist": 3.0, "h": 1.0, "notrail": true, "dummy": 1.5}],
		["v2_qd", Vector3(45, 0, 10), PI, 3.4, [[0.8, "tap", "attack_light"]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.0, "h": 1.0, "video": true, "vstart": 0.6, "notrail": true}],
		["v2_qd_front", Vector3(45, 0, 30), PI, 3.4, [[0.8, "tap", "attack_light"]], [], 1, {"fixed": [0.45, 0.05, 1.0], "dist": 3.0, "h": 1.1, "video": true, "vstart": 0.6, "notrail": true}],
		["v2_cu_grip", Vector3(60, 0, -50), PI, 4.6, [[0.2, "call", "request_draw"], [2.4, "tap", "attack_light"], [2.6, "tap", "attack_light"], [2.85, "tap", "attack_light"]], [], 1,
			{"bone": "mixamorig_RightHand", "dir": [0.35, -0.35, 1.0], "dist": 0.75, "video": true, "vstart": 2.2, "notrail": true}],
		["v2_cu_mouth", Vector3(60, 0, -30), PI, 3.4, [[0.8, "tap", "attack_light"]], [], 1,
			{"bone": "mixamorig_Hips", "dir": [-0.45, -0.15, 1.0], "dist": 1.15, "video": true, "vstart": 0.6, "notrail": true}],
		["v2_cu_head", Vector3(60, 0, -10), PI, 6.6, [[0.2, "call", "request_draw"], [2.4, "press", "attack_heavy"], [4.9, "unpress", "attack_heavy"]], [], 1,
			{"bone": "mixamorig_Head", "dir": [-0.7, 0.2, 0.7], "dist": 1.2, "video": true, "vstart": 4.6, "notrail": true}],
		["v2_hit_combo", Vector3(60, 0, 10), PI, 4.6, [[0.2, "call", "request_draw"], [2.4, "tap", "attack_light"], [2.6, "tap", "attack_light"], [2.85, "tap", "attack_light"]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.0, "h": 1.0, "video": true, "vstart": 2.2, "notrail": true, "dummy": 1.25}],
		["v2_whiff", Vector3(60, 0, 30), PI, 4.6, [[0.2, "call", "request_draw"], [2.4, "tap", "attack_light"], [2.6, "tap", "attack_light"], [2.85, "tap", "attack_light"]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.0, "h": 1.0, "notrail": true, "dummy": 3.2}],
		["v2_hit_heavy", Vector3(75, 0, -50), PI, 4.0, [[0.2, "call", "request_draw"], [2.4, "tap", "attack_heavy"]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.0, "h": 1.0, "notrail": true, "dummy": 1.3}],
		["v2_hit_qd", Vector3(75, 0, -30), PI, 3.4, [[0.8, "tap", "attack_light"]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.0, "h": 1.0, "notrail": true, "dummy": 1.3}],
		["v2_move_combo", Vector3(75, 0, -10), PI, 5.0, [[0.2, "call", "request_draw"], [2.2, "hold", "move_forward"], [2.4, "tap", "attack_light"], [2.6, "tap", "attack_light"], [2.85, "tap", "attack_light"], [3.6, "release", "move_forward"]], [], 1,
			{"back": true, "dist": 3.6, "h": 1.0, "video": true, "vstart": 2.0, "notrail": true, "dummy": 3.0}],
		["v2_strafe_combo", Vector3(75, 0, 10), PI, 5.0, [[0.2, "call", "request_draw"], [2.2, "hold", "move_right"], [2.4, "tap", "attack_light"], [2.6, "tap", "attack_light"], [2.85, "tap", "attack_light"], [3.6, "release", "move_right"]], [], 1,
			{"back": true, "dist": 3.6, "h": 1.0, "video": true, "vstart": 2.0, "notrail": true}],
		["v2_combo_then_move", Vector3(75, 0, 30), PI, 5.0, [[0.2, "call", "request_draw"], [2.4, "tap", "attack_light"], [2.6, "hold", "move_forward"], [4.2, "release", "move_forward"]], [], 1,
			{"fixed": [1.0, 0.0, 0.35], "dist": 3.0, "h": 1.0, "notrail": true}],
		["v2_int_combo", Vector3(90, 0, -50), PI, 5.0, [[0.2, "call", "request_draw"], [2.4, "tap", "attack_light"], [2.47, "hit"], [3.4, "tap", "attack_light"]], [], 1,
			{"fixed": [1.0, 0.0, 0.35], "dist": 3.0, "h": 1.0, "video": true, "vstart": 2.2, "notrail": true}],
		["v2_int_qd_noto", Vector3(90, 0, -30), PI, 4.0, [[0.8, "tap", "attack_light"], [2.45, "hit"], [3.5, "tap", "attack_light"]], [], 1,
			{"fixed": [1.0, 0.0, 0.35], "dist": 3.0, "h": 1.0, "video": true, "vstart": 0.6, "notrail": true}],
		["v2_int_qd_cut", Vector3(90, 0, -10), PI, 4.0, [[0.8, "tap", "attack_light"], [1.45, "hit"], [2.6, "tap", "attack_light"]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.0, "h": 1.0, "video": true, "vstart": 0.6, "notrail": true}],
		["v2_int_charge", Vector3(90, 0, 10), PI, 5.0, [[0.2, "call", "request_draw"], [2.4, "press", "attack_heavy"], [3.6, "hit"], [4.6, "unpress", "attack_heavy"]], [], 1,
			{"fixed": [1.0, 0.0, 0.35], "dist": 3.0, "h": 1.0, "notrail": true}],
	]
	# P3 uses this same capture pipeline. Each scenario occupies its own clear coordinate.
	var p3 := [["05", 10], ["06", 4], ["09", 5], ["10", 7]]
	for i in p3.size():
		var label: String = p3[i][0]
		var form_id: int = p3[i][1]
		var pc := {"fixed": [1.0, 0.02, 0.28], "dist": 5.6, "h": 1.55, "video": true, "vstart": 2.0, "notrail": true}
		if form_id == 5:
			pc.fixed = [0.18, 0.02, 1.0]
		_tests.append(["p3_" + label + "_ground", Vector3(-75, 0, -90 + i * 12), PI, 4.6,
			[[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [form_id, true]]], [], 1, pc.duplicate(true)])
		var ac: Dictionary = pc.duplicate(true)
		ac["dist"] = 6.8
		ac["h"] = 2.1  # Normal jump + aerial form can rise above the ground-start framing.
		if form_id == 5:
			ac["fixed"] = [-1.0, 0.02, 0.65]  # Keep the elevated post from hiding the inverted body.
		ac["dummy"] = [-0.6, 1.0] if form_id == 5 else ([0.9, -0.1] if form_id == 7 else 1.5)
		if form_id == 5:
			ac["dummy_height"] = 1.0  # Inverted horizontal cut aims at a genuinely elevated target, not a widened hurt volume.
		_tests.append(["p3_" + label + "_airhit", Vector3(-55, 0, -90 + i * 12), PI, 5.0,
			[[0.2, "call", "request_draw"], [2.1, "tap", "jump"], [2.45, "callv", "execute_form", [form_id, true]]], [], 1, ac])
		var ic: Dictionary = ac.duplicate(true)
		ic.erase("dummy")
		ic.erase("dummy_height")
		_tests.append(["p3_" + label + "_interrupt", Vector3(-35, 0, -90 + i * 12), PI, 5.0,
			[[0.2, "call", "request_draw"], [2.1, "tap", "jump"], [2.45, "callv", "execute_form", [form_id, true]],
			[2.75, "hit"], [4.2, "hold", "move_forward"], [4.6, "release", "move_forward"]], [], 1, ic])
	# REF09 MX 比較：第三人稱後方鏡頭（同輸入時刻；以 R7_REF09_VARIANT=mx|p31 切版本）與落地後移動取消量測
	_tests.append(["p3_09_tps", Vector3(-15, 0, -78), PI, 4.8,
		[[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [5, true]]],
		[], 1, {"fixed": [0.30, 0.38, -1.0], "dist": 6.6, "h": 1.8, "video": true, "vstart": 2.0, "notrail": true}])
	# MX 專用 airhit：木樁放在 MX 命中窗實測刀路「前下段」（blade log：相對起點 側 +0.55、前 0.95 m、刀高約 1.9–2.4 m）；墊高與 P3.1 相同 1.0，判定體積不變
	_tests.append(["p3_09mx_airhit", Vector3(-15, 0, -54), PI, 5.0,
		[[0.2, "call", "request_draw"], [2.1, "tap", "jump"], [2.45, "callv", "execute_form", [5, true]]],
		[], 1, {"fixed": [-1.0, 0.02, 0.65], "dist": 6.8, "h": 2.1, "video": true, "vstart": 2.0, "notrail": true, "dummy": [0.55, 0.95], "dummy_height": 1.0}])
	_tests.append(["p3_09_movecancel", Vector3(-15, 0, -66), PI, 5.0,
		[[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [5, true]], [3.45, "hold", "move_forward"], [4.6, "release", "move_forward"]],
		[], 1, {"fixed": [1.0, 0.02, 0.28], "dist": 5.6, "h": 1.55, "notrail": true}])
	# P3.1：落地恢復中按移動 → 驗證「視覺恢復 ≠ 全程鎖控」（REF05 觸地 ≈ 2.2+0.967 s、取消點 ≈ 2.2+1.167 s）
	_tests.append(["p3_05_movecancel", Vector3(-15, 0, -90), PI, 4.6,
		[[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [10, true]], [3.30, "hold", "move_forward"], [4.3, "release", "move_forward"]],
		[], 1, {"fixed": [1.0, 0.02, 0.28], "dist": 5.6, "h": 1.55, "video": true, "vstart": 2.0, "notrail": true}])
	# R7 P4 十三型：公開 form13 action（InputEventAction＋action_press）按住兩圈→鬆開（本型播完收勢）→移動恢復。
	# 呼吸政策：展示用 form13_unlocked = true（每圈不扣滿槽）；資源不足退出另在 test_r7_form13.gd breath 測。木樁在正前 1.6 m（enemies 群組，型位移會在接觸前停）。
	# 擷取視窗失焦時 Godot 會釋放所有按住的 action（另一行程搶焦點即中斷）→ 擷取改 r7c_hold_to_continue=false，
	# 仍以公開 form13 InputEventAction 起手；17.6 s 呼叫 r7c_request_stop（＝鬆鍵走的同一停止路徑；鬆鍵本身在 test_r7_form13 lap2 驗證）。
	var f13_ev := [[0.2, "call", "request_draw"], [0.3, "callv", "set", ["form13_unlocked", true]], [0.3, "callv", "set", ["r7c_hold_to_continue", false]],
		[2.4, "press", "form13"], [2.5, "unpress", "form13"], [17.6, "call", "r7c_request_stop"], [21.2, "hold", "move_forward"], [22.6, "release", "move_forward"]]
	_tests.append(["f13_tps", Vector3(30, 0, 40), PI, 23.4, f13_ev, [], 1, {"tps": true, "dist": 5.2, "h": 1.7, "video": true, "vstart": 1.8, "dummy": 1.6}])
	_tests.append(["f13_fixed", Vector3(30, 0, 40), PI, 23.4, f13_ev.duplicate(true), [], 1, {"fixed": [1.0, 0.25, 0.55], "dist": 8.0, "h": 1.6, "video": true, "vstart": 1.8, "notrail": true, "dummy": 1.6}])
	# 閃避取消版（R7 P4 輸入仲裁）：固定輸入時刻 2.62 s（≈ REF01 af13，尚不可取消）呼叫 request_dodge（＝公開 dodge 輸入的同一入口）
	# → 循環閃避緩衝 0.40 s → REF01 接出格（af24）翻滾退出 → 4.2 s 起按住移動＝恢復操作。
	_tests.append(["f13_tps_dodge", Vector3(30, 0, 40), PI, 6.6, [[0.2, "call", "request_draw"], [0.3, "callv", "set", ["form13_unlocked", true]], [0.3, "callv", "set", ["r7c_hold_to_continue", false]], [2.4, "press", "form13"],
		[2.5, "unpress", "form13"], [2.62, "call", "request_dodge"], [4.2, "hold", "move_forward"], [5.4, "release", "move_forward"]], [], 1, {"tps": true, "dist": 5.2, "h": 1.7, "video": true, "vstart": 1.8, "dummy": 1.6}])
	# 受擊中斷版：第一圈第 3 型中受擊 → 退出 → 移動
	_tests.append(["f13_tps_hit", Vector3(30, 0, 40), PI, 8.6, [[0.2, "call", "request_draw"], [0.3, "callv", "set", ["form13_unlocked", true]], [0.3, "callv", "set", ["r7c_hold_to_continue", false]], [2.4, "press", "form13"],
		[2.5, "unpress", "form13"], [4.25, "hit"], [6.4, "hold", "move_forward"], [7.6, "release", "move_forward"]], [], 1, {"tps": true, "dist": 5.2, "h": 1.7, "video": true, "vstart": 1.8, "dummy": 1.6}])
	# R7 P5c 握刀近景：十三型 01→02、08→09（左手骨追拍，原速）；9.2 s 呼叫停止（REF09 已開始）
	_tests.append(["p5_grip_close", Vector3(30, 0, 70), PI, 11.0, [[0.2, "call", "request_draw"], [0.3, "callv", "set", ["form13_unlocked", true]], [0.3, "callv", "set", ["r7c_hold_to_continue", false]],
		[2.4, "press", "form13"], [2.5, "unpress", "form13"], [9.2, "call", "r7c_request_stop"]], [], 1,
		{"bone": "mixamorig_Spine2", "dir": [0.55, 0.15, 0.85], "dist": 1.55, "video": true, "vstart": 2.2, "notrail": true}])
	# R7 P5c REF01 右鍵分支：木樁放在分支命中窗實測刀路（test_r7_ref01_rmb rmb_dummy：角色左 1.17 m、前 1.98 m）；判定不放大
	var rmb_single := [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [1, true]], [2.76, "call", "request_heavy_cut"], [5.2, "hold", "move_forward"], [5.9, "release", "move_forward"]]
	var rmb_cycle := [[0.2, "call", "request_draw"], [0.3, "callv", "set", ["form13_unlocked", true]], [0.3, "callv", "set", ["r7c_hold_to_continue", false]],
		[2.4, "press", "form13"], [2.5, "unpress", "form13"], [2.62, "call", "request_heavy_cut"], [5.4, "hold", "move_forward"], [6.1, "release", "move_forward"]]
	_tests.append(["p5_rmb_single_fixed", Vector3(30, 0, 40), PI, 6.4, rmb_single, [], 1, {"fixed": [1.0, 0.35, 0.45], "dist": 6.2, "h": 1.1, "video": true, "vstart": 1.9, "notrail": true, "dummy": [-1.17, 1.98]}])
	_tests.append(["p5_rmb_cycle_fixed", Vector3(30, 0, 40), PI, 6.6, rmb_cycle, [], 1, {"fixed": [1.0, 0.35, 0.45], "dist": 6.2, "h": 1.1, "video": true, "vstart": 1.9, "notrail": true, "dummy": [-1.17, 1.98]}])
	_tests.append(["p5_rmb_single_tps", Vector3(30, 0, 40), PI, 6.4, rmb_single.duplicate(true), [], 1, {"tps": true, "dist": 5.2, "h": 1.7, "video": true, "vstart": 1.9, "notrail": true, "dummy": [-1.17, 1.98]}])
	# R7 P5d 握刀審圖鏡頭（確定性：雙手＋刀柄中點、角色本地方向、FOV 34、距 1.25 m）；十三型 01→02、08→09，原速
	var gev := [[0.2, "call", "request_draw"], [0.3, "callv", "set", ["form13_unlocked", true]], [0.3, "callv", "set", ["r7c_hold_to_continue", false]],
		[2.4, "press", "form13"], [2.5, "unpress", "form13"], [9.2, "call", "r7c_request_stop"]]
	_tests.append(["p5d_grip_cam", Vector3(30, 0, 70), PI, 11.0, gev, [], 1, {"grip": true, "dir": [0.75, 0.30, 0.60], "dist": 1.25, "fov": 34.0, "video": true, "vstart": 2.2, "notrail": true}])
	# R7 P5d 右鍵分支：鏡頭跟拍（第三人稱後方，木樁完整入框）＋俯視固定（量穿樁用）
	var rmb_d := [[0.2, "call", "request_draw"], [2.2, "callv", "execute_form", [1, true]], [2.76, "call", "request_heavy_cut"], [5.2, "hold", "move_forward"], [5.9, "release", "move_forward"]]
	_tests.append(["p5d_rmb_tps", Vector3(30, 0, 40), PI, 6.4, rmb_d, [], 1, {"tps": true, "dist": 6.0, "h": 2.2, "video": true, "vstart": 1.9, "notrail": true, "dummy": [-1.17, 1.98]}])
	_tests.append(["p5d_rmb_top", Vector3(30, 0, 40), PI, 5.4, rmb_d.duplicate(true), [], 1, {"fixed": [0.15, 1.0, 0.25], "dist": 5.5, "h": 0.0, "video": true, "vstart": 2.1, "notrail": true, "dummy": [-1.17, 1.98]}])
	_tests.append(["p5d_rmb_side", Vector3(30, 0, 40), PI, 5.4, rmb_d.duplicate(true), [], 1, {"fixed": [-1.0, 0.25, 0.6], "dist": 5.4, "h": 1.0, "video": true, "vstart": 2.1, "notrail": true, "dummy": [-1.17, 1.98]}])
	if not _only.is_empty():
		_tests = _tests.filter(func(t): return t[0] in _only)

var _dump: Array = []
var _skf: Skeleton3D = null
var _want_dump := false
var _dump_frame := -1


## 最終姿勢（modifier 之後）在這裡記錄；每個 process frame 只記一次
func _on_skel() -> void:
	if not _want_dump or _ti < 0 or _ti >= _tests.size():
		return
	var pf := Engine.get_process_frames()
	if pf == _dump_frame:
		return
	_dump_frame = pf
	var fr := {"t": snappedf(_t, 0.001), "skel_xf": _xf12(_skf.global_transform), "st": _state()}
	var bones := {}
	for bi in _skf.get_bone_count():
		bones[_skf.get_bone_name(bi)] = _xf12(_skf.get_bone_global_pose(bi))
	fr["bones"] = bones
	var sh: Node3D = _p.get("_sword_hand")
	if sh:
		fr["sword_hand"] = _xf12(_skf.global_transform.affine_inverse() * sh.global_transform)
	var sb: Node3D = _p.find_child("Sheath", true, false) as Node3D
	if sb:
		fr["sheath"] = _xf12(_skf.global_transform.affine_inverse() * sb.global_transform)
	_dump.append(fr)


func _ik_state() -> Dictionary:
	var ik = _p.get("_r62_ik")
	if ik == null:
		return {}
	return {"w": snappedf(ik.right_weight, 0.001), "lw": snappedf(ik.last_left_weight, 0.001), "qd": ik.qd_on,
		"err": [snappedf(ik.last_err[0], 0.01), snappedf(ik.last_err[1], 0.01)],
		"wR": ik.last_wrist.get("Right", {}), "wL": ik.last_wrist.get("Left", {}),
		"aR": ik.last_wrist_anim.get("Right", {}), "aL": ik.last_wrist_anim.get("Left", {})}

func _xf12(t: Transform3D) -> Array:
	var b := t.basis
	return [b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z, t.origin.x, t.origin.y, t.origin.z]

func _flush_dump() -> void:
	if _ti >= 0 and _ti < _tests.size() and not _dump.is_empty():
		var vd: String = OUT + _tests[_ti][0] + "/"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(vd))
		var f := FileAccess.open(vd + "poses.json", FileAccess.WRITE)
		f.store_string(JSON.stringify(_dump))
		f.close()
	_dump = []

func _next_test() -> void:
	_want_dump = false
	_flush_dump()
	for a in ["move_forward", "move_back", "move_left", "move_right", "sprint", "walk", "guard", "jump", "attack_light", "draw_sword"]:
		if InputMap.has_action(a):
			Input.action_release(a)
	if _ti >= 0 and _p != null and is_instance_valid(_p) and _p.get("r7_blade_trace") != null:
		var tr: Array = []
		for e in (_p.get("r7_blade_trace") as Array):
			var ln := []
			for v in (e[2] as Array):
				ln.append([snappedf(v.x, 0.0001), snappedf(v.y, 0.0001), snappedf(v.z, 0.0001)])
			tr.append([e[0], e[1], ln])
		if not tr.is_empty():
			_log[str(_tests[_ti][0]) + "__blade"] = tr
		_log[str(_tests[_ti][0]) + "__sweep_perf"] = [_p.get("r7_sweep_usec"), _p.get("r7_sweep_calls")]
		_log[str(_tests[_ti][0]) + "__sweep_hits"] = _p.get("r7_sweep_hits")
		_log[str(_tests[_ti][0]) + "__end"] = {"face_err_deg": _p.get("r7_face_err"), "player_hp": _p.posture.health if _p.posture != null else null,
			"hit_results": _hit_results, "pos": [_p.global_position.x, _p.global_position.z], "yaw_deg": rad_to_deg((_p._visual as Node3D).global_rotation.y)}
		if _dummy != null and is_instance_valid(_dummy):
			_log[str(_tests[_ti][0]) + "__dummy"] = [_dummy.global_position.x, _dummy.global_position.y, _dummy.global_position.z]
	_ti += 1
	if _ti >= _tests.size():
		var f := FileAccess.open(OUT + "log.json", FileAccess.WRITE)
		f.store_string(JSON.stringify(_log, "  "))
		f.close()
		print("OUT ", ProjectSettings.globalize_path(OUT))
		quit()
		return
	var tt: Array = _tests[_ti]
	_p.velocity = Vector3.ZERO
	_fix_anchor = Vector3.INF
	_grip_aim = Vector3.INF
	_grip_yaw = 1.0e9
	# 每個測項從收刀、自由狀態開始（前一項可能停在拔刀）
	if int(_p.get("sword_state")) != 0:
		_p.set("sword_state", 0)
		_p.set("action_state", 0)
		_p.call("_apply_sword_visibility")
		_p._tree.set("parameters/grip/blend_amount", 0.0)
	var bvr := _p.get_node_or_null("BodyVisual")
	if bvr and bvr.get("springs_enabled") != null:
		bvr.set("springs_enabled", true)
	_p.global_position = tt[1]
	_p.snap_yaw(tt[2] - PI)
	_t = 0.0
	_events = (tt[4] as Array).duplicate(true)
	_shots_pending = (tt[5] as Array).duplicate(true)
	_cam_side = tt[6]
	_log[tt[0]] = []
	_vframe = 0
	if _dummy != null:
		_dummy.queue_free()
		_dummy = null
	var cm: Dictionary = tt[7] if tt.size() > 7 else {}
	if cm.has("dummy"):
		_dummy = (load("res://characters/combat/training_dummy.tscn") as PackedScene).instantiate()
		root.add_child(_dummy)
		var fw: Vector3 = (_p._visual as Node3D).global_transform.basis.orthonormalized() * Vector3(0, 0, 1)
		fw.y = 0.0
		if cm["dummy"] is Array:
			# [角色右方 m, 角色前方 m]（角色面向視覺 +Z，右手側 = 視覺 −X）
			var rt: Vector3 = (_p._visual as Node3D).global_transform.basis.orthonormalized() * Vector3(-1, 0, 0)
			rt.y = 0.0
			_dummy.global_position = _p.global_position + rt.normalized() * float(cm["dummy"][0]) + fw.normalized() * float(cm["dummy"][1])
		else:
			_dummy.global_position = _p.global_position + fw.normalized() * float(cm["dummy"])
		if cm.has("dummy_height"):
			var elevation := float(cm["dummy_height"])
			_box(_dummy.global_position, Vector3(1.0, elevation, 1.0), Color(0.42, 0.39, 0.34))
			_dummy.global_position.y += elevation
		_dummy.add_to_group("enemies")      # 讓型的位移看得到目標（正式敵人本來就在 enemies 群組）
	if cm.has("wolf"):
		# 山犬（正式敵人資產，不改檔）：只改這個實例的執行期參數——AI 暫停、血量／軀幹放大，避免兩刀就死或反擊打斷測試
		var wv: Array = cm["wolf"]
		var wf: Vector3 = (_p._visual as Node3D).global_transform.basis.orthonormalized() * Vector3(0, 0, 1)
		wf.y = 0.0
		var wr: Vector3 = (_p._visual as Node3D).global_transform.basis.orthonormalized() * Vector3(-1, 0, 0)
		wr.y = 0.0
		_dummy = (load("res://characters/combat/enemy_wolf.tscn") as PackedScene).instantiate()
		_dummy.set("max_health", 1.0e6)
		_dummy.set("max_posture", 1.0e6)
		_dummy.set("dodge_enabled", false)
		_wolf_live = bool(cm.get("wolf_live", false))
		if cm.has("wolf_lunge_only"):
			_dummy.set("claw_chance", 0.0)
			_dummy.set("pounce_chance", 0.0)
		if not _wolf_live:
			_dummy.set("detect_range", 0.0)
		root.add_child(_dummy)
		_dummy.global_position = _p.global_position + wr.normalized() * float(wv[0]) + wf.normalized() * float(wv[1])
		# 朝向：wv[2] = 狼身相對「面向玩家」再轉幾度（0 = 正對玩家，90 = 側身）
		var to_p: Vector3 = _p.global_position - _dummy.global_position
		to_p.y = 0.0
		_dummy.look_at(_dummy.global_position - to_p.normalized(), Vector3.UP)
		_dummy.rotate_y(deg_to_rad(float(wv[2]) if wv.size() > 2 else 0.0))
		if not _wolf_live:
			_dummy.set_physics_process(false)
		else:
			_dummy.set("target", _p)   # 測試玩家不在 player 群組：直接指定目標（執行期實例設定）
		_wolf_dumped = {}
		_evade_on_windup = int(cm.get("evade_on_windup", 0))
		_evade_delay = float(cm.get("evade_delay", 0.0))
		_windup_t0 = -1.0
		_evaded = false
		_hit_results = []
		if not _p.is_connected("player_was_hit", _on_player_hit):
			_p.connect("player_was_hit", _on_player_hit)
	if cm.has("wall_left"):
		var rt2: Vector3 = (_p._visual as Node3D).global_transform.basis.orthonormalized() * Vector3(-1, 0, 0)
		rt2.y = 0.0
		var c2 := _p.global_position - rt2.normalized() * (float(cm["wall_left"]) + 0.15)
		_box(c2, Vector3(0.3 if absf(rt2.x) > 0.5 else 3.0, 2.5, 3.0 if absf(rt2.x) > 0.5 else 0.3), Color(0.5, 0.45, 0.4))
	if cm.has("wall"):
		var fw2: Vector3 = (_p._visual as Node3D).global_transform.basis.orthonormalized() * Vector3(0, 0, 1)
		fw2.y = 0.0
		var c := _p.global_position + fw2.normalized() * (float(cm["wall"]) + 0.15)
		_box(c - Vector3(0, 0, 0), Vector3(3.0 if absf(fw2.z) > 0.5 else 0.3, 2.5, 0.3 if absf(fw2.z) > 0.5 else 3.0), Color(0.5, 0.45, 0.4))

func _dummy_hp():
	if _dummy.get("health") != null:
		return _dummy.get("health")
	var po = _dummy.get("posture")
	return po.health if po != null else null


func _wolf_tick() -> void:
	if _dummy == null or not is_instance_valid(_dummy) or not _dummy.has_node("Hurtbox"):
		return
	if _evade_on_windup > 0 and not _evaded:
		var smap: Dictionary = _dummy.get_script().get_script_constant_map()["State"]
		if int(_dummy.get("state")) == int(smap["WINDUP"]) and _windup_t0 < 0.0:
			_windup_t0 = _t
		if _windup_t0 >= 0.0 and _t - _windup_t0 >= _evade_delay:
			_evaded = true
			_log[str(_tests[_ti][0]) + "__evade_t"] = [snappedf(_t, 0.01), _p.call("execute_form", _evade_on_windup, true)]
	var g := int(_p.get("r7_hit_group")) if _p.get("r7_hit_group") != null else 0
	var key := "g%d" % g if g > 0 else ("t0" if _t > 1.0 else "")
	if key != "" and not _wolf_dumped.has(key):
		_wolf_dumped[key] = true
		var nm := str(_tests[_ti][0]) + "__wolf_" + key
		_log[nm] = _wolf_snapshot()


func _feet() -> Array:
	var sk: Skeleton3D = _p._visual.find_children("*", "Skeleton3D", true, false)[0]
	var out := []
	for bn in ["mixamorig_LeftToeBase", "mixamorig_RightToeBase", "mixamorig_LeftFoot", "mixamorig_RightFoot"]:
		var i := sk.find_bone(bn)
		var w := sk.global_transform * sk.get_bone_global_pose(i).origin if i >= 0 else Vector3.ZERO
		out.append([snappedf(w.x, 0.001), snappedf(w.y, 0.001), snappedf(w.z, 0.001)])
	return out

func _send(action: String, pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	Input.parse_input_event(ev)

## 左手（中指根）到刀鞘軸的距離（m）與沿軸位置：鞘 MeshInstance3D 的 AABB 最長軸當鞘軸
func _lh_saya() -> Array:
	var sh: Node3D = _p.find_child("Sheath", true, false) as Node3D
	if sh == null:
		return []
	var mis := sh.find_children("*", "MeshInstance3D", true, false)
	if mis.is_empty():
		return []
	var mi: MeshInstance3D = mis[0]
	var ab := mi.get_aabb()
	var ax := 0
	for k in 3:
		if ab.size[k] > ab.size[ax]:
			ax = k
	var a := ab.get_center()
	var b := a
	a[ax] = ab.position[ax]
	b[ax] = ab.position[ax] + ab.size[ax]
	var A := mi.global_transform * a
	var B := mi.global_transform * b
	var sk: Skeleton3D = _p._visual.find_children("*", "Skeleton3D", true, false)[0]
	var out := []
	for bn in ["mixamorig_LeftHandMiddle1", "mixamorig_LeftHand"]:
		var P := sk.global_transform * sk.get_bone_global_pose(sk.find_bone(bn)).origin
		var ab3 := B - A
		var t := clampf((P - A).dot(ab3) / ab3.length_squared(), 0.0, 1.0)
		out.append([snappedf((P - (A + ab3 * t)).length(), 0.001), snappedf(t, 0.01)])
	return out

func _state() -> Dictionary:
	var pb: AnimationNodeStateMachinePlayback = _p._tree.get("parameters/loco/playback")
	return {"t": snappedf(_t, 0.01), "pos": str(_p.global_position.snapped(Vector3.ONE * 0.01)), "vel": str(_p.velocity.snapped(Vector3.ONE * 0.01)),
		"floor": _p.is_on_floor(), "loco": str(pb.get_current_node()), "full": str(_p._tree.get("parameters/full_sel/current_state")),
		"full_on": _p._tree.get("parameters/full/active"), "sword": _p.sword_state, "action": _p.action_state,
		"climb": snappedf(_p._climb_left, 0.01), "trick": snappedf(_p._trick_left, 0.01),
		"r5": _p.get("_r5_active"), "r5_tail": _p.get("_r5_tail"), "layer": _p._attack_layer,
		"r5_frame": snappedf(_p._action_elapsed * 30.0, 0.1) if _p.get("_r5_active") else -1.0,
		"hand_vis": _p._sword_hand.visible if _p._sword_hand else null, "sheathed_vis": _p._sword_sheathed.visible if _p._sword_sheathed else null,
		"hitbox": _p._hitbox.monitoring if _p._hitbox else null, "lower": _p._tree.get("parameters/lower/internal_active"),
		"upper": _p._tree.get("parameters/upper/internal_active"), "upper_sel": str(_p._tree.get("parameters/upper_sel/current_state")),
		"trail": _p._sword_trail.is_emitting if _p._sword_trail else null, "atk": str(_p._active_attack_name),
		"dummy_hp": (_dummy_hp() if _dummy != null else null), "php": (_p.posture.health if _p.posture != null else null), "lkey": str(_p.get("r7_last_light_key")), "grp": _p.get("r7_hit_group"), "form": _p.active_form, "variant": str(_p.get("r7_form_variant")), "guard": _p.get("_guard_held"), "cap": _p.get("r7_root_cap_used"), "feet": _feet(), "tip_rel": str(((_p._visual as Node3D).global_transform.basis.orthonormalized().inverse() * (_p._blade_tip.global_position - _p.global_position)).snapped(Vector3.ONE * 0.01)) if _p._blade_tip else "", "hb_rel": str(((_p._visual as Node3D).global_transform.basis.orthonormalized().inverse() * (_p._hitbox.global_position - _p.global_position)).snapped(Vector3.ONE * 0.01)) if _p._hitbox else "", "combo": _p.combo_stage,
		"elapsed": snappedf(_p._action_elapsed, 0.001), "action_real": snappedf(_p._action_real, 0.001),
		"ik": _ik_state(), "lh_saya": _lh_saya() if (str(_tests[_ti][0]).begins_with("idle") or str(_tests[_ti][0]).begins_with("qd")) else []}

var _settle := 0
func _process(delta: float) -> bool:
	if _skf == null and _p.get("_visual") != null:
		_skf = _p._visual.find_children("*", "Skeleton3D", true, false)[0]
		_skf.skeleton_updated.connect(_on_skel)
	if _settle < 10:
		_settle += 1
		if _settle == 10:
			_next_test()
		return false
	if _ti >= _tests.size():
		return true
	# 截圖：Godot 視窗抓圖要等兩幀渲染
	if _shot_wait > 0:
		_shot_wait -= 1
		if _shot_wait == 0:
			var name: String = _tests[_ti][0] + "_" + _pending_name
			root.get_viewport().get_texture().get_image().save_png(OUT + name + ".png")
			var st := _state()
			st["shot"] = name
			(_log[_tests[_ti][0]] as Array).append(st)
		return false
	_t += delta
	for ev in _events.duplicate():
		if _t >= ev[0]:
			match ev[1]:
				"hold":
					Input.action_press(ev[2])
				"release":
					Input.action_release(ev[2])
				"tap":
					_send(ev[2], true)
					_send(ev[2], false)
				"tap_sprint":
					_send(ev[2], true)
					_send(ev[2], false)
				"call":
					_p.call(ev[2])
				"callv":
					var accepted = _p.callv(ev[2], ev[3])
					if str(_tests[_ti][0]).begins_with("p3_"):
						print("P3_CAPTURE_CALL ", _tests[_ti][0], " ", ev[2], " t=", _t, " accepted=", accepted, " floor=", _p.is_on_floor())
				"hit":
					_hits_taken += 1
					var fwh: Vector3 = (_p._visual as Node3D).global_transform.basis.orthonormalized() * Vector3(0, 0, 1)
					var res = _p.take_hit({"damage": 4.0, "posture_damage": 2.0, "hit_dir": -fwh, "hit_pos": _p.global_position + Vector3(0, 1.1, 0)})
					print("HIT_PLAYER t=", _t, " res=", res)
				"rig":
					_p.get_node("BodyVisual").set(ev[2], ev[3])
				"press":
					_send(ev[2], true)
					Input.action_press(ev[2])
				"unpress":
					_send(ev[2], false)
					Input.action_release(ev[2])
			_events.erase(ev)
	# 追身鏡頭：角色右前 45°（cam_side=-1 為左前）
	var c := _p.global_position + Vector3(0, 1.0, 0)
	var fwd := Vector3(0, 0, -1)
	var side := Vector3(1, 0, 0) * _cam_side
	if _tests[_ti][0] == "walljump":
		fwd = Vector3(1, 0, 0)    # 鏡頭在牆外側（+x），看角色貼牆與蹬離
		side = Vector3(0, 0, 1.6)
	var cam: Dictionary = _tests[_ti][7] if (_tests[_ti] as Array).size() > 7 else {}
	var dist: float = cam.get("dist", 4.5)
	if cam.get("tps", false):
		# 第三人稱跟拍：角色後上方，偏航平滑追角色面向（≈0.35 s 時間常數），注視點隨角色高度（空中最高點不裁切）
		var vy: float = (_p._visual as Node3D).global_rotation.y
		if _tps_yaw > 1.0e8:
			_tps_yaw = vy
		_tps_yaw += wrapf(vy - _tps_yaw, -PI, PI) * minf(1.0, delta / 0.35)
		var back := -Vector3(sin(_tps_yaw), 0.0, cos(_tps_yaw))
		var look := _p.global_position + Vector3(0, 1.15, 0)
		_cam.global_position = look + back * dist + Vector3(0, float(cam.get("h", 1.6)) - 0.6, 0) + Vector3(-back.z, 0, back.x) * 0.9
		_cam.look_at(look, Vector3.UP)
	elif cam.has("fixed"):
		# 固定世界鏡頭：以測項開始時的角色位置為錨（看得到真實踏步／位移），dir 為角色本地方向
		if _fix_anchor == Vector3.INF:
			_fix_anchor = _p.global_position + Vector3(0, float(cam.get("h", 1.0)), 0)
			if cam.has("fixed_at"):   # 移動中測項：鏡頭錨點直接給世界 x,z（整段位移的中點，實測軌跡決定）
				_fix_anchor = Vector3(float(cam["fixed_at"][0]), float(cam.get("h", 1.0)), float(cam["fixed_at"][1]))
			var fv: Array = cam["fixed"]
			_fix_dir = ((_p._visual as Node3D).global_transform.basis.orthonormalized() * Vector3(float(fv[0]), float(fv[1]), float(fv[2]))).normalized()
		_cam.global_position = _fix_anchor + _fix_dir * dist
		_cam.look_at(_fix_anchor + Vector3(0, 0, 0), Vector3.UP)
	elif cam.get("grip", false):
		# R7 P5d 審圖鏡頭：瞄準雙手＋刀柄中點（世界方向以角色本地 dir；位置平滑、不隨揮刀抖動），FOV 固定
		var skg: Skeleton3D = _p._visual.find_children("*", "Skeleton3D", true, false)[0]
		var lh := skg.global_transform * skg.get_bone_global_pose(skg.find_bone("mixamorig_LeftHand")).origin
		var rh := skg.global_transform * skg.get_bone_global_pose(skg.find_bone("mixamorig_RightHand")).origin
		var le := skg.global_transform * skg.get_bone_global_pose(skg.find_bone("mixamorig_LeftForeArm")).origin
		var re := skg.global_transform * skg.get_bone_global_pose(skg.find_bone("mixamorig_RightForeArm")).origin
		var hilt: Vector3 = (_p._sword_hand as Node3D).global_position if _p._sword_hand != null else rh
		var aim := (lh + rh + hilt) / 3.0 * 0.7 + (le + re) * 0.5 * 0.3
		if _grip_aim == Vector3.INF:
			_grip_aim = aim
		_grip_aim = _grip_aim.lerp(aim, minf(1.0, delta / 0.12))
		var gv: Array = cam.get("dir", [0.6, 0.25, 0.8])
		var gb: Basis = (_p._visual as Node3D).global_transform.basis.orthonormalized()
		if _grip_yaw > 1.0e8:
			_grip_yaw = (_p._visual as Node3D).global_rotation.y
		_grip_yaw += wrapf((_p._visual as Node3D).global_rotation.y - _grip_yaw, -PI, PI) * minf(1.0, delta / float(cam.get("yaw_tc", 0.5)))
		gb = Basis(Vector3.UP, _grip_yaw)
		var gw: Vector3 = (gb * Vector3(float(gv[0]), float(gv[1]), float(gv[2]))).normalized()
		_cam.fov = float(cam.get("fov", 40.0))
		_cam.global_position = _grip_aim + gw * dist
		_cam.look_at(_grip_aim, Vector3.UP)
	elif cam.has("bone"):
		var sk: Skeleton3D = _p._visual.find_children("*", "Skeleton3D", true, false)[0]
		var bi := sk.find_bone(str(cam["bone"]))
		var bp := sk.global_transform * sk.get_bone_global_pose(bi).origin
		var dv: Array = cam.get("dir", [1, 0, 1])
		var vb: Basis = (_p._visual as Node3D).global_transform.basis.orthonormalized()
		var dw: Vector3 = (vb * Vector3(float(dv[0]), float(dv[1]), float(dv[2]))).normalized()
		_cam.global_position = bp + dw * dist
		_cam.look_at(bp, Vector3.UP)
	elif cam.get("back", false):
		_cam.global_position = c - fwd * dist * 0.7 + side * dist * 0.7 + Vector3(0, cam.get("h", 0.6), 0)
	elif cam.get("side", false):
		_cam.global_position = c + side * dist + Vector3(0, cam.get("h", 0.6), 0)
	elif cam.get("front", false):
		_cam.global_position = c + fwd * dist + side * dist * 0.35 + Vector3(0, cam.get("h", 0.6), 0)
	else:
		_cam.global_position = c + (fwd + side).normalized() * dist + Vector3(0, cam.get("h", 0.6), 0)
	if not cam.has("bone") and not cam.has("fixed") and not cam.get("tps", false) and not cam.get("grip", false):
		_cam.look_at(c, Vector3.UP)
	if cam.get("notrail", false) and _p._sword_trail != null:
		_p._sword_trail.visible = false
	if cam.has("hide"):
		# 診斷視圖：暫時隱藏指定衣料網格（正式展示不用）
		for m in _p.find_children("*", "MeshInstance3D", true, false):
			if str(m.name) in cam["hide"]:
				(m as Node3D).visible = false
	if cam.get("notrail", false):
		# 無特效審片：火花／煙塵／速度線（GPUParticles）與點光源（命中閃光）全部隱藏；太陽（Directional）保留
		for n in root.find_children("*", "GPUParticles3D", true, false):
			(n as Node3D).visible = false
		for n in root.find_children("*", "OmniLight3D", true, false):
			(n as Node3D).visible = false
	_want_dump = cam.get("dump", false)
	if cam.get("video", false) and _t > float(cam.get("vstart", 1.5)):
		var vd: String = OUT + _tests[_ti][0] + "/"
		if _vframe == 0:
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(vd))
		root.get_viewport().get_texture().get_image().save_png(vd + "f%04d.png" % _vframe)
		var vs := _state()
		vs["vframe"] = _vframe
		if _p.has_method("r7c_running"):
			vs["r7c"] = [_p.call("r7c_running"), _p.get("r7c_lap"), _p.get("r7c_idx"), str(_p.get("r7c_exit")), Input.is_action_pressed("form13")]
		(_log[_tests[_ti][0]] as Array).append(vs)
		_vframe += 1
	_wolf_tick()
	if _t > 0.0 and int(_t * 10.0) != int((_t - delta) * 10.0):
		var st := _state()
		(_log[_tests[_ti][0]] as Array).append(st)
	for sh in _shots_pending.duplicate():
		if _t >= sh[0]:
			_pending_name = sh[1]
			_shots_pending.erase(sh)
			_shot_wait = 2
			return false
	if _t >= _tests[_ti][3]:
		_next_test()
	return false

var _pending_name := ""

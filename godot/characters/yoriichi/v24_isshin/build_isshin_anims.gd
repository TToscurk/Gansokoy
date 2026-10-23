extends SceneTree
## 一次性工具：把 Blender 重定向輸出的 JSON（glTF/Godot 局部旋轉＋Hips 位置）烘成 Animation .res。
## 用法：godot --headless --path godot -s res://characters/yoriichi/v24_isshin/build_isshin_anims.gd
## 路徑慣例與 yoriichi_v24.glb 內建動畫相同：相對 glb 根節點的 "緣一_fbx/Armature/Skeleton3D:<bone>"。
const SK := "緣一_fbx/Armature/Skeleton3D:"
const OUT := "res://characters/yoriichi/v24_isshin/anims/"
const JOBS := {
	"isshin_walk": "D:/research/sekiro_r8_p0/retarget/godot_tracks_a000_405000.json",
	"isshin_idle": "D:/research/sekiro_r8_p0/retarget/godot_tracks_a000_400000.json",
	"isshin_back": "D:/research/sekiro_r8_p0/retarget/godot_tracks_a000_405001.json",
	"isshin_strafe_l": "D:/research/sekiro_r8_p0/retarget/godot_tracks_a000_405002.json",
	"isshin_strafe_r": "D:/research/sekiro_r8_p0/retarget/godot_tracks_a000_405003.json",
	"isshin_run": "D:/research/sekiro_r8_p0/retarget/godot_tracks_a000_405010.json",
	"isshin_turn_l90": "D:/research/sekiro_r8_p0/retarget/godot_tracks_a000_405400.json",
	"isshin_turn_r90": "D:/research/sekiro_r8_p0/retarget/godot_tracks_a000_405401.json",
	"isshin_turn_l180": "D:/research/sekiro_r8_p0/retarget/godot_tracks_a000_405402.json",
	"isshin_turn_r180": "D:/research/sekiro_r8_p0/retarget/godot_tracks_a000_405403.json",
	"isshin_dodge_l": "D:/research/sekiro_r8_p0/retarget/godot_tracks_a000_405012.json",
	"isshin_dodge_r": "D:/research/sekiro_r8_p0/retarget/godot_tracks_a000_405013.json",
	# _reach＝notes/fix_twohand_reach.py 修正後版本（舉刀最高點左鎖骨前引＋右上臂微收，左手可握到刀柄）
	"isshin_slash_v": "D:/research/sekiro_r8_p0/retarget/godot_tracks_a000_003012_reach.json",
	# 兩刀連段（notes/build_combo.py；v1 版存 godot_tracks_combo_vh_v1.json 供回退）：縱斬 A f0–18 → 9 格交接（左腳釘地、右腳後撤）→ 橫斬 3071 f9–102；根位移已換算成公尺
	"isshin_slash_vh": "D:/research/sekiro_r8_p0/retarget/godot_tracks_combo_vh.json",
	# 三刀連段：同上到 3071 f20，再 8 格交接（右腳釘地）接一心 TAE 3031 左上→右下袈裟斬 f13–115（回到待機姿）
	"isshin_slash_vhx": "D:/research/sekiro_r8_p0/retarget/godot_tracks_combo_vhx.json",
	# 跨角色融合候選：同上到 3071 f20，7 格交接接 弦一郎（c7100）TAE 3001 雙手上步唐竹斬 f7–71（結尾為弦一郎警戒姿）
	"isshin_slash_vhg": "D:/research/sekiro_r8_p0/retarget/godot_tracks_combo_vhg.json",
	# 葦名流居合（c1400 居合型＝佐瀬甚助／水生氏成用的 a100 動畫組）：快速拔刀橫斬 a100_003021（TAE 100003021）＋居合構 a100_400000。
	# notes/build_iai.py 已把拔刀／納刀改成「刀身經過緣一自己的鞘口」並附逐格刀可見度（*_sword.json）。
	"isshin_iai": "D:/research/sekiro_r8_p0/retarget/godot_tracks_iai_quick.json",
	"isshin_iai_stance": "D:/research/sekiro_r8_p0/retarget/godot_tracks_iai_stance.json",
	# 葦名流二連斬（c1400 居合型 a100_003010／TAE 100003010）：鞘中起手 → 拔刀逆袈裟（上撩）→ 沿同一斜線袈裟斬下 → 殘心 → 血振 → 納刀
	# notes/build_twocut.py（沿用 build_iai.py 的鞘口拔刀／納刀模型）
	"isshin_twocut": "D:/research/sekiro_r8_p0/retarget/godot_tracks_twocut.json",
	# 主城劍客（c1400 a000「剣客 守り／攻めタイプ」）前衝突刺 a000_003014（TAE 3014）：雙手、刀已出鞘、命中時刀軸朝正前方；
	# 直接用 bl_retarget_walk.py 的重定向（Godot 骨架上刀離身體各部位 ≥ 2.7 cm，不需推刀）。
	# 註：第一輪盤點寫成「突刺」的 a000_003057 其實刀尖朝後、雙手把柄頭往前推，不是突刺。
	"isshin_thrust": "D:/research/sekiro_r8_p0/retarget/godot_tracks_c1400_a000_003014.json",
	# 主城劍客退步縱斬 a000_003009（TAE 3009）：雙手、刀已出鞘；舉刀過頂 → 邊後退邊縱斬下（命中窗內刀由頭頂後方劈到身前下方）；
	# 直接用 bl_retarget_walk.py 的重定向（Godot 骨架上刀離身體 ≥ 4.8 cm）
	"isshin_backcut": "D:/research/sekiro_r8_p0/retarget/godot_tracks_c1400_a000_003009.json",
	# 主城劍客雙手交叉二連斬：a000_003072（左上→右下縱斬，斬完刀回到頭頂）→ 橋接 10 格 → a000_003056（由頭頂右上→左下袈裟）。
	# 原定順序 3056→3072 姿勢不相容（需要整個重新舉刀），改用 3072→3056；notes/pair_3056_3072.py、notes/build_pair.py
	"isshin_pairx": "D:/research/sekiro_r8_p0/retarget/godot_tracks_pair_x.json",
	# ==== BATCH ANIMS BEGIN（notes/gen_batch_moves.py 產生；手改會被覆蓋）
	"isshin_q_sidecut": "D:/research/sekiro_r8_p0/retarget/godot_tracks_c7400_a000_003015.json",
	"isshin_q_sidevert": "D:/research/sekiro_r8_p0/retarget/godot_tracks_c5400_a000_003084_fx.json",
	"isshin_q_pivotcut": "D:/research/sekiro_r8_p0/retarget/godot_tracks_c5400_a000_003025.json",
	"isshin_q_spinpass": "D:/research/sekiro_r8_p0/retarget/godot_tracks_c7400_a000_003021.json",
	"isshin_q_jumpcut": "D:/research/sekiro_r8_p0/retarget/godot_tracks_c7100_a000_003022.json",
	"isshin_q_aerial3": "D:/research/sekiro_r8_p0/retarget/godot_tracks_c7100_a000_003026.json",
	"isshin_q_gen3": "D:/research/sekiro_r8_p0/retarget/godot_tracks_c7100_a000_003041_fx.json",
	"isshin_q_emma2": "D:/research/sekiro_r8_p0/retarget/godot_tracks_c7400_a000_003019_fx.json",
	"isshin_q_flick": "D:/research/sekiro_r8_p0/retarget/godot_tracks_c7100_a000_003002.json",
	"isshin_q_emmacut": "D:/research/sekiro_r8_p0/retarget/godot_tracks_c7400_a000_003067.json",
	"isshin_q_dashcut": "D:/research/sekiro_r8_p0/retarget/godot_tracks_c7400_a000_003027.json",
	"isshin_q_iaiup": "D:/research/sekiro_r8_p0/retarget/godot_tracks_iai_up.json",
	"isshin_q_retreat": "D:/research/sekiro_r8_p0/retarget/godot_tracks_c1400_a000_003013.json",
	"isshin_q_c_emma": "D:/research/sekiro_r8_p0/retarget/godot_tracks_combo_emma.json",
	"isshin_q_c_retthrust": "D:/research/sekiro_r8_p0/retarget/godot_tracks_combo_retthrust.json",
	"isshin_draw": "D:/research/sekiro_r8_p0/retarget/godot_tracks_iai_quick.json",
	"isshin_noto": "D:/research/sekiro_r8_p0/retarget/godot_tracks_twocut.json",
	# ==== BATCH ANIMS END
	# R9（notes/r9/）：衝刺循環（弦一郎 a000_405010，刀身推離右大腿 2.4 cm 的 _fx 版）、不攻擊的跳躍（3022 起跳＋上半身回待機的落地）、日之呼吸・圓舞（永真 3008 重新配時）
	"isshin_r9_sprint": "D:/research/sekiro_r8_p0/retarget/godot_tracks_c7100_a000_405010_fx.json",
	"isshin_r9_jump": "D:/research/sekiro_r8_p0/retarget/godot_tracks_r9_jump.json",
	"isshin_sun_enbu": "D:/research/sekiro_r8_p0/retarget/godot_tracks_sun_enbu.json",
}

## 只取前 N 格（單發動作）。slash_v＝一心 TAE 3038（hkx a000_003012）的第一刀：中段→上段→直劈→殘心（f0–f19，0.63 s）；
## 之後原動作會抬回上段並接第二刀，不用。
const TRIM := {"isshin_slash_v": 20}
## 取出的片段後面補幾格「定格最後一姿」，讓 OneShot 的淡出發生在殘心之後（不然淡出從 0.45 s 就開始，把命中後的隨揮吃掉）。
const PAD := {"isshin_slash_v": 12}

## 循環相位平移（占整個循環的比例）：把各動作的左右腳站立時機對齊走路（walk：左 0.054／右 0.576），
## 斜向混合時兩支動作的支撐腳才同時間，不然混合出來的腳會漂（實測 fwd+L 站立腳世界速度 0.76 m/s）。
## 數值來自 measure_isshin_clips.gd 的「站立相位」（左右腳圓周平均後取平均偏移）。
const SHIFT := {"isshin_back": 0.066, "isshin_strafe_l": 0.473, "isshin_strafe_r": -0.367}

var roots := {}

## 取前 n_src 格，再用最後一個值補到 n 格
func _ext(arr: Array, n_src: int, n: int) -> Array:
	var out: Array = arr.slice(0, n_src)
	while out.size() < n:
		out.append(out[out.size() - 1])
	return out

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for name_ in JOBS:
		if not FileAccess.file_exists(JOBS[name_]):
			print("skip (no json) ", name_)
			continue
		var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(JOBS[name_]))
		var fps: float = d["fps"]
		var n: int = int(d["loop_frames"])           # 循環：首尾同姿 → 截掉重複的最後一格；單發（轉身／閃避）：全部幀
		var n_src := n
		if TRIM.has(name_):
			n_src = mini(n, int(TRIM[name_]))
		n = n_src + int(PAD.get(name_, 0))
		var is_loop: bool = d.get("is_loop", true)
		var a := Animation.new()
		a.length = n / fps if is_loop else (n - 1) / fps
		a.loop_mode = Animation.LOOP_LINEAR if is_loop else Animation.LOOP_NONE
		if d.get("root") != null:
			var rt: Dictionary = d["root"]
			roots[name_] = {"fps": fps, "frames": n, "length": a.length, "yaw": _ext(rt["yaw_rad"], n_src, n), "left": _ext(rt["left_m"], n_src, n), "fwd": _ext(rt["fwd_m"], n_src, n)}
		var k: int = int(round(SHIFT.get(name_, 0.0) * n))
		var hp: Array = d["hips_pos"]
		var tp := a.add_track(Animation.TYPE_POSITION_3D)
		a.track_set_path(tp, NodePath(SK + "mixamorig_Hips"))
		for f in n:
			var sf: int = mini(posmod(f - k, n), n_src - 1)
			a.position_track_insert_key(tp, f / fps, Vector3(hp[sf][0], hp[sf][1], hp[sf][2]))
		var tracks: Dictionary = d["tracks"]
		for bone in tracks:
			var t := a.add_track(Animation.TYPE_ROTATION_3D)
			a.track_set_path(t, NodePath(SK + bone))
			var q: Array = tracks[bone]
			for f in n:
				var sf: int = mini(posmod(f - k, n), n_src - 1)
				a.rotation_track_insert_key(t, f / fps, Quaternion(q[sf][0], q[sf][1], q[sf][2], q[sf][3]).normalized())
		if d.has("iai_sword"):
			var sf := FileAccess.open(OUT + name_ + "_sword.json", FileAccess.WRITE)
			sf.store_string(JSON.stringify(d["iai_sword"]))
			sf.close()
		var path: String = OUT + name_ + ".res"
		var err := ResourceSaver.save(a, path)
		print("saved ", path, " err=", err, " len=", a.length, " tracks=", a.get_track_count(), " keys/track=", n)
	var rf := FileAccess.open(OUT + "root_motion.json", FileAccess.WRITE)
	rf.store_string(JSON.stringify(roots))
	rf.close()
	print("root_motion.json clips=", roots.keys())
	quit()

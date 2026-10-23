extends SceneTree
## R10 動畫烘焙（只烘 R10 新增的動作，不重烘既有 .res）：r10/r10_anim_jobs.json → anims/<name>.res，根位移寫 anims/root_motion_r10.json
## （combat_locomotion.gd 讀 root_motion.json 後會合併這份；既有 root_motion.json 不動）。
## 用法：godot --headless --path godot -s res://characters/yoriichi/v24_isshin/r10/build_r10_anims.gd [-- --only=name1,name2]
## jobs 格式：{name: {"json": 絕對路徑, "trim": 只取前 N 格(選用), "pad": 補定格數(選用), "start": 從第幾格開始(選用)}}
const SK := "緣一_fbx/Armature/Skeleton3D:"
const OUT := "res://characters/yoriichi/v24_isshin/anims/"
const JOBS := "res://characters/yoriichi/v24_isshin/r10/r10_anim_jobs.json"

func _ext(arr: Array, i0: int, n_src: int, n: int) -> Array:
	var out: Array = arr.slice(i0, i0 + n_src)
	while out.size() < n:
		out.append(out[out.size() - 1])
	return out

func _init() -> void:
	var jobs_path := JOBS
	var only := []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7).split(",")
		elif a.begins_with("--jobs="):              # R11：其他階段的 jobs 檔（同格式；沒給＝R10 的）
			jobs_path = a.substr(7)
	var jobs: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(jobs_path))
	var rpath := OUT + "root_motion_r10.json"
	var roots: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(rpath)) if FileAccess.file_exists(rpath) else {}
	var n_ok := 0
	for name_ in jobs:
		if only.size() > 0 and not only.has(name_):
			continue
		var J: Dictionary = jobs[name_]
		if not FileAccess.file_exists(J["json"]):
			print("skip (no json) ", name_)
			continue
		var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(J["json"]))
		var fps: float = d["fps"]
		var is_loop: bool = d.get("is_loop", true)
		var total: int = int(d["loop_frames"])          # 同 build_isshin_anims.gd：循環＝截掉重複的最後一格；單發＝全部幀
		var i0: int = int(J.get("start", 0))
		var n_src: int = mini(total - i0, int(J.get("trim", total)))
		var n: int = n_src + int(J.get("pad", 0))
		var a := Animation.new()
		a.length = n / fps if is_loop else (n - 1) / fps
		a.loop_mode = Animation.LOOP_LINEAR if is_loop else Animation.LOOP_NONE
		if d.get("root") != null:
			var rt: Dictionary = d["root"]
			var yaw := _ext(rt["yaw_rad"], i0, n_src, n)
			var left := _ext(rt["left_m"], i0, n_src, n)
			var fwd := _ext(rt["fwd_m"], i0, n_src, n)
			var y0 := float(yaw[0])
			var l0 := float(left[0])
			var f0 := float(fwd[0])
			for i in n:                         # 從 start 開始時根位移歸零
				yaw[i] = float(yaw[i]) - y0
				left[i] = float(left[i]) - l0
				fwd[i] = float(fwd[i]) - f0
			roots[name_] = {"fps": fps, "frames": n, "length": a.length, "yaw": yaw, "left": left, "fwd": fwd}
		else:                                     # 來源沒有根位移（refframe 缺）：原地動作，根位移全 0
			var z := []
			z.resize(n)
			z.fill(0.0)
			roots[name_] = {"fps": fps, "frames": n, "length": a.length, "yaw": z, "left": z.duplicate(), "fwd": z.duplicate()}
		var hp: Array = d["hips_pos"]
		var tp := a.add_track(Animation.TYPE_POSITION_3D)
		a.track_set_path(tp, NodePath(SK + "mixamorig_Hips"))
		for f in n:
			var sf: int = i0 + mini(f, n_src - 1)
			a.position_track_insert_key(tp, f / fps, Vector3(hp[sf][0], hp[sf][1], hp[sf][2]))
		var tracks: Dictionary = d["tracks"]
		for bone in tracks:
			var t := a.add_track(Animation.TYPE_ROTATION_3D)
			a.track_set_path(t, NodePath(SK + bone))
			var q: Array = tracks[bone]
			for f in n:
				var sf: int = i0 + mini(f, n_src - 1)
				a.rotation_track_insert_key(t, f / fps, Quaternion(q[sf][0], q[sf][1], q[sf][2], q[sf][3]).normalized())
		if d.has("iai_sword"):
			var sw: Dictionary = d["iai_sword"]
			var fr: Array = (sw["frames"] as Array).slice(i0, i0 + n_src)
			while fr.size() < n:
				fr.append(fr[fr.size() - 1])
			var sf2 := FileAccess.open(OUT + name_ + "_sword.json", FileAccess.WRITE)
			sf2.store_string(JSON.stringify({"fps": sw["fps"], "frames": fr}))
			sf2.close()
		var err := ResourceSaver.save(a, OUT + name_ + ".res")
		if err == OK:
			n_ok += 1
		else:
			print("save FAIL ", name_, " err=", err)
	var rf := FileAccess.open(rpath, FileAccess.WRITE)
	rf.store_string(JSON.stringify(roots))
	rf.close()
	print("R10 anims saved ", n_ok, "  root_motion_r10 clips=", roots.size())
	quit()

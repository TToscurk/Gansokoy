extends SceneTree
## 本輪新增動作的「評片影片」：42 支連續播、逐格存 PNG，再用 ffmpeg 併成 mp4。
##
##   Godot.exe --path godot --script tools/reel_new_clips.gd
##   ffmpeg -framerate 30 -i reel/frame_%05d.png -c:v libx264 -pix_fmt yuv420p reel.mp4
##
## 為什麼不用 --write-movie：Movie Maker 錄的是**主視窗**、影格率取自專案設定（60），
## 而這支要 30 fps＋固定 640×800、還要逐格控制。自己存 PNG 序列最穩。
##
## rig 沿用 tools/_shot_clip_review.gd 的作法（同一個「看得出對錯」的舞台）：
##   - install characters/yoriichi/player_yoriichi.tscn（刀／鞘照遊戲真實掛法）
##   - 關掉並移除 AnimationTree（一 active，AnimationPlayer 的結果就被丟掉→紅色一坨）
##   - 移除遊戲相機、根節點歸零（腳踩 y=0、地板 y=0）
##   - 保留地板 + y=0 紅色基準線（貼地／懸空一眼看出）
##
## 輸出：D:/神社/shrine/work/shots/reel/frame_00001.png ...

const PLAYER := "res://characters/yoriichi/player_yoriichi.tscn"
const ANIM := "res://characters/yoriichi/animations/"
const OUT := "D:/神社/shrine/work/shots/reel/"
const FPS := 30.0
const W := 640
const H := 800
const HOLD := 12          # 每支播完後停幾格（讓眼睛跟得上）
const LEAD := 6           # 開播前等幾格（等第一格姿態穩定）

var _clips: Array = []
var _skip := 0       # --skip=N 跳過前 N 支（續跑用）
var _idx0 := 0       # --idx=N  從第 N 格接下去編號（續跑用）


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--skip="):
			_skip = int(a.split("=", 1)[1])
		elif a.begins_with("--idx="):
			_idx0 = int(a.split("=", 1)[1])
	_collect()
	_run.call_deferred()


func _collect() -> void:
	var seen := {}
	for grp in [["_mixamo_aligned", "aligned"], ["_mixamo_staging", "staging"], ["_mixamo_gap_staging", "gap"]]:
		var d := DirAccess.open(ANIM + grp[0])
		if d == null:
			continue
		var fs := d.get_files()
		fs.sort()
		for f in fs:
			if not f.ends_with(".res"):
				continue
			var nm: String = f.replace(".res", "")
			if seen.has(nm):
				continue
			seen[nm] = true
			_clips.append({"n": nm, "src": grp[1], "p": ANIM + grp[0] + "/" + f})
	_clips.append({"n": "yoriichi_deathblow", "src": "final-slice", "p": ANIM + "yoriichi_deathblow.res"})


func _settle(n: int) -> void:
	for i in n:
		await process_frame


func _shoot(idx: int) -> void:
	root.get_viewport().get_texture().get_image().save_png(OUT + "frame_%05d.png" % idx)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var total := _clips.size()
	if _skip > 0:
		_clips = _clips.slice(_skip)
	print("[REEL] 共 %d 支（跳過前 %d 支，剩 %d 支；起始格 %d）" % [
		total, _skip, _clips.size(), _idx0])
	Engine.max_fps = int(FPS)

	# ---- 舞台（照 _shot_clip_review.gd，唯一差別是畫在主視窗）----
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.35, 0.38, 0.42)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_energy = 1.4
	root.add_child(sun)
	var sun2 := DirectionalLight3D.new()
	sun2.rotation_degrees = Vector3(-20, -120, 0)
	sun2.light_energy = 0.5
	root.add_child(sun2)

	var floor_mi := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(14, 0.02, 14)
	floor_mi.mesh = fm
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.22, 0.24, 0.27)
	floor_mi.material_override = fmat
	floor_mi.position = Vector3(0, -0.01, 0)
	root.add_child(floor_mi)
	var line_mi := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(3.2, 0.004, 0.02)
	line_mi.mesh = lm
	var lmat := StandardMaterial3D.new()
	lmat.albedo_color = Color(0.9, 0.25, 0.2)
	lmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_mi.material_override = lmat
	line_mi.position = Vector3(0, 0.003, 0)
	root.add_child(line_mi)

	var cam := Camera3D.new()
	cam.fov = 44.0
	cam.position = Vector3(-2.35, 1.65, -3.75)
	root.add_child(cam)
	cam.look_at(Vector3(0, 1.15, 0), Vector3.UP)
	cam.make_current()

	# 字幕：左上角顯示「第幾支／名稱／來源」
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var lab := Label.new()
	lab.position = Vector2(14, 10)
	lab.add_theme_font_size_override("font_size", 26)
	lab.add_theme_color_override("font_color", Color(1, 1, 1))
	lab.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	lab.add_theme_constant_override("outline_size", 6)
	layer.add_child(lab)

	# ---- 角色 ----
	var body: Node3D = (load(PLAYER) as PackedScene).instantiate()
	root.add_child(body)
	await _settle(8)
	body.set_process(false)
	body.set_physics_process(false)
	var trees := body.find_children("*", "AnimationTree", true, false)
	for t in trees:
		(t as AnimationTree).active = false
		t.queue_free()
	var cams := body.find_children("*", "Camera3D", true, false)
	for c in cams:
		(c as Camera3D).queue_free()
	cam.make_current()
	body.global_position = Vector3.ZERO
	await _settle(3)
	print("[REEL] 關掉 %d 個 AnimationTree、移除 %d 個相機" % [trees.size(), cams.size()])

	# 刀／鞘都顯示（手上那把 vs 鞘的位置同框才看得出拔收刀對不對）
	for nm in ["Sword_Hand", "Sword_Sheathed", "Sheath"]:
		var arr := body.find_children(nm, "", true, false)
		if not arr.is_empty():
			(arr[0] as Node3D).visible = true

	# ---- 播放器：**沿用遊戲自己的那顆**，只掛一個獨立 library ----
	# 為什麼不新增第二顆：兩顆 AnimationPlayer 會搶同一副骨架，輸出互相覆蓋。
	var aps := body.find_children("*", "AnimationPlayer", true, false)
	var ap: AnimationPlayer = null
	if aps.is_empty():
		ap = AnimationPlayer.new()
		body.add_child(ap)
	else:
		ap = aps[0] as AnimationPlayer
		for extra in aps.slice(1):
			(extra as AnimationPlayer).active = false
	ap.active = true
	ap.stop()
	await _settle(2)
	var lib := AnimationLibrary.new()
	ap.add_animation_library("reel", lib)

	var idx := _idx0
	var done := _skip
	for c in _clips:
		var anim: Animation = load(c["p"])
		if anim == null:
			print("[REEL] 載入失敗：%s" % c["p"])
			continue
		var key := "reel/%s" % c["n"]
		if lib.has_animation(c["n"]):
			lib.remove_animation(c["n"])
		lib.add_animation(c["n"], anim)
		lab.text = "%d/%d   %s   [%s]   %.2f s" % [
			idx + 1, _clips.size(), c["n"], c["src"], anim.length]
		ap.play(key)
		await _settle(LEAD)
		var n := int(ceil(anim.length * FPS)) + HOLD
		for i in n:
			await process_frame
			idx += 1
			_shoot(idx)
		done += 1
		print("[REEL] %2d/%d %-42s %5.2f s → 累計 %d 格" % [
			done, _clips.size(), c["n"], anim.length, idx])
		ap.stop()

	print("[REEL] ===== 完成：%d 格（%.1f s @%d fps）=====" % [idx, idx / FPS, int(FPS)])
	quit()

extends SceneTree
## 批次看片：把 .res 逐一套在**遊戲自己的 player 場景**（刀／鞘照遊戲真實掛法）或
## 純身體 FBX 上，抓等距 N 格畫面拼成 strip + contact sheet。
##
##   <godot_console.exe> --path godot --script res://tools/_shot_clip_review.gd -- \
##       [--clips=A,B | --dir=res://...] [--frames=5] [--per-sheet=4] [--tag=x] \
##       [--rig=player|body] [--sword=both|hand|sheath|off] [--cam=wide|upper]
##
## rig=player 直接實例化 characters/yoriichi/player_yoriichi.tscn：
##   - 刀在 BodyVisual/Armature/Skeleton3D/HandSocket（BoneAttachment3D, RightHand）
##   - 鞘＋鞘中刀在 .../SheathSocket（BoneAttachment3D, Hips）
## 這是判斷拔收刀唯一有意義的看法：手的路徑要對得上鞘口。
## 看片時兩把同時顯示（--sword=both）＝手上那把 vs 鞘的位置同框比對。
##
## ⚠ 一定要加地板：腳有沒有穿地／懸空，眼睛看最快。
## ⚠ shot 名一律 ASCII（capture 管線讀非 UTF-8 會壞）。
## ⚠ WASAPI 音效 ERROR 是這台機器的常態，不影響截圖。

const BODY := "res://characters/yoriichi/yoriichi_body.fbx"
const PLAYER := "res://characters/yoriichi/player_yoriichi.tscn"
const OUT := "D:/神社/shrine/work/shots/clip_review/"
const DEFAULT_DIR := "res://characters/yoriichi/animations/_mixamo_staging"
## 貼地基準用的遊戲原生 clip（校準地板用）
const IDLE := "res://characters/yoriichi/animations/yoriichi_idle_grounded.res"
const W := 480
const H := 640
const FPS := 30.0

var _dir := DEFAULT_DIR
var _names: Array = []
var _frames := 5
var _per_sheet := 4
var _tag := "preview"
var _rig := "player"
var _sword := "both"
var _cam := "wide"
var _ghost := false
var _cols := 1
var _step := 1


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dir="):
			_dir = a.split("=", 1)[1]
		elif a.begins_with("--clips="):
			for n in a.split("=", 1)[1].split(","):
				_names.append(n)
		elif a.begins_with("--frames="):
			_frames = maxi(2, int(a.split("=", 1)[1]))
		elif a.begins_with("--per-sheet="):
			_per_sheet = maxi(1, int(a.split("=", 1)[1]))
		elif a.begins_with("--tag="):
			_tag = a.split("=", 1)[1]
		elif a.begins_with("--rig="):
			_rig = a.split("=", 1)[1]
		elif a.begins_with("--sword="):
			_sword = a.split("=", 1)[1]
		elif a.begins_with("--cam="):
			_cam = a.split("=", 1)[1]
		elif a.begins_with("--ghost="):
			_ghost = a.split("=", 1)[1] != "0"
		elif a.begins_with("--cols="):
			_cols = maxi(1, int(a.split("=", 1)[1]))
		elif a.begins_with("--step="):
			_step = maxi(1, int(a.split("=", 1)[1]))
	_run.call_deferred()


func _settle(n: int) -> void:
	for i in n:
		await process_frame


## 腳部 4 根骨頭在世界座標的最低 y（= 腳底高度）
func _min_foot_y(sk: Skeleton3D) -> float:
	var lo := 1e9
	for b in ["LeftFoot", "RightFoot", "LeftToeBase", "RightToeBase"]:
		var i := sk.find_bone(b)
		if i >= 0:
			lo = minf(lo, (sk.global_transform * sk.get_bone_global_pose(i).origin).y)
	return lo


func _run() -> void:
	if _names.is_empty():
		var d := DirAccess.open(_dir)
		var fs := []
		for f in d.get_files():
			if f.ends_with(".res"):
				fs.append(f.replace(".res", ""))
		fs.sort()
		_names = fs
	if _names.is_empty():
		print("[shot] 沒有 clip")
		quit(1)
		return

	DirAccess.make_dir_recursive_absolute(OUT)

	var sv := SubViewport.new()
	sv.size = Vector2i(W, H)
	sv.own_world_3d = true
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sv.msaa_3d = Viewport.MSAA_2X
	root.add_child(sv)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.35, 0.38, 0.42)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	sv.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_energy = 1.4
	sv.add_child(sun)
	var sun2 := DirectionalLight3D.new()
	sun2.rotation_degrees = Vector3(-20, -120, 0)
	sun2.light_energy = 0.5
	sv.add_child(sun2)

	# 地板 + y=0 基準線
	var floor_mi := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(14, 0.02, 14)
	floor_mi.mesh = fm
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.22, 0.24, 0.27)
	floor_mi.material_override = fmat
	floor_mi.position = Vector3(0, -0.01, 0)
	sv.add_child(floor_mi)
	var line_mi := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(3.2, 0.004, 0.02)
	line_mi.mesh = lm
	var lmat := StandardMaterial3D.new()
	lmat.albedo_color = Color(0.9, 0.25, 0.2)
	lmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_mi.material_override = lmat
	line_mi.position = Vector3(0, 0.003, 0)
	sv.add_child(line_mi)

	var cam := Camera3D.new()
	sv.add_child(cam)
	# ⚠ 緣一的正面朝 **-Z**（tools/_shot_pose_isolated.gd 的註解寫相反；實測相機在 +Z 拍到的是背）。
	# 拔收刀要看得到鞘口與右手路徑，一律用正面 3/4。
	match _cam:
		"wide_r":                       # 正面 3/4（角色右前方）
			cam.fov = 40.0
			cam.position = Vector3(1.9, 1.35, -3.0)
			cam.look_at(Vector3(0, 0.95, 0), Vector3.UP)
		"upper":                        # 上半身＋刀的特寫（判斷握刀／腕部朝向）
			cam.fov = 34.0
			cam.position = Vector3(-1.05, 1.32, -1.75)
			cam.look_at(Vector3(0.0, 1.02, 0), Vector3.UP)
		"back":                         # 背面（對照用）
			cam.fov = 40.0
			cam.position = Vector3(2.1, 1.35, 3.1)
			cam.look_at(Vector3(0, 0.95, 0), Vector3.UP)
		"wide_tall":                    # 正面 3/4 拉高拉遠：翻滾／跳躍會騰空到 2.3 m
			cam.fov = 44.0
			cam.position = Vector3(-2.35, 1.65, -3.75)
			cam.look_at(Vector3(0, 1.15, 0), Vector3.UP)
		_:                              # wide = 正面 3/4（角色左前方，看得到左腰的鞘）
			cam.fov = 40.0
			cam.position = Vector3(-1.9, 1.35, -3.0)
			cam.look_at(Vector3(0, 0.95, 0), Vector3.UP)
	cam.make_current()

	var body: Node
	if _rig == "player":
		body = (load(PLAYER) as PackedScene).instantiate()
	else:
		body = (load(BODY) as PackedScene).instantiate()
	sv.add_child(body)
	await _settle(8)

	if _rig == "player":
		# 只關根節點（控制器 yoriichi_character.gd）的 process，別全關——
		# BoneAttachment3D / sheath_sway 需要正常更新才是遊戲真實樣貌。
		body.set_process(false)
		body.set_physics_process(false)
		# yoriichi_character.gd:1181 在 _ready 建 AnimationTree 並接管骨架。
		# AnimationTree 一 active，AnimationPlayer.seek() 的結果就被丟掉 →
		# 拍到的是未初始化的混合輸出（人形會變成一坨紅）。必須關掉並移除。
		var trees := body.find_children("*", "AnimationTree", true, false)
		for t in trees:
			(t as AnimationTree).active = false
			t.queue_free()
		# 遊戲自己的相機可能是 current（player_camera_adapter.gd）→ 鏡頭會貼在角色上。
		# 移除場景內所有相機，並把我的相機重新設為 current。
		var cams := body.find_children("*", "Camera3D", true, false)
		for c in cams:
			(c as Camera3D).queue_free()
		cam.make_current()
		# 控制器（或場景預設）把根節點擺在 y=-0.85，相機對著 y≈1 看就只拍到外套頂部
		# （人形變成一坨紅）。看片要在「腳踩 y=0、地板在 y=0」的條件下比對 → 歸零。
		(body as Node3D).global_position = Vector3.ZERO
		await _settle(3)
		print("[shot] 關掉 %d 個 AnimationTree、移除 %d 個遊戲相機；根節點歸零" % [trees.size(), cams.size()])
		# 強制刀／鞘的可見性（原本 Sword_Hand 是 visible=false，由控制器切換）
		var shown := []
		for nm in ["Sword_Hand", "Sword_Sheathed", "Sheath"]:
			var arr := body.find_children(nm, "", true, false)
			if arr.is_empty():
				continue
			var nd := arr[0] as Node3D
			var want := _sword == "both"
			if _sword == "hand":
				want = nm == "Sword_Hand"
			elif _sword == "sheath":
				want = nm != "Sword_Hand"
			elif _sword == "off":
				want = false
			nd.visible = want
			if want:
				shown.append(nm)
		print("[shot] rig=player 顯示: %s" % ", ".join(shown))

	# 透視身體：紅色長外套會把手／臂完全遮住，拔刀的手部路徑就看不到了。
	# 把「身體」網格改半透明（刀與鞘維持不透明）→ 看得到刀相對軀幹的位置。
	if _ghost:
		var made := 0
		for m in body.find_children("*", "MeshInstance3D", true, false):
			var mi := m as MeshInstance3D
			var p := str(mi.get_path())
			if p.contains("HandSocket") or p.contains("SheathSocket"):
				continue
			var gm := StandardMaterial3D.new()
			gm.albedo_color = Color(0.58, 0.18, 0.15, 0.28)
			gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			gm.cull_mode = BaseMaterial3D.CULL_DISABLED
			mi.material_override = gm
			made += 1
		print("[shot] ghost：%d 個身體網格改半透明" % made)

	var sk := body.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var ap := body.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	print("[shot] 骨數=%d 動畫播放器=%s" % [sk.get_bone_count(), ap.get_path()])
	if not ap.has_animation_library(""):
		ap.add_animation_library("", AnimationLibrary.new())

	# 校準地面：控制器在 _ready 會另外位移視覺節點，所以「根節點歸零」不等於腳踩在 0。
	# 用遊戲自己的 idle_grounded 當基準——量它的腳底世界 y，再把整尊平移，讓它落在
	# +0.0235（這套骨架的貼地值；tools/_probe_clip_foot.gd 實測）。
	# 這樣地板 y=0 就等於遊戲地面，每支 clip 的腳底都跟 idle 同基準，看圖不會被騙。
	if _rig == "player":
		var cal: Animation = load(IDLE)
		if cal != null:
			var libc := ap.get_animation_library("")
			libc.add_animation("_cal", cal)
			ap.play("_cal")
			var ref := 1e9
			for k in 12:
				ap.seek(cal.length * float(k) / 11.0, true)
				await _settle(2)
				ref = minf(ref, _min_foot_y(sk))
			var off := 0.0235 - ref
			(body as Node3D).global_position.y += off
			ap.stop()
			await _settle(2)
			print("[shot] 校準：idle 腳底世界 y=%+.4f → 平移 %+.4f → 腳底 %+.4f；再量 = %+.4f" % [
				ref, off, ref + off, _min_foot_y(sk)])

	var cl := CanvasLayer.new()
	sv.add_child(cl)
	var lab := Label.new()
	lab.add_theme_color_override("font_color", Color(0.03, 0.03, 0.03))
	lab.add_theme_color_override("font_outline_color", Color(1, 1, 1))
	lab.add_theme_constant_override("outline_size", 6)
	lab.add_theme_font_size_override("font_size", 15)
	lab.position = Vector2(6, 4)
	cl.add_child(lab)

	var lib := ap.get_animation_library("")
	var strips := []
	var idx := 0
	for name in _names:
		var anim: Animation = load("%s/%s.res" % [_dir, name])
		if anim == null:
			print("[shot] 載入失敗 %s" % name)
			continue
		idx += 1
		var cn := "c%d" % idx
		lib.add_animation(cn, anim)
		ap.play(cn)
		var total := int(round(anim.length * FPS))
		# 取樣格：_step=1 時是等距 _frames 格；_step>1 時是每 _step 格取一格（逐格審片用）
		var flist := []
		if _step <= 1:
			for k in _frames:
				flist.append(int(round(float(k) * float(maxi(0, total - 1)) / float(maxi(1, _frames - 1)))))
		else:
			var f := 0
			while f < total and flist.size() < _frames:
				flist.append(f)
				f += _step
		var nf := flist.size()
		var cols := _cols if _cols > 1 else nf
		var rows := int(ceil(float(nf) / float(cols)))
		var strip := Image.create(W * cols, H * rows, false, Image.FORMAT_RGBA8)
		for k in nf:
			var fr: int = flist[k]
			ap.seek(float(fr) / FPS, true)
			lab.text = "%s  f%d/%d" % [name, fr, total]
			await _settle(3)
			await RenderingServer.frame_post_draw
			var img := sv.get_texture().get_image()
			img.convert(Image.FORMAT_RGBA8)
			strip.blit_rect(img, Rect2i(0, 0, W, H), Vector2i(W * (k % cols), H * (k / cols)))
		var sp := "%s%s_%s.png" % [OUT, name, _tag]
		strip.save_png(sp)
		print("[shot] %s（%d格 每%d格取1 / 全%d格）" % [name, nf, _step, total])
		strips.append({"name": name, "img": strip})
		ap.stop()

	# contact sheet：每 _per_sheet 支疊一張（網格模式 _cols>1 時每支自己一張，不併）
	var s := 0
	while _cols <= 1 and s < strips.size():
		var grp: Array = strips.slice(s, s + _per_sheet)
		var sz: Vector2i = (grp[0]["img"] as Image).get_size()
		var sheet := Image.create(sz.x, sz.y * grp.size(), false, Image.FORMAT_RGBA8)
		for r in grp.size():
			sheet.blit_rect(grp[r]["img"], Rect2i(0, 0, sz.x, sz.y), Vector2i(0, sz.y * r))
		var nm := "sheet_%s_%02d.png" % [_tag, s / _per_sheet + 1]
		sheet.save_png(OUT + nm)
		print("[shot] -> %s" % nm)
		s += _per_sheet
	print("[shot] 完成 %d 支" % strips.size())
	quit(0)

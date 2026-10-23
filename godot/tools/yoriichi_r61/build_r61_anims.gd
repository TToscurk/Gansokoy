extends SceneTree
## R6.1：把 Blender R6.1 匯出的 JSON（work/yoriichi_r61/export/<name>.json）建成 Godot Animation .res，輸出 v24/anims_r61/。
## （複製自 tools/yoriichi_r6/build_r6_anims.gd；R6 的 anims_r6/ 與原工具一律不動。metadata 鍵沿用 r5_/r6_，R6 控制器邏輯可直接讀。）
## 軌道路徑／順序／型別沿用 R3 attack_combo.res（同一 v2.4 骨架慣例）；R3 anims/、R4 anims_r4/、R5 anims_r5/ 一律不動。
## meta.loop = true → LOOP_LINEAR（待機）；meta.r5（鞘 offset／刀身露出／手上刀可見／命中窗）沿用 R5 的 metadata 鍵，
## 讓 R5 拔刀機制（yoriichi_character_r5.gd）直接讀 R6 拔刀斬。
##   godot --headless --path . -s res://tools/yoriichi_r61/build_r61_anims.gd -- [name1,name2,...]
const SRC_DIR := "D:/神社/shrine/work/yoriichi_r61/export/"
const OUT_DIR := "res://characters/yoriichi/v24/anims_r61/"
const TEMPLATE := "res://characters/yoriichi/v24/anims/attack_combo.res"

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var only: Array = []
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and args[0] != "":
		only = Array(args[0].split(","))
	var tpl: Animation = load(TEMPLATE)
	var names: Array = []
	for fn in DirAccess.get_files_at(SRC_DIR):
		if fn.ends_with(".json") and not fn.ends_with("_extras_blender.json") and (fn.begins_with("r61_") or fn.begins_with("r61c_")):
			var nm := fn.get_basename()
			if only.is_empty() or only.has(nm):
				names.append(nm)
	for nm in names:
		_build(tpl, nm)
	quit()

func _build(tpl: Animation, nm: String) -> void:
	var f := FileAccess.open(SRC_DIR + nm + ".json", FileAccess.READ)
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	var fps: float = float(d.fps)
	var hips: Array = d.hips_pos
	var n: int = hips.size()
	var meta: Dictionary = d.get("meta", {})
	var loop := bool(meta.get("loop", false))
	var a := Animation.new()
	a.length = float(n - 1) / fps
	a.step = 1.0 / fps
	a.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	var bones: Dictionary = d.bones
	var made := 0
	var missing: Array = []
	for ti in tpl.get_track_count():
		var path := tpl.track_get_path(ti)
		var typ := tpl.track_get_type(ti)
		var bn := str(path).get_slice(":", 1)
		if typ == Animation.TYPE_POSITION_3D:
			var t := a.add_track(Animation.TYPE_POSITION_3D)
			a.track_set_path(t, path)
			a.track_set_interpolation_type(t, Animation.INTERPOLATION_LINEAR)
			for i in n:
				var p: Array = hips[i]
				a.position_track_insert_key(t, float(i) / fps, Vector3(p[0], p[1], p[2]))
			made += 1
		elif typ == Animation.TYPE_ROTATION_3D:
			if not bones.has(bn):
				missing.append(bn)
				continue
			var t := a.add_track(Animation.TYPE_ROTATION_3D)
			a.track_set_path(t, path)
			a.track_set_interpolation_type(t, Animation.INTERPOLATION_LINEAR)
			var qs: Array = bones[bn]
			var prev := Quaternion.IDENTITY
			for i in n:
				var q: Array = qs[i]
				var qq := Quaternion(q[0], q[1], q[2], q[3]).normalized()
				if i > 0 and prev.dot(qq) < 0.0:
					qq = -qq
				prev = qq
				a.rotation_track_insert_key(t, float(i) / fps, qq)
			made += 1
	if meta.has("r5"):
		var r5: Dictionary = meta.r5
		var saya := PackedFloat32Array()
		for row in r5.saya_offset_cols:
			for v in row:
				saya.append(float(v))
		var clip := PackedFloat32Array()
		for v in r5.clip_y:
			clip.append(float(v))
		var vis := PackedByteArray()
		for v in r5.hand_visible:
			vis.append(1 if v else 0)
		a.set_meta("r5_fps", fps)
		a.set_meta("r5_saya_offset", saya)
		a.set_meta("r5_clip_y", clip)
		a.set_meta("r5_hand_visible", vis)
		a.set_meta("r5_hit_window", PackedInt32Array(r5.hit_window))
	if meta.has("markers"):
		a.set_meta("r5_markers", meta.markers)
	for k in meta:
		if k not in ["r5", "markers", "loop", "root_speed", "orig"]:
			# 已帶 r6_ 前綴的鍵（例：r6_ctrl_end）不再重複加前綴
			a.set_meta(str(k) if str(k).begins_with("r6_") else "r6_" + str(k), meta[k])
	# 由正式片段改出的（meta.orig）：原片段的 metadata（root_speed、sections…）原樣帶過來，loop 也沿用原片段
	if meta.has("orig") and ResourceLoader.exists(str(meta.orig)):
		var o: Animation = load(str(meta.orig))
		for k in o.get_meta_list():
			a.set_meta(k, o.get_meta(k))
		a.loop_mode = o.loop_mode
	a.set_meta("r6_source", "work/yoriichi_r61 Blender R6.1 candidate (" + nm + ")")
	var err: int = ResourceSaver.save(a, OUT_DIR + nm + ".res")
	print("R61_BUILT ", nm, " len=", a.length, " frames=", n, " tracks=", made, " missing=", missing.size(), " loop=", loop, " err=", err)

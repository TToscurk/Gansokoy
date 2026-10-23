extends SceneTree
## R5：把 Blender R5 匯出的 JSON（work/yoriichi_r5/export/r5_quickdraw_kesa.json）建成 Godot Animation .res。
## 軌道路徑／順序／型別沿用 R3 attack_combo.res（同一 v2.4 骨架慣例）；輸出到 v24/anims_r5/（R3 anims/、R4 anims_r4/ 不動）。
## 鞘的左手控制（saya offset）、刀身露出長度、手上刀可見性、命中窗口存成 Animation metadata，由候選子類 yoriichi_character_r5.gd 讀。
##   godot --headless --path . -s res://tools/yoriichi_r5/build_r5_anims.gd
const SRC := "D:/神社/shrine/work/yoriichi_r5/export/r5_quickdraw_kesa.json"
const OUT_DIR := "res://characters/yoriichi/v24/anims_r5/"
const OUT := OUT_DIR + "r5_quickdraw_kesa.res"
const TEMPLATE := "res://characters/yoriichi/v24/anims/attack_combo.res"

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var tpl: Animation = load(TEMPLATE)
	var f := FileAccess.open(SRC, FileAccess.READ)
	if f == null:
		push_error("missing " + SRC)
		quit(1)
		return
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	var fps: float = float(d.fps)
	var hips: Array = d.hips_pos
	var n: int = hips.size()
	var a := Animation.new()
	a.length = float(n - 1) / fps
	a.step = 1.0 / fps
	a.loop_mode = Animation.LOOP_NONE
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
	var meta: Dictionary = d.meta
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
	a.set_meta("r5_saya_offset", saya)        # 每格 12 floats：basis x,y,z 欄 + origin（SheathSocket 空間）
	a.set_meta("r5_clip_y", clip)             # 手上刀：刀本地 y > clip_y 的部分在鞘內，不畫
	a.set_meta("r5_hand_visible", vis)        # 1 = 手上刀可見（握柄～納刀完成），0 = 鞘中刀可見
	a.set_meta("r5_hit_window", PackedInt32Array(r5.hit_window))
	a.set_meta("r5_markers", meta.markers)
	a.set_meta("r5_source", "work/yoriichi_r5 Blender R5 candidate R5_QuickDrawKesa (R5_candidate.blend)")
	var err: int = ResourceSaver.save(a, OUT)
	print("R5_BUILT len=", a.length, " frames=", n, " tracks=", made, " missing=", missing, " saya=", saya.size() / 12, " err=", err)
	quit()

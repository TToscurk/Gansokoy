extends SceneTree
## R4：把 Blender R4 匯出的 JSON（work/yoriichi_r4/export/*.json）建成 Godot Animation .res，
## 軌道路徑／順序／型別沿用 R3 attack_combo.res（同一 v2.4 骨架慣例）。輸出到 v24/anims_r4/（R3 v24/anims/ 不動）。
##   godot --headless --path . -s res://tools/yoriichi_r4/build_r4_anims.gd
const SRC_DIR := "D:/神社/shrine/work/yoriichi_r4/export/"
const OUT_DIR := "res://characters/yoriichi/v24/anims_r4/"
const TEMPLATE := "res://characters/yoriichi/v24/anims/attack_combo.res"
const CLIPS := ["r4_idle", "r4_light_combo", "r4_heavy_cut"]

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var tpl: Animation = load(TEMPLATE)
	print("template sections meta: ", tpl.get_meta("sections") if tpl.has_meta("sections") else "none")
	var report := {}
	for clip in CLIPS:
		var f := FileAccess.open(SRC_DIR + str(clip) + ".json", FileAccess.READ)
		if f == null:
			push_error("missing " + clip)
			continue
		var d: Dictionary = JSON.parse_string(f.get_as_text())
		f.close()
		var fps: float = float(d.fps)
		var hips: Array = d.hips_pos
		var n := hips.size()
		var a := Animation.new()
		a.length = (float(n) / fps) if d.loop else (float(n - 1) / fps)
		a.step = 1.0 / fps
		a.loop_mode = Animation.LOOP_LINEAR if d.loop else Animation.LOOP_NONE
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
		for k in meta:
			if k == "sections":
				a.set_meta("sections", PackedFloat32Array(meta[k]))
			else:
				a.set_meta(k, meta[k])
		a.set_meta("r4_source", "work/yoriichi_r4 Blender R4 candidate (" + clip + ")")
		var out: String = OUT_DIR + str(clip) + ".res"
		var err: int = ResourceSaver.save(a, out)
		report[clip] = {"len": a.length, "tracks": made, "missing": missing, "err": err}
		print("R4_BUILT ", clip, " len=", a.length, " tracks=", made, " missing=", missing, " err=", err)
	quit()

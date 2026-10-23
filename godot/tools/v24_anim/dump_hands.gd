extends "res://tools/v24_anim/fit_v24_sockets.gd"
## 傾印持刀相關骨頭位置（Player 空間）到 user://v24_hands/<clip>.json，供 Python 擬合握把軸、雙手距離、刀身淨空。
## 用法：godot --headless --path . -s tools/v24_anim/dump_hands.gd -- clip1,clip2   （clip = v24/anims/<clip>.res）
const BONES := ["mixamorig_Hips", "mixamorig_Spine2", "mixamorig_Neck", "mixamorig_Head",
	"mixamorig_RightArm", "mixamorig_RightForeArm", "mixamorig_RightHand", "mixamorig_LeftArm", "mixamorig_LeftForeArm", "mixamorig_LeftHand",
	"mixamorig_RightHandThumb1", "mixamorig_RightHandThumb2", "mixamorig_RightHandThumb3",
	"mixamorig_RightHandIndex1", "mixamorig_RightHandIndex2", "mixamorig_RightHandIndex3",
	"mixamorig_RightHandMiddle1", "mixamorig_RightHandMiddle2", "mixamorig_RightHandMiddle3",
	"mixamorig_RightHandRing1", "mixamorig_RightHandRing2", "mixamorig_RightHandRing3",
	"mixamorig_RightHandPinky1", "mixamorig_RightHandPinky2", "mixamorig_RightHandPinky3",
	"mixamorig_LeftHandThumb1", "mixamorig_LeftHandThumb2", "mixamorig_LeftHandThumb3",
	"mixamorig_LeftHandIndex1", "mixamorig_LeftHandIndex2", "mixamorig_LeftHandIndex3",
	"mixamorig_LeftHandMiddle1", "mixamorig_LeftHandMiddle2", "mixamorig_LeftHandMiddle3",
	"mixamorig_LeftHandRing1", "mixamorig_LeftHandRing2", "mixamorig_LeftHandRing3",
	"mixamorig_LeftHandPinky1", "mixamorig_LeftHandPinky2", "mixamorig_LeftHandPinky3",
	"mixamorig_LeftUpLeg", "mixamorig_RightUpLeg", "mixamorig_LeftLeg", "mixamorig_RightLeg"]

func _process(_d: float) -> bool:
	_n += 1
	if _n < 5:
		return false
	(_p._tree as AnimationTree).active = false
	var sk := _skel()
	var ap: AnimationPlayer = _p._anim
	var lib := ap.get_animation_library(ap.get_animation_library_list()[0])
	var out_dir := "user://v24_hands/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var args := OS.get_cmdline_user_args()
	var inv := _p.global_transform.affine_inverse()
	for k in (args[0] if args.size() > 0 else "gs_idle").split(","):
		var a: Animation = load("res://characters/yoriichi/v24/anims/%s.res" % k)
		lib.add_animation("D_" + k, a)
		var frames := []
		var nf := int(round(a.length * 30.0))
		for fi in nf + 1:
			var g := _pose_at("D_" + k, minf(fi / 30.0, a.length))
			var row := {}
			for b in BONES:
				var t := inv * _w(sk, g, b)
				row[b] = [t.origin.x, t.origin.y, t.origin.z]
				if b == "mixamorig_RightHand" or b == "mixamorig_LeftHand":
					row[b + "_basis"] = [t.basis.x.x, t.basis.x.y, t.basis.x.z, t.basis.y.x, t.basis.y.y, t.basis.y.z, t.basis.z.x, t.basis.z.y, t.basis.z.z]
			frames.append(row)
		var f := FileAccess.open(out_dir + k + ".json", FileAccess.WRITE)
		f.store_string(JSON.stringify({"len": a.length, "frames": frames}))
		f.close()
		print("DUMPED ", k, " frames=", frames.size())
	return true

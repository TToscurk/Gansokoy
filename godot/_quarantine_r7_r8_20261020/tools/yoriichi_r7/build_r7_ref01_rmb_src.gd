extends "res://tools/yoriichi_r7/build_r7_ref09_mx_src.gd"
## R7 P5 REF01 右鍵分支素材（Sword And Shield High Attack）：沿用 REF09 MX 同一套重定向＋水平軌跡補回，只換來源／輸出資料夾。
##   godot --headless --path godot -s res://tools/yoriichi_r7/build_r7_ref01_rmb_src.gd -- r01_ss_high_atk
const R01_DIR := "res://characters/yoriichi/v24_r7/ref01_rmb_mx/"

func _src_path(key: String) -> String:
	return R01_DIR + key.trim_prefix("r01_") + ".fbx"

func _process(_d: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false
	_tsk = _tgt.find_child("Skeleton3D", true, false)
	for i in _tsk.get_bone_count():
		var p := _tsk.get_bone_parent(i)
		_t_rest_g[i] = (_t_rest_g[p] as Transform3D) * _tsk.get_bone_rest(i) if p >= 0 else _tsk.get_bone_rest(i)
		if _tsk.get_bone_name(i).begins_with("mixamorig_"):
			_t_body.append(i)
	_measure_target_idle()
	var args := OS.get_cmdline_user_args()
	for k in Array(args[0].split(",")):
		var a := build_clip(k)
		if a == null:
			continue
		_add_horizontal(k, a)
		print("R01_BUILT ", k, " len=", snappedf(a.length, 0.001), " err=", ResourceSaver.save(a, R01_DIR + k + ".res"))
	quit()
	return true

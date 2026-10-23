extends "res://tools/yoriichi_r7/build_r7_ref09_mx_src.gd"
## R7 P5 普通跳躍素材（Sword And Shield Running Jump）：沿用 REF09 MX 同一套重定向，只換來源／輸出資料夾。
##   godot --headless --path godot -s res://tools/yoriichi_r7/build_r7_jump_mx_src.gd -- jmx_ss_running_jump[,...] [nohoriz]
## 有水平軌跡版只供離線預覽；遊戲用三段由 split_r7_jump_mx.gd 從 nohoriz 版切出。
const JMX_DIR := "res://characters/yoriichi/v24_r7/jump_mx/"

func _src_path(key: String) -> String:
	return JMX_DIR + key.trim_prefix("jmx_").trim_suffix("_full") + ".fbx"

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
		if (k as String).ends_with("_full"):
			_add_horizontal(k, a)
		print("JMX_BUILT ", k, " len=", snappedf(a.length, 0.001), " err=", ResourceSaver.save(a, JMX_DIR + k + ".res"))
	quit()
	return true

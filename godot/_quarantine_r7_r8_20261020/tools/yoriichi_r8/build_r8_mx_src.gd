extends "res://tools/yoriichi_r7/build_r7_ref09_mx_src.gd"
## R8 P1 素材預覽：沿用 R7 REF09 MX 同一套重定向（世界旋轉差量、rest 髖高比例、貼地、水平軌跡補回），不改共用工具。
## key 前綴 r8_ → 先找 R8 素材資料夾，再找共用 v24/mixamo/。輸出只寫 res://characters/yoriichi/v24_r8/mx_src/。
##   godot --headless --path godot -s res://tools/yoriichi_r8/build_r8_mx_src.gd -- r8_th_combo,r8_gs_combo_slash
const R8_DIR := "res://characters/yoriichi/v24_r8/mx_src/"

func _src_path(key: String) -> String:
	var name := key.trim_prefix("r8_")
	return R8_DIR + name + ".fbx" if ResourceLoader.exists(R8_DIR + name + ".fbx") else SRC_DIR + name + ".fbx"

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
		print("R8_BUILT ", k, " len=", snappedf(a.length, 0.001), " err=", ResourceSaver.save(a, R8_DIR + k + ".res"))
	quit()
	return true

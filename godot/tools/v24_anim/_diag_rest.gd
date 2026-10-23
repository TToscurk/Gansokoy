extends "res://tools/v24_anim/build_v24_anims.gd"
## 診斷：來源 FBX rest 與目標 GLB rest 的骨段方向差；以及 walk 逐骨平均誤差。
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
	var L := _load_src("_calib_walk")
	var sk: Skeleton3D = L[1]
	var ws: Transform3D = L[3]
	print("ws ", ws)
	var srg := {}
	for i in sk.get_bone_count():
		var p := sk.get_bone_parent(i)
		srg[i] = (srg[p] as Transform3D) * sk.get_bone_rest(i) if p >= 0 else sk.get_bone_rest(i)
	var out := []
	for ti in _t_body:
		var n := _tsk.get_bone_name(ti)
		var si := sk.find_bone(n)
		var tp := _tsk.get_bone_parent(ti)
		if tp < 0: continue
		var sp := sk.get_bone_parent(si)
		var td := ((_t_rest_g[ti] as Transform3D).origin - (_t_rest_g[tp] as Transform3D).origin)
		var sd := (ws * (srg[si] as Transform3D).origin) - (ws * (srg[sp] as Transform3D).origin)
		if td.length() < 0.001 or sd.length() < 0.001: continue
		out.append([rad_to_deg(td.angle_to(sd)), n, td.length(), sd.length()])
	out.sort_custom(func(a, b): return a[0] > b[0])
	for o in out.slice(0, 14):
		print("REST seg diff %.1f deg %s  tlen %.3f slen %.3f" % o)
	quit()
	return true

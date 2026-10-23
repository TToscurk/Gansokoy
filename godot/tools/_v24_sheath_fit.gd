extends SceneTree
## 一次性：把 v2.4 的刀鞘＋鞘中刀（剛體一組）繞鞘口轉到「插在腰帶左側、鞘尾朝後下」的佩刀角度。
## headless 可跑（只讀靜態網格 AABB 與骨骼 pose，不涉及 MultiMesh）。
## 用法：godot --headless --path . -s tools/_v24_sheath_fit.gd -- [dx dy dz]（鞘尾方向，Player 空間，面向 -Z）

var _p: Node3D
var _n := 0
var _dir := Vector3(-0.35, -0.45, 0.82)
var _mouth_target := Vector3.INF

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() >= 3:
		_dir = Vector3(float(a[0]), float(a[1]), float(a[2]))
	if a.size() >= 6:
		_mouth_target = Vector3(float(a[3]), float(a[4]), float(a[5]))
	_dir = _dir.normalized()
	_p = (load("res://characters/yoriichi/player_yoriichi.tscn") as PackedScene).instantiate()
	root.add_child(_p)

func _rel(n: Node3D) -> Transform3D:
	return _p.global_transform.affine_inverse() * n.global_transform

## 節點底下所有 MeshInstance3D 合併 AABB（節點本地座標）。
func _local_aabb(n: Node3D) -> AABB:
	var inv := n.global_transform.affine_inverse()
	var out := AABB()
	var first := true
	for m: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		var bb := m.get_aabb()
		for i in 8:
			var p := inv * (m.global_transform * bb.get_endpoint(i))
			if first:
				out = AABB(p, Vector3.ZERO)
				first = false
			else:
				out = out.expand(p)
	return out

func _ends(n: Node3D) -> Array:
	var bb := _local_aabb(n)
	var ax := bb.get_longest_axis_index()
	var c := bb.get_center()
	var e0 := c
	var e1 := c
	e0[ax] = bb.position[ax]
	e1[ax] = bb.end[ax]
	var t := _rel(n)
	return [t * e0, t * e1, bb.size[ax], ax]

func _process(_d: float) -> bool:
	_n += 1
	if _n < 30:
		return false
	var sheath: Node3D = _p.find_child("Sheath", true, false)
	var sword: Node3D = _p.find_child("Sword_Sheathed", true, false)
	var se := _ends(sheath)
	var we := _ends(sword)
	var sc: Vector3 = (se[0] + se[1]) * 0.5
	# 刀柄端 = 刀兩端中離鞘中心較遠者；鞘口 = 鞘兩端中離刀柄較近者。
	var hilt: Vector3 = we[0] if we[0].distance_to(sc) > we[1].distance_to(sc) else we[1]
	var mouth: Vector3 = se[0] if se[0].distance_to(hilt) < se[1].distance_to(hilt) else se[1]
	var tip: Vector3 = se[1] if mouth == se[0] else se[0]
	var d := (tip - mouth).normalized()
	print("WORLD sheath ", se[0], "->", se[1], " len ", se[0].distance_to(se[1]), " | sword ", we[0], "->", we[1], " len ", we[0].distance_to(we[1]))
	print("sheath len ", se[2], " sword len ", we[2], " mouth ", mouth, " tip ", tip, " hilt ", hilt, " cur dir ", d)
	var r := Basis(Quaternion(d, _dir))
	# 刃向：刀本地 −X（README 實測）。轉完後把刃向投影到垂直鞘軸的平面，滾轉到最接近 +Y（刃朝上）。
	var edge := (_rel(sword).basis * Vector3(-1, 0, 0)).normalized()
	edge = r * edge
	var e_perp := (edge - _dir * edge.dot(_dir)).normalized()
	var up_perp := (Vector3.UP - _dir * Vector3.UP.dot(_dir)).normalized()
	var roll := e_perp.signed_angle_to(up_perp, _dir)
	var rot := Basis(_dir, roll) * r
	var dest := mouth if _mouth_target == Vector3.INF else _mouth_target
	var xf := Transform3D(Basis(), dest) * Transform3D(rot, Vector3.ZERO) * Transform3D(Basis(), -mouth)
	var sk: Skeleton3D = _p.find_children("*", "Skeleton3D", true, false)[0]
	var hips := _p.global_transform.affine_inverse() * sk.global_transform * sk.get_bone_global_pose(sk.find_bone("mixamorig_Hips"))
	var s_new := hips.affine_inverse() * (xf * _rel(sheath))
	var w_new := hips.affine_inverse() * (xf * _rel(sword))
	print("roll deg ", rad_to_deg(roll), " new mouth ", dest, " new hilt ", xf * hilt, " new tip ", dest + _dir * mouth.distance_to(tip))
	print("SHEATH ", var_to_str(s_new))
	print("SWORD ", var_to_str(w_new))
	return true

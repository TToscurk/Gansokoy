class_name IsshinFootLock
extends SkeletonModifier3D
## 局部腳掌鎖定 IK（候選專用）：只在「起步／停步／反向／待機」使用，支撐腳落地後把腳踝釘在世界座標上，
## 用解析式二骨 IK（UpLeg→Leg→Foot）把腳拉回去，腳掌方向維持動畫原樣。
## 不用於騰空閃避與轉身（combat_locomotion 在這兩個階段把 enabled 關掉並 clear()），
## 也不改任何動畫資源；放在 Skeleton3D 的 HipTwist 之後、SpringBone 之前。
##
## 抓取：腳踝動畫高度 < 待機高度 + ACQUIRE_H（腳掌貼地）→ 釘在當下世界座標。
## 釋放：腳踝動畫高度 > 待機高度 + RELEASE_H（要抬腳了）→ 權重在 RELEASE_T 內降到 0。
const ACQUIRE_H := 0.03
const RELEASE_H := 0.05
const RAMP_IN := 0.05
const RELEASE_T := 0.12
const SWING_SPEED := 0.7         # 動畫腳踝水平世界速度超過此值＝正在滑步／邁步（一心的邁步腳是貼地滑過去的，不能只看高度）
const ERR_MAX := 0.30            # 安全閥：離鎖定點超過 30 cm 一定是出狀況才放掉（太早放會在腳還貼地時一口氣補幾十公分）
const MAX_REACH := 0.985        # 腿伸直比例上限（避免鎖死膝蓋）
const IDLE_ANKLE := {"Left": 0.153, "Right": 0.167}   # 待機站姿的腳踝高度（Godot 量測值）

var enabled := false
## 哪隻腳允許被鎖：起步只鎖「該相位的支撐腳」，邁步腳不鎖（一心的邁步腳是貼地滑出去的，鎖了會在放開時一口氣補 20 cm）。
var allow := {"Left": true, "Right": true}
var dt := 1.0 / 60.0
var _ix := {}
var _prev := {}                  # 每腳上一幀『動畫』腳踝世界座標（IK 之前）
var _lock := {}                  # "Left"/"Right" -> {pos: Vector3(world), w: float, releasing: bool}
var last_info := {}              # 除錯用：每腳的鎖定狀態／誤差

func clear() -> void:
	_lock.clear()

## 全部放掉：用 over 秒把權重降到 0（不是硬切）。
func release_all(over: float) -> void:
	for k in _lock.keys():
		var st: Dictionary = _lock[k]
		if float(st.get("err", 0.0)) < 0.04:
			_lock.erase(k)            # 鎖定點和動畫腳差不到 4 cm：直接放，不會跳（閃避起手要乾淨，不能被拖住）
		else:
			st["releasing"] = true
			st["rel_t"] = over

func _b(n: String) -> int:
	if not _ix.has(n):
		_ix[n] = get_skeleton().find_bone(n)
	return _ix[n]

func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	var inv := sk.global_transform.affine_inverse()
	last_info = {}
	for side in ["Left", "Right"]:
		var foot := _b("mixamorig_%sFoot" % side)
		var a_g := sk.get_bone_global_pose(foot)
		var h: float = a_g.origin.y - float(IDLE_ANKLE[side])
		var wpos: Vector3 = sk.global_transform * a_g.origin
		var spd := 0.0
		if _prev.has(side):
			var dv: Vector3 = wpos - (_prev[side] as Vector3)
			dv.y = 0.0
			spd = dv.length() / dt
		_prev[side] = wpos
		var st: Dictionary = _lock.get(side, {})
		last_info[side] = {"w": -1.0, "err_cm": 0.0, "h_cm": h * 100.0, "spd": spd}
		if st.is_empty():
			if enabled and allow.get(side, true) and h < ACQUIRE_H and spd < SWING_SPEED:
				st = {"pos": sk.global_transform * a_g.origin, "w": 0.0, "releasing": false}
				_lock[side] = st
			else:
				continue
		var err0 := (inv * (st["pos"] as Vector3) - a_g.origin).length()
		if h > RELEASE_H or spd > SWING_SPEED or err0 > ERR_MAX or not allow.get(side, true):
			st["releasing"] = true
		var rate := dt / (float(st.get("rel_t", RELEASE_T)) if st["releasing"] else RAMP_IN)
		st["w"] = move_toward(float(st["w"]), 0.0 if st["releasing"] else 1.0, rate)
		if st["releasing"] and float(st["w"]) <= 0.0:
			_lock.erase(side)
			continue
		var target_anim := a_g.origin
		var target := target_anim.lerp(inv * (st["pos"] as Vector3), float(st["w"]))
		var err := (inv * (st["pos"] as Vector3) - target_anim).length()
		st["err"] = err
		last_info[side] = {"w": st["w"], "err_cm": err * 100.0, "h_cm": h * 100.0, "spd": spd}
		_solve(sk, side, target)

func _solve(sk: Skeleton3D, side: String, target: Vector3) -> void:
	var up := _b("mixamorig_%sUpLeg" % side)
	var kn := _b("mixamorig_%sLeg" % side)
	var ft := _b("mixamorig_%sFoot" % side)
	var gu := sk.get_bone_global_pose(up)
	var gk := sk.get_bone_global_pose(kn)
	var gf := sk.get_bone_global_pose(ft)
	var hip := gu.origin
	var l1 := (gk.origin - hip).length()
	var l2 := (gf.origin - gk.origin).length()
	var to_t := target - hip
	var d := clampf(to_t.length(), absf(l1 - l2) + 0.01, (l1 + l2) * MAX_REACH)
	var u := to_t.normalized()
	var a := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var hgt := sqrt(maxf(l1 * l1 - a * a, 0.0))
	var pole := (gk.origin - hip)
	pole = pole - u * pole.dot(u)
	if pole.length() < 1e-4:
		pole = Vector3.FORWARD
	pole = pole.normalized()
	var knee_new := hip + u * a + pole * hgt
	var v1_old := gk.origin - hip
	var v1_new := knee_new - hip
	var q1 := _from_to(v1_old, v1_new)
	var nb_u := Basis(q1) * gu.basis
	sk.set_bone_global_pose(up, Transform3D(nb_u, hip))
	# 膝：原本膝→踝向量被 q1 轉過去後，再轉到 膝→目標
	var v2_old := Basis(q1) * (gf.origin - gk.origin)
	var ankle_goal := hip + u * d
	var q2 := _from_to(v2_old, ankle_goal - knee_new)
	var nb_k := Basis(q2) * Basis(q1) * gk.basis
	sk.set_bone_global_pose(kn, Transform3D(nb_k, knee_new))
	sk.set_bone_global_pose(ft, Transform3D(gf.basis, ankle_goal))

func _from_to(a: Vector3, b: Vector3) -> Quaternion:
	var an := a.normalized()
	var bn := b.normalized()
	var dot := clampf(an.dot(bn), -1.0, 1.0)
	if dot > 0.99999:
		return Quaternion.IDENTITY
	var axis := an.cross(bn)
	if axis.length() < 1e-6:
		axis = an.cross(Vector3.RIGHT)
		if axis.length() < 1e-6:
			axis = an.cross(Vector3.UP)
	return Quaternion(axis.normalized(), acos(dot))

extends "res://characters/yoriichi/vfx/sword_trail.gd"
## R9 日之呼吸刀光（候選；沿用正式 SwordTrail3D 的雙層 ribbon、兩支火焰著色器與色階，正式檔不改）。
## 只換「取樣」與「時鐘」：
##   * 由外部在骨架更新後呼叫 feed(刀的 global_transform, dt)，用的是這一幀畫面上的刀（不落後一幀、不和刀身分離）。
##   * 上一幀→這一幀之間用刀的整個變換插值（護手位置線性、旋轉 slerp）補樣本：刀每轉 max_step_deg 度或刀尖每走 max_step_len
##     公尺補一個，快速轉向時 ribbon 沿真正的弧走，不會拉出一條弦（巨大三角形）或斷開。
##   * 年齡用動畫時鐘：clock_scale＝0（Hit Stop 停格）時尾巴不老化、不斷裂，停格結束接著燒完。
##   * 刀沒動（停格、殘心）時不補樣本，避免重疊的退化三角形。
var guard_local := Vector3(0, 0.0, 0)
var tip_local := Vector3(0, 1.085, 0)
var clock_scale := 1.0
var max_step_deg := 4.0
var max_step_len := 0.06
var samples_added := 0
## 刀光最新的 head_fade 秒（動畫時鐘）由透明淡入：刀身本體在刀光前緣保持看得見（不被白熱核心洗掉）；停格時年齡不前進，
## 所以命中停格那幾格刀與目標的接觸點上方沒有不透明的火。0＝關（＝正式刀光的行為）。
var head_fade := 0.0
var _prev_xf := Transform3D()
var _have_prev := false

func _ready() -> void:
	super._ready()
	min_distance = 0.0
	smooth_subdiv = 1

func start_trail() -> void:
	is_emitting = true
	_travel = 0.0
	_runs.append([])
	_have_prev = false

func _process(_delta: float) -> void:
	_push_params()

func _sample(xf: Transform3D, age: float) -> Dictionary:
	return {"tip": xf * tip_local, "base": xf * guard_local, "age": age, "life": maxf(lifetime, 0.0001),
		"extend": flame_extend, "inset": flame_inset, "travel": _travel}

func feed(cur: Transform3D, dt: float) -> void:
	var adt := dt * clock_scale
	var r := 0
	while r < _runs.size():
		var run: Array = _runs[r]
		var i := 0
		while i < run.size():
			run[i]["age"] = float(run[i]["age"]) + adt
			if float(run[i]["age"]) >= float(run[i]["life"]):
				run.remove_at(i)
			else:
				i += 1
		if run.is_empty() and not (is_emitting and r == _runs.size() - 1):
			_runs.remove_at(r)
		else:
			r += 1
	if is_emitting and not _runs.is_empty():
		var run: Array = _runs.back()
		if not _have_prev or run.is_empty():
			run.append(_sample(cur, 0.0))
			samples_added += 1
		else:
			var ang := rad_to_deg(_prev_xf.basis.get_rotation_quaternion().angle_to(cur.basis.get_rotation_quaternion()))
			var tip_d := (_prev_xf * tip_local).distance_to(cur * tip_local)
			if ang > 0.3 or tip_d > 0.004:
				var n := clampi(int(ceil(maxf(ang / max_step_deg, tip_d / max_step_len))), 1, 24)
				for k in range(1, n + 1):
					var w := float(k) / float(n)
					var xf := _prev_xf.interpolate_with(cur, w)
					var last_tip: Vector3 = run.back()["tip"]
					_travel += last_tip.distance_to(xf * tip_local)
					run.append(_sample(xf, (1.0 - w) * adt))
					samples_added += 1
	_prev_xf = cur
	_have_prev = true
	_rebuild()

## 正式 SwordTrail3D._build_run 的同一套幾何與色彩，只多乘 head_fade 淡入（正式檔不改）
func _build_run(run: Array) -> void:
	var n := run.size()
	var steps: int = maxi(smooth_subdiv, 0) + 1
	var pts: Array[Dictionary] = []
	for idx in range(n - 1):
		for s_ in range(steps):
			var t := float(s_) / float(steps)
			var base_p := _catmull(_sample_at(run, idx - 1, "base"), _sample_at(run, idx, "base"), _sample_at(run, idx + 1, "base"), _sample_at(run, idx + 2, "base"), t)
			var tip_p := _catmull(_sample_at(run, idx - 1, "tip"), _sample_at(run, idx, "tip"), _sample_at(run, idx + 1, "tip"), _sample_at(run, idx + 2, "tip"), t)
			var s0: Dictionary = run[idx]
			var s1: Dictionary = run[idx + 1]
			pts.append({"base": base_p, "tip": tip_p, "age": lerpf(float(s0.age), float(s1.age), t), "life": lerpf(float(s0.life), float(s1.life), t),
				"extend": lerpf(float(s0.extend), float(s1.extend), t), "inset": lerpf(float(s0.inset), float(s1.inset), t), "travel": lerpf(float(s0.travel), float(s1.travel), t)})
	pts.append((run[n - 1] as Dictionary).duplicate())
	if pts.size() < 2:
		return
	_flame_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _flame_mat)
	for p in pts:
		var base_p: Vector3 = p.base
		var tip_p: Vector3 = p.tip
		var dir := tip_p - base_p
		if dir.length_squared() < 0.000001:
			dir = Vector3.UP
		dir = dir.normalized()
		var t: float = clampf(p.age / maxf(float(p.life), 0.0001), 0.0, 1.0)
		var inner := base_p - dir * float(p.inset)
		var outer := tip_p + dir * float(p.extend) + Vector3.UP * flame_lift * t
		var alpha: float = (1.0 - smoothstep(fade_hold, 1.0, t)) * (smoothstep(0.0, head_fade, float(p.age)) if head_fade > 0.0 else 1.0)
		var c := Color(1, 1, 1, alpha)
		_flame_mesh.surface_set_color(c)
		_flame_mesh.surface_set_uv(Vector2(p.travel, 0.0))
		_flame_mesh.surface_add_vertex(inner)
		_flame_mesh.surface_set_color(c)
		_flame_mesh.surface_set_uv(Vector2(p.travel, 1.0))
		_flame_mesh.surface_add_vertex(outer)
	_flame_mesh.surface_end()
	var core_pts: Array[Dictionary] = []
	for p in pts:
		if p.age <= float(p.life) * core_lifetime_ratio:
			core_pts.append(p)
	if core_pts.size() < 2:
		return
	_core_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _core_mat)
	for p in core_pts:
		var core_life: float = maxf(float(p.life) * core_lifetime_ratio, 0.0001)
		var t: float = clampf(p.age / core_life, 0.0, 1.0)
		var alpha: float = (1.0 - t) * (1.0 - t) * (smoothstep(0.0, head_fade, float(p.age)) if head_fade > 0.0 else 1.0)
		var c := Color(1, 1, 1, alpha)
		var cdir: Vector3 = p.tip - p.base
		var cbase: Vector3 = p.base + cdir * core_root_skip
		_core_mesh.surface_set_color(c)
		_core_mesh.surface_set_uv(Vector2(p.travel, 0.0))
		_core_mesh.surface_add_vertex(cbase)
		_core_mesh.surface_set_color(c)
		_core_mesh.surface_set_uv(Vector2(p.travel, 1.0))
		_core_mesh.surface_add_vertex(p.tip)
	_core_mesh.surface_end()

## 量測用：目前 ribbon 的取樣點總數
func sample_count() -> int:
	var n := 0
	for run in _runs:
		n += (run as Array).size()
	return n

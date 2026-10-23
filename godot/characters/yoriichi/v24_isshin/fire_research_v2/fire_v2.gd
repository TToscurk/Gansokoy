extends Node3D
## FIRE_RESEARCH_V2：日之呼吸・圓舞的火焰候選（ART_REVIEW）。只做 VFX；動作、判定、Hit Stop、戰鬥控制器全部沿用 R9。
## 五層（全部由「這一幀畫面上的刀」的實際變換與技能時間驅動）：
##   1. 斬擊核心 core：刀身外段、壽命 0.13 s 的白金刀線 → 刀路可讀性。
##   2. 斬擊火幕 sheet：世界座標 ribbon，壽命 0.42 s，噪聲侵蝕把火幕撕成往後、往上竄的火舌 → 主要火體。
##   3. 火舌 tongues：依刀尖走過的距離發射（不是每秒固定數量），每顆是程序化火焰（生→長→撕裂→冷卻透明）→ 體積與殘焰。
##      刀身火 blade＋刀身小火：起手點燃到收勢熄滅，貼著刀。
##   4. 細節：火星（加法、沿速度拉長、數量少）。
##   5. 命中：沿斬擊方向的高溫裂口＋定向爆燃火舌＋火星。
## Hit Stop：所有火焰的時鐘（shader fx_time、粒子 time_scale、ribbon 年齡）一起停，放開後接著燒。
## 介面同 R9 的 sun_vfx.gd：setup(sword, cam)；begin(profile)；end()；frame(sword_xf, skill_t, dt, freeze, tip_speed)；hit(pos, dir, normal)；stats()
const NOISE := preload("res://characters/yoriichi/v24_isshin/fire_research_v2/fire_noise_v2.png")
const SH_TONGUE := preload("res://characters/yoriichi/v24_isshin/fire_research_v2/fire_v2_tongue.gdshader")
const SH_SPARK := preload("res://characters/yoriichi/v24_isshin/fire_research_v2/fire_v2_spark.gdshader")
const SH_PROC := preload("res://characters/yoriichi/v24_isshin/fire_research_v2/fire_v2_process.gdshader")
const SH_SHEET := preload("res://characters/yoriichi/v24_isshin/fire_research_v2/fire_v2_sheet.gdshader")
const SH_CORE := preload("res://characters/yoriichi/v24_isshin/fire_research_v2/fire_v2_core.gdshader")
const SH_BLADE := preload("res://characters/yoriichi/v24_isshin/fire_research_v2/fire_v2_blade.gdshader")
const SH_FLASH := preload("res://characters/yoriichi/v24_isshin/fire_research_v2/fire_v2_flash.gdshader")
const FLAGS := GPUParticles3D.EMIT_FLAG_POSITION | GPUParticles3D.EMIT_FLAG_ROTATION_SCALE | GPUParticles3D.EMIT_FLAG_VELOCITY | GPUParticles3D.EMIT_FLAG_COLOR | GPUParticles3D.EMIT_FLAG_CUSTOM
const TIP := 1.085

## 可調參數（試玩後調整用）
var P := {
	"slash_window": [0.44, 0.72],     # 技能時間：刀光／火幕／刀路火舌的產生窗（圓舞主斬 0.48–0.68）
	"speed_lo": 3.0, "speed_hi": 16.0, # 刀尖速度 → 出刀強度 0..1（火隨刀加速展開）
	"sheet_life": 0.32, "sheet_u0": 0.40, "sheet_ext": 0.12, "sheet_lift": 0.20,
	"core_life": 0.12, "core_u0": 0.70,
	"tongue_spacing_far": 0.32, "tongue_spacing_near": 0.16, "tongue_cap": 36,
	"tongue_w": [0.22, 0.34], "tongue_h": [0.34, 0.56], "tongue_life": [0.34, 0.55],
	"aura_rate": 40.0, "aura_max_speed": 12.0,
	"spark_spacing": 0.11, "spark_cap": 60,
	"blade_height": 0.20,
	# 刀身火包絡（技能秒, 0..1）：蓄勢點燃 → 主斬全亮 → 隨揮時就退，不拖到收勢
	"blade_env": [[0.05, 0.0], [0.30, 1.0], [0.70, 1.0], [1.00, 0.0]],
	"hit_tongues": 7, "hit_sparks": 22, "hit_flash_len": 0.55, "hit_flash_w": 0.14, "hit_flash_life": 0.16,
}

var sword: Node3D
var cam: Camera3D
var profile := {}
var enabled := true
var active := false
var skill_t := 0.0
var fx_time := 0.0
var blade_level := 0.0
var rng := RandomNumberGenerator.new()

var flames: GPUParticles3D
var sparks: GPUParticles3D
var proc_mat: ShaderMaterial
var tongue_mat: ShaderMaterial
var spark_mat: ShaderMaterial
var sheet_mat: ShaderMaterial
var core_mat: ShaderMaterial
var blade_mat: ShaderMaterial
var _sheet_mesh := ImmediateMesh.new()
var _core_mesh := ImmediateMesh.new()
var _blade_mesh := ImmediateMesh.new()
var _flash_pool: Array = []
var _flashes: Array = []
var _flash_ix := 0

var _runs: Array = []          # 每段刀光：取樣陣列 {xf, age, trav, lvl}
var _emitting := false
var _prev := Transform3D()
var _have_prev := false
var _travel := 0.0
var _seed := 0.0
var _tongue_debt := 0.0
var _spark_debt := 0.0
var _aura_debt := 0.0
var _slash_tongues := 0
var _slash_sparks := 0

var n_emit := {"tongue": 0, "aura": 0, "hit": 0, "spark": 0}
var hits_spawned := 0
var frozen_frames := 0
var ribbon_samples := 0
var _prewarm := 4                # 開場前幾幀：在相機前畫一次全部材質（完全透明），先把著色器編好

func setup(sword_: Node3D, cam_: Camera3D) -> void:
	sword = sword_
	cam = cam_
	top_level = true
	global_transform = Transform3D.IDENTITY
	rng.seed = 31415
	proc_mat = ShaderMaterial.new()
	proc_mat.shader = SH_PROC
	proc_mat.set_shader_parameter("time_scale", 1.0)
	tongue_mat = _mat(SH_TONGUE)
	spark_mat = _mat(SH_SPARK)
	sheet_mat = _mat(SH_SHEET)
	core_mat = _mat(SH_CORE)
	blade_mat = _mat(SH_BLADE)
	# 繪製順序：火幕在下、火舌、刀身火、核心刀線在最上（仍做深度測試，不會穿透角色）
	sheet_mat.render_priority = 0
	tongue_mat.render_priority = 1
	blade_mat.render_priority = 2
	spark_mat.render_priority = 2
	core_mat.render_priority = 3
	flames = _mk_particles("Flames", 192, 1.0, tongue_mat, 1.0)
	sparks = _mk_particles("Sparks", 160, 1.0, spark_mat, 1.0)
	_mk_mi("FireSheet", _sheet_mesh, sheet_mat)
	_mk_mi("SlashCore", _core_mesh, core_mat)
	_mk_mi("BladeFire", _blade_mesh, blade_mat)
	var q := QuadMesh.new()
	for i in 3:
		var mi := MeshInstance3D.new()
		mi.name = "HitCore%d" % i
		mi.mesh = q
		var m := _mat(SH_FLASH)
		m.render_priority = 4
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_flash_pool.append(mi)

func _mat(sh: Shader) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = sh
	if sh != SH_SPARK:
		m.set_shader_parameter("noise_tex", NOISE)
	return m

func _mk_particles(n: String, amount: int, life: float, draw: ShaderMaterial, quad: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = n
	p.amount = amount
	p.lifetime = life
	p.local_coords = false
	p.emitting = false
	p.one_shot = false
	p.fixed_fps = 0
	p.interpolate = false
	p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	p.visibility_aabb = AABB(Vector3(-6, -3, -6), Vector3(12, 9, 12))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.process_material = proc_mat
	var qm := QuadMesh.new()
	qm.size = Vector2(quad, quad)
	qm.material = draw
	p.draw_pass_1 = qm
	add_child(p)
	return p

func _mk_mi(n: String, m: ImmediateMesh, mat: ShaderMaterial) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = m
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 4.0
	add_child(mi)
	return mi

## 開始一招（profile＝sun_breathing.json 的 vfx 欄；這裡只用 blade.env 的點燃包絡）
func begin(prof: Dictionary) -> void:
	profile = prof
	active = true
	skill_t = 0.0
	_tongue_debt = 0.0
	_spark_debt = 0.0
	_aura_debt = 0.0
	_slash_tongues = 0
	_slash_sparks = 0

func end() -> void:
	active = false

## 切版本時：全部清掉
func clear() -> void:
	active = false
	_emitting = false
	_runs.clear()
	blade_level = 0.0
	flames.restart()
	flames.emitting = false
	sparks.restart()
	sparks.emitting = false
	_sheet_mesh.clear_surfaces()
	_core_mesh.clear_surfaces()
	_blade_mesh.clear_surfaces()
	for f in _flashes:
		(f["mi"] as MeshInstance3D).visible = false
	_flashes.clear()

static func _env(pts: Array, t: float) -> float:
	if pts.is_empty():
		return 0.0
	if t <= float(pts[0][0]):
		return float(pts[0][1])
	for i in range(1, pts.size()):
		if t <= float(pts[i][0]):
			var a: Array = pts[i - 1]
			var b: Array = pts[i]
			var k := (t - float(a[0])) / maxf(float(b[0]) - float(a[0]), 1e-4)
			return lerpf(float(a[1]), float(b[1]), smoothstep(0.0, 1.0, k))
	return float(pts[pts.size() - 1][1])

## 每幀（骨架更新後）：刀的變換、技能時間、真實 dt、是否停格、刀尖速度（m/s）
func frame(xf: Transform3D, t: float, dt: float, freeze: bool, tip_speed: float) -> void:
	if _prewarm > 0:
		_do_prewarm()
		_prev = xf
		_have_prev = true
		return
	var clock := 0.0 if freeze else 1.0
	var adt := dt * clock
	if freeze:
		frozen_frames += 1
	fx_time += adt
	for m: ShaderMaterial in [tongue_mat, sheet_mat, core_mat, blade_mat]:
		m.set_shader_parameter("fx_time", fx_time)
	proc_mat.set_shader_parameter("time_scale", clock)
	skill_t = t
	var on := enabled and active
	flames.visible = enabled
	sparks.visible = enabled
	# 粒子節點跟著刀走（只移動剔除用的 AABB；粒子在世界座標，不會被拖動）
	flames.global_position = xf.origin
	sparks.global_position = xf.origin
	# 刀身火（點燃包絡＝P.blade_env）
	var env: Array = P["blade_env"]
	blade_level = _env(env, t) if on else move_toward(blade_level, 0.0, dt * 4.0)
	_build_blade(xf, blade_level if enabled else 0.0)
	# 斬擊核心＋火幕
	var lvl := clampf((tip_speed - float(P["speed_lo"])) / (float(P["speed_hi"]) - float(P["speed_lo"])), 0.0, 1.0)
	var w: Array = P["slash_window"]
	var want := on and t >= float(w[0]) and t <= float(w[1]) and tip_speed > float(P["speed_lo"]) * 0.8
	_feed_ribbon(xf, adt, want, lvl)
	# 粒子發射（停格時不發）
	if on and not freeze and _have_prev and dt > 0.0:
		_emit_slash(xf, dt, t, lvl, want)
		_emit_aura(xf, dt, tip_speed)
	_update_flashes(adt)
	_prev = xf
	_have_prev = true

## 第一次出招才編譯著色器會卡 80–150 ms（首輪檢查實測：shot_t 0.47→0.55、0.59→0.74 跳格），刀身掃掠因此漏掉命中。
## 開場在相機前 2 m 把每種材質畫一次（顏色與覆蓋全為 0，看不見），連畫幾幀後清掉。
func _do_prewarm() -> void:
	_prewarm -= 1
	_sheet_mesh.clear_surfaces()
	_core_mesh.clear_surfaces()
	_blade_mesh.clear_surfaces()
	if _prewarm <= 0 or cam == null:
		for mi in _flash_pool:
			(mi as MeshInstance3D).visible = false
		return
	var p := cam.global_transform * Vector3(0, 0, -2.0)
	var r := cam.global_basis.x * 0.2
	var u := cam.global_basis.y * 0.2
	for im: ImmediateMesh in [_sheet_mesh, _core_mesh, _blade_mesh]:
		im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		for v: Vector3 in [p - r - u, p - r + u, p + r - u, p + r + u]:
			im.surface_set_color(Color(1, 1, 1, 0))
			im.surface_set_uv(Vector2(0.5, 0.5))
			im.surface_set_uv2(Vector2(1.0, 0.0))
			im.surface_add_vertex(v)
		im.surface_end()
	_emit(flames, p, Vector3.ZERO, Vector3.UP, 0.1, 0.1, 0.05, 0, 0.0)
	_emit(sparks, p, Vector3.ZERO, Vector3.UP, 0.01, 0.03, 0.05, 3, 0.0)
	for mi in _flash_pool:
		var m := (mi as MeshInstance3D).material_override as ShaderMaterial
		m.set_shader_parameter("age", 1.0)
		(mi as MeshInstance3D).global_position = p
		(mi as MeshInstance3D).visible = true

# ------------------------------------------------------------------ 斬擊 ribbon（核心＋火幕）
func _feed_ribbon(cur: Transform3D, adt: float, want: bool, lvl: float) -> void:
	var life := float(P["sheet_life"])
	var r := 0
	while r < _runs.size():
		var run: Array = _runs[r]
		var i := 0
		while i < run.size():
			run[i]["age"] = float(run[i]["age"]) + adt
			if float(run[i]["age"]) >= life:
				run.remove_at(i)
			else:
				i += 1
		if run.is_empty() and not (_emitting and r == _runs.size() - 1):
			_runs.remove_at(r)
		else:
			r += 1
	if want and not _emitting:
		_emitting = true
		_runs.append([])
		_seed = rng.randf() * 10.0
	elif not want and _emitting:
		_emitting = false
	if _emitting:
		var run: Array = _runs.back()
		if run.is_empty() or not _have_prev:
			run.append({"xf": cur, "age": 0.0, "trav": _travel, "lvl": lvl})
			ribbon_samples += 1
		else:
			var ang := rad_to_deg(_prev.basis.get_rotation_quaternion().angle_to(cur.basis.get_rotation_quaternion()))
			var tip_d := (_prev * Vector3(0, TIP, 0)).distance_to(cur * Vector3(0, TIP, 0))
			if ang > 0.3 or tip_d > 0.004:
				var n := clampi(int(ceil(maxf(ang / 4.0, tip_d / 0.06))), 1, 24)
				var lvl0: float = float(run.back()["lvl"])
				for k in range(1, n + 1):
					var f := float(k) / float(n)
					var xf := _prev.interpolate_with(cur, f)
					var last: Transform3D = run.back()["xf"]
					_travel += (last * Vector3(0, TIP, 0)).distance_to(xf * Vector3(0, TIP, 0))
					run.append({"xf": xf, "age": (1.0 - f) * adt, "trav": _travel, "lvl": lerpf(lvl0, lvl, f)})
					ribbon_samples += 1
	_build_ribbons()

func _build_ribbons() -> void:
	_sheet_mesh.clear_surfaces()
	_core_mesh.clear_surfaces()
	if not enabled:
		return
	var life := float(P["sheet_life"])
	var clife := float(P["core_life"])
	var u0 := float(P["sheet_u0"]) * TIP
	var ext := float(P["sheet_ext"])
	var lift := float(P["sheet_lift"])
	var cu0 := float(P["core_u0"]) * TIP
	for run: Array in _runs:
		if run.size() < 2:
			continue
		_sheet_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		for s: Dictionary in run:
			var xf: Transform3D = s["xf"]
			var a: float = float(s["age"]) / life
			var lv: float = float(s["lvl"])
			var base := xf * Vector3(0, u0, 0)
			var tip := xf * Vector3(0, TIP, 0)
			var dir := (tip - base).normalized()
			var up := Vector3.UP * lift * pow(a, 1.4)
			var outer := tip + dir * (ext * (0.45 + 0.55 * lv) + 0.10 * a) + up
			var inner := base + up * 0.45
			var c := Color(1, 1, 1, 0.35 + 0.65 * lv)
			_sheet_mesh.surface_set_color(c)
			_sheet_mesh.surface_set_uv(Vector2(float(s["trav"]), 0.0))
			_sheet_mesh.surface_set_uv2(Vector2(a, _seed))
			_sheet_mesh.surface_add_vertex(inner)
			_sheet_mesh.surface_set_color(c)
			_sheet_mesh.surface_set_uv(Vector2(float(s["trav"]), 1.0))
			_sheet_mesh.surface_set_uv2(Vector2(a, _seed))
			_sheet_mesh.surface_add_vertex(outer)
		_sheet_mesh.surface_end()
		var core: Array = []
		for s: Dictionary in run:
			if float(s["age"]) < clife:
				core.append(s)
		if core.size() >= 2:
			_core_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
			for s: Dictionary in core:
				var xf: Transform3D = s["xf"]
				var a: float = float(s["age"]) / clife
				var lv: float = float(s["lvl"])
				var c := Color(1, 1, 1, (0.25 + 0.75 * lv) * smoothstep(0.0, 0.10, a))    # 最前緣淡入：刀身本體不被白光洗掉
				_core_mesh.surface_set_color(c)
				_core_mesh.surface_set_uv(Vector2(float(s["trav"]), 0.0))
				_core_mesh.surface_set_uv2(Vector2(a, 0.0))
				_core_mesh.surface_add_vertex(xf * Vector3(0, cu0, 0))
				_core_mesh.surface_set_color(c)
				_core_mesh.surface_set_uv(Vector2(float(s["trav"]), 1.0))
				_core_mesh.surface_set_uv2(Vector2(a, 0.0))
				_core_mesh.surface_add_vertex(xf * Vector3(0, TIP + 0.025, 0))
			_core_mesh.surface_end()

# ------------------------------------------------------------------ 刀身火
func _build_blade(xf: Transform3D, level: float) -> void:
	_blade_mesh.clear_surfaces()
	if level <= 0.01 or cam == null:
		return
	var a := xf * Vector3.ZERO
	var b := xf * Vector3(0, TIP, 0)
	var axis := (b - a).normalized()
	var blen := a.distance_to(b)
	var h := float(P["blade_height"])
	var n := 12
	for side: float in [1.0, -1.0]:
		_blade_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		for k in n + 1:
			var u := lerpf(0.12, 1.0, float(k) / n)
			var p := a.lerp(b, u)
			var view := (cam.global_position - p).normalized()
			var o: Vector3 = axis.cross(view).normalized() * side
			var taper := 0.45 + 0.55 * clampf((u - 0.12) / 0.88, 0.0, 1.0)
			var c := Color(1, 1, 1, level * taper)
			var x := u * blen + (0.0 if side > 0.0 else 7.3)
			_blade_mesh.surface_set_color(c)
			_blade_mesh.surface_set_uv(Vector2(x, 0.0))
			_blade_mesh.surface_add_vertex(p + o * 0.006)
			_blade_mesh.surface_set_color(c)
			_blade_mesh.surface_set_uv(Vector2(x, 1.0))
			_blade_mesh.surface_add_vertex(p + o * (0.006 + h * level * (0.55 + 0.45 * u)) + Vector3.UP * 0.035 * level)
		_blade_mesh.surface_end()

# ------------------------------------------------------------------ 粒子發射
func _emit(ps: GPUParticles3D, pos: Vector3, vel: Vector3, axis: Vector3, w: float, h: float, life: float, kind: int, inten: float) -> void:
	var ax := axis.normalized() if axis.length_squared() > 1e-6 else Vector3.UP
	var right := ax.cross(Vector3.FORWARD)
	if right.length_squared() < 0.01:
		right = ax.cross(Vector3.RIGHT)
	right = right.normalized()
	var bs := Basis(right * w, ax * h, right.cross(ax).normalized() * w)
	ps.emit_particle(Transform3D(bs, pos), vel, Color(1, 1, 1, inten), Color(0, life, rng.randf(), float(kind)), FLAGS)

func _blade_vel(cur: Transform3D, u: float, dt: float) -> Vector3:
	return (cur * Vector3(0, u, 0) - _prev * Vector3(0, u, 0)) / maxf(dt, 0.001)

## 刀路火舌與火星：依刀身外段（u＝0.85）走過的距離發射；刀越快、間距越密，總量有上限
func _emit_slash(cur: Transform3D, dt: float, t: float, lvl: float, want: bool) -> void:
	if not want or lvl < 0.12:
		return
	var ref := TIP * 0.85
	var dist := (cur * Vector3(0, ref, 0)).distance_to(_prev * Vector3(0, ref, 0))
	var spacing := lerpf(float(P["tongue_spacing_far"]), float(P["tongue_spacing_near"]), lvl)
	_tongue_debt += dist / spacing
	var tw: Array = P["tongue_w"]
	var th: Array = P["tongue_h"]
	var tl: Array = P["tongue_life"]
	while _tongue_debt >= 1.0 and _slash_tongues < int(P["tongue_cap"]):
		_tongue_debt -= 1.0
		var f := rng.randf()
		var xf := _prev.interpolate_with(cur, f)
		var u := rng.randf_range(0.42, 1.04) * TIP
		var pos := xf * Vector3(0, u, 0)
		var v := _blade_vel(cur, u, dt)
		var back := -v.normalized() if v.length() > 0.5 else Vector3.ZERO
		var axis := (Vector3.UP + back * 0.45 + Vector3(rng.randf_range(-0.2, 0.2), 0, rng.randf_range(-0.2, 0.2))).normalized()
		var sz := lerpf(0.65, 1.0, lvl) * lerpf(0.75, 1.0, u / TIP)
		_emit(flames, pos, v * 0.07 + Vector3.UP * rng.randf_range(0.15, 0.4), axis,
			rng.randf_range(float(tw[0]), float(tw[1])) * sz, rng.randf_range(float(th[0]), float(th[1])) * sz,
			rng.randf_range(float(tl[0]), float(tl[1])), 0, lerpf(0.75, 1.0, lvl))
		_slash_tongues += 1
		n_emit["tongue"] += 1
	if lvl < 0.35:
		return
	_spark_debt += dist / float(P["spark_spacing"])
	while _spark_debt >= 1.0 and _slash_sparks < int(P["spark_cap"]):
		_spark_debt -= 1.0
		var xf2 := _prev.interpolate_with(cur, rng.randf())
		var u2 := rng.randf_range(0.80, 1.06) * TIP
		var v2 := _blade_vel(cur, u2, dt)
		var rnd := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.2, 1.2), rng.randf_range(-1, 1)) * rng.randf_range(0.6, 2.0)
		_emit(sparks, xf2 * Vector3(0, u2, 0), v2 * 0.22 + rnd, Vector3.UP, rng.randf_range(0.010, 0.016), 0.03, rng.randf_range(0.35, 0.9), 3, 1.0)
		_slash_sparks += 1
		n_emit["spark"] += 1

## 刀身小火：刀慢的時候（蓄勢、收勢）從刀刃往上竄；刀快的時候交給刀路火舌
func _emit_aura(cur: Transform3D, dt: float, tip_speed: float) -> void:
	if blade_level < 0.15 or tip_speed > float(P["aura_max_speed"]):
		return
	_aura_debt += dt * float(P["aura_rate"]) * blade_level
	while _aura_debt >= 1.0:
		_aura_debt -= 1.0
		var u := rng.randf_range(0.25, 1.0) * TIP
		var pos := cur * Vector3(0, u, 0)
		var v := _blade_vel(cur, u, dt)
		var s := lerpf(0.7, 1.0, u / TIP) * blade_level
		_emit(flames, pos, v * 0.05 + Vector3.UP * 0.25, Vector3.UP, rng.randf_range(0.13, 0.20) * s, rng.randf_range(0.26, 0.40) * s,
			rng.randf_range(0.26, 0.42), 1, 0.9)
		n_emit["aura"] += 1

# ------------------------------------------------------------------ 命中
## pos＝刀刃切入點，dir＝刀的行進方向，normal＝目標表面往外（水平）
func hit(pos: Vector3, dir: Vector3, normal := Vector3.ZERO) -> void:
	if not enabled:
		return
	hits_spawned += 1
	var cut := dir.normalized() if dir.length() > 0.1 else Vector3.DOWN
	var nrm := normal.normalized() if normal.length() > 0.1 else -cut
	var at := pos + nrm * 0.06
	# 高溫裂口：沿刀的行進方向拉長，Hit Stop 期間停在最亮
	var mi: MeshInstance3D = _flash_pool[_flash_ix % _flash_pool.size()]
	_flash_ix += 1
	for f0 in _flashes:
		if f0["mi"] == mi:
			_flashes.erase(f0)
			break
	var side := cut.cross(nrm)
	if side.length_squared() < 1e-4:
		side = cut.cross(Vector3.UP)
	side = side.normalized()
	mi.global_transform = Transform3D(Basis(side * float(P["hit_flash_w"]), cut * float(P["hit_flash_len"]), side.cross(cut).normalized()), at)
	var m := mi.material_override as ShaderMaterial
	m.set_shader_parameter("age", 0.0)
	m.set_shader_parameter("seed", rng.randf() * 10.0)
	mi.visible = enabled
	_flashes.append({"mi": mi, "t": 0.0, "life": float(P["hit_flash_life"])})
	# 定向爆燃：往「表面外法線＋刀的行進方向」噴，迅速減速後轉為上浮
	for i in int(P["hit_tongues"]):
		var d := (cut * 0.65 + nrm * 0.85 + Vector3(rng.randf_range(-0.35, 0.35), rng.randf_range(-0.1, 0.45), rng.randf_range(-0.35, 0.35))).normalized()
		var axis := (d + Vector3.UP * 0.6).normalized()
		_emit(flames, at + d * rng.randf_range(0.0, 0.08), d * rng.randf_range(1.6, 3.6), axis,
			rng.randf_range(0.30, 0.46), rng.randf_range(0.52, 0.85), rng.randf_range(0.30, 0.50), 2, 1.0)
		n_emit["hit"] += 1
	for i in int(P["hit_sparks"]):
		var d2 := (cut * 0.8 + nrm * 0.9 + Vector3(rng.randf_range(-0.7, 0.7), rng.randf_range(-0.3, 0.9), rng.randf_range(-0.7, 0.7))).normalized()
		_emit(sparks, at, d2 * rng.randf_range(2.0, 5.5), Vector3.UP, rng.randf_range(0.010, 0.017), 0.03, rng.randf_range(0.30, 0.75), 3, 1.0)
		n_emit["spark"] += 1

func _update_flashes(adt: float) -> void:
	var i := 0
	while i < _flashes.size():
		var f: Dictionary = _flashes[i]
		f["t"] = float(f["t"]) + adt
		var k := clampf(float(f["t"]) / float(f["life"]), 0.0, 1.0)
		var mi: MeshInstance3D = f["mi"]
		(mi.material_override as ShaderMaterial).set_shader_parameter("age", k)
		mi.visible = enabled
		if k >= 1.0:
			mi.visible = false
			_flashes.remove_at(i)
		else:
			i += 1

## 量測用
func stats() -> Dictionary:
	var rs := 0
	for run in _runs:
		rs += (run as Array).size()
	return {"emitted": n_emit.duplicate(), "hits": hits_spawned, "freeze_frames": frozen_frames, "ribbon_live": rs, "ribbon_total": ribbon_samples,
		"blade": blade_level, "flashes": _flashes.size(), "fx_time": fx_time, "lights": 0,
		"trail_samples": rs, "sparks_est": 0, "hit_particles": 0}

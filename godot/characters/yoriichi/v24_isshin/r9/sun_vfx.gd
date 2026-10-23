extends Node3D
## R9 日之呼吸 VFX 模組（候選；可重用：之後其他型只換 profile 參數）。正式 Player 的刀光／著色器只讀重用，不改。
## 組件（全部以刀的實際變換與「技能時間」驅動，不寫死在任何動畫裡）：
##   1. 刀刃火焰 blade：沿刀身、朝相機展開的兩條火舌帶（外焰 sun_flame_trail＋白熱核心 sun_flame_core），每幀依刀的變換重建，
##      所以火焰永遠貼著刀；強度依 profile.blade.env（[[技能秒, 0..1], ...] 折線）＝起手點燃、主斬全亮、收勢熄滅。
##   2. 斬擊殘影 trail：sun_trail_r9.gd（正式 SwordTrail3D 的子類），只在 profile.trail.emit 的時間窗內產生新刀光，舊刀光照壽命燒完；
##      幀間用刀的整個變換插值補樣本；Hit Stop 時 clock_scale＝0，尾巴凍結不斷。
##   3. 火星 sparks：GPUParticles3D 掛在刀身外段，只在 profile.sparks.windows 內、且刀尖速度 ≥ min_speed 時依速度噴出。
##   4. 命中火焰 hit：在刀刃切入點（判定給的 entry）沿刀的行進方向往前推 offset 公尺爆一小團火星＋短閃光；不蓋住切入點。
## 介面：setup(sword, cam)；begin(profile)；end()；frame(sword_xf, skill_t, dt, clock_scale, tip_speed)（骨架更新後呼叫）；hit(pos, dir)；stats()
const TrailR9 = preload("res://characters/yoriichi/v24_isshin/r9/sun_trail_r9.gd")
const FLAME_SHADER := preload("res://characters/yoriichi/vfx/sun_flame_trail.gdshader")
const CORE_SHADER := preload("res://characters/yoriichi/vfx/sun_flame_core.gdshader")
const GUARD_LOCAL := Vector3(0, 0.0, 0)
const TIP_LOCAL := Vector3(0, 1.085, 0)

var sword: Node3D
var cam: Camera3D
var profile := {}
var active := false
var enabled := true
var skill_t := 0.0
var trail
var blade_flame: MeshInstance3D
var blade_core: MeshInstance3D
var _bf_mesh := ImmediateMesh.new()
var _bc_mesh := ImmediateMesh.new()
var _bf_mat := ShaderMaterial.new()
var _bc_mat := ShaderMaterial.new()
var sparks: GPUParticles3D
var _hit_pool: Array = []
var _hit_ix := 0
var _flashes: Array = []
var _flash_pool: Array = []
var _flash_ix := 0
var blade_level := 0.0
var hits_spawned := 0

func setup(sword_: Node3D, cam_: Camera3D) -> void:
	sword = sword_
	cam = cam_
	top_level = true
	global_transform = Transform3D.IDENTITY
	trail = TrailR9.new()
	trail.name = "SunTrailR9"
	add_child(trail)
	_bf_mat.shader = FLAME_SHADER
	_bc_mat.shader = CORE_SHADER
	_bc_mat.render_priority = 1
	blade_flame = _mk_mi("BladeFlame", _bf_mesh, _bf_mat)
	blade_core = _mk_mi("BladeCore", _bc_mesh, _bc_mat)
	sparks = _mk_sparks()
	add_child(sparks)
	for i in 3:
		var hp := _mk_hit_particles()
		add_child(hp)
		_hit_pool.append(hp)
	# 命中閃光：預先建好 3 片輪流用（每次命中新建 QuadMesh＋材質，實測那一幀 script 卡 ~40 ms）
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var rg := Gradient.new()                 # 圓形放射漸層（中心白熱 → 邊緣透明），不是方形色塊
	rg.set_color(0, Color(1, 1, 1, 1))
	rg.set_color(1, Color(1, 0.6, 0.2, 0))
	rg.add_point(0.35, Color(1, 0.85, 0.5, 0.8))
	var rt := GradientTexture2D.new()
	rt.gradient = rg
	rt.fill = GradientTexture2D.FILL_RADIAL
	rt.fill_from = Vector2(0.5, 0.5)
	rt.fill_to = Vector2(1.0, 0.5)
	rt.width = 64
	rt.height = 64
	for i in 3:
		var mi := MeshInstance3D.new()
		mi.name = "HitFlash%d" % i
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.no_depth_test = true
		m.render_priority = 2
		m.albedo_color = Color(1.0, 0.85, 0.55, 0.0)    # 不超過泛光門檻 1.1：HDR 亮度會被 glow 放大成 0.8–1 m 的光團、蓋住接觸點（R9 審圖）
		m.albedo_texture = rt
		mi.material_override = m
		mi.mesh = q
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.top_level = true
		add_child(mi)
		mi.global_position = Vector3(0, -50, 0)
		_flash_pool.append(mi)

func _mk_mi(n: String, m: ImmediateMesh, mat: ShaderMaterial) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = m
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 4.0
	mi.top_level = true
	add_child(mi)
	mi.global_transform = Transform3D.IDENTITY
	return mi

func _spark_draw(size: float, gain := 1.0) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(2.2 * gain, 1.6 * gain, 0.8 * gain, 1.0)
	m.no_depth_test = false
	q.material = m
	return q

func _ramp() -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.95, 0.75, 1.0))
	g.set_color(1, Color(0.85, 0.18, 0.04, 0.0))
	g.add_point(0.35, Color(1.0, 0.62, 0.16, 1.0))
	var t := GradientTexture1D.new()
	t.gradient = g
	return t

func _mk_sparks() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Sparks"
	p.amount = 64
	p.lifetime = 0.40
	p.local_coords = false
	p.emitting = false
	p.amount_ratio = 0.0
	p.visibility_aabb = AABB(Vector3(-6, -6, -6), Vector3(12, 12, 12))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.012, 0.28, 0.012)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.4
	pm.initial_velocity_max = 1.6
	pm.gravity = Vector3(0, -5.0, 0)
	pm.damping_min = 1.0
	pm.damping_max = 2.0
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	pm.color_ramp = _ramp()
	pm.inherit_velocity_ratio = 0.12
	p.process_material = pm
	p.draw_pass_1 = _spark_draw(0.035)
	return p

func _mk_hit_particles() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "HitBurst"
	p.amount = 28
	p.lifetime = 0.32
	p.one_shot = true
	p.explosiveness = 0.92
	p.local_coords = false
	p.emitting = false
	p.visibility_aabb = AABB(Vector3(-4, -4, -4), Vector3(8, 8, 8))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.06
	pm.direction = Vector3(0, 0, -1)
	pm.spread = 38.0
	pm.initial_velocity_min = 2.5
	pm.initial_velocity_max = 5.5
	pm.gravity = Vector3(0, -4.0, 0)
	pm.damping_min = 2.0
	pm.damping_max = 4.0
	pm.scale_min = 0.5
	pm.scale_max = 0.9
	pm.color_ramp = _ramp()
	p.process_material = pm
	p.draw_pass_1 = _spark_draw(0.03, 0.65)      # 命中火星：同時噴出會在接觸點疊成一團，所以每顆暗一點、小一點、噴得快
	return p

## 開始一招（profile＝sun_breathing.json 的 vfx 欄）
func begin(prof: Dictionary) -> void:
	profile = prof
	active = true
	skill_t = 0.0
	var tr: Dictionary = profile.get("trail", {})
	trail.lifetime = float(tr.get("lifetime", 0.28))
	trail.flame_extend = float(tr.get("extend", 0.35))
	trail.flame_inset = float(tr.get("inset", 0.05))
	trail.flame_lift = float(tr.get("lift", 0.10))
	trail.max_step_deg = float(tr.get("max_step_deg", 4.0))
	trail.flame_emission = 2.2 * float(tr.get("emission", 1.0))
	trail.core_emission = 3.4 * float(tr.get("emission", 1.0)) * float(tr.get("core_emission", 1.0))
	trail.opacity = float(tr.get("opacity", 1.0))
	trail.core_root_skip = float(tr.get("core_root_skip", 0.22))
	trail.core_lifetime_ratio = float(tr.get("core_ratio", 0.55))
	trail.head_fade = float(tr.get("head_fade", 0.0))
	var bl: Dictionary = profile.get("blade", {})
	_bf_mat.set_shader_parameter("emission_strength", 2.2 * float(bl.get("emission", 1.0)))
	_bf_mat.set_shader_parameter("flame_height", float(bl.get("tongue", 0.9)))
	_bf_mat.set_shader_parameter("tile", float(bl.get("tile", 6.0)))
	_bf_mat.set_shader_parameter("flow_speed", float(bl.get("flow", 3.0)))
	_bc_mat.set_shader_parameter("emission_strength", 3.4 * float(bl.get("emission", 1.0)) * float(bl.get("core_emission", 1.0)))
	_bc_mat.set_shader_parameter("core_width", float(bl.get("core_width", 0.35)))
	var sp: Dictionary = profile.get("sparks", {})
	sparks.lifetime = float(sp.get("lifetime", 0.40))

func end() -> void:
	active = false
	if trail.is_emitting:
		trail.stop_trail()
	sparks.emitting = false
	sparks.amount_ratio = 0.0

static func _in_windows(ws: Array, t: float) -> bool:
	for w in ws:
		if t >= float(w[0]) and t <= float(w[1]):
			return true
	return false

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

## 每幀（骨架更新後）：刀的變換、技能時間（shot_t，Hit Stop 時不前進）、真實 dt、時鐘倍率（停格＝0）、刀尖速度
func frame(sw: Transform3D, t: float, dt: float, clock: float, tip_speed: float) -> void:
	skill_t = t
	var on := enabled and active
	# 2. 殘影
	var tr: Dictionary = profile.get("trail", {})
	var want_trail := on and _in_windows(tr.get("emit", []), t)
	if want_trail and not trail.is_emitting:
		trail.start_trail()
	elif not want_trail and trail.is_emitting:
		trail.stop_trail()
	trail.clock_scale = clock
	trail.feed(sw, dt)
	# 1. 刀刃火焰
	blade_level = _env((profile.get("blade", {}) as Dictionary).get("env", []), t) if on else move_toward(blade_level, 0.0, dt * 4.0)
	_build_blade(sw, blade_level)
	# 3. 火星
	var sp: Dictionary = profile.get("sparks", {})
	var mid := sw * TIP_LOCAL.lerp(GUARD_LOCAL, 0.32)
	sparks.global_transform = Transform3D(sw.basis.orthonormalized(), mid)
	var ratio := 0.0
	if on and _in_windows(sp.get("windows", []), t):
		var v0 := float(sp.get("min_speed", 5.0))
		var v1 := float(sp.get("full_speed", 20.0))
		ratio = clampf((tip_speed - v0) / maxf(v1 - v0, 0.1), 0.0, 1.0) * float(sp.get("max_ratio", 1.0))
	sparks.amount_ratio = ratio
	sparks.emitting = ratio > 0.01
	# 4. 閃光淡出（真實時間）
	var i := 0
	while i < _flashes.size():
		var f: Dictionary = _flashes[i]
		f["t"] = float(f["t"]) + dt
		var k := clampf(float(f["t"]) / float(f["life"]), 0.0, 1.0)
		var mi: MeshInstance3D = f["mi"]
		(mi.material_override as StandardMaterial3D).albedo_color.a = (1.0 - k) * (1.0 - k)
		mi.scale = Vector3.ONE * float(f["size"]) * lerpf(0.6, 1.0, k)
		if k >= 1.0:
			mi.global_position = Vector3(0, -50, 0)
			_flashes.remove_at(i)
		else:
			i += 1

func _build_blade(sw: Transform3D, level: float) -> void:
	_bf_mesh.clear_surfaces()
	_bc_mesh.clear_surfaces()
	if level <= 0.01 or cam == null:
		return
	var bl: Dictionary = profile.get("blade", {})
	var h := float(bl.get("height", 0.10))
	var u0 := float(bl.get("u0", 0.10))
	var a := sw * GUARD_LOCAL
	var b := sw * TIP_LOCAL
	var axis := (b - a).normalized()
	var blen := a.distance_to(b)
	var n := 10
	for side: float in [1.0, -1.0]:
		_bf_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _bf_mat)
		for k in n + 1:
			var u := lerpf(u0, 1.0, float(k) / n)
			var p := a.lerp(b, u)
			var view := (cam.global_position - p).normalized()
			var o: Vector3 = axis.cross(view).normalized() * side
			var taper := 0.5 + 0.5 * clampf((u - u0) / (1.0 - u0), 0.0, 1.0)     # 刀根淡、往刀尖漸強
			var c := Color(1, 1, 1, level * taper)
			_bf_mesh.surface_set_color(c)
			_bf_mesh.surface_set_uv(Vector2(u * blen, 0.0))
			_bf_mesh.surface_add_vertex(p + o * 0.004)
			_bf_mesh.surface_set_color(c)
			_bf_mesh.surface_set_uv(Vector2(u * blen, 1.0))
			_bf_mesh.surface_add_vertex(p + o * (0.004 + h * level * (0.6 + 0.4 * u)))
		_bf_mesh.surface_end()
		_bc_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _bc_mat)
		for k in n + 1:
			var u := lerpf(u0, 1.0, float(k) / n)
			var p := a.lerp(b, u)
			var view := (cam.global_position - p).normalized()
			var o: Vector3 = axis.cross(view).normalized() * side
			var c := Color(1, 1, 1, level)
			_bc_mesh.surface_set_color(c)
			_bc_mesh.surface_set_uv(Vector2(u * blen, 0.0))
			_bc_mesh.surface_add_vertex(p + o * 0.006)          # 核心從刀刃外 6 mm 起，刀身本體（金屬）保持看得見
			_bc_mesh.surface_set_color(c)
			_bc_mesh.surface_set_uv(Vector2(u * blen, 1.0))
			_bc_mesh.surface_add_vertex(p + o * (0.006 + h * 0.45 * level))
		_bc_mesh.surface_end()

## 命中：pos＝刀刃切入點，dir＝刀的行進方向，normal＝目標表面往外的方向（水平）。
## 火星從切入點沿「表面外法線＋刀的行進方向」噴出（不往目標裡面噴、不被目標擋住）；閃光放在切入點外側 offset 公尺，
## 不做深度遮擋（不然會被目標本體吃掉），尺寸小、0.09 s 就熄，不蓋住刀與目標的接觸。
func hit(pos: Vector3, dir: Vector3, normal := Vector3.ZERO) -> void:
	if not (enabled and active):
		return
	var hp_: Dictionary = profile.get("hit", {})
	var cut := dir.normalized() if dir.length() > 0.1 else Vector3.DOWN
	var nrm := normal.normalized() if normal.length() > 0.1 else -cut
	var d := (nrm * float(hp_.get("normal_w", 0.7)) + cut * float(hp_.get("cut_w", 0.5))).normalized()
	var at := pos + nrm * float(hp_.get("offset", 0.05))
	var p: GPUParticles3D = _hit_pool[_hit_ix % _hit_pool.size()]
	_hit_ix += 1
	p.amount = int(hp_.get("particles", 28))
	var up := Vector3.UP if absf(d.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	p.global_transform = Transform3D(Basis.looking_at(d, up), at)       # 粒子方向 -Z＝沿刀的行進方向
	p.restart()
	p.emitting = true
	hits_spawned += 1
	var fs := float(hp_.get("flash_size", 0.16))
	if fs > 0.0:
		var mi: MeshInstance3D = _flash_pool[_flash_ix % _flash_pool.size()]
		_flash_ix += 1
		for f0 in _flashes:
			if f0["mi"] == mi:
				_flashes.erase(f0)
				break
		mi.global_position = at
		mi.scale = Vector3.ONE * fs * 0.6
		(mi.material_override as StandardMaterial3D).albedo_color.a = 1.0
		_flashes.append({"mi": mi, "t": 0.0, "life": float(hp_.get("flash_time", 0.09)), "size": fs})

## 量測用：刀光最新取樣點的刀尖與這一幀刀尖的距離（m）；-1＝目前沒有在產生刀光
func trail_head_lag(sw: Transform3D) -> float:
	if not trail.is_emitting or trail._runs.is_empty() or (trail._runs.back() as Array).is_empty():
		return -1.0
	var last: Dictionary = (trail._runs.back() as Array).back()
	return (last["tip"] as Vector3).distance_to(sw * TIP_LOCAL)

## 量測用：刀刃火焰最外一點離刀身軸線的距離（m）；火焰帶寬度上限＝height（不會離開刀）
func blade_flame_offset_max() -> float:
	var bl: Dictionary = profile.get("blade", {})
	return float(bl.get("height", 0.10)) * blade_level + 0.004

## 量測用
func stats() -> Dictionary:
	var hit_alive := 0
	for p in _hit_pool:
		if (p as GPUParticles3D).emitting:
			hit_alive += (p as GPUParticles3D).amount
	return {"trail_samples": trail.sample_count(), "spark_ratio": sparks.amount_ratio, "spark_max": sparks.amount,
		"sparks_est": int(round(sparks.amount * sparks.amount_ratio)) if sparks.emitting else 0, "hit_particles": hit_alive, "blade": blade_level, "flashes": _flashes.size()}

extends Node3D
## R9-C 日之呼吸・圓舞 Blender 特效候選的播放模組（候選；R9 的程式刀光 sun_vfx.gd 保留不動，可隨時切回）。
## 資產：r9c/enbu_vfx_<A|B>.glb（Blender：notes/r9c/build_enbu_vfx.py，依 Godot 實際記錄的刀路建模；物件 Core／Flames／Tail／Embers／
##       BladeFlame／HitFlame），貼圖 r9c_tongue／r9c_core／r9c_ember.png，著色器 enbu_flame／enbu_core.gdshader。
## 播放：
##   * Core／Flames／Tail／Embers 的頂點是「角色本地座標」的刀路 → 掛在角色底下；主斬結束（freeze_t）後改成世界座標固定，殘焰留在原地消散。
##   * BladeFlame 是刀的本地座標 → 掛在刀上；明暗依 blade_env（技能時間折線：蓄勢點燃 → 主斬全亮 → 收勢熄滅）。
##   * 每一片火的出現／長出／撕裂／熄滅由著色器依「技能時間 − 刀經過的時間」計算；技能時間＝shot_t，Hit Stop 時不前進（畫面靜止）。
##   * Blender 做的 shape key「drift」＝火舌上捲、殘焰飛散；權重依技能時間。
##   * 命中：HitFlame（Blender 的 5–7 條短火舌）放在刀刃切入點、+Z 對準刀的行進方向；外加少量火星（水滴形貼圖，不是方塊）。
const DIR := "res://characters/yoriichi/v24_isshin/r9c/"
const FLAME_SH := preload("res://characters/yoriichi/v24_isshin/r9c/enbu_flame.gdshader")
const CORE_SH := preload("res://characters/yoriichi/v24_isshin/r9c/enbu_core.gdshader")
const TEX_TONGUE := preload("res://characters/yoriichi/v24_isshin/r9c/r9c_tongue.png")
const TEX_CORE := preload("res://characters/yoriichi/v24_isshin/r9c/r9c_core.png")
const TEX_EMBER := preload("res://characters/yoriichi/v24_isshin/r9c/r9c_ember.png")
## R9-C2（C1／C2／C3）新增：Sheet／Layer*／Fin＝主體火焰帶與交叉立面（貼圖 r9c2_body）、Ring＝日輪（r9c2_ring）、
##   命中改成 HitFlame＋HitRing（往外擴的火環，shape key drift）＋HitStar（0.08 s 針狀星芒）一組，外加命中閃光（OmniLight3D）。
const TEX_BODY := preload("res://characters/yoriichi/v24_isshin/r9c/r9c2_body.png")
const TEX_RING := preload("res://characters/yoriichi/v24_isshin/r9c/r9c2_ring.png")
const HIT_KEYS := ["hit", "hitring", "hitstar"]
## R9-C3（L1／L2）：動態光照。火焰 mesh 不變（C2 的流焰＋C1 的命中爆燃，見 sun_breathing.json 的 mesh／extra），
##   只加一組在 setup 時建好、全部版本共用、沒有陰影的局部光（不在出招時新建燈光或材質）：
##   * 刀身火光 BladeLight：跟著刀身中段；亮度依技能時間折線（蓄勢漸亮 → 主斬增強 → 命中峰值 → 收勢快速衰退），Hit Stop 時技能時間不動＝停在峰值。
##   * 火焰體光 TrailLight×2：落在刀後 lag 秒（火正在燒的位置），主斬結束後固定在世界中、隨殘焰熄滅。
##   * 命中光 HitLight：Hit Stop 期間＝白金色強光，停格一放開就轉成橘紅爆燃再衰減（真實時間）。
##   * 餘光 EmberLight（L2）：命中後木樁附近的深橘紅餘燼光。
##   * 熱浪 Haze（L2 實驗）：只扭曲比熱浪遠的背景（enbu_haze.gdshader 依深度判斷），人物、刀、木樁不扭曲。
const HAZE_SH := preload("res://characters/yoriichi/v24_isshin/r9c/enbu_haze.gdshader")

var actor: Node3D
var sword: Node3D
var cam: Camera3D
var enabled := true
var sets := {}            # variant -> {arc: Node3D, blade: MeshInstance3D, hit: MeshInstance3D, mats: {}, meshes: [], params}
var cur := ""
var active := false
var skill_t := 0.0
var frozen := false
var _hits: Array = []
var sparks: GPUParticles3D
var burst: GPUParticles3D
var hits_spawned := 0
var flare := 0.0
var hit_light: OmniLight3D
var _ignited := false
var light_t := 9.0
var hitstop := false                 # R9-C3：場景每幀給（combat.hitstop_left > 0）
var blade_light: OmniLight3D
var trail_lights: Array = []
var ember_light: OmniLight3D
var haze: MeshInstance3D
var _path: Array = []                # [技能時間, arc 本地座標]：刀身中段走過的路
var _flick := 0.0                    # 火光閃爍的時鐘（Hit Stop 時不走）
var _hit_age := -1.0                 # 命中後經過的真實時間（-1＝沒有）
var _rel_age := -1.0                 # 停格放開後經過的真實時間（-1＝還在白光段）
var _hit_pos := Vector3.ZERO
var _hit_nrm := Vector3.FORWARD
var _ls := {}                        # 這一幀的光照狀態（記錄用）

func setup(actor_: Node3D, sword_: Node3D, cam_: Camera3D, variants: Dictionary) -> void:
	actor = actor_
	sword = sword_
	cam = cam_
	for v in variants:
		_load_variant(str(v), variants[v])
	sparks = _mk_particles(48, 0.40, false)
	add_child(sparks)
	burst = _mk_particles(10, 0.30, true)
	add_child(burst)
	hit_light = OmniLight3D.new()
	hit_light.light_color = Color(1.0, 0.55, 0.18)
	hit_light.shadow_enabled = false
	hit_light.light_energy = 0.0
	hit_light.visible = false
	hit_light.name = "EnbuHitLight"
	add_child(hit_light)
	blade_light = _mk_light("EnbuBladeLight")
	for i in 2:
		trail_lights.append(_mk_light("EnbuTrailLight%d" % i))
	ember_light = _mk_light("EnbuEmberLight")
	haze = MeshInstance3D.new()
	haze.name = "EnbuHaze"
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	haze.mesh = q
	var hm := ShaderMaterial.new()
	hm.shader = HAZE_SH
	hm.render_priority = -3                  # 先畫熱浪（取的是不透明場景），火焰畫在它上面
	haze.material_override = hm
	haze.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	haze.visible = false
	add_child(haze)

func _mk_light(nm: String) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.name = nm
	l.shadow_enabled = false
	l.light_energy = 0.0
	l.visible = false
	add_child(l)
	return l

func _mat(kind: String, p: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	var lp: Dictionary = p.get(kind, {})
	if kind == "core":
		m.shader = CORE_SH
		m.set_shader_parameter("tex", TEX_CORE)
		if p.get("core_on_top", false):
			m.render_priority = 2                 # C 系列：刀光核心永遠畫在火焰之上（A／B 維持原樣）
	else:
		m.shader = FLAME_SH
		m.set_shader_parameter("tex", {"embers": TEX_EMBER, "body": TEX_BODY, "ring": TEX_RING, "hitring": TEX_RING}.get(kind, TEX_TONGUE))
		m.render_priority = {"tail": -1, "body": -1, "ring": -2}.get(kind, 0)
	for k in lp:
		var val = lp[k]
		if val is Array and (val as Array).size() == 4:
			val = Color(float(val[0]), float(val[1]), float(val[2]), float(val[3]))
		m.set_shader_parameter(k, val)
	return m

func _load_variant(v: String, p: Dictionary) -> void:
	var arc := Node3D.new()
	arc.name = "EnbuArc_" + v
	var S := {"arc": arc, "mats": {}, "meshes": [], "params": p, "blade": null, "hit": null}
	# R9-C3：mesh＝主體取哪一版的 GLB；extra＝{版本: [類別…]} 這幾類改用別版（同一條實測刀路建模，可混用）
	var extra: Dictionary = p.get("extra", {})
	var taken: Array = []
	for g in extra:
		taken.append_array(extra[g])
	if not ResourceLoader.exists(DIR + "enbu_vfx_%s.glb" % str(p.get("mesh", v))):
		push_warning("SunVFXMesh: 沒有 enbu_vfx_%s.glb，略過版本 %s" % [str(p.get("mesh", v)), v])
		arc.free()
		return
	_take(S, str(p.get("mesh", v)), [], taken)
	for g in extra:
		_take(S, str(g), extra[g], [])
	_finish_variant(v, S)

func _take(S: Dictionary, src: String, only: Array, skip: Array) -> void:
	var p: Dictionary = S["params"]
	var arc: Node3D = S["arc"]
	var ps: PackedScene = load(DIR + "enbu_vfx_%s.glb" % src)
	var inst := ps.instantiate()
	for c in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		var kind := str(mi.name).split("_")[0].to_lower()            # core / flames / tail / embers / bladeflame / hitflame
		var key: String = {"core": "core", "flames": "flames", "tail": "tail", "embers": "embers", "bladeflame": "blade", "hitflame": "hit",
			"sheet": "body", "layer0": "body", "layer1": "body", "fin": "body", "ring": "ring", "burst": "burst", "hitring": "hitring", "hitstar": "hitstar"}.get(kind, "flames")
		if (not only.is_empty() and not only.has(key)) or skip.has(key):
			continue
		var m: ShaderMaterial = S["mats"][key] if S["mats"].has(key) else _mat(key, p)     # 同類共用一份材質（少切換）
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 4.0
		mi.owner = null                          # 拿出 GLB 場景（避免 owner 不一致警告）
		mi.get_parent().remove_child(mi)
		mi.transform = Transform3D.IDENTITY
		S["mats"][key] = m
		if key == "blade":
			S["blade"] = mi
		elif key in HIT_KEYS:
			if S["hit"] == null:
				S["hit"] = Node3D.new()
			(S["hit"] as Node3D).add_child(mi)
		else:
			arc.add_child(mi)
			S["meshes"].append(mi)
	inst.free()

func _finish_variant(v: String, S: Dictionary) -> void:
	var arc: Node3D = S["arc"]
	arc.visible = false
	add_child(arc)
	S["blade"].visible = false
	sword.add_child(S["blade"])
	S["hit"].visible = false
	add_child(S["hit"])
	S["hit_pool"] = []
	for i in 3:                                # 命中火預先複製 3 份輪流用（每次命中新建節點／材質會卡幀，R9 實測）
		var hm := (S["hit"] as Node3D).duplicate() as Node3D
		for c in hm.get_children():
			var cm := c as MeshInstance3D
			cm.material_override = (cm.material_override as ShaderMaterial).duplicate()
		hm.visible = false
		add_child(hm)
		S["hit_pool"].append(hm)
	S["hit_ix"] = 0
	sets[v] = S

func _mk_particles(n: int, life: float, one_shot: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = n
	p.lifetime = life
	p.one_shot = one_shot
	p.explosiveness = 0.9 if one_shot else 0.0
	p.local_coords = false
	p.emitting = false
	p.visibility_aabb = AABB(Vector3(-6, -6, -6), Vector3(12, 12, 12))
	var pm := ParticleProcessMaterial.new()
	if one_shot:
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = 0.05
		pm.direction = Vector3(0, 0, -1)
		pm.spread = 35.0
		pm.initial_velocity_min = 2.0
		pm.initial_velocity_max = 4.5
	else:
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = Vector3(0.012, 0.22, 0.012)
		pm.direction = Vector3(0, 1, 0)
		pm.spread = 120.0
		pm.initial_velocity_min = 0.5
		pm.initial_velocity_max = 1.8
		pm.inherit_velocity_ratio = 0.10
	pm.gravity = Vector3(0, -3.0, 0)
	pm.damping_min = 1.5
	pm.damping_max = 3.0
	pm.scale_min = 0.5
	pm.scale_max = 1.3
	pm.particle_flag_align_y = true               # 水滴形沿速度方向拉長
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.92, 0.6, 1.0))
	g.set_color(1, Color(0.8, 0.15, 0.03, 0.0))
	g.add_point(0.4, Color(1.0, 0.55, 0.12, 1.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.025, 0.06)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.billboard_keep_scale = true
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = TEX_EMBER
	m.uv1_scale = Vector3(0.25, 1, 1)
	m.uv1_offset = Vector3(0.25, 0, 0)          # 圖集第 2 格：水滴
	m.albedo_color = Color(1.4, 1.1, 0.7, 1.0)
	q.material = m
	p.draw_pass_1 = q
	return p

## 預熱：每個版本畫一幀（透明度 0），讓管線在第一次出招前就編好
func prewarm() -> void:
	for v in sets:
		var S: Dictionary = sets[v]
		(S["arc"] as Node3D).visible = true
		for m in (S["mats"] as Dictionary).values():
			(m as ShaderMaterial).set_shader_parameter("intensity", 0.0)

func end_prewarm() -> void:
	for v in sets:
		var S: Dictionary = sets[v]
		(S["arc"] as Node3D).visible = false
		for m in (S["mats"] as Dictionary).values():
			(m as ShaderMaterial).set_shader_parameter("intensity", 1.0)

func begin(v: String) -> void:
	if not sets.has(v):
		return
	if cur != "" and cur != v:
		_hide(cur)
	cur = v
	active = true
	frozen = false
	skill_t = 0.0
	var S: Dictionary = sets[v]
	var arc: Node3D = S["arc"]
	if arc.get_parent() != actor:
		arc.get_parent().remove_child(arc)
		actor.add_child(arc)
	arc.top_level = false
	arc.transform = Transform3D.IDENTITY
	arc.visible = enabled
	(S["blade"] as MeshInstance3D).visible = enabled
	for m in (S["mats"] as Dictionary).values():
		(m as ShaderMaterial).set_shader_parameter("intensity", 1.0)
		var f0 = (m as ShaderMaterial).get_shader_parameter("ignite_from")
		if f0 != null and float(f0) > 0.0:
			(m as ShaderMaterial).set_shader_parameter("ignite_t", float(f0))   # 沒命中＝照設計時間點燃
	_ignited = false
	_path.clear()
	_hit_age = -1.0
	_rel_age = -1.0

func _hide(v: String) -> void:
	var S: Dictionary = sets[v]
	(S["arc"] as Node3D).visible = false
	(S["blade"] as MeshInstance3D).visible = false

func end() -> void:
	active = false

static func _env(pts: Array, t: float) -> float:
	if pts.is_empty():
		return 0.0
	if t <= float(pts[0][0]):
		return float(pts[0][1])
	for i in range(1, pts.size()):
		if t <= float(pts[i][0]):
			var a: Array = pts[i - 1]
			var b: Array = pts[i]
			return lerpf(float(a[1]), float(b[1]), smoothstep(0.0, 1.0, (t - float(a[0])) / maxf(float(b[0]) - float(a[0]), 1e-4)))
	return float(pts[pts.size() - 1][1])

## 每幀（骨架更新後）：t＝技能時間（shot_t；技能結束後由呼叫端用真實時間續走，讓殘焰燒完）
func frame(t: float, dt: float, tip_speed: float) -> void:
	if cur == "":
		return
	var S: Dictionary = sets[cur]
	var p: Dictionary = S["params"]
	skill_t = t
	var arc: Node3D = S["arc"]
	if not frozen and t >= float(p.get("freeze_t", 0.70)):
		frozen = true
		var g := arc.global_transform
		arc.top_level = true                   # 主斬結束：殘焰留在世界中原地消散（不再跟著角色收勢移動）
		arc.global_transform = g
	var L: Dictionary = p.get("lights", {})
	if L.is_empty():
		flare = move_toward(flare, 0.0, dt / 0.12)
		light_t += dt
		var hl: Dictionary = p.get("hit_light", {})
		var le := float(hl.get("energy", 0.0)) * maxf(0.0, 1.0 - light_t / float(hl.get("time", 0.16))) if enabled else 0.0
		hit_light.light_energy = le
		hit_light.visible = le > 0.01
		_rig_off()
	else:
		if not hitstop:                       # R9-C3：Hit Stop 期間火焰脈衝停在峰值，放開才衰減
			flare = move_toward(flare, 0.0, dt / float(L.get("flare_time", 0.12)))
		_lights(t, dt, S, L)
	var fl := flare * float(L.get("flare_gain", 1.0))
	for m in (S["mats"] as Dictionary).values():
		(m as ShaderMaterial).set_shader_parameter("skill_t", t)
		(m as ShaderMaterial).set_shader_parameter("flare", fl)
	var dw := smoothstep(float(p.get("drift_from", 0.64)), float(p.get("drift_to", 1.0)), t)
	for mi in S["meshes"]:
		var mm := mi as MeshInstance3D
		if mm.mesh and mm.mesh.get_blend_shape_count() > 0:
			mm.set_blend_shape_value(0, dw)
	(S["mats"]["blade"] as ShaderMaterial).set_shader_parameter("intensity", _env(p.get("blade_env", []), t) if active else 0.0)
	var done: bool = t > float(p.get("end_t", 1.6))
	arc.visible = enabled and not done
	(S["blade"] as MeshInstance3D).visible = enabled and active
	# 火星：只在高速斬擊段、依刀尖速度
	var sp: Dictionary = p.get("sparks", {})
	var on := enabled and active and t >= float(sp.get("from", 0.5)) and t <= float(sp.get("to", 0.72))
	var ratio := clampf((tip_speed - float(sp.get("min_speed", 10.0))) / 20.0, 0.0, 1.0) if on else 0.0
	var sw := sword.global_transform
	sparks.global_transform = Transform3D(sw.basis.orthonormalized(), sw * Vector3(0, 0.75, 0))
	sparks.amount_ratio = ratio * float(sp.get("max_ratio", 0.6))
	sparks.emitting = ratio > 0.01
	# 命中火：真實時間
	var i := 0
	while i < _hits.size():
		var h: Dictionary = _hits[i]
		h["t"] = float(h["t"]) + dt
		var ht := float(h["t"])
		for c in (h["mi"] as Node3D).get_children():
			var cm := c as MeshInstance3D
			(cm.material_override as ShaderMaterial).set_shader_parameter("skill_t", ht)
			if cm.mesh and cm.mesh.get_blend_shape_count() > 0:
				cm.set_blend_shape_value(0, 1.0 - pow(1.0 - clampf(ht / float(p.get("hitring_t", 0.22)), 0.0, 1.0), 2.0))
		if ht > 0.6:
			(h["mi"] as Node3D).visible = false
			_hits.remove_at(i)
		else:
			i += 1

## 命中：pos＝刀刃切入點、dir＝刀的行進方向、normal＝目標表面往外
func hit(pos: Vector3, dir: Vector3, normal := Vector3.ZERO) -> void:
	if cur == "" or not enabled:
		return
	var S: Dictionary = sets[cur]
	var d := dir.normalized() if dir.length() > 0.1 else Vector3.DOWN
	var nrm := normal.normalized() if normal.length() > 0.1 else -d
	var z := (d * 0.6 + nrm * 0.8).normalized()
	var up := Vector3.UP if absf(z.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var pool: Array = S["hit_pool"]
	var mi: Node3D = pool[int(S["hit_ix"]) % pool.size()]
	S["hit_ix"] = int(S["hit_ix"]) + 1
	for h0 in _hits:
		if h0["mi"] == mi:
			_hits.erase(h0)
			break
	mi.visible = true
	var p: Dictionary = S["params"]
	mi.global_transform = Transform3D(Basis.looking_at(-z, up).scaled(Vector3.ONE * float(p.get("hit_scale", 1.0))), pos + nrm * float(p.get("hit_off", 0.08)))
	if not _ignited:                             # R9-C2：第一次命中＝點燃時刻（停格畫面就是點燃的那一格）
		_ignited = true
		for m in (S["mats"] as Dictionary).values():
			var f0 = (m as ShaderMaterial).get_shader_parameter("ignite_from")
			if f0 != null and float(f0) > 0.0 and skill_t <= float(f0) + 0.03:
				(m as ShaderMaterial).set_shader_parameter("ignite_t", minf(skill_t, float(f0)))
	flare = 1.0                                  # 命中拍點：整體火焰亮度瞬間抬高、0.12 s 退回
	for c in mi.get_children():
		((c as MeshInstance3D).material_override as ShaderMaterial).set_shader_parameter("skill_t", 0.0)
	_hits.append({"mi": mi, "t": 0.0})
	var hl: Dictionary = p.get("hit_light", {})
	hit_light.omni_range = float(hl.get("range", 3.0))
	hit_light.global_position = pos + nrm * 0.35
	light_t = 0.0
	_hit_age = 0.0
	_rel_age = -1.0
	_hit_pos = pos
	_hit_nrm = nrm
	burst.global_transform = Transform3D(Basis.looking_at(z, up), pos + nrm * 0.03)
	burst.restart()
	burst.emitting = true
	hits_spawned += 1

# ------------------------------------------------------------------ R9-C3 動態光照
static func _col(a: Variant, d: Color) -> Color:
	if a is Array and (a as Array).size() >= 3:
		return Color(float(a[0]), float(a[1]), float(a[2]))
	return d

func _flk(k: float, ph: float) -> float:
	var f := _flick
	return maxf(0.0, 1.0 + k * (0.55 * sin(f * 37.0 + ph * 2.1) + 0.3 * sin(f * 21.3 + ph) + 0.15 * sin(f * 63.0 + ph * 3.7)))

func _set_light(l: OmniLight3D, pos: Vector3, e: float, D: Dictionary, col: Color) -> void:
	l.global_position = pos
	l.light_energy = e
	l.visible = e > 0.01
	l.omni_range = float(D.get("range", 3.0))
	l.omni_attenuation = float(D.get("attn", 1.0))
	l.light_specular = float(D.get("spec", 0.5))
	l.light_color = col

func _rig_off() -> void:
	for l in [blade_light, ember_light] + trail_lights:
		(l as OmniLight3D).light_energy = 0.0
		(l as OmniLight3D).visible = false
	haze.visible = false
	_ls = {}

## arc 本地刀路上「技能時間 tq」的位置（世界座標）
func _path_at(tq: float, arc: Node3D) -> Variant:
	if _path.is_empty():
		return null
	var i := _path.size() - 1
	while i > 0 and float(_path[i][0]) > tq:
		i -= 1
	return arc.global_transform * (_path[i][1] as Vector3)

func _lights(t: float, dt: float, S: Dictionary, L: Dictionary) -> void:
	var p: Dictionary = S["params"]
	var arc: Node3D = S["arc"]
	if not hitstop:
		_flick += dt
	var on := enabled
	# 1. 刀身火光
	var B: Dictionary = L.get("blade", {})
	var mid := sword.global_transform * Vector3(0, float(B.get("pos_u", 0.6)), 0)
	var lft := float(p.get("light_freeze_t", p.get("freeze_t", 0.70)))   # R12（選用）：火焰網格一開始就固定在世界（freeze_t 0），火焰體光仍沿刀路走到這個時間
	if active and t < lft:
		_path.append([t, arc.global_transform.affine_inverse() * mid])
	var be := float(B.get("energy", 0.0)) * _env(B.get("env", []), t) * _flk(float(B.get("flicker", 0.1)), 0.0) if (on and active) else 0.0
	_set_light(blade_light, mid, be, B, _col(B.get("color"), Color(1.0, 0.62, 0.25)))
	# 2. 火焰體光：主斬結束（freeze_t）後位置固定
	var T: Dictionary = L.get("trail", {})
	var lags: Array = T.get("lag", [0.06, 0.14])
	var tq := minf(t, lft)
	var te_sum := 0.0
	for i in trail_lights.size():
		var pos = _path_at(tq - float(lags[i]), arc)
		if pos != null:
			pos.y = maxf(pos.y, float(T.get("min_y", 0.0)))     # 火焰體光不貼地（貼地會在地面燒出一大片亮斑）
		var te := 0.0
		if on and pos != null:
			te = float(T.get("energy", 0.0)) * _env(T.get("env", []), t) * _flk(float(T.get("flicker", 0.2)), 1.7 + float(i))
		_set_light(trail_lights[i], pos if pos != null else Vector3.ZERO, te, T, _col(T.get("color"), Color(1.0, 0.42, 0.12)))
		te_sum += te
	# 3. 命中光：停格中＝白金強光；放開後轉橘紅爆燃再衰減（真實時間）
	var H: Dictionary = L.get("hit", {})
	var he := 0.0
	var hc := _col(H.get("flash_col"), Color(1.0, 0.92, 0.75))
	var ee := 0.0
	var hz := 0.0
	if _hit_age >= 0.0:
		_hit_age += dt
		if _rel_age < 0.0 and not hitstop and _hit_age >= float(H.get("min_flash", 0.05)):
			_rel_age = 0.0
		elif _rel_age >= 0.0:
			_rel_age += dt
		var fe := float(H.get("flash_e", 0.0))
		if _rel_age < 0.0:
			he = fe
		else:
			var xf := float(H.get("xfade", 0.06))
			var k := clampf(_rel_age / xf, 0.0, 1.0)
			hc = hc.lerp(_col(H.get("burn_col"), Color(1.0, 0.42, 0.12)), k)
			he = lerpf(fe, float(H.get("burn_e", 0.0)), k) * (1.0 - smoothstep(0.0, float(H.get("burn_t", 0.3)), maxf(_rel_age - xf, 0.0)))
			he *= _flk(float(H.get("flicker", 0.15)), 4.2)
		var E: Dictionary = L.get("ember", {})
		if not E.is_empty() and _rel_age >= 0.0:
			var a := _rel_age
			ee = float(E.get("energy", 0.0)) * smoothstep(0.0, 0.08, a) * (1.0 - smoothstep(0.0, float(E.get("time", 0.7)), a)) * _flk(float(E.get("flicker", 0.3)), 6.1)
		var Z: Dictionary = L.get("haze", {})
		if not Z.is_empty():
			hz = float(Z.get("strength", 1.0)) * (1.0 if _rel_age < 0.0 else 1.0 - smoothstep(0.0, float(Z.get("time", 0.45)), _rel_age))
		if _hit_age > 2.0:
			_hit_age = -1.0
	if not on:
		he = 0.0
		ee = 0.0
		hz = 0.0
	_set_light(hit_light, _hit_pos + _hit_nrm * float(H.get("off", 0.35)) + Vector3(0, float(H.get("up", 0.0)), 0), he, H, hc)
	var E2: Dictionary = L.get("ember", {})
	var gp := _hit_pos + _hit_nrm * float(E2.get("off", 0.3))
	gp.y = maxf(float(E2.get("y", 0.35)), 0.05)
	_set_light(ember_light, gp, ee, E2, _col(E2.get("color"), Color(1.0, 0.28, 0.06)))
	haze.visible = hz > 0.01
	if haze.visible:
		var Z2: Dictionary = L.get("haze", {})
		var hp := _hit_pos + _hit_nrm * float(Z2.get("off", 0.15)) + Vector3(0, float(Z2.get("up", 0.35)), 0)
		var sz := float(Z2.get("size", 1.1))
		haze.global_transform = Transform3D(cam.global_basis.scaled(Vector3(sz, sz * 1.4, 1.0)), hp)   # 面向鏡頭
		var hm := haze.material_override as ShaderMaterial
		hm.set_shader_parameter("strength", hz)
		hm.set_shader_parameter("amount", float(Z2.get("amount", 0.006)))
		hm.set_shader_parameter("flow_t", _flick)
	_ls = {"be": snappedf(be, 0.001), "bp": [snappedf(mid.x, 0.001), snappedf(mid.y, 0.001), snappedf(mid.z, 0.001)], "te": snappedf(te_sum, 0.001),
		"tp0": [snappedf(trail_lights[0].global_position.x, 0.001), snappedf(trail_lights[0].global_position.y, 0.001), snappedf(trail_lights[0].global_position.z, 0.001)],
		"he": snappedf(he, 0.001), "hc": [snappedf(hc.r, 0.001), snappedf(hc.g, 0.001), snappedf(hc.b, 0.001)], "ee": snappedf(ee, 0.001), "hz": snappedf(hz, 0.001),
		"vis": int(blade_light.visible) + int(trail_lights[0].visible) + int(trail_lights[1].visible) + int(hit_light.visible) + int(ember_light.visible), "flare": snappedf(flare, 0.001)}

func light_state() -> Dictionary:
	return _ls

func light_count() -> int:
	return find_children("*", "Light3D", true, false).size()

func stats() -> Dictionary:
	var verts := 0
	if cur != "":
		for mi in sets[cur]["meshes"]:
			if (mi as MeshInstance3D).visible:
				verts += ((mi as MeshInstance3D).mesh as ArrayMesh).surface_get_array_len(0)
	return {"sparks_est": int(round(sparks.amount * sparks.amount_ratio)) if sparks.emitting else 0, "hit_particles": burst.amount if burst.emitting else 0,
		"trail_samples": verts, "hits": _hits.size()}

extends Node3D
## R16 日之呼吸「招式主特效」（AOE 視覺）：sun_fire.gd 的子模組（同一套統一火焰系統，不是平行系統）。
## 只在 sun_fire_profiles.json 該型 profile 有 "aoe" 時運作；沒有 aoe 的 profile（R9–R15 全部）完全不受影響。
## 技能時間軸驅動：sun_fire.frame() 每幀把技能時間與 Hit Stop（freeze）傳進來，Hit Stop 時所有主特效一起凍結。
## 物件（profile.aoe.items，notes/r16/r16lib.py 產生）：
##   crescent＝大型弧形火焰斬：沿該刀「實際刀路平面」依掃掠時間展開、放大、往前推進、撕裂消散（不逐點貼刀尖）；
##   vortex＝往前噴射的火焰旋流；burst＝爆燃（on_hit＝實際命中那一刀時才在命中點生成）；
##   dragon＝龍頭在蓄勢時成形 → 瞬步時在角色前方帶路、龍身沿實際走過的路線拖出 → 收尾爆燃後由尾往頭燒散；
##   swirl（R16b）＝數道彼此分離的火焰，各自沿不同的螺旋軌跡繞同一軸旋轉、往前推進、往外散開、在不同時間撕裂消散（不是封閉的火龍捲）；
##          spin 0＋小半徑＝直線火焰（一閃的光帶、陽華突的突刺）。
## 淡粉紅火舌末端（R16b）：每個物件的 pink（沒有就用 spec.pink；sun_fire.gd 會把 profile.pink 帶進來），0＝關。
## 位置＝生成當下角色的變換 × 物件的角色本地座標（被牆擋住、依實際目標繞行時也不會錯位），生成後留在世界原地演完。
## 只是視覺：不做判定，不改傷害、半徑、擊退、多目標。
const SH := preload("res://characters/yoriichi/v24_isshin/fire_research_v2/sun_fire_aoe.gdshader")
const NOISE := preload("res://characters/yoriichi/v24_isshin/fire_research_v2/fire_noise_v2.png")
const HEAD_GLB := "res://assets/vfx/sun_dragon_head_r16.glb"
const BIG_AABB := AABB(Vector3(-12, -12, -12), Vector3(24, 24, 24))
const PRI_OUTER := -3
const PRI_CORE := -2
## R16g 灼骨炎陽「日輪渦」（type shakkotsu_sun）：profile 物件可覆寫的著色器參數（ss_<key>）
const SUN_KEYS := ["turns", "r_in", "r_out", "up", "w_in", "w_out", "z_in", "z_out", "spin", "th0", "open0", "open1", "break", "flare", "gap", "flash"]

var actor: Node3D
var cam: Camera3D
var ember: Callable                      # (pos, vel) -> 由 sun_fire 的火星粒子池噴一顆
var spec := {}
var items: Array = []                    # {d, state(0 等待/1 演出/2 結束), age, nodes, mats, xf, ...}
var accepting := false
var light: OmniLight3D
var _mesh := {}
var _head_mesh: Mesh
var _t := 0.0
var _pending: Array = []                 # 這一幀新生成的物件（龍的收尾爆燃），迴圈結束後才併入 items
var spawned := 0                         # 檢查用
var _warm: MeshInstance3D               # 預熱：開場畫幾幀讓著色器先編譯（第一次出招不卡）
var _warm_frames := 0
var _warm2: MeshInstance3D
var peak_items := 0
var _skel: Skeleton3D                    # follow＝"hips" 的物件跟著髖部走（火車 R16b：火輪隨翻轉的身體一起往前）
var _hips_ix := -1
var blade_xf := Transform3D.IDENTITY
var visual_target: Callable
var projectile_log: Array = []
var _frozen := false


# R16d opt-in finisher projectile: only the last-cut timeline item can launch it.
# Physics sweeps stop at walls before testing the visual target, and never deal damage.
func _launch_projectile(it: Dictionary) -> void:
	var d: Dictionary = it["d"].duplicate(true)
	var p := blade_xf * Vector3(0, 0.72, 0)
	var aim := actor.global_basis.z.normalized()
	if visual_target.is_valid():
		var tg: Vector3 = visual_target.call()
		if p.distance_to(tg) > 0.01:
			aim = p.direction_to(tg)
	var up := Vector3.UP if absf(aim.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var bx := up.cross(aim).normalized()
	var xf := Transform3D(Basis(bx, aim.cross(bx).normalized(), aim), p)
	d["type"] = "swirl"
	it["d"] = d
	_spawn(it, xf)
	# A compact irregular flame body in front of the trailing swirl, reusing the burst mesh/shader.
	var body := {"d":{"type":"burst", "life":d["life"], "size":0.95, "spread":1.65, "tongues":7,
		"tear":0.7,"gain":0.85,"pink":0.15,"hot":0.55,"seed":444.0},"state":0,"age":0.0,"nodes":[],"mats":[]}
	_spawn(body, xf)
	(it["nodes"] as Array).append_array(body["nodes"])
	(it["mats"] as Array).append_array(body["mats"])
	it["projectile"] = true
	it["p"] = p
	it["direction"] = aim
	it["distance"] = 0.0
	it["launch_check"] = actor.global_position + Vector3(0,1.1,0)
	projectile_log.append({"event": "launch", "t": _t, "pos": [p.x,p.y,p.z]})

func _physics_process(dt: float) -> void:
	if _frozen:
		return
	for it in items:
		if not bool(it.get("projectile", false)) or int(it["state"]) != 1:
			continue
		var d: Dictionary = it["d"]
		var p: Vector3 = it["p"]
		var dir: Vector3 = it["direction"]
		var q := p + dir * float(d.get("speed", 9.0)) * dt
		# Continuous segment sweep; wall layer belongs to the existing dojo.
		var start: Vector3 = it.get("launch_check", p)
		it.erase("launch_check")
		var query := PhysicsRayQueryParameters3D.create(start, q, 1 << 4)
		query.hit_from_inside = true
		var wall := get_world_3d().direct_space_state.intersect_ray(query)
		var stop := q
		if not wall.is_empty():
			stop = wall["position"]
		var target_hit := false
		if visual_target.is_valid():
			var target: Vector3 = visual_target.call()
			var seg := stop - p
			var u := clampf((target-p).dot(seg) / maxf(seg.length_squared(), 0.000001), 0.0, 1.0)
			var cp := p + seg*u
			# A visual proxy only (dummy has no physics body); never changes blade judgement.
			if cp.distance_to(target) < 0.48:
				stop = cp
				target_hit = true
		var travel := p.distance_to(stop)
		it["distance"] = float(it["distance"]) + travel
		it["p"] = stop
		it["center"] = stop
		for node: Node3D in it["nodes"]:
			node.global_position = stop
		if target_hit or not wall.is_empty():
			_projectile_impact(it, stop, "target" if target_hit else "wall")
		elif float(it["distance"]) >= float(d.get("range", 9.0)):
			projectile_log.append({"event":"miss", "distance": it["distance"]})
			_kill(it)

func _projectile_impact(it: Dictionary, p: Vector3, reason: String) -> void:
	var dir: Vector3 = it["direction"]
	var xf: Transform3D = it["xf"]
	xf.origin = p - dir*0.08
	var burst := {"d": {"type":"burst", "name":"finisher_impact", "life":0.48, "size":3.3, "spread":1.5, "tongues":11,
		"gain":0.95, "tear":0.24, "pink":0.22, "seed":442.0, "hot":0.55}, "state":0, "age":0.0,"nodes":[],"mats":[]}
	_spawn(burst, xf)
	_pending.append(burst)
	projectile_log.append({"event":reason, "age":it["age"], "distance":it["distance"], "pos":[p.x,p.y,p.z]})
	_kill(it)

func setup(actor_: Node3D, cam_: Camera3D = null) -> void:
	actor = actor_
	cam = cam_
	var sks := actor.find_children("*", "Skeleton3D", true, false)
	if not sks.is_empty():
		_skel = sks[0] as Skeleton3D
		_hips_ix = _skel.find_bone("mixamorig_Hips")
	top_level = true
	global_transform = Transform3D.IDENTITY
	light = OmniLight3D.new()
	light.name = "AoeLight"
	light.shadow_enabled = false
	light.light_energy = 0.0
	light.omni_attenuation = 1.6
	light.visible = false
	add_child(light)
	if ResourceLoader.exists(HEAD_GLB):
		var ps := load(HEAD_GLB) as PackedScene
		if ps:
			var inst := ps.instantiate()
			for mi: MeshInstance3D in inst.find_children("*", "MeshInstance3D", true, false):
				_head_mesh = mi.mesh
				break
			inst.free()
	# 預熱兩種頂點格式（參數網格；龍頭／龍身網格），放在鏡頭正前方畫 30 幀：放在角色身上時若不在畫面內不會被畫到、不會編譯
	_warm = _mi(_grid("crescent", 1, 72, 10), _mat(0, 0.0, {"life": 1.0}), Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.01), Vector3.ZERO))
	(_warm.material_override as ShaderMaterial).set_shader_parameter("age", 0.05)
	if _head_mesh:
		_warm2 = _mi(_head_mesh, _mat(3, 1.0, {"life": 99.0}), Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.01), Vector3.ZERO))
	_warm_frames = 30

func _process(_dt: float) -> void:
	if _warm:
		var p := actor.global_position + Vector3(0, 1.2, 0)
		if cam:
			p = cam.global_position - cam.global_basis.z * 1.5
		_warm.global_position = p
		if _warm2:
			_warm2.global_position = p + Vector3(0.02, 0, 0)
		_warm_frames -= 1
		if _warm_frames <= 0:
			_warm.queue_free()
			_warm = null
			if _warm2:
				_warm2.queue_free()
				_warm2 = null

func begin(sp: Dictionary) -> void:
	clear()
	spec = sp
	accepting = not sp.is_empty()
	for d in sp.get("items", []):
		items.append({"d": d, "state": 0, "age": 0.0, "nodes": [], "mats": []})

## 招式結束或中斷：不再生成新的；已生成的照壽命演完（龍：直接開始燒散）
func end() -> void:
	accepting = false
	for it in items:
		if bool(it.get("projectile", false)) and int(it["state"]) == 1:
			projectile_log.append({"event": "cancel", "age": it["age"]})
			_kill(it)
	for it in items:
		if int(it["state"]) == 1 and str((it["d"] as Dictionary)["type"]) == "dragon" and float(it.get("burn_at", -1.0)) < 0.0:
			it["burn_at"] = float(it["age"])

func clear() -> void:
	accepting = false
	for it in items:
		for n: Node in it["nodes"]:
			if is_instance_valid(n):
				n.queue_free()
	items.clear()
	if light:
		light.light_energy = 0.0
		light.visible = false

func is_busy() -> bool:
	for it in items:
		if int(it["state"]) < 2:
			return true
	return false

## 實際命中（sun_fire.hit 去重後）：on_hit＝該刀序號的 burst 在命中點生成
func hit(pos: Vector3, dir: Vector3, strike: int) -> void:
	for it in items:
		var d: Dictionary = it["d"]
		if int(it["state"]) != 0 or str(d["type"]) != "burst" or typeof(d.get("on_hit", false)) == TYPE_BOOL:
			continue
		if int(d["on_hit"]) != strike:
			continue
		var up := Vector3.UP
		var f := dir
		f.y = 0.0
		if f.length() < 0.1:
			f = actor.global_basis.z
		f = f.normalized()
		var xf := Transform3D(Basis(up.cross(f).normalized(), up, f), pos)
		_spawn(it, xf)

# ------------------------------------------------------------------ 每幀
func frame(skill_t: float, dt: float, freeze: bool, enabled: bool) -> void:
	if items.is_empty():
		return
	_frozen = freeze
	var adt := 0.0 if freeze else dt
	_t = skill_t
	var lp := Vector3.ZERO
	var lw := 0.0
	var le := 0.0
	var alive := 0
	for it in items:
		var d: Dictionary = it["d"]
		var st := int(it["state"])
		if st == 0:
			if accepting and typeof(d.get("on_hit", false)) == TYPE_BOOL and skill_t >= float(d["t0"]):
				var xf := _place(d)
				if str(d["type"]) == "finisher_projectile":
					_launch_projectile(it)
				else:
					_spawn(it, xf)
				st = 1
			else:
				continue
		if st != 1:
			continue
		it["age"] = float(it["age"]) + adt
		var age := float(it["age"])
		if d.has("follow") and skill_t <= float(d.get("follow_until", 99.0)) and str(d["type"]) != "dragon":
			var fx := _place(d)
			for nd: Node3D in it["nodes"]:
				nd.global_transform = fx
			it["center"] = fx.origin
		var e := 0.0
		if str(d["type"]) == "dragon":
			e = _dragon_frame(it, skill_t, adt)
			if int(it["state"]) != 1:
				continue
		else:
			var lf := float(d["life"])
			for m: ShaderMaterial in it["mats"]:
				m.set_shader_parameter("age", age)
			e = smoothstep(0.0, 0.06, age) * (1.0 - smoothstep(float(d.get("tear", 0.5)) * lf, lf, age)) * float(d.get("gain", 1.0))
			if not bool(it.get("embers", false)) and age >= float(d.get("tear", 0.5)) * lf:
				it["embers"] = true
				_embers(it, 10)
			if age >= lf:
				if bool(it.get("projectile", false)):
					projectile_log.append({"event":"expired", "age":age, "distance":it.get("distance",0.0)})
				_kill(it)
				continue
		for n: Node3D in it["nodes"]:
			n.visible = enabled
		alive += 1
		var c: Vector3 = it.get("center", Vector3.ZERO)
		lp += c * e
		lw += e
		le = maxf(le, e)
	if not _pending.is_empty():
		items.append_array(_pending)
		_pending.clear()
	peak_items = maxi(peak_items, alive)
	var lg: Dictionary = spec.get("light", {})
	if lw > 0.01 and enabled and not lg.is_empty():
		light.visible = true
		light.global_position = lp / lw + Vector3(0, 0.3, 0)
		light.light_energy = float(lg.get("peak", 2.5)) * clampf(le, 0.0, 1.5)
		light.omni_range = float(lg.get("range", 7.0))
		var cc: Array = lg.get("color", [1.0, 0.55, 0.2])
		light.light_color = Color(float(cc[0]), float(cc[1]), float(cc[2]))
	else:
		light.light_energy = 0.0
		light.visible = false

## 生成／跟隨的位置：角色變換 × 物件本地座標；follow＝"hips" 時原點改用髖部骨頭的世界位置（＋角色朝向下的 o 偏移）
func _place(d: Dictionary) -> Transform3D:
	var axf := actor.global_transform
	if str(d.get("follow", "")) == "hips" and _skel and _hips_ix >= 0:
		var hp := _skel.global_transform * _skel.get_bone_global_pose(_hips_ix).origin
		return Transform3D(axf.basis * _basis(d), hp + axf.basis * _v3(d["o"]))
	return axf * Transform3D(_basis(d), _v3(d["o"]))

func _kill(it: Dictionary) -> void:
	it["state"] = 2
	for n: Node in it["nodes"]:
		if is_instance_valid(n):
			n.queue_free()
	it["nodes"] = []
	it["mats"] = []

func _v3(a) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))

func _basis(d: Dictionary) -> Basis:
	if not d.has("x"):
		return Basis.IDENTITY
	return Basis(_v3(d["x"]), _v3(d["y"]), _v3(d["z"])).orthonormalized()

func _mat(shape: int, core: float, d: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SH
	m.render_priority = (PRI_CORE if core > 0.5 else PRI_OUTER) + int(d.get("pri", 0))   # R16c：pri -1＝外焰層畫在主火焰後面
	m.set_shader_parameter("noise_tex", NOISE)
	m.set_shader_parameter("shape", shape)
	m.set_shader_parameter("core", core)
	m.set_shader_parameter("life", float(d.get("life", 1.0)))
	m.set_shader_parameter("tear", float(d.get("tear", 0.5)))
	m.set_shader_parameter("gain", float(d.get("gain", 1.0)) * (1.15 if core > 0.5 else 1.0))
	m.set_shader_parameter("seed", float(d.get("seed", 0.0)) + core * 3.7)
	m.set_shader_parameter("pink", float(d.get("pink", spec.get("pink", 0.0))))
	m.set_shader_parameter("hot", float(d.get("hot", spec.get("hot", 1.0))))   # R16b：沒設＝1＝R16 原樣
	# R16b 第二輪：style 1＝風格化火焰（火舌、分岔、撕裂、尖端淡粉紅）；沒設＝0＝R16 原樣。火舌參數可逐物件覆寫
	m.set_shader_parameter("style", int(d.get("style", spec.get("style", 0))))
	for k in ["t_space", "t_len", "t_lean", "t_fork", "t_pinksel", "t_body"]:
		if d.has(k) or spec.has(k):
			m.set_shader_parameter(k, float(d.get(k, spec.get(k))))
	m.set_shader_parameter("wreath_enrich", float(d.get("enrich", 0.0)))
	m.set_shader_parameter("wreath_speed", float(d.get("vfx_speed", 1.0)))
	m.set_shader_parameter("heat_mul", float(d.get("heat", 1.0)))   # R16c：沒設＝1＝原樣
	m.set_shader_parameter("age", 0.0)
	return m

func _mi(mesh: Mesh, m: ShaderMaterial, xf: Transform3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 8.0
	add_child(mi)
	mi.global_transform = xf
	return mi

func _spawn(it: Dictionary, xf: Transform3D) -> void:
	var d: Dictionary = it["d"]
	it["state"] = 1
	it["age"] = 0.0
	it["xf"] = xf
	spawned += 1
	var ty := str(d["type"])
	if ty == "dragon":
		_dragon_spawn(it, xf)
		return
	if ty == "shakkotsu_sun":
		_sun_spawn(it, xf)
		return
	var shape := 0
	var mesh: Mesh
	if ty == "crescent":
		shape = 0
		mesh = _grid("crescent", 1, 72, 10)
	elif ty == "vortex":
		shape = 1
		mesh = _grid("vortex", int(d.get("bands", 4)) + 1, 110, 8)
	elif ty == "shakkotsu_wreath":
		shape = 5
		mesh = _grid("shakkotsu_wreath", 2, 112, 12)
	elif ty == "swirl":
		shape = 4
		mesh = _grid("swirl", int(d.get("streaks", 6)), 56, 8)
	else:
		shape = 2
		mesh = _grid("burst", int(d.get("tongues", 14)), 12, 8)
	var layers := int(d.get("layers", 2))       # R16c：1＝只有外層（外焰層用）；現有物件都是 2
	for li in layers:
		var core := float(li)
		var m := _mat(shape, core, d)
		match shape:
			0:
				m.set_shader_parameter("a0", deg_to_rad(float(d["a0"])))
				m.set_shader_parameter("a1", deg_to_rad(float(d["a1"])))
				m.set_shader_parameter("reveal_s", maxf(float(d.get("reveal", 0.15)) * (float(d["a1"]) - float(d["a0"])) / maxf(float(d.get("cut_a1", d["a1"])), 1.0), 0.02))
				m.set_shader_parameter("r0", float(d["r"]))
				m.set_shader_parameter("r1", float(d["r_end"]))
				m.set_shader_parameter("width", float(d.get("width", 0.6)))
				m.set_shader_parameter("thick", float(d.get("thick", 0.3)))
				var tr := _v3(d.get("travel", [0, 0, 0]))
				m.set_shader_parameter("travel", _basis(d).inverse() * tr)
			1:
				m.set_shader_parameter("v_len", float(d.get("length", 7.0)))
				m.set_shader_parameter("jet", float(d.get("jet", 0.45)))
				m.set_shader_parameter("vr0", float(d.get("r0", 0.4)))
				m.set_shader_parameter("vr1", float(d.get("r1", 1.7)))
				m.set_shader_parameter("turns", float(d.get("turns", 2.5)))
				m.set_shader_parameter("spin", float(d.get("spin", 2.2)))
				m.set_shader_parameter("bands", float(d.get("bands", 4)))
			2:
				m.set_shader_parameter("b_size", float(d.get("size", 1.6)))
				m.set_shader_parameter("spread", float(d.get("spread", 1.0)))
				m.set_shader_parameter("flatten", float(d.get("flat", 0.0)))
				m.set_shader_parameter("tongues", float(d.get("tongues", 14)))
			4:
				m.set_shader_parameter("sw_n", float(d.get("streaks", 6)))
				m.set_shader_parameter("sw_r0", float(d.get("r0", 0.45)))
				m.set_shader_parameter("sw_r1", float(d.get("r1", 1.5)))
				m.set_shader_parameter("sw_len", float(d.get("length", 3.2)))
				m.set_shader_parameter("sw_jet", float(d.get("jet", 0.35)))
				m.set_shader_parameter("sw_spin", float(d.get("spin", 1.5)))
				m.set_shader_parameter("sw_span", float(d.get("span", 2.0)))
				m.set_shader_parameter("sw_w", float(d.get("width", 0.3)))
				m.set_shader_parameter("sw_stag", float(d.get("stagger", 0.12)))
				m.set_shader_parameter("sw_var", float(d.get("var", 1.0)))
				m.set_shader_parameter("sw_slow", float(d.get("slow", 0.35)))
				m.set_shader_parameter("sw_fling", float(d.get("fling", 0.0)))
				m.set_shader_parameter("sw_instant", float(d.get("instant", 0.0)))
				m.set_shader_parameter("sw_th", float(d.get("th", 0.55)))
				m.set_shader_parameter("sw_band", float(d.get("band", 0.0)))
		var mi := _mi(mesh, m, xf)
		(it["nodes"] as Array).append(mi)
		(it["mats"] as Array).append(m)
	var c := xf.origin
	if shape == 1:
		c = xf.origin + xf.basis.z * float(d.get("length", 7.0)) * 0.35
	elif shape == 4:
		c = xf.origin + xf.basis.z * float(d.get("length", 3.2)) * 0.45
	elif shape == 0:
		c = xf.origin + xf.basis * (Vector3(cos(deg_to_rad(float(d["a1"]) * 0.5)), sin(deg_to_rad(float(d["a1"]) * 0.5)), 0.0) * float(d["r"]))
	it["center"] = c

## R16g 灼骨炎陽「日輪渦」：朝相機的星芒／日輪（最先畫）→ 暗紅柔光 → cel 火焰片（一條往內捲約兩圈的火焰帶＋兩條短伴隨細帶，最後畫）。
## 與其他物件同一個技能時鐘、follow、Hit Stop 凍結與燈光；只有 type＝shakkotsu_sun 的物件會走這裡，其他 type 不變。
func _sun_spawn(it: Dictionary, xf: Transform3D) -> void:
	var d: Dictionary = it["d"]
	var spiral := _grid("sun_spiral", 3, 200, 6)
	var parts := [[1, 0.0, spiral], [0, 1.0, spiral], [2, 1.0, _grid("sun_flash", 1, 2, 1)]]
	for pa in parts:
		var m := _mat(6, float(pa[1]), d)
		m.render_priority = [PRI_CORE, PRI_OUTER, PRI_OUTER - 1][int(pa[0])]   # star / disk first, then halo, then the sheet over both
		m.set_shader_parameter("ss_part", int(pa[0]))
		m.set_shader_parameter("gain", float(d.get("gain", 1.0)))
		for k in SUN_KEYS:
			if d.has(k):
				m.set_shader_parameter("ss_" + str(k), float(d[k]))
		m.set_shader_parameter("ss_ground", actor.global_position.y)
		var mi := _mi(pa[2] as Mesh, m, xf)
		(it["nodes"] as Array).append(mi)
		(it["mats"] as Array).append(m)
	it["center"] = xf.origin

func _embers(it: Dictionary, n: int) -> void:
	if not ember.is_valid():
		return
	var c: Vector3 = it.get("center", Vector3.ZERO)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(float((it["d"] as Dictionary).get("seed", 0.0)) * 1000.0) + 17
	for i in n:
		var p := c + Vector3(rng.randf_range(-0.9, 0.9), rng.randf_range(-0.3, 0.7), rng.randf_range(-0.9, 0.9))
		ember.call(p, Vector3(rng.randf_range(-1.2, 1.2), rng.randf_range(0.8, 2.6), rng.randf_range(-1.2, 1.2)))

## 參數網格：count 份 (nu x nv) 格點；UV＝(u 沿長, v 繞截面)，UV2.x＝份序號、UV2.y＝亂數；位置全部由著色器算
func _grid(kind: String, count: int, nu: int, nv: int) -> ArrayMesh:
	var key := "%s:%d" % [kind, count]
	if _mesh.has(key):
		return _mesh[key]
	var pos := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 911
	for k in count:
		var base := pos.size()
		var r := rng.randf()
		for i in nu:
			for j in nv + 1:
				pos.append(Vector3(float(i), float(j), float(k)) * 0.01)
				uv.append(Vector2(float(i) / float(nu - 1), float(j) / float(nv)))
				uv2.append(Vector2(float(k), r))
		for i in nu - 1:
			for j in nv:
				var a := base + i * (nv + 1) + j
				var b := a + nv + 1
				idx.append_array(PackedInt32Array([a, b, a + 1, a + 1, b, b + 1]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pos
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_TEX_UV2] = uv2
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	am.custom_aabb = BIG_AABB
	_mesh[key] = am
	return am

# ------------------------------------------------------------------ 龍（日暈之龍）
func _dragon_spawn(it: Dictionary, xf: Transform3D) -> void:
	var d: Dictionary = it["d"]
	if _head_mesh == null and ResourceLoader.exists(HEAD_GLB):
		var ps := load(HEAD_GLB) as PackedScene
		if ps:
			var inst := ps.instantiate()
			for mi: MeshInstance3D in inst.find_children("*", "MeshInstance3D", true, false):
				_head_mesh = mi.mesh
				break
			inst.free()
	var sc := float(d.get("head_scale", 1.0))
	var head_xf := xf
	var nodes: Array = []
	var mats: Array = []
	if _head_mesh:
		for li in 2:
			var m := _mat(3, 1.0 if li == 0 else 0.0, d)
			m.set_shader_parameter("form_shade", 0.42 if li == 0 else 0.0)
			m.set_shader_parameter("flow", -1.1)
			m.set_shader_parameter("body_len", 2.2)
			m.set_shader_parameter("reveal", 0.0)
			m.set_shader_parameter("life", 99.0)
			m.set_shader_parameter("tear", 0.98)
			m.set_shader_parameter("gain", float(d.get("gain", 1.0)) * (1.05 if li == 0 else 0.95))
			m.set_shader_parameter("erode", 0.0 if li == 0 else 0.38)
			var mi := _mi(_head_mesh, m, head_xf)
			mi.scale = Vector3.ONE * sc * (1.0 if li == 0 else 1.13)
			nodes.append(mi)
			mats.append(m)
	var body := ArrayMesh.new()
	var bm := _mat(3, 0.0, d)
	bm.set_shader_parameter("flow", -1.6)
	bm.set_shader_parameter("life", 99.0)
	bm.set_shader_parameter("tear", 0.98)
	bm.set_shader_parameter("sway", 0.06)
	bm.set_shader_parameter("erode", 0.26)
	var bmi := MeshInstance3D.new()
	bmi.mesh = body
	bmi.material_override = bm
	bmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bmi.extra_cull_margin = 16.0
	bmi.top_level = true
	add_child(bmi)
	bmi.global_transform = Transform3D.IDENTITY
	var cm := _mat(3, 1.0, d)
	cm.set_shader_parameter("flow", -1.6)
	cm.set_shader_parameter("life", 99.0)
	cm.set_shader_parameter("tear", 0.98)
	var cmi := MeshInstance3D.new()
	cmi.mesh = ArrayMesh.new()
	cmi.material_override = cm
	cmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cmi.extra_cull_margin = 16.0
	cmi.top_level = true
	add_child(cmi)
	cmi.global_transform = Transform3D.IDENTITY
	nodes.append(bmi)
	nodes.append(cmi)
	it["nodes"] = nodes
	it["mats"] = mats
	it["body"] = bmi
	it["body_core"] = cmi
	it["body_mats"] = [bm, cm]
	it["head_pos"] = head_xf.origin
	it["head_fwd"] = head_xf.basis.z
	it["path"] = PackedVector3Array()
	it["dir"] = Vector3(head_xf.basis.z.x, 0.0, head_xf.basis.z.z).normalized()
	it["prev_actor"] = actor.global_position
	it["burn_at"] = -1.0
	it["final_done"] = false
	it["center"] = head_xf.origin

func _dragon_frame(it: Dictionary, skill_t: float, adt: float) -> float:
	var d: Dictionary = it["d"]
	var age := float(it["age"])
	var t0 := float(d["t0"])
	var st := t0 + age                     # 龍自己的時鐘＝生成時的技能時間＋存活時間（Hit Stop 時一起停）
	var form := float(d.get("form", 0.7))
	var t_go := float(d.get("t_go", t0 + form))
	var t_fin := float(d.get("t_final", t_go + 1.5))
	var sc := float(d.get("head_scale", 1.0))
	var axf := actor.global_transform
	var hp: Vector3 = it["head_pos"]
	var target: Vector3
	var k := 10.0
	if st < t_go:
		target = axf * _v3(d.get("charge_pos", [0.0, 2.3, 0.9])) + Vector3(0, sin(age * 3.1) * 0.05, 0)
		k = 7.0
	elif st < t_fin or bool(it["final_done"]):
		if adt > 0.0:
			var v := (actor.global_position - (it["prev_actor"] as Vector3)) / adt
			v.y = 0.0
			if v.length() > 1.2:
				it["dir"] = ((it["dir"] as Vector3).lerp(v.normalized(), clampf(adt * 14.0, 0.0, 1.0))).normalized()
		var lead := float(d.get("lead", 1.5))
		target = actor.global_position + Vector3(0, float(d.get("height", 1.4)), 0) + (it["dir"] as Vector3) * lead
		k = 13.0
		if bool(it["final_done"]):
			target = it["final_pos"]
			k = 9.0
	else:
		it["final_done"] = true
		it["final_pos"] = axf * _v3(d.get("final_pos", [0.0, 1.0, 2.0]))
		target = it["final_pos"]
		var fb: Dictionary = d.get("final_burst", {})
		if not fb.is_empty():
			var bi := {"d": fb, "state": 0, "age": 0.0, "nodes": [], "mats": []}
			var fwd := it["dir"] as Vector3
			_spawn(bi, Transform3D(Basis(Vector3.UP.cross(fwd).normalized(), Vector3.UP, fwd), it["final_pos"]))
			_pending.append(bi)
		if float(it["burn_at"]) < 0.0:
			it["burn_at"] = age + float(d.get("burn_delay", 0.25))
	it["prev_actor"] = actor.global_position
	hp = hp.lerp(target, 1.0 - exp(-k * adt))
	var vel := (hp - (it["head_pos"] as Vector3)) / maxf(adt, 1e-4)
	var fw: Vector3 = it["head_fwd"]
	if adt > 0.0 and vel.length() > 0.8:
		fw = fw.slerp(vel.normalized(), clampf(adt * 10.0, 0.0, 1.0)).normalized()
	elif st < t_go:
		var cy := deg_to_rad(float(d.get("charge_yaw_deg", 70.0)))
		var cw := (axf.basis * Vector3(sin(cy), 0.28, cos(cy))).normalized()
		fw = fw.slerp(cw, clampf(adt * 6.0, 0.0, 1.0)).normalized()
	it["head_pos"] = hp
	it["head_fwd"] = fw
	var grow := smoothstep(0.0, form, age)
	var burn := 0.0
	var ba := float(it["burn_at"])
	if ba >= 0.0:
		burn = clampf((age - ba) / float(d.get("burn", 0.8)), 0.0, 1.0)
	var upv := Vector3.UP
	if absf(fw.dot(upv)) > 0.95:
		upv = Vector3.FORWARD
	var hb := Basis.looking_at(-fw, upv)    # 模型 +Z＝吻部朝前
	for i in (it["mats"] as Array).size():
		var mi: MeshInstance3D = it["nodes"][i]
		mi.global_transform = Transform3D(hb, hp)
		mi.scale = Vector3.ONE * sc * lerpf(0.45, 1.0, grow) * (1.0 if i == 0 else 1.13)
		var m: ShaderMaterial = it["mats"][i]
		m.set_shader_parameter("age", age)
		m.set_shader_parameter("reveal", clampf(grow * 1.25, 0.0, 1.0))
		m.set_shader_parameter("burn", clampf(burn * 1.3 - 0.3, 0.0, 1.0))
	# 龍身：瞬步開始後，把「頸部」走過的位置記下來（角色實際路線），從尾到頸做成一條會流動的火焰身體
	var path: PackedVector3Array = it["path"]
	if st >= t_go and burn <= 0.0:
		var neck := hp - fw * 0.45 * sc
		if path.is_empty() or path[path.size() - 1].distance_to(neck) > 0.06:
			path.append(neck)
			if path.size() > 260:
				var p2 := PackedVector3Array()
				for j in range(0, path.size(), 2):
					p2.append(path[j])
				path = p2
		it["path"] = path
	for m: ShaderMaterial in it["body_mats"]:
		m.set_shader_parameter("age", age)
		m.set_shader_parameter("burn", burn)
		m.set_shader_parameter("body_len", maxf(_plen(path), 1.0))
	_tube(it["body"] as MeshInstance3D, path, float(d.get("radius", 0.34)) * sc, 1.0, age)
	_tube(it["body_core"] as MeshInstance3D, path, float(d.get("radius", 0.34)) * sc, 0.38, age)
	it["center"] = hp
	if burn >= 1.0:
		_embers(it, 14)
		_kill(it)
		return 0.0
	var e := (0.35 + 0.65 * grow) * (1.0 - burn) * float(d.get("gain", 1.0))
	if bool(it["final_done"]):
		e *= 1.3
	return e

func _plen(p: PackedVector3Array) -> float:
	var s := 0.0
	for i in range(1, p.size()):
		s += p[i].distance_to(p[i - 1])
	return s

## 管狀龍身：尾（u＝0）細、頸（u＝1）粗；截面加一點不規則（鬃毛般的起伏）
func _tube(mi: MeshInstance3D, p: PackedVector3Array, r_neck: float, scl: float, age := 0.0) -> void:
	var am := mi.mesh as ArrayMesh
	am.clear_surfaces()
	var n := p.size()
	if n < 3:
		return
	var nv := 10
	var total := _plen(p)
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	var s := 0.0
	var prev_n := Vector3.UP
	for i in n:
		if i > 0:
			s += p[i].distance_to(p[i - 1])
		var u := s / maxf(total, 1e-3)
		var tg := (p[mini(i + 1, n - 1)] - p[maxi(i - 1, 0)]).normalized()
		var side := tg.cross(prev_n)
		if side.length() < 0.05:
			side = tg.cross(Vector3.RIGHT)
		side = side.normalized()
		var nn := side.cross(tg).normalized()
		prev_n = nn
		var r := lerpf(0.05, r_neck, pow(u, 0.55)) * scl * (0.82 + 0.18 * sin(s * 3.1 + age * 2.2))
		var amp := 0.26 * smoothstep(0.0, 0.2, 1.0 - u)            # 蜿蜒：頸部接龍頭處不擺，往尾越擺越開
		var c := p[i] + side * sin(s * 1.6 - age * 3.4) * amp + nn * cos(s * 1.1 - age * 2.6) * amp * 0.5
		for j in nv + 1:
			var ph := TAU * float(j) / float(nv)
			var dirv := nn * cos(ph) + side * sin(ph)
			var bump := 1.0 + 0.22 * sin(ph * 3.0 + s * 9.0) * (0.5 + 0.5 * cos(ph))
			pos.append(c + dirv * r * bump)
			nrm.append(dirv)
			uv.append(Vector2(u, float(j) / float(nv)))
	for i in n - 1:
		for j in nv:
			var a := i * (nv + 1) + j
			var b := a + nv + 1
			idx.append_array(PackedInt32Array([a, b, a + 1, a + 1, b, b + 1]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pos
	arr[Mesh.ARRAY_NORMAL] = nrm
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_INDEX] = idx
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)

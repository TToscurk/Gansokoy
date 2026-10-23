extends Node3D
## 日之呼吸火焰系統（統一版，ART_REVIEW）。一個播放入口、一條刀身軌跡、一個技能時鐘、一套生命週期。
## 三套既有技術各取所長（不是三套同時播放）：
##   第一層 高溫刀光核心：原始 R9 程式刀光 sun_trail_r9.gd（實際刀變換插值取樣、Catmull 平滑、Hit Stop 時鐘）的核心 strip，
##          換成斷續、粗細會變的白金刀線（sun_fire_core.gdshader），不再是均勻的霓虹圓弧。
##   第二層 火焰主體：R9-C2 Blender 資產的 Flames／Sheet／Fin／Embers／BladeFlame（不規則火舌、交叉立面＝厚度、同一條實測刀路），
##          換成 sun_fire_mesh.gdshader（V2 噪聲流動與撕裂、HDR 溫度色、預乘 alpha）。不取 Blender 的 Core／Ring／Layer／Hit。
##   第三層 動態燃燒：R9 刀光的火焰 strip 掛 V2 噪聲侵蝕（sun_fire_trail.gdshader），把火焰黏在這一幀真實的刀路上；
##          第二層的流動、撕裂、冷卻也都用 V2 的噪聲與色彩。V2 的大量刀路火舌粒子不再使用，只留少量火星。
##   風格化火帶（stroke，每型自己的構圖，例：碧羅天＝包圍角色的火環）：手繪造型貼圖＋硬邊色塊＋深色輪廓線，沿刀尖實際走過的路徑
##		  逐段點燃、朝相機展開（自由視角都讀得到），完整呈現一下再由外往內撕開消散（sun_fire_stroke.gdshader）。只是視覺，不擴大判定。
##   第四層 命中爆燃：V2 的高溫裂口（偏到接觸點前方與外側，不蓋住刀與目標的接觸）＋5 道定向爆燃＋火星；每招每段判定只觸發一次。
## 時鐘：技能時間 skill_t（Hit Stop 時不前進）驅動 Blender 層與刀光；fx_time（Hit Stop 時不前進）驅動噪聲；粒子 time_scale 同步。
## 中斷：end() 之後不再點燃新的部分（cut_t），已點燃的照壽命燒完、整體在 0.25 s 內收掉；不留下「之後才會被刀經過」的火。
## 介面：setup(actor, sword, cam)；begin(skill_key)；end()；clear()；frame(sword_xf, skill_t, dt, freeze, tip_speed)；
##       hit(pos, dir, normal, strike)；stats()。每型的資料在 sun_fire_profiles.json。
const PROFILES := "res://characters/yoriichi/v24_isshin/fire_research_v2/sun_fire_profiles.json"
const TrailR9 = preload("res://characters/yoriichi/v24_isshin/r9/sun_trail_r9.gd")
const SH_MESH := preload("res://characters/yoriichi/v24_isshin/fire_research_v2/sun_fire_mesh.gdshader")
const SH_TRAIL := preload("res://characters/yoriichi/v24_isshin/fire_research_v2/sun_fire_trail.gdshader")
const SH_CORE := preload("res://characters/yoriichi/v24_isshin/fire_research_v2/sun_fire_core.gdshader")
const SH_TONGUE := preload("res://characters/yoriichi/v24_isshin/fire_research_v2/fire_v2_tongue.gdshader")
const SH_SPARK := preload("res://characters/yoriichi/v24_isshin/fire_research_v2/fire_v2_spark.gdshader")
const SH_PROC := preload("res://characters/yoriichi/v24_isshin/fire_research_v2/fire_v2_process.gdshader")
const SH_FLASH := preload("res://characters/yoriichi/v24_isshin/fire_research_v2/fire_v2_flash.gdshader")
const SH_EDGE := preload("res://characters/yoriichi/v24_isshin/fire_research_v2/fire_v2_blade.gdshader")
const SH_STROKE := preload("res://characters/yoriichi/v24_isshin/fire_research_v2/sun_fire_stroke.gdshader")
const BAND := preload("res://characters/yoriichi/v24_isshin/fire_research_v2/stylized_flame_band.png")
const NOISE := preload("res://characters/yoriichi/v24_isshin/fire_research_v2/fire_noise_v2.png")
const TEX := {
	"tongue": preload("res://characters/yoriichi/v24_isshin/r9c/r9c_tongue.png"),
	"body": preload("res://characters/yoriichi/v24_isshin/r9c/r9c2_body.png"),
	"ember": preload("res://characters/yoriichi/v24_isshin/r9c/r9c_ember.png"),
}
const PART_OF := {"flames": "flames", "sheet": "sheet", "fin": "fin", "embers": "embers", "bladeflame": "blade"}
const PRIORITY := {"fin": -2, "sheet": -1, "flames": 0, "embers": 0, "blade": 1}
const FLAGS := GPUParticles3D.EMIT_FLAG_POSITION | GPUParticles3D.EMIT_FLAG_ROTATION_SCALE | GPUParticles3D.EMIT_FLAG_VELOCITY | GPUParticles3D.EMIT_FLAG_COLOR | GPUParticles3D.EMIT_FLAG_CUSTOM
const TIP := 1.085

var actor: Node3D
var sword: Node3D
var cam: Camera3D
var enabled := true
var active := false
var skill_key := ""
var skill_t := 0.0
var fx_time := 0.0
var profiles := {}
var prof := {}
var rng := RandomNumberGenerator.new()

var trail
var trail_mat: ShaderMaterial
var edge_mat: ShaderMaterial          # 刀刃熱邊（V2 朝相機的刀身火帶）：刀側對鏡頭時 Blender 立體火舌會變薄，這條保證點燃讀得到
var _edge_mesh := ImmediateMesh.new()
var _edge_mi: MeshInstance3D
var core_mat: ShaderMaterial
var stroke_mat: ShaderMaterial
var _stroke_mesh := ImmediateMesh.new()
var _stroke_mi: MeshInstance3D
var _stroke_paths := {}  # 路徑檔 -> {pts: [[t, Vector3]], u: [], center: Vector3}（角色根的本地座標）
var _stroke: Dictionary = {}  # 這一招用的路徑
var _stroke_pts: Array = []  # 已點燃的段：[世界位置, 世界中心, 點燃時間, u]
var _stroke_next := 0
var _stroke_loc: Array = []  # stroke.follow_until（選用，R12 碧羅天）：已點燃段的根本地座標 [p, c]；在這個技能時間之前火環跟著角色根走，之後留在世界原地
var stroke_sync_err := 0.0  # 火帶前緣與實際刀尖的最大距離（檢查用）
var _pose_t := 0.0  # 畫面上的姿勢＝上一幀的技能時間（R11 實測：骨架晚 shot_t 一幀，火環照畫面上的刀點燃）
var _last_t := 0.0
var sets := {}                 # glb 路徑 -> {arc, blade, mats: {part: ShaderMaterial}, meshes: []}
var cur := {}
var _frozen := false
var _cut_t := 99.0
var _fade := 1.0
var _fading := false
var _flare := 0.0

var bursts: GPUParticles3D
var sparks: GPUParticles3D
var proc_mat: ShaderMaterial
var tongue_mat: ShaderMaterial
var spark_mat: ShaderMaterial
var _flash_pool: Array = []
var _flashes: Array = []
var _flash_ix := 0
var _prev := Transform3D()
var _have_prev := false
var _spark_debt := 0.0
var _slash_sparks := 0
var _aura_debt := 0.0
var _aura_n := 0
var _blade_level := 0.0
var _hit_strikes := {}
var _prewarm := 4

var hits_spawned := 0
var hits_ignored := 0
var frozen_frames := 0
var n_emit := {"burst": 0, "spark": 0}

func setup(actor_: Node3D, sword_: Node3D, cam_: Camera3D) -> void:
	actor = actor_
	sword = sword_
	cam = cam_
	top_level = true
	global_transform = Transform3D.IDENTITY
	rng.seed = 7741
	profiles = JSON.parse_string(FileAccess.get_file_as_string(PROFILES))
	# 第一層＋第三層：原始 R9 刀光（取樣、幾何、時鐘全用原檔），只換兩個材質
	trail = TrailR9.new()
	trail.name = "SunTrailR9"
	add_child(trail)
	trail_mat = _shader_mat(SH_TRAIL)
	core_mat = _shader_mat(SH_CORE)
	core_mat.render_priority = 3                     # 刀光核心畫在所有火焰之上（仍做深度測試）
	trail_mat.render_priority = 0
	trail._flame_mat = trail_mat
	trail.material_override = trail_mat
	trail._core_mat = core_mat
	trail._core_mi.material_override = core_mat
	trail.fade_hold = 0.0                            # 讓 COLOR.a 單調對應年齡（著色器用它做 V2 的侵蝕）
	edge_mat = _shader_mat(SH_EDGE)
	edge_mat.render_priority = 2
	_edge_mi = MeshInstance3D.new()
	_edge_mi.name = "BladeEdgeFire"
	_edge_mi.mesh = _edge_mesh
	_edge_mi.material_override = edge_mat
	_edge_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_edge_mi.extra_cull_margin = 4.0
	add_child(_edge_mi)
	stroke_mat = _shader_mat(SH_STROKE)
	stroke_mat.set_shader_parameter("band_tex", BAND)
	stroke_mat.render_priority = -3				  # 風格化火帶最底；刀光核心、命中爆燃畫在它上面
	_stroke_mi = MeshInstance3D.new()
	_stroke_mi.name = "StylizedStroke"
	_stroke_mi.mesh = _stroke_mesh
	_stroke_mi.material_override = stroke_mat
	_stroke_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_stroke_mi.extra_cull_margin = 6.0
	add_child(_stroke_mi)
	# 第二層：Blender 造型（每型一份 GLB；同一 GLB 共用）
	for k in profiles:
		if str(k).begins_with("_"):
			continue
		var m: Dictionary = (profiles[k] as Dictionary).get("mesh", {})
		if m.has("glb") and not sets.has(str(m["glb"])):
			_load_set(m)
	# 第四層＋火星：V2 粒子
	proc_mat = ShaderMaterial.new()
	proc_mat.shader = SH_PROC
	tongue_mat = _shader_mat(SH_TONGUE)
	tongue_mat.render_priority = 1
	spark_mat = ShaderMaterial.new()
	spark_mat.shader = SH_SPARK
	spark_mat.render_priority = 2
	bursts = _mk_particles("HitBursts", 48, tongue_mat)
	sparks = _mk_particles("Sparks", 96, spark_mat)
	var q := QuadMesh.new()
	for i in 3:
		var mi := MeshInstance3D.new()
		mi.name = "HitCore%d" % i
		mi.mesh = q
		var fm := _shader_mat(SH_FLASH)
		fm.render_priority = 4
		mi.material_override = fm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_flash_pool.append(mi)

func _shader_mat(sh: Shader) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("noise_tex", NOISE)
	return m

func _load_set(mp: Dictionary) -> void:
	var glb := str(mp["glb"])
	var parts: Dictionary = mp.get("parts", {})
	var S := {"arc": Node3D.new(), "blade": null, "mats": {}, "meshes": []}
	(S["arc"] as Node3D).name = "SunFireArc"
	var inst: Node = (load(glb) as PackedScene).instantiate()
	for c in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		var part: String = PART_OF.get(str(mi.name).split("_")[0].to_lower(), "")
		if part == "" or not parts.has(part):
			continue
		var pp: Dictionary = parts[part]
		var m: ShaderMaterial = S["mats"].get(part, null)
		if m == null:
			m = _shader_mat(SH_MESH)
			m.set_shader_parameter("tex", TEX[str(pp.get("tex", "tongue"))])
			for key in pp:
				if key != "tex" and not str(key).begins_with("_"):
					m.set_shader_parameter(key, pp[key])
			m.render_priority = int(PRIORITY.get(part, 0))
			S["mats"][part] = m
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 4.0
		mi.owner = null
		mi.get_parent().remove_child(mi)
		mi.transform = Transform3D.IDENTITY
		if part == "blade":
			S["blade"] = mi
		else:
			(S["arc"] as Node3D).add_child(mi)
			S["meshes"].append(mi)
	inst.free()
	(S["arc"] as Node3D).visible = false
	add_child(S["arc"])
	if S["blade"] != null:
		(S["blade"] as MeshInstance3D).visible = false
		sword.add_child(S["blade"])
	sets[glb] = S

func _mk_particles(n: String, amount: int, draw: ShaderMaterial) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = n
	p.amount = amount
	p.lifetime = 1.0
	p.local_coords = false
	p.emitting = false
	p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	p.visibility_aabb = AABB(Vector3(-6, -3, -6), Vector3(12, 9, 12))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.process_material = proc_mat
	var qm := QuadMesh.new()
	qm.material = draw
	p.draw_pass_1 = qm
	add_child(p)
	return p

func _all_mats() -> Array:
	var a: Array = [trail_mat, core_mat, tongue_mat, edge_mat, stroke_mat]
	for S in sets.values():
		a.append_array((S["mats"] as Dictionary).values())
	return a

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

static func _in(ws: Array, t: float) -> bool:
	for w in ws:
		if t >= float(w[0]) and t <= float(w[1]):
			return true
	return false

# ------------------------------------------------------------------ 播放入口
func has_skill(key: String) -> bool:
	return profiles.has(key)

func begin(key: String) -> void:
	if not profiles.has(key):
		return
	_finish_previous()
	skill_key = key
	prof = profiles[key]
	active = true
	skill_t = 0.0
	_cut_t = 99.0
	_fade = 1.0
	_fading = false
	_frozen = false
	_spark_debt = 0.0
	_slash_sparks = 0
	_aura_debt = 0.0
	_aura_n = 0
	_hit_strikes.clear()
	var tr: Dictionary = prof.get("trail", {})
	trail.lifetime = float(tr.get("lifetime", 0.22))
	trail.flame_extend = float(tr.get("extend", 0.1))
	trail.flame_inset = float(tr.get("inset", 0.0))
	trail.flame_lift = float(tr.get("lift", 0.05))
	trail.max_step_deg = float(tr.get("max_step_deg", 4.0))
	trail.core_root_skip = float(tr.get("core_root_skip", 0.4))
	trail.core_lifetime_ratio = float(tr.get("core_ratio", 0.5))
	trail.head_fade = float(tr.get("head_fade", 0.03))
	core_mat.set_shader_parameter("gain", float(tr.get("core_gain", 0.5)))
	trail_mat.set_shader_parameter("heat_gain", float(tr.get("flame_heat", 1.0)))
	trail_mat.set_shader_parameter("occlusion", float(tr.get("flame_occlusion", 0.5)))
	_begin_stroke()
	var mp: Dictionary = prof.get("mesh", {})
	cur = sets.get(str(mp.get("glb", "")), {})
	if not cur.is_empty():
		var arc: Node3D = cur["arc"]
		if arc.get_parent() != actor:
			arc.get_parent().remove_child(arc)
			actor.add_child(arc)
		arc.top_level = false
		arc.transform = Transform3D.IDENTITY
		arc.visible = enabled
		for m: ShaderMaterial in (cur["mats"] as Dictionary).values():
			m.set_shader_parameter("cut_t", 99.0)

func _begin_stroke() -> void:
	_stroke_pts.clear()
	_stroke_loc.clear()
	_stroke_next = 0
	stroke_sync_err = 0.0
	_pose_t = 0.0
	_last_t = 0.0
	_stroke_mesh.clear_surfaces()
	var sp: Dictionary = prof.get("stroke", {})
	_stroke = {}
	if sp.is_empty():
		return
	var path := str(sp["path"])
	if not _stroke_paths.has(path):
		var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		var pts: Array = []
		var us: Array = []
		var acc := 0.0
		for i in (d["points"] as Array).size():
			var r: Array = d["points"][i]
			var p := Vector3(float(r[1]), float(r[2]), float(r[3]))
			if i > 0:
				acc += p.distance_to(pts[i - 1][1])
			pts.append([float(r[0]), p, float(r[4]) if r.size() > 4 else 1.0])   # 第 5 欄（選用）＝這一段的火帶寬度倍率
			us.append(acc)
		for i in us.size():
			us[i] = float(us[i]) / maxf(acc, 1e-4)
		var c: Array = d["center"]
		_stroke_paths[path] = {"pts": pts, "u": us, "center": Vector3(float(c[0]), float(c[1]), float(c[2])), "len": acc}
	_stroke = _stroke_paths[path]
	stroke_mat.set_shader_parameter("vanish_age", 99.0)     # 選用參數先回預設：上一招設過的不帶到這一招
	stroke_mat.set_shader_parameter("vanish_soft", 0.12)
	for key in sp:
		if key != "path" and key != "inner" and key != "outer" and not str(key).begins_with("_"):
			var v = sp[key]
			stroke_mat.set_shader_parameter(key, Vector3(float(v[0]), float(v[1]), float(v[2])) if v is Array else v)
	stroke_mat.set_shader_parameter("ring_t0", float(_stroke["pts"][0][0]))
	stroke_mat.set_shader_parameter("cut_t", 99.0)

## 風格化火帶：刀經過的段才點燃（路徑是刀尖相對角色根的實測軌跡，用「當下」的角色變換放進世界，之後留在原地）
func _feed_stroke(t: float, xf: Transform3D) -> void:
	if _stroke.is_empty() or actor == null:
		return
	var pts: Array = _stroke["pts"]
	var A := actor.global_transform
	var c: Vector3 = A * (_stroke["center"] as Vector3)
	while _stroke_next < pts.size() and float(pts[_stroke_next][0]) <= t and float(pts[_stroke_next][0]) <= _cut_t:
		var p: Vector3 = A * (pts[_stroke_next][1] as Vector3)
		_stroke_pts.append([p, c, float(pts[_stroke_next][0]), float(_stroke["u"][_stroke_next]), float(pts[_stroke_next][2])])
		_stroke_loc.append([pts[_stroke_next][1], _stroke["center"]])
		_stroke_next += 1
	if t < float((prof.get("stroke", {}) as Dictionary).get("follow_until", -1.0)):
		for i in _stroke_pts.size():
			_stroke_pts[i][0] = A * (_stroke_loc[i][0] as Vector3)
			_stroke_pts[i][1] = c
	# 同步檢查：畫面上的刀尖到火環路徑（前後 ±8 段）的最近距離（有 break_gap 時：兩刀之間的空檔不算）
	var gap0 := float((prof.get("stroke", {}) as Dictionary).get("break_gap", 0.0))
	if _stroke_next > 0 and _stroke_next < pts.size() and t <= float(pts[pts.size() - 1][0]) - 0.06 and (gap0 <= 0.0 or float(pts[_stroke_next][0]) - t <= gap0):
		var tip := xf * Vector3(0, TIP, 0)
		var best := 99.0
		for j in range(maxi(_stroke_next - 8, 0), mini(_stroke_next + 8, pts.size())):
			best = minf(best, tip.distance_to(A * (pts[j][1] as Vector3)))
		stroke_sync_err = maxf(stroke_sync_err, best)

## 每幀依鏡頭重建：火帶朝相機展開，方向一律朝「環的外側」（整圈同一側，避免翻面）；擋在角色與鏡頭之間的段變窄、變透明
func _build_stroke(level: float) -> void:
	_stroke_mesh.clear_surfaces()
	var n := _stroke_pts.size()
	if n < 2 or level <= 0.0 or cam == null:
		return
	var sp: Dictionary = prof.get("stroke", {})
	var w_in := float(sp.get("inner", 0.22))
	var w_out := float(sp.get("outer", 0.62))
	var R := maxf(float(_stroke.get("len", 6.0)) / TAU, 0.3)
	var cp := cam.global_position
	var chest := actor.global_position + Vector3.UP * 1.15
	var to_cam := (cp - chest).normalized()
	# break_gap（選用，R13 炎舞）：相鄰兩點的點燃時間差超過這個值＝不同的刀，火帶在這裡斷開、各自一條；沒設＝整條相連（舊行為）
	var gap := float(sp.get("break_gap", 0.0))
	var runs: Array = [[0, n - 1]]
	if gap > 0.0:
		runs = []
		var s0 := 0
		for i in range(1, n + 1):
			if i == n or float(_stroke_pts[i][2]) - float(_stroke_pts[i - 1][2]) > gap:
				runs.append([s0, i - 1])
				s0 = i
	var dirs: Array = []
	dirs.resize(n)
	var s := 0.0
	for rn: Array in runs:
		var lo := int(rn[0])
		var hi := int(rn[1])
		for i in range(lo, hi + 1):
			var p: Vector3 = _stroke_pts[i][0]
			var tg: Vector3 = (_stroke_pts[mini(i + 1, hi)][0] as Vector3) - (_stroke_pts[maxi(i - 1, lo)][0] as Vector3)
			var a := tg.cross(cp - p)
			a = a.normalized() if a.length_squared() > 1e-10 else Vector3.UP
			dirs[i] = a
			s += a.dot(p - (_stroke_pts[i][1] as Vector3))
	var sgn := 1.0 if s >= 0.0 else -1.0
	for rn: Array in runs:
		if int(rn[1]) > int(rn[0]):
			_stroke_run(int(rn[0]), int(rn[1]), cp, chest, to_cam, R, w_in, w_out, sgn, dirs)

func _stroke_run(lo: int, hi: int, cp: Vector3, chest: Vector3, to_cam: Vector3, R: float, w_in: float, w_out: float, sgn: float, dirs: Array) -> void:
	_stroke_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in range(lo, hi + 1):
		var p: Vector3 = _stroke_pts[i][0]
		# 朝相機的展開方向混一點「螢幕上的徑向」：刀路轉彎或與視線平行時火帶不會扭成一條帶子
		var rad: Vector3 = p - (_stroke_pts[i][1] as Vector3)
		var vv := (cp - p).normalized()
		rad = rad - vv * rad.dot(vv)
		var d: Vector3 = dirs[i] * sgn
		if rad.length_squared() > 1e-6:
			d = (d * 0.6 + rad.normalized() * 0.4).normalized()
		var near := clampf((p - chest).dot(to_cam) / R, 0.0, 1.0) * clampf(1.4 - (p - chest).length() / R * 0.4, 0.0, 1.0)
		var ws := float(_stroke_pts[i][4]) if (_stroke_pts[i] as Array).size() > 4 else 1.0
		var wo := w_out * (1.0 - 0.35 * near) * ws
		var u := float(_stroke_pts[i][3])
		var t0 := float(_stroke_pts[i][2])
		_stroke_mesh.surface_set_uv(Vector2(u, 0.0))
		_stroke_mesh.surface_set_uv2(Vector2(t0, near))
		_stroke_mesh.surface_add_vertex(p - d * w_in * minf(1.0, 0.4 + ws))
		_stroke_mesh.surface_set_uv(Vector2(u, 1.0))
		_stroke_mesh.surface_set_uv2(Vector2(t0, near))
		_stroke_mesh.surface_add_vertex(p + d * wo)
	_stroke_mesh.surface_end()

## 上一招的 Blender 層還在燒時又出招：同一份網格要重用，先把上一份收掉
func _finish_previous() -> void:
	if not cur.is_empty():
		(cur["arc"] as Node3D).visible = false
		if cur["blade"] != null:
			(cur["blade"] as MeshInstance3D).visible = false

## 招式結束或被中斷：不再點燃新的部分，已點燃的照壽命燒完；整體在 0.25 s 內收掉
func end() -> void:
	if not active:
		return
	active = false
	_cut_t = skill_t
	stroke_mat.set_shader_parameter("cut_t", _cut_t)
	if not cur.is_empty():
		for m: ShaderMaterial in (cur["mats"] as Dictionary).values():
			m.set_shader_parameter("cut_t", _cut_t)
		_freeze_arc()
	var mp: Dictionary = prof.get("mesh", {})
	if skill_t < float(mp.get("end_t", 1.6)) - 0.25:
		_fading = true

## 切到其他特效：立刻全部清掉
func clear() -> void:
	active = false
	_fading = false
	if trail.is_emitting:
		trail.stop_trail()
	trail._runs.clear()
	trail._flame_mesh.clear_surfaces()
	trail._core_mesh.clear_surfaces()
	_finish_previous()
	_edge_mesh.clear_surfaces()
	_stroke_mesh.clear_surfaces()
	_stroke_pts.clear()
	_stroke_loc.clear()
	_stroke = {}
	bursts.restart()
	bursts.emitting = false
	sparks.restart()
	sparks.emitting = false
	for f in _flashes:
		(f["mi"] as MeshInstance3D).visible = false
	_flashes.clear()

func _freeze_arc() -> void:
	if _frozen or cur.is_empty():
		return
	_frozen = true
	var arc: Node3D = cur["arc"]
	var g := arc.global_transform
	arc.top_level = true                       # 殘焰留在世界中原地消散，不跟著角色收勢移動
	arc.global_transform = g

# ------------------------------------------------------------------ 每幀（骨架更新後；Hit Stop 時 freeze＝true）
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
	skill_t = t
	if _fading:
		_fade = move_toward(_fade, 0.0, dt / 0.25)
	if not freeze:
		_flare = move_toward(_flare, 0.0, dt / float((prof.get("hit", {}) as Dictionary).get("flare_time", 0.12)))
	var on := enabled and active
	# 第一層＋第三層：R9 刀光
	var tr: Dictionary = prof.get("trail", {})
	var want := on and _in(tr.get("emit", []), t)
	if want and not trail.is_emitting:
		trail.start_trail()
	elif not want and trail.is_emitting:
		trail.stop_trail()
	trail.clock_scale = clock
	trail.feed(xf, dt)
	trail.visible = enabled
	for m: ShaderMaterial in _all_mats():
		m.set_shader_parameter("fx_time", fx_time)
	trail_mat.set_shader_parameter("intensity", _fade * float(tr.get("flame_on", 1.0)))
	core_mat.set_shader_parameter("intensity", _fade)
	# 風格化火帶
	_pose_t = _last_t
	_last_t = t
	if not _stroke.is_empty():
		if on:
			_feed_stroke(_pose_t, xf)
		stroke_mat.set_shader_parameter("skill_t", _pose_t)
		stroke_mat.set_shader_parameter("flare", _flare)
		stroke_mat.set_shader_parameter("intensity", _fade)
		var live := enabled and _fade > 0.0 and t <= float((prof.get("stroke", {}) as Dictionary).get("end_t", 1.8))
		_build_stroke(1.0 if live else 0.0)
		_stroke_mi.visible = live
	# 刀身熱邊（點燃）
	var mp: Dictionary = prof.get("mesh", {})
	var be := _env(mp.get("blade_env", []), t) * (1.0 if active else 0.0)
	_build_edge(xf, be * _fade if enabled else 0.0, float(mp.get("edge_height", 0.12)))
	_blade_level = be
	# 第二層：Blender 造型
	if not cur.is_empty():
		if t >= float(mp.get("freeze_t", 0.7)):
			_freeze_arc()
		var dr: Array = mp.get("drift", [0.62, 1.35])
		var dw := smoothstep(float(dr[0]), float(dr[1]), t)
		for mi in cur["meshes"]:
			var mm := mi as MeshInstance3D
			if mm.mesh and mm.mesh.get_blend_shape_count() > 0:
				mm.set_blend_shape_value(0, dw)
		for part in cur["mats"]:
			var m: ShaderMaterial = cur["mats"][part]
			m.set_shader_parameter("skill_t", t)
			m.set_shader_parameter("flare", _flare)
			m.set_shader_parameter("intensity", (be if part == "blade" else 1.0) * _fade)
		(cur["arc"] as Node3D).visible = enabled and t <= float(mp.get("end_t", 1.6)) and _fade > 0.0
		if cur["blade"] != null:
			(cur["blade"] as MeshInstance3D).visible = enabled and be > 0.01 and _fade > 0.0
	# 火星：只在高速斬擊段，依刀尖走過的距離，總量有上限
	proc_mat.set_shader_parameter("time_scale", clock)
	bursts.visible = enabled
	sparks.visible = enabled
	bursts.global_position = xf.origin
	sparks.global_position = xf.origin
	var sp: Dictionary = prof.get("sparks", {})
	if on and not freeze and _have_prev and dt > 0.0 and _in([sp.get("window", [0.5, 0.72])], t) and tip_speed >= float(sp.get("min_speed", 8.0)):
		var ref := TIP * 0.95
		_spark_debt += (xf * Vector3(0, ref, 0)).distance_to(_prev * Vector3(0, ref, 0)) / float(sp.get("spacing", 0.14))
		while _spark_debt >= 1.0 and _slash_sparks < int(sp.get("cap", 30)):
			_spark_debt -= 1.0
			var w := _prev.interpolate_with(xf, rng.randf())
			var u := rng.randf_range(0.85, 1.06) * TIP
			var v := (xf * Vector3(0, u, 0) - _prev * Vector3(0, u, 0)) / dt
			var rnd := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.2, 1.2), rng.randf_range(-1, 1)) * rng.randf_range(0.5, 1.8)
			_emit(sparks, w * Vector3(0, u, 0), v * 0.2 + rnd, Vector3.UP, rng.randf_range(0.010, 0.015), 0.03, rng.randf_range(0.3, 0.8), 3, 1.0)
			_slash_sparks += 1
			n_emit["spark"] += 1
	# 點燃：刀慢（蓄勢）時，少量小火舌從刀刃往上竄（V2 程序化火舌；刀側對鏡頭時也讀得到「刀燒起來了」），每招有上限
	var au: Dictionary = prof.get("ignite", {})
	if on and not freeze and _have_prev and dt > 0.0 and _blade_level > 0.25 and tip_speed < float(au.get("max_speed", 12.0)) and _aura_n < int(au.get("cap", 14)):
		_aura_debt += dt * float(au.get("rate", 22.0)) * _blade_level
		while _aura_debt >= 1.0 and _aura_n < int(au.get("cap", 14)):
			_aura_debt -= 1.0
			var uu := rng.randf_range(0.35, 1.0) * TIP
			var vv := (xf * Vector3(0, uu, 0) - _prev * Vector3(0, uu, 0)) / dt
			var s := lerpf(0.75, 1.0, uu / TIP)
			_emit(bursts, xf * Vector3(0, uu, 0), vv * 0.05 + Vector3.UP * 0.3, Vector3.UP, rng.randf_range(0.12, 0.18) * s, rng.randf_range(0.24, 0.36) * s,
				rng.randf_range(0.28, 0.40), 1, 0.95)
			_aura_n += 1
			n_emit["ignite"] = int(n_emit.get("ignite", 0)) + 1
	_update_flashes(adt)
	_prev = xf
	_have_prev = true

## 刀刃熱邊：沿刀身、朝相機展開兩側的火焰帶（V2 fire_v2_blade.gdshader），每幀依刀的變換重建
func _build_edge(xf: Transform3D, level: float, h: float) -> void:
	_edge_mesh.clear_surfaces()
	if level <= 0.01 or cam == null:
		return
	var a := xf * Vector3.ZERO
	var b := xf * Vector3(0, TIP, 0)
	var axis := (b - a).normalized()
	var blen := a.distance_to(b)
	for side: float in [1.0, -1.0]:
		_edge_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		for k in 13:
			var u := lerpf(0.15, 1.0, float(k) / 12.0)
			var p := a.lerp(b, u)
			var o: Vector3 = axis.cross((cam.global_position - p).normalized()).normalized() * side
			var c := Color(1, 1, 1, level * (0.45 + 0.55 * (u - 0.15) / 0.85))
			var x := u * blen + (0.0 if side > 0.0 else 7.3)
			_edge_mesh.surface_set_color(c)
			_edge_mesh.surface_set_uv(Vector2(x, 0.0))
			_edge_mesh.surface_add_vertex(p + o * 0.005)
			_edge_mesh.surface_set_color(c)
			_edge_mesh.surface_set_uv(Vector2(x, 1.0))
			_edge_mesh.surface_add_vertex(p + o * (0.005 + h * level * (0.55 + 0.45 * u)) + Vector3.UP * 0.03 * level)
		_edge_mesh.surface_end()

func _emit(ps: GPUParticles3D, pos: Vector3, vel: Vector3, axis: Vector3, w: float, h: float, life: float, kind: int, inten: float) -> void:
	var ax := axis.normalized() if axis.length_squared() > 1e-6 else Vector3.UP
	var right := ax.cross(Vector3.FORWARD)
	if right.length_squared() < 0.01:
		right = ax.cross(Vector3.RIGHT)
	right = right.normalized()
	ps.emit_particle(Transform3D(Basis(right * w, ax * h, right.cross(ax).normalized() * w), pos), vel, Color(1, 1, 1, inten),
		Color(0, life, rng.randf(), float(kind)), FLAGS)

# ------------------------------------------------------------------ 命中（每招每段判定只一次）
func hit(pos: Vector3, dir: Vector3, normal := Vector3.ZERO, strike := 0) -> void:
	if not enabled or skill_key == "":
		return
	if _hit_strikes.has(strike):
		hits_ignored += 1
		return
	_hit_strikes[strike] = true
	hits_spawned += 1
	var H: Dictionary = prof.get("hit", {})
	var cut := dir.normalized() if dir.length() > 0.1 else Vector3.DOWN
	var nrm := normal.normalized() if normal.length() > 0.1 else -cut
	_flare = 1.0
	# 高溫裂口：沿刀的行進方向拉長，中心放在接觸點「前方＋外側」，接觸點本身留給刀與目標
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
	var at := pos + nrm * float(H.get("flash_out", 0.1)) + cut * float(H.get("flash_ahead", 0.12))
	mi.global_transform = Transform3D(Basis(side * float(H.get("flash_w", 0.1)), cut * float(H.get("flash_len", 0.42)), side.cross(cut).normalized()), at)
	var fm := mi.material_override as ShaderMaterial
	fm.set_shader_parameter("age", 0.0)
	fm.set_shader_parameter("seed", rng.randf() * 10.0)
	mi.visible = true
	_flashes.append({"mi": mi, "t": 0.0, "life": float(H.get("flash_life", 0.16))})
	# 定向爆燃＋火星：往「表面外法線＋刀的行進方向」噴
	var base := pos + nrm * 0.08
	for i in int(H.get("tongues", 5)):
		var d := (cut * 0.65 + nrm * 0.85 + Vector3(rng.randf_range(-0.35, 0.35), rng.randf_range(-0.1, 0.45), rng.randf_range(-0.35, 0.35))).normalized()
		_emit(bursts, base + d * rng.randf_range(0.02, 0.1), d * rng.randf_range(1.6, 3.4), (d + Vector3.UP * 0.6).normalized(),
			rng.randf_range(0.26, 0.40), rng.randf_range(0.45, 0.75), rng.randf_range(0.28, 0.45), 2, 1.0)
		n_emit["burst"] += 1
	for i in int(H.get("sparks", 18)):
		var d2 := (cut * 0.8 + nrm * 0.9 + Vector3(rng.randf_range(-0.7, 0.7), rng.randf_range(-0.3, 0.9), rng.randf_range(-0.7, 0.7))).normalized()
		_emit(sparks, base, d2 * rng.randf_range(2.0, 5.0), Vector3.UP, rng.randf_range(0.010, 0.016), 0.03, rng.randf_range(0.3, 0.7), 3, 1.0)
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

# ------------------------------------------------------------------ 預熱：第一次出招才編譯著色器會卡 80–150 ms、讓判定漏掉（V2 實測）
func _do_prewarm() -> void:
	_prewarm -= 1
	var done := _prewarm <= 0 or cam == null
	for S in sets.values():
		(S["arc"] as Node3D).visible = not done
		if S["blade"] != null:
			(S["blade"] as MeshInstance3D).visible = not done
		for m: ShaderMaterial in (S["mats"] as Dictionary).values():
			m.set_shader_parameter("intensity", 0.0 if not done else 1.0)
	for mi in _flash_pool:
		(mi as MeshInstance3D).visible = not done
	trail._flame_mesh.clear_surfaces()
	trail._core_mesh.clear_surfaces()
	_edge_mesh.clear_surfaces()
	_stroke_mesh.clear_surfaces()
	if done:
		return
	var p := cam.global_transform * Vector3(0, 0, -2.0)
	var r := cam.global_basis.x * 0.2
	var u := cam.global_basis.y * 0.2
	for pair in [[trail._flame_mesh, trail_mat], [trail._core_mesh, core_mat], [_edge_mesh, edge_mat], [_stroke_mesh, stroke_mat]]:
		var im: ImmediateMesh = pair[0]
		im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, pair[1])
		for v: Vector3 in [p - r - u, p - r + u, p + r - u, p + r + u]:
			im.surface_set_color(Color(1, 1, 1, 0))
			im.surface_set_uv(Vector2(0.5, 0.5))
			im.surface_set_uv2(Vector2(99.0, 0.0))
			im.surface_add_vertex(v)
		im.surface_end()
	for mi in _flash_pool:
		((mi as MeshInstance3D).material_override as ShaderMaterial).set_shader_parameter("age", 1.0)
		(mi as MeshInstance3D).global_position = p
	_emit(bursts, p, Vector3.ZERO, Vector3.UP, 0.1, 0.1, 0.05, 2, 0.0)
	_emit(sparks, p, Vector3.ZERO, Vector3.UP, 0.01, 0.03, 0.05, 3, 0.0)

func stats() -> Dictionary:
	return {"hits": hits_spawned, "hits_ignored": hits_ignored, "freeze_frames": frozen_frames, "emitted": n_emit.duplicate(),
		"trail_live": trail.sample_count(), "fx_time": fx_time, "skill_t": skill_t, "frozen_arc": _frozen, "fade": _fade,
		"flashes": _flashes.size(), "lights": 0, "mesh_parts": (cur.get("mats", {}) as Dictionary).keys() if not cur.is_empty() else [],
		"trail_samples": trail.sample_count(), "sparks_est": 0, "hit_particles": 0, "stroke_pts": _stroke_pts.size(), "stroke_sync_err": stroke_sync_err}

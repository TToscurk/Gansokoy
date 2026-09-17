extends MeshInstance3D
class_name SwordTrail3D
## 日之呼吸刀光 —— 雙層程序 ribbon。
##
## 介面對 yoriichi_character.gd 完全不變：
##   base_node / tip_node / lifetime / start_trail() / stop_trail()
## 內部實作全換：單層 ADD ribbon → 外焰(blend_mix 保實色輪廓) + 內核(blend_add 進 bloom)。
##
## 為什麼外焰不能用 ADD：
##   動畫式火焰的辨識度來自深赤色實色外輪廓。ADD 把暗色也加成亮色，輪廓被沖掉，
##   結果是一團光而不是火。外焰走 mix 保邊，核心才走 ADD 發光。
##
## 為什麼 ribbon 要比刀身寬：
##   火舌要有往外長的空間。舊版頂點只到刀尖，火焰被壓在刀身寬度內，
##   看起來像「刀在發光」而不是「刀帶著火」。
##
## 舊版保留的欄位 tip_color / base_color 已由五層色階取代（見 Colors 群組）。

@export var base_node: Node3D
@export var tip_node: Node3D
## 外焰壽命（秒）。yoriichi_character.gd 會在型發動時改寫這個值。
@export var lifetime := 0.20
## 取樣最小間距（公尺）。太小會在慢速揮刀時塞進大量共線點。
@export var min_distance := 0.04

@export_group("Flame Shape")
## 火焰往刀尖外側延伸的長度（公尺）。這是火舌生長空間，0 = 退回舊版貼刀身。
@export_range(0.0, 2.0, 0.01) var flame_extend := 0.55
## 火焰往刀根內側延伸（公尺）。少量即可，讓火焰包住刀身不是只長在單側。
@export_range(0.0, 0.5, 0.01) var flame_inset := 0.08
## 內層白熱核心的壽命倍率。核心收得比火舌快，揮刀才讀成「快」。
@export_range(0.15, 1.0, 0.01) var core_lifetime_ratio := 0.55
## ribbon 平滑細分：每兩個取樣點之間插入幾段。0 = 不平滑（快速揮刀會有折角）。
@export_range(0, 4, 1) var smooth_subdiv := 2

@export_group("Colors")
## 五層色階，預設取自參考圖：白熱 → 金黃 → 橙琥珀 → 朱紅 → 暗紅褐。
@export var core_color := Color(1.000, 0.984, 0.910)
@export var gold_color := Color(1.000, 0.847, 0.290)
@export var amber_color := Color(1.000, 0.616, 0.110)
@export var crimson_color := Color(0.914, 0.212, 0.110)
@export var ember_color := Color(0.231, 0.090, 0.075)
## 外焰發光強度。專案 glow_hdr_threshold 介於 1.05~1.25，低於此不進 bloom。
@export_range(0.0, 6.0, 0.05) var flame_emission := 2.2
## 內核發光強度。要明顯推過 HDR 門檻。
@export_range(0.0, 8.0, 0.05) var core_emission := 3.4
## 整體不透明度（給腳本淡入淡出用）。
@export_range(0.0, 1.0, 0.01) var opacity := 1.0

const FLAME_SHADER := preload("res://characters/yoriichi/vfx/sun_flame_trail.gdshader")
const CORE_SHADER := preload("res://characters/yoriichi/vfx/sun_flame_core.gdshader")

var is_emitting := false

## 預設值快照：型結束後 reset_form() 還原，已核准的普通刀光不得被上一招污染。
var _def_lifetime := 0.20
var _def_extend := 0.55
var _def_inset := 0.08
var _def_flame_emission := 2.2
var _def_core_emission := 3.4

## 多段 run：每次 start_trail() 開一段新 run，舊 run 照自己的壽命燒完。
## 以前是單一 _segments 且 start 就 clear —— 型尾巴拉到 0.5 s 後，
## 接招（cancel 窗、拾參型鏈式、旋轉斬中途換招）會讓上一刀的火當幀消失。
## 不能只是「不 clear 續接」：新招起手位置不同，會拉出一條連到舊尾的長四邊形。
var _runs: Array[Array] = []
var _flame_mesh: ImmediateMesh
var _core_mesh: ImmediateMesh
var _flame_mat: ShaderMaterial
var _core_mat: ShaderMaterial
var _core_mi: MeshInstance3D
var _travel := 0.0


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY

	_flame_mesh = ImmediateMesh.new()
	mesh = _flame_mesh
	_flame_mat = ShaderMaterial.new()
	_flame_mat.shader = FLAME_SHADER
	material_override = _flame_mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# ribbon 的 AABB 每幀重建，給足裕度避免快速揮刀時被視錐剔除。
	extra_cull_margin = 8.0

	# 內核是獨立 MeshInstance3D：兩層混色模式不同，無法共用一次 draw。
	_core_mi = MeshInstance3D.new()
	_core_mi.name = "FlameCore"
	_core_mi.top_level = true
	_core_mesh = ImmediateMesh.new()
	_core_mi.mesh = _core_mesh
	_core_mat = ShaderMaterial.new()
	_core_mat.shader = CORE_SHADER
	_core_mi.material_override = _core_mat
	_core_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_core_mi.extra_cull_margin = 8.0
	# 核心畫在外焰之上，否則會被外焰的實色蓋掉。
	_core_mat.render_priority = 1
	add_child(_core_mi)
	_core_mi.global_transform = Transform3D.IDENTITY

	_def_lifetime = lifetime
	_def_extend = flame_extend
	_def_inset = flame_inset
	_def_flame_emission = flame_emission
	_def_core_emission = core_emission
	_push_params()


## 套用型的刀光側寫（sun_breathing.gd FORMS[id].trail）。
## 火只從刀長出來：招式差異全在「尾巴留多久、火扇多寬、多亮」，
## 不另起以角色為圓心的幾何。缺欄位＝維持預設。
## 值要對著動畫實際時長填：0.37 s 的橫斬拖 0.6 s 尾巴，收招後火還掛著。
func apply_form(def: Dictionary) -> void:
	var t: Dictionary = def.get("trail", {})
	lifetime = float(t.get("lifetime", _def_lifetime))
	flame_extend = float(t.get("extend", _def_extend))
	flame_inset = float(t.get("inset", _def_inset))
	var gain := float(t.get("emission", 1.0))
	flame_emission = _def_flame_emission * gain
	core_emission = _def_core_emission * gain


## 還原普通刀光。_finish_attack / cancel 都要呼叫；拾參型鏈式
## _finish_attack → execute_form 會先 reset 再 apply，順序正確。
func reset_form() -> void:
	lifetime = _def_lifetime
	flame_extend = _def_extend
	flame_inset = _def_inset
	flame_emission = _def_flame_emission
	core_emission = _def_core_emission


## 把 @export 的顏色與強度推進兩個 shader。
## 使用者會在編輯器拉這些滑桿，所以每幀都推一次（ribbon 本來就每幀重建，成本可忽略）。
func _push_params() -> void:
	if _flame_mat != null:
		_flame_mat.set_shader_parameter("core_color", core_color)
		_flame_mat.set_shader_parameter("gold_color", gold_color)
		_flame_mat.set_shader_parameter("amber_color", amber_color)
		_flame_mat.set_shader_parameter("crimson_color", crimson_color)
		_flame_mat.set_shader_parameter("ember_color", ember_color)
		_flame_mat.set_shader_parameter("emission_strength", flame_emission)
		_flame_mat.set_shader_parameter("layer_alpha", opacity)
	if _core_mat != null:
		_core_mat.set_shader_parameter("core_color", core_color)
		_core_mat.set_shader_parameter("gold_color", gold_color)
		_core_mat.set_shader_parameter("emission_strength", core_emission)
		_core_mat.set_shader_parameter("layer_alpha", opacity)


func start_trail() -> void:
	is_emitting = true
	_travel = 0.0
	var run: Array = []
	if tip_node and base_node:
		run.append(_make_sample())
	_runs.append(run)


func stop_trail() -> void:
	is_emitting = false


## 記一個取樣點。存刀根、刀尖與累積行進距離；
## travel 用累積距離而非索引，舊點淘汰時 UV 不會整條重貼（火焰不會跳動）。
## life / extend / inset 都存在取樣點上：型結束 reset_form() 把參數切回預設時，
## 已經拖出來的尾巴要照原壽命、原寬度燒完，不能當幀縮形或消失。
func _make_sample() -> Dictionary:
	return {
		"tip": tip_node.global_position,
		"base": base_node.global_position,
		"age": 0.0,
		"life": maxf(lifetime, 0.0001),
		"extend": flame_extend,
		"inset": flame_inset,
		"travel": _travel,
	}


func _process(delta: float) -> void:
	_push_params()

	var r := 0
	while r < _runs.size():
		var run: Array = _runs[r]
		var i := 0
		while i < run.size():
			run[i].age += delta
			if run[i].age >= float(run[i].life):
				run.remove_at(i)
			else:
				i += 1
		# 已停止取樣且燒完的 run 丟掉；最後一段若仍在取樣則保留（可能暫時空）。
		if run.is_empty() and not (is_emitting and r == _runs.size() - 1):
			_runs.remove_at(r)
		else:
			r += 1

	if is_emitting and tip_node and base_node and not _runs.is_empty():
		var run: Array = _runs.back()
		var cur_tip: Vector3 = tip_node.global_position
		var should_add := true
		if not run.is_empty():
			var last_tip: Vector3 = run.back().tip
			if cur_tip.distance_squared_to(last_tip) < (min_distance * min_distance):
				should_add = false
		if should_add:
			if not run.is_empty():
				_travel += cur_tip.distance_to(run.back().tip)
			run.append(_make_sample())

	_rebuild()


## Catmull-Rom 插值：快速揮刀時取樣點稀疏，不插值會看到明顯折線。
func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


func _sample_at(run: Array, idx: int, key: String) -> Vector3:
	var c: int = clampi(idx, 0, run.size() - 1)
	return run[c][key]


## 重建兩層 ribbon：每個 run 各畫一段 strip（多 surface）。
## 外焰頂點往刀尖外推 extend、往刀根內縮 inset（取樣點自帶），給火舌生長空間；
## 內核維持刀身寬度，貼著刃走。
func _rebuild() -> void:
	_flame_mesh.clear_surfaces()
	_core_mesh.clear_surfaces()
	for run in _runs:
		if run.size() >= 2:
			_build_run(run)


func _build_run(run: Array) -> void:
	var n := run.size()
	var steps: int = maxi(smooth_subdiv, 0) + 1

	var flame_pts: Array[Dictionary] = []
	for idx in range(n - 1):
		for s in range(steps):
			var t := float(s) / float(steps)
			var base_p := _catmull(_sample_at(run, idx - 1, "base"), _sample_at(run, idx, "base"), _sample_at(run, idx + 1, "base"), _sample_at(run, idx + 2, "base"), t)
			var tip_p := _catmull(_sample_at(run, idx - 1, "tip"), _sample_at(run, idx, "tip"), _sample_at(run, idx + 1, "tip"), _sample_at(run, idx + 2, "tip"), t)
			var s0: Dictionary = run[idx]
			var s1: Dictionary = run[idx + 1]
			flame_pts.append({
				"base": base_p,
				"tip": tip_p,
				"age": lerpf(float(s0.age), float(s1.age), t),
				"life": lerpf(float(s0.life), float(s1.life), t),
				"extend": lerpf(float(s0.extend), float(s1.extend), t),
				"inset": lerpf(float(s0.inset), float(s1.inset), t),
				"travel": lerpf(float(s0.travel), float(s1.travel), t),
			})
	# 補上最後一個原始取樣點，否則 ribbon 會少一節、刀尖脫節。
	flame_pts.append(run[n - 1].duplicate())

	if flame_pts.size() < 2:
		return

	# --- 外焰層 ---
	_flame_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _flame_mat)
	for p in flame_pts:
		var base_p: Vector3 = p.base
		var tip_p: Vector3 = p.tip
		var dir := tip_p - base_p
		if dir.length_squared() < 0.000001:
			dir = Vector3.UP
		dir = dir.normalized()
		var inner := base_p - dir * float(p.inset)
		var outer := tip_p + dir * float(p.extend)

		var t: float = clampf(p.age / maxf(float(p.life), 0.0001), 0.0, 1.0)
		# 平方衰減：尾端收得快，刀光才有「甩出去」的錐形而不是等寬色帶。
		var alpha: float = (1.0 - t) * (1.0 - t)
		var c := Color(1, 1, 1, alpha)

		_flame_mesh.surface_set_color(c)
		_flame_mesh.surface_set_uv(Vector2(p.travel, 0.0))
		_flame_mesh.surface_add_vertex(inner)

		_flame_mesh.surface_set_color(c)
		_flame_mesh.surface_set_uv(Vector2(p.travel, 1.0))
		_flame_mesh.surface_add_vertex(outer)
	_flame_mesh.surface_end()

	# --- 內核層 ---
	# 核心壽命較短：超過該取樣點 life × ratio 的直接不畫。
	var core_pts: Array[Dictionary] = []
	for p in flame_pts:
		if p.age <= float(p.life) * core_lifetime_ratio:
			core_pts.append(p)
	if core_pts.size() < 2:
		return

	_core_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _core_mat)
	for p in core_pts:
		var core_life: float = maxf(float(p.life) * core_lifetime_ratio, 0.0001)
		var t: float = clampf(p.age / core_life, 0.0, 1.0)
		var alpha: float = (1.0 - t) * (1.0 - t)
		var c := Color(1, 1, 1, alpha)

		_core_mesh.surface_set_color(c)
		_core_mesh.surface_set_uv(Vector2(p.travel, 0.0))
		_core_mesh.surface_add_vertex(p.base)

		_core_mesh.surface_set_color(c)
		_core_mesh.surface_set_uv(Vector2(p.travel, 1.0))
		_core_mesh.surface_add_vertex(p.tip)
	_core_mesh.surface_end()

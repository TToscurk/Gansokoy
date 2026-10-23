extends WorldEnvironment
## 獸道 V1.3 大氣（generate_beast_path.gd 掛在 beast_path.tscn 根節點下）。
##
## 沿用 main 的 Environment（天空 shader、色調映射、SSAO、glow、霧密度、日夜環境光全部一樣），只覆寫兩個值：
##   · fog_sky_affect：main 預設 1.0＝天空整片被霧色 (0.78, 0.80, 0.82) 取代——灰白天空的根因
##     （同鏡位量測：畫面頂端 120 px 平均 RGB (197, 200, 201)、飽和度 15；設 0 時 (137, 164, 211)／85）。
##     0.5＝天空與雲露出一半，遠景仍罩一層霧，不會變成晴空廣告色（同鏡位比較 0／0.35／0.5，見 layout.atmosphere._choice）。
##   · fog_aerial_perspective：遠景的霧取天空色（樹林一層比一層淡藍），不靠加霧密度。
## 霧密度、霧色、日夜循環都不動。
##
## 只在 S04：S01–S03 已凍結（＝V1.2 的天空，main 的原值）。相機的 z 在 blend_z0 → blend_z1（與 bp_ground 的 S03／S04 接縫同一段，26 m）
##   之間線性淡入，走進 S04 的林間空地時天空慢慢打開；回 S03 再淡回去。沒有相機時＝S03 的值。
##
## 交接：main.gd 依「型別」找到圖裡的 WorldEnvironment → 讓出自己那份、離圖時還回去；
##       daynight.gd 的日夜環境光每 0.02 h 照樣套在這份複本上（它只改霧色／霧亮度、不碰這兩個值；圖裡沒有天象系統）。
##       map 是在 add_child 時進樹，那時 main 的 Environment 還沒被拿掉，所以這裡複製得到。
##       單獨開這張圖（沒有 Main）時不做事——和 V1.2 一樣沒有環境。

@export var fog_sky_affect := 0.5
@export var fog_aerial_perspective := 0.35
@export var blend_z0 := -340.0
@export var blend_z1 := -366.0
## 時刻：只在日高的時段生效。天空 shader 在太陽仰角 > 20° 時一律是正午的藍（晨昏染色只在 < 20°），
##   07:00／17:00（仰角約 25°）露出天空＝正午藍天配黃昏的暗光（第三輪 07／10／17 審圖抓到）；
##   霧色則由 DayNight 依時刻調暗調藍 → 低太陽時退回 V1.2（天空＝霧色，跟著時刻走）。
##   k＝DayNight 的日照係數（0 半夜～1 正午），k 在 day_k0 → day_k1 之間淡入（10:00 的 k＝0.89、07:00／17:00＝0.37）。
@export var day_k0 := 0.40
@export var day_k1 := 0.85
## 2026-10-18 荒野化：林中幽暗（gloom）——只在 S02／S03。相機 z 在 gloom_z[0]→[1] 淡入、[2]→[3] 淡出（淡出完才到 S03／S04 接縫 −340，
##   S04 與 BOSS 的大氣完全不受影響）。只動 daynight.gd 不寫的三個值：fog_density（main 0.0012）、adjustment_brightness、adjustment_saturation。
##   gloom_enabled＝false＝原樣。
@export var gloom_enabled := false
@export var gloom_z := PackedFloat32Array([-60.0, -112.0, -312.0, -336.0])
@export var gloom_fog_density := 0.008
@export var gloom_brightness := 0.88
@export var gloom_saturation_k := 0.88

var _base_sky := 1.0
var _base_aerial := 0.0
var _w := -1.0
var _base_fog := 0.0012
var _base_bright := 1.0
var _base_sat := 1.0
var _g := -1.0


func _enter_tree() -> void:
	if environment != null:
		return
	var src := _main_env()
	if src == null:
		push_warning("[beast_path] 找不到 main 的 Environment：大氣覆寫沒有生效")
		return
	var e := src.duplicate() as Environment
	_base_sky = e.fog_sky_affect
	_base_aerial = e.fog_aerial_perspective
	_base_fog = e.fog_density
	_base_bright = e.adjustment_brightness
	_base_sat = e.adjustment_saturation
	environment = e
	_apply(_weight())
	_apply_gloom(_gloom_weight())


func _process(_delta: float) -> void:
	if environment == null:
		return
	var w := _weight()
	if absf(w - _w) > 0.002:
		_apply(w)
	var g := _gloom_weight()
	if absf(g - _g) > 0.002:
		_apply_gloom(g)


## S04 的權重：0＝S03 以北或低太陽（main 的原值）、1＝S04 內且日高（本檔的值）
func weight() -> float:
	return maxf(_w, 0.0)


func _weight() -> float:
	var vp := get_viewport()
	var cam := vp.get_camera_3d() if vp != null else null
	if cam == null:
		return 0.0
	var ws := clampf((blend_z0 - cam.global_position.z) / maxf(blend_z0 - blend_z1, 0.01), 0.0, 1.0)
	return ws * _day_weight()


## DayNight 的日照係數 k（與 daynight.gd 的 _apply_ambient 同一式）→ day_k0..day_k1 平滑淡入；沒有 DayNight 時＝1
func _day_weight() -> float:
	var dn := get_tree().root.get_node_or_null("DayNight")
	if dn == null:
		return 1.0
	var hour := float(dn.get("hour"))
	var k := clampf((sin(PI * (hour - 6.0) / 12.0) + 0.18) / 1.18, 0.0, 1.0)
	return smoothstep(day_k0, day_k1, k)


func _apply(w: float) -> void:
	_w = w
	environment.fog_sky_affect = lerpf(_base_sky, fog_sky_affect, w)
	environment.fog_aerial_perspective = lerpf(_base_aerial, fog_aerial_perspective, w)


func _main_env() -> Environment:
	var main := get_tree().root.get_node_or_null("Main")
	if main == null:
		return null
	var we := main.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we != null and we.environment != null:
		return we.environment
	# 前一張圖自帶環境時，main 的那份已被拿掉、暫存在 _default_env
	return main.get("_default_env") as Environment


## 林中幽暗的權重（0＝原樣、1＝全幽暗）：只看相機 z
func _gloom_weight() -> float:
	if not gloom_enabled or gloom_z.size() < 4:
		return 0.0
	var vp := get_viewport()
	var cam := vp.get_camera_3d() if vp != null else null
	if cam == null:
		return 0.0
	var z := cam.global_position.z
	var a := smoothstep(gloom_z[0], gloom_z[1], z) if gloom_z[0] < gloom_z[1] else smoothstep(-gloom_z[0], -gloom_z[1], -z)
	var b := 1.0 - (smoothstep(-gloom_z[2], -gloom_z[3], -z))
	return clampf(minf(a, b), 0.0, 1.0)


func _apply_gloom(g: float) -> void:
	_g = g
	environment.fog_density = lerpf(_base_fog, gloom_fog_density, g)
	environment.adjustment_brightness = lerpf(_base_bright, _base_bright * gloom_brightness, g)
	environment.adjustment_saturation = lerpf(_base_sat, _base_sat * gloom_saturation_k, g)

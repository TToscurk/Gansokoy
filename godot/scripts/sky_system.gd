@tool
class_name 天象系統
extends Node3D
## Day-night cycle, weather and starfield for the village scenes.
##
## Why one node instead of three: sun angle, sky colour, fog density and cloud
## cover are not independent. Rain at noon must still be brighter than a clear
## midnight; stars may only appear once the sun is below the horizon; fog tints
## toward whatever the sky is doing. Splitting these into separate systems means
## every one of those couplings becomes a bug waiting to happen. One node owns
## the whole atmosphere and resolves the couplings in a fixed order.
##
## Design notes:
##   - Sun colour/energy comes from a measured-ish physical curve, not a linear
##     lerp: real daylight is near-constant through the middle of the day and
##     collapses fast at the horizon. A linear ramp makes 3pm look like sunset.
##   - The moon is a second DirectionalLight3D rather than a recoloured sun, so
##     dusk can have both in the sky at once, which is what actually happens.
##   - Stars live in the sky shader, not as particles or meshes: they must sit
##     at infinity and cost nothing.
##   - @tool so lighting can be judged in the editor. Art review needs to see
##     the 5pm look without entering play mode.
##
## Attach as a child of the map root. It creates and owns its own
## WorldEnvironment, sun and moon — do not also keep the scene's old ones, or
## the two lighting rigs will fight.

# ── 時間 ──────────────────────────────────────────────────────────────

## 一天中的時刻，0~24。6=日出、12=正午、18=日落、0=午夜。
@export_range(0.0, 24.0, 0.01) var 時刻: float = 10.0:
	set(v):
		時刻 = v
		_dirty = true

## 一個遊戲日等於幾分鐘的真實時間。0 = 停住時間（用來做美術審查）。
##
## ⚠ 只有在「沒有 DayNight autoload」時才由這裡推進時間。有 autoload 時
## 時間的權威是它——見 _process 的說明。
@export_range(0.0, 240.0, 0.5) var 一日長度分鐘: float = 0.0

## 太陽在天空中偏離正南的角度，決定日出日落的方位。
@export_range(-180.0, 180.0, 1.0) var 方位角: float = -30.0:
	set(v):
		方位角 = v
		_dirty = true

## 緯度感：值越大太陽越高，正午影子越短。幻想鄉設定在溫帶。
@export_range(20.0, 90.0, 1.0) var 正午高度: float = 62.0:
	set(v):
		正午高度 = v
		_dirty = true

# ── 天氣 ──────────────────────────────────────────────────────────────

enum 天氣類型 { 晴, 薄雲, 陰, 雨, 霧, 雪 }

@export var 天氣: 天氣類型 = 天氣類型.晴:
	set(v):
		天氣 = v
		_dirty = true

## 天氣切換的過渡秒數。真實天氣不會瞬間改變。
@export_range(0.0, 120.0, 1.0) var 天氣過渡秒數: float = 8.0

# ── 星空 ──────────────────────────────────────────────────────────────

## 星星密度。0 關閉星空。
@export_range(0.0, 1.0, 0.01) var 星星密度: float = 0.55:
	set(v):
		星星密度 = v
		_dirty = true

## 銀河亮度。
@export_range(0.0, 1.0, 0.01) var 銀河強度: float = 0.35:
	set(v):
		銀河強度 = v
		_dirty = true

@export var 顯示月亮: bool = true:
	set(v):
		顯示月亮 = v
		_dirty = true

# ── 概念圖雲層 ────────────────────────────────────────────────────────

## 從 人里skybox.png 抽出的雲層（tools/extract_sky_clouds.py）。天空顏色仍由
## 時刻計算，只借用畫裡的雲形，並依太陽位置重新打光。留空 = 純程序化雲。
@export var 概念圖雲層: Texture2D = preload("res://assets/sky/人里_clouds.png"):
	set(v):
		概念圖雲層 = v
		_dirty = true

## 0 = 只用程序化雲，1 = 只用概念圖雲。
@export_range(0.0, 1.0, 0.05) var 概念圖雲層比例: float = 1.0:
	set(v):
		概念圖雲層比例 = v
		_dirty = true

## 把整張畫繞垂直軸轉幾度，用來決定那團大積雲要落在哪個方位。
@export_range(-180.0, 180.0, 1.0) var 概念圖雲層方位: float = 0.0:
	set(v):
		概念圖雲層方位 = v
		_dirty = true

## 雲層緩慢漂移的速度。0 = 完全靜止。
@export_range(0.0, 0.02, 0.0005) var 概念圖雲層漂移: float = 0.0025:
	set(v):
		概念圖雲層漂移 = v
		_dirty = true

## 晴天時概念圖雲層還保留多少濃度。
##
## 概念圖的雲形是美術權威，不是天氣效果 —— 以前 shader 把它寫死成 0.35，
## 「晴」（雲量 0.10）會把畫裡的雲壓到 41% 不透明度，看起來就像沒有雲。
## 現在天氣只在這個底線之上「加厚」，所以調高雲量永遠會讓天空更濃。
## 1.0 = 不管什麼天氣都完整顯示畫裡的雲；0.0 = 晴天完全不畫（舊行為的極端）。
@export_range(0.0, 1.0, 0.05) var 概念圖雲層晴天濃度: float = 0.85:
	set(v):
		概念圖雲層晴天濃度 = v
		_dirty = true

# ── 品質 ──────────────────────────────────────────────────────────────

## 開啟後陰影更細緻但較耗效能。審查時建議開。
@export var 高品質陰影: bool = true:
	set(v):
		高品質陰影 = v
		_dirty = true

## 太陽是否投影。關掉＝整個場景無日照陰影，只給效能 A/B 用，不是美術選項。
@export var 太陽投影: bool = true:
	set(v):
		太陽投影 = v
		_dirty = true

## 高品質陰影關閉時的投影距離（公尺）。街道視角 100 m 外的陰影幾乎看不到，
## 但每一級 cascade 都要重畫整個村子的建物。
@export_range(40.0, 260.0, 5.0) var 陰影距離: float = 140.0:
	set(v):
		陰影距離 = v
		_dirty = true

## 定向光 cascade 級數（2 或 4）。每一級都是一次完整的場景陰影 pass；
## 街道視角 4 級把 5.6M 面畫成 28M。
@export_range(2, 4, 2) var 陰影分級: int = 4:
	set(v):
		陰影分級 = v
		_dirty = true

## 體積霧。GTX 1070 級顯卡上是固定的每幀成本；關掉改用深度霧（fog_enabled
## 仍開）。效能 A/B 用。
@export var 體積霧: bool = true:
	set(v):
		體積霧 = v
		_dirty = true

## 螢幕空間環境光遮蔽。效能 A/B 用。
@export var 環境光遮蔽: bool = true:
	set(v):
		環境光遮蔽 = v
		_dirty = true

@export var 編輯器中即時更新: bool = true

# ── 內部 ──────────────────────────────────────────────────────────────

const SKY_SHADER := "res://shaders/sky_daynight.gdshader"

var _sun: DirectionalLight3D
var _moon: DirectionalLight3D
var _env_node: WorldEnvironment
var _env: Environment
var _sky_mat: ShaderMaterial
var _dirty := true

# Current (smoothed) weather values; targets come from the enum.
var _cloud := 0.0
var _fog := 0.0
var _rain := 0.0
var _grey := 0.0


func _ready() -> void:
	_build()
	var t := _weather_targets()
	_cloud = t.x
	_fog = t.y
	_rain = t.z
	_grey = t.w
	var dn: Node = get_node_or_null("/root/DayNight")
	if dn != null and not Engine.is_editor_hint():
		時刻 = dn.get("hour")
	_apply()
	_dirty = false
	set_process(true)


func _process(delta: float) -> void:
	if Engine.is_editor_hint() and not 編輯器中即時更新:
		return

	# ── 時刻的單一權威 ──
	#
	# DayNight autoload（scripts/daynight.gd）持有 `hour`、吃 `--hour=` 旗標、
	# 驅動環境光下限與街燈點滅，而且 HUD 時鐘也是讀它。這個節點若自己另外
	# 推進一份時刻，場上就有兩套時間：實測過 DayNight 說 11:00、這裡說 6.85，
	# 太陽仰角 −11.3°（地平線以下），整排町家沒有光照到卻看起來像陰影，
	# 而 `--hour=11` 完全改不動畫面——因為它改的是 DayNight，這裡不讀。
	#
	# 所以：有 autoload 時以它為準，這個節點只負責「把時刻畫成天空」。
	# 沒有 autoload 時（例如 --script 工具直接載入場景）才自己走時鐘，
	# 那些情境下 一日長度分鐘 仍然有效。
	var dn: Node = get_node_or_null("/root/DayNight")
	if dn != null and not Engine.is_editor_hint():
		var h: float = dn.get("hour")
		if absf(h - 時刻) > 0.001:
			時刻 = h
			_dirty = true
	elif 一日長度分鐘 > 0.0 and not Engine.is_editor_hint():
		時刻 = fposmod(時刻 + delta * (24.0 / (一日長度分鐘 * 60.0)), 24.0)
		_dirty = true

	var t := _weather_targets()
	var rate: float = 1.0 if 天氣過渡秒數 <= 0.0 else delta / 天氣過渡秒數
	rate = clampf(rate, 0.0, 1.0)
	var before := Vector4(_cloud, _fog, _rain, _grey)
	_cloud = lerpf(_cloud, t.x, rate)
	_fog = lerpf(_fog, t.y, rate)
	_rain = lerpf(_rain, t.z, rate)
	_grey = lerpf(_grey, t.w, rate)
	var now := Vector4(_cloud, _fog, _rain, _grey)
	# An exponential lerp never reaches its target: it sat at ~0.001/frame for
	# minutes, re-running the whole _apply (sky shader, environment, sun, moon,
	# precipitation rebuild) every frame. Snap once we are within a hair and
	# stop dirtying. (probe_process_cost 2026-09-03: sky_system ≈ 400 ms/frame)
	if now.distance_to(t) < 0.002:
		_cloud = t.x
		_fog = t.y
		_rain = t.z
		_grey = t.w
		now = t
	if now.distance_to(before) > 0.0005:
		_dirty = true

	if _dirty:
		_apply()
		_dirty = false


## 天氣的四個數值：雲量、霧量、降雨、灰度（去飽和 + 壓對比）
func _weather_targets() -> Vector4:
	match 天氣:
		天氣類型.晴:
			return Vector4(0.10, 0.05, 0.0, 0.0)
		天氣類型.薄雲:
			return Vector4(0.38, 0.12, 0.0, 0.12)
		天氣類型.陰:
			return Vector4(0.85, 0.30, 0.0, 0.55)
		天氣類型.雨:
			return Vector4(0.95, 0.55, 1.0, 0.72)
		天氣類型.霧:
			return Vector4(0.55, 1.00, 0.0, 0.45)
		天氣類型.雪:
			return Vector4(0.80, 0.45, 0.0, 0.30)
	return Vector4(0.1, 0.05, 0.0, 0.0)


func _build() -> void:
	# Reuse existing children on re-entry so repeated _ready calls (editor
	# reloads) do not stack duplicate lights.
	_sun = get_node_or_null("太陽") as DirectionalLight3D
	if _sun == null:
		_sun = DirectionalLight3D.new()
		_sun.name = "太陽"
		add_child(_sun)
		if Engine.is_editor_hint() and owner:
			_sun.owner = owner

	_moon = get_node_or_null("月亮") as DirectionalLight3D
	if _moon == null:
		_moon = DirectionalLight3D.new()
		_moon.name = "月亮"
		add_child(_moon)
		if Engine.is_editor_hint() and owner:
			_moon.owner = owner

	_env_node = get_node_or_null("天空環境") as WorldEnvironment
	if _env_node == null:
		_env_node = WorldEnvironment.new()
		_env_node.name = "天空環境"
		add_child(_env_node)
		if Engine.is_editor_hint() and owner:
			_env_node.owner = owner

	if _env_node.environment == null:
		_env_node.environment = Environment.new()
	_env = _env_node.environment

	var sky := _env.sky
	if sky == null:
		sky = Sky.new()
		_env.sky = sky
	if not (sky.sky_material is ShaderMaterial):
		var sm := ShaderMaterial.new()
		var sh: Shader = load(SKY_SHADER)
		if sh == null:
			push_error("找不到天空著色器 %s" % SKY_SHADER)
		sm.shader = sh
		sky.sky_material = sm
	_sky_mat = sky.sky_material as ShaderMaterial
	_env.background_mode = Environment.BG_SKY
	# Radiance must refresh every frame or the ambient light stays stuck at
	# whatever time of day the sky was first baked at.
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	sky.process_mode = Sky.PROCESS_MODE_REALTIME

	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_env.ssao_enabled = true
	_env.ssao_intensity = 1.6
	_env.ssil_enabled = false
	_env.glow_enabled = true
	_env.glow_intensity = 0.55
	_env.glow_bloom = 0.05
	_env.glow_hdr_threshold = 1.1
	_env.fog_enabled = true
	_env.fog_mode = Environment.FOG_MODE_DEPTH
	_env.fog_sky_affect = 0.25
	_env.volumetric_fog_enabled = true
	_env.volumetric_fog_length = 320.0
	_env.volumetric_fog_gi_inject = 0.4


func _apply() -> void:
	if _sun == null:
		_build()
	if _sky_mat == null:
		return

	# ── 太陽位置 ──
	# Hour angle: 0 at midnight, sun crosses zenith at 12.
	var h := deg_to_rad((時刻 - 12.0) * 15.0)
	var peak := deg_to_rad(正午高度)
	# Elevation follows a cosine of hour angle scaled to the noon altitude, so
	# the sun sits high through the middle of the day and drops fast near dawn
	# and dusk — a straight lerp makes mid-afternoon read as evening.
	var sun_elev := asin(clampf(sin(peak) * cos(h), -1.0, 1.0))
	if 時刻 < 6.0 or 時刻 > 18.0:
		sun_elev = -abs(sun_elev)

	var az := deg_to_rad(方位角) + h
	var sun_dir := Vector3(
		cos(sun_elev) * sin(az),
		sin(sun_elev),
		cos(sun_elev) * cos(az)
	).normalized()

	_sun.rotation = Vector3.ZERO
	# look_at_from_position aims the node's -Z at the target, and a
	# DirectionalLight3D emits along its -Z. So to make light travel FROM the
	# sun's position TOWARD the scene, the light must look at -sun_dir... but
	# that is what inverts the elevation. Aim at +sun_dir's opposite explicitly:
	# stand at the sun and look at the origin.
	_sun.look_at_from_position(sun_dir * 100.0, Vector3.ZERO, Vector3.UP)

	# ── 太陽亮度與色溫 ──
	var above := sun_dir.y            # -1..1
	var day := smoothstep(-0.10, 0.16, above)   # 0 night, 1 day
	# Direct sun strength must keep tracking elevation AFTER sunrise, or every
	# hour from 7am to 5pm renders identically — the first sweep showed a flat
	# 1.550 across the whole day, which is why afternoons looked like noon.
	# Air mass thins as the sun climbs, so brightness keeps rising to the zenith.
	var climb := smoothstep(0.0, 0.85, maxf(above, 0.0))
	var 直射強度 := day * lerpf(0.55, 1.0, climb)
	# The warm band is narrow: only within a few degrees of the horizon.
	var golden := 1.0 - smoothstep(0.0, 0.28, maxf(above, 0.0))
	golden *= smoothstep(-0.12, 0.02, above)

	var 正午色 := Color(1.0, 0.97, 0.92)
	var 黃昏色 := Color(1.0, 0.62, 0.34)
	var sun_col := 正午色.lerp(黃昏色, golden)
	# Overcast greys and dims the direct light; rain more so.
	sun_col = sun_col.lerp(Color(0.82, 0.85, 0.90), _grey * 0.8)

	_sun.light_color = sun_col
	_sun.light_energy = 直射強度 * lerpf(1.55, 0.42, _grey)
	_sun.visible = _sun.light_energy > 0.005
	# Overcast light is diffuse — soften the shadows rather than only dimming.
	_sun.shadow_enabled = 太陽投影
	_sun.light_angular_distance = lerpf(0.6, 7.0, _grey)
	_sun.directional_shadow_max_distance = 260.0 if 高品質陰影 else 陰影距離
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if 陰影分級 >= 4 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	_sun.directional_shadow_split_1 = 0.06
	_sun.directional_shadow_split_2 = 0.16
	_sun.directional_shadow_split_3 = 0.42
	_sun.directional_shadow_blend_splits = true
	_sun.shadow_bias = 0.04
	_sun.shadow_normal_bias = 1.4

	# ── 月亮 ──
	var moon_dir := -sun_dir
	_moon.rotation = Vector3.ZERO
	_moon.look_at_from_position(moon_dir * 100.0, Vector3.ZERO, Vector3.UP)
	var night := 1.0 - day
	_moon.light_color = Color(0.62, 0.72, 0.95)
	_moon.light_energy = night * 0.16 * lerpf(1.0, 0.25, _grey) * (1.0 if 顯示月亮 else 0.0)
	_moon.visible = _moon.light_energy > 0.005
	_moon.shadow_enabled = 顯示月亮 and night > 0.5 and _grey < 0.5
	_moon.light_angular_distance = 1.2

	# ── 環境 ──
	# Ambient tracks the sky but never reaches zero: a pitch-black night is
	# unreadable and nothing in this game is meant to be unlit.
	_env.ambient_light_sky_contribution = 1.0
	_env.ambient_light_energy = lerpf(0.18, 1.0, maxf(day * 0.35 + climb * 0.65, 0.0)) * lerpf(1.0, 1.25, _grey)
	_env.tonemap_exposure = lerpf(1.18, 0.98, day)
	_env.adjustment_enabled = true
	_env.adjustment_saturation = lerpf(1.05, 0.72, _grey) * lerpf(0.86, 1.0, day)
	_env.adjustment_contrast = lerpf(1.0, 0.93, _grey)

	# Fog colour follows the sky rather than staying a fixed grey, or dusk fog
	# reads as smoke.
	var 霧色 := Color(0.70, 0.78, 0.86).lerp(Color(0.92, 0.68, 0.52), golden * 0.7)
	霧色 = 霧色.lerp(Color(0.10, 0.13, 0.20), night * 0.85)
	霧色 = 霧色.lerp(Color(0.74, 0.76, 0.79), _grey * 0.6)
	_env.fog_light_color = 霧色
	# Night fog must be far thinner than day fog. The same density that reads as
	# gentle haze at noon turns the whole night sky into grey soup, which is the
	# "everything looks blurry" the user reported — it was fog and glow, not DOF.
	var 夜間霧折減 := lerpf(0.28, 1.0, day)
	_env.fog_density = lerpf(0.00018, 0.0075, _fog) * 夜間霧折減
	_env.fog_sun_scatter = 0.28 * day
	# Volumetric fog is the bigger offender: it scatters the moon into a huge
	# soft blob and smears every silhouette. Keep it for genuinely foggy/rainy
	# weather, cut it hard on clear nights.
	_env.volumetric_fog_density = lerpf(0.0012, 0.024, _fog) * lerpf(0.15, 1.0, day)
	_env.volumetric_fog_albedo = 霧色
	_env.volumetric_fog_emission = Color(0, 0, 0)
	_env.volumetric_fog_enabled = 體積霧 and (_fog > 0.12 or day > 0.25)
	_env.ssao_enabled = 環境光遮蔽

	# Glow bloom bleeds the moon across the sky at night. Lower the intensity and
	# raise the threshold so only genuinely bright things bloom — lanterns and
	# the moon disc, not the whole sky gradient.
	_env.glow_intensity = lerpf(0.30, 0.55, day)
	_env.glow_hdr_threshold = lerpf(1.8, 1.1, day)

	# ── 降水 ──
	# The precipitation node is optional: scenes that only need lighting do not
	# have to carry particle cost. Look it up each apply rather than caching, so
	# adding one later just works without a restart.
	var 降水 := get_node_or_null("降水") 
	if 降水 != null and 降水.has_method("set"):
		var 是雪 := 天氣 == 天氣類型.雪
		降水.set("降水種類", 1 if 是雪 else 0)
		var amount := _rain
		if 是雪:
			# Snow is not in the rain channel; drive it from cloud cover so the
			# 雪 weather actually snows.
			amount = clampf(_cloud, 0.0, 1.0)
		降水.set("強度", amount)

	# ── 天空著色器 ──
	_sky_mat.set_shader_parameter("sun_dir", sun_dir)
	_sky_mat.set_shader_parameter("day_amount", day)
	_sky_mat.set_shader_parameter("golden", golden)
	_sky_mat.set_shader_parameter("cloud_cover", _cloud)
	_sky_mat.set_shader_parameter("overcast", _grey)
	_sky_mat.set_shader_parameter("star_density", 星星密度)
	_sky_mat.set_shader_parameter("milkyway", 銀河強度)
	_sky_mat.set_shader_parameter("moon_visible", 1.0 if 顯示月亮 else 0.0)
	_sky_mat.set_shader_parameter("moon_dir", moon_dir)
	# Painted cloud layer: a null texture must also zero the mix, or the shader
	# samples a default white and the whole sky reads as overcast.
	_sky_mat.set_shader_parameter("painted_clouds", 概念圖雲層)
	_sky_mat.set_shader_parameter("painted_mix", 概念圖雲層比例 if 概念圖雲層 != null else 0.0)
	_sky_mat.set_shader_parameter("painted_yaw", 概念圖雲層方位)
	_sky_mat.set_shader_parameter("painted_base", 概念圖雲層晴天濃度)
	_sky_mat.set_shader_parameter("painted_drift", 概念圖雲層漂移)


## 給遊戲程式呼叫：平順地切到某個天氣。
func 切換天氣(新天氣: 天氣類型, 過渡秒數: float = -1.0) -> void:
	if 過渡秒數 >= 0.0:
		天氣過渡秒數 = 過渡秒數
	天氣 = 新天氣


## 給遊戲程式呼叫：直接跳到某個時刻。
func 設定時刻(小時: float) -> void:
	時刻 = fposmod(小時, 24.0)
	_dirty = true
	_apply()

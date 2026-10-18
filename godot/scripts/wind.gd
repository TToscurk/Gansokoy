extends Node
## 幻想鄉全域風場 V1（autoload：Wind）
##
## 為什麼是一個 autoload 而不是每個場景各自一份：
## 人里 V2、獸道 s01–s04、神社、trail、slice 都用同一批植被材質（veg_leaf／veg_bark／
## meadow_grass／p8_paddy_plant／grass_wind）。風只有一個來源，換圖時方向與陣風相位才接得上；
## 每個場景各寫一份 wind 參數會讓跨圖過場時整片植被瞬間換風。
##
## 分工：
##   本檔＝風場狀態機（方向、強度、陣風、平滑過渡、空間取樣、除錯 API）。
##   shader＝把風場套到頂點上（GPU，逐實例相位）：場公式唯一實作在 assets/shaders/wind_field.gdshaderinc，
##     樹／竹在 veg_kit/veg_common.gdshaderinc，草在 meadow_grass／grass_wind／p8_paddy_plant。
## 兩者只透過 global shader uniform 溝通：每幀上傳 gw_dir／gw_strength／gw_gust／gw_time／gw_flutter／gw_ctrl，
##   事件、遮蔽、物種、陣風響應是小貼圖（gw_events 4×3、gw_shelters 8×2、gw_species N×5、gw_resp 65×4N），
##   只在變動時更新。
##   不逐棵樹、不逐叢草寫 CPU 資料，MultiMesh 也不需要重建。
##
## V1.2（高度加權植被動態）：
##   行進陣風事件（_events）：每道陣風從上風處以 GUST_SPEED 推進、有限寬，植物依位置先後被掃到。
##   垂直風剖面（gw_vprof）：離地愈高風愈強（冪律）＋海拔增益；與水平空間場相乘，不取代。
##   物種表（WindSpeciesTable）：stiffness／bend／tip／lag／damping／flutter／max_deform…逐物種可調。
##   植被接線：節點進場時依 mesh 名稱設 wind_sp（物種＋局部高度）與 extra_cull_margin（剔除邊界容納變形）。
##
## 單位約定：
##   strength 0–1.5 ＝ 風場強度（不是 m/s）。各 shader 用自己的校準常數換成公尺：
##     BREEZE(0.55) 下樹冠葉卡尖端約 6–18 cm、草尖約 5–9 cm、竹梢約 4–7 cm。
##   sample_wind() 另外回傳「近似 m/s」給之後的頭髮／羽織／玩法用（strength × 6）。
##
## 不在 V1：完整天氣、風推動角色、空氣動力戰鬥、布料模擬、樹木破壞。

signal preset_changed(name: String)
signal gust_triggered(strength: float)
signal wind_toggled(enabled: bool)

## 預設值＝Light Breeze。Calm 讓環境幾乎靜止；GUST 是「強陣風」測試狀態。
enum Preset { CALM, BREEZE, MODERATE, GUST }

const PRESET_NAMES := {
	Preset.CALM: "calm",
	Preset.BREEZE: "breeze",
	Preset.MODERATE: "moderate",
	Preset.GUST: "gust",
}

## base＝穩定風；gust＝陣風振幅（會疊在 base 上）；period／hold＝自動陣風的節奏。
## 兩個不同週期的脈衝相加 → 不會每 N 秒機械式重複同一個陣風。
const PRESETS := {
	Preset.CALM: {
		"base": 0.04, "gust": 0.00, "period": 0.0, "hold": 0.0,
		"flutter": 0.15, "label": "Calm",
	},
	Preset.BREEZE: {
		"base": 0.55, "gust": 0.18, "period": 11.0, "hold": 3.4,
		"flutter": 1.0, "label": "Light Breeze",
	},
	Preset.MODERATE: {
		"base": 0.88, "gust": 0.26, "period": 8.0, "hold": 3.0,
		"flutter": 1.35, "label": "Moderate Wind",
	},
	Preset.GUST: {
		"base": 1.10, "gust": 0.45, "period": 5.5, "hold": 2.6,
		"flutter": 1.8, "label": "Strong Gust",
	},
}

## 過渡時間常數（秒）。指數趨近＝永遠不會瞬間跳方向或跳強度。
const TAU_STRENGTH := 1.35
const TAU_ANGLE := 1.9
## 關風時用比較快的斜坡（但仍不是 0 幀切斷），免得放開除錯鍵後整片植被還在動 5 秒。
const TAU_OFF := 0.45
## 手動陣風的最短／最長長度。
const GUST_MIN := 0.8
const GUST_MAX := 8.0

# ── 隨機但可重現的風場（Wind V1.1） ───────────────────────────────
## 空間場的兩個波向量。shader 與 GDScript 用同一組常數 → 植被與道具吃到同一個場。
## 波長：k1 ≈ 27 m（大塊風袋）、k2 ≈ 35 m（次級不均）。
const FIELD_K1 := Vector2(0.045, 0.031)
const FIELD_K2 := Vector2(-0.021, 0.038)
## 方向／強度的空間擾動幅度（弧度／倍率）
const FIELD_DIR_A1 := 0.38
const FIELD_DIR_A2 := 0.12
const FIELD_STR_A1 := 0.28
const FIELD_STR_A2 := 0.14
## 全域風向每隔 7–18 s 挑一個新目標，單次最多轉 50°，再用 tau 5.5 s 慢慢過去。
## → 會有緩慢轉向與「繞一圈」的風，但永遠不會一幀 180° 掉頭。
const TURN_MIN := 7.0
const TURN_MAX := 18.0
const TURN_MAX_DEG := 50.0
const TAU_TURN := 5.5
## 低頻強弱起伏（lull）：0.55–1.0 倍，週期 ~40 s。讓陣風不是等間隔。
const LULL_MIN := 0.55

# ── 行進陣風（Wind V1.2） ───────────────────────────────
## 陣風前緣推進速度（m/s）、生成在焦點上風多遠、橫向半寬（m）、最多同時幾道（= shader 迴圈上限）。
const GUST_SPEED := 9.0
const GUST_LEAD := 20.0
const GUST_HALF_WIDTH := 38.0
const MAX_EVENTS := 4
## 前緣掃過焦點後再走多遠才回收（m）：植被 shader 只在相機 60 m 內算風，再遠的前緣只是空跑迴圈。
const GUST_TRAVEL_TAIL := 60.0

# ── 垂直風剖面（Wind V1.2） ─────────────────────────────
## 強度 ×clamp((z/z0)^α, 0.55, 1.9) × clamp(1 + gain·(根部 y − ref), 0.7, 1.5)
## z0＝0.6 m（草尖）→ 草的外觀維持 P9 審定；12 m 樹冠約 ×1.6。
const VPROF_DEFAULT := Vector4(0.16, 0.6, 0.0, 0.02)

const SPECIES_TABLE_PATH := "res://data/wind/wind_species.tres"
const SHELTER_SLOTS := 8
const VEG_TREE_SHADERS := ["veg_leaf.gdshader", "veg_bark.gdshader"]
const VEG_GRASS_SHADERS := ["meadow_grass.gdshader", "grass_wind.gdshader", "p8_paddy_plant.gdshader"]

var enabled := true
var preset: int = Preset.BREEZE
## 決定性種子：同一個 seed＋同一串 dt 會得到完全一樣的風。
var seed_value := 20261018
var _rng := RandomNumberGenerator.new()
var _angle := deg_to_rad(38.0)
var _target_angle := _angle
var _dir_goal := _angle
var _turn_in := 0.0
var _lull := 1.0
var _shelters: Array = []     # {pos: Vector3, radius: float, factor: float, top: float}
var _strength := 0.0
var _target_strength := 0.0
var _gust := 0.0
## 焦點處的行進陣風（V1.2；由 _events 算出，不是獨立狀態）
var _flutter := 1.0
var _time := 0.0
var _time_scale := 1.0
var _frozen := false
## 事件／劇情覆寫（優先於 preset）。空＝沒有覆寫。
var _override := {}
var _last_preset := -1

## 行進陣風事件（V1.2）。每筆：o (Vector2)、t0、amp、dir (Vector2)、dur、speed、hw、seed。
var _events: Array = []
var _events_dirty := true
var _gust_rng := RandomNumberGenerator.new()
var _auto_in := 2.0
## 開關風時陣風總增益的平滑值（0–1）
var _gust_gain := 1.0
## 焦點：陣風在它上風處生成、遮蔽依離它的距離挑最近 8 個。預設跟主相機；set_focus() 可鎖定。
var _focus := Vector3.ZERO
var _focus_locked := false
var _vprof := VPROF_DEFAULT
## 局部風力差異倍率（空間場方向／強度擾動的振幅；1＝V1.1 設計值）。shader 端＝gw_tune.x。
var _local_var := 1.0
## 陣風振幅覆寫（風場強度單位；<0＝用 preset 的 gust）。除錯面板「陣風強度」寫這個。
var _gust_amp_override := -1.0
var _debug_view := 0
var _ev_img: Image
var _ev_tex: ImageTexture
var _sh_img: Image
var _sh_tex: ImageTexture
var _sh_t := 0.0
var _shelters_dirty := true
var _shelter_n := 0
var _sp_img: Image
var _sp_tex: ImageTexture
## 陣風×物種的樹冠響應查表（gw_resp，65 × MAX_EVENTS·N，R32F）
var _rs_img: Image
var _rs_tex: ImageTexture
var _species_table: WindSpeciesTable
var _species_index := {}
## 植被接線統計（物種 → 節點數）與沒對到物種表的 mesh 名稱
var _veg_stats := {}
var _veg_unknown := {}
## 接線快取：(mesh, material_override) → [kind, 物種名, Vector4 wind_sp, cull margin]。
## 村裡 13 萬個植被節點只用到幾百種 mesh；不快取時接線讓 village_v2 載入多 ~0.7 s。
var _veg_cache := {}

# ── 水面場（Wind V2 Phase E） ─────────────────────────────
## 已接線的河（WaterField）；null＝目前地圖沒有接線的水體（取樣回傳 NAN／零流）。
var water: WaterField = null
var _river_node: MeshInstance3D = null
## 河名 → 中心線來源（layout JSON 的 water.<名> pts／half_w）。只接這些；其他水體維持原材質。
const RIVER_SOURCES := {"MainRiver": "res://maps/village_v2/layout_v2.json"}
const RIVER_SHADER := "res://assets/shaders/water.gdshader"
const RIVER_NORMAL_TEX := "res://assets/textures/terrain_grass_nor_gl.jpg"
const RIVER_FLOW_SPEED := 0.55
const FLOW_CACHE_DIR := "user://wind_flow_cache"

## 除錯 UI（F9）。只有 debug build 才會建立；release 不會出現。
const DEBUG_KEY := KEY_F9
var _debug_ui: CanvasLayer = null
const DEBUG_PANEL := "res://scripts/wind/wind_debug_panel.gd"
var _mouse_before := -1
var _debug_on := false

## 布料（暖簾）接線用的共用材質；第一次碰到 noren 才建立。
const CLOTH_SHADER := "res://assets/shaders/wind_cloth.gdshader"
const KIT_MAT_PATH := "res://assets/village_v2/machiya_kit/V2_MachiyaKit.tres"
var _cloth_mat: ShaderMaterial = null
var _cloth_mats := {}
var _cloth_n := 0
var _cloth_nodes: Array = []
var _cloth_t := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = seed_value
	_gust_rng.seed = seed_value + 1
	_turn_in = _rng.randf_range(2.0, 6.0)
	_auto_in = _gust_rng.randf_range(1.5, 4.0)
	_init_textures()
	_load_species()
	_apply_preset(Preset.BREEZE, true)
	# 命令列覆寫（A/B、錄影、審圖用）：--wind=off|calm|breeze|moderate|gust
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--wind="):
			var v := arg.substr(7)
			if v == "off":
				enabled = false
				_strength = 0.0
				_gust = 0.0
			else:
				var idx: Variant = PRESET_NAMES.find_key(v)
				if idx != null:
					_apply_preset(int(idx), true)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--wind-params="):
			_apply_params_arg(arg.substr(14))
	_push_globals()
	# 植被接線（V1.2）：release 也要（物種／高度／剔除邊界）；WIND_NO_VEG_WIRE=1 可跳過做 A/B。
	if not OS.has_environment("WIND_NO_VEG_WIRE"):
		get_tree().node_added.connect(_on_node_added_veg)
	# V2 Phase G：暖簾／竹簾／吊燈籠／生物接線在 release 也開（正式整合，不再只是 debug）。
	# 診斷用：WIND_NO_CLOTH=1 可完全跳過（量載入成本或 A/B 用）。
	if not OS.has_environment("WIND_NO_CLOTH"):
		get_tree().node_added.connect(_on_node_added)
		_scan_existing_cloth()
	if OS.is_debug_build():
		if "--wind-debug" in OS.get_cmdline_user_args():
			_set_debug_visible(true)
	_print_startup()


func _apply_params_arg(v: String) -> void:
	var txt := v
	if v.begins_with("res://") or v.begins_with("user://") or FileAccess.file_exists(v):
		txt = FileAccess.get_file_as_string(v)
	var d: Variant = JSON.parse_string(txt)
	if d is Dictionary:
		apply_params(d)
		print("[Wind] 套用測試參數 %s" % JSON.stringify(get_params()))
	else:
		push_warning("[Wind] --wind-params 不是 JSON：%s" % v)


func _print_startup() -> void:
	print("[Wind] V1 %s；preset=%s enabled=%s  dir=%.0f°  base=%.2f  eff=%.2f" % [
		"debug" if OS.is_debug_build() else "release",
		PRESET_NAMES[preset], str(enabled), rad_to_deg(_angle), _target_strength,
		(_strength + _gust) if enabled else 0.0])
	if OS.is_debug_build():
		print("[Wind] F9 開 Wind Debug 面板（滑桿＋1–4 預設、G 陣風、H 熱圖、0 開關風、[ ] 方向、- = 強度）")


# ───────────────────────── 公開 API ─────────────────────────

## 切換預設。direction 不會因為換預設而跳動 —— 同一個風場只換強度與陣風節奏。
func set_preset(p: int) -> void:
	if not PRESETS.has(p):
		push_warning("[Wind] 未知 preset %s" % p)
		return
	_override.clear()
	_apply_preset(p, false)
	preset_changed.emit(PRESET_NAMES[p])


## 直接指定風向與強度（deg：風「吹向」的方位，0=+X、90=+Z）。
## 這是給劇情事件／技能／之後天氣系統用的低階入口；不會清掉 preset 的陣風節奏。
func set_wind(direction_deg: float, strength: float) -> void:
	_target_angle = deg_to_rad(direction_deg)
	_target_strength = clampf(strength, 0.0, 2.0)
	_override = {"mode": "manual"}


## 事件用：暫時覆寫風（例如「龍捲風來襲」），結束後呼叫 clear_override() 回到 preset。
func set_override(direction_deg: float, strength: float, seconds := 6.0) -> Dictionary:
	_override = {
		"mode": "timed",
		"until": _time + maxf(seconds, 0.1),
		"angle": deg_to_rad(direction_deg),
		"strength": clampf(strength, 0.0, 2.0),
	}
	return _override.duplicate()


func clear_override() -> void:
	_override.clear()
	_apply_preset(preset, false)


# ── V2 合約介面（docs/風力系統.md §2.1）────────────────────────────
# 單位：strength＝風場強度 0–2（1.0 ≈ 6 m/s）；方向＝世界 XZ 平面「吹向」，deg 0＝+X、90＝+Z。

## preset 以名稱切換（calm／breeze／moderate／gust）。
func set_wind_preset(preset_id: StringName) -> bool:
	var idx: Variant = PRESET_NAMES.find_key(String(preset_id))
	if idx == null:
		push_warning("[Wind] 未知 preset %s" % preset_id)
		return false
	set_preset(int(idx))
	return true


## 以向量指定目標風（direction 只取 XZ；會平滑轉過去，不瞬跳）。
func set_wind_target(direction: Vector3, strength: float) -> void:
	var d := Vector2(direction.x, direction.z)
	var deg := rad_to_deg(_target_angle) if d.length() < 1e-4 else rad_to_deg(atan2(d.y, d.x))
	set_wind(deg, strength)


## 換種子：重設 RNG（風向排程與自動陣風），時間與目前狀態不動。同 seed＋同 dt 序列 → 同結果。
func set_wind_seed(seed: int) -> void:
	seed_value = seed
	_rng.seed = seed
	_gust_rng.seed = seed + 1
	_turn_in = _rng.randf_range(2.0, 6.0)
	_auto_in = _gust_rng.randf_range(1.5, 4.0)


## 風場強度（不是 m/s）。agl＝離地高度（不給＝不套垂直剖面）。
func sample_wind_strength(world_position: Vector3, agl := -1.0) -> float:
	return float(sample_field(world_position, agl)["strength"])


## 指定時間取樣：空間擾動、front 波、行進陣風都依 time_sec 計算；全域風向／基礎強度用目前狀態
## （那兩個是狀態機的積分結果，不是時間的純函數）。回傳近似風速向量 m/s。
func sample_wind_at(world_position: Vector3, time_sec: float, agl := -1.0) -> Vector3:
	var keep := _time
	_time = time_sec
	var v := sample_wind(world_position, agl)
	_time = keep
	return v


## 局部風力差異（0–2；1＝預設）。同時影響 CPU 取樣與植被 shader（gw_tune.x）。
func set_local_variation(v: float) -> void:
	_local_var = clampf(v, 0.0, 2.0)


func get_local_variation() -> float:
	return _local_var


## 陣風振幅覆寫（0–1.5 風場強度；<0＝回到 preset 預設）。
func set_gust_amplitude(v: float) -> void:
	_gust_amp_override = v if v < 0.0 else clampf(v, 0.0, 1.5)


func gust_amplitude() -> float:
	return _gust_amp_override if _gust_amp_override >= 0.0 else float(PRESETS[preset]["gust"])


func is_manual() -> bool:
	return not _override.is_empty()


## 測試參數（除錯面板「複製測試參數」的內容）。apply_params() 吃同一格式；
## 命令列 --wind-params=<JSON 字串或 res://／絕對路徑> 開機即套用（審圖／錄影重現用）。
func get_params() -> Dictionary:
	return {
		"wind_params": 1,
		"seed": seed_value,
		"preset": PRESET_NAMES[preset],
		"enabled": enabled,
		"manual": is_manual(),
		"direction_deg": snappedf(wrapf(rad_to_deg(_target_angle), 0.0, 360.0), 0.1),
		"strength": snappedf(_target_strength, 0.001),
		"gust_amplitude": snappedf(gust_amplitude(), 0.001),
		"local_variation": snappedf(_local_var, 0.001),
		"vertical_profile": [_vprof.x, _vprof.y, _vprof.z, _vprof.w],
		"time": snappedf(_time, 0.01),
	}


func apply_params(d: Dictionary) -> void:
	if d.has("seed"):
		set_wind_seed(int(d["seed"]))
	if d.has("preset"):
		set_wind_preset(StringName(str(d["preset"])))
	if d.has("enabled"):
		set_enabled(bool(d["enabled"]))
	if d.has("gust_amplitude"):
		set_gust_amplitude(float(d["gust_amplitude"]))
	if d.has("local_variation"):
		set_local_variation(float(d["local_variation"]))
	if d.has("vertical_profile"):
		var vp: Array = d["vertical_profile"]
		set_vertical_profile(float(vp[0]), float(vp[1]), float(vp[2]), float(vp[3]))
	if bool(d.get("manual", false)) and d.has("direction_deg") and d.has("strength"):
		set_wind(float(d["direction_deg"]), float(d["strength"]))


## 手動陣風（V1.2：行進事件）。origin＝陣風生成點；預設在焦點上風 GUST_LEAD m，
## 所以前緣約 GUST_LEAD / GUST_SPEED ≈ 2.2 s 後抵達焦點，再依位置先後掃過其他植物。
func trigger_gust(strength := -1.0, duration := -1.0, origin: Variant = null) -> void:
	var amp := strength if strength > 0.0 else maxf(0.35, gust_amplitude() * 2.2)
	amp = clampf(amp, 0.05, 1.5)
	var dur := clampf(duration, GUST_MIN, GUST_MAX) if duration > 0.0 else 2.8
	var o: Vector3 = origin if origin is Vector3 else _focus - wind_direction() * GUST_LEAD
	_spawn_event(Vector2(o.x, o.z), amp, dur, _gust_rng.randf())
	gust_triggered.emit(amp)


## 完全關風（平滑降到 0）／恢復目前 preset。
func set_enabled(v: bool) -> void:
	if enabled == v:
		return
	enabled = v
	if v:
		_apply_preset(preset, false)
	else:
		_target_strength = 0.0
	wind_toggled.emit(v)


func toggle_enabled() -> void:
	set_enabled(not enabled)


func is_enabled() -> bool:
	return enabled


## 目前風場狀態。direction_deg＝吹向；strength＝基礎風（含 lull，不含陣風）；
## gust＝焦點處的行進陣風；effective＝焦點處 strength＋gust。
func get_wind() -> Dictionary:
	return {
		"preset": PRESET_NAMES[preset],
		"enabled": enabled,
		"direction_deg": rad_to_deg(_angle),
		"target_direction_deg": rad_to_deg(_target_angle),
		"strength": _strength,
		"base_strength": _target_strength,
		"gust": _gust,
		"effective": _strength + _gust,
		"time": _time,
		"events": _events.size(),
		"focus": _focus,
	}


func wind_direction() -> Vector3:
	return Vector3(cos(_angle), 0.0, sin(_angle))


## 給角色／玩法用的空間取樣：同一點的結果可重現（純函式，只吃位置與風時鐘）。
## 回傳近似風速向量（m/s）。方向／強度都吃與 shader 同一組空間場 → 植被與道具同步。
func sample_wind(world_pos: Vector3, agl := -1.0) -> Vector3:
	var f := sample_field(world_pos, agl)
	return Vector3(cos(float(f["angle"])), 0.0, sin(float(f["angle"]))) * float(f["speed"])


## 公開的場取樣（道具／除錯用）：回傳 angle（弧度）、strength（0–2）、speed（近似 m/s）、gust（行進陣風）。
## 與 wind_field.gdshaderinc 的 wf_force 是同一個量：
##   strength = env × (基礎風 × 空間倍率 × (0.85 + 0.30·front) + 行進陣風)
##   env = 海拔 × 遮蔽 ×（agl ≥ 0 時）垂直剖面。agl＝離地高度（m）；不給＝不套剖面（道具維持 V1.1 校準）。
func sample_field(world_pos: Vector3, agl := -1.0) -> Dictionary:
	var p := Vector2(world_pos.x, world_pos.z)
	var n1 := 0.5 + 0.5 * sin(p.dot(FIELD_K1) + _time * 0.11)
	var n2 := 0.5 + 0.5 * sin(p.dot(FIELD_K2) + _time * 0.07)
	var ang := _angle + _local_var * (FIELD_DIR_A1 * (n1 - 0.5) + FIELD_DIR_A2 * (n2 - 0.5))
	# 前緣波：沿風向以 ~12.5 m/s 推進。CPU 物件與 shader 用同一個式子。
	var wd := Vector2(cos(ang), sin(ang))
	var front := 0.5 + 0.5 * sin(_time * 1.25 - p.dot(wd) * 0.10)
	var m := (1.0 + _local_var * FIELD_STR_A1 * (n1 - 0.5)) * (1.0 + _local_var * FIELD_STR_A2 * (n2 - 0.5))
	var g := gust_at(p, _time)
	var ground_y := world_pos.y - agl if agl >= 0.0 else world_pos.y
	var env := elev_factor(ground_y) * _exposure(world_pos)
	if agl >= 0.0:
		env *= height_factor(agl)
	var s := maxf(0.0, env * (_strength * m * (0.85 + 0.30 * front) + g))
	return {"angle": ang, "strength": s, "speed": s * 6.0, "gust": g * env}


## 行進陣風在某點某時刻的強度（與 wf_gusts 同式）。
func gust_at(p: Vector2, t: float) -> float:
	var g := 0.0
	for e in _events:
		var rel: Vector2 = p - (e["o"] as Vector2)
		var d: Vector2 = e["dir"]
		var along := rel.dot(d)
		var across := rel.dot(Vector2(-d.y, d.x))
		var tau := t - float(e["t0"]) - along / GUST_SPEED \
			+ 0.6 * sin(across * 0.07 + fposmod(float(e["t0"]) * 0.6180339, 1.0) * TAU)
		var dur := float(e["dur"])
		if tau > 0.0 and tau < dur:
			var hw := float(e["hw"])
			var lat := 1.0 - smoothstep(0.55 * hw, hw, absf(across))
			var md := 0.80 + 0.25 * sin(across * 0.11 + float(e["seed"]) * TAU)
			var r := 0.3 * dur
			var env := smoothstep(0.0, r, tau) * (1.0 - smoothstep(r, dur, tau))
			g += float(e["amp"]) * env * lat * md
	return g * _gust_gain


## 垂直風剖面（與 wf_height_factor 同式）：z＝離地高度 m。
func height_factor(z: float) -> float:
	return clampf(pow(maxf(z, 0.05) / maxf(_vprof.y, 0.05), _vprof.x), 0.55, 1.9)


## 海拔增益（與 wf_elev_factor 同式）：y＝根部／地面世界高度。
func elev_factor(y: float) -> float:
	return clampf(1.0 + _vprof.w * (y - _vprof.z), 0.7, 1.5)


## 設定垂直剖面：alpha（冪律指數）、z0（正規化高度 m）、elev_ref（海拔參考 y）、elev_gain（每公尺增益）。
func set_vertical_profile(alpha := 0.16, z0 := 0.6, elev_ref := 0.0, elev_gain := 0.02) -> void:
	_vprof = Vector4(maxf(alpha, 0.0), maxf(z0, 0.05), elev_ref, elev_gain)


func get_vertical_profile() -> Vector4:
	return _vprof


## 植被物種的驅動力響應（CPU 鏡像，給驗證／玩法用）：回傳 trunk（主幹，0.25×lag 延遲）與
## crown（樹冠彈簧）—— 與 veg_common 的 wf_force／wf_spring 同式；height_m＝樹高（決定樹冠剖面）。
func sample_vegetation(root_pos: Vector3, species: String, height_m: float, t := -1.0) -> Dictionary:
	var tt := _time if t < 0.0 else t
	var prof := _profile(species)
	var p := Vector2(root_pos.x, root_pos.z)
	var n1 := 0.5 + 0.5 * sin(p.dot(FIELD_K1) + _time * 0.11)
	var n2 := 0.5 + 0.5 * sin(p.dot(FIELD_K2) + _time * 0.07)
	var ang := _angle + _local_var * (FIELD_DIR_A1 * (n1 - 0.5) + FIELD_DIR_A2 * (n2 - 0.5))
	var wd := Vector2(cos(ang), sin(ang))
	var m := (1.0 + _local_var * FIELD_STR_A1 * (n1 - 0.5)) * (1.0 + _local_var * FIELD_STR_A2 * (n2 - 0.5))
	var zc := 0.7 * height_m
	var env := height_factor(zc) * elev_factor(root_pos.y) \
		* _exposure(Vector3(root_pos.x, root_pos.y + zc, root_pos.z))
	var force := func(s: float) -> float:
		var front := 0.5 + 0.5 * sin(s * 1.25 - p.dot(wd) * 0.10)
		return env * (_strength * m * (0.85 + 0.30 * front) + gust_at(p, s))
	var trunk: float = force.call(tt - 0.25 * prof.response_lag)
	var w: Array = prof.spring_taps()
	var dt := float(w[6])
	var s0 := tt - prof.response_lag - 0.5 * dt
	var crown := 0.0
	for k in 6:
		crown += float(w[k]) * float(force.call(s0 - float(k) * dt))
	return {"trunk": trunk, "crown": crown, "env": env}


## 遮蔽體積（近似的「這裡比較避風」）：建築後巷、牆後、林下、山丘背風面。
## 水平圓（半徑 radius）× 係數 factor；top_y 以上 2 m 內漸回開闊（高過牆的樹梢照樣吃風）。
## V1.2：植被 shader 也吃（離焦點最近的 8 個，0.5 s 挑一次）。
func add_shelter(world_pos: Vector3, radius: float, factor := 0.35, top_y := NAN) -> int:
	var r := maxf(radius, 0.1)
	var top := top_y if not is_nan(top_y) else world_pos.y + r * 0.5
	_shelters.append({"pos": world_pos, "radius": r, "factor": clampf(factor, 0.0, 1.0), "top": top})
	_shelters_dirty = true
	return _shelters.size() - 1


func clear_shelters() -> void:
	_shelters.clear()
	_shelters_dirty = true


func shelter_count() -> int:
	return _shelters.size()


## 與 wf_shelter 同式（水平距離、頂高漸回）。
func _exposure(world_pos: Vector3) -> float:
	var f := 1.0
	for s in _shelters:
		var r := float(s["radius"])
		var sp: Vector3 = s["pos"]
		var d := Vector2(world_pos.x - sp.x, world_pos.z - sp.z).length()
		if d < r:
			var k := lerpf(float(s["factor"]), 1.0, smoothstep(r * 0.55, r, d))
			var top := float(s["top"])
			f *= lerpf(k, 1.0, smoothstep(top, top + 2.0, world_pos.y))
	return f


## 焦點：陣風生成與遮蔽挑選的參考點。lock=true 之後不再跟相機（pilot／錄影用）。
func set_focus(pos: Vector3, lock := true) -> void:
	_focus = pos
	_focus_locked = lock
	_shelters_dirty = true


func clear_focus() -> void:
	_focus_locked = false


## 除錯檢視：0＝正常、1＝植被位移熱圖（灰階 emission，0.6 m＝白）。
func set_debug_view(mode: int) -> void:
	_debug_view = clampi(mode, 0, 1)


func get_debug_view() -> int:
	return _debug_view


func events() -> Array:
	return _events.duplicate(true)


## 除錯／測試用暫停風時鐘（shader 的風相位就不會再走）。水的 TIME 不受影響。
func set_frozen(v: bool) -> void:
	_frozen = v


func is_frozen() -> bool:
	return _frozen


## 測試用：直接推進風時鐘（不是等真實時間）。
func debug_advance(seconds: float) -> void:
	_advance(maxf(seconds, 0.0))
	_push_globals()


func set_time_scale(v: float) -> void:
	_time_scale = maxf(v, 0.0)


## 測試用：把整個場（時間、方向、陣風、RNG）重設回 seed 的初始狀態。
## 同一個 seed＋同一串 dt，取樣會逐位元相同。
func debug_reset() -> void:
	_rng.seed = seed_value
	_turn_in = _rng.randf_range(2.0, 6.0)
	_angle = deg_to_rad(38.0)
	_target_angle = _angle
	_dir_goal = _angle
	_strength = 0.0
	_target_strength = 0.0
	_gust = 0.0
	_lull = 1.0
	_time = 0.0
	_override.clear()
	_shelters.clear()
	_shelters_dirty = true
	_events.clear()
	_events_dirty = true
	_gust_rng.seed = seed_value + 1
	_auto_in = _gust_rng.randf_range(1.5, 4.0)
	_gust_gain = 1.0
	_local_var = 1.0
	_gust_amp_override = -1.0
	enabled = true
	_apply_preset(Preset.BREEZE, true)
	_push_globals()


# ───────────────────────── 每幀 ─────────────────────────

func _process(delta: float) -> void:
	if not _focus_locked:
		var cam := get_viewport().get_camera_3d() if get_viewport() else null
		if cam != null:
			_focus = cam.global_position
	# 暫停（get_tree().paused）＝風時鐘停：植被、水面、布料一起停；恢復後從同一點接著走。
	# Wind 本身 PROCESS_MODE_ALWAYS 只是為了暫停中 F9 面板還能操作。
	if not _frozen and not get_tree().paused:
		_advance(delta * _time_scale)
	_sh_t += delta
	if _sh_t >= 0.5:
		_sh_t = 0.0
		_shelters_dirty = true
	_push_globals()
	_update_cloth(delta)


## 每片暖簾取樣自己的世界位置（含遮蔽），5 Hz 就夠——布料本身是 1–3 Hz 的運動。
## 這樣同一條街的不同店面不會吃到完全一樣的風，避風的巷內暖簾也會小一點。
func _update_cloth(delta: float) -> void:
	if _cloth_nodes.is_empty():
		return
	_cloth_t += delta
	if _cloth_t < 0.2:
		return
	_cloth_t = 0.0
	var alive: Array = []
	for n in _cloth_nodes:
		if not is_instance_valid(n):
			continue
		var mi := n as MeshInstance3D
		if mi != null:
			alive.append(mi)
	_cloth_nodes = alive
	for mi in _cloth_nodes:
		var f := sample_field((mi as MeshInstance3D).global_position)
		(mi as MeshInstance3D).set_instance_shader_parameter("obj_wind",
			Vector4(cos(float(f["angle"])), sin(float(f["angle"])), float(f["strength"]), 0.0))


func _advance(dt: float) -> void:
	_time += dt
	# 事件覆寫優先
	if not _override.is_empty() and String(_override.get("mode", "")) == "timed" \
			and _time >= float(_override.get("until", 0.0)):
		_override.clear()
		_apply_preset(preset, false)
	# 平滑趨近（指數；tau 大＝慢）
	var tau := TAU_STRENGTH
	if not enabled:
		tau = TAU_OFF
	var raw := _preset_target()
	# 低頻強弱起伏：同一個 preset 也有比較靜與比較強的時段（週期 ~40 s）。
	var lull_target := LULL_MIN + (1.0 - LULL_MIN) \
		* (0.5 + 0.5 * sin(_time * 0.157 + sin(_time * 0.061) * 1.7))
	_lull = lerpf(_lull, lull_target, 1.0 - exp(-dt / 3.0))
	if _override.is_empty():
		raw *= _lull
	_target_strength = raw
	var k := 1.0 - exp(-dt / maxf(tau, 0.001))
	_strength = lerpf(_strength, _target_strength, k)
	if absf(_strength - _target_strength) < 0.002:
		_strength = _target_strength
	# 全域方向：沒有手動覆寫時，按排程慢慢轉（每 7–18 s 換目標、單次 ≤50°）。
	# 手動 set_wind／override 時用比較快的 tau（1.9 s），排程風用 5.5 s。
	var manual := not _override.is_empty()
	if not manual:
		_turn_in -= dt
		if _turn_in <= 0.0:
			_turn_in = _rng.randf_range(TURN_MIN, TURN_MAX)
			var maxd := deg_to_rad(TURN_MAX_DEG)
			_dir_goal = wrapf(_angle + _rng.randf_range(-maxd, maxd), -PI, PI)
		_target_angle = _dir_goal
	var tau_ang := TAU_ANGLE if manual else TAU_TURN
	var da := wrapf(_target_angle - _angle, -PI, PI)
	_angle = wrapf(_angle + da * (1.0 - exp(-dt / tau_ang)), -PI, PI)
	# 行進陣風（V1.2）：自動陣風按 preset 節奏生成「事件」，從焦點上風處推進；
	# 手動陣風（trigger_gust）也是事件。_gust＝焦點處的值（給除錯面板、gw_gust 舊介面、flutter）。
	_gust_gain = lerpf(_gust_gain, 1.0 if enabled else 0.0, 1.0 - exp(-dt / TAU_OFF))
	# 關風且陣風已淡出：清掉事件 → shader 的陣風迴圈整段跳過（不是乘 0 還在算）
	if not enabled and _gust_gain < 0.001 and not _events.is_empty():
		_events.clear()
		_events_dirty = true
	_schedule_auto_gust(dt)
	_expire_events()
	_gust = gust_at(Vector2(_focus.x, _focus.z), _time)
	_flutter = float(PRESETS[preset]["flutter"]) * (1.0 + 1.1 * _gust)


## 自動陣風排程：間隔＝period × 0.55–1.25（不等間隔），振幅＝preset gust × 0.8–1.35，
## 長度＝hold × 0.85–1.3，生成點沿橫向 ±15 m 隨機 → 每道陣風掃過的帶子不同。RNG 獨立（_gust_rng）→ 可重現。
func _schedule_auto_gust(dt: float) -> void:
	var p: Dictionary = PRESETS[preset]
	var per := float(p["period"])
	var gamp := gust_amplitude()
	if not enabled or gamp <= 0.0:
		return
	# calm 沒有排程週期；面板把陣風調大時用 8 s／2.6 s 的節奏
	var hold := float(p["hold"])
	if per <= 0.0:
		per = 8.0
		hold = 2.6
	_auto_in -= dt
	if _auto_in > 0.0:
		return
	_auto_in = per * _gust_rng.randf_range(0.55, 1.25)
	var amp := gamp * _gust_rng.randf_range(0.8, 1.35)
	var dur := hold * _gust_rng.randf_range(0.85, 1.3)
	var wd := Vector2(cos(_angle), sin(_angle))
	var side := Vector2(-wd.y, wd.x) * _gust_rng.randf_range(-15.0, 15.0)
	var o := Vector2(_focus.x, _focus.z) - wd * GUST_LEAD + side
	_spawn_event(o, amp, dur, _gust_rng.randf())


func _spawn_event(o: Vector2, amp: float, dur: float, seed01: float) -> void:
	if _events.size() >= MAX_EVENTS:
		_events.pop_front()
	_events.append({
		"o": o, "t0": _time, "amp": amp,
		"dir": Vector2(cos(_angle), sin(_angle)),
		"dur": dur, "speed": GUST_SPEED,
		"hw": GUST_HALF_WIDTH * (0.8 + 0.4 * seed01),
		"seed": seed01,
	})
	_events_dirty = true


func _expire_events() -> void:
	var keep: Array = []
	for e in _events:
		var life := float(e["dur"]) + (GUST_LEAD + GUST_TRAVEL_TAIL) / float(e["speed"]) + 2.0
		if _time - float(e["t0"]) < life:
			keep.append(e)
	if keep.size() != _events.size():
		_events = keep
		_events_dirty = true


func _preset_target() -> float:
	if not enabled:
		return 0.0
	if not _override.is_empty():
		var mode := String(_override.get("mode", ""))
		if mode == "manual":
			return float(_target_strength)
		if mode == "timed" and _time < float(_override.get("until", 0.0)):
			_target_angle = float(_override.get("angle", _target_angle))
			return float(_override.get("strength", 0.0))
	return float(PRESETS[preset]["base"])


func _apply_preset(p: int, instant: bool) -> void:
	preset = p
	var d: Dictionary = PRESETS[p]
	_target_strength = float(d["base"]) if enabled else 0.0
	if instant:
		_strength = _target_strength


## V1.2：gw_strength＝基礎風（關風時跟著 TAU_OFF 平滑降，不再一幀切 0）；陣風走 gw_events。
## gw_gust 保留給舊介面（暖簾退路、除錯），＝焦點處的行進陣風。
func _push_globals() -> void:
	var dirv := wind_direction()
	RenderingServer.global_shader_parameter_set("gw_dir", dirv)
	RenderingServer.global_shader_parameter_set("gw_strength", _strength)
	RenderingServer.global_shader_parameter_set("gw_gust", clampf(_gust, 0.0, 1.0))
	RenderingServer.global_shader_parameter_set("gw_time", _time)
	RenderingServer.global_shader_parameter_set("gw_flutter", _flutter)
	if _events_dirty:
		_upload_events()
	if _shelters_dirty:
		_upload_shelters()
	RenderingServer.global_shader_parameter_set("gw_ctrl",
		Vector4(float(_events.size()), _gust_gain, float(_debug_view), float(_shelter_n)))
	RenderingServer.global_shader_parameter_set("gw_vprof", _vprof)
	RenderingServer.global_shader_parameter_set("gw_tune", Vector4(_local_var, 0.0, 0.0, 0.0))
	if water != null:
		RenderingServer.global_shader_parameter_set("gw_water", Vector4(water.long_amp, water.ripple_gain, 0.0, 0.0))


# ───────────────────────── 事件／遮蔽／物種貼圖（V1.2） ─────────────────────────

func _init_textures() -> void:
	_ev_img = Image.create_empty(MAX_EVENTS, 3, false, Image.FORMAT_RGBAF)
	_ev_tex = ImageTexture.create_from_image(_ev_img)
	_sh_img = Image.create_empty(SHELTER_SLOTS, 2, false, Image.FORMAT_RGBAF)
	_sh_tex = ImageTexture.create_from_image(_sh_img)
	RenderingServer.global_shader_parameter_set("gw_events", _ev_tex)
	RenderingServer.global_shader_parameter_set("gw_shelters", _sh_tex)


## 事件貼圖：row1.w＝這道陣風所有物種響應的最長範圍（shader 早退用）；前緣速度固定 GUST_SPEED。
func _upload_events() -> void:
	_events_dirty = false
	var tmax: Array = _upload_responses()
	_ev_img.fill(Color(0, 0, 0, 0))
	for i in _events.size():
		var e: Dictionary = _events[i]
		var o: Vector2 = e["o"]
		var d: Vector2 = e["dir"]
		_ev_img.set_pixel(i, 0, Color(o.x, o.y, float(e["t0"]), float(e["amp"])))
		_ev_img.set_pixel(i, 1, Color(d.x, d.y, float(e["dur"]), float(tmax[i])))
		_ev_img.set_pixel(i, 2, Color(float(e["hw"]), float(e["seed"]), 0.0, 0.0))
	_ev_tex.update(_ev_img)


## 每道陣風 × 每個物種的樹冠彈簧響應表（WindSpeciesProfile.response_table）。只在陣風生成／回收、
## 物種參數變動時重算（4 × 9 × 64 點 × 6 tap，~0.1 ms）；shader 每頂點只查表。
func _upload_responses() -> Array:
	var order: Array = WindSpeciesProfile.SPECIES_ORDER
	var ns := order.size()
	var tmax_all: Array = []
	if _rs_img == null:
		_rs_img = Image.create_empty(65, MAX_EVENTS * ns, false, Image.FORMAT_RF)
	_rs_img.fill(Color(0, 0, 0, 0))
	for i in _events.size():
		var dur := float(_events[i]["dur"])
		var tm := dur
		for s in ns:
			var tab: PackedFloat32Array = _profile(String(order[s])).response_table(dur)
			tm = maxf(tm, tab[64])
			for j in 65:
				_rs_img.set_pixel(j, i * ns + s, Color(tab[j], 0, 0, 0))
		tmax_all.append(tm)
	if _rs_tex == null:
		_rs_tex = ImageTexture.create_from_image(_rs_img)
		RenderingServer.global_shader_parameter_set("gw_resp", _rs_tex)
	else:
		_rs_tex.update(_rs_img)
	return tmax_all


## 植被 shader 只吃離焦點最近的 SHELTER_SLOTS 個（CPU 取樣吃全部）。
func _upload_shelters() -> void:
	_shelters_dirty = false
	var list := _shelters.duplicate()
	if list.size() > SHELTER_SLOTS:
		var f := Vector2(_focus.x, _focus.z)
		list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var pa: Vector3 = a["pos"]
			var pb: Vector3 = b["pos"]
			return Vector2(pa.x, pa.z).distance_to(f) - float(a["radius"]) \
				< Vector2(pb.x, pb.z).distance_to(f) - float(b["radius"]))
		list = list.slice(0, SHELTER_SLOTS)
	_sh_img.fill(Color(0, 0, 0, 0))
	for i in list.size():
		var s: Dictionary = list[i]
		var p: Vector3 = s["pos"]
		_sh_img.set_pixel(i, 0, Color(p.x, p.z, float(s["radius"]), float(s["factor"])))
		_sh_img.set_pixel(i, 1, Color(float(s["top"]), 0.0, 0.0, 0.0))
	_shelter_n = list.size()
	_sh_tex.update(_sh_img)


func _load_species() -> void:
	_species_table = null
	if ResourceLoader.exists(SPECIES_TABLE_PATH):
		_species_table = load(SPECIES_TABLE_PATH) as WindSpeciesTable
	if _species_table == null:
		_species_table = WindSpeciesTable.make_default()
	_species_index.clear()
	for i in WindSpeciesProfile.SPECIES_ORDER.size():
		_species_index[WindSpeciesProfile.SPECIES_ORDER[i]] = i
	_upload_species()


func _profile(name: String) -> WindSpeciesProfile:
	var p := _species_table.get_profile(name) if _species_table else null
	return p if p != null else WindSpeciesProfile.from_defaults(name)


func _upload_species() -> void:
	var order: Array = WindSpeciesProfile.SPECIES_ORDER
	if _sp_img == null:
		_sp_img = Image.create_empty(order.size(), 5, false, Image.FORMAT_RGBAF)
	for i in order.size():
		var rows: Array = _profile(String(order[i])).texel_rows()
		for r in 5:
			_sp_img.set_pixel(i, r, rows[r])
	if _sp_tex == null:
		_sp_tex = ImageTexture.create_from_image(_sp_img)
		RenderingServer.global_shader_parameter_set("gw_species", _sp_tex)
	else:
		_sp_tex.update(_sp_img)
	RenderingServer.global_shader_parameter_set("gw_species_n", float(order.size()))
	# 物種參數變了 → 陣風響應表也要重算
	_events_dirty = true


func species_index(name: String) -> int:
	return int(_species_index.get(name, -1))


func get_species(name: String) -> WindSpeciesProfile:
	return _profile(name)


## 執行中調物種參數（key＝WindSpeciesProfile 的屬性名），立即生效；不寫回 .tres。
func set_species_param(name: String, key: String, value: float) -> bool:
	var p := _species_table.get_profile(name) if _species_table else null
	if p == null or not (key in p):
		return false
	p.set(key, value)
	_upload_species()
	return true


# ───────────────────────── 水面（Wind V2 Phase E） ─────────────────────────

## 主河進場：建流場（中心線→1 m 世界貼圖，user:// 快取）、換上 water.gdshader 的「人里主河模式」
## （顏色／透明＝原 P2 頂點色，加流向細節、長波、風漣漪）。原材質留在 meta wind_orig_material。
## 不改 mesh、不改 .tscn；WIND_NO_RIVER=1 可跳過做 A/B。
func _attach_river(mi: MeshInstance3D) -> void:
	if not is_instance_valid(mi) or not mi.is_inside_tree():
		return
	var src: String = RIVER_SOURCES[String(mi.name)]
	var L: Variant = JSON.parse_string(FileAccess.get_file_as_string(src))
	if not (L is Dictionary) or not (L as Dictionary).get("water", {}).has(String(mi.name)):
		push_warning("[Wind] 找不到河道中心線 %s：%s" % [mi.name, src])
		return
	var W: Dictionary = L["water"][String(mi.name)]
	var pts := PackedVector2Array()
	for q in W["pts"]:
		pts.append(Vector2(float(q[0]), float(q[1])))
	var hw := PackedFloat32Array()
	for v in W["half_w"]:
		hw.append(float(v))
	var wf := WaterField.new()
	var key := "%s_%d" % [String(mi.name), hash(str(W["pts"]) + str(W["half_w"]) + str(RIVER_FLOW_SPEED))]
	var cache := "%s/%s.res" % [FLOW_CACHE_DIR, key]
	if ResourceLoader.exists(cache):
		wf.load_cached(load(cache) as Image, String(mi.name), pts, hw, float(mi.get_meta("water_y")))
	else:
		wf.build(String(mi.name), pts, hw, float(mi.get_meta("water_y")), RIVER_FLOW_SPEED)
		DirAccess.make_dir_recursive_absolute(FLOW_CACHE_DIR)
		ResourceSaver.save(wf.img, cache)
	water = wf
	RenderingServer.global_shader_parameter_set("gw_flow", wf.tex)
	RenderingServer.global_shader_parameter_set("gw_flow_rect", Vector4(wf.rect.position.x, wf.rect.position.y,
		1.0 / wf.rect.size.x, 1.0 / wf.rect.size.y))
	var orig := mi.material_override
	var m := ShaderMaterial.new()
	m.shader = load(RIVER_SHADER)
	m.set_shader_parameter("wave_nor", load(RIVER_NORMAL_TEX))
	m.set_shader_parameter("wind_coupled", 1.0)
	m.set_shader_parameter("vc_albedo", 1.0)
	m.set_shader_parameter("wave_scale", 0.25)
	m.set_shader_parameter("detail_slope", 0.025)
	if orig is BaseMaterial3D:
		m.set_shader_parameter("vc_roughness", (orig as BaseMaterial3D).roughness)
		m.set_shader_parameter("vc_specular", (orig as BaseMaterial3D).metallic_specular)
	mi.set_meta("wind_orig_material", orig)
	mi.material_override = m
	# 長波 2 cm＋浮物：剔除邊界放寬一點
	mi.extra_cull_margin = maxf(mi.extra_cull_margin, 0.2)
	_river_node = mi
	if not mi.tree_exiting.is_connected(_on_river_exit):
		mi.tree_exiting.connect(_on_river_exit.bind(mi))
	print("[Wind] 河 %s 接線：流場 %dx%d（%.0f×%.0f m）" % [mi.name, wf.img.get_width(), wf.img.get_height(),
		wf.rect.size.x, wf.rect.size.y])


func _on_river_exit(mi: MeshInstance3D) -> void:
	# 換圖時新地圖的主河可能比舊地圖先進場：只有「目前這條」離場才清空
	if mi != _river_node:
		return
	water = null
	_river_node = null
	RenderingServer.global_shader_parameter_set("gw_flow_rect", Vector4.ZERO)


## 測試／A-B：把主河換回原材質（或再接回）
func set_river_enabled(v: bool) -> void:
	if _river_node == null or not is_instance_valid(_river_node):
		return
	if v:
		_attach_river(_river_node)
	else:
		_river_node.material_override = _river_node.get_meta("wind_orig_material")


func has_water() -> bool:
	return water != null


## 水面當地風力（與 wf_water_wind 同：env＝1，不吃海拔／遮蔽）
func _water_wind(p: Vector2, t: float) -> Vector3:
	var n1 := 0.5 + 0.5 * sin(p.dot(FIELD_K1) + t * 0.11)
	var n2 := 0.5 + 0.5 * sin(p.dot(FIELD_K2) + t * 0.07)
	var ang := _angle + _local_var * (FIELD_DIR_A1 * (n1 - 0.5) + FIELD_DIR_A2 * (n2 - 0.5))
	var wd := Vector2(cos(ang), sin(ang))
	var m := (1.0 + _local_var * FIELD_STR_A1 * (n1 - 0.5)) * (1.0 + _local_var * FIELD_STR_A2 * (n2 - 0.5))
	var front := 0.5 + 0.5 * sin(t * 1.25 - p.dot(wd) * 0.10)
	return Vector3(wd.x, wd.y, _strength * m * (0.85 + 0.30 * front) + gust_at(p, t))


## 水面高度（世界 Y）＝靜水面＋長波＋風漣漪；不在水中回傳 NAN。
func sample_water_height(world_position: Vector3) -> float:
	if water == null:
		return NAN
	var p := Vector2(world_position.x, world_position.z)
	var fl := water.flow3(p)
	if fl.z < 0.05:
		return NAN
	var w := _water_wind(p, _time)
	var f2 := Vector2(fl.x, fl.y)
	var fd := f2.normalized() if f2.length() > 1e-4 else Vector2(1, 0)
	return water.water_y + water.long_wave(p, fd, _time, w.z) \
		+ water.ripple(p, Vector2(w.x, w.y), f2, _time, w.z).x


## 水面法線（世界）：長波＋漣漪斜率（長波斜率用中央差分，漣漪用解析導數——與 shader 同源）。
func sample_water_normal(world_position: Vector3) -> Vector3:
	if water == null:
		return Vector3.UP
	var p := Vector2(world_position.x, world_position.z)
	var fl := water.flow3(p)
	var w := _water_wind(p, _time)
	var f2 := Vector2(fl.x, fl.y)
	var fd := f2.normalized() if f2.length() > 1e-4 else Vector2(1, 0)
	var e := 0.25
	var dx := (water.long_wave(p + Vector2(e, 0), fd, _time, w.z) - water.long_wave(p - Vector2(e, 0), fd, _time, w.z)) / (2.0 * e)
	var dz := (water.long_wave(p + Vector2(0, e), fd, _time, w.z) - water.long_wave(p - Vector2(0, e), fd, _time, w.z)) / (2.0 * e)
	var r := water.ripple(p, Vector2(w.x, w.y), f2, _time, w.z)
	return Vector3(-(dx + r.y), 1.0, -(dz + r.z)).normalized()


## 水流（m/s，世界 XZ；y＝0）。不在水中＝零。
func sample_water_flow(world_position: Vector3) -> Vector3:
	if water == null:
		return Vector3.ZERO
	var fl := water.flow3(Vector2(world_position.x, world_position.z))
	return Vector3(fl.x, 0.0, fl.y)


## 0–1：這裡有沒有水（流場貼圖 B）
func sample_water_mask(world_position: Vector3) -> float:
	if water == null:
		return 0.0
	return water.flow3(Vector2(world_position.x, world_position.z)).z


# ───────────────────────── 植被接線（V1.2） ─────────────────────────

## 植被節點進場：依 shader 判斷是樹／竹（veg_leaf／veg_bark）或草，設定
##   wind_sp＝(物種索引, mesh 局部頂高, 樞軸高, 0) —— shader 用它把局部高度正規化（不是世界 Y）
##   extra_cull_margin ≥ 物種 max_deform × 1.3 ＋ 0.1 m —— 剔除邊界（含陰影）容納變形
## 不改 mesh、不改 .tscn；已有作者設定的 wind_sp（x ≥ 0）不覆寫。
func _on_node_added_veg(n: Node) -> void:
	if n is MeshInstance3D or n is MultiMeshInstance3D:
		_wire_veg(n as GeometryInstance3D)
		if RIVER_SOURCES.has(String(n.name)) and n.has_meta("water_y") and not OS.has_environment("WIND_NO_RIVER"):
			_attach_river.call_deferred(n)


func wire_vegetation(root: Node) -> Dictionary:
	for n in root.find_children("*", "GeometryInstance3D", true, false):
		if n is MeshInstance3D or n is MultiMeshInstance3D:
			_wire_veg(n as GeometryInstance3D)
	return veg_stats()


func veg_stats() -> Dictionary:
	return {"species": _veg_stats.duplicate(), "unknown": _veg_unknown.keys()}


func _veg_kind(gi: GeometryInstance3D, mesh: Mesh) -> int:
	var mats: Array = [gi.material_override]
	if gi is MeshInstance3D:
		for i in mesh.get_surface_count():
			mats.append((gi as MeshInstance3D).get_surface_override_material(i))
	for i in mesh.get_surface_count():
		mats.append(mesh.surface_get_material(i))
	var kind := 0
	for m in mats:
		var sm := m as ShaderMaterial
		if sm == null or sm.shader == null:
			continue
		var f := sm.shader.resource_path.get_file()
		if f in VEG_TREE_SHADERS:
			return 1
		if f in VEG_GRASS_SHADERS:
			kind = 2
	return kind


func _veg_classify(gi: GeometryInstance3D, mesh: Mesh) -> Array:
	var kind := _veg_kind(gi, mesh)
	if kind == 0:
		return [0, "", Vector4(), 0.0]
	if kind == 2:
		return [2, "grass", Vector4(), 0.0]
	var sp_name := WindSpeciesProfile.species_for_mesh_path(mesh.resource_path)
	if sp_name == "":
		# 沒對到物種表＝不是樹（庭園的竹垣／蹲踞／手桶也用 veg_bark）→ 剛體，不彎
		_veg_unknown[mesh.resource_path.get_file()] = true
		sp_name = "rigid"
	var aabb := mesh.get_aabb()
	var top := aabb.position.y + aabb.size.y
	var piv := clampf(aabb.position.y, 0.0, top)
	return [1, sp_name, Vector4(species_index(sp_name), top, piv, 0.0), 0.0]


func _wire_veg(gi: GeometryInstance3D) -> void:
	if not is_instance_valid(gi):
		return
	var mesh: Mesh = null
	if gi is MeshInstance3D:
		mesh = (gi as MeshInstance3D).mesh
	elif gi is MultiMeshInstance3D and (gi as MultiMeshInstance3D).multimesh:
		mesh = (gi as MultiMeshInstance3D).multimesh.mesh
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var key := Vector2i(mesh.get_instance_id(), gi.material_override.get_instance_id() if gi.material_override else 0)
	var info: Array = _veg_cache.get(key, [])
	if info.is_empty():
		info = _veg_classify(gi, mesh)
		_veg_cache[key] = info
	var kind: int = info[0]
	if kind == 0:
		return
	var sp_name: String = info[1]
	if kind == 1:
		var cur: Variant = gi.get_instance_shader_parameter("wind_sp")
		if not (cur is Vector4 and (cur as Vector4).x >= 0.0):
			gi.set_instance_shader_parameter("wind_sp", info[2])
		else:
			sp_name = String(WindSpeciesProfile.SPECIES_ORDER[clampi(int((cur as Vector4).x), 0, 8)])
	var margin := _profile(sp_name).max_deform_m * 1.3 + 0.1
	if gi.extra_cull_margin < margin:
		gi.extra_cull_margin = margin
	_veg_stats[sp_name] = int(_veg_stats.get(sp_name, 0)) + 1


# ───────────────────────── 暖簾（布料） ─────────────────────────

## 只接「nr_noren*」＝屋簷下垂掛的暖簾。牆板、格子窗等 kit 件不動。
## 用共用 ShaderMaterial ＋ 逐節點 instance uniform（top／length），不動 mesh、不動 .scn。
func _on_node_added(n: Node) -> void:
	if n is MeshInstance3D:
		var nm := String(n.name)
		if nm.begins_with("nr_noren") or nm.begins_with("nr_sudare"):
			_attach_cloth.call_deferred(n as MeshInstance3D)
		elif (n as MeshInstance3D).mesh and _is_lantern((n as MeshInstance3D).mesh.resource_path.get_file()):
			_attach_lantern.call_deferred(n as MeshInstance3D)
	elif n is Skeleton3D:
		_attach_secondary.call_deferred(n as Skeleton3D)


func _scan_existing_cloth() -> void:
	var root := get_tree().root
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var nm := String(n.name)
		if nm.begins_with("nr_noren") or nm.begins_with("nr_sudare"):
			_attach_cloth(n as MeshInstance3D)


func _attach_cloth(mi: MeshInstance3D) -> void:
	if not is_instance_valid(mi) or mi.material_override != null:
		return
	var mesh: Mesh = mi.mesh
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var src := mesh.surface_get_material(0) as BaseMaterial3D
	if src == null or src.albedo_texture == null:
		return
	# 一個來源材質一個布料材質（暖簾與竹簾的貼圖／顏色不一定相同；共用會換錯外觀）
	var cm: ShaderMaterial = _cloth_mats.get(src)
	if cm == null:
		cm = ShaderMaterial.new()
		cm.shader = load(CLOTH_SHADER)
		cm.set_shader_parameter("albedo_tex", src.albedo_texture)
		cm.set_shader_parameter("albedo_color", src.albedo_color)
		if src.emission_enabled and src.emission_texture:
			cm.set_shader_parameter("emit_tex", src.emission_texture)
			cm.set_shader_parameter("emit_energy", src.emission_energy_multiplier)
		_cloth_mats[src] = cm
		if _cloth_mat == null:
			_cloth_mat = cm
	var aabb := mesh.get_aabb()
	mi.material_override = cm
	# top＝AABB 上緣（吊竿處），len＝布長；兩者都是 mesh 局部座標，跟著節點走。
	mi.set_instance_shader_parameter("cloth_top", aabb.position.y + aabb.size.y - 0.02)
	mi.set_instance_shader_parameter("cloth_len", maxf(aabb.size.y - 0.02, 0.05))
	# 竹簾：比布硬、重 → 擺幅 30 %（同一個材質、同一個風場，只差 instance 增益）
	mi.set_instance_shader_parameter("cloth_gain", 0.3 if String(mi.name).begins_with("nr_sudare") else 1.0)
	_cloth_nodes.append(mi)
	_cloth_n += 1


func cloth_count() -> int:
	return _cloth_n

# ───────────────────────── 吊燈籠（V2 Phase G） ─────────────────────────
## 只接「單顆、掛在簷下／竿上」的燈籠 mesh（一個 mesh＝一顆燈籠）。繩串燈籠（ms_tsuna_chochin、mk_chochin_line）
## 一個 mesh 裡有很多顆、各自吊點不同，整串一起擺會錯 → 不接（維持靜止）。
const LANTERN_PREFIX := ["ms_noki_chochin", "st_chochin_shiro", "gd_chochin"]
const SUSPENDED_SCRIPT := "res://scripts/wind/wind_suspended.gd"
var _lantern_n := 0


func _is_lantern(nm: String) -> bool:
	for p in LANTERN_PREFIX:
		if nm.begins_with(p):
			return true
	return false


## 在吊點（mesh AABB 頂面中心）插一個世界軸對齊的鉸鏈節點，把燈籠 mesh 原樣（global transform 不變）
## 掛到鉸鏈下，鉸鏈掛 wind_suspended（擺錘＋慣性＋阻尼）。LOD0／LOD1 各自一個鉸鏈、同參數同輸入 → 擺動一致。
## 不改 .tscn、不動建築與碰撞；靜止時 transform＝原擺位。
func _attach_lantern(mi: MeshInstance3D) -> void:
	if not is_instance_valid(mi) or not mi.is_inside_tree() or mi.mesh == null:
		return
	var par := mi.get_parent()
	if par == null or String(par.name).begins_with("WindPivot"):
		return
	var ab := mi.mesh.get_aabb()
	var hook := mi.global_transform * Vector3(ab.get_center().x, ab.position.y + ab.size.y, ab.get_center().z)
	var keep := mi.global_transform
	mi.set_meta("wind_orig_xf", keep)
	var pivot := Node3D.new()
	pivot.name = "WindPivot_" + String(mi.name)
	pivot.set_script(load(SUSPENDED_SCRIPT))
	var hgt := ab.size.y * mi.global_transform.basis.get_scale().y
	# 物理參數沿用 pilot 校準（0.55 kg／0.11 m²／0.5 m 時強陣風 ~28°）：迎風面積依燈籠寬×高×0.5 夾在 0.03–0.12 m²
	var wid := ab.size.x * mi.global_transform.basis.get_scale().x
	pivot.set("mass_kg", 0.6)
	pivot.set("area_m2", clampf(wid * hgt * 0.5, 0.03, 0.12))
	pivot.set("length_m", clampf(hgt * 0.6, 0.2, 0.7))
	pivot.set("wind_gain", 0.7)
	pivot.set("max_angle_deg", 28.0)
	pivot.set("damping", 1.6)
	par.add_child(pivot)
	pivot.global_transform = Transform3D(Basis(), hook)
	# _ready 已經用加入當下的 transform 記成靜止姿勢；這裡改了位置 → 重記
	pivot.set("_rest", pivot.transform)
	mi.reparent(pivot, false)
	mi.global_transform = keep
	_lantern_n += 1


func lantern_count() -> int:
	return _lantern_n


# ───────────────────────── 生物二次運動自動接線（V2 Phase G） ─────────────────────────
## 依骨架「簽名」（必備骨名＋驗證）接 WindSecondaryMotion；不改角色場景／戰鬥腳本。
## 目前只登記狼 rig；其他角色（含緣一）不會被接到。骨架 meta wind_secondary_off＝true 可排除（對照組用）。
const SECONDARY_RIGS := [
	{"bones": ["Tail1", "Tail5", "ManeB.L1", "Ruff1"], "profile": "res://data/wind/secondary/wolf.tres"},
]
var _secondary_n := 0


func _attach_secondary(sk: Skeleton3D) -> void:
	if not is_instance_valid(sk) or not sk.is_inside_tree() or bool(sk.get_meta("wind_secondary_off", false)):
		return
	for c in sk.get_children():
		if c is WindSecondaryMotion:
			return
	for rig in SECONDARY_RIGS:
		var ok := true
		for b in rig["bones"]:
			if sk.find_bone(String(b)) < 0:
				ok = false
				break
		if not ok:
			continue
		var m := WindSecondaryMotion.new()
		m.name = "WindSecondaryMotion"
		m.profile = load(String(rig["profile"]))
		sk.add_child(m)
		# 身體＝最近的 CharacterBody3D 祖先（沒有就骨架父節點）
		var body: Node = sk.get_parent()
		var a: Node = sk
		while a != null:
			if a is CharacterBody3D:
				body = a
				break
			a = a.get_parent()
		m.body_path = m.get_path_to(body)
		m._rebuild()
		_secondary_n += 1
		return


func secondary_count() -> int:
	return _secondary_n



# ───────────────────────── 除錯面板 ─────────────────────────

## F9：Wind Debug Preview 面板（scripts/wind/wind_debug_panel.gd）。開啟時放出滑鼠游標、關閉時還原，
## 不改玩家／相機腳本（它們用 _unhandled_input，點在面板上的事件 GUI 先吃掉）。
func _set_debug_visible(v: bool) -> void:
	if not OS.is_debug_build():
		return
	if v and _debug_ui == null:
		_debug_ui = CanvasLayer.new()
		_debug_ui.name = "WindDebug"
		_debug_ui.layer = 90
		var panel: PanelContainer = load(DEBUG_PANEL).new()
		_debug_ui.add_child(panel)
		panel.call("setup", self)
		# _ready 期間 root 還在建子節點：直接 add_child 會失敗（--wind-debug 開機開面板時）→ deferred
		get_tree().root.add_child.call_deferred(_debug_ui)
	if v and not _debug_on:
		_mouse_before = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif not v and _debug_on and _mouse_before >= 0:
		Input.mouse_mode = _mouse_before as Input.MouseMode
	_debug_on = v
	if _debug_ui:
		_debug_ui.visible = v


func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == DEBUG_KEY:
			_set_debug_visible(not _debug_on)
			get_viewport().set_input_as_handled()
			return
	if not _debug_on:
		return
	var k := event as InputEventKey
	if k == null or not k.pressed:
		return
	match k.physical_keycode:
		KEY_1: set_preset(Preset.CALM)
		KEY_2: set_preset(Preset.BREEZE)
		KEY_3: set_preset(Preset.MODERATE)
		KEY_4: set_preset(Preset.GUST)
		KEY_G: trigger_gust()
		KEY_H: set_debug_view(0 if _debug_view == 1 else 1)
		KEY_0: toggle_enabled()
		KEY_BRACKETLEFT: set_wind(rad_to_deg(_target_angle) - 15.0, _target_strength)
		KEY_BRACKETRIGHT: set_wind(rad_to_deg(_target_angle) + 15.0, _target_strength)
		KEY_MINUS: set_wind(rad_to_deg(_target_angle), _target_strength - 0.1)
		KEY_EQUAL: set_wind(rad_to_deg(_target_angle), _target_strength + 0.1)
		_: return
	get_viewport().set_input_as_handled()


func _veg_total() -> int:
	var t := 0
	for k in _veg_stats:
		t += int(_veg_stats[k])
	return t

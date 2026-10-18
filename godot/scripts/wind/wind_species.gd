class_name WindSpeciesProfile
extends Resource
## Wind V1.2 物種參數（一個物種一份）。Wind autoload 讀 res://data/wind/wind_species.tres，
## 打包成 gw_species 貼圖給所有植被 shader（assets/shaders/wind_field.gdshaderinc wf_species）。
##
## 單位：
##   stiffness      0–1   愈大愈硬（主幹彎曲幅度 ×(1−0.8·stiffness)）
##   bend_mult      倍率   主幹彎曲與枝擺總倍率（0＝完全不彎，例如倒木）
##   tip_response   指數   高度權重 pow(hn, tip_response)；2.2＝規格建議起始值，愈大愈集中在梢
##   response_lag   s      樹冠／葉叢彈簧在主幹之後多晚才開始反應
##   damping        ζ      樹冠彈簧阻尼比（小＝回彈多次；0.95 以上視同臨界）
##   flutter_hz     Hz     葉片／細枝顫動頻率
##   max_deform_m   m      總位移安全上限（tanh 軟夾；× 實例縮放）
##   crown_gain     倍率   樹冠相對主幹的彈性位移權重
##   sway_hz        Hz     主幹自然擺動頻率；樹冠彈簧固有頻率＝1.6 × sway_hz

@export var id := "broad_tall"
@export_range(0.0, 1.0, 0.01) var stiffness := 0.5
@export_range(0.0, 3.0, 0.01) var bend_mult := 1.0
@export_range(0.5, 4.0, 0.05) var tip_response := 2.2
@export_range(0.0, 2.0, 0.01, "suffix:s") var response_lag := 0.45
@export_range(0.05, 1.0, 0.01) var damping := 0.32
@export_range(0.0, 4.0, 0.01, "suffix:Hz") var flutter_hz := 1.15
@export_range(0.0, 3.0, 0.01, "suffix:m") var max_deform_m := 0.8
@export_range(0.0, 2.0, 0.01) var crown_gain := 0.55
@export_range(0.0, 2.0, 0.01, "suffix:Hz") var sway_hz := 0.22

## 物種索引＝貼圖欄位。順序必須與 wind_field.gdshaderinc 的 WF_SP_* 常數一致。
const SPECIES_ORDER := [
	"broad_tall", "broad_small", "conifer", "weeping", "bamboo", "bush", "grass", "paddy", "rigid",
]

## 預設表（res://data/wind/wind_species.tres 不存在時用；也是 tools/wind/wind_species_init.gd 的來源）。
##             stiff  bend  tip   lag   damp  flut  maxd  crown sway
const DEFAULTS := {
	"broad_tall":  [0.50, 1.00, 2.2, 0.45, 0.32, 1.15, 0.80, 0.55, 0.22],
	"broad_small": [0.45, 1.00, 2.0, 0.30, 0.30, 1.30, 0.45, 0.50, 0.32],
	"conifer":     [0.65, 0.85, 2.4, 0.55, 0.40, 0.90, 0.65, 0.35, 0.18],
	"weeping":     [0.30, 1.10, 1.6, 0.70, 0.22, 1.00, 0.70, 0.90, 0.20],
	"bamboo":      [0.22, 1.55, 1.8, 0.35, 0.18, 1.60, 1.20, 0.45, 0.28],
	"bush":        [0.55, 0.90, 1.6, 0.15, 0.40, 1.60, 0.22, 0.40, 0.55],
	"grass":       [0.35, 1.00, 2.0, 0.08, 0.35, 0.65, 0.25, 0.50, 0.90],
	"paddy":       [0.40, 1.00, 2.0, 0.10, 0.35, 0.62, 0.18, 0.50, 0.80],
	"rigid":       [1.00, 0.00, 2.2, 0.00, 0.95, 0.00, 0.00, 0.00, 0.00],
}

## mesh 檔名（去掉 _LODn.res）前綴 → 物種。先比對的先贏。
const MESH_PREFIX := [
	["take_litter", "rigid"], ["takenoko", "rigid"], ["take_", "bamboo"],
	["sakura_shidare", "weeping"], ["yanagi", "weeping"],
	["sakura_yama", "broad_tall"], ["sakura_somei", "broad_tall"],
	["keyaki", "broad_tall"], ["kusu", "broad_tall"], ["enoki", "broad_tall"],
	["konara", "broad_tall"], ["shii", "broad_tall"],
	["momiji", "broad_small"], ["young_broad", "broad_small"], ["niwamatsu", "broad_small"],
	["young_sugi", "conifer"], ["sugi", "conifer"], ["hinoki", "conifer"],
	["akamatsu", "conifer"], ["kuromatsu", "conifer"],
	["tsutsuji", "bush"], ["shrub", "bush"], ["sasa", "bush"], ["fern", "bush"],
	["log", "rigid"], ["snag", "rigid"],
]

const TAPS := 6
const TAP_SPAN_PERIODS := 1.6


static func from_defaults(name: String) -> WindSpeciesProfile:
	var p := WindSpeciesProfile.new()
	var d: Array = DEFAULTS.get(name, DEFAULTS["broad_tall"])
	p.id = name
	p.stiffness = d[0]
	p.bend_mult = d[1]
	p.tip_response = d[2]
	p.response_lag = d[3]
	p.damping = d[4]
	p.flutter_hz = d[5]
	p.max_deform_m = d[6]
	p.crown_gain = d[7]
	p.sway_hz = d[8]
	return p


static func species_for_mesh_path(path: String) -> String:
	var stem := path.get_file().get_basename()
	var i := stem.rfind("_LOD")
	if i > 0:
		stem = stem.substr(0, i)
	for pair in MESH_PREFIX:
		if stem.begins_with(String(pair[0])):
			return String(pair[1])
	return ""


## 樹冠彈簧的 6 個取樣權重：欠阻尼二階系統脈衝響應 h(s)=e^{−ζωs}·sin(ω_d s)，
## 取樣點 s_k=(k+½)·dt，涵蓋 1.6 個固有週期，正規化成和＝1（穩定風下樹冠＝主幹，不漂移）。
## 負權重＝過衝。回傳 [w0..w5, dt]。
func spring_taps() -> Array:
	var f := maxf(sway_hz * 1.6, 0.05)
	var z := clampf(damping, 0.02, 0.95)
	var om := TAU * f
	var od := om * sqrt(1.0 - z * z)
	var dt := TAP_SPAN_PERIODS / (f * float(TAPS))
	var h: Array = []
	var s := 0.0
	for k in TAPS:
		var t := (float(k) + 0.5) * dt
		var v := exp(-z * om * t) * sin(od * t)
		h.append(v)
		s += v
	if absf(s) < 1e-6 or bend_mult <= 0.0:
		return [1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.2]
	for k in TAPS:
		h[k] = float(h[k]) / s
	h.append(dt)
	return h


## front 正弦波（ω＝1.25 rad/s，與 wf_drive 同）經過樹冠彈簧的增益與相位：
## y(t)=Σ w_k·x(t−s_k)，x=e^{iωt} → y=e^{iωt}·S，S=Σ w_k·e^{−iω s_k}，s_k=lag+(k+½)dt。回傳 [|S|, arg S]。
func front_response(omega := 1.25) -> Array:
	var w := spring_taps()
	var dt := float(w[6])
	var re := 0.0
	var im := 0.0
	for k in TAPS:
		var sk := response_lag + (float(k) + 0.5) * dt
		re += float(w[k]) * cos(omega * sk)
		im -= float(w[k]) * sin(omega * sk)
	return [sqrt(re * re + im * im), atan2(im, re)]


## 單一陣風封包（長度 dur）的樹冠響應查表：64 點，定義域 [0, tmax]，tmax＝dur＋lag＋6·dt。
## R(τ)=Σ w_k·env(τ − lag − (k+½)dt)；env＝wf_env（快升 30 %、慢落）。回傳 [64 個值..., tmax]。
func response_table(dur: float) -> PackedFloat32Array:
	var w := spring_taps()
	var dt := float(w[6])
	var tmax := dur + response_lag + 6.0 * dt
	var out := PackedFloat32Array()
	out.resize(65)
	for j in 64:
		var tau := tmax * float(j) / 63.0
		var r := 0.0
		for k in TAPS:
			r += float(w[k]) * env(tau - response_lag - (float(k) + 0.5) * dt, dur)
		out[j] = r
	out[64] = tmax
	return out


## 與 wind_field.gdshaderinc wf_env 同式
static func env(tau: float, dur: float) -> float:
	var r := 0.3 * dur
	return smoothstep(0.0, r, tau) * (1.0 - smoothstep(r, dur, tau))


## gw_species 貼圖的 5 列（shader 讀前 3 列；後 2 列是彈簧權重，給除錯／CPU 鏡像對照）
## r2.w＝樹冠響應範圍 lag＋6·dt（＝response_table 的 tmax − dur）
func texel_rows() -> Array:
	var w := spring_taps()
	var fr := front_response()
	return [
		Color(stiffness, bend_mult, tip_response, response_lag),
		Color(damping, flutter_hz, max_deform_m, crown_gain),
		Color(float(fr[0]), float(fr[1]), sway_hz, response_lag + 6.0 * float(w[6])),
		Color(w[0], w[1], w[2], w[3]),
		Color(w[4], w[5], w[6], 0.0),
	]

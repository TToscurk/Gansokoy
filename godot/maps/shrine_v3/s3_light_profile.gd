extends Node
## 博麗神社 v3 專用：白天的天空補光（只作用在本圖；掛在「天象系統」底下，見 tools/shrine_v3/build_scene.gd add_sky）。
##
## 為什麼需要（2026-10-23 光照診斷，docs/shrine_v3/02_植被光照診斷.md）：
##   共用的天象系統（scripts/sky_system.gd）每幀把 ambient_light_sky_contribution 設成 1.0。
##   Godot 的 ambient_light_energy 只在 sky_contribution < 1 時有作用（官方文件），所以天象系統裡
##   隨時刻變化的環境光強度在這個設定下不起作用——白天的陰影只剩天空 radiance：
##   實測 10:30 關掉太陽後地面的光照係數只有 0.19–0.24（＝陰影裡的全部），直射另加 1.3–1.8（約 1:7），陰影近乎全黑；
##   淺色的櫻花在同樣的陰影裡仍有 0.2–0.3 的亮度，和全黑的地面一比就像自己發光。
## 做法：白天把環境光的一部分（1 − 天空比例）換成固定的天空色補光；太陽落到地平線下時
##   漸變回天象系統原本的值（夜間完全不變）。process_priority＝100 → 每幀在天象系統之後寫入，
##   同一幀內只有這一個最終值，不會兩邊互相蓋來蓋去而閃爍。
## 不改共用的 sky_system.gd（其他地圖、其他工作階段在用）。

@export_range(0.0, 1.0, 0.01) var 天空比例: float = 0.5
# 偏冷的天空色（0.78, 0.84, 0.95）會把陰影裡的粉櫻染成灰紫（第一輪審圖）；只留一點點藍
@export var 補光色: Color = Color(0.90, 0.91, 0.96)
@export_range(0.0, 2.0, 0.01) var 補光強度: float = 0.65

var _env: Environment
var _sun: DirectionalLight3D


func _ready() -> void:
	process_priority = 100


func _find() -> void:
	var sky := get_parent()
	if sky == null:
		return
	for c in sky.get_children():
		if c is WorldEnvironment and (c as WorldEnvironment).environment != null:
			_env = (c as WorldEnvironment).environment
		elif c is DirectionalLight3D and String(c.name) == "太陽":
			_sun = c


func _process(_delta: float) -> void:
	if _env == null or _sun == null:
		_find()
		if _env == null or _sun == null:
			return
	# 朝向太陽的方向＝+basis.z（天象系統用 look_at_from_position 從太陽位置看向原點）
	var day := smoothstep(-0.10, 0.16, _sun.global_transform.basis.z.y)
	_env.ambient_light_sky_contribution = lerpf(1.0, 天空比例, day)
	_env.ambient_light_color = 補光色
	_env.ambient_light_energy = 補光強度

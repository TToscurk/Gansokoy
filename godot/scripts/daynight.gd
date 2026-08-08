extends Node
## 晝夜系統（autoload：DayNight）—— 全地圖統一，web 版 Environment 的接班人。
## 轉動 Main/Sun、調光色與強度；HUD 時鐘由 main.gd 讀 hour 顯示。

signal hour_changed(hour: float)

## 遊戲內時刻 0..24
## 預設時刻。正午是最平的光 —— 沒有長影子、沒有色溫，建築的面看不出明暗。
## 下午 15:40 的斜陽有方向感，同一個村子立刻不一樣。
var hour := 15.7
var flowing := true
## 現實幾秒 = 遊戲一天（預設 20 分鐘一天）
var day_seconds := 1200.0

const DAY_COLOR := Color(1.0, 0.956, 0.87)
const DAWN_COLOR := Color(1.0, 0.62, 0.38)
const NIGHT_COLOR := Color(0.55, 0.65, 0.95)

func _process(delta: float) -> void:
	if flowing:
		set_hour(fmod(hour + delta * 24.0 / day_seconds, 24.0))

func set_hour(h: float) -> void:
	hour = fmod(h + 24.0, 24.0)
	hour_changed.emit(hour)
	var sun := get_tree().root.get_node_or_null("Main/Sun") as DirectionalLight3D
	if sun == null:
		return
	# 6:00 日出、12:00 最高、18:00 日落；夜間當月光用
	var t := (hour - 6.0) / 12.0
	var day := t >= 0.0 and t <= 1.0
	var elev: float
	if day:
		elev = sin(PI * t) * 72.0 + 6.0
	else:
		var tn := fmod(t + 1.0, 1.0)
		elev = sin(PI * tn) * 40.0 + 8.0
	var azim := -40.0 + (t if day else fmod(t + 1.0, 1.0)) * 80.0
	sun.rotation_degrees = Vector3(-elev, azim, 0.0)
	if day:
		var low := clampf(1.0 - sin(PI * t) * 1.6, 0.0, 1.0)   # 晨昏 → 1
		sun.light_color = DAY_COLOR.lerp(DAWN_COLOR, low)
		sun.light_energy = lerpf(0.35, 1.35, clampf(sin(PI * t) * 1.4, 0.0, 1.0))
	else:
		sun.light_color = NIGHT_COLOR
		sun.light_energy = 0.12

func clock_text() -> String:
	return "%02d:%02d" % [int(hour), int(fmod(hour, 1.0) * 60.0)]

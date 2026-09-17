extends Node3D
## 水邊生態 —— 鴨子沿水路游、鯉魚在水下擺尾、鷺鷥站岸邊偶爾理羽。
## 目前人間之里場景提供路徑與水面高度，這裡只管理動態行為。
##
## 設計取捨：不用 AnimationPlayer 或骨架 —— 這些是遠景小物，
## 用程式算位移與擺動最省，而且產生器不必輸出動畫資料。

## [{ "pts": [Vector2...], "ys": [float...] }] 水路中心線與**每個節點**的水面高度
## v6 的 bug：整條水路只存一個 y，地面沿路有起伏 → 有些鴨子浮到路上、
## 有些沉進地裡。改成逐節點取樣再內插。
@export var paths: Array = []
## 各自的巡游狀態：{ node, path_i, t, speed, dir, phase, kind }
var _swimmers: Array = []

const KIND_DUCK := 0
const KIND_KOI := 1

## 水花音效。⚠ 沒有鴨叫 —— CC0／PD 素材庫裡找不到，Wikimedia 上的鴨聲全是
## CC BY-SA（傳染性授權，對遊戲資產有風險）已排除。鴨子只給划水／拍水聲，
## 寧可沒有叫聲，也不用假的。
const SND_SPLASH: Array[AudioStream] = [
	preload("res://assets/audio/sfx/water_splash_1.wav"),
	preload("res://assets/audio/sfx/water_splash_2.wav"),
	preload("res://assets/audio/sfx/water_splash_3.wav"),
]
const SND_FISH = preload("res://assets/audio/sfx/fish_splash.wav")

## 兩次水聲之間的隨機間隔（秒）。刻意稀疏 —— 一群鴨子每隻每秒拍一次水
## 會變成噪音牆，遠景小物的聲音只該偶爾提醒你它在那裡。
@export var splash_interval_min := 9.0
@export var splash_interval_max := 26.0
## 超過這個距離（公尺）就不播，免得整條水路幾十隻同時佔用 voices。
@export var audible_range := 30.0
@export var duck_volume_db := -14.0
@export var fish_volume_db := -22.0

var splashes_played := 0
var _audio_players: Array[AudioStreamPlayer3D] = []
var _rng := RandomNumberGenerator.new()
const AUDIO_POOL := 3

func _ready() -> void:
	_rng.randomize()
	for i in AUDIO_POOL:
		var p := AudioStreamPlayer3D.new()
		p.bus = AudioBuses.wildlife()
		p.max_distance = audible_range
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p)
		_audio_players.append(p)
	# 產生器在每個游動物件上標了 meta（swim_kind / swim_t / swim_speed），
	# 這裡自動收集 —— 場景存檔只會帶 meta，帶不走執行期的陣列。
	for c in get_children():
		if c is Node3D and c.has_meta("swim_kind"):
			register(c, int(c.get_meta("swim_kind")), 0,
				float(c.get_meta("swim_t")), float(c.get_meta("swim_speed")))

func register(node: Node3D, kind: int, path_i: int, t: float, speed: float) -> void:
	_swimmers.append({
		"node": node, "kind": kind, "path_i": path_i, "t": t,
		"speed": speed, "phase": randf() * TAU, "yaw": 0.0,
		# 每隻自己的水聲倒數，初值隨機散開 —— 全部同時歸零的話
		# 一群鴨子會整齊劃一地拍水，比沒有聲音更假。
		"splash_t": randf_range(splash_interval_min, splash_interval_max * 2.0),
	})

func _path_point(pi: int, t: float) -> Dictionary:
	var p: Dictionary = paths[pi]
	var pts: Array = p.pts
	var n := pts.size() - 1
	var ft := clampf(t, 0.0, 0.999) * float(n)
	var i := int(ft)
	var f := ft - float(i)
	var a: Vector2 = pts[i]
	var b: Vector2 = pts[mini(i + 1, n)]
	var pos := a.lerp(b, f)
	var ys: Array = p.ys
	var y0: float = ys[i]
	var y1: float = ys[mini(i + 1, n)]
	return { "pos": pos, "dir": (b - a).normalized(), "y": lerpf(y0, y1, f) }

func _process(delta: float) -> void:
	if paths.is_empty():
		return
	var tt := float(Time.get_ticks_msec()) * 0.001
	for s in _swimmers:
		var node: Node3D = s.node
		if not is_instance_valid(node):
			continue
		s.t += s.speed * delta
		# 走到底就掉頭（水路是有限長的）
		if s.t > 1.0:
			s.t = 1.0
			s.speed = -absf(s.speed)
		elif s.t < 0.0:
			s.t = 0.0
			s.speed = absf(s.speed)
		var info := _path_point(s.path_i, s.t)
		# 在水路寬度內左右擺一點，不要排成一直線
		var dirv: Vector2 = info.dir
		# 橫向擺動限制在水路中線附近（±1.8m），不會擦到石垣護岸
		var side: Vector2 = dirv.orthogonal() * sin(tt * 0.35 + s.phase) * 1.5
		var pos: Vector2 = Vector2(info.pos) + side
		var y: float = info.y
		if s.kind == KIND_DUCK:
			y += sin(tt * 2.3 + s.phase) * 0.045          # 浮沉（划水的節奏）
		else:
			y -= 0.32 + sin(tt * 0.9 + s.phase) * 0.10    # 鯉魚在水面下
		node.global_position = Vector3(pos.x, y, pos.y)
		# 朝向：模型的頭朝 +X（Blender 裡身體是沿 x 軸拉的），
		# Godot 繞 Y 轉 θ 會把 +X 轉到 (cos θ, -sin θ) —— v6 直接套
		# atan2(dx, dz) 是照「頭朝 -Z」算的，所以鴨子是橫著滑行。
		var fdir := dirv * signf(s.speed)
		var want := atan2(-fdir.y, fdir.x)
		# 划水會左右擺頭，不是一直線
		want += sin(tt * (1.4 if s.kind == KIND_DUCK else 2.2) + s.phase) * (0.22 if s.kind == KIND_DUCK else 0.35)
		s.yaw = lerp_angle(s.yaw, want, 3.0 * delta)
		node.rotation.y = s.yaw
		if s.kind == KIND_KOI:
			node.rotation.z = sin(tt * 3.4 + s.phase) * 0.18   # 擺尾
			node.rotation.x = sin(tt * 1.7 + s.phase * 1.3) * 0.10
		else:
			# 鴨子：划水時船身前後點頭 + 左右微傾
			node.rotation.x = sin(tt * 2.3 + s.phase) * 0.09
			node.rotation.z = sin(tt * 1.9 + s.phase * 0.7) * 0.07
		# 水聲：每隻自己倒數，稀疏觸發。
		s.splash_t -= delta
		if s.splash_t <= 0.0:
			s.splash_t = _rng.randf_range(splash_interval_min, splash_interval_max)
			_play_splash(node, s.kind)


## 水花。太遠就不播 —— 一條水路上幾十隻，全播會吃光 voices。
func _play_splash(node: Node3D, kind: int) -> void:
	var listener := node.global_position
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0 and players[0] is Node3D:
		if node.global_position.distance_to((players[0] as Node3D).global_position) > audible_range:
			return
	var target: AudioStreamPlayer3D = null
	for p in _audio_players:
		if not p.playing:
			target = p
			break
	if target == null:
		return   # 全忙就跳過這次，遠景小物不值得搶佔發聲數
	target.global_position = node.global_position
	if kind == KIND_KOI:
		target.stream = SND_FISH
		target.volume_db = fish_volume_db
	else:
		target.stream = SND_SPLASH[_rng.randi_range(0, SND_SPLASH.size() - 1)]
		target.volume_db = duck_volume_db
	target.pitch_scale = maxf(0.05, 1.0 + _rng.randf_range(-0.14, 0.14))
	target.play()
	splashes_played += 1

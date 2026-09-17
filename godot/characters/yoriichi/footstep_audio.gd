extends Node3D
class_name FootstepAudio
## 腳步音效：依腳下地表選音庫，依移動速度決定步頻。
##
## 為什麼用射線判地表而不是碰撞層：專案的地面碰撞體是各地圖自己生成的
## StaticBody3D（Terrain / 石板_00xx / RockPath_* / 木橋碰撞 …），沒有統一的
## physics layer 可分辨材質。改用射線打到的 collider 名稱比對關鍵字 —— 命名
## 是現成的、不必回頭改幾十個 .tscn，也不會動到唯讀的 sources/。
##
## 掛在 CharacterBody3D 底下，每個 physics 幀呼叫 tick()。

const GRASS_WALK: Array[AudioStream] = [
	preload("res://assets/audio/sfx/step_grass_walk_1.wav"),
	preload("res://assets/audio/sfx/step_grass_walk_2.wav"),
	preload("res://assets/audio/sfx/step_grass_walk_3.wav"),
	preload("res://assets/audio/sfx/step_grass_walk_4.wav"),
]
const GRASS_RUN: Array[AudioStream] = [
	preload("res://assets/audio/sfx/step_grass_run_1.wav"),
	preload("res://assets/audio/sfx/step_grass_run_2.wav"),
	preload("res://assets/audio/sfx/step_grass_run_3.wav"),
	preload("res://assets/audio/sfx/step_grass_run_4.wav"),
]
const STONE: Array[AudioStream] = [
	preload("res://assets/audio/sfx/step_stone_1.wav"),
	preload("res://assets/audio/sfx/step_stone_2.wav"),
	preload("res://assets/audio/sfx/step_stone_3.wav"),
]
const WOOD: Array[AudioStream] = [
	preload("res://assets/audio/sfx/step_wood_1.wav"),
	preload("res://assets/audio/sfx/step_wood_2.wav"),
	preload("res://assets/audio/sfx/step_wood_3.wav"),
]
const DIRT: Array[AudioStream] = [
	preload("res://assets/audio/sfx/step_dirt_1.wav"),
	preload("res://assets/audio/sfx/step_dirt_2.wav"),
	preload("res://assets/audio/sfx/step_dirt_3.wav"),
]

enum Surface { GRASS, STONE, WOOD, DIRT }

## 走路時每秒幾步。實測：走速 4 m/s、步幅約 1.0 m → 約 2 步/秒。
@export var walk_steps_per_sec := 1.9
## 跑步時每秒幾步。跑速 7 m/s、步幅約 1.55 m → 約 2.9 步/秒。
@export var run_steps_per_sec := 2.9
## 走路音量（dB）。
@export var walk_volume_db := -6.0
## 跑步音量（dB）。跑步踏地更重，比走路大。
@export var run_volume_db := -1.5
## 每步音高隨機範圍，避免連走時聽起來像複製貼上。
@export var pitch_variance := 0.10
## 低於這個水平速度（m/s）不算在移動，不播腳步。
@export var min_speed := 0.35
## 射線往下探多深（公尺）找地表。
@export var probe_depth := 1.6
## 3D 衰減距離（公尺）。
@export var max_distance := 28.0

var steps_played := 0
var last_surface: int = Surface.GRASS

var _body: CharacterBody3D
var _players: Array[AudioStreamPlayer3D] = []
var _phase := 0.0
var _rng := RandomNumberGenerator.new()
const POOL_SIZE := 6


func _ready() -> void:
	_rng.randomize()
	_body = get_parent() as CharacterBody3D
	for i in POOL_SIZE:
		var p := AudioStreamPlayer3D.new()
		# 不走 Master：Master 留給最終限幅，遊戲音效走 SFX 才有辦法
		# 之後做音量選單分類調整（見 scripts/audio_buses.gd）。
		p.bus = AudioBuses.sfx()
		p.max_distance = max_distance
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		# 腳步在腳下，不是身體中心 —— 正上方播會有 panning 抖動。
		p.position = Vector3(0.0, 0.05, 0.0)
		add_child(p)
		_players.append(p)


## 每個 physics 幀呼叫。grounded=接地、speed=水平速度(m/s)、running=是否衝刺。
func tick(delta: float, grounded: bool, speed: float, running: bool) -> void:
	if not grounded or speed < min_speed:
		# 停下或騰空：相位歸零，下次起步立刻有第一聲，不會延遲半拍。
		_phase = 0.0
		return
	var rate := run_steps_per_sec if running else walk_steps_per_sec
	# 步頻跟著實際速度走：慢慢推搖桿時腳步也跟著慢。
	var ref_speed := 7.0 if running else 4.0
	rate *= clampf(speed / ref_speed, 0.45, 1.35)
	_phase += delta * rate
	if _phase < 1.0:
		return
	_phase -= 1.0
	_play_step(running)


func _play_step(running: bool) -> void:
	var surface := detect_surface()
	last_surface = surface
	var bank: Array[AudioStream]
	match surface:
		Surface.STONE:
			bank = STONE
		Surface.WOOD:
			bank = WOOD
		Surface.DIRT:
			bank = DIRT
		_:
			bank = GRASS_RUN if running else GRASS_WALK
	if bank.is_empty():
		return
	var stream: AudioStream = bank[_rng.randi_range(0, bank.size() - 1)]
	var db := run_volume_db if running else walk_volume_db
	# 石板/木板沒有分走跑版本，用音量補回力度差
	if surface != Surface.GRASS and running:
		db += 3.0
	_play(stream, db)


func _play(stream: AudioStream, volume_db: float) -> void:
	var target: AudioStreamPlayer3D = null
	for p in _players:
		if not p.playing:
			target = p
			break
	if target == null:
		target = _players[0]
	target.stream = stream
	target.volume_db = volume_db
	target.pitch_scale = maxf(0.05, 1.0 + _rng.randf_range(-pitch_variance, pitch_variance))
	target.play()
	steps_played += 1


## 射線往腳下探，用 collider 名稱判斷踩在什麼上面。
## 找不到東西（例如空中或射線漏掉）一律當草地 —— 幻想鄉戶外絕大多數是草地。
func detect_surface() -> int:
	if _body == null:
		return Surface.GRASS
	var space := _body.get_world_3d().direct_space_state
	if space == null:
		return Surface.GRASS
	var from := _body.global_position + Vector3(0.0, 0.35, 0.0)
	var to := from + Vector3(0.0, -probe_depth, 0.0)
	var q := PhysicsRayQueryParameters3D.create(from, to, _body.collision_mask)
	q.exclude = [_body.get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return Surface.GRASS
	var col: Object = hit.get("collider")
	if col == null:
		return Surface.GRASS
	return classify(String(col.name) + "/" + _parent_names(col as Node))


## 名稱 → 地表。獨立成 static 方便無頭測試直接驗規則，不必生場景。
static func classify(path: String) -> int:
	var s := path.to_lower()
	# 木構：橋面、緣廊、地板、階段的木造部分
	for k in ["木橋", "wooden bri", "plank", "deck", "緣側", "縁側", "床板", "木道"]:
		if s.contains(k):
			return Surface.WOOD
	# 石構：參道石階、石板鋪面、石垣、踏石
	for k in ["石板", "石階", "石段", "踏石", "rockpath", "stone", "coping", "石垣", "階段", "bedstones"]:
		if s.contains(k):
			return Surface.STONE
	# 土路：獸道、土間、河灘
	for k in ["獸道", "獣道", "trail", "土間", "dirt", "riverbank", "河原", "gravel"]:
		if s.contains(k):
			return Surface.DIRT
	return Surface.GRASS


func _parent_names(n: Node) -> String:
	var out := ""
	var cur := n
	var depth := 0
	while cur != null and depth < 3:
		out += String(cur.name) + "/"
		cur = cur.get_parent()
		depth += 1
	return out

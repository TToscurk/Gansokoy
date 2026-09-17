extends Node3D
class_name WildlifeAudio
## 環境生物音效：白天鳥鳴、夜間梟／夜鳥／蛙、遠景森林層。
##
## 為什麼獨立一個節點而不是塞進 ambience.gd：ambience 管的是「整張圖的
## 背景床音」（單一 AudioStreamPlayer、A/B 對淡、非定位）。鳥叫需要的是
## **定位的、稀疏的、隨機的**一次性音，兩者的生命週期完全不同，混在一起
## 會把 ambience 的對淡邏輯弄髒。
##
## 掛在地圖節點底下即可；時刻讀 DayNight（走場景樹查名字，拿不到就當白天，
## 與 ambience.gd 同樣的防呆——工具模式下 autoload 不存在）。

const SND_CHIRP: Array[AudioStream] = [
	preload("res://assets/audio/sfx/bird_chirp_1.wav"),
	preload("res://assets/audio/sfx/bird_chirp_2.wav"),
	preload("res://assets/audio/sfx/bird_chirp_3.wav"),
]
const SND_FOREST = preload("res://assets/audio/sfx/bird_forest_distant.wav")
const SND_NIGHT_BIRD = preload("res://assets/audio/sfx/night_bird.wav")
const SND_OWL = preload("res://assets/audio/sfx/owl_hoot.wav")
const SND_FROG = preload("res://assets/audio/sfx/frog_croak.wav")

## 兩次叫聲之間的隨機間隔（秒）。刻意稀疏 —— 密集的鳥叫比沒有鳥叫更假。
@export var interval_min := 7.0
@export var interval_max := 22.0
## 叫聲出現在聽者周圍這個半徑內（公尺）的隨機位置。
@export var spawn_radius := 18.0
## 叫聲的高度範圍（公尺）：鳥在樹上，蛙在地面。
@export var bird_height := 6.0
@export var ground_height := 0.4
@export var volume_db := -9.0
## 遠景森林層音量（白天持續循環的底噪）。
@export var forest_layer_db := -22.0
## 關掉整組（給不需要生態音的室內地圖用）。
@export var enabled := true

var calls_played := 0

var _players: Array[AudioStreamPlayer3D] = []
## 非定位 —— 這是整張圖的背景底噪，不是某個點發出的聲音。
var _forest: AudioStreamPlayer = null
var _timer := 0.0
var _rng := RandomNumberGenerator.new()
const POOL_SIZE := 4


func _ready() -> void:
	_rng.randomize()
	for i in POOL_SIZE:
		var p := AudioStreamPlayer3D.new()
		p.bus = AudioBuses.wildlife()
		p.max_distance = 40.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p)
		_players.append(p)
	# ⚠ 遠景森林層用**非定位**播放器：它是整張圖的背景底噪，不是某個點發出的聲音。
	#   用 AudioStreamPlayer3D 綁在地圖原點的話，玩家走遠超過 max_distance
	#   就整個聽不到 —— 一張圖幾百公尺，原點附近才有鳥叫是錯的。
	_forest = AudioStreamPlayer.new()
	_forest.bus = AudioBuses.wildlife()
	_forest.volume_db = forest_layer_db
	# 8 kHz 來源，只堪當遠景底層 —— 近距離聽得出混疊，所以壓很低。
	var s := SND_FOREST
	if s is AudioStreamWAV:
		s = (s as AudioStreamWAV).duplicate()
		(s as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	_forest.stream = s
	add_child(_forest)
	_reset_timer()


func _reset_timer() -> void:
	_timer = _rng.randf_range(interval_min, interval_max)


## 目前時刻。與 ambience.gd 用同一套防呆：autoload 在工具模式下不存在，
## 直接寫 DayNight.hour 會是編譯期錯誤，整份腳本載不起來。
func _hour() -> float:
	var dn := get_tree().root.get_node_or_null("DayNight")
	return dn.hour if dn != null else 12.0


func is_night() -> bool:
	var h := _hour()
	return h < 5.0 or h >= 19.0


func _process(delta: float) -> void:
	if not enabled:
		return
	var night := is_night()
	# 遠景森林層只在白天鋪；夜裡交給 ambience 的蟲鳴。
	if _forest != null:
		if night and _forest.playing:
			_forest.stop()
		elif not night and not _forest.playing:
			_forest.play()
	_timer -= delta
	if _timer > 0.0:
		return
	_reset_timer()
	play_random_call(night)


func play_random_call(night: bool) -> void:
	var stream: AudioStream
	var height := bird_height
	if night:
		# 夜裡三選一：夜鳥最常見，梟與蛙較稀有。
		var roll := _rng.randf()
		if roll < 0.5:
			stream = SND_NIGHT_BIRD
		elif roll < 0.8:
			stream = SND_OWL
		else:
			stream = SND_FROG
			height = ground_height
	else:
		stream = SND_CHIRP[_rng.randi_range(0, SND_CHIRP.size() - 1)]
	_play_at_random_spot(stream, height)


func _play_at_random_spot(stream: AudioStream, height: float) -> void:
	if stream == null:
		return
	var target: AudioStreamPlayer3D = null
	for p in _players:
		if not p.playing:
			target = p
			break
	if target == null:
		return   # 全忙就跳過這次 —— 鳥叫不值得搶佔，寧可少叫一聲
	# 以聽者為中心隨機撒點；沒有玩家就以自己為中心。
	var origin := global_position
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0 and players[0] is Node3D:
		origin = (players[0] as Node3D).global_position
	var a := _rng.randf() * TAU
	var r := spawn_radius * sqrt(_rng.randf())   # 面積均勻，不會擠在中心
	target.global_position = origin + Vector3(cos(a) * r, height, sin(a) * r)
	target.stream = stream
	target.volume_db = volume_db
	target.pitch_scale = maxf(0.05, 1.0 + _rng.randf_range(-0.12, 0.12))
	target.play()
	calls_played += 1

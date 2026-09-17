extends Node3D
class_name WolfAudio
## 山犬音效：低吼、撲擊、受傷、死亡、遠景嚎叫。
##
## 素材全部 CC0 / Public Domain（見 work/sfx_sourcing/CREDITS.md）：
## 真實犬科錄音（96 kHz）降頻並變慢 —— 變慢等於體型變大，山犬約 2.0 m，
## 比家犬大得多，直接用原音聽起來會像鄰居家的狗。

const SND_GROWL = preload("res://assets/audio/sfx/wolf_growl.wav")
const SND_SNARL = preload("res://assets/audio/sfx/wolf_snarl.wav")
const SND_GRUMBLE = preload("res://assets/audio/sfx/wolf_grumble.wav")
const SND_ATTACK = preload("res://assets/audio/sfx/wolf_attack.wav")
const SND_HURT = preload("res://assets/audio/sfx/wolf_hurt.wav")
const SND_DEATH = preload("res://assets/audio/sfx/wolf_death.wav")
const SND_HOWL = preload("res://assets/audio/sfx/wolf_howl_distant.wav")

## 待機時每隔幾秒可能哼一聲（隨機區間下限／上限）。
@export var idle_grumble_min := 5.0
@export var idle_grumble_max := 13.0
## 整體音量偏移（dB）。
@export var volume_offset_db := 0.0
## 3D 衰減距離（公尺）。狼吼要比腳步傳得遠。
@export var max_distance := 45.0
@export var pitch_variance := 0.07

var events_played := 0

var _players: Array[AudioStreamPlayer3D] = []
var _rng := RandomNumberGenerator.new()
var _idle_timer := 0.0
const POOL_SIZE := 4


func _ready() -> void:
	_rng.randomize()
	for i in POOL_SIZE:
		var p := AudioStreamPlayer3D.new()
		p.bus = AudioBuses.wildlife()
		p.max_distance = max_distance
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		# 聲音從頭部高度出來，不是腳下。
		p.position = Vector3(0.0, 0.6, 0.0)
		add_child(p)
		_players.append(p)
	_reset_idle_timer()


func _play(stream: AudioStream, volume_db: float = 0.0, pitch_offset: float = 0.0) -> void:
	if stream == null:
		return
	var target: AudioStreamPlayer3D = null
	for p in _players:
		if not p.playing:
			target = p
			break
	if target == null:
		target = _players[0]
	target.stream = stream
	target.volume_db = volume_db + volume_offset_db
	target.pitch_scale = maxf(0.05, 1.0 + pitch_offset + _rng.randf_range(-pitch_variance, pitch_variance))
	target.play()
	events_played += 1


func _reset_idle_timer() -> void:
	_idle_timer = _rng.randf_range(idle_grumble_min, idle_grumble_max)


## 待機哼聲：由狼的 _physics_process 在 IDLE/APPROACH 狀態呼叫。
## 不自己跑 _process —— 死掉、破防時不該還在哼。
func tick_idle(delta: float, alerted: bool) -> void:
	_idle_timer -= delta
	if _idle_timer > 0.0:
		return
	_reset_idle_timer()
	if alerted:
		# 已經發現玩家：壓低喉音的威嚇
		_play(SND_GROWL, -3.0, -0.05)
	else:
		_play(SND_GRUMBLE, -9.0, 0.0)


## 前搖：撲擊是危攻擊，叫聲更凶。
func play_windup(perilous: bool) -> void:
	if perilous:
		_play(SND_SNARL, 1.0, -0.08)
	else:
		_play(SND_GROWL, -1.0, 0.0)


## 出招瞬間。
func play_attack() -> void:
	_play(SND_ATTACK, 0.0, 0.0)


## 挨打。
func play_hurt() -> void:
	_play(SND_HURT, 1.0, 0.0)


## 軀幹爆掉（可忍殺）。
func play_break() -> void:
	_play(SND_GRUMBLE, 0.0, -0.2)


## 死亡。
func play_death() -> void:
	_play(SND_DEATH, 1.5, 0.0)


## 遠景嚎叫（公有領域真實狼嚎）。給氣氛用，不綁戰鬥。
func play_howl() -> void:
	_play(SND_HOWL, -6.0, 0.0)

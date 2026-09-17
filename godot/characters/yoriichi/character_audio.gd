extends Node3D
class_name CharacterAudio
## Manages 3D sound effects for Yoriichi character actions, swings, impacts, and footsteps.

const SND_SWING_1 = preload("res://assets/audio/sfx/sword_swing_1.wav")
const SND_SWING_2 = preload("res://assets/audio/sfx/sword_swing_2.wav")
const SND_SWING_3 = preload("res://assets/audio/sfx/sword_swing_3.wav")
const SND_SWING_FIRE_1 = preload("res://assets/audio/sfx/sword_fire_swing_1.wav")
const SND_SWING_FIRE_2 = preload("res://assets/audio/sfx/sword_fire_swing_2.wav")
const SND_SWING_FIRE_3 = preload("res://assets/audio/sfx/sword_fire_swing_3.wav")
const SND_HEAVY = preload("res://assets/audio/sfx/sword_heavy.wav")
const SND_DRAW = preload("res://assets/audio/sfx/sword_draw.wav")
const SND_SHEATHE = preload("res://assets/audio/sfx/sword_sheathe.wav")
const SND_TAKEOFF = preload("res://assets/audio/sfx/jump_takeoff.wav")
const SND_LAND = preload("res://assets/audio/sfx/jump_land.wav")
const SND_ROLL = preload("res://assets/audio/sfx/roll_whoosh.wav")
const SND_HIT_LIGHT = preload("res://assets/audio/sfx/hit_impact_light.wav")
const SND_HIT_HEAVY = preload("res://assets/audio/sfx/hit_impact_heavy.wav")
const SND_HIT_FIRE_LIGHT_1 = preload("res://assets/audio/sfx/hit_fire_light_1.wav")
const SND_HIT_FIRE_LIGHT_2 = preload("res://assets/audio/sfx/hit_fire_light_2.wav")
const SND_HIT_FIRE_HEAVY = preload("res://assets/audio/sfx/hit_fire_heavy.wav")
const SND_HIT_FIRE_SPIN = preload("res://assets/audio/sfx/hit_fire_spin.wav")
## 彈刀／格擋／受傷的專用素材（CC0 真實刀劍撞擊錄音切段而來）。
## 2026-09-17 之前這三個沒有專用檔，全靠 hit_impact 調音高頂替。
const SND_DEFLECT = preload("res://assets/audio/sfx/deflect_clang.wav")
const SND_BLOCK = preload("res://assets/audio/sfx/block_thud.wav")
const SND_HURT = preload("res://assets/audio/sfx/hurt_impact.wav")

# Optional reviewed sound designs. Empty slots preserve the existing sound set.
@export var designed_swings: Array[AudioStream] = []
@export var designed_heavy: AudioStream
@export var designed_hit_light: AudioStream
@export var designed_hit_heavy: AudioStream
var events_played := 0
var _players: Array[AudioStreamPlayer3D] = []
const POOL_SIZE := 12


func _ready() -> void:
	for i in range(POOL_SIZE):
		var p := AudioStreamPlayer3D.new()
		# 不走 Master：Master 留給最終限幅（見 scripts/audio_buses.gd）。
		p.bus = AudioBuses.sfx()
		p.max_distance = 35.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p)
		_players.append(p)


func _play(stream: AudioStream, volume_db: float = 0.0, pitch_variance: float = 0.06, pitch_offset: float = 0.0) -> void:
	if stream == null:
		return
	# Find idle player
	var target: AudioStreamPlayer3D = null
	for p in _players:
		if not p.playing:
			target = p
			break
	if target == null:
		target = _players[0]

	target.stream = stream
	target.volume_db = volume_db
	target.pitch_scale = maxf(0.05, 1.0 + pitch_offset + randf_range(-pitch_variance, pitch_variance))
	target.play()
	events_played += 1


func play_swing(stage: int) -> void:
	if not designed_swings.is_empty():
		_play(designed_swings[posmod(stage - 1, designed_swings.size())], -3.0, 0.015)
		return
	match stage:
		1:
			_play(SND_SWING_FIRE_1, 0.0, 0.02)
		2:
			_play(SND_SWING_FIRE_2, 0.0, 0.02)
		3:
			_play(SND_SWING_FIRE_3, 0.0, 0.02)
		_:
			_play(SND_SWING_FIRE_1, 0.0, 0.02)


func play_heavy_swing() -> void:
	if designed_heavy != null:
		_play(designed_heavy, -2.0, 0.015)
	else:
		_play(SND_HEAVY, 0.5, 0.02)


func play_draw() -> void:
	_play(SND_DRAW, 2.5, 0.04)


func play_sheathe() -> void:
	_play(SND_SHEATHE, 2.5, 0.03)


func play_jump_takeoff() -> void:
	_play(SND_TAKEOFF, 0.5, 0.05)


func play_jump_land(heavy := false) -> void:
	_play(SND_LAND, 3.0 if heavy else 1.5, 0.06)


func play_roll() -> void:
	_play(SND_ROLL, 1.0, 0.05)


func play_fire_hit(heavy: bool = false, is_spin: bool = false, stage: int = 1) -> void:
	var designed := designed_hit_heavy if heavy else designed_hit_light
	if designed != null:
		_play(designed, -2.0, 0.015)
		return
	if is_spin:
		_play(SND_HIT_FIRE_SPIN, 5.5, 0.06)
	elif heavy:
		_play(SND_HIT_FIRE_HEAVY, 6.5, 0.04)
	else:
		var snd := SND_HIT_FIRE_LIGHT_1 if (stage % 2 == 1) else SND_HIT_FIRE_LIGHT_2
		_play(snd, 5.0, 0.05)


func play_hit(heavy := false) -> void:
	play_fire_hit(heavy)


## 彈刀：清脆的金屬撞擊。2026-09-17 起有專用素材（CC0 刀刃互擊錄音切段，
## 拉高音域 + ding 金屬泛音），不再拿 light impact 硬調音高頂替。
## ⚠ 這個方法以前不存在：yoriichi_character.gd 的 take_hit() 一直用
##   has_method("play_deflect") 擋著，所以彈刀從來沒有聲音。
func play_deflect() -> void:
	_play(SND_DEFLECT, 2.0, 0.03)


## 格擋：悶響。低通過的刀刃撞擊，與彈刀明確區隔。
func play_block() -> void:
	_play(SND_BLOCK, -1.5, 0.04)


## 玩家自己被打到。
func play_hurt() -> void:
	_play(SND_HURT, 0.0, 0.05)


## 倒地（Dead 動畫起手）。
func play_death_collapse() -> void:
	_play(SND_LAND, 0.0, 0.03, -0.3)


## 日之呼吸：型發動的專用音效。起手一律「點火」；依型再疊突刺／迴旋層。
## 使用者裁定（2026-09-16）：合成第二批太重太吵，全部退回既有素材，只用音高／音量區分。
func play_form(id: int) -> void:
	match id:
		8:
			_play(SND_SWING_FIRE_1, -2.0, 0.02, 0.25)   # 突刺：短、高
		2, 9, 10:
			_play(SND_SWING_FIRE_3, -2.0, 0.02, -0.15)  # 迴旋：長、低
		_:
			_play(SND_SWING_FIRE_2, -2.0, 0.02, 0.0)


## 忍殺。
func play_deathblow() -> void:
	play_heavy_swing()

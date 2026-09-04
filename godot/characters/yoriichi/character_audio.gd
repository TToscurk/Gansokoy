extends Node3D
class_name CharacterAudio
## Manages 3D sound effects for Yoriichi character actions, swings, impacts, and footsteps.

const SND_SWING_1 = preload("res://assets/audio/sfx/sword_swing_1.wav")
const SND_SWING_2 = preload("res://assets/audio/sfx/sword_swing_2.wav")
const SND_SWING_3 = preload("res://assets/audio/sfx/sword_swing_3.wav")
const SND_HEAVY = preload("res://assets/audio/sfx/sword_heavy.wav")
const SND_DRAW = preload("res://assets/audio/sfx/sword_draw.wav")
const SND_SHEATHE = preload("res://assets/audio/sfx/sword_sheathe.wav")
const SND_TAKEOFF = preload("res://assets/audio/sfx/jump_takeoff.wav")
const SND_LAND = preload("res://assets/audio/sfx/jump_land.wav")
const SND_ROLL = preload("res://assets/audio/sfx/roll_whoosh.wav")
const SND_HIT_LIGHT = preload("res://assets/audio/sfx/hit_impact_light.wav")
const SND_HIT_HEAVY = preload("res://assets/audio/sfx/hit_impact_heavy.wav")

var _players: Array[AudioStreamPlayer3D] = []
const POOL_SIZE := 8


func _ready() -> void:
	for i in range(POOL_SIZE):
		var p := AudioStreamPlayer3D.new()
		p.bus = &"Master"
		p.max_distance = 35.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p)
		_players.append(p)


func _play(stream: AudioStream, volume_db: float = 0.0, pitch_variance: float = 0.06) -> void:
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
	target.pitch_scale = 1.0 + randf_range(-pitch_variance, pitch_variance)
	target.play()


func play_swing(stage: int) -> void:
	match stage:
		1:
			_play(SND_SWING_1, 2.0, 0.05)
		2:
			_play(SND_SWING_2, 2.0, 0.05)
		3:
			_play(SND_SWING_3, 3.0, 0.04)
		_:
			_play(SND_SWING_1, 2.0, 0.05)


func play_heavy_swing() -> void:
	_play(SND_HEAVY, 4.0, 0.03)


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


func play_hit(heavy := false) -> void:
	if heavy:
		_play(SND_HIT_HEAVY, 5.0, 0.04)
	else:
		_play(SND_HIT_LIGHT, 3.5, 0.06)

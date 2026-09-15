class_name MachiVisualStreamer
extends Node3D
## Streams visual-only MachiCanal pieces. ground_collision.scn remains resident.

const REGIONS := {
	"Machi_Waterworks": "res://maps/slice/gen/machi_waterworks.tscn",
	"Machi_BankDressing": "res://maps/slice/gen/machi_bank_dressing.tscn",
}
# Local authored canal bounds: x -7..7, z -88..94. slice.tscn places it at
# (287, -2.868, 10), so this world rectangle includes the complete visual canal.
const X0 := 278.0
const X1 := 296.0
const Z0 := -82.0
const Z1 := 108.0
const LOAD_DISTANCE := 22.0
const UNLOAD_DISTANCE := 36.0

var _player: Node3D
var _loaded: Dictionary = {}
var _pending: Array[String] = []

func _ready() -> void:
	set_process(true)

func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = _find_player()
	if _player == null:
		return
	var distance := _distance_to_canal(_player.global_position)
	for region_name: String in REGIONS:
		if _loaded.has(region_name):
			if distance > UNLOAD_DISTANCE:
				_loaded[region_name].queue_free()
				_loaded.erase(region_name)
		elif distance <= LOAD_DISTANCE and not _pending.has(region_name):
			_pending.append(region_name)
	if not _pending.is_empty():
		_load_one(_pending.pop_front())

func _find_player() -> Node3D:
	var grouped := get_tree().get_first_node_in_group("player") as Node3D
	if grouped != null:
		return grouped
	return get_tree().root.find_child("Player", true, false) as Node3D

func _load_one(region_name: String) -> void:
	if _loaded.has(region_name):
		return
	var packed := ResourceLoader.load(REGIONS[region_name], "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if packed == null:
		push_error("[Machi stream] missing %s" % REGIONS[region_name])
		return
	var instance := packed.instantiate() as Node3D
	instance.name = region_name
	add_child(instance)
	_loaded[region_name] = instance
	var culler := get_parent().get_node_or_null("場景效能裁剪")
	if culler != null and culler.has_method("apply_to_subtree"):
		culler.call_deferred("apply_to_subtree", instance)

func _distance_to_canal(point: Vector3) -> float:
	var dx := maxf(maxf(X0 - point.x, 0.0), point.x - X1)
	var dz := maxf(maxf(Z0 - point.z, 0.0), point.z - Z1)
	return Vector2(dx, dz).length()

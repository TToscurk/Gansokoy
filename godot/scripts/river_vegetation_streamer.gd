class_name RiverVegetationStreamer
extends Node3D
## Streams visual-only river vegetation bands. Terrain and collision stay resident.

const REGIONS := {
	"RiverVegetationSouth": {"path": "res://maps/slice/gen/river_vegetation_south.tscn", "z0": -620.0, "z1": -300.0},
	"RiverVegetationLower": {"path": "res://maps/slice/gen/river_vegetation_lower.tscn", "z0": -308.0, "z1": 0.0},
	"RiverVegetationUpper": {"path": "res://maps/slice/gen/river_vegetation_upper.tscn", "z0": -8.0, "z1": 300.0},
	"RiverVegetationNorth": {"path": "res://maps/slice/gen/river_vegetation_north.tscn", "z0": 292.0, "z1": 660.0},
}
# Whole river corridor including its meanders. Z banding is the actual split.
const X0 := 250.0
const X1 := 600.0
const LOAD_DISTANCE := 70.0
const UNLOAD_DISTANCE := 100.0

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
	for region_name: String in REGIONS:
		var distance := _distance_to_region(_player.global_position, REGIONS[region_name])
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
	var spec: Dictionary = REGIONS[region_name]
	var packed := ResourceLoader.load(spec["path"], "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if packed == null:
		push_error("[River stream] missing %s" % spec["path"])
		return
	var instance := packed.instantiate() as Node3D
	instance.name = region_name
	add_child(instance)
	_loaded[region_name] = instance
	var culler := get_parent().get_node_or_null("場景效能裁剪")
	if culler != null and culler.has_method("apply_to_subtree"):
		culler.call_deferred("apply_to_subtree", instance)

func _distance_to_region(point: Vector3, spec: Dictionary) -> float:
	var dx := maxf(maxf(X0 - point.x, 0.0), point.x - X1)
	var dz := maxf(maxf(float(spec["z0"]) - point.z, 0.0), point.z - float(spec["z1"]))
	return Vector2(dx, dz).length()

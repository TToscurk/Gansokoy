class_name B1VisualStreamer
extends Node3D
## Keeps only the nearby B1 visual chunk instantiated. Building collision remains
## in building_collision.scn, so unloading visuals never opens a walk-through gap.

const SUPPORT_PATH := "res://maps/slice/gen/b1_support.tscn"
const REGIONS := {
	"B1_North": {"path": "res://maps/slice/gen/b1_north.tscn", "z0": -90.0, "z1": 0.0},
	"B1_Central": {"path": "res://maps/slice/gen/b1_central.tscn", "z0": 0.0, "z1": 46.0},
	"B1_South": {"path": "res://maps/slice/gen/b1_south.tscn", "z0": 46.0, "z1": 110.0},
}
const X0 := 198.0
const X1 := 272.0
const LOAD_DISTANCE := 18.0
const UNLOAD_DISTANCE := 30.0

var _player: Node3D
var _loaded: Dictionary = {}
var _pending: Array[String] = []
var _support: Node3D

func _ready() -> void:
	_load_support()
	set_process(true)

func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = _find_player()
	if _player == null:
		return
	for region_name in REGIONS:
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

func _load_support() -> void:
	var packed := ResourceLoader.load(SUPPORT_PATH, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if packed == null:
		push_error("[B1 stream] missing support scene")
		return
	_support = packed.instantiate() as Node3D
	add_child(_support)

func _load_one(region_name: String) -> void:
	if _loaded.has(region_name):
		return
	var spec: Dictionary = REGIONS[region_name]
	var packed := ResourceLoader.load(spec["path"], "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if packed == null:
		push_error("[B1 stream] missing %s" % spec["path"])
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

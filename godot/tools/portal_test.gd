# Portal and map-transition regression test.
#
# Run with the project-approved Godot 4.4 executable:
#   Godot --headless --path godot --script tools/portal_test.gd
extends SceneTree

const PLAYER_RADIUS := 0.45
const PLAYER_HEIGHT := 1.7
const PLAYER_SHAPE_OFFSET_Y := 0.85
const PORTAL_RADIUS := 1.6
const PORTAL_COOLDOWN := 2.0
const TRIMESH_MIN_SPAN := 15.0
const META_Y_TOLERANCE := 2.5

const HOPS := [
	["trail", "village"],
	["village", "trail"],
	["village", "kourindou"],
	["kourindou", "village"],
	["village", "hieda1f"],
	["hieda1f", "village"],
	["hieda1f", "hieda2f"],
	["hieda2f", "hieda1f"],
	["hieda2f", "hieda3f"],
	["hieda3f", "hieda2f"],
]

const SMOKE_ROUTE := ["trail", "village", "kourindou", "village", "trail"]

var _failures: Array[String] = []
var _arrivals: Dictionary = {}
var _capsule := CapsuleShape3D.new()
var _validated_dependencies: Dictionary = {}
var _scene_cache: Dictionary = {}


func _init() -> void:
	_capsule.radius = PLAYER_RADIUS
	_capsule.height = PLAYER_HEIGHT

	var version := Engine.get_version_info()
	if int(version.get("major", -1)) != 4 or int(version.get("minor", -1)) != 4:
		_fail("environment", "expected Godot 4.4.x, got %s" % Engine.get_version_info().get("string", "unknown"))

	var arrivals_by_target: Dictionary = {}
	for hop in HOPS:
		var source_id := String(hop[0])
		var target_id := String(hop[1])
		if not arrivals_by_target.has(target_id):
			arrivals_by_target[target_id] = []
		arrivals_by_target[target_id].append(source_id)
	for target_id in arrivals_by_target:
		await _check_target(String(target_id), arrivals_by_target[target_id])

	await _check_runtime_smoke_route()

	print("\n=== Portal transition summary ===")
	for route in _arrivals:
		print("ARRIVAL %s = %s" % [route, _arrivals[route]])
	if _failures.is_empty():
		print("PASS: %d hops and runtime smoke route %s" % [HOPS.size(), " -> ".join(SMOKE_ROUTE)])
		quit(0)
	else:
		print("FAIL: %d problem(s)" % _failures.size())
		for failure in _failures:
			print("  - %s" % failure)
		quit(1)


func _fail(scope: String, message: String) -> void:
	var failure := "%s: %s" % [scope, message]
	_failures.append(failure)
	push_error(failure)


func _scene_path(map_id: String) -> String:
	return "res://maps/%s/%s.tscn" % [map_id, map_id]


func _load_meta(map_id: String) -> Dictionary:
	var scope := "meta[%s]" % map_id
	var path := "res://data/%s.meta.json" % map_id
	if not FileAccess.file_exists(path):
		_fail(scope, "missing %s" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_fail(scope, "cannot open %s" % path)
		return {}
	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	if error != OK:
		_fail(scope, "malformed JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()])
		return {}
	if not json.data is Dictionary:
		_fail(scope, "root must be an object")
		return {}
	var meta: Dictionary = json.data
	if not meta.has("portals") or not meta.portals is Array:
		_fail(scope, "portals must be an array")
		return {}
	for index in range(meta.portals.size()):
		var portal: Variant = meta.portals[index]
		if not portal is Dictionary:
			_fail(scope, "portals[%d] must be an object" % index)
			return {}
		for axis in ["x", "y", "z"]:
			if not portal.has(axis) or not portal[axis] is float and not portal[axis] is int:
				_fail(scope, "portals[%d].%s must be numeric" % [index, axis])
				return {}
		if not portal.has("target"):
			_fail(scope, "portals[%d] is missing target" % index)
			return {}
		if portal.target != null and not portal.target is String:
			_fail(scope, "portals[%d].target must be a string or null" % index)
			return {}
		if portal.has("arrival_y_offset") and not portal.arrival_y_offset is float and not portal.arrival_y_offset is int:
			_fail(scope, "portals[%d].arrival_y_offset must be numeric" % index)
			return {}
		for optional_axis in ["arrival_ground_y", "arrival_yaw"]:
			if portal.has(optional_axis) and not portal[optional_axis] is float and not portal[optional_axis] is int:
				_fail(scope, "portals[%d].%s must be numeric" % [index, optional_axis])
				return {}
	return meta


func _load_scene(map_id: String) -> PackedScene:
	if _scene_cache.has(map_id):
		return _scene_cache[map_id]
	var scope := "scene[%s]" % map_id
	var path := _scene_path(map_id)
	if not ResourceLoader.exists(path, "PackedScene"):
		_fail(scope, "missing %s" % path)
		return null
	if not _validate_dependencies(path, scope, {}):
		return null
	var resource := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_REUSE)
	if not resource is PackedScene:
		_fail(scope, "failed to load PackedScene %s" % path)
		return null
	_scene_cache[map_id] = resource
	return resource


func _validate_dependencies(path: String, scope: String, seen: Dictionary) -> bool:
	if _validated_dependencies.has(path):
		return bool(_validated_dependencies[path])
	if seen.has(path):
		return true
	seen[path] = true
	var valid := true
	for encoded_dependency in ResourceLoader.get_dependencies(path):
		var dependency := String(encoded_dependency).get_slice("::", String(encoded_dependency).get_slice_count("::") - 1)
		if dependency.is_empty() or not dependency.begins_with("res://"):
			continue
		if not ResourceLoader.exists(dependency):
			_fail(scope, "required resource is unavailable: %s" % dependency)
			valid = false
			continue
		if dependency.ends_with(".tscn") or dependency.ends_with(".tres"):
			valid = _validate_dependencies(dependency, scope, seen) and valid
	_validated_dependencies[path] = valid
	return valid


func _portal_to(meta: Dictionary, target: String) -> Variant:
	for portal in meta.get("portals", []):
		if portal.get("target") == target:
			return portal
	return null


func _arrival_for(portal: Dictionary) -> Vector3:
	var arrival_y_offset := float(portal.get("arrival_y_offset", 2.0))
	var arrival_ground_y := float(portal.get("arrival_ground_y", portal.y))
	var arrival := Vector3(float(portal.x), arrival_ground_y + arrival_y_offset, float(portal.z))
	var inward := Vector3(0.0, arrival.y, 0.0) - arrival
	inward.y = 0.0
	if inward.length() > 0.01:
		arrival += inward.normalized() * 4.0
	return arrival


func _check_target(target_id: String, source_ids: Array) -> void:
	print("\n--- target %s; arrivals from %s ---" % [target_id, source_ids])
	var target_meta := _load_meta(target_id)
	var target_scene := _load_scene(target_id)
	if target_meta.is_empty() or target_scene == null:
		return
	var root := target_scene.instantiate() as Node3D
	if root == null:
		_fail("target[%s]" % target_id, "target scene could not be instantiated")
		return
	get_root().add_child(root)
	_build_runtime_collisions(root, target_meta)
	await physics_frame
	await physics_frame

	var terrain := root.find_child("Terrain", true, false) as MeshInstance3D
	if terrain == null or terrain.mesh == null:
		_fail("target[%s]" % target_id, "target Terrain mesh is missing or failed to load")
		await _teardown(root)
		return
	var space := root.get_world_3d().direct_space_state
	for source_id_value in source_ids:
		var source_id := String(source_id_value)
		var scope := "%s -> %s" % [source_id, target_id]
		var source_meta := _load_meta(source_id)
		var source_scene := _load_scene(source_id)
		if source_meta.is_empty() or source_scene == null:
			continue
		if _portal_to(source_meta, target_id) == null:
			_fail(scope, "source portal is missing")
			continue
		var return_portal: Variant = _portal_to(target_meta, source_id)
		if return_portal == null:
			_fail(scope, "target portal back to source is missing; arrival cannot be resolved")
			continue

		var arrival := _arrival_for(return_portal)
		_arrivals[scope] = arrival
		var ground: Variant = _ground_at(space, terrain, arrival.x, arrival.z)
		if ground == null:
			_fail(scope, "no ground below arrival %s" % arrival)
			continue
		if absf(float(ground) - float(return_portal.y)) > META_Y_TOLERANCE:
			_fail(scope, "ground y %.2f differs from portal y %.2f" % [float(ground), float(return_portal.y)])
		var overlaps := _capsule_overlaps(space, arrival)
		if not overlaps.is_empty():
			var names: Array[String] = []
			for overlap in overlaps:
				var collider: Object = overlap.get("collider")
				names.append(String(collider.name) if collider is Node else "RID %s" % overlap.get("rid"))
			_fail(scope, "player capsule overlaps %s at actual arrival %s" % [names, arrival])

		var portal_center := Vector2(float(return_portal.x), float(return_portal.z))
		var arrival_xz := Vector2(arrival.x, arrival.z)
		var portal_clearance := arrival_xz.distance_to(portal_center) - PORTAL_RADIUS - PLAYER_RADIUS
		if portal_clearance <= 0.0:
			_fail(scope, "arrival remains inside return portal trigger (clearance %.2f m)" % portal_clearance)
		else:
			print("%s arrival=%s ground_y=%.2f clearance=%.2fm" % [scope, arrival, float(ground), portal_clearance])
	await _teardown(root)


func _build_runtime_collisions(root: Node3D, meta: Dictionary) -> void:
	var own_colliders: bool = root.get_meta("own_colliders", false)
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child: Node in node.get_children():
			stack.append(child)
		if node is MeshInstance3D:
			if own_colliders and not (String(node.name) == "Terrain" or node.has_meta("needs_trimesh")):
				continue
			var bounds: AABB = (node as MeshInstance3D).get_aabb()
			if maxf(bounds.size.x, bounds.size.z) >= TRIMESH_MIN_SPAN:
				(node as MeshInstance3D).create_trimesh_collision()
	if own_colliders:
		return
	var body := StaticBody3D.new()
	body.name = "TestGameColliders"
	root.add_child(body)
	for collider in meta.get("colliders", []):
		var shape := CollisionShape3D.new()
		var height := float(collider.get("h", 1.0))
		if collider.has("r"):
			var cylinder := CylinderShape3D.new()
			cylinder.radius = float(collider.r)
			cylinder.height = height
			shape.shape = cylinder
		else:
			var box := BoxShape3D.new()
			box.size = Vector3(float(collider.hw) * 2.0, height, float(collider.hd) * 2.0)
			shape.shape = box
		shape.position = Vector3(float(collider.x), float(collider.get("y", 0.0)) + height * 0.5, float(collider.z))
		body.add_child(shape)


func _ground_at(space: PhysicsDirectSpaceState3D, terrain: MeshInstance3D, x: float, z: float) -> Variant:
	var terrain_bounds := terrain.global_transform * terrain.get_aabb()
	var terrain_top := terrain_bounds.position.y + terrain_bounds.size.y
	var from_y := terrain_top + 60.0
	for attempt in range(8):
		var query := PhysicsRayQueryParameters3D.create(Vector3(x, from_y, z), Vector3(x, terrain_top - 40.0, z))
		query.collide_with_areas = false
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return null
		var y := float(hit.position.y)
		if y <= terrain_top + META_Y_TOLERANCE:
			return y
		from_y = y - 0.05
	return null


func _capsule_overlaps(space: PhysicsDirectSpaceState3D, player_position: Vector3) -> Array[Dictionary]:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _capsule
	query.collide_with_areas = false
	query.transform = Transform3D(Basis(), player_position + Vector3.UP * PLAYER_SHAPE_OFFSET_Y)
	return space.intersect_shape(query, 32)


func _check_runtime_smoke_route() -> void:
	print("\n--- Runtime smoke: %s ---" % " -> ".join(SMOKE_ROUTE))
	var packed := ResourceLoader.load("res://scenes/main.tscn", "PackedScene") as PackedScene
	if packed == null:
		_fail("runtime smoke", "main scene failed to load")
		return
	var main := packed.instantiate()
	if main == null:
		_fail("runtime smoke", "main scene failed to instantiate")
		return
	get_root().add_child(main)
	await process_frame
	await physics_frame

	main.load_map(SMOKE_ROUTE[0], "")
	await process_frame
	await physics_frame
	if main.current_id != SMOKE_ROUTE[0]:
		_fail("runtime smoke", "failed to start on %s" % SMOKE_ROUTE[0])
		await _teardown(main)
		return

	for index in range(1, SMOKE_ROUTE.size()):
		var source_id: String = SMOKE_ROUTE[index - 1]
		var target_id: String = SMOKE_ROUTE[index]
		main.portal_cooldown = 0.0
		main._on_portal_entered(main.player, target_id)
		await process_frame
		await process_frame
		if main.current_id != target_id:
			_fail("runtime smoke", "transition %s -> %s did not complete" % [source_id, target_id])
			break
		var observed: Vector3 = main.player.global_position
		var expected_meta := _load_meta(target_id)
		var return_portal: Variant = _portal_to(expected_meta, source_id)
		if return_portal == null:
			_fail("runtime smoke", "arrival for %s -> %s cannot be resolved" % [source_id, target_id])
			break
		var expected := _arrival_for(return_portal)
		if Vector2(observed.x, observed.z).distance_to(Vector2(expected.x, expected.z)) > 0.05:
			_fail("runtime smoke", "%s -> %s arrived at wrong XZ %s, expected %s" % [source_id, target_id, observed, expected])
		if observed.y > expected.y + 0.05 or observed.y < float(return_portal.y) - 0.5:
			_fail("runtime smoke", "%s -> %s arrival y %.2f is outside safe range" % [source_id, target_id, observed.y])
		print("runtime %s -> %s arrival=%s cooldown=%.2fs" % [source_id, target_id, observed, main.portal_cooldown])

		var before_bounce_id: String = main.current_id
		main._on_portal_entered(main.player, source_id)
		await process_frame
		await process_frame
		if main.current_id != before_bounce_id:
			_fail("runtime smoke", "cooldown failed; %s immediately bounced back to %s" % [target_id, source_id])
		if main.portal_cooldown <= 0.0 or main.portal_cooldown > PORTAL_COOLDOWN:
			_fail("runtime smoke", "invalid cooldown after %s -> %s: %.3f" % [source_id, target_id, main.portal_cooldown])
	await _teardown(main)


func _teardown(node: Node) -> void:
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	node.queue_free()
	await process_frame

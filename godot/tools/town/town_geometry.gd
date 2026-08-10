extends RefCounted

## Pure geometry helpers shared by the Human Village generator.
##
## OBB layout is kept as the legacy Array contract so extracting this module
## cannot change serialized output or the order in which callers operate:
## [center, local_x, local_z, half_x, half_z, kind].


static func obb_of(entry: Array, modules: Dictionary) -> Array:
	## Build a world-space OBB from a module's measured Godot-local bounding box.
	var module: Dictionary = modules[entry[0]]
	var gbox: Array
	if bool(module.get("centered", false)):
		gbox = [-float(module["fw"]) * 0.5, float(module["fw"]) * 0.5,
			-float(module["fd"]) * 0.5, float(module["fd"]) * 0.5]
	else:
		gbox = module.get("gbox", [-float(module["fw"]) * 0.5,
			float(module["fw"]) * 0.5, -float(module["fd"]) + 0.85, 0.85])
	var yaw: float = entry[4]
	var axis_x := Vector2(cos(yaw), -sin(yaw))
	var axis_z := Vector2(sin(yaw), cos(yaw))
	var center_x: float = (float(gbox[0]) + float(gbox[1])) * 0.5
	var center_z: float = (float(gbox[2]) + float(gbox[3])) * 0.5
	var center := Vector2(entry[1], entry[3]) + axis_x * center_x + axis_z * center_z
	return [center, axis_x, axis_z,
		(float(gbox[1]) - float(gbox[0])) * 0.5,
		(float(gbox[3]) - float(gbox[2])) * 0.5, entry[0]]


static func penetration(a: Array, b: Array) -> float:
	## Return the shallowest separating-axis overlap, or zero when disjoint.
	var depth := 1e18
	for rect in [a, b]:
		for axis_index in [1, 2]:
			var axis: Vector2 = rect[axis_index]
			var center_a: float = Vector2(a[0]).dot(axis)
			var center_b: float = Vector2(b[0]).dot(axis)
			var extent_a: float = absf(Vector2(a[1]).dot(axis)) * a[3] \
				+ absf(Vector2(a[2]).dot(axis)) * a[4]
			var extent_b: float = absf(Vector2(b[1]).dot(axis)) * b[3] \
				+ absf(Vector2(b[2]).dot(axis)) * b[4]
			var overlap := extent_a + extent_b - absf(center_a - center_b)
			if overlap <= 0.0:
				return 0.0
			depth = minf(depth, overlap)
	return depth

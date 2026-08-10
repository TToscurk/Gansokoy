extends RefCounted

## Pure river-shape queries. Terrain carving and scene construction remain in
## the generator so this module has no access to generator state or RNG.


static func spline(control_points: Array, points_per_segment: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in control_points.size() - 1:
		var p0: Vector2 = control_points[max(i - 1, 0)]
		var p1: Vector2 = control_points[i]
		var p2: Vector2 = control_points[i + 1]
		var p3: Vector2 = control_points[min(i + 2, control_points.size() - 1)]
		for k in points_per_segment:
			var t := float(k) / points_per_segment
			points.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t
				+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t
				+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t))
	points.append(control_points[control_points.size() - 1])
	return points


static func nearest_point(points: PackedVector2Array, at: Vector2) -> Vector2:
	var best := points[0]
	var best_distance := 1e18
	for point in points:
		var distance := point.distance_squared_to(at)
		if distance < best_distance:
			best_distance = distance
			best = point
	return best


static func tangent(points: PackedVector2Array, at: Vector2) -> Vector2:
	var best_index := 0
	var best_distance := 1e18
	for i in points.size():
		var distance := points[i].distance_squared_to(at)
		if distance < best_distance:
			best_distance = distance
			best_index = i
	return (points[min(best_index + 1, points.size() - 1)]
		- points[max(best_index - 1, 0)]).normalized()

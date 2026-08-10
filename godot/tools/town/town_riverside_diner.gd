extends RefCounted


# "unomitei" is the legacy asset key. The canonical visible name is 鯢吞亭.
const ASSET_KEY := "unomitei"


static func build(
		lib,
		root: Node3D,
		anchor: Vector2,
		river_half: float,
		mods: Dictionary,
		nearest_river_point: Callable,
		river_tangent: Callable,
		bank_h: Callable,
		obb_of: Callable,
		dump: Array,
		reserved: Array,
		audit: Array[String]) -> Vector2:
	var river_point: Vector2 = nearest_river_point.call(anchor)
	var tangent: Vector2 = river_tangent.call(river_point)
	var land_normal := Vector2(-tangent.y, tangent.x)
	if land_normal.dot(anchor - river_point) < 0.0:
		land_normal = -land_normal
	var position: Vector2 = river_point + land_normal * 18.5
	var mesh: Mesh = lib.prop_mesh(String(mods[ASSET_KEY]["glb"]))
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	var yaw := atan2(land_normal.x, land_normal.y)
	instance.position = Vector3(
		position.x, float(bank_h.call(position.x, position.y)), position.y)
	instance.rotation.y = yaw
	instance.set_meta("needs_trimesh", true)
	lib.add(root, instance, "鯢吞亭")
	dump.append([ASSET_KEY, position.x, instance.position.y, position.y, yaw])
	reserved.append(obb_of.call(
		[ASSET_KEY, position.x, 0.0, position.y, yaw]))
	var deck_out: Vector2 = position - land_normal * 16.0
	audit.append("鯢吞亭（臨河食堂）@(%.1f,%.1f) yaw %.1f°　川床外緣離河心 %.1fm"
		% [position.x, position.y, rad_to_deg(yaw),
			deck_out.distance_to(river_point)]
		+ "（水面半寬 %.1f → 懸在水上 %.1fm）、離主橋 %.0fm"
		% [river_half * 0.86,
			river_half * 0.86 - deck_out.distance_to(river_point),
			position.distance_to(Vector2(66, 30))])
	return position

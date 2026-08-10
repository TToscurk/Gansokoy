extends RefCounted


static func kitify(config: Dictionary) -> Dictionary:
	var result: Dictionary = config.duplicate(true)
	result["kit"] = true
	var front_row: Dictionary = result["rows"][0]
	front_row["setback"] = 0.15
	front_row["jog"] = [0.35, 1.1]
	front_row["jog_max"] = 1.35
	return result


static func build_block(
		seed_index: int,
		config: Dictionary,
		rng: RandomNumberGenerator,
		context: Dictionary) -> void:
	var mods: Dictionary = context.mods
	var plaza: Vector2 = context.plaza
	var start: Vector2 = config["frontage"]["a"]
	var finish: Vector2 = config["frontage"]["b"]
	var along := (finish - start).normalized()
	var inward: Vector2 = config.get("into", Vector2(-along.y, along.x))
	var face := -inward
	var span := start.distance_to(finish)
	var rows: Array = config["rows"]
	var block_name: String = config.get("name", "block")
	var spacing: Array = config.get("spacing", [1.9, 3.0])
	var wrap: String = config.get("wrap", "")
	var wrap_kind: String = config.get("wrap_kind", "machiya_f_a")
	var wrap_end: String = config.get("wrap_end", "b")
	var reserve_start := 0.0
	var reserve_finish := 0.0
	if wrap == "U" or (wrap == "L" and wrap_end == "a"):
		reserve_start = float(mods[wrap_kind]["d"]) + 1.6
	if wrap == "U" or (wrap == "L" and wrap_end == "b"):
		reserve_finish = float(mods[wrap_kind]["d"]) + 1.6
	var river_reserve := 0.0
	if config.get("river_end", false):
		river_reserve = float(
			mods[config.get("river_kind", "machiya_f_b")]["fd"]) + 2.6
		reserve_finish = maxf(reserve_finish, river_reserve)
	var front_depth := 0.0
	var row_index := 0
	for row in rows:
		var kinds: Array = row["kinds"]
		var jog: Array = row.get("jog", [1.0, 2.0])
		var base_setback: float = row.get("setback", 0.8)
		if row_index > 0:
			base_setback = front_depth + rng.randf_range(
				row["gap"][0], row["gap"][1])
		var cursor: float = row.get("start", 0.6) \
			+ float(row.get("lateral", 0.0))
		if row_index == 0:
			cursor += reserve_start
		var gap_after: int = row.get("gap_after", -1)
		var previous_setback := base_setback
		var deepest := base_setback
		var house_index := 0
		while true:
			var pick_position: Vector2 = start + along * cursor \
				+ inward * base_setback
			var kind: String = _kit_pick(
				pick_position, rng, context.commerce) \
				if (config.get("kit", false) and row_index == 0) \
				else kinds[(house_index + seed_index) % kinds.size()]
			if row_index == 0 and not config.get("kit", false):
				kind = _frontage_pick(
					kind, pick_position, rng, context.commerce)
			kind = _consolidate(
				kind, start + along * cursor + inward * base_setback, context)
			var module: Dictionary = mods[kind]
			var width: float = module["w"]
			var limit: float = span - 0.4 \
				- (reserve_finish if row_index == 0 else river_reserve)
			if cursor + width > limit:
				break
			var setback := base_setback
			if house_index > 0:
				var delta := rng.randf_range(jog[0], jog[1]) \
					* (1.0 if house_index % 2 == 1 else -1.0)
				setback = clampf(
					previous_setback + delta, base_setback,
					base_setback + float(row.get("jog_max", 2.2)))
			previous_setback = setback
			var provisional: Vector2 = start + along * (cursor + width * 0.5) \
				+ inward * setback
			if Vector2(
					provisional.x,
					provisional.y - plaza.y).length() >= 155.0 \
					and kind != "machiya_e_a" and kind != "machiya_e_p":
				kind = "machiya_f_s" if rng.randf() < 0.26 \
					else _consolidate("machiya_e_a", provisional, context)
				module = mods[kind]
				width = module["w"]
			var centre: Vector2 = start + along * (cursor + width * 0.5) \
				+ inward * setback
			if _on_road(centre, face, kind, context) \
					or _in_reserved(kind, centre, face, context):
				cursor += width + rng.randf_range(spacing[0], spacing[1])
				house_index += 1
				continue
			_house(kind, centre, face, context)
			deepest = maxf(deepest, setback + float(module["d"]) + 1.0)
			cursor += width + rng.randf_range(spacing[0], spacing[1])
			if house_index == gap_after:
				cursor += rng.randf_range(6.5, 8.0)
			house_index += 1
		front_depth = deepest
		row_index += 1
	if wrap != "":
		var ends: Array = []
		if wrap == "U":
			ends = [[start, -1.0], [finish, 1.0]]
		else:
			ends = [[finish, 1.0]] if wrap_end == "b" \
				else [[start, -1.0]]
		for end_pair in ends:
			var endpoint: Vector2 = end_pair[0]
			var sign: float = end_pair[1]
			if sign > 0 and config.get("river_end", false):
				continue
			var wrap_module: Dictionary = mods[wrap_kind]
			var front_setback: float = rows[0].get("setback", 0.8)
			var position: Vector2 = endpoint + along * sign * 0.3 \
				+ inward * (front_setback + float(wrap_module["w"]) * 0.5)
			_house(wrap_kind, position, along * sign, context)
	if config.get("river_end", false):
		var river_kind: String = config.get("river_kind", "machiya_f_b")
		var river_point: Vector2 = context.nearest_river_point.call(
			config["river_anchor"])
		var tangent: Vector2 = context.river_tangent.call(river_point)
		var normal := Vector2(-tangent.y, tangent.x)
		if normal.dot(Vector2(config["river_anchor"]) - river_point) < 0.0:
			normal = -normal
		_house(
			river_kind,
			river_point + normal * (float(context.river_half) + 4.9),
			-normal, context)


static func _kit_pick(
		position: Vector2,
		rng: RandomNumberGenerator,
		commerce: Callable) -> String:
	var weight: float = commerce.call(position)
	var random_value := rng.randf()
	if weight > 0.55:
		if random_value < 0.18:
			return "machiya_f_o"
		if random_value < 0.36:
			return "machiya_w_a"
		if random_value < 0.48:
			return "machiya_f_n"
		if random_value < 0.58:
			return "machiya_f_s"
		return "machiya_f_a"
	if weight > 0.30:
		if random_value < 0.15:
			return "machiya_t_a"
		if random_value < 0.29:
			return "machiya_f_n"
		if random_value < 0.40:
			return "machiya_w_a"
		return "machiya_f_a"
	if random_value < 0.34:
		return "machiya_f_s"
	return "machiya_f_a"


static func _frontage_pick(
		base_kind: String,
		position: Vector2,
		rng: RandomNumberGenerator,
		commerce_fn: Callable) -> String:
	if base_kind != "machiya_f_a":
		return base_kind
	var random_value := rng.randf()
	var commerce: float = commerce_fn.call(position)
	if random_value < 0.12:
		return "machiya_f_s"
	if random_value < 0.22:
		return "machiya_w_a"
	if random_value < 0.29 and commerce > 0.22:
		return "machiya_t_a"
	if random_value < 0.36 and commerce > 0.30:
		return "machiya_f_n"
	return base_kind


static func _consolidate(
		kind: String,
		position: Vector2,
		context: Dictionary) -> String:
	if bool(context.ghosting):
		return kind
	var replacements: Dictionary = context.consolidate
	if not replacements.has(kind):
		return kind
	if not bool(context.consolidate_all) and not (
			absf(position.x) < 40.0
			and position.y >= -165.0 and position.y <= -80.0):
		return kind
	return String(replacements[kind])


static func _house(
		kind: String,
		position: Vector2,
		face_direction: Vector2,
		context: Dictionary) -> void:
	var plaza: Vector2 = context.plaza
	if kind != "machiya_e_a" and kind.begins_with("machiya") \
			and Vector2(position.x, position.y - plaza.y).length() >= 155.0:
		kind = _consolidate("machiya_e_a", position, context)
	kind = _consolidate(kind, position, context)
	if _in_reserved(kind, position, face_direction, context) \
			or _on_road(position, face_direction, kind, context):
		return
	var yaw := atan2(face_direction.x, face_direction.y)
	var y: float = context.bank_h.call(position.x, position.y)
	if bool(context.ghosting):
		(context.ghost as Array).append([
			kind, position.x, y, position.y, yaw])
		return
	var transform := Transform3D(
		Basis(Vector3.UP, yaw), Vector3(position.x, y, position.y))
	var batches: Dictionary = context.batches
	if not batches.has(kind):
		batches[kind] = []
	batches[kind].append(transform)
	(context.dump as Array).append([kind, position.x, y, position.y, yaw])


static func _on_road(
		position: Vector2,
		face_direction: Vector2,
		kind: String,
		context: Dictionary) -> bool:
	var module: Dictionary = (context.mods as Dictionary)[kind]
	var forward := face_direction.normalized()
	var side := Vector2(forward.y, -forward.x)
	var half_width: float = float(module["w"]) * 0.5
	var depth: float = float(module["d"])
	for side_sign in [-1.0, 1.0]:
		for depth_sign in [0.0, 1.0]:
			var point: Vector2 = position + side * side_sign * half_width \
				- forward * (depth * depth_sign)
			for road in context.roads:
				if context.lib.poly_dist(road.pts, point.x, point.y) \
						< road.w * 0.5 + 0.9:
					return true
	return false


static func _in_reserved(
		kind: String,
		position: Vector2,
		face_direction: Vector2,
		context: Dictionary) -> bool:
	var yaw := atan2(face_direction.x, face_direction.y)
	var bounds: Array = context.obb_of.call(
		[kind, position.x, 0.0, position.y, yaw])
	for reserved_bounds in context.reserved:
		if float(context.obb_pen.call(bounds, reserved_bounds)) > 0.05:
			return true
	return false

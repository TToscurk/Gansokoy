extends RefCounted

## Pure terrain-mask helpers. They read the supplied deterministic noise but
## do not mutate generator state or consume an RNG sequence.

static func rounded_rect(noise: FastNoiseLite, x: float, z: float,
		center: Vector2, half_size: Vector2, fade: float, wobble: float) -> float:
	var sd: float = maxf(absf(x - center.x) - half_size.x,
		absf(z - center.y) - half_size.y)
	if wobble > 0.0:
		sd += noise.get_noise_2d(x * 0.55 + 13.0, z * 0.55 - 9.0) * wobble
	return clampf(1.0 - smoothstep(0.0, fade, sd), 0.0, 1.0)


static func market_ground(noise: FastNoiseLite, x: float, z: float) -> float:
	var plaza: float = rounded_rect(noise, x, z,
		Vector2(-25.0, 62.5), Vector2(18.0, 13.0), 5.0, 2.4)
	# 東端延伸到本通路肩，避免南東角的藏獨自立在草上。
	var south: float = rounded_rect(noise, x, z,
		Vector2(-27.0, 76.5), Vector2(22.0, 7.5), 4.2, 1.8)
	var west: float = rounded_rect(noise, x, z,
		Vector2(-49.0, 65.0), Vector2(6.5, 10.5), 4.0, 1.6)
	return maxf(plaza, maxf(south, west))


static func market_paving(noise: FastNoiseLite, x: float, z: float) -> float:
	# 本通到市木戶的入口，以及南緣、西緣常設店的門檻。
	var entry: float = rounded_rect(noise, x, z,
		Vector2(-11.5, 62.0), Vector2(6.5, 16.0), 3.0, 1.1)
	var threshold: float = rounded_rect(noise, x, z,
		Vector2(-28.5, 71.6), Vector2(13.5, 1.8), 2.4, 0.9)
	var west: float = rounded_rect(noise, x, z,
		Vector2(-43.4, 64.5), Vector2(2.2, 9.0), 2.2, 0.9)
	return maxf(entry, maxf(threshold, west))

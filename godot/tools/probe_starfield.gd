extends SceneTree
## Measure the 2D cube-face starfield the same way a camera samples it.
##
## Why this replaced the previous probe: the old 3D-cell version measured a 0.4%
## hit rate and no amount of threshold tuning fixed it, because the flaw was
## geometric — stars were placed in a VOLUME while only the sphere's surface is
## ever visible, so a star's radial offset alone dimmed it to nothing. This
## version ports the cube-face maths verbatim and reports both how many
## directions light up AND how bright those hits are, which is the number that
## actually decides whether a star survives tonemapping.
##
## Run: godot --headless --path godot --script tools/probe_starfield.gd

const DENSITIES := [0.0, 0.01, 0.15, 0.3, 0.5, 0.75, 1.0]
const CELL_SCALE := 190.0


func _init() -> void:
	print("星場取樣測試（2D 立方面版本）\n")
	print("%-8s %-12s %-12s %-12s %s" % [
		"密度", "有星比例", "平均亮度", "亮星比例", "最大亮度"])

	for d in DENSITIES:
		var hits := 0
		var bright := 0
		var total := 0
		var sum := 0.0
		var best := 0.0

		for i in 90:
			for j in 180:
				var theta := PI * 0.5 * (float(i) + 0.5) / 90.0
				var phi := TAU * (float(j) + 0.5) / 180.0
				var dir := Vector3(
					sin(theta) * cos(phi),
					cos(theta),
					sin(theta) * sin(phi)
				).normalized()
				var v := _starfield(dir, d)
				total += 1
				sum += v
				if v > 0.02:
					hits += 1
				# 0.25 is roughly where a star still reads as a point after the
				# ACES curve and the glow threshold.
				if v > 0.25:
					bright += 1
				best = maxf(best, v)

		print("%-8.2f %-12s %-12.5f %-12s %.4f" % [
			d,
			"%.2f%%" % (100.0 * hits / total),
			sum / total,
			"%.2f%%" % (100.0 * bright / total),
			best])

	print("\n判讀：")
	print("  亮星比例 < 0.2%%  → 螢幕上幾乎看不到")
	print("  亮星比例 1~4%%   → 正常星空")
	print("  亮星比例 > 10%%  → 太密，像雜訊")
	quit(0)


## Verbatim port of hash_star from sky_daynight.gdshader.
func _hash_star(p: Vector3) -> float:
	var q := Vector3(floor(p.x), floor(p.y), floor(p.z))
	q = Vector3(
		fposmod(q.x * 0.1031, 1.0),
		fposmod(q.y * 0.1030, 1.0),
		fposmod(q.z * 0.0973, 1.0)
	)
	var dotv: float = q.dot(Vector3(q.y, q.x, q.z) + Vector3(33.33, 33.33, 33.33))
	q += Vector3(dotv, dotv, dotv)
	return fposmod((q.x + q.y) * q.z, 1.0)


## Verbatim port of cube_uv.
func _cube_uv(d: Vector3) -> Array:
	var a := Vector3(absf(d.x), absf(d.y), absf(d.z))
	if a.x >= a.y and a.x >= a.z:
		return [Vector2(d.z, d.y) / a.x, 0.0 if d.x > 0.0 else 1.0]
	if a.y >= a.z:
		return [Vector2(d.x, d.z) / a.y, 2.0 if d.y > 0.0 else 3.0]
	return [Vector2(d.x, d.y) / a.z, 4.0 if d.z > 0.0 else 5.0]


func _starfield(dir: Vector3, density: float) -> float:
	if density <= 0.001:
		return 0.0
	var r := _cube_uv(dir)
	var uv: Vector2 = r[0]
	var face: float = r[1]
	var p := uv * CELL_SCALE
	var cell := Vector2(floor(p.x), floor(p.y))
	var f := p - cell
	var best := 0.0
	for x in range(-1, 2):
		for y in range(-1, 2):
			var o := Vector2(x, y)
			var key := Vector3(cell.x + o.x, cell.y + o.y, face)
			var seed := _hash_star(key)
			if seed > lerpf(0.9992, 0.90, density * density):
				var pos := o + Vector2(
					_hash_star(key + Vector3(11.3, 11.3, 11.3)),
					_hash_star(key + Vector3(27.7, 27.7, 27.7))
				)
				var dd := (f - pos).length()
				var mag := 0.35 + 0.65 * _hash_star(key + Vector3(61.9, 61.9, 61.9))
				var s := smoothstep(0.45, 0.0, dd) * mag
				best = maxf(best, s)
	return best

class_name WaterField
extends RefCounted
## Wind V2 水面場（CPU 鏡像）——與 assets/shaders/water_field.gdshaderinc 逐項同式。
## 由 Wind autoload 持有（Wind.water）；浮物與玩法用 Wind.sample_water_height／normal／flow。
##
## 座標：世界 XZ（m）。流速 m/s。高度＝世界 Y（靜水面 water_y ＋長波＋漣漪）。
## 流場：河道中心線（上游→下游）＋半寬 → 1 m 解析度世界貼圖（R,G＝流速／2／FLOW_RANGE＋0.5、B＝在水中）。
##   上傳成 gw_flow（shader 線性內插）；CPU 這邊對同一張 Image 做雙線性取樣 → 兩邊同一個流。

const FLOW_RANGE := 2.0
const RES_M := 1.0
const G := 9.81

var water_y := 0.0
var rect := Rect2()          # 流場覆蓋範圍（世界 XZ）
var img: Image               # RGBA8：同上傳給 shader 的那張
var tex: ImageTexture
var long_amp := 0.02         # gw_water.x：長波振幅（m）
var ripple_gain := 1.0       # gw_water.y
var name := ""


## 從中心線建流場。pts：PackedVector2Array（上游→下游）；half_w：每點半寬（m）；speed：中央流速 m/s。
func build(body_name: String, pts: PackedVector2Array, half_w: PackedFloat32Array, wy: float, speed := 0.55) -> void:
	name = body_name
	water_y = wy
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var maxhw := 0.0
	for i in pts.size():
		lo = lo.min(pts[i])
		hi = hi.max(pts[i])
		maxhw = maxf(maxhw, half_w[i])
	var pad := maxhw + 6.0
	rect = Rect2(lo - Vector2(pad, pad), hi - lo + Vector2(pad, pad) * 2.0)
	var w := int(ceil(rect.size.x / RES_M))
	var h := int(ceil(rect.size.y / RES_M))
	img = Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	for iy in h:
		for ix in w:
			var p := rect.position + Vector2((ix + 0.5) * RES_M, (iy + 0.5) * RES_M)
			var best := INF
			var bt := Vector2.ZERO
			var bhw := 1.0
			for s in pts.size() - 1:
				var a := pts[s]
				var b := pts[s + 1]
				var ab := b - a
				var u := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
				var d := p.distance_to(a + ab * u)
				if d < best:
					best = d
					bt = ab.normalized()
					bhw = lerpf(half_w[s], half_w[s + 1], u)
			# 中央快、近岸慢（拋物線剖面）；半寬外 3 m 內淡出（網格水面會略超出中心線半寬）
			var r := best / maxf(bhw, 0.5)
			var prof := clampf(1.0 - r * r, 0.0, 1.0) * 0.85 + 0.15
			var inside := 1.0 - smoothstep(bhw, bhw + 3.0, best)
			var v := bt * speed * prof * inside
			img.set_pixel(ix, iy, Color(v.x / (2.0 * FLOW_RANGE) + 0.5, v.y / (2.0 * FLOW_RANGE) + 0.5, inside, 1.0))
	tex = ImageTexture.create_from_image(img)


## 從快取的流場 Image 還原（rect 由中心線重算，與 build() 同式）
func load_cached(cached: Image, body_name: String, pts: PackedVector2Array, half_w: PackedFloat32Array, wy: float) -> void:
	name = body_name
	water_y = wy
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var maxhw := 0.0
	for i in pts.size():
		lo = lo.min(pts[i])
		hi = hi.max(pts[i])
		maxhw = maxf(maxhw, half_w[i])
	var pad := maxhw + 6.0
	rect = Rect2(lo - Vector2(pad, pad), hi - lo + Vector2(pad, pad) * 2.0)
	img = cached
	tex = ImageTexture.create_from_image(img)


func valid() -> bool:
	return img != null


## (流速 x, 流速 z, 在水中)——與 wf_flow 同（雙線性、texel 中心 0.5）。
func flow3(p: Vector2) -> Vector3:
	if img == null:
		return Vector3.ZERO
	var uv := (p - rect.position) / rect.size
	if uv.x < 0.0 or uv.y < 0.0 or uv.x > 1.0 or uv.y > 1.0:
		return Vector3.ZERO
	var fx := uv.x * img.get_width() - 0.5
	var fy := uv.y * img.get_height() - 0.5
	var x0 := clampi(int(floor(fx)), 0, img.get_width() - 1)
	var y0 := clampi(int(floor(fy)), 0, img.get_height() - 1)
	var x1 := mini(x0 + 1, img.get_width() - 1)
	var y1 := mini(y0 + 1, img.get_height() - 1)
	var tx := clampf(fx - floor(fx), 0.0, 1.0)
	var ty := clampf(fy - floor(fy), 0.0, 1.0)
	var c := img.get_pixel(x0, y0).lerp(img.get_pixel(x1, y0), tx).lerp(
		img.get_pixel(x0, y1).lerp(img.get_pixel(x1, y1), tx), ty)
	# RGBA8 的 0.5 零點量化成 ±0.008 m/s：水域外（B < 0.02）強制歸零（與 wf_flow 同）
	var on := 1.0 if c.b >= 0.02 else 0.0
	return Vector3((c.r - 0.5) * 2.0 * FLOW_RANGE * on, (c.g - 0.5) * 2.0 * FLOW_RANGE * on, c.b)


## 長波（與 wf_water_long 同）
func long_wave(p: Vector2, fd: Vector2, t: float, wind: float) -> float:
	var amp := long_amp * (1.0 + 0.6 * clampf(wind / 1.2, 0.0, 1.0))
	var fs := Vector2(-fd.y, fd.x)
	var n := sin(p.x * 0.071 + p.y * 0.053) + 0.6 * sin(p.x * -0.043 + p.y * 0.089)
	var h1 := sin(p.dot(fd) * (TAU / 11.0) - t * 1.05 + 1.7 * n)
	var h2 := sin(p.dot((fd * 0.6 + fs * 0.8).normalized()) * (TAU / 7.0) - t * 1.38 + 2.3 * n)
	return amp * (0.6 * h1 + 0.4 * h2)


## 風漣漪（與 wf_water_ripple 同）：回傳 Vector3(高度, ∂h/∂x, ∂h/∂z)
func ripple(p: Vector2, wdir: Vector2, flow: Vector2, t: float, wind: float) -> Vector3:
	# 風斑（與 wf_water_ripple 同）
	var patch := 0.5 + 0.5 * sin(p.dot(Vector2(0.13, 0.07)) - t * 0.6 + 2.0 * sin(p.y * 0.09 + t * 0.2)) 		* sin(p.dot(Vector2(-0.05, 0.11)) + t * 0.37)
	var a0 := 0.0045 * ripple_gain * clampf(wind, 0.0, 2.0) * (0.25 + 1.1 * patch * patch)
	var acc := Vector3.ZERO
	if a0 <= 0.0:
		return acc
	var q := p - flow * t
	var lams := [0.9, 1.8, 3.1]
	var angs := [-0.62, 0.08, 0.71]
	for i in 3:
		var fi := float(i)
		var ang: float = angs[i]
		var d := Vector2(wdir.x * cos(ang) - wdir.y * sin(ang), wdir.x * sin(ang) + wdir.y * cos(ang))
		var k := TAU / float(lams[i])
		var c := sqrt(G / k)
		var ph := k * (q.dot(d) - c * t) + fi * 2.1 + 1.6 * sin(p.dot(Vector2(0.21, -0.17)) + fi) \
			+ 1.1 * sin(p.dot(Vector2(-0.09, 0.27)) - fi * 1.3)
		var a := a0 * (1.0 - 0.25 * fi)
		acc += Vector3(a * sin(ph), a * k * cos(ph) * d.x, a * k * cos(ph) * d.y)
	return acc

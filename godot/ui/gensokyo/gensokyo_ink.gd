extends RefCounted
class_name GensokyoInk
## 程式繪製的墨筆語彙（不依賴貼圖）：筆觸條、円相、日輪、刀鍔、楓葉、紙垂、繩結、鍵帽。
## 全部是 static，傳入要畫的 CanvasItem。形狀由 seed 決定且每幀穩定（不抖動）。

const TAU_F := TAU


static func _h(x: float) -> float:
	return fposmod(sin(x * 127.1 + 311.7) * 43758.5453, 1.0)


static func _n1(x: float, s: float) -> float:
	# 1D value noise，0..1
	var i := floorf(x)
	var f := x - i
	var u := f * f * (3.0 - 2.0 * f)
	return lerpf(_h(i + s * 17.0), _h(i + 1.0 + s * 17.0), u)


## 水平毛筆筆觸（起筆重、收筆飛白）。回傳多邊形點。
## rect：筆觸範圍；fill：0..1 只畫到哪；roughness：邊緣起伏 px。
static func stroke_points(rect: Rect2, s: float, roughness: float = 1.6, fill: float = 1.0,
		head_taper: float = 0.35, tail_taper: float = 0.85) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var n := maxi(int(rect.size.x / 6.0), 8)
	var w := rect.size.x * clampf(fill, 0.0, 1.0)
	if w < 1.0:
		return pts
	var cy := rect.position.y + rect.size.y * 0.5
	var hh := rect.size.y * 0.5
	var top := PackedVector2Array()
	var bot := PackedVector2Array()
	for k in n + 1:
		var t := float(k) / n
		var x := rect.position.x + w * t
		var gt := t * fill   # 在整條筆觸上的位置（收筆形狀跟著總長，不跟 fill）
		var th := 1.0
		th *= lerpf(1.0 - head_taper, 1.0, smoothstep(0.0, 0.06, gt))
		th *= lerpf(1.0, 1.0 - tail_taper, smoothstep(0.72, 1.0, gt))
		var wob := (_n1(x * 0.08, s) - 0.5) * roughness
		var wob2 := (_n1(x * 0.11, s + 3.0) - 0.5) * roughness
		top.append(Vector2(x, cy - hh * th + wob - hh * 0.10 * (1.0 - gt)))
		bot.append(Vector2(x, cy + hh * th + wob2 + hh * 0.05 * gt))
	for p in top:
		pts.append(p)
	for k in range(bot.size() - 1, -1, -1):
		pts.append(bot[k])
	return pts


static func stroke(ci: CanvasItem, rect: Rect2, color: Color, s: float, roughness := 1.6,
		fill := 1.0, head_taper := 0.35, tail_taper := 0.85) -> void:
	var pts := stroke_points(rect, s, roughness, fill, head_taper, tail_taper)
	if pts.size() >= 3:
		_safe_poly(ci, pts, color)


## 飛白：在已畫好的筆觸收筆段刻幾條細縫（用底色畫），讓筆觸像乾筆掃過。
static func dry_brush(ci: CanvasItem, rect: Rect2, gap_color: Color, s: float, fill := 1.0) -> void:
	if rect.size.y < 5.0 or fill < 0.3:
		return
	var w := rect.size.x * fill
	for k in 3:
		var y := rect.position.y + rect.size.y * (0.30 + 0.20 * k)
		var x0 := rect.position.x + w * (0.70 + 0.12 * _h(s + k))
		ci.draw_line(Vector2(x0, y), Vector2(rect.position.x + w + 1.0, y + 0.5), gap_color, 1.0)


static func _safe_poly(ci: CanvasItem, pts: PackedVector2Array, color: Color) -> void:
	# 自交或退化的多邊形 draw_colored_polygon 會報錯；三角化失敗就改畫折線。
	if Geometry2D.triangulate_polygon(pts).is_empty():
		ci.draw_polyline(pts, color, 1.5, true)
	else:
		ci.draw_colored_polygon(pts, color)


## 円相（墨圈）：不閉合、粗細變化、起筆處有墨溜。progress 0..1 = 畫到幾成。
static func enso(ci: CanvasItem, center: Vector2, radius: float, width: float, color: Color,
		s: float, progress: float = 1.0, gap: float = 0.13) -> void:
	var span := TAU_F * (1.0 - gap) * clampf(progress, 0.0, 1.0)
	if span <= 0.01:
		return
	var start := -PI * 0.62 + (_h(s) - 0.5) * 0.4
	var n := maxi(int(span * radius / 3.0), 12)
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for k in n + 1:
		var t := float(k) / n
		var a := start + span * t
		var gt := t * progress
		var w := width * lerpf(1.25, 0.25, smoothstep(0.55, 1.0, gt)) * lerpf(0.7, 1.0, smoothstep(0.0, 0.08, gt))
		w *= 0.85 + 0.3 * _n1(t * 9.0, s)
		var r := radius * (1.0 + (_n1(t * 4.0, s + 5.0) - 0.5) * 0.06)
		var d := Vector2(cos(a), sin(a))
		outer.append(center + d * (r + w * 0.5))
		inner.append(center + d * (r - w * 0.5))
	var pts := PackedVector2Array()
	pts.append_array(outer)
	for k in range(inner.size() - 1, -1, -1):
		pts.append(inner[k])
	_safe_poly(ci, pts, color)


## 日輪：實心圓 + 12 條短焰（日之呼吸的曲線，低彩度）。glow 0..1 呼吸光。
static func sun(ci: CanvasItem, center: Vector2, radius: float, core: Color, flame: Color,
		glow: float = 0.0, rays: int = 12) -> void:
	if glow > 0.001:
		for k in 4:
			var rr := radius * (1.5 + 0.35 * k)
			ci.draw_circle(center, rr, Color(flame.r, flame.g, flame.b, 0.06 * glow * (4 - k)))
	for k in rays:
		var a := TAU_F * k / rays
		var d := Vector2(cos(a), sin(a))
		var side := Vector2(-d.y, d.x)
		var p0 := center + d * radius * 1.05
		var tip := center + d * radius * 1.55 + side * radius * 0.18   # 火焰尖端微彎
		var pts := PackedVector2Array([p0 - side * radius * 0.16, tip, p0 + side * radius * 0.16])
		ci.draw_colored_polygon(pts, flame)
	ci.draw_circle(center, radius, core)


## 刀鍔：四葉木瓜形外輪 + 中孔（茎穴）。
static func tsuba(ci: CanvasItem, center: Vector2, radius: float, color: Color, hole: Color) -> void:
	var pts := PackedVector2Array()
	var n := 48
	for k in n:
		var a := TAU_F * k / n
		var r := radius * (0.88 + 0.12 * absf(cos(2.0 * a)))
		pts.append(center + Vector2(cos(a), sin(a)) * r)
	ci.draw_colored_polygon(pts, color)
	var slot := PackedVector2Array([
		center + Vector2(-radius * 0.12, -radius * 0.34), center + Vector2(radius * 0.12, -radius * 0.34),
		center + Vector2(radius * 0.08, radius * 0.30), center + Vector2(-radius * 0.08, radius * 0.30)])
	ci.draw_colored_polygon(slot, hole)


## 楓葉（七裂）。rot 弧度。
static func maple(ci: CanvasItem, center: Vector2, size: float, rot: float, color: Color) -> void:
	var pts := PackedVector2Array()
	var lobes := 7
	var n := 70
	for k in n:
		var t := float(k) / n
		var a := -PI * 0.5 + (t - 0.5) * TAU_F * 0.86      # 底部留一個缺口給葉柄
		var lobe := absf(sin(t * PI * lobes))
		var r := size * (0.42 + 0.58 * pow(lobe, 0.55))
		r *= 1.0 - 0.35 * pow(absf(t - 0.5) * 2.0, 3.0)     # 下方兩裂較短
		var p := Vector2(cos(a), sin(a)) * r
		pts.append(center + p.rotated(rot))
	pts.append(center)
	_safe_poly(ci, pts, color)
	var stem := Vector2(0, size * 0.55).rotated(rot)
	ci.draw_line(center, center + stem, color, maxf(size * 0.07, 1.0), true)


## 紙垂（御幣的白紙）：一條紙帶折成閃電形往下，左右交錯。從 top 往下 length、寬 width。
static func shide(ci: CanvasItem, top: Vector2, length: float, width: float, paper: Color, edge: Color) -> void:
	var steps := 4
	var h := length / steps
	var hw := width * 0.5
	# 左緣與右緣各一串點，每段向右／左平移 hw，段與段之間斜切相接
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for k in steps + 1:
		var y := top.y + h * k
		var off := hw if k % 2 == 1 else 0.0
		left.append(Vector2(top.x + off, y))
		right.append(Vector2(top.x + off + hw, y + h * 0.35 * float(k < steps)))
	for k in steps:
		var quad := PackedVector2Array([left[k], right[k], right[k + 1] - Vector2(0, h * 0.35 * float(k + 1 < steps)), left[k + 1]])
		ci.draw_colored_polygon(quad, paper)
		ci.draw_line(quad[1], quad[2], edge, 1.0, true)
		ci.draw_line(quad[3], quad[0], edge, 1.0, true)


## 細繩結：一條下垂的繩 + 小結 + 兩條穗。
static func cord(ci: CanvasItem, top: Vector2, length: float, color: Color, knot: Color, s: float) -> void:
	var pts := PackedVector2Array()
	var n := 14
	for k in n + 1:
		var t := float(k) / n
		pts.append(top + Vector2(sin(t * 2.4 + s) * 2.0 * t, length * 0.62 * t))
	ci.draw_polyline(pts, color, 1.6, true)
	var kp := pts[pts.size() - 1]
	ci.draw_circle(kp, 3.2, knot)
	ci.draw_circle(kp + Vector2(-3.0, 1.5), 2.2, knot)
	ci.draw_circle(kp + Vector2(3.0, 1.5), 2.2, knot)
	for side in [-1.0, 1.0]:
		ci.draw_line(kp + Vector2(side * 1.5, 3.0), kp + Vector2(side * 3.0, length * 0.38 + 3.0), color, 1.2, true)


## 鍵帽：手繪墨框方塊（不是圓角 APP 按鈕）。
static func keycap(ci: CanvasItem, rect: Rect2, ink: Color, paper: Color, s: float) -> void:
	var r := rect
	var j := func(v: Vector2, k: float) -> Vector2:
		return v + Vector2((_h(s + k) - 0.5) * 1.6, (_h(s + k + 7.0) - 0.5) * 1.6)
	var pts := PackedVector2Array([
		j.call(r.position, 1.0), j.call(r.position + Vector2(r.size.x, 0), 2.0),
		j.call(r.end, 3.0), j.call(r.position + Vector2(0, r.size.y), 4.0)])
	ci.draw_colored_polygon(pts, paper)
	# 上、左細，右、下粗 —— 筆壓不均
	ci.draw_line(pts[0], pts[1], ink, 1.2, true)
	ci.draw_line(pts[1], pts[2], ink, 2.2, true)
	ci.draw_line(pts[2], pts[3], ink, 2.4, true)
	ci.draw_line(pts[3], pts[0], ink, 1.1, true)


## 刀的剪影（刀鞘＋鍔＋柄），水平；給快捷列當基座。
static func katana(ci: CanvasItem, from: Vector2, length: float, thick: float, color: Color) -> void:
	var blade_len := length * 0.74
	var pts := PackedVector2Array()
	var n := 24
	# 鞘（微彎）
	for k in n + 1:
		var t := float(k) / n
		pts.append(from + Vector2(blade_len * t, -sin(t * PI * 0.9) * thick * 0.9 - thick * 0.5 * (1.0 - t * 0.3)))
	for k in range(n, -1, -1):
		var t := float(k) / n
		pts.append(from + Vector2(blade_len * t, -sin(t * PI * 0.9) * thick * 0.9 + thick * 0.5 * (1.0 - t * 0.3)))
	_safe_poly(ci, pts, color)
	var g := from + Vector2(blade_len + thick * 0.4, -thick * 0.1)
	ci.draw_rect(Rect2(g - Vector2(thick * 0.3, thick * 1.1), Vector2(thick * 0.6, thick * 2.2)), color)
	ci.draw_line(g + Vector2(thick * 0.4, 0), g + Vector2(length - blade_len - thick * 0.4, thick * 0.15), color, thick * 0.9, true)

# 程序化貼圖生成器 —— 自己烤 PBR 貼圖組（ADR-003 的延伸）
#
#   godot --headless --path godot --script tools/gen_textures.gd
#   godot --headless --editor --quit --path godot     ← 烤完要跑這行讓 Godot 匯入
#
# 為什麼要有這支：使用者說「目前的素材很單調」。查了才發現 manifest.json
# 登記了 25 組貼圖，但**只有 11 組真的下載過** —— 茅葺（roof_thatch）、
# 木格子、疊蓆、石板全部缺席，缺的那些一律退化成純色，難怪單調。
#
# 補不回來：Poly Haven 被這個環境的網路政策擋掉（CONNECT 403），
# 而 numpy 在這台機器上是壞的。所以改成**用程式生**。
#
# 做法：可平舖的 value-noise（格點先隨機好再雙線性取樣，週期整除 →
# 天生無縫）+ 每種材質自己的圖案函式。高度場做完再用中央差分轉法線。
# 存成 .jpg 是因為 gen_lib.pbr() 寫死了 `_diff.jpg` / `_nor_gl.jpg` / `_rough.jpg`。
extends SceneTree

const SIZE := 384
const DIR := "res://assets/textures/"
const TAU_ := 6.283185307179586

var _rng := RandomNumberGenerator.new()

func _init() -> void:
	var t0 := Time.get_ticks_msec()
	var made: Array[String] = []
	for fn in [
		["roof_thatch", 11], ["wood_lattice", 22], ["pebble", 33], ["foliage", 44],
		["namako", 55], ["tatami", 66], ["stone_flag", 77], ["shoji", 88],
	]:
		var name: String = fn[0]
		_rng.seed = int(fn[1])
		print("烤 %s …" % name)
		_bake(name)
		made.append(name)
	_update_manifest(made)
	print("\n══ 貼圖生成完成：%d 組，%.1fs ══" % [made.size(), float(Time.get_ticks_msec() - t0) / 1000.0])
	print("記得跑：godot --headless --editor --quit --path godot（讓 Godot 匯入新檔）")
	quit(0)

## 一組 = 反照率 + 粗糙度 + 法線
func _bake(name: String) -> void:
	var alb := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	var rgh := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	var hgt := PackedFloat32Array()
	hgt.resize(SIZE * SIZE)
	var n2 := _fbm_field(4, 4)          # 兩張通用雜訊，各材質自己怎麼用
	var n3 := _fbm_field(16, 3)
	for y in SIZE:
		for x in SIZE:
			var u := float(x) / float(SIZE)
			var v := float(y) / float(SIZE)
			var i := y * SIZE + x
			var out: Array = _pattern(name, u, v, n2[i], n3[i])
			var c: Color = out[0]
			hgt[i] = float(out[1])
			var r: float = float(out[2])
			alb.set_pixel(x, y, c)
			rgh.set_pixel(x, y, Color(r, r, r))
	alb.save_jpg(DIR + name + "_diff.jpg", 0.92)
	rgh.save_jpg(DIR + name + "_rough.jpg", 0.9)
	_normal_from_height(hgt, name)

## 高度場 → 法線圖（OpenGL 慣例：Y 朝上，對應 gen_lib 的 _nor_gl）
func _normal_from_height(h: PackedFloat32Array, name: String, strength := 2.6) -> void:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	for y in SIZE:
		for x in SIZE:
			# 環繞取樣 —— 不環繞的話貼圖接縫會有一條亮線
			var l := h[y * SIZE + (x - 1 + SIZE) % SIZE]
			var r := h[y * SIZE + (x + 1) % SIZE]
			var d := h[((y - 1 + SIZE) % SIZE) * SIZE + x]
			var up := h[((y + 1) % SIZE) * SIZE + x]
			var n := Vector3((l - r) * strength, (d - up) * strength, 1.0).normalized()
			img.set_pixel(x, y, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5))
	img.save_jpg(DIR + name + "_nor_gl.jpg", 0.94)

# ─────────────────────────── 可平舖的雜訊 ───────────────────────────
# 格點先隨機好，再用 smoothstep 雙線性取樣。週期整除貼圖寬度 → 天生無縫。
# （FastNoiseLite 的 2D 不可平舖，接縫會很明顯。）

func _lattice(period: int) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(period * period)
	for i in period * period:
		a[i] = _rng.randf()
	return a

func _sample(lat: PackedFloat32Array, period: int, u: float, v: float) -> float:
	var fx := u * float(period)
	var fy := v * float(period)
	var x0 := int(floor(fx))
	var y0 := int(floor(fy))
	var tx: float = smoothstep(0.0, 1.0, fx - float(x0))
	var ty: float = smoothstep(0.0, 1.0, fy - float(y0))
	var xa := x0 % period
	var xb := (x0 + 1) % period
	var ya := (y0 % period) * period
	var yb := ((y0 + 1) % period) * period
	return lerpf(lerpf(lat[ya + xa], lat[ya + xb], tx),
		lerpf(lat[yb + xa], lat[yb + xb], tx), ty)

## 整張 fbm 先算好存成陣列 —— 每個像素現算會慢十倍
func _fbm_field(base_period: int, octaves: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(SIZE * SIZE)
	var amp := 1.0
	var total := 0.0
	for o in octaves:
		var p: int = base_period << o
		if p > SIZE:
			break
		var lat := _lattice(p)
		for y in SIZE:
			var v := float(y) / float(SIZE)
			for x in SIZE:
				out[y * SIZE + x] += _sample(lat, p, float(x) / float(SIZE), v) * amp
		total += amp
		amp *= 0.5
	for i in out.size():
		out[i] /= total
	return out

# ─────────────────────────── 各材質的圖案 ───────────────────────────
# 回傳 [反照率 Color, 高度 0~1, 粗糙度 0~1]

func _pattern(name: String, u: float, v: float, n1: float, n2: float) -> Array:
	match name:
		"roof_thatch": return _p_thatch(u, v, n1, n2)
		"wood_lattice": return _p_lattice(u, v, n1, n2)
		"pebble": return _p_pebble(u, v, n1, n2)
		"foliage": return _p_foliage(u, v, n1, n2)
		"namako": return _p_namako(u, v, n1, n2)
		"tatami": return _p_tatami(u, v, n1, n2)
		"stone_flag": return _p_flag(u, v, n1, n2)
		"shoji": return _p_shoji(u, v, n1, n2)
	return [Color(1, 0, 1), 0.5, 0.8]

## 茅葺：一束一束的稻稈往下流，束與束之間有陰影溝
func _p_thatch(u: float, v: float, n1: float, n2: float) -> Array:
	var strands := 150.0
	var wob := (n1 - 0.5) * 0.05                    # 稈不是直的
	var s: float = fposmod((u + wob) * strands, 1.0)
	var groove: float = absf(s - 0.5) * 2.0          # 0=稈心 1=溝
	# 束（每 12 根一束），束緣更深
	var bundle: float = fposmod((u + wob) * strands / 12.0, 1.0)
	var bgroove: float = smoothstep(0.86, 1.0, absf(bundle - 0.5) * 2.0)
	var h: float = (1.0 - groove * groove) * 0.7 - bgroove * 0.45 + n2 * 0.18
	# 稈色：曬過的麥稈黃 → 老化的灰褐，沿 v（屋頂由脊到簷）漸變
	var age: float = clampf(n2 * 1.3 + v * 0.25, 0.0, 1.0)
	var c := Color(0.62, 0.50, 0.30).lerp(Color(0.34, 0.31, 0.26), age)
	c = c.darkened(clampf(groove * 0.45 + bgroove * 0.3, 0.0, 0.7))
	# 一點點雜色（苔、濕痕）
	if n1 > 0.78:
		c = c.lerp(Color(0.30, 0.34, 0.24), (n1 - 0.78) * 2.2)
	return [c, h, 0.88 + n2 * 0.1]

## 木格子：直的細木條 + 中間的空隙（空隙做成暗色，不做透明）
func _p_lattice(u: float, v: float, n1: float, n2: float) -> Array:
	var bars := 14.0
	var t: float = fposmod(u * bars, 1.0)
	var solid: float = 1.0 - smoothstep(0.34, 0.46, absf(t - 0.5) * 2.0)
	# 橫貫（每 1/3 高有一根橫木）
	var hb: float = fposmod(v * 3.0, 1.0)
	var horiz: float = 1.0 - smoothstep(0.80, 0.92, absf(hb - 0.5) * 2.0)
	var mask: float = maxf(solid, horiz)
	var grain: float = n2 * 0.5 + fposmod(v * 90.0, 1.0) * 0.1     # 木紋
	var wood := Color(0.40, 0.31, 0.22).lerp(Color(0.28, 0.21, 0.15), grain)
	var gap := Color(0.05, 0.05, 0.06)
	var c: Color = gap.lerp(wood, mask)
	return [c, mask * 0.75 + n1 * 0.08, 0.62 + (1.0 - mask) * 0.3]

## 玉石（鵝卵石）：圓潤、扁、擠在一起 —— 使用者要的「山水畫的鵝卵石」
## 用 Worley/cellular：格點各放一顆石心，取最近距離當高度。
func _p_pebble(u: float, v: float, n1: float, n2: float) -> Array:
	var cells := 9.0
	var best := 9.0
	var best2 := 9.0
	var bid := 0.0
	var gx: float = floor(u * cells)
	var gy: float = floor(v * cells)
	for dy in [-1.0, 0.0, 1.0]:
		for dx in [-1.0, 0.0, 1.0]:
			var cx: float = gx + dx
			var cy: float = gy + dy
			# 環繞的雜湊 → 貼圖無縫
			var wx: float = fposmod(cx, cells)
			var wy: float = fposmod(cy, cells)
			var hsh: float = fposmod(sin(wx * 127.1 + wy * 311.7) * 43758.5453, 1.0)
			var hsh2: float = fposmod(sin(wx * 269.5 + wy * 183.3) * 43758.5453, 1.0)
			var px: float = (cx + 0.2 + hsh * 0.6) / cells
			var py: float = (cy + 0.2 + hsh2 * 0.6) / cells
			# 石頭是扁的（橫向拉長）
			var d: float = Vector2((u - px) * 0.82, (v - py) * 1.18).length() * cells
			if d < best:
				best2 = best
				best = d
				bid = hsh
			elif d < best2:
				best2 = d
	var edge: float = clampf(best2 - best, 0.0, 1.0)             # 石縫
	var dome: float = clampf(1.0 - best * 1.35, 0.0, 1.0)
	var h: float = sqrt(dome) * 0.9 * smoothstep(0.0, 0.16, edge) + n2 * 0.06
	# 河石的顏色：灰藍 / 米白 / 淡赭，一顆一個色
	var pal := [Color(0.52, 0.54, 0.55), Color(0.66, 0.63, 0.57),
		Color(0.44, 0.46, 0.50), Color(0.60, 0.55, 0.48), Color(0.38, 0.40, 0.42)]
	var c: Color = pal[int(bid * float(pal.size())) % pal.size()]
	c = c.lerp(c.darkened(0.5), 1.0 - smoothstep(0.0, 0.2, edge))  # 石縫壓暗
	c = c.lerp(c.lightened(0.18), dome * 0.5)                      # 石頂受光
	c = c.lerp(Color(0.42, 0.44, 0.38), clampf((n1 - 0.72) * 2.0, 0.0, 0.35))  # 苔
	return [c, h, 0.42 + (1.0 - dome) * 0.35]

## 樹葉團：給生垣與樹籬用。重點是**成叢**與**深淺差**，不是單片葉子。
func _p_foliage(u: float, v: float, n1: float, n2: float) -> Array:
	var cells := 13.0
	var best := 9.0
	var bid := 0.0
	var gx: float = floor(u * cells)
	var gy: float = floor(v * cells)
	for dy in [-1.0, 0.0, 1.0]:
		for dx in [-1.0, 0.0, 1.0]:
			var wx: float = fposmod(gx + dx, cells)
			var wy: float = fposmod(gy + dy, cells)
			var hsh: float = fposmod(sin(wx * 127.1 + wy * 311.7) * 43758.5453, 1.0)
			var hsh2: float = fposmod(sin(wx * 269.5 + wy * 183.3) * 43758.5453, 1.0)
			var px: float = (gx + dx + hsh) / cells
			var py: float = (gy + dy + hsh2) / cells
			var d: float = Vector2(u - px, v - py).length() * cells
			if d < best:
				best = d
				bid = hsh2
	var leaf: float = clampf(1.0 - best * 1.1, 0.0, 1.0)
	var h: float = leaf * 0.8 + n2 * 0.2
	# 綠色要有幅度：新葉黃綠 → 老葉深綠 → 陰影處近墨綠
	var tone: float = clampf(bid * 0.7 + n1 * 0.5, 0.0, 1.0)
	var c := Color(0.42, 0.52, 0.20).lerp(Color(0.13, 0.24, 0.12), tone)
	c = c.darkened((1.0 - leaf) * 0.55)                 # 叢與叢之間是暗的
	c = c.lerp(Color(0.55, 0.60, 0.26), clampf((n2 - 0.80) * 3.0, 0.0, 0.5))  # 陽光打到的葉尖
	return [c, h, 0.72 + n1 * 0.2]

## なまこ壁：土藏的招牌 —— 方形平瓦斜排 + 凸起的白色漆喰目地。
## 這是最能讓町方一眼變豐富的一張。
func _p_namako(u: float, v: float, n1: float, n2: float) -> Array:
	var n := 7.0
	# 轉 45 度 → 菱形排列
	var a: float = (u + v) * n
	var b: float = (u - v) * n
	var fa: float = absf(fposmod(a, 1.0) - 0.5) * 2.0
	var fb: float = absf(fposmod(b, 1.0) - 0.5) * 2.0
	var joint: float = maxf(smoothstep(0.62, 0.88, fa), smoothstep(0.62, 0.88, fb))
	var tile: float = 1.0 - joint
	# 目地是**凸**的（半圓，像海參，名字就是這樣來的）
	var h: float = tile * 0.25 + joint * 0.95 + n2 * 0.05
	var kawara := Color(0.24, 0.26, 0.28).lerp(Color(0.34, 0.35, 0.36), n1 * 0.7)
	var shikkui := Color(0.86, 0.85, 0.80).lerp(Color(0.72, 0.71, 0.66), n2 * 0.6)
	var c: Color = kawara.lerp(shikkui, joint)
	return [c, h, 0.34 + joint * 0.4]

## 疊蓆：藺草橫織 + 每半疊一條縫（室內用）
func _p_tatami(u: float, v: float, n1: float, n2: float) -> Array:
	var weave: float = fposmod(v * 190.0, 1.0)
	var strand: float = 1.0 - absf(weave - 0.5) * 2.0
	var mat_seam: float = smoothstep(0.94, 1.0, absf(fposmod(u * 2.0, 1.0) - 0.5) * 2.0)
	var h: float = strand * 0.5 + n2 * 0.15 - mat_seam * 0.6
	var green := Color(0.66, 0.63, 0.38).lerp(Color(0.45, 0.48, 0.28), n1 * 0.8)
	var c: Color = green.darkened((1.0 - strand) * 0.22 + mat_seam * 0.45)
	return [c, h, 0.78 + n2 * 0.15]

## 石板：不規則的板石鋪面（給店前與參道）
func _p_flag(u: float, v: float, n1: float, n2: float) -> Array:
	var cells := 6.0
	var best := 9.0
	var best2 := 9.0
	var bid := 0.0
	var gx: float = floor(u * cells)
	var gy: float = floor(v * cells)
	for dy in [-1.0, 0.0, 1.0]:
		for dx in [-1.0, 0.0, 1.0]:
			var wx: float = fposmod(gx + dx, cells)
			var wy: float = fposmod(gy + dy, cells)
			var hsh: float = fposmod(sin(wx * 127.1 + wy * 311.7) * 43758.5453, 1.0)
			var hsh2: float = fposmod(sin(wx * 269.5 + wy * 183.3) * 43758.5453, 1.0)
			var px: float = (gx + dx + 0.15 + hsh * 0.7) / cells
			var py: float = (gy + dy + 0.15 + hsh2 * 0.7) / cells
			var d: float = maxf(absf(u - px) * 1.05, absf(v - py)) * cells   # 切比雪夫 → 方一點
			if d < best:
				best2 = best
				best = d
				bid = hsh
			elif d < best2:
				best2 = d
	var seam: float = smoothstep(0.0, 0.13, best2 - best)
	var h: float = seam * 0.8 + n2 * 0.12
	var base := Color(0.46, 0.45, 0.43).lerp(Color(0.60, 0.58, 0.54), bid)
	var c: Color = base.lerp(Color(0.26, 0.25, 0.23), 1.0 - seam)
	c = c.lerp(c.darkened(0.25), n1 * 0.35)
	return [c, h, 0.55 + (1.0 - seam) * 0.3]

## 障子：和紙 + 木格（室內與店面用）
func _p_shoji(u: float, v: float, n1: float, n2: float) -> Array:
	var gx: float = smoothstep(0.90, 0.98, absf(fposmod(u * 6.0, 1.0) - 0.5) * 2.0)
	var gy: float = smoothstep(0.90, 0.98, absf(fposmod(v * 8.0, 1.0) - 0.5) * 2.0)
	var grid: float = maxf(gx, gy)
	# 和紙的纖維
	var fiber: float = n2 * 0.14 + fposmod(v * 220.0, 1.0) * 0.04
	var paper := Color(0.93, 0.91, 0.84).darkened(fiber)
	var frame := Color(0.34, 0.26, 0.18)
	var c: Color = paper.lerp(frame, grid)
	return [c, grid * 0.7 + fiber * 0.3, 0.86 - grid * 0.25]

## manifest 要記錄這幾組是**生成的**不是下載的，別讓下一個人去 Poly Haven 找
func _update_manifest(made: Array[String]) -> void:
	var path := DIR + "manifest.json"
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	if data == null:
		return
	var gen := {}
	for n in made:
		gen[n] = {
			"source": "procedural (tools/gen_textures.gd)",
			"files": ["%s_diff.jpg" % n, "%s_nor_gl.jpg" % n, "%s_rough.jpg" % n],
		}
	data["generated"] = gen
	data["generated_note"] = "這幾組是 tools/gen_textures.gd 烤出來的 —— Poly Haven 被網路政策擋掉，改成程式生成。要改樣式就改那支，不要手動編輯 jpg。"
	var w := FileAccess.open(path, FileAccess.WRITE)
	w.store_string(JSON.stringify(data, "  "))
	w.close()

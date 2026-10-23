extends RefCounted
## 獸道 S01 R5 林床規劃（R4 Demo 精修＋擴區；使用者 2026-10-16：先把「森林的立體感」做對）。
## 參考：docs/reference/獸道概念圖/植被.PNG（蕨冠＋闊葉草本＋幼樹＋倒木交錯）、叢林感.PNG（植被豐富、路仍可辨認）。
## 與 R4（s01_dress.gd 的 cover 迴圈）不同：
##   · 依「棲地」分：開闊（草地）／林緣／林下／壁腳；林下以蕨冠、闊葉草本、笹、幼樹為主，草退到陽光處；
##   · 林下的優勢種由兩個低頻「群落」場決定（蕨群／草本群／笹群互相消長），交界處互相穿插；
##   · 「林窗／空隙」場：林下有成片的開口（只剩落葉、苔、林下低草），不是到處一樣密；
##   · 樹腳環（0.4–3 m）與岩／木環吸引蕨、苔、落葉；路緣淨空沿路起伏、兩側不對稱；
##   · 每類的資產變體由低頻噪聲選（同一片是同一種＝克隆群落），加上非等比縮放與傾斜，不是同一個網格轉來轉去；
##   · 只輸出 cover（MultiMesh 用）＋ auto_wood（露根、倒木、殘株、枯枝堆，走 s01_dress 的岩／木貼地流程）。
const S01Wall := preload("res://tools/beast_path/s01_wall.gd")

## 類別 → 材質／陰影等用的「家族」（s01_dress.veg_mat 的分類）
const FAMILY := {"grass_tall": "tall", "grass_short": "short", "shadegrass": "short", "sedge": "tall", "fern_big": "fern", "fern_small": "fern",
	"herb": "shrub", "forb": "forb", "sasa": "sasa", "shrub": "shrub", "sapling": "shrub", "litter": "litter", "moss": "moss", "twigs": "twigs"}


class Grid:
	var cell := 4.0
	var b := {}

	func add(p: Vector2, item) -> void:
		var k := Vector2i(floori(p.x / cell), floori(p.y / cell))
		if not b.has(k):
			b[k] = []
		(b[k] as Array).append(item)

	func near(p: Vector2, r: float) -> Array:
		var out: Array = []
		var n := int(ceil(r / cell))
		var c := Vector2i(floori(p.x / cell), floori(p.y / cell))
		for dx in range(-n, n + 1):
			for dz in range(-n, n + 1):
				var k := Vector2i(c.x + dx, c.y + dz)
				if b.has(k):
					out.append_array(b[k])
		return out


static func _noise(seed_: int, freq: float) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed_
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_octaves = 3
	return n


# ================================================================= 情境（0.5 m 格快取）
static func ctx_at(S: Dictionary, p: Vector2) -> Dictionary:
	var key := Vector2i(floori(p.x * 2.0), floori(p.y * 2.0))
	var cache: Dictionary = S["cache"]
	if cache.has(key):
		return cache[key]
	var lib = S["lib"]
	var F = S["F"]
	var cfg: Dictionary = S["cfg"]
	var clr: Dictionary = S["clr"]
	var c := {"ok": false}
	var zw: float = S["dress"].zone_w(cfg, p, S["n_edge"])
	if zw <= 0.01 or lib.scene_id_of_z(p.y) != String(S["dress"].scene_id):
		cache[key] = c
		return c
	# 鋪石（PV）：S01 照舊整片不長；S02／S03 的舊石鋪（岔路辻）邊緣讓低地被從石縫長進來（clear.paving_low；物種另限 low 類）
	var pv: float = lib.sample_arr(lib.PV, p.x, p.y)
	var pv_max := 0.05 if String(S["dress"].scene_id) == "S01" else float(clr.get("paving_low", 0.05))
	if lib.sample_arr(lib.DB, p.x, p.y) < float(clr["branch_db"]) or lib.sample_arr(lib.DS, p.x, p.y) < float(clr["stream_ds"]) or pv > pv_max:
		cache[key] = c
		return c
	for f: Dictionary in S["foot"]:
		var q: Vector2 = f["p"]
		if absf(q.y - p.y) < 16.0 and p.distance_to(q) < float(f["r"]) + float(clr["foot_pad"]):
			cache[key] = c
			return c
	var ch: PackedFloat32Array = F.ch(p.x, p.y)
	var sl: float = lib.slope_deg_at(p.x, p.y)
	var soil := ch[8]
	var rock := maxf(ch[3], smoothstep(48.7, 61.0, sl) * (1.0 - soil))
	var lit := ch[9] if ch.size() >= 13 else 0.0
	var mg := ch[10] if ch.size() >= 13 else 0.0
	var can: float = F.canopy(p.x, p.y)
	# 林分密度（樹幹的高斯和，半徑 7 m）：R3 的 canopy 只在樹冠正下方（S01 八成面積 < 0.1），林下／林緣要看「附近有多少樹」
	var dens := dens_at(S, p)
	var wood := smoothstep(0.35, 1.25, dens)
	var shade := maxf(smoothstep(0.12, 0.8, can), wood)
	# 樹腳：最近樹幹距離（扣樹幹半徑）
	var td := 1e9
	for t: Dictionary in (S["g_trunk"] as Grid).near(p, 4.0):
		td = minf(td, p.distance_to(t["p"]) - float(t["r"]))
	var ud := 1e9
	for u: Vector2 in (S["g_under"] as Grid).near(p, 4.0):
		ud = minf(ud, p.distance_to(u))
	# 岩／木：環與內部
	var ring_h := 0.0
	var in_h := 0.0
	for h: Dictionary in (S["g_hard"] as Grid).near(p, 8.0):
		var d: float = p.distance_to(h["p"])
		var rr := float(h["rr"])
		if d < rr:
			in_h = maxf(in_h, 1.0 - d / rr)
		ring_h = maxf(ring_h, exp(-pow((d - rr) / 1.4, 2.0)))
	var wr_in := false
	for w: Dictionary in S["wrocks"]:
		if absf((w["p"] as Vector2).y - p.y) < 8.0 and p.distance_to(w["p"]) < float(w["r"]) * 0.8 + float(clr["wall_rock_pad"]):
			wr_in = true
			break
	c = {"ok": true, "zw": zw, "de": S01Wall.path_edge_d(lib, p), "sl": sl, "dirt": ch[0], "rock": rock, "rough": ch[4], "lit": lit, "mg": mg,
		"dry": ch[11] if ch.size() >= 13 else 0.0, "lush": ch[12] if ch.size() >= 13 else 0.0, "soil": soil, "moss6": ch[6],
		"lawn": clampf(1.0 - (ch[0] + ch[1] + ch[2] + rock + ch[4] + lit + mg), 0.0, 1.0),
		"can": maxf(can, wood), "dens": dens, "shade": shade, "edge": smoothstep(0.10, 0.40, dens) * (1.0 - smoothstep(0.75, 1.3, dens)),
		"wallfoot": smoothstep(8.0, 17.0, sl) * (1.0 - smoothstep(40.0, 50.0, sl)), "face": smoothstep(38.0, 46.0, sl) * (1.0 - soil),
		"td": td, "ring_t": smoothstep(0.3, 0.9, td) * (1.0 - smoothstep(2.0, 3.6, td)), "ud": ud,
		"ring_h": ring_h, "in_h": in_h, "wr_in": wr_in,
		"depth": clampf((8.0 - p.y) / 60.0, 0.0, 1.0), "pv": pv}
	c["open"] = (1.0 - float(c["shade"])) * (1.0 - float(c["wallfoot"])) * (1.0 - float(c["face"]))
	cache[key] = c
	return c


static func dens_at(S: Dictionary, p: Vector2) -> float:
	var D: PackedFloat32Array = S["dens"]
	var o: Vector2 = S["dens_o"]
	var nx: int = S["dens_nx"]
	var nz: int = S["dens_nz"]
	var fx := clampf(p.x - o.x, 0.0, nx - 1.001)
	var fz := clampf(p.y - o.y, 0.0, nz - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var a := lerpf(D[iz * nx + ix], D[iz * nx + ix + 1], tx)
	var b := lerpf(D[(iz + 1) * nx + ix], D[(iz + 1) * nx + ix + 1], tx)
	return lerpf(a, b, tz)


static func _build_dens(S: Dictionary, bb: Rect2, trunks: Array, unders: Array) -> void:
	var o := bb.position - Vector2(4, 4)
	var nx := int(ceil(bb.size.x)) + 9
	var nz := int(ceil(bb.size.y)) + 9
	var D := PackedFloat32Array()
	D.resize(nx * nz)
	var R := 7.0
	for t: Dictionary in trunks:
		_splat(D, o, nx, nz, t["p"], R * clampf(0.75 + float(t["r"]), 0.8, 1.35), 1.0)
	for u: Vector2 in unders:
		_splat(D, o, nx, nz, u, 4.0, 0.45)
	S["dens"] = D
	S["dens_o"] = o
	S["dens_nx"] = nx
	S["dens_nz"] = nz


static func _splat(D: PackedFloat32Array, o: Vector2, nx: int, nz: int, c: Vector2, R: float, w: float) -> void:
	var x0 := maxi(0, int(c.x - o.x - 2.5 * R))
	var x1 := mini(nx - 1, int(c.x - o.x + 2.5 * R))
	var z0 := maxi(0, int(c.y - o.y - 2.5 * R))
	var z1 := mini(nz - 1, int(c.y - o.y + 2.5 * R))
	for iz in range(z0, z1 + 1):
		for ix in range(x0, x1 + 1):
			var d2 := (Vector2(o.x + ix, o.y + iz) - c).length_squared()
			D[iz * nx + ix] += w * exp(-d2 / (R * R))


# ================================================================= 每一類的接受率
static func _p(S: Dictionary, sp: String, p: Vector2, c: Dictionary) -> float:
	if sp.begins_with("verge_"):
		return _p_verge(S, sp, p, c)
	var N: Dictionary = S["noise"]
	var wx := p.x + 7.0 * (N["warp"] as FastNoiseLite).get_noise_2d(p.x, p.y)
	var wz := p.y + 7.0 * (N["warp"] as FastNoiseLite).get_noise_2d(p.x + 71.0, p.y - 33.0)
	var nn: float = (N[sp] as FastNoiseLite).get_noise_2d(wx, wz)
	var cA: float = (N["commA"] as FastNoiseLite).get_noise_2d(wx, wz)
	var cB: float = (N["commB"] as FastNoiseLite).get_noise_2d(wx, wz)
	var gap := smoothstep(0.16, 0.40, (N["gap"] as FastNoiseLite).get_noise_2d(wx, wz)) * float(c["shade"])     # 林窗（只在林下有意義）
	var fern_dom := smoothstep(-0.15, 0.25, cA)
	var herb_dom := smoothstep(-0.15, 0.25, -cA) * smoothstep(-0.25, 0.15, cB)
	var sasa_dom := smoothstep(0.0, 0.32, -cB) * smoothstep(-0.2, 0.25, -cA)
	var shade: float = c["shade"]
	var edge: float = c["edge"]
	var openm: float = c["open"]
	var dirt: float = c["dirt"]
	var rough: float = c["rough"]
	var lawn: float = c["lawn"]
	var wallfoot: float = c["wallfoot"]
	var face: float = c["face"]
	var ring_h: float = c["ring_h"]
	var ring_t: float = c["ring_t"]
	var lush: float = c["lush"]
	var depth: float = c["depth"]
	var sl: float = c["sl"]
	var soil: float = c["soil"]
	var near_road := 1.0 - smoothstep(0.5, 4.5, float(c["de"]))
	var low := sp == "litter" or sp == "moss" or sp == "twigs" or sp == "shadegrass"
	# 岩／木的內部：低地被只在外緣、高的不進去
	if float(c["in_h"]) > (0.08 if low else 0.0):
		return 0.0
	if bool(c["wr_in"]):
		return 0.0
	# 樹幹與既有林下植物
	if float(c["td"]) < (0.12 if low else 0.35):
		return 0.0
	if not low and float(c["ud"]) < 0.55:
		return 0.0
	var rough_open := openm * rough
	var pr := 0.0
	match sp:
		"grass_tall":
			# 芒／野草的大叢：陽光處（開闊、林緣、壁腳）成片，片與片之間留空
			if sl > 42.0 and soil < 0.3 and ring_h < 0.45:
				return 0.0
			var h := clampf(openm * (0.55 + 0.5 * rough + 0.25 * lawn) + 0.5 * edge * (1.0 - shade) + 0.35 * wallfoot * (1.0 - shade), 0.0, 1.0)
			h *= (1.0 - 1.5 * dirt) * (1.0 - 0.8 * face) * (1.0 - 0.7 * near_road)
			pr = maxf(_col(nn + 0.2 * (cA * 0.6 + cB * 0.4), h, 0.1) * (0.6 + 0.4 * depth + 0.3 * wallfoot), 0.03 * h)
		"grass_short":
			if sl > 44.0 and soil < 0.3:
				return 0.0
			var h2 := clampf(openm * (0.45 + 0.5 * rough + 0.35 * lawn + 0.35 * near_road), 0.0, 1.0) * (1.0 - 1.2 * dirt) * (1.0 - 0.6 * face)
			pr = _col(nn, h2, 0.08)
		"shadegrass":
			if sl > 40.0:
				return 0.0
			var h3 := clampf(shade * (0.5 + 0.5 * gap) + 0.4 * edge, 0.0, 1.0) * (1.0 - dirt)
			pr = _col(nn, h3, -0.05)
		"sedge":
			if sl > 40.0:
				return 0.0
			var h4 := clampf(0.7 * lush + 0.5 * wallfoot + 0.5 * ring_h + 0.3 * edge, 0.0, 1.0) * (1.0 - dirt) * (1.0 - 0.6 * near_road)
			pr = _col(nn, h4, 0.25)
		"fern_big":
			# 林下：劍羊齒冠／大羊齒成群（蕨群落場決定在哪裡佔優勢）；開闊處只有岩旁、壁腳、粗草地的蕨（蕨菜型）
			if sl > (58.0 if (soil > 0.3 or ring_h > 0.45) else 44.0):
				return 0.0
			var h5 := clampf(0.85 * shade + 0.5 * wallfoot + 0.6 * ring_h + 0.4 * ring_t * shade + 0.3 * lush + 0.35 * rough_open, 0.0, 1.0) * (1.0 - 0.85 * gap) * (1.0 - dirt)
			pr = _col(nn + 0.35 * (fern_dom - 0.5), h5, 0.05)
		"fern_small":
			if sl > 50.0:
				return 0.0
			var h6 := clampf(0.5 * shade + 0.5 * ring_h + 0.4 * ring_t + 0.3 * edge + 0.3 * wallfoot + 0.4 * gap, 0.0, 1.0) * (1.0 - dirt)
			pr = _col(nn, h6, 0.0)
		"herb":
			if sl > 38.0:
				return 0.0
			var h7 := clampf(0.6 * shade + 0.6 * lush + 0.4 * wallfoot + 0.3 * ring_h, 0.0, 1.0) * (1.0 - 0.75 * gap) * (1.0 - dirt) * (1.0 - 0.5 * openm)
			pr = _col(nn + 0.35 * (herb_dom - 0.5), h7, 0.15)
		"forb":
			if sl > 40.0:
				return 0.0
			var h8 := clampf(0.5 * rough + 0.4 * openm + 0.4 * ring_h + 0.4 * edge, 0.0, 1.0) * (1.0 - 1.2 * dirt) * (1.0 - 0.7 * shade) * (1.0 - 0.6 * near_road)
			pr = _col(nn, h8, 0.25)
		"sasa":
			if sl > 40.0:
				return 0.0
			var h9 := clampf(0.75 * shade + 0.6 * wallfoot + 0.3 * edge + 0.3 * ring_h, 0.0, 1.0) * (1.0 - 0.6 * face) * (1.0 - dirt) * (1.0 - 0.8 * gap)
			pr = _col(nn + 0.4 * (sasa_dom - 0.5), h9, 0.15)
		"shrub":
			if sl > 36.0:
				return 0.0
			var h10 := clampf(0.9 * edge + 0.4 * shade + 0.8 * wallfoot * (1.0 - face) + 0.5 * ring_h, 0.0, 1.0) * (1.0 - dirt) * (1.0 - 0.7 * gap)
			pr = _col(nn, h10, 0.05)
		"sapling":
			# 林緣與林窗邊（光從開口進來的地方）、壁腳
			if sl > 32.0 or float(c["td"]) < 1.3:
				return 0.0
			# 林緣結構：幼樹＋灌木成叢（壁腳、樹群外緣、林窗邊）——開闊草地與林之間的那一層
			var h11 := clampf(0.9 * edge + 0.6 * gap + 0.7 * wallfoot * (1.0 - face) + 0.4 * ring_h, 0.0, 1.0) * (1.0 - dirt) * (1.0 - 0.7 * openm * (1.0 - wallfoot) * (1.0 - edge))
			pr = _col(nn, h11, 0.0)
		"litter":
			if sl > 40.0:
				return 0.0
			var h12 := clampf(0.9 * shade + 0.9 * float(c["lit"]) + 0.4 * ring_h + 0.4 * ring_t + 0.4 * gap - 0.8 * dirt, 0.0, 1.0)
			pr = _col(nn, h12, -0.25)
		"moss":
			if sl > 46.0 or (shade < 0.25 and ring_h < 0.35):
				return 0.0
			var h13 := clampf(1.0 * float(c["mg"]) + 0.7 * float(c["moss6"]) + 0.6 * ring_h + 0.4 * ring_t * shade + 0.4 * shade * wallfoot + 0.25 * lush, 0.0, 1.0) * (1.0 - dirt)
			pr = _col(nn, h13, 0.0)
		"twigs":
			if sl > 32.0:
				return 0.0
			var h14 := clampf(0.8 * shade + 0.3 * ring_h + 0.3 * gap, 0.0, 1.0) * (1.0 - dirt)
			pr = _col(nn, h14, 0.1) * 0.5
	return clampf(pr * float(c["zw"]), 0.0, 1.0)


## 群落：噪聲＋棲地適合度 → 幾乎二值的「片」（片內接受率接近 1＝叢與叢相接；片外 0＝自然的空隙），而不是到處 0.3 的稀疏撒點
static func _col(nn: float, h: float, bias: float) -> float:
	return smoothstep(bias, bias + 0.2, nn + 0.6 * (h - 0.5)) * smoothstep(0.05, 0.45, h)


## 變體：低頻噪聲成片（同一片＝同一種），加情境
static func _variant(S: Dictionary, sp: String, assets: Array, p: Vector2, c: Dictionary, vr: float) -> int:
	if assets.size() <= 1:
		return 0
	var nv: float = (S["noise"]["var"] as FastNoiseLite).get_noise_2d(p.x + sp.length() * 37.0, p.y - sp.length() * 11.0) + (vr - 0.5) * 0.35
	match sp:
		"grass_tall":
			if float(c["dry"]) > 0.5 and nv > 0.1:
				return 2
			if nv < -0.22:
				return 1
			if nv > 0.2:
				return 0
			return 3
		"fern_big":
			return 1 if (float(c["shade"]) > 0.45 and float(c["de"]) > 3.0 and nv > 0.02) else 0
		"fern_small":
			return 1 if nv > -0.05 else 0
		"herb":
			if nv < -0.32 and float(c["lush"]) < 0.35:
				return 2                              # 擬寶珠型只成小片
			return 0 if nv > -0.05 else 1
		"forb":
			return 1 if float(c["can"]) > 0.25 else 0
		"sasa":
			return 1 if nv < -0.38 else 0        # 隈笹為主，細葉笹只在少數片
		"litter":
			return 1 if nv < 0.2 else 0
	return 1 if nv < -0.05 else 0


const BASE_TINT := {"grass_tall": Color(0.64, 0.71, 0.70), "grass_short": Color(0.70, 0.77, 0.75), "shadegrass": Color(0.78, 0.82, 0.80), "sedge": Color(0.80, 0.84, 0.82),
	"fern_big": Color(0.72, 0.74, 0.76), "fern_small": Color(0.80, 0.82, 0.82), "herb": Color(0.80, 0.83, 0.80), "forb": Color(0.80, 0.82, 0.80),
	"sasa": Color(0.80, 0.82, 0.82), "shrub": Color(0.82, 0.84, 0.84), "sapling": Color(0.86, 0.88, 0.86),
	"litter": Color(0.92, 0.90, 0.90), "moss": Color(0.62, 0.64, 0.58), "twigs": Color(0.9, 0.9, 0.9)}


static func _tint(S: Dictionary, sp: String, p: Vector2, c: Dictionary, rng: RandomNumberGenerator) -> Color:
	var k := rng.randf_range(0.90, 1.06)
	var col: Color = BASE_TINT.get(sp.trim_prefix("verge_"), Color(1, 1, 1)) * k
	if sp == "grass_tall" or sp == "grass_short":
		var pd := clampf(float(c["dry"]) * 0.7 + 0.45 * (S["noise"]["var"] as FastNoiseLite).get_noise_2d(p.x * 0.6 + 50.0, p.y * 0.6), 0.0, 1.0)
		col = col * Color(1, 1, 1).lerp(Color(1.04, 0.98, 0.84), pd * 0.8)
		col = col * Color(1, 1, 1).lerp(Color(0.90, 1.02, 0.92), clampf(float(c["lush"]), 0.0, 1.0))
	if sp.begins_with("grass") or sp == "sedge":
		col = col * lerpf(1.0, 0.86, float(c["shade"]))
	if sp == "verge_litter":
		col = col * Color(0.76, 0.72, 0.68)                 # 荒野化 R2：路上的落葉是踩過、濕的（審圖：橘色太飽和像貼紙）
	elif sp == "verge_moss":
		col = col * Color(0.78, 0.80, 0.74)      # 闊葉、蕨在林下不再額外壓暗（光照已經夠暗，再壓會變黑色剪影）
	return Color(minf(col.r, 1.0), minf(col.g, 1.0), minf(col.b, 1.0), 1.0)


# ================================================================= 主規劃
static func plan(dress, lib, cfg: Dictionary, F, trunks: Array, unders: Array, wrocks: Array, foot: Array, hard: Array, clr: Dictionary, seed_: int) -> Dictionary:
	var fl: Dictionary = cfg["floor"]
	var spc: Dictionary = fl["species"]
	var S := {"lib": lib, "F": F, "cfg": cfg, "clr": clr, "foot": foot, "wrocks": wrocks, "cache": {}, "dress": dress,
		"n_edge": _noise(seed_ + 7, 0.09), "g_trunk": Grid.new(), "g_under": Grid.new(), "g_hard": Grid.new(), "noise": {}}
	for t: Dictionary in trunks:
		(S["g_trunk"] as Grid).add(t["p"], t)
	for u: Vector2 in unders:
		(S["g_under"] as Grid).add(u, u)
	for h: Dictionary in hard:
		(S["g_hard"] as Grid).add(h["p"], h)
	var N: Dictionary = S["noise"]
	N["warp"] = _noise(seed_ + 313, 0.04)
	N["commA"] = _noise(seed_ + 555, 0.035)
	N["commB"] = _noise(seed_ + 777, 0.045)
	N["gap"] = _noise(seed_ + 888, 0.085)
	N["var"] = _noise(seed_ + 991, 0.05)
	var names: Array = spc.keys()
	for i in names.size():
		N[names[i]] = _noise(seed_ + 101 * (i + 1), float((spc[names[i]] as Dictionary)["freq"]))
	N["roadside"] = _noise(seed_ + 4242, 0.11)
	var bb := Rect2()
	var first := true
	for zr: Dictionary in cfg["zones"]:
		var r := Rect2(float(zr["x"][0]), float(zr["z"][0]), float(zr["x"][1]) - float(zr["x"][0]), float(zr["z"][1]) - float(zr["z"][0]))
		bb = r if first else bb.merge(r)
		first = false
	if cfg.has("bbox"):
		var rb := Rect2(float(cfg["bbox"][0]), float(cfg["bbox"][1]), float(cfg["bbox"][2]) - float(cfg["bbox"][0]), float(cfg["bbox"][3]) - float(cfg["bbox"][1]))
		bb = rb if first else bb.merge(rb)
		first = false
	_build_dens(S, bb.grow(6.0), trunks, unders)
	var cover := {}
	var counts := {}
	var lod := {}
	var shadow: Array = []
	for i2 in names.size():
		var sp: String = names[i2]
		var cc: Dictionary = spc[sp]
		lod[sp] = cc["lod"]
		if bool(cc.get("shadow", false)):
			shadow.append(sp)
		var spacing := float(cc["spacing"])
		var assets: Array = cc["assets"]
		var need0 := float(cc["clear"])
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_ * 31 + i2 * 7919
		var gr_rot := rng.randf() * TAU
		var gcen := bb.get_center()
		var ext := bb.size.length() * 0.5 + spacing
		var x := -ext
		while x < ext:
			var z := -ext
			while z < ext:
				var p := gcen + Vector2(x + rng.randf_range(-0.5, 0.5) * spacing, z + rng.randf_range(-0.5, 0.5) * spacing).rotated(gr_rot)
				var u := rng.randf()
				var yaw := rng.randf() * TAU
				var sc := rng.randf_range(float(cc["s"][0]), float(cc["s"][1]))
				var vr := rng.randf()
				var j1 := rng.randf_range(-1.0, 1.0)
				var j2 := rng.randf_range(-1.0, 1.0)
				var j3 := rng.randf()
				z += spacing
				if not bb.has_point(p):
					continue
				var c := ctx_at(S, p)
				if not bool(c["ok"]):
					continue
				# 路緣淨空：沿路起伏、兩側不同（噪聲在世界座標＝路兩側 5 m 以上就不相關）
				var nr: float = (N["roadside"] as FastNoiseLite).get_noise_2d(p.x, p.y)
				if float(c["de"]) < need0 * (1.0 + 1.3 * maxf(0.0, nr) + 0.9 * minf(0.0, nr)):
					continue
				var pr := _p(S, sp, p, c)
				var spb := sp.trim_prefix("verge_")            # 路緣侵蝕種：擺法（傾斜、下沉、石鋪規則）同原種
				if float(c["pv"]) > 0.05:
					# 石鋪上：只有低地被（苔、短草、蔭草、落葉、枯枝、小草花），越往石鋪中心越少
					if not (spb == "moss" or spb == "grass_short" or spb == "shadegrass" or spb == "litter" or spb == "twigs" or spb == "forb" or spb == "mud"):
						continue
					pr *= 1.0 - smoothstep(0.05, float(clr.get("paving_low", 0.05)), float(c["pv"]))
				if pr <= 0.0 or u > pr * float(cc["pmax"]):
					continue
				var ai := _variant(S, sp, assets, p, c, vr)
				var an: String = assets[mini(ai, assets.size() - 1)]
				var y := float(lib.h_at(p.x, p.y))
				var nrm: Vector3 = dress.normal_at(lib, p.x, p.y)
				var tilt := 1.0 if (spb == "litter" or spb == "moss" or spb == "twigs" or spb == "mud") else (0.7 if spb == "shadegrass" else (0.5 if spb.begins_with("fern") or spb == "herb" else 0.3))
				var upv := Vector3.UP.slerp(nrm, tilt).normalized()
				if sp == "grass_tall" or sp == "forb" or sp == "sedge" or sp == "fern_big" or sp == "sapling":
					var lean := 0.14 if sp != "sapling" else 0.08
					upv = (upv + Vector3(j1 * lean, 0.0, j2 * lean)).normalized()
				var sy := sc
				if sp.begins_with("grass") or sp.begins_with("fern") or sp == "sedge" or sp == "herb" or sp == "forb":
					sy = sc * lerpf(0.78, 1.22, j3)
				elif spb == "moss" or spb == "mud":
					sy = sc * 0.6
				elif sp == "sapling":
					sy = sc * lerpf(0.85, 1.2, j3)
				var b3: Basis = dress._basis_up(upv, yaw) * Basis.from_scale(Vector3(sc, sy, sc))
				var sink := 0.004 if (spb == "litter" or spb == "twigs") else (0.0 if (spb == "moss" or spb == "mud") else 0.03)
				if not cover.has(an):
					cover[an] = []
				(cover[an] as Array).append({"xf": Transform3D(b3, Vector3(p.x, y - sink, p.y)), "c": _tint(S, sp, p, c, rng), "cat": sp})
				counts[an] = int(counts.get(an, 0)) + 1
			x += spacing
	return {"cover": cover, "counts": counts, "lod": lod, "shadow": shadow, "ctx_cells": (S["cache"] as Dictionary).size()}


static func _n_trees(trunks: Array, p: Vector2, r: float) -> int:
	var n := 0
	for t: Dictionary in trunks:
		if (t["p"] as Vector2).distance_to(p) < r:
			n += 1
	return n


# ================================================================= 自動木（露根、倒木、殘株、枯枝堆）
## 回傳 s01_dress 木清單格式的項目（之後走同一套貼地／量測／碰撞流程）
static func auto_wood(dress, lib, cfg: Dictionary, F, trunks: Array, foot: Array, wrocks: Array, named: Array, clr: Dictionary) -> Array:
	var aw: Dictionary = cfg["auto_wood"]
	var rng := RandomNumberGenerator.new()
	rng.seed = int(aw.get("seed", 515))
	var n_edge := _noise(int(cfg.get("seed", 1)) + 7, 0.09)
	var out: Array = []
	var taken_tree := {}
	for e: Dictionary in named:
		if e.has("tree_near"):
			taken_tree[Vector2(float(e["tree_near"][0]), float(e["tree_near"][1]))] = true
	# ---- 露根：林下（遮蔭夠）的樹挑一部分，不是每棵都有（避免每棵樹一圈）
	var rcfg: Dictionary = aw["roots"]
	var nroot := 0
	var tlist := trunks.duplicate()
	tlist.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["id"]) + str(a["p"]) < String(b["id"]) + str(b["p"]))
	for t: Dictionary in tlist:
		var tp: Vector2 = t["p"]
		if dress.zone_w(cfg, tp, n_edge) < 0.6 or lib.scene_id_of_z(tp.y) != String(dress.scene_id):
			continue
		var skip := false
		for q: Vector2 in taken_tree:
			if q.distance_to(tp) < 1.5:
				skip = true
		if skip:
			continue
		var de: float = S01Wall.path_edge_d(lib, tp)
		var sl: float = lib.slope_deg_at(tp.x, tp.y)
		if _n_trees(trunks, tp, 7.0) < int(rcfg["min_trees_7m"]) or de < float(rcfg["min_road"]) or sl > 38.0:
			continue
		if String(t["id"]).begins_with("sakura") or String(t["id"]).begins_with("young"):
			continue                                   # 櫻（既定群落）與幼樹不加根
		var blocked := false
		for f: Dictionary in foot:
			if tp.distance_to(f["p"]) < float(f["r"]) + 1.6:
				blocked = true
				break
		if blocked or rng.randf() > float(rcfg["p"]):
			continue
		nroot += 1
		out.append({"id": "AR%d" % nroot, "asset": "s01_roots_a" if nroot % 3 != 1 else "s01_roots_b", "tree_near": [tp.x, tp.y],
			"s": clampf(0.55 + 0.45 * float(t["r"]) / 0.35, 0.65, 1.15), "sink": 0.04, "moss": rng.randf_range(0.25, 0.55), "yaw_add": rng.randf_range(-45.0, 45.0)})
		if nroot >= int(rcfg["max"]):
			break
	# ---- 倒木／殘株／枯枝堆：林下、緩坡、離路遠；不等距（亂序＋貪婪）
	var dcfg: Dictionary = aw["dead"]
	var keyed: Array = []
	var zlist: Array = (cfg["zones"] as Array).duplicate()
	if cfg.has("bbox"):
		zlist.append({"x": [cfg["bbox"][0], cfg["bbox"][2]], "z": [cfg["bbox"][1], cfg["bbox"][3]]})
	for zr: Dictionary in zlist:
		var x := float(zr["x"][0])
		while x <= float(zr["x"][1]):
			var z := float(zr["z"][0])
			while z <= float(zr["z"][1]):
				var p := Vector2(x + rng.randf_range(-1.0, 1.0), z + rng.randf_range(-1.0, 1.0))
				var key := rng.randf()
				z += 2.0
				if dress.zone_w(cfg, p, n_edge) < 0.6 or lib.scene_id_of_z(p.y) != String(dress.scene_id):
					continue
				if _n_trees(trunks, p, 7.0) < int(dcfg["min_trees_7m"]) or lib.slope_deg_at(p.x, p.y) > 24.0:
					continue
				if S01Wall.path_edge_d(lib, p) < float(dcfg["min_road"]):
					continue
				keyed.append([key, p])
			x += 2.0
	keyed.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var assets: Array = dcfg["assets"]
	var taken: Array = []
	for e2: Dictionary in named:
		if e2.has("at"):
			taken.append(Vector2(float(e2["at"][0]), float(e2["at"][1])))
	var nd := 0
	for kv: Array in keyed:
		if nd >= int(dcfg["max"]):
			break
		var p2: Vector2 = kv[1]
		var ok := true
		for q2: Vector2 in taken:
			if p2.distance_to(q2) < float(dcfg["min_d"]):
				ok = false
				break
		if not ok:
			continue
		var an: String = assets[nd % assets.size()]
		var gr := S01Wall.grad(lib, p2)
		var yaw := rng.randf_range(0.0, 360.0)
		if gr.length() > 0.05:
			yaw = rad_to_deg(atan2(gr.y, gr.x)) + 90.0 + rng.randf_range(-30.0, 30.0)     # 倒木大致沿等高線
		# 長件（倒木）：整段離樹幹至少 0.5 m
		var half := 2.0 if an.contains("log") else (1.2 if an.contains("branch") else 0.9)
		var dirv := Vector2(cos(deg_to_rad(yaw)), -sin(deg_to_rad(yaw)))
		var bad := false
		for t2: Dictionary in trunks:
			var tq: Vector2 = t2["p"]
			if tq.distance_to(p2) > half + 2.0:
				continue
			var proj := clampf((tq - p2).dot(dirv), -half, half)
			if tq.distance_to(p2 + dirv * proj) < float(t2["r"]) + 0.5:
				bad = true
				break
		for f2: Dictionary in foot:
			if p2.distance_to(f2["p"]) < float(f2["r"]) + half + 0.3:
				bad = true
				break
		for w: Dictionary in wrocks:
			if p2.distance_to(w["p"]) < float(w["r"]) + half:
				bad = true
				break
		if bad:
			continue
		nd += 1
		var e3 := {"id": "AD%d" % nd, "asset": an, "at": [snappedf(p2.x, 0.01), snappedf(p2.y, 0.01)], "yaw": yaw, "sink": 0.05 if an.contains("log") else 0.03,
			"moss": rng.randf_range(0.45, 0.85)}
		out.append(e3)
		taken.append(p2)
	return out


## 2026-10-18 荒野化 R2：路緣侵蝕。路面土帶的「邊」不再是一條直線——落葉、苔、泥、矮草沿路緣以不規則的舌狀
## 長進路面（de＜0）與路肩。只用低矮、無碰撞的地被（MultiMesh），路線與碰撞不變。
##   species.<verge_x>.verge＝[伸進路面最多的 de（負）, 路肩外緣的 de]；verge_ramp_z＝[z0, z1]：z0（村端）只伸 35 %，到 z1 全量（S01 村緣→荒野）
static func _p_verge(S: Dictionary, sp: String, p: Vector2, c: Dictionary) -> float:
	var N: Dictionary = S["noise"]
	var cc: Dictionary = ((S["cfg"] as Dictionary)["floor"] as Dictionary)["species"][sp]
	var band: Array = cc.get("verge", [-1.2, 0.8])
	if float(c["sl"]) > 38.0 or float(c["in_h"]) > 0.08 or float(c["td"]) < 0.12:
		return 0.0
	var de := float(c["de"])
	var nr: float = (N["roadside"] as FastNoiseLite).get_noise_2d(p.x * 0.6 + 13.0, p.y * 0.6 - 7.0)
	var ramp := 1.0
	if cc.has("verge_ramp_z"):
		var rz: Array = cc["verge_ramp_z"]
		ramp = lerpf(0.35, 1.0, smoothstep(float(rz[0]), float(rz[1]), p.y) if float(rz[0]) < float(rz[1]) else 1.0 - smoothstep(float(rz[1]), float(rz[0]), p.y))
	var reach := float(band[0]) * ramp * (0.30 + 0.70 * smoothstep(-0.35, 0.45, nr))
	var inside := smoothstep(reach, reach * 0.3, de)
	var outside := 1.0 - smoothstep(float(band[1]) * 0.5, float(band[1]), de)
	var nn: float = (N[sp] as FastNoiseLite).get_noise_2d(p.x, p.y)
	var patch := smoothstep(-0.5, 0.12, nn + 0.35 * nr)
	return clampf(inside * outside * patch * float(c["zw"]), 0.0, 1.0)

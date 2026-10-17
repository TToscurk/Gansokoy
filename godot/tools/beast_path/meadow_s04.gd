extends RefCounted
## 獸道 S04 草叢層（V1.2 C）：中央空地「過度平整」＋外圈「低矮草叢與蕨類不足」→ 3D 立體植被（不是貼圖）。
## 重用人間之里 P9 R5-3 已封存的叢 Kit（tools/village_v2_meadow_lib.gd 的 kit()／material()／bake()／_tint()，唯讀引用、不改它）；
## 規劃（哪裡長、長什麼）是獸道自己的：
##   · 地面語意＝bp_lib.ground_channels（0 土／1 礫／2 泥／3 岩／4 葉／5 濕；草＝剩餘權重）：長在草、落葉、濕處；壓實土上只有零星短草；
##   · 戰鬥圓（r < 14 m）只放極稀疏的短草／乾草，無任何碰撞；空地邊緣帶（r 18~34 m）、岩腳（離落地線 0.3~3.6 m）、溪潭邊加厚；
##   · 蕨類在林蔭（樹冠遮蔭 > 0.32）與岩腳；穗草／高草在濕處；
##   · 禁區：路面（由 ground 權重處理）、水面（DM/DS）、岩落地線以內、樹幹圓、陡坡、岩層權重 > 0.45、地形遮罩外 6 m。
## 距離三層（近 0–31 m / 中 23–54 m / 54 m 以遠 0）由 meadow_grass.gdshader 的縮放淡出負責。
## 輸入由 generate_beast_path.gd 寫出（gen/s04_meadow_inputs.json）；烘焙 bake_meadow_s04.gd（非 headless）。

const ML := preload("res://tools/village_v2_meadow_lib.gd")
const BPLib := preload("res://tools/beast_path/bp_lib.gd")

const SEED := 4417
const STEP := 0.52
const RANGE := 62.0
const MAX_N := 9000
const SINK := 0.02


static func _noise(seed_: int, freq: float) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed_
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	return n


## 岩腳落地線（8 m 格）與樹幹圓（6 m 格）的空間雜湊——plan()／adopt_frozen() 共用
static func _hashes(feet: Array, stems: Array) -> Array:
	var fh := {}
	for f: Dictionary in feet:
		var key := Vector2i(floori(float(f["p"][0]) / 8.0), floori(float(f["p"][1]) / 8.0))
		if not fh.has(key):
			fh[key] = []
		(fh[key] as Array).append([Vector2(float(f["p"][0]), float(f["p"][1])), float(f["r"])])
	var th := {}
	for t: Array in stems:
		var key2 := Vector2i(floori(float(t[0]) / 6.0), floori(float(t[1]) / 6.0))
		if not th.has(key2):
			th[key2] = []
		(th[key2] as Array).append([Vector2(float(t[0]), float(t[1])), float(t[2])])
	return [fh, th]


## 一個落點的禁區判定（plan()／adopt_frozen() 共用；V1.3 由 plan() 原樣抽出，順序與門檻不變——不耗用亂數）。
##   回傳 {"why": ""（可長）／"mask"／"water"／"slope"／"rock"／"foot"／"stem"，可長時另附 ds、g、ix、iz、foot_d 給密度與種類用}
static func _site(lib: BPLib, ctx: Dictionary, fh: Dictionary, th: Dictionary, p: Vector2) -> Dictionary:
	if lib.mask_sdf(p) > 6.0:
		return {"why": "mask"}
	var ds := lib.sample_arr(lib.DS, p.x, p.y)
	if ds < 0.5:
		return {"why": "water"}
	if lib.slope_deg_at(p.x, p.y) > 36.0:
		return {"why": "slope"}
	var ix := clampi(int(round(lib._ix(p.x))), 0, lib.nx - 1)
	var iz := clampi(int(round(lib._iz(p.y))), 0, lib.nz - 1)
	var g: PackedFloat32Array = lib.ground_channels(ix, iz, ctx)
	if g[3] > 0.45:
		return {"why": "rock"}
	# ---- 岩腳：離落地線（半徑已含裕度）的距離
	var foot_d := 99.0
	var kf := Vector2i(floori(p.x / 8.0), floori(p.y / 8.0))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var kk := Vector2i(kf.x + dx, kf.y + dz)
			if fh.has(kk):
				for e: Array in fh[kk]:
					foot_d = minf(foot_d, p.distance_to(e[0] as Vector2) - float(e[1]))
	if foot_d < -0.6:
		return {"why": "foot"}
	# ---- 樹幹圓
	var kt := Vector2i(floori(p.x / 6.0), floori(p.y / 6.0))
	for dx2 in range(-1, 2):
		for dz2 in range(-1, 2):
			var kk2 := Vector2i(kt.x + dx2, kt.y + dz2)
			if th.has(kk2):
				for e2: Array in th[kk2]:
					if p.distance_to(e2[0] as Vector2) < float(e2[1]) + 0.3:
						return {"why": "stem"}
	return {"why": "", "ds": ds, "g": g, "ix": ix, "iz": iz, "foot_d": foot_d}


## ctx：{"canopy", "rock_d"}；feet：[{id, p:[x,z], r}]；stems：[[x,z,r]]
static func plan(lib: BPLib, ctx: Dictionary, feet: Array, stems: Array) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var n_big := _noise(SEED + 1, 1.0 / 17.0)
	var n_mid := _noise(SEED + 2, 1.0 / 6.0)
	var n_dry := _noise(SEED + 4, 1.0 / 23.0)
	var c0 := lib.arena_c()
	var hs := _hashes(feet, stems)
	var fh: Dictionary = hs[0]
	var th: Dictionary = hs[1]
	var canopy: PackedFloat32Array = ctx["canopy"]
	var P := PackedVector2Array()
	var K := PackedByteArray()
	var Y := PackedFloat32Array()
	var COL := PackedColorArray()
	var S := PackedFloat32Array()
	var W := PackedFloat32Array()
	var YAW := PackedFloat32Array()
	var stats := {"cand": 0, "kept": 0, "core": 0, "rim": 0, "foot": 0, "wet": 0, "shade": 0, "open": 0,
		"rej_water": 0, "rej_slope": 0, "rej_rock": 0, "rej_foot": 0, "rej_stem": 0, "rej_mask": 0}
	var kinds_n := {}
	var x0 := c0.x - RANGE
	var z0 := c0.y - RANGE
	var nxs := int(2.0 * RANGE / STEP)
	for ia in nxs:
		for ib in nxs:
			var p := Vector2(x0 + (float(ia) + rng.randf()) * STEP, z0 + (float(ib) + rng.randf()) * STEP)
			if P.size() >= MAX_N:
				break
			if lib.scene_id_of_z(p.y) != "S04":
				continue
			var r := p.distance_to(c0)
			if r > RANGE:
				continue
			stats["cand"] += 1
			var st := _site(lib, ctx, fh, th, p)
			var why: String = st["why"]
			if why != "":
				stats["rej_" + why] += 1
				continue
			var ds: float = st["ds"]
			var ix: int = st["ix"]
			var iz: int = st["iz"]
			var g: PackedFloat32Array = st["g"]
			var foot_d: float = st["foot_d"]
			var w_grass := maxf(1.0 - (g[0] + g[1] + g[2] + g[3] + g[4]), 0.0)
			var w_leaf := g[4]
			var w_dirt := g[0]
			var wet := g[5]
			# ---- 密度（叢 / m²）
			var can := canopy[iz * lib.nx + ix]
			var clump := smoothstep(-0.25, 0.45, n_big.get_noise_2d(p.x, p.y) + 0.45 * n_mid.get_noise_2d(p.x, p.y))
			var core := smoothstep(7.0, 17.0, r)
			var rim := smoothstep(13.0, 26.0, r)
			var d := 0.95 * pow(w_grass, 1.15) + 0.34 * w_leaf + 0.10 * w_dirt
			d *= (0.12 + 0.88 * core) * (0.35 + 0.65 * clump)
			d *= 1.0 + 0.55 * rim
			if foot_d < 3.6:
				d *= 1.0 + 1.5 * (1.0 - smoothstep(0.3, 3.6, foot_d))
			if wet > 0.25 or ds < 6.0:
				d *= 1.25
			d = minf(d, 1.5)
			if rng.randf() > d * STEP * STEP:
				continue
			# ---- 種類
			var k := ML.K_MEDIUM
			var u := rng.randf()
			var tag := "open"
			if r < 14.0:                                  # 戰鬥中心不分遠近岩腳：只有極稀的短草／乾草（高草與羊歯留給外圈）
				k = ML.K_SHORT if u < 0.45 else (ML.K_SPARSE if u < 0.8 else ML.K_DRY)
				tag = "core"
			elif foot_d < 2.8 and u < 0.62:
				k = ML.K_FERN if u < 0.34 else ML.K_TALL
				tag = "foot"
			elif wet > 0.3 or ds < 5.0:
				k = ML.K_SEED if u < 0.35 else (ML.K_TALL if u < 0.7 else ML.K_MEDIUM)
				tag = "wet"
			elif can > 0.32:
				k = ML.K_FERN if u < 0.46 else (ML.K_MEDIUM if u < 0.76 else ML.K_TALL)
				tag = "shade"
			else:
				var dryv := n_dry.get_noise_2d(p.x, p.y) * 0.5 + 0.5
				if u < 0.30:
					k = ML.K_MEDIUM
				elif u < 0.48:
					k = ML.K_SHORT
				elif u < 0.62:
					k = ML.K_LEAN
				elif u < 0.78:
					k = ML.K_DRY if dryv > 0.45 else ML.K_SPARSE
				elif u < 0.9:
					k = ML.K_TALL
				else:
					k = ML.K_FERN if can > 0.12 else ML.K_SEED
				tag = "rim" if rim > 0.5 else "open"
			stats[tag] += 1
			kinds_n[ML.KIND_NAMES[k]] = int(kinds_n.get(ML.KIND_NAMES[k], 0)) + 1
			var lush := clampf(wet * 0.8 + can * 0.5, 0.0, 1.0)
			var dry := clampf(0.55 * (1.0 - wet) * (1.0 - can) * (0.4 + 0.6 * (n_dry.get_noise_2d(p.x + 80.0, p.y) * 0.5 + 0.5)), 0.0, 1.0)
			P.append(p)
			K.append(k)
			Y.append(lib.h_at(p.x, p.y) - SINK)
			COL.append(ML._tint(rng, k, dry, lush))
			S.append(rng.randf_range(0.78, 1.28) if tag != "core" else rng.randf_range(0.7, 1.0))
			W.append(rng.randf_range(0.9, 1.18))
			YAW.append(rng.randf() * TAU)
			stats["kept"] += 1
	stats["kinds"] = kinds_n
	return {"n": P.size(), "p": P, "k": K, "y": Y, "col": COL, "s": S, "w": W, "yaw": YAW, "stats": stats}


## V1.3：S04 草叢＝V1.2 凍結（layout.forest.freeze_s04_meadow；凍結檔＝在 V1.2 狀態下以 plan() 原樣重算匯出的 V1.2 規劃，數量＝V1.2 的 s04_meadow.scn）。
##   每一叢依「現在的」地形／水／岩腳／樹幹重跑 _site() 的禁區規則：通過＝原樣保留（y 只在現在地面差 > 1 mm 時重新落地），不通過＝剔除；**不新增任何一叢、不重抽樣**。
##   陣列順序：保留的叢維持 V1.2 的 index（P9 封存的 ML.mid_keep 依 index 挑中級 LOD），剔除留下的空位由陣列尾端的叢補上——只有這幾叢可能換中級資格。
static func adopt_frozen(lib: BPLib, ctx: Dictionary, feet: Array, stems: Array, F: Dictionary) -> Dictionary:
	var hs := _hashes(feet, stems)
	var fh: Dictionary = hs[0]
	var th: Dictionary = hs[1]
	var n0 := int(F["n"])
	var fp: Array = F["p"]
	var drop := {}
	var dropped: Array = []
	var why_n := {}
	for i in n0:
		var p := Vector2(float(fp[i][0]), float(fp[i][1]))
		var why: String = _site(lib, ctx, fh, th, p)["why"]
		if why != "":
			drop[i] = true
			dropped.append({"i": i, "x": snappedf(p.x, 0.01), "z": snappedf(p.y, 0.01), "why": why})
			why_n[why] = int(why_n.get(why, 0)) + 1
	var n_keep := n0 - drop.size()
	var tail: Array = []
	for i in range(n_keep, n0):
		if not drop.has(i):
			tail.append(i)
	var order := PackedInt32Array()
	order.resize(n_keep)
	var ti := 0
	for q in n_keep:
		if drop.has(q):
			order[q] = int(tail[ti])
			ti += 1
		else:
			order[q] = q
	var P := PackedVector2Array()
	var K := PackedByteArray()
	var Y := PackedFloat32Array()
	var COL := PackedColorArray()
	var S := PackedFloat32Array()
	var W := PackedFloat32Array()
	var YAW := PackedFloat32Array()
	var reground: Array = []
	for q in n_keep:
		var i := order[q]
		var p := Vector2(float(fp[i][0]), float(fp[i][1]))
		P.append(p)
		K.append(int(F["k"][i]))
		var y0 := float(F["y"][i])
		var y1 := lib.h_at(p.x, p.y) - SINK
		if absf(y1 - y0) > 0.001:
			reground.append({"i": i, "x": snappedf(p.x, 0.01), "z": snappedf(p.y, 0.01), "dy": snappedf(y1 - y0, 0.001)})
			Y.append(y1)
		else:
			Y.append(y0)
		var c: Array = F["col"][i]
		COL.append(Color(float(c[0]), float(c[1]), float(c[2]), float(c[3])))
		S.append(float(F["s"][i]))
		W.append(float(F["w"][i]))
		YAW.append(float(F["yaw"][i]))
	var stats := {"frozen": n0, "kept": n_keep, "dropped_n": drop.size(), "why": why_n, "reground_n": reground.size(),
		"moved_for_mid": tail.size(), "dropped": dropped, "reground": reground}
	return {"n": n_keep, "p": P, "k": K, "y": Y, "col": COL, "s": S, "w": W, "yaw": YAW, "stats": stats, "order": order}

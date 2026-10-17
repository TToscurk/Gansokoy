extends RefCounted
## 獸道 S01 入口林道地表情境（R1）。把「村緣土路 → 草地 → 林床」的分布寫進頂點通道，由 bp_ground_s01.gdshader 畫出來。
##
## 設計原則（使用者 S01 規格）：
##   · 主路：自然土路、視覺寬度略有變化——不是公園中央步道那種均勻的帶子；邊緣不規則，草成舌狀侵入、局部踩踏；
##   · 地表：泥土、草地、落葉、少量碎石——不是一整片單色綠草坪；落葉隨『沿主路的相對進度』增加（村緣 0–30 % 幾乎沒有 → 深處 70–100 % 成片）；
##   · 分布要有原因（沿用 S04 的做法）：落葉聚在樹冠下與林緣、礫在岩腳與路面被踢出來的邊、苔在岩腳與林蔭、泥在農田邊與林下低窪、
##     壓實土在小屋門口、路標旁、岔進田裡的小徑、鳥居腳；
##   · 只動地表著色，不動高度與碰撞（s01_terrain_shape.res 雜湊不變，gate 檢查）；道路中心線與物理寬度不變——這裡的『視覺寬度』只是壓實土的著色範圍。
##
## 通道（與 S04 同一套，shader 讀法也一樣）：
##   0 trodden 踏み固め土、1 gravel 礫、2 mud 濕泥、3 rock 岩、4 forest 林床落葉、5 wet、6 moss、7 路中心側向距離 m（右為正；車轍用）。其餘＝草。
## 優先序填充：岩 → 泥 → 礫 → 落葉 → 壓實土 → 草（剩餘），所以 Σ ≤ 1。

const BP := preload("res://tools/beast_path/bp_lib.gd")

var lib: BP
var cfg: Dictionary = {}
var s0 := 0.0
var s_len := 117.2
var _feat: Array = []
var _n_big := FastNoiseLite.new()        # 約 28 m：草地乾濕、落葉帶
var _n_mid := FastNoiseLite.new()        # 約 9 m
var _n_fine := FastNoiseLite.new()       # 約 2.4 m
var _n_edge := FastNoiseLite.new()       # 約 3 m：路緣起伏
var _n_tongue := FastNoiseLite.new()     # 約 5 m：草舌
var _n_leaf := FastNoiseLite.new()       # 約 7 m：落葉堆
var _n_grav := FastNoiseLite.new()       # 約 1.6 m：礫斑
var _n_wid := FastNoiseLite.new()        # 沿路向的寬度起伏（1D，約 20 m）
var _n_drift := FastNoiseLite.new()      # 沿路向的路心漂移（1D，約 40 m）
var _n_tuft := FastNoiseLite.new()       # 約 1 m：路緣草簇
var _n_face := FastNoiseLite.new()       # R2 谷壁面：約 16 m 的植被／岩面塊（沿落水線拉長取樣）
var _n_face2 := FastNoiseLite.new()      # R2 谷壁面：約 6 m 的邊界打散
# R3 地表自然化（cfg.r3.enabled 才用；種子另取，不影響 R1／R2 的噪聲）
var r3: Dictionary = {}
var r3_on := false
var _r3_wind := Vector2.ZERO
var _n_wx := FastNoiseLite.new()         # domain warp（約 30 m）
var _n_wz := FastNoiseLite.new()
var _n_reg := FastNoiseLite.new()        # 區域（約 45 m）：哪一帶是粗草、哪一帶是短草／乾草
var _n_pat := FastNoiseLite.new()        # 中尺度（約 12 m）：落葉毯、苔地的邊界
var _n_pat2 := FastNoiseLite.new()       # 約 7 m：毯子裡的缺口、裸土
var _n_reg2 := FastNoiseLite.new()       # 約 38 m：乾／潤
var stats: Dictionary = {}


func _init(lib_: BP = null) -> void:
	if lib_ == null:
		return
	setup(lib_)


func setup(lib_: BP) -> void:
	lib = lib_
	cfg = lib.L.get("s01_ground", {})
	s0 = lib.st_s("village")
	s_len = lib.st_s("s01_s02") - s0
	var seed_ := int(lib.L["frame"]["seed"]) + 3101
	var defs: Array = [[_n_big, 0.036], [_n_mid, 0.11], [_n_fine, 0.42], [_n_edge, 0.33], [_n_tongue, 0.2], [_n_leaf, 0.15], [_n_grav, 0.62], [_n_wid, 0.05], [_n_drift, 0.026], [_n_tuft, 1.0], [_n_face, 0.085], [_n_face2, 0.21]]
	for k in defs.size():
		var n: FastNoiseLite = defs[k][0]
		n.seed = seed_ + 17 * k
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.frequency = float(defs[k][1])
	r3 = cfg.get("r3", {})
	r3_on = bool(r3.get("enabled", false))
	if r3_on:
		var defs3: Array = [[_n_wx, 0.032], [_n_wz, 0.032], [_n_reg, 0.022], [_n_pat, 0.085], [_n_pat2, 0.14], [_n_reg2, 0.026]]
		for k3 in defs3.size():
			var n3: FastNoiseLite = defs3[k3][0]
			n3.seed = seed_ + 5003 + 29 * k3
			n3.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
			n3.frequency = float(defs3[k3][1]) * float(r3.get("freq_k", 1.0))
		var wd: Array = r3.get("wind", [1.0, 0.25])
		_r3_wind = Vector2(float(wd[0]), float(wd[1])).normalized()
	_build_features()


# ---------------------------------------------------------------- 手放的地表特徵（每一個都有原因）
## layout.s01_ground.features：{id, kind: trodden|gravel|mud|leaf|grass, at: {st, ds, off}|{x, z}, a, b, yaw(度，可省), k, why}
## 邊界用噪聲扭曲，不是正橢圓；a／b＝半長軸／半短軸 m；k＝強度。
func _build_features() -> void:
	_feat.clear()
	for f: Dictionary in cfg.get("features", []):
		if not f.has("kind") or not ["trodden", "gravel", "mud", "leaf", "grass"].has(String(f["kind"])):
			push_warning("s01_ground.features：略過未知的 kind（%s）" % str(f.get("id", "?")))
			continue
		var c: Vector2
		var at: Dictionary = f["at"]
		if at.has("st"):
			c = lib.resolve(at)["p"]
		else:
			c = Vector2(float(at["x"]), float(at["z"]))
		var yaw := deg_to_rad(float(f.get("yaw", 0.0)))
		if f.has("face"):                                  # face＝朝向某個站點（長軸沿該方向），例：小徑從路邊走向小屋門口
			var fa: Dictionary = f["face"]
			var tgt: Vector2 = lib.resolve(fa)["p"] if fa.has("st") else Vector2(float(fa["x"]), float(fa["z"]))
			var d := tgt - c
			yaw = atan2(d.x, d.y)
		var ax := Vector2(sin(yaw), cos(yaw))
		_feat.append({"k": String(f["kind"]), "c": c, "a": float(f["a"]), "b": float(f["b"]), "ax": ax, "az": Vector2(-ax.y, ax.x), "st": float(f.get("k", 1.0)), "id": String(f.get("id", ""))})


func feature_w(x: float, z: float) -> Dictionary:
	var out := {"trodden": 0.0, "gravel": 0.0, "mud": 0.0, "leaf": 0.0, "grass": 0.0}
	var p := Vector2(x, z)
	for g: Dictionary in _feat:
		var d: Vector2 = p - (g["c"] as Vector2)
		if d.length_squared() > pow(maxf(float(g["a"]), float(g["b"])) * 1.9, 2.0):
			continue
		var wu := _n_edge.get_noise_2d(x * 1.3 + 17.0, z * 1.3 - 5.0)
		var wv := _n_edge.get_noise_2d(x * 1.3 - 31.0, z * 1.3 + 44.0)
		var u := d.dot(g["ax"]) / float(g["a"]) + 0.34 * wu
		var v := d.dot(g["az"]) / float(g["b"]) + 0.34 * wv
		var dn := sqrt(u * u + v * v)
		var f := (1.0 - smoothstep(0.42, 1.0, dn)) * float(g["st"])
		if f > float(out[g["k"]]):
			out[g["k"]] = f
	return out


# ---------------------------------------------------------------- 情境（樹冠遮蔭、岩腳距離）
## trees：規劃器的條目（scene／x／z／y／s／id／kind）；feet：道具腳印 [{id, p: Vector2, r}]。
## wall（R2）：s01_wall.plan 的結果——岩露頭／碎石併進岩腳場（碎石、苔成斑），土袋做成 pocket 場（土袋裡的地表不再是裸岩／土坡）。
##   wall 為空（R1／replay）時 pocket 場全 0、岩腳場與 R1 相同 → 輸出逐位元不變。
## 回傳可直接交給 terrain_generator.build_tile 的 ctx（有 "s01" 鍵＝S01 模式；也帶 canopy／rock_d／pocket 場）。
static func build_ctx(lib_: BP, trees: Array, kit: Dictionary, feet: Array, wall: Dictionary = {}) -> Dictionary:
	var crowns: Array = []
	for t: Dictionary in trees:
		var z := float(t["z"])
		var sc := String(t["scene"])
		if not (sc == "S01" or (sc == "S02" and z > -116.0)):
			continue                                            # S01 的樹，加上越過接縫、樹冠會伸進 S01 的 S02 樹
		var kind := String(t["kind"])
		if kind != "tree" and kind != "pin" and kind != "landmark":
			continue
		var hh := float((kit[String(t["id"])] as Dictionary)["h"]) * float(t["s"])
		crowns.append({"x": float(t["x"]), "z": z, "reach": clampf(hh * 0.30, 2.0, 8.0), "w": clampf(hh / 20.0, 0.4, 1.3)})
	var rocks: Array = []
	for f: Dictionary in feet:
		var id := String(f["id"])
		var q: Vector2 = f["p"]
		if q.y < -104.0 or q.y > 34.0:
			continue
		if id.contains("rock") or id.contains("stone_marker"):
			rocks.append({"p": q, "r": float(f["r"])})
	var pockets: Array = []
	var unders: Array = []
	if not wall.is_empty():
		# R2：林下（灌木、羊齒、笹、杜鵑）腳下的地面：落葉＋苔的小裙，邊界由噪聲打散——不再是插在修剪草坪上的一叢
		for t2: Dictionary in trees:
			if String(t2["scene"]) == "S01" and String(t2["kind"]) == "under":
				var hu := float((kit[String(t2["id"])] as Dictionary)["h"]) * float(t2["s"])
				unders.append({"x": float(t2["x"]), "z": float(t2["z"]), "reach": clampf(0.9 + hu * 0.9, 1.0, 2.6), "w": 1.0})
	for wr: Dictionary in wall.get("rocks", []):
		rocks.append({"p": Vector2(float(wr["x"]), float(wr["z"])), "r": 0.42 * maxf(float(wr["w"]), float(wr["d"]))})
	for pk: Dictionary in wall.get("pockets", []):
		if int(pk.get("trees", 1)) + int(pk.get("under", 1)) <= 0:
			continue                                    # 沒有植物的土袋（總量守恆扣光了）：地表不畫土
		pockets.append({"x": float(pk["x"]), "z": float(pk["z"]), "reach": float(pk["R"]) * 1.35, "w": 1.6})
	var g := load("res://tools/beast_path/s01_ground.gd")
	var inst = g.new(lib_)
	var ctx := {"s01": inst, "canopy": lib_.build_canopy_field(crowns), "rock_d": lib_.build_rockprox_field(rocks), "pocket": lib_.build_canopy_field(pockets),
		"n_crowns": crowns.size(), "n_rocks": rocks.size(), "n_pockets": pockets.size()}
	if not wall.is_empty():
		ctx["under_f"] = lib_.build_canopy_field(unders)
		var fc: Dictionary = wall.get("face", {})
		if not fc.is_empty():
			ctx["face"] = fc                            # R2 谷壁面的植被／岩面鑲嵌（R1／replay 沒有 wall → 沒有這個鍵 → 輸出不變）
	var r3c: Dictionary = (lib_.L.get("s01_ground", {}) as Dictionary).get("r3", {})
	if bool(r3c.get("enabled", false)):
		ctx.merge(_r3_fields(lib_, trees, kit, r3c, wall))
	return ctx


# ---------------------------------------------------------------- R3 地表自然化：情境場
## 只算 S01 tile（含 2 m 外圈）。所有場都是『平滑的大尺度量』，在 channels() 裡再用 domain-warp 噪聲推擠門檻，
## 所以落葉毯／苔地的邊界是不規則、連貫的大塊——不是每棵樹一圈、也不是整片均勻雜訊。
##   r3_wood ：樹冠覆蓋（每棵樹冠圓 → 盒狀模糊 ≈ 高斯 σ 4 m）。群落裡連成一片，孤樹只剩一團淡的、門檻一推就散。
##   r3_under：林下植物（灌木、羊齒、笹、杜鵑）的床（σ ≈ 2.4 m）：讓林下叢併進同一片林床，不是一叢一圈。
##   r3_hol  ：低窪（σ 5.5 m 平滑高度 − 高度，m；＋＝窪地、谷腳的積土帶；−＝凸起、坡肩）。
##   r3_hol2 ：小低窪（σ 2.4 m）。
## bounds／zone：S02／S03 森林地表（zone_ground.gd）用同一套場；zone＝""＝S01（範圍與樹的篩選與原本逐位元相同）。
static func _r3_fields(lib_: BP, trees: Array, kit: Dictionary, r3c: Dictionary, wall: Dictionary, bounds := Rect2(-114.0, -108.0, 228.0, 142.0), zone := "") -> Dictionary:
	var nx: int = lib_.nx
	var nz: int = lib_.nz
	var i0 := clampi(int(floor(lib_._ix(bounds.position.x))), 0, nx - 1)
	var i1 := clampi(int(ceil(lib_._ix(bounds.end.x))), 0, nx - 1)
	var j0 := clampi(int(floor(lib_._iz(bounds.position.y))), 0, nz - 1)
	var j1 := clampi(int(ceil(lib_._iz(bounds.end.y))), 0, nz - 1)
	var wood := PackedFloat32Array()
	wood.resize(nx * nz)
	var und := PackedFloat32Array()
	und.resize(nx * nz)
	var crown_k := float(r3c.get("crown_k", 1.0))
	for t: Dictionary in trees:
		var z := float(t["z"])
		var sc := String(t["scene"])
		if zone == "":
			if not (sc == "S01" or (sc == "S02" and z > -116.0)):
				continue
		elif z < bounds.position.y - 8.0 or z > bounds.end.y + 8.0:
			continue
		var kind := String(t["kind"])
		var hh := float((kit[String(t["id"])] as Dictionary)["h"]) * float(t["s"])
		if kind == "tree" or kind == "pin" or kind == "landmark":
			_disc(lib_, wood, float(t["x"]), z, clampf(hh * 0.30, 2.0, 8.0) * crown_k, clampf(hh / 20.0, 0.4, 1.3))
		elif kind == "under" and sc == "S01" and zone == "":
			_disc(lib_, und, float(t["x"]), z, clampf(0.7 + hh * 0.8, 0.9, 2.2), 1.0)
	for pk: Dictionary in wall.get("pockets", []):
		if int(pk.get("trees", 1)) + int(pk.get("under", 1)) > 0:
			_disc(lib_, und, float(pk["x"]), float(pk["z"]), float(pk["R"]) * 0.8, 0.6)
	var wb := _box_blur(wood, nx, i0, i1, j0, j1, int(r3c.get("wood_rx", 5)), 3, int(r3c.get("wood_rz", 3)))
	var ub := _box_blur(und, nx, i0, i1, j0, j1, 2, 3)
	# 低窪：只用谷底（谷緣 SDF < 0）的高度做加權平均（normalized convolution）——
	# 否則谷壁的高度會把整圈谷腳都算成『窪地』，畫出一條沿谷壁的平行帶。谷壁上（SDF > 1）低窪場＝0，谷壁另有 R2 的谷壁面鑲嵌。
	var msk := PackedFloat32Array()
	msk.resize(nx * nz)
	var hm := PackedFloat32Array()
	hm.resize(nx * nz)
	var sdf_c := PackedFloat32Array()
	sdf_c.resize(nx * nz)
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var k0 := j * nx + i
			var sd := lib_.mask_sdf(Vector2(lib_.lx0 + float(i) * lib_.cell, lib_.lz0 + float(j) * lib_.cell))
			sdf_c[k0] = sd
			var m := 1.0 - smoothstep(-1.0, 0.5, sd)
			msk[k0] = m
			hm[k0] = lib_.H[k0] * m
	var hb := _box_blur(hm, nx, i0, i1, j0, j1, 5, 3)
	var mb := _box_blur(msk, nx, i0, i1, j0, j1, 5, 3)
	var hb2 := _box_blur(hm, nx, i0, i1, j0, j1, 2, 3)
	var mb2 := _box_blur(msk, nx, i0, i1, j0, j1, 2, 3)
	var hol := PackedFloat32Array()
	hol.resize(nx * nz)
	var hol2 := PackedFloat32Array()
	hol2.resize(nx * nz)
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var k := j * nx + i
			var on_floor := 1.0 - smoothstep(0.0, 1.5, sdf_c[k])
			if mb[k] > 0.05 and on_floor > 0.0:
				hol[k] = clampf(hb[k] / mb[k] - lib_.H[k], -1.0, 1.0) * on_floor
			if mb2[k] > 0.05 and on_floor > 0.0:
				hol2[k] = clampf(hb2[k] / mb2[k] - lib_.H[k], -0.6, 0.6) * on_floor
	return {"r3_wood": wb, "r3_under": ub, "r3_hol": hol, "r3_hol2": hol2,
		"r3_sk_soil": lib_.build_canopy_field((wall.get("skirts", []) as Array).filter(func(e: Dictionary) -> bool: return String(e["kind"]) == "soil").map(func(e: Dictionary) -> Dictionary: return {"x": e["x"], "z": e["z"], "reach": e["R"], "w": 1.0})),
		"r3_sk_scree": lib_.build_canopy_field((wall.get("skirts", []) as Array).filter(func(e: Dictionary) -> bool: return String(e["kind"]) == "scree").map(func(e: Dictionary) -> Dictionary: return {"x": e["x"], "z": e["z"], "reach": e["R"], "w": 1.0}))}


## 圓盤（邊緣 1 m 軟化）累加進場
static func _disc(lib_: BP, f: PackedFloat32Array, x: float, z: float, r: float, w: float) -> void:
	var ix0 := maxi(int(floor(lib_._ix(x - r - 1.0))), 0)
	var ix1 := mini(int(ceil(lib_._ix(x + r + 1.0))), lib_.nx - 1)
	var iz0 := maxi(int(floor(lib_._iz(z - r - 1.0))), 0)
	var iz1 := mini(int(ceil(lib_._iz(z + r + 1.0))), lib_.nz - 1)
	for jz in range(iz0, iz1 + 1):
		for jx in range(ix0, ix1 + 1):
			var d := Vector2(lib_.lx0 + float(jx) * lib_.cell - x, lib_.lz0 + float(jz) * lib_.cell - z).length()
			var k := 1.0 - smoothstep(r - 0.5, r + 0.5, d)
			if k > 0.0:
				f[jz * lib_.nx + jx] += k * w


## 可分離盒狀模糊（running sum），只在視窗 [i0,i1]×[j0,j1] 內；passes 次 ≈ 高斯。視窗外保持原值。rz＜0＝與 r 相同（各向同性）。
static func _box_blur(src: PackedFloat32Array, nx: int, i0: int, i1: int, j0: int, j1: int, r: int, passes: int, rz: int = -1) -> PackedFloat32Array:
	var a := src.duplicate()
	var tmp := src.duplicate()
	var inv := 1.0 / float(2 * r + 1)
	if rz < 0:
		rz = r
	var invz := 1.0 / float(2 * rz + 1)
	for _p in passes:
		for j in range(j0, j1 + 1):
			var row := j * nx
			var acc := 0.0
			for k in range(-r, r + 1):
				acc += a[row + clampi(i0 + k, i0, i1)]
			for i in range(i0, i1 + 1):
				tmp[row + i] = acc * inv
				acc += a[row + clampi(i + r + 1, i0, i1)] - a[row + clampi(i - r, i0, i1)]
		for i in range(i0, i1 + 1):
			var acc2 := 0.0
			for k in range(-rz, rz + 1):
				acc2 += tmp[clampi(j0 + k, j0, j1) * nx + i]
			for j in range(j0, j1 + 1):
				a[j * nx + i] = acc2 * invz
				acc2 += tmp[clampi(j + rz + 1, j0, j1) * nx + i] - tmp[clampi(j - rz, j0, j1) * nx + i]
	return a


# ---------------------------------------------------------------- 頂點通道
func channels(ix: int, iz: int, ctx: Dictionary) -> PackedFloat32Array:
	var i := clampi(iz, 0, lib.nz - 1) * lib.nx + clampi(ix, 0, lib.nx - 1)
	var x := lib.lx0 + float(ix) * lib.cell
	var z := lib.lz0 + float(iz) * lib.cell
	var p := Vector2(x, z)
	var sx := (lib.hl(ix + 1, iz) - lib.hl(ix - 1, iz)) / (2.0 * lib.cell)
	var sz := (lib.hl(ix, iz + 1) - lib.hl(ix, iz - 1)) / (2.0 * lib.cell)
	var slope := rad_to_deg(atan(sqrt(sx * sx + sz * sz)))
	var can: float = (ctx["canopy"] as PackedFloat32Array)[i]
	var rd: float = (ctx["rock_d"] as PackedFloat32Array)[i]
	var q := lib.main.q(p)
	var s_path := float(q["s"])
	var off := float(q["off"])
	var u := clampf((s_path - s0) / s_len, 0.0, 1.0)
	var n_big := _n_big.get_noise_2d(x, z)
	var n_mid := _n_mid.get_noise_2d(x, z)
	var n_fine := _n_fine.get_noise_2d(x, z)
	var n_edge := _n_edge.get_noise_2d(x, z)
	var n_tongue := _n_tongue.get_noise_2d(x + 311.0, z - 97.0)
	var n_leaf := _n_leaf.get_noise_2d(x - 41.0, z + 23.0)
	var n_grav := _n_grav.get_noise_2d(x + 7.0, z - 13.0)
	var n_wid := _n_wid.get_noise_1d(s_path)
	var n_drift := _n_drift.get_noise_1d(s_path + 500.0)
	# 進度分帶（使用者規格：入口 0–30 % 村緣、30–70 % 自然雜木與草叢、70–100 % 樹冠交錯與較密地被）
	var vil := 1.0 - smoothstep(0.24, 0.46, u)
	var forest_k := smoothstep(0.42, 0.96, u)
	# ---- 路：視覺寬度（壓實土的著色範圍）沿路起伏，村緣寬、林內窄；樹幹擠近的地方變窄；路心在路廊裡微微漂移
	var hw := lib.sample_arr(lib.WM, x, z)
	var hw_vis := hw * (0.58 + 0.66 * (0.5 + 0.5 * n_wid))                      # 0.58–1.24 倍的物理半寬：忽寬忽窄（V1.3 的白模是等寬色帶）
	hw_vis *= lerpf(1.0, 1.12, vil) * lerpf(1.0, 0.80, forest_k)
	hw_vis *= 1.0 - 0.34 * smoothstep(0.12, 0.5, can)
	var tuft := smoothstep(0.50, 0.80, _n_tuft.get_noise_2d(x * 1.0, z * 1.0))                                 # 約 1 m 的草簇：邊緣處零星探進土路
	var d_eff := absf(off - 0.55 * n_drift) + 0.60 * n_edge + 0.34 * n_fine - 0.55 * tuft * (0.35 + 0.65 * smoothstep(0.0, 1.0, 1.0 - absf(absf(off) - hw * 0.75) / 1.6))
	var tongue := smoothstep(0.28, 0.58, n_tongue + 0.30 * n_big) * (0.60 + 0.40 * forest_k)
	d_eff += tongue * 1.15
	var road := 1.0 - smoothstep(hw_vis - 0.28, hw_vis + 0.24, d_eff)
	var edge_band := 1.0 - smoothstep(0.0, 1.3, absf(d_eff - hw_vis))
	var shoulder := (1.0 - smoothstep(hw_vis + 0.1, hw_vis + 2.1, d_eff)) * (0.26 + 0.24 * (0.5 + 0.5 * n_mid))
	# ---- 鋪石／壓實地（鳥居腳、石燈籠）：邊界打散，只成斑塊
	var pv := lib.sample_arr(lib.PV, x, z) + 0.30 * n_mid + 0.16 * n_fine
	var earth := smoothstep(0.12, 0.55, pv)
	var stonep := smoothstep(0.50, 0.76, pv + 0.20 * n_big)
	var ft := feature_w(x, z)
	# ---- 岩
	var w_rock := smoothstep(30.0, 46.0, slope)
	# ---- 泥：林下／低窪的陰濕處（隨進度增加），加上手放的農田邊濕土
	var damp := smoothstep(0.34, 0.60, 0.5 * n_mid + 0.5 * n_big + 0.22 * can) * (0.12 + 0.60 * forest_k)
	var mud_p := clampf(damp * 0.55, 0.0, 1.0) * (1.0 - 0.7 * road)
	mud_p = maxf(mud_p, float(ft["mud"]) * (1.0 - 0.6 * road))
	# ---- 礫：路面裡的小石（村緣車道多）、路緣被踢出來的、岩腳的崩落、鋪石斑
	var grav_road := smoothstep(0.52, 0.78, n_grav + 0.35 * n_big) * road * (0.26 + 0.34 * vil)
	var grav_rock := (1.0 - smoothstep(0.0, 1.5, rd + 0.9 * n_mid)) * 0.34 * smoothstep(0.30, 0.62, 0.7 * n_grav + 0.5 * n_mid + 0.3)      # 岩腳的碎石成『斑』（崩落的方向性），不是繞岩一圈
	var grav_edge := edge_band * smoothstep(0.55, 0.80, n_grav * 0.8 + 0.5 * n_fine) * 0.34
	var gravel_p := clampf(grav_road + grav_rock + grav_edge + stonep * 0.55, 0.0, 1.0)
	gravel_p = maxf(gravel_p, float(ft["gravel"]) * (1.0 - 0.5 * road))
	# ---- 落葉：樹冠下；林床隨進度成片；路緣的落葉堆（掃到邊上）；手放的落葉
	var pile := smoothstep(-0.05, 0.40, n_leaf + 0.3 * n_edge)
	var leaf_tree := smoothstep(0.08, 0.60, can)
	var leaf_floor := forest_k * (0.22 + 0.62 * pile)
	var leaf_edge := edge_band * pile * (0.12 + 0.58 * forest_k)
	var leaf_cap := lerpf(0.62, 0.95, smoothstep(0.62, 0.92, u))             # 草地段的落葉只到六成（高度混合出『葉蓋在草上』），深處才接近滿
	var leaf_p := minf(leaf_tree * 0.75 + leaf_floor + leaf_edge, leaf_cap) * (1.0 - 0.78 * road)
	leaf_p = maxf(leaf_p, float(ft["leaf"]) * (1.0 - 0.7 * road))
	# ---- 壓實土：路＋肩部踩踏草＋鋪石地＋手放的踩實處；草斑（手放）切走一部分
	var bare := smoothstep(0.60, 0.80, 0.55 * n_mid + 0.55 * n_fine + 0.25 * n_big) * 0.30 * (1.0 - forest_k)      # 草地裡的裸土斑（踩薄的草皮）
	var dirt_p := clampf(maxf(maxf(road, shoulder * (1.0 - road)), maxf(maxf(earth * 0.7, float(ft["trodden"])), bare)), 0.0, 1.0)
	dirt_p *= 1.0 - float(ft["grass"]) * (1.0 - road)
	# ---- 苔：岩腳、林蔭潮處
	# 岩腳的苔：成『斑』（陰濕處才長），不是繞岩一圈；範圍縮小、強度降低
	var moss := (1.0 - smoothstep(0.0, 1.9, rd + 0.5 * n_mid)) * smoothstep(0.30, 0.62, 0.55 * n_mid + 0.45 * n_fine + 0.30 + 0.25 * can) * 0.62
	moss += smoothstep(0.35, 0.85, can) * smoothstep(0.0, 0.45, n_big + 0.1) * 0.40 * (0.25 + 0.75 * forest_k)
	moss = clampf(moss * (1.0 - road), 0.0, 1.0)
	var leaf_feat := float(ft["leaf"]) * (1.0 - 0.7 * road)
	if r3_on and ctx.has("r3_wood"):
		# R3：落葉／苔改由 _channels_r3 依樹冠群、低窪、林下床決定（不再是『每棵樹冠一圈』＋均勻噪聲）；
		#     這裡只留岩腳的苔，leaf_p 歸零後只收谷壁土袋／谷壁面（R2 已接受的谷壁畫面不變）
		leaf_p = 0.0
		moss = clampf((1.0 - smoothstep(0.0, 1.9, rd + 0.5 * n_mid)) * smoothstep(0.30, 0.62, 0.55 * n_mid + 0.45 * n_fine + 0.30) * 0.62 * (1.0 - road), 0.0, 1.0)
	# ---- R2 土袋：谷壁上植物扎根的土（pocket 場；R1 為 0）。土袋裡不是裸岩／落葉土坡，而是草＋落葉＋苔；
	#      邊界用 9 m／2.4 m 噪聲打散，不是正圓。soil 也寫進頂點 CUSTOM0.a，讓 shader 在土袋裡不畫『陡坡→岩』
	var soil := 0.0
	if ctx.has("pocket"):
		var pk: float = (ctx["pocket"] as PackedFloat32Array)[i]
		if pk > 0.0:
			soil = smoothstep(0.12, 0.62, pk + 0.22 * n_mid + 0.12 * n_fine)
			w_rock *= 1.0 - soil
			leaf_p = maxf(leaf_p, soil * (0.40 + 0.25 * (0.5 + 0.5 * n_leaf)))
			moss = maxf(moss, soil * (0.22 + 0.30 * smoothstep(-0.2, 0.5, n_fine)))
	# ---- R2 谷壁面：陡坡不再整面是同一種岩色。天然的谷壁＝落水線上的植被帶（苔、草、少量落葉）與岩脊上的裸岩交錯：
	#      ① 噪聲沿落水線拉長取樣（5 點平均）→ 植被成縱向的帶，不是圓斑；② 橫斷面上凹（沖溝）的地方加分、凸（岩脊）的地方扣分；
	#      ③ 實體岩的周圍保留裸岩（岩是從裸岩面露出來的）。結果寫進 soil（shader 在 soil 處不畫陡坡岩），只改顏色通道，不改高度。
	if ctx.has("face") and slope > float((ctx["face"] as Dictionary).get("slope_min", 36.0)) and z > -95.0:
		var fc: Dictionary = ctx["face"]
		var gl := sqrt(sx * sx + sz * sz)
		var fall := Vector2(-sx, -sz) / maxf(gl, 1e-4)
		var nf := 0.0
		for k5 in 5:
			var q5 := p + fall * (float(k5) - 2.0) * float(fc.get("streak_m", 3.5))
			nf += _n_face.get_noise_2d(q5.x, q5.y)
		nf /= 5.0
		var hxx := (lib.hl(ix + 2, iz) + lib.hl(ix - 2, iz) - 2.0 * lib.hl(ix, iz)) / (4.0 * lib.cell * lib.cell)
		var hzz := (lib.hl(ix, iz + 2) + lib.hl(ix, iz - 2) - 2.0 * lib.hl(ix, iz)) / (4.0 * lib.cell * lib.cell)
		var hxz := (lib.hl(ix + 2, iz + 2) - lib.hl(ix + 2, iz - 2) - lib.hl(ix - 2, iz + 2) + lib.hl(ix - 2, iz - 2)) / (16.0 * lib.cell * lib.cell)
		var kp := (hxx * sz * sz - 2.0 * hxz * sx * sz + hzz * sx * sx) / maxf(gl * gl, 1e-4)      # 沿等高線方向的曲率：＋＝沖溝、−＝岩脊
		# 小台（落水線方向上坡度忽然變緩的地方）：土會積、植物會長
		var bench := 0.0
		for sgn in [-1.0, 1.0]:
			var jx := clampi(ix + int(roundf(fall.x * 2.0 * sgn)), 1, lib.nx - 2)
			var jz := clampi(iz + int(roundf(fall.y * 2.0 * sgn)), 1, lib.nz - 2)
			var tx := (lib.hl(jx + 1, jz) - lib.hl(jx - 1, jz)) / (2.0 * lib.cell)
			var tz := (lib.hl(jx, jz + 1) - lib.hl(jx, jz - 1)) / (2.0 * lib.cell)
			bench += rad_to_deg(atan(sqrt(tx * tx + tz * tz))) * 0.5
		bench -= slope                                                               # ＞0：比上下都緩
		var n2 := _n_face2.get_noise_2d(x, z)
		var score := nf * float(fc.get("noise_k", 1.0)) + 0.30 * n2 + 0.22 * n_fine + clampf(kp * float(fc.get("curv_k", 6.0)), -0.7, 0.7) 			+ clampf(bench * float(fc.get("bench_k", 0.04)), -0.3, 0.4) + float(fc.get("bias", 0.0))
		score -= float(fc.get("steep_k", 0.010)) * maxf(slope - 50.0, 0.0)          # 越陡越難長東西
		var veg := smoothstep(float(fc.get("lo", -0.05)), float(fc.get("hi", 0.25)), score)
		veg *= lerpf(float(fc.get("break_min", 1.0)), 1.0, smoothstep(-0.22, 0.18, n2 + 0.55 * n_fine))   # 帶裡也有裸岩缺口：不連成整條
		veg *= 0.45 + 0.55 * smoothstep(0.4, 2.6, rd)                               # 實體岩周圍留裸岩
		veg *= 1.0 - road
		veg *= smoothstep(-95.0, -90.0, z)
		if veg > soil:
			soil = veg
			w_rock *= 1.0 - veg
			var tone := _n_face.get_noise_2d(x * 0.6 + 213.0, z * 0.6 - 71.0)           # 每塊植被的組成不同：苔多／草多／落葉多
			leaf_p = maxf(leaf_p, veg * clampf(0.10 + 0.40 * smoothstep(0.05, 0.45, tone) + 0.12 * n_leaf, 0.05, 0.6))
			moss = maxf(moss, veg * clampf(0.25 + 0.55 * smoothstep(-0.45, 0.0, -tone) + 0.25 * n_fine, 0.1, 0.95))
		stats["face_cells"] = int(stats.get("face_cells", 0)) + 1
		stats["face_veg"] = float(stats.get("face_veg", 0.0)) + veg
	if ctx.has("under_f") and not (r3_on and ctx.has("r3_wood")):
		var uf: float = (ctx["under_f"] as PackedFloat32Array)[i]
		if uf > 0.0:
			var sk := smoothstep(0.10, 0.55, uf + 0.25 * n_fine + 0.12 * n_mid) * (1.0 - road)
			leaf_p = maxf(leaf_p, sk * (0.30 + 0.30 * (0.5 + 0.5 * n_leaf)))
			moss = maxf(moss, sk * (0.15 + 0.25 * smoothstep(-0.2, 0.5, n_fine)))
	if r3_on and ctx.has("r3_wood"):
		return _channels_r3(i, x, z, sx, sz, slope, u, off, rd, n_mid, n_fine, n_leaf, road, edge_band, shoulder, earth, ft, w_rock, gravel_p, soil, leaf_p, leaf_feat, moss, ctx)
	var free := 1.0 - w_rock
	var w_mud := free * mud_p
	free -= w_mud
	var w_grv := free * gravel_p
	free -= w_grv
	var w_leaf := free * leaf_p
	free -= w_leaf
	var w_dirt := free * dirt_p
	var out := PackedFloat32Array()
	out.resize(9)
	out[0] = w_dirt
	out[1] = w_grv
	out[2] = w_mud
	out[3] = w_rock
	out[4] = w_leaf
	out[5] = clampf(w_mud * 0.8 + moss * 0.2, 0.0, 1.0)
	out[6] = moss
	out[7] = clampf(off, -16.0, 16.0)
	out[8] = soil
	return out


# ---------------------------------------------------------------- R3：地表自然化（使用者 S01 R3 Stage 1 第一優先）
## 問題：P7 共用貼圖陣列只有一張『修剪過的草坪』草貼圖，R1／R2 讓它鋪滿所有開闊地；第 6 層其實是粗草＋枯草（R1 把它當落葉用）。
## 做法（只在 S01；共用 bp_ground.* 不動）：
##   · 新增兩層 S01 專用貼圖（專案裡已有、CC0）：真正的林床落葉（Poly Haven forest_leaves_02）、苔地（aerial_grass_rock）。
##   · 開闊地以『粗草（第 6 層）』為主、短草只在路肩／踩踏處與區域噪聲的小塊；草色降飽和，乾／潤由地形決定（凸處乾、窪處潤）。
##   · 落葉毯＝樹冠群的平滑覆蓋場（σ≈4 m，順坡／順風偏移）＋ domain-warp 噪聲推擠門檻 → 群落下連成一片、邊界不規則，孤樹多半沒有；
##     加上低窪的堆積、林下植物的床（林下叢併進同一片林床，不是一叢一圈）。
##   · 苔地＝濃蔭×潮濕（窪地）、岩腳；裸土＝坡肩沖刷、開闊乾處的薄草皮；泥＝林中低窪。
##   · 村緣（u 0–0.3）保留開闊草地；越往林內，林床越完整。
## 輸出 13 個值：0–8 與 R2 相同（4＝粗草＋谷壁土袋草）＋ 9 林床落葉、10 苔地、11 乾、12 潤（後四個寫進頂點 CUSTOM1）。
func _channels_r3(i: int, x: float, z: float, sx: float, sz: float, slope: float, u: float, off: float, rd: float, n_mid: float, n_fine: float, n_leaf: float,
		road: float, edge_band: float, shoulder: float, earth: float, ft: Dictionary, w_rock: float, gravel_p: float, soil: float,
		leaf_wall: float, leaf_feat: float, moss: float, ctx: Dictionary) -> PackedFloat32Array:
	var road_k := 1.0 - road
	var gl := sqrt(sx * sx + sz * sz)
	var fall := Vector2(-sx, -sz) / maxf(gl, 1e-4)
	# 落葉順坡往下滑、順風吹：在 p 點看到的落葉，來自上坡／上風處的樹冠
	var shift := -fall * float(r3.get("drift_m", 1.4)) * clampf(gl * 3.0, 0.0, 1.0) - _r3_wind * float(r3.get("wind_m", 1.0))
	var wood: PackedFloat32Array = ctx["r3_wood"]
	var Wd := lib.sample_arr(wood, x + shift.x, z + shift.y)
	var Wl: float = wood[i]
	var Ub := lib.sample_arr(ctx["r3_under"], x + shift.x * 0.6, z + shift.y * 0.6)
	var hol: float = (ctx["r3_hol"] as PackedFloat32Array)[i]
	var hol2: float = (ctx["r3_hol2"] as PackedFloat32Array)[i]
	var wm := float(r3.get("warp_m", 9.0))
	var wx := x + _n_wx.get_noise_2d(x, z) * wm
	var wz := z + _n_wz.get_noise_2d(x, z) * wm
	var reg := _n_reg.get_noise_2d(wx, wz)
	var reg2 := _n_reg2.get_noise_2d(wx + 91.0, wz - 57.0)
	var pat := _n_pat.get_noise_2d(wx + 40.0, wz - 13.0)
	var pat2 := _n_pat2.get_noise_2d(x - 77.0, z + 31.0)
	var vr: Array = r3.get("vil", [0.14, 0.40])
	var vil3 := 1.0 - smoothstep(float(vr[0]), float(vr[1]), u)
	var dr: Array = r3.get("deep", [0.35, 0.95])
	var deep3 := smoothstep(float(dr[0]), float(dr[1]), u)
	var wk := float(r3.get("wood_k", 1.0))
	var Wn := 1.0 - exp(-Wd * wk)                                                  # 樹冠覆蓋（飽和到 0–1；群落裡疊很多棵也不會一直變大）
	var Wln := 1.0 - exp(-Wl * wk)
	var wi := Wn + float(r3.get("deep_k", 0.38)) * deep3 - float(r3.get("vil_k", 0.20)) * vil3
	# R3 指名岩組（谷腳岩）的岩腳：岩擋住的土＋苔＋落葉（不規則，不是一圈），下坡側崩落的碎石扇（s01_wall.apply_r3_fixes 的 skirts）
	var sk_soil := 0.0
	var sk_scree := 0.0
	if ctx.has("r3_sk_soil"):
		var sks: float = (ctx["r3_sk_soil"] as PackedFloat32Array)[i]
		if sks > 0.0:
			sk_soil = smoothstep(0.05, 0.45, sks + 0.22 * pat + 0.15 * n_fine) * road_k
		var skc: float = (ctx["r3_sk_scree"] as PackedFloat32Array)[i]
		if skc > 0.0:
			sk_scree = smoothstep(0.05, 0.40, skc + 0.20 * pat2 + 0.18 * n_fine) * 0.75 * road_k
	if sk_soil > 0.0:
		w_rock *= 1.0 - 0.8 * sk_soil
		soil = maxf(soil, 0.9 * sk_soil)
		moss = maxf(moss, 0.40 * sk_soil)
	gravel_p = maxf(gravel_p, sk_scree)
	var steep_k := 1.0 - smoothstep(34.0, 46.0, slope) * (1.0 - soil)          # 陡坡留不住落葉（土袋例外）
	var moist := smoothstep(-0.02, 0.10, hol2 + 0.8 * hol + 0.06 * pat2)
	# ---- 1 林床（樹冠群下的地被；邊界由 warp 噪聲推擠 → 不規則的大塊、往草地伸出舌狀）
	var lr: Array = r3.get("lit", [0.34, 0.74])
	var cover := smoothstep(float(lr[0]), float(lr[1]), wi + 0.30 * reg + 0.26 * pat + 0.03 * n_fine)
	cover = maxf(cover, smoothstep(0.03, 0.14, hol) * smoothstep(0.15, 0.50, wi + 0.15 * pat) * 0.80)    # 林緣低窪的堆積
	var ub := smoothstep(0.22, 0.55, Ub + 0.28 * pat + 0.04 * n_fine)
	# 林下植物的床：在林裡併進林床（落葉）；在開闊草地上的單叢灌木／羊齒則長在粗草裡（不是草坪上一圈褐色）
	var in_wood := smoothstep(0.20, 0.60, wi)
	cover = maxf(cover, ub * float(r3.get("under_lit", 0.70)) * in_wood)
	var reach_edge := smoothstep(-0.15, 0.25, pat2 + 0.5 * reg)                                       # 有些段落葉一路鋪到路緣、有些段留一點路肩草（不是沿路連續的綠帶）
	cover *= steep_k * road_k * (1.0 - 0.55 * shoulder * (1.0 - reach_edge))
	# 路旁 2–8 m 的帶子：沿路被不規則地切段（有的段林床退後、讓粗草／短草穿過來），不讓落葉沿路連成一條緞帶
	var verge := (1.0 - smoothstep(6.0, 9.0, absf(off) - lib.sample_arr(lib.WM, x, z))) * (1.0 - vil3 * 0.5)
	cover *= 1.0 - verge * float(r3.get("verge_cut", 0.6)) * (1.0 - smoothstep(-0.30, 0.10, pat + 0.6 * reg2))
	# 林床的組成（中尺度分區，不是每格亂跳）：落葉為主；潮濕處苔地；林冠縫隙的亮處長粗草；濃蔭根盤露黑土
	var fm := 0.6 * pat2 + 0.4 * reg2
	var moss_part := smoothstep(0.05, 0.55, 0.45 * moist + 0.35 * fm + 0.30 * n_mid - 0.05) * float(r3.get("moss_part", 0.60))
	var gap_part := smoothstep(0.10, 0.45, -0.8 * fm + 0.45 * (1.0 - Wln) - 0.12) * float(r3.get("gap_part", 0.70))
	var edge_part := 4.0 * cover * (1.0 - cover)                                                       # 林緣過渡帶：粗草與落葉交錯
	var lit := cover * (1.0 - moss_part) * (1.0 - gap_part) * (1.0 - 0.35 * edge_part)
	lit = maxf(lit, leaf_feat)
	lit = maxf(lit, sk_soil * (0.30 + 0.25 * smoothstep(-0.3, 0.3, pat2)))
	lit = minf(lit, float(r3.get("lit_cap", 0.92)))
	var mg := cover * moss_part * (1.0 - 0.5 * gap_part)
	mg = maxf(mg, (1.0 - smoothstep(0.0, 2.4, rd + 0.7 * n_mid)) * 0.50 * smoothstep(-0.2, 0.3, pat2) * road_k * steep_k)   # 岩腳
	mg = maxf(mg, sk_soil * 0.32 * smoothstep(-0.4, 0.2, -pat2))
	mg *= float(r3.get("mg_k", 1.0)) * (1.0 - 0.6 * vil3)
	var shade := smoothstep(0.35, 0.90, Wln + 0.25 * deep3)
	moss = maxf(moss, shade * moist * 0.50 * road_k)
	# ---- 3 裸土：坡肩沖刷（中坡、凸處）＋開闊地凸起乾處的薄草皮（只在村緣與路旁的使用痕跡範圍）＋路／肩／鋪石地／手放踩實
	var bank := smoothstep(11.0, 17.0, slope) * (1.0 - smoothstep(30.0, 38.0, slope)) * smoothstep(0.05, 0.45, -hol * 6.0 + 0.35 * pat + 0.10)
	var dry_k := smoothstep(-0.30, 0.45, 0.65 * reg2 - 5.0 * hol + 0.30 * pat2 - 0.35 * Wln)
	var near_use := 1.0 - smoothstep(3.0, 9.0, absf(off) - lib.sample_arr(lib.WM, x, z))           # 只在路旁（被人踩薄的地方）
	var thin := (1.0 - cover) * smoothstep(0.55, 0.92, dry_k + 0.25 * n_mid) * smoothstep(0.01, 0.10, -hol) * near_use * float(r3.get("thin_k", 0.30))
	var root := smoothstep(0.75, 0.97, Wln) * smoothstep(0.15, 0.50, -fm) * cover * 0.35
	var dirt_p := clampf(maxf(maxf(road, shoulder * road_k), maxf(earth * 0.7, float(ft["trodden"]))), 0.0, 1.0)
	dirt_p = maxf(dirt_p, maxf(bank * float(r3.get("bank_k", 0.7)), thin) * road_k)
	dirt_p *= 1.0 - float(ft["grass"]) * road_k
	# ---- 4 泥（林中低窪、濃蔭根盤的黑土）
	var mud3 := smoothstep(0.05, 0.20, hol) * cover * float(r3.get("mud_k", 0.45)) * smoothstep(-0.2, 0.3, pat)
	var mud_p := maxf(float(ft["mud"]) * (1.0 - 0.6 * road), maxf(mud3, root) * road_k)
	# ---- 5 草：粗草（第 6 層）vs 短草（踩踏／路肩）。林床裡剩下的空隙也是粗草
	# 短草（被踩、被啃）：路肩只是斷斷續續（沿路噪聲切斷），不是沿路一條連續的綠帶
	var mow := maxf(maxf(shoulder * 1.1, edge_band * 0.35) * smoothstep(-0.25, 0.25, pat2 + 0.4 * reg), maxf(earth, float(ft["trodden"])))
	var rr: Array = r3.get("rough", [0.18, 0.62])
	# 粗草成『塊』：門檻窄（邊緣 2–4 m 的過渡），塊內是粗草為主、塊外是安靜的短草——不是整片細碎交錯的斑駁
	var rough := smoothstep(float(rr[0]), float(rr[1]), 0.30 * reg + 0.26 * pat + 0.05 * n_mid - 0.85 * mow - float(r3.get("vil_lawn", 0.40)) * vil3) * float(r3.get("rough_max", 0.9))
	rough = maxf(rough, maxf(maxf(cover * 0.95, sk_soil * 0.85), ub * 0.80 * (1.0 - in_wood)) * road_k)
	var lush := smoothstep(0.02, 0.12, hol) * (1.0 - cover)
	var dry := dry_k * (1.0 - lush)
	# ---- 合成：岩 → 泥 → 礫 → 林床落葉 → 苔地 → 谷壁土袋草 → 裸土 → 粗草 → 短草（剩餘）
	var free := 1.0 - w_rock
	var w_mud := free * mud_p
	free -= w_mud
	var w_grv := free * gravel_p
	free -= w_grv
	var w_lit := free * lit
	free -= w_lit
	var w_mg := free * mg
	free -= w_mg
	var w_l6 := free * leaf_wall
	free -= w_l6
	var w_dirt := free * dirt_p
	free -= w_dirt
	var w_rough := free * rough
	free -= w_rough
	stats["r3_n"] = int(stats.get("r3_n", 0)) + 1
	for kv: Array in [["r3_lit", w_lit], ["r3_mg", w_mg], ["r3_rough", w_rough + w_l6], ["r3_lawn", free], ["r3_dirt", w_dirt], ["r3_mud", w_mud], ["r3_rock", w_rock]]:
		stats[kv[0]] = float(stats.get(kv[0], 0.0)) + float(kv[1])
	var out := PackedFloat32Array()
	out.resize(13)
	out[0] = w_dirt
	out[1] = w_grv
	out[2] = w_mud
	out[3] = w_rock
	out[4] = w_l6 + w_rough
	out[5] = clampf(w_mud * 0.8 + moss * 0.2, 0.0, 1.0)
	out[6] = moss
	out[7] = clampf(off, -16.0, 16.0)
	out[8] = soil
	out[9] = w_lit
	out[10] = w_mg
	out[11] = dry
	out[12] = lush
	return out

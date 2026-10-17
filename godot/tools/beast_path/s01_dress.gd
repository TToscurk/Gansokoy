extends RefCounted
## 獸道 S01 R4 Demo：Blender 環境資產（assets/beast_path/s01_kit，build_s01_kit.py）在 S01 東側的擺放與場景組裝。
## 規則（使用者 2026-10-16「S01 轉 Blender 資產」）：
##   · 只放在 s01_dress.json 的 Demo 區（邊緣用噪聲打散的漸變，不是一條直線截斷）；
##   · 岩／木（個別節點）：設定檔點名的位置；貼地用「資產的地面線以下必須全在地形下」＋各自的下沉量，量測懸空與埋深；
##     玩家走得到且凸出 > 0.45 m 的岩、倒木才有碰撞（凸包）；
##   · 地被（MultiMesh）：依 R3 地表通道（粗草／落葉／苔／乾濕）、樹冠遮蔭、坡度、離路距離、新岩的岩腳環、塊狀噪聲決定接受率——
##     同一類成塊、塊之間留空；不碰撞；草／落葉／苔不投影；
##   · 不改地形高度、不改 380 棵森林規劃、不碰 S02–S04；設定 enabled＝false → generator 不掛 → S01 回到 R3 Stage 1。
const BP := preload("res://tools/beast_path/bp_lib.gd")
const S01Wall := preload("res://tools/beast_path/s01_wall.gd")
const CFG := "res://tools/beast_path/s01_dress.json"
const GLB_DIR := "res://assets/beast_path/s01_kit/glb/"
const MEADOW_SH := "res://assets/village_v2/meadow/meadow_grass.gdshader"
const ROCK_SH := "res://assets/beast_path/s01_kit/mat/s01k_rock.gdshader"
const WOOD_SH := "res://assets/beast_path/s01_kit/mat/s01k_wood.gdshader"
const V2G := "res://assets/village_v2/_matlib/ground/"
const VB := "res://assets/village_v2/veg_kit/tex/"

static var _glb := {}
## 全區美術完成：同一套擺放用在 S02／S03（設定檔的 "scene"；S01 設定檔沒有這個鍵＝"S01"，結果不變）
static var scene_id := "S01"
static var zlib = null
const CATS := ["tall", "short", "fern", "sasa", "shrub", "litter", "moss", "twigs", "forb",
	"grass_tall", "grass_short", "shadegrass", "sedge", "fern_big", "fern_small", "herb", "sapling"]
const S01Floor := preload("res://tools/beast_path/s01_floor.gd")
const SELF_PATH := "res://tools/beast_path/s01_dress.gd"


static func load_cfg() -> Dictionary:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(CFG))
	return d if d is Dictionary else {}


## GLB → 頂點陣列（執行期用 GLTFDocument 讀，不依賴編輯器匯入快取；同 rock_builder.load_hero）
static func glb(name: String) -> Dictionary:
	if _glb.has(name):
		return _glb[name]
	var path := GLB_DIR + name + ".glb"
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(ProjectSettings.globalize_path(path), st) != OK:
		push_error("[dress] 讀不到 %s" % path)
		return {}
	var scn := doc.generate_scene(st)
	var out := {}
	for n in scn.find_children("*", "", true, false):
		var m: Mesh = null
		if n is MeshInstance3D:
			m = (n as MeshInstance3D).mesh
		elif n is ImporterMeshInstance3D:
			m = ((n as ImporterMeshInstance3D).mesh as ImporterMesh).get_mesh()
		if m != null and out.is_empty():
			var a := m.surface_get_arrays(0)
			out = {"V": a[Mesh.ARRAY_VERTEX], "N": a[Mesh.ARRAY_NORMAL], "C": a[Mesh.ARRAY_COLOR], "UV": a[Mesh.ARRAY_TEX_UV], "UV2": a[Mesh.ARRAY_TEX_UV2],
				"I": a[Mesh.ARRAY_INDEX], "aabb": m.get_aabb(), "sha": FileAccess.get_sha256(path)}
	scn.free()
	_glb[name] = out
	return out


# ================================================================= 材質
static func veg_mat(cat0: String, lod: Array) -> ShaderMaterial:
	var cat: String = S01Floor.FAMILY.get(cat0, cat0)
	var m := ShaderMaterial.new()
	m.shader = load(MEADOW_SH)
	m.set_shader_parameter("fade_out", Vector2(float(lod[0]), float(lod[1])))
	if cat == "litter" or cat == "moss" or cat == "twigs":
		m.set_shader_parameter("wind_strength", 0.0)
		m.set_shader_parameter("base_ao", 1.0)
		m.set_shader_parameter("translucency", 0.04)
		m.set_shader_parameter("roughness", 0.93)
		m.set_shader_parameter("specular", 0.18)
		m.set_shader_parameter("far_widen", 0.0)
	elif cat0 == "herb":
		# R5 闊葉草本（蕗／擬寶珠）：葉面大、靠葉色本身的明暗就夠；底部 AO 壓太暗會讀成黑色槳片
		m.set_shader_parameter("gust_amp", 0.03)
		m.set_shader_parameter("flutter_amp", 0.01)
		m.set_shader_parameter("base_ao", 0.88)
		m.set_shader_parameter("far_widen", 0.0)
	elif cat == "shrub" or cat == "sasa" or cat == "forb":
		m.set_shader_parameter("gust_amp", 0.035)
		m.set_shader_parameter("flutter_amp", 0.012)
		m.set_shader_parameter("base_ao", 0.62)
		m.set_shader_parameter("far_widen", 0.0)
	elif cat == "tall" or cat == "short":
		m.set_shader_parameter("far_widen", 0.9)                      # 遠處（26 m 以外）葉寬 ×1.9：TPS 距離仍讀得出草的量
	elif cat == "fern":
		m.set_shader_parameter("gust_amp", 0.045)
		m.set_shader_parameter("base_ao", 0.55)
		m.set_shader_parameter("far_widen", 0.1)
	return m


static func rock_mat() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(ROCK_SH)
	m.set_shader_parameter("albedo_arr", load(V2G + "V2G_albedo.jpg"))
	m.set_shader_parameter("nrh_arr", load(V2G + "V2G_nrh.jpg"))
	m.set_shader_parameter("noise_tex", load(V2G + "V2G_noise.png"))
	m.set_shader_parameter("ground_k", 0.26)
	m.set_shader_parameter("tone", 1.06)            # a7 審圖：新岩比壁面暗太多、像另外放上去的
	return m


static func wood_mat(bark: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(WOOD_SH)
	m.set_shader_parameter("bark_alb", load(VB + "VB_%s_albedo.jpg" % bark))
	m.set_shader_parameter("bark_nrm", load(VB + "VB_%s_normal.jpg" % bark))
	m.set_shader_parameter("noise_tex", load(V2G + "V2G_noise.png"))
	return m


# ================================================================= 場（地表通道等）
class Fields:
	var lib
	var ctx: Dictionary
	var g
	var cache := {}

	func ch(x: float, z: float) -> PackedFloat32Array:
		var ix := int(round(lib._ix(x)))
		var iz := int(round(lib._iz(z)))
		var key := iz * 100000 + ix
		if not cache.has(key):
			cache[key] = g.channels(ix, iz, ctx)
		return cache[key]

	func canopy(x: float, z: float) -> float:
		return lib.sample_arr(ctx["canopy"], x, z)


static func _sstep(e0: float, e1: float, x: float) -> float:
	return smoothstep(e0, e1, x)


static func _noise(seed_: int, freq: float) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed_
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_octaves = 3
	return n


static func zone_w(cfg: Dictionary, p: Vector2, n_edge: FastNoiseLite) -> float:
	var w := 0.0
	if cfg.has("band") and zlib != null:
		# 沿路帶（S02／S03）：離主路／支線路緣 max_m 以內，外緣 fade_m 用噪聲打散（再遠的林內只靠地表＋樹，玩家看不到也不付成本）
		var bd: Dictionary = cfg["band"]
		var de: float = minf(zlib.sample_arr(zlib.DM, p.x, p.y) - zlib.sample_arr(zlib.WM, p.x, p.y), zlib.sample_arr(zlib.DB, p.x, p.y))
		w = _sstep(0.0, 1.0, (float(bd["max_m"]) - de) / float(bd["fade_m"]) + 0.9 * n_edge.get_noise_2d(p.x, p.y))
	for zr: Dictionary in cfg["zones"]:
		var xr: Array = zr["x"]
		var zz: Array = zr["z"]
		var d := minf(minf(p.x - float(xr[0]), float(xr[1]) - p.x), minf(p.y - float(zz[0]), float(zz[1]) - p.y))
		var f := float(zr.get("fade", 5.0))
		w = maxf(w, _sstep(0.0, 1.0, d / f + 0.9 * n_edge.get_noise_2d(p.x, p.y)))
	return w


static func normal_at(lib, x: float, z: float) -> Vector3:
	var gx: float = (lib.h_at(x + 0.5, z) - lib.h_at(x - 0.5, z))
	var gz: float = (lib.h_at(x, z + 0.5) - lib.h_at(x, z - 0.5))
	return Vector3(-gx, 1.0, -gz).normalized()


static func _basis_up(up: Vector3, yaw: float) -> Basis:
	var b := Basis(Vector3.UP, yaw)
	var axis := Vector3.UP.cross(up)
	if axis.length() > 1e-5:
		b = Basis(axis.normalized(), Vector3.UP.angle_to(up)) * b
	return b


# ================================================================= 岩（RockBuilder.build_hero 的頂點色規則；岩腳的環境遮蔽沒那麼黑）
static func rock_colors(lib, V: PackedVector3Array, N: PackedVector3Array, xf: Transform3D, moss_k: float, sd: int, ao_lift: float) -> PackedColorArray:
	var nz1 := FastNoiseLite.new()
	nz1.seed = sd % 100000
	nz1.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	nz1.frequency = 1.0
	var C := PackedColorArray()
	C.resize(V.size())
	for k in V.size():
		var wp := xf * V[k]
		var wn := (xf.basis * N[k]).normalized()
		var above: float = wp.y - float(lib.h_at(wp.x, wp.z))
		var foot := 1.0 - smoothstep(-0.4, 1.1, above)
		var up := clampf((wn.y - 0.25) * 1.7, 0.0, 1.0)
		var moss := clampf(moss_k * (up * (0.55 + 0.9 * nz1.get_noise_3d(wp.x * 0.5 + 3.0, wp.y * 0.4, wp.z * 0.5))) + moss_k * 0.45 * foot, 0.0, 1.0)
		var tint := 0.5 + 0.5 * nz1.get_noise_3d(V[k].x * 0.08 + 9.0, V[k].y * 0.06, V[k].z * 0.08)
		var cav := clampf(0.84 + 0.26 * nz1.get_noise_3d(V[k].x * 0.7 + 21.0, V[k].y * 0.5, V[k].z * 0.7), 0.55, 1.0)
		var ao := cav * lerpf(ao_lift, 1.0, smoothstep(0.0, 1.6, above)) * lerpf(0.80, 1.0, smoothstep(-0.55, 0.15, wn.y))
		C[k] = Color(moss, ao, tint, foot)
	return C


## 依地面線貼地：band＝資產本地 y 低於這個值的頂點（地面線以下＝要埋起來的部分）必須全在地形下 margin；
## bury_frac＞0 → 改用「至少這個比例的頂點在地形下」（沿坡躺的岩肋）。回傳 [需要下降的量, 統計]
static func ground_fit(lib, V: PackedVector3Array, N: PackedVector3Array, xf: Transform3D, band: float, margin: float, bury_frac: float) -> Array:
	if bury_frac > 0.0:
		var lo := 0.0
		var hi := 4.0
		for it in 22:
			var mid := (lo + hi) * 0.5
			var nb := 0
			for k in V.size():
				var wp := xf * V[k]
				if wp.y - mid < float(lib.h_at(wp.x, wp.z)):
					nb += 1
			if float(nb) / float(V.size()) < bury_frac:
				lo = mid
			else:
				hi = mid
		return [hi + margin]
	var drop := -1e9
	for k in V.size():
		if V[k].y > band:
			continue
		var wp := xf * V[k]
		drop = maxf(drop, wp.y - float(lib.h_at(wp.x, wp.z)) + margin)
	return [maxf(drop, 0.0)]


static func contact_stats(lib, V: PackedVector3Array, N: PackedVector3Array, xf: Transform3D) -> Dictionary:
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := -lo
	var below := 0
	var protrude := -1e9
	var under_gap := 0.0
	var under_n := 0
	var pe := 1e9
	for k in V.size():
		var wp := xf * V[k]
		lo = lo.min(wp)
		hi = hi.max(wp)
		var a: float = wp.y - float(lib.h_at(wp.x, wp.z))
		protrude = maxf(protrude, a)
		if a < 0.0:
			below += 1
		else:
			pe = minf(pe, S01Wall.path_edge_d(lib, Vector2(wp.x, wp.z)))
			var wn := (xf.basis * N[k]).normalized()
			if wn.y < -0.5:
				# 朝下的面：沿法線走到地面的距離＝這片底面下真正的空隙
				var t := 0.0
				while t < 3.0:
					t += 0.05
					var q := wp + wn * t
					if q.y <= float(lib.h_at(q.x, q.z)):
						break
				if t > 0.3:
					under_n += 1
				under_gap = maxf(under_gap, t)
	return {"aabb_min": [snappedf(lo.x, 0.01), snappedf(lo.y, 0.01), snappedf(lo.z, 0.01)], "size": [snappedf(hi.x - lo.x, 0.01), snappedf(hi.y - lo.y, 0.01), snappedf(hi.z - lo.z, 0.01)],
		"below_pct": snappedf(100.0 * below / maxf(1.0, V.size()), 0.1), "protrude_m": snappedf(protrude, 0.01), "underside_gap_max_m": snappedf(under_gap, 0.05),
		"underside_verts_gap_gt30cm": under_n, "path_edge_min_m": snappedf(pe, 0.01), "verts": V.size()}


# ================================================================= 規劃
## trees＝S01 森林規劃（forest_planner 的 trees）；foot＝道具腳印；wall＝S01 R2/R3 谷壁岩（fp.s01_wall）；rm＝玩家走得到的格子
static func plan(lib, cfg: Dictionary, F: Fields, trees: Array, foot: Array, wall: Dictionary, rm: Dictionary) -> Dictionary:
	scene_id = String(cfg.get("scene", "S01"))
	zlib = lib
	# （回傳的 cover 每項含 xf／c／cat；bake 腳本可另存點位圖）
	var seed_ := int(cfg.get("seed", 1))
	var clr: Dictionary = cfg["clear"]
	var n_edge := _noise(seed_ + 7, 0.09)
	var trunks: Array = []
	var unders: Array = []
	for t: Dictionary in trees:
		if String(t["scene"]) != scene_id:
			continue
		var tp := Vector2(float(t["x"]), float(t["z"]))
		if String(t["kind"]) == "under":
			unders.append(tp)
		else:
			trunks.append({"p": tp, "r": 0.35 * float(t["s"]), "id": String(t["id"])})
	var wrocks: Array = []
	for r: Dictionary in wall.get("rocks", []):
		wrocks.append({"p": Vector2(float(r["x"]), float(r["z"])), "r": 0.5 * maxf(float(r["w"]), float(r["d"]))})
	var hard: Array = []
	var skipped: Array = []
	var rock_list: Array = (cfg["rocks"] as Array).duplicate()
	if cfg.has("wall_rocks"):
		rock_list.append_array(wall_rock_sites(lib, cfg["wall_rocks"], cfg["rocks"], trunks, wrocks))
	if cfg.has("foot_talus"):
		rock_list.append_array(foot_talus_sites(lib, cfg["foot_talus"], rock_list, trunks))
	# ---- 岩
	for rc: Dictionary in rock_list:
		var a := glb(String(rc["asset"]))
		if a.is_empty():
			continue
		var p := Vector2(float(rc["at"][0]), float(rc["at"][1]))
		var s := float(rc.get("s", 1.0))
		var ab: AABB = a["aabb"]
		var rr := 0.5 * maxf(ab.size.x, ab.size.z) * s
		var why := _hard_clear(lib, clr, p, rr, foot, trunks, wrocks, true)
		if why != "":
			skipped.append({"id": rc["id"], "why": why})
			continue
		var gr := S01Wall.grad(lib, p)
		var dd := (-gr).normalized() if gr.length() > 0.02 else Vector2(-1.0, 0.0)
		var slope := atan(gr.length())
		var bz := Vector3(dd.x, 0.0, dd.y)
		var b := Basis(Vector3.UP.cross(bz).normalized(), Vector3.UP, bz)
		b = Basis(Vector3.UP, deg_to_rad(float(rc.get("yaw_add", 0.0)))) * b
		var lk := float(rc.get("lean_k", 0.3))
		var along := String(rc["asset"]).contains("rib")
		if along:
			# 岩肋：長軸（資產本地 +Y）沿坡面往上坡，離開坡面 rib_out 度（躺在坡上的一道岩脊，不是立在坡上的柱）
			var upd := Vector3(-dd.x, 0.0, -dd.y)
			var el := slope + deg_to_rad(float(rc.get("rib_out", 10.0)))
			var yax := (upd * cos(el) + Vector3.UP * sin(el)).normalized()
			var xax := Vector3.UP.cross(upd).normalized()
			var zax := xax.cross(yax).normalized()
			b = Basis(Vector3.UP, deg_to_rad(float(rc.get("yaw_add", 0.0)))) * Basis(xax, yax, zax)
		else:
			b = Basis(b.x, slope * lk) * b                  # 正＝頂往下坡傾（順著坡面法線）
		b = b.scaled(Vector3.ONE * s)
		var xf := Transform3D(b, Vector3(p.x, lib.h_at(p.x, p.y), p.y))
		var V: PackedVector3Array = a["V"]
		var N: PackedVector3Array = a["N"]
		var is_deb := String(rc["asset"]).contains("debris")
		var bury := float(rc.get("bury", 0.42 if along else (0.55 if is_deb else 0.0)))
		var fit := ground_fit(lib, V, N, xf, 0.06, float(rc.get("sink", 0.1)), bury)
		xf.origin.y -= float(fit[0])
		var st := contact_stats(lib, V, N, xf)
		var reach := S01Wall.reachable(rm, p) or S01Wall.reachable(rm, p + dd * 2.0) or S01Wall.reachable(rm, p + dd * 4.0)
		var collide := reach and float(st["protrude_m"]) > 0.45
		st["drop_m"] = snappedf(float(fit[0]), 0.01)
		st["reachable"] = reach
		st["trunk_clear_m"] = snappedf(_trunk_d(p, trunks) - rr, 0.01)
		hard.append({"id": String(rc["id"]), "kind": "rock", "asset": String(rc["asset"]), "xf": xf, "moss": float(rc.get("moss", 0.5)), "collide": collide, "rr": rr, "p": p, "stats": st,
			"seed": seed_ * 13 + hard.size() * 977})
	# ---- 木
	var wood_list: Array = (cfg["wood"] as Array).duplicate()
	if cfg.has("auto_wood"):
		wood_list.append_array(S01Floor.auto_wood(load(SELF_PATH), lib, cfg, F, trunks, foot, wrocks, wood_list, clr))
	for wc: Dictionary in wood_list:
		var a2 := glb(String(wc["asset"]))
		if a2.is_empty():
			continue
		var s2 := float(wc.get("s", 1.0))
		var ab2: AABB = a2["aabb"]
		var p2: Vector2
		var tree_id := ""
		if wc.has("tree_near"):
			var tn := Vector2(float(wc["tree_near"][0]), float(wc["tree_near"][1]))
			var best := 1e9
			for t2: Dictionary in trunks:
				var dt: float = (t2["p"] as Vector2).distance_to(tn)
				if dt < best:
					best = dt
					p2 = t2["p"]
					tree_id = String(t2["id"])
			if best > 1.5:
				skipped.append({"id": wc["id"], "why": "附近 1.5 m 內沒有樹"})
				continue
		else:
			p2 = Vector2(float(wc["at"][0]), float(wc["at"][1]))
		var asset := String(wc["asset"])
		var is_log := asset.contains("log")
		var is_stump := asset.contains("stump")
		var rr2 := 0.5 * maxf(ab2.size.x, ab2.size.z) * s2
		if is_log or is_stump:
			var why2 := _hard_clear(lib, clr, p2, rr2, foot, trunks, wrocks, false)
			if why2 != "":
				skipped.append({"id": wc["id"], "why": why2})
				continue
		var nrm := normal_at(lib, p2.x, p2.y)
		var b2: Basis
		if is_log:
			var yaw := deg_to_rad(float(wc.get("yaw", 0.0)))
			var dir := Vector2(cos(yaw), -sin(yaw))
			var L := ab2.size.x * s2
			var h0: float = lib.h_at(p2.x - dir.x * L * 0.5, p2.y - dir.y * L * 0.5)
			var h1: float = lib.h_at(p2.x + dir.x * L * 0.5, p2.y + dir.y * L * 0.5)
			var ax := Vector3(dir.x, (h1 - h0) / L, dir.y).normalized()
			var bz2 := ax.cross(Vector3.UP).normalized()
			b2 = Basis(ax, bz2.cross(ax).normalized(), bz2)
		elif wc.has("tree_near"):
			var gr2 := S01Wall.grad(lib, p2)
			var dd2 := (-gr2).normalized() if gr2.length() > 0.02 else Vector2(1.0, 0.0)
			var yaw2 := atan2(-dd2.y, dd2.x) + deg_to_rad(float(wc.get("yaw_add", 0.0)))     # 本地 +X（主根）朝下坡（＋各自的偏轉）
			b2 = _basis_up(Vector3.UP.slerp(nrm, 0.8).normalized(), yaw2)
		else:
			b2 = _basis_up(nrm, deg_to_rad(float(wc.get("yaw", 0.0))))
		b2 = b2.scaled(Vector3.ONE * s2)
		var xf2 := Transform3D(b2, Vector3(p2.x, lib.h_at(p2.x, p2.y), p2.y))
		var V2: PackedVector3Array = a2["V"]
		var N2: PackedVector3Array = a2["N"]
		var band := 0.05 if is_log else (-0.08 if wc.has("tree_near") else 0.02)
		var fit2 := ground_fit(lib, V2, N2, xf2, band, float(wc.get("sink", 0.04)), 0.0)
		xf2.origin.y -= float(fit2[0])
		var st2 := contact_stats(lib, V2, N2, xf2)
		st2["drop_m"] = snappedf(float(fit2[0]), 0.01)
		if tree_id != "":
			st2["tree"] = tree_id
		var reach2 := S01Wall.reachable(rm, p2)
		hard.append({"id": String(wc["id"]), "kind": "wood", "asset": asset, "xf": xf2, "moss": float(wc.get("moss", 0.4)), "collide": (is_log or is_stump) and reach2,
			"rr": rr2 if is_log else 0.6 * rr2, "p": p2, "stats": st2, "ground_y": float(lib.h_at(p2.x, p2.y))})
	# ---- 地被
	if cfg.has("floor"):
		var fl: Dictionary = S01Floor.plan(load(SELF_PATH), lib, cfg, F, trunks, unders, wrocks, foot, hard, clr, seed_)
		return {"hard": hard, "cover": fl["cover"], "counts": fl["counts"], "skipped": skipped, "lod": fl["lod"], "shadow": fl["shadow"]}
	var cover := {}
	var counts := {}
	var cv: Dictionary = cfg["cover"]
	var bb := Rect2()
	var first := true
	for zr: Dictionary in cfg["zones"]:
		var r := Rect2(float(zr["x"][0]), float(zr["z"][0]), float(zr["x"][1]) - float(zr["x"][0]), float(zr["z"][1]) - float(zr["z"][0]))
		bb = r if first else bb.merge(r)
		first = false
	var cats := CATS
	var noises := {}
	for ci in cats.size():
		var c: String = cats[ci]
		noises[c] = _noise(seed_ + 101 * (ci + 1), float((cv[c] as Dictionary)["freq"]))
	var n_var := _noise(seed_ + 991, 0.05)
	noises["comm"] = _noise(seed_ + 555, 0.03)          # 群落尺度（~30 m）：高草地／草本地／短草地互相消長
	var n_warp := _noise(seed_ + 313, 0.04)
	for ci2 in cats.size():
		var c2: String = cats[ci2]
		var cc: Dictionary = cv[c2]
		var sp := float(cc["spacing"])
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_ * 31 + ci2 * 7919
		var assets: Array = cc["assets"]
		# 候選格：每類轉不同角度、整格抖動（不會出現跨類對齊的行列）
		var gr_rot := rng.randf() * TAU
		var gcen := bb.get_center()
		var ext := bb.size.length() * 0.5 + sp
		var x := -ext
		while x < ext:
			var z := -ext
			while z < ext:
				var p3 := gcen + Vector2(x + rng.randf_range(-0.5, 0.5) * sp, z + rng.randf_range(-0.5, 0.5) * sp).rotated(gr_rot)
				var u := rng.randf()
				var yaw3 := rng.randf() * TAU
				var sc := rng.randf_range(float(cc["s"][0]), float(cc["s"][1]))
				var vr := rng.randf()
				z += sp
				if not bb.has_point(p3):
					continue
				var pr := _p_cover(lib, cfg, F, c2, p3, n_edge, noises, n_warp, trunks, unders, wrocks, foot, hard, clr)
				if pr <= 0.0 or u > pr * float(cc["pmax"]):
					continue
				# 同一塊用同一型：變體由低頻噪聲選（不是每叢亂抽）
				var nv := n_var.get_noise_2d(p3.x * 1.0 + ci2 * 37.0, p3.y)
				var ai := 0
				if assets.size() > 1:
					var ch3 := F.ch(p3.x, p3.y)
					if c2 == "tall" and assets.size() >= 3 and ch3[11] > 0.5 and nv > 0.1:
						ai = 2
					elif nv + (vr - 0.5) * 0.5 < -0.05:
						ai = 1
					if c2 == "forb":
						ai = 1 if F.canopy(p3.x, p3.y) > 0.25 else 0       # 車前草型的蓮座只在樹蔭下（開闊處像一顆顆星形）
					ai = mini(ai, assets.size() - 1)
				var an: String = assets[ai]
				var y := float(lib.h_at(p3.x, p3.y))
				var nrm3 := normal_at(lib, p3.x, p3.y)
				var tilt := 1.0 if (c2 == "litter" or c2 == "moss" or c2 == "twigs") else (0.5 if c2 == "fern" else 0.3)
				var sy := sc * (rng.randf_range(0.78, 1.22) if (c2 == "tall" or c2 == "short" or c2 == "fern") else (0.6 if c2 == "moss" else 1.0))
				var upv := Vector3.UP.slerp(nrm3, tilt).normalized()
				if c2 == "tall" or c2 == "forb":
					# 草叢各自歪一點（±8°）：同一個資產的輪廓不會每株都一樣直
					upv = (upv + Vector3(rng.randf_range(-0.14, 0.14), 0.0, rng.randf_range(-0.14, 0.14))).normalized()
				var b3 := _basis_up(upv, yaw3) * Basis.from_scale(Vector3(sc, sy, sc))
				var sink := 0.004 if (c2 == "litter" or c2 == "twigs") else (0.0 if c2 == "moss" else 0.03)
				var col := _tint(F, c2, p3, rng, n_var)
				if not cover.has(an):
					cover[an] = []
				(cover[an] as Array).append({"xf": Transform3D(b3, Vector3(p3.x, y - sink, p3.y)), "c": col, "cat": c2})
				counts[an] = int(counts.get(an, 0)) + 1
			x += sp
	return {"hard": hard, "cover": cover, "counts": counts, "skipped": skipped}


## 谷壁面的岩（不改地形）：在壁面（坡度範圍內）挑點，彼此至少 min_d，避開樹幹／既有谷壁岩／點名的岩；
## 不等距（固定種子亂序＋貪婪）、資產相鄰不同；大部分埋進坡裡（bury），只露出節理面與上緣＝壁面的岩棚／岩脊。
static func wall_rock_sites(lib, wc: Dictionary, named: Array, trunks: Array, wrocks: Array) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(wc.get("seed", 77))
	var xr: Array = wc["x"]
	var zr: Array = wc["z"]
	var sr: Array = wc["slope"]
	var keyed: Array = []
	var x := float(xr[0])
	while x <= float(xr[1]):
		var z := float(zr[0])
		while z <= float(zr[1]):
			var p := Vector2(x + rng.randf_range(-0.5, 0.5), z + rng.randf_range(-0.5, 0.5))
			var key := rng.randf()
			var sl: float = lib.slope_deg_at(p.x, p.y)
			var hy: float = lib.h_at(p.x, p.y)
			var yr: Array = wc.get("y", [-1e9, 1e9])
			if sl >= float(sr[0]) and sl <= float(sr[1]) and hy >= float(yr[0]) and hy <= float(yr[1]) and lib.scene_id_of_z(p.y) == scene_id:
				keyed.append([key, p])
			z += 1.0
		x += 1.0
	keyed.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var assets: Array = wc["assets"]
	var out: Array = []
	var taken: Array = []
	for rcn: Dictionary in named:
		taken.append(Vector2(float(rcn["at"][0]), float(rcn["at"][1])))
	var min_d := float(wc.get("min_d", 7.0))
	var n := int(wc.get("n", 10))
	for kv: Array in keyed:
		if taken.size() - named.size() >= n:          # n＝主岩數（副岩／碎石不算）
			break
		var p3: Vector2 = kv[1]
		var ok := true
		for q: Vector2 in taken:
			if p3.distance_to(q) < min_d:
				ok = false
				break
		if not ok:
			continue
		if _trunk_d(p3, trunks) < 1.8:
			continue
		# 可以與既有（R2/R3 程序）谷壁岩部分重疊：新岩接在舊岩旁＝同一道岩層的延續；只排除幾乎同位置
		var near_w := false
		for w: Dictionary in wrocks:
			if p3.distance_to(w["p"]) < float(w["r"]) * 0.75:
				near_w = true
				break
		if near_w:
			continue
		var ai := rng.randi() % assets.size()
		var nearest := -1
		var nd := 1e9
		for oi in out.size():
			var dd: float = p3.distance_to(Vector2(float(out[oi]["at"][0]), float(out[oi]["at"][1])))
			if dd < nd:
				nd = dd
				nearest = oi
		if nearest >= 0 and String(out[nearest]["asset"]) == String(assets[ai]):
			ai = (ai + 1) % assets.size()
		var sc := rng.randf_range(float(wc["s"][0]), float(wc["s"][1]))
		var wid := "W%d" % (taken.size() - named.size() + 1)  # 主岩編號
		# 同一面壁的節理方向一致：統一的傾角（lean_k）、轉角只有 ±yaw_j
		var yj := float(wc.get("yaw_j", 10.0))
		var lk := float(wc.get("lean_k", 0.6))
		out.append({"id": wid, "asset": String(assets[ai]), "at": [snappedf(p3.x, 0.01), snappedf(p3.y, 0.01)], "lean_k": lk,
			"rib_out": rng.randf_range(6.0, 12.0), "sink": 0.1, "bury": rng.randf_range(float(wc["bury"][0]), float(wc["bury"][1])), "s": sc,
			"yaw_add": rng.randf_range(-yj, yj), "moss": rng.randf_range(0.35, 0.65), "why": "谷壁面的岩組主岩（自動挑點）"})
		# 岩組：沿等高線 1–2 塊較小的岩（同一道岩層露出的其他段）＋下方的崩落碎石（talus）
		var gr := S01Wall.grad(lib, p3)
		var dd := (-gr).normalized() if gr.length() > 0.02 else Vector2(-1.0, 0.0)
		var along := Vector2(-dd.y, dd.x)
		var base_r := 2.2 * sc
		var n_sat := 1 + int(rng.randf() < float(wc.get("p_two", 0.5)))
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		for si in n_sat:
			var off := along * side * base_r * rng.randf_range(0.85, 1.25) + dd * rng.randf_range(-0.4, 0.9)
			side = -side
			var sa: String = wc["sat_assets"][rng.randi() % (wc["sat_assets"] as Array).size()]
			out.append({"id": "%s%s" % [wid, "abc"[si]], "asset": sa, "at": [snappedf(p3.x + off.x, 0.01), snappedf(p3.y + off.y, 0.01)], "lean_k": lk,
				"rib_out": 8.0, "sink": 0.1, "bury": rng.randf_range(float(wc["bury"][0]), float(wc["bury"][1])), "s": sc * rng.randf_range(0.42, 0.62),
				"yaw_add": rng.randf_range(-yj, yj) * 1.5, "moss": rng.randf_range(0.4, 0.7), "why": "岩組的副岩"})
		# 崩落碎石：從岩組沿落水線往下走到坡腳（坡度 < 28°）才放——不放在陡壁面上
		var tp := p3 + along * rng.randf_range(-1.5, 1.5)
		var found := false
		for k in 40:
			tp += dd * 0.5
			if lib.slope_deg_at(tp.x, tp.y) < 28.0:
				found = true
				break
		if not found:
			taken.append(p3)
			continue
		tp += dd * rng.randf_range(0.3, 1.5)
		out.append({"id": wid + "t", "asset": "s01_debris_a", "at": [snappedf(tp.x, 0.01), snappedf(tp.y, 0.01)], "lean_k": 1.0, "sink": 0.02, "bury": 0.5,
			"s": rng.randf_range(0.9, 1.3), "yaw_add": rng.randf_range(0.0, 360.0), "moss": 0.35, "why": "岩組下方的崩落碎石"})
		taken.append(p3)
	return out


## 壁腳的崩落碎石帶（坡度 20–34° 的坡腳）：不等距的碎石／苔石，讓「壁 → 大岩 → 碎石 → 土與草」連起來
static func foot_talus_sites(lib, fc: Dictionary, existing: Array, trunks: Array) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(fc.get("seed", 91))
	var keyed: Array = []
	var x := float(fc["x"][0])
	while x <= float(fc["x"][1]):
		var z := float(fc["z"][0])
		while z <= float(fc["z"][1]):
			var p := Vector2(x + rng.randf_range(-0.5, 0.5), z + rng.randf_range(-0.5, 0.5))
			var key := rng.randf()
			var sl: float = lib.slope_deg_at(p.x, p.y)
			if sl >= float(fc["slope"][0]) and sl <= float(fc["slope"][1]) and lib.scene_id_of_z(p.y) == scene_id:
				keyed.append([key, p])
			z += 1.0
		x += 1.0
	keyed.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var taken: Array = []
	for e: Dictionary in existing:
		taken.append(Vector2(float(e["at"][0]), float(e["at"][1])))
	var out: Array = []
	var assets: Array = fc["assets"]
	for kv: Array in keyed:
		if out.size() >= int(fc["n"]):
			break
		var p3: Vector2 = kv[1]
		var ok := _trunk_d(p3, trunks) > 0.9
		for q: Vector2 in taken:
			if p3.distance_to(q) < float(fc["min_d"]):
				ok = false
				break
		if not ok:
			continue
		var an := String(assets[rng.randi() % assets.size()])
		if an.contains("debris") and lib.slope_deg_at(p3.x, p3.y) > 27.0:
			an = "s01_mossstone_b"                  # 碎石叢是一整塊網格：陡處下坡側的小石會懸空 → 陡處改單顆苔石
		out.append({"id": "T%d" % (out.size() + 1), "asset": an, "at": [snappedf(p3.x, 0.01), snappedf(p3.y, 0.01)],
			"lean_k": 1.0, "sink": 0.03, "bury": 0.5, "s": rng.randf_range(0.8, 1.35), "yaw_add": rng.randf_range(0.0, 360.0), "moss": rng.randf_range(0.4, 0.8), "why": "壁腳的崩落碎石帶"})
		taken.append(p3)
	return out


static func _trunk_d(p: Vector2, trunks: Array) -> float:
	var best := 1e9
	for t: Dictionary in trunks:
		best = minf(best, p.distance_to(t["p"]) - float(t["r"]))
	return best


static func _hard_clear(lib, clr: Dictionary, p: Vector2, rr: float, foot: Array, trunks: Array, wrocks: Array, is_rock: bool) -> String:
	if lib.scene_id_of_z(p.y - rr) != scene_id or lib.scene_id_of_z(p.y + rr) != scene_id:
		return "越過 S01 邊界"
	var de := S01Wall.path_edge_d(lib, p) - rr
	if de < float(clr["hard"]):
		return "離主路路緣 %.2f m（要 ≥ %.1f）" % [de, float(clr["hard"])]
	if lib.sample_arr(lib.DB, p.x, p.y) - rr < float(clr["branch_db"]) or lib.sample_arr(lib.DS, p.x, p.y) - rr < float(clr["stream_ds"]):
		return "離支線／溪太近"
	for f: Dictionary in foot:
		if p.distance_to(f["p"]) < float(f["r"]) + rr * 0.8:
			return "壓到道具腳印 %s" % String(f["id"])
	if _trunk_d(p, trunks) < rr * (0.55 if is_rock else 0.2):
		return "樹幹在岩裡"
	for w: Dictionary in wrocks:
		if p.distance_to(w["p"]) < (float(w["r"]) + rr) * 0.55:
			return "與既有谷壁岩重疊"
	return ""


static func _p_cover(lib, cfg: Dictionary, F: Fields, c: String, p: Vector2, n_edge: FastNoiseLite, noises: Dictionary, n_warp: FastNoiseLite,
		trunks: Array, unders: Array, wrocks: Array, foot: Array, hard: Array, clr: Dictionary) -> float:
	var zw := zone_w(cfg, p, n_edge)
	if zw <= 0.01:
		return 0.0
	if lib.scene_id_of_z(p.y) != scene_id:
		return 0.0
	var de := S01Wall.path_edge_d(lib, p)
	var nv0: float = (noises["twigs"] as FastNoiseLite).get_noise_2d(p.x * 0.7 + 400.0, p.y * 0.7)
	var need := float(clr["low"])
	if c == "tall":
		need = float(clr["tall"])
	elif c == "short":
		need = float(clr["grass"])
	elif c == "fern" or c == "sasa":
		need = float(clr["fern"])
	elif c == "shrub":
		need = float(clr["shrub"])
	# 路緣淨空寬度沿路起伏（a2 審圖：路東側出現一條與路平行的直線邊界）
	need *= 1.0 + 1.3 * maxf(0.0, nv0) + 0.25 * nv0
	if de < need:
		return 0.0
	# 鋪石（PV）：S01 照舊整片不長；S02／S03 的舊石鋪（岔路辻）邊緣讓苔、短草、落葉、草花從石縫長進來（規格：交會區較開闊，但不是公園廣場）
	var pv_max := 0.05
	if scene_id != "S01" and (c == "moss" or c == "litter" or c == "short" or c == "forb" or c == "twigs"):
		pv_max = float(clr.get("paving_low", 0.05))
	if lib.sample_arr(lib.DB, p.x, p.y) < float(clr["branch_db"]) or lib.sample_arr(lib.DS, p.x, p.y) < float(clr["stream_ds"]) or lib.sample_arr(lib.PV, p.x, p.y) > pv_max:
		return 0.0
	for f: Dictionary in foot:
		var q: Vector2 = f["p"]
		if absf(q.y - p.y) < 16.0 and p.distance_to(q) < float(f["r"]) + float(clr["foot_pad"]):
			return 0.0
	var low := c == "litter" or c == "moss" or c == "twigs"
	for t: Dictionary in trunks:
		var tq: Vector2 = t["p"]
		if absf(tq.y - p.y) < 3.0 and p.distance_to(tq) < float(t["r"]) + (0.15 if low else float(clr["trunk"])):
			return 0.0
	if not low:
		for uq: Vector2 in unders:
			if absf(uq.y - p.y) < 2.0 and p.distance_to(uq) < float(clr["under"]):
				return 0.0
	for w: Dictionary in wrocks:
		if p.distance_to(w["p"]) < float(w["r"]) * 0.8 + float(clr["wall_rock_pad"]):
			return 0.0
	var ring := 0.0
	for h: Dictionary in hard:
		var d: float = p.distance_to(h["p"])
		var rr := float(h["rr"])
		if d < rr * (0.92 if low else 0.8):
			return 0.0
		ring = maxf(ring, exp(-pow((d - rr) / 1.4, 2.0)))
	var sl: float = lib.slope_deg_at(p.x, p.y)
	var ch := F.ch(p.x, p.y)
	var dirt := ch[0]
	var rock := maxf(ch[3], smoothstep(48.7, 61.0, sl) * (1.0 - ch[8]))
	var rough := ch[4]
	var lit := ch[9] if ch.size() >= 13 else 0.0
	var mg := ch[10] if ch.size() >= 13 else 0.0
	var dry := ch[11] if ch.size() >= 13 else 0.0
	var lush := ch[12] if ch.size() >= 13 else 0.0
	var soil := ch[8]
	var lawn := clampf(1.0 - (ch[0] + ch[1] + ch[2] + rock + rough + lit + mg), 0.0, 1.0)
	var can := F.canopy(p.x, p.y)
	var shade := smoothstep(0.12, 0.8, can)
	var wallfoot := smoothstep(8.0, 17.0, sl) * (1.0 - smoothstep(40.0, 50.0, sl))
	var face := smoothstep(38.0, 46.0, sl) * (1.0 - soil)
	var near_road := 1.0 - smoothstep(0.5, 4.5, de)
	# 村端→林內：村端（主路起點 z≈+8）較開闊，往南 60 m 林床漸繁（使用者：村端保持開闊、越深入越複雜）
	var depth := clampf((8.0 - p.y) / 60.0, 0.0, 1.0)
	var meadow := (1.0 - shade) * (1.0 - wallfoot) * (1.0 - face)
	# 塊狀噪聲（domain warp）
	var wx := p.x + 7.0 * n_warp.get_noise_2d(p.x, p.y)
	var wz := p.y + 7.0 * n_warp.get_noise_2d(p.x + 71.0, p.y - 33.0)
	var nn: float = (noises[c] as FastNoiseLite).get_noise_2d(wx, wz)
	var comm: float = (noises["comm"] as FastNoiseLite).get_noise_2d(wx, wz)
	var pr := 0.0
	if c == "tall":
		if sl > 42.0 and soil < 0.3 and ring < 0.45:          # 壁面：岩旁（岩棚上、岩腳）可以長
			return 0.0
		var patch := smoothstep(-0.02, 0.22, nn + 0.22 * rough + 0.25 * wallfoot + 0.35 * ring - 0.4 * dirt - 0.12)
		pr = patch * clampf(0.45 + 0.8 * rough + 0.35 * lawn, 0.0, 1.0) * (1.0 - 1.5 * dirt) * (1.0 - 0.55 * shade) * (1.0 - 0.8 * face) * (1.0 - 0.75 * near_road) * (0.5 + 0.5 * depth + 0.4 * wallfoot)
		pr *= 0.45 + 1.1 * smoothstep(-0.25, 0.3, comm)
		pr = maxf(pr, 0.035 * (1.0 - dirt) * (1.0 - face) * (1.0 - shade))          # 塊外零星的株（塊有毛邊，不是一刀切）
	elif c == "short":
		if sl > 44.0 and soil < 0.3:
			return 0.0
		var tallp := smoothstep(-0.02, 0.22, (noises["tall"] as FastNoiseLite).get_noise_2d(wx, wz) + 0.22 * rough + 0.25 * wallfoot - 0.4 * dirt - 0.12)
		var patch2 := smoothstep(-0.2, 0.2, nn + 0.3 * rough - 0.2 * dirt)
		pr = patch2 * clampf(0.3 + 0.9 * rough + 0.45 * lawn + 0.3 * near_road, 0.0, 1.0) * (1.0 - 0.3 * tallp) * (1.0 - 1.2 * dirt) * (1.0 - 0.6 * face)
		pr = maxf(pr, 0.06 * (1.0 - dirt) * (1.0 - face))
	elif c == "fern":
		if sl > (58.0 if (soil > 0.3 or ring > 0.45) else 44.0):
			return 0.0
		var patch3 := smoothstep(-0.10, 0.25, nn + 0.3 * lush + 0.2 * mg + 0.35 * ring + 0.25 * wallfoot)
		pr = patch3 * clampf(0.85 * shade + 0.7 * wallfoot + 0.9 * ring + 0.8 * soil + 0.35 * lush, 0.0, 1.0) * (1.0 - 0.75 * meadow * (1.0 - ring)) * (1.0 - dirt) * (0.45 + 0.55 * maxf(depth, ring))
	elif c == "sasa":
		if sl > 40.0:
			return 0.0
		var patch4 := smoothstep(0.05, 0.30, nn + 0.15 * shade + 0.15 * wallfoot)
		pr = patch4 * clampf(0.8 * shade + 0.8 * wallfoot + 0.4 * ring, 0.0, 1.0) * (1.0 - 0.6 * face) * (1.0 - dirt) * (0.3 + 0.7 * depth)
	elif c == "shrub":
		if sl > 36.0:
			return 0.0
		var edge := smoothstep(0.08, 0.45, can) * (1.0 - smoothstep(1.0, 1.8, can))
		var patch5 := smoothstep(-0.1, 0.25, nn + 0.2 * wallfoot)
		pr = patch5 * clampf(0.9 * edge + 0.8 * wallfoot + 0.5 * ring, 0.0, 1.0) * (1.0 - dirt)
	elif c == "litter":
		if sl > 40.0:
			return 0.0
		var patch6 := smoothstep(-0.25, 0.2, nn + 0.4 * lit)
		pr = patch6 * clampf(1.2 * lit + 0.6 * shade + 0.5 * ring + 0.25 * wallfoot - 0.8 * dirt, 0.0, 1.0) * (0.5 + 0.5 * depth)
	elif c == "moss":
		if sl > 46.0 or (shade < 0.25 and ring < 0.35):      # a7 審圖：開闊草地上的苔墊像綠色石塊 → 只在樹蔭／岩旁
			return 0.0
		var patch7 := smoothstep(-0.05, 0.3, nn + 0.3 * mg + 0.3 * lush)
		pr = patch7 * clampf(1.1 * mg + 0.9 * ch[6] + 0.6 * ring + 0.45 * shade * wallfoot + 0.25 * lush, 0.0, 1.0) * (1.0 - dirt)
	elif c == "forb":
		if sl > 40.0:
			return 0.0
		# 草本：小群落（幾株一起），長在高草塊裡與岩旁；不單株散在草坪上
		var tallp3 := smoothstep(-0.02, 0.22, (noises["tall"] as FastNoiseLite).get_noise_2d(wx, wz) + 0.22 * rough + 0.25 * wallfoot - 0.4 * dirt - 0.12)
		var patch8 := smoothstep(0.18, 0.38, nn + 0.12 * ring)
		pr = patch8 * clampf(0.5 * rough + 0.6 * tallp3 + 0.5 * ring + 0.3 * wallfoot, 0.0, 1.0) * (1.0 - 1.2 * dirt) * (1.0 - 0.6 * near_road) * (0.55 + 0.9 * smoothstep(-0.1, 0.4, -comm))
	elif c == "twigs":
		if sl > 32.0:
			return 0.0
		pr = smoothstep(0.0, 0.3, nn) * clampf(0.8 * shade + 0.3 * ring, 0.0, 1.0) * (1.0 - dirt)
	return clampf(pr * zw, 0.0, 1.0)


## 顏色：各類的基準（a1 審圖：草比地面亮 ~40 %、偏黃 → 壓暗、偏綠）＋塊狀的乾／潤（低頻，不是每叢亂跳）
const BASE_TINT := {"tall": Color(0.64, 0.71, 0.70), "short": Color(0.70, 0.77, 0.75), "fern": Color(0.70, 0.72, 0.74), "sasa": Color(0.80, 0.82, 0.82),
	"shrub": Color(0.82, 0.84, 0.84), "litter": Color(0.92, 0.90, 0.90), "moss": Color(0.62, 0.64, 0.58), "twigs": Color(0.9, 0.9, 0.9), "forb": Color(0.80, 0.82, 0.80)}


static func _tint(F: Fields, c: String, p: Vector2, rng: RandomNumberGenerator, n_var: FastNoiseLite) -> Color:
	var ch := F.ch(p.x, p.y)
	var dry := ch[11] if ch.size() >= 13 else 0.0
	var lush := ch[12] if ch.size() >= 13 else 0.0
	var shade := smoothstep(0.12, 0.8, F.canopy(p.x, p.y))
	var k := rng.randf_range(0.90, 1.06)
	var col: Color = BASE_TINT.get(c, Color(1, 1, 1)) * k
	if c == "tall" or c == "short":
		var pd := clampf(dry * 0.7 + 0.45 * n_var.get_noise_2d(p.x * 0.6 + 50.0, p.y * 0.6), 0.0, 1.0)
		col = col * Color(1, 1, 1).lerp(Color(1.04, 0.98, 0.84), pd * 0.8)
		col = col * Color(1, 1, 1).lerp(Color(0.90, 1.02, 0.92), clampf(lush, 0.0, 1.0))
	return Color(minf(col.r, 1.0), minf(col.g, 1.0), minf(col.b, 1.0), 1.0)


# ================================================================= 組裝場景
static func build(lib, cfg: Dictionary, P: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "S01Dress"
	var rocks := Node3D.new()
	rocks.name = "Rocks"
	root.add_child(rocks)
	var wood := Node3D.new()
	wood.name = "Wood"
	root.add_child(wood)
	var cover := Node3D.new()
	cover.name = "Cover"
	root.add_child(cover)
	var rmat := rock_mat()
	var wmats := {"log": wood_mat("dead"), "root": wood_mat("hackberry"), "branch": wood_mat("dead")}
	var wmesh := {}
	var ncol := 0
	for h: Dictionary in P["hard"]:
		var a := glb(String(h["asset"]))
		var holder := Node3D.new()
		holder.name = String(h["id"]) + "_" + String(h["asset"]).trim_prefix("s01_")
		holder.transform = h["xf"]
		holder.set_meta("s01_dress", String(h["asset"]))
		var mi := MeshInstance3D.new()
		mi.name = "Mesh"
		if String(h["kind"]) == "rock":
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = a["V"]
			arrays[Mesh.ARRAY_NORMAL] = a["N"]
			arrays[Mesh.ARRAY_COLOR] = rock_colors(lib, a["V"], a["N"], h["xf"], float(h["moss"]), int(h["seed"]), 0.88)
			arrays[Mesh.ARRAY_INDEX] = a["I"]
			var m := ArrayMesh.new()
			m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			m.surface_set_material(0, rmat)
			mi.mesh = m
			rocks.add_child(holder)
		else:
			var an := String(h["asset"])
			if not wmesh.has(an):
				var arr2 := []
				arr2.resize(Mesh.ARRAY_MAX)
				arr2[Mesh.ARRAY_VERTEX] = a["V"]
				arr2[Mesh.ARRAY_NORMAL] = a["N"]
				arr2[Mesh.ARRAY_COLOR] = a["C"]
				arr2[Mesh.ARRAY_TEX_UV] = a["UV"]
				arr2[Mesh.ARRAY_INDEX] = a["I"]
				var m0 := ArrayMesh.new()
				m0.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr2)
				var stl := SurfaceTool.new()
				stl.create_from(m0, 0)
				stl.generate_tangents()
				var m1 := stl.commit()
				m1.surface_set_material(0, wmats["log" if an.contains("log") else ("root" if an.contains("root") else "branch")])
				wmesh[an] = m1
			mi.mesh = wmesh[an]
			mi.set_instance_shader_parameter("moss_k", float(h["moss"]))
			mi.set_instance_shader_parameter("ground_y", float(h.get("ground_y", (h["xf"] as Transform3D).origin.y)))
			wood.add_child(holder)
		holder.add_child(mi)
		if bool(h["collide"]):
			var body := StaticBody3D.new()
			body.name = "Body"
			var cs := CollisionShape3D.new()
			cs.name = "Shape"
			cs.shape = mi.mesh.create_convex_shape(true, true)
			body.add_child(cs)
			holder.add_child(body)
			ncol += 1
	# ---- 地被：每種 × 每 chunk 一個 MultiMesh
	var lod: Dictionary = P["lod"] if P.has("lod") else cfg["lod"]
	var shadow_list: Array = P["shadow"] if P.has("shadow") else cfg["lod"]["shadow"]
	var chunk := float((cfg["floor"] as Dictionary).get("chunk_m", 16.0)) if cfg.has("floor") else float(cfg["lod"].get("chunk_m", 16.0))
	var n_lod1 := 0
	var vmeshes := {}
	var n_items := 0
	var n_nodes := 0
	for an2: String in (P["cover"] as Dictionary):
		var items: Array = P["cover"][an2]
		if items.is_empty():
			continue
		var cat: String = items[0]["cat"]
		# lod：R4＝[淡出起, 淡出終]；R5 林床＝[換 LOD1 的距離, 淡出起, 淡出終]（0＝沒有 LOD1）
		var L: Array = lod[cat]
		var fade: Array = [L[L.size() - 2], L[L.size() - 1]]
		var sw := float(L[0]) if L.size() == 3 else 0.0
		var lod1_name := an2 + "_lod1"
		var has_lod1 := sw > 0.0 and FileAccess.file_exists(GLB_DIR + lod1_name + ".glb")
		if not vmeshes.has(an2):
			var vmat := veg_mat(cat, fade)
			for nm: String in ([an2, lod1_name] if has_lod1 else [an2]):
				var a2 := glb(nm)
				var arr3 := []
				arr3.resize(Mesh.ARRAY_MAX)
				arr3[Mesh.ARRAY_VERTEX] = a2["V"]
				arr3[Mesh.ARRAY_NORMAL] = a2["N"]
				arr3[Mesh.ARRAY_COLOR] = a2["C"]
				arr3[Mesh.ARRAY_TEX_UV] = a2["UV"]
				arr3[Mesh.ARRAY_TEX_UV2] = a2["UV2"]
				arr3[Mesh.ARRAY_INDEX] = a2["I"]
				var mv := ArrayMesh.new()
				mv.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr3)
				mv.surface_set_material(0, vmat)
				vmeshes[nm] = mv
		var buckets := {}
		for it: Dictionary in items:
			var o: Vector3 = (it["xf"] as Transform3D).origin
			var key := "%d_%d" % [int(floor(o.x / chunk)), int(floor(o.z / chunk))]
			if not buckets.has(key):
				buckets[key] = []
			(buckets[key] as Array).append(it)
		for key2: String in buckets:
			var its: Array = buckets[key2]
			# 近級（全網格）與遠級（LOD1）用同一組 instance；以 chunk 的 AABB 中心距離切換（margin 0＝沒有遲滯，冷啟動也不會兩級都不顯示）
			for lv in (2 if has_lod1 else 1):
				var mm := MultiMesh.new()
				mm.transform_format = MultiMesh.TRANSFORM_3D
				mm.use_colors = true
				mm.mesh = vmeshes[an2 if lv == 0 else lod1_name]
				mm.instance_count = its.size()
				for k in its.size():
					mm.set_instance_transform(k, its[k]["xf"])
					mm.set_instance_color(k, its[k]["c"])
				var mmi := MultiMeshInstance3D.new()
				mmi.name = "%s_%s%s" % [an2.trim_prefix("s01_"), key2, "" if lv == 0 else "_lod1"]
				mmi.multimesh = mm
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if (shadow_list.has(cat) and lv == 0) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				if has_lod1 and lv == 0:
					mmi.visibility_range_end = sw
				else:
					mmi.visibility_range_begin = sw if lv == 1 else 0.0
					mmi.visibility_range_end = float(fade[1]) + chunk * 0.75
				mmi.visibility_range_begin_margin = 0.0
				mmi.visibility_range_end_margin = 0.0
				cover.add_child(mmi)
				n_nodes += 1
				if lv == 1:
					n_lod1 += 1
			n_items += its.size()
	root.set_meta("hard", (P["hard"] as Array).size())
	root.set_meta("collide", ncol)
	root.set_meta("items", n_items)
	root.set_meta("mm_nodes", n_nodes)
	root.set_meta("mm_lod1_nodes", n_lod1)
	for n in root.find_children("*", "", true, false):
		n.owner = root
	return root

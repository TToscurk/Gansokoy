extends RefCounted
## P10 R5c World Boundary Closure（使用者 2026-10-09 D2 APPROVED：frame 外 Vista＋林帶自然收邊，P1 主地形與現有碰撞不動）。
## 產出 overlay `EdgeClosureP10`（maps/village_v2/gen/edge_closure_p10.scn，掛 root、HumanUseExpansionP10 之後）：
##   VistaTerrain  frame 外 0–700 m 的遠景地形（tensor 格：frame 邊 2 m 與 P1 頂點逐點重合 → 接縫無縫；向外逐步加寬）
##                  近：延續邊緣坡度與地面權重 → 中：丘陵 → 遠：環狀山脊（≥ 70 m，高於村內任何可達視點）
##   VistaWater    主河（北入／東出）、水渠與西渠（南出）延續到遠景；水渠與西渠匯入「南の川」，南の川東流與主河於遠景會合
##   VistaPaths    獸道（入口道路南延）、東側田埂道延伸（只寫地面權重，無獨立網格）
##   VistaTrees    近帶樹（veg_kit 樹庫 LOD0–3 MultiMesh，樹種依方位）＋遠山林冠（VistaCanopy，頂點色起伏面）
## 全部無碰撞（玩家仍由 Collision/Boundary 擋）。地面 shader 共用 P7 ground.gdshader（材質由場景 MainTerrain 複製），水面材質複製 Water/MainRiver。
## generator＝source of truth；plan() 為純函數（同 seed 同結果），build() 只把 plan 變成節點。

const NODE_NAME := "EdgeClosureP10"
const OUTPUT := "res://maps/village_v2/gen/edge_closure_p10.scn"
const PLAN_JSON := "res://data/village_v2_p10r5c_edge_plan.json"
const ART_REVISION := "P10 R5c r5：效能：遠帶樹減密、LOD3 ≤ 360 m、只 LOD0 投影；林冠貼實際地形網格、遠景格距 ≤ 37 m；林冠獨立 8 m 均勻格、水面頂點色依實際水深（與 P2 同規則）；frame 外 Vista 地形＋水系延續（岸線不規則）＋近帶樹延到 176 m＋遠山林冠（暗色叢塊）（ART_REVIEW）"
const FX0 := 0.0
const FX1 := 560.0
const FZ0 := -340.0
const FZ1 := 220.0
const STEP := 2.0
const SEED := 50109
## frame 外的格距列（m，離 frame 邊的距離）。近處 2 m（與 P1 一致），外圍逐步加寬。
const D_LIST := [2.0, 4.0, 6.0, 8.0, 10.0, 12.0, 14.0, 16.0, 18.0, 20.0, 23.0, 26.0, 30.0, 34.0, 38.0, 43.0, 48.0, 54.0, 60.0,
	67.0, 75.0, 84.0, 94.0, 105.0, 117.0, 130.0, 145.0, 162.0, 180.0, 200.0, 220.0, 240.0, 262.0, 285.0, 310.0, 335.0, 362.0,
	390.0, 420.0, 450.0, 482.0, 515.0, 550.0, 586.0, 622.0, 660.0, 700.0]
## 各方位：mid＝丘陵高（相對 0 m）、d1＝[開始, 完成] 爬升到 mid 的距離帶、rim＝外環山脊高、tree＝近帶樹密度係數
const SIDES := {
	"N": {"mid": 58.0, "d1": [14.0, 200.0], "rim": 125.0, "tree": 0.55, "mix": "mountain"},
	"W": {"mid": 52.0, "d1": [12.0, 180.0], "rim": 105.0, "tree": 0.55, "mix": "mountain"},
	"E": {"mid": 12.0, "d1": [45.0, 230.0], "rim": 78.0, "tree": 0.32, "mix": "east"},
	"S": {"mid": 20.0, "d1": [22.0, 190.0], "rim": 82.0, "tree": 0.62, "mix": "south"},
}
const RIM_BAND := [300.0, 660.0]
const NEAR_SLOPE_D := 9.0          # 邊緣坡度延續的衰減距離（m）
const SEAM_BLEND_D := 14.0         # 地面權重：從 P1 邊緣頂點權重過渡到遠景權重的距離（m）
## 水系延續（frame 邊 → 外）：level＝[起點, 終點] 水面高；flow＝"out"（離開 frame 流向外）或 "in"（從外流入 frame）
const WATERS := [
	{"name": "RiverNorth", "pts": [[392.0, -340.0], [389.5, -372.0], [381.0, -410.0], [386.0, -452.0], [402.0, -490.0], [418.0, -532.0], [409.0, -585.0], [388.0, -640.0], [371.0, -700.0], [362.0, -760.0]],
		"hw": [6.5, 5.0], "level": [-0.8, 3.0], "depth": 2.4, "flow": "in", "valley": [26.0, 0.18]},
	{"name": "RiverEast", "pts": [[560.0, -112.0], [600.0, -108.0], [640.0, -99.0], [676.0, -81.0], [706.0, -54.0], [730.0, -18.0], [746.0, 32.0], [758.0, 92.0], [770.0, 150.0], [790.0, 210.0], [815.0, 280.0]],
		"hw": [15.0, 16.0], "level": [-0.8, -3.3], "depth": 2.4, "flow": "out", "valley": [40.0, 0.22]},
	{"name": "CanalSouth", "pts": [[288.0, 220.0], [287.0, 248.0], [285.5, 276.0], [289.0, 300.0], [293.0, 318.0]],
		"hw": [3.0, 3.0], "level": [-1.63, -2.25], "depth": 0.8, "flow": "out", "valley": [10.0, 0.15]},
	{"name": "StreamSouth", "pts": [[122.0, 220.0], [121.0, 246.0], [125.5, 272.0], [131.0, 296.0], [136.0, 316.0]],
		"hw": [1.6, 1.9], "level": [-1.19, -2.05], "depth": 0.9, "flow": "out", "valley": [8.0, 0.15]},
	{"name": "SouthRiver", "pts": [[-160.0, 336.0], [-60.0, 326.0], [40.0, 322.0], [136.0, 318.0], [214.0, 324.0], [293.0, 320.0], [370.0, 312.0], [452.0, 300.0], [530.0, 292.0], [610.0, 282.0], [686.0, 262.0], [744.0, 232.0], [790.0, 210.0]],
		"hw": [7.0, 9.5], "level": [-1.95, -2.95], "depth": 1.6, "flow": "path", "valley": [30.0, 0.2]},
]
## 小徑延續（只寫地面權重）：hw＝半寬（m），fade＝[開始淡出, 結束] 沿線距離
const PATHS := [
	{"name": "BeastPath", "pts": [[222.0, 220.0], [218.0, 246.0], [208.0, 272.0], [197.0, 298.0], [186.0, 324.0]], "hw": 1.5, "fade": [70.0, 110.0], "w": 0.85},
	{"name": "FarmEast0", "pts": [[556.0, 0.0], [600.0, 2.0], [642.0, -3.0]], "hw": 1.2, "fade": [50.0, 86.0], "w": 0.7},
	{"name": "FarmEast70", "pts": [[556.0, 70.0], [604.0, 72.0], [648.0, 66.0]], "hw": 1.2, "fade": [50.0, 92.0], "w": 0.7},
]
## 樹種組合（veg_kit 樹庫 id：權重）
const MIXES := {
	"mountain": {"sugi_a": 18, "sugi_c": 16, "akamatsu_a": 10, "konara_a": 14, "konara_b": 10, "shii_a": 10},
	"south": {"konara_a": 16, "konara_b": 14, "shii_a": 12, "enoki_a": 10, "sugi_c": 12, "akamatsu_a": 8, "young_broad_a": 6},
	"east": {"keyaki_a": 18, "enoki_a": 12, "konara_b": 12, "sugi_c": 16, "shii_a": 8, "young_broad_a": 8},
	"water": {"yanagi_a": 34, "enoki_a": 18, "konara_b": 14, "young_broad_a": 12},
}
const PRESET_W := {"mature": 62, "deep": 38}
const TREE_CELL := 7.0
const TREE_D := [4.5, 176.0]
const TREE_MAX := 3600
const CANOPY_D0 := 108.0           # 遠山林冠開始（離 frame）；之前是實樹帶
const CANOPY_D1 := 160.0           # 林冠完全升起
const CANOPY_H := [9.0, 15.0]
const CHUNK_NEAR := 112.0
const CHUNK_FAR := 280.0
const TREE_EMBED := 0.08
const WATER_SHALLOW := Color(0.30, 0.56, 0.68, 0.62)
const WATER_DEEP := Color(0.10, 0.27, 0.46, 0.93)
const ALBEDO_K := 0.42

const FLib := preload("res://tools/village_v2_forest_lib.gd")
const TreeLib := preload("res://tools/village_v2_veg_lib.gd")


static func _noise(seed_v: int, freq: float, oct := 4) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed_v
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = oct
	return n


static func inside(p: Vector2) -> bool:
	return p.x > FX0 and p.x < FX1 and p.y > FZ0 and p.y < FZ1


## 離 frame 的距離（frame 內為 0）與最近的 frame 點
static func frame_near(p: Vector2) -> Vector2:
	return Vector2(clampf(p.x, FX0, FX1), clampf(p.y, FZ0, FZ1))


## 方位權重（frame 外的點）：邊的正外側＝該邊 1；角落依方向在兩邊之間平滑分配
static func side_w(p: Vector2) -> Dictionary:
	var e := frame_near(p)
	var d := p - e
	var w := {"N": 0.0, "W": 0.0, "E": 0.0, "S": 0.0}
	if d.length() < 1e-4:
		# 落在邊上：看是哪條邊
		if absf(p.y - FZ0) < 1e-3:
			w["N"] = 1.0
		elif absf(p.y - FZ1) < 1e-3:
			w["S"] = 1.0
		elif absf(p.x - FX0) < 1e-3:
			w["W"] = 1.0
		else:
			w["E"] = 1.0
		return w
	var ax := absf(d.x)
	var az := absf(d.y)
	var tx := ax / (ax + az)
	var tz := 1.0 - tx
	# 平滑：tx^2/(tx^2+tz^2)
	var sx := tx * tx / (tx * tx + tz * tz)
	var sz := 1.0 - sx
	if d.x < 0.0:
		w["W"] += sx
	elif d.x > 0.0:
		w["E"] += sx
	if d.y < 0.0:
		w["N"] += sz
	elif d.y > 0.0:
		w["S"] += sz
	var s := 0.0
	for k in w:
		s += float(w[k])
	for k in w:
		w[k] = float(w[k]) / maxf(s, 1e-6)
	return w


static func _seg_near(pts: PackedVector2Array, cum: PackedFloat32Array, p: Vector2) -> Vector2:
	## 回傳 (距離, 沿線距離 s)
	var best := INF
	var bs := 0.0
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
		var d := p.distance_to(a + ab * t)
		if d < best:
			best = d
			bs = cum[i] + ab.length() * t
	return Vector2(best, bs)


static func _poly(a: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for q in a:
		out.append(Vector2(float(q[0]), float(q[1])))
	return out


static func _cum(pts: PackedVector2Array) -> PackedFloat32Array:
	var c := PackedFloat32Array([0.0])
	for i in range(1, pts.size()):
		c.append(c[i - 1] + pts[i - 1].distance_to(pts[i]))
	return c


static func _ss(e0: float, e1: float, x: float) -> float:
	if e1 <= e0:
		return 1.0 if x >= e1 else 0.0
	var t := clampf((x - e0) / (e1 - e0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## ─────────── P1 邊緣取樣：高度（地形碰撞射線）＋頂點權重／法線（地形網格陣列） ───────────
static func edge_data(v: Node3D) -> Dictionary:
	var space := v.get_world_3d().direct_space_state
	var trid := (v.get_node("Collision/TerrainCollision") as CollisionObject3D).get_rid()
	var hfn := func(x: float, z: float) -> float:
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, 200.0, z), Vector3(x, -60.0, z))
		var ex: Array[RID] = []
		for k in 24:
			q.exclude = ex
			var h := space.intersect_ray(q)
			if h.is_empty():
				return NAN
			if h["rid"] == trid:
				return float(h["position"].y)
			ex.append(h["rid"])
		return NAN
	# 地形網格頂點（frame 邊上的）：權重與法線
	var vtx := {}
	for t in v.get_node("Terrain").get_children():
		if not (t is MeshInstance3D):
			continue
		var arr: Array = (t as MeshInstance3D).mesh.surface_get_arrays(0)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var cs: PackedColorArray = arr[Mesh.ARRAY_COLOR] if arr[Mesh.ARRAY_COLOR] != null else PackedColorArray()
		var u1: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV] if arr[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		var u2: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2] if arr[Mesh.ARRAY_TEX_UV2] != null else PackedVector2Array()
		var xf := (t as MeshInstance3D).global_transform
		for i in vs.size():
			var w := xf * vs[i]
			var onb := absf(w.x - FX0) < 0.01 or absf(w.x - FX1) < 0.01 or absf(w.z - FZ0) < 0.01 or absf(w.z - FZ1) < 0.01
			if not onb:
				continue
			var key := Vector2i(roundi(w.x), roundi(w.z))
			if vtx.has(key):
				continue
			vtx[key] = {"y": w.y, "n": ns[i] if i < ns.size() else Vector3.UP,
				"c": cs[i] if i < cs.size() else Color(0, 0, 0, 0),
				"u1": u1[i] if i < u1.size() else Vector2.ZERO, "u2": u2[i] if i < u2.size() else Vector2.ZERO}
	# 四邊每 2 m：高度（優先網格頂點 y，否則射線）、向外坡度（邊上 vs 內 6 m）
	var edges := {}
	for side in ["N", "S", "W", "E"]:
		var arr := []
		var n := int(round((FX1 - FX0) / STEP)) if side in ["N", "S"] else int(round((FZ1 - FZ0) / STEP))
		for k in n + 1:
			var p: Vector2
			var inw: Vector2
			match side:
				"N":
					p = Vector2(FX0 + k * STEP, FZ0)
					inw = Vector2(0, 1)
				"S":
					p = Vector2(FX0 + k * STEP, FZ1)
					inw = Vector2(0, -1)
				"W":
					p = Vector2(FX0, FZ0 + k * STEP)
					inw = Vector2(1, 0)
				_:
					p = Vector2(FX1, FZ0 + k * STEP)
					inw = Vector2(-1, 0)
			var key := Vector2i(roundi(p.x), roundi(p.y))
			var y: float
			var info: Dictionary = vtx.get(key, {})
			if not info.is_empty():
				y = float(info["y"])
			else:
				y = hfn.call(p.x + inw.x * 0.01, p.y + inw.y * 0.01)
			var yin: float = hfn.call(p.x + inw.x * 6.0, p.y + inw.y * 6.0)
			var g := 0.0 if (is_nan(y) or is_nan(yin)) else (y - yin) / 6.0
			arr.append({"p": p, "y": y, "g": clampf(g, -0.45, 0.7), "info": info})
		edges[side] = arr
	return {"edges": edges, "vtx_found": vtx.size(), "hfn": hfn}


## frame 邊上任一點的高度／坡度／權重（線性內插相鄰 2 m 取樣）
static func edge_at(E: Dictionary, e: Vector2) -> Dictionary:
	var side := ""
	var s := 0.0
	if absf(e.y - FZ0) < 1e-3:
		side = "N"
		s = (e.x - FX0) / STEP
	elif absf(e.y - FZ1) < 1e-3:
		side = "S"
		s = (e.x - FX0) / STEP
	elif absf(e.x - FX0) < 1e-3:
		side = "W"
		s = (e.y - FZ0) / STEP
	else:
		side = "E"
		s = (e.y - FZ0) / STEP
	var arr: Array = E["edges"][side]
	var i0 := clampi(floori(s), 0, arr.size() - 1)
	var i1 := clampi(i0 + 1, 0, arr.size() - 1)
	var t := clampf(s - i0, 0.0, 1.0)
	var a: Dictionary = arr[i0]
	var b: Dictionary = arr[i1]
	return {"y": lerpf(float(a["y"]), float(b["y"]), t), "g": lerpf(float(a["g"]), float(b["g"]), t), "a": a, "b": b, "t": t, "side": side}


## ─────────── 高度場（frame 外） ───────────
static func make_ctx(E: Dictionary, prm := {}) -> Dictionary:
	var C := {"E": E, "prm": prm}
	C["n_hill"] = _noise(SEED + 1, 0.0065, 5)
	C["n_rim"] = _noise(SEED + 2, 0.0042, 4)
	C["n_fine"] = _noise(SEED + 3, 0.03, 3)
	C["n_tree"] = _noise(SEED + 4, 0.018, 3)
	C["n_can"] = _noise(SEED + 5, 0.05, 2)
	C["n_path"] = _noise(SEED + 6, 0.11, 2)
	C["n_bank"] = _noise(SEED + 8, 0.045, 3)
	C["n_clump"] = _noise(SEED + 9, 0.16, 2)
	var waters := []
	for w: Dictionary in WATERS:
		var pts := _poly(w["pts"])
		waters.append({"def": w, "pts": pts, "cum": _cum(pts)})
	C["waters"] = waters
	var paths := []
	for pd: Dictionary in PATHS:
		var pts := _poly(pd["pts"])
		paths.append({"def": pd, "pts": pts, "cum": _cum(pts)})
	C["paths"] = paths
	return C


static func water_level(W: Dictionary, s: float) -> float:
	var total: float = (W["cum"] as PackedFloat32Array)[(W["cum"] as PackedFloat32Array).size() - 1]
	var lv: Array = W["def"]["level"]
	return lerpf(float(lv[0]), float(lv[1]), clampf(s / maxf(total, 1.0), 0.0, 1.0))


static func water_hw(W: Dictionary, s: float) -> float:
	var total: float = (W["cum"] as PackedFloat32Array)[(W["cum"] as PackedFloat32Array).size() - 1]
	var hw: Array = W["def"]["hw"]
	return lerpf(float(hw[0]), float(hw[1]), clampf(s / maxf(total, 1.0), 0.0, 1.0))


## frame 外一點的「未刻水道」地形高與方位資訊
static func base_h(C: Dictionary, p: Vector2) -> float:
	var e := frame_near(p)
	var d := p.distance_to(e)
	var ed := edge_at(C["E"], e)
	var h_seam: float = ed["y"]
	var g: float = ed["g"]
	var near := h_seam + g * NEAR_SLOPE_D * (1.0 - exp(-d / NEAR_SLOPE_D))
	var sw := side_w(p)
	var mid := 0.0
	var rim := 0.0
	var d1a := 0.0
	var d1b := 0.0
	var prm: Dictionary = C["prm"]
	for k in sw:
		var S: Dictionary = SIDES[k]
		var wk := float(sw[k])
		mid += wk * float(prm.get("mid_" + k, S["mid"]))
		rim += wk * float(prm.get("rim_" + k, S["rim"]))
		d1a += wk * float(S["d1"][0])
		d1b += wk * float(S["d1"][1])
	var nh: float = (C["n_hill"] as FastNoiseLite).get_noise_2d(p.x, p.y)
	var nr: float = (C["n_rim"] as FastNoiseLite).get_noise_2d(p.x, p.y)
	var hill := maxf(mid + nh * (6.0 + mid * 0.35), h_seam + 4.0)
	var s1 := _ss(d1a, d1b, d)
	var h := lerpf(near, hill, s1)
	var s2 := _ss(float(RIM_BAND[0]), float(RIM_BAND[1]), d)
	var rim_h := rim + nr * rim * 0.22
	h = lerpf(h, maxf(h, rim_h), s2)
	h += (C["n_fine"] as FastNoiseLite).get_noise_2d(p.x, p.y) * 1.2 * _ss(10.0, 80.0, d)
	return h


## 刻水道後的高度＋水體資訊（最近水體的距離、水位、半寬、權重）
static func vista_h(C: Dictionary, p: Vector2) -> Dictionary:
	var e := frame_near(p)
	var d := p.distance_to(e)
	var h := base_h(C, p)
	var wet := 0.0
	var near_w := {}
	var best_c := INF
	for W: Dictionary in C["waters"]:
		var r := _seg_near(W["pts"], W["cum"], p)
		var c := r.x
		var s := r.y
		var hw := water_hw(W, s) * (1.0 + 0.24 * (C["n_bank"] as FastNoiseLite).get_noise_1d(s + float(W["def"]["hw"][0]) * 37.0))
		var lv := water_level(W, s)
		var vd: Array = W["def"]["valley"]
		var vw := float(vd[0]) + float(vd[1]) * d
		if c > hw + vw + 2.0:
			continue
		var depth := float(W["def"]["depth"])
		var bed: float
		if c < hw:
			bed = lv - depth * (1.0 - (c / hw) * (c / hw)) - 0.15
		else:
			# 岸：水線上 0.35 m 起，向外以約 1:3 坡升到 valley 寬，之後回到地形
			bed = lv + 0.3 + (c - hw) * 0.33 * (1.0 + 0.6 * (C["n_bank"] as FastNoiseLite).get_noise_2d(p.x * 3.0, p.y * 3.0))
		var wcarve := _ss(hw + vw * 0.55, hw + vw, c)
		var hc := lerpf(minf(bed, h), h, wcarve)
		# frame 邊上（d < 3 m）保持 P1 高度：刻道權重隨 d 淡入
		var fade := _ss(0.0, 5.0, d)
		h = lerpf(h, hc, fade) if hc < h else h
		if c < best_c:
			best_c = c
			near_w = {"name": W["def"]["name"], "c": c, "hw": hw, "lv": lv}
		wet = maxf(wet, 1.0 - _ss(hw, hw + 4.0, c))
	return {"h": h, "d": d, "water": near_w, "wet": wet}


## ─────────── 小徑權重 ───────────
static func path_w(C: Dictionary, p: Vector2) -> float:
	var w := 0.0
	for P: Dictionary in C["paths"]:
		var r := _seg_near(P["pts"], P["cum"], p)
		var hw := float(P["def"]["hw"]) * (1.0 + 0.35 * (C["n_path"] as FastNoiseLite).get_noise_2d(p.x, p.y))
		var fd: Array = P["def"]["fade"]
		var f := 1.0 - _ss(float(fd[0]), float(fd[1]), r.y)
		var k := (1.0 - _ss(hw * 0.6, hw + 0.9, r.x)) * f * float(P["def"]["w"])
		w = maxf(w, k)
	return w


## ─────────── 格 ───────────
static func axes() -> Array:
	var xs := PackedFloat32Array()
	var zs := PackedFloat32Array()
	for i in range(D_LIST.size() - 1, -1, -1):
		xs.append(FX0 - float(D_LIST[i]))
		zs.append(FZ0 - float(D_LIST[i]))
	var n := int(round((FX1 - FX0) / STEP))
	for k in n + 1:
		xs.append(FX0 + k * STEP)
	n = int(round((FZ1 - FZ0) / STEP))
	for k in n + 1:
		zs.append(FZ0 + k * STEP)
	for dd in D_LIST:
		xs.append(FX1 + float(dd))
		zs.append(FZ1 + float(dd))
	return [xs, zs]


static func _pick(rng: RandomNumberGenerator, w: Dictionary) -> String:
	var tot := 0
	var keys := w.keys()
	keys.sort()
	for k in keys:
		tot += int(w[k])
	var r := rng.randi_range(1, tot)
	for k in keys:
		r -= int(w[k])
		if r <= 0:
			return String(k)
	return String(keys[0])


## ─────────── plan（純函數） ───────────
static func plan(v: Node3D, prm := {}) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var E := edge_data(v)
	var C := make_ctx(E, prm)
	var ax := axes()
	var xs: PackedFloat32Array = ax[0]
	var zs: PackedFloat32Array = ax[1]
	var nxv := xs.size()
	var nzv := zs.size()
	# 全格高度（frame 內＝P1 地形射線；frame 外＝vista）
	var hgrid := PackedFloat32Array()
	hgrid.resize(nxv * nzv)
	var info := []
	info.resize(nxv * nzv)
	var hfn: Callable = E["hfn"]
	for j in nzv:
		for i in nxv:
			var p := Vector2(xs[i], zs[j])
			var k := j * nxv + i
			if inside(p):
				var y: float = hfn.call(p.x, p.y)
				hgrid[k] = y if not is_nan(y) else 0.0
				info[k] = null
			elif p.x >= FX0 - 1e-3 and p.x <= FX1 + 1e-3 and p.y >= FZ0 - 1e-3 and p.y <= FZ1 + 1e-3:
				# frame 邊上：P1 高度（接縫逐點重合）
				var ed := edge_at(E, p)
				hgrid[k] = float(ed["y"])
				info[k] = {"h": float(ed["y"]), "d": 0.0, "water": {}, "wet": 0.0}
			else:
				var r := vista_h(C, p)
				hgrid[k] = float(r["h"])
				info[k] = r
	# 樹（近帶）
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 77
	var trees := []
	var x := FX0 - float(TREE_D[1])
	while x <= FX1 + float(TREE_D[1]):
		var z := FZ0 - float(TREE_D[1])
		while z <= FZ1 + float(TREE_D[1]):
			var p := Vector2(x + rng.randf_range(0.15, 0.85) * TREE_CELL, z + rng.randf_range(0.15, 0.85) * TREE_CELL)
			var roll := rng.randf()
			var tid_roll := rng.randi()
			z += TREE_CELL
			if inside(p):
				continue
			var e := frame_near(p)
			var d := p.distance_to(e)
			if d < float(TREE_D[0]) or d > float(TREE_D[1]):
				continue
			var vh := vista_h(C, p)
			var wn: Dictionary = vh["water"]
			var in_water := false
			for W: Dictionary in C["waters"]:
				var rw := _seg_near(W["pts"], W["cum"], p)
				if rw.x < water_hw(W, rw.y) * 1.3 + 2.5:
					in_water = true
					break
			if in_water:
				continue
			if path_w(C, p) > 0.15:
				continue
			var sw := side_w(p)
			var dens := 0.0
			for k in sw:
				dens += float(sw[k]) * float(SIDES[k]["tree"])
			var nt := (C["n_tree"] as FastNoiseLite).get_noise_2d(p.x, p.y)
			dens *= clampf(0.75 + nt * 0.9, 0.15, 1.35)
			# 東側：近帶（< 40 m）是田野延續，只有防風林線（約 26–36 m）與水邊
			if float(sw["E"]) > 0.5:
				var line := 1.0 - _ss(3.0, 6.0, absf(d - 31.0))
				var field := 1.0 - _ss(36.0, 52.0, d)
				dens = lerpf(dens, maxf(line * 0.95, 0.04), field)
			# 林冠帶（> 120 m）：實樹變疏，與遠山林冠交疊過渡
			dens *= lerpf(0.78, 0.28, _ss(110.0, 176.0, d))
			# 近 frame 的南側入口路兩旁讓出
			if d < 9.0:
				dens *= 0.55
			if not wn.is_empty() and float(wn["c"]) < float(wn["hw"]) + 14.0:
				dens = maxf(dens, 0.45)
			if roll > dens:
				continue
			var mix := "mountain"
			var best := -1.0
			for k in sw:
				if float(sw[k]) > best:
					best = float(sw[k])
					mix = String(SIDES[k]["mix"])
			if not wn.is_empty() and float(wn["c"]) < float(wn["hw"]) + 9.0:
				mix = "water"
			var rr := RandomNumberGenerator.new()
			rr.seed = tid_roll
			var tid := _pick(rr, MIXES[mix])
			var sc := rr.randf_range(0.82, 1.12)
			if d > 60.0:
				sc *= rr.randf_range(1.0, 1.12)
			trees.append({"id": tid, "p": p, "y": float(vh["h"]) - TREE_EMBED, "yaw": rr.randf_range(0.0, TAU), "sc": snappedf(sc, 0.001),
				"lean": 0.0, "lean_dir": 0.0, "layer": "vista", "preset": _pick(rr, PRESET_W), "d": d})
		x += TREE_CELL
	if trees.size() > TREE_MAX:
		trees.resize(TREE_MAX)
	var out := {"xs": xs, "zs": zs, "h": hgrid, "info": info, "trees": trees, "ctx": C, "edges": E,
		"stats": {"grid": [nxv, nzv], "trees": trees.size(), "edge_vtx_found": E["vtx_found"], "ms": Time.get_ticks_msec() - t0}}
	return out


## 全格雙線性高度（frame 內外皆可；格外回傳 NAN）
static func grid_h(P: Dictionary, p: Vector2) -> float:
	var xs: PackedFloat32Array = P["xs"]
	var zs: PackedFloat32Array = P["zs"]
	if p.x < xs[0] or p.x > xs[xs.size() - 1] or p.y < zs[0] or p.y > zs[zs.size() - 1]:
		return NAN
	var i := xs.bsearch(p.x) - 1
	var j := zs.bsearch(p.y) - 1
	i = clampi(i, 0, xs.size() - 2)
	j = clampi(j, 0, zs.size() - 2)
	var tx := (p.x - xs[i]) / maxf(xs[i + 1] - xs[i], 1e-6)
	var tz := (p.y - zs[j]) / maxf(zs[j + 1] - zs[j], 1e-6)
	var n := xs.size()
	var H: PackedFloat32Array = P["h"]
	var a := lerpf(H[j * n + i], H[j * n + i + 1], tx)
	var b := lerpf(H[(j + 1) * n + i], H[(j + 1) * n + i + 1], tx)
	return lerpf(a, b, tz)


## 視線閉合：從 eye 沿 dir 前進，碰到地形＝hit；跑出格外仍在地形上方＝escape（看見世界盡頭）
static func ray_closed(P: Dictionary, eye: Vector3, dir: Vector3, max_t := 3000.0) -> bool:
	var t := 1.0
	while t < max_t:
		var q := eye + dir * t
		var g := grid_h(P, Vector2(q.x, q.z))
		if is_nan(g):
			return false
		if q.y <= g:
			return true
		t += maxf(1.0, t * 0.012)
	return false


## ─────────── build（plan → 節點） ───────────
static func build(v: Node3D, P: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = NODE_NAME
	root.set_meta("art_revision", ART_REVISION)
	root.set_meta("phase", "P10 R5c")
	root.set_meta("no_collision", true)
	var gmat := ((v.get_node("Terrain/MainTerrain") as MeshInstance3D).material_override as ShaderMaterial).duplicate() as ShaderMaterial
	var wmat := ((v.get_node("Water/MainRiver") as MeshInstance3D).material_override as Material).duplicate() as Material
	var terr := MeshInstance3D.new()
	terr.name = "VistaTerrain"
	terr.mesh = _terrain_mesh(P)
	terr.material_override = gmat
	terr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(terr)
	var wat := MeshInstance3D.new()
	wat.name = "VistaWater"
	wat.mesh = _water_mesh(P)
	wat.material_override = wmat
	wat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(wat)
	var can := MeshInstance3D.new()
	can.name = "VistaCanopy"
	can.mesh = _canopy_mesh(P)
	var cm := StandardMaterial3D.new()
	cm.vertex_color_use_as_albedo = true
	cm.vertex_color_is_srgb = true
	cm.roughness = 1.0
	cm.cull_mode = BaseMaterial3D.CULL_DISABLED
	can.material_override = cm
	can.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(can)
	root.add_child(_trees(P["trees"]))
	return root


static func _normal_at(P: Dictionary, i: int, j: int) -> Vector3:
	var xs: PackedFloat32Array = P["xs"]
	var zs: PackedFloat32Array = P["zs"]
	var n := xs.size()
	var H: PackedFloat32Array = P["h"]
	var i0 := maxi(i - 1, 0)
	var i1 := mini(i + 1, xs.size() - 1)
	var j0 := maxi(j - 1, 0)
	var j1 := mini(j + 1, zs.size() - 1)
	var dhdx := (H[j * n + i1] - H[j * n + i0]) / maxf(xs[i1] - xs[i0], 1e-6)
	var dhdz := (H[j1 * n + i] - H[j0 * n + i]) / maxf(zs[j1] - zs[j0], 1e-6)
	return Vector3(-dhdx, 1.0, -dhdz).normalized()


static func _terrain_mesh(P: Dictionary) -> ArrayMesh:
	var xs: PackedFloat32Array = P["xs"]
	var zs: PackedFloat32Array = P["zs"]
	var nxv := xs.size()
	var nzv := zs.size()
	var H: PackedFloat32Array = P["h"]
	var info: Array = P["info"]
	var C: Dictionary = P["ctx"]
	var E: Dictionary = P["edges"]
	var remap := PackedInt32Array()
	remap.resize(nxv * nzv)
	remap.fill(-1)
	var vs := PackedVector3Array()
	var ns := PackedVector3Array()
	var cs := PackedColorArray()
	var u1 := PackedVector2Array()
	var u2 := PackedVector2Array()
	for j in nzv:
		for i in nxv:
			var k := j * nxv + i
			if info[k] == null:
				continue
			var p := Vector2(xs[i], zs[j])
			var r: Dictionary = info[k]
			var d := float(r["d"])
			remap[k] = vs.size()
			vs.append(Vector3(p.x, H[k], p.y))
			var nrm := _normal_at(P, i, j)
			# 遠景權重
			var ny := nrm.y
			var rk := 1.0 - _ss(0.62, 0.9, ny)
			var fo := clampf(0.35 + 0.6 * _ss(20.0, 90.0, d), 0.0, 0.92)
			var sw := side_w(p)
			if float(sw["E"]) > 0.5:
				fo *= _ss(30.0, 70.0, d)
			var tr := path_w(C, p)
			var md := 0.0
			var gr := 0.0
			var wt := 0.0
			var wn: Dictionary = r["water"]
			if not wn.is_empty():
				var c := float(wn["c"])
				var hw := float(wn["hw"])
				var rel := H[k] - float(wn["lv"])
				if c < hw + 6.0:
					fo *= _ss(hw + 1.0, hw + 6.0, c)
					var toe := 1.0 - _ss(0.0, 0.6, rel)
					md = maxf(md, toe * 0.55)
					gr = maxf(gr, toe * 0.4)
					wt = maxf(wt, 1.0 - _ss(0.0, 0.7, rel))
			var col := Color(clampf(tr, 0.0, 1.0), clampf(gr, 0.0, 1.0), clampf(md, 0.0, 1.0), clampf(rk, 0.0, 1.0))
			var uv := Vector2(clampf(fo * (1.0 - tr), 0.0, 1.0), 0.0)
			var uv2 := Vector2(clampf(wt, 0.0, 1.0), 0.0)
			# 接縫：P1 邊緣頂點的權重與法線 → SEAM_BLEND_D 內漸變到遠景
			if d < SEAM_BLEND_D:
				var e := frame_near(p)
				var ed := edge_at(E, e)
				var ia: Dictionary = ed["a"]["info"]
				var ib: Dictionary = ed["b"]["info"]
				if not ia.is_empty() and not ib.is_empty():
					var tt := float(ed["t"])
					var c0: Color = (ia["c"] as Color).lerp(ib["c"], tt)
					var a0: Vector2 = (ia["u1"] as Vector2).lerp(ib["u1"], tt)
					var b0: Vector2 = (ia["u2"] as Vector2).lerp(ib["u2"], tt)
					var n0: Vector3 = (ia["n"] as Vector3).lerp(ib["n"], tt).normalized()
					a0.y = 0.0     # 田權重不延伸到 frame 外（不畫田格）
					var s := _ss(0.0, SEAM_BLEND_D, d)
					col = c0.lerp(col, s)
					uv = a0.lerp(uv, s)
					uv2 = b0.lerp(uv2, s)
					var ns_s := _ss(0.0, 6.0, d)
					nrm = n0.lerp(nrm, ns_s).normalized()
			ns.append(nrm)
			cs.append(col)
			u1.append(uv)
			u2.append(uv2)
	var idx := PackedInt32Array()
	for j in nzv - 1:
		for i in nxv - 1:
			var cx := (xs[i] + xs[i + 1]) * 0.5
			var cz := (zs[j] + zs[j + 1]) * 0.5
			if inside(Vector2(cx, cz)):
				continue
			var a := remap[j * nxv + i]
			var b := remap[j * nxv + i + 1]
			var c := remap[(j + 1) * nxv + i + 1]
			var d := remap[(j + 1) * nxv + i]
			if a < 0 or b < 0 or c < 0 or d < 0:
				continue
			idx.append_array(PackedInt32Array([a, b, c, a, c, d]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = vs
	arr[Mesh.ARRAY_NORMAL] = ns
	arr[Mesh.ARRAY_COLOR] = cs
	arr[Mesh.ARRAY_TEX_UV] = u1
	arr[Mesh.ARRAY_TEX_UV2] = u2
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.set_meta("vertices", vs.size())
	m.set_meta("triangles", idx.size() / 3)
	return m


static func _water_col(depth: float) -> Color:
	var c := WATER_SHALLOW.lerp(WATER_DEEP, _ss(0.0, 2.2, maxf(depth, 0.0)))
	return Color(c.r * ALBEDO_K, c.g * ALBEDO_K, c.b * ALBEDO_K, c.a)


static func _water_mesh(P: Dictionary) -> ArrayMesh:
	var C: Dictionary = P["ctx"]
	var E: Dictionary = P["edges"]
	var hfn: Callable = E["hfn"]
	var vs := PackedVector3Array()
	var ns := PackedVector3Array()
	var cs := PackedColorArray()
	var idx := PackedInt32Array()
	const ACROSS := 9
	for W: Dictionary in C["waters"]:
		var pts: PackedVector2Array = W["pts"]
		var cum: PackedFloat32Array = W["cum"]
		var total := cum[cum.size() - 1]
		var s := 0.0
		var prev := -1
		while s <= total + 0.01:
			var ss := minf(s, total)
			var k := 0
			while k < pts.size() - 2 and cum[k + 1] < ss:
				k += 1
			var a := pts[k]
			var b := pts[k + 1]
			var tt := clampf((ss - cum[k]) / maxf(cum[k + 1] - cum[k], 1e-6), 0.0, 1.0)
			var c := a.lerp(b, tt)
			var tdir := (b - a).normalized()
			var nn := Vector2(-tdir.y, tdir.x)
			var hw := water_hw(W, ss) * 1.3 + 1.2
			var lv := water_level(W, ss)
			var base := vs.size()
			for q in ACROSS:
				var f := -1.0 + 2.0 * float(q) / float(ACROSS - 1)
				var pp := c + nn * hw * f
				# 水深＝水位 − 河床（frame 邊上取 P1 地形、frame 外取 vista 刻道後高度）→ 與 P2 水面同一套頂點色規則，接縫不換色
				var gh: float
				if pp.distance_to(frame_near(pp)) < 1.0:
					gh = hfn.call(clampf(pp.x, FX0 + 0.01, FX1 - 0.01), clampf(pp.y, FZ0 + 0.01, FZ1 - 0.01))
				else:
					gh = float(vista_h(C, pp)["h"])
				vs.append(Vector3(pp.x, lv, pp.y))
				ns.append(Vector3.UP)
				cs.append(_water_col(lv - gh))
			if prev >= 0:
				for q in ACROSS - 1:
					idx.append_array(PackedInt32Array([prev + q, prev + q + 1, base + q + 1, prev + q, base + q + 1, base + q]))
			prev = base
			s += 2.0 if s < 40.0 else 5.0
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = vs
	arr[Mesh.ARRAY_NORMAL] = ns
	arr[Mesh.ARRAY_COLOR] = cs
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.set_meta("triangles", idx.size() / 3)
	return m


## 遠山林冠：獨立的均勻 8 m 格（不沿用 vista 的放射狀格，避免顏色與起伏被拉長），d ∈ [CANOPY_D0−20, 700]
static func _canopy_mesh(P: Dictionary) -> ArrayMesh:
	var C: Dictionary = P["ctx"]
	const G := 8.0
	var x0 := FX0 - 704.0
	var z0 := FZ0 - 704.0
	var nx := int((FX1 - FX0 + 1408.0) / G) + 1
	var nz := int((FZ1 - FZ0 + 1408.0) / G) + 1
	var remap := PackedInt32Array()
	remap.resize(nx * nz)
	remap.fill(-1)
	var vs := PackedVector3Array()
	var cs := PackedColorArray()
	var hh := PackedFloat32Array()
	hh.resize(nx * nz)
	var nc: FastNoiseLite = C["n_can"]
	var nt: FastNoiseLite = C["n_tree"]
	var nk: FastNoiseLite = C["n_clump"]
	for j in nz:
		for i in nx:
			var p := Vector2(x0 + i * G, z0 + j * G)
			var e := frame_near(p)
			var d := p.distance_to(e)
			if d < CANOPY_D0 - 24.0 or d > 700.0:
				continue
			var r := vista_h(C, p)
			# 林冠坐在「實際渲染的地形網格」上（vista 格的雙線性），不是解析高度——遠處格距大，解析高度與網格可差數公尺
			var gh := grid_h(P, p)
			if is_nan(gh):
				continue
			var rise := _ss(CANOPY_D0, CANOPY_D1, d)
			var wn: Dictionary = r["water"]
			var wm := 1.0
			if not wn.is_empty():
				wm = _ss(float(wn["hw"]) + 4.0, float(wn["hw"]) + 22.0, float(wn["c"]))
			var clump := nk.get_noise_2d(p.x, p.y)
			var ch := lerpf(float(CANOPY_H[0]), float(CANOPY_H[1]), 0.5 + 0.5 * nc.get_noise_2d(p.x, p.y)) + clump * 3.0
			var k := rise * wm
			var y := maxf(gh, float(r["h"])) + 1.2 + ch * k - 5.5 * (1.0 - k)
			remap[j * nx + i] = vs.size()
			hh[j * nx + i] = y
			vs.append(Vector3(p.x, y, p.y))
			var sw := side_w(p)
			var con := float(sw["N"]) + float(sw["W"]) * 0.8
			var t := clampf(0.5 + 0.5 * nt.get_noise_2d(p.x * 1.7, p.y * 1.7) + clump * 0.55, 0.0, 1.0)
			var c_con := Color(0.10, 0.16, 0.11).lerp(Color(0.18, 0.25, 0.15), t)
			var c_brd := Color(0.15, 0.21, 0.10).lerp(Color(0.26, 0.32, 0.14), t)
			cs.append(c_brd.lerp(c_con, clampf(con, 0.0, 1.0)))
	var ns := PackedVector3Array()
	ns.resize(vs.size())
	for j in nz:
		for i in nx:
			var k := remap[j * nx + i]
			if k < 0:
				continue
			var hx0 := hh[j * nx + maxi(i - 1, 0)] if remap[j * nx + maxi(i - 1, 0)] >= 0 else hh[j * nx + i]
			var hx1 := hh[j * nx + mini(i + 1, nx - 1)] if remap[j * nx + mini(i + 1, nx - 1)] >= 0 else hh[j * nx + i]
			var hz0 := hh[maxi(j - 1, 0) * nx + i] if remap[maxi(j - 1, 0) * nx + i] >= 0 else hh[j * nx + i]
			var hz1 := hh[mini(j + 1, nz - 1) * nx + i] if remap[mini(j + 1, nz - 1) * nx + i] >= 0 else hh[j * nx + i]
			ns[k] = Vector3(-(hx1 - hx0) / (2.0 * G), 1.0, -(hz1 - hz0) / (2.0 * G)).normalized()
	var idx := PackedInt32Array()
	for j in nz - 1:
		for i in nx - 1:
			var a := remap[j * nx + i]
			var b := remap[j * nx + i + 1]
			var c := remap[(j + 1) * nx + i + 1]
			var d := remap[(j + 1) * nx + i]
			if a < 0 or b < 0 or c < 0 or d < 0:
				continue
			idx.append_array(PackedInt32Array([a, b, c, a, c, d]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = vs
	arr[Mesh.ARRAY_NORMAL] = ns
	arr[Mesh.ARRAY_COLOR] = cs
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.set_meta("triangles", idx.size() / 3)
	return m


## 樹：全部 MultiMesh（LOD0–3 各自分塊，可見範圍取樹庫 prefab 值 ± 塊半對角；逐實例換檔由 veg shader 的 lod_band 決定）
static func _trees(items: Array) -> Node3D:
	var root := Node3D.new()
	root.name = "VistaTrees"
	var M := FLib.modules()
	var protos := {}
	for it: Dictionary in items:
		var tid := String(it["id"])
		if not protos.has(tid):
			protos[tid] = (load(FLib.KIT + "/trees/%s.tscn" % tid) as PackedScene).instantiate()
	var n_mmi := 0
	var n_inst := 0
	for lod in 4:
		var cs := CHUNK_NEAR if lod < 2 else CHUNK_FAR
		var groups := {}
		for it: Dictionary in items:
			var tid := String(it["id"])
			if lod >= (M[tid]["lods"] as Array).size():
				continue
			var p: Vector2 = it["p"]
			var gk := "%d_%d|%s|%s" % [floori(p.x / cs), floori(p.y / cs), tid, it["preset"]]
			if not groups.has(gk):
				groups[gk] = []
			(groups[gk] as Array).append(it)
		var ln := Node3D.new()
		ln.name = "LOD%d" % lod
		root.add_child(ln)
		var gkeys := groups.keys()
		gkeys.sort()
		for gk: String in gkeys:
			var parts := gk.split("|")
			var tid := parts[1]
			var src := (protos[tid] as Node).get_node_or_null("LOD%d" % lod) as MeshInstance3D
			if src == null:
				continue
			var arr: Array = groups[gk]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = src.mesh
			mm.instance_count = arr.size()
			var ab := AABB()
			for k in arr.size():
				var xf := FLib.xf_of(arr[k])
				mm.set_instance_transform(k, xf)
				var wb: AABB = xf * src.mesh.get_aabb()
				ab = wb if k == 0 else ab.merge(wb)
			mm.custom_aabb = ab
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "C_%s_%s_%s" % [parts[0], tid, parts[2]]
			mmi.multimesh = mm
			mmi.set_instance_shader_parameter("lod_band", src.get_instance_shader_parameter("lod_band"))
			mmi.set_instance_shader_parameter("lod_ref", src.get_instance_shader_parameter("lod_ref"))
			var pr: Array = TreeLib.COLOR_PRESETS.get(parts[2], TreeLib.COLOR_PRESETS["mature"])
			mmi.set_instance_shader_parameter("leaf_tint", pr[0])
			mmi.set_instance_shader_parameter("leaf_sat", pr[1])
			var hd := Vector2(ab.size.x, ab.size.z).length() * 0.5
			mmi.visibility_range_begin = maxf(0.0, src.visibility_range_begin - hd) if src.visibility_range_begin > 0.0 else 0.0
			# 遠景樹：LOD3 只到 360 m（更遠由林冠面負責）；只有 LOD0（≤ 約 36 m，貼牆時）投影
			var vend := src.visibility_range_end
			if lod == 3:
				vend = minf(vend, 360.0)
			mmi.visibility_range_end = vend + hd if vend > 0.0 else 0.0
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if lod >= 1 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			mmi.set_meta("veg_id", tid)
			mmi.set_meta("instances", arr.size())
			ln.add_child(mmi)
			n_mmi += 1
			n_inst += arr.size()
	for tid in protos:
		(protos[tid] as Node).free()
	root.set_meta("trees", items.size())
	root.set_meta("multimesh_nodes", n_mmi)
	root.set_meta("multimesh_instances", n_inst)
	return root


static func own(n: Node, owner: Node) -> void:
	for c in n.get_children():
		c.owner = owner
		own(c, owner)

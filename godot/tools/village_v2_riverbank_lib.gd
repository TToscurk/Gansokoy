extends RefCounted
## 人間之里 V2 P7 R2：河岸 Kit（Riverbank / Bridge Transition）擺放＋合併。
## 產生器（gen_village_v2.gd _riverbank）與 gate（verify_village_v2_riverbank_gate.gd）共用：
##   plan(v, L)  → 決定性擺放清單（不改 P1 地形、不改 P2 水面、不改河道中心線／layout）
##   bake(v, items, lib) → v/Riverbank：每 32 m 區塊合併成 LOD0／LOD1 各一個 ArrayMesh（依材質分 surface）＋少量碰撞箱
## 輸入全部取自場景已產生的核准資料：
##   地形＝Collision/TerrainCollision 的三角面（與玩家踩的面同一份）；水位＝Water/* 水面網格頂點；路面＝Roads/* 帶狀網格；
##   橋＝Roads/Bridges/Bridge_* 灰盒（HLib.bridge_frame／bridge_dims，與 P7 R2 正式橋同一座標）。
## 濕石／苔：合併時依「頂點離該處水位高度」＋朝上程度＋低頻雜訊寫進頂點色（材質＝V2_KitStoneTri 乘頂點色）。

const HLib := preload("res://tools/village_v2_hero_lib.gd")
const PLib := preload("res://tools/village_v2_parcel_lib.gd")
const TLib := preload("res://tools/village_v2_terrain_lib.gd")
const MESH_DIR := "res://assets/village_v2/riverbank_kit/mesh/"
const PARCELS := "res://maps/village_v2/gen/parcels.json"

const CHUNK := 32.0
const LOD_RANGES := [0.0, 75.0, 420.0]
const LOD_MARGIN := 4.0
const PW := 2.4               # 護岸面板寬（沿岸）
const PH := 0.9               # 護岸面板高（沿坡）
const FACE_OFF := 0.04        # 面板平面離地形弦外推
const BACK := 0.30            # 面板石背深
const TOE_BELOW := 0.30       # 護岸腳在水位下
const CAP_TOP := 0.12         # 笠石頂高出岸頂地面
const STEP_TREAD := 0.44
const STEP_RISE_MAX := 0.27
const LAND_TOP := 0.13        # 親水平台頂高出水位
const TALL_BANK := 3.6        # 岸高超過 → 只做護岸腳（不砌整面）
const WATER_PATH := {"MainRiver": "Water/MainRiver", "Canal": "Water/Canal", "WestStream": "Water/Streams/WestStream"}
const SPACING := {"MainRiver": 3.0, "Canal": 2.4, "WestStream": 3.0}
const RIVER_WING := 9.0       # 龍神橋兩側護岸長（m）
const STREAM_WING := 3.0
const CANAL_BRIDGE_FULL := 16.0
const MODS := {
	"rev": ["rb_rev_a", "rb_rev_b", "rb_rev_c", "rb_rev_d", "rb_rev_e", "rb_rev_f"], "revb": ["rb_revb_a", "rb_revb_b"],
	"cap": ["rb_cap_a", "rb_cap_b", "rb_cap_c"], "bld": ["rb_bld_a", "rb_bld_b", "rb_bld_c", "rb_bld_d", "rb_bld_e"],
	"cob": ["rb_cob_a", "rb_cob_b", "rb_cob_c"], "flag": ["rb_flag_a", "rb_flag_b", "rb_flag_c", "rb_flag_d"],
	"curb": ["rb_curb_a", "rb_curb_b"], "step": ["rb_step_a", "rb_step_b"], "land": ["rb_land"],
	"pile": ["rb_pile_a"], "piler": ["rb_pile_r"], "rail": ["rb_rail"], "shig": ["rb_shig"],
}
## 構件標稱尺寸（Blender build_riverbank_kit.py 常數；gate 以 mesh AABB 比對）
const FLAG_W := {"rb_flag_a": 0.56, "rb_flag_b": 0.70, "rb_flag_c": 0.84, "rb_flag_d": 0.62}


# ─────────────────────────── 取樣器 ───────────────────────────

## 三角面高度取樣（xz → 最高的包含三角面高度）；4 m 分格
class TriSampler:
	var cell := 4.0
	var bins := {}
	var f := PackedVector3Array()

	func add(faces: PackedVector3Array, xf: Transform3D) -> void:
		var base := f.size()
		for p: Vector3 in faces:
			f.append(xf * p)
		for t in range(base, f.size(), 3):
			var a := f[t]
			var b := f[t + 1]
			var c := f[t + 2]
			var i0 := floori(minf(a.x, minf(b.x, c.x)) / cell)
			var i1 := floori(maxf(a.x, maxf(b.x, c.x)) / cell)
			var j0 := floori(minf(a.z, minf(b.z, c.z)) / cell)
			var j1 := floori(maxf(a.z, maxf(b.z, c.z)) / cell)
			for i in range(i0, i1 + 1):
				for j in range(j0, j1 + 1):
					var k := Vector2i(i, j)
					if not bins.has(k):
						bins[k] = []
					(bins[k] as Array).append(t)

	func h(x: float, z: float) -> float:
		var k := Vector2i(floori(x / cell), floori(z / cell))
		if not bins.has(k):
			return NAN
		var best := NAN
		for t: int in bins[k]:
			var a := f[t]
			var b := f[t + 1]
			var c := f[t + 2]
			var d := (b.z - c.z) * (a.x - c.x) + (c.x - b.x) * (a.z - c.z)
			if absf(d) < 1e-9:
				continue
			var l1 := ((b.z - c.z) * (x - c.x) + (c.x - b.x) * (z - c.z)) / d
			var l2 := ((c.z - a.z) * (x - c.x) + (a.x - c.x) * (z - c.z)) / d
			var l3 := 1.0 - l1 - l2
			if l1 < -1e-4 or l2 < -1e-4 or l3 < -1e-4:
				continue
			var y := l1 * a.y + l2 * b.y + l3 * c.y
			if is_nan(best) or y > best:
				best = y
		return best


## 水面頂點最近點高度（每水體一份）
class WaterLv:
	var cell := 4.0
	var bins := {}

	func add(verts: PackedVector3Array, xf: Transform3D) -> void:
		for p: Vector3 in verts:
			var w := xf * p
			var k := Vector2i(floori(w.x / cell), floori(w.z / cell))
			if not bins.has(k):
				bins[k] = PackedVector3Array()
			var arr: PackedVector3Array = bins[k]
			arr.append(w)
			bins[k] = arr

	func at(x: float, z: float) -> float:
		var ci := floori(x / cell)
		var cj := floori(z / cell)
		var best := INF
		var by := NAN
		for r in 3:
			for i in range(ci - r, ci + r + 1):
				for j in range(cj - r, cj + r + 1):
					if r > 0 and absi(i - ci) < r and absi(j - cj) < r:
						continue
					var k := Vector2i(i, j)
					if not bins.has(k):
						continue
					for w: Vector3 in bins[k]:
						var d := (w.x - x) * (w.x - x) + (w.z - z) * (w.z - z)
						if d < best:
							best = d
							by = w.y
			if best < INF:
				return by
		return by


static func rel_xf(n: Node, top: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var c: Node = n
	while c != null and c != top:
		if c is Node3D:
			xf = (c as Node3D).transform * xf
		c = c.get_parent()
	return xf


static func terrain_sampler(v: Node3D) -> TriSampler:
	var s := TriSampler.new()
	var tc := v.get_node("Collision/TerrainCollision")
	for cs in tc.find_children("*", "CollisionShape3D", true, false):
		var sh := (cs as CollisionShape3D).shape
		if sh is ConcavePolygonShape3D:
			s.add((sh as ConcavePolygonShape3D).get_faces(), rel_xf(cs, v))
	return s


static func road_sampler(v: Node3D) -> TriSampler:
	var s := TriSampler.new()
	for g in v.get_node("Roads").get_children():
		if String(g.name) == "Bridges":
			continue
		for mi in g.find_children("*", "MeshInstance3D", true, false):
			var m := (mi as MeshInstance3D).mesh
			if m != null:
				s.add(m.get_faces(), rel_xf(mi, v))
	return s


static func water_levels(v: Node3D) -> Dictionary:
	var out := {}
	for nm: String in WATER_PATH:
		var mi := v.get_node_or_null(String(WATER_PATH[nm])) as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var w := WaterLv.new()
		for s in mi.mesh.get_surface_count():
			w.add(mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX], rel_xf(mi, v))
		out[nm] = w
	return out


## 構件真實 mesh AABB（惰性快取）。gate 的 parcel_fit 就是拿 mesh AABB 做查詢，
## lib 若用 HALF 近似就會出現「lib 說淨空、gate 說壓到」的量尺落差。
static var _aabb_cache := {}


static func mesh_aabb(m_name: String) -> AABB:
	if _aabb_cache.has(m_name):
		return _aabb_cache[m_name]
	var m: Mesh = load(MESH_DIR + m_name + ".res")
	var a := AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE)
	if m != null:
		a = m.get_aabb()
	_aabb_cache[m_name] = a
	return a


static func load_lib() -> Dictionary:
	var lib := {}
	for f in DirAccess.get_files_at(MESH_DIR):
		if f.ends_with(".res"):
			lib[f.get_basename()] = load(MESH_DIR + f)
	return lib


# ─────────────────────────── 小工具 ───────────────────────────

static func _rng(key: String) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = key.hash()
	return r


static func _pick(r: RandomNumberGenerator, kind: String) -> String:
	var a: Array = MODS[kind]
	return String(a[r.randi() % a.size()])


static func _cum(pts: PackedVector2Array) -> PackedFloat32Array:
	var cum := PackedFloat32Array([0.0])
	for k in range(1, pts.size()):
		cum.append(cum[k - 1] + pts[k - 1].distance_to(pts[k]))
	return cum


static func _along(pts: PackedVector2Array, cum: PackedFloat32Array, s: float) -> Array:
	for k in pts.size() - 1:
		if s <= cum[k + 1] or k == pts.size() - 2:
			var seg := maxf(cum[k + 1] - cum[k], 1e-6)
			var t := clampf((s - cum[k]) / seg, 0.0, 1.0)
			return [pts[k].lerp(pts[k + 1], t), (pts[k + 1] - pts[k]) / seg]
	return [pts[0], Vector2(1, 0)]


static func _proj_s(pts: PackedVector2Array, cum: PackedFloat32Array, p: Vector2) -> float:
	var best := INF
	var bs := 0.0
	for k in pts.size() - 1:
		var a := pts[k]
		var ab := pts[k + 1] - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
		var d := p.distance_to(a + ab * t)
		if d < best:
			best = d
			bs = cum[k] + t * (cum[k + 1] - cum[k])
	return bs


static func _surf(S: TriSampler, R: TriSampler, x: float, z: float) -> float:
	var h := S.h(x, z)
	var r := R.h(x, z)
	if not is_nan(r) and (is_nan(h) or r > h):
		return r
	return h


static func _on_road(R: TriSampler, c: Vector3, hx: Vector3, hz: Vector3) -> bool:
	for o: Vector3 in [Vector3.ZERO, hx + hz, hx - hz, -hx + hz, -hx - hz]:
		if not is_nan(R.h(c.x + o.x, c.z + o.z)):
			return true
	return false


static func _item(m: String, xf: Transform3D, k: String, wl: float, tag: String, shape := {}) -> Dictionary:
	return {"m": m, "xf": xf, "k": k, "wl": wl, "tag": tag, "shape": shape}


# ─────────────────────────── 護岸石砌清理（R3）───────────────────────────
# 使用者 2026-09-28：不得有石頭被地形吃掉／只露一角／浮空／石列上下亂跳。
# 只修 placement／scale／rotation／embed depth，不動河道、水位、已核准地形。
# 決定性、有界（單顆位移 ≤ SETTLE_MOVE），無亂數。

const SETTLE_KINDS: Array[String] = ["rev", "revb", "cap", "bld"]   # 與 gate TIGHT_KINDS 一致；cob/shig 為自然散石，維持不規則
const SETTLE_LO := 0.40          # 低於此＝被地形切掉／只露一角 → 往外推（使用者目標帶下緣）
const SETTLE_HI := 0.70          # 高於此＝過度外露 → 往內收（使用者目標帶上緣）
const SETTLE_BACK := 0.55        # 石背露出比例上限（超過＝石頭離開坡面、背後會露空洞）
const SETTLE_MOVE := 0.45        # 單顆最大水平位移（沿河向；限制 jitter，不讓石列上下亂跳）
const SETTLE_SINK := 0.26        # 水平修正時的最大下潛／上抬（維持貼坡）
const SETTLE_LIFT := 1.35        # 被埋深的石頭可上抬的範圍（上表面露出、底部仍可埋入）
const SETTLE_FLOAT := 0.04       # 容許浮空（m）
const SETTLE_SAMPLES := 14       # 三角面抽樣數（越多越不會被單一三角面誤導）
const SETTLE_STEP := 0.06        # 位移搜尋步長（步長太粗會超調成浮在坡面上）
const MAX_COURSES := 4           # 砌築層數上限（使用者：2–4 層）


## 清理是否啟用（gate 可加 --nosettle 量 before 狀態，用同一把量尺比較）
static func settle_enabled() -> bool:
	for a: String in OS.get_cmdline_user_args():
		if a == "--nosettle":
			return false
	return true


## 每個構件（Mesh 資源共用）只抓一次 surface arrays 與「朝岸內」的取樣點，
## 之後用局部座標 + 世界矩陣轉換，避免每顆石頭、每個候選位移都重新配置陣列。
static var _mcache := {}


static func _mdata(m: Mesh) -> Dictionary:
	var k := m.get_instance_id()
	if _mcache.has(k):
		return _mcache[k]
	var a: Array = m.surface_get_arrays(0)
	var V: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var I: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var N: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var back: Array = []
	var step_b := maxi(1, (I.size() / 3) / 10)
	for t in range(0, I.size(), 3 * step_b):
		if t + 2 >= I.size():
			break
		var n3 := ((N[I[t]] + N[I[t + 1]] + N[I[t + 2]]).normalized()).normalized()
		back.append([(V[I[t]] + V[I[t + 1]] + V[I[t + 2]]) / 3.0, n3])
	var out := {"V": V, "I": I, "N": N, "back": back}
	_mcache[k] = out
	return out


static func _exposure(m: Mesh, xf: Transform3D, S: TriSampler, out_h: Vector3) -> float:
	## 「未被地形埋住」的表面積比例（0＝整顆埋在坡裡、只露一角；1＝整顆在坡面之上）。
	## 三角面取樣點再細分一層（每個面 4 個子面），避免面板只有 ~322 面時
	## 粗量化成 0.87／0.90 這種跳階值——那會讓「調到 40–70 %」變成不可能的任務。
	## 沒有地形樣本（水面上方／河床未建）的子面一律從分子與分母剔除：
	## 沒有土可埋，就不能當成「露出」的證據。有效子面 < 35 % → 回傳 -1.0（無從判定）。
	var d := _mdata(m)
	var V: PackedVector3Array = d["V"]
	var I: PackedInt32Array = d["I"]
	var all := 0.0
	var tot := 0.0
	var ex := 0.0
	var step := maxi(1, (I.size() / 3) / SETTLE_SAMPLES)
	for t in range(0, I.size(), 3 * step):
		if t + 2 >= I.size():
			break
		var p0 := xf * V[I[t]]
		var p1 := xf * V[I[t + 1]]
		var p2 := xf * V[I[t + 2]]
		var mid01 := (p0 + p1) * 0.5
		var mid12 := (p1 + p2) * 0.5
		var mid20 := (p2 + p0) * 0.5
		for tri: Array in [[p0, mid01, mid20], [mid01, p1, mid12], [mid20, mid12, p2], [mid01, mid12, mid20]]:
			var q0: Vector3 = tri[0]
			var q1: Vector3 = tri[1]
			var q2: Vector3 = tri[2]
			var ar := (q1 - q0).cross(q2 - q0).length() * 0.5
			if ar < 1e-9:
				continue
			all += ar
			var c := (q0 + q1 + q2) / 3.0
			var th := S.h(c.x, c.z)
			if is_nan(th):
				continue
			tot += ar
			if c.y > th:
				ex += ar
	if all < 1e-6 or tot < 0.35 * all:
		return -1.0
	return ex / tot


## 石背（朝岸內的面）露出地面的面積比例。> 0.5＝整顆離開坡面（浮在坡上／背後空洞）。
static func _back_out(m: Mesh, xf: Transform3D, S: TriSampler, out_h: Vector3) -> float:
	var a: Array = m.surface_get_arrays(0)
	var V: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var N: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var I: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var tot := 0.0
	var ex := 0.0
	var step := maxi(1, (I.size() / 3) / SETTLE_SAMPLES)
	for t in range(0, I.size(), 3 * step):
		if t + 2 >= I.size():
			break
		var p0 := xf * V[I[t]]
		var p1 := xf * V[I[t + 1]]
		var p2 := xf * V[I[t + 2]]
		var ar := (p1 - p0).cross(p2 - p0).length() * 0.5
		if ar < 1e-9:
			continue
		var wn := (xf.basis * ((N[I[t]] + N[I[t + 1]] + N[I[t + 2]]).normalized())).normalized()
		if wn.dot(out_h) >= -0.25:
			continue                                   # 只看石背（朝岸內）的面
		tot += ar
		var c := (p0 + p1 + p2) / 3.0
		var th := S.h(c.x, c.z)
		if is_nan(th) or c.y > th:
			ex += ar
	return ex / maxf(tot, 1e-6) if tot > 1e-6 else 0.0


## 最低點離地形（或路面）的距離（< 0＝埋入）
static func _lowest_gap(m: Mesh, xf: Transform3D, S: TriSampler, R: TriSampler) -> float:
	var V: PackedVector3Array = m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var wy := INF
	for pv: Vector3 in V:
		var wp := xf * pv
		var th := _surf(S, R, wp.x, wp.z)
		if is_nan(th):
			continue
		wy = minf(wy, wp.y - th)
	return wy if wy < INF else -1.0


## tag「水體/側/站號」→ 站點；回傳朝河（XZ 單位）方向
static func _outward_of(it: Dictionary, st_by_key: Dictionary) -> Vector3:
	var parts := String(it["tag"]).split("/")
	if parts.size() < 3 or not parts[2].is_valid_int():
		return Vector3.ZERO
	var key := "%s|%s" % [parts[0], parts[1]]
	if not st_by_key.has(key):
		return Vector3.ZERO
	var arr: Array = st_by_key[key]
	var i := int(parts[2])
	if i < 0 or i >= arr.size():
		return Vector3.ZERO
	var c: Array = arr[i]["c"]
	var o: Vector3 = (it["xf"] as Transform3D).origin
	var d := Vector2(float(c[0]) - o.x, float(c[1]) - o.z)
	if d.length() < 0.05:
		return Vector3.ZERO
	d = d.normalized()
	return Vector3(d.x, 0, d.y)


## 逐顆有界修正（決定性）：同時搜「往外／往內」與「下沉」兩個方向，
## 找出讓「迎水面露出地面比例」最接近目標帶的位移。
## 下沉＝底部埋入地形、上表面仍露出（使用者明示允許）；不會整顆漂在坡面上。
## 離「可讀帶」的距離（帶內＝0）。比鎖定單一目標值穩定：
## 護岸面板幾何上是貼坡的，曝光比例呈雙峰（整片露出／整片被埋），
## 硬拉向中間值只會超調成浮在坡面上——改用「進帶即停、取最小位移」。
static func _band_cost(v: float) -> float:
	return maxf(0.0, SETTLE_LO - v) + maxf(0.0, v - SETTLE_HI)


## 曝光比例對「沿河向外位移」單調遞增、對「下潛」單調遞減（探針 revcurve.txt 實測）。
## 由小到大掃位移，第一個「進帶且通過貼坡／浮空檢查」的解就是最小位移解：
##   · 被埋（vis 低）→ 先試往河（往河＝out_h 正向），再試往岸內、再試沿坡下滑
##   · 過露（vis 高）→ 先試往岸內，再試往河、再試下潛
## 由小到大＝天然偏好小位移，保留相鄰石塊的尺寸／旋轉／深度變化，不把石列拉平。
## _exposure 回傳 -1.0 表示「地形樣本不足、無從判定」，一律視為不合格候選而非「被埋」。
## 註：settle 會改動「已通過後置過濾」的件位置，所以候選位置必須再過同一套淨空標準，
## 否則會把石頭推回橋體／地塊／路帶（gate parcel_fit 會抓到）。原地本身已合格，退回原位安全。
static func _settle_stonework(items: Array, st_by_key: Dictionary, S: TriSampler, R: TriSampler,
		lib: Dictionary, boxes: Array, brs: Array, parcels: Array) -> Dictionary:
	var moved := 0
	var rescued := 0
	var sunk := 0
	var kept := 0
	var stuck := 0
	var hist := {}
	var reasons := {}
	for idx in items.size():
		var it: Dictionary = items[idx]
		if not SETTLE_KINDS.has(String(it["k"])):
			continue
		var m: Mesh = lib.get(String(it["m"]))
		if m == null:
			continue
		var out_h := _outward_of(it, st_by_key)
		if out_h == Vector3.ZERO:
			continue
		var xf: Transform3D = it["xf"]
		var vis := _exposure(m, xf, S, out_h)
		if vis < 0.0:
			continue                                        # 地形樣本不足，無從判定 → 不動
		var b0 := int(round(vis * 20.0))
		# 在帶內、且石背真的有地形 → 才算完成（保留既有變化，不硬拉平）
		if vis >= SETTLE_LO and vis <= SETTLE_HI and _has_back_terrain(m, xf, S, out_h):
			kept += 1
			hist[b0] = int(hist.get(b0, 0)) + 1
			continue
		var sol := _solve(m, xf, S, R, out_h, vis, reasons, false, it, boxes, brs, parcels)
		if not sol.is_empty() and not _settle_clear(it, sol["xf"], boxes, brs, R, parcels):
			# 快路徑候選壓到結構／地塊／路帶（罕見）→ 只對這顆開嚴格模式重解，其餘不受影響
			sol = _solve(m, xf, S, R, out_h, vis, reasons, true, it, boxes, brs, parcels)
		if sol.is_empty():
			stuck += 1                                    # 找不到可達成的解 → 明確計數
			hist[b0] = int(hist.get(b0, 0)) + 1
			continue
		var sol_xf: Transform3D = sol["xf"]
		if not _settle_clear(it, sol_xf, boxes, brs, R, parcels):
			reasons["blocked"] = int(reasons.get("blocked", 0)) + 1   # 最後一道護欄
			stuck += 1
			hist[b0] = int(hist.get(b0, 0)) + 1
			continue
		it["xf"] = sol_xf
		moved += 1
		var v3 := float(sol["vis"])
		if vis < SETTLE_LO and v3 >= SETTLE_LO:
			rescued += 1
		if vis > SETTLE_HI and v3 <= SETTLE_HI:
			sunk += 1
		hist[int(round(v3 * 20.0))] = int(hist.get(int(round(v3 * 20.0)), 0)) + 1
	return {"moved": moved, "rescued": rescued, "sunk": sunk, "kept": kept, "stuck": stuck,
		"reasons": reasons, "hist": hist}


static func _expo(m: Mesh, xf: Transform3D, S: TriSampler, out_h: Vector3) -> float:
	return _exposure(m, xf, S, out_h)


## 檢查候選解：不得浮空、不得讓石背整片離開坡面（否則背後會露空洞）。合格才回傳。
static func _accept(m: Mesh, xf: Transform3D, out_h: Vector3, off: Vector3,
		S: TriSampler, R: TriSampler) -> bool:
	var txf := xf.translated(off)
	if _lowest_gap(m, txf, S, R) > SETTLE_FLOAT:
		return false
	if _back_out(m, txf, S, out_h) > SETTLE_BACK:
		return false
	return true


## 石背之後是否真有地形（樣本有效）＝石頭背後不會露空洞。純地形取樣，不需物理射線。
static func _has_back_terrain(m: Mesh, xf: Transform3D, S: TriSampler, out_h: Vector3) -> bool:
	var d := _mdata(m)
	for b: Array in d["back"]:
		var n3 := (xf.basis * (b[1] as Vector3)).normalized()
		if n3.dot(out_h) >= -0.25:
			continue                                   # 只看朝岸內的面
		var c := xf * (b[0] as Vector3)
		for r: float in [0.15, 0.35, 0.6]:
			var q := c - out_h * r
			if not is_nan(S.h(q.x, q.z)):
				return true
	return false


## 求一顆石頭的修正位移（決定性、有界）。
## 幾何性質（探針 revcurve.txt 實測）：曝光比例對「沿河向外」單調遞增、對「下潛」單調遞減。
## 探針 _probe_stuck.gd 證實：帶外的石頭多數仍存在合法進帶解，只是不在一維線上，
## 所以做「粗掃 + 在粗掃最佳解附近細掃」，並優先選「石背仍有地形」的解（避免背後露空洞）。
## 一律取位移最小者，保留相鄰石塊的尺寸／旋轉／深度變化，不把石列拉平。
## 求一顆石頭的修正位移（決定性、有界）。
## 幾何性質（探針 revcurve.txt 實測）：曝光比例對「沿河向外」單調遞增、對「下潛」單調遞減。
## 探針 _probe_stuck.gd 證實：帶外的石頭多數仍存在合法進帶解；實測最深的一顆埋在地下
## 0.92 m，遠超水平修正可及的 0.26 m，所以垂直方向必須容許「上抬」（使用者明示：
## 底部可埋入地形、上表面必須可見）。上抬與浮空檢查同時生效，抬過頭會被 _accept 擋掉。
## 一律取位移最小者，保留相鄰石塊的尺寸／旋轉／深度變化，不把石列拉平。
## 求一顆石頭的修正位移（決定性、有界）。
## 幾何性質（探針 revcurve.txt 實測）：曝光比例對「沿河向外」與「上抬」都單調遞增，
## 對「下潛」單調遞減。所以對每個水平位移用二分求「剛好進帶」的垂直位置，
## 不必靠固定網格硬碰——前一版網格太疏，實測有 76 顆存在合法進帶解卻找不到。
## 被埋深的石頭允許上抬到 SETTLE_LIFT（使用者明示：底部可埋入地形、上表面必須可見），
## 但仍受浮空（_lowest_gap）與石背貼坡（_back_out）約束：抬過頭會被擋掉。
## 取位移最小者，保留相鄰石塊的尺寸／旋轉／深度變化，不把石列拉平。
static func _solve(m: Mesh, xf: Transform3D, S: TriSampler, R: TriSampler, out_h: Vector3,
		vis: float, reasons: Dictionary, strict: bool, it: Dictionary, boxes: Array, brs: Array,
		parcels: Array) -> Dictionary:
	var buried := vis < SETTLE_LO
	var v_top := SETTLE_LIFT if buried else SETTLE_SINK
	var v_bot := -SETTLE_SINK
	var best := {}
	var best_key := INF
	var fb := {}
	var fb_cost := INF
	var hs: Array = [0.0]
	for k in 1:
		for step: float in [0.06, 0.12, 0.185, 0.25, 0.32, 0.39, 0.45]:
			hs.append(step)
			hs.append(-step)
	for hd: float in hs:
		if absf(hd) > SETTLE_MOVE:
			continue
		var base: Transform3D = xf.translated(out_h * hd)
		# 這個水平位移下的曝光可達範圍；碰不到目標帶就跳過
		var e_top := _expo(m, base.translated(Vector3(0, v_top, 0)), S, out_h)
		var e_bot := _expo(m, base.translated(Vector3(0, v_bot, 0)), S, out_h)
		if e_top < 0.0 or e_bot < 0.0:
			continue
		if e_top < SETTLE_LO or e_bot > SETTLE_HI:
			continue
		# 二分：最小 v 使曝光 >= SETTLE_LO
		var a := v_bot
		var b := v_top
		for _i in 12:
			var mid := (a + b) * 0.5
			var em := _expo(m, base.translated(Vector3(0, mid, 0)), S, out_h)
			if em >= SETTLE_LO or em < 0.0:
				b = mid
			else:
				a = mid
		for dv: float in [0.0, 0.05, 0.12, 0.22, 0.34, 0.48]:
			var v := b + dv
			if v > v_top + 1e-6:
				continue
			var off := out_h * hd + Vector3(0, v, 0)
			var txf := xf.translated(off)
			var e := _expo(m, txf, S, out_h)
			if e < SETTLE_LO or e > SETTLE_HI:
				continue
			var cost := 0.05 * (absf(hd) + absf(v))     # 偏好小位移
			# 嚴格模式：settle 在後置過濾之後才動石頭，候選位置必須自行把關（見 _settle_clear）
			if strict and not _settle_clear(it, txf, boxes, brs, R, parcels):
				continue
			if _lowest_gap(m, txf, S, R) > SETTLE_FLOAT:
				continue
			if _back_out(m, txf, S, out_h) > SETTLE_BACK:
				if cost < fb_cost:
					fb_cost = cost
					fb = {"xf": txf, "vis": e}          # 記錄但不採用（背後會露空洞）
				continue
			var key := cost + (0.0 if _has_back_terrain(m, txf, S, out_h) else 0.6)
			if key < best_key:
				best_key = key
				best = {"xf": txf, "vis": e}
	if not best.is_empty():
		reasons["ok"] = int(reasons.get("ok", 0)) + 1
		return best
	if not fb.is_empty():
		reasons["detach_only"] = int(reasons.get("detach_only", 0)) + 1
		return fb
	reasons["no_band"] = int(reasons.get("no_band", 0)) + 1
	return {}


## 朝向：X 沿 ax（水平）、Y 上、Z＝X×Y
static func _yaw_basis(ax: Vector3) -> Basis:
	var x := Vector3(ax.x, 0, ax.z).normalized()
	return Basis(x, Vector3.UP, x.cross(Vector3.UP))


# ─────────────────────────── 斷面 ───────────────────────────

## 從中心 c 沿 u（單位，水平）往外每 0.1 m 取地形；找水線、護岸腳、岸頂
static func profile(S: TriSampler, c: Vector2, u: Vector2, wl: float, rmax: float) -> Dictionary:
	var hs := PackedFloat32Array()
	var r := 0.0
	while r <= rmax:
		hs.append(S.h(c.x + u.x * r, c.y + u.y * r))
		r += 0.1
	var iw := -1
	for i in hs.size():
		if not is_nan(hs[i]) and hs[i] > wl:
			iw = i
			break
	if iw <= 0 or is_nan(hs[iw - 1]):
		return {"ok": false}
	var itoe := -1
	for i in range(iw - 1, maxi(-1, iw - 30), -1):
		if is_nan(hs[i]):
			break
		if hs[i] <= wl - TOE_BELOW:
			itoe = i
			break
	if itoe < 0:
		var lo := INF
		for i in range(iw - 1, maxi(-1, iw - 30), -1):
			if not is_nan(hs[i]) and hs[i] < lo:
				lo = hs[i]
				itoe = i
	var itop := -1
	for i in range(iw + 1, mini(hs.size() - 6, iw + 90)):
		if is_nan(hs[i]) or is_nan(hs[i + 5]):
			break
		if hs[i] > wl + 0.25 and (hs[i + 5] - hs[i]) / 0.5 < 0.22:
			itop = i
			break
	var out := {"ok": true, "hs": hs, "iw": iw, "itoe": itoe, "itop": itop, "c": c, "u": u, "wl": wl}
	if itop > 0:
		out["h_top"] = hs[itop]
		out["bank_h"] = hs[itop] - wl
		out["slope_deg"] = rad_to_deg(atan2(hs[itop] - wl, maxf((itop - iw) * 0.1, 0.05)))
	return out


static func _r_at_h(P: Dictionary, h: float) -> float:
	var hs: PackedFloat32Array = P["hs"]
	for i in range(int(P["iw"]) - 1, hs.size()):
		if not is_nan(hs[i]) and hs[i] >= h:
			return i * 0.1
	return NAN


static func _pt3(P: Dictionary, r: float, h: float) -> Vector3:
	var c: Vector2 = P["c"]
	var u: Vector2 = P["u"]
	return Vector3(c.x + u.x * r, h, c.y + u.y * r)


# ─────────────────────────── 護岸 ───────────────────────────

## 一站一側的石張り：rows＝允許列數（0＝不做）；big＝最下列用大石；回傳最上列頂 (r, h) 或空
static func _revet(items: Array, P: Dictionary, t2: Vector2, sx: float, rows_allowed: int, big: bool, tag: String,
		key: String) -> Array:
	var hs: PackedFloat32Array = P["hs"]
	var i0 := int(P["itoe"])
	var i1 := int(P["itop"]) if int(P["itop"]) > 0 else mini(hs.size() - 1, int(P["iw"]) + 8)
	if i1 <= i0 + 2:
		return []
	var arc := PackedFloat32Array([0.0])
	for i in range(i0 + 1, i1 + 1):
		arc.append(arc[arc.size() - 1] + Vector2(0.1, hs[i] - hs[i - 1]).length())
	var total := arc[arc.size() - 1]
	var n := maxi(1, roundi(total / PH))
	var rl := total / n
	if rl / PH > 1.45:
		n += 1
		rl = total / n
	var rows := mini(n, mini(rows_allowed, MAX_COURSES))
	if rows_allowed >= 2 and rows < 2 and total >= PH * 1.3:
		rows = 2                       # 人工護岸段至少要兩列，否則該站讀成「只有單列」＝護岸帶消失
	var u: Vector2 = P["u"]
	var u3 := Vector3(u.x, 0, u.y)
	var wl := float(P["wl"])
	var top := []
	var r := _rng(key)
	for k in rows:
		var a0 := k * rl
		var a1 := (k + 1) * rl
		var B := _arc_pt(hs, arc, i0, a0)
		var T := _arc_pt(hs, arc, i0, a1)
		var d := (T - B).normalized()
		var n2 := Vector2(-d.y, d.x)
		var emax := -INF
		for i in range(i0, i1 + 1):
			var q := Vector2(i * 0.1, hs[i])
			var along := (q - B).dot(d)
			if along < -0.05 or along > (T - B).length() + 0.05:
				continue
			emax = maxf(emax, (q - B).dot(n2))
		var o := maxf(emax, 0.0) + FACE_OFF
		var C := (B + T) * 0.5 + n2 * o
		var n3 := u3 * n2.x + Vector3.UP * n2.y
		var y3 := u3 * d.x + Vector3.UP * d.y
		var x3 := y3.cross(n3)
		var sy := (T - B).length() / PH
		var b := Basis(x3 * sx, y3 * sy, n3)
		var pos := _pt3(P, C.x, C.y)
		var mod := _pick(r, "revb" if (big and k == 0) else "rev")
		var row_it := _item(mod, Transform3D(b, pos), "rev", wl, tag)
		row_it["row"] = k              # 砌築列序（0＝最下層大石）；gate 直接量實際列數
		row_it["tan"] = t2             # 沿河切線（被橋台／路帶佔位時沿此微移，不整列刪除）
		items.append(row_it)
		top = [T.x, T.y, o]
	return top


static func _arc_pt(hs: PackedFloat32Array, arc: PackedFloat32Array, i0: int, a: float) -> Vector2:
	for j in range(1, arc.size()):
		if arc[j] >= a or j == arc.size() - 1:
			var t := clampf((a - arc[j - 1]) / maxf(arc[j] - arc[j - 1], 1e-6), 0.0, 1.0)
			var r0 := (i0 + j - 1) * 0.1
			return Vector2(r0 + t * 0.1, lerpf(hs[i0 + j - 1], hs[i0 + j], t))
	return Vector2(i0 * 0.1, hs[i0])


## 笠石：岸頂（護岸最上列頂）往岸內 0.16 m，一站 2 塊
static func _caps(items: Array, S: TriSampler, R: TriSampler, P: Dictionary, t2: Vector2, w_along: float, top: Array,
		tag: String, key: String) -> void:
	var u: Vector2 = P["u"]
	var z3 := -Vector3(u.x, 0, u.y)
	var x3 := Vector3.UP.cross(z3)
	var r := _rng(key)
	var sx := (w_along * 0.5) / 1.15 * 1.02
	for q: float in [-0.25, 0.25]:
		var rc := float(top[0]) + 0.16
		var p := _pt3(P, rc, 0.0) + Vector3(t2.x, 0, t2.y) * (q * w_along)
		var g := -INF
		for o: Vector2 in [Vector2(0, 0), Vector2(0.24, 0), Vector2(-0.24, 0)]:
			var pp := p + Vector3(u.x, 0, u.y) * o.x
			var hh := S.h(pp.x, pp.z)
			if not is_nan(hh):
				g = maxf(g, hh)
		if g == -INF:
			continue
		# 笠石埋入土肩 0.10 m：保留收頭讀性，避免玩家視角讀成連續巨大板塊
		var c := Vector3(p.x, g + CAP_TOP - 0.34, p.z)
		if _on_road(R, c, x3 * 0.55 * sx, z3 * 0.22):
			continue
		items.append(_item(_pick(r, "cap"), Transform3D(Basis(x3 * sx, Vector3.UP, z3), c), "cap", float(P["wl"]), tag))


# ─────────────────────────── 自然岸件 ───────────────────────────

## 巨石：原點＝足跡最低地面＋0.1 s（底埋 ≥ 0.18 s）
static func _boulder(items: Array, S: TriSampler, p: Vector2, sc: float, wl: float, tag: String, r: RandomNumberGenerator,
		flat := 1.0) -> void:
	var lo := INF
	for o: Vector2 in [Vector2.ZERO, Vector2(0.45, 0), Vector2(-0.45, 0), Vector2(0, 0.45), Vector2(0, -0.45),
			Vector2(0.32, 0.32), Vector2(-0.32, 0.32), Vector2(0.32, -0.32), Vector2(-0.32, -0.32)]:
		var hh := S.h(p.x + o.x * sc, p.y + o.y * sc)
		if is_nan(hh):
			return
		lo = minf(lo, hh)
	var yaw := r.randf() * TAU
	# 陡坡上以足跡最低點落位 → 中心地面可能高過石頂（整顆埋）：石頂至少露出中心地面 0.15·sc，否則不放
	var hc := S.h(p.x, p.y)
	if lo + 0.1 * sc + 0.46 * sc * flat < hc + 0.15 * sc:
		return
	var b := Basis(Vector3.UP, yaw).scaled(Vector3(sc, sc * flat, sc))
	var shape := {}
	if sc >= 0.9:
		shape = {"size": Vector3(0.75, 0.62 * flat, 0.75) * sc, "xf": Transform3D(Basis(Vector3.UP, yaw), Vector3(0, 0.12 * sc * flat, 0))}
	items.append(_item(_pick(r, "bld"), Transform3D(b, Vector3(p.x, lo + 0.1 * sc, p.y)), "bld", wl, tag, shape))


## 河原石群：貼地形平面（三點擬合）
static func _cobbles(items: Array, S: TriSampler, p: Vector2, sc: float, wl: float, tag: String,
		r: RandomNumberGenerator) -> void:
	var e := 0.6 * sc
	var h0 := S.h(p.x, p.y)
	var hx := S.h(p.x + e, p.y)
	var hz := S.h(p.x, p.y + e)
	var hx2 := S.h(p.x - e, p.y)
	var hz2 := S.h(p.x, p.y - e)
	for hh: float in [h0, hx, hz, hx2, hz2]:
		if is_nan(hh):
			return
	var tx := Vector3(2 * e, hx - hx2, 0).normalized()
	var tz := Vector3(0, hz - hz2, 2 * e).normalized()
	var ny := tz.cross(tx).normalized()
	if ny.y < 0.8:
		return
	var yaw := r.randf() * TAU
	var fx := Vector3(cos(yaw), 0, -sin(yaw))
	fx = (fx - ny * fx.dot(ny)).normalized()
	var fz := fx.cross(ny)
	var b := Basis(fx * sc, ny * sc, fz * sc)
	var lo := minf(minf(hx, hx2), minf(hz, hz2))
	var y := minf(h0, (hx + hx2 + hz + hz2) * 0.25) - 0.015 * sc
	items.append(_item(_pick(r, "cob"), Transform3D(b, Vector3(p.x, maxf(y, lo), p.y)), "cob", wl, tag))


## 木樁列：沿岸 n 根、間距 0.24、頂高出地 0.2–0.55
static func _piles(items: Array, S: TriSampler, P: Dictionary, t2: Vector2, n: int, r_at: float, tag: String,
		r: RandomNumberGenerator) -> void:
	var wl := float(P["wl"])
	for i in n:
		var p3 := _pt3(P, r_at + r.randf_range(-0.04, 0.04), 0) + Vector3(t2.x, 0, t2.y) * ((i - (n - 1) * 0.5) * 0.24)
		var g := S.h(p3.x, p3.z)
		if is_nan(g):
			continue
		var above := r.randf_range(0.2, 0.55)
		var b := Basis(Vector3.UP, r.randf() * TAU).rotated(Vector3(t2.x, 0, t2.y).normalized(), r.randf_range(-0.06, 0.06))
		items.append(_item(_pick(r, "pile"), Transform3D(b, Vector3(p3.x, g - 0.95 + above, p3.z)), "pile", wl, tag))


static func _shig(items: Array, S: TriSampler, P: Dictionary, t2: Vector2, r_at: float, tag: String,
		r: RandomNumberGenerator) -> void:
	var p3 := _pt3(P, r_at, 0)
	var ax := Vector3(t2.x, 0, t2.y)
	var lo := INF
	for q: float in [-0.95, 0.0, 0.95]:
		var hh := S.h(p3.x + ax.x * q, p3.z + ax.z * q)
		if is_nan(hh):
			return
		lo = minf(lo, hh)
	items.append(_item("rb_shig", Transform3D(_yaw_basis(ax), Vector3(p3.x, lo - 0.02, p3.z)), "shig", float(P["wl"]), tag))


# ─────────────────────────── 親水：雁木石段＋平台 ───────────────────────────

static func _stair(items: Array, S: TriSampler, R: TriSampler, body: Dictionary, s0: float, side: float, wl: float,
		tag: String) -> Dictionary:
	var pts: PackedVector2Array = body["pts"]
	var cum: PackedFloat32Array = body["cum"]
	var rmax := float(body["rmax"])
	var P0 := _prof_s(S, pts, cum, s0, side, wl, rmax)
	if not P0["ok"] or int(P0["itop"]) <= 0:
		return {}
	var htop := float(P0["h_top"])
	var drop := htop - (wl + LAND_TOP)
	var n := maxi(2, ceili(drop / STEP_RISE_MAX))
	var rise := drop / n
	var r := _rng(tag)
	var steps := 0
	var tops: Array = []
	# 沿岸步距：以「岸邊實際切向距離」解（主河寬且彎，中心線 0.44 m 在岸邊會拉成 ~1.0 m → 踏面間露土縫，2026-09-28 審查）
	var si := s0
	var prev := Vector3(INF, 0, 0)
	for i in n:
		var hi := htop - (i + 1) * rise
		var ds := STEP_TREAD
		var c := Vector3.ZERO
		var x3 := Vector3.ZERO
		for it in 3:
			var Pi := _prof_s(S, pts, cum, si + ds, side, wl, rmax)
			if not Pi["ok"]:
				return {}
			var rin := _r_at_h(Pi, hi)
			if is_nan(rin):
				return {}
			var u: Vector2 = Pi["u"]
			x3 = -Vector3(u.x, 0, u.y)
			# 踏面中心＝地形到達踏面高度處往水側 0.35 m：約 0.3 m 切入岸坡、1.0 m 外露，石身往下 1.4 m 填住斜面
			c = _pt3(Pi, rin - 0.35, hi)
			if i == 0 or prev.x == INF:
				break
			var tz := x3.cross(Vector3.UP).normalized()
			var dt := absf((c - prev).dot(tz))
			if dt < 0.05:
				break
			ds *= (STEP_TREAD - 0.02) / dt
		si += ds
		prev = c
		var b := Basis(x3, Vector3.UP, x3.cross(Vector3.UP))
		items.append(_item(_pick(r, "step"), Transform3D(b, c), "step", wl, tag,
			{"size": Vector3(1.3, 0.36, STEP_TREAD), "xf": Transform3D(Basis.IDENTITY, Vector3(0, -0.18, 0))}))
		tops.append(c)
		steps += 1
	var sl := si + 0.5 * STEP_TREAD + 0.95
	var PL := _prof_s(S, pts, cum, sl, side, wl, rmax)
	if not PL["ok"]:
		return {}
	var rl := _r_at_h(PL, wl + LAND_TOP)
	if is_nan(rl):
		return {}
	var tl: Vector2 = _along(pts, cum, sl)[1]
	var t3 := Vector3(tl.x, 0, tl.y).normalized()
	var lc := _pt3(PL, rl + 0.3 - 0.7, wl + LAND_TOP)
	items.append(_item("rb_land", Transform3D(Basis(t3, Vector3.UP, t3.cross(Vector3.UP)), lc), "land", wl, tag,
		{"size": Vector3(1.9, 0.5, 1.4), "xf": Transform3D(Basis.IDENTITY, Vector3(0, -0.25, 0))}))
	# 繫船樁（綁繩）：平台下游端水邊
	var PM := _prof_s(S, pts, cum, sl + 1.35, side, wl, rmax)
	if PM["ok"]:
		var pm := _pt3(PM, float(PM["iw"]) * 0.1 - 0.15, 0)
		var gm := S.h(pm.x, pm.z)
		if not is_nan(gm):
			items.append(_item("rb_pile_r", Transform3D(Basis.IDENTITY, Vector3(pm.x, wl + 0.72 - 0.95, pm.z)), "pile", wl, tag))
	# 岸頂矮欄：石段上方（落差最大段）沿岸 2 m
	var sr := s0 + minf(n * STEP_TREAD, 2.6) * 0.5 + 0.3
	var PR := _prof_s(S, pts, cum, sr, side, wl, rmax)
	if PR["ok"] and int(PR["itop"]) > 0:
		var tr: Vector2 = _along(pts, cum, sr)[1]
		var rp := _pt3(PR, int(PR["itop"]) * 0.1 + 0.6, 0)
		_rail(items, S, R, rp, Vector3(tr.x, 0, tr.y), wl, tag)
	return {"s0": s0, "side": side, "steps": steps, "rise": rise, "land": lc, "tops": tops, "len": n * STEP_TREAD + 1.9}


static func _rail(items: Array, S: TriSampler, R: TriSampler, c: Vector3, ax: Vector3, wl: float, tag: String) -> bool:
	var a := Vector3(ax.x, 0, ax.z).normalized()
	var h1 := S.h(c.x + a.x * 0.95, c.z + a.z * 0.95)
	var h2 := S.h(c.x - a.x * 0.95, c.z - a.z * 0.95)
	if is_nan(h1) or is_nan(h2) or absf(h1 - h2) > 0.35:
		return false
	var b := _yaw_basis(a)
	var p := Vector3(c.x, minf(h1, h2), c.z)
	if _on_road(R, p, a * 1.0, b.z * 0.06):
		return false
	var tilt := atan2(h1 - h2, 1.9)
	b = b.rotated(b.z.normalized(), tilt)
	items.append(_item("rb_rail", Transform3D(b, p), "rail", wl, tag,
		{"size": Vector3(2.04, 0.92, 0.12), "xf": Transform3D(Basis.IDENTITY, Vector3(0, 0.40, 0))}))
	return true


static func _prof_s(S: TriSampler, pts: PackedVector2Array, cum: PackedFloat32Array, s: float, side: float, wl: float,
		rmax: float) -> Dictionary:
	var at: Array = _along(pts, cum, s)
	var c: Vector2 = at[0]
	var t: Vector2 = (at[1] as Vector2).normalized()
	var u := Vector2(-t.y, t.x) * side
	var P := profile(S, c, u, wl, rmax)
	P["s"] = s
	return P


# ─────────────────────────── 主流程 ───────────────────────────

## 決定性擺放清單。回傳 {"items": [...], "stairs": [...], "bridges": [...], "stats": {...}}
const ROAD_OK := ["flag", "curb", "rev", "revb", "step", "land"]
## LOD1（75 m 外）不放：平貼路面的鋪石／見切り石（起伏 ≤ 0.03 m，遠處次像素；路面帶本身仍在）
const LOD1_SKIP := ["flag", "curb"]
## 構件標稱半尺寸（擺放後乘縮放；只用於與橋碰撞體的保守重疊測試）
const CEN := {"rev": Vector3(0, 0, -0.11), "revb": Vector3(0, 0, -0.1), "cap": Vector3(0, 0.08, 0), "bld": Vector3(0, 0.12, 0),
	"curb": Vector3(0, -0.17, 0), "flag": Vector3(0, -0.08, 0), "step": Vector3(0, -0.7, 0), "land": Vector3(0, -0.55, 0),
	"pile": Vector3(0, 0.08, 0), "piler": Vector3(0, 0.08, 0), "rail": Vector3(0, 0.2, 0), "shig": Vector3(0, 0.1, 0)}
const HALF := {"rev": Vector3(1.2, 0.45, 0.2), "revb": Vector3(1.2, 0.45, 0.2), "cap": Vector3(0.56, 0.12, 0.24),
	"bld": Vector3(0.5, 0.35, 0.5), "cob": Vector3(0.75, 0.08, 0.75), "flag": Vector3(0.3, 0.08, 0.25),
	"curb": Vector3(0.53, 0.17, 0.15), "step": Vector3(0.62, 0.7, 0.21), "land": Vector3(0.95, 0.55, 0.69),
	"pile": Vector3(0.1, 0.87, 0.1), "piler": Vector3(0.11, 0.87, 0.12), "rail": Vector3(1.02, 0.65, 0.05),
	"shig": Vector3(1.01, 0.45, 0.07)}


## 橋／地標／建築 碰撞體（世界 OBB）：[Transform3D（含半尺寸縮放的單位盒→世界）] ；取 shape debug mesh AABB 當局部盒
static func _bridge_boxes(v: Node3D) -> Array:
	var out: Array = []
	var css: Array = []
	for gp: String in ["Roads/Bridges", "Landmarks", "Districts"]:
		var g := v.get_node_or_null(gp)
		if g != null:
			css.append_array(g.find_children("*", "CollisionShape3D", true, false))
	for cs in css:
		var c := cs as CollisionShape3D
		if c.shape == null or c.disabled:
			continue
		var ab := c.shape.get_debug_mesh().get_aabb()
		var xf := rel_xf(c, v) * Transform3D(Basis.from_scale(ab.size * 0.5), ab.get_center())
		# [世界→單位盒, 世界中心, 外接半徑]（半徑先粗篩）
		out.append([xf.affine_inverse(), xf.origin, (xf.basis * Vector3.ONE).length() + ab.size.length() * 0.5,
			"%s/%s" % [String(cs.get_parent().name), String(cs.name)]])
	return out


## 件（內縮 20 % 的 OBB）是否碰到橋／地標／建築碰撞體或落在橋面矩形內（橋面下 0.6 m 以上）
static func _hits_bridge(it: Dictionary, inv_boxes: Array, brs: Array) -> bool:
	return _bridge_hit(it, inv_boxes, brs) != ""


## 回傳占位原因：""（淨空）／"deck"（橋面矩形內）／"box"（壓到橋台等地標碰撞體）。
## 分開回報才能判斷該「整站沿河微移」還是「根本在橋下、不該歸類為人工護岸」。
static func _bridge_hit(it: Dictionary, inv_boxes: Array, brs: Array) -> String:
	var xf: Transform3D = it["xf"]
	var k := String(it["k"])
	var o := xf.origin
	for b: Dictionary in brs:
		var lp := (b["F"] as Transform3D).affine_inverse() * o
		if absf(lp.x) < float(b["W"]) * 0.5 and absf(lp.z) < float(b["L"]) * 0.5 and lp.y > -0.6:
			return "deck"
	# 平貼路面的鋪石／見切り石：頂＝路面，橋台碰撞體頂也＝路面 → 只驗「不進橋面」
	if k in LOD1_SKIP:
		return ""
	# 量尺必須「不寬鬆於 gate 的 parcel_fit」（gate 用物理查詢把件 OBB 打進碰撞盒）。
	# 歷史教訓：舊版純 0.25 m 離散取樣會從薄橋台之間穿過（實測 cap@Canal/R/22 被判淨空、
	# 卻命中 Collision/Abut_S）；改用 SAT 後仍有極少數浮點邊界情形。
	# 因此取兩者之「聯集」：SAT（精確、快）或 密取樣（覆蓋 SAT 的邊界情形）。
	# 聯集只會更保守，不會讓石頭被放進橋台；代價是偶爾多擋掉幾顆，由 settle／微移救回。
	var ma := mesh_aabb(String(it["m"]))
	var sc := xf.basis.get_scale()
	var half := ma.size * sc * 0.8 * 0.5
	var cv: Vector3 = ma.get_center()
	var cw: Vector3 = xf * cv
	var rot := xf.basis.orthonormalized()
	var ns := clampi(int(ceil(half.length() / 0.12)), 4, 8)
	for bx: Array in inv_boxes:
		if (bx[1] as Vector3).distance_to(cw) > float(bx[2]) + half.length():
			continue
		var inv: Transform3D = bx[0]
		var hit := _obb_unit_hit(rot, cw, half, inv)
		if not hit:
			for ix in ns:
				for iy in ns:
					for iz in ns:
						# 取樣覆蓋整個查詢盒（half 已是 gate 的 20 % 內縮盒）。
						# 曾在這裡再縮到 ±0.88 ＝ 內縮兩次，漏掉「淺淺擦到橋面」的件（實測 cap@Canal/R/88）。
						var lp := cv + Vector3(
							half.x * lerpf(-1.0, 1.0, float(ix) / float(ns - 1)),
							half.y * lerpf(-1.0, 1.0, float(iy) / float(ns - 1)),
							half.z * lerpf(-1.0, 1.0, float(iz) / float(ns - 1)))
						var q: Vector3 = inv * (xf * lp)
						if absf(q.x) < 1.0 and absf(q.y) < 1.0 and absf(q.z) < 1.0:
							hit = true
							break
					if hit:
						break
				if hit:
					break
		if hit:
			if bx.size() > 3:
				return "box:%s" % String(bx[3])
			return "box"
	return ""


## OBB（件）與單位立方體 [-1,1]^3 是否相交：15 軸 SAT（Ericson, Real-Time Collision Detection）。
## inv_box 把世界映射到該碰撞盒的單位空間（盒心在原點、半尺寸 1）。
## rot／cw／half＝OBB 的朝向、世界中心、半尺寸（已含縮放）。盒空間為中心原點、半尺寸 1。
static func _obb_unit_hit(rot: Basis, cw: Vector3, half: Vector3, inv_box: Transform3D) -> bool:
	var b := inv_box * Transform3D(rot, cw)
	var t: Vector3 = b.origin                    # OBB 中心（盒空間）
	var u0 := b.basis.x
	var u1 := b.basis.y
	var u2 := b.basis.z
	var l0 := u0.length()
	var l1 := u1.length()
	var l2 := u2.length()
	if l0 < 1e-9 or l1 < 1e-9 or l2 < 1e-9:
		return false
	var a0 := u0 / l0
	var a1 := u1 / l1
	var a2 := u2 / l2
	var E := Vector3(half.x * l0, half.y * l1, half.z * l2)
	var axes: Array = [a0, a1, a2]
	var abs0 := Vector3(absf(a0.x), absf(a0.y), absf(a0.z))
	var abs1 := Vector3(absf(a1.x), absf(a1.y), absf(a1.z))
	var abs2 := Vector3(absf(a2.x), absf(a2.y), absf(a2.z))
	# 單位盒的三個軸（盒半尺寸 1，盒心為原點）
	for i in 3:
		var rb := E.x * abs0[i] + E.y * abs1[i] + E.z * abs2[i]
		if absf(t[i]) > 1.0 + rb:
			return false
	# OBB 的三個軸
	for i in 3:
		var a: Vector3 = axes[i]
		var r := E.x * absf(a.dot(a0)) + E.y * absf(a.dot(a1)) + E.z * absf(a.dot(a2))
		if absf(t.dot(a)) > E[i] + absf(a.x) + absf(a.y) + absf(a.z):
			return false
	# 9 個叉積軸：必須是「OBB 軸 × 盒軸(a_i × e_j)」。
	# 誤寫成 a_i × a_j 會退化為自身第三軸 → 9 條全失效，只剩 6 條面軸，OBB vs OBB 就會漏檢。
	for i in 3:
		var a: Vector3 = axes[i]
		for j in 3:
			var bj := Vector3.ZERO
			bj[j] = 1.0
			var ax := a.cross(bj)
			if ax.length_squared() < 1e-12:
				continue
			ax = ax.normalized()
			var r0 := E.x * absf(ax.dot(a0)) + E.y * absf(ax.dot(a1)) + E.z * absf(ax.dot(a2))
			var r1 := absf(ax.x) + absf(ax.y) + absf(ax.z)
			if absf(t.dot(ax)) > r0 + r1:
				return false
	return true


static func plan(v: Node3D, L: Dictionary) -> Dictionary:
	var S := terrain_sampler(v)
	var R := road_sampler(v)
	var WL := water_levels(v)
	var items: Array = []
	var stats := {}
	var parcels: Array = []
	var pj: Variant = JSON.parse_string(FileAccess.get_file_as_string(PARCELS))
	if pj is Dictionary:
		for pc: Dictionary in pj["parcels"]:
			parcels.append(TLib.pts(pc["footprint"]))
	# 橋：灰盒錨點（世界 frame、橋長、寬、高差、跨哪條水）
	var brs: Array = []
	var bg := v.get_node_or_null("Roads/Bridges")
	if bg != null:
		var names: Array = []
		for b in bg.get_children():
			if String(b.name).begins_with("Bridge_"):
				names.append(String(b.name))
		names.sort()
		for nm: String in names:
			var a := bg.get_node(nm) as Node3D
			var dims := HLib.bridge_dims(a)
			if dims.is_empty():
				continue
			var F := rel_xf(a, v) * HLib.bridge_frame(a)
			var wn := "MainRiver" if nm.ends_with("_River") else ("Canal" if nm.ends_with("_Canal") else nm.get_slice("_", nm.get_slice_count("_") - 1))
			brs.append({"name": nm, "F": F, "L": float(dims["L"]), "W": float(dims["W"]), "dh": float(dims["dh"]), "water": wn})
	# 水體
	var bodies: Array = []
	for w: Dictionary in PLib.waters(L):
		var nm := String(w["name"])
		if not WL.has(nm):
			continue
		var pts: PackedVector2Array = w["pts"]
		var hwa: PackedFloat32Array = w["hw"]
		var hwmax := 0.0
		for q in hwa:
			hwmax = maxf(hwmax, q)
		bodies.append({"name": nm, "pts": pts, "cum": _cum(pts), "rmax": hwmax + 14.0})
	for body: Dictionary in bodies:
		_body(items, S, R, WL, body, brs, stats)
	# 橋頭
	for br: Dictionary in brs:
		_bridge_head(items, S, R, WL, br, stats)
	# 地塊內一律不放（防呆；layout 保證地塊離水）；橋的 Hero 碰撞體（橋台／排架 proxy）與橋面矩形內不放；
	# 路帶上只准鋪石類（巨石／河原石／木樁／しがらみ／矮欄／笠石 不擋路）
	var boxes := _bridge_boxes(v)
	# 結構佔位：同站整組沿河微移（保住砌列節奏，不讓上層單獨消失）
	var nudged := _station_fix(items, stats.get("tangents", {}), boxes, brs, R, parcels)
	var kept: Array = []
	var dropped := 0
	var d_br := 0
	var d_road := 0
	var drop_by_tag := {}       # 診斷：哪個站點的護岸件被後置過濾丟掉（gate／稽核用）
	for it: Dictionary in items:
		var o: Vector3 = (it["xf"] as Transform3D).origin
		var inside := false
		for pp: PackedVector2Array in parcels:
			if Geometry2D.is_point_in_polygon(Vector2(o.x, o.z), pp):
				inside = true
				break
		if inside:
			dropped += 1
			_drop_add(drop_by_tag, it, "parcel")
			continue
		var hr := _bridge_hit(it, boxes, brs)
		if hr != "":
			if _fit_free(it, boxes, brs, R, parcels):
				nudged += 1
				kept.append(it)
				continue
			d_br += 1
			_drop_add(drop_by_tag, it, "bridge_" + hr)
			continue
		if not String(it["k"]) in ROAD_OK and not is_nan(R.h(o.x, o.z)):
			if _fit_free(it, boxes, brs, R, parcels):
				nudged += 1
				kept.append(it)
				continue
			d_road += 1
			_drop_add(drop_by_tag, it, "road")
			continue
		kept.append(it)
	stats["drop_by_tag"] = drop_by_tag
	stats["nudged"] = nudged
	stats["dropped_in_parcel"] = dropped
	stats["dropped_bridge"] = d_br
	stats["dropped_on_road"] = d_road
	# 護岸石砌清理（R3）：逐顆有界修正 placement／埋深，只動已保留的件
	var st_by_key := {}
	for s: Dictionary in stats.get("stations", []):
		var sk := "%s|%s" % [String(s["water"]), ("L" if float(s["side"]) < 0.0 else "R")]
		if not st_by_key.has(sk):
			st_by_key[sk] = []
		(st_by_key[sk] as Array).append(s)
	stats["settle"] = {"moved": 0, "rescued": 0, "sunk": 0, "kept": 0, "hist": {}}
	if settle_enabled():
		stats["settle"] = _settle_stonework(kept, st_by_key, S, R, load_lib(), boxes, brs, parcels)
	var kinds := {}
	for it: Dictionary in kept:
		kinds[it["k"]] = int(kinds.get(it["k"], 0)) + 1
	stats["kinds"] = kinds
	stats["items"] = kept.size()
	return {"items": kept, "stairs": stats.get("stairs", []), "bridges": brs, "stats": stats}


## 診斷：記錄某站某原因被丟棄的件數（不影響擺放結果）
static func _drop_add(acc: Dictionary, it: Dictionary, why: String) -> void:
	var tg := String(it.get("tag", ""))
	if not acc.has(tg):
		acc[tg] = {}
	var d: Dictionary = acc[tg]
	var k := "%s:%s" % [String(it.get("k", "?")), why]
	d[k] = int(d.get(k, 0)) + 1


## 橋台／橋面／路帶佔位時：護岸石不直接丟棄。
## 使用者要求「龍神橋、水車、親水石階、橋頭附近要做更完整的人工護岸」，
## 所以先沿河微移（≤0.8 m），仍不行就沿河把面板裁短（用 scale，使用者明示可調），
## 最後才放棄。只動 placement／scale，不動河道、水位、地形。
static func _fit_free(it: Dictionary, boxes: Array, brs: Array, R: TriSampler,
		parcels: Array) -> bool:
	var tg: Variant = it.get("tan", null)
	if tg == null:
		return false
	var t: Vector2 = tg
	var dir3 := Vector3(t.x, 0, t.y)
	var base_xf: Transform3D = it["xf"]
	# 候選 1：沿河微移
	for step: float in [0.3, -0.3, 0.55, -0.55, 0.8, -0.8]:
		var cand := it.duplicate()
		cand["xf"] = base_xf.translated(dir3 * step)
		if _free_at(cand, boxes, brs, R, parcels):
			it["xf"] = cand["xf"]
			return true
	return false


## 位置是否淨空（不在地塊內、不壓橋／路）
static func _free_at(it: Dictionary, boxes: Array, brs: Array, R: TriSampler,
		parcels: Array) -> bool:
	var o: Vector3 = (it["xf"] as Transform3D).origin
	for pp: PackedVector2Array in parcels:
		if Geometry2D.is_point_in_polygon(Vector2(o.x, o.z), pp):
			return false
	if _hits_bridge(it, boxes, brs):
		return false
	if not String(it["k"]) in ROAD_OK and not is_nan(R.h(o.x, o.z)):
		return false
	return true


## settle 候選位置的淨空檢查（與後置過濾同一套標準）：不在地塊內、不壓橋／路。
## 必須帶完整件字典：淨空判定讀 mesh AABB（it["m"]），只傳 k/xf 會退回預設盒而低估體積。
static func _settle_clear(it: Dictionary, xf: Transform3D, boxes: Array, brs: Array, R: TriSampler,
		parcels: Array) -> bool:
	return _free_at({"k": it["k"], "m": it["m"], "xf": xf}, boxes, brs, R, parcels)


## 結構（橋台／地標／水車）佔位時：整個站（tag）的所有件一起沿河微移，
## 避免只移動撞到結構的那一列 → 該站砌石帶剩單列、讀成「護岸突然變薄」。
## 位移有界（≤ 0.7 m）、決定性；只動 placement，不動河道／水位／地形。
static func _station_fix(items: Array, tang_map: Dictionary, boxes: Array, brs: Array,
		R: TriSampler, parcels: Array) -> int:
	var groups := {}
	for it: Dictionary in items:
		var tg := String(it["tag"])
		if not tang_map.has(tg):
			continue
		if not groups.has(tg):
			groups[tg] = []
		(groups[tg] as Array).append(it)
	var fixed := 0
	for tg: String in groups:
		var g: Array = groups[tg]
		var blocked := false
		for it: Dictionary in g:
			if not _free_at(it, boxes, brs, R, parcels):
				blocked = true
				break
		if not blocked:
			continue
		var t: Vector2 = tang_map[tg]
		var dir3 := Vector3(t.x, 0, t.y)
		for step: float in [0.35, -0.35, 0.7, -0.7, 1.15, -1.15, 1.6, -1.6, 2.1, -2.1]:
			var ok := true
			for it: Dictionary in g:
				var cand := it.duplicate()
				cand["xf"] = (it["xf"] as Transform3D).translated(dir3 * step)
				if not _free_at(cand, boxes, brs, R, parcels):
					ok = false
					break
			if ok:
				for it: Dictionary in g:
					it["xf"] = (it["xf"] as Transform3D).translated(dir3 * step)
				fixed += 1
				break
	return fixed


static func _body(items: Array, S: TriSampler, R: TriSampler, WL: Dictionary, body: Dictionary, brs: Array,
		stats: Dictionary) -> void:
	var nm := String(body["name"])
	var pts: PackedVector2Array = body["pts"]
	var cum: PackedFloat32Array = body["cum"]
	var total := cum[cum.size() - 1]
	var W: WaterLv = WL[nm]
	var rmax := float(body["rmax"])
	var tangs := {}                 # tag → 沿河切線（結構佔位時整站同步微移用）
	# 橋位（沿水道 s）：排除區＝橋寬／2＋0.15（依交角放大）；wing＝護岸強制區
	var excl: Array = []
	var wings: Array = []
	for br: Dictionary in brs:
		if String(br["water"]) != nm:
			continue
		var F: Transform3D = br["F"]
		var p := Vector2(F.origin.x, F.origin.z)
		var sb := _proj_s(pts, cum, p)
		var tb: Vector2 = (_along(pts, cum, sb)[1] as Vector2).normalized()
		var bz := Vector2(F.basis.z.x, F.basis.z.z).normalized()
		var sn := maxf(0.6, absf(bz.cross(tb)))
		var half := (float(br["W"]) * 0.5 + 0.15) / sn
		excl.append([sb - half, sb + half])
		var wing := CANAL_BRIDGE_FULL if nm == "Canal" else (RIVER_WING if nm == "MainRiver" else STREAM_WING)
		wings.append([sb - half - wing, sb + half + wing, sb, half])
	# 橋體排除區匯出（gate 的 coverage 需剔除「橋下本無護岸」的區段，否則會誤算成空窗）
	if not stats.has("excl"):
		stats["excl"] = []
	for e: Array in excl:
		(stats["excl"] as Array).append({"water": nm, "s0": float(e[0]), "s1": float(e[1])})
	# 站點：扣掉排除區後均分
	var ivs: Array = [[0.0, total]]
	for e: Array in excl:
		var nv: Array = []
		for iv: Array in ivs:
			if float(e[1]) <= float(iv[0]) or float(e[0]) >= float(iv[1]):
				nv.append(iv)
				continue
			if float(e[0]) > float(iv[0]):
				nv.append([float(iv[0]), float(e[0])])
			if float(e[1]) < float(iv[1]):
				nv.append([float(e[1]), float(iv[1])])
		ivs = nv
	var sp := float(SPACING[nm])
	var st: Array = []
	for iv: Array in ivs:
		var ln := float(iv[1]) - float(iv[0])
		if ln < 1.0:
			continue
		var n := maxi(1, roundi(ln / sp))
		var d := ln / n
		for i in n:
			st.append({"s": float(iv[0]) + d * (i + 0.5), "w": d})
	# 斷面（兩側）
	for q: Dictionary in st:
		var at: Array = _along(pts, cum, float(q["s"]))
		var c: Vector2 = at[0]
		var wl := W.at(c.x, c.y)
		q["wl"] = wl
		q["c"] = c
		q["t"] = (at[1] as Vector2).normalized()
		for side: float in [-1.0, 1.0]:
			q["P%d" % int(side)] = _prof_s(S, pts, cum, float(q["s"]), side, wl, rmax) if not is_nan(wl) else {"ok": false}
	# 親水點（先選，護岸要讓位給它）
	var stairs: Array = stats.get("stairs", [])
	var busy: Array = []   # [s0, s1, side]
	if nm == "Canal" or nm == "MainRiver":
		var want := 3 if nm == "Canal" else 1
		var cands: Array = []
		for q: Dictionary in st:
			for side: float in [-1.0, 1.0]:
				var P: Dictionary = q["P%d" % int(side)]
				if not P["ok"] or int(P["itop"]) <= 0:
					continue
				var bh := float(P["bank_h"])
				var sd := float(P["slope_deg"])
				if bh < 1.2 or bh > 2.8 or sd < 14.0 or sd > 50.0:
					continue
				var far := true
				for wg: Array in wings:
					if absf(float(q["s"]) - float(wg[2])) < float(wg[3]) + 20.0:
						far = false
				if not far or float(q["s"]) < 15.0 or float(q["s"]) > total - 20.0:
					continue
				# 岸頂外 1–10 m 內有路面（走得到）
				var road_d := INF
				var top_r := int(P["itop"]) * 0.1
				for k in range(0, 20):
					var pp := _pt3(P, top_r + 0.5 + k * 0.5, 0)
					if not is_nan(R.h(pp.x, pp.z)):
						road_d = 0.5 + k * 0.5
						break
				if road_d == INF:
					continue
				cands.append([road_d + absf(bh - 2.0) * 0.5, float(q["s"]), side])
		cands.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]) or (float(a[0]) == float(b[0]) and float(a[1]) < float(b[1])))
		var picked: Array = []
		for cd: Array in cands:
			if picked.size() >= want:
				break
			var ok := true
			for pk: Array in picked:
				if absf(float(pk[1]) - float(cd[1])) < 70.0:
					ok = false
			if not ok:
				continue
			var tag := "%s/stair_%d" % [nm, picked.size() + 1]
			var wl0 := W.at(_along(pts, cum, float(cd[1]))[0].x, _along(pts, cum, float(cd[1]))[0].y)
			var sd := _stair(items, S, R, body, float(cd[1]), float(cd[2]), wl0, tag)
			if sd.is_empty():
				continue
			sd["water"] = nm
			sd["tag"] = tag
			stairs.append(sd)
			picked.append(cd)
			busy.append([float(cd[1]) - 2.0, float(cd[1]) + float(sd["len"]) + 1.5, float(cd[2])])
	stats["stairs"] = stairs
	# 分段（每側）
	var nfull := 0
	var ntoe := 0
	var segs_out: Array = []
	var stations_out: Array = []
	for side: float in [-1.0, 1.0]:
		var cls: Array = []
		for q: Dictionary in st:
			var s := float(q["s"])
			var P: Dictionary = q["P%d" % int(side)]
			var c := "nat"
			if nm == "Canal":
				var nz := sin(s * 0.021 + side * 1.7) * 0.6 + sin(s * 0.057 + 2.1 + side) * 0.4
				c = "full" if nz > -0.35 else "toe"
				if P["ok"] and int(P["itop"]) > 0 and float(P["bank_h"]) > TALL_BANK:
					c = "toe"
			for wg: Array in wings:
				if s > float(wg[0]) and s < float(wg[1]):
					c = "full"
			for bz: Array in busy:
				if float(bz[2]) == side and s > float(bz[0]) - 3.0 and s < float(bz[1]) + 3.0:
					c = "full"
				if float(bz[2]) == side and s > float(bz[0]) - 0.6 and s < float(bz[1]) + 0.6:
					c = "stair"      # 石段／平台本身就是護岸面：不再貼石張り（會穿過踏面）
			if not P["ok"]:
				c = "none"
			cls.append(c)
		# 段彙總（給 gate／稽核量測沿水道的護岸覆蓋；cls＝既有的幾何分段結果，不新增設計規則）
		var run_cls := ""
		var run_s0 := 0.0
		var run_band := 0.0
		var run_n := 0
		var band_of := func(pp: Dictionary, wl_v: float) -> float:
			if pp["ok"] and int(pp["itop"]) > 0:
				return clampf(float(pp["h_top"]) - wl_v, 0.7, TALL_BANK)
			return 1.2
		for i in st.size() + 1:
			var now := String(cls[i]) if i < st.size() else "__end__"
			if now != run_cls:
				if run_cls != "" and run_cls != "none" and run_cls != "stair":
					segs_out.append({"water": nm, "side": side, "cls": run_cls, "s0": run_s0,
						"s1": float(st[i - 1]["s"]), "n": run_n, "band_h": run_band / maxf(float(run_n), 1.0)})
				if now != "__end__":
					run_cls = now
					run_s0 = float(st[i]["s"])
					run_band = 0.0
					run_n = 0
			if i < st.size():
				run_band += band_of.call(st[i]["P%d" % int(side)], float(st[i]["wl"]))
				run_n += 1
		for i in st.size():
			var qq: Dictionary = st[i]
			var pp: Dictionary = qq["P%d" % int(side)]
			stations_out.append({"water": nm, "side": side, "cls": cls[i], "s": float(qq["s"]),
				"c": [qq["c"].x, qq["c"].y], "t": [qq["t"].x, qq["t"].y], "wl": float(qq["wl"]),
				"bank_h": float(pp["bank_h"]) if pp["ok"] and int(pp["itop"]) > 0 else null,
				"h_top": float(pp["h_top"]) if pp["ok"] and int(pp["itop"]) > 0 else null,
				"iw_r": int(pp["iw"]) * 0.1 if pp["ok"] else null,
				"itop_r": int(pp["itop"]) * 0.1 if pp["ok"] and int(pp["itop"]) > 0 else null,
				"band_h": band_of.call(pp, float(qq["wl"]))})
		for i in st.size():
			var q: Dictionary = st[i]
			var P: Dictionary = q["P%d" % int(side)]
			if cls[i] == "none" or cls[i] == "stair":
				continue
			var s := float(q["s"])
			var t2: Vector2 = q["t"]
			var w_along := float(q["w"])
			var tag := "%s/%s/%d" % [nm, "L" if side < 0 else "R", i]
			tangs[tag] = t2            # 站點沿河切線（結構佔位時整站同步微移用）
			var key := "%s|%d|%.1f" % [nm, int(side), s]
			var r := _rng(key)
			var wl := float(q["wl"])
			if cls[i] == "full" or cls[i] == "toe":
				var rows := 1
				if cls[i] == "full":
					var k := 99
					for j in range(maxi(0, i - 2), mini(st.size(), i + 3)):
						if cls[j] != "full":
							k = mini(k, absi(j - i) - 1)
					rows = 99 if k >= 2 else 2      # 「full」段至少 2 層，避免護岸帶在接頭處只剩單列而讀成突然消失
					nfull += 1
				else:
					ntoe += 1
				var sx := clampf(w_along * 1.04 / PW, 0.8, 1.35)
				# 下列同用小中石面板；大石 revb 在玩家視角呈連續板條，改由獨立 boulder 點綴
				var top := _revet(items, P, t2, sx, rows, true, tag, key)
				if top.is_empty():
					continue
				var full_top: bool = cls[i] == "full" and rows == 99 and int(P["itop"]) > 0
				if full_top:
					_caps(items, S, R, P, t2, w_along, top, tag, key + "c")
				elif cls[i] == "full":
					# 収頭：列數遞減處上端放一顆石
					var pt := _pt3(P, float(top[0]) + 0.2, 0)
					_boulder(items, S, Vector2(pt.x, pt.z), r.randf_range(0.55, 0.8), wl, tag, r)
				if cls[i] == "toe" and r.randf() < 0.3:
					_piles(items, S, P, t2, 4 + r.randi() % 4, int(P["iw"]) * 0.1 + 0.1, tag, r)
				if cls[i] == "toe" and r.randf() < 0.25:
					var pw := _pt3(P, int(P["iw"]) * 0.1 + r.randf_range(0.3, 1.2), 0)
					_boulder(items, S, Vector2(pw.x, pw.z), r.randf_range(0.45, 0.8), wl, tag, r)
				# 牆腳用 2–3 群中小河原石接到水線；避免石張り下緣像獨立巨型板條
				var rw0 := int(P["iw"]) * 0.1
				var ncob := 1 + r.randi() % 2 + (1 if nm == "MainRiver" and cls[i] == "full" else 0)
				for j in ncob:
					var pc0 := _pt3(P, rw0 + r.randf_range(-0.45, 0.75), 0) + Vector3(t2.x, 0, t2.y) * r.randf_range(-w_along * 0.42, w_along * 0.42)
					_cobbles(items, S, Vector2(pc0.x, pc0.z), r.randf_range(0.55, 0.78), wl, tag, r)
				continue
			# 自然岸（主河／細渠）：依 R1 地面分段
			var rw := int(P["iw"]) * 0.1
			var pw3 := _pt3(P, rw, 0)
			if _on_road(R, pw3, Vector3(0.5, 0, 0), Vector3(0, 0, 0.5)):
				continue
			if nm == "WestStream":
				var outer := side * _curv(pts, cum, s) > 0.004
				if outer or r.randf() < 0.22:
					_shig(items, S, P, t2, rw + 0.12, tag, r)
				elif r.randf() < 0.5:
					var pc := _pt3(P, rw + r.randf_range(-0.25, 0.35), 0) + Vector3(t2.x, 0, t2.y) * r.randf_range(-0.8, 0.8)
					_cobbles(items, S, Vector2(pc.x, pc.z), r.randf_range(0.55, 0.8), wl, tag, r)
				continue
			var seg := _seg(pw3.x, pw3.z)
			if seg < -0.05:        # 礫灘：中小石群形成水→礫→土連續帶，避免只剩少數長板
				for j in 2 + r.randi() % 3:
					var pc := _pt3(P, rw + r.randf_range(-0.9, 1.7), 0) + Vector3(t2.x, 0, t2.y) * r.randf_range(-1.5, 1.5)
					_cobbles(items, S, Vector2(pc.x, pc.z), r.randf_range(0.55, 0.88), wl, tag, r)
				if r.randf() < 0.15:
					var pb := _pt3(P, rw + r.randf_range(0.0, 1.5), 0)
					_boulder(items, S, Vector2(pb.x, pb.z), r.randf_range(0.5, 0.8), wl, tag, r)
			elif seg > 0.12:       # 岩岸
				# 大石間補中小石，不讓草坡直接切到水面
				for j in 1 + r.randi() % 2:
					var pc1 := _pt3(P, rw + r.randf_range(-0.7, 1.0), 0) + Vector3(t2.x, 0, t2.y) * r.randf_range(-1.2, 1.2)
					_cobbles(items, S, Vector2(pc1.x, pc1.z), r.randf_range(0.55, 0.72), wl, tag, r)
				for j in 1 + r.randi() % 3:
					var pb := _pt3(P, rw + r.randf_range(-0.8, 1.6), 0) + Vector3(t2.x, 0, t2.y) * r.randf_range(-1.3, 1.3)
					_boulder(items, S, Vector2(pb.x, pb.z), r.randf_range(0.6, 1.8), wl, tag, r, r.randf_range(0.8, 1.1))
				if r.randf() < 0.3 and int(P["itop"]) > 0:
					var hm := wl + r.randf_range(0.5, 1.5)
					var rm := _r_at_h(P, hm)
					if not is_nan(rm):
						var pm := _pt3(P, rm, 0)
						_boulder(items, S, Vector2(pm.x, pm.z), r.randf_range(0.7, 1.3), wl, tag, r)
			else:                  # 侵蝕土岸：土留め木樁／零星石；每站至少一群細石做濕土收邊
				if r.randf() < 0.6:
					var pc2 := _pt3(P, rw + r.randf_range(-0.45, 0.7), 0) + Vector3(t2.x, 0, t2.y) * r.randf_range(-0.8, 0.8)
					_cobbles(items, S, Vector2(pc2.x, pc2.z), r.randf_range(0.55, 0.65), wl, tag, r)
				if r.randf() < 0.35:
					_piles(items, S, P, t2, 5 + r.randi() % 4, rw + 0.15, tag, r)
				elif r.randf() < 0.3:
					var pc := _pt3(P, rw + r.randf_range(-0.3, 0.6), 0)
					_cobbles(items, S, Vector2(pc.x, pc.z), r.randf_range(0.7, 1.0), wl, tag, r)
	stats[nm] = {"stations": st.size(), "full": nfull, "toe": ntoe, "bridges": excl.size()}
	# 給 gate／稽核用的幾何量測資料（僅輸出既有分類與斷面值，不改任何擺放）
	if not stats.has("segments"):
		if not stats.has("tangents"):
			stats["tangents"] = {}
		(stats["tangents"] as Dictionary).merge(tangs, true)
		stats["segments"] = []
	(stats["segments"] as Array).append_array(segs_out)
	if not stats.has("stations"):
		stats["stations"] = []
	(stats["stations"] as Array).append_array(stations_out)


static func _curv(pts: PackedVector2Array, cum: PackedFloat32Array, s: float) -> float:
	var a: Vector2 = (_along(pts, cum, s - 4.0)[1] as Vector2).normalized()
	var b: Vector2 = (_along(pts, cum, s + 4.0)[1] as Vector2).normalized()
	return a.cross(b) / 8.0


## R1 地面的河岸分段雜訊（gen_village_v2.gd noise2：seed＝relief.seed＋7、頻率 0.035；BANK_SEG_FREQ 0.45）
static var _n2: FastNoiseLite = null


static func _seg(x: float, z: float) -> float:
	if _n2 == null:
		var L: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://maps/village_v2/layout_v2.json"))
		_n2 = FastNoiseLite.new()
		_n2.seed = int(L["relief"]["seed"]) + 7
		_n2.frequency = 0.035
	return _n2.get_noise_2d(x * 0.45 + 517.0, z * 0.45 - 211.0)


# ─────────────────────────── 橋頭 ───────────────────────────

static func _bridge_head(items: Array, S: TriSampler, R: TriSampler, WL: Dictionary, br: Dictionary,
		stats: Dictionary) -> void:
	var F: Transform3D = br["F"]
	var Lh := float(br["L"])
	var W := float(br["W"])
	var dh := float(br["dh"])
	var nm := String(br["name"])
	var wn := String(br["water"])
	var wl := NAN
	if WL.has(wn):
		wl = (WL[wn] as WaterLv).at(F.origin.x, F.origin.z)
	var bx := Vector3(F.basis.x.x, 0, F.basis.x.z).normalized()
	var bz := Vector3(F.basis.z.x, 0, F.basis.z.z).normalized()
	var hs := {"flag": 0, "curb": 0, "bld": 0, "cob": 0, "rail": 0}
	for e: float in [1.0, -1.0]:
		var tag := "%s/%s" % [nm, "+z" if e > 0 else "-z"]
		var r := _rng(tag)
		var zend := e * Lh * 0.5
		var zo := bz * e       # 往外（離橋）
		# 橋面端高：鋪石只放在「接這座橋的路面」上（±APRON_DY）；別條路帶疊在上方（如龍神橋南端 RiverNorthPath 高 0.24 m）
		# 不鋪——否則石頭坐在上層路帶邊緣、影子落到下層，1.7 m 視角讀成浮石（2026-09-28 審查）
		var yend := F.origin.y + e * dh * 0.5     # bridge_frame 只有 yaw：端高＝中心＋dh/2（dh＝+z 端減 −z 端）
		var yb := _yaw_basis(bx)
		if e < 0:
			yb = _yaw_basis(-bx)
		# 見切り石：橋面端外 0.2 m 一列
		var cw := W - 0.2
		var nc := ceili(cw / 1.08)
		for i in nc:
			var lx := -cw * 0.5 + cw * (i + 0.5) / nc
			var p := F * Vector3(lx, 0, zend) + zo * 0.2
			p = Vector3(p.x, 0, p.z)
			var g := _top_under(S, R, p, bx * 0.5, zo * 0.15)
			if is_nan(g) or absf(g - yend) > APRON_DY:
				continue
			var sx := (cw / nc) / 1.1 * 0.99
			items.append(_item(_pick(r, "curb"), Transform3D(Basis(yb.x * sx, yb.y, yb.z), Vector3(p.x, g + 0.02, p.z)),
				"curb", wl, tag))
			hs["curb"] += 1
		# 鋪石 apron：7 列、每列深 ~0.48；前 4 列連續承接橋面，外 3 列漸疏融入土路
		var fw := W * 0.5 - 0.15
		var z := 0.38
		for row in 7:
			var skip: float = [0.0, 0.0, 0.03, 0.08, 0.18, 0.35, 0.55][row]
			var x := -fw
			while x < fw - 0.2:
				var m := _pick(r, "flag")
				var w := float(FLAG_W[m])
				if x + w > fw:
					w = fw - x
				if w < 0.3:
					break
				var sx := w / float(FLAG_W[m])
				if r.randf() >= skip:
					var jz := r.randf_range(-0.04, 0.04)
					var p := F * Vector3(x + w * 0.5, 0, zend) + zo * (z + jz)
					p = Vector3(p.x, 0, p.z)
					var g := _top_under(S, R, p, bx * (w * 0.5), zo * 0.24)
					if not is_nan(g) and absf(g - yend) <= APRON_DY + 0.02 * row:
						var b := Basis(yb.x * sx, yb.y, yb.z).rotated(Vector3.UP, r.randf_range(-0.05, 0.05))
						items.append(_item(m, Transform3D(b, Vector3(p.x, g + 0.006, p.z)), "flag", wl, tag))
						hs["flag"] += 1
				x += w + r.randf_range(0.03, 0.06)
			z += 0.48
		# 角：袖石（巨石）＋石群；水渠橋另加岸頂矮欄
		for sx: float in [-1.0, 1.0]:
			var pb := F * Vector3(sx * (W * 0.5 + 0.7), 0, zend) - zo * 0.3
			_boulder(items, S, Vector2(pb.x, pb.z), r.randf_range(0.6, 0.8), wl, tag, r, 0.7)
			hs["bld"] += 1
			var pc := F * Vector3(sx * (W * 0.5 + 1.2), 0, zend) + zo * 0.7
			if not _on_road(R, Vector3(pc.x, 0, pc.z), bx * 0.4, zo * 0.4):
				_cobbles(items, S, Vector2(pc.x, pc.z), 0.8, wl, tag, r)
				hs["cob"] += 1
			if wn == "Canal":
				for tries in 4:
					var pr := F * Vector3(sx * (W * 0.5 + 2.2), 0, zend) - zo * (0.9 - tries * 0.3)
					if _rail(items, S, R, Vector3(pr.x, 0, pr.z), bx, wl, tag):
						hs["rail"] += 1
						break
	var bh: Dictionary = stats.get("bridge_heads", {})
	bh[nm] = hs
	stats["bridge_heads"] = bh


## 足跡內最高的「可見地面」（地形與路面取高）
## 足跡跨在高差邊（路面板邊、土坎）上 → 回 NAN（不放；否則半邊懸空、1.7 m 視角讀成黑縫浮石，2026-09-28 審查）
const FLUSH_TOL := 0.10
const APRON_DY := 0.14


static func _top_under(S: TriSampler, R: TriSampler, c: Vector3, hx: Vector3, hz: Vector3) -> float:
	var g := -INF
	var lo := INF
	for o: Vector3 in [Vector3.ZERO, hx + hz, hx - hz, -hx + hz, -hx - hz, hx, -hx, hz, -hz]:
		var h := _surf(S, R, c.x + o.x, c.z + o.z)
		if is_nan(h):
			return NAN
		g = maxf(g, h)
		lo = minf(lo, h)
	if g - lo > FLUSH_TOL:
		return NAN
	return g


# ─────────────────────────── 合併 ───────────────────────────

static func chunk_key(p: Vector3) -> String:
	return "RB_%d_%d" % [floori(p.x / CHUNK), floori(p.z / CHUNK)]


## 頂點色：濕（水線 −0.05～+0.35 m 變暗）、水下藻色、水線上 0–1.1 m 朝上面長苔（低頻雜訊）
static func wet_color(c: Color, wp: Vector3, n: Vector3, wl: float, wood: bool, nz: FastNoiseLite) -> Color:
	if is_nan(wl):
		return c
	var rel := wp.y - wl
	# 玩家視角需可讀：濕色延到水線上 0.55 m，最濕處比乾石暗約 52 %
	var w := 1.0 - smoothstep(-0.05, 0.55, rel)
	var k := lerpf(1.0, 0.48, w)
	var out := Color(c.r * k * lerpf(1.0, 0.94, w), c.g * k, c.b * k * lerpf(1.0, 1.04, w), c.a)
	if rel < -0.05:
		out = Color(out.r * 0.78, out.g * 0.86, out.b * 0.70, out.a)
	if wood:
		return out
	var m := smoothstep(-0.15, 0.06, rel) * (1.0 - smoothstep(0.68, 1.25, rel)) * clampf(n.y * 1.3 + 0.35, 0.0, 1.0)
	m *= clampf(nz.get_noise_2d(wp.x, wp.z) * 0.9 + 0.55, 0.0, 1.0)
	if m > 0.0:
		out = out.lerp(Color(out.r * 0.60, out.g * 0.82, out.b * 0.42, out.a), clampf(m, 0.0, 1.0) * 0.85)
	return out


## save（可選）：Callable(res: Resource, name: String) -> Resource——產生器傳 _save，把每區塊網格存成 gen/riverbank_*.res（場景只存引用）
static func bake(v: Node3D, items: Array, lib: Dictionary, save := Callable()) -> Node3D:
	var old := v.get_node_or_null("Riverbank")
	if old != null:
		v.remove_child(old)
		old.free()
	var rb := Node3D.new()
	rb.name = "Riverbank"
	v.add_child(rb)
	var nz := FastNoiseLite.new()
	nz.seed = 7031
	nz.frequency = 0.09
	var cache := {}
	var chunks := {}
	var keys: Array = []
	for it: Dictionary in items:
		var xf: Transform3D = it["xf"]
		var ck := chunk_key(xf.origin)
		if not chunks.has(ck):
			chunks[ck] = {"lod": [{}, {}], "shapes": [], "n": 0}
			keys.append(ck)
		var C: Dictionary = chunks[ck]
		C["n"] = int(C["n"]) + 1
		for lod in 2:
			if lod == 1 and String(it["k"]) in LOD1_SKIP:
				continue
			var mn := String(it["m"]) + ("_l1" if lod == 1 else "")
			var mesh: Mesh = lib.get(mn)
			if mesh == null:
				push_error("[riverbank] 缺構件 %s" % mn)
				continue
			if not cache.has(mn):
				var surfs: Array = []
				for s in mesh.get_surface_count():
					surfs.append([mesh.surface_get_arrays(s), mesh.surface_get_material(s), mesh.surface_get_name(s)])
				cache[mn] = surfs
			for sd: Array in cache[mn]:
				_append((C["lod"] as Array)[lod], sd, xf, float(it["wl"]), nz)
		var sh: Dictionary = it["shape"]
		if not sh.is_empty():
			(C["shapes"] as Array).append([it, sh])
	keys.sort()
	var tri := [0, 0]
	for ck: String in keys:
		var C: Dictionary = chunks[ck]
		var cn := Node3D.new()
		cn.name = ck
		cn.set_meta("items", int(C["n"]))
		rb.add_child(cn)
		for lod in 2:
			var am := ArrayMesh.new()
			var bufs: Dictionary = (C["lod"] as Array)[lod]
			var mnames: Array = bufs.keys()
			mnames.sort()
			for mname: String in mnames:
				var B: Dictionary = bufs[mname]
				var arr := []
				arr.resize(Mesh.ARRAY_MAX)
				arr[Mesh.ARRAY_VERTEX] = B["v"]
				arr[Mesh.ARRAY_NORMAL] = B["n"]
				arr[Mesh.ARRAY_TANGENT] = B["t"]
				arr[Mesh.ARRAY_COLOR] = B["c"]
				arr[Mesh.ARRAY_TEX_UV] = B["uv"]
				arr[Mesh.ARRAY_INDEX] = B["i"]
				am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
				am.surface_set_name(am.get_surface_count() - 1, mname)
				am.surface_set_material(am.get_surface_count() - 1, B["mat"])
				tri[lod] += (B["i"] as PackedInt32Array).size() / 3
			am.resource_name = "%s_lod%d" % [ck, lod]
			var mi := MeshInstance3D.new()
			mi.name = "LOD%d" % lod
			mi.mesh = am if not save.is_valid() else save.call(am, ("riverbank_%s_lod%d" % [ck, lod]).to_lower().replace("-", "m"))
			mi.visibility_range_begin = float(LOD_RANGES[lod])
			mi.visibility_range_end = float(LOD_RANGES[lod + 1])
			mi.visibility_range_begin_margin = LOD_MARGIN if lod > 0 else 0.0
			mi.visibility_range_end_margin = LOD_MARGIN
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
			cn.add_child(mi)
		if not (C["shapes"] as Array).is_empty():
			var sb := StaticBody3D.new()
			sb.name = "Collision"
			cn.add_child(sb)
			var si := 0
			for pr: Array in C["shapes"]:
				var it: Dictionary = pr[0]
				var sh: Dictionary = pr[1]
				var ixf: Transform3D = it["xf"]
				var sc := ixf.basis.get_scale()
				var cs := CollisionShape3D.new()
				cs.name = "%s_%d" % [String(it["k"]), si]
				var box := BoxShape3D.new()
				box.size = sh["size"]
				cs.shape = box
				var lx: Transform3D = sh["xf"]
				cs.transform = Transform3D(ixf.basis.orthonormalized(), ixf.origin) * Transform3D(lx.basis, lx.origin * sc)
				sb.add_child(cs)
				si += 1
	rb.set_meta("lod0_tris", tri[0])
	rb.set_meta("lod1_tris", tri[1])
	rb.set_meta("items", items.size())
	return rb


static func _append(bufs: Dictionary, sd: Array, xf: Transform3D, wl: float, nz: FastNoiseLite) -> void:
	var a: Array = sd[0]
	var mat: Material = sd[1]
	var mname := String(sd[2])
	if not bufs.has(mname):
		bufs[mname] = {"v": PackedVector3Array(), "n": PackedVector3Array(), "t": PackedFloat32Array(),
			"c": PackedColorArray(), "uv": PackedVector2Array(), "i": PackedInt32Array(), "mat": mat}
	var B: Dictionary = bufs[mname]
	var wood := mname == "V2_Wood"
	var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var ns: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var ts: PackedFloat32Array = a[Mesh.ARRAY_TANGENT] if a[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
	var cs: PackedColorArray = a[Mesh.ARRAY_COLOR] if a[Mesh.ARRAY_COLOR] != null else PackedColorArray()
	var uvs: PackedVector2Array = a[Mesh.ARRAY_TEX_UV] if a[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
	var ids: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var nb := xf.basis.inverse().transposed()
	var base := (B["v"] as PackedVector3Array).size()
	var V: PackedVector3Array = B["v"]
	var N: PackedVector3Array = B["n"]
	var T: PackedFloat32Array = B["t"]
	var Cc: PackedColorArray = B["c"]
	var U: PackedVector2Array = B["uv"]
	var I: PackedInt32Array = B["i"]
	for k in vs.size():
		var wp := xf * vs[k]
		var wn := (nb * ns[k]).normalized()
		V.append(wp)
		N.append(wn)
		if ts.size() >= (k + 1) * 4:
			var tt := (xf.basis * Vector3(ts[k * 4], ts[k * 4 + 1], ts[k * 4 + 2])).normalized()
			T.append_array(PackedFloat32Array([tt.x, tt.y, tt.z, ts[k * 4 + 3]]))
		else:
			T.append_array(PackedFloat32Array([1, 0, 0, 1]))
		var col := cs[k] if k < cs.size() else Color.WHITE
		Cc.append(wet_color(col, wp, wn, wl, wood, nz))
		U.append(uvs[k] if k < uvs.size() else Vector2.ZERO)
	if ids.is_empty():
		for k in vs.size():
			I.append(base + k)
	else:
		for q in ids:
			I.append(base + q)
	B["v"] = V
	B["n"] = N
	B["t"] = T
	B["c"] = Cc
	B["uv"] = U
	B["i"] = I


## 一區塊某 LOD 三角面數
static func lod_tris(cn: Node, lod: int) -> int:
	var mi := cn.get_node_or_null("LOD%d" % lod) as MeshInstance3D
	if mi == null or mi.mesh == null:
		return 0
	var n := 0
	for s in mi.mesh.get_surface_count():
		n += (mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return n

extends RefCounted
## 人間之里 V2 P9 R5-1 Groundcover／Final Vegetation Dressing：地被素材組＋試作區（ART-FIRST）。
##   規劃（plan）＋烘焙（bake）→ maps/village_v2/gen/groundcover_p9.scn → village_v2.tscn 掛 Vegetation/GroundcoverP9（KirisameP9 之後）。
##   目標＝修掉「草地像平面貼圖／建築與地面硬切／路肩直線切邊／林下沒有近地層／水際與草地缺過渡」；不以降低空地百分比為目標。
##   R1–R4 封存不重開：封存 overlay（Ground／Props／Low／Trees…）的範圍、P7 河岸構件、P8 農田、水面、道路中央、建物都不進，只在外緣銜接。
## 素材（kit＝本檔程序生成、P8 plant shader 只讀共用：頂點色×instance color、風擺、不投影、24 m 分塊 MultiMesh＋緊 AABB）：
##   草叢 4 種 silhouette＝丸い株／細葉の立ち株／穂草／倒れた枯れ株（本檔で公尺建模；葉片構築は FV._blade 只讀呼叫）；
##   新：牆腳雜草（車前草・蒲公英系の rosette）、高い雜草（蓬系）、野花 2 色（黄・淡紫）、落葉 cluster、苔の座布団、小石（V2_Stone）。
##   只讀沿用：veg_kit 蕨・笹・低木、waterside_kit 菅・蘆・花菖蒲。
## 擺放＝環境語意（不是均勻 RNG）：
##   開闊草地＝大片留白＋局部草叢群（低頻 noise の島だけ）／常走處＝裸土多草少／牆腳＝斷續（周長の一部だけ）雜草・苔／
##   樹根＝落葉・苔集中、根元は空ける／林緣＝草 → 蕨・笹 → 灌木と林へ向かって漸密／水際＝濕土 → 苔 → 水邊草 → 蘆／
##   路肩・路口＝踩踏の裸土の指と草の侵入で直線を切る。

const FV := preload("res://tools/village_v2_farmland_visual.gd")
const RLib := preload("res://tools/village_v2_riverbank_lib.gd")
const FLib := preload("res://tools/village_v2_forest_lib.gd")
const UNDER_IDS := ["fern", "sasa", "shrub", "tsutsuji"]
const SG := preload("res://tools/village_v2_shrine_grove_lib.gd")
const GL := preload("res://tools/village_v2_hieda_garden_lib.gd")

const OUTPUT := "res://maps/village_v2/gen/groundcover_p9.scn"
const NODE_NAME := "GroundcoverP9"
const WK := "res://assets/village_v2/waterside_kit/mesh/"
const SEED := 5101
const CHUNK := 24.0
const NEAR := 32.0
const FAR := 65.0
const SMALL_RANGE := 45.0
const G_STEP := 0.4
## P7 封存河岸の核心帯（水面からの距離）：ここより外だけを扱う
const RB_CORE := 1.5
## R5 地面層が P7 核心の外緣から內側へ視覺的に淡入してよい幅（2026-10-03 使用者許可：P7 の mesh／collision／placement は不變、P7 構件の上には描かない）
const RB_FADE := 0.5
## 地面 overlay の格子（凍結の路口・草地は 0.4 m のまま、溪・林は帯を細かく）
const ZONE_STEP := {"street": 0.4, "lawn": 0.4, "forest": 0.35, "stream": 0.3}
## 草叢を置く地形の草重みの下限（路縁へ食い込む群れは低め）
const GRASS_MIN := 0.45
const GRASS_MIN_EDGE := 0.4
## 區ごとの下限：溪岸は濕土・泥の上に水邊の草が生える（0）、林緣は林床と草の混ざる所まで（0.3）
const ZONE_GRASS_MIN := {"lawn": 0.45, "street": 0.45, "forest": 0.3, "stream": 0.0}
## 地形の草の境界は確率で羽毛状に（下限 −FEATHER まで）
const FEATHER := 0.25


static func grass_min(zone: String, edge: bool) -> float:
	return GRASS_MIN_EDGE if edge else float(ZONE_GRASS_MIN.get(zone, GRASS_MIN))

## 草叢 silhouette 4 種＝K_SHORT 丸い株／K_FINE 細葉の立ち株／K_STEM 穂草／K_DRY 倒れた枯れ株（本檔で公尺建模、P8 plant shader 只讀）
enum { K_SHORT, K_FINE, K_STEM, K_ROSETTE, K_TALLWEED, K_FLOWER_Y, K_FLOWER_V, K_LITTER, K_MOSS, K_STONE, K_DRY, K_PEBBLE, K_ROOT }
const KIND_NAMES := ["short", "fine", "stem", "rosette", "tallweed", "flower_y", "flower_v", "litter", "moss", "stone", "dry", "pebble", "root"]
const GRASS_KINDS := [K_SHORT, K_FINE, K_STEM, K_DRY]
## 試作區（世界座標）
const ZONES := {
	"lawn": {"label": "鈴奈庵北側空地", "rect": Rect2(203.0, -88.0, 60.0, 62.0)},
	## 主街は全線 P6 frontage（ART_APPROVED）が路縁まで埋めている → 露出した路肩・巷口・退縮建物の牆腳がある CrossStreetMid 路口の三方向
	"street": {"label": "主街×CrossStreetMid 路口（牆腳・路肩）", "segs": [[Vector2(262.6, -21.0), Vector2(270.9, -49.0)], [Vector2(234.0, -20.0), Vector2(262.0, -20.0)],
		[Vector2(262.0, -20.0), Vector2(298.0, -26.8)]], "half": 10.0},
	## 北丘林冠（ForestP9）の西南角：西縁 x≈186–194、南縁 z≈−176；外は西北の大きな空地
	"forest": {"label": "北丘林冠 西南角", "rect": Rect2(174.0, -214.0, 62.0, 56.0)},
	"stream": {"label": "西の溪 外岸", "rect": Rect2(150.0, -104.0, 46.0, 50.0)},
}
const ZONE_ORDER := ["street", "lawn", "forest", "stream"]
## R4 封存 overlay（この子ノードの範囲には入らない）
const SEALED_OVERLAYS := ["HiedaGardenP9", "ShrineGroveP9", "SchoolYardP9", "WatersideP9", "TowerYardP9", "SuzunaanP9", "GeidonteiP9", "KirisameP9"]


# ─────────────────────────── 文脈 ───────────────────────────

## 格子の符號付き距離場：inside の外＝＋（最寄りの inside まで m）、内＝−。帯の等値線を滑らかに取るため（water_d の 0.5 m 量子化は階段になる）
class DGrid:
	var o := Vector2.ZERO
	var st := 0.5
	var nx := 0
	var nz := 0
	var d := PackedFloat32Array()

	func build(bb: Rect2, step: float, inside: Callable) -> void:
		o = bb.position
		st = step
		nx = int(ceil(bb.size.x / step)) + 1
		nz = int(ceil(bb.size.y / step)) + 1
		var m := PackedByteArray()
		m.resize(nx * nz)
		for j in nz:
			for i in nx:
				m[j * nx + i] = 1 if inside.call(o + Vector2(i * st, j * st)) else 0
		var dout := _chamfer(m, 1)
		var din := _chamfer(m, 0)
		d.resize(nx * nz)
		for k in nx * nz:
			d[k] = maxf(dout[k] - 0.5 * st, 0.0) if m[k] == 0 else -maxf(din[k] - 0.5 * st, 0.0)

	func _chamfer(m: PackedByteArray, target: int) -> PackedFloat32Array:
		var a := PackedFloat32Array()
		a.resize(nx * nz)
		for k in nx * nz:
			a[k] = 0.0 if m[k] == target else 1e6
		var s1 := st
		var s2 := st * 1.41421
		for j in nz:
			for i in nx:
				var k := j * nx + i
				var v := a[k]
				if v == 0.0:
					continue
				if i > 0:
					v = minf(v, a[k - 1] + s1)
				if j > 0:
					v = minf(v, a[k - nx] + s1)
					if i > 0:
						v = minf(v, a[k - nx - 1] + s2)
					if i < nx - 1:
						v = minf(v, a[k - nx + 1] + s2)
				a[k] = v
		for j in range(nz - 1, -1, -1):
			for i in range(nx - 1, -1, -1):
				var k := j * nx + i
				var v := a[k]
				if v == 0.0:
					continue
				if i < nx - 1:
					v = minf(v, a[k + 1] + s1)
				if j < nz - 1:
					v = minf(v, a[k + nx] + s1)
					if i < nx - 1:
						v = minf(v, a[k + nx + 1] + s2)
					if i > 0:
						v = minf(v, a[k + nx - 1] + s2)
				a[k] = v
		return a

	func at(p: Vector2) -> float:
		var fx := (p.x - o.x) / st
		var fz := (p.y - o.y) / st
		var i := clampi(floori(fx), 0, nx - 2)
		var j := clampi(floori(fz), 0, nz - 2)
		var tx := clampf(fx - i, 0.0, 1.0)
		var tz := clampf(fz - j, 0.0, 1.0)
		var k := j * nx + i
		return lerpf(lerpf(d[k], d[k + 1], tx), lerpf(d[k + nx], d[k + nx + 1], tx), tz)


## P7 地形の地面層重み（ground.gdshader mode 0：COLOR＝trodden,gravel,mud,rock；UV＝forest,farm；UV2.y＝street；grass＝其餘）を
## 三角形ハッシュで重心補間。地被は「地形が草として描かれている所」にだけ置く（路面・踏み固め土・林床の上に草叢を立てない）。
class TerrainW:
	var tris: Array = []
	var cell := {}
	const CS := 4.0

	func add(mi: MeshInstance3D, xf: Transform3D, bb: Rect2) -> void:
		var arr := mi.mesh.surface_get_arrays(0)
		var V: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var Cc: PackedColorArray = arr[Mesh.ARRAY_COLOR]
		var U: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		var U2: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2]
		var I: Variant = arr[Mesh.ARRAY_INDEX]
		var n := (I as PackedInt32Array).size() if I != null else V.size()
		for t in range(0, n, 3):
			var ids := [t, t + 1, t + 2]
			if I != null:
				ids = [(I as PackedInt32Array)[t], (I as PackedInt32Array)[t + 1], (I as PackedInt32Array)[t + 2]]
			var P2: Array = []
			var W: Array = []
			var tb := Rect2()
			for k in 3:
				var w3 := xf * V[ids[k]]
				var q := Vector2(w3.x, w3.z)
				P2.append(q)
				tb = Rect2(q, Vector2.ZERO) if k == 0 else tb.expand(q)
				var c: Color = Cc[ids[k]]
				var u: Vector2 = U[ids[k]] if U.size() > 0 else Vector2.ZERO
				var u2: Vector2 = U2[ids[k]] if U2.size() > 0 else Vector2.ZERO
				W.append(PackedFloat32Array([c.r, c.g, c.b, c.a, u.x, u.y, u2.y, w3.y]))
			if not bb.intersects(tb):
				continue
			var ti := tris.size()
			tris.append([P2, W])
			for cx in range(floori(tb.position.x / CS), floori(tb.end.x / CS) + 1):
				for cz in range(floori(tb.position.y / CS), floori(tb.end.y / CS) + 1):
					var key := Vector2i(cx, cz)
					if not cell.has(key):
						cell[key] = []
					cell[key].append(ti)

	## 見た目の地形網格の高さ（衝突網格 S とずれる所がある：overlay がその下に潜らないように）；地形外は NAN
	func vh(p: Vector2) -> float:
		var w := weights8(p)
		return NAN if w.is_empty() else w[7]

	func weights8(p: Vector2) -> PackedFloat32Array:
		for ti: int in cell.get(Vector2i(floori(p.x / CS), floori(p.y / CS)), []):
			var T: Array = tris[ti]
			var a: Vector2 = T[0][0]
			var v0: Vector2 = (T[0][1] as Vector2) - a
			var v1: Vector2 = (T[0][2] as Vector2) - a
			var v2 := p - a
			var den := v0.x * v1.y - v1.x * v0.y
			if absf(den) < 1e-9:
				continue
			var l1 := (v2.x * v1.y - v1.x * v2.y) / den
			var l2 := (v0.x * v2.y - v2.x * v0.y) / den
			var l0 := 1.0 - l1 - l2
			if l0 < -1e-4 or l1 < -1e-4 or l2 < -1e-4:
				continue
			var out := PackedFloat32Array()
			out.resize(8)
			for k in 8:
				out[k] = (T[1][0] as PackedFloat32Array)[k] * l0 + (T[1][1] as PackedFloat32Array)[k] * l1 + (T[1][2] as PackedFloat32Array)[k] * l2
			return out
		return PackedFloat32Array()

	## 地面層 7 權重（trodden, gravel, mud, rock, forest, farm, street）の重心補間；地形外は空
	func weights(p: Vector2) -> PackedFloat32Array:
		for ti: int in cell.get(Vector2i(floori(p.x / CS), floori(p.y / CS)), []):
			var T: Array = tris[ti]
			var a: Vector2 = T[0][0]
			var v0: Vector2 = (T[0][1] as Vector2) - a
			var v1: Vector2 = (T[0][2] as Vector2) - a
			var v2 := p - a
			var den := v0.x * v1.y - v1.x * v0.y
			if absf(den) < 1e-9:
				continue
			var l1 := (v2.x * v1.y - v1.x * v2.y) / den
			var l2 := (v0.x * v2.y - v2.x * v0.y) / den
			var l0 := 1.0 - l1 - l2
			if l0 < -1e-4 or l1 < -1e-4 or l2 < -1e-4:
				continue
			var out := PackedFloat32Array()
			out.resize(7)
			for k in 7:
				out[k] = (T[1][0] as PackedFloat32Array)[k] * l0 + (T[1][1] as PackedFloat32Array)[k] * l1 + (T[1][2] as PackedFloat32Array)[k] * l2
			return out
		return PackedFloat32Array()

	## 草の重み（1＝草だけ、0＝土・路・林床・田）；地形外は −1
	func grass(p: Vector2) -> float:
		for ti: int in cell.get(Vector2i(floori(p.x / CS), floori(p.y / CS)), []):
			var T: Array = tris[ti]
			var a: Vector2 = T[0][0]
			var b: Vector2 = T[0][1]
			var c: Vector2 = T[0][2]
			var v0 := b - a
			var v1 := c - a
			var v2 := p - a
			var den := v0.x * v1.y - v1.x * v0.y
			if absf(den) < 1e-9:
				continue
			var l1 := (v2.x * v1.y - v1.x * v2.y) / den
			var l2 := (v0.x * v2.y - v2.x * v0.y) / den
			var l0 := 1.0 - l1 - l2
			if l0 < -1e-4 or l1 < -1e-4 or l2 < -1e-4:
				continue
			var s := 0.0
			for k in 7:
				s += (T[1][0] as PackedFloat32Array)[k] * l0 + (T[1][1] as PackedFloat32Array)[k] * l1 + (T[1][2] as PackedFloat32Array)[k] * l2
			return clampf(1.0 - s, 0.0, 1.0)
		return -1.0


static func zone_of(p: Vector2) -> String:
	for z: String in ZONE_ORDER:
		if in_zone(z, p):
			return z
	return ""


static func in_zone(z: String, p: Vector2) -> bool:
	var Z: Dictionary = ZONES[z]
	if Z.has("rect"):
		return (Z["rect"] as Rect2).has_point(p)
	for sg: Array in Z["segs"]:
		if seg_d(sg[0], sg[1], p) <= float(Z["half"]):
			return true
	return false


## 區の境界までの距離（内側＋）：地面 overlay の外縁淡出に使う
static func zone_inset(z: String, p: Vector2) -> float:
	var Z: Dictionary = ZONES[z]
	if Z.has("rect"):
		var r: Rect2 = Z["rect"]
		return minf(minf(p.x - r.position.x, r.end.x - p.x), minf(p.y - r.position.y, r.end.y - p.y))
	var best := -99.0
	for sg: Array in Z["segs"]:
		best = maxf(best, float(Z["half"]) - seg_d(sg[0], sg[1], p))
	return best


static func zone_bbox(z: String) -> Rect2:
	var Z: Dictionary = ZONES[z]
	if Z.has("rect"):
		return Z["rect"]
	var bb := Rect2((Z["segs"][0] as Array)[0], Vector2.ZERO)
	for sg: Array in Z["segs"]:
		bb = bb.expand(sg[0]).expand(sg[1])
	return bb.grow(float(Z["half"]))


static func seg_d(a: Vector2, b: Vector2, p: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
	return p.distance_to(a + ab * t)


## 林緣までの距離（林の外＋、樹冠下−）：封存 ForestP9 の實樹ノードの位置 − 樹冠半徑（LOD0 網格の水平幅 × 0.4）
static func forest_d(C: Dictionary, p: Vector2) -> float:
	var H: Dictionary = C["tree_hash"]
	var k := Vector2i(floori(p.x / 8.0), floori(p.y / 8.0))
	var best := 24.0
	for dx in range(-3, 4):
		for dz in range(-3, 4):
			for t: Array in H.get(k + Vector2i(dx, dz), []):
				best = minf(best, p.distance_to(t[0]) - float(t[1]))
	return best


## 既存の ForestP9 下層（蕨・笹・低木・躑躅）が r 以内にある
static func near_under(C: Dictionary, p: Vector2, r: float) -> bool:
	var H: Dictionary = C["under_hash"]
	var k := Vector2i(floori(p.x / 4.0), floori(p.y / 4.0))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for q: Vector2 in H.get(k + Vector2i(dx, dz), []):
				if q.distance_to(p) < r:
					return true
	return false


## 最寄りの樹幹：[距離, 幹→点の向き, 樹の sc]
static func trunk_near(C: Dictionary, p: Vector2) -> Array:
	var H: Dictionary = C["tree_hash"]
	var k := Vector2i(floori(p.x / 8.0), floori(p.y / 8.0))
	var best := 99.0
	var bp := p
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for t: Array in H.get(k + Vector2i(dx, dz), []):
				var dd := p.distance_to(t[0])
				if dd < best:
					best = dd
					bp = t[0]
	var dir := (p - bp).normalized() if best > 1e-4 and best < 99.0 else Vector2.ZERO
	return [best, dir]


## 最寄りの樹幹までの距離
static func trunk_d(C: Dictionary, p: Vector2) -> float:
	var H: Dictionary = C["tree_hash"]
	var k := Vector2i(floori(p.x / 8.0), floori(p.y / 8.0))
	var best := 99.0
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for t: Array in H.get(k + Vector2i(dx, dz), []):
				best = minf(best, p.distance_to(t[0]))
	return best


static func _n(p: Vector2, f: float, s: float = 0.0) -> float:
	return 0.5 + 0.35 * sin(p.x * 0.83 * f + p.y * 0.37 + s) * sin(p.y * 0.71 * f - p.x * 0.29 + s * 1.7) + 0.15 * sin(p.x * 2.3 * f - p.y * 1.9 + s * 0.5)


static func context(v: Node3D) -> Dictionary:
	var S := RLib.terrain_sampler(v)
	var R := RLib.road_sampler(v)
	var WS := RLib.TriSampler.new()
	for nm in ["Water/MainRiver", "Water/Canal", "Water/Streams/WestStream"]:
		var g := v.get_node(nm) as MeshInstance3D
		WS.add(g.mesh.get_faces(), RLib.rel_xf(g, v))
	var FS := RLib.TriSampler.new()
	var fm := v.get_node("Terrain/FarmlandTerrain") as MeshInstance3D
	FS.add(fm.mesh.get_faces(), RLib.rel_xf(fm, v))
	var all_bb := Rect2()
	var first := true
	for z: String in ZONE_ORDER:
		all_bb = zone_bbox(z) if first else all_bb.merge(zone_bbox(z))
		first = false
	all_bb = all_bb.grow(6.0)
	# 建物の足元（OBB：B_ ノードの width_m／depth_m）、その他の網格は障礙物の AABB
	var obb: Array = []
	var obst: Array = []
	for b in v.get_node("Districts").find_children("B_*", "", true, false):
		var n3 := b as Node3D
		if n3 == null or not n3.has_meta("width_m"):
			continue
		var o := Vector2(n3.global_position.x, n3.global_position.z)
		if not all_bb.has_point(o):
			continue
		var bx := Vector2(n3.global_transform.basis.x.x, n3.global_transform.basis.x.z).normalized()
		var bz := Vector2(n3.global_transform.basis.z.x, n3.global_transform.basis.z.z).normalized()
		obb.append({"o": o, "bx": bx, "bz": bz, "h": Vector2(float(n3.get_meta("width_m")) * 0.5, float(n3.get_meta("depth_m")) * 0.5), "name": String(n3.name)})
	for root_name in ["Districts", "Landmarks"]:
		for mi in v.get_node(root_name).find_children("*", "MeshInstance3D", true, false):
			var g := mi as MeshInstance3D
			if g.mesh == null or not g.is_visible_in_tree():
				continue
			var path := String(v.get_path_to(g))
			if path.contains("/B_") and not path.contains("/Frontage/") and String(g.name) != "Foundation":
				continue
			var a := g.global_transform * g.get_aabb()
			var r := Rect2(a.position.x, a.position.z, a.size.x, a.size.z)
			if r.size.x > 30.0 or r.size.y > 30.0 or not all_bb.intersects(r) or a.size.y < 0.08:
				continue
			obst.append(r)
	# 封存 overlay の範囲（子グループの網格 AABB；地面網格は特徴の所だけ不透明なので外接を 1 m 広げる）
	var sealed: Array = []
	for nm: String in SEALED_OVERLAYS:
		var ov := v.get_node_or_null("Vegetation/" + nm)
		if ov == null:
			continue
		for mi in ov.find_children("*", "MeshInstance3D", true, false):
			var g := mi as MeshInstance3D
			if g.mesh == null:
				continue
			var a := g.global_transform * g.get_aabb()
			var r := Rect2(a.position.x, a.position.z, a.size.x, a.size.z)
			if all_bb.intersects(r.grow(1.0)):
				sealed.append([nm, r.grow(1.0) if String(g.name) != "Ground" else r.grow(0.5)])
	# P7 河岸構件
	var rb: Array = []
	for mi in v.get_node("Riverbank").find_children("*", "MeshInstance3D", true, false):
		var g := mi as MeshInstance3D
		var a := g.global_transform * g.get_aabb()
		var r := Rect2(a.position.x, a.position.z, a.size.x, a.size.z)
		if all_bb.intersects(r.grow(1.5)):
			rb.append(r.grow(1.0))
	# 樹點＝封存 ForestP9 の實ノード（Near/C_*/NNNN_id、headless でも位置が讀める）。
	#   R2 規劃（FLib.plan）を今の場面で再計算すると封存時と一致しない（試作林區で 44 本中 42 本が 0.4–1.5 m ずれ、實ノードは 76 本）→ 使わない
	var trees: Array = []
	var th := {}
	var uh := {}
	var tbb := all_bb.grow(24.0)
	var fnear := v.get_node_or_null("Vegetation/ForestP9/Near")
	if fnear != null:
		for ch in fnear.get_children():
			for t in ch.get_children():
				var nm := String(t.name)
				if not (t is Node3D) or nm.length() < 6 or nm[4] != "_":
					continue
				var tn := t as Node3D
				var p := Vector2(tn.global_position.x, tn.global_position.z)
				if not tbb.has_point(p):
					continue
				var id := nm.substr(5)
				if UNDER_IDS.any(func(u: String) -> bool: return id.begins_with(u)):
					var ku := Vector2i(floori(p.x / 4.0), floori(p.y / 4.0))
					if not uh.has(ku):
						uh[ku] = []
					uh[ku].append(p)
					continue
				var sc := tn.global_transform.basis.get_scale().x
				var cr := 2.5 * sc
				for mi in tn.find_children("LOD0", "MeshInstance3D", true, false):
					var ab := (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
					cr = 0.4 * maxf(ab.size.x, ab.size.z)
					break
				cr = clampf(cr, 1.2, 4.5)
				trees.append({"id": id, "p": p, "sc": sc, "cr": cr})
				var k := Vector2i(floori(p.x / 8.0), floori(p.y / 8.0))
				if not th.has(k):
					th[k] = []
				th[k].append([p, cr])
	var RBS := RLib.TriSampler.new()
	var sbb := zone_bbox("stream").grow(4.0)
	for mi in v.get_node("Riverbank").find_children("*", "MeshInstance3D", true, false):
		var g := mi as MeshInstance3D
		if g.mesh == null or not g.is_visible_in_tree():
			continue
		var a := g.global_transform * g.get_aabb()
		if sbb.intersects(Rect2(a.position.x, a.position.z, a.size.x, a.size.z)):
			RBS.add(g.mesh.get_faces(), RLib.rel_xf(g, v))
	var TW := TerrainW.new()
	for nm in ["Terrain/MainTerrain", "Terrain/NorthHill", "Terrain/RiverTerrain"]:
		var tm := v.get_node_or_null(nm) as MeshInstance3D
		if tm != null:
			TW.add(tm, RLib.rel_xf(tm, v), all_bb)
	return {"S": S, "R": R, "WS": WS, "FS": FS, "obb": obb, "obst": obst, "sealed": sealed, "rb": rb, "bb": all_bb, "trees": trees, "tree_hash": th, "under_hash": uh, "TW": TW, "RBS": RBS}


## r10 距離場：水面（溪）・地形の林床層（林）・地形の草（鈴奈庵北空地）
static func fields(C: Dictionary) -> void:
	if C.has("wgrid"):
		return
	var S: RLib.TriSampler = C["S"]
	var WS: RLib.TriSampler = C["WS"]
	var TW: TerrainW = C["TW"]
	var wg := DGrid.new()
	wg.build(zone_bbox("stream").grow(9.0), 0.3, func(q: Vector2) -> bool:
		var wh := WS.h(q.x, q.y)
		return not is_nan(wh) and wh > S.h(q.x, q.y) + 0.02)
	C["wgrid"] = wg
	var sg := DGrid.new()
	sg.build(zone_bbox("forest").grow(7.0), 0.5, func(q: Vector2) -> bool:
		var w := TW.weights(q)
		return not w.is_empty() and w[4] >= 0.5)
	C["seam"] = sg
	var gg := DGrid.new()
	gg.build(zone_bbox("lawn").grow(7.0), 0.5, func(q: Vector2) -> bool: return TW.grass(q) >= GRASS_MIN)
	C["ggrid"] = gg


## 水面までの滑らかな距離（m、水上＝0）
static func wdist(C: Dictionary, p: Vector2) -> float:
	return maxf((C["wgrid"] as DGrid).at(p), 0.0)


## P7 河岸構件がこの點の地面を覆っている（構件の上面が地表 −3 cm より上）
static func p7_covered(C: Dictionary, p: Vector2) -> bool:
	var h := (C["RBS"] as RLib.TriSampler).h(p.x, p.y)
	return not is_nan(h) and h > (C["S"] as RLib.TriSampler).h(p.x, p.y) - 0.03


## 溪の地面 overlay をこの點に敷いてよいか：P7 核心內は外緣から RB_FADE 以內・水面外・P7 構件の無い地面だけ
static func stream_ground_ok(P: Dictionary, p: Vector2, br: String) -> bool:
	if br == "":
		return true
	if br != "riverbank":
		return false
	var C: Dictionary = P["C"]
	var fade: float = 1.5 if P.get("_neg_core_deep", false) else RB_FADE
	if wdist(C, p) < RB_CORE - fade:
		return false
	return P.get("_neg_core_deep", false) or not p7_covered(C, p)


## 水から離れる向き（距離場の勾配）
static func wgrad(C: Dictionary, p: Vector2) -> Vector2:
	var g := Vector2(wdist(C, p + Vector2(0.3, 0)) - wdist(C, p - Vector2(0.3, 0)), wdist(C, p + Vector2(0, 0.3)) - wdist(C, p - Vector2(0, 0.3)))
	return g.normalized() if g.length() > 1e-5 else Vector2.RIGHT


## 地形の林床層（forest）との境：林床側＋、草側−（m）
static func seam_d(C: Dictionary, p: Vector2) -> float:
	return -(C["seam"] as DGrid).at(p)


## 地形の草の領域までの距離（m、草の上＝0）
static func gdist(C: Dictionary, p: Vector2) -> float:
	return maxf((C["ggrid"] as DGrid).at(p), 0.0)


## 地形がこの点で草として描かれている度合い（TerrainW）
static func grass_w(C: Dictionary, p: Vector2) -> float:
	return (C["TW"] as TerrainW).grass(p)


static func obb_d(o: Dictionary, p: Vector2) -> float:
	var d := p - (o["o"] as Vector2)
	var lx := absf(d.dot(o["bx"])) - (o["h"] as Vector2).x
	var lz := absf(d.dot(o["bz"])) - (o["h"] as Vector2).y
	if lx <= 0.0 and lz <= 0.0:
		return maxf(lx, lz)
	return Vector2(maxf(lx, 0.0), maxf(lz, 0.0)).length()


static func wall_d(C: Dictionary, p: Vector2) -> float:
	var best := 99.0
	for o: Dictionary in C["obb"]:
		best = minf(best, obb_d(o, p))
	return best


static func on_road(C: Dictionary, p: Vector2) -> bool:
	return not is_nan((C["R"] as RLib.TriSampler).h(p.x, p.y))


## 路面の縁までの距離（路面上＝−、外＝＋；0.25 m 刻みの近似、最大 3 m）
static func road_edge_d(C: Dictionary, p: Vector2) -> float:
	var inside := on_road(C, p)
	for k in range(1, 13):
		var r := k * 0.25
		for a in 8:
			var q := p + Vector2(cos(a * TAU / 8.0), sin(a * TAU / 8.0)) * r
			if on_road(C, q) != inside:
				return -r if inside else r
	return -3.0 if inside else 3.0


static func water_d(C: Dictionary, p: Vector2) -> float:
	var S: RLib.TriSampler = C["S"]
	var WS: RLib.TriSampler = C["WS"]
	var wh := WS.h(p.x, p.y)
	if not is_nan(wh) and wh > S.h(p.x, p.y) + 0.02:
		return 0.0
	for k in range(1, 16):
		var r := k * 0.5
		for a in 12:
			var q := p + Vector2(cos(a * TAU / 12.0), sin(a * TAU / 12.0)) * r
			var w2 := WS.h(q.x, q.y)
			if not is_nan(w2) and w2 > S.h(q.x, q.y) + 0.02:
				return r
	return 99.0


## 置いてはいけない所（理由文字列、空＝可）
static func blocked(C: Dictionary, p: Vector2, allow_road_edge := false, road_in := 0.35) -> String:
	if is_nan((C["S"] as RLib.TriSampler).h(p.x, p.y)):
		return "terrain"
	if not is_nan((C["FS"] as RLib.TriSampler).h(p.x, p.y)):
		return "farm"
	for o: Dictionary in C["obb"]:
		if obb_d(o, p) < 0.05:
			return "building"
	if C.has("tree_hash") and trunk_d(C, p) < 0.4:
		return "trunk"
	for r: Rect2 in C["obst"]:
		if r.has_point(p):
			return "obstacle"
	for s: Array in C["sealed"]:
		if (s[1] as Rect2).has_point(p):
			return "sealed:" + String(s[0])
	for r: Rect2 in C["rb"]:
		if r.has_point(p):
			if water_d(C, p) <= RB_CORE:
				return "riverbank"
			break
	if on_road(C, p):
		if not allow_road_edge or road_edge_d(C, p) < -road_in:
			return "road"
	var WS: RLib.TriSampler = C["WS"]
	var wh := WS.h(p.x, p.y)
	if not is_nan(wh) and wh > (C["S"] as RLib.TriSampler).h(p.x, p.y) - 0.02:
		return "water"
	return ""


# ─────────────────────────── 規劃 ───────────────────────────

static func gi(S: RLib.TriSampler, kind: int, p: Vector2, h: float, w: float, yaw: float, col: Color, zone: String, tag: String) -> Dictionary:
	var y := S.h(p.x, p.y) - (0.03 if kind in GRASS_KINDS or kind in [K_TALLWEED, K_FLOWER_Y, K_FLOWER_V] else 0.01)
	return {"kind": "mm", "k": kind, "p": p, "y": y, "h": h, "w": w, "yaw": yaw, "col": col, "zone": zone, "tag": tag}


static func plan(v: Node3D) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var C := context(v)
	var S: RLib.TriSampler = C["S"]
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var items: Array = []
	var nodes: Array = []
	var stats := {}
	C["drifts"] = []
	fields(C)
	_lawn(C, rng, items, nodes)
	_street(C, rng, items, nodes)
	_forest(C, rng, items, nodes)
	_stream(C, rng, items, nodes)
	# r10：鈴奈庵北空地の土場（別 RNG＝凍結した草地・牆腳・路口の乱数列を動かさない）
	var rng_d := RandomNumberGenerator.new()
	rng_d.seed = SEED + 77
	_lawn_dirt(C, rng_d, items)
	for it: Dictionary in items:
		var key := "%s/%s" % [it["zone"], KIND_NAMES[int(it["k"])]]
		stats[key] = int(stats.get(key, 0)) + 1
	for it: Dictionary in nodes:
		var key := "%s/%s" % [it["zone"], it["id"]]
		stats[key] = int(stats.get(key, 0)) + 1
	return {"items": items, "nodes": nodes, "C": C, "S": S, "stats": stats, "ms": Time.get_ticks_msec() - t0}


static func grass_col(rng: RandomNumberGenerator, dry: float) -> Color:
	var r := rng.randf()
	var g := Color(0.28, 0.40, 0.18).lerp(Color(0.23, 0.34, 0.15), r * 2.0) if r < 0.5 else Color(0.23, 0.34, 0.15).lerp(Color(0.17, 0.26, 0.11), (r - 0.5) * 2.0)
	return g.lerp(Color(0.40, 0.39, 0.25), clampf(dry + rng.randf_range(-0.1, 0.12), 0.0, 1.0))


## 草叢の群れ（drift）1 つ：中心 c、長半徑 r の向きランダムな楕円に n 株（正規分布で中心に寄る）；中心ほど立ち株・穂草、縁は丸株・枯れ株、外に飛び株
static func tuft_group(C: Dictionary, rng: RandomNumberGenerator, items: Array, c: Vector2, r: float, n: int, zone: String, dry: float, tall_p: float, allow_road := false, tag := "tuft", on_dirt := false, register := true, hscale := 1.0) -> void:
	var S: RLib.TriSampler = C["S"]
	if register and C.has("drifts"):
		(C["drifts"] as Array).append([c, r])
	var ang := rng.randf() * TAU
	var ax := Vector2(cos(ang), sin(ang))
	var ay := Vector2(-ax.y, ax.x)
	var el := rng.randf_range(0.45, 0.85)
	for i in n:
		var u := Vector2(rng.randfn(0.0, 0.45), rng.randfn(0.0, 0.45))
		if u.length() > 1.0:
			u = u.normalized() * rng.randf_range(0.7, 1.0)
		var p := c + ax * u.x * r + ay * u.y * r * el
		if blocked(C, p, allow_road) != "":
			continue
		if on_dirt:
			if lawn_inv(C, p) < 0.12:
				continue                        # 土場の中央・通行區には出さない
		else:
			var gm := grass_min(zone, allow_road)
			if rng.randf() > smoothstep(gm - FEATHER, gm + 0.15, grass_w(C, p)):
				continue
		var cen := clampf(1.0 - u.length(), 0.0, 1.0)
		var k := K_SHORT
		var h := rng.randf_range(0.18, 0.30)
		var roll := rng.randf()
		var p_stem := tall_p * (0.3 + cen)
		var p_fine := p_stem + 0.45
		var p_dry := p_fine + 0.1 + 0.15 * dry
		if roll < p_stem:
			k = K_STEM
			h = rng.randf_range(0.45, 0.70)
		elif roll < p_fine:
			k = K_FINE
			h = rng.randf_range(0.30, 0.48) * lerpf(0.75, 1.0, cen)
		elif roll < p_dry:
			k = K_DRY
			h = rng.randf_range(0.24, 0.34)
		items.append(gi(S, k, p, h * hscale, rng.randf_range(0.85, 1.2), rng.randf() * TAU, grass_col(rng, 0.85 if k == K_DRY else dry), zone, tag))
	# 群れの外に 0–2 株の飛び株
	for i in rng.randi_range(0, 2):
		var a := rng.randf() * TAU
		var p := c + Vector2(cos(a), sin(a)) * r * rng.randf_range(1.3, 2.2)
		var ok_g := lawn_inv(C, p) >= 0.12 if on_dirt else grass_w(C, p) >= grass_min(zone, false)
		if blocked(C, p, allow_road) == "" and ok_g:
			items.append(gi(S, K_SHORT, p, rng.randf_range(0.18, 0.28), 1.0, rng.randf() * TAU, grass_col(rng, dry), zone, tag))


## 1 開闊草地：低頻 noise の島（patch）だけに群れ；常走の線（踏み跡）は裸土で草が減る
const LAWN_PATHS := [[Vector2(205.0, -40.0), Vector2(228.0, -48.0), Vector2(248.0, -44.0), Vector2(262.0, -36.0)],
	[Vector2(232.0, -86.0), Vector2(236.0, -62.0), Vector2(240.0, -46.0)]]

static func lawn_path_d(p: Vector2) -> float:
	var d := 99.0
	for pl: Array in LAWN_PATHS:
		d = minf(d, GL.line_d(pl, p).x)
	return d


static func _lawn(C: Dictionary, rng: RandomNumberGenerator, items: Array, nodes: Array) -> void:
	var S: RLib.TriSampler = C["S"]
	var rect: Rect2 = ZONES["lawn"]["rect"]
	# 群れの中心：ジッター格子（3.2 m）を patch noise で間引く（固定間隔にしない）
	var gx := rect.position.x
	while gx < rect.end.x:
		var gz := rect.position.y
		while gz < rect.end.y:
			var c := Vector2(gx + rng.randf_range(0.0, 3.2), gz + rng.randf_range(0.0, 3.2))
			gz += 3.2
			var pn := _n(c * 0.33, 1.0, 1.3)          # 大きな島
			var pd := lawn_path_d(c)
			if pn < 0.55 or pd < 1.6 or blocked(C, c) != "" or grass_w(C, c) < 0.6:
				continue
			var wd := wall_d(C, c)
			if wd < 1.2:
				continue                            # 牆腳は別規則
			var k := smoothstep(0.55, 0.85, pn) * smoothstep(1.6, 4.0, pd)
			if rng.randf() > 0.35 + 0.65 * k:
				continue
			var r := lerpf(0.8, 2.1, k) * rng.randf_range(0.8, 1.2)
			tuft_group(C, rng, items, c, r, int(lerpf(18, 42, k) * rng.randf_range(0.7, 1.2)), "lawn", 0.15 + 0.25 * _n(c * 0.2, 1.0, 4.0), 0.22)
			# 野花：一部の島だけ、3–8 本を寄せて
			if rng.randf() < 0.28 * k:
				var kf := K_FLOWER_Y if _n(c * 0.5, 1.0, 9.0) > 0.5 else K_FLOWER_V
				for i in rng.randi_range(2, 5):
					var p := c + Vector2(rng.randf_range(-0.8, 0.8), rng.randf_range(-0.8, 0.8))
					if blocked(C, p) == "":
						items.append(gi(S, kf, p, rng.randf_range(0.8, 1.15), 1.0, rng.randf() * TAU, Color(1, 1, 1), "lawn", "flower"))
		gx += 3.2
	# 近地層 micro：低い株を疎らに（0.12 株/m² 前後、noise で濃淡、踏み跡と牆腳は除く）
	var mx := rect.position.x
	while mx < rect.end.x:
		var mz := rect.position.y
		while mz < rect.end.y:
			var q := Vector2(mx + rng.randf_range(0.0, 1.2), mz + rng.randf_range(0.0, 1.2))
			mz += 1.2
			if rng.randf() > 0.08 + 0.18 * _n(q * 0.5, 1.0, 29.0) or lawn_path_d(q) < 0.9 or wall_d(C, q) < 0.8:
				continue
			if blocked(C, q) != "" or grass_w(C, q) < 0.55:
				continue
			var km := K_DRY if rng.randf() < 0.25 else K_SHORT
			items.append(gi(S, km, q, rng.randf_range(0.08, 0.15), rng.randf_range(1.0, 1.4), rng.randf() * TAU, grass_col(rng, 0.25), "lawn", "micro"))
		mx += 1.2
	# 群れの間の疎らな低い株（noise の中間帯だけ・確率で間引く＝固定間隔にしない）
	var sx := rect.position.x
	while sx < rect.end.x:
		var sz := rect.position.y
		while sz < rect.end.y:
			var q := Vector2(sx + rng.randf_range(0.0, 1.6), sz + rng.randf_range(0.0, 1.6))
			sz += 1.6
			var pn2 := _n(q * 0.33, 1.0, 1.3)
			if pn2 < 0.42 or pn2 > 0.6 or rng.randf() > 0.1 or lawn_path_d(q) < 1.2 or wall_d(C, q) < 1.2:
				continue
			if blocked(C, q) != "" or grass_w(C, q) < 0.6:
				continue
			var kk := K_DRY if rng.randf() < 0.3 else K_SHORT
			items.append(gi(S, kk, q, rng.randf_range(0.12, 0.22), rng.randf_range(0.9, 1.2), rng.randf() * TAU, grass_col(rng, 0.2), "lawn", "tuft"))
		sx += 1.6
	# 踏み跡の縁：短い草が少し（踏まれて低い）
	for pl: Array in LAWN_PATHS:
		for e: Array in GL.resample(pl, 0.9):
			var q: Vector2 = e[0]
			for s in [-1.0, 1.0]:
				if rng.randf() < 0.45:
					var nrm := Vector2(-(e[1] as Vector2).y, (e[1] as Vector2).x) if e.size() > 1 and e[1] is Vector2 else Vector2(1, 0)
					var p: Vector2 = q + nrm.normalized() * s * rng.randf_range(0.7, 1.3)
					if blocked(C, p) == "" and rect.has_point(p):
						items.append(gi(S, K_SHORT, p, rng.randf_range(0.10, 0.18), 1.1, rng.randf() * TAU, grass_col(rng, 0.35), "lawn", "path_edge"))
	_wall_foot(C, rng, items, "lawn")
	_edge_tufts(C, rng, items, "lawn")


## 土場の「草が侵入しうる度合い」0–1：地形の草の縁（4 m 以内）か牆腳（3.2 m 以内）から、通行線（踏み跡）から 1.6 m 以上離れた所だけ。
##   中央（草からも壁からも遠い）と通行區は 0＝裸土のまま。
static func lawn_inv(C: Dictionary, p: Vector2) -> float:
	var src := maxf(0.6 * (1.0 - smoothstep(0.5, 2.4, gdist(C, p))), 1.0 - smoothstep(0.6, 3.4, wall_d(C, p)))
	return src * smoothstep(1.6, 4.5, lawn_path_d(p))


## 1b 鈴奈庵北空地（土場語意、r10）：地形が土の所に、縁・牆腳・低使用區から局所的な草叢（均一な草坪にしない）
static func _lawn_dirt(C: Dictionary, rng: RandomNumberGenerator, items: Array) -> void:
	var S: RLib.TriSampler = C["S"]
	var rect: Rect2 = ZONES["lawn"]["rect"]
	var gx := rect.position.x
	while gx < rect.end.x:
		var gz := rect.position.y
		while gz < rect.end.y:
			var c := Vector2(gx + rng.randf_range(0.0, 1.8), gz + rng.randf_range(0.0, 1.8))
			gz += 1.8
			if not rect.has_point(c) or blocked(C, c) != "" or grass_w(C, c) >= GRASS_MIN or wall_d(C, c) < 0.9:
				continue                            # 草の上は凍結した草地規則、牆腳 0.9 m 内は凍結した牆腳規則
			var pr := smoothstep(0.3, 0.9, lawn_inv(C, c)) * smoothstep(0.35, 0.65, _n(c * 0.45, 1.0, 47.0))
			if rng.randf() > pr * (0.85 if wall_d(C, c) < 2.5 else 0.45):
				continue
			tuft_group(C, rng, items, c, rng.randf_range(0.35, 0.8), rng.randi_range(4, 9), "lawn", 0.45, 0.03, false, "dirt", true, false, 0.75)
			if rng.randf() < 0.1:
				for j in rng.randi_range(1, 2):
					var q := c + Vector2(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.6, 0.6))
					if blocked(C, q) == "" and lawn_inv(C, q) >= 0.12:
						items.append(gi(S, K_ROSETTE, q, rng.randf_range(0.7, 1.0), 1.0, rng.randf() * TAU, Color(0.85, 0.9, 0.8), "lawn", "dirt"))
		gx += 1.8


## 地形の草／土の境界（等値線）の草側に小さな群れ：noise の山だけ（断続）、境界 1 m あたり最大 1 群
static func _edge_tufts(C: Dictionary, rng: RandomNumberGenerator, items: Array, zone: String) -> void:
	var bb := zone_bbox(zone)
	var gx := bb.position.x
	while gx < bb.end.x:
		var gz := bb.position.y
		while gz < bb.end.y:
			var q := Vector2(gx + rng.randf_range(0.0, 1.0), gz + rng.randf_range(0.0, 1.0))
			gz += 1.0
			if zone_of(q) != zone or blocked(C, q) != "":
				continue
			var gw := grass_w(C, q)
			if gw < 0.5 or gw > 0.72 or _n(q * 0.6, 1.0, 23.0) < 0.6 or rng.randf() < 0.45:
				continue
			if zone == "lawn" and lawn_path_d(q) < 1.0:
				continue
			tuft_group(C, rng, items, q, rng.randf_range(0.3, 0.6), rng.randi_range(3, 6), zone, 0.3, 0.1)
		gx += 1.0


## 牆腳：建物周長に沿って、noise で途切れる帯（周長の 25–55 %）に雜草・苔・小石；入口（主街側の正面中央）は空ける
static func _wall_foot(C: Dictionary, rng: RandomNumberGenerator, items: Array, zone: String) -> void:
	var S: RLib.TriSampler = C["S"]
	for o: Dictionary in C["obb"]:
		var hh: Vector2 = o["h"]
		var corners := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
		for e in 4:
			var a: Vector2 = corners[e]
			var b: Vector2 = corners[(e + 1) % 4]
			var A := (o["o"] as Vector2) + (o["bx"] as Vector2) * a.x * hh.x + (o["bz"] as Vector2) * a.y * hh.y
			var B := (o["o"] as Vector2) + (o["bx"] as Vector2) * b.x * hh.x + (o["bz"] as Vector2) * b.y * hh.y
			var L := A.distance_to(B)
			var out := ((A + B) * 0.5 - (o["o"] as Vector2)).normalized()
			var t := rng.randf_range(0.0, 0.6)
			while t < L:
				var q := A.lerp(B, t / L)
				t += rng.randf_range(0.55, 0.9)
				if not in_zone(zone, q):
					continue
				# 断続：周長沿いの 1D noise（波長 3–5 m）の山だけ、角は少し多め
				var corner := minf(t, L - t) < 1.2
				if _n(q * 0.9, 1.0, float(e) * 2.1 + hh.x) < (0.52 if corner else 0.62):
					continue
				var c := q + out * rng.randf_range(0.15, 0.35)
				if blocked(C, c) != "" or road_edge_d(C, c) < 0.6:
					continue                        # 路面直結の正面（frontage）は除く
				# 小群：雜草（車前草系・蓬系）＋細い草、ときどき苔の座布団・小石
				for j in rng.randi_range(5, 9):
					var p := c + (q - A).normalized() * rng.randf_range(-0.4, 0.4) + out * rng.randf_range(-0.08, 0.22)
					if blocked(C, p) != "":
						continue
					var r := rng.randf()
					if r < 0.28:
						items.append(gi(S, K_ROSETTE, p, rng.randf_range(0.7, 1.0), 1.0, rng.randf() * TAU, Color(0.85, 0.9, 0.8).lerp(Color(1, 1, 1), rng.randf()), zone, "wallfoot"))
					elif r < 0.5:
						items.append(gi(S, K_TALLWEED, p, rng.randf_range(0.75, 1.15), 1.0, rng.randf() * TAU, Color(0.88, 0.92, 0.84), zone, "wallfoot"))
					elif r < 0.84:
						items.append(gi(S, K_FINE, p, rng.randf_range(0.30, 0.50), 1.0, rng.randf() * TAU, grass_col(rng, 0.25), zone, "wallfoot"))
					elif r < 0.95:
						var pm := q + out * rng.randf_range(0.12, 0.3)
						if blocked(C, pm) == "":
							items.append(gi(S, K_MOSS, pm, rng.randf_range(0.8, 1.2), rng.randf_range(0.9, 1.5), rng.randf() * TAU, Color(1, 1, 1), zone, "wallfoot"))
					else:
						items.append(gi(S, K_STONE, p, rng.randf_range(0.6, 1.0), 1.0, rng.randf() * TAU, Color(1, 1, 1), zone, "wallfoot"))


## 2 主街×CrossStreetMid 路口：牆腳（退縮建物・巷口の側面）＋露出路肩（踩踏の裸土の指＝地面 overlay、草の侵入＝路縁に食い込む小さな群れ）
static func _street(C: Dictionary, rng: RandomNumberGenerator, items: Array, nodes: Array) -> void:
	var S: RLib.TriSampler = C["S"]
	_wall_foot(C, rng, items, "street")
	_edge_tufts(C, rng, items, "street")
	var Z: Dictionary = ZONES["street"]
	for sg: Array in Z["segs"]:
		var a: Vector2 = sg[0]
		var b: Vector2 = sg[1]
		var dir := (b - a).normalized()
		var nrm := Vector2(-dir.y, dir.x)
		var L := a.distance_to(b)
		for side in [-1.0, 1.0]:
			var t := 0.0
			while t < L:
				t += rng.randf_range(0.6, 1.6)
				var c := a + dir * t
				var edge := Vector2.INF
				for k in range(4, 80):
					var q: Vector2 = c + nrm * float(side) * k * 0.15
					if not on_road(C, q):
						edge = q
						break
				if edge == Vector2.INF or not in_zone("street", edge):
					continue
				if blocked(C, edge + nrm * float(side) * 0.4) != "":
					continue                    # P6 frontage が路縁まで来ている所は触らない
				if _n(edge * 0.7, 1.0, 3.0 + side) < 0.55:
					continue
				# 草の侵入：路縁の内外に小さな群れ、群れの後は間を空ける（帯にしない）
				tuft_group(C, rng, items, edge + nrm * float(side) * rng.randf_range(0.0, 0.35), rng.randf_range(0.35, 0.7), rng.randi_range(4, 9), "street", 0.3, 0.0, true)
				t += rng.randf_range(1.5, 3.5)
## 3 林緣（北丘林冠 西南角、r10 forest-floor-first）：地面＝overlay の林床（暗い腐植・落葉・苔、地形の林床層の縁から草側へ不規則にこぼれる、樹根の輪）が主。
##   植物はその上に群落で：外 3–9 m＝背の高い草の群れ → 縁 −1.5–3 m＝蕨・笹の群落（林側に低木）→ 樹冠下＝蕨の小群。
static func _forest(C: Dictionary, rng: RandomNumberGenerator, items: Array, nodes: Array) -> void:
	var S: RLib.TriSampler = C["S"]
	var rect: Rect2 = ZONES["forest"]["rect"]
	# 群落の中心：ジッター格子 4.2 m（地面は overlay の林床が主、植物は群落で後から）
	var gx := rect.position.x
	while gx < rect.end.x:
		var gz := rect.position.y
		while gz < rect.end.y:
			var c := Vector2(gx + rng.randf_range(0.0, 4.2), gz + rng.randf_range(0.0, 4.2))
			gz += 4.2
			if not rect.has_point(c) or blocked(C, c) != "":
				continue
			var fd := forest_d(C, c) + 2.0 * (_n(c * 0.25, 1.0, 7.0) - 0.5)
			var pn := _n(c * 0.3, 1.0, 5.5)
			if fd > 9.0 or fd < -7.0:
				continue
			if fd > 3.0:
				# 草：林へ向かって背の高い草の群れ（穂草多め）
				if pn > 0.45 and rng.randf() < 0.22 + 0.4 * smoothstep(9.0, 4.0, fd):
					tuft_group(C, rng, items, c, rng.randf_range(1.0, 1.8), rng.randi_range(10, 20), "forest", 0.25, 0.4)
			elif fd > -1.5:
				# 縁：蕨・笹の群落（1 群 3–7 株、群ごとにほぼ 1 種）、林側ほど低木が混ざる；斜面の樹間（境から遠い）には置かない
				var sdc := seam_d(C, c)
				if sdc > -3.0 and sdc < 5.0 and rng.randf() < 0.9:
					var main := "fern_a" if pn > 0.5 else "sasa_a"
					for j in rng.randi_range(4, 8):
						var q := c + Vector2(clampf(rng.randfn(0.0, 0.8), -1.8, 1.8), clampf(rng.randfn(0.0, 0.8), -1.8, 1.8))
						var id := main if rng.randf() < 0.8 else ("sasa_a" if main == "fern_a" else "fern_a")
						if forest_d(C, q) < 1.0 and rng.randf() < 0.2:
							id = "shrub_a"
						var sc := rng.randf_range(0.6, 0.9) if id == "shrub_a" else rng.randf_range(0.5, 0.85)
						if fits(C, q, 0.5 * sc) and not near_under(C, q, 0.8) and not near_node(nodes, q, 0.55) and trunk_d(C, q) > 1.6:
							nodes.append(tnode(S, id, q, sc, rng, "forest", "edge"))
				if rng.randf() < 0.35:
					tuft_group(C, rng, items, c + Vector2(rng.randf_range(-1.5, 1.5), rng.randf_range(-1.5, 1.5)), rng.randf_range(0.6, 1.0), rng.randi_range(4, 8), "forest", 0.3, 0.3)
			else:
				# 樹冠下：植物は ForestP9 の下層に任せる（斜面に水玉を作らない）、落葉の塊だけ
				if rng.randf() < 0.4:
					items.append(gi(S, K_LITTER, c, 1.0, rng.randf_range(1.0, 1.6), rng.randf() * TAU, Color(1, 1, 1), "forest", "litter"))
		gx += 4.2
	# 樹根（3D は補助、主は overlay の輪）：林縁の樹の日陰側に大きめの苔座布団＋落葉
	for t: Dictionary in C["trees"]:
		var p: Vector2 = t["p"]
		if not rect.has_point(p):
			continue
		var edge := false
		for a in 8:
			if forest_d(C, p + Vector2(cos(a * TAU / 8.0), sin(a * TAU / 8.0)) * (float(t["cr"]) + 2.5)) > 0.0:
				edge = true
				break
		if not edge:
			continue
		# 張り出した根（3D）：TPS 5–15 m で幹元が地面から生えて見えるように
		var tsc := float(t["sc"])
		var a1 := rng.randf() * TAU
		var nr := rng.randi_range(4, 6)
		for k in nr:
			var a := a1 + TAU * k / nr + rng.randf_range(-0.35, 0.35)
			var dv := Vector2(cos(a), sin(a))
			var ln := (0.6 + 0.5 * tsc) * rng.randf_range(0.75, 1.25)
			var hgt := (0.08 + 0.07 * tsc) * rng.randf_range(0.8, 1.2)
			var o := p + dv * 0.04
			var y0 := S.h(o.x, o.y)
			var y1 := S.h(o.x + dv.x * ln, o.y + dv.y * ln)
			if is_nan(y0) or is_nan(y1):
				continue
			var bas := Basis(Vector3(dv.x * ln, y1 - y0, dv.y * ln), Vector3.UP * hgt, Vector3(-dv.y, 0.0, dv.x) * hgt * 1.6)
			var it := gi(S, K_ROOT, o, hgt, ln, 0.0, Color(1, 1, 1).lerp(Color(0.9, 0.95, 0.85), rng.randf()), "forest", "rootflare")
			it["y"] = y0 - 0.04
			it["basis"] = bas
			items.append(it)
		var r0 := 0.5 + 0.15 * float(t["sc"])
		for k in rng.randi_range(3, 5):
			var a := -PI * 0.5 + rng.randf_range(-1.6, 1.6)          # 北（−z）＝日陰側に寄せる
			var q := p + Vector2(cos(a), sin(a)) * rng.randf_range(r0, r0 + 0.9)
			if blocked(C, q) != "":
				continue
			# 苔は overlay の襟が担う（3D の苔座布団は空の環境光で青緑に見える）→ 3D は落葉の塊だけ
			items.append(gi(S, K_LITTER, q, rng.randf_range(0.9, 1.3), rng.randf_range(1.2, 1.8), a, Color(1, 1, 1), "forest", "root"))


## nodes の中に q から r 以内の植物がある
static func near_node(nodes: Array, q: Vector2, r: float) -> bool:
	for n: Dictionary in nodes:
		if (n["p"] as Vector2).distance_to(q) < r:
			return true
	return false


## 足元の半径 r の 4 点がすべて置ける
static func fits(C: Dictionary, p: Vector2, r: float) -> bool:
	if blocked(C, p) != "":
		return false
	for d in [Vector2(r, 0), Vector2(-r, 0), Vector2(0, r), Vector2(0, -r)]:
		if blocked(C, p + d) != "":
			return false
	return true


static func tnode(S: RLib.TriSampler, id: String, p: Vector2, sc: float, rng: RandomNumberGenerator, zone: String, tag: String) -> Dictionary:
	return {"kind": "tree", "id": id, "p": p, "y": S.h(p.x, p.y) - 0.02, "yaw": rng.randf() * TAU, "sc": Vector3.ONE * sc, "zone": zone, "tag": tag, "preset": "mature"}


static func wnode(S: RLib.TriSampler, id: String, p: Vector2, sc: float, rng: RandomNumberGenerator, zone: String, tag: String) -> Dictionary:
	return {"kind": "mesh", "id": id, "p": p, "y": S.h(p.x, p.y) - 0.03, "yaw": rng.randf() * TAU, "sc": Vector3.ONE * sc, "zone": zone, "tag": tag}


## 4 溪の外岸（r10 substrate-first）：P7 核心（水面 1.5 m）の外に overlay で 卵石・碎石の汀 → 濕泥 → 苔・濕った暗い土 → 地形 を連續で敷く（帯幅は低頻 noise で大きく揺らす）。
##   植物は點綴：蘆＝數個の小群落（孤立單叢なし）、菅・花菖蒲＝泥帯の小群、草＝外縁に疎、3D 卵石＝汀の寄り。
static func _stream(C: Dictionary, rng: RandomNumberGenerator, items: Array, nodes: Array) -> void:
	var S: RLib.TriSampler = C["S"]
	var rect: Rect2 = ZONES["stream"]["rect"]
	# 候補點（e＝P7 核心の縁から外へ m）
	var c_reed: Array = []
	var c_bank: Array = []
	var gx := rect.position.x + 0.25
	while gx < rect.end.x:
		var gz := rect.position.y + 0.25
		while gz < rect.end.y:
			var q := Vector2(gx, gz)
			gz += 0.5
			if zone_inset("stream", q) < 2.5 or blocked(C, q) != "":
				continue
			var e := wdist(C, q) - RB_CORE
			if e > 0.4 and e < 1.0:
				c_reed.append(q)
			elif e > 1.4 and e < 2.6:
				c_bank.append(q)
		gx += 0.5
	_shuffle(c_reed, rng)
	_shuffle(c_bank, rng)
	# ① 蘆：5–7 の小群落（岸沿いに細長い楕円 2.4–4.4 m、互いに ≥ 9 m）、群落外の蘆は置かない、5 株未滿の群落は捨てる
	var cols: Array = []
	var n_col := rng.randi_range(4, 6)
	for c: Vector2 in c_reed:
		if cols.size() >= n_col:
			break
		var far := true
		for o: Vector2 in cols:
			if o.distance_to(c) < 9.0:
				far = false
		if not far:
			continue
		var g := wgrad(C, c)
		var tg := Vector2(-g.y, g.x)
		var hl := rng.randf_range(1.2, 2.4)
		var placed: Array = []
		# 小株を岸沿いに順に 0.9–1.3 m 間隔で 2–4 個（隣の小株とは途切れない＝1 群落）
		var subs: Array = []
		var along := -hl * 0.5
		for j in rng.randi_range(2, 3):
			subs.append(c + tg * along + g * rng.randf_range(-0.2, 0.6))
			along += rng.randf_range(0.9, 1.3)
		var members: Array = []
		for sc2: Vector2 in subs:
			for k2 in rng.randi_range(2, 3):
				members.append([sc2 + Vector2(clampf(rng.randfn(0.0, 0.25), -0.45, 0.45), clampf(rng.randfn(0.0, 0.25), -0.45, 0.45)), rng.randf_range(0.6, 0.9)])
		for k2 in rng.randi_range(0, 1):
			members.append([c + tg * rng.randf_range(-hl - 0.6, hl + 0.6) + g * rng.randf_range(0.0, 0.7), rng.randf_range(0.5, 0.7)])
		for mb: Array in members:
			var q: Vector2 = mb[0]
			var e := wdist(C, q) - RB_CORE
			if blocked(C, q) != "" or e < 0.1 or e > 1.7:
				continue
			placed.append(wnode(S, "wk_reed" if rng.randf() < 0.6 else "wk_reed_s", q, float(mb[1]), rng, "stream", "reed"))
		# 1.6 m 連結の最大成分だけ残す（ちぎれた株・孤立單叢を出さない）
		placed = _largest_component(placed, 1.6)
		if placed.size() >= 5:
			nodes.append_array(placed)
			cols.append(c)
	# ② 菅・花菖蒲：泥帯に 3–5 株の小群（7–10 群、互いに ≥ 5 m、蘆の群落から ≥ 3 m）
	var gs: Array = []
	var n_g := rng.randi_range(7, 10)
	for c: Vector2 in c_bank:
		if gs.size() >= n_g:
			break
		var ok := true
		for o: Vector2 in gs + cols:
			if o.distance_to(c) < (5.0 if gs.has(o) else 3.0):
				ok = false
		if not ok:
			continue
		var n_ok := 0
		for j in rng.randi_range(3, 5):
			var q := c + Vector2(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.6, 0.6))
			if blocked(C, q) != "" or wdist(C, q) - RB_CORE < 1.0:
				continue
			nodes.append(wnode(S, "wk_iris" if rng.randf() < 0.2 else "wk_sedge", q, rng.randf_range(0.65, 0.95), rng, "stream", "bank"))
			n_ok += 1
		if n_ok > 0:
			gs.append(c)
	# ③ 卵石（3D）：汀帯 e 0.15–1.3 に小さな寄り（overlay の卵石面に乗せる）、④ 苔座布団：苔帯に少し、⑤ 草：外縁 e 3.5–6 に小さな群れ（疎）
	gx = rect.position.x
	while gx < rect.end.x:
		var gz := rect.position.y
		while gz < rect.end.y:
			var c := Vector2(gx + rng.randf_range(0.0, 1.3), gz + rng.randf_range(0.0, 1.3))
			gz += 1.3
			if blocked(C, c) != "":
				continue
			var e := wdist(C, c) - RB_CORE
			if e > 0.15 and e < 1.3:
				if rng.randf() < 0.45 * smoothstep(0.3, 0.6, _n(c * 0.7, 1.0, 59.0)):
					for j in rng.randi_range(1, 3):
						var q := c + Vector2(rng.randf_range(-0.4, 0.4), rng.randf_range(-0.4, 0.4))
						if blocked(C, q) == "":
							items.append(gi(S, K_PEBBLE, q, rng.randf_range(0.8, 1.3), 1.0, rng.randf() * TAU, Color(1, 1, 1), "stream", "stone"))
			# 苔は overlay の苔帯だけ（3D の苔座布団は乾いた土の上の青緑の板に見えた）
		gx += 1.3
	gx = rect.position.x
	while gx < rect.end.x:
		var gz := rect.position.y
		while gz < rect.end.y:
			var c := Vector2(gx + rng.randf_range(0.0, 3.0), gz + rng.randf_range(0.0, 3.0))
			gz += 3.0
			var e := wdist(C, c) - RB_CORE
			if e < 3.2 or e > 5.8 or blocked(C, c) != "":
				continue
			if _n(c * 0.5, 1.0, 11.0) > 0.55 and rng.randf() < 0.35:
				tuft_group(C, rng, items, c, rng.randf_range(0.7, 1.1), rng.randi_range(8, 14), "stream", 0.15, 0.25, false, "tuft", false, true)
		gx += 3.0


static func _largest_component(items: Array, link: float) -> Array:
	var lab := []
	lab.resize(items.size())
	lab.fill(-1)
	var best := -1
	var best_n := 0
	var nc := 0
	for i in items.size():
		if lab[i] >= 0:
			continue
		var st := [i]
		lab[i] = nc
		var cnt := 0
		while not st.is_empty():
			var a: int = st.pop_back()
			cnt += 1
			for b in items.size():
				if lab[b] < 0 and (items[a]["p"] as Vector2).distance_to(items[b]["p"]) < link:
					lab[b] = nc
					st.append(b)
		if cnt > best_n:
			best_n = cnt
			best = nc
		nc += 1
	var out: Array = []
	for i in items.size():
		if lab[i] == best:
			out.append(items[i])
	return out


static func _shuffle(a: Array, rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: Variant = a[i]
		a[i] = a[j]
		a[j] = t


# ─────────────────────────── 素材（程序網格） ───────────────────────────

static func grass_mesh(kind: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 700 + kind * 53
	var hi := SurfaceTool.new()
	hi.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lo := SurfaceTool.new()
	lo.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base_c := Color(0.50, 0.52, 0.48)
	var tip_c := Color(0.86, 0.90, 0.78)
	match kind:
		K_SHORT:
			# 丸い株（mound）：40 枚、外側の葉ほど外へ寝る；高さ 1＝公尺（instance で 0.17–0.30 m）
			for i in 32:
				var rr := sqrt(rng.randf()) * 0.12
				var a := rng.randf() * TAU
				var base := Vector3(cos(a) * rr, 0, sin(a) * rr)
				var az := a + rng.randf_range(-0.5, 0.5)
				var lean := lerpf(0.25, 1.0, rr / 0.12) * rng.randf_range(0.8, 1.15)
				var h := rng.randf_range(0.55, 1.0) * lerpf(1.0, 0.75, rr / 0.12)
				FV._blade(hi, base, az, lean, h, 0.05, base_c, tip_c)
				if i % 5 == 0:
					FV._blade_lo(lo, base, az, lean, h, 0.06, base_c, tip_c)
		K_FINE:
			# 細葉の立ち株：30 枚、ほぼ直立（0.30–0.50 m）
			for i in 24:
				var rr := sqrt(rng.randf()) * 0.08
				var a := rng.randf() * TAU
				var base := Vector3(cos(a) * rr, 0, sin(a) * rr)
				var lean := rng.randf_range(0.05, 0.45)
				var h := rng.randf_range(0.6, 1.0)
				FV._blade(hi, base, a + rng.randf_range(-0.8, 0.8), lean, h, 0.034, base_c, tip_c)
				if i % 5 == 0:
					FV._blade_lo(lo, base, a, lean, h, 0.04, base_c, tip_c)
		K_STEM:
			# 穂草：根葉 14＋穂茎 7（先端に細長い穂；0.55–0.85 m）
			for i in 14:
				var rr := sqrt(rng.randf()) * 0.08
				var a := rng.randf() * TAU
				var base := Vector3(cos(a) * rr, 0, sin(a) * rr)
				var lean := rng.randf_range(0.5, 1.0)
				var h := rng.randf_range(0.35, 0.55)
				FV._blade(hi, base, a, lean, h, 0.042, base_c, tip_c)
				if i % 4 == 0:
					FV._blade_lo(lo, base, a, lean, h, 0.05, base_c, tip_c)
			for i in 7:
				var a := rng.randf() * TAU
				var base := Vector3(cos(a) * 0.03, 0, sin(a) * 0.03)
				var lean := rng.randf_range(0.04, 0.22)
				var h := rng.randf_range(0.8, 1.0)
				FV._blade(hi, base, a, lean, h, 0.009, base_c, Color(0.95, 0.92, 0.75))
				var dir := Vector3(cos(a), 0, sin(a))
				var top := base + dir * (lean * h * 1.3 + h * 0.18) + Vector3.UP * h * (1.0 - lean * 0.5)
				FV._blade(hi, top - Vector3.UP * 0.16, a, 0.08, 0.18, 0.022, Color(0.86, 0.80, 0.58), Color(0.92, 0.86, 0.62))
				if i % 3 == 0:
					FV._blade_lo(lo, base, a, lean, h, 0.02, base_c, Color(0.98, 0.9, 0.62))
		K_DRY:
			# 倒れた枯れ株：22 枚、寝て外へ広がる（0.26–0.40 m）
			for i in 22:
				var rr := sqrt(rng.randf()) * 0.1
				var a := rng.randf() * TAU
				var base := Vector3(cos(a) * rr, 0, sin(a) * rr)
				var lean := rng.randf_range(0.9, 1.4)
				var h := rng.randf_range(0.6, 1.0)
				FV._blade(hi, base, a, lean, h, 0.046, Color(0.66, 0.62, 0.52), Color(0.90, 0.86, 0.72))
				if i % 4 == 0:
					FV._blade_lo(lo, base, a, lean, h, 0.05, Color(0.92, 0.88, 0.76), Color(1.0, 0.96, 0.84))
	return [hi.commit(), lo.commit()]


static func kind_mesh(kind: int) -> Array:
	if kind in GRASS_KINDS:
		return grass_mesh(kind)
	var rng := RandomNumberGenerator.new()
	rng.seed = 900 + kind * 37
	var hi := SurfaceTool.new()
	hi.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lo := SurfaceTool.new()
	lo.begin(Mesh.PRIMITIVE_TRIANGLES)
	match kind:
		K_ROSETTE:
			# 車前草・蒲公英：寝た広い葉 7 枚＋花茎 1–2（高さ 0.18、幅 0.32）
			var g := Color(0.34, 0.46, 0.20)
			for i in 7:
				var az := TAU * i / 7.0 + rng.randf_range(-0.2, 0.2)
				FV._blade(hi, Vector3.ZERO, az, rng.randf_range(0.9, 1.2), rng.randf_range(0.12, 0.17), 0.055, g, Color(0.46, 0.56, 0.26))
				if i % 2 == 0:
					FV._blade(lo, Vector3.ZERO, az, 1.0, 0.15, 0.08, g, Color(0.46, 0.56, 0.26))
			FV._blade(hi, Vector3(0.02, 0, 0.0), 0.3, 0.12, 0.30, 0.008, Color(0.40, 0.48, 0.22), Color(0.80, 0.74, 0.40))
		K_TALLWEED:
			# 蓬系：直立の茎 4（0.45–0.7）＋下葉 4
			for i in 4:
				var az := TAU * i / 4.0 + rng.randf_range(-0.4, 0.4)
				FV._blade(hi, Vector3(rng.randf_range(-0.05, 0.05), 0, rng.randf_range(-0.05, 0.05)), az, rng.randf_range(0.08, 0.25), rng.randf_range(0.45, 0.70), 0.022, Color(0.30, 0.40, 0.20), Color(0.52, 0.56, 0.36))
				FV._blade(hi, Vector3.ZERO, az + 0.6, rng.randf_range(0.5, 0.8), rng.randf_range(0.18, 0.26), 0.04, Color(0.30, 0.42, 0.20), Color(0.44, 0.52, 0.30))
				if i < 2:
					FV._blade(lo, Vector3.ZERO, az, 0.2, 0.6, 0.04, Color(0.30, 0.40, 0.20), Color(0.52, 0.56, 0.36))
		K_FLOWER_Y, K_FLOWER_V:
			var fc := Color(0.95, 0.82, 0.25) if kind == K_FLOWER_Y else Color(0.86, 0.82, 0.96)
			for i in 5:
				var base := Vector3(rng.randf_range(-0.07, 0.07), 0, rng.randf_range(-0.07, 0.07))
				var h := rng.randf_range(0.22, 0.38)
				var az := rng.randf() * TAU
				var lean := rng.randf_range(0.05, 0.25)
				FV._blade(hi, base, az, lean, h, 0.006, Color(0.32, 0.44, 0.20), Color(0.38, 0.50, 0.24))
				var dir := Vector3(cos(az), 0, sin(az))
				var top := base + dir * (lean * h * 1.3 + h * 0.18) + Vector3.UP * h * (1.0 - lean * 0.5)
				for k in 5:
					FV._blade(hi, top - Vector3.UP * 0.005, TAU * k / 5.0 + az, 1.0, 0.05, 0.024, fc, fc)
				if i < 2:
					FV._blade(lo, top, az, 1.0, 0.04, 0.03, fc, fc)
			for i in 3:
				FV._blade(hi, Vector3.ZERO, TAU * i / 3.0, 0.8, 0.12, 0.03, Color(0.32, 0.44, 0.20), Color(0.40, 0.50, 0.24))
		K_LITTER:
			# 落葉 cluster：寝た葉 16 枚（茶・黄土・赤茶・枯緑）、半径 0.45、高さ 0.005–0.03
			var cols := [Color(0.48, 0.34, 0.18), Color(0.62, 0.48, 0.24), Color(0.55, 0.28, 0.14), Color(0.44, 0.42, 0.22), Color(0.36, 0.26, 0.16)]
			for i in 16:
				var c := Vector3(rng.randf_range(-0.45, 0.45), rng.randf_range(0.004, 0.025), rng.randf_range(-0.45, 0.45)) * Vector3(1, 1, 1)
				if Vector2(c.x, c.z).length() > 0.5:
					c *= Vector3(0.6, 1, 0.6)
				_leaf(hi, c, rng.randf() * TAU, rng.randf_range(0.035, 0.06), cols[i % cols.size()], rng)
				if i % 3 == 0:
					_leaf(lo, c, rng.randf() * TAU, 0.07, cols[i % cols.size()], rng)
		K_MOSS:
			# 苔の座布団：ゆがんだ低いドーム（半径 0.22、高さ 0.06）＋小さな子 2
			_dome(hi, Vector3.ZERO, 0.22, 0.06, Color(0.38, 0.48, 0.21), rng, 9)
			_dome(hi, Vector3(0.2, 0, 0.1), 0.11, 0.04, Color(0.44, 0.52, 0.24), rng, 7)
			_dome(hi, Vector3(-0.15, 0, -0.16), 0.09, 0.03, Color(0.34, 0.44, 0.19), rng, 7)
			_dome(lo, Vector3.ZERO, 0.24, 0.05, Color(0.38, 0.48, 0.21), rng, 6)
		K_PEBBLE:
			# 卵石：扁平で丸い石 6 個（半徑 0.05–0.13 m）
			for i in 6:
				var c := Vector3(rng.randf_range(-0.28, 0.28), 0, rng.randf_range(-0.28, 0.28))
				_pebble(hi, c, rng.randf_range(0.05, 0.13), rng)
			_pebble(lo, Vector3.ZERO, 0.14, rng)
			_pebble(lo, Vector3(0.18, 0, 0.1), 0.1, rng)
		K_ROOT:
			# 樹根の張り出し：+x へ 0→1 で細る低い稜（斷面三角、下は −0.3 まで地中）
			_root(hi, 7)
			_root(lo, 3)
		K_STONE:
			for i in 4:
				var c := Vector3(rng.randf_range(-0.18, 0.18), 0, rng.randf_range(-0.18, 0.18))
				_rock(hi, c, rng.randf_range(0.04, 0.09), rng)
			_rock(lo, Vector3.ZERO, 0.1, rng)
	if kind in [K_MOSS, K_STONE, K_PEBBLE, K_ROOT]:
		hi.generate_normals()
		lo.generate_normals()
	return [hi.commit(), lo.commit()]


static func _leaf(t: SurfaceTool, c: Vector3, az: float, s: float, col: Color, rng: RandomNumberGenerator) -> void:
	var d := Vector3(cos(az), 0, sin(az)) * s
	var sd := Vector3(-sin(az), 0, cos(az)) * s * 0.45
	var tilt := Vector3.UP * rng.randf_range(-0.012, 0.012)
	var pts := [c - d, c + sd + tilt, c + d, c - sd - tilt]
	for tr in [[0, 1, 2], [0, 2, 3]]:
		for k: int in tr:
			t.set_color(col)
			t.set_uv(Vector2(0.0, 0.6))
			t.set_normal(Vector3.UP)
			t.add_vertex(pts[k])


static func _dome(t: SurfaceTool, c: Vector3, r: float, h: float, col: Color, rng: RandomNumberGenerator, seg: int) -> void:
	var ring: Array = []
	var ring2: Array = []
	for i in seg:
		var a := TAU * i / seg
		var rr := r * rng.randf_range(0.8, 1.15)
		ring.append(c + Vector3(cos(a) * rr, -0.01, sin(a) * rr))
		ring2.append(c + Vector3(cos(a) * rr * 0.6, h * rng.randf_range(0.7, 1.0), sin(a) * rr * 0.6))
	var top := c + Vector3(0, h * 1.1, 0)
	for i in seg:
		var j := (i + 1) % seg
		for tri in [[ring[i], ring2[j], ring[j]], [ring[i], ring2[i], ring2[j]], [ring2[i], top, ring2[j]]]:
			for p: Vector3 in tri:
				t.set_color(col.lerp(Color(0.42, 0.52, 0.22), clampf((p.y - c.y) / maxf(h, 0.01), 0.0, 1.0) * 0.4))
				t.set_uv(Vector2(0.0, 0.7))
				t.add_vertex(p)


static func _pebble(t: SurfaceTool, c: Vector3, r: float, rng: RandomNumberGenerator) -> void:
	var seg := 7
	var ring: Array = []
	var top := c + Vector3(0, r * rng.randf_range(0.45, 0.65), 0)
	var ph := rng.randf() * TAU
	var el := rng.randf_range(0.65, 1.0)
	for i in seg:
		var a := ph + TAU * i / seg
		ring.append(c + Vector3(cos(a) * r, -0.02, sin(a) * r * el))
	var mid: Array = []
	for i in seg:
		var q: Vector3 = ring[i]
		mid.append(c + (q - c) * 0.8 + Vector3(0, r * 0.4, 0))
	var col := Color(0.86, 0.83, 0.76).lerp(Color(0.70, 0.68, 0.64), rng.randf())
	for i in seg:
		var j := (i + 1) % seg
		for tri in [[ring[i], mid[j], ring[j]], [ring[i], mid[i], mid[j]], [mid[i], top, mid[j]]]:
			for p: Vector3 in tri:
				t.set_color(col)
				t.set_uv(Vector2(0.0, 0.7))
				t.add_vertex(p)


static func _root(t: SurfaceTool, steps: int) -> void:
	var prev: Array = []
	for k in steps + 1:
		var u := float(k) / steps
		var w := 0.5 * (1.0 - 0.8 * u)
		var h := pow(1.0 - u, 1.3)
		var x := u
		var sec := [Vector3(x, -0.3, -w), Vector3(x, h, 0.0), Vector3(x, -0.3, w)]
		if not prev.is_empty():
			for tri in [[prev[0], sec[0], prev[1]], [sec[0], sec[1], prev[1]], [prev[1], sec[1], prev[2]], [sec[1], sec[2], prev[2]]]:
				for p: Vector3 in tri:
					var top := clampf((p.y + 0.3) / 1.3, 0.0, 1.0)
					t.set_color(Color(0.30, 0.25, 0.20).lerp(Color(0.40, 0.36, 0.28), top))
					t.set_uv(Vector2(0.0, 0.7))
					t.add_vertex(p)
		prev = sec


static func _rock(t: SurfaceTool, c: Vector3, r: float, rng: RandomNumberGenerator) -> void:
	var seg := 6
	var b: Array = []
	var u: Array = []
	var ph := rng.randf() * TAU
	for i in seg:
		var a := ph + TAU * i / seg
		b.append(c + Vector3(cos(a) * r * rng.randf_range(0.8, 1.2), -0.02, sin(a) * r * rng.randf_range(0.8, 1.2)))
		u.append(c + Vector3(cos(a + 0.3) * r * 0.6, r * rng.randf_range(0.5, 0.9), sin(a + 0.3) * r * 0.6))
	var top := c + Vector3(rng.randf_range(-0.2, 0.2) * r, r * 0.95, rng.randf_range(-0.2, 0.2) * r)
	for i in seg:
		var j := (i + 1) % seg
		for tri in [[b[i], u[j], b[j]], [b[i], u[i], u[j]], [u[i], top, u[j]]]:
			for p: Vector3 in tri:
				t.set_color(Color(0.70, 0.68, 0.64))
				t.set_uv(Vector2(0.0, 0.7))
				t.add_vertex(p)


# ─────────────────────────── 地面 overlay（gc_ground：COLOR＝碎石, 苔／濃い草, 踏み固め土, 落葉・枯れ草；不透明度＝權重和；UV2＝濕潤, 區境界淡出） ───────────────────────────

static func ground_w(P: Dictionary, p: Vector2) -> Variant:
	var C: Dictionary = P["C"]
	var z := zone_of(p)
	if z == "":
		return null
	var nz := _n(p, 1.0)
	var pb := _n(p * 2.7 + Vector2(19.0, 41.0), 1.1)
	var gv := 0.0
	var mo := 0.0
	var so := 0.0
	var li := 0.0
	var wet := 0.0
	var md := 0.0
	var pe := 0.0
	var k_in := 1.0
	# 共通：牆腳の雨落ち帯（0–0.8 m、noise で途切れる；土＋碎石、所々苔）
	if z != "stream":
		var wd := wall_d(C, p)
		if wd < 0.8:
			var kw := (1.0 - smoothstep(0.05, 0.8, wd)) * smoothstep(0.38, 0.55, _n(p * 0.8, 1.0, 2.0)) * smoothstep(0.2, 0.6, grass_w(C, p))
			so = maxf(so, 0.55 * kw)
			gv = maxf(gv, 0.45 * kw * smoothstep(0.4, 0.6, pb))
			mo = maxf(mo, 0.4 * kw * smoothstep(0.55, 0.7, _n(p * 1.7, 1.0, 4.0)))
			wet = maxf(wet, 0.12 * kw)
	# 共通（草地・路口）：地形の草／土の境界（草重み 0.5 の等値線）を noise で雙方向に交錯させる
	#   草側へ踏み跡の土の指、土側へ草の舌（苔チャンネル＝草色 tint）——直線の境界を崩す（林は林床の境で別規則）
	if z == "lawn" or z == "street":
		var gw := grass_w(C, p)
		if gw >= 0.0 and absf(gw - 0.5) < 0.42:
			var e := gw - 0.5 + 0.6 * (_n(p * 0.45, 1.0, 12.0) - 0.5) + 0.3 * (_n(p * 1.3, 1.0, 19.0) - 0.5)
			if gw >= 0.5 and e < 0.0:
				so = maxf(so, 0.75 * smoothstep(0.0, -0.25, e))
				gv = maxf(gv, 0.2 * smoothstep(0.0, -0.25, e) * smoothstep(0.5, 0.7, pb))
			elif gw < 0.5 and e > 0.0:
				# 土場（lawn）では草の舌は草の領域から 3 m 以内・通行線の外だけ（中央と通行區は裸土のまま）
				var kt := 1.0 if z == "street" else (1.0 - smoothstep(1.5, 3.0, gdist(C, p))) * smoothstep(1.0, 2.2, lawn_path_d(p))
				mo = maxf(mo, 0.7 * smoothstep(0.0, 0.25, e) * kt)
	# 共通：草叢の根元の暗い環（叢を地面に座らせる）
	var dk := drift_k(C, p)
	so = maxf(so, 0.16 * dk * smoothstep(0.3, 0.6, grass_w(C, p)))
	match z:
		"lawn":
			# 常走の線＝裸土（縁は不規則）
			var pd := lawn_path_d(p) + 0.5 * (nz - 0.5)
			var wv := 0.55 + 0.9 * _n(p * 0.15, 1.0, 17.0)       # 路幅が沿路で 0.6–1.5 倍に変わる
			var kp := 1.0 - smoothstep(0.35 * wv, 1.3 * wv, pd)
			so = maxf(so, 0.85 * kp)
			gv = maxf(gv, 0.35 * kp * smoothstep(0.55, 0.75, pb))
			# 大尺度の斑（5–15 m）：濃い草／枯れ草——地形の草の上だけ（土場を草色に塗らない）
			var on_g := smoothstep(0.35, 0.55, grass_w(C, p))
			mo = maxf(mo, 0.35 * smoothstep(0.62, 0.8, _n(p * 0.12, 1.0, 21.0)) * on_g)
			li = maxf(li, 0.26 * smoothstep(0.64, 0.82, _n(p * 0.15 + Vector2(7.0, 3.0), 1.0, 33.0)) * on_g)
			# 土場への草の侵入（r10）：縁・牆腳・低使用區から noise の舌で、中央と通行區は 0
			if grass_w(C, p) < 0.5:
				var tg := smoothstep(0.55, 0.85, lawn_inv(C, p) * (0.5 + 0.9 * _n(p * 0.6, 1.0, 41.0)))
				mo = maxf(mo, 0.55 * tg)
			so = maxf(so, 0.3 * smoothstep(0.7, 0.86, _n(p * 0.2, 1.0, 44.0)))
			# 小さな裸土（モグラ塚・踏まれ跡）
			so = maxf(so, 0.8 * smoothstep(0.8, 0.9, _n(p * 1.3, 1.0, 6.0)))
		"street":
			var red := road_edge_d(C, p)
			if red > -1.2 and red < 2.4:
				# 路縁の線を ±0.6 m 揺らし、路面側には草が食い込み、草地側には踏み跡の指が入る
				var e := red - 1.2 * (_n(p * 0.5, 1.0, 1.0) - 0.5)
				var fing := 1.7 * smoothstep(0.58, 0.82, _n(p * 0.9, 1.0, 5.0))
				if red < 0.0 and e > 0.0:
					mo = maxf(mo, 0.9 * smoothstep(0.0, 0.3, e))
				elif red >= 0.0:
					var kr := maxf(1.0 - smoothstep(-0.3, 0.0, e), 1.0 - smoothstep(fing * 0.55, fing + 0.01, red))
					so = maxf(so, 0.85 * kr)
					gv = maxf(gv, 0.35 * kr * smoothstep(0.5, 0.7, pb))
		"forest":
			# r10 forest-floor-first：① 林床（地形 forest 層）の縁から草側へ 0.5–4.2 m、場所で大きく変わるこぼれ出し（落葉）
			var sd := seam_d(C, p)
			var n1 := _n(p * 0.22, 1.0, 7.0)
			var n2 := _n(p * 0.8, 1.0, 13.0)
			var nF := _n(p * 0.45, 1.0, 71.0)
			var reach := maxf(0.5 + 4.0 * smoothstep(0.45, 0.8, nF) + 0.9 * smoothstep(0.55, 0.8, n1) + 0.5 * (n2 - 0.5), 0.2)
			if P.get("_neg_no_floor", false):
				reach = 0.0
			var spill := 1.0 if sd >= 0.0 else 1.0 - smoothstep(reach * 0.45, reach + 0.01, -sd)
			var inner := smoothstep(0.5, 5.0, sd)
			var tip := 1.0 if sd >= 0.0 else 1.0 - 0.45 * smoothstep(0.0, reach, -sd)
			li = maxf(li, 0.8 * spill * tip * (1.0 - 0.4 * inner) * (0.7 + 0.3 * smoothstep(0.3, 0.6, pb)))
			# ② 暗い腐植土（mud 層）と ③ 苔：林床側の縁帯（0–4 m）は濃く、奥は低頻の斑で地形林床の tile 格子を崩す
			var band := smoothstep(-0.5, 0.5, sd)
			var edge_b := band * (1.0 - smoothstep(3.0, 6.0, sd))
			md = maxf(md, band * (0.35 * edge_b + 0.5 * smoothstep(0.45, 0.7, _n(p * 0.3, 1.0, 31.0))))
			mo = maxf(mo, band * 0.45 * smoothstep(0.58, 0.78, _n(p * 0.25, 1.0, 3.0)))
			li = maxf(li, band * 0.55 * smoothstep(0.35, 0.65, _n(p * 0.2 + Vector2(13.0, 5.0), 1.0, 77.0)))
			md = maxf(md, 0.55 * edge_b)
			# ④ 樹根の輪（直徑 3–5 m、TPS 5–15 m で読める）：幹元 0.25–0.55 m＝暗い土（裸根）、0.45–1.1 m＝苔の襟（北＝日陰側ほど濃い）、外＝落葉、外縁は noise で欠ける
			var tn := trunk_near(C, p)
			var td: float = tn[0]
			if td < 3.2:
				var shade := 0.5 + 0.5 * (tn[1] as Vector2).dot(Vector2(0.0, -1.0))
				var R := (2.2 + 1.0 * _n(p * 1.1, 1.0, 37.0)) * (0.9 + 0.2 * n1)
				var cr := 1.3 + 0.5 * _n(p * 1.7, 1.0, 39.0)
				var root := smoothstep(0.12, 0.25, td) * (1.0 - smoothstep(0.45, 0.7, td))
				var collar := smoothstep(0.35, 0.55, td) * (1.0 - smoothstep(cr * 0.8, cr, td))
				var ring := smoothstep(cr * 0.7, cr, td) * (1.0 - smoothstep(R * 0.7, R, td))
				md = maxf(md, 0.8 * root)
				mo = maxf(mo, collar * (0.55 + 0.35 * shade))
				li = maxf(li, 0.7 * ring)
				wet = maxf(wet, 0.25 * root + 0.1 * collar)
			if P.get("_neg_no_floor", false):
				li = 0.0
				md = 0.0
				mo = 0.0
			wet = maxf(wet, 0.25 * md)
		"stream":
			# r10 substrate-first：e＝P7 核心の縁から外へ（m）。卵石・碎石の汀 → 濕泥（ところどころ舌状に延びる）→ 苔・濕った暗い土 → 地形
			var e := wdist(C, p) - RB_CORE
			if e < 7.5:
				var nA := _n(p * 0.5, 1.0, 51.0)
				var nB := _n(p * 1.1, 1.0, 53.0)
				var ew := e - 2.4 * (nA - 0.5) - 0.7 * (nB - 0.5) - 1.0 * (_n(p * 1.6, 1.0, 67.0) - 0.5)
				var pw := 0.7 + 1.0 * smoothstep(0.3, 0.7, _n(p * 0.6, 1.0, 55.0))
				var mw := 2.2 + 1.8 * smoothstep(0.35, 0.75, _n(p * 0.42, 1.0, 61.0)) + 1.6 * smoothstep(0.68, 0.85, _n(p * 0.35, 1.0, 57.0))
				if P.get("_neg_flat_bank", false):
					ew = e
					pw = 1.2
					mw = 3.2
				var el := e - 0.6 * (nB - 0.5)
				pe = 0.85 * (1.0 - smoothstep(pw * 0.5, pw, el))
				gv = maxf(gv, 0.45 * smoothstep(pw * 0.3, pw * 0.8, ew) * (1.0 - smoothstep(pw, pw + 0.9, ew)))
				md = 0.75 * smoothstep(pw * 0.4, pw * 0.9, ew) * (1.0 - smoothstep(mw * 0.7, mw, ew)) * (0.65 + 0.35 * smoothstep(0.3, 0.7, pb))
				mo = maxf(mo, 0.7 * smoothstep(mw * 0.55, mw * 0.95, ew) * (1.0 - smoothstep(mw + 1.0, mw + 2.6, ew)) * smoothstep(0.3, 0.62, _n(p * 0.7, 1.0, 63.0)))
				so = maxf(so, 0.45 * smoothstep(mw * 0.6, mw, ew) * (1.0 - smoothstep(mw + 1.4, mw + 3.0, ew)))
				wet = 0.55 * (1.0 - smoothstep(0.3, mw + 0.5, ew))
				# P7 核心の縁から立ち上げる（核心の切り口を硬い線にしない）
				# P7 核心の外緣から內側 RB_FADE までで立ち上げる（交界の斷層を消す；核心のより內側と P7 構件の上は網格自體を作らない）
				var fade: float = 1.5 if P.get("_neg_core_deep", false) else RB_FADE
				k_in = smoothstep(-fade, 0.15, e)
				md = maxf(md, 0.45 * smoothstep(-fade, -0.1, e) * (1.0 - smoothstep(0.2, 0.7, e)) * smoothstep(0.35, 0.6, pb))
				gv = maxf(gv, 0.35 * (1.0 - smoothstep(-0.1, 0.5, e)) * smoothstep(0.45, 0.7, nB))
				wet = maxf(wet, 0.6 * (1.0 - smoothstep(0.0, 0.8, e)))
	gv *= k_in
	mo *= k_in
	so *= k_in
	li *= k_in
	md *= k_in
	pe *= k_in
	var tot := gv + mo + so + li + md + pe
	if tot > 1.0:
		gv /= tot
		mo /= tot
		so /= tot
		li /= tot
		md /= tot
		pe /= tot
		tot = 1.0
	if tot < 0.02:
		return null
	return [Color(gv, mo, so, li), Vector2(wet, smoothstep(0.0, 4.0, zone_inset(z, p))), Vector2(md, pe)]


## 地面重み 7 値 [碎石, 苔, 踏土, 落葉, 泥, 卵石, 濕潤]（gate 用；overlay なし＝全 0）
static func gwt(P: Dictionary, p: Vector2) -> PackedFloat32Array:
	var w: Variant = ground_w(P, p)
	if w == null:
		return PackedFloat32Array([0, 0, 0, 0, 0, 0, 0])
	var c: Color = w[0]
	var u: Vector2 = w[2]
	return PackedFloat32Array([c.r, c.g, c.b, c.a, u.x, u.y, (w[1] as Vector2).x])


## 草叢 drift の中心ほど 1（半徑×1.25 で 0）
static func drift_k(C: Dictionary, p: Vector2) -> float:
	if not C.has("drift_hash"):
		var H := {}
		for d: Array in C.get("drifts", []):
			var k := Vector2i(floori((d[0] as Vector2).x / 4.0), floori((d[0] as Vector2).y / 4.0))
			if not H.has(k):
				H[k] = []
			H[k].append(d)
		C["drift_hash"] = H
	var H2: Dictionary = C["drift_hash"]
	var kk := Vector2i(floori(p.x / 4.0), floori(p.y / 4.0))
	var best := 0.0
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for d: Array in H2.get(kk + Vector2i(dx, dz), []):
				var q := p.distance_to(d[0]) / (float(d[1]) * 1.25)
				best = maxf(best, 1.0 - smoothstep(0.35, 1.0, q))
	return best


const GC_SHADER := "res://assets/village_v2/groundcover/gc_ground.gdshader"

static func gc_material(z: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(GC_SHADER)
	m.set_shader_parameter("albedo_arr", load("res://assets/village_v2/_matlib/ground/V2G_albedo.jpg"))
	m.set_shader_parameter("nrh_arr", load("res://assets/village_v2/_matlib/ground/V2G_nrh.jpg"))
	m.set_shader_parameter("noise_tex", load("res://assets/village_v2/_matlib/ground/V2G_noise.png"))
	if z == "street" or z == "lawn":
		# 土側へ食い込む草の舌・濃い草の斑：苔チャンネルを地形の草色（やや濃い）へ寄せる
		m.set_shader_parameter("moss_tint", Vector3(0.70, 0.84, 0.60))
		m.set_shader_parameter("moss_contrast", 0.92)
	elif z == "forest":
		# 林床：落葉は地形の林床層より暖かく細かい tile（同じ texture のままだと見分けがつかない）、腐植は暗く
		m.set_shader_parameter("litter_tint", Vector3(1.0, 0.9, 0.8))
		m.set_shader_parameter("litter_tile", 1.1)
		m.set_shader_parameter("litter_rot", 0.66)
		m.set_shader_parameter("mud_tint", Vector3(0.78, 0.74, 0.68))
		m.set_shader_parameter("moss_tint", Vector3(0.50, 0.72, 0.32))
	elif z == "stream":
		m.set_shader_parameter("pebble_tile", 1.9)
		m.set_shader_parameter("pebble_tint", Vector3(1.05, 1.03, 0.98))
		m.set_shader_parameter("pebble_contrast", 1.1)
		m.set_shader_parameter("mud_tint", Vector3(1.2, 1.13, 1.02))
		m.set_shader_parameter("moss_tint", Vector3(0.55, 0.66, 0.40))
	m.resource_name = "GC_Ground_" + z
	return m


static func ground_mesh(P: Dictionary, z: String) -> ArrayMesh:
	var C: Dictionary = P["C"]
	var S: RLib.TriSampler = C["S"]
	var bb := zone_bbox(z)
	var gs: float = ZONE_STEP.get(z, G_STEP)
	var nx := int(ceil(bb.size.x / gs))
	var nz := int(ceil(bb.size.y / gs))
	var WG := {}
	for j in nz + 1:
		for i in nx + 1:
			var p := bb.position + Vector2(i * gs, j * gs)
			if zone_of(p) != z:
				continue
			var br := blocked(C, p, true, 1.25)
			if z == "stream" and br == "riverbank":
				if not stream_ground_ok(P, p, br):
					continue
			elif br != "" and br != "road" and br != "obstacle" and br != "trunk":
				continue
			if br == "road" and z != "street":
				continue
			var w: Variant = ground_w(P, p)
			if w == null:
				continue
			WG[Vector2i(i, j)] = w
	# 3×3 平滑（格子の段を消す）＋縁は淡出
	var nw := {}
	for g: Vector2i in WG:
		var c4: Color = (WG[g][0] as Color) * 4.0
		var u2: Vector2 = (WG[g][1] as Vector2) * 4.0
		var u1: Vector2 = (WG[g][2] as Vector2) * 4.0
		var ws := 4.0
		var nb := 0
		for d: Vector2i in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]:
			if WG.has(g + d):
				var wt := 1.0 if (d.x != 0 and d.y != 0) else 2.0
				c4 += (WG[g + d][0] as Color) * wt
				u2 += (WG[g + d][1] as Vector2) * wt
				u1 += (WG[g + d][2] as Vector2) * wt
				ws += wt
				nb += 1
		nw[g] = [c4 / ws, u2 / ws, u1 / ws]
	WG = nw
	var V := PackedVector3Array()
	var N := PackedVector3Array()
	var Cc := PackedColorArray()
	var U2 := PackedVector2Array()
	var U1 := PackedVector2Array()
	var idx := PackedInt32Array()
	var vid := {}
	for j in nz + 1:
		for i in nx + 1:
			var g := Vector2i(i, j)
			if not WG.has(g):
				continue
			var p := bb.position + Vector2(i * gs, j * gs)
			var h := S.h(p.x, p.y)
			var rh := (C["R"] as RLib.TriSampler).h(p.x, p.y)
			if not is_nan(rh):
				h = maxf(h, rh)
			var d := 0.4
			var nrm := Vector3(S.h(p.x - d, p.y) - S.h(p.x + d, p.y), 2.0 * d, S.h(p.x, p.y - d) - S.h(p.x, p.y + d))
			vid[g] = V.size()
			V.append(Vector3(p.x, h + 0.011, p.y))
			N.append(nrm.normalized() if nrm.is_finite() else Vector3.UP)
			Cc.append(WG[g][0])
			U2.append(WG[g][1])
			U1.append(WG[g][2])
	for j in nz:
		for i in nx:
			var k00: Variant = vid.get(Vector2i(i, j))
			var k10: Variant = vid.get(Vector2i(i + 1, j))
			var k01: Variant = vid.get(Vector2i(i, j + 1))
			var k11: Variant = vid.get(Vector2i(i + 1, j + 1))
			if k00 == null or k10 == null or k01 == null or k11 == null:
				continue
			if absf(V[k00].y - V[k11].y) <= absf(V[k10].y - V[k01].y):
				idx.append_array([k00, k10, k11, k00, k11, k01])
			else:
				idx.append_array([k00, k10, k01, k10, k11, k01])
	var am := ArrayMesh.new()
	if idx.is_empty():
		return am
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = V
	arr[Mesh.ARRAY_NORMAL] = N
	arr[Mesh.ARRAY_COLOR] = Cc
	arr[Mesh.ARRAY_TEX_UV2] = U2
	arr[Mesh.ARRAY_TEX_UV] = U1
	arr[Mesh.ARRAY_INDEX] = idx
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	am.surface_set_material(0, gc_material(z))
	am.resource_name = "gc_ground_" + z
	return am


# ─────────────────────────── 烘焙 ───────────────────────────

## 小石：_matlib V2_Stone（只讀）の triplanar 副本（P8 FV._stone_mat は P8 生成中の registry 文脈が要るので使わない）
const STONE_TRES := "res://assets/village_v2/_matlib/V2_Stone.tres"

static func stone_mat() -> StandardMaterial3D:
	var m := (load(STONE_TRES) as StandardMaterial3D).duplicate() as StandardMaterial3D
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * 1.25
	m.albedo_color = Color(0.62, 0.62, 0.62)
	m.resource_name = "GC_Stone"
	return m


static func bake(P: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = NODE_NAME
	var gnode := Node3D.new()
	gnode.name = "Ground"
	root.add_child(gnode)
	for z: String in ZONE_ORDER:
		var g := MeshInstance3D.new()
		g.name = "Ground_" + z
		g.mesh = ground_mesh(P, z)
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		gnode.add_child(g)
	# MultiMesh 分塊（P8 plant shader／V2_Stone）
	var acc := {}
	for it: Dictionary in P["items"]:
		var p: Vector2 = it["p"]
		var key := Vector3i(floori(p.x / CHUNK), floori(p.y / CHUNK), int(it["k"]))
		if not acc.has(key):
			acc[key] = [[], []]
		var kk := int(it["k"])
		var hh := float(it["h"])
		var ww := float(it["w"])
		var sc := Vector3.ONE * hh
		if kk in GRASS_KINDS:
			sc = Vector3(hh * ww, hh, hh * ww)
		elif kk in [K_LITTER, K_MOSS]:
			sc = Vector3(ww, hh, ww)
		var b := Basis(Vector3.UP, float(it["yaw"])).scaled(sc)
		if it.has("basis"):
			b = it["basis"]
		acc[key][0].append(Transform3D(b, Vector3(p.x, float(it["y"]), p.y)))
		acc[key][1].append(it["col"])
	var meshes := {}
	var mm_root := Node3D.new()
	mm_root.name = "Chunks"
	root.add_child(mm_root)
	var plant := FV._plant_mat()
	var stone := stone_mat()
	var pebble := stone_mat()
	pebble.albedo_color = Color(0.95, 0.93, 0.88)
	pebble.roughness = 0.75
	pebble.resource_name = "GC_Pebble"
	var rootm := StandardMaterial3D.new()
	rootm.vertex_color_use_as_albedo = true
	rootm.vertex_color_is_srgb = true            # 頂點色は sRGB で作っている（linear 扱いだと 2 倍明るく白く見える）
	rootm.roughness = 0.9
	rootm.resource_name = "GC_Root"
	var keys := acc.keys()
	keys.sort()
	var n_mm := 0
	for key: Vector3i in keys:
		var k := key.z
		if not meshes.has(k):
			meshes[k] = kind_mesh(k)
		var nm := "GC_%d_%d_%s" % [key.x, key.y, KIND_NAMES[k]]
		var mat: Material = stone if k == K_STONE else (pebble if k == K_PEBBLE else (rootm if k == K_ROOT else plant))
		var inst: Array = acc[key]
		if k in GRASS_KINDS:
			FV._mm_node(mm_root, nm + "_near", meshes[k][0], inst[0], inst[1], mat, 0.0, 0.0, NEAR, 4.0, true)
			var fx: Array = []
			var fc: Array = []
			var widen := Basis.from_scale(Vector3(1.3, 1.0, 1.3))
			for i in inst[0].size():
				if fposmod(float(i) * 0.618034, 1.0) < 0.45:
					var xf: Transform3D = inst[0][i]
					fx.append(Transform3D(xf.basis * widen, xf.origin))
					fc.append(inst[1][i])
			if not fx.is_empty():
				FV._mm_node(mm_root, nm + "_far", meshes[k][1], fx, fc, mat, NEAR, 4.0, FAR, 6.0, true)
			n_mm += 2
		else:
			FV._mm_node(mm_root, nm + "_near", meshes[k][0], inst[0], inst[1], mat, 0.0, 0.0, 22.0, 3.0, true)
			FV._mm_node(mm_root, nm + "_far", meshes[k][1], inst[0], inst[1], mat, 22.0, 3.0, SMALL_RANGE, 5.0, true)
			n_mm += 2
	# 只讀沿用の植物（蕨・笹・低木＝veg_kit prefab、菅・蘆・花菖蒲＝waterside_kit mesh）
	var low := Node3D.new()
	low.name = "Plants"
	root.add_child(low)
	var wmesh := {}
	var n_i := 0
	for it: Dictionary in P["nodes"]:
		var id := String(it["id"])
		var xf := SG.xf_of(it)
		if String(it["kind"]) == "tree":
			var t := SG.tree_expanded(id, String(it.get("preset", "mature")))
			t.name = "%04d_%s" % [n_i, id]
			t.transform = xf
			t.set_meta("gc_zone", String(it["zone"]))
			for cs in t.find_children("*", "CollisionShape3D", true, false):
				cs.get_parent().remove_child(cs)
				cs.free()
			for sb in t.find_children("*", "StaticBody3D", true, false):
				sb.get_parent().remove_child(sb)
				sb.free()
			low.add_child(t)
		else:
			var node := Node3D.new()
			node.name = "%04d_%s" % [n_i, id]
			node.transform = xf
			node.set_meta("gc_zone", String(it["zone"]))
			for lod in 2:
				var key := id + ("_l1" if lod == 1 else "")
				if not wmesh.has(key):
					wmesh[key] = load(WK + key + ".res")
				var mi := MeshInstance3D.new()
				mi.name = "LOD%d" % lod
				mi.mesh = wmesh[key]
				mi.visibility_range_begin = 0.0 if lod == 0 else 30.0
				mi.visibility_range_end = 30.0 if lod == 0 else 80.0
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				node.add_child(mi)
			low.add_child(node)
		n_i += 1
	root.set_meta("items", (P["items"] as Array).size())
	root.set_meta("nodes", (P["nodes"] as Array).size())
	root.set_meta("multimesh_nodes", n_mm)
	root.set_meta("art_revision", "P9 R5-1 Groundcover pilot r10f（targeted rework：溪 substrate-first／林 forest-floor-first／鈴奈庵北 土場；ART_REVIEW）")
	return root


static func own(n: Node, owner: Node) -> void:
	SG.own(n, owner)

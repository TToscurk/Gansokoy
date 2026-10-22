extends SceneTree
## 博麗神社 v3 場景組裝（總裝）。每次從頭組出 maps/shrine_v3/shrine_v3.tscn（沒有任何舊神社資產）。
##   python tools/shrine_v3/gen_terrain.py
##   godot --headless --path godot --script res://tools/shrine_v3/build_terrain.gd
##   （Blender）make_arch.py／make_site.py／make_veg.py → --import → build_assets.gd／build_veg.gd
##   godot --headless --path godot --script res://tools/shrine_v3/build_scene.gd
## 約定：x 東 / z 南(入口) / y 上；主軸 x=0；神社正面朝 +z。地面高一律 S3.height_at()（＝近景網格實際高度）。
## 不存 MultiMesh（headless 存出零矩陣）：草叢／蕨由 maps/shrine_v3/s3_scatter.gd 在執行期依 meta 生成。

const S3 := preload("res://tools/shrine_v3/s3lib.gd")
const M := preload("res://tools/shrine_v3/s3mat.gd")
const OUT := "res://maps/shrine_v3/shrine_v3.tscn"
const GEN := "res://maps/shrine_v3/gen/"
const SCN := "res://assets/shrine_v3/scenes/"
const SITE := "res://assets/shrine_v3/mesh/site/"
const VEG := "res://assets/shrine_v3/mesh/veg/"
const VEG_INFO := "res://assets/shrine_v3/models/veg/"
## 內部資產（樹以外，使用者 2026-10-22 同意）：獸道 S01 套件地被，tools/shrine_v3/build_internal.gd 轉成 mesh/int/
const INT := "res://assets/shrine_v3/mesh/int/"
## 地被圖層（執行期 MultiMesh，s3_scatter.gd）：名 → 設定。stride 7＝(x, y, z, yaw, scale, nx, nz)
const COVER := {
	"蕨_大a": {"mesh": "s01_fern_a", "lod": true, "vis_end": 56.0, "shadow": true},
	"蕨_大c": {"mesh": "s01_fern_c", "lod": true, "vis_end": 56.0, "shadow": true},
	"蕨_b": {"mesh": "s01_fern_b", "lod": true, "vis_end": 56.0, "shadow": true},
	"蕨_小": {"mesh": "s01_fern_d", "lod": true, "vis_end": 50.0},
	"草本_a": {"mesh": "s01_forb_a", "lod": true, "vis_end": 46.0},
	"草本_b": {"mesh": "s01_forb_b", "lod": false, "vis_end": 40.0},
	"蕗": {"mesh": "s01_fuki_a", "lod": true, "vis_end": 46.0},
	"闊葉草": {"mesh": "s01_herb_broad_a", "lod": true, "vis_end": 46.0},
	"熊笹_a": {"mesh": "s01_sasa_a", "lod": true, "vis_end": 56.0, "shadow": true},
	"熊笹_b": {"mesh": "s01_sasa_b", "lod": true, "vis_end": 56.0, "shadow": true},
	"莎草": {"mesh": "s01_sedge_a", "lod": true, "vis_end": 52.0},
	"蔭草": {"mesh": "s01_shadegrass_a", "lod": true, "vis_end": 42.0},
	"高草_a": {"mesh": "s01_grass_tall_a", "lod": true, "vis_end": 52.0},
	"高草_c": {"mesh": "s01_grass_tall_c", "lod": true, "vis_end": 52.0},
	"矮草_a": {"mesh": "s01_grass_short_a", "lod": true, "vis_end": 42.0},
	"矮草_b": {"mesh": "s01_grass_short_b", "lod": true, "vis_end": 42.0},
	"落葉_a": {"mesh": "s01_litter_a", "lod": false, "vis_end": 40.0},
	"落葉_b": {"mesh": "s01_litter_b", "lod": false, "vis_end": 40.0},
	"楓落葉": {"mesh": "s01_litter_b", "lod": false, "vis_end": 40.0, "color": [1.55, 0.62, 0.42], "color_var": 0.18},
	"苔": {"mesh": "s01_moss_a", "lod": false, "vis_end": 40.0},
	"細枝": {"mesh": "s01_twigs_a", "lod": false, "vis_end": 28.0},
	"灌叢_a": {"mesh": "s01_shrub_a", "lod": false, "vis_end": 75.0, "shadow": true},
	"灌叢_b": {"mesh": "s01_shrub_b", "lod": false, "vis_end": 75.0, "shadow": true},
}

var sroot: Node3D
var L: Dictionary
var P := 30.0
var stats := {}
var rng := RandomNumberGenerator.new()
var occupied: Array = []      # [Vector2 中心, 半徑]：已放置物件（樹／岩／建築）
var veg_info := {}
var mask_a: Image
var mask_b: Image
var mask_c: Image
var cover := {}                # 地被圖層名 → Array[float]（stride 7；收集完才轉 PackedFloat32Array）
var cover_n := {}              # 統計：各區放了多少


func add(parent: Node, n: Node, nm := "") -> Node:
	if nm != "":
		n.name = nm
	parent.add_child(n)
	n.owner = sroot
	return n


func group(parent: Node, nm: String) -> Node3D:
	return add(parent, Node3D.new(), nm) as Node3D


func gy(x: float, z: float) -> float:
	return S3.height_at(x, z)


func v2(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


# ───────── 幾何查詢 ─────────
func poly_of(key: String) -> PackedVector2Array:
	var pv := PackedVector2Array()
	for p in L[key]:
		pv.append(v2(p))
	return pv


func dist_polyline(p: Vector2, pts: Array) -> float:
	var best := INF
	for i in pts.size() - 1:
		var a := v2(pts[i])
		var b := v2(pts[i + 1])
		var q := Geometry2D.get_closest_point_to_segment(p, a, b)
		best = minf(best, p.distance_to(q))
	return best


func dist_to_poly(p: Vector2, poly: PackedVector2Array) -> float:
	var best := INF
	for i in poly.size():
		var q := Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()])
		best = minf(best, p.distance_to(q))
	return best


func pond_ring(k: float, i: int, n: int) -> Vector2:
	var pc: Dictionary = L["pond"]
	var th := deg_to_rad(float(pc["rot_deg"]))
	var a := TAU * float(i) / float(n)
	var wob := 1.0 + 0.13 * sin(2.0 * a + 0.7) + 0.08 * sin(3.0 * a - 1.2) + 0.05 * sin(5.0 * a + 2.0)
	var lx := cos(a) * float(pc["rx"]) * wob * k
	var lz := sin(a) * float(pc["rz"]) * wob * k
	return Vector2(float(pc["cx"]) + lx * cos(th) - lz * sin(th), float(pc["cz"]) + lx * sin(th) + lz * cos(th))


func pond_rn(p: Vector2) -> float:
	## 與 terrain_lib 相同的岸線定義：rn＝1 是水線（橢圓×擾動）。
	var pc: Dictionary = L["pond"]
	var th := deg_to_rad(float(pc["rot_deg"]))
	var dx := p.x - float(pc["cx"])
	var dz := p.y - float(pc["cz"])
	var lx := dx * cos(th) + dz * sin(th)
	var lz := -dx * sin(th) + dz * cos(th)
	var a := atan2(lz / float(pc["rz"]), lx / float(pc["rx"]))
	var wob := 1.0 + 0.13 * sin(2.0 * a + 0.7) + 0.08 * sin(3.0 * a - 1.2) + 0.05 * sin(5.0 * a + 2.0)
	return sqrt(pow(lx / float(pc["rx"]), 2) + pow(lz / float(pc["rz"]), 2)) / wob


func in_pond(p: Vector2, k := 1.0) -> bool:
	return pond_rn(p) < k


func mask(img: Image, x: float, z: float) -> Color:
	var nr: Dictionary = L["near"]
	var u := (x - float(nr["x0"])) / (float(nr["x1"]) - float(nr["x0"]))
	var v := (z - float(nr["z0"])) / (float(nr["z1"]) - float(nr["z0"]))
	var px := clampi(int(u * img.get_width()), 0, img.get_width() - 1)
	var pz := clampi(int(v * img.get_height()), 0, img.get_height() - 1)
	return img.get_pixel(px, pz)


func beast_xz() -> Array:
	var out := []
	for p in L["beast"]:
		out.append([float(p[0]), float(p[1])])
	return out


## 行走動線與構造物的淨空（r＝物件半徑）
func blocked(p: Vector2, r: float) -> bool:
	var st: Dictionary = L["stair"]
	if absf(p.x) < float(st["width"]) * 0.5 + 0.6 + r and p.y > 8.0 and p.y < float(L["z_foot"]) + 4.0:
		return true
	if dist_polyline(p, beast_xz()) < float(L["beast_half_w"]) + 0.8 + r:
		return true
	if p.distance_to(Vector2(0.0, float(L["z_foot"]) + 2.2)) < 5.5 + r:
		return true
	for key in ["grove", "pond_w", "to_store", "to_temizuya"]:
		if dist_polyline(p, L["paths"][key]) < 1.1 + r:
			return true
	if on_paving(p, 0.35 + r):
		return true
	if in_pond(p, 1.25):
		return true
	for o in occupied:
		if p.distance_to(o[0]) < float(o[1]) + r:
			return true
	return false


func occupy(p: Vector2, r: float) -> void:
	occupied.append([p, r])


## 參道鋪石半寬（與 layout.py sando_hw 同一定義；z 在範圍外回 0）
func sando_hw(z: float) -> float:
	var s: Dictionary = L["sando"]
	if z > float(s["z0"]) or z < float(s["z1"]):
		return 0.0
	if z >= float(s["torii_z"]):
		return float(s["torii_hw"])
	if z >= float(s["nat_z"]):
		var t := clampf((float(s["torii_z"]) - z) / 0.8, 0.0, 1.0)
		var hw := float(s["torii_hw"]) + (float(s["nat_hw"]) - float(s["torii_hw"])) * t
		var u := clampf((float(s["nat_z"]) + 0.8 - z) / 0.8, 0.0, 1.0)
		return hw + (float(s["mid_hw"]) - hw) * u
	if z >= float(s["fan_z0"]):
		return float(s["mid_hw"])
	if z >= float(s["fan_z1"]):
		var t2 := (float(s["fan_z0"]) - z) / (float(s["fan_z0"]) - float(s["fan_z1"]))
		t2 = t2 * t2 * (3.0 - 2.0 * t2)
		return float(s["mid_hw"]) + (float(s["apron_hw"]) - float(s["mid_hw"])) * t2
	return float(s["apron_hw"])


## 參道（含拜殿前台）與手水舍石台的外擴範圍內？
func on_paving(p: Vector2, margin: float) -> bool:
	var s: Dictionary = L["sando"]
	if p.y <= float(s["z0"]) + margin and p.y >= float(s["z1"]) - margin:
		var hw := sando_hw(clampf(p.y, float(s["z1"]), float(s["z0"])))
		if absf(p.x) < hw + margin:
			return true
	var tp: Array = L["temizuya_pad"]
	return p.x > float(tp[0]) - margin and p.x < float(tp[1]) + margin and p.y > float(tp[2]) - margin and p.y < float(tp[3]) + margin


## 斜坡上放植物：取底部一圈（半徑 r）四點與中心的最低地面高（下坡側不懸空）
func ground_min(x: float, z: float, r: float) -> float:
	var y := gy(x, z)
	if r <= 0.01:
		return y
	for k in 4:
		var a := float(k) * PI * 0.5 + 0.4
		y = minf(y, gy(x + cos(a) * r, z + sin(a) * r))
	return y


var _arect := {}


## 建築／道具的世界外框（models/<名>.json 的 render_bounds，含屋簷；依 yaw 旋轉後取 XZ 外接矩形）
func asset_rect(nm: String, x: float, z: float, yaw: float) -> Rect2:
	if not _arect.has(nm):
		_arect[nm] = JSON.parse_string(FileAccess.get_file_as_string("res://assets/shrine_v3/models/%s.json" % nm))["render_bounds"]
	var rb: Dictionary = _arect[nm]
	var lo := Vector2(INF, INF)
	var hi := -lo
	for lx in [float(rb["min"][0]), float(rb["max"][0])]:
		for lz in [float(rb["min"][2]), float(rb["max"][2])]:
			var v := Vector3(lx, 0.0, lz).rotated(Vector3.UP, yaw)
			lo = lo.min(Vector2(x + v.x, z + v.z))
			hi = hi.max(Vector2(x + v.x, z + v.z))
	return Rect2(lo, hi - lo)


## 西柵在 z 處的 x（layout fence_w 折線內插）
func fence_x(z: float) -> float:
	var f: Array = L["fence_w"]
	for i in f.size() - 1:
		var z0 := float(f[i][1])
		var z1 := float(f[i + 1][1])
		if (z <= z0 and z >= z1) or (z >= z0 and z <= z1):
			var t := (z - z0) / (z1 - z0) if absf(z1 - z0) > 1e-4 else 0.0
			return lerpf(float(f[i][0]), float(f[i + 1][0]), t)
	return float(f[0][0]) if z > float(f[0][1]) else float(f[f.size() - 1][0])


## 地被一株：圖層名、位置、縮放、貼坡程度（0＝直立、1＝完全貼地面法線）、底部半徑（決定下沉）
func cov(layer: String, x: float, z: float, s: float, tilt := 0.0, base_r := 0.15, sink := 0.02) -> void:
	if not COVER.has(layer):
		push_error("未知地被圖層 %s" % layer)
		return
	var n := S3.normal_at(x, z, maxf(base_r, 0.4))
	var y := ground_min(x, z, base_r * s) - sink
	if not cover.has(layer):
		cover[layer] = []
	(cover[layer] as Array).append_array([x, y, z, rng.randf() * TAU, s, n.x * tilt, n.z * tilt])


# ───────── 地形、天空、邊界 ─────────
func add_terrain() -> void:
	var g := group(sroot, "地形")
	var near := MeshInstance3D.new()
	near.mesh = load(GEN + "terrain_near.res")
	near.material_override = M.save(M.terrain(), "terrain_near")
	add(g, near, "近景地形")
	var body := StaticBody3D.new()
	add(g, body, "近景地形碰撞")
	var cs := CollisionShape3D.new()
	cs.shape = load(GEN + "terrain_near_col.res")
	add(body, cs, "CollisionShape3D")
	var vm := M.save(M.vista(L["near"]), "terrain_vista")
	for nm in ["terrain_mid", "terrain_far"]:
		var mi := MeshInstance3D.new()
		mi.mesh = load(GEN + nm + ".res")
		mi.material_override = vm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if nm == "terrain_far" else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add(g, mi, "中景地形" if nm == "terrain_mid" else "遠景地形")


func add_sky() -> void:
	var sky := Node3D.new()
	sky.set_script(load("res://scripts/sky_system.gd"))
	sky.set("時刻", 10.0)
	sky.set("一日長度分鐘", 60.0)
	sky.set("方位角", 0.0)
	sky.set("陰影距離", 160.0)
	add(sroot, sky, "天象系統")


## 隱形牆：沿可走範圍多邊形，每段一塊薄牆（外推 0.6 m），高 80 m。
func add_boundary() -> void:
	var body := StaticBody3D.new()
	add(sroot, body, "邊界")
	var pv := poly_of("play")
	var n := pv.size()
	for i in n:
		var a := pv[i]
		var b := pv[(i + 1) % n]
		var mid := (a + b) * 0.5
		var d := b - a
		var nrm := Vector2(-d.y, d.x).normalized()
		if Geometry2D.is_point_in_polygon(mid + nrm * 0.5, pv):
			nrm = -nrm
		var c := mid + nrm * 0.6
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(d.length() + 1.4, 80.0, 1.0)
		cs.shape = bx
		var yaw := atan2(-d.y, d.x)
		cs.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(c.x, gy(c.x, c.y) + 20.0, c.y))
		add(body, cs, "牆_%02d" % i)
	stats["walls"] = n


# ───────── 建築與境內物件 ─────────
func place_scene(parent: Node, asset: String, nm: String, x: float, z: float, yaw: float, y := NAN) -> Node3D:
	var ps := load(SCN + asset + ".tscn") as PackedScene
	var inst := ps.instantiate() as Node3D
	inst.name = nm
	if is_nan(y):
		y = gy(x, z)
	inst.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(x, y, z))
	parent.add_child(inst)
	inst.owner = sroot
	return inst


func foot_hi(x: float, z: float, hw: float, hd: float, yaw: float) -> float:
	return S3.footprint_range(x, z, hw, hd, yaw).y


func add_architecture() -> void:
	var g := group(sroot, "建築")
	var pl: Dictionary = L["place"]
	var h: Array = pl["haiden"]
	place_scene(g, "haiden", "拜殿", float(h[0]), float(h[1]), float(h[2]), foot_hi(float(h[0]), float(h[1]), 4.0, 3.3, 0.0))
	occupy(Vector2(float(h[0]), float(h[1]) + 0.5), 6.2)
	var t: Array = pl["torii"]
	var gl := gy(-1.7, float(t[1]))
	var gr := gy(1.7, float(t[1]))
	place_scene(g, "torii", "鳥居", 0.0, float(t[1]), 0.0, maxf(gl, gr) - 0.02)
	var tz: Array = pl["temizuya"]
	place_scene(g, "temizuya", "手水舍", float(tz[0]), float(tz[1]), float(tz[2]), foot_hi(float(tz[0]), float(tz[1]), 1.1, 0.8, float(tz[2])) - 0.02)
	occupy(Vector2(float(tz[0]), float(tz[1])), 2.0)
	var sh: Array = pl["storehouse"]
	place_scene(g, "storehouse", "倉庫", float(sh[0]), float(sh[1]), float(sh[2]), foot_hi(float(sh[0]), float(sh[1]), 1.6, 1.3, float(sh[2])) - 0.03)
	occupy(Vector2(float(sh[0]), float(sh[1])), 2.6)
	var o := group(sroot, "境內物件")
	var sa: Array = pl["saisen"]
	place_scene(o, "saisen", "賽錢箱", float(sa[0]), float(sa[1]), 0.0, foot_hi(float(sa[0]), float(sa[1]), 0.62, 0.32, 0.0) + 0.012)     # 坐在拜殿前台鋪石上（石頂＝地面最高點 +1.4 cm）
	for side in [["komainu_l", "狛犬_吽", "komainu_un"], ["komainu_r", "狛犬_阿", "komainu_a"]]:
		var k: Array = pl[side[0]]
		var y := foot_hi(float(k[0]), float(k[1]), 0.46, 0.46, float(k[2])) - 0.03
		place_scene(o, "komainu_base", String(side[1]) + "_台座", float(k[0]), float(k[1]), float(k[2]), y)
		place_scene(o, String(side[2]), String(side[1]), float(k[0]), float(k[1]), float(k[2]), y + 0.86)
		occupy(Vector2(float(k[0]), float(k[1])), 0.8)
	# 石燈籠（美術深化）：鳥居左側單座（大）→ 參道中段一對（小）→ 拜殿前一對（大），見 layout.py PLACE
	var lanterns := [["lantern_gate", "石燈籠_鳥居左", "lantern_l", 1.15], ["lantern_mid_l", "石燈籠_參道左", "lantern_s", 1.0],
		["lantern_mid_r", "石燈籠_參道右", "lantern_s", 1.0], ["lantern_haiden_l", "石燈籠_拜殿左", "lantern_l", 1.1],
		["lantern_haiden_r", "石燈籠_拜殿右", "lantern_l", 1.1]]
	for ln in lanterns:
		var lp: Array = pl[ln[0]]
		var sc := float(ln[3])
		var lan := place_scene(o, String(ln[2]), String(ln[1]), float(lp[0]), float(lp[1]), rng.randf_range(-0.05, 0.05))
		# 落在腳印最低點（台座外框 = render_bounds × 縮放）：斜坡上高側埋入、低側不懸空（量測：鳥居左那座坡差 19 cm）
		var lr := asset_rect(String(ln[2]), float(lp[0]), float(lp[1]), 0.0)
		lan.position.y = S3.footprint_range(float(lp[0]), float(lp[1]), lr.size.x * 0.5 * sc, lr.size.y * 0.5 * sc, 0.0).x - 0.02
		lan.scale = Vector3.ONE * sc
		lan.rotate_object_local(Vector3.RIGHT, rng.randf_range(-0.012, 0.012))
		occupy(Vector2(float(lp[0]), float(lp[1])), 0.6 * sc)
	var sg: Array = pl["shagohyo"]
	place_scene(o, "shagohyo", "社號標", float(sg[0]), float(sg[1]), 0.15, foot_hi(float(sg[0]), float(sg[1]), 0.3, 0.3, 0.15) - 0.02)
	occupy(Vector2(float(sg[0]), float(sg[1])), 0.6)
	# 生活小道具：倉庫旁木箱、靠牆竹箒、手水舍邊木桶
	var shx := float(sh[0])
	var shz := float(sh[1])
	place_scene(o, "crate", "木箱_1", shx - 0.2, shz - 2.0, 0.1)
	place_scene(o, "crate", "木箱_2", shx + 0.5, shz - 2.1, -0.25)
	var cr2 := place_scene(o, "crate", "木箱_3", shx + 0.1, shz - 2.05, 0.4)
	cr2.position.y += 0.44
	var br := place_scene(o, "broom", "竹箒", shx - 1.62, shz + 1.0, 0.0)
	br.rotate_object_local(Vector3.FORWARD, 0.22)
	# 手水舍旁木桶：放在手水舍腳印外（局部 x 0.9、z 1.75 → 世界），落在地面上
	var tyaw := float(tz[2])
	var boff := Vector3(0.9, 0.0, 1.75).rotated(Vector3.UP, tyaw)
	var bx_ := float(tz[0]) + boff.x
	var bz_ := float(tz[1]) + boff.z
	place_scene(o, "bucket", "木桶", bx_, bz_, 0.3, foot_hi(bx_, bz_, 0.18, 0.18, 0.0) - 0.01)
	occupy(Vector2(bx_, bz_), 0.35)
	# 陰陽玉彩蛋（規格 §25–27：全圖 1 顆、直徑 0.26 m、像靈夢隨手放的；倉庫北側木箱旁的苔石間、落楓葉）
	var eg: Array = pl["onmyoudama"]
	var ex := float(eg[0])
	var ez := float(eg[1])
	var egg := group(o, "陰陽玉彩蛋")
	var orb := place_scene(egg, "onmyoudama", "陰陽玉", ex, ez, 0.6, ground_min(ex, ez, 0.1) - 0.035)
	orb.set_meta("easter_egg", "§25–27 LEVEL 3 實體陰陽玉，全圖僅此 1 顆。直徑 0.26 m。來源：assets/shrine/陰陽玉.glb（內部資產）")
	# 西側是木箱_2（x ≤ 16.08）；石頭只放北、東兩側
	put_rock(egg, "rock_small_a", ex + 0.08, ez - 0.37, 0.85, false, 900)
	put_rock(egg, "rock_small_b", ex + 0.39, ez + 0.03, 0.8, false, 901)
	occupy(Vector2(ex, ez), 0.55)
	for i in 7:
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.3, 1.1)
		cov("楓落葉", ex + cos(a) * r, ez + sin(a) * r, rng.randf_range(0.18, 0.3), 1.0, 0.3, 0.0)
	cov("蕨_小", ex + 0.6, ez - 0.5, 0.75, 0.3, 0.3)
	cov("蔭草", ex + 0.15, ez - 0.75, 0.9, 0.2, 0.2)
	stats["arch"] = g.get_child_count() + o.get_child_count()


# ───────── 場地構件：石段、參道、西崖木柵＋碰撞 ─────────
func add_site() -> void:
	var g := group(sroot, "參道石段")
	for nm in [["stairs", "石段"], ["sando", "參道石板"], ["fence_w", "西崖木柵"]]:
		var mi := MeshInstance3D.new()
		mi.mesh = load(SITE + String(nm[0]) + ".res")
		add(g, mi, nm[1])
	var site: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/shrine_v3/models/site/site.json"))
	var body := StaticBody3D.new()
	add(g, body, "石段碰撞")
	var k := 0
	for c in site["collision"]:
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		var t := String(c["type"])
		if t == "ramp":
			var z0 := float(c["z0"])
			var z1 := float(c["z1"])
			var y0 := float(c["y0"])
			var y1 := float(c["y1"])
			var ln := Vector2(z1 - z0, y1 - y0).length()
			# 繞 +x 旋轉 a：局部 +z 轉成 (0, -sin a, cos a)。要讓 +z 方向下降 (y1<y0) → sin a = (y0-y1)/ln。
			var a := atan2(y0 - y1, z1 - z0)
			var bas := Basis(Vector3.RIGHT, a)
			bx.size = Vector3(float(c["w"]), 0.4, ln + 0.1)
			var mid := Vector3(0.0, (y0 + y1) * 0.5, (z0 + z1) * 0.5)
			cs.transform = Transform3D(bas, mid - bas.y * 0.2)
		elif t == "flat":
			bx.size = Vector3(float(c["w"]), 0.4, float(c["z1"]) - float(c["z0"]))
			cs.transform = Transform3D(Basis(), Vector3(0.0, float(c["y"]) - 0.2, (float(c["z0"]) + float(c["z1"])) * 0.5))
		else:
			bx.size = Vector3(c["size"][0], c["size"][1], c["size"][2])
			cs.transform = Transform3D(Basis(Vector3.UP, float(c["yaw"])), Vector3(c["pos"][0], c["pos"][1], c["pos"][2]))
		cs.shape = bx
		add(body, cs, "%02d_%s" % [k, String(c.get("note", t))])
		k += 1
	stats["site_cols"] = k


# ───────── 池塘 ─────────
func add_pond() -> void:
	var pc: Dictionary = L["pond"]
	var lvl := float(pc["level"])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 72
	var ring := []
	for i in n:
		var q := pond_ring(1.06, i, n)       # 水面多延伸 6%（藏進岸坡）
		ring.append(Vector3(q.x, lvl, q.y))
	var cen := Vector3(float(pc["cx"]), lvl, float(pc["cz"]))
	# Godot 正面＝順時針（由上往下看）。ring 依角度遞增在俯視畫面是順時針 → (中心, i, i+1)。
	#（反過來會被 cull_back 剔掉：俯視看不到水面，只剩一個乾的窪地。）
	for i in n:
		for v in [cen, ring[i], ring[(i + 1) % n]]:
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2((v as Vector3).x, (v as Vector3).z))
			st.add_vertex(v)
	var mesh := st.commit()
	var pm := M.asset("s3_water") as ShaderMaterial
	pm.set_shader_parameter("depth_m", 1.1)
	pm.set_shader_parameter("clarity", 0.42)
	pm.resource_name = "s3_pond"
	mesh.surface_set_material(0, M.save(pm, "s3_pond"))
	S3.save_retry(mesh, GEN + "pond_water.res")
	var mi := MeshInstance3D.new()
	mi.mesh = load(GEN + "pond_water.res")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add(sroot, mi, "池塘水面")
	# 池岸隱形矮牆（水線內 4%）：玩家站得到水邊、走不進池裡
	var body := StaticBody3D.new()
	add(sroot, body, "池岸碰撞")
	var m := 40
	for i in m:
		var a := pond_ring(0.96, i, m)
		var b := pond_ring(0.96, (i + 1) % m, m)
		var mid := (a + b) * 0.5
		var d := b - a
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(d.length() + 0.15, 2.0, 0.3)
		cs.shape = bx
		cs.transform = Transform3D(Basis(Vector3.UP, atan2(-d.y, d.x)), Vector3(mid.x, lvl + 0.5, mid.y))
		add(body, cs, "岸_%02d" % i)


# ───────── 岩石 ─────────
const ROCKS_BIG := ["rock_boulder_a", "rock_boulder_b"]
const ROCKS_MID := ["rock_mid_a", "rock_mid_b", "rock_mid_c"]
const ROCKS_SMALL := ["rock_small_a", "rock_small_b", "rock_flat_a"]


func put_rock(g: Node, kind: String, x: float, z: float, s: float, with_col: bool, idx: int) -> void:
	var mesh: Mesh = load(SITE + kind + ".res")
	var aabb := mesh.get_aabb()
	var r := maxf(aabb.size.x, aabb.size.z) * 0.5 * s
	var lo := S3.footprint_range(x, z, r * 0.7, r * 0.7, 0.0).x
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var yaw := rng.randf() * TAU
	var nrm := S3.normal_at(x, z, maxf(r, 0.5))
	var b := Basis(Vector3.UP, yaw)
	var tilt := Basis()
	if nrm.y < 0.999:
		tilt = Basis(Vector3.UP.cross(nrm).normalized(), Vector3.UP.angle_to(nrm) * 0.6)
	mi.transform = Transform3D(tilt * b.scaled(Vector3(s, s * rng.randf_range(0.85, 1.1), s)), Vector3(x, lo, z))
	add(g, mi, "%s_%02d" % [kind, idx])
	if with_col:
		var body := StaticBody3D.new()
		add(mi, body, "碰撞")
		var cs := CollisionShape3D.new()
		cs.shape = load(SITE + kind + "_col.res")
		add(body, cs, "CollisionShape3D")
	occupy(Vector2(x, z), r * 0.8)


func add_rocks() -> void:
	var g := group(sroot, "岩石")
	var n := 0
	# 平台南緣（填方坡）兩側
	for i in 14:
		var x := lerpf(-19.0, 21.0, float(i) / 13.0) + rng.randf_range(-1.2, 1.2)
		if absf(x) < 3.2:
			continue
		var z := 10.6 + rng.randf_range(0.0, 2.6)
		if blocked(Vector2(x, z), 0.4):
			continue
		var kind: String = ROCKS_MID[rng.randi() % 3] if rng.randf() < 0.6 else ROCKS_SMALL[rng.randi() % 3]
		put_rock(g, kind, x, z, rng.randf_range(0.8, 1.25), true, n)
		n += 1
	# 石段兩側
	var zz := 13.0
	while zz < float(L["z_foot"]):
		for sx in [-1.0, 1.0]:
			if rng.randf() < 0.7:
				var x2: float = sx * rng.randf_range(2.6, 4.2)
				var z2 := zz + rng.randf_range(-1.5, 1.5)
				if not blocked(Vector2(x2, z2), 0.3):
					var kind2: String = ROCKS_MID[rng.randi() % 3] if rng.randf() < 0.5 else ROCKS_SMALL[rng.randi() % 3]
					put_rock(g, kind2, x2, z2, rng.randf_range(0.8, 1.3), false, n)
					n += 1
		zz += rng.randf_range(4.5, 6.5)
	# 池岸
	for i in 11:
		var q := pond_ring(rng.randf_range(1.02, 1.22), i * 6 + rng.randi_range(0, 3), 66)
		if dist_polyline(q, L["paths"]["pond_w"]) < 1.2 or dist_polyline(q, L["paths"]["grove"]) < 1.2:
			continue
		var kind3: String = ROCKS_SMALL[rng.randi() % 3] if rng.randf() < 0.55 else ROCKS_MID[rng.randi() % 3]
		put_rock(g, kind3, q.x, q.y, rng.randf_range(0.8, 1.2), true, n)
		n += 1
	# 西崖崖面（柵外）：沿崖線散置大小岩塊當露頭，打斷崖面（玩家到不了，不加碰撞）
	var fw: Array = L["fence_w"]
	for i in 16:
		var si := rng.randi_range(0, fw.size() - 2)
		var fa := v2(fw[si])
		var fb := v2(fw[si + 1])
		var fd := (fb - fa).normalized()
		var outw := Vector2(fd.y, -fd.x)
		var q4 := fa.lerp(fb, rng.randf()) + outw * rng.randf_range(2.2, 10.0)
		var kind4: String = ROCKS_BIG[rng.randi() % 2] if rng.randf() < 0.65 else ROCKS_MID[rng.randi() % 3]
		put_rock(g, kind4, q4.x, q4.y, rng.randf_range(1.5, 3.0), false, n)
		n += 1
	# 林床散石（南坡、東林、獸道旁）
	var tries := 0
	var placed := 0
	var plat := poly_of("platform")
	var play := poly_of("play")
	while placed < 26 and tries < 600:
		tries += 1
		var x5 := rng.randf_range(-70.0, 70.0)
		var z5 := rng.randf_range(-90.0, 100.0)
		var pl5 := Vector2(x5, z5)
		if Geometry2D.is_point_in_polygon(pl5, plat):
			continue
		if blocked(pl5, 1.2):
			continue
		var kind5: String = ROCKS_BIG[rng.randi() % 2] if rng.randf() < 0.3 else ROCKS_MID[rng.randi() % 3]
		put_rock(g, kind5, x5, z5, rng.randf_range(0.8, 1.4), Geometry2D.is_point_in_polygon(pl5, play), n)
		n += 1
		placed += 1
	stats["rocks"] = n


# ───────── 樹木 ─────────
func tree_h(nm: String) -> float:
	if not veg_info.has(nm):
		veg_info[nm] = JSON.parse_string(FileAccess.get_file_as_string(VEG_INFO + nm + ".json"))
	return float(veg_info[nm]["aabb_max"][1])


func tree_r(nm: String) -> float:
	tree_h(nm)
	return float(veg_info[nm]["trunk_r"])


func tree_crown(nm: String) -> float:
	tree_h(nm)
	return float(veg_info[nm]["crown_w"]) * 0.5


## 視線走廊：從前庭往南／西看，近距樹冠頂不得高於眼高（P+1.6）。回傳此處允許的最大樹頂高（世界 y）。
func max_top(x: float, z: float) -> float:
	var south := z > 9.0 and z < 120.0 and absf(x) < 55.0
	var west := x < -24.0 and z > -60.0 and z < 40.0
	if south or west:
		return P + 0.6
	return INF


const TALL := ["sugi_v3_b", "sugi_v3_a", "keyaki_v3_a", "konara_v3_b", "sugi_v3_c", "konara_v3_a", "sakura_yama_v3_c", "sakura_yama_v3_a", "sakura_yama_v3_b", "momiji_v3_a", "momiji_v3_b"]


func pick_species(zone: String, x: float, z: float, g: float) -> String:
	var cap := max_top(x, z) - g
	var pool: Array
	match zone:
		"grove":
			pool = ["sakura_yama_v3_a", "sakura_yama_v3_b", "sakura_yama_v3_c", "sakura_yama_v3_a", "sakura_yama_v3_b", "momiji_v3_a", "konara_v3_a"]
		"east":
			pool = ["sugi_v3_a", "sugi_v3_b", "sugi_v3_c", "sugi_v3_a", "konara_v3_a", "konara_v3_b", "keyaki_v3_a", "sakura_yama_v3_c"]
		"north":
			pool = ["sugi_v3_b", "sugi_v3_a", "konara_v3_b", "keyaki_v3_a", "sugi_v3_c"]
		"south":
			pool = ["sugi_v3_a", "sugi_v3_c", "konara_v3_a", "konara_v3_b", "sugi_v3_b", "keyaki_v3_a", "sakura_yama_v3_b"]
		"west":
			pool = ["konara_v3_a", "sugi_v3_c", "konara_v3_b", "sugi_v3_a"]
		_:
			pool = TALL
	var cand: String = pool[rng.randi() % pool.size()]
	if tree_h(cand) <= cap:
		return cand
	for nm in TALL:
		if tree_h(String(nm)) <= cap:
			return String(nm)
	return ""


func put_tree(g: Node, nm: String, x: float, z: float, idx: int, with_col: bool) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = load(VEG + nm + ".res")
	var s := rng.randf_range(0.9, 1.1)
	var y := S3.footprint_range(x, z, 0.3, 0.3, 0.0).x
	mi.transform = Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)), Vector3(x, y, z))
	mi.visibility_range_end = 600.0     # 近景區內的樹一律可見（鳥瞰／遠望時近景地面不會露出無樹的林床）
	mi.visibility_range_end_margin = 30.0
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add(g, mi, "%s_%03d" % [nm, idx])
	var tr := tree_r(nm) * s
	if with_col and tr > 0.06:
		var body := StaticBody3D.new()
		add(mi, body, "碰撞")
		var cs := CollisionShape3D.new()
		var cy := CylinderShape3D.new()
		cy.radius = tr * 1.15 / s
		cy.height = 3.2 / s
		cs.shape = cy
		cs.position = Vector3(0, 1.4 / s, 0)
		add(body, cs, "樹幹")


func _count_tree(counts: Dictionary, nm: String) -> int:
	var i := int(counts.get("_n", 0))
	counts["_n"] = i + 1
	counts[nm] = int(counts.get(nm, 0)) + 1
	return i


func scatter_trees(g: Node, zone: String, rect: Rect2, spacing: float, accept: Callable, n_max: int, counts: Dictionary, min_ny := 0.70) -> void:
	var cols := int(rect.size.x / spacing)
	var rows := int(rect.size.y / spacing)
	var play := poly_of("play")
	var plat := poly_of("platform")
	var cells := []
	for i in cols:
		for j in rows:
			cells.append(Vector2i(i, j))
	for i in range(cells.size() - 1, 0, -1):     # 決定性洗牌（rng 固定種子）
		var j := rng.randi_range(0, i)
		var tmp = cells[i]
		cells[i] = cells[j]
		cells[j] = tmp
	var n := 0
	for c in cells:
		if n >= n_max:
			break
		var x := rect.position.x + (float(c.x) + rng.randf_range(0.15, 0.85)) * spacing
		var z := rect.position.y + (float(c.y) + rng.randf_range(0.15, 0.85)) * spacing
		var p := Vector2(x, z)
		if Geometry2D.is_point_in_polygon(p, plat):
			continue
		if not accept.call(p):
			continue
		if S3.normal_at(x, z, 1.0).y < min_ny:
			continue
		var nm := pick_species(zone, x, z, gy(x, z))
		if nm == "":
			continue
		var cr := tree_crown(nm)
		if blocked(p, maxf(cr * 0.45, 1.2)):
			continue
		var in_play := Geometry2D.is_point_in_polygon(p, play)
		put_tree(g, nm, x, z, _count_tree(counts, nm), in_play or dist_to_poly(p, play) < 3.0)
		occupy(p, cr * 0.45)
		n += 1


func add_trees() -> void:
	var g := group(sroot, "樹木")
	var counts := {}
	# 境內特定位置（layout.py FIXED_TREES：御神木＝西北角老山櫻、手水舍與倉庫旁的野村楓、池畔山櫻、鳥居右側小楓）
	for f in L["fixed_trees"]:
		var nm0 := String(f[0])
		put_tree(g, nm0, float(f[1]), float(f[2]), _count_tree(counts, nm0), true)
		occupy(Vector2(float(f[1]), float(f[2])), tree_crown(nm0) * 0.45)
	scatter_trees(g, "grove", Rect2(-30, -84, 80, 54), 7.0, func(p: Vector2) -> bool: return p.y < -27.0 or p.x > 26.0, 70, counts)
	scatter_trees(g, "east", Rect2(27, -96, 51, 170), 7.0, func(p: Vector2) -> bool: return true, 140, counts)
	scatter_trees(g, "north", Rect2(-78, -96, 105, 14), 7.5, func(p: Vector2) -> bool: return true, 40, counts)
	scatter_trees(g, "south", Rect2(-78, 11, 156, 97), 6.5, func(p: Vector2) -> bool: return true, 190, counts)
	# 西坡（regional 西翼平均 ~46°、連續落 50 m 以上）：容許到 ~53° 的坡長樹，否則整片陡坡裸露成一道牆
	scatter_trees(g, "west", Rect2(-78, -82, 50, 93), 6.0, func(p: Vector2) -> bool: return p.x < -28.0, 110, counts, 0.60)
	# 崖松：西崖柵外（低矮框景）
	var pines := 0
	for i in 40:
		if pines >= 5:
			break
		var z := rng.randf_range(-30.0, 6.0)
		var x := -26.5 - rng.randf_range(0.5, 4.0)
		var p := Vector2(x, z)
		if blocked(p, 1.5):
			continue
		var nm := "akamatsu_v3_a" if rng.randf() < 0.5 else "akamatsu_v3_b"
		if gy(x, z) + tree_h(nm) > P + 1.2:
			continue
		put_tree(g, nm, x, z, _count_tree(counts, nm), false)
		occupy(p, 2.0)
		pines += 1
	stats["trees"] = counts


# ───────── 灌木（個別節點）、地被（執行期 MultiMesh） ─────────
func add_shrubs() -> void:
	var g := group(sroot, "下層植栽")
	var n := 0
	var plat := poly_of("platform")
	var tries := 0
	while n < 90 and tries < 3000:
		tries += 1
		var x := rng.randf_range(-60.0, 60.0)
		var z := rng.randf_range(-80.0, 100.0)
		var p := Vector2(x, z)
		if Geometry2D.is_point_in_polygon(p, plat):
			continue
		var d := dist_to_poly(p, plat)
		var edge := d > 0.8 and d < 6.0
		if not edge and rng.randf() > 0.25:
			continue
		if blocked(p, 0.9):
			continue
		if S3.normal_at(x, z, 0.6).y < 0.72:
			continue
		var nm := "tsutsuji_v3_a" if edge and rng.randf() < 0.55 else ("tsutsuji_v3_b" if edge else "shrub_v3_a")
		var mi := MeshInstance3D.new()
		mi.mesh = load(VEG + nm + ".res")
		var s := rng.randf_range(0.8, 1.2)
		mi.transform = Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)), Vector3(x, gy(x, z) - 0.05, z))
		mi.visibility_range_end = 200.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		add(g, mi, "%s_%03d" % [nm, n])
		occupy(p, 0.9 * s)
		n += 1
	stats["shrubs"] = n
	# 視線走廊（南坡、西崖下）：低灌木叢，樹冠頂不高過平台面（不擋前庭外望），讓草坡不至於光禿
	var nc := 0
	tries = 0
	while nc < 80 and tries < 4000:
		tries += 1
		var west := rng.randf() < 0.3
		var x2 := rng.randf_range(-40.0, -27.0) if west else rng.randf_range(-44.0, 44.0)
		var z2 := rng.randf_range(-55.0, 25.0) if west else rng.randf_range(11.5, 52.0)
		var p2 := Vector2(x2, z2)
		if Geometry2D.is_point_in_polygon(p2, plat):
			continue
		if blocked(p2, 0.8):
			continue
		if S3.normal_at(x2, z2, 0.6).y < 0.62:
			continue
		var nm2 := "tsutsuji_v3_a" if rng.randf() < 0.45 else ("tsutsuji_v3_b" if rng.randf() < 0.6 else "shrub_v3_a")
		var s2 := rng.randf_range(0.75, 1.15)
		var hgt := 2.1 if nm2 == "shrub_v3_a" else 1.6
		var g2 := gy(x2, z2)
		if g2 + hgt * s2 > P - 0.3:
			continue
		var mi2 := MeshInstance3D.new()
		mi2.mesh = load(VEG + nm2 + ".res")
		mi2.transform = Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s2, s2, s2)), Vector3(x2, g2 - 0.05, z2))
		mi2.visibility_range_end = 200.0
		mi2.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		add(g, mi2, "%s_c%03d" % [nm2, nc])
		occupy(p2, 0.9 * s2)
		nc += 1
	stats["shrubs_corridor"] = nc


## 石段兩側（美術深化 A）：成團、非對稱、三層（低：草／苔／落葉／小石；中：蕨、灌木、熊笹、蕗；高：小樹）。
## 西側（往獸道的陰側）比東側密；團與團之間留空；緊貼耳石有一條斷續的低植被遮住石段與坡面的交界。
## 小樹受視線走廊限高（樹冠頂 ≤ 平台 +0.6 m）：上段只有矮楓，下半段才有 6–10 m 的樹。
func add_stair_sides() -> void:
	var g := group(sroot, "石段兩側")
	var gt := group(g, "小樹")
	var gb := group(g, "灌木")
	var gr := group(g, "岩")
	var zf := float(L["z_foot"])
	var st := {"clusters": 0, "trees": 0, "shrubs": 0, "rocks": 0, "edge": 0}
	var plat := poly_of("platform")
	# 1) 緊貼耳石（|x| 1.8–2.5）：斷續的低植被，遮住石段與坡面交界（西側較連續）
	var z := 10.6
	while z < zf - 3.0:
		for sx in [-1.0, 1.0]:
			if rng.randf() < (0.75 if sx < 0.0 else 0.55):
				var x: float = sx * rng.randf_range(1.8, 2.5)
				var r := rng.randf()
				if r < 0.28:
					cov("矮草_a" if rng.randf() < 0.5 else "矮草_b", x, z, rng.randf_range(0.8, 1.2), 0.25, 0.12)
				elif r < 0.5:
					cov("蔭草", x, z, rng.randf_range(0.9, 1.3), 0.3, 0.12)
				elif r < 0.68:
					cov("蕨_小", x, z, rng.randf_range(0.7, 1.0), 0.35, 0.25)
				elif r < 0.84:
					cov("苔", x, z, rng.randf_range(0.5, 0.9), 1.0, 0.3, 0.0)
				else:
					cov("草本_b", x, z, rng.randf_range(0.8, 1.1), 0.2, 0.1)
				st["edge"] += 1
		z += rng.randf_range(0.3, 0.55)
	# 2) 小樹（先放，佔位優先；|x| 4–9.5 m，每側每 6–10 m 一棵、每棵最多試 4 個位置；樹種依此處允許樹高：上段只剩矮楓或不放）
	var counts := {}
	var play := poly_of("play")
	var cands := ["momiji_v3_b", "momiji_v3_a", "akamatsu_v3_b", "akamatsu_v3_a", "sakura_yama_v3_b", "sakura_yama_v3_a", "konara_v3_a"]
	for sx in [-1.0, 1.0]:
		var zt := 12.0 + rng.randf_range(0.0, 3.0)
		while zt < zf - 1.0:
			for attempt in 4:
				var x: float = sx * rng.randf_range(4.2, 9.5)
				var zz := zt + rng.randf_range(-1.2, 1.2)
				var p := Vector2(x, zz)
				var cap := max_top(x, zz) - gy(x, zz)
				var pick := ""
				var k0 := rng.randi() % cands.size()
				for j in cands.size():
					var c := String(cands[(k0 + j) % cands.size()])
					if tree_h(c) * 1.1 <= cap:
						pick = c
						break
				if pick != "" and not Geometry2D.is_point_in_polygon(p, plat) and not blocked(p, 1.0) and S3.normal_at(x, zz, 1.0).y > 0.6:
					put_tree(gt, pick, x, zz, _count_tree(counts, pick), Geometry2D.is_point_in_polygon(p, play) or dist_to_poly(p, play) < 3.0)
					occupy(p, maxf(tree_crown(pick) * 0.35, 1.0))
					st["trees"] += 1
					break
			zt += rng.randf_range(6.0, 10.0)
	st["tree_species"] = counts
	# 3) 團：內列（|x| 2.6–5.5，小、克制）＋外列（|x| 6–12，大、密：外圍包覆）；西側（陰側）團距短
	#    團型：0 蕨床／1 灌木團／2 草坡／3 熊笹／4 岩＋蕨／5 蕗＋闊葉草
	for row in [[2.6, 5.5, 0.9, 1.6, 3.5, 6.5], [6.0, 12.0, 2.4, 3.6, 3.5, 6.0]]:
		for sx in [-1.0, 1.0]:
			var zc := 11.0 + rng.randf_range(0.0, 2.5)
			while zc < zf - 2.0:
				var cx: float = sx * rng.randf_range(float(row[0]), float(row[1]))
				var cr := rng.randf_range(float(row[2]), float(row[3]))
				var kind := rng.randi() % 6
				if kind == 2 and rng.randf() < 0.5:
					kind = 0
				_stair_cluster(gb, gr, Vector2(cx, zc), cr, kind, st)
				st["clusters"] += 1
				var step := rng.randf_range(float(row[4]), float(row[5]))
				zc += step if sx < 0.0 else step * 1.35
	stats["stair_sides"] = st


## 波浪邊斜橢圓內的隨機點：lobe＝[相位1, 相位2, 長短軸比, 旋轉]；邊界半徑 r(θ)＝cr·(1＋0.3 sin 3θ＋0.18 sin 5θ)
func _lobe_pt(c: Vector2, cr: float, lobe: Array) -> Vector2:
	for k in 8:
		var a := rng.randf() * TAU
		var rb := cr * (1.0 + 0.3 * sin(3.0 * a + float(lobe[0])) + 0.18 * sin(5.0 * a + float(lobe[1])))
		var r := rb * sqrt(rng.randf())
		var v := Vector2(cos(a) * r * float(lobe[2]), sin(a) * r / float(lobe[2])).rotated(float(lobe[3]))
		if v.length() > 0.0 or k == 7:
			return c + v
	return c


## 一團植物（石段兩側用）：kind 0 蕨床、1 灌木團、2 草坡、3 熊笹、4 岩＋蕨、5 蕗＋闊葉草
## 審圖 r2：團的外形用「波浪邊的斜橢圓」（不是正圓），邊緣不齊，團與團之間留空
func _stair_cluster(gb: Node, gr: Node, c: Vector2, cr: float, kind: int, st: Dictionary) -> void:
	var n := int(cr * cr * 3.2) + 4
	var lobe := [rng.randf() * TAU, rng.randf() * TAU, rng.randf_range(1.0, 1.6), rng.randf() * PI]
	if kind == 1 or kind == 4:
		# 中心物件：灌木 1–3 叢或岩 1–2 顆
		var k := 1 + rng.randi() % (3 if kind == 1 else 2)
		for i in k:
			var a := rng.randf() * TAU
			var rr := rng.randf_range(0.0, cr * 0.5)
			var p := c + Vector2(cos(a), sin(a)) * rr
			if blocked(p, 0.5):
				continue
			if kind == 1:
				var nm: String = ["shrub_v3_a", "灌叢_a", "灌叢_b", "tsutsuji_v3_a", "灌叢_a", "shrub_v3_a"][rng.randi() % 6]
				if nm.begins_with("灌叢"):
					cov(nm, p.x, p.y, rng.randf_range(1.0, 1.5), 0.25, 0.4)
					occupy(p, 0.6)
					st["shrubs"] += 1
					continue
				var hgt := 2.1 if nm == "shrub_v3_a" else 1.6
				var s := rng.randf_range(0.7, 1.1)
				if gy(p.x, p.y) + hgt * s > max_top(p.x, p.y) + 0.4:
					s = maxf(0.5, (max_top(p.x, p.y) + 0.4 - gy(p.x, p.y)) / hgt)
				var mi := MeshInstance3D.new()
				mi.mesh = load(VEG + nm + ".res")
				mi.transform = Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(p.x, ground_min(p.x, p.y, 0.4 * s) - 0.06, p.y))
				mi.visibility_range_end = 200.0
				mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
				add(gb, mi, "%s_s%03d" % [nm, st["shrubs"]])
				occupy(p, 0.7 * s)
				st["shrubs"] += 1
			else:
				var kd: String = ROCKS_MID[rng.randi() % 3] if rng.randf() < 0.6 else ROCKS_SMALL[rng.randi() % 3]
				put_rock(gr, kd, p.x, p.y, rng.randf_range(0.8, 1.3), false, 700 + st["rocks"])
				rock_skirt(p, 0.45 if kd.begins_with("rock_mid") else 0.3)
				st["rocks"] += 1
	# 低層地毯（審圖 r1：團內只有幾株大葉植物＝「展示標本」）：蔭草／苔／落葉把團內的植物連起來
	for i in int(cr * cr * 1.8) + 2:
		var p3 := _lobe_pt(c, cr * 1.15, lobe)
		if absf(p3.x) < 1.8 or blocked(p3, 0.0):
			continue
		var t3 := rng.randf()
		if t3 < 0.45:
			cov("蔭草", p3.x, p3.y, rng.randf_range(0.9, 1.3), 0.3, 0.12)
		elif t3 < 0.7:
			cov("苔", p3.x, p3.y, rng.randf_range(0.6, 1.0), 1.0, 0.3, 0.0)
		elif t3 < 0.9:
			cov("落葉_a" if rng.randf() < 0.5 else "落葉_b", p3.x, p3.y, rng.randf_range(0.3, 0.45), 1.0, 0.4, 0.0)
		else:
			cov("矮草_a" if rng.randf() < 0.5 else "矮草_b", p3.x, p3.y, rng.randf_range(0.8, 1.2), 0.25, 0.12)
	for i in n:
		var p2 := _lobe_pt(c, cr, lobe)
		if absf(p2.x) < 1.8 or blocked(p2, 0.0):
			continue
		var r := rng.randf()
		match kind:
			0, 4:
				if r < 0.55:
					cov(["蕨_大a", "蕨_大c", "蕨_b"][rng.randi() % 3], p2.x, p2.y, rng.randf_range(0.75, 1.15), 0.35, 0.35)
				elif r < 0.75:
					cov("蔭草", p2.x, p2.y, rng.randf_range(0.9, 1.3), 0.3, 0.15)
				elif r < 0.9:
					cov("落葉_a" if rng.randf() < 0.5 else "落葉_b", p2.x, p2.y, rng.randf_range(0.25, 0.4), 1.0, 0.4, 0.0)
				else:
					cov("苔", p2.x, p2.y, rng.randf_range(0.6, 1.0), 1.0, 0.3, 0.0)
			1:
				if r < 0.35:
					cov("蕨_b", p2.x, p2.y, rng.randf_range(0.7, 1.0), 0.35, 0.35)
				elif r < 0.65:
					cov("高草_a" if rng.randf() < 0.5 else "高草_c", p2.x, p2.y, rng.randf_range(0.8, 1.1), 0.2, 0.15)
				elif r < 0.8:
					cov("草本_a", p2.x, p2.y, rng.randf_range(0.8, 1.1), 0.2, 0.15)
				else:
					cov("落葉_b", p2.x, p2.y, rng.randf_range(0.25, 0.4), 1.0, 0.4, 0.0)
			2:
				if r < 0.55:
					cov(["高草_a", "高草_c", "矮草_a", "矮草_b"][rng.randi() % 4], p2.x, p2.y, rng.randf_range(0.8, 1.2), 0.2, 0.15)
				elif r < 0.75:
					cov("莎草", p2.x, p2.y, rng.randf_range(0.8, 1.1), 0.2, 0.12)
				else:
					cov("草本_a" if rng.randf() < 0.6 else "草本_b", p2.x, p2.y, rng.randf_range(0.8, 1.15), 0.2, 0.12)
			3:
				if r < 0.75:
					cov("熊笹_a" if rng.randf() < 0.6 else "熊笹_b", p2.x, p2.y, rng.randf_range(0.8, 1.15), 0.25, 0.3)
				else:
					cov("蔭草", p2.x, p2.y, rng.randf_range(0.9, 1.3), 0.3, 0.15)
			5:
				# 蕗／闊葉草只當點綴，混在蔭草與小蕨裡（審圖 r1：單獨幾株＝展示標本）
				if r < 0.3:
					cov("蕗", p2.x, p2.y, rng.randf_range(0.8, 1.2), 0.3, 0.25)
				elif r < 0.42:
					cov("闊葉草", p2.x, p2.y, rng.randf_range(0.8, 1.1), 0.3, 0.25)
				elif r < 0.75:
					cov("蔭草", p2.x, p2.y, rng.randf_range(0.9, 1.3), 0.3, 0.15)
				else:
					cov("蕨_小", p2.x, p2.y, rng.randf_range(0.7, 1.0), 0.35, 0.25)


## 前庭與境內周邊（美術深化 D–G）：鳥居周邊、手水舍、倉庫與林緣、拜殿兩側與背後、西柵內側、燈籠／狛犬台座。
## 前庭中央與參道兩側 2.5 m 內不加（規格 §3：中央留 4–6 m 低遮擋帶；§6：中央草侵入 <10%）。
func add_court_dressing() -> void:
	var g := group(sroot, "境內周邊")
	var gb := group(g, "灌木")
	var gr := group(g, "岩")
	var st := {"spots": 0, "shrubs": 0, "rocks": 0}
	# 鳥居周邊（E）：左＝燈籠旁苔岩＋灌木＋蕨；右＝小楓（定點樹）樹下的岩與草。鳥居中間與階頂前保持淨空。
	_spot(gb, gr, Vector2(-5.6, 8.9), 1.6, ["rock_mid_b", "tsutsuji_v3_b"], ["蕨_b", "蔭草", "矮草_a", "苔"], 10, st)
	_spot(gb, gr, Vector2(-8.8, 7.6), 1.4, ["tsutsuji_v3_a"], ["高草_a", "草本_a", "矮草_b"], 8, st)
	_spot(gb, gr, Vector2(4.4, 9.5), 1.2, ["rock_small_a", "rock_mid_c"], ["蕨_小", "矮草_a", "楓落葉", "苔"], 9, st)
	_spot(gb, gr, Vector2(9.2, 8.6), 1.5, ["shrub_v3_a"], ["高草_c", "草本_a", "矮草_a"], 8, st)
	for sx in [-1.7, 1.7]:          # 鳥居石台腳：苔與蔭草
		for i in 4:
			var a := rng.randf() * TAU
			cov("苔" if i % 2 == 0 else "蔭草", sx + cos(a) * 0.62, 7.4 + sin(a) * 0.62, rng.randf_range(0.45, 0.7), 0.6, 0.15, 0.01)
	# 手水舍（F）：背側（西）一小團蕨與草本、石台邊零星短草、濕處苔
	var tp: Array = L["temizuya_pad"]
	_spot(gb, gr, Vector2(float(tp[0]) - 1.3, 0.2), 1.5, ["rock_small_b"], ["蕨_b", "蕨_小", "闊葉草", "蔭草"], 11, st)
	_spot(gb, gr, Vector2(float(tp[0]) - 0.9, 3.3), 1.1, [], ["蕗", "蔭草", "苔"], 7, st)
	for i in 10:
		var t := rng.randf()
		var px := lerpf(float(tp[0]), float(tp[1]), t)
		var pz := float(tp[2]) - rng.randf_range(0.38, 0.65) if i % 2 == 0 else float(tp[3]) + rng.randf_range(0.38, 0.65)
		if not blocked(Vector2(px, pz), 0.0):
			cov("矮草_b" if i % 3 else "苔", px, pz, rng.randf_range(0.6, 0.9), 0.4, 0.12)
	# 倉庫與林緣（G）：牆腳（屋簷滴水線外）草叢、背側（東）到林緣的蕨／灌木／熊笹過渡、北側陰濕
	var sh: Array = L["place"]["storehouse"]
	var shx := float(sh[0])
	var shz := float(sh[1])
	var sr := asset_rect("storehouse", shx, shz, float(sh[2]))       # 含屋簷：x 13.35–16.94、z −19.35～−15.45
	for i in 18:
		var side := i % 3
		var p := Vector2.ZERO
		var o := rng.randf_range(0.08, 0.45)
		match side:
			0: p = Vector2(sr.end.x + o, rng.randf_range(sr.position.y, sr.end.y))           # 背面（東）
			1: p = Vector2(rng.randf_range(sr.position.x + 0.6, sr.end.x), sr.end.y + o)     # 南側
			2: p = Vector2(rng.randf_range(sr.position.x + 0.3, sr.end.x), sr.position.y - o)  # 北側（木箱那側）
		if not blocked(p, 0.0):
			cov(["矮草_a", "蔭草", "高草_a", "草本_b", "蔭草"][rng.randi() % 5], p.x, p.y, rng.randf_range(0.7, 1.1), 0.2, 0.12)
	# 生活痕跡（內部資產 village_v2 humanuse_kit）：南牆東段一堆柴、旁邊一個木盆；簡化盒碰撞
	var props := group(g, "倉庫生活道具")
	_prop(props, "hu_makiwari", "柴堆", Vector2(16.05, sr.end.y + 0.68), 0.0)
	_prop(props, "hu_tarai", "木盆", Vector2(14.75, sr.end.y + 0.75), 0.5)
	for i in 6:
		var q := Vector2(rng.randf_range(14.3, 16.9), sr.end.y + rng.randf_range(1.35, 1.7))
		if not blocked(q, 0.0):
			cov("矮草_a" if i % 2 else "蔭草", q.x, q.y, rng.randf_range(0.7, 1.0), 0.2, 0.12)
	_spot(gb, gr, Vector2(sr.end.x + 2.3, shz + 1.0), 2.0, ["灌叢_a", "shrub_v3_a"], ["蕨_大a", "蕨_b", "熊笹_a", "蔭草"], 16, st)
	_spot(gb, gr, Vector2(sr.end.x + 2.6, sr.position.y - 1.4), 1.8, ["rock_mid_a", "灌叢_b"], ["熊笹_b", "蕨_大c", "蔭草", "落葉_b"], 14, st)
	_spot(gb, gr, Vector2(shx + 2.4, sr.end.y + 2.6), 1.5, ["灌叢_a"], ["高草_c", "草本_a", "蕨_小"], 9, st)
	# 拜殿兩側與背後（陰）：綠灌木＋蕨，不擋拜殿正面
	_spot(gb, gr, Vector2(-6.8, -21.5), 1.6, ["灌叢_b", "tsutsuji_v3_a"], ["蕨_b", "蔭草", "蕨_小"], 10, st)
	_spot(gb, gr, Vector2(7.0, -24.5), 1.7, ["shrub_v3_a", "rock_small_a"], ["蕨_大a", "蔭草", "闊葉草"], 11, st)
	_spot(gb, gr, Vector2(-3.5, -28.3), 1.8, ["灌叢_a"], ["蕨_大c", "蕗", "蔭草"], 11, st)
	_spot(gb, gr, Vector2(4.2, -28.6), 1.5, ["灌叢_b"], ["蕨_b", "熊笹_a", "苔"], 9, st)
	# 西柵內側（外望方向）：只放低矮的（< 0.8 m），柵內 1.2–2.0 m，保留越過木柵往西看的視線；避開崖邊視點
	for zc in [-27.0, -19.5, -13.8, -3.0, 4.0]:
		var zz: float = zc + rng.randf_range(-1.0, 1.0)
		var fx := fence_x(zz) + rng.randf_range(1.2, 2.0)
		_spot(gb, gr, Vector2(fx, zz), 1.1, ["rock_small_b"] if rng.randf() < 0.4 else [], ["矮草_a", "草本_b", "莎草", "苔"], 8, st)
	# 平台南緣（鳥居兩側往外）：低灌木＋草，非對稱
	for xc in [-15.5, -11.0, 12.5, 17.0]:
		_spot(gb, gr, Vector2(xc, 8.0 + rng.randf_range(-0.6, 0.8)), 1.5, ["tsutsuji_v3_b"] if rng.randf() < 0.6 else [], ["高草_a", "矮草_b", "草本_a"], 8, st)
	# 燈籠／狛犬台座腳：2–4 叢短草與苔（不圍成一圈）
	for key in L["place"]:
		if String(key).begins_with("lantern") or String(key).begins_with("komainu"):
			var lp: Array = L["place"][key]
			var k := 2 + rng.randi() % 3
			for i in k:
				# 偏在台座外側（遠離參道那側），不圍成一圈
				var a := rng.randf_range(-1.1, 1.1) + (PI if float(lp[0]) < 0.0 else 0.0)
				var rr := rng.randf_range(0.5, 0.75)
				var q := Vector2(float(lp[0]) + cos(a) * rr, float(lp[1]) + sin(a) * rr)
				if on_paving(q, 0.05):
					continue
				cov("苔" if i == 0 else ("矮草_b" if rng.randf() < 0.6 else "蔭草"), q.x, q.y, rng.randf_range(0.45, 0.7), 0.5, 0.1, 0.01)
	stats["court_dressing"] = st


## 內部資產道具（village_v2 humanuse_kit 的 mesh，只引用不改）：落地（腳印最低點）＋ AABB 盒碰撞
func _prop(parent: Node, mesh_name: String, nm: String, p: Vector2, yaw: float) -> MeshInstance3D:
	var mesh: Mesh = load("res://assets/village_v2/humanuse_kit/mesh/%s.res" % mesh_name)
	var ab := mesh.get_aabb()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var y := ground_min(p.x, p.y, maxf(ab.size.x, ab.size.z) * 0.4) - 0.02
	mi.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, y, p.y))
	mi.set_meta("internal_asset", "res://assets/village_v2/humanuse_kit/mesh/%s.res" % mesh_name)
	add(parent, mi, nm)
	var body := StaticBody3D.new()
	add(mi, body, "碰撞")
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = ab.size
	cs.shape = bx
	cs.position = ab.get_center()
	add(body, cs, "CollisionShape3D")
	occupy(p, maxf(ab.size.x, ab.size.z) * 0.55)
	return mi


## 一個小區塊：中心物件（灌木或岩，可空）＋周圍 n 株地被。中心名「灌叢_a／b」＝內部資產綠灌叢（地被圖層，無碰撞）
func _spot(gb: Node, gr: Node, c: Vector2, cr: float, centers: Array, covers: Array, n: int, st: Dictionary) -> void:
	for nm in centers:
		var a := rng.randf() * TAU
		var p := c + Vector2(cos(a), sin(a)) * rng.randf_range(0.0, cr * 0.35)
		if blocked(p, 0.45):
			continue
		var s_nm := String(nm)
		if s_nm.begins_with("rock_"):
			put_rock(gr, s_nm, p.x, p.y, rng.randf_range(0.8, 1.15), s_nm.begins_with("rock_mid"), 800 + st["rocks"])
			rock_skirt(p, 0.45 if s_nm.begins_with("rock_mid") else 0.3)
			st["rocks"] += 1
		elif s_nm.begins_with("灌叢"):
			cov(s_nm, p.x, p.y, rng.randf_range(1.0, 1.45), 0.2, 0.4)
			occupy(p, 0.6)
			st["shrubs"] += 1
		else:
			var s := rng.randf_range(0.7, 1.0)
			var mi := MeshInstance3D.new()
			mi.mesh = load(VEG + s_nm + ".res")
			mi.transform = Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(p.x, ground_min(p.x, p.y, 0.4 * s) - 0.06, p.y))
			mi.visibility_range_end = 200.0
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			add(gb, mi, "%s_c%03d" % [s_nm, st["shrubs"]])
			occupy(p, 0.7 * s)
			st["shrubs"] += 1
	for i in n:
		var a2 := rng.randf() * TAU
		var p2 := c + Vector2(cos(a2), sin(a2)) * cr * sqrt(rng.randf())
		if blocked(p2, 0.0) or on_paving(p2, 0.3):
			continue
		var lay := String(covers[rng.randi() % covers.size()])
		var flat := lay in ["苔", "落葉_a", "落葉_b", "楓落葉", "細枝"]
		cov(lay, p2.x, p2.y, rng.randf_range(0.3, 0.45) if lay.begins_with("落葉") or lay == "楓落葉" else rng.randf_range(0.75, 1.15), 1.0 if flat else 0.25, 0.3 if flat else 0.2, 0.0 if flat else 0.02)
	st["spots"] += 1


## 岩腳一圈低植被（審圖 r1：裸岩像「擺上去的道具」）：苔、蔭草、小蕨 3–5 株，偏在上坡側與陰側
func rock_skirt(p: Vector2, r: float) -> void:
	var k := 3 + rng.randi() % 3
	var a0 := rng.randf() * TAU
	for i in k:
		var a := a0 + float(i) * TAU / float(k) + rng.randf_range(-0.4, 0.4)
		var q := p + Vector2(cos(a), sin(a)) * r * rng.randf_range(0.85, 1.25)
		if on_paving(q, 0.2):
			continue
		var t := rng.randf()
		if t < 0.4:
			cov("苔", q.x, q.y, rng.randf_range(0.45, 0.75), 1.0, 0.3, 0.0)
		elif t < 0.75:
			cov("蔭草", q.x, q.y, rng.randf_range(0.8, 1.2), 0.3, 0.12)
		else:
			cov("蕨_小", q.x, q.y, rng.randf_range(0.6, 0.9), 0.35, 0.25)


func blocked_cover(p: Vector2, sd: Dictionary) -> bool:
	# 參道（可變寬，含拜殿前台）與手水舍石台：鋪面外 0.25 m 內不長（碎石帶），再往外交給遮罩
	if on_paving(p, 0.25):
		return true
	if absf(p.x) < 2.0 and p.y > 8.5 and p.y < float(L["z_foot"]) + 1.0:
		return true
	if in_pond(p, 1.06):
		return true
	if p.x > -4.4 and p.x < 4.4 and p.y > -26.5 and p.y < -17.6:
		return true
	for key in ["to_store", "grove", "pond_w", "to_temizuya"]:
		if dist_polyline(p, L["paths"][key]) < 0.55:
			return true
	for o in occupied:
		var r := float(o[1])
		# 建築／道具／岩石：外緣再留 0.35 m；大樹冠只清樹幹周圍
		var lim := r + 0.35 if r <= 3.0 else r * 0.85
		if p.distance_to(o[0]) < lim:
			return true
	return false


func add_ground_cover() -> void:
	var node := Node3D.new()
	node.set_script(load("res://maps/shrine_v3/s3_scatter.gd"))
	add(sroot, node, "地被")
	var grass := PackedFloat32Array()
	var ferns := PackedFloat32Array()
	var plat := poly_of("platform")
	var sd: Dictionary = L["sando"]
	var n_weed := 0
	var n_litter := 0
	var n_leaf := 0
	var x := -77.0
	while x < 77.0:
		var z := -95.0
		while z < 107.0:
			var px := x + rng.randf_range(0.0, 0.9)
			var pz := z + rng.randf_range(0.0, 0.9)
			var p := Vector2(px, pz)
			var ma := mask(mask_a, px, pz)
			var mb := mask(mask_b, px, pz)
			var mc := mask(mask_c, px, pz)
			var ny := S3.normal_at(px, pz, 0.4).y
			if not blocked_cover(p, sd):
				var on_plat := Geometry2D.is_point_in_polygon(p, plat)
				# 美術深化：踩踏量（mask_c.r）高的地方草少（參道兩側、拜殿前、手水舍前、往倉庫的路）
				var gw := ma.a * (1.0 - ma.r) * (1.0 - mb.r) * (1.0 - 0.75 * mc.r)
				if ny > 0.80 and gw > 0.45 and rng.randf() < gw * 0.85:
					grass.append_array([px, gy(px, pz), pz, rng.randf() * TAU, rng.randf_range(0.75, 1.25)])
				elif ny > 0.80 and ma.g > 0.5 and rng.randf() < 0.06 * ma.g and not on_plat:
					ferns.append_array([px, gy(px, pz) - 0.03, pz, rng.randf() * TAU, rng.randf_range(0.8, 1.3)])
				elif on_plat and gw > 0.12 and mc.r < 0.4 and rng.randf() < 0.05 + 0.25 * gw:
					# 前庭零星雜草／苔斑：夯土與草地的交界、少踩踏處（跟著遮罩的過渡帶走，不是均勻撒）
					if mb.a > 0.3 and rng.randf() < 0.35:
						cov("苔", px, pz, rng.randf_range(0.5, 0.9), 1.0, 0.3, 0.0)
					else:
						cov(["矮草_a", "矮草_b", "草本_b", "莎草", "蔭草"][rng.randi() % 5], px, pz, rng.randf_range(0.6, 1.0), 0.3, 0.1)
					n_weed += 1
				elif not on_plat and ma.g > 0.45 and ny > 0.5 and rng.randf() < 0.03 * ma.g:
					# 林床：落葉堆、細枝、苔（貼坡）
					var r := rng.randf()
					var lay := "落葉_a" if r < 0.4 else ("落葉_b" if r < 0.7 else ("細枝" if r < 0.85 else "苔"))
					cov(lay, px, pz, rng.randf_range(0.35, 0.6) if lay.begins_with("落葉") else rng.randf_range(0.5, 0.9), 1.0, 0.4, 0.0)
					n_litter += 1
				# 楓落葉：楓樹下（mask_c.g；遮罩已扣掉踩踏處）
				if mc.g > 0.35 and rng.randf() < 0.22 * mc.g:
					cov("楓落葉", px, pz, rng.randf_range(0.18, 0.32), 1.0, 0.3, 0.0)
					n_leaf += 1
			z += 0.9
		x += 0.9
	var layers := []
	var cnt := grass.size() / 5
	for v in 3:
		var sub := PackedFloat32Array()
		for i in range(v, cnt, 3):
			sub.append_array(grass.slice(i * 5, i * 5 + 5))
		layers.append({"name": "草叢%d" % v, "mesh": VEG + "grass_clump_v3_%s.res" % "abc"[v], "vis_end": 40.0, "pts": sub})
	var fa := PackedFloat32Array()
	var fb := PackedFloat32Array()
	var cntf := ferns.size() / 5
	for i in cntf:
		if i % 2 == 0:
			fa.append_array(ferns.slice(i * 5, i * 5 + 5))
		else:
			fb.append_array(ferns.slice(i * 5, i * 5 + 5))
	layers.append({"name": "蕨a", "mesh": VEG + "fern_v3_a.res", "vis_end": 60.0, "pts": fa})
	layers.append({"name": "蕨b", "mesh": VEG + "fern_v3_b.res", "vis_end": 60.0, "pts": fb})
	# 內部資產地被（獸道 S01 套件，樹以外）：stride 7（含地面法線，落葉／苔貼坡）
	var n_int := 0
	for nm in cover:
		var cfg: Dictionary = COVER[nm]
		var arr: Array = cover[nm]
		var lay2 := {"name": String(nm), "mesh": INT + String(cfg["mesh"]) + ".res", "vis_end": float(cfg["vis_end"]),
			"shadow": bool(cfg.get("shadow", false)), "stride": 7, "pts": PackedFloat32Array(arr)}
		if bool(cfg.get("lod", false)):
			lay2["lod1"] = INT + String(cfg["mesh"]) + "_lod1.res"
			lay2["lod_sw"] = 18.0
		if cfg.has("color"):
			lay2["color"] = cfg["color"]
			lay2["color_var"] = float(cfg.get("color_var", 0.0))
		layers.append(lay2)
		cover_n[nm] = arr.size() / 7
		n_int += arr.size() / 7
	node.set_meta("layers", layers)
	stats["grass"] = cnt
	stats["ferns"] = cntf
	stats["cover_internal"] = {"total": n_int, "weeds_court": n_weed, "litter_forest": n_litter, "maple_leaves": n_leaf, "by_layer": cover_n}


# ───────── 互動、標記 ─────────
func _area(parent: Node, nm: String, pos: Vector3, size: Vector3, props: Dictionary) -> Area3D:
	var a := Area3D.new()
	a.set_script(load("res://components/interaction/world_interaction.gd"))
	a.collision_layer = 0
	a.collision_mask = 1
	for k in props:
		a.set(k, props[k])
	add(parent, a, nm)
	a.position = pos
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = size
	cs.shape = bx
	add(a, cs, "CollisionShape3D")
	return a


func add_interactions() -> void:
	var g := group(sroot, "神社互動點")
	var zf := float(L["z_foot"])
	var yf := float(L["y_foot"])
	_area(g, "參道抵達", Vector3(0.0, yf + 1.0, zf - 3.0), Vector3(16, 8, 12), {
		"interaction_id": "hakurei_shrine_approach", "interaction_label": "",
		"quest_event_type": "REACH", "quest_target_id": "hakurei_shrine_approach"})
	_area(g, "拜殿拜訪", Vector3(0.0, P + 1.2, -16.8), Vector3(8, 4, 5), {
		"interaction_id": "hakurei_shrine_visit", "interaction_label": "拜訪", "place_name": "博麗神社",
		"dialogue_id": "reimu_hakurei_shrine", "require_quest": "MQ04"})
	# 陰陽玉彩蛋：只在玉旁 ~1 m 內出現提示（規格 §25：不要求第一次通過就發現）；可重看，第一次看過立 found_onmyoudama
	var eg: Array = L["place"]["onmyoudama"]
	var ex := float(eg[0])
	var ez := float(eg[1])
	# 玉在倉庫北牆外、木箱東側：玩家只能從北／東靠近 → 互動區往北偏 0.6 m
	_area(g, "陰陽玉", Vector3(ex + 0.1, gy(ex, ez) + 1.0, ez - 0.6), Vector3(2.2, 2.4, 2.4), {
		"interaction_id": "shrine_onmyoudama", "interaction_label": "調查",
		"dialogue_id": "yoriichi_onmyoudama"})
	stats["egg"] = {"pos": [ex, snappedf(gy(ex, ez), 0.001), ez], "in_play": Geometry2D.is_point_in_polygon(Vector2(ex, ez), poly_of("play")),
		"in_platform": Geometry2D.is_point_in_polygon(Vector2(ex, ez), poly_of("platform"))}


func add_markers() -> void:
	var g := group(sroot, "標記")
	var pt: Array = L["portal"]
	var m2 := Marker3D.new()
	m2.position = Vector3(float(pt[0]), gy(float(pt[0]), float(pt[1])), float(pt[1]))
	m2.set_meta("portal", "trail")
	add(g, m2, "傳送點_南_獸道")
	for k in L["viewpoints"]:
		var vp: Array = L["viewpoints"][k]
		var m := Marker3D.new()
		m.position = Vector3(float(vp[0]), gy(float(vp[0]), float(vp[1])) + 1.6, float(vp[1]))
		add(g, m, "視點_" + String(k))


# ───────── 導航 ─────────
func _to_root(n: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var c: Node = n
	while c != null and c != sroot:
		if c is Node3D:
			t = (c as Node3D).transform * t
		c = c.get_parent()
	return t


func _shape_aabb(s: Shape3D) -> AABB:
	if s is BoxShape3D:
		var e := (s as BoxShape3D).size
		return AABB(-e * 0.5, e)
	if s is CylinderShape3D:
		var cy := s as CylinderShape3D
		return AABB(Vector3(-cy.radius, -cy.height * 0.5, -cy.radius), Vector3(cy.radius * 2, cy.height, cy.radius * 2))
	if s is ConvexPolygonShape3D:
		var pts := (s as ConvexPolygonShape3D).points
		var lo := Vector3(INF, INF, INF)
		var hi := -lo
		for p in pts:
			lo = lo.min(p)
			hi = hi.max(p)
		return AABB(lo, hi - lo)
	return AABB()


func add_navigation() -> void:
	var geo := NavigationMeshSourceGeometryData3D.new()
	var terr := sroot.get_node("地形/近景地形") as MeshInstance3D
	geo.add_mesh(terr.mesh, Transform3D.IDENTITY)
	var stairs := sroot.get_node("參道石段/石段") as MeshInstance3D
	geo.add_mesh(stairs.mesh, Transform3D.IDENTITY)
	var n_obs := 0
	for grp in ["建築", "境內物件", "樹木", "岩石"]:
		var gn := sroot.get_node_or_null(grp)
		if gn == null:
			continue
		for cs_n in gn.find_children("*", "CollisionShape3D", true, false):
			var cs := cs_n as CollisionShape3D
			if cs.shape == null or cs.disabled:
				continue
			var lb := _shape_aabb(cs.shape)
			if lb.size == Vector3.ZERO:
				continue
			var xf := _to_root(cs)
			var lo := Vector3(1.0e9, 1.0e9, 1.0e9)
			var hi := Vector3(-1.0e9, -1.0e9, -1.0e9)
			for ix in 2:
				for iy in 2:
					for iz in 2:
						var c := xf * (lb.position + lb.size * Vector3(ix, iy, iz))
						lo = lo.min(c)
						hi = hi.max(c)
			if hi.x - lo.x > 40.0 or hi.z - lo.z > 40.0:
				continue
			var cxm := (lo.x + hi.x) * 0.5
			var czm := (lo.z + hi.z) * 0.5
			var hxm := maxf((hi.x - lo.x) * 0.5, 0.25)
			var hzm := maxf((hi.z - lo.z) * 0.5, 0.25)
			var poly := PackedVector3Array([
				Vector3(cxm - hxm, lo.y, czm - hzm), Vector3(cxm + hxm, lo.y, czm - hzm), Vector3(cxm + hxm, lo.y, czm + hzm), Vector3(cxm - hxm, lo.y, czm + hzm)])
			geo.add_projected_obstruction(poly, lo.y - 1.2, maxf(hi.y - lo.y, 0.5) + 1.2, false)
			n_obs += 1
	var pc: Dictionary = L["pond"]
	var ring := PackedVector3Array()
	for i in 48:
		var q := pond_ring(1.0, i, 48)
		ring.append(Vector3(q.x, float(pc["level"]) - 2.0, q.y))
	geo.add_projected_obstruction(ring, float(pc["level"]) - 2.0, 2.6, false)
	n_obs += 1
	var nm := NavigationMesh.new()
	nm.cell_size = 0.25
	nm.cell_height = 0.1
	nm.agent_height = 1.8
	nm.agent_radius = 0.8
	nm.agent_max_climb = 0.3
	nm.agent_max_slope = 30.0
	nm.region_min_size = 4.0
	nm.edge_max_error = 1.0
	var pv := poly_of("play")
	var lo2 := Vector2(INF, INF)
	var hi2 := -lo2
	for p in pv:
		lo2 = lo2.min(p)
		hi2 = hi2.max(p)
	nm.filter_baking_aabb = AABB(Vector3(lo2.x, -10.0, lo2.y), Vector3(hi2.x - lo2.x, 80.0, hi2.y - lo2.y))
	NavigationServer3D.bake_from_source_geometry_data(nm, geo)
	var e := S3.save_retry(nm, GEN + "navmesh.res")
	var reg := NavigationRegion3D.new()
	reg.navigation_mesh = load(GEN + "navmesh.res")
	add(sroot, reg, "導航")
	stats["nav"] = {"save_err": e, "polys": nm.get_polygon_count(), "verts": nm.get_vertices().size(), "obstacles": n_obs}


## 候選圖的 meta（main.gd 用 --map=shrine_v3 載入時讀）：只寫新檔 data/shrine_v3.meta.json，不動正式 shrine。
func write_meta() -> void:
	var pt: Array = L["portal"]
	var px := float(pt[0])
	var pz := float(pt[1])
	# main._arrival_for_portal：落點＝傳送點往原點方向內縮 4 m
	var inward := Vector2(-px, -pz).normalized() * 4.0
	var ax := px + inward.x
	var az := pz + inward.y
	# 面向石段腳（玩家 yaw 慣例：atan2(-dx, -dz)）
	var d := Vector2(0.0, float(L["z_foot"])) - Vector2(ax, az)
	var pv := poly_of("play")
	var lo := Vector2(INF, INF)
	var hi := -lo
	for p in pv:
		lo = lo.min(p)
		hi = hi.max(p)
	var meta := {
		"_note": "博麗神社 v3 全面重製（候選場景，--map=shrine_v3）。由 tools/shrine_v3/build_scene.gd 寫出，勿手改。",
		"id": "shrine_v3",
		"connections": ["trail"],
		"safe": true,
		"mobTheme": null,
		"playSize": [snappedf(hi.x - lo.x, 0.1), snappedf(hi.y - lo.y, 0.1)],
		"colliders": [],
		"portals": [{
			"_note": "南端獸道口 → 獸道。y＝傳送點地面高；arrival_ground_y＝內縮 4 m 落點的地面高。",
			"target": "trail", "x": px, "y": snappedf(gy(px, pz), 0.001), "z": pz,
			"arrival_ground_y": snappedf(gy(ax, az), 0.001), "arrival_y_offset": 1.2,
			"arrival_yaw": snappedf(atan2(-d.x, -d.y), 0.001)}],
	}
	var f := FileAccess.open("res://data/shrine_v3.meta.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(meta, "  ") + "\n")
	f.close()
	stats["meta"] = meta["portals"][0]


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	rng.seed = 20261022
	L = S3.load_layout()
	P = float(L["P"])
	S3.load_height()
	mask_a = (load(GEN + "mask_a.res") as Texture2D).get_image()
	mask_b = (load(GEN + "mask_b.res") as Texture2D).get_image()
	mask_c = (load(GEN + "mask_c.res") as Texture2D).get_image()
	for im in [mask_a, mask_b, mask_c]:
		if (im as Image).is_compressed():
			(im as Image).decompress()
	sroot = Node3D.new()
	sroot.name = "博麗神社"
	sroot.set_meta("own_colliders", true)
	sroot.set_meta("shrine_v3", true)
	# 每一段用自己的種子（美術深化起）：改一區不會把其他區的隨機配置整個洗掉
	var steps := [["terrain", add_terrain], ["sky", add_sky], ["boundary", add_boundary], ["architecture", add_architecture],
		["site", add_site], ["pond", add_pond], ["rocks", add_rocks], ["trees", add_trees], ["shrubs", add_shrubs],
		["stair_sides", add_stair_sides], ["court_dressing", add_court_dressing], ["ground_cover", add_ground_cover],
		["interactions", add_interactions], ["markers", add_markers], ["navigation", add_navigation], ["meta", write_meta]]
	for s in steps:
		rng.seed = 20261022 + hash(String(s[0]))
		(s[1] as Callable).call()
	var pk := PackedScene.new()
	var e := pk.pack(sroot)
	var e2 := S3.save_retry(pk, OUT)
	print("[BUILD] pack=%d save=%d nodes=%d -> %s" % [e, e2, _count(sroot), OUT])
	for k in stats:
		print("[BUILD] %s = %s" % [k, stats[k]])
	quit()


func _count(n: Node) -> int:
	var c := 1
	for k in n.get_children():
		c += _count(k)
	return c

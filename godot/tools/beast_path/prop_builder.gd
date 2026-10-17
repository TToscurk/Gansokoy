extends RefCounted
## 獸道 道具建造器（V0.1 白模）：layout.pois 的每一筆 → 帶碰撞的 Node3D（以基本幾何擺出可辨識外形與正確尺寸）。
## 這些是「白模代理」，不是最終美術；每個節點都帶 meta：bp_id / bp_kind / bp_spec（對應規格書資產 ID，之後換 Blender 資產時用）。
## 約定：節點本地 −Z＝正面／行進方向、+X＝右；root.position＝世界座標（場景根在原點）。

const BPLib := preload("res://tools/beast_path/bp_lib.gd")
const RockBuilder := preload("res://tools/beast_path/rock_builder.gd")
const ROCK_MAT_PATH := "res://assets/beast_path/materials/bp_rock.tres"
const ROCK_MESH_DIR := "res://maps/beast_path/gen/rocks/"

var lib: BPLib
var footprints: Array = []          # [{id, p: Vector2, r: float}]  供森林避讓
var anchors: Dictionary = {}        # id → {p: Vector3, h: float}  供注連繩等取端點
var face_boxes: Array = []          # V1.3：崖面岩塊的世界 AABB（森林凍結區剔除撞到的樹；verify 檢查不壓瀑布）
var _mats := {}
var _meshes := {}
var _shapes := {}
var _rock_cache := {}
var _rng := RandomNumberGenerator.new()
var _noise := FastNoiseLite.new()

const COL_WOOD := Color(0.40, 0.29, 0.18)
const COL_WOOD_DARK := Color(0.26, 0.18, 0.12)
const COL_WOOD_OLD := Color(0.33, 0.30, 0.26)
const COL_STONE := Color(0.54, 0.53, 0.50)
const COL_STONE_MOSS := Color(0.32, 0.42, 0.28)
const COL_RED := Color(0.72, 0.10, 0.07)
const COL_RED_OLD := Color(0.46, 0.18, 0.13)
const COL_BLACK := Color(0.11, 0.10, 0.10)
const COL_ROOF := Color(0.20, 0.18, 0.17)
const COL_STRAW := Color(0.70, 0.58, 0.30)
const COL_PAPER := Color(0.93, 0.92, 0.88)


func setup(lib_: BPLib) -> void:
	lib = lib_
	_noise.seed = 4242
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 1.0


# ---------------------------------------------------------------- 基本積木
func mat(col: Color, rough: float = 0.92, alpha: float = 1.0) -> StandardMaterial3D:
	var key := "%.3f,%.3f,%.3f,%.3f,%.2f" % [col.r, col.g, col.b, alpha, rough]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(col.r, col.g, col.b, alpha)
	m.roughness = rough
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.resource_name = "BP_" + key
	_mats[key] = m
	return m


func _box_mesh(size: Vector3) -> BoxMesh:
	var key := "b%.3f,%.3f,%.3f" % [size.x, size.y, size.z]
	if not _meshes.has(key):
		var bm := BoxMesh.new()
		bm.size = size
		_meshes[key] = bm
	return _meshes[key]


func _cyl_mesh(r0: float, r1: float, h: float, seg: int = 12) -> CylinderMesh:
	var key := "c%.3f,%.3f,%.3f,%d" % [r0, r1, h, seg]
	if not _meshes.has(key):
		var cm := CylinderMesh.new()
		cm.top_radius = r1
		cm.bottom_radius = r0
		cm.height = h
		cm.radial_segments = seg
		cm.rings = 1
		_meshes[key] = cm
	return _meshes[key]


func _sph_mesh(r: float, sy: float = 1.0) -> SphereMesh:
	var key := "s%.3f,%.3f" % [r, sy]
	if not _meshes.has(key):
		var sm := SphereMesh.new()
		sm.radius = r
		sm.height = r * 2.0 * sy
		sm.radial_segments = 10
		sm.rings = 5
		_meshes[key] = sm
	return _meshes[key]


func mi(parent: Node, mesh: Mesh, col: Color, pos: Vector3 = Vector3.ZERO, rot_deg: Vector3 = Vector3.ZERO, rough: float = 0.92, alpha: float = 1.0) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat(col, rough, alpha)
	m.position = pos
	m.rotation_degrees = rot_deg
	parent.add_child(m)
	return m


func box(parent: Node, size: Vector3, pos: Vector3, col: Color, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	return mi(parent, _box_mesh(size), col, pos, rot_deg)


func cyl(parent: Node, r: float, h: float, pos: Vector3, col: Color, rot_deg: Vector3 = Vector3.ZERO, r_top: float = -1.0) -> MeshInstance3D:
	return mi(parent, _cyl_mesh(r, r if r_top < 0.0 else r_top, h), col, pos, rot_deg)


## 兩點之間的方梁（柵欄橫木、注連繩節）。thick＝(寬, 高)，長度沿 a→b
func beam(parent: Node, a: Vector3, b: Vector3, thick: Vector2, col: Color) -> MeshInstance3D:
	var len := a.distance_to(b)
	var m := MeshInstance3D.new()
	m.mesh = _box_mesh(Vector3(thick.x, thick.y, len))
	m.material_override = mat(col)
	var up := Vector3.UP if absf((b - a).normalized().y) < 0.95 else Vector3.RIGHT
	m.transform = Transform3D(Basis.looking_at((b - a).normalized(), up), (a + b) * 0.5)
	parent.add_child(m)
	return m


func body(parent: Node, nm: String = "Col") -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.name = nm
	parent.add_child(sb)
	return sb


func col_box(sb: StaticBody3D, size: Vector3, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO) -> void:
	var key := "bx%.3f,%.3f,%.3f" % [size.x, size.y, size.z]
	if not _shapes.has(key):
		var bs := BoxShape3D.new()
		bs.size = size
		_shapes[key] = bs
	var cs := CollisionShape3D.new()
	cs.shape = _shapes[key]
	cs.position = pos
	cs.rotation_degrees = rot_deg
	sb.add_child(cs)


func col_cyl(sb: StaticBody3D, r: float, h: float, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO) -> void:
	var key := "cy%.3f,%.3f" % [r, h]
	if not _shapes.has(key):
		var c := CylinderShape3D.new()
		c.radius = r
		c.height = h
		_shapes[key] = c
	var cs := CollisionShape3D.new()
	cs.shape = _shapes[key]
	cs.position = pos
	cs.rotation_degrees = rot_deg
	sb.add_child(cs)


func _fp(id: String, p: Vector2, r: float) -> void:
	footprints.append({"id": id, "p": p, "r": r})


func _g(p: Vector2) -> float:
	return lib.h_at(p.x, p.y)


## V1.3：崖面岩塊用的「地面」——遠在下方，RockBuilder 就不畫貼地 AO 暗邊與腳邊泥土
func _g_far(_p: Vector2) -> float:
	return -10000.0


func _root(poi: Dictionary, p: Vector2, yaw: float, y_off: float = 0.0) -> Node3D:
	var r := Node3D.new()
	r.name = String(poi["id"])
	r.position = Vector3(p.x, _g(p) + y_off, p.y)
	r.rotation.y = yaw
	r.set_meta("bp_id", String(poi["id"]))
	r.set_meta("bp_kind", String(poi.get("kind", "")))
	r.set_meta("bp_spec", String(poi.get("spec", "")))
	return r


func _world_root(poi: Dictionary) -> Node3D:
	var r := Node3D.new()
	r.name = String(poi["id"])
	r.set_meta("bp_id", String(poi["id"]))
	r.set_meta("bp_kind", String(poi.get("kind", "")))
	r.set_meta("bp_spec", String(poi.get("spec", "")))
	return r


## 面向最近的主路中心線（本地 −Z 朝向路）
func yaw_face_path(p: Vector2) -> float:
	var q := lib.main.q(p)
	var d: Vector2 = (q["pos"] as Vector2) - p
	if d.length() < 0.01:
		return 0.0
	return BPLib.yaw_of(d.normalized())


# ---------------------------------------------------------------- 崖岩片（BOSS 場環形岩壁／瀑布兩翼）
## V1.1：改用 rock_builder.gd 的自然岩石（圓角方盒→層理／脊線／起伏位移→平滑法線）＋ bp_rock.gdshader（三平面 PBR 岩層）。
## V0.1 的「6×6 細分方盒＋平面著色」已退役。約定：本地 X＝寬（沿弧切線）、Y＝高（底部埋入地下）、Z＝厚。
var _rock_mat: ShaderMaterial = null
var rock_stats := {"meshes": 0, "tris": 0, "bad": 0}


func rock_material() -> ShaderMaterial:
	if _rock_mat == null:
		_rock_mat = ResourceLoader.load(ROCK_MAT_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as ShaderMaterial
	return _rock_mat


## 網格存成外部 .res（不塞進 .tscn），回傳磁碟上的那份
func _save_rock_mesh(mesh: ArrayMesh, nm: String) -> ArrayMesh:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROCK_MESH_DIR))
	mesh.surface_set_material(0, rock_material())
	mesh.resource_name = nm
	var path := ROCK_MESH_DIR + nm + ".res"
	var e := ResourceSaver.save(mesh, path)
	if e != OK:
		push_error("存 %s 失敗：%s" % [path, error_string(e)])
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as ArrayMesh


func _tally(rb: Dictionary) -> void:
	rock_stats["meshes"] += 1
	rock_stats["tris"] += int(rb["ntri"])
	rock_stats["bad"] += int(rb["bad"])


const ROCK_VIS_END := 190.0            # 超過這個距離就不畫（S02／S03 視野看得到的遠處 S04 岩石不必付 156k 三角形）
const ROCK_VIS_MARGIN := 30.0


func _add_rock_body(root: Node3D, mesh: ArrayMesh, pts: PackedVector3Array, collide: bool, shadow: bool = true) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.visibility_range_end = ROCK_VIS_END
	mi.visibility_range_end_margin = ROCK_VIS_MARGIN
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	if collide:
		var sb := body(root)
		var shape := ConvexPolygonShape3D.new()
		shape.points = pts
		var cs := CollisionShape3D.new()
		cs.shape = shape
		sb.add_child(cs)


func make_slab(parent: Node3D, id: String, p: Vector2, w: float, h: float, d: float, yaw: float, moss: float, form: String = "slab") -> Node3D:
	var sd := absi(id.hash())
	var rng := RandomNumberGenerator.new()
	rng.seed = sd
	var ax := Vector2(cos(yaw), -sin(yaw))
	var az := Vector2(sin(yaw), cos(yaw))
	var gmin := 1e9
	var gmax := -1e9
	for ox: float in [-0.5, 0.0, 0.5]:
		for oz: float in [-0.5, 0.0, 0.5]:
			var g := _g(p + ax * (ox * w) + az * (oz * d))
			gmin = minf(gmin, g)
			gmax = maxf(gmax, g)
	var hh := h + (gmax - gmin) * 0.5 + 0.9
	var root := Node3D.new()
	root.name = id
	root.position = Vector3(p.x, gmin - 0.9, p.y)
	root.rotation.y = yaw
	root.set_meta("bp_slab", true)
	var prm := {
		"seed": sd, "n": clampi(int(round(maxf(hh, w) / 1.35)), 8, 13),
		"rho": rng.randf_range(0.22, 0.5), "taper": rng.randf_range(0.10, 0.42),
		"lean": Vector2(rng.randf_range(-0.16, 0.16), rng.randf_range(-0.07, 0.07)),
		"lump": rng.randf_range(0.10, 0.20), "strata": rng.randf_range(0.05, 0.10), "ridge": rng.randf_range(0.05, 0.10), "rough": 0.018,
		"moss": moss, "step": rng.randf_range(1.2, 2.1),
	}
	# V1.2：外形預設。slab＝V1.1 的方塊岩片（不加抽樣，JR 守門岩與 V1.1 逐位元相同）；
	#   boulder＝圓石（大圓角、少收窄、薄層理）；spire＝細高主岩（高收窄、明顯傾斜）。
	if form == "boulder":
		prm["n"] = clampi(int(round(maxf(hh, w) / 1.5)), 7, 11)
		prm["rho"] = rng.randf_range(0.62, 0.9)
		prm["taper"] = rng.randf_range(0.0, 0.14)
		prm["lean"] = Vector2(rng.randf_range(-0.06, 0.06), rng.randf_range(-0.05, 0.05))
		prm["lump"] = rng.randf_range(0.16, 0.26)
		prm["strata"] = rng.randf_range(0.03, 0.06)
		prm["step"] = rng.randf_range(0.8, 1.3)
	elif form == "spire":
		prm["rho"] = rng.randf_range(0.28, 0.42)
		prm["taper"] = rng.randf_range(0.28, 0.46)
		prm["lean"] = Vector2(rng.randf_range(-0.2, 0.2), rng.randf_range(-0.1, 0.1))
	root.set_meta("bp_slab_form", form)
	var xf := Transform3D(Basis(Vector3.UP, yaw), root.position)
	var rb: Dictionary = {}
	if form.begins_with("hero_"):
		# V1.2 F：Blender Hero Rock（找不到 GLB 就退回程序岩片，不會讓生成失敗）
		prm["mirror"] = (sd % 2) == 1
		rb = RockBuilder.build_hero("hero_rock_" + form.trim_prefix("hero_"), Vector3(w, hh, d), prm, xf, Callable(self, "_g"))
		if rb.is_empty():
			push_warning("Hero Rock %s 不可用，退回程序岩片" % form)
		else:
			root.set_meta("bp_hero", form)
			root.set_meta("bp_hero_size", Vector3(w, hh, d))        # 預期的網格尺寸（verify 對照 Godot 實際 AABB）
			root.set_meta("bp_hero_sha", String(RockBuilder.load_hero("hero_rock_" + form.trim_prefix("hero_"))["sha"]))
	if rb.is_empty():
		rb = RockBuilder.build(Vector3(w, hh, d), prm, xf, Callable(self, "_g"))
	_tally(rb)
	_add_rock_body(root, _save_rock_mesh(rb["mesh"], id), rb["pts"], true)
	root.set_meta("bp_slab_r", maxf(w, d) * 0.5)
	parent.add_child(root)
	return root


func _cliff_slab(poi: Dictionary) -> Node3D:
	var at := lib.resolve(poi["at"])
	var holder := _world_root(poi)
	var yaw := deg_to_rad(float(poi.get("yaw_deg", 0.0)))
	var w := float(poi["w"])
	var d := float(poi["d"])
	var moss := float(poi.get("moss", 0.4))
	var form := String(poi.get("form", "slab"))
	if String(poi.get("hero", "")) != "":
		form = String(poi["hero"])
	make_slab(holder, String(poi["id"]) + "_slab", at["p"], w, float(poi["h"]), d, yaw, moss, form)
	# 腳邊碎石：把乾淨的落地線打散（岩腳要像「從地裡長出來」，不是擺上去）
	var rr := RandomNumberGenerator.new()
	rr.seed = absi(String(poi["id"]).hash()) + 17
	var ax := Vector2(cos(yaw), -sin(yaw))
	var az := Vector2(sin(yaw), cos(yaw))
	# V1.2 C：岩腳碎石有尺寸層次——1 顆中石、1~2 顆圓石、數顆小石、一把細碎石（細碎石不收碰撞、不投影）
	var n_rub := 3
	var sizes: Array = ["medium", "small", "small"]
	if form.begins_with("hero_") or w * d > 30.0:
		sizes = ["medium", "cobble", "small", "small", "tiny", "tiny"]
	elif form == "boulder" or form == "spire":
		sizes = ["cobble", "small", "small", "tiny"]
	n_rub = sizes.size()
	for k in n_rub:
		var q: Vector2 = at["p"] + ax * rr.randf_range(-0.6, 0.6) * w + az * (rr.randf_range(0.0, 1.0) * 0.6 + 0.55) * d * (1.0 if rr.randf() < 0.5 else -1.0)
		make_rock(holder, "%s_rub%d" % [poi["id"], k], q, String(sizes[k]), moss, rr.randf() * TAU)
		_fp("%s_rub%d" % [poi["id"], k], q, 1.2 if String(sizes[k]) != "tiny" else 0.5)
	_fp(String(poi["id"]), at["p"], maxf(float(poi["w"]), float(poi["d"])) * 0.5 + 1.2)
	return holder


## V1.3：嵌進北崖崖面的岩塊（崖壁的層理／岩棚／扶壁）。
## V1.2 的北崖＝平滑的地形崖面＋站在崖腳前的岩柱；柱與崖之間是暗縫、崖面是一整片細碎平鋪的岩紋，
## 審圖讀成「一面坡＋前面一排柱子」。這些岩塊嵌在柱子上方與柱間的崖面，把柱子和崖頂連成同一塊石頭；兩端漸小、漸疏。
## 位置：x、y（岩塊中心高）由 layout 給；z＝該高度的崖面（由南往北第一次地形 ≥ y），厚度的 embed 比例埋進崖裡；
## 朝向：崖面法線（地形梯度）＋往崖內仰 tilt 度。
## 沒有碰撞：都在崖面上（地面以上 5 m 起），人到不了；也不擋 arena.rock_rhythm 的眼高射線、不登記腳印（樹與草叢的抽樣不受影響）。
func _face_rock(poi: Dictionary) -> Node3D:
	var holder := _world_root(poi)
	var id := String(poi["id"])
	var x := float(poi["x"])
	var yc := float(poi["y"])
	var w := float(poi["w"])
	var h := float(poi["h"])
	var d := float(poi["d"])
	var embed := float(poi.get("embed", 0.6))
	var zf := float(poi.get("z_from", -425.0))
	while zf > -480.0 and lib.h_at(x, zf) < yc:
		zf -= 0.1
	var gx := lib.h_at(x + 0.6, zf) - lib.h_at(x - 0.6, zf)
	var gz := lib.h_at(x, zf + 0.6) - lib.h_at(x, zf - 0.6)
	var nrm := Vector2(-gx, -gz)
	nrm = nrm.normalized() if nrm.length() > 1e-3 else Vector2(0.0, 1.0)
	var yaw := atan2(nrm.x, nrm.y) + deg_to_rad(float(poi.get("yaw", 0.0)))
	var tilt := deg_to_rad(float(poi.get("tilt", 10.0)))
	var bas := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -tilt)
	var c := Vector3(x, yc, zf) + Vector3(nrm.x, 0.0, nrm.y) * ((0.5 - embed) * d)
	var root := Node3D.new()
	root.name = id + "_rock"
	root.transform = Transform3D(bas, c - bas.y * (h * 0.5))
	root.set_meta("bp_face_rock", true)
	var sd := absi(id.hash())
	var rng := RandomNumberGenerator.new()
	rng.seed = sd
	var prm := {
		"seed": sd, "n": clampi(int(round(maxf(h, w) / 1.1)), 7, 11),
		"rho": rng.randf_range(0.34, 0.58), "taper": rng.randf_range(0.0, 0.16),
		"lean": Vector2(rng.randf_range(-0.06, 0.06), rng.randf_range(-0.04, 0.04)),
		"lump": rng.randf_range(0.14, 0.22), "strata": rng.randf_range(0.06, 0.11), "ridge": rng.randf_range(0.05, 0.10), "rough": 0.018,
		"moss": float(poi.get("moss", 0.5)), "step": rng.randf_range(0.9, 1.6),
	}
	# 頂點屬性的「離地高」用 _g_far（地面在很遠的下方）：崖面岩塊與崖是同一塊石頭，不畫貼地暗邊／腳邊泥土
	# （第一輪審圖：每顆岩塊外圈一道暗縫＋暗底面 → 讀成黏上去的板子）
	var rb := RockBuilder.build(Vector3(w, h, d), prm, root.transform, Callable(self, "_g_far"))
	_tally(rb)
	_add_rock_body(root, _save_rock_mesh(rb["mesh"], id), rb["pts"], false)
	var bb := AABB(root.transform * (rb["pts"] as PackedVector3Array)[0], Vector3.ZERO)
	for q: Vector3 in (rb["pts"] as PackedVector3Array):
		bb = bb.expand(root.transform * q)
	face_boxes.append(bb)
	root.set_meta("bp_face_aabb", bb)
	holder.add_child(root)
	holder.set_meta("bp_kind", "face_rock")
	return holder


# ---------------------------------------------------------------- 岩石（程序低模，重用 16 個變體）
func _rock_variant(size: String, k: int) -> Dictionary:
	var key := "%s_%d" % [size, k]
	if _rock_cache.has(key):
		return _rock_cache[key]
	var sd := absi(key.hash())
	_noise.seed = sd % 100000
	# 二十面體 + 一次細分
	var t := (1.0 + sqrt(5.0)) * 0.5
	var v: Array = [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0), Vector3(0, -1, t), Vector3(0, 1, t),
		Vector3(0, -1, -t), Vector3(0, 1, -t), Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	var f: Array = [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
		[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
	for i in v.size():
		v[i] = (v[i] as Vector3).normalized()
	var mid_cache := {}
	var faces2: Array = []
	for tri: Array in f:
		var m: Array = []
		for e in 3:
			var a: int = tri[e]
			var b: int = tri[(e + 1) % 3]
			var ek := "%d_%d" % [mini(a, b), maxi(a, b)]
			if not mid_cache.has(ek):
				v.append(((v[a] as Vector3) + (v[b] as Vector3)).normalized())
				mid_cache[ek] = v.size() - 1
			m.append(mid_cache[ek])
		faces2.append([tri[0], m[0], m[2]])
		faces2.append([tri[1], m[1], m[0]])
		faces2.append([tri[2], m[2], m[1]])
		faces2.append([m[0], m[1], m[2]])
	var squash := 0.62 if size != "boulder" else 0.78
	var rough_amp := 0.26
	var verts: Array = []
	for i in v.size():
		var u: Vector3 = v[i]
		var n := _noise.get_noise_3d(u.x * 1.9 + float(k) * 7.0, u.y * 1.9, u.z * 1.9)
		var p := u * (1.0 + rough_amp * n)
		p = Vector3(p.x * (1.0 + 0.18 * float(k % 3)), p.y * squash, p.z * (1.0 - 0.1 * float(k % 2)))
		p.y = maxf(p.y, -0.32)              # 平底，落地穩
		verts.append(p)
	var V := PackedVector3Array()
	var N := PackedVector3Array()
	var I := PackedInt32Array()
	for tri2: Array in faces2:
		var a2: Vector3 = verts[tri2[0]]
		var b2: Vector3 = verts[tri2[1]]
		var c2: Vector3 = verts[tri2[2]]
		var nn := (b2 - a2).cross(c2 - a2).normalized()
		# 二十面體面為逆時針（外向 cross 指外）；Godot 正面為順時針 → 反轉頂點序
		var base := V.size()
		V.append(a2)
		V.append(c2)
		V.append(b2)
		N.append(nn)
		N.append(nn)
		N.append(nn)
		I.append_array(PackedInt32Array([base, base + 1, base + 2]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = V
	arrays[Mesh.ARRAY_NORMAL] = N
	arrays[Mesh.ARRAY_INDEX] = I
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var pts := PackedVector3Array()
	for p3: Vector3 in verts:
		pts.append(p3)
	var out := {"mesh": mesh, "pts": pts}
	_rock_cache[key] = out
	return out


func _rock_radius(size: String) -> float:
	match size:
		"tiny": return _rng.randf_range(0.10, 0.19)
		"small": return _rng.randf_range(0.22, 0.40)
		"cobble": return _rng.randf_range(0.42, 0.62)
		"medium": return _rng.randf_range(0.65, 1.0)
		"large": return _rng.randf_range(1.3, 1.8)
		_: return _rng.randf_range(2.0, 2.8)       # boulder


## S04 的巨石／碎石：每顆獨立生成（種子＝id），不再共用 16 個二十面體變體
func _natural_rock(parent: Node, id: String, p: Vector2, size: String, moss: float, yaw: float, collide: bool, r: float, ground_min: bool = false) -> Node3D:
	var sd := absi(id.hash()) + 4242
	var rng := RandomNumberGenerator.new()
	rng.seed = sd
	var hs := rng.randf_range(0.55, 0.86) if (size != "small" and size != "tiny") else rng.randf_range(0.5, 0.8)
	var sz := Vector3(2.0 * r * rng.randf_range(0.80, 1.06), 2.0 * r * hs, 2.0 * r * rng.randf_range(0.74, 1.0))   # 半寬 ≤ 1.06 r：碰撞不比舊岩大，戰鬥圓淨空 gate 才守得住
	var gr := _g(p)
	if ground_min:
		# V1.3：坡上的岩（崖口河岸、崖腳）用落點範圍內最低的地面——V1.2 只看中心點，下坡那側的岩底懸空 0.2–0.8 m（_v13_probe_rocks 實測）
		for k in 8:
			var a := TAU * float(k) / 8.0
			gr = minf(gr, _g(p + Vector2(cos(a) * sz.x, sin(a) * sz.z) * 0.45))
	var eul := Vector3(deg_to_rad(rng.randf_range(-5.0, 5.0)), yaw, deg_to_rad(rng.randf_range(-5.0, 5.0)))
	var root := Node3D.new()
	root.name = id
	root.position = Vector3(p.x, gr - 0.22 * sz.y, p.y)
	root.rotation = eul
	var prm := {
		"seed": sd, "n": 4 if size == "tiny" else (5 if (size == "small" or size == "cobble") else (7 if size == "medium" else 9)),
		"rho": rng.randf_range(0.5, 0.88), "taper": rng.randf_range(0.0, 0.22),
		"lean": Vector2(rng.randf_range(-0.08, 0.08), rng.randf_range(-0.05, 0.05)),
		"lump": rng.randf_range(0.10, 0.2), "strata": rng.randf_range(0.02, 0.06), "ridge": rng.randf_range(0.03, 0.08), "rough": 0.02,
		"moss": clampf(moss + 0.15, 0.0, 1.0), "step": rng.randf_range(0.5, 1.1),
	}
	var rb := RockBuilder.build(sz, prm, Transform3D(Basis.from_euler(eul), root.position), Callable(self, "_g"))
	_tally(rb)
	_add_rock_body(root, _save_rock_mesh(rb["mesh"], id), rb["pts"], collide and size != "tiny", size != "small" and size != "tiny")
	root.set_meta("bp_rock_r", r)
	parent.add_child(root)
	return root


func make_rock(parent: Node, id: String, p: Vector2, size: String, moss: float, yaw: float, collide: bool = true, ground_min: bool = false) -> Node3D:
	var k := _rng.randi() % 4
	var r := _rock_radius(size)
	if lib.scene_id_of_z(p.y) == "S04":
		return _natural_rock(parent, id, p, size, moss, yaw, collide, r, ground_min)
	var rv := _rock_variant(size, k)
	var node := Node3D.new()
	node.name = id
	node.position = Vector3(p.x, _g(p) - 0.12 * r, p.y)
	node.rotation.y = yaw
	var sc := Vector3(r, r, r)
	var m := MeshInstance3D.new()
	m.mesh = rv["mesh"]
	m.scale = sc
	m.material_override = mat(Color(0.47, 0.46, 0.43).lerp(COL_STONE_MOSS, clampf(moss, 0.0, 1.0) * 0.8), 0.97)
	node.add_child(m)
	if collide:
		var sb := body(node)
		var cs := CollisionShape3D.new()
		var shape := ConvexPolygonShape3D.new()
		var pts := PackedVector3Array()
		for q: Vector3 in (rv["pts"] as PackedVector3Array):
			pts.append(q * r)
		shape.points = pts
		cs.shape = shape
		sb.add_child(cs)
	node.set_meta("bp_rock_r", r)
	parent.add_child(node)
	return node


# ---------------------------------------------------------------- 入口
const ZONE_PROPS := "res://tools/beast_path/zone_props.gd"


## 全區美術完成：layout 的 POI 有 "skin": true → 照原本建（碰撞／腳印／錨點不變），再由 zone_props.gd 換成 Blender 資產的外觀（S04 不處理）
func build(poi: Dictionary) -> Node3D:
	var n := _build_v01(poi)
	if n != null and bool(poi.get("skin", false)) and _skin_ok(n):
		n = load(ZONE_PROPS).skin(self, poi, n)
	return n


func _skin_ok(n: Node3D) -> bool:
	var p := n.position
	if p == Vector3.ZERO:
		for c in n.get_children():
			if c is Node3D and (c as Node3D).position != Vector3.ZERO:
				p = (c as Node3D).position
				break
	return lib.scene_id_of_z(p.z) != "S04"


func _build_v01(poi: Dictionary) -> Node3D:
	_rng.seed = absi(String(poi["id"]).hash())
	var kind := String(poi["kind"])
	match kind:
		"torii": return _torii(poi)
		"lantern": return _lantern(poi)
		"signpost": return _signpost(poi)
		"fence_run": return _fence_run(poi)
		"hut": return _hut(poi)
		"shrine_small": return _shrine_small(poi)
		"stone_marker": return _stone_marker(poi)
		"rock": return _rock_poi(poi)
		"rock_scatter": return _rock_scatter(poi)
		"log": return _log(poi)
		"stump": return _stump(poi)
		"roots": return _roots(poi)
		"footprints": return _footprints(poi)
		"offerings": return _offerings(poi)
		"bones": return _bones(poi)
		"mushrooms": return _mushrooms(poi)
		"broken_branch": return _broken_branch(poi)
		"stone_steps": return _stone_steps(poi)
		"bridge": return _bridge(poi)
		"stepping_stones": return _stepping_stones(poi)
		"cascade": return _cascade(poi)
		"locked_gate": return _locked_gate(poi)
		"stone_pillar": return _stone_pillar(poi)
		"cliff_slab": return _cliff_slab(poi)
		"face_rock": return _face_rock(poi)
		"farm_patch": return _farm_patch(poi)
		"firewood": return _firewood(poi)
		"basket": return _basket(poi)
		"altar": return _altar(poi)
		"spawn", "portal_marker": return _marker(poi)
		"shimenawa": return null          # 第二輪（需先有 pillar / tree 錨點）
	push_warning("未知 POI kind：%s" % kind)
	return null


func build_deferred(poi: Dictionary) -> Node3D:
	_rng.seed = absi(String(poi["id"]).hash())
	if String(poi["kind"]) == "shimenawa":
		return _shimenawa(poi)
	return null


# ---------------------------------------------------------------- 各種道具
func _pos_yaw(poi: Dictionary) -> Dictionary:
	var at := lib.resolve(poi["at"])
	var yaw: float = at["yaw"]
	if String(poi.get("face", "")) == "path":
		yaw = yaw_face_path(at["p"])
	if poi.has("yaw_deg"):
		yaw = deg_to_rad(float(poi["yaw_deg"]))
	return {"p": at["p"], "yaw": yaw, "at": at}


func _marker(poi: Dictionary) -> Node3D:
	var py := _pos_yaw(poi)
	var r := _root(poi, py["p"], py["yaw"])
	r.set_meta("bp_marker", true)
	return r


## S01 R6：POI 有 "model" 欄位 → Blender 資產版本（tools/beast_path/s01_arch.gd）；沒有的（S02–S04）照舊
const S01_ARCH := "res://tools/beast_path/s01_arch.gd"


func _torii(poi: Dictionary) -> Node3D:
	if poi.has("model"):
		return load(S01_ARCH).torii(self, poi)
	var py := _pos_yaw(poi)
	var r := _root(poi, py["p"], py["yaw"])
	var span := float(poi.get("span", 4.0))
	var h := float(poi.get("h", 4.2))
	var weathered := String(poi.get("color", "red")) == "weathered"
	var broken := bool(poi.get("broken", false))
	var col := COL_RED_OLD if weathered else COL_RED
	var pr := 0.24 if not weathered else 0.2
	var sb := body(r)
	if broken:
		# 破鳥居：左柱完整＋缺角笠木掛在柱頭；右柱斷在 0.9 m，上半段倒在地上
		cyl(r, pr, h, Vector3(-span * 0.5, h * 0.5, 0), col, Vector3.ZERO, pr * 0.88)
		cyl(r, pr * 1.18, 0.35, Vector3(-span * 0.5, 0.175, 0), COL_BLACK)
		col_cyl(sb, pr + 0.03, h, Vector3(-span * 0.5, h * 0.5, 0))
		cyl(r, pr, 0.9, Vector3(span * 0.5, 0.45, 0), col, Vector3.ZERO, pr * 0.97)
		col_cyl(sb, pr + 0.03, 0.9, Vector3(span * 0.5, 0.45, 0))
		box(r, Vector3(span * 0.45, 0.30, 0.55), Vector3(-span * 0.25, h + 0.15, 0), COL_BLACK, Vector3(0, 0, -7))
		box(r, Vector3(span * 0.4, 0.14, 0.7), Vector3(-span * 0.27, h + 0.36, 0), COL_BLACK, Vector3(0, 0, -7))
		var fallen := cyl(r, pr, h - 0.9, Vector3(span * 0.5 + 0.9, pr * 0.9, 1.4), col, Vector3(0, 0, 90) + Vector3(0, 35, 0), pr * 0.9)
		fallen.name = "FallenPillar"
		col_cyl(sb, pr, h - 0.9, Vector3(span * 0.5 + 0.9, pr * 0.9, 1.4), Vector3(0, 35, 0) + Vector3(0, 0, 90))
		box(r, Vector3(span * 0.35, 0.28, 0.5), Vector3(span * 0.5 + 1.5, 0.16, -1.1), COL_BLACK, Vector3(0, 28, 4))
		_fp(String(poi["id"]), py["p"], span * 0.5 + 2.6)
		anchors[String(poi["id"])] = {"p": r.position, "h": h}
		return r
	for sx in [-1.0, 1.0]:
		cyl(r, pr, h, Vector3(sx * span * 0.5, h * 0.5, 0), col, Vector3.ZERO, pr * 0.88)
		cyl(r, pr * 1.18, 0.35, Vector3(sx * span * 0.5, 0.175, 0), COL_BLACK)
		col_cyl(sb, pr + 0.03, h, Vector3(sx * span * 0.5, h * 0.5, 0))
	box(r, Vector3(span + 1.5, 0.30, 0.55), Vector3(0, h + 0.15, 0), COL_BLACK, Vector3(0, 0, 0))
	box(r, Vector3(span + 1.9, 0.14, 0.7), Vector3(0, h + 0.38, 0), COL_BLACK)
	box(r, Vector3(span + 0.5, 0.22, 0.30), Vector3(0, h * 0.8, 0), col)
	box(r, Vector3(0.7, 0.5, 0.1), Vector3(0, h * 0.8 + 0.4, 0), COL_BLACK)
	_fp(String(poi["id"]), py["p"], span * 0.5 + 2.2)
	anchors[String(poi["id"])] = {"p": r.position, "h": h}
	return r


## 祭壇遺跡（B：西側）：兩層石座＋一根立柱＋一根斷柱＋供品
func _altar(poi: Dictionary) -> Node3D:
	var py := _pos_yaw(poi)
	var r := _root(poi, py["p"], py["yaw"])
	var sb := body(r)
	var c := COL_STONE.lerp(COL_STONE_MOSS, 0.45)
	box(r, Vector3(4.2, 0.42, 3.0), Vector3(0, 0.1, 0), c.darkened(0.05))
	col_box(sb, Vector3(4.2, 0.42, 3.0), Vector3(0, 0.1, 0))
	box(r, Vector3(3.2, 0.36, 2.2), Vector3(0, 0.49, 0), c)
	col_box(sb, Vector3(3.2, 0.36, 2.2), Vector3(0, 0.49, 0))
	box(r, Vector3(1.4, 0.25, 0.5), Vector3(0, 0.0, -1.85), c.darkened(0.08))
	col_box(sb, Vector3(1.4, 0.25, 0.5), Vector3(0, 0.0, -1.85))
	box(r, Vector3(0.5, 2.0, 0.5), Vector3(-1.2, 1.65, 0.6), c, Vector3(0, 8, 1.5))
	box(r, Vector3(0.62, 0.14, 0.62), Vector3(-1.2, 2.68, 0.6), c.lightened(0.05), Vector3(0, 8, 1.5))
	col_box(sb, Vector3(0.55, 2.0, 0.55), Vector3(-1.2, 1.65, 0.6))
	box(r, Vector3(0.5, 0.8, 0.5), Vector3(1.2, 0.95, 0.6), c, Vector3(4, 20, 0))
	col_box(sb, Vector3(0.5, 0.8, 0.5), Vector3(1.2, 0.95, 0.6))
	box(r, Vector3(0.46, 0.9, 0.46), Vector3(1.9, 0.2, 1.7), c.darkened(0.1), Vector3(0, 33, 82))
	box(r, Vector3(0.7, 0.3, 0.5), Vector3(0, 0.84, -0.2), c.lightened(0.04))
	var cols := [Color(0.9, 0.9, 0.85), Color(0.78, 0.2, 0.14), Color(0.85, 0.8, 0.7)]
	for i in 3:
		box(r, Vector3(0.1, 0.09, 0.1), Vector3(-0.2 + 0.2 * float(i), 1.04, -0.2), cols[i], Vector3(0, 20.0 * float(i), 0))
	_fp(String(poi["id"]), py["p"], 3.4)
	return r


func _lantern(poi: Dictionary) -> Node3D:
	if poi.has("model"):
		return load(S01_ARCH).lantern(self, poi)
	var py := _pos_yaw(poi)
	var r := _root(poi, py["p"], py["yaw"])
	var moss := float(poi.get("moss", 0.0))
	var c := COL_STONE.lerp(COL_STONE_MOSS, moss * 0.8)
	var holder := Node3D.new()
	holder.name = "Body"
	r.add_child(holder)
	box(holder, Vector3(0.56, 0.26, 0.56), Vector3(0, 0.13, 0), c)
	cyl(holder, 0.13, 0.78, Vector3(0, 0.65, 0), c)
	box(holder, Vector3(0.52, 0.12, 0.52), Vector3(0, 1.1, 0), c)
	box(holder, Vector3(0.44, 0.46, 0.44), Vector3(0, 1.4, 0), c.darkened(0.06))
	box(holder, Vector3(0.84, 0.16, 0.84), Vector3(0, 1.71, 0), c)
	box(holder, Vector3(0.3, 0.2, 0.3), Vector3(0, 1.89, 0), c)
	var sb := body(r)
	if bool(poi.get("fallen", false)):
		holder.rotation_degrees = Vector3(0, 0, 78)
		holder.position = Vector3(0.5, 0.25, 0)
		col_box(sb, Vector3(1.9, 0.6, 0.6), Vector3(0.9, 0.3, 0))
	else:
		col_box(sb, Vector3(0.6, 1.95, 0.6), Vector3(0, 0.975, 0))
	_fp(String(poi["id"]), py["p"], 1.1)
	return r


func _signpost(poi: Dictionary) -> Node3D:
	var py := _pos_yaw(poi)
	var r := _root(poi, py["p"], py["yaw"])
	box(r, Vector3(0.15, 2.2, 0.15), Vector3(0, 1.1, 0), COL_WOOD_DARK)
	box(r, Vector3(0.24, 0.12, 0.24), Vector3(0, 2.26, 0), COL_WOOD_DARK)
	var boards: Array = poi.get("boards", [])
	# 板的長軸指向「世界方位」（N＝−z、W＝−x…），箭頭端在 +X；字面向路（本地 −Z）
	var dirs := {"N": Vector2(0, -1), "S": Vector2(0, 1), "W": Vector2(-1, 0), "E": Vector2(1, 0)}
	for i in boards.size():
		var b: Dictionary = boards[i]
		var dv: Vector2 = dirs.get(String(b["dir"]), Vector2(0, -1))
		var alpha := atan2(-dv.y, dv.x)               # 繞 Y 轉 alpha 後，本地 +X → 世界 dv
		var holder := Node3D.new()
		holder.position = Vector3(0, 1.95 - 0.34 * float(i), 0)
		holder.rotation.y = alpha - float(py["yaw"])
		holder.name = "Board_%s" % String(b["dir"])
		holder.set_meta("bp_label", String(b.get("label", "")))
		r.add_child(holder)
		box(holder, Vector3(1.05, 0.26, 0.05), Vector3(0.45, 0, 0), COL_WOOD)
		box(holder, Vector3(0.2, 0.2, 0.05), Vector3(1.02, 0, 0), COL_WOOD, Vector3(0, 0, 45))
		box(holder, Vector3(0.62, 0.05, 0.06), Vector3(0.42, 0, 0), COL_BLACK)     # 示意文字帶（白模；正式字待 H01）
	var sb := body(r)
	col_box(sb, Vector3(0.3, 2.2, 0.3), Vector3(0, 1.1, 0))
	_fp(String(poi["id"]), py["p"], 1.2)
	return r


func _run_side(poi_at: Dictionary, s_mid: float) -> float:
	## off 正負；side＝downhill 時選地形較低的一側
	var off := float(poi_at.get("off", 0.0))
	if String(poi_at.get("side", "")) == "downhill":
		var t := lib.main.tan_at(s_mid)
		var rv := BPLib.right_of(t)
		var c := lib.main.pos_at(s_mid)
		var hr := lib.h_at(c.x + rv.x * absf(off), c.y + rv.y * absf(off))
		var hl_ := lib.h_at(c.x - rv.x * absf(off), c.y - rv.y * absf(off))
		return absf(off) if hr < hl_ else -absf(off)
	return off


func _fence_run(poi: Dictionary) -> Node3D:
	var at: Dictionary = poi["at"]
	var s0 := lib.st_s(String(at["st"])) + float(at["ds0"])
	var s1 := lib.st_s(String(at["st"])) + float(at["ds1"])
	var off := _run_side(at, (s0 + s1) * 0.5)
	var d_off := (float(at["off1"]) - float(at["off"])) if at.has("off1") else 0.0      # S01 R1：選用——起點到終點的離路距離變化（柵欄離路斜開＝地界，不是沿路的欄杆）
	var weathered := float(poi.get("weathered", 0.2))
	var r := _world_root(poi)
	var sb := body(r)
	var n := maxi(int(ceil((s1 - s0) / 2.4)), 1)
	var prev := Vector3.ZERO
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(String(poi["id"]).hash())
	for i in n + 1:
		var s := lerpf(s0, s1, float(i) / float(n))
		var t := lib.main.tan_at(s)
		var p := lib.main.pos_at(s) + BPLib.right_of(t) * (off + d_off * float(i) / float(n))
		var gy := _g(p)
		var post_h := 0.95 * (1.0 - 0.25 * weathered * rng.randf())
		var lean := rng.randf_range(-1.0, 1.0) * 9.0 * weathered
		var pn := box(r, Vector3(0.13, post_h + 0.25, 0.13), Vector3(p.x, gy + post_h * 0.5 - 0.12, p.y), COL_WOOD_OLD.lerp(COL_WOOD, 1.0 - weathered), Vector3(lean, 0, lean * 0.6))
		pn.name = "Post%d" % i
		if i > 0:
			for k in 2:
				if rng.randf() < weathered * 0.5 and k == 1:
					continue                     # 缺一根橫木
				var hh := 0.45 + 0.34 * float(k) - 0.12
				beam(r, Vector3(prev.x, prev.y + hh, prev.z), Vector3(p.x, gy + hh, p.y), Vector2(0.06, 0.08), COL_WOOD_OLD.lerp(COL_WOOD, 1.0 - weathered))
			# 碰撞：一片薄板（0.95 高，可跳過；不是牆）
			var a := Vector3(prev.x, 0, prev.z)
			var b := Vector3(p.x, 0, p.y)
			var mid := (a + b) * 0.5
			var seg := a.distance_to(b)
			var ang := atan2(b.x - a.x, b.z - a.z)
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = Vector3(0.12, 0.9, seg)
			cs.shape = bs
			cs.position = Vector3(mid.x, (prev.y + gy) * 0.5 + 0.38, mid.z)
			cs.rotation.y = ang
			sb.add_child(cs)
		prev = Vector3(p.x, gy, p.y)
		_fp(String(poi["id"]) + "_%d" % i, p, 0.9)
	return r


func _hut(poi: Dictionary) -> Node3D:
	var py := _pos_yaw(poi)
	var r := _root(poi, py["p"], py["yaw"])
	var w := float(poi.get("w", 4.4))
	var d := float(poi.get("d", 3.4))
	var h := float(poi.get("h", 3.2))
	var wall_h := h * 0.62
	box(r, Vector3(w + 0.3, 0.3, d + 0.3), Vector3(0, 0.1, 0), COL_STONE.darkened(0.15))
	box(r, Vector3(w, wall_h, d), Vector3(0, 0.25 + wall_h * 0.5, 0), COL_WOOD_OLD)
	var roof := mi(r, _prism(Vector3(w + 1.0, h - wall_h, d + 0.9)), COL_ROOF, Vector3(0, 0.25 + wall_h + (h - wall_h) * 0.5, 0))
	roof.name = "Roof"
	box(r, Vector3(1.0, 1.9, 0.08), Vector3(0, 1.2, -d * 0.5 - 0.02), COL_WOOD_DARK)
	var sb := body(r)
	col_box(sb, Vector3(w, wall_h + 0.3, d), Vector3(0, 0.25 + wall_h * 0.5, 0))
	_fp(String(poi["id"]), py["p"], maxf(w, d) * 0.5 + 2.0)
	return r


func _prism(size: Vector3) -> PrismMesh:
	var key := "p%.3f,%.3f,%.3f" % [size.x, size.y, size.z]
	if not _meshes.has(key):
		var pm := PrismMesh.new()
		pm.size = size
		_meshes[key] = pm
	return _meshes[key]


func _shrine_small(poi: Dictionary) -> Node3D:
	var py := _pos_yaw(poi)
	var r := _root(poi, py["p"], py["yaw"])
	var w := float(poi.get("w", 2.6))
	var d := float(poi.get("d", 2.2))
	var h := float(poi.get("h", 2.8))
	var steps := int(poi.get("steps", 3))
	var plat_h := 0.18 * float(steps) + 0.1
	var sb := body(r)
	box(r, Vector3(w + 1.0, plat_h, d + 1.0), Vector3(0, plat_h * 0.5 - 0.05, 0), COL_STONE)
	col_box(sb, Vector3(w + 1.0, plat_h, d + 1.0), Vector3(0, plat_h * 0.5 - 0.05, 0))
	for i in steps:
		var sy := 0.18 * float(i + 1) - 0.05
		var sz := -(d + 1.0) * 0.5 - 0.55 * float(steps - i) + 0.25
		box(r, Vector3(1.8, sy, 0.5), Vector3(0, sy * 0.5, sz), COL_STONE.darkened(0.04))
		col_box(sb, Vector3(1.8, sy, 0.5), Vector3(0, sy * 0.5, sz))
	var bh := h * 0.55
	box(r, Vector3(w, bh, d), Vector3(0, plat_h + bh * 0.5 - 0.05, 0), COL_WOOD_DARK)
	col_box(sb, Vector3(w, bh, d), Vector3(0, plat_h + bh * 0.5 - 0.05, 0))
	mi(r, _prism(Vector3(w + 1.1, h - bh, d + 1.0)), COL_ROOF, Vector3(0, plat_h + bh + (h - bh) * 0.5 - 0.05, 0))
	box(r, Vector3(0.6, 0.9, 0.06), Vector3(0, plat_h + 0.65, -d * 0.5 - 0.02), Color(0.07, 0.06, 0.06))
	if bool(poi.get("fence", false)):
		var fx := (w + 1.0) * 0.5 + 0.9
		var fz := (d + 1.0) * 0.5 + 0.9
		for sx in [-1.0, 1.0]:
			for k in 3:
				var zz := lerpf(-fz, fz, float(k) / 2.0)
				box(r, Vector3(0.1, 0.85, 0.1), Vector3(sx * fx, 0.4, zz), COL_WOOD_OLD)
			beam(r, Vector3(sx * fx, 0.7, -fz), Vector3(sx * fx, 0.7, fz), Vector2(0.05, 0.07), COL_WOOD_OLD)
			col_box(sb, Vector3(0.1, 0.8, fz * 2.0), Vector3(sx * fx, 0.4, 0))
		for k in 3:
			var xx := lerpf(-fx, fx, float(k) / 2.0)
			box(r, Vector3(0.1, 0.85, 0.1), Vector3(xx, 0.4, fz), COL_WOOD_OLD)
		beam(r, Vector3(-fx, 0.7, fz), Vector3(fx, 0.7, fz), Vector2(0.05, 0.07), COL_WOOD_OLD)
		col_box(sb, Vector3(fx * 2.0, 0.8, 0.1), Vector3(0, 0.4, fz))
	_fp(String(poi["id"]), py["p"], maxf(w, d) * 0.5 + 3.4)
	return r


func _stone_marker(poi: Dictionary) -> Node3D:
	var py := _pos_yaw(poi)
	var r := _root(poi, py["p"], py["yaw"])
	var h := float(poi.get("h", 1.1))
	box(r, Vector3(0.5, h, 0.42), Vector3(0, h * 0.5 - 0.1, 0), COL_STONE.lerp(COL_STONE_MOSS, 0.25), Vector3(0, 0, 2.5))
	box(r, Vector3(0.62, 0.12, 0.54), Vector3(0, h - 0.1, 0), COL_STONE)
	var sb := body(r)
	col_box(sb, Vector3(0.55, h, 0.45), Vector3(0, h * 0.5 - 0.1, 0))
	_fp(String(poi["id"]), py["p"], 1.0)
	return r


func _rock_poi(poi: Dictionary) -> Node3D:
	var at := lib.resolve(poi["at"])
	var holder := Node3D.new()
	holder.name = String(poi["id"]) + "_root"
	holder.set_meta("bp_id", String(poi["id"]))
	holder.set_meta("bp_kind", "rock")
	holder.set_meta("bp_spec", String(poi.get("spec", "")))
	var rock := make_rock(holder, String(poi["id"]), at["p"], String(poi.get("size", "medium")), float(poi.get("moss", 0.2)), _rng.randf() * TAU, true, String(poi.get("ground", "")) == "min")
	_fp(String(poi["id"]), at["p"], float(rock.get_meta("bp_rock_r")) * 1.3 + 0.4)
	return holder


func _rock_scatter(poi: Dictionary) -> Node3D:
	var holder := _world_root(poi)
	var s0 := lib.st_s(String(poi["st0"])) + float(poi.get("ds0", 0.0))
	var s1 := lib.st_s(String(poi["st1"])) + float(poi.get("ds1", 0.0))
	var band: Array = poi["band"]
	var n := int(poi["n"])
	for i in n:
		var s := _rng.randf_range(minf(s0, s1), maxf(s0, s1))
		var side := -1.0 if _rng.randf() < 0.5 else 1.0
		var off := side * _rng.randf_range(float(band[0]), float(band[1]))
		var at := lib.resolve({"x": 0.0, "z": 0.0})
		var t := lib.main.tan_at(s)
		var p := lib.main.pos_at(s) + BPLib.right_of(t) * off
		var rock := make_rock(holder, "%s_%d" % [poi["id"], i], p, String(poi.get("size", "small")), _rng.randf_range(0.0, 0.5), _rng.randf() * TAU)
		_fp("%s_%d" % [poi["id"], i], p, float(rock.get_meta("bp_rock_r")) * 1.3 + 0.3)
	return holder


func _beam_on_ground(parent: Node, center: Vector2, yaw: float, length: float, r: float, col: Color, lift: float = 0.0) -> Dictionary:
	var dirv := Vector2(sin(yaw), cos(yaw))        # 朝 +z 的 yaw 方向（本地 Z 軸）
	var a2 := center - dirv * length * 0.5
	var b2 := center + dirv * length * 0.5
	var ya := _g(a2) + r * 0.7 + lift
	var yb := _g(b2) + r * 0.7 + lift
	var a := Vector3(a2.x, ya, a2.y)
	var b := Vector3(b2.x, yb, b2.y)
	var m := MeshInstance3D.new()
	m.mesh = _cyl_mesh(r, r * 0.9, length, 10)
	m.material_override = mat(col, 0.98)
	var up := Vector3.UP
	var axis := (b - a).normalized()
	# 圓柱本地 Y 軸對到 a→b
	var bx := up.cross(axis)
	if bx.length() < 0.001:
		bx = Vector3.RIGHT
	bx = bx.normalized()
	var bz := bx.cross(axis).normalized()
	m.transform = Transform3D(Basis(bx, axis, bz), (a + b) * 0.5)
	parent.add_child(m)
	return {"a": a, "b": b, "mid": (a + b) * 0.5, "axis": axis, "mesh": m}


func _log(poi: Dictionary) -> Node3D:
	var py := _pos_yaw(poi)
	var holder := _world_root(poi)
	var len := float(poi.get("len", 5.0))
	var r := float(poi.get("r", 0.35))
	var info := _beam_on_ground(holder, py["p"], py["yaw"], len, r, Color(0.30, 0.22, 0.15))
	var sb := body(holder)
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = r
	shape.height = len
	cs.shape = shape
	cs.transform = (info["mesh"] as MeshInstance3D).transform
	sb.add_child(cs)
	# 苔斑
	var patch := mi(holder, _sph_mesh(r * 0.7, 0.4), Color(0.22, 0.36, 0.17), (info["mid"] as Vector3) + Vector3(0, r * 0.55, 0))
	patch.scale = Vector3(1.0, 0.5, 2.2)
	_fp(String(poi["id"]), py["p"], len * 0.5 + 0.8)
	return holder


func _stump(poi: Dictionary) -> Node3D:
	var py := _pos_yaw(poi)
	var r := _root(poi, py["p"], py["yaw"])
	var rad := float(poi.get("r", 0.5))
	var h := float(poi.get("h", 0.7))
	cyl(r, rad, h, Vector3(0, h * 0.5 - 0.1, 0), Color(0.31, 0.22, 0.14), Vector3.ZERO, rad * 0.85)
	cyl(r, rad * 1.5, 0.25, Vector3(0, 0.0, 0), Color(0.29, 0.21, 0.13), Vector3.ZERO, rad * 0.9)
	cyl(r, rad * 0.9, 0.04, Vector3(0, h - 0.08, 0), Color(0.66, 0.55, 0.38))
	var sb := body(r)
	col_cyl(sb, rad * 1.05, h, Vector3(0, h * 0.5 - 0.1, 0))
	_fp(String(poi["id"]), py["p"], rad * 1.5 + 0.7)
	return r


func _roots(poi: Dictionary) -> Node3D:
	if bool(poi.get("natural", false)):
		return _roots_natural(poi)
	var py := _pos_yaw(poi)
	var holder := _world_root(poi)
	var rad := float(poi.get("r", 1.2))
	var n := 4
	for i in n:
		var yaw := _rng.randf() * TAU
		var len := rad * _rng.randf_range(1.4, 2.2)
		var c: Vector2 = (py["p"] as Vector2) + Vector2(sin(yaw), cos(yaw)) * len * 0.5
		var thick := _rng.randf_range(0.14, 0.24)
		_beam_on_ground(holder, c, yaw, len, thick, Color(0.30, 0.22, 0.15), -thick * 0.75)
	_fp(String(poi["id"]), py["p"], rad + 1.0)
	return holder


# ---------------------------------------------------------------- V1.2 自然樹根／倒木（只用在 S04）
## 沿 pts 掃出一根會漸細的管（平行傳輸座標框）。UV＝繞圈 × 沿長；貼 P9 veg_kit 的枯木樹皮（唯讀重用）。
## 頂點色＝樹皮貼圖的乘數：頂面偏苔、底面較暗、沿長度隨機明暗。
const BARK_ALB := "res://assets/village_v2/veg_kit/tex/VB_dead_albedo.jpg"
const BARK_NRM := "res://assets/village_v2/veg_kit/tex/VB_dead_normal.jpg"


func _bark_mat() -> StandardMaterial3D:
	if _mats.has("bark_dead_tube"):
		return _mats["bark_dead_tube"]
	var sm := StandardMaterial3D.new()
	sm.resource_name = "BP_BarkDeadTube"
	sm.vertex_color_use_as_albedo = true
	sm.vertex_color_is_srgb = true
	sm.albedo_color = Color(1, 1, 1, 1)
	sm.albedo_texture = load(BARK_ALB) as Texture2D
	sm.normal_enabled = true
	sm.normal_texture = load(BARK_NRM) as Texture2D
	sm.normal_scale = 1.0
	sm.roughness = 0.95
	_mats["bark_dead_tube"] = sm
	return sm


func _tube(parent: Node, pts: PackedVector3Array, rad: PackedFloat32Array, col: Color, seed_i: int, sides: int = 7, moss: float = 0.0) -> MeshInstance3D:
	var n := pts.size()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_i
	var V := PackedVector3Array()
	var N := PackedVector3Array()
	var C := PackedColorArray()
	var UV := PackedVector2Array()
	var prev_n := Vector3.ZERO
	var run := 0.0
	var ring := sides + 1                          # 多一個重複頂點，UV 接縫才不會拉伸
	var ucount := maxf(1.0, roundf(TAU * maxf(rad[0], rad[n / 2]) / 0.9))
	for i in n:
		var t: Vector3 = pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]
		t = t.normalized()
		var nn := Vector3.ZERO
		if i == 0:
			nn = t.cross(Vector3.UP)
			if nn.length() < 0.01:
				nn = t.cross(Vector3.RIGHT)
		else:
			nn = prev_n - t * prev_n.dot(t)
			run += pts[i].distance_to(pts[i - 1])
		nn = nn.normalized()
		prev_n = nn
		var bb := t.cross(nn).normalized()
		var shade := 1.0 + (rng.randf() - 0.5) * 0.2
		for k in ring:
			if k == sides:
				V.append(V[i * ring])
				N.append(N[i * ring])
				C.append(C[i * ring])
				UV.append(Vector2(ucount, run / 1.1))
				continue
			var a := TAU * float(k) / float(sides)
			var d := nn * cos(a) + bb * sin(a)
			var furrow := 1.0 + 0.07 * sin(a * 5.0 + float(i) * 0.9) + 0.04 * sin(a * 11.0 - float(i) * 1.3) + rng.randf_range(-0.03, 0.03)
			V.append(pts[i] + d * rad[i] * furrow)
			N.append(d)
			var up := clampf(d.y, -1.0, 1.0)
			var tint := Color(0.60, 0.52, 0.45) * (0.74 + 0.26 * up + 0.10) * shade
			tint = tint.lerp(Color(0.55, 0.68, 0.38), clampf(up, 0.0, 1.0) * moss)
			C.append(Color(tint.r, tint.g, tint.b, 1.0))
			UV.append(Vector2(float(k) / float(sides) * ucount, run / 1.1))
	var I := PackedInt32Array()
	for i in n - 1:
		for k in sides:
			var a0 := i * ring + k
			var b0 := i * ring + k + 1
			var c0 := (i + 1) * ring + k
			var d0 := (i + 1) * ring + k + 1
			for tri: Array in [[a0, b0, c0], [b0, d0, c0]]:
				var fn := (V[tri[2]] - V[tri[0]]).cross(V[tri[1]] - V[tri[0]])
				if fn.dot(N[tri[0]]) < 0.0:
					I.append_array(PackedInt32Array([tri[0], tri[2], tri[1]]))
				else:
					I.append_array(PackedInt32Array([tri[0], tri[1], tri[2]]))
	# 起點端蓋（埋在地下／岩下，看不見但封口）
	var cap0 := V.size()
	V.append(pts[0])
	N.append((pts[0] - pts[1]).normalized())
	C.append(C[0])
	UV.append(Vector2(0.5, 0.0))
	for k in sides:
		var tri2 := [cap0, k + 1, k]
		var fn2 := (V[tri2[2]] - V[tri2[0]]).cross(V[tri2[1]] - V[tri2[0]])
		if fn2.dot(N[cap0]) < 0.0:
			tri2 = [cap0, k, k + 1]
		I.append_array(PackedInt32Array(tri2))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = V
	arr[Mesh.ARRAY_NORMAL] = N
	arr[Mesh.ARRAY_COLOR] = C
	arr[Mesh.ARRAY_TEX_UV] = UV
	arr[Mesh.ARRAY_INDEX] = I
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	# 法線貼圖需要切線：用 SurfaceTool 產生
	var st := SurfaceTool.new()
	st.create_from(am, 0)
	st.generate_tangents()
	var am2 := st.commit()
	var m := MeshInstance3D.new()
	m.mesh = am2
	m.material_override = _bark_mat()
	parent.add_child(m)
	return m


## 一根向外延伸的地表樹根：起點略高於地面、中段貼地起伏、末端沒入土中；有一支岔根。
func _root_run(parent: Node, c: Vector2, yaw: float, length: float, thick: float, seed_i: int, depth: int = 0) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_i
	var dir := Vector2(sin(yaw), cos(yaw))
	var side := Vector2(dir.y, -dir.x)
	var n := int(clampf(length / 0.28, 10.0, 22.0))
	var pts := PackedVector3Array()
	var rad := PackedFloat32Array()
	var wob := rng.randf_range(0.45, 0.9) * thick * 3.2
	var ph := rng.randf() * TAU
	for i in n + 1:
		var s := float(i) / float(n)
		var q: Vector2 = c + dir * (s * length) + side * (sin(s * 3.6 + ph) * wob * s + sin(s * 9.0 + ph * 2.0) * thick * 0.35 * s)
		# 起點抬高並外展、中段半埋、末端沒入土中
		var lift := thick * (0.05 * (1.0 - s) - 0.55 * s - 1.35 * s * s * s)
		pts.append(Vector3(q.x, _g(q) + lift, q.y))
		rad.append(thick * (lerpf(1.0, 0.2, pow(s, 0.75)) + 0.55 * pow(1.0 - s, 4.0)))
	_tube(parent, pts, rad, Color(0.30, 0.23, 0.16), seed_i, 7, 0.35)
	if depth == 0 and length > 1.6:
		var k := int(n * rng.randf_range(0.35, 0.55))
		var fb := Vector2(pts[k].x, pts[k].z)
		var fyaw := yaw + rng.randf_range(0.5, 0.85) * (1.0 if rng.randf() < 0.5 else -1.0)
		_root_run(parent, fb, fyaw, length * rng.randf_range(0.45, 0.65), thick * 0.55, seed_i + 91, 1)


func _roots_natural(poi: Dictionary) -> Node3D:
	var py := _pos_yaw(poi)
	var holder := _world_root(poi)
	var rad := float(poi.get("r", 1.2))
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(String(poi["id"]).hash()) + 5
	var n := rng.randi_range(5, 7)
	var y0 := rng.randf() * TAU
	for i in n:
		var yaw := y0 + TAU * (float(i) + rng.randf_range(-0.28, 0.28)) / float(n)
		var length := rad * rng.randf_range(1.0, 1.9)
		var thick := rng.randf_range(0.13, 0.26)
		_root_run(holder, py["p"], yaw, length, thick, absi(String(poi["id"]).hash()) + i * 13)
	_fp(String(poi["id"]), py["p"], rad + 1.0)
	return holder



func _footprints(poi: Dictionary) -> Node3D:
	var py := _pos_yaw(poi)
	var holder := _world_root(poi)
	var n := int(poi.get("n", 3))
	var t: Vector2 = (py["at"] as Dictionary)["tan"]
	var col := Color(0.20, 0.13, 0.08)
	for i in n:
		var p: Vector2 = py["p"] + t * float(i) * 0.9 + BPLib.right_of(t) * (0.28 if i % 2 == 0 else -0.28)
		var h := holder
		var pad := cyl(h, 0.13, 0.02, Vector3(p.x, _g(p) + 0.03, p.y), col)
		pad.scale = Vector3(1.0, 1.0, 1.35)
		for k in 4:
			var a := (float(k) - 1.5) * 0.45
			var tp := p + Vector2(sin(a), cos(a) * -1.0).rotated(atan2(t.x, t.y)) * 0.2
			cyl(h, 0.045, 0.02, Vector3(tp.x, _g(tp) + 0.03, tp.y), col)
	return holder


func _offerings(poi: Dictionary) -> Node3D:
	var py := _pos_yaw(poi)
	var r := _root(poi, py["p"], py["yaw"])
	box(r, Vector3(0.62, 0.32, 0.5), Vector3(0, 0.12, 0), COL_STONE.lerp(COL_STONE_MOSS, 0.5), Vector3(0, 12, 0))
	var cols := [Color(0.9, 0.9, 0.85), Color(0.78, 0.2, 0.14), Color(0.9, 0.62, 0.18), Color(0.85, 0.8, 0.7)]
	for i in 5:
		var ox := _rng.randf_range(-0.22, 0.22)
		var oz := _rng.randf_range(-0.18, 0.18)
		box(r, Vector3(0.1, 0.09, 0.1), Vector3(ox, 0.32, oz), cols[i % cols.size()], Vector3(0, _rng.randf() * 90.0, 0))
	cyl(r, 0.05, 0.07, Vector3(0.18, 0.32, 0.12), Color(0.82, 0.78, 0.7))
	for i in 3:
		var a := _rng.randf() * TAU
		box(r, Vector3(0.09, 0.07, 0.09), Vector3(sin(a) * 0.55, 0.0, cos(a) * 0.45), cols[(i + 1) % cols.size()], Vector3(0, a * 20.0, 0))
	var sb := body(r)
	col_box(sb, Vector3(0.62, 0.45, 0.5), Vector3(0, 0.2, 0), Vector3(0, 12, 0))
	_fp(String(poi["id"]), py["p"], 1.0)
	return r


func _bones(poi: Dictionary) -> Node3D:
	var py := _pos_yaw(poi)
	var r := _root(poi, py["p"], py["yaw"])
	var bone := Color(0.88, 0.85, 0.76)
	for i in 4:
		var a := _rng.randf() * TAU
		var m := cyl(r, 0.025, 0.4, Vector3(sin(a) * 0.3, 0.04, cos(a) * 0.3), bone, Vector3(90, a * 57.3, 0))
		m.scale = Vector3(1, 1, 1)
	mi(r, _sph_mesh(0.09, 0.8), bone, Vector3(0.05, 0.08, 0.0))
	for i in 3:
		var a := _rng.randf() * TAU
		box(r, Vector3(0.04, 0.003, 0.2), Vector3(sin(a) * 0.5, 0.02, cos(a) * 0.5), Color(0.85, 0.82, 0.78), Vector3(0, a * 57.3, 10))
	_fp(String(poi["id"]), py["p"], 0.8)
	return r


func _mushrooms(poi: Dictionary) -> Node3D:
	var py := _pos_yaw(poi)
	var r := _root(poi, py["p"], py["yaw"])
	var caps := [Color(0.52, 0.30, 0.74), Color(0.25, 0.62, 0.66), Color(0.62, 0.30, 0.62)]
	for i in 5:
		var ox := _rng.randf_range(-0.3, 0.3)
		var oz := _rng.randf_range(-0.3, 0.3)
		var hh := _rng.randf_range(0.1, 0.2)
		cyl(r, 0.018, hh, Vector3(ox, hh * 0.5, oz), Color(0.88, 0.86, 0.8))
		var cap := mi(r, _sph_mesh(0.065, 0.6), caps[i % caps.size()], Vector3(ox, hh, oz))
		cap.material_override = _glow_mat(caps[i % caps.size()])
	_fp(String(poi["id"]), py["p"], 0.7)
	return r


func _glow_mat(c: Color) -> StandardMaterial3D:
	var key := "glow%.2f,%.2f,%.2f" % [c.r, c.g, c.b]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 0.35
	m.roughness = 0.5
	_mats[key] = m
	return m


func _broken_branch(poi: Dictionary) -> Node3D:
	var py := _pos_yaw(poi)
	var holder := _world_root(poi)
	var yaw: float = py["yaw"] + _rng.randf_range(-0.6, 0.6)
	_beam_on_ground(holder, py["p"], yaw, 2.4, 0.05, Color(0.50, 0.40, 0.28))
	_beam_on_ground(holder, py["p"] + Vector2(sin(yaw + 0.9), cos(yaw + 0.9)) * 0.7, yaw + 0.9, 1.3, 0.035, Color(0.50, 0.40, 0.28))
	var tip := mi(holder, _sph_mesh(0.05, 0.6), Color(0.78, 0.68, 0.5), Vector3(py["p"].x, _g(py["p"]) + 0.07, py["p"].y))
	tip.name = "FreshBreak"
	_fp(String(poi["id"]), py["p"], 1.3)
	return holder


## 不規則石階：一塊塊石板貼著「實際地形」鋪（頂面＝前後緣較高處的地面 + 7 cm），不是照路中心線的設計高度。
## （設計高 y_at 在溪切口對岸等處與實際地形差 1~2 m，照它鋪會變成懸空／擋路的牆——驗證器抓到過。）
func _stone_steps(poi: Dictionary) -> Node3D:
	var at: Dictionary = poi["at"]
	var poly: BPLib.Poly = lib.main
	var s0 := 0.0
	var s1 := 0.0
	if at.has("br"):
		poly = lib.branches[String(at["br"])]
		s0 = float(at["u0"]) * poly.length
		s1 = float(at["u1"]) * poly.length
	else:
		s0 = lib.st_s(String(at["st"])) + float(at["ds0"])
		s1 = lib.st_s(String(at["st"])) + float(at["ds1"])
	var width := float(poi.get("width", 2.2))
	var holder := _world_root(poi)
	var sb := body(holder)
	var n := maxi(int(ceil(absf(s1 - s0) / 0.8)), 3)
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(String(poi["id"]).hash())
	var tread := absf(s1 - s0) / float(n)
	for k in n:
		var u := (float(k) + 0.5) / float(n)
		var s := lerpf(s0, s1, u)
		var t := poly.tan_at(s)
		var c := poly.pos_at(s)
		var depth := tread * rng.randf_range(0.82, 0.96)
		var w := width * rng.randf_range(0.92, 1.12)
		var yaw := BPLib.yaw_of(t) + deg_to_rad(rng.randf_range(-5.0, 5.0))
		var gf := _g(c + t * depth * 0.5)
		var gb := _g(c - t * depth * 0.5)
		var top := maxf(gf, gb) + 0.07
		var low := minf(gf, gb) - 0.3
		var hgt := top - low
		var node := Node3D.new()
		node.name = "Step%d" % k
		node.position = Vector3(c.x + BPLib.right_of(t).x * rng.randf_range(-0.12, 0.12), low + hgt * 0.5, c.y + BPLib.right_of(t).y * rng.randf_range(-0.12, 0.12))
		node.rotation.y = yaw
		holder.add_child(node)
		box(node, Vector3(w, hgt, depth), Vector3.ZERO, COL_STONE.lerp(COL_STONE_MOSS, rng.randf_range(0.0, 0.35)))
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(w, hgt, depth)
		cs.shape = bs
		cs.transform = Transform3D(Basis.from_euler(Vector3(0, yaw, 0)), node.position)
		sb.add_child(cs)
	_fp(String(poi["id"]), poly.pos_at((s0 + s1) * 0.5), absf(s1 - s0) * 0.5 + 1.0)
	holder.set_meta("bp_steps", n)
	return holder


func _bridge(poi: Dictionary) -> Node3D:
	var at := lib.resolve(poi["at"])
	var holder := _world_root(poi)
	var len := float(poi.get("length", 8.6))
	var wid := float(poi.get("width", 2.8))
	var rail_h := float(poi.get("rail_h", 0.95))
	var s := float(at["s"])
	var yd := lib.main.y_at(s)                       # 橋面高＝主路在此的路面高（flats 保證兩端同高）
	# 量身定長：沿路掃出「地形比橋面低 0.25 m 以上」的範圍（溪切口），橋兩端各留 0.8 m 落在接近橋面高的地上。
	# （固定長度會讓一端懸在比橋面低 ~1 m 的坡上 → 玩家 step_height 0.35 上不了橋——驗證器 ground.main_steps 抓到的。）
	var lo := 0.0
	var hi := 0.0
	var found := false
	var k := -14.0
	while k <= 14.0:
		var pp := lib.main.pos_at(s + k)
		if lib.h_at(pp.x, pp.y) < yd - 0.25:
			if not found:
				lo = k
				found = true
			hi = k
		k += 0.25
	if found:
		len = clampf(maxf(len, (hi - lo) + 1.6), 6.0, 15.0)
		s += (lo + hi) * 0.5
	var t := lib.main.tan_at(s)
	var rv := BPLib.right_of(t)
	var c := lib.main.pos_at(s)
	var yaw := BPLib.yaw_of(t)
	var root := Node3D.new()
	root.name = "Deck"
	root.position = Vector3(c.x, yd, c.y)
	root.rotation.y = yaw
	holder.add_child(root)
	var sb := body(root)
	box(root, Vector3(wid, 0.16, len), Vector3(0, -0.08, 0), COL_WOOD)
	col_box(sb, Vector3(wid, 0.2, len), Vector3(0, -0.1, 0))
	for sx in [-1.0, 1.0]:
		box(root, Vector3(0.2, 0.36, len + 0.4), Vector3(sx * (wid * 0.5 - 0.2), -0.34, 0), COL_WOOD_DARK)
		var n := int(ceil(len / 2.15)) + 1
		for i in n:
			var z := lerpf(-len * 0.5 + 0.1, len * 0.5 - 0.1, float(i) / float(n - 1))
			box(root, Vector3(0.14, rail_h + 0.1, 0.14), Vector3(sx * wid * 0.5, rail_h * 0.5, z), COL_WOOD_DARK)
		box(root, Vector3(0.1, 0.1, len), Vector3(sx * wid * 0.5, rail_h, 0), COL_WOOD_OLD)
		box(root, Vector3(0.06, 0.08, len), Vector3(sx * wid * 0.5, rail_h * 0.5, 0), COL_WOOD_OLD)
		col_box(sb, Vector3(0.12, rail_h, len), Vector3(sx * wid * 0.5, rail_h * 0.5, 0))
	# 橋台（兩端石座）
	for sz in [-1.0, 1.0]:
		box(root, Vector3(wid + 0.8, 0.7, 1.0), Vector3(0, -0.5, sz * (len * 0.5 + 0.2)), COL_STONE.darkened(0.1))
	holder.set_meta("bp_deck_y", yd)
	holder.set_meta("bp_len", len)
	holder.set_meta("bp_center", Vector3(c.x, yd, c.y))
	holder.set_meta("bp_yaw", yaw)
	_fp(String(poi["id"]), c, len * 0.5 + 1.0)
	return holder


func _stepping_stones(poi: Dictionary) -> Node3D:
	var holder := _world_root(poi)
	var at: Dictionary = poi["at"]
	var center: Vector2
	var dir2: Vector2
	var sid := ""
	if at.has("cross_branch"):
		var rr := lib.resolve(at)
		center = rr["p"]
		dir2 = rr["tan"]
		sid = String(at["with"])
	else:
		var rr2 := lib.resolve(at)
		center = rr2["p"]
		dir2 = BPLib.right_of(rr2["tan"])              # 垂直溪向＝橫過溪
		sid = String(at["stream"])
	var n := int(poi.get("count", 5))
	var sb := body(holder)
	var spacing := 1.15
	for i in n:
		var u := (float(i) - float(n - 1) * 0.5) * spacing
		var p := center + dir2 * u + BPLib.right_of(dir2) * _rng.randf_range(-0.2, 0.2)
		var sq := lib.streams[sid] as BPLib.Poly
		var qs := sq.q(p)
		var wl := sq.bed_at(qs["s"]) + float(lib._stream_def(sid)["water_depth"])
		var rad := _rng.randf_range(0.42, 0.58)
		var top := wl + 0.22
		var bot := sq.bed_at(qs["s"]) - 0.3
		var hh := top - bot
		var stone := cyl(holder, rad, hh, Vector3(p.x, bot + hh * 0.5, p.y), COL_STONE.lerp(COL_STONE_MOSS, 0.4), Vector3.ZERO, rad * 0.85)
		stone.name = "Stone%d" % i
		col_cyl(sb, rad, hh, Vector3(p.x, bot + hh * 0.5, p.y))
	_fp(String(poi["id"]), center, 3.5)
	return holder


func _cascade(poi: Dictionary) -> Node3D:
	var at := lib.resolve(poi["at"])
	var sid := String(poi["at"]["stream"])
	var st := lib.streams[sid] as BPLib.Poly
	var s: float = at["s"]
	var holder := _world_root(poi)
	var a := st.pos_at(s - 3.0)
	var b := st.pos_at(s + 3.0)
	var ya := st.bed_at(s - 3.0) + float(lib._stream_def(sid)["water_depth"]) + 0.03
	var yb := st.bed_at(s + 3.0) + float(lib._stream_def(sid)["water_depth"]) + 0.03
	var w := float(poi.get("w", 4.0))
	var strip := beam(holder, Vector3(a.x, ya, a.y), Vector3(b.x, yb, b.y), Vector2(w, 0.04), Color(0.92, 0.96, 0.98))
	strip.material_override = mat(Color(0.92, 0.96, 0.98), 0.3, 0.7)
	_fp(String(poi["id"]), at["p"], 3.0)
	return holder


func _locked_gate(poi: Dictionary) -> Node3D:
	var at := lib.resolve(poi["at"])
	var yaw: float = at["yaw"]
	var r := _root(poi, at["p"], yaw)
	var sb := body(r)
	for sx in [-1.0, 1.0]:
		box(r, Vector3(0.2, 1.9, 0.2), Vector3(sx * 1.05, 0.95, 0), COL_WOOD_DARK)
	box(r, Vector3(2.3, 0.2, 0.22), Vector3(0, 1.9, 0), COL_WOOD_DARK)
	box(r, Vector3(1.9, 1.4, 0.1), Vector3(0, 0.85, 0), COL_WOOD)
	box(r, Vector3(1.9, 0.08, 0.12), Vector3(0, 0.45, 0), COL_WOOD_DARK)
	box(r, Vector3(1.9, 0.08, 0.12), Vector3(0, 1.25, 0), COL_WOOD_DARK)
	box(r, Vector3(0.18, 0.22, 0.12), Vector3(0.7, 0.9, -0.1), COL_BLACK)
	col_box(sb, Vector3(2.3, 1.9, 0.3), Vector3(0, 0.95, 0))
	r.set_meta("bp_reserved", "return_to_village_shortcut")
	_fp(String(poi["id"]), at["p"], 2.0)
	return r


func _stone_pillar(poi: Dictionary) -> Node3D:
	var py := _pos_yaw(poi)
	var r := _root(poi, py["p"], py["yaw"])
	var h := float(poi.get("h", 2.4))
	var broken := bool(poi.get("broken", false))
	box(r, Vector3(0.56, h, 0.56), Vector3(0, h * 0.5 - 0.1, 0), COL_STONE.lerp(COL_STONE_MOSS, 0.5), Vector3(0, 0, 1.5))
	var sb := body(r)
	col_box(sb, Vector3(0.6, h, 0.6), Vector3(0, h * 0.5 - 0.1, 0))
	if broken:
		# 折斷的石柱（規格：斷裂或風化石柱）：斜切的斷口、倒下的柱段、碎塊
		box(r, Vector3(0.5, 0.34, 0.5), Vector3(0.06, h - 0.02, 0), COL_STONE.darkened(0.12), Vector3(8, 0, 21))
		box(r, Vector3(0.58, 0.5, 1.5), Vector3(1.0, 0.22, 0.5), COL_STONE.lerp(COL_STONE_MOSS, 0.6), Vector3(0, 28, 6))
		col_box(sb, Vector3(0.6, 0.5, 1.5), Vector3(1.0, 0.22, 0.5), Vector3(0, 28, 6))
		box(r, Vector3(0.3, 0.22, 0.3), Vector3(-0.7, 0.1, -0.5), COL_STONE.darkened(0.2), Vector3(12, 40, 9))
	else:
		box(r, Vector3(0.7, 0.16, 0.7), Vector3(0, h - 0.05, 0), COL_STONE)
		box(r, Vector3(0.1, 0.6, 0.02), Vector3(0, h * 0.5, -0.29), Color(0.6, 0.12, 0.08))
	_fp(String(poi["id"]), py["p"], 1.0)
	anchors[String(poi["id"])] = {"p": r.position, "h": h * 0.95, "r": 0.3}
	return r


func _farm_patch(poi: Dictionary) -> Node3D:
	if poi.has("model"):
		return load(S01_ARCH).field(self, poi)
	var py := _pos_yaw(poi)
	var holder := _world_root(poi)
	var hx := float(poi.get("hx", 10.0))
	var hz := float(poi.get("hz", 7.0))
	var ridges := int(poi.get("ridges", 5))
	var t: Vector2 = (py["at"] as Dictionary)["tan"]
	var rv := BPLib.right_of(t)
	var yaw := BPLib.yaw_of(t)
	for i in ridges:
		var u := lerpf(-hz + 1.0, hz - 1.0, float(i) / float(maxi(ridges - 1, 1)))
		var p: Vector2 = py["p"] + t * u
		var node := Node3D.new()
		node.position = Vector3(p.x, _g(p) + 0.1, p.y)
		node.rotation.y = yaw
		holder.add_child(node)
		box(node, Vector3(hx * 1.8, 0.3, 0.7), Vector3.ZERO, Color(0.30, 0.22, 0.14))
		box(node, Vector3(hx * 1.7, 0.06, 0.4), Vector3(0, 0.17, 0), Color(0.36, 0.5, 0.2))
	_fp(String(poi["id"]), py["p"], maxf(hx, hz) + 3.0)
	return holder


func _firewood(poi: Dictionary) -> Node3D:
	var py := _pos_yaw(poi)
	var r := _root(poi, py["p"], py["yaw"])
	var sb := body(r)
	for row in 3:
		for i in 4 - row:
			cyl(r, 0.09, 1.0, Vector3((float(i) - float(3 - row) * 0.5) * 0.19, 0.1 + row * 0.17, 0), Color(0.42, 0.30, 0.18), Vector3(90, 0, 0))
	col_box(sb, Vector3(0.9, 0.55, 1.0), Vector3(0, 0.28, 0))
	_fp(String(poi["id"]), py["p"], 1.2)
	return r


func _basket(poi: Dictionary) -> Node3D:
	var py := _pos_yaw(poi)
	var r := _root(poi, py["p"], py["yaw"])
	cyl(r, 0.3, 0.42, Vector3(0, 0.21, 0), COL_STRAW, Vector3(4, 0, 6), 0.24)
	cyl(r, 0.28, 0.05, Vector3(0, 0.44, 0), Color(0.18, 0.12, 0.08))
	_fp(String(poi["id"]), py["p"], 0.7)
	return r


func _shimenawa(poi: Dictionary) -> Node3D:
	var ends: Array = poi["between"]
	var a: Dictionary = anchors.get(String(ends[0]), {})
	var b: Dictionary = anchors.get(String(ends[1]), {})
	if a.is_empty() or b.is_empty():
		push_warning("注連繩 %s 找不到端點 %s / %s" % [poi["id"], ends[0], ends[1]])
		return null
	var holder := _world_root(poi)
	var hh := float(poi.get("h", 2.4))
	var pa: Vector3 = a["p"]
	var pb: Vector3 = b["p"]
	var dir_h := Vector3(pb.x - pa.x, 0.0, pb.z - pa.z).normalized()
	pa += dir_h * float(a.get("r", 0.0))
	pb -= dir_h * float(b.get("r", 0.0))
	pa.y += minf(hh, float(a["h"]) * 0.9)
	pb.y += minf(hh, float(b["h"]) * 0.9)
	var segs := 14
	var prev := pa
	var wea := bool(poi.get("weathered", false))      # V1.2：出口封印的繩——曬褪的稻草色、較細、紙垂只留三片（S03 的 shimenawa_north 維持 V0.1 原樣）
	for i in range(1, segs + 1):
		var u := float(i) / float(segs)
		var p := pa.lerp(pb, u)
		p.y -= sin(u * PI) * (0.45 if not wea else 0.62)  # 下垂
		if wea:
			beam(holder, prev, p, Vector2(0.105, 0.105), Color(0.47, 0.40, 0.27) if i % 2 == 0 else Color(0.40, 0.33, 0.22))
			if i == 4 or i == 8 or i == 11:
				box(holder, Vector3(0.10, 0.30, 0.010), p + Vector3(0.0, -0.22, 0.0), Color(0.74, 0.72, 0.66), Vector3(0, 0, 8.0 * (1 if i != 8 else -1)))
		else:
			beam(holder, prev, p, Vector2(0.14, 0.14), Color(0.82, 0.74, 0.5))
			if i % 3 == 0 and i < segs:
				for k in 2:
					box(holder, Vector3(0.14, 0.34, 0.012), p + Vector3(0.0, -0.2 - 0.12 * k, 0.0), COL_PAPER, Vector3(0, 0, 12.0 * (1 if k == 0 else -1)))
		prev = p
	return holder

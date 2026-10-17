extends RefCounted
## 獸道全區美術完成（S01 收尾＋S02／S03 製作，2026-10-17 授權）：V0.1 白模道具換成 Blender 資產（assets/beast_path/s01_kit/src/build_bp_props.py＋build_s01_*）。
## 做法＝「換皮」：prop_builder 照原本程式建出節點（碰撞、腳印、錨點、meta、階梯／橋面高度全部不變），
## 這裡只把它的可見網格（盒子／圓柱）拿掉，換上資產網格。玩法幾何與功能標記因此與原版逐一相同。
## 只對 layout 中有 "skin": true 的 POI 生效；S04 的 POI 一律不處理（V1.3 保護）。
const S01Arch := preload("res://tools/beast_path/s01_arch.gd")
const Dress := preload("res://tools/beast_path/s01_dress.gd")
const BPLib := preload("res://tools/beast_path/bp_lib.gd")

static var _wood := {}
static var _paint: ShaderMaterial = null
static var _wmesh := {}


static var _bb := {}


## 資產網格的 AABB（Godot 座標）
static func _aabb(asset: String) -> AABB:
	if not _bb.has(asset):
		var V: PackedVector3Array = Dress.glb(asset)["V"]
		var b := AABB(V[0], Vector3.ZERO)
		for v in V:
			b = b.expand(v)
		_bb[asset] = b
	return _bb[asset]


static func _paint_mat() -> ShaderMaterial:
	if _paint == null:
		_paint = S01Arch.paint_mat()
	return _paint


static func _wood_mat(bark: String) -> ShaderMaterial:
	if not _wood.has(bark):
		_wood[bark] = Dress.wood_mat(bark)
	return _wood[bark]


## 木（倒木／殘株／露根／枝）：同 S01 林床的 s01k_wood＋VB 樹皮（要切線）
static func _kit_wood_mesh(name: String) -> ArrayMesh:
	if _wmesh.has(name):
		return _wmesh[name]
	var a := Dress.glb(name)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = a["V"]
	arr[Mesh.ARRAY_NORMAL] = a["N"]
	arr[Mesh.ARRAY_COLOR] = a["C"]
	arr[Mesh.ARRAY_TEX_UV] = a["UV"]
	arr[Mesh.ARRAY_INDEX] = a["I"]
	var m0 := ArrayMesh.new()
	m0.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var st := SurfaceTool.new()
	st.create_from(m0, 0)
	st.generate_tangents()
	var m := st.commit()
	m.surface_set_material(0, _wood_mat("dead" if not name.contains("root") else "hackberry"))
	_wmesh[name] = m
	return m


static func _paint_mesh(name: String, recolor: Callable = Callable()) -> ArrayMesh:
	var key := name + ("" if not recolor.is_valid() else "#r")
	if _wmesh.has(key):
		return _wmesh[key]
	var cols := PackedColorArray()
	if recolor.is_valid():
		cols = (Dress.glb(name)["C"] as PackedColorArray).duplicate()
		for k in cols.size():
			cols[k] = recolor.call(cols[k])
	var m := S01Arch._arr_mesh(name, _paint_mat(), cols)
	_wmesh[key] = m
	return m


## n 相對 root 的變換（root 自己不算）
static func _rel(root: Node, n: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var c := n
	while c != null and c != root:
		if c is Node3D:
			xf = (c as Node3D).transform * xf
		c = c.get_parent()
	return xf


## 拿掉 root 底下所有可見的白模網格（碰撞形狀、空節點、meta 保留）；回傳 [{name, parent, xf(相對 parent), mesh}]
static func _strip(root: Node3D) -> Array:
	var out := []
	var stack: Array = [root]
	var found: Array = []
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			if c is MeshInstance3D:
				found.append(c)
			elif not (c is CollisionObject3D):
				stack.append(c)
	for c: MeshInstance3D in found:
		out.append({"name": String(c.name), "parent": c.get_parent(), "xf": c.transform, "mesh": c.mesh})
		c.get_parent().remove_child(c)
		c.free()
	return out


static func _add(parent: Node, name: String, mesh: Mesh, xf: Transform3D, ground_y := NAN) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = mesh
	mi.transform = xf
	if not is_nan(ground_y):
		mi.set_instance_shader_parameter("ground_y", ground_y)
	parent.add_child(mi)
	return mi


## 加工石／自然石（頂點色依世界位置算苔與腳邊）：world＝這個網格的世界變換（含縮放）
static func _stone(pb, parent: Node, name: String, asset: String, local: Transform3D, world: Transform3D, moss: float, sd: int, tone := 1.0, interior: Callable = Callable()) -> MeshInstance3D:
	var st: MeshInstance3D = S01Arch._stone(pb, asset, world, moss, sd, interior, tone)
	st.name = name
	st.transform = local
	parent.add_child(st)
	return st


## 自然石（踏み石、飛び石、橋台）：S01 林床的天然岩材質 s01k_rock＋同一套頂點色規則（苔、腳邊泥、凹處）
static var _rmat: ShaderMaterial = null


static func _rock(pb, parent: Node, name: String, asset: String, local: Transform3D, world: Transform3D, moss: float, sd: int) -> MeshInstance3D:
	if _rmat == null:
		_rmat = Dress.rock_mat()
	var a := Dress.glb(asset)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = a["V"]
	arr[Mesh.ARRAY_NORMAL] = a["N"]
	arr[Mesh.ARRAY_COLOR] = Dress.rock_colors(pb.lib, a["V"], a["N"], world, moss, sd, 0.86)
	arr[Mesh.ARRAY_INDEX] = a["I"]
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.surface_set_material(0, _rmat)
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = m
	mi.transform = local
	parent.add_child(mi)
	return mi


static func _xf_of(n: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var c := n
	while c != null:
		if c is Node3D:
			xf = (c as Node3D).transform * xf
		c = c.get_parent()
	return xf


# ================================================================= 入口
static func skin(pb, poi: Dictionary, n: Node3D) -> Node3D:
	if n == null:
		return n
	var lib = pb.lib
	var kind := String(poi["kind"])
	var sd := absi(String(poi["id"]).hash()) % 100000
	var rng := RandomNumberGenerator.new()
	rng.seed = sd + 17
	match kind:
		"stone_steps": _steps(pb, poi, n, rng, sd)
		"bridge": _bridge(pb, poi, n, sd)
		"stepping_stones": _ford(pb, poi, n, rng, sd)
		"fence_run": _fence(pb, poi, n, rng)
		"signpost": _signpost(pb, poi, n)
		"stone_marker": _marker(pb, poi, n, sd)
		"shrine_small": _shrine(pb, poi, n, rng, sd)
		"lantern": _lantern(pb, poi, n, sd)
		"locked_gate": _gate(pb, poi, n)
		"offerings": _offerings(pb, poi, n, sd)
		"torii": _torii(pb, poi, n, sd)
		"log": _log(pb, poi, n)
		"stump": _stump(pb, poi, n, rng)
		"roots": _roots(pb, poi, n, rng)
		"broken_branch": _branch(pb, poi, n, rng)
		"basket": _basket(pb, poi, n)
		"rock", "rock_scatter": _rocks(pb, poi, n, rng)
		"hut": _hut(pb, poi, n)
		"firewood": _firewood(pb, poi, n)
		_:
			return n
	n.set_meta("bp_skin", "build_bp_props")
	return n


# ================================================================= 坂道の土留め階段（2026-10-17 最終整合）
## 實測（steps_descent／steps_bridge_n／steps_rootstep／steps_bamboo）：都在 4–6° 的緩坡上，每段只升 5–10 cm——
## 環境上的用途＝「土留め丸太階段」（林道的侵蝕防止段），不是石板路。原本的白模箱＝踏面，碰撞箱一律不動。
## 外觀：踏面＝踩實的土（頂面＝碰撞箱頂，四周裙邊往下貼地形）、下坡側的蹴込み＝橫放的丸太（頂比踏面高 2 cm）＋兩根木杭。
const STEP_SOIL := "res://assets/beast_path/s01_kit/mat/s01k_soil.gdshader"
const V2G := "res://assets/village_v2/_matlib/ground/"
static var _soil: ShaderMaterial = null


static func _soil_mat() -> ShaderMaterial:
	if _soil == null:
		_soil = ShaderMaterial.new()
		_soil.shader = load(STEP_SOIL)
		_soil.set_shader_parameter("albedo_arr", load(V2G + "V2G_albedo.jpg"))
		_soil.set_shader_parameter("nrh_arr", load(V2G + "V2G_nrh.jpg"))
		_soil.set_shader_parameter("noise_tex", load(V2G + "V2G_noise.png"))
		_soil.set_shader_parameter("dry_tint", Color(1.08, 1.03, 0.97))      # a1 審圖：比路面暗、偏暖 → 提亮、偏灰（踩實的乾土）
		_soil.set_shader_parameter("ground_k", 0.28)
	return _soil


## 踏面（整段一個網格，a2 審圖：逐段各自的裙邊在兩側排成鋸齒、像一節節平台）：
## 每段的頂面＝碰撞箱頂（step 節點只有 yaw → 頂面的世界高＝原點 y＋top）；兩側裙邊沿整段連續、寬度沿路緩變，外緣貼地形下 3 cm；
## 段與段之間的高差面藏在丸太後；兩端（上坡端／下坡端）各一條短裙邊。座標＝holder（世界，無變換）。
static func _tread_run(pb, info: Array, rng: RandomNumberGenerator) -> ArrayMesh:
	var nzz := FastNoiseLite.new()
	nzz.seed = rng.randi() % 100000
	nzz.frequency = 0.35
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var NX := 6
	var NZ := 3
	var g := func(p: Vector3) -> float:
		return float(pb._g(Vector2(p.x, p.z)))
	var col := func(p: Vector3, b: float) -> Color:
		return Color(0.05 + 0.12 * (0.5 + 0.5 * nzz.get_noise_2d(p.x * 4.0, p.z * 4.0)), 0.45, b, 0.5 + 0.5 * nzz.get_noise_2d(p.x * 6.0 + 3.0, p.z * 6.0))
	var tri := func(a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color) -> void:
		# 一律讓面朝上（法線 y＞0）
		if (b - a).cross(c - a).y < 0.0:
			var t := b
			b = c
			c = t
			var tc := cb
			cb = cc
			cc = tc
		st.set_color(ca); st.add_vertex(a)
		st.set_color(cb); st.add_vertex(b)
		st.set_color(cc); st.add_vertex(c)
	var sides := {-1.0: [], 1.0: []}         # 每側：[內緣點, 往外方向]，沿行進方向排序
	var dist := 0.0
	for k in info.size():
		var it: Dictionary = info[k]
		var wx: Transform3D = it["wx"]
		var W: float = it["W"]
		var D: float = it["D"]
		var top: float = it["top"]
		var rows: Array = []
		for iz in NZ + 1:
			var row: Array = []
			var zz := lerpf(D * 0.5, -D * 0.5, float(iz) / NZ)          # +Z（後）→ −Z（前）＝沿行進方向
			for ix in NX + 1:
				var x := lerpf(-W * 0.5, W * 0.5, float(ix) / NX)
				var e := maxf(absf(x) / (W * 0.5), absf(zz) / (D * 0.5))
				row.append(wx * Vector3(x, top - 0.006 * (1.0 - e), zz))
			rows.append(row)
		for iz in NZ:
			for ix in NX:
				var a: Vector3 = rows[iz][ix]
				var b: Vector3 = rows[iz][ix + 1]
				var c: Vector3 = rows[iz + 1][ix + 1]
				var d: Vector3 = rows[iz + 1][ix]
				tri.call(a, b, c, col.call(a, 0.0), col.call(b, 0.0), col.call(c, 0.0))
				tri.call(a, c, d, col.call(a, 0.0), col.call(c, 0.0), col.call(d, 0.0))
		var xdir := (wx.basis.x).normalized()
		for iz in NZ + 1:
			(sides[-1.0] as Array).append([rows[iz][0], -xdir])
			(sides[1.0] as Array).append([rows[iz][NX], xdir])
		it["rows"] = rows
	# 兩側裙邊（連續）
	for sgn in [-1.0, 1.0]:
		var pts: Array = sides[sgn]
		var outs: Array = []
		for j in pts.size():
			var p: Vector3 = pts[j][0]
			var od: Vector3 = pts[j][1]
			var w := 0.5 + 0.18 * nzz.get_noise_2d(p.x * 0.8 + 50.0 * sgn, p.z * 0.8)
			var q := p + od * w
			q.y = minf(g.call(q) - 0.03, p.y - 0.03)
			outs.append(q)
		for j in pts.size() - 1:
			var a: Vector3 = pts[j][0]
			var b: Vector3 = pts[j + 1][0]
			var c: Vector3 = outs[j + 1]
			var d: Vector3 = outs[j]
			var ca: Color = col.call(a, 0.12)
			var cb: Color = col.call(b, 0.12)
			var cc: Color = col.call(c, 0.45)
			var cd: Color = col.call(d, 0.45)
			tri.call(a, b, c, ca, cb, cc)
			tri.call(a, c, d, ca, cc, cd)
	# 段與段之間：前一段的前緣列 → 下一段的後緣列（高差面，在丸太後面）
	for k in info.size() - 1:
		var r0: Array = (info[k]["rows"] as Array)[NZ]
		var r1: Array = (info[k + 1]["rows"] as Array)[0]
		for ix in NX:
			var a: Vector3 = r0[ix]
			var b: Vector3 = r0[ix + 1]
			var c: Vector3 = r1[ix + 1]
			var d: Vector3 = r1[ix]
			st.set_color(col.call(a, 0.0)); st.add_vertex(a)
			st.set_color(col.call(c, 0.0)); st.add_vertex(c)
			st.set_color(col.call(b, 0.0)); st.add_vertex(b)
			st.set_color(col.call(a, 0.0)); st.add_vertex(a)
			st.set_color(col.call(d, 0.0)); st.add_vertex(d)
			st.set_color(col.call(c, 0.0)); st.add_vertex(c)
	# 兩端短裙邊：第一段的後緣、最後一段的前緣，往外 0.35 m 到地形下
	for e in [[0, 0, 1.0], [info.size() - 1, NZ, -1.0]]:
		var it2: Dictionary = info[int(e[0])]
		var wx2: Transform3D = it2["wx"]
		var zd: Vector3 = (wx2.basis.z).normalized() * float(e[2])
		var row2: Array = (it2["rows"] as Array)[int(e[1])]
		for ix in NX:
			var a: Vector3 = row2[ix]
			var b: Vector3 = row2[ix + 1]
			var c: Vector3 = b + zd * 0.35
			var d: Vector3 = a + zd * 0.35
			c.y = minf(g.call(c) - 0.03, b.y - 0.03)
			d.y = minf(g.call(d) - 0.03, a.y - 0.03)
			tri.call(a, b, c, col.call(a, 0.1), col.call(b, 0.1), col.call(c, 0.4))
			tri.call(a, c, d, col.call(a, 0.1), col.call(c, 0.4), col.call(d, 0.4))
	st.index()
	st.generate_normals()
	var m := st.commit()
	m.surface_set_material(0, _soil_mat())
	return m


static func _steps(pb, poi: Dictionary, n: Node3D, rng: RandomNumberGenerator, sd: int) -> void:
	var old := _strip(n)
	var i := 0
	var post := _paint_mesh("bp_fence_post_a")
	var info: Array = []
	for o: Dictionary in old:
		var step: Node3D = o["parent"]
		var sz: Vector3 = (o["mesh"] as BoxMesh).size
		var top := sz.y * 0.5                          # 相對 step 節點＝碰撞箱頂
		var wx := _xf_of(step)
		var pz := wx * Vector3(0, 0, sz.z * 0.5)       # 本地 +Z 端（行進方向的後方）
		var mz := wx * Vector3(0, 0, -sz.z * 0.5)      # 本地 −Z 端（行進方向）
		var g_pz: float = pb._g(Vector2(pz.x, pz.z))
		var g_mz: float = pb._g(Vector2(mz.x, mz.z))
		var down_z := sz.z * 0.5 if g_pz < g_mz else -sz.z * 0.5          # 下坡側
		info.append({"wx": wx, "W": sz.x, "D": sz.z, "top": top})
		# 蹴込み丸太：沿 X、比踏面寬（兩端壓進路肩）、頂＝踏面＋2 cm、壓在踏面下坡緣
		var la: String = "bp_step_log_c" if (i + sd) % 2 == 0 else "bp_step_log_d"
		var ab := _aabb(la)
		var sx := (sz.x + 0.45) / ab.size.x
		var lb := Basis(Vector3.UP, deg_to_rad(rng.randf_range(-2.5, 2.5)) + (PI if rng.randf() < 0.5 else 0.0)) * Basis.from_scale(Vector3(sx, 1.0, 1.0))
		var lpos := Vector3(rng.randf_range(-0.04, 0.04), top + 0.02 - ab.end.y, down_z)
		var lm := _add(step, "Riser", _kit_wood_mesh(la), Transform3D(lb, lpos))
		lm.set_instance_shader_parameter("moss_k", rng.randf_range(0.0, 0.18))     # a1 審圖：苔太多、讀成綠色橫帶
		lm.set_instance_shader_parameter("ground_y", wx.origin.y + lpos.y)
		# 木杭（下坡側，丸太外 13 cm）
		var sgn := signf(down_z)
		for sxp in [-1.0, 1.0]:
			if rng.randf() < 0.2:
				continue
			var pb2 := Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(0.65, 0.42, 0.65))
			var pp := Vector3(sxp * (sz.x * 0.5 - rng.randf_range(0.18, 0.35)), top + 0.03 - 1.25 * 0.42, down_z + sgn * 0.13)
			_add(step, "Stake%d" % int(sxp), post, Transform3D(pb2, pp), wx.origin.y + pp.y)
		i += 1
	if not info.is_empty():
		_add(n, "Tread", _tread_run(pb, info, rng), Transform3D.IDENTITY)


# ================================================================= 板橋（橋面＝原 Deck 根節點 y 0；長度沿 Deck 本地 Z）
static func _bridge(pb, poi: Dictionary, n: Node3D, sd: int) -> void:
	var deck: Node3D = n.get_node("Deck")
	_strip(n)
	var len := float(n.get_meta("bp_len"))
	var wid := float(poi.get("width", 2.8))
	var gy: float = deck.position.y
	var b := Basis(Vector3.UP, PI * 0.5) * Basis.from_scale(Vector3(len / 10.0, 1.0, wid / 2.6))
	_add(deck, "Bridge", _paint_mesh("bp_bridge_a"), Transform3D(b, Vector3.ZERO), gy - 2.0)
	for sz in [-1.0, 1.0]:
		var bb := Basis(Vector3.UP, -PI * 0.5 * sz) * Basis.from_scale(Vector3(1.0, 1.0, wid / 2.6))
		var local := Transform3D(bb, Vector3(0, 0, sz * len * 0.5))
		_rock(pb, deck, "Abut%d" % int(sz), "bp_bridge_a_abut", local, deck.transform * local, 0.6, sd + int(sz))


# ================================================================= 飛び石
static func _ford(pb, poi: Dictionary, n: Node3D, rng: RandomNumberGenerator, sd: int) -> void:
	var old := _strip(n)
	var i := 0
	for o: Dictionary in old:
		var cm: CylinderMesh = o["mesh"]
		var c: Vector3 = (o["xf"] as Transform3D).origin
		var rad := cm.bottom_radius
		var top := c.y + cm.height * 0.5
		var s := rad / 0.5
		var sy := cm.height / 0.845
		var b := Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(s, sy, s))
		var xf := Transform3D(b, Vector3(c.x, top - 0.215 * sy, c.z))
		_rock(pb, n, "Stone%d" % i, "bp_stepstone_a" if i % 2 == 0 else "bp_stepstone_b", xf, xf, 0.7, sd + i)
		i += 1


# ================================================================= 柵（杭＝原 Post 盒子的位置／傾き；横木＝原 beam）
static func _fence(pb, poi: Dictionary, n: Node3D, rng: RandomNumberGenerator) -> void:
	var old := _strip(n)
	var wea := float(poi.get("weathered", 0.2))
	var tone := func(c: Color) -> Color:
		return c.lerp(Color(c.r * 0.92, c.g * 0.92, c.b * 0.95), wea)
	var nr := 0
	for o: Dictionary in old:
		var xf: Transform3D = o["xf"]
		var sz: Vector3 = (o["mesh"] as BoxMesh).size
		if String(o["name"]).begins_with("Post"):
			var post_h := sz.y - 0.25
			var up := xf.basis.y.normalized()
			var org := xf.origin - up * (post_h * 0.5 - 0.12)
			var b := Basis(xf.basis.x.normalized(), up, xf.basis.z.normalized()) * Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(1.0, post_h / 1.25, 1.0))
			_add(n, String(o["name"]), _paint_mesh("bp_fence_post_a", tone), Transform3D(b, org), org.y)
		else:
			var dir := -xf.basis.z.normalized()
			var len := sz.z
			var b2 := xf.basis.orthonormalized() * Basis(Vector3.UP, PI * 0.5) * Basis.from_scale(Vector3(len + 0.14, 1.0 + rng.randf_range(-0.1, 0.15), 1.0 + rng.randf_range(-0.1, 0.15)))
			_add(n, "Rail%d" % nr, _paint_mesh("bp_fence_rail_a", tone), Transform3D(b2, xf.origin - dir * (len * 0.5 + 0.07)), xf.origin.y - 0.6)
			nr += 1


# ================================================================= 道標
static func _signpost(pb, poi: Dictionary, n: Node3D) -> void:
	_strip(n)
	_add(n, "Post", _paint_mesh("bp_signpost_a"), Transform3D.IDENTITY, n.position.y)
	for c in n.get_children():
		if c is Node3D and String(c.name).begins_with("Board_"):
			_add(c, "Board", _paint_mesh("bp_signpost_board"), Transform3D.IDENTITY, n.position.y)


static func _marker(pb, poi: Dictionary, n: Node3D, sd: int) -> void:
	_strip(n)
	var h := float(poi.get("h", 1.1))
	var p := Vector2(n.position.x, n.position.z)
	var yaw_f: float = pb.yaw_face_path(p) - n.rotation.y + PI          # 刻字面（資產 +Y＝Godot −Z）朝路
	var b := Basis(Vector3.UP, yaw_f) * Basis(Vector3.FORWARD, deg_to_rad(2.5)) * Basis.from_scale(Vector3(1.15, h / 1.06, 1.15))
	var local := Transform3D(b, Vector3(0, -0.04, 0))
	_stone(pb, n, "Marker", "bp_marker_a", local, n.transform * local, 0.45, sd, 0.95)


# ================================================================= 小祠
static func _shrine(pb, poi: Dictionary, n: Node3D, rng: RandomNumberGenerator, sd: int) -> void:
	_strip(n)
	var w := float(poi.get("w", 2.6))
	var d := float(poi.get("d", 2.2))
	var h := float(poi.get("h", 2.8))
	var steps := int(poi.get("steps", 3))
	var plat_h := 0.18 * float(steps) + 0.1
	var top := plat_h - 0.05
	var lb := Transform3D(Basis.from_scale(Vector3((w + 1.0) / 3.4, top / 0.42, (d + 1.0) / 3.0)), Vector3.ZERO)
	_stone(pb, n, "Base", "bp_hokora_a_base", lb, n.transform * lb, 0.5, sd, 0.92)
	var hb := Basis.from_scale(Vector3(w / 2.4, h / 2.28, d / 2.0))
	_add(n, "Hokora", _paint_mesh("bp_hokora_a"), Transform3D(hb, Vector3(0, top, 0)), n.position.y)
	for i in steps:
		var sy := 0.18 * float(i + 1) - 0.05
		var sz := -(d + 1.0) * 0.5 - 0.55 * float(steps - i) + 0.25
		var a: String = ["bp_step_stone_a", "bp_step_stone_c", "bp_step_stone_e"][(i + sd) % 3]
		var ab := _aabb(a)
		var ls := Transform3D(Basis(Vector3.UP, PI if i % 2 == 1 else 0.0) * Basis.from_scale(Vector3(1.8 / ab.size.x, maxf(sy / maxf(-ab.position.y, 0.3), 1.0) + 0.2, 0.5 / ab.size.z)), Vector3(0, sy + 0.005, sz))
		_rock(pb, n, "Step%d" % i, a, ls, n.transform * ls, 0.4, sd + 3 + i)
	if bool(poi.get("fence", false)):
		var fx := (w + 1.0) * 0.5 + 0.9
		var fz := (d + 1.0) * 0.5 + 0.9
		var posts: Array = []
		for sx in [-1.0, 1.0]:
			for k in 3:
				posts.append(Vector3(sx * fx, 0, lerpf(-fz, fz, float(k) / 2.0)))
		for k in [1]:
			posts.append(Vector3(lerpf(-fx, fx, float(k) / 2.0), 0, fz))
		var kp := 0
		for p: Vector3 in posts:
			var bp := Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(0.9, 0.85 / 1.25, 0.9))
			_add(n, "FencePost%d" % kp, _paint_mesh("bp_fence_post_a"), Transform3D(bp, p), n.position.y)
			kp += 1
		var rails := [[Vector3(-fx, 0.7, -fz), Vector3(-fx, 0.7, fz)], [Vector3(fx, 0.7, -fz), Vector3(fx, 0.7, fz)], [Vector3(-fx, 0.7, fz), Vector3(fx, 0.7, fz)]]
		var kr := 0
		for rr: Array in rails:
			var a3: Vector3 = rr[0]
			var b3: Vector3 = rr[1]
			var dv := (b3 - a3)
			var yaw := atan2(-dv.z, dv.x)
			var br := Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(dv.length() + 0.12, 1.0, 1.0))
			_add(n, "FenceRail%d" % kr, _paint_mesh("bp_fence_rail_a"), Transform3D(br, a3 - dv.normalized() * 0.06), n.position.y)
			kr += 1


# ================================================================= 石燈籠（立っている：S01 と同じ資産；倒れている：二つに割れて転がる）
static func _lantern(pb, poi: Dictionary, n: Node3D, sd: int) -> void:
	_strip(n)
	var moss := float(poi.get("moss", 0.35))
	if bool(poi.get("fallen", false)):
		# 竿・中台の部分が +X 方向に倒れ（基礎は埋まって傾いて残る）、火袋と笠は先で横倒し
		var lo := Transform3D(Basis(Vector3.BACK, -deg_to_rad(84.0)) * Basis(Vector3.UP, 0.4), Vector3(0.12, 0.30, 0.0))
		_stone(pb, n, "LanternLow", "s01_lantern_a_low", lo, n.transform * lo, minf(moss * 1.1, 1.0), sd, 0.95)
		var tp := Transform3D(Basis(Vector3.UP, 0.7) * Basis(Vector3.BACK, -deg_to_rad(100.0)), Vector3(2.55, 1.05, 0.25))
		_stone(pb, n, "LanternTop", "s01_lantern_a_top", tp, n.transform * tp, minf(moss * 1.1, 1.0), sd + 1, 0.95)
		return
	var inside := func(v: Vector3) -> bool:
		return Vector2(v.x, v.z).length() < 0.21 and v.y > 1.24 and v.y < 1.60
	var xf := Transform3D(Basis(Vector3.UP, 0.0), Vector3(0, -0.03, 0))
	_stone(pb, n, "Lantern", "s01_lantern_a", xf, n.transform * xf, moss, sd, 0.98, inside)


static func _gate(pb, poi: Dictionary, n: Node3D) -> void:
	_strip(n)
	_add(n, "Gate", _paint_mesh("bp_gate_a"), Transform3D(Basis.from_scale(Vector3(0.98, 1.0, 1.0)), Vector3.ZERO), n.position.y)


static func _offerings(pb, poi: Dictionary, n: Node3D, sd: int) -> void:
	_strip(n)
	var ls := Transform3D(Basis(Vector3.UP, deg_to_rad(12.0)), Vector3(0, -0.02, 0))
	_stone(pb, n, "Stone", "bp_offering_stone", ls, n.transform * ls, 0.55, sd, 0.92)
	_add(n, "Offering", _paint_mesh("bp_offering_a"), Transform3D(Basis(Vector3.UP, deg_to_rad(12.0)), Vector3(0, -0.02, 0)), n.position.y)


# ================================================================= 小さな鳥居（S01 の明神鳥居を span に合わせて等倍縮小；weathered＝朱が褪せて灰褐）
static func _torii(pb, poi: Dictionary, n: Node3D, sd: int) -> void:
	if bool(poi.get("broken", false)):
		return                                         # 破鳥居は S04 側の別物（触らない）
	_strip(n)
	var span := float(poi.get("span", 4.0))
	var k := span / 5.0
	var wea := String(poi.get("color", "red")) == "weathered"
	var rc := func(c: Color) -> Color:
		if c.r > c.g * 1.6:
			return c.lerp(Color(0.44, 0.35, 0.29), 0.5)
		return c
	var b := Basis.from_scale(Vector3(k, k, k))
	_add(n, "Torii", _paint_mesh("s01_torii_a", rc if wea else Callable()), Transform3D(b, Vector3(0, 0.02, 0)), n.position.y)
	var lb := Transform3D(b, Vector3(0, 0.02, 0))
	_stone(pb, n, "Base", "s01_torii_a_base", lb, n.transform * lb, 0.7, sd, 0.92)


# ================================================================= 倒木／殘株／露根／折れ枝（S01 林床と同じ木の資產）
static func _log(pb, poi: Dictionary, n: Node3D) -> void:
	var old := _strip(n)
	for o: Dictionary in old:
		if not (o["mesh"] is CylinderMesh):
			continue
		var xf: Transform3D = o["xf"]
		var cm: CylinderMesh = o["mesh"]
		var axis := xf.basis.y.normalized()
		var len := cm.height
		var r := cm.bottom_radius
		var up := Vector3.UP - axis * axis.dot(Vector3.UP)
		up = up.normalized()
		var s := r / 0.27
		var b := Basis(axis, up, axis.cross(up).normalized()) * Basis.from_scale(Vector3(len / 4.2, s, s))
		var org := xf.origin - up * (0.92 * r + 0.06)          # 資產的軸高＝r0×0.92；原本圓柱軸在地面＋0.7 r → 微埋
		var mi := _add(n, "Log", _kit_wood_mesh("s01_log_a"), Transform3D(b, org))
		mi.set_instance_shader_parameter("moss_k", 0.55)
		mi.set_instance_shader_parameter("ground_y", org.y)


static func _stump(pb, poi: Dictionary, n: Node3D, rng: RandomNumberGenerator) -> void:
	_strip(n)
	var rad := float(poi.get("r", 0.5))
	var h := float(poi.get("h", 0.7))
	var s := rad / 0.27 * 0.95                       # 資產幹半徑 0.27、高 0.72
	var b := Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(s, h / 0.72, s))
	var mi := _add(n, "Stump", _kit_wood_mesh("s01_stump_a"), Transform3D(b, Vector3(0, -0.05, 0)))
	mi.set_instance_shader_parameter("moss_k", 0.5)
	mi.set_instance_shader_parameter("ground_y", n.position.y)


static func _roots(pb, poi: Dictionary, n: Node3D, rng: RandomNumberGenerator) -> void:
	var old := _strip(n)
	var c := Vector3.ZERO
	for o: Dictionary in old:
		c += (o["xf"] as Transform3D).origin
	if old.is_empty():
		return
	c /= float(old.size())
	var rad := float(poi.get("r", 1.2))
	var s := rad / 1.8
	var a := "s01_roots_a" if rng.randf() < 0.5 else "s01_roots_b"
	var b := Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(s, s * 0.9, s))
	var g: float = pb._g(Vector2(c.x, c.z))
	var mi := _add(n, "Roots", _kit_wood_mesh(a), Transform3D(b, Vector3(c.x, g - 0.06, c.z)))
	mi.set_instance_shader_parameter("moss_k", 0.6)
	mi.set_instance_shader_parameter("ground_y", g)


static func _branch(pb, poi: Dictionary, n: Node3D, rng: RandomNumberGenerator) -> void:
	var old := _strip(n)
	if old.is_empty():
		return
	var xf: Transform3D = old[0]["xf"]
	var axis := xf.basis.y.normalized()
	var yaw := atan2(-axis.z, axis.x)
	var c := xf.origin
	var g: float = pb._g(Vector2(c.x, c.z))
	var b := Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3.ONE * rng.randf_range(0.9, 1.1))
	var mi := _add(n, "Branch", _kit_wood_mesh("s01_branch_a"), Transform3D(b, Vector3(c.x, g - 0.03, c.z)))
	mi.set_instance_shader_parameter("moss_k", 0.15)
	mi.set_instance_shader_parameter("ground_y", g)


static func _basket(pb, poi: Dictionary, n: Node3D) -> void:
	_strip(n)
	_add(n, "Basket", _paint_mesh("bp_basket_a"), Transform3D(Basis(Vector3.BACK, deg_to_rad(5.0)), Vector3(0, -0.02, 0)), n.position.y)


## 岩（V0.1 的二十面體變體）→ S01 kit 的岩（同一顆的碰撞照舊）。大小依原半徑 r：巨石／大岩＝露頭、崖岩；中＝苔石 a；小＝苔石 b。
static func _rocks(pb, poi: Dictionary, n: Node3D, rng: RandomNumberGenerator) -> void:
	var nodes: Array = []
	if n.has_meta("bp_rock_r"):
		nodes.append(n)
	for c in n.get_children():
		if c is Node3D and c.has_meta("bp_rock_r"):
			nodes.append(c)
	var moss := float(poi.get("moss", 0.3))
	var i := 0
	for rn: Node3D in nodes:
		var r := float(rn.get_meta("bp_rock_r"))
		var world0 := _xf_of(rn)
		if pb.lib.scene_id_of_z(world0.origin.z) == "S04":
			continue
		for c in rn.get_children():
			if c is MeshInstance3D:
				rn.remove_child(c)
				c.free()
		var asset := "s01_mossstone_b"
		var half := 0.36
		var top := 0.36
		if r >= 1.9:
			asset = "s01_rock_outcrop_c"                                     # 巨石：低く広い露頭（立った板状にしない）
			half = 2.4
			top = 1.87
		elif r >= 1.25:
			asset = "s01_rock_cliff_b" if (i + absi(String(poi["id"]).hash())) % 3 == 0 else "s01_rock_outcrop_c"
			half = 1.35 if asset == "s01_rock_cliff_b" else 2.4
			top = 2.56 if asset == "s01_rock_cliff_b" else 1.87
		elif r >= 0.6:
			asset = "s01_mossstone_a"
			half = 0.58
			top = 0.61
		var s := r / half
		var sy := clampf((0.95 * r) / (top * s), 0.75, 1.15) * s           # 頂高 ≈ 原岩的頂（地面上 ~0.9 r）
		var g := rn.position.y + 0.12 * r                                     # 原本：根 y＝地面 − 0.12 r（相對 parent）
		var local := Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(s, sy, s * rng.randf_range(0.85, 1.05))), Vector3(0, 0.12 * r - 0.06 * sy, 0))
		var world := world0 * local
		_rock(pb, rn, "Rock", asset, local, world, clampf(moss + 0.1, 0.0, 1.0), absi(String(rn.name).hash()) % 100000)
		i += 1


static func _hut(pb, poi: Dictionary, n: Node3D) -> void:
	_strip(n)
	var b := Basis.from_scale(Vector3(float(poi.get("w", 4.4)) / 4.6, float(poi.get("h", 3.2)) / 3.2, float(poi.get("d", 3.4)) / 3.6))
	_add(n, "Shed", _paint_mesh("bp_shed_a"), Transform3D(b, Vector3.ZERO), n.position.y)


static func _firewood(pb, poi: Dictionary, n: Node3D) -> void:
	_strip(n)
	_add(n, "Firewood", _paint_mesh("bp_firewood_a"), Transform3D(Basis(Vector3.UP, deg_to_rad(3.0)), Vector3(0, -0.01, 0)), n.position.y)

extends SceneTree
## 火見櫓候選點勘查（唯讀，不改場景）
## 目的：從南端大鳥居望向北方主街，找出「落在街道消失點附近」且淨空足夠的塔基座標。
## 地面無碰撞（純 MeshInstance3D），故直接對 UnifiedGround 的三角形做最近點取樣，
## 與 audit_ground_colors.gd 同法。依 .claude/rules/godot.md：量產出物，不信參數。

const STREET_X: float = 235.0
const Z0: float = -60.0
const Z1: float = 92.0
const TORII_Z: float = 101.0
const EYE: float = 1.6
const TOWER_H: float = 15.0
const TOWER_R: float = 3.0        # 塔基半徑（四腳約 5-6m 見方）
const CANDS: Array = [
	[224.0, -67.0, "新位置(西退11m)"],
	[222.0, -62.0, "候補A"],
	[226.5, -64.0, "候補B"],
	[246.0, -64.0, "候補C(東退)"],
]

var _gverts: PackedVector3Array

func _load_ground(root: Node3D) -> void:
	var mi: MeshInstance3D = root.get_node_or_null("UnifiedGround") as MeshInstance3D
	if mi == null or mi.mesh == null:
		push_error("UnifiedGround missing")
		return
	var xf: Transform3D = mi.transform
	var out: PackedVector3Array = PackedVector3Array()
	for si in range(mi.mesh.get_surface_count()):
		var arr: Array = mi.mesh.surface_get_arrays(si)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		if v == null or v.size() == 0:
			continue
		var idx_any = arr[Mesh.ARRAY_INDEX]
		if idx_any != null and (idx_any as PackedInt32Array).size() > 0:
			for i in (idx_any as PackedInt32Array):
				out.append(xf * v[i])
		else:
			for p in v:
				out.append(xf * p)
	_gverts = out

## 取樣：找出離 (x,z) 最近的地面頂點高度（網格 ~5m，足夠定基座）
func _ground_y(x: float, z: float) -> Array:
	var best: float = 1e9
	var by: float = NAN
	for p in _gverts:
		var d: float = (p.x - x) * (p.x - x) + (p.z - z) * (p.z - z)
		if d < best:
			best = d
			by = p.y
	return [by, sqrt(best)]

func _wbox(n: Node3D) -> AABB:
	var acc: AABB = AABB()
	var has: bool = false
	var stack: Array = [[n, (n as Node3D).transform]]
	while not stack.is_empty():
		var pair: Array = stack.pop_back()
		var node: Node = pair[0]
		var xf: Transform3D = pair[1]
		if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
			var a: AABB = xf * (node as MeshInstance3D).mesh.get_aabb()
			if has:
				acc = acc.merge(a)
			else:
				acc = a
				has = true
		for c in node.get_children():
			if c is Node3D:
				stack.push_back([c, xf * (c as Node3D).transform])
	return acc

func _init() -> void:
	var scn: PackedScene = load("res://maps/slice/slice.tscn")
	var root: Node3D = scn.instantiate() as Node3D
	_load_ground(root)
	print("GROUND_VERTS %d" % _gverts.size())

	var boxes: Array = []
	var street: Node = root.get_node_or_null("B1_Street")
	if street != null:
		for c in street.get_children():
			if not (c is Node3D):
				continue
			var nm: String = String(c.name)
			if nm in ["StreetPaving", "PlazaMarket"]:
				continue
			var bb: AABB = _wbox(c as Node3D)
			boxes.append([nm, bb])
	print("BUILDINGS_SAMPLED %d" % boxes.size())

	var er: Array = _ground_y(STREET_X, TORII_Z - 4.0)
	var eye: Vector3 = Vector3(STREET_X, float(er[0]) + EYE, TORII_Z - 4.0)
	print("EYE (%.1f, %.2f, %.1f) 向北\n" % [eye.x, eye.y, eye.z])
	print("%-24s %-7s %-7s %-8s %-9s %s" % [
		"候選", "地面y", "視距", "水平角°", "塔頂仰角°", "最近建築淨空"])

	for cand in CANDS:
		var x: float = cand[0]
		var z: float = cand[1]
		var gr: Array = _ground_y(x, z)
		var gy: float = gr[0]
		var d: float = Vector2(x - eye.x, z - eye.z).length()
		var ang: float = rad_to_deg(atan2(absf(x - eye.x), absf(z - eye.z)))
		var elev: float = rad_to_deg(atan2((gy + TOWER_H) - eye.y, d))
		var clear: float = 1e9
		var who: String = "-"
		for b in boxes:
			var bb: AABB = b[1]
			var dx: float = maxf(maxf(bb.position.x - x, x - (bb.position.x + bb.size.x)), 0.0)
			var dz: float = maxf(maxf(bb.position.z - z, z - (bb.position.z + bb.size.z)), 0.0)
			var dist: float = Vector2(dx, dz).length() - TOWER_R
			if dist < clear:
				clear = dist
				who = b[0]
		var flag: String = "  <-- 撞建築" if clear < 0.5 else ""
		print("%-24s %-7.2f %-7.1f %-8.1f %-9.1f %.2f (%s)%s" % [
			cand[2], gy, d, ang, elev, clear, who, flag])
	root.free()
	quit()

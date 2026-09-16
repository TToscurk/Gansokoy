extends SceneTree
## 人間之里（slice）任務錨點探針 —— 給任務互動區與 waypoints 取實測值。
##   Godot --headless --path godot --script tools/probe_village_arc.gd
##
##  直接載入已產出的 maps/slice/slice.tscn 讀幾何，不重算產生器的高度函式 ——
##   要驗的是「場景實際長怎樣」。座標印出來才填進 slice_interactions.tscn 與
##   data/waypoints.json；不得目測填空。
##  1. y 一律由地形網格取樣得出，不手填（arrival_ground_y 的舊教訓）。
##  2. 建築外框由 mesh AABB × transform 得出，不用名目尺寸猜。
##  3. 鄰近節點清單用來判斷「這一點旁邊有沒有牆／／棚架」——
##     靜態外框查不出來的東西，靠節點位置與距離看。

const SCENE := "res://maps/slice/slice.tscn"

## 名稱 → 候選 (x, z)。地面 y 由地形網格插值。
const CANDIDATES := {
	# 村門（MQ08，已實裝）
	"村門_守衛位":    Vector2(240.0, 92.0),
	# 寺子屋（MQ09／MQ12）
	"寺子屋_南門口":  Vector2(315.0, 46.0),
	"寺子屋_南外":    Vector2(315.0, 55.0),
	# 鈴奈庵（MQ10 小鈴）
	"鈴奈庵_南":      Vector2(227.0, -58.0),
	"鈴奈庵_北":      Vector2(227.0, -78.0),
	"鈴奈庵_東":      Vector2(236.0, -68.0),
	"鈴奈庵_西":      Vector2(218.0, -68.0),
	# 稗田邸（MQ10／MQ11 阿求）
	"稗田邸_門前":    Vector2(233.0, -133.0),
	"稗田邸_南":      Vector2(233.0, -122.0),
	"稗田邸_西":      Vector2(213.0, -139.0),
	"稗田邸_東":      Vector2(252.0, -139.0),
	# 火見櫓（MQ10 確認火見番）
	"火見櫓_南":      Vector2(243.0, -62.0),
	"火見櫓_北":      Vector2(243.0, -76.0),
	"火見櫓_西":      Vector2(236.0, -69.0),
	"火見櫓_東":      Vector2(251.0, -69.0),
	# 鯢吞亭（MQ12 美宵）
	"鯢吞亭_南":      Vector2(213.0, -82.0),
	"鯢吞亭_東":      Vector2(226.0, -94.0),
	"鯢吞亭_北":      Vector2(213.0, -107.0),
}

## 需要量外框的實例節點名（判「互動區有沒有埋進建築」）
const BUILDINGS := ["寺子屋", "鈴奈庵", "鯢吞亭", "霧雨店", "稗田底新版", "火見櫓"]

## 要列鄰近節點的錨點（名稱 → (x, z, 半徑)）
const NEIGHBOURHOOD := {
	"鈴奈庵南": Vector3(227.0, -58.0, 18.0),
	"稗田邸門前": Vector3(233.0, -133.0, 20.0),
	"火見櫓南": Vector3(243.0, -62.0, 16.0),
	"鯢吞亭南": Vector3(213.0, -82.0, 18.0),
}

var _root: Node3D


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var ps := load(SCENE) as PackedScene
	if ps == null:
		push_error("載不到 %s" % SCENE)
		quit(1)
		return
	_root = ps.instantiate() as Node3D
	root.add_child(_root)

	var terrain := _find_mesh_by_name("Terrain")
	if terrain == null:
		push_error("找不到 Terrain")
		quit(1)
		return
	var gy := _height_fn(terrain)

	print("[ARC] 地形取樣：%s" % terrain.name)
	print("[ARC] %-14s %8s %8s %9s" % ["名稱", "x", "z", "地面y"])
	for k in CANDIDATES:
		var c: Vector2 = CANDIDATES[k]
		print("[ARC] %-14s %8.2f %8.2f %9.3f" % [k, c.x, c.y, gy.call(c.x, c.y)])

	print("[ARC]  建築世界外框（mesh AABB 經 transform，非名目尺寸）──")
	for b in BUILDINGS:
		var n := _find_node_by_name(b)
		if n == null:
			print("[ARC] %-12s 找不到節點" % b)
			continue
		var aabb := _world_aabb(n)
		print("[ARC] %-12s x[%8.2f,%8.2f] z[%8.2f,%8.2f] y[%7.2f,%7.2f]" % [
			b, aabb.position.x, aabb.end.x, aabb.position.z, aabb.end.z,
			aabb.position.y, aabb.end.y])

	for k in NEIGHBOURHOOD:
		var v: Vector3 = NEIGHBOURHOOD[k]
		print("[ARC] ─ %s 半徑 %.0fm 內的節點（依距離排序）──" % [k, v.z])
		for e in _nearby(_root, Vector2(v.x, v.y), v.z):
			print("[ARC]   %6.1fm  %-34s %s" % [e[0], e[1], e[2]])

	quit(0)


## [(距離, 節點路徑, 型別), …]，只回有實際位置的節點；跳過地形與植被層。
func _nearby(n: Node, xz: Vector2, radius: float) -> Array:
	var out: Array = []
	var stack: Array[Node] = [n]
	while stack.size() > 0:
		var node: Node = stack.pop_back()
		for c in node.get_children():
			stack.push_back(c)
		if node is Node3D:
			var nm := String(node.name)
			if nm == "Terrain" or nm.begins_with("VillageTrees") or nm == "BasinHills":
				continue
			var p: Vector3 = (node as Node3D).global_position
			var d := Vector2(p.x, p.z).distance_to(xz)
			if d <= radius:
				out.append([d, _path_of(node), node.get_class()])
	out.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	return out.slice(0, 26)


func _path_of(n: Node) -> String:
	var s := String(n.name)
	var cur := n.get_parent()
	var depth := 0
	while cur != null and cur != _root and depth < 3:
		s = String(cur.name) + "/" + s
		cur = cur.get_parent()
		depth += 1
	return s


func _find_node_by_name(nm: String) -> Node:
	return _root.find_child(nm, true, false)


func _find_mesh_by_name(nm: String) -> MeshInstance3D:
	for c in _root.get_children():
		if c is MeshInstance3D and String(c.name).findn(nm) >= 0:
			return c
	return null


## 地形網格 → 雙線性插值的 (x, z) → y。與 probe_trail_anchors.gd 同一手法。
func _height_fn(terrain: MeshInstance3D) -> Callable:
	var verts: PackedVector3Array = terrain.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var res := int(round(sqrt(float(verts.size()))))
	var xs := PackedFloat32Array()
	var zs := PackedFloat32Array()
	for v in verts:
		xs.append(v.x)
		zs.append(v.z)
	xs.sort()
	zs.sort()
	var half_x := maxf(absf(xs[0]), absf(xs[xs.size() - 1]))
	var half_z := maxf(absf(zs[0]), absf(zs[zs.size() - 1]))
	var step_x := 2.0 * half_x / float(res - 1)
	var step_z := 2.0 * half_z / float(res - 1)
	print("[ARC] 地形 %d×%d 格，範圍 x±%.1f z±%.1f，格距 %.2f×%.2f" % [
		res, res, half_x, half_z, step_x, step_z])
	return func(x: float, z: float) -> float:
		var fi: float = clampf((x + half_x) / step_x, 0.0, float(res - 1))
		var fj: float = clampf((z + half_z) / step_z, 0.0, float(res - 1))
		var i0 := int(floor(fi))
		var j0 := int(floor(fj))
		var i1: int = mini(i0 + 1, res - 1)
		var j1: int = mini(j0 + 1, res - 1)
		var tx := fi - float(i0)
		var tz := fj - float(j0)
		var h00: float = verts[j0 * res + i0].y
		var h10: float = verts[j0 * res + i1].y
		var h01: float = verts[j1 * res + i0].y
		var h11: float = verts[j1 * res + i1].y
		return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


## 節點底下所有 MeshInstance3D 的 mesh AABB 併成世界空間 AABB。
func _world_aabb(n: Node) -> AABB:
	var out := AABB()
	var first := true
	for m in _collect_meshes(n):
		var mi := m as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var local: AABB = mi.mesh.get_aabb()
		var xf: Transform3D = mi.global_transform
		for i in 8:
			var p: Vector3 = xf * local.get_endpoint(i)
			if first:
				out = AABB(p, Vector3.ZERO)
				first = false
			else:
				out = out.expand(p)
	return out


func _collect_meshes(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D and n.mesh != null:
		out.append(n)
	for c in n.get_children():
		out.append_array(_collect_meshes(c))
	return out
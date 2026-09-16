extends SceneTree
## 獸道樹木扎根探針 —— 量「樹的底部」離地多高（不是原點，是 mesh AABB 的下緣）。
##   Godot --headless --path godot --script tools/probe_trail_trees.gd
##
## 使用者回報：獸道的樹浮在空中；他的樹資產**底部是有東西的**（有根部／底盤），
##   浮起來就會看到底座懸在半空。
##
## 量法：
##   ground = 地形網格（視覺 mesh，不是 height_at 的解析函式）在該 x/z 的雙線性插值高度
##   bottom = 實例底下所有 MeshInstance3D 的 mesh AABB 下緣，經世界變換取最小值
##   gap    = bottom − ground   （> 0 = 浮空、< 0 = 埋進土裡）
##
##  用視覺 mesh 當地面，不用 height_at()：要驗的是「玩家看到什麼」。
##   產生器以為的地面跟場景實際的地面是兩回事（獸道踩過這個坑）。

const SCENE := "res://maps/trail/trail.tscn"

var _root: Node3D
var _verts: PackedVector3Array
var _res := 0
var _half := 0.0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_root = (load(SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(_root)

	var terrain: MeshInstance3D = null
	for c in _root.get_children():
		if c is MeshInstance3D and String(c.name).findn("Terrain") >= 0:
			terrain = c
			break
	if terrain == null:
		push_error("找不到 Terrain")
		quit(1)
		return
	_verts = terrain.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	_res = int(round(sqrt(float(_verts.size()))))
	_half = 120.0
	print("[TREE] 地形 %d×%d，取樣半徑 %.0f m" % [_res, _res, _half])

	# 依「樹種分組」找：產生器把樹放在 森林/<路沿|外圍>/<種>_近｜_遠 底下
	var rows: Array = []
	var groups: Array[Node] = []
	var stack: Array[Node] = [_root]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.push_back(c)
		var nm := String(n.name)
		if nm.contains("_近") or nm.contains("_遠"):
			groups.append(n)
	print("[TREE] 找到 %d 個樹群組" % groups.size())
	for grp in groups:
		for inst in grp.get_children():
			if not (inst is Node3D):
				continue
			var bottom := _aabb_bottom(inst)
			if bottom == INF:
				continue
			var p: Vector3 = (inst as Node3D).global_position
			var g := _ground(p.x, p.z)
			# ⚠ 只看原點的地面高度不夠：斜地上「原點貼地」等於下坡側懸空，
			#   而使用者的樹資產底部有根盤，任何空隙都看得見。
			#   所以在底座足跡（±0.6 m 九宮格）內取地面最高與最低：
			#     gap_low  = 底部 − 足跡最低地面（>0 = 下坡側露出空隙）
			#     gap_high = 底部 − 足跡最高地面（<0 = 已經插進土裡）
			var gmin := g
			var gmax := g
			for dx in [-0.6, 0.0, 0.6]:
				for dz in [-0.6, 0.0, 0.6]:
					var gg := _ground(p.x + dx, p.z + dz)
					gmin = minf(gmin, gg)
					gmax = maxf(gmax, gg)
			rows.append([String(grp.name), String(inst.name), p.x, p.z,
				bottom - gmin, bottom - gmax, gmax - gmin])
	if rows.is_empty():
		print("[TREE] 沒有找到樹群組（命名規則變了嗎？）")
		quit(1)
		return

	rows.sort_custom(func(a, b): return float(a[4]) > float(b[4]))   # 下坡側空隙由大到小
	var gaps: Array = rows.map(func(r): return float(r[4]))
	var slopes: Array = rows.map(func(r): return float(r[6]))
	slopes.sort()                       # 由小到大 → 最大值取 [-1]
	var median: float = gaps[int(gaps.size() / 2)]
	var floating := 0
	var buried := 0
	for g in gaps:
		if float(g) > 0.10:
			floating += 1
		elif float(g) < -0.10:
			buried += 1
	print("[TREE] 共 %d 棵：浮空(>+0.10 m) %d、埋土(<-0.10 m) %d、貼地 %d" % [
		rows.size(), floating, buried, rows.size() - floating - buried])
	print("[TREE] gap_low(下坡側) 中位數 %.2f m、最大 %+.2f、最小 %+.2f（負 = 已埋住）" % [median, float(gaps[0]), float(gaps[-1])])
	print("[TREE] 足跡落差中位數 %.2f m、最大 %.2f（斜地越大，單點接地越容易露空隙）" % [
		float(slopes[int(slopes.size() / 2)]), float(slopes[-1])])

	# 依樹種統計
	var by_kind := {}
	for r in rows:
		var k := String(r[0])
		if not by_kind.has(k):
			by_kind[k] = []
		by_kind[k].append(float(r[4]))
	print("[TREE] ── 依群組（近＝路沿、遠＝外圍）──")
	for k in by_kind:
		var g: Array = by_kind[k]
		g.sort()
		print("[TREE]   %-16s n=%-5d 下坡側空隙中位 %+6.2f m  範圍 %+6.2f … %+6.2f" % [
			k, g.size(), float(g[int(g.size() / 2)]), float(g[0]), float(g[-1])])

	print("[TREE] ─ 浮最高的 12 棵 ──")
	for i in mini(12, rows.size()):
		var r: Array = rows[i]
		print("[TREE]   %-14s %-20s (%.1f, %.1f) 下坡側空隙 %+6.2f m  插土 %+6.2f m  足跡落差 %.2f m" % [
			String(r[0]), String(r[1]), float(r[2]), float(r[3]),
			float(r[4]), float(r[5]), float(r[6])])
	print("[TREE] ── 埋最深的 5 棵 ──")
	for i in mini(5, rows.size()):
		var r: Array = rows[rows.size() - 1 - i]
		print("[TREE]   %-16s %-22s (%.1f, %.1f) 下坡側空隙 %+6.2f m" % [
			String(r[0]), String(r[1]), float(r[2]), float(r[3]), float(r[4])])
	quit(0)


## 地形 mesh 雙線性插值（與 probe_trail_anchors.gd 同法）
func _ground(x: float, z: float) -> float:
	var step := 2.0 * _half / float(_res - 1)
	var fi: float = clampf((x + _half) / step, 0.0, float(_res - 1))
	var fj: float = clampf((z + _half) / step, 0.0, float(_res - 1))
	var i0 := int(floor(fi))
	var j0 := int(floor(fj))
	var i1: int = mini(i0 + 1, _res - 1)
	var j1: int = mini(j0 + 1, _res - 1)
	var tx := fi - float(i0)
	var tz := fj - float(j0)
	var h00: float = _verts[j0 * _res + i0].y
	var h10: float = _verts[j0 * _res + i1].y
	var h01: float = _verts[j1 * _res + i0].y
	var h11: float = _verts[j1 * _res + i1].y
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


## 實例底下所有 MeshInstance3D 的世界 AABB 下緣（最小的 y）
func _aabb_bottom(n: Node) -> float:
	var bottom := INF
	var stack: Array[Node] = [n]
	while stack.size() > 0:
		var node: Node = stack.pop_back()
		for c in node.get_children():
			stack.push_back(c)
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var local: AABB = mi.mesh.get_aabb()
		var xf: Transform3D = mi.global_transform
		for i in 8:
			bottom = minf(bottom, (xf * local.get_endpoint(i)).y)
	return bottom
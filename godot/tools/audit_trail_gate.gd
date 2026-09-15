extends SceneTree
## 走廊淨空體檢：量「路心到最近障礙物表面」的實際淨空（隘口與全線）。
##
##   Godot --headless --path godot --script tools/audit_trail_gate.gd
##
## 為什麼要有這支：r3 第一版把隘口岩塊撒在離路心 3.2 m 起，而該處路半寬只有
## 0.82 m、岩塊水平半徑 ≈1.7 m → 岩體邊緣壓進路面，路被堵死。
##
## ⚠ 兩個做錯過的地方，別再犯：
##  1. 在 `extends SceneTree` 的體檢腳本裡，**global_transform 讀不到值**。
##     節點掛上樹之後仍要等一個 frame 才會更新全域變換；_init() 裡沒有
##     那個 frame，於是 global_position 全部回傳 (0,0,0)，量出來的淨空
##     是假的（第一版量到 6.71 m，實際 1.74 m）。
##     解法：自己沿 parent 鏈把 local transform 乘起來，見 _world_of()。
##  2. 路心不能用「岩塊群中心」之類的近似猜。產生器已把主脊折線與路半寬
##     烘進場景 meta("spine") / meta("spine_half_w")，直接讀那份。
const SCENE := "res://maps/trail/trail.tscn"
## 玩家膠囊半徑 0.4 + 餘裕；低於此視為侵入走廊
const NEED := 1.5
## 要檢查的群組（節點名 → 是否為必檢）
const GROUPS := ["岩壁隘口", "岩石與倒木", "人類遺跡"]
## **本來就該在路上**的東西，不算侵入：
##   碎石 = 路面碎石（規格要求）；橫跨倒木 = 刻意擋路的跨越點；
##   木橋 = 路從它上面過。名稱含這些字串就豁免。
const ON_PATH_OK := ["Pebble", "碎石", "橫跨", "木橋", "暫代倒木"]


func _exempt(nm: String) -> bool:
	for k in ON_PATH_OK:
		if nm.findn(k) >= 0:
			return true
	return false


## 自己算世界變換（不靠 global_transform，理由見檔頭）
func _world_of(n: Node3D, stop: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != stop:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t


## 收集「葉子物件」：有網格的實例根，而不是群組節點。
## ⚠ 直接對群組節點量 AABB 會把散佈全圖的 300 顆碎石併成一個
##   200 m 寬的盒子，算出 −98 m 的假淨空。要往下走到實例。
##   判準：這個節點的**子節點**裡還有帶網格的 Node3D → 它是群組，繼續往下；
##   否則（網格都在自己身上或 GLB 內部）才算一個物件。
func _leaf_objects(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is StaticBody3D or not (c is Node3D):
			continue
		var child_has_mesh := false
		for gc in c.get_children():
			if gc is Node3D and not (gc is StaticBody3D) and not _mesh_nodes(gc).is_empty():
				child_has_mesh = true
				break
		if child_has_mesh:
			_leaf_objects(c, out)
		elif not _mesh_nodes(c).is_empty():
			out.append(c)


func _mesh_nodes(n: Node) -> Array:
	var out := []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append(n)
	for c in n.get_children():
		out.append_array(_mesh_nodes(c))
	return out


## 點到主脊折線的距離 + 該處路半寬
func _spine_info(p: Vector2, spine: PackedVector2Array, hw: PackedFloat32Array) -> Array:
	var best := INF
	var bhw := 1.0
	for i in spine.size() - 1:
		var a := spine[i]
		var b := spine[i + 1]
		var ab := b - a
		var u := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var d := p.distance_to(a + ab * u)
		if d < best:
			best = d
			bhw = lerpf(hw[i], hw[i + 1], u)
	return [best, bhw]


func _init() -> void:
	var root := (load(SCENE) as PackedScene).instantiate() as Node3D
	# ⚠ 必須掛上樹，否則 global_transform 全是 IDENTITY
	get_root().add_child(root)
	if not root.has_meta("spine"):
		print("場景沒有 meta(\"spine\")：請重跑 gen_trail_v2.gd")
		quit(1)
		return
	var spine: PackedVector2Array = root.get_meta("spine")
	var hw: PackedFloat32Array = root.get_meta("spine_half_w")
	var hw_lo := INF
	var hw_hi := -INF
	for v in hw:
		hw_lo = minf(hw_lo, v)
		hw_hi = maxf(hw_hi, v)
	print("[GATE] 主脊 %d 點，路半寬 %.2f–%.2f m" % [spine.size(), hw_lo, hw_hi])

	for gname in GROUPS:
		var g := root.get_node_or_null(NodePath(gname))
		if g == null:
			print("[GATE] （略過：場景無 %s）" % gname)
			continue
		var worst := INF
		var worst_node := ""
		var intrude := 0
		var counted := 0
		var leaves := []
		_leaf_objects(g, leaves)
		for ch in leaves:
			if _exempt(str(ch.name)):
				continue
			var box: Variant = null
			for m in _mesh_nodes(ch):
				var mi := m as MeshInstance3D
				var b: AABB = _world_of(mi, root) * mi.get_aabb()
				box = b if box == null else (box as AABB).merge(b)
			if box == null:
				continue
			counted += 1
			var a: AABB = box
			var c := Vector2(a.position.x + a.size.x * 0.5, a.position.z + a.size.z * 0.5)
			var rad := 0.5 * maxf(a.size.x, a.size.z)
			var info := _spine_info(c, spine, hw)
			# 淨空 = 中心到路心距離 − 自己的水平半徑
			var clear: float = info[0] - rad
			if clear < NEED:
				intrude += 1
			if clear < worst:
				worst = clear
				worst_node = str(ch.name)
		if counted == 0:
			continue
		var verdict := "✓" if intrude == 0 else "✗"
		print("[GATE] %s %-10s 物件 %3d，最小淨空 %6.2f m（%s）；侵入走廊 %d 件"
			% [verdict, gname, counted, worst, worst_node, intrude])
	quit(0)

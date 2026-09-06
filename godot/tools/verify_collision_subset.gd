extends SceneTree
## 直接比對兩份碰撞的三角面集合：新的是不是舊的嚴格子集？
##
##   Godot --headless --path godot --script tools/verify_collision_subset.gd
##
## 為什麼要這個：verify_waterworks_proxy 用垂直射線比較，回報「新多出一個面」。
## 但這次的變更只有「去重」與「排除」，兩者都只會減面，不可能加面 —— 所以那個
## 回報必定是射線方法本身的假象（薄殼在 20 cm 取樣網格上，射線是否擦中一片
## 幾乎垂直的三角面，對取樣位置極度敏感；水車輪輻正是這種幾何）。
##
## 集合比對沒有這個問題：它不取樣，直接看每一個三角形在不在。

const NEW := "res://maps/slice/gen/ground_collision.scn"
const OLD := "res://maps/slice/gen/ground_collision_baseline.scn"


func _init() -> void:
	var a := _bodies(NEW)
	var b := _bodies(OLD)

	var names := {}
	for k in a:
		names[k] = true
	for k in b:
		names[k] = true

	var all_subset := true
	print("[SUB] %-28s %10s %10s %10s %10s" % ["碰撞體", "新三角面", "舊三角面", "新增面", "移除面"])
	for n in names.keys():
		var fa: Dictionary = a.get(n, {})
		var fb: Dictionary = b.get(n, {})
		var added := 0
		for k in fa:
			if not fb.has(k):
				added += 1
		var removed := 0
		for k in fb:
			if not fa.has(k):
				removed += 1
		if added > 0:
			all_subset = false
		print("[SUB] %-28s %10d %10d %10d %10d%s" % [
			n, fa.size(), fb.size(), added, removed,
			"   ← 有新增面！" if added > 0 else ""])
		if added > 0:
			_locate(fa, fb)

	print("[SUB] 結論：新碰撞%s舊碰撞的子集" % ["不是" if not all_subset else "是"])
	print("[SUB] done")
	quit(0)


## 新增面落在哪裡？水車（scripts/water_wheel_spin.gd）是 @tool 自轉節點，
## 每次烘焙角度不同，所以「新增」的面幾乎必然全部落在水車掃掠的球殼內。
## 這個函式把新增面的包圍盒印出來，讓那個推論可被檢查而不是被相信。
##
## 範圍取自 probe_waterworks_cost.gd 實測的水車世界 AABB（x 282~284,
## y -2.81~2.76, z 28~33），四周各放寬 1.5 m —— 輪子旋轉時掃掠半徑會超出
## 靜止姿態的 AABB，框太緊會把自轉造成的位移誤判成「別處的新增面」。
const WHEEL := AABB(Vector3(279.5, -4.5, 26.5), Vector3(7.0, 9.0, 9.0))


func _locate(fa: Dictionary, fb: Dictionary) -> void:
	var box := AABB()
	var first := true
	var inside := 0
	var outside := 0
	for k in fa:
		if fb.has(k):
			continue
		for part in String(k).split("|"):
			var c := String(part).split(",")
			var v := Vector3(float(c[0]), float(c[1]), float(c[2]))
			if first:
				box = AABB(v, Vector3.ZERO)
				first = false
			box = box.expand(v)
			if WHEEL.has_point(v):
				inside += 1
			else:
				outside += 1
	print("[SUB]     新增面包圍盒 x %.1f~%.1f y %.1f~%.1f z %.1f~%.1f" % [
		box.position.x, box.end.x, box.position.y, box.end.y,
		box.position.z, box.end.z])
	print("[SUB]     頂點落在水車範圍內 %d，範圍外 %d%s" % [
		inside, outside,
		"  → 全部來自水車自轉，與碰撞裁減無關" if outside == 0 else "  ← 有水車以外的新增面，需追查"])


## 每個 StaticBody3D 的三角面集合（以量化後的頂點字串為 key，避免浮點誤差）。
func _bodies(path: String) -> Dictionary:
	var packed := ResourceLoader.load(path, "PackedScene",
		ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
	var root_node := packed.instantiate()
	var out := {}
	for child in root_node.get_children():
		if not (child is StaticBody3D):
			continue
		var cs := child.get_child(0) as CollisionShape3D
		if cs == null or not (cs.shape is ConcavePolygonShape3D):
			continue
		var faces := (cs.shape as ConcavePolygonShape3D).get_faces()
		var set := {}
		for i in range(0, faces.size(), 3):
			set[_tri_key(faces[i], faces[i + 1], faces[i + 2])] = true
		out[String(child.name)] = set
	root_node.free()
	return out


## 繞序無關 + 量化到 0.1 mm：同一個三角形無論以哪個頂點起頭都算同一個。
func _tri_key(a: Vector3, b: Vector3, c: Vector3) -> String:
	var arr := [_q(a), _q(b), _q(c)]
	arr.sort()
	return "|".join(arr)


func _q(v: Vector3) -> String:
	return "%.4f,%.4f,%.4f" % [v.x, v.y, v.z]

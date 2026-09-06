extends SceneTree
## 場景內容盤點：目前村子裡有什麼、缺什麼。
##
##   Godot --headless --path godot --script tools/survey_slice_content.gd
##
## 這不是效能稽核，是「內容清單」——把場上的東西按用途分類數出來，
## 讓人能一眼看出哪一類已經飽和、哪一類還是空的。判斷「還能加什麼」
## 必須基於實際清單，不是印象。

## 分類規則：節點名或其資產路徑含這些關鍵字就歸類。順序有意義，先中先得。
const BUCKETS := [
	["建物·町家", ["machiya", "komachiya", "shouka", "nagaya", "町家", "長屋", "商家"]],
	["建物·地標", ["鈴奈庵", "鯢吞亭", "霧雨店", "寺子屋", "稗田", "龍神像", "火見櫓", "倉庫"]],
	["鳥居·橋", ["鳥居", "torii", "橋", "bridge", "Bri"]],
	["圍牆", ["圍牆", "Castle Wall", "竹垣", "TakeFence", "Fence"]],
	["水系", ["Canal", "Water", "水", "River", "Bed", "Weir", "堰", "水車", "護岸", "Bank"]],
	["植被·樹", ["Tree", "Pine", "樹", "杉", "衫", "杜", "櫻"]],
	["植被·地被", ["Grass", "Bush", "Clover", "Fern", "Flower", "草", "Plant", "Petal", "灌木"]],
	["石·路面", ["Rock", "Pebble", "Stone", "石", "Paving", "Path", "畦"]],
	["市集·雜物", ["zatsu", "雜物", "Market", "屋台", "攤", "旗", "Barrel", "Crate", "Basket", "Box", "Log"]],
	["燈·光源", ["路燈", "Lantern", "燈", "Lamp"]],
	["田·農", ["稻", "Paddy", "田", "Ine", "Aze"]],
	["遠景", ["遠景", "山", "Hill", "Basin", "skybox"]],
	["碰撞·系統", ["碰撞", "Collision", "天象", "效能裁剪", "夜間燈火", "Ground"]],
]


func _init() -> void:
	var packed: PackedScene = load("res://maps/slice/slice.tscn")
	var src := packed.instantiate()

	var counts := {}
	var tris := {}
	var uncat: Array = []
	for b in BUCKETS:
		counts[b[0]] = 0
		tris[b[0]] = 0

	var total_nodes := 0
	var total_mi := 0
	for n in _all(src):
		total_nodes += 1
		if not (n is MeshInstance3D or n is MultiMeshInstance3D):
			continue
		total_mi += 1
		var label := _classify(n)
		if label == "":
			uncat.append(_path_of(n, src))
			continue
		counts[label] += 1
		tris[label] += _tris(n)

	print("[SURVEY] === 場景內容清單 ===")
	print("[SURVEY] 節點總數 %d，其中可見網格 %d" % [total_nodes, total_mi])
	print("[SURVEY] %-14s %8s %14s" % ["分類", "物件數", "三角面"])
	for b in BUCKETS:
		var k: String = b[0]
		if counts[k] == 0:
			print("[SURVEY] %-14s %8s %14s   ← 空的" % [k, "0", "-"])
		else:
			print("[SURVEY] %-14s %8d %14s" % [k, counts[k], _fmt(tris[k])])
	if uncat.size() > 0:
		print("[SURVEY] 未分類 %d 個，前 12：" % uncat.size())
		for i in mini(12, uncat.size()):
			print("[SURVEY]     %s" % uncat[i])

	# 頂層節點一覽：場景的骨架
	print("[SURVEY] === 頂層節點 ===")
	for c in src.get_children():
		var kids := _all(c).size()
		print("[SURVEY]   %-28s %-22s 子樹 %d 節點" % [c.name, c.get_class(), kids])

	src.free()
	print("[SURVEY] done")
	quit(0)


func _classify(n: Node) -> String:
	var hay := String(n.name)
	var p := n.get_parent()
	var depth := 0
	while p != null and depth < 4:
		hay += "/" + String(p.name)
		p = p.get_parent()
		depth += 1
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		hay += "/" + (n as MeshInstance3D).mesh.resource_path
	for b in BUCKETS:
		for kw in b[1]:
			if hay.findn(kw) != -1:
				return b[0]
	return ""


func _tris(n: Node) -> int:
	var m: Mesh = null
	var mult := 1
	if n is MeshInstance3D:
		m = (n as MeshInstance3D).mesh
	elif n is MultiMeshInstance3D:
		var mm := (n as MultiMeshInstance3D).multimesh
		if mm == null:
			return 0
		m = mm.mesh
		mult = mm.instance_count
	if m == null:
		return 0
	var t := 0
	for s in m.get_surface_count():
		var arr := m.surface_get_arrays(s)
		if arr.is_empty():
			continue
		var idx: Variant = arr[Mesh.ARRAY_INDEX]
		if idx != null and (idx as PackedInt32Array).size() > 0:
			t += (idx as PackedInt32Array).size() / 3
		else:
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			t += v.size() / 3
	return t * mult


func _fmt(v: int) -> String:
	var s := str(v)
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return out


func _path_of(n: Node, root_node: Node) -> String:
	var parts := PackedStringArray()
	var cur: Node = n
	while cur != null and cur != root_node:
		parts.append(String(cur.name))
		cur = cur.get_parent()
	parts.reverse()
	return "/".join(parts)


func _all(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out.append_array(_all(c))
	return out

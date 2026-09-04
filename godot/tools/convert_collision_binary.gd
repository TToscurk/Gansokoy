extends SceneTree
## 把碰撞產出場景從文字 .tscn 轉成二進位 .scn，並逐項驗證等價。
##
##   Godot --headless --path godot --script tools/convert_collision_binary.gd
##
## 為什麼是轉檔而不是重跑產生器：gen_*_collision.gd 會從**當下的**
## slice.tscn 重新烘碰撞，而 slice.tscn 在那次烘焙之後又被手調過。重跑等於
## 偷偷換掉一份已經走過、驗過的碰撞。轉檔則是同一個 PackedScene 物件換一種
## 序列化格式，幾何逐位保留。
##
## 原始 .tscn 一律保留不刪 —— 這是回退路徑。

const JOBS := [
	["res://maps/slice/gen/ground_collision.tscn", "res://maps/slice/gen/ground_collision.scn"],
	["res://maps/slice/gen/building_collision.tscn", "res://maps/slice/gen/building_collision.scn"],
]


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var all_ok := true
	for job in JOBS:
		if not _convert(job[0], job[1]):
			all_ok = false
	print("[CONV] %s" % ("全部成功" if all_ok else "有失敗項目"))
	quit(0 if all_ok else 1)


func _convert(src: String, dst: String) -> bool:
	print("[CONV] === %s" % src.get_file())
	var packed := ResourceLoader.load(src, "PackedScene",
		ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
	if packed == null:
		print("[CONV]   載入失敗")
		return false

	var err := ResourceSaver.save(packed, dst)
	if err != OK:
		print("[CONV]   存檔失敗 err=%d" % err)
		return false

	var before := _fingerprint(packed)
	var reloaded := ResourceLoader.load(dst, "PackedScene",
		ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
	if reloaded == null:
		print("[CONV]   回讀失敗")
		return false
	var after := _fingerprint(reloaded)

	var sz_a := FileAccess.open(src, FileAccess.READ).get_length() / 1048576.0
	var sz_b := FileAccess.open(dst, FileAccess.READ).get_length() / 1048576.0
	print("[CONV]   %.2f MB → %.2f MB" % [sz_a, sz_b])

	if before == after:
		print("[CONV]   ✓ 等價：%s" % before)
		return true
	print("[CONV]   ✗ 不等價")
	print("[CONV]     文字：%s" % before)
	print("[CONV]     二進位：%s" % after)
	return false


## 指紋：節點總數、名稱串、collision_layer/mask、每個 shape 的三角面數與
## 頂點座標總和。任何幾何或物理設定的變動都會讓總和對不上。
func _fingerprint(packed: PackedScene) -> String:
	var root := packed.instantiate()
	var names := PackedStringArray()
	var layers := 0
	var masks := 0
	var tris := 0
	var checksum := 0.0
	var stack: Array[Node] = [root]
	var count := 0
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		count += 1
		names.append(String(n.name))
		for c in n.get_children():
			stack.push_back(c)
		if n is CollisionObject3D:
			layers += (n as CollisionObject3D).collision_layer
			masks += (n as CollisionObject3D).collision_mask
		if n is CollisionShape3D:
			var s: Shape3D = (n as CollisionShape3D).shape
			if s is ConcavePolygonShape3D:
				var f := (s as ConcavePolygonShape3D).get_faces()
				tris += f.size() / 3
				for v in f:
					checksum += v.x + v.y + v.z
			elif s is ConvexPolygonShape3D:
				var pts := (s as ConvexPolygonShape3D).points
				tris += pts.size()
				for v in pts:
					checksum += v.x + v.y + v.z
	root.free()
	names.sort()
	return "節點%d 名稱雜湊%d layer合%d mask合%d 面/點%d 座標和%.4f" % [
		count, String("|").join(names).hash(), layers, masks, tris, checksum]

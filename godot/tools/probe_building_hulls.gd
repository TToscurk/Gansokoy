extends SceneTree
## 建物碰撞現況剖析：74 個凸包各用多少頂點，能簡化到什麼程度。
##
##   Godot --headless --path godot --script tools/probe_building_hulls.gd
##
## 凸包的成本是「頂點數」而非三角面。Godot 的 ConvexPolygonShape3D 用 GJK
## 做碰撞查詢，成本隨頂點數上升。町家是方盒子，理論上 8~20 個頂點就夠；
## 若實測是幾百個，那就有可觀的簡化空間。

const COL := "res://maps/slice/gen/building_collision.scn"


func _init() -> void:
	var packed: PackedScene = load(COL)
	var root_node := packed.instantiate()

	var rows: Array = []
	var total_pts := 0
	var total_tris := 0
	for body in root_node.get_children():
		if not (body is StaticBody3D):
			continue
		for c in body.get_children():
			if not (c is CollisionShape3D):
				continue
			var s: Shape3D = (c as CollisionShape3D).shape
			if s is ConvexPolygonShape3D:
				var n := (s as ConvexPolygonShape3D).points.size()
				total_pts += n
				rows.append({"n": String(body.name), "k": "凸包", "c": n})
			elif s is ConcavePolygonShape3D:
				var t := (s as ConcavePolygonShape3D).get_faces().size() / 3
				total_tris += t
				rows.append({"n": String(body.name), "k": "三角網", "c": t})

	rows.sort_custom(func(a, b): return a["c"] > b["c"])
	print("[HULL] 前 20 重的碰撞體：")
	print("[HULL] %-44s %8s %8s" % ["名稱", "類型", "頂點/面"])
	for i in mini(20, rows.size()):
		print("[HULL] %-44s %8s %8d" % [rows[i]["n"], rows[i]["k"], rows[i]["c"]])

	var hulls := 0
	var meshes := 0
	for r in rows:
		if r["k"] == "凸包":
			hulls += 1
		else:
			meshes += 1
	print("[HULL] ---")
	print("[HULL] 凸包 %d 個，合計 %d 頂點（平均 %.0f）" % [
		hulls, total_pts, float(total_pts) / maxf(hulls, 1)])
	print("[HULL] 三角網 %d 個，合計 %d 面" % [meshes, total_tris])

	# 分布：多少個凸包超過「盒子等級」的頂點數？
	var buckets := {"≤16 (盒子級)": 0, "17-64": 0, "65-256": 0, ">256": 0}
	for r in rows:
		if r["k"] != "凸包":
			continue
		var c: int = r["c"]
		if c <= 16:
			buckets["≤16 (盒子級)"] += 1
		elif c <= 64:
			buckets["17-64"] += 1
		elif c <= 256:
			buckets["65-256"] += 1
		else:
			buckets[">256"] += 1
	print("[HULL] 凸包頂點數分布：")
	for k in buckets:
		print("[HULL]   %-14s %d 個" % [k, buckets[k]])

	root_node.free()
	print("[HULL] done")
	quit(0)

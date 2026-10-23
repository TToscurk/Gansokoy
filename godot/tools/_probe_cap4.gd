extends SceneTree
## 針對最後 1 件違規（gate parcel_fit）做決定性診斷：
##   gate 用物理 intersect_shape 判定「件 OBB 壓到碰撞盒」；lib 的 _bridge_hit 卻說淨空。
## 本探針對同一件、同一 transform 同時做：
##   (1) lib._bridge_hit 的答案
##   (2) _bridge_boxes 清單裡每個鄰近盒的 SAT／密取樣結果（判斷是幾何漏檢）
##   (3) 物理 intersect_shape（與 gate 完全相同）找到的 collider 路徑（判斷是清單漏收）
## 兩者一比即可定出根因是 (a) 清單漏收 或 (b) 幾何漏檢。
const RLib := preload("res://tools/village_v2_riverbank_lib.gd")
const SCENE := "res://maps/village_v2/village_v2.tscn"
const LAYOUT := "res://maps/village_v2/layout_v2.json"
const TARGET := Vector3(313.6, 0.3, 46.1)


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var ps: PackedScene = load(SCENE)
	var v: Node3D = ps.instantiate()
	root.add_child(v)
	var L: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	var P: Dictionary = RLib.plan(v, L)
	var items: Array = P["items"]
	var boxes: Array = RLib._bridge_boxes(v)
	await physics_frame
	await physics_frame
	var space := v.get_world_3d().direct_space_state
	var terrain_rid := (v.get_node("Collision/TerrainCollision") as CollisionObject3D).get_rid()

	# 找最近件
	var bi := -1
	var bd := 1e9
	for i in items.size():
		var o: Vector3 = (items[i]["xf"] as Transform3D).origin
		var d := o.distance_to(TARGET)
		if d < bd:
			bd = d
			bi = i
	var it: Dictionary = items[bi]
	var xf: Transform3D = it["xf"]
	var ma: AABB = RLib.mesh_aabb(String(it["m"]))
	var sc := xf.basis.get_scale()
	var half := ma.size * sc * 0.8 * 0.5
	var cw: Vector3 = xf * ma.get_center()
	var rot := xf.basis.orthonormalized()
	print("[cap4] 件 idx=%d k=%s m=%s tag=%s 距目標 %.3f m" % [
		bi, String(it["k"]), String(it["m"]), String(it["tag"]), bd])
	print("[cap4]   origin %s  scale %s" % [str(xf.origin), str(sc)])
	print("[cap4]   查詢盒 half %s  center %s（gate 同款：mesh AABB × scale × 0.8）" % [str(half), str(cw)])
	print("[cap4] (1) lib._bridge_hit → '%s'" % RLib._bridge_hit(it, boxes, P["bridges"]))

	# (2) 清單裡每個鄰近盒
	var shown := 0
	for bx: Array in boxes:
		if (bx[1] as Vector3).distance_to(cw) > float(bx[2]) + half.length():
			continue
		var inv: Transform3D = bx[0]
		var sat: bool = RLib._obb_unit_hit(rot, cw, half, inv)
		var samp := false
		var ns := 7
		for ix in ns:
			for iy in ns:
				for iz in ns:
					var lp := ma.get_center() + Vector3(
						half.x * lerpf(-0.99, 0.99, float(ix) / float(ns - 1)),
						half.y * lerpf(-0.99, 0.99, float(iy) / float(ns - 1)),
						half.z * lerpf(-0.99, 0.99, float(iz) / float(ns - 1)))
					var q: Vector3 = inv * (xf * lp)
					if absf(q.x) < 1.0 and absf(q.y) < 1.0 and absf(q.z) < 1.0:
						samp = true
						break
				if samp:
					break
			if samp:
				break
		var cen: Vector3 = bx[1]
		if shown < 10:
			shown += 1
			print("[cap4] (2) box %-34s 中心距 %.2f m  SAT=%s 取樣=%s" % [
				String(bx[3]) if bx.size() > 3 else "?", cen.distance_to(cw), str(sat), str(samp)])

	# (3) 物理查詢（與 gate 完全相同）
	var q := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = (ma.size * sc * 0.8).max(Vector3(0.02, 0.02, 0.02))
	q.shape = box
	q.collision_mask = 0xFFFFFFFF
	q.transform = Transform3D(rot, cw)
	var own: Array[RID] = []
	for cb in v.find_children("*", "StaticBody3D", true, false):
		var r := (cb as CollisionObject3D).get_rid()
		if String(v.get_path_to(cb)).begins_with("Riverbank"):
			own.append(r)
	var ex: Array[RID] = [terrain_rid]
	ex.append_array(own)
	q.exclude = ex
	var hits := space.intersect_shape(q, 8)
	print("[cap4] (3) 物理查詢命中 %d（排除 terrain 與 Riverbank）" % hits.size())
	for h: Dictionary in hits:
		var col: Object = h.get("collider")
		if col is Node:
			print("[cap4]      collider 路徑 %s（CollisionShape3D=%s）" % [
				String(v.get_path_to(col as Node)), String((col as Node).get_class())])
	print("[cap4] 判定： (2) 有 SAT/取樣=True 但 (1) 說淨空 → 幾何漏檢；" \
		+ " (3) 有命中但 (2) 全 False → 清單漏收")
	quit()

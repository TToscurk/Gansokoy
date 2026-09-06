extends SceneTree
## 路燈碰撞驗收：圓柱位置對不對、擋不擋得住、有沒有擋到路。
##
##   Godot --headless --path godot --script tools/verify_lamp_collision.gd
##
## 三個問題：
##   1. 每根圓柱是否對齊它的視覺柱身？（比中心 XZ）
##   2. 玩家走向燈柱會被擋住？
##   3. 圓柱之間的走道還通得過嗎？（半徑 0.71 m 是否吃掉太多路面）

const COL := "res://maps/slice/gen/lamp_collision.scn"
const SRC := "res://maps/slice/slice.tscn"
const LAMP_GROUP := "village_lamps"


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	# ── 1. 對齊 ──
	var packed: PackedScene = load(SRC)
	var src := packed.instantiate()
	var visual := {}
	for lamp in _lamps(src):
		visual[String(lamp.name)] = _global_xform(lamp, src).origin

	var col_scene: PackedScene = load(COL)
	var col_root := col_scene.instantiate()
	var worst := 0.0
	var n := 0
	for body in col_root.get_children():
		if not (body is StaticBody3D):
			continue
		var lamp_name := String(body.name).replace("_碰撞", "")
		if not visual.has(lamp_name):
			print("[LAMP] ✗ 碰撞體 %s 找不到對應的路燈" % body.name)
			continue
		var d: float = (visual[lamp_name] as Vector3).distance_to(
			(body as StaticBody3D).transform.origin)
		worst = maxf(worst, d)
		n += 1
	print("[LAMP] 對齊：%d 根，最大偏差 %.4f m %s" % [
		n, worst, "✓" if worst < 0.01 else "← 有偏移"])

	var shape_count := 0
	var tri_count := 0
	for body in col_root.get_children():
		for c in body.get_children():
			if c is CollisionShape3D:
				shape_count += 1
				var s: Shape3D = (c as CollisionShape3D).shape
				if s is ConcavePolygonShape3D:
					tri_count += (s as ConcavePolygonShape3D).get_faces().size() / 3
				elif s is ConvexPolygonShape3D:
					tri_count += (s as ConvexPolygonShape3D).points.size()
	print("[LAMP] 形狀 %d 個，三角面/頂點 %d %s" % [
		shape_count, tri_count, "✓ 純數學形狀" if tri_count == 0 else ""])

	# ── 2/3. 實機 ──
	var main_p := ResourceLoader.load("res://scenes/main.tscn", "PackedScene") as PackedScene
	var main := main_p.instantiate()
	root.add_child(main)
	await process_frame
	main.load_map("slice", "")
	# ⚠ 不要在這裡再 add_child 一份碰撞。lamp_collision.scn 已經由
	# slice.tscn 實例化（節點名「路燈碰撞」），重複掛載會在同一位置疊兩層
	# StaticBody3D，掃掠命中哪一個由物理引擎順序決定，量到的結果不可信。
	# 接線前的版本需要手動掛載，接線後就必須拿掉。
	if main.map_root.get_node_or_null("路燈碰撞") == null:
		print("[LAMP] ⚠ slice.tscn 尚未引用 lamp_collision.scn，改為手動掛載測試")
		main.map_root.add_child(col_scene.instantiate())
	for i in 8:
		await physics_frame

	var space: PhysicsDirectSpaceState3D = main.map_root.get_world_3d().direct_space_state
	var mask: int = main.player.collision_mask

	# 取一對相對的燈測「撞得到」與「走道還通」。
	#
	# 座標必須挑**空曠處**的燈。第一版用 z=-56.34 那對，三次掃掠全部撞到旁邊的
	# 町家（machiya_西_00 / komachiya_東_00）而不是燈柱——量到的是房子，
	# 完全沒驗證到路燈碰撞。這裡改用最北的一對（z=86.06，鳥居外側空地）。
	var west := Vector3(231.12, 2.33, 86.06)
	var east := Vector3(241.09, 2.33, 86.06)
	print("[LAMP] === 實機掃掠（膠囊 r=0.45 h=1.7）===")
	print("[LAMP] 測點選在 z=86 的空地，避開町家干擾")
	var y := 1.3
	for t in [
			{"n": "正面撞西側燈柱", "a": Vector3(west.x, y, west.z - 4.0),
				"b": Vector3(west.x, y, west.z + 4.0), "want": "擋"},
			{"n": "正面撞東側燈柱", "a": Vector3(east.x, y, east.z - 4.0),
				"b": Vector3(east.x, y, east.z + 4.0), "want": "擋"},
			{"n": "兩燈之間走主街（南北）", "a": Vector3(236.1, y, west.z - 6.0),
				"b": Vector3(236.1, y, west.z + 6.0), "want": "通"},
			{"n": "貼西燈內側 2m 通過", "a": Vector3(west.x + 2.0, y, west.z - 5.0),
				"b": Vector3(west.x + 2.0, y, west.z + 5.0), "want": "通"},
		]:
		var r := _sweep(space, t["a"], t["b"], mask, main)
		var blocked: bool = r["f"] < 0.999
		var ok: bool = blocked == (t["want"] == "擋")
		print("[LAMP] %-24s 走了 %5.1f%%  %-22s %s" % [
			t["n"], r["f"] * 100.0,
			("擋住（%s）" % r["hit"]) if blocked else "暢通",
			"✓" if ok else "✗ 與預期不符"])

	# 走道淨寬：兩根燈柱之間實際剩多少可走空間
	var gap := absf(east.x - west.x) - 2.0 * 0.712
	print("[LAMP] 東西燈柱間距 %.2f m，扣掉兩側圓柱後淨寬 %.2f m（玩家直徑 0.6 m）" % [
		absf(east.x - west.x), gap])

	src.free()
	col_root.free()
	print("[LAMP] done")
	quit(0)


func _sweep(space: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3,
		mask: int, main: Node) -> Dictionary:
	var shape := CapsuleShape3D.new()
	shape.radius = 0.45
	shape.height = 1.7
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis.IDENTITY, a)
	q.motion = b - a
	q.collision_mask = mask
	q.exclude = [main.player.get_rid()]
	var r := space.cast_motion(q)
	var hit := ""
	if r[0] < 0.999:
		q.transform.origin = a + q.motion * r[1]
		q.motion = Vector3.ZERO
		var hits := space.intersect_shape(q, 1)
		if not hits.is_empty():
			hit = String((hits[0]["collider"] as Node).name)
	return {"f": r[0], "hit": hit}


func _global_xform(node: Node3D, scene_root: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != scene_root:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


func _lamps(node: Node) -> Array:
	var out: Array = []
	if node is Node3D and node.is_in_group(LAMP_GROUP):
		out.append(node)
	for c in node.get_children():
		out.append_array(_lamps(c))
	return out

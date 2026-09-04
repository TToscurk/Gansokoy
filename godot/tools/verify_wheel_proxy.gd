extends SceneTree
## 水車圓柱代理驗收：
##   1. 圓柱是否包住輪子的完整掃掠體（任何轉角都在內）？
##   2. 玩家從水路走過去會被擋住，而不是穿過輪輻？
##   3. 圓柱有沒有多擋到不該擋的地方（例如把水路整條封死）？
##
##   Godot --headless --path godot --script tools/verify_wheel_proxy.gd

const COL := "res://maps/slice/gen/ground_collision.scn"
## _add_body 會在標籤後補「_碰撞」，所以完整節點名是這個。
const WHEEL_BODY := "水車_旋轉代理_碰撞"


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	# ── 輪子在任意轉角下的掃掠體 ──
	# 把靜止網格繞本地 Z（腳本的轉軸）轉 36 個角度，取所有角度的聯集。
	var packed: PackedScene = load("res://maps/slice/slice.tscn")
	var src := packed.instantiate()
	var wheel := src.get_node_or_null("MachiCanal/Waterworks/水車") as Node3D
	if wheel == null:
		print("[WP] 找不到水車節點")
		quit(1)
		return
	var mi: MeshInstance3D = null
	for m in _meshes(wheel):
		mi = m
		break
	var faces := mi.mesh.get_faces()
	var xf := _global_xform(mi, src)

	var swept := AABB(xf * faces[0], Vector3.ZERO)
	for step in 36:
		var ang := TAU * float(step) / 36.0
		var spin := Transform3D(Basis(Vector3.BACK, ang), Vector3.ZERO)
		var combined := xf * spin
		for v in faces:
			swept = swept.expand(combined * v)
	print("[WP] 輪子掃掠體 中心=%v 尺寸=%v" % [swept.get_center(), swept.size])

	# ── 碰撞裡的圓柱 ──
	# 圓柱是自己的碰撞體，按名字取即可。先前試過三種「從合併幾何裡撈出圓柱」
	# 的方法（AABB 框選鄰域、取尾端三角形、半徑簽名比對），全部撈到錯的東西：
	# 框選會框進旁邊的石造堰檻、尾端不是水車、半徑比對敵不過浮點誤差。
	# 讓產生器把它烘成獨立命名的 body，驗證就不需要任何猜測。
	var col: PackedScene = load(COL)
	var col_root := col.instantiate()
	var wheel_body := col_root.get_node_or_null(WHEEL_BODY) as StaticBody3D
	if wheel_body == null:
		var names := PackedStringArray()
		for c in col_root.get_children():
			names.append(String(c.name))
		print("[WP] ✗ 碰撞裡沒有 %s" % WHEEL_BODY)
		print("[WP]   現有碰撞體：%s" % ", ".join(names))
		quit(1)
		return

	var wcs := wheel_body.get_child(0) as CollisionShape3D
	var cylf := (wcs.shape as ConcavePolygonShape3D).get_faces()
	var cyl_box := AABB(cylf[0], Vector3.ZERO)
	for v in cylf:
		cyl_box = cyl_box.expand(v)
	print("[WP] 碰撞圓柱   中心=%v 尺寸=%v（%d 三角面）" % [
		cyl_box.get_center(), cyl_box.size, cylf.size() / 3])
	print("[WP] 圖層=%d（1=玩家、bit32=筆刷）" % wheel_body.collision_layer)

	print("[WP] 中心偏差 %.3f m" % swept.get_center().distance_to(cyl_box.get_center()))

	# 覆蓋檢查：比「掃掠半徑 vs 圓柱半徑」，不是比 AABB 的角。
	#
	# 先前這裡拿 swept 的 8 個角去測 has_point，永遠有 6 個「在外面」——
	# 那是方形的角本來就落在內接圓外，不是碰撞漏了。圓柱要包住的是輪子的
	# 迴轉體，判準只有半徑與軸長。
	var axis_i := 0   # 最薄軸 = 軸向，與 _wheel_proxy 同一套判定
	var s := swept.size
	if s.y < s.x and s.y <= s.z:
		axis_i = 1
	elif s.z < s.x and s.z <= s.y:
		axis_i = 2
	var j1 := (axis_i + 1) % 3
	var j2 := (axis_i + 2) % 3
	var swept_r: float = maxf(s[j1], s[j2]) * 0.5
	var cyl_r: float = maxf(cyl_box.size[j1], cyl_box.size[j2]) * 0.5
	var swept_len: float = s[axis_i]
	var cyl_len: float = cyl_box.size[axis_i]
	print("[WP] 軸=%s  掃掠半徑 %.3f m vs 圓柱半徑 %.3f m（差 %+.3f）" % [
		["X", "Y", "Z"][axis_i], swept_r, cyl_r, cyl_r - swept_r])
	print("[WP] 軸長   掃掠 %.3f m vs 圓柱 %.3f m（差 %+.3f）" % [
		swept_len, cyl_len, cyl_len - swept_len])
	# 容差 5 cm：掃掠體是 36 個離散角度的聯集，本來就略大於真實迴轉體。
	var covered: bool = cyl_r >= swept_r - 0.05 and cyl_len >= swept_len - 0.05
	print("[WP] 覆蓋判定：%s" % [
		"✓ 圓柱包住輪子的迴轉體" if covered else "✗ 圓柱偏小，輪子會穿出"])

	# ── 實機掃掠 ──
	var main_p := ResourceLoader.load("res://scenes/main.tscn", "PackedScene") as PackedScene
	var main := main_p.instantiate()
	root.add_child(main)
	await process_frame
	main.load_map("slice", "")
	for i in 6:
		await physics_frame
	var space: PhysicsDirectSpaceState3D = main.map_root.get_world_3d().direct_space_state
	var mask: int = main.player.collision_mask
	var c := swept.get_center()

	print("[WP] === 實機掃掠（膠囊 r=0.45 h=1.7，水路底 y≈-2.3）===")
	for t in [
			{"n": "沿水路 北→南 穿輪心", "a": Vector3(c.x, -2.3, c.z - 6.0),
				"b": Vector3(c.x, -2.3, c.z + 6.0), "want": "擋"},
			{"n": "沿水路 南→北 穿輪心", "a": Vector3(c.x, -2.3, c.z + 6.0),
				"b": Vector3(c.x, -2.3, c.z - 6.0), "want": "擋"},
			{"n": "沿輪軸 東→西（薄向）", "a": Vector3(c.x - 6.0, -2.3, c.z),
				"b": Vector3(c.x + 6.0, -2.3, c.z), "want": "擋"},
			{"n": "輪子外 4m 處平行通過", "a": Vector3(c.x, -2.3, c.z - 8.0),
				"b": Vector3(c.x, -2.3, c.z - 5.0), "want": "通"},
		]:
		var r := _sweep(space, t["a"], t["b"], mask, main)
		var blocked: bool = r["f"] < 0.999
		var ok: bool = blocked == (t["want"] == "擋")
		print("[WP] %-22s 走了 %5.1f%%  %-24s %s" % [
			t["n"], r["f"] * 100.0,
			("擋住（%s）" % r["hit"]) if blocked else "暢通",
			"✓" if ok else "✗ 與預期不符"])

	src.free()
	col_root.free()
	print("[WP] done")
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


func _meshes(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(_meshes(c))
	return out
